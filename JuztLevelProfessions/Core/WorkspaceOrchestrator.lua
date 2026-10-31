local _, JLP = ...

local function prerequisiteWorkspace(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    if ownership and ownership.owned==true then return nil end
    local state=ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN"
    local reg=JLP:GetModule("ProfessionRegistry")
    local label=reg and reg:GetDisplayNameOrKey(key) or tostring(key)
    local text=state=="PROFESSION_NOT_LEARNED" and
        ("Learn "..label.." before JuztLevel can plan this profession.") or
        ("Verify learned "..label.." ownership before JuztLevel can plan this profession.")
    return {key=ownership and ownership.key or key,ownership=ownership,state=state,
        status=state,terminalReason=state,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,lightweightPrerequisite=true,workspaceState=state,workspaceReady=false,guidance=text}
end

local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end
local function memoObservation(group,key,fn)
    if JLP.MemoObservation then return JLP:MemoObservation(group,key,fn) end
    return fn()
end
local WorkspaceOrchestrator = {
    contract = "source-aware-route-orchestration-v2",
    sessions = {},
    history = {},
    revision = 0,
}

local function registry() return JLP:GetModule("ProfessionRegistry") end

local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end

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
    return reg and reg:GetDisplayName(key) or tostring(key or "Unknown profession")
end

local function currentPlan(key)
    local planner = JLP:GetModule("Planner")
    return planner and planner:GetProfessionPlan(key) or nil
end

local function currentAction(key, plan)
    local queueModule = JLP:GetModule("ActionQueue")
    local queue = queueModule and queueModule:Build(key, plan) or nil
    local index = queue and tonumber(queue.currentIndex) or 0
    return index > 0 and queue and queue.actions and queue.actions[index] or nil, queue
end

local function resolveAssist(key, plan, queue)
    local assist = JLP:GetModule("ActionAssist")
    return assist and assist:Get(key, plan, queue) or nil
end

local function actionID(key, action, plan)
    if type(action)~="table" or action.identityUnresolved then return nil end
    if action.identityContract=="semantic-plan-action-v1" and type(action.actionID)=="string" and action.actionID~="" then
        return action.actionID
    end
    return nil -- Only ActionQueue-assigned identity, never a synthetic fallback.
end

-- Read the existing queue, never a caller-selected action. Invalid prepared
-- inputs fail closed without rebuilding a plan or resolving another source.
local function queueHead(key, plan, queue)
    if type(plan)~="table" or type(queue)~="table" or type(queue.actions)~="table" then
        return nil,"NO_QUALIFIED_QUEUE"
    end
    if plan.step~=nil and type(plan.step)~="table" then return nil,"INVALID_PLAN_STEP" end
    if queue.status=="active" or queue.status=="complete" then
        if queue.key==nil then return nil,"MISSING_QUEUE_KEY" end
        if queue.plan~=plan then return nil,"QUEUE_PLAN_MISMATCH" end
    end
    local reg=registry()
    local function sameKey(value)
        return value==nil or (reg and reg.NormalizeKey and reg:NormalizeKey(value) or value)==key
    end
    if not sameKey(queue.key) or not sameKey(plan.key) or
        (queue.plan~=nil and queue.plan~=plan) then return nil,"QUEUE_CONTEXT_MISMATCH" end
    local index=queue.currentIndex
    if type(index)~="number" or index<0 or index%1~=0 then return nil,"INVALID_QUEUE_INDEX" end
    if index==0 then
        if next(queue.actions)~=nil then return nil,"INVALID_TERMINAL_QUEUE_ACTIONS" end
        if queue.status=="complete" or queue.status=="unqualified" or queue.status=="reference" then return nil end
        return nil,queue.terminalReason or "NO_QUALIFIED_QUEUE_HEAD"
    end
    local action=queue.actions[index]
    if queue.status~="active" or index>#queue.actions or type(action)~="table" or
        type(action.kind)~="string" or not sameKey(action.professionKey) then return nil,"INVALID_QUEUE_HEAD" end
    if action.identityContract~="semantic-plan-action-v1" then return nil,"INVALID_QUEUE_IDENTITY_CONTRACT" end
    if action.identityUnresolved then return nil,"UNRESOLVED_QUEUE_IDENTITY" end
    if type(action.actionID)~="string" or action.actionID=="" then return nil,"MISSING_QUEUE_IDENTITY" end
    -- ActionQueue's existing semantic identity binds character, profession and
    -- route. Do not invent snapshot tokens or treat unknown identity as proof.
    if action.identityContract=="semantic-plan-action-v1" and type(action.actionID)=="string" then
        local module=JLP:GetModule("ActionQueue")
        if not module or not module.GetActionID or module:GetActionID(key,action,plan)~=action.actionID then
            return nil,"QUEUE_IDENTITY_MISMATCH"
        end
    end
    return action
end

local function boundedAppend(list, value, limit)
    list[#list + 1] = value
    while #list > (limit or 30) do table.remove(list, 1) end
end

function WorkspaceOrchestrator:GetContext()
    local flow = JLP:GetModule("ExecutionFlow")
    if flow and flow.GetCurrentContext then return flow:GetCurrentContext() end
    return { station="world", label="World" }
end

function WorkspaceOrchestrator:GetRequiredWorkspace(key, action)
    if not action then return nil, nil end
    local flow = JLP:GetModule("ExecutionFlow")
    local station = flow and flow.StationForAction and flow:StationForAction(key, action) or "unknown"
    local label = flow and flow.GetStationLabel and flow:GetStationLabel(station) or tostring(station or "Other")
    return station, label
end

function WorkspaceOrchestrator:SourceMatch(requiredStation, source, context)
    context = context or self:GetContext()
    if not requiredStation or context.station ~= requiredStation then return nil, "station-mismatch" end

    if requiredStation ~= "vendor" and requiredStation ~= "trainer" and requiredStation ~= "source" then
        return true, "workspace-match"
    end

    local expected = source and source.name or nil
    local observed = context.actorName or context.merchantName or context.trainerName
    if not expected or expected == "" then return true, "workspace-match-no-specific-source" end
    if not observed or observed == "" then return nil, "source-unresolved" end
    if normalize(expected) == normalize(observed) then return true, "source-name-match" end
    return false, "source-name-mismatch"
end

function WorkspaceOrchestrator:_BuildModel(key, plan, action, queue, assist, context)
    local requiredStation, requiredLabel = self:GetRequiredWorkspace(key, action)
    local source = action and action.sourceInfo or assist and assist.source or nil
    local stationMatch = requiredStation ~= nil and context.station == requiredStation or false
    local sourceMatch, sourceReason = self:SourceMatch(requiredStation, source, context)
    local workspaceReady = stationMatch and sourceMatch ~= false
    local state, tone, guidance

    if not action and queue and queue.status=="unqualified" then
        state, tone, guidance = "UNQUALIFIED", "muted", "No qualified route; reference and live profession evidence are required"
    elseif not action and queue and queue.status=="reference" then
        state, tone, guidance = "REFERENCE", "muted", "Historical/reference route only; no native execution authority"
    elseif not action and queue and queue.status=="complete" then
        state, tone, guidance = "COMPLETE", "good", "Route complete"
    elseif not action then
        state, tone, guidance = "UNQUALIFIED", "muted", "No qualified current queue action; verify the current profession plan"
    elseif workspaceReady then
        if sourceMatch == nil then
            state, tone = "HERE_UNVERIFIED", "warn"
            guidance = tostring(requiredLabel or "Workspace") .. " · open, source not identified"
        else
            state, tone = "HERE", "good"
            guidance = tostring(requiredLabel or "Workspace") .. " · ready here"
        end
    elseif stationMatch and sourceMatch == false then
        state, tone = "WRONG_SOURCE", "bad"
        guidance = string.format("%s · expected %s", tostring(requiredLabel or "Source"), tostring(source and source.name or "another source"))
    elseif context.station ~= "world" and context.station ~= "unknown" then
        state, tone = "SWITCH", "warn"
        guidance = string.format("%s · leave %s", tostring(requiredLabel or "next workspace"), tostring(context.label or "current workspace"))
    else
        state, tone = "GO", "cyan"
        if source and source.name then
            guidance = string.format("%s · %s", tostring(requiredLabel or "Source"), tostring(source.name))
        elseif requiredStation and requiredStation:match("^craft:") then
            guidance = tostring(requiredLabel or professionLabel(key)) .. " · open profession window"
        elseif requiredStation == "bank" then
            guidance = "Bank · open your bank"
        elseif requiredStation == "auction" then
            guidance = "Auction House · open Auction House"
        elseif requiredStation == "trainer" then
            guidance = "Trainer · open the required profession trainer"
        elseif requiredStation == "vendor" then
            guidance = "Vendor · open the required vendor"
        else
            guidance = tostring(requiredLabel or "Next workspace")
        end
    end

    local execution = JLP:GetModule("ExecutionProgress")
    local executionStatus = execution and execution:GetStatus(key) or nil
    local session = self.sessions[key]
    local lastSession = nil
    for i = #self.history, 1, -1 do
        if self.history[i].key == key then lastSession = self.history[i]; break end
    end

    return {
        contract = self.contract,
        key = key,
        profession = professionLabel(key),
        plan = plan,
        queue = queue,
        action = action,
        actionID = actionID(key, action, plan),
        actionKind = action and action.kind or nil,
        requiredStation = requiredStation,
        requiredLabel = requiredLabel,
        source = source,
        expectedSource = source and source.name or nil,
        currentStation = context.station,
        currentLabel = context.label,
        observedSource = context.actorName or context.merchantName or context.trainerName,
        stationMatch = stationMatch,
        sourceMatch = sourceMatch,
        sourceReason = sourceReason,
        workspaceReady = workspaceReady,
        workspaceState = state,
        terminalReason = not action and state~="COMPLETE" and queue and queue.terminalReason or nil,
        tone = tone,
        guidance = guidance,
        canMap = assist and assist.canMap and true or false,
        canAH = assist and assist.canAH and true or false,
        session = session,
        sessionStatus = session and session.status or nil,
        workspaceEntered = session and session.enteredAt ~= nil or false,
        execution = executionStatus,
        lastCompletedWorkspace = lastSession and lastSession.status == "completed" and lastSession or nil,
    }
end

function WorkspaceOrchestrator:Build(key, prepared)
    local prerequisite=prerequisiteWorkspace(key)
    if prerequisite then return prerequisite end
    local reg=registry()
    local availability=reg and reg:ResolveWorkflowAvailability(key,"executionFlow") or nil
    if availability and availability.state~="available" then
        local normalized=availability.key or key
        return {contract=self.contract,key=normalized,profession=professionLabel(normalized),plan=nil,queue=nil,action=nil,terminalReason=availability.terminalReason,workspaceState=availability.state=="not-production-enabled" and "STAGED" or "UNSUPPORTED",tone=availability.state=="not-production-enabled" and "muted" or "bad",guidance=availability.state=="not-production-enabled" and "Profession is registered but not production-enabled." or "Profession is unsupported.",workspaceReady=false}
    end
    if reg then key=availability.key end
    prepared = type(prepared) == "table" and prepared or nil
    local plan = prepared and prepared.plan or currentPlan(key)
    local queue = prepared and prepared.queue or nil
    if not queue then
        local ignored
        ignored, queue = currentAction(key, plan)
    end
    local action, invalid = queueHead(key, plan, queue)
    if invalid then
        queue={key=key,plan=plan,status="unqualified",currentIndex=0,actions={},
            terminalReason=invalid,readOnly=true,nativeDispatchAllowed=false}
    end
    local assist = prepared and prepared.assist or nil
    if assist and (type(assist)~="table" or assist.action~=action or assist.queue~=queue) then assist=nil
    elseif not assist and action then assist=resolveAssist(key,plan,queue) end
    if not action then assist=nil end
    local context = prepared and prepared.context or memoObservation("workspace","context",function() return self:GetContext() end)
    return self:_BuildModel(key, plan, action, queue, assist, context)
end

function WorkspaceOrchestrator:_FinalizeSession(key, session, status, reason)
    if not session then return end
    session.status = status
    session.finishedAt = now()
    session.finishReason = reason
    boundedAppend(self.history, session, 40)
    self.sessions[key] = nil
end

function WorkspaceOrchestrator:_ObserveKey(key, reason, prepared)
    local prerequisite=prerequisiteWorkspace(key)
    if prerequisite then return false,prerequisite end
    local model = self:Build(key,prepared)
    local action = model.action
    local id = model.actionID
    local session = self.sessions[key]
    local execution = model.execution
    local lastCompleted = execution and execution.lastCompleted or nil
    local changed = false

    if session and session.executionID and lastCompleted and lastCompleted.id == session.executionID and session.status ~= "completed" then
        self:_FinalizeSession(key, session, "completed", lastCompleted.completionReason or "confirmed-action-completion")
        session = nil
        changed = true
    end

    if session and (not action or session.actionID ~= id) then
        self:_FinalizeSession(key, session, "superseded", "route-action-changed")
        session = nil
        changed = true
    end

    if action and id and not session then
        session = {
            key = key,
            profession = professionLabel(key),
            actionID = id,
            actionKind = action.kind,
            actionText = action.text,
            requiredStation = model.requiredStation,
            requiredLabel = model.requiredLabel,
            expectedSource = model.expectedSource,
            status = "waiting",
            createdAt = now(),
            lastObservedAt = now(),
            lastReason = tostring(reason or "observe"),
        }
        if execution and execution.active and execution.active.kind == action.kind then
            session.executionID = execution.activeID
        end
        self.sessions[key] = session
        changed = true
    end

    if session then
        if not session.executionID and execution and execution.active and execution.active.kind == action.kind then
            session.executionID = execution.activeID
            changed = true
        end
        if model.workspaceReady and not session.enteredAt then
            session.enteredAt = now()
            session.enteredStation = model.currentStation
            session.enteredSource = model.observedSource
            session.status = model.sourceMatch == nil and "entered-unverified" or "entered"
            changed = true
        elseif model.workspaceReady and session.enteredAt then
            session.status = model.sourceMatch == nil and "entered-unverified" or "entered"
        elseif session.enteredAt and not model.workspaceReady and session.status ~= "completed" then
            session.status = "left"
            session.leftAt = now()
        end
        session.lastObservedAt = now()
        session.lastReason = tostring(reason or "observe")
    end
    return changed
end

function WorkspaceOrchestrator:ObserveAll(reason)
    local changed = false
    for _, key in ipairs((JLP.GetObservationKeys and JLP:GetObservationKeys() or productionKeys())) do
        if self:_ObserveKey(key, reason) then changed = true end
    end
    if changed then
        self.revision = self.revision + 1
        if JLP.EventBus then JLP.EventBus:Emit("WORKSPACE_ORCHESTRATION_UPDATED", self.revision, reason) end
    end
    return changed
end

function WorkspaceOrchestrator:Initialize()
    return self:ObserveAll("player-login")
end

function WorkspaceOrchestrator:BuildAll()
    local context = self:GetContext()
    local models = {}
    for _, key in ipairs(productionKeys()) do models[key] = self:Build(key, {context=context}) end

    local decisionModule = JLP:GetModule("NextBestAction")
    local decision = decisionModule and type(decisionModule.Select)=="function" and decisionModule:Select(models, context) or nil
    local selected
    local reason, terminalReason, routeComplete = "unqualified", "UNQUALIFIED", false
    if type(decision)=="table" then
        reason, terminalReason = decision.reason or "unqualified", decision.terminalReason
        if decision.selected~=nil or decision.selectedKey~=nil or decision.selectedAction~=nil then
            local candidate = type(decision.selected)=="table" and decision.selected or nil
            local model = type(decision.selectedKey)=="string" and models[decision.selectedKey] or nil
            local head, invalid
            if model then head, invalid = queueHead(model.key, model.plan, model.queue) end
            local id = actionID(model and model.key, head, model and model.plan)
            if candidate and model and head and not invalid and id and decision.routeComplete==false
                and not decision.terminalReason and candidate.key==model.key and decision.selectedKey==model.key
                and candidate.action==head and decision.selectedAction==head and model.action==head
                and candidate.actionID==id and model.actionID==id
                and (candidate.workspaceActionID==nil or candidate.workspaceActionID==id) then
                selected = model
            else
                reason, terminalReason = "unqualified", "UNQUALIFIED"
            end
        elseif decision.routeComplete==true then
            local seen, complete = false, true
            for _, model in pairs(models) do
                if not model.lightweightPrerequisite then
                    seen = true
                    local head, invalid = queueHead(model.key, model.plan, model.queue)
                    if invalid or head or model.workspaceState~="COMPLETE" or model.action~=nil or not model.queue or model.queue.status~="complete" then
                        complete = false
                    end
                end
            end
            routeComplete = seen and complete and decision.terminalReason=="ROUTE_COMPLETE" and decision.reason=="route-complete"
            if not routeComplete then reason, terminalReason = "unqualified", "UNQUALIFIED" end
        elseif decision.reason=="route-complete" or decision.terminalReason=="ROUTE_COMPLETE" then
            reason, terminalReason = "unqualified", "UNQUALIFIED"
        end
    end

    return {
        contract = self.contract,
        context = context,
        professions = models,
        recommended = selected,
        recommendedKey = selected and selected.key or nil,
        recommendedAction = selected and selected.action or nil,
        reason = reason,
        terminalReason = terminalReason,
        routeComplete = routeComplete,
        decision = decision,
        revision = self.revision,
    }
end

function WorkspaceOrchestrator:FormatCompact(model)
    if type(model) == "string" then model = self:Build(model) end
    if not model then return "Workspace: unavailable" end
    if model.terminalReason then return "Workspace: "..tostring(model.workspaceState or model.terminalReason) end
    if not model.action then
        local queue=model.queue
        local head, invalid = queueHead(model.key, model.plan, queue)
        if invalid or head then return "Workspace: UNQUALIFIED" end
        if model.workspaceState=="COMPLETE" and queue and queue.status=="complete" and
            queue.currentIndex==0 and type(queue.actions)=="table" and next(queue.actions)==nil then
            return "Workspace: route complete"
        end
        return "Workspace: "..tostring(model.workspaceState or "UNQUALIFIED")
    end
    return string.format("Workspace: %s - %s", tostring(model.workspaceState or "GO"), tostring(model.guidance or model.requiredLabel or "next workspace"))
end

function WorkspaceOrchestrator:GetSummary()
    local all = self:BuildAll()
    local lines = {
        string.format("Current workspace: %s", tostring(all.context and all.context.label or "World")),
    }
    for _, key in ipairs(productionKeys()) do
        local model = all.professions[key]
        lines[#lines + 1] = string.format("%s: %s", professionLabel(key), self:FormatCompact(model):gsub("^Workspace:%s*", ""))
    end
    if all.recommended then
        lines[#lines + 1] = string.format("Recommended next: %s - %s (%s)", tostring(all.recommended.profession), tostring(all.recommended.action and all.recommended.action.text or "Continue"), tostring(all.reason))
    else
        lines[#lines + 1] = all.routeComplete and "Recommended next: route complete" or ("Recommended next: "..tostring(all.reason or "unqualified"))
    end
    return table.concat(lines, "\n")
end

-- Synchronous request scope; discarded before the caller returns.
do
    local build=WorkspaceOrchestrator.Build
    function WorkspaceOrchestrator:Build(...)
        local args={n=select("#",...),...}
        local function evaluate() return build(self,(unpack or table.unpack)(args,1,args.n)) end
        return withObservationPass("WorkspaceOrchestrator.Build",evaluate)
    end
end
do
    local build=WorkspaceOrchestrator.BuildAll
    function WorkspaceOrchestrator:BuildAll(...)
        local args={n=select("#",...),...}
        local function evaluate() return build(self,(unpack or table.unpack)(args,1,args.n)) end
        return withObservationPass("WorkspaceOrchestrator.BuildAll",evaluate)
    end
end
do
    local build=WorkspaceOrchestrator.ObserveAll
    function WorkspaceOrchestrator:ObserveAll(...)
        local args={n=select("#",...),...}
        local function evaluate() return build(self,(unpack or table.unpack)(args,1,args.n)) end
        return withObservationPass("WorkspaceOrchestrator.ObserveAll",evaluate)
    end
end

JLP:RegisterModule("WorkspaceOrchestrator", WorkspaceOrchestrator)
