local _, JLP = ...

-- Plans a dependency-safe chain of workspace batches across Tailoring and
-- Enchanting. It never invents paths or travel times: physical transitions are
-- classified only through TravelRouter's audited source geography, while Bank,
-- Auction House and profession-window transitions remain workspace guidance.
local TravelSession = {
    contract = "audited-workspace-travel-session-v1",
    active = nil,
    lastCompleted = nil,
    serial = 0,
    revision = 0,
    initialized = false,
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end
local function professionRank(key)
    local reg=registry()
    return reg and reg:GetOrder(key) or 9999
end
local SOURCE_SENSITIVE = { vendor=true, trainer=true, source=true }
local MAX_BATCHES = 10

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

local function sourceName(action)
    local source = action and action.sourceInfo or nil
    return source and source.name or nil
end

local function currentAction(queue, pointer)
    local index = tonumber(pointer) or tonumber(queue and queue.currentIndex) or 0
    return index > 0 and index%1==0 and queue and queue.status=="active"
        and type(queue.actions)=="table" and queue.actions[index] or nil, index
end

local function stationLabel(station)
    local flow = JLP:GetModule("ExecutionFlow")
    if flow and flow.GetStationLabel then return flow:GetStationLabel(station) end
    if station == "bank" then return "Bank" end
    if station == "auction" then return "Auction House" end
    if station == "trainer" then return "Trainer" end
    if station == "vendor" then return "Vendor" end
    if station == "source" then return "Recipe Source" end
    local key = tostring(station or ""):match("^craft:(.+)$")
    if key then
        local reg=registry()
        local label=reg and reg:GetDisplayName(key) or nil
        if label then return label end
    end
    return "Workspace"
end

local function workspaceKey(station, actor)
    local routeSession = JLP:GetModule("RouteSession")
    if routeSession and routeSession.GetWorkspaceKey then
        return routeSession:GetWorkspaceKey(station, actor)
    end
    station = tostring(station or "unknown")
    if SOURCE_SENSITIVE[station] then
        local name = normalize(actor)
        if name ~= "" then return station .. "|" .. name end
    end
    return station
end

local function actionID(key, action, plan)
    if type(action)=="table" and action.identityContract=="semantic-plan-action-v1"
        and not action.identityUnresolved and type(action.actionID)=="string" and action.actionID~="" then
        return action.actionID
    end
    return nil -- Project only the identity already assigned by ActionQueue.
end

local function descriptorFor(key, action, queue)
    if type(action)~="table" then return nil end
    local flow = JLP:GetModule("ExecutionFlow")
    local station = flow and flow.StationForAction and flow:StationForAction(key, action) or "unknown"
    local source = action.sourceInfo
    local actor = source and source.name or nil
    local label = actor or stationLabel(station)
    return {
        key = key,
        action = action,
        actionID = actionID(key, action, queue and queue.plan),
        station = station,
        workspaceKey = workspaceKey(station, actor),
        source = source,
        sourceName = actor,
        label = label,
    }
end

local function sameWorkspace(a, b)
    if not a or not b or a.station ~= b.station then return false end
    if not SOURCE_SENSITIVE[a.station] then return true end
    local left, right = normalize(a.sourceName), normalize(b.sourceName)
    if left == "" or right == "" then return true end
    return left == right
end

local function clonePointers(queues)
    local pointers = {}
    for _, key in ipairs(productionKeys()) do
        local queue = queues and queues[key]
        pointers[key] = tonumber(queue and queue.currentIndex) or 0
    end
    return pointers
end

local function copyPointers(pointers)
    local out = {}
    for _, key in ipairs(productionKeys()) do out[key] = tonumber(pointers and pointers[key]) or 0 end
    return out
end

local function actionEntry(key, action, queue, index)
    return {
        id = actionID(key, action, queue and queue.plan),
        key = key,
        kind = action and action.kind,
        text = action and action.text,
        itemID = action and action.itemID,
        itemName = action and action.itemName,
        recipe = action and (action.recipe or action.recipeName) or (queue and queue.plan and queue.plan.step and queue.plan.step.recipe) or nil,
        queueIndex = index,
    }
end

-- Consume every action that can be executed at the target workspace without
-- skipping either profession's current dependency head.
local function collectWorkspaceBatch(queues, pointers, target)
    local nextPointers = copyPointers(pointers)
    local actions, seen = {}, {}
    local advanced, safety = true, 0
    while advanced and safety < 64 do
        safety = safety + 1
        advanced = false
        for _, key in ipairs(productionKeys()) do
            local queue = queues and queues[key]
            local action, index = currentAction(queue, nextPointers[key])
            local descriptor = descriptorFor(key, action, queue)
            if descriptor and sameWorkspace(descriptor, target) then
                local entry = actionEntry(key, action, queue, index)
                if entry.id then
                    if not seen[entry.id] then
                        seen[entry.id] = true
                        actions[#actions + 1] = entry
                    end
                    nextPointers[key] = index + 1
                    advanced = true
                end
            end
        end
    end
    return actions, nextPointers
end

local function hasRemaining(queues, pointers)
    for _, key in ipairs(productionKeys()) do
        local action = currentAction(queues and queues[key], pointers and pointers[key])
        if action then return true end
    end
    return false
end

local function fallbackWorkspaceCost(station)
    if tostring(station or ""):match("^craft:") then return 8 end
    if station == "bank" then return 10 end
    if station == "auction" then return 12 end
    if station == "trainer" or station == "vendor" or station == "source" then return 20 end
    return 24
end

local function contextMatches(context, descriptor)
    if not context or not descriptor or context.station ~= descriptor.station then return false end
    if not SOURCE_SENSITIVE[descriptor.station] then return true end
    local expected = normalize(descriptor.sourceName)
    local observed = normalize(context.actorName or context.merchantName or context.trainerName)
    if expected == "" then return true end
    if observed == "" then return false end
    return expected == observed
end

local function transitionShort(transition)
    local kind = transition and transition.kind or "unknown"
    if kind == "same-zone" then return "same zone" end
    if kind == "same-continent" then return "same continent" end
    if kind == "cross-continent" then return "cross continent" end
    if kind == "dungeon" then return "dungeon source" end
    if kind == "current-workspace" then return "already here" end
    if kind == "workspace-switch" then return "workspace switch" end
    return "travel not fully audited"
end

function TravelSession:_LocationFor(descriptor)
    local router = JLP:GetModule("TravelRouter")
    if not router or not descriptor or not descriptor.source then return nil end
    return router:GetSourceLocation(descriptor.source)
end

function TravelSession:_CandidateScore(descriptor, actions, currentLocation, origin, context)
    local router = JLP:GetModule("TravelRouter")
    local location = self:_LocationFor(descriptor)
    local here = contextMatches(context, descriptor)
    local rawCost = location and router and router:Cost(currentLocation, location) or nil
    local effectiveCost = rawCost or fallbackWorkspaceCost(descriptor.station)
    local batchBenefit = math.max(0, #(actions or {}) - 1)
    local rank = professionRank(descriptor.key)
    local score = (here and -10000 or 0) + (effectiveCost * 10) - (batchBenefit * 35) + rank
    return score, rawCost, effectiveCost, location, here
end

function TravelSession:_Transition(currentLocation, location, origin, descriptor, here)
    if here then
        return { kind="current-workspace", label="Current workspace already matches this batch.", cost=0, audited=true }
    end
    local router = JLP:GetModule("TravelRouter")
    if location and router then
        local transition = router:Transition(currentLocation, location, origin)
        if transition then transition.audited = true end
        return transition
    end
    return {
        kind = "workspace-switch",
        label = "Workspace switch is required; no physical route is inferred for this workspace.",
        cost = fallbackWorkspaceCost(descriptor and descriptor.station),
        audited = false,
    }
end

function TravelSession:BuildFromModels(models, context, origin, maxBatches)
    models = models or {}
    context = context or { station="world", label="World" }
    local reg=registry()
    if reg then
        local staged,unknown={},{}
        for rawKey,model in pairs(models) do
            if model~=nil then
                local normalized=reg:NormalizeKey(rawKey)
                if not normalized then
                    unknown[#unknown+1]=tostring(rawKey)
                elseif not reg:IsWorkflowEnabled(normalized) or not reg:HasCapability(normalized,"executionFlow") then
                    staged[#staged+1]=normalized
                end
            end
        end
        if #unknown>0 or #staged>0 then
            table.sort(unknown); staged=reg:OrderKeys(staged)
            local reason=#unknown>0 and "UNSUPPORTED_PROFESSION" or "NOT_PRODUCTION_ENABLED"
            return {contract=self.contract,batches={},batchCount=0,currentBatch=nil,nextBatch=nil,workspaceSwitches=0,auditedTransitions=0,unknownTransitions=0,origin=origin,routeComplete=false,status=reason=="UNSUPPORTED_PROFESSION" and "unsupported-profession" or "not-production-enabled",terminalReason=reason,unsupportedKeys=unknown,nonProductionKeys=staged,chainText=reason,evidence="registry-scoped-travel-chain"}
        end
    end
    local queues = {}
    for _, key in ipairs(productionKeys()) do queues[key] = models[key] and models[key].queue or nil end
    local pointers = clonePointers(queues)
    local router = JLP:GetModule("TravelRouter")
    origin = origin or (router and router:GetPlayerOrigin()) or nil
    local currentLocation = origin
    local batches = {}
    local workspaceSwitches, auditedTransitions, unknownTransitions = 0, 0, 0
    local previousWorkspace = context.station and context.station ~= "world" and context.station ~= "unknown" and workspaceKey(context.station, context.actorName or context.merchantName or context.trainerName) or nil
    maxBatches = math.max(1, math.min(tonumber(maxBatches) or MAX_BATCHES, 20))

    local safety = 0
    while hasRemaining(queues, pointers) and #batches < maxBatches and safety < 64 do
        safety = safety + 1
        local candidates, candidateByWorkspace = {}, {}
        for _, key in ipairs(productionKeys()) do
            local queue = queues[key]
            local action = currentAction(queue, pointers[key])
            local descriptor = descriptorFor(key, action, queue)
            if descriptor and descriptor.actionID then
                local actions, nextPointers = collectWorkspaceBatch(queues, pointers, descriptor)
                if #actions > 0 and not candidateByWorkspace[descriptor.workspaceKey] then
                    local score, rawCost, effectiveCost, location, here = self:_CandidateScore(descriptor, actions, currentLocation, origin, context)
                    local candidate = {
                        descriptor = descriptor,
                        actions = actions,
                        nextPointers = nextPointers,
                        score = score,
                        rawTravelCost = rawCost,
                        travelCost = effectiveCost,
                        location = location,
                        here = here,
                    }
                    candidateByWorkspace[descriptor.workspaceKey] = candidate
                    candidates[#candidates + 1] = candidate
                end
            end
        end
        if #candidates == 0 then break end
        table.sort(candidates, function(a, b)
            if a.score ~= b.score then return a.score < b.score end
            local ar = professionRank(a.descriptor.key)
            local br = professionRank(b.descriptor.key)
            if ar ~= br then return ar < br end
            return tostring(a.descriptor.workspaceKey) < tostring(b.descriptor.workspaceKey)
        end)
        local chosen = candidates[1]
        local descriptor = chosen.descriptor
        local transition = self:_Transition(currentLocation, chosen.location, origin, descriptor, chosen.here)
        local batch = {
            index = #batches + 1,
            workspaceKey = descriptor.workspaceKey,
            station = descriptor.station,
            label = descriptor.label,
            sourceName = descriptor.sourceName,
            source = descriptor.source,
            actions = chosen.actions,
            actionCount = #chosen.actions,
            primaryKey = descriptor.key,
            transition = transition,
            transitionKind = transition and transition.kind or "unknown",
            travelCost = tonumber(chosen.travelCost) or 0,
            rawTravelCost = chosen.rawTravelCost,
            audited = transition and transition.audited == true or false,
            alreadyHere = chosen.here and true or false,
        }
        batch.rationale = string.format("%s; %d dependency-safe action%s", transitionShort(transition), batch.actionCount, batch.actionCount == 1 and "" or "s")
        batches[#batches + 1] = batch
        if previousWorkspace and previousWorkspace ~= batch.workspaceKey then workspaceSwitches = workspaceSwitches + 1 end
        previousWorkspace = batch.workspaceKey
        if batch.audited then auditedTransitions = auditedTransitions + 1 else unknownTransitions = unknownTransitions + 1 end
        pointers = chosen.nextPointers
        if chosen.location and not chosen.location.dungeon then currentLocation = chosen.location end
        -- Only the first batch can be the workspace that is currently open.
        context = { station="world", label="World" }
    end

    -- A lack of admitted batches is not evidence that an unqualified queue ended.
    -- Preserve the empty/no-model case; every presented queue must otherwise be
    -- explicitly complete and empty at index zero.
    local queuesComplete = true
    local observedKeys, qualifiedKeys = {}, {}
    for _, key in ipairs(productionKeys()) do
        if models[key] then
            local queue = queues[key]
            observedKeys[key] = true
            if actionID(key,currentAction(queue),queue and queue.plan) then qualifiedKeys[key] = true end
            if not queue or queue.status~="complete" or tonumber(queue.currentIndex)~=0
                or type(queue.actions)~="table" or next(queue.actions)~=nil then
                queuesComplete = false
            end
        end
    end
    local routeComplete = #batches == 0 and queuesComplete
    local emptyText = routeComplete and "Route complete" or "Route unqualified"
    local labels = {}
    for _, batch in ipairs(batches) do labels[#labels + 1] = tostring(batch.label or stationLabel(batch.station)) end
    local chainText = #labels > 0 and table.concat(labels, " → ") or emptyText
    local signatureParts = {}
    for _, batch in ipairs(batches) do
        signatureParts[#signatureParts + 1] = batch.workspaceKey
        for _, entry in ipairs(batch.actions or {}) do signatureParts[#signatureParts + 1] = tostring(entry.id or "") end
    end

    return {
        contract = self.contract,
        batches = batches,
        batchCount = #batches,
        currentBatch = batches[1],
        nextBatch = batches[2],
        workspaceSwitches = workspaceSwitches,
        auditedTransitions = auditedTransitions,
        unknownTransitions = unknownTransitions,
        origin = origin,
        routeComplete = routeComplete,
        observedKeys = observedKeys,
        qualifiedKeys = qualifiedKeys,
        chainText = chainText,
        signature = table.concat(signatureParts, ";"),
        evidence = "dependency-safe-audited-workspace-travel-chain",
    }
end

function TravelSession:Build(keys)
    local orchestrator = JLP:GetModule("WorkspaceOrchestrator")
    local context = orchestrator and orchestrator:GetContext() or { station="world", label="World" }
    local models = {}
    for _, key in ipairs(keys or productionKeys()) do models[key] = orchestrator and orchestrator:Build(key) or nil end
    return self:BuildFromModels(models, context)
end

function TravelSession:GetCandidateBias(candidate, plan)
    if not candidate or not plan or not plan.currentBatch then return 0, false end
    local routeSession = JLP:GetModule("RouteSession")
    local currentRoute = routeSession and routeSession:GetStatus() or nil
    if currentRoute and currentRoute.active and currentRoute.active.enteredAt and (currentRoute.remainingActions or 0) > 0 then
        return 0, false
    end
    local key = workspaceKey(candidate.requiredStation, candidate.expectedSource or (candidate.source and candidate.source.name))
    if key == plan.currentBatch.workspaceKey then return -140, true end
    return 140, false
end

local function completedPrefix(active)
    local out = {}
    for _, entry in ipairs(active and active.completedWorkspaces or {}) do
        out[#out + 1] = string.format("%s %d/%d", tostring(entry.label or "Workspace"), tonumber(entry.completedActions) or 0, tonumber(entry.totalActions) or 0)
    end
    return out
end

local function scopeObserved(active, plan)
    for key in pairs(active and active.professionKeys or {}) do
        if not (plan and plan.observedKeys and plan.observedKeys[key]) then return false end
    end
    return true
end

function TravelSession:_CaptureCompletedWorkspace(active)
    local routeSession = JLP:GetModule("RouteSession")
    local completed = routeSession and routeSession.lastCompleted or nil
    if not active or not completed or not completed.id then return false end
    active.seenRouteSessions = active.seenRouteSessions or {}
    if active.seenRouteSessions[completed.id] then return false end
    if active.createdAt and completed.finishedAt and completed.finishedAt < active.createdAt then return false end
    active.seenRouteSessions[completed.id] = true
    active.completedWorkspaces = active.completedWorkspaces or {}
    active.completedWorkspaces[#active.completedWorkspaces + 1] = {
        routeSessionID = completed.id,
        workspaceKey = completed.workspaceKey,
        label = completed.label or completed.station,
        completedActions = tonumber(completed.completedActions) or #(completed.actions or {}),
        totalActions = tonumber(completed.totalActions) or #(completed.actions or {}),
        finishedAt = completed.finishedAt,
    }
    while #active.completedWorkspaces > 6 do table.remove(active.completedWorkspaces, 1) end
    return true
end

function TravelSession:Observe(reason)
    local plan = self:Build(JLP.GetObservationKeys and JLP:GetObservationKeys() or nil)
    local changed = false
    if not self.active and plan.currentBatch then
        self.serial = self.serial + 1
        self.active = {
            id = "travel-session:" .. tostring(self.serial),
            createdAt = now(),
            status = "active",
            createdReason = tostring(reason or "observe"),
            completedWorkspaces = {},
            seenRouteSessions = {},
        }
        changed = true
    end
    local active = self.active
    if active then
        active.professionKeys = active.professionKeys or {}
        for key in pairs(plan.qualifiedKeys or {}) do active.professionKeys[key] = true end
        if not scopeObserved(active, plan) then
            plan.routeComplete = false
            if not plan.currentBatch then plan.chainText = "Route unqualified" end
        end
        local status = plan.currentBatch and "active" or "unqualified"
        if active.status ~= status then active.status = status; changed = true end
        if self:_CaptureCompletedWorkspace(active) then changed = true end
        if active.planSignature ~= plan.signature then changed = true end
        active.plan = plan
        active.planSignature = plan.signature
        active.updatedAt = now()
        active.lastReason = tostring(reason or "observe")
        if plan.routeComplete then
            active.status = "completed"
            active.finishedAt = now()
            self.lastCompleted = active
            self.active = nil
            changed = true
        end
    end
    if changed then
        self.revision = self.revision + 1
        if JLP.EventBus then JLP.EventBus:Emit("TRAVEL_SESSION_UPDATED", self.revision, reason, self:GetStatus(plan)) end
    end
    return changed, self:GetStatus(plan)
end

function TravelSession:Initialize()
    if not self.initialized then
        self.initialized = true
        if JLP.EventBus then
            for _, eventName in ipairs({
                "ROUTE_SESSION_UPDATED", "PROFESSION_EXECUTION_UPDATED",
                "PROFESSION_TRANSACTION_UPDATED", "WORKSPACE_ORCHESTRATION_UPDATED"
            }) do
                JLP.EventBus:On(eventName, function() TravelSession:Observe(eventName) end)
            end
        end
    end
    return self:Observe("player-login")
end

function TravelSession:GetStatus(plan)
    plan = plan or (self.active and self.active.plan) or self:Build(JLP.GetObservationKeys and JLP:GetObservationKeys() or nil)
    local active = self.active or self.lastCompleted
    local prefix = completedPrefix(active)
    local unqualified = not plan or (not plan.currentBatch and (not plan.routeComplete or not scopeObserved(self.active, plan)))
    local emptyText = unqualified and "Route unqualified" or "Route complete"
    local labels = {}
    for _, value in ipairs(prefix) do labels[#labels + 1] = value end
    for _, batch in ipairs(plan and plan.batches or {}) do labels[#labels + 1] = tostring(batch.label or stationLabel(batch.station)) end
    if unqualified then labels[#labels + 1] = emptyText end
    local displayText = #labels > 0 and table.concat(labels, " → ") or emptyText
    local guideLabels = {}
    if #prefix > 0 then guideLabels[#guideLabels + 1] = prefix[#prefix] end
    local remaining = plan and plan.batches or {}
    for i = 1, math.min(#remaining, 3) do guideLabels[#guideLabels + 1] = tostring(remaining[i].label or stationLabel(remaining[i].station)) end
    if #remaining > 3 then guideLabels[#guideLabels + 1] = "+" .. tostring(#remaining - 3) end
    if unqualified then guideLabels[#guideLabels + 1] = emptyText end
    local guideText = #guideLabels > 0 and table.concat(guideLabels, " → ") or emptyText
    return {
        contract = self.contract,
        sessionID = active and active.id or nil,
        status = unqualified and "unqualified" or (self.active and "active" or (self.lastCompleted and "completed" or "idle")),
        active = self.active,
        plan = plan,
        currentBatch = plan and plan.currentBatch or nil,
        nextBatch = plan and plan.nextBatch or nil,
        batchCount = plan and plan.batchCount or 0,
        workspaceSwitches = plan and plan.workspaceSwitches or 0,
        auditedTransitions = plan and plan.auditedTransitions or 0,
        unknownTransitions = plan and plan.unknownTransitions or 0,
        chainText = unqualified and emptyText or (plan and plan.chainText or emptyText),
        displayText = displayText,
        guideText = guideText,
        completedWorkspaces = active and active.completedWorkspaces or {},
        revision = self.revision,
    }
end

function TravelSession:FormatCompact(status)
    status = status or self:GetStatus()
    return string.format(
        "Travel session: %s | %d workspace switch%s | %d audited transition%s",
        tostring(status.displayText or "Route complete"),
        tonumber(status.workspaceSwitches) or 0, (tonumber(status.workspaceSwitches) or 0) == 1 and "" or "es",
        tonumber(status.auditedTransitions) or 0, (tonumber(status.auditedTransitions) or 0) == 1 and "" or "s"
    )
end

function TravelSession:GetSummary()
    local status = self:GetStatus()
    local lines = { self:FormatCompact(status) }
    for index, batch in ipairs(status.plan and status.plan.batches or {}) do
        lines[#lines + 1] = string.format(
            "%d. %s - %s - %s",
            index, tostring(batch.label or batch.station or "Workspace"),
            tostring(batch.rationale or "dependency-safe batch"),
            batch.audited and "audited travel" or "workspace guidance"
        )
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("TravelSession", TravelSession)
