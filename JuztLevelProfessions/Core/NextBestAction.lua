local _, JLP = ...
local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end

-- Cross-profession decision layer. Only the current ActionQueue head for each
-- profession is eligible, so scoring can optimize workspace/travel without
-- reordering prerequisites inside a profession route.
local NextBestAction = {
    contract = "deterministic-next-best-action-v1",
}

local function registry() return JLP:GetModule("ProfessionRegistry") end

local function professionRank(key)
    local reg = registry()
    return reg and reg:GetOrder(key) or 9999
end

local function orderedModelKeys(models, productionOnly)
    local reg = registry()
    local raw = {}
    for key, model in pairs(models or {}) do
        local candidate = type(model) == "table" and model.key or key
        candidate = reg and reg:NormalizeKey(candidate) or tostring(candidate or ""):upper()
        if candidate and candidate ~= "" then raw[candidate] = true end
    end
    local keys = reg and reg:OrderKeys(raw) or {}
    if productionOnly and reg then
        local filtered = {}
        for _, key in ipairs(keys) do if reg:IsWorkflowEnabled(key) and reg:HasCapability(key, "executionFlow") then filtered[#filtered+1]=key end end
        return filtered
    end
    return keys
end

local STATE_WEIGHT = {
    CRAFTING = 0,
    TRAIN = 8,
    LEARN = 10,
    VERIFY = 12,
    LEARN_RECIPE = 14,
    RETRIEVE = 16,
    ACQUIRE = 18,
    PREPARE = 20,
    NEXT_RECIPE = 22,
    CRAFT = 24,
    BLOCKED = 80,
    COMPLETE = 100,
}

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("[%p%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function professionLabel(key)
    local reg = registry()
    return reg and reg:GetDisplayName(key) or tostring(key or "Unknown profession")
end

local function currentAction(queue)
    local index = queue and tonumber(queue.currentIndex) or 0
    return index > 0 and queue and queue.actions and queue.actions[index] or nil, index
end

local function sameSource(a, b)
    local an = normalize(a and a.expectedSource)
    local bn = normalize(b and b.expectedSource)
    if an == "" or bn == "" then return true end
    return an == bn
end

local function workspaceKey(model)
    if not model then return "unknown" end
    local station = tostring(model.requiredStation or "unknown")
    if station == "vendor" or station == "trainer" or station == "source" then
        local source = normalize(model.expectedSource)
        return source ~= "" and (station .. "|" .. source) or station
    end
    return station
end

local function reasonFor(candidate)
    if candidate.machineState == "CRAFTING" then return "active-transaction" end
    if candidate.routeSessionEngaged then return "active-workspace-session" end
    if candidate.workspaceReady and candidate.sourceMatch == true then return "verified-current-workspace" end
    if candidate.workspaceReady then return "available-in-current-workspace" end
    if candidate.workspaceState == "WRONG_SOURCE" then return "correct-source-required" end
    if candidate.rawTravelCost ~= nil then return "lowest-safe-travel-cost" end
    if (candidate.batchBenefit or 0) > 0 then return "workspace-batch-efficiency" end
    return "dependency-safe-order"
end

function NextBestAction:_ResolveSource(model)
    if not model then return nil end
    if model.source then return model.source end
    local action = model.action
    if action and action.sourceInfo then return action.sourceInfo end
    return nil
end

function NextBestAction:_Lookahead(model)
    if not model or not model.queue or not model.action then return 0 end
    local flow = JLP:GetModule("ExecutionFlow")
    if not flow or not flow.StationForAction then return 0 end
    local _, index = currentAction(model.queue)
    local station = model.requiredStation
    local count = 0
    for i = math.max(1, index), math.min(#(model.queue.actions or {}), math.max(1, index) + 3) do
        local action = model.queue.actions[i]
        if flow:StationForAction(model.key, action) ~= station then break end
        count = count + 1
    end
    return math.max(0, count - 1)
end

function NextBestAction:_CrossProfessionSynergy(model, models)
    if not model or not model.action then return 0 end
    local key = workspaceKey(model)
    local count = 0
    for _, otherKey in ipairs(orderedModelKeys(models, true)) do
        local other = models and models[otherKey] or nil
        if other and other ~= model and other.action and workspaceKey(other) == key and sameSource(model, other) then
            count = count + 1
        end
    end
    return count
end

function NextBestAction:_Travel(model, context, origin)
    if not model or not model.action or model.workspaceReady then return nil, nil, nil end
    local source = self:_ResolveSource(model)
    local router = JLP:GetModule("TravelRouter")
    if not router then return nil, nil, nil end
    local destination = source and router:GetSourceLocation(source) or nil
    if not destination then return nil, nil, nil end
    origin = origin or router:GetPlayerOrigin()
    local transition = router:Transition(origin, destination, origin)
    return transition and tonumber(transition.cost) or nil, transition, destination
end

function NextBestAction:_Arrival(model, transition)
    if not model or not model.action then return "COMPLETE", "Route complete" end
    if model.workspaceState == "HERE" then
        return "HERE_VERIFIED", tostring(model.requiredLabel or "Workspace") .. " ready"
    end
    if model.workspaceState == "HERE_UNVERIFIED" then
        return "HERE_UNVERIFIED", tostring(model.requiredLabel or "Workspace") .. " open; source identity unverified"
    end
    if model.workspaceState == "WRONG_SOURCE" then
        return "WRONG_SOURCE", string.format("Go to %s", tostring(model.expectedSource or model.requiredLabel or "the required source"))
    end
    if model.workspaceState == "SWITCH" then
        local target = model.expectedSource or model.requiredLabel or "the next workspace"
        return "SWITCH_WORKSPACE", string.format("Switch to %s", tostring(target))
    end
    if transition then
        local short = transition.kind == "same-zone" and "same zone"
            or transition.kind == "same-continent" and "same continent"
            or transition.kind == "cross-continent" and "cross continent"
            or transition.kind == "dungeon" and "dungeon source"
            or "travel required"
        local target = model.expectedSource or model.requiredLabel or "required source"
        return "TRAVEL_REQUIRED", string.format("%s · %s", tostring(target), tostring(short))
    end
    if model.requiredStation and tostring(model.requiredStation):match("^craft:") then
        return "OPEN_PROFESSION", "Open " .. tostring(model.requiredLabel or professionLabel(model.key))
    end
    if model.requiredStation == "bank" then return "OPEN_BANK", "Open your bank" end
    if model.requiredStation == "auction" then return "OPEN_AUCTION", "Open the Auction House" end
    if model.requiredStation == "trainer" then return "OPEN_TRAINER", "Open the required profession trainer" end
    if model.requiredStation == "vendor" then return "OPEN_VENDOR", "Open the required vendor" end
    return "GO", tostring(model.expectedSource or model.guidance or model.requiredLabel or "Continue")
end

function NextBestAction:_SourceGuidance(model, transition)
    local source = self:_ResolveSource(model)
    local resolver = JLP:GetModule("SourceResolver")
    local formatted = source and resolver and resolver:Format(source, false) or nil
    local parts = {}
    if formatted and formatted ~= "" then parts[#parts + 1] = formatted end
    if transition and transition.label then parts[#parts + 1] = transition.label end
    if #parts == 0 then parts[#parts + 1] = tostring(model and model.guidance or "Continue with the current route action.") end
    return table.concat(parts, " | ")
end

function NextBestAction:BuildCandidate(model, context, models, origin, travelPlan)
    if not model or not model.action then return nil end
    if model.action.kind == "verify-reference" or model.action.kind == "planner" then return nil end
    context = context or { station="world", label="World" }
    local machine = JLP:GetModule("ProfessionState")
    local machineModel = machine and machine:Get(model.key, model.plan) or nil
    local state = model.machineState or (model.machine and model.machine.state) or (machineModel and machineModel.state) or nil
    local travelCost, transition, destination = self:_Travel(model, context, origin)
    local lookahead = self:_Lookahead(model)
    local synergy = self:_CrossProfessionSynergy(model, models)
    local batchBenefit = lookahead + synergy

    local bucket
    if state == "CRAFTING" then bucket = 0
    elseif model.workspaceReady and model.sourceMatch == true then bucket = 1
    elseif model.workspaceReady then bucket = 2
    elseif model.workspaceState == "WRONG_SOURCE" then bucket = 4
    elseif context.station ~= "world" and context.station ~= "unknown" then bucket = 5
    else bucket = 3 end

    local switchPenalty = 0
    if not model.workspaceReady and context.station ~= "world" and context.station ~= "unknown" then
        switchPenalty = 120
    end
    if model.workspaceState == "WRONG_SOURCE" then switchPenalty = switchPenalty + 80 end

    local effectiveTravel = travelCost
    if effectiveTravel == nil and not model.workspaceReady then
        if model.requiredStation == "bank" or model.requiredStation == "auction" or tostring(model.requiredStation or ""):match("^craft:") then
            effectiveTravel = 12
        elseif model.requiredStation == "vendor" or model.requiredStation == "trainer" or model.requiredStation == "source" then
            effectiveTravel = 20
        else
            effectiveTravel = 24
        end
    end

    local stateWeight = STATE_WEIGHT[state or "BLOCKED"] or 60
    local rank = professionRank(model.key)
    local score = (bucket * 1000) + switchPenalty + ((effectiveTravel or 0) * 10) + stateWeight - (batchBenefit * 25) + rank
    local arrivalState, arrivalText = self:_Arrival(model, transition)

    -- Project only the queue-assigned identity. Missing, unresolved or
    -- contradictory evidence must not become a new receipt/session ID here.
    local assignedID
    local action = model.action
    if action.identityContract=="semantic-plan-action-v1" and not action.identityUnresolved and
        type(action.actionID)=="string" and action.actionID~="" and
        (model.actionID==nil or model.actionID==action.actionID) then
        assignedID=action.actionID
    end

    local candidate = {
        contract = self.contract,
        key = model.key,
        profession = model.profession or professionLabel(model.key),
        action = model.action,
        actionID = assignedID,
        actionKind = model.actionKind or model.action.kind,
        machineState = state,
        requiredStation = model.requiredStation,
        requiredLabel = model.requiredLabel,
        workspaceState = model.workspaceState,
        workspaceReady = model.workspaceReady and true or false,
        sourceMatch = model.sourceMatch,
        expectedSource = model.expectedSource,
        observedSource = model.observedSource,
        source = self:_ResolveSource(model),
        canMap = model.canMap and true or false,
        canAH = model.canAH and true or false,
        bucket = bucket,
        switchPenalty = switchPenalty,
        travelCost = effectiveTravel,
        rawTravelCost = travelCost,
        transition = transition,
        destination = destination,
        lookahead = lookahead,
        synergy = synergy,
        batchBenefit = batchBenefit,
        stateWeight = stateWeight,
        score = score,
        arrivalState = arrivalState,
        arrivalText = arrivalText,
        sourceGuidance = self:_SourceGuidance(model, transition),
        -- Preserve the stateful execution/workspace session with the candidate.
        -- ContextAction uses these fields to keep progress labels anchored to the
        -- original execution baseline even when live queue quantities shrink.
        execution = model.execution,
        session = model.session,
        sessionStatus = model.sessionStatus,
        workspaceEntered = model.workspaceEntered and true or false,
        workspaceActionID = assignedID,
    }
    local routeSession = JLP:GetModule("RouteSession")
    local sessionAdjustment, sessionStatus = 0, nil
    if routeSession and routeSession.GetBias then
        sessionAdjustment, sessionStatus = routeSession:GetBias(candidate)
    end
    -- An in-flight protected Craft/Enchant transaction is always stronger than
    -- workspace affinity; never let a route-session penalty displace CRAFTING.
    if state == "CRAFTING" then sessionAdjustment = 0 end
    candidate.routeSessionAdjustment = tonumber(sessionAdjustment) or 0
    candidate.routeSession = sessionStatus or (routeSession and routeSession.GetForCandidate and routeSession:GetForCandidate(candidate) or nil)
    candidate.routeSessionEngaged = candidate.routeSession and candidate.routeSession.engaged and true or false
    local travelSession = JLP:GetModule("TravelSession")
    local travelAdjustment, travelPreferred = 0, false
    if travelSession and travelSession.GetCandidateBias then
        travelAdjustment, travelPreferred = travelSession:GetCandidateBias(candidate, travelPlan)
    end
    -- An entered workspace batch remains authoritative; travel-session affinity
    -- only orders the next workspace after the active RouteSession is finished.
    if candidate.routeSessionEngaged then travelAdjustment = 0; travelPreferred = false end
    if state == "CRAFTING" then travelAdjustment = 0; travelPreferred = false end
    candidate.travelSessionAdjustment = tonumber(travelAdjustment) or 0
    candidate.travelSessionPreferred = travelPreferred and true or false
    candidate.travelSession = travelPlan
    candidate.score = candidate.score + candidate.routeSessionAdjustment + candidate.travelSessionAdjustment
    if state == "CRAFTING" then candidate.score = -100000 + professionRank(model.key) end
    candidate.reason = reasonFor(candidate)
    return candidate
end

function NextBestAction:Select(models, context, origin)
    models = models or {}
    context = context or { station="world", label="World" }
    local reg = registry()
    local modelKeys = orderedModelKeys(models, false)
    local unknownKeys = {}
    for key, model in pairs(models or {}) do
        local candidate = type(model)=="table" and model.key or key
        local normalized = reg and reg:NormalizeKey(candidate) or nil
        if not normalized then unknownKeys[#unknownKeys+1]=tostring(candidate or key or "UNKNOWN") end
    end
    table.sort(unknownKeys)
    local productionKeys, nonProductionKeys = {}, {}
    for _, key in ipairs(modelKeys) do
        local api=JLP:GetModule("ProfessionAPI")
        local ownership=api and api.GetOwnership and api:GetOwnership(key)
        if not (ownership and ownership.owned==true) then -- catalogue entries never compete with owned actions
        elseif reg and reg:IsWorkflowEnabled(key) and reg:HasCapability(key, "executionFlow") then productionKeys[#productionKeys+1]=key
        else nonProductionKeys[#nonProductionKeys+1]=key end
    end
    local productionModels = {}
    for _, key in ipairs(productionKeys) do productionModels[key]=models[key] end
    local travelSession = JLP:GetModule("TravelSession")
    local travelPlan = travelSession and travelSession.BuildFromModels and travelSession:BuildFromModels(productionModels, context, origin) or nil
    local candidates = {}
    for _, key in ipairs(productionKeys) do
        local candidate = self:BuildCandidate(models[key], context, productionModels, origin, travelPlan)
        if candidate then candidates[#candidates + 1] = candidate end
    end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        local ar, br = professionRank(a.key), professionRank(b.key)
        if ar ~= br then return ar < br end
        return tostring(a.actionID or "") < tostring(b.actionID or "")
    end)

    local selected = candidates[1]
    local routeComplete = false
    local terminalReason, reason
    if selected then
        reason = selected.reason
    elseif #unknownKeys > 0 then
        terminalReason = "UNSUPPORTED_PROFESSION"
        reason = "unsupported-profession"
    elseif #nonProductionKeys > 0 then
        terminalReason = "NOT_PRODUCTION_ENABLED"
        reason = "not-production-enabled"
    elseif #productionKeys == 0 then
        terminalReason = "NO_MODELS"
        reason = "no-models"
    else
        local allComplete = true
        for _, key in ipairs(productionKeys) do
            local model = models[key]
            local explicitComplete = model and (model.workspaceState == "COMPLETE" or model.machineState == "COMPLETE" or (model.queue and model.queue.status == "complete")) or false
            if not explicitComplete then allComplete = false; break end
        end
        if allComplete then routeComplete=true; terminalReason="ROUTE_COMPLETE"; reason="route-complete"
        else terminalReason="NO_ELIGIBLE_ACTION"; reason="no-eligible-action" end
    end
    local travelTransitionModule = JLP:GetModule("TravelTransition")
    local routeSession = JLP:GetModule("RouteSession")
    local travelTransition = travelTransitionModule and travelTransitionModule.BuildFrom
        and travelTransitionModule:BuildFrom(travelPlan, context, origin, routeSession and routeSession:GetStatus() or nil) or nil
    local navigationGuidanceModule = JLP:GetModule("NavigationGuidance")
    local navigationGuidance = navigationGuidanceModule and navigationGuidanceModule.BuildFrom
        and navigationGuidanceModule:BuildFrom(travelTransition) or nil
    return {
        contract = self.contract,
        context = context,
        selected = selected,
        selectedKey = selected and selected.key or nil,
        selectedAction = selected and selected.action or nil,
        candidates = candidates,
        reason = reason,
        terminalReason = terminalReason,
        routeComplete = routeComplete,
        evaluatedKeys = productionKeys,
        nonProductionKeys = nonProductionKeys,
        unknownKeys = unknownKeys,
        registryContract = reg and reg.contract or nil,
        travelPlan = travelPlan,
        travelTransition = travelTransition,
        navigationGuidance = navigationGuidance,
    }
end

function NextBestAction:Build()
    local orchestrator = JLP:GetModule("WorkspaceOrchestrator")
    local context = orchestrator and orchestrator:GetContext() or { station="world", label="World" }
    local models = {}
    local reg = registry()
    local keys = reg and reg:GetWorkflowKeys("executionFlow") or {}
    for _, key in ipairs(keys) do models[key] = orchestrator and orchestrator:Build(key) or nil end
    local decision = self:Select(models, context)
    local destinationHandoff = JLP:GetModule("DestinationHandoff")
    decision.destinationHandoff = destinationHandoff and destinationHandoff.GetStatus and destinationHandoff:GetStatus() or nil
    return decision
end

function NextBestAction:GetCandidate(decision, key)
    for _, candidate in ipairs(decision and decision.candidates or {}) do
        if candidate.key == key then return candidate end
    end
    return nil
end

function NextBestAction:FormatCompact(decision)
    decision = decision or self:Build()
    local selected = decision and decision.selected or nil
    if not selected then
        if decision and decision.routeComplete then return "Next best action: route complete" end
        return "Next best action: " .. tostring(decision and decision.reason or "unavailable")
    end
    local action = selected.action and selected.action.text or "Continue"
    return string.format("Next best action: %s - %s - %s", tostring(selected.profession), tostring(action), tostring(selected.reason))
end

function NextBestAction:GetSummary()
    local decision = self:Build()
    local lines = { self:FormatCompact(decision) }
    for _, candidate in ipairs(decision.candidates or {}) do
        lines[#lines + 1] = string.format(
            "%s: score %.0f | %s | %s | batch %d",
            tostring(candidate.profession), tonumber(candidate.score) or 0,
            tostring(candidate.arrivalState or "GO"), tostring(candidate.sourceGuidance or "Continue"), tonumber(candidate.batchBenefit) or 0
        )
    end
    return table.concat(lines, "\n")
end

-- Synchronous request scope; discarded before the caller returns.
do
    local build=NextBestAction.Build
    function NextBestAction:Build(...)
        local args={n=select("#",...),...}
        local function evaluate() return build(self,(unpack or table.unpack)(args,1,args.n)) end
        return withObservationPass("NextBestAction.Build",evaluate)
    end
end

JLP:RegisterModule("NextBestAction", NextBestAction)
