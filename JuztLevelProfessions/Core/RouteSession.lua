local _, JLP = ...
local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end

-- Maintains one cross-profession workspace batch across consecutive route
-- actions. The batch never bypasses a profession queue head: it only groups
-- actions that are already dependency-safe and require the same workspace/
-- audited source. Completion remains evidence-driven through ExecutionProgress
-- or confirmed Craft/Enchant transactions.
local RouteSession = {
    contract = "workspace-route-session-v1",
    active = nil,
    lastCompleted = nil,
    history = {},
    serial = 0,
    revision = 0,
    initialized = false,
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end
local SOURCE_SENSITIVE = { vendor=true, trainer=true, source=true }

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return value end
    end
    return nil
end

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("[%p%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local function boundedAppend(list, value, limit)
    list[#list + 1] = value
    while #list > (limit or 30) do table.remove(list, 1) end
end

local function actionID(key, action, plan)
    if type(action)~="table" then return nil end
    if action.identityContract=="semantic-plan-action-v1" and not action.identityUnresolved and
        type(action.actionID)=="string" and action.actionID~="" then
        return action.actionID
    end
    return nil -- Read only the ID assigned by ActionQueue; never reconstruct it.
end

local function sourceNameFor(action)
    local source = action and action.sourceInfo or nil
    return source and source.name or nil
end

local function workspaceKey(station, sourceName)
    station = tostring(station or "unknown")
    if SOURCE_SENSITIVE[station] then
        local source = normalize(sourceName)
        if source ~= "" then return station .. "|" .. source end
    end
    return station
end

local function candidateWorkspaceKey(candidate)
    if not candidate then return nil end
    local sourceName = candidate.expectedSource or (candidate.source and candidate.source.name) or nil
    return workspaceKey(candidate.requiredStation, sourceName)
end

local function currentQueues(keys)
    local queueModule = JLP:GetModule("ActionQueue")
    local queues = {}
    if not queueModule then return queues end
    for _, key in ipairs(keys or productionKeys()) do queues[key] = queueModule:Build(key) end
    return queues
end

local function currentAction(queue)
    local index = queue and tonumber(queue.currentIndex) or 0
    return index > 0 and queue and queue.actions and queue.actions[index] or nil
end

function RouteSession:GetWorkspaceKey(station, sourceName)
    return workspaceKey(station, sourceName)
end

function RouteSession:GetActionID(key, action, plan)
    return actionID(key, action, plan)
end

function RouteSession:_ActionMatchesTarget(key, action, targetStation, targetSourceName)
    if not action then return false end
    local flow = JLP:GetModule("ExecutionFlow")
    local station = flow and flow.StationForAction and flow:StationForAction(key, action) or "unknown"
    if station ~= targetStation then return false end
    if not SOURCE_SENSITIVE[station] then return true end
    local wanted = normalize(targetSourceName)
    local observed = normalize(sourceNameFor(action))
    if wanted == "" or observed == "" then return true end
    return wanted == observed
end

-- Build a dependency-safe snapshot of the consecutive actions that can be
-- completed in the selected workspace. Each profession pointer advances only
-- after its own current action was admitted, so prerequisites are never skipped.
function RouteSession:BuildBatch(candidate, queues)
    if not candidate or not candidate.action then return {} end
    queues = queues or currentQueues()
    local selectedQueue = queues[candidate.key]
    local selectedPlan = candidate.plan or (selectedQueue and selectedQueue.plan) or nil
    local selectedID = actionID(candidate.key, candidate.action, selectedPlan)
    if candidate.actionID~=nil and candidate.actionID~=selectedID then return {} end
    local targetStation = tostring(candidate.requiredStation or "unknown")
    local targetSourceName = candidate.expectedSource or (candidate.source and candidate.source.name) or nil
    local pointers, out, seen = {}, {}, {}

    for _, key in ipairs(productionKeys()) do
        local queue = queues[key]
        pointers[key] = tonumber(queue and queue.currentIndex) or 0
    end

    local safety = 0
    local advanced = true
    while advanced and safety < 64 do
        safety = safety + 1
        advanced = false
        for _, key in ipairs(productionKeys()) do
            local queue = queues[key]
            local index = pointers[key]
            local action = queue and queue.actions and queue.actions[index] or nil
            if action and self:_ActionMatchesTarget(key, action, targetStation, targetSourceName) then
                local id = actionID(key, action, queue and queue.plan)
                if id and not seen[id] then
                    seen[id] = true
                    out[#out + 1] = {
                        id = id,
                        key = key,
                        profession = professionLabel(key),
                        kind = action.kind,
                        text = action.text,
                        itemID = action.itemID,
                        itemName = action.itemName,
                        recipe = action.recipe or action.recipeName or (queue and queue.plan and queue.plan.step and queue.plan.step.recipe) or nil,
                        recipeID = action.recipeID or (queue and queue.plan and queue.plan.step and queue.plan.step.recipeID) or nil,
                        targetSkill = queue and queue.plan and queue.plan.step and queue.plan.step.skillTarget or nil,
                        source = action.source,
                        sourceName = sourceNameFor(action),
                        status = "pending",
                        queueIndex = index,
                    }
                end
                if id then
                    pointers[key] = index + 1
                    advanced = true
                end
            end
        end
    end

    -- Partial decisions may retain their assigned head, but must not jump a
    -- different or unresolved current prerequisite in an available queue.
    local selectedHead = currentAction(selectedQueue)
    if selectedHead and actionID(candidate.key,selectedHead,selectedPlan)~=selectedID then selectedID=nil end
    if selectedID and not seen[selectedID] then
        table.insert(out, 1, {
            id = selectedID,
            key = candidate.key,
            profession = candidate.profession or professionLabel(candidate.key),
            kind = candidate.action.kind,
            text = candidate.action.text,
            itemID = candidate.action.itemID,
            itemName = candidate.action.itemName,
            recipe = candidate.action.recipe or candidate.action.recipeName or (selectedPlan and selectedPlan.step and selectedPlan.step.recipe) or nil,
            recipeID = candidate.action.recipeID or (selectedPlan and selectedPlan.step and selectedPlan.step.recipeID) or nil,
            targetSkill = selectedPlan and selectedPlan.step and selectedPlan.step.skillTarget or nil,
            source = candidate.action.source,
            sourceName = candidate.expectedSource or sourceNameFor(candidate.action),
            status = "pending",
            queueIndex = 1,
        })
    end
    return out
end

local function countCompleted(session)
    local done = 0
    for _, entry in ipairs(session and session.actions or {}) do
        if entry.status == "completed" then done = done + 1 end
    end
    return done
end

function RouteSession:_UpdateCounts(session)
    session.totalActions = #(session.actions or {})
    session.completedActions = countCompleted(session)
    session.remainingActions = math.max(0, session.totalActions - session.completedActions)
    if session.totalActions > 0 then
        session.ratio = math.min(1, session.completedActions / session.totalActions)
    else
        session.ratio = 1
    end
end

function RouteSession:_ContextMatches(session)
    local flow = JLP:GetModule("ExecutionFlow")
    local context = flow and flow.GetCurrentContext and flow:GetCurrentContext() or { station="world" }
    if not session or context.station ~= session.station then return false, context end
    if not SOURCE_SENSITIVE[session.station] then return true, context end
    local wanted = normalize(session.expectedSource)
    local observed = normalize(context.actorName or context.merchantName or context.trainerName)
    if wanted == "" then return true, context end
    if observed == "" then return nil, context end
    return wanted == observed, context
end

function RouteSession:_Start(candidate, reason, queues)
    if not candidate or not candidate.action then return nil end
    local actions = self:BuildBatch(candidate, queues)
    if #actions == 0 then return nil end
    self.serial = self.serial + 1
    local station = tostring(candidate.requiredStation or "unknown")
    local sourceName = candidate.expectedSource or (candidate.source and candidate.source.name) or nil
    local match, context = nil, nil
    local session = {
        id = "route-session:" .. tostring(self.serial),
        workspaceKey = workspaceKey(station, sourceName),
        station = station,
        label = candidate.requiredLabel or station,
        expectedSource = sourceName,
        status = "planned",
        createdAt = now(),
        createdReason = tostring(reason or "observe"),
        lastObservedAt = now(),
        actions = actions,
        completedActions = 0,
        totalActions = #actions,
        remainingActions = #actions,
        ratio = 0,
    }
    self.active = session
    match, context = self:_ContextMatches(session)
    if match ~= false and context and context.station == station then
        session.enteredAt = now()
        session.status = match == nil and "entered-unverified" or "entered"
        session.observedSource = context.actorName or context.merchantName or context.trainerName
    end
    return session
end

function RouteSession:_Finalize(status, reason)
    local session = self.active
    if not session then return nil end
    session.status = status
    session.finishedAt = now()
    session.finishReason = tostring(reason or status)
    self:_UpdateCounts(session)
    boundedAppend(self.history, session, 30)
    if status == "completed" then self.lastCompleted = session end
    self.active = nil
    return session
end

function RouteSession:_EntryCurrent(entry, queues)
    local queue = queues and queues[entry.key] or nil
    local action = currentAction(queue)
    local id = action and actionID(entry.key, action, queue and queue.plan) or nil
    -- Unknown IDs cannot constitute completion/entry equivalence.
    return id ~= nil and entry.id ~= nil and id == entry.id, action, queue
end

function RouteSession:_BindExecution(entry, queues)
    local isCurrent = self:_EntryCurrent(entry, queues)
    if not isCurrent then return end
    local execution = JLP:GetModule("ExecutionProgress")
    local status = execution and execution:GetStatus(entry.key) or nil
    -- A shared action kind is not a transaction identity.  Only the exact
    -- semantic queue action can bind a stateful execution receipt.
    if status and status.active and entry.id and status.active.id == entry.id
        and status.activeID == entry.id and status.active.kind == entry.kind then
        entry.executionID = entry.id
    end
end

function RouteSession:_CompletedByExecution(entry, session)
    -- Rebuilt sessions and older saved references must not transplant evidence
    -- from a different recipe/source action, even if its kind is identical.
    if not entry.id or entry.executionID ~= entry.id then return false end
    local execution = JLP:GetModule("ExecutionProgress")
    if execution and execution.HasCompleted then
        local completed, receipt = execution:HasCompleted(entry.key, entry.executionID, session.createdAt)
        if not completed or type(receipt) ~= "table" or receipt.id ~= entry.id
            or receipt.status ~= "completed" then return false end
        if session.createdAt and (not receipt.completedAt or receipt.completedAt < session.createdAt) then
            return false
        end
        return true
    end
    local status = execution and execution:GetStatus(entry.key) or nil
    local last = status and status.lastCompleted or nil
    return last and last.id == entry.id and last.status == "completed"
        and (not session.createdAt or (last.completedAt and last.completedAt >= session.createdAt)) or false
end

function RouteSession:_CompletedByTransaction(entry, session, queues)
    if entry.kind ~= "craft-leveling" then return false end
    local isCurrent = self:_EntryCurrent(entry, queues)
    if isCurrent then return false end
    local tracker = JLP:GetModule("ProgressTracker")
    local status = tracker and tracker:GetStatus(entry.key) or nil
    local tx = status and status.lastTransaction or nil
    if not tx or tx.status ~= "success" then return false end
    -- A historic success receipt without a verifiable finish time cannot
    -- establish that THIS newly created session completed.  Neither the
    -- recipe name nor a stepAdvanced flag provides temporal attribution.
    -- ProgressTracker normally timestamps finished transactions; preserve
    -- those legitimate receipts without synthesizing missing legacy times.
    local finishedAt = tonumber(tx.finishedAt)
    if not finishedAt then return false end
    if session.createdAt then
        local createdAt = tonumber(session.createdAt)
        if not createdAt or finishedAt < createdAt then return false end
    end
    -- A successful craft is evidence for THIS recipe/skill target only.  A
    -- generic stepAdvanced flag or a nameless transaction is not proof that a
    -- distinct queued craft was completed after route recalculation.
    local matchingRecipe = false
    if entry.recipeID and tx.recipeID then
        if tonumber(entry.recipeID) ~= tonumber(tx.recipeID) then return false end
        matchingRecipe = true
    end
    if entry.recipe and tx.recipeName then
        if normalize(entry.recipe) ~= normalize(tx.recipeName) then return false end
        matchingRecipe = true
    end
    if not matchingRecipe then return false end
    if entry.targetSkill then
        if not tx.targetSkill or tonumber(entry.targetSkill) ~= tonumber(tx.targetSkill) then return false end
    end
    return tx.stepAdvanced == true or tx.targetReached == true
end

function RouteSession:_ReconcileEntries(session, queues)
    local changed = false
    for _, entry in ipairs(session.actions or {}) do
        if entry.status ~= "completed" then
            self:_BindExecution(entry, queues)
            local completed = self:_CompletedByExecution(entry, session)
            if not completed then completed = self:_CompletedByTransaction(entry, session, queues) end
            if completed then
                entry.status = "completed"
                entry.completedAt = now()
                changed = true
            end
        end
    end
    local before = session.completedActions or 0
    self:_UpdateCounts(session)
    if before ~= session.completedActions then changed = true end
    return changed
end

function RouteSession:_Extend(session, candidate, queues)
    if not session or not candidate then return false end
    local key = candidateWorkspaceKey(candidate)
    if key ~= session.workspaceKey then return false end
    local additions = self:BuildBatch(candidate, queues)
    local seen = {}
    for _, entry in ipairs(session.actions or {}) do seen[entry.id] = true end
    local changed = false
    for _, entry in ipairs(additions) do
        if entry.id and not seen[entry.id] then
            seen[entry.id] = true
            session.actions[#session.actions + 1] = entry
            changed = true
        end
    end
    if changed then self:_UpdateCounts(session) end
    return changed
end

function RouteSession:Observe(reason)
    local keys=(JLP.GetObservationKeys and JLP:GetObservationKeys() or productionKeys())
    local queues = currentQueues(keys)
    local nextBest = JLP:GetModule("NextBestAction")
    local workspace=JLP:GetModule("WorkspaceOrchestrator")
    local models={}
    for _,key in ipairs(keys) do models[key]=workspace and workspace:Build(key) end
    local decision = nextBest and nextBest:Select(models,workspace and workspace:GetContext()) or nil
    local selected = decision and decision.selected or nil
    local changed = false

    if not self.active and selected then
        if self:_Start(selected, reason, queues) then changed = true end
    end

    local session = self.active
    if session then
        local match, context = self:_ContextMatches(session)
        if context and context.station == session.station and match ~= false then
            if not session.enteredAt then session.enteredAt = now(); changed = true end
            local nextStatus = match == nil and "entered-unverified" or "entered"
            if session.status ~= nextStatus then session.status = nextStatus; changed = true end
            session.observedSource = context.actorName or context.merchantName or context.trainerName
        elseif session.enteredAt and session.status ~= "left" then
            session.status = "left"
            session.leftAt = now()
            changed = true
        end

        if selected and candidateWorkspaceKey(selected) == session.workspaceKey then
            if self:_Extend(session, selected, queues) then changed = true end
        end
        if self:_ReconcileEntries(session, queues) then changed = true end

        if session.remainingActions <= 0 and session.totalActions > 0 then
            self:_Finalize("completed", "workspace-batch-complete")
            changed = true
        elseif not session.enteredAt and selected and candidateWorkspaceKey(selected) ~= session.workspaceKey then
            self:_Finalize("superseded", "next-best-workspace-changed-before-entry")
            self:_Start(selected, reason, queues)
            changed = true
        end
    end

    if changed then
        self.revision = self.revision + 1
        if JLP.EventBus then JLP.EventBus:Emit("ROUTE_SESSION_UPDATED", self.revision, reason, self:GetStatus()) end
    end
    return changed, self:GetStatus()
end

function RouteSession:Initialize()
    if not self.initialized then
        self.initialized = true
        if JLP.EventBus then
            for _, eventName in ipairs({
                "PROFESSION_EXECUTION_UPDATED", "WORKSPACE_ORCHESTRATION_UPDATED",
                "CRAFT_ACTION_UPDATED", "ENCHANT_ACTION_UPDATED", "PROFESSION_TRANSACTION_UPDATED"
            }) do
                JLP.EventBus:On(eventName, function() RouteSession:Observe(eventName) end)
            end
        end
    end
    return self:Observe("player-login")
end

function RouteSession:GetStatus()
    local session = self.active or self.lastCompleted
    if not session then
        return {
            contract = self.contract,
            status = "idle",
            active = nil,
            lastCompleted = self.lastCompleted,
            revision = self.revision,
        }
    end
    local active = self.active ~= nil
    return {
        contract = self.contract,
        status = active and session.status or "completed",
        active = active and session or nil,
        session = session,
        sessionID = session.id,
        workspaceKey = session.workspaceKey,
        station = session.station,
        label = session.label,
        expectedSource = session.expectedSource,
        enteredAt = session.enteredAt,
        completedActions = tonumber(session.completedActions) or 0,
        totalActions = tonumber(session.totalActions) or 0,
        remainingActions = tonumber(session.remainingActions) or 0,
        ratio = tonumber(session.ratio) or 0,
        progressText = string.format("%d / %d actions completed here", tonumber(session.completedActions) or 0, tonumber(session.totalActions) or 0),
        lastCompleted = self.lastCompleted,
        revision = self.revision,
    }
end

function RouteSession:GetForCandidate(candidate)
    local session = self.active
    if not session or not candidate then return nil end
    if candidateWorkspaceKey(candidate) ~= session.workspaceKey then return nil end
    local status = self:GetStatus()
    status.engaged = session.enteredAt ~= nil and (session.remainingActions or 0) > 0
    return status
end

function RouteSession:GetBias(candidate)
    local session = self.active
    if not session or not session.enteredAt or (session.remainingActions or 0) <= 0 then return 0, nil end
    if candidateWorkspaceKey(candidate) == session.workspaceKey then
        return -900, self:GetForCandidate(candidate)
    end
    return 900, nil
end

function RouteSession:FormatCompact(status)
    status = status or self:GetStatus()
    if not status or not status.session then return "Route session: idle" end
    local session = status.session
    local source = session.expectedSource and (" @ " .. tostring(session.expectedSource)) or ""
    return string.format(
        "Route session: %s%s - %d/%d actions - %s",
        tostring(session.label or session.station or "Workspace"), source,
        tonumber(session.completedActions) or 0, tonumber(session.totalActions) or 0,
        tostring(status.status or session.status or "active")
    )
end

function RouteSession:GetSummary()
    local lines = { self:FormatCompact(self:GetStatus()) }
    local session = self.active
    if session then
        for index, entry in ipairs(session.actions or {}) do
            lines[#lines + 1] = string.format(
                "%d. %s - %s - %s",
                index, tostring(entry.profession or entry.key), tostring(entry.status or "pending"), tostring(entry.text or entry.kind or "Continue")
            )
        end
    end
    return table.concat(lines, "\n")
end

-- Synchronous request scope; discarded before the caller returns.
do
    local build=RouteSession.Observe
    function RouteSession:Observe(...)
        local args={n=select("#",...),...}
        local function evaluate() return build(self,(unpack or table.unpack)(args,1,args.n)) end
        return withObservationPass("RouteSession.Observe",evaluate)
    end
end

JLP:RegisterModule("RouteSession", RouteSession)
