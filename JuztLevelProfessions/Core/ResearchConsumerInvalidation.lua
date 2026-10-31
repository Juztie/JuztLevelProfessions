local _, JLP = ...

-- Event-driven invalidation for alpha71 read-only Planner consumers.
-- This module never persists authority and never owns execution. It only keeps
-- an in-memory observation of consumer snapshots that have actually been read
-- by a downstream surface, then revalidates those tracked snapshots when
-- authority/evidence/profession/inventory signals change.
local ResearchConsumerInvalidation = {
    contract = "research-consumer-invalidation-orchestrator-v1",
    stateContract = "research-consumer-invalidation-state-v1",
    authority = "tracked-consumer-snapshot-revalidation-only",
    readOnly = true,
    executionEligible = false,
    persisted = false,
    tracked = {},
    revision = 0,
    initialized = false,
}

local INPUT_EVENTS = {
    "RESEARCH_ROUTE_AUTHORITY_UPDATED",
    "PRODUCTION_TAILORING_AUTHORITY_UPDATED",
    "PRODUCTION_ENCHANTING_AUTHORITY_UPDATED",
    "PRODUCTION_ENCHANTING_TARGET_UPDATED",
    "SETTINGS_CHANGED",
    "PROFESSION_PROGRESS_UPDATED",
    "PROFESSION_CRAFT_OBSERVED",
    "PROFESSION_TRANSACTION_UPDATED",
    "RECIPE_TELEMETRY_UPDATED",
    "RECIPE_OUTPUT_EVIDENCE_UPDATED",
    "RECIPE_ACCESS_EVIDENCE_UPDATED",
    "MATERIAL_ACQUISITION_EVIDENCE_UPDATED",
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(value)
    return value == "aggressive" and "aggressive" or "normal"
end

local function isActive(model)
    return type(model) == "table"
        and model.state == "consumer-authority-active"
        and model.consumerAuthorityEnabled == true
        and model.routeAuthorityEnabled == true
        and model.plannerEligible == true
        and model.executionEligible == false
end

local function project(model, trigger)
    model = type(model) == "table" and model or {}
    local snapshot = model.snapshot
    return {
        contract = ResearchConsumerInvalidation.stateContract,
        professionKey = normalizeKey(model.professionKey),
        mode = normalizeMode(model.mode),
        active = isActive(model),
        consumerState = tostring(model.state or "consumer-bridge-unavailable"),
        sourceAuthorityState = tostring(model.sourceAuthorityState or "unavailable"),
        currentBuild = tonumber(model.currentBuild),
        token = snapshot and snapshot.token or model.snapshotToken,
        stateFingerprint = snapshot and snapshot.stateFingerprint or model.stateFingerprint,
        selectedSegment = model.selectedSegment,
        recipe = snapshot and snapshot.recipe or (model.plan and model.plan.step and model.plan.step.recipe),
        trigger = tostring(trigger or "unspecified"),
        readOnly = true,
        executionEligible = false,
        persisted = false,
    }
end

local function meaningfulTransition(previous, current)
    if not previous then return "baseline" end
    if previous.active and not current.active then return "revoked" end
    if not previous.active and current.active then return "promoted" end
    if previous.active and current.active and tostring(previous.token or "") ~= tostring(current.token or "") then
        return "invalidated"
    end
    if previous.active == current.active
        and (tostring(previous.consumerState or "") ~= tostring(current.consumerState or "")
            or tostring(previous.sourceAuthorityState or "") ~= tostring(current.sourceAuthorityState or "")
            or tonumber(previous.currentBuild) ~= tonumber(current.currentBuild)) then
        return "state-changed"
    end
    return "unchanged"
end

local function transitionEventName(transition)
    if transition == "promoted" then return "RESEARCH_CONSUMER_AUTHORITY_PROMOTED" end
    if transition == "revoked" then return "RESEARCH_CONSUMER_AUTHORITY_REVOKED" end
    if transition == "invalidated" then return "RESEARCH_CONSUMER_SNAPSHOT_INVALIDATED" end
    if transition == "state-changed" then return "RESEARCH_CONSUMER_AUTHORITY_STATE_CHANGED" end
    return nil
end

function ResearchConsumerInvalidation:IsTrackable(professionKey)
    local bridge = JLP:GetModule("ResearchPlannerConsumerBridge")
    return bridge and bridge.IsSupported and bridge:IsSupported(normalizeKey(professionKey)) or false
end

function ResearchConsumerInvalidation:_Apply(model, trigger, emitEvents)
    local current = project(model, trigger)
    local key = current.professionKey
    if not key or not self:IsTrackable(key) then return nil, "untracked-profession" end

    local previous = self.tracked[key]
    local transition = meaningfulTransition(previous, current)
    local priorMeaningful = previous and previous.lastTransition or nil
    local hadAuthority = (previous and previous.hadAuthority == true) or (previous and previous.active == true) or current.active == true

    if transition ~= "unchanged" and transition ~= "baseline" then
        self.revision = self.revision + 1
    end

    current.revision = self.revision
    current.transition = transition
    current.lastTransition = (transition ~= "unchanged" and transition ~= "baseline") and transition or priorMeaningful
    current.hadAuthority = hadAuthority
    current.lastActiveToken = current.active and current.token or (previous and (previous.lastActiveToken or previous.token) or nil)
    self.tracked[key] = current

    if emitEvents and transition ~= "unchanged" and transition ~= "baseline" and JLP.EventBus and JLP.EventBus.Emit then
        local specific = transitionEventName(transition)
        if specific then JLP.EventBus:Emit(specific, current, previous) end
        JLP.EventBus:Emit("RESEARCH_CONSUMER_AUTHORITY_UPDATED", transition, current, previous)
    end
    return current, transition
end

function ResearchConsumerInvalidation:TrackModel(model, trigger)
    return self:_Apply(model, trigger or "consumer-read", false)
end

function ResearchConsumerInvalidation:Observe(professionKey, trigger, options)
    professionKey = normalizeKey(professionKey)
    if not professionKey or not self:IsTrackable(professionKey) then return nil, "untracked-profession" end
    local consumer = JLP:GetModule("ResearchPlannerConsumerBridge")
    if not consumer or not consumer.Build then return nil, "consumer-bridge-unavailable" end
    local prior = self.tracked[professionKey]
    local requestedMode = type(options) == "table" and options.mode or nil
    local mode = normalizeMode(requestedMode or (prior and prior.mode) or nil)
    local model = consumer:Build(professionKey, mode, options)
    return self:_Apply(model, trigger or "consumer-revalidation", true)
end

function ResearchConsumerInvalidation:ObserveTracked(trigger, options)
    local keys = {}
    for key in pairs(self.tracked) do keys[#keys + 1] = key end
    table.sort(keys)
    local transitions = {}
    for _, key in ipairs(keys) do
        local state, transition = self:Observe(key, trigger, options)
        transitions[#transitions + 1] = { professionKey=key, state=state, transition=transition }
    end
    return transitions
end

function ResearchConsumerInvalidation:GetStatus(professionKey)
    return self.tracked[normalizeKey(professionKey)]
end

function ResearchConsumerInvalidation:GetRevision()
    return tonumber(self.revision) or 0
end

function ResearchConsumerInvalidation:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        for _, eventName in ipairs(INPUT_EVENTS) do
            if eventName == "RESEARCH_ROUTE_AUTHORITY_UPDATED" or eventName == "PRODUCTION_TAILORING_AUTHORITY_UPDATED" or eventName == "PRODUCTION_ENCHANTING_AUTHORITY_UPDATED" or eventName == "PRODUCTION_ENCHANTING_TARGET_UPDATED" then
                JLP.EventBus:On(eventName, function(payload)
                    self:ObserveTracked(eventName, { mode=payload and payload.mode or nil })
                end)
            else
                JLP.EventBus:On(eventName, function()
                    self:ObserveTracked(eventName)
                end)
            end
        end
    end
    return true
end

function ResearchConsumerInvalidation:GetSummary(professionKey)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local state = self:GetStatus(professionKey)
    local lines = {
        "PLANNER CONSUMER INVALIDATION / EVENT ORCHESTRATION",
        professionKey,
        "Contract: " .. self.contract,
        "Revision: " .. tostring(self:GetRevision()),
    }
    if not state then
        lines[#lines + 1] = "Tracking: not observed by a consumer"
    else
        lines[#lines + 1] = "Tracking: active"
        lines[#lines + 1] = "Consumer state: " .. tostring(state.consumerState)
        lines[#lines + 1] = "Source route authority: " .. tostring(state.sourceAuthorityState)
        lines[#lines + 1] = "Snapshot active: " .. (state.active and "yes" or "no")
        lines[#lines + 1] = "Last transition: " .. tostring(state.lastTransition or state.transition or "baseline")
        lines[#lines + 1] = "Trigger: " .. tostring(state.trigger or "unknown")
        lines[#lines + 1] = "Current build: " .. tostring(state.currentBuild or "unknown")
        lines[#lines + 1] = "Snapshot token: " .. tostring(state.token or "none")
        lines[#lines + 1] = "Had authority: " .. (state.hadAuthority and "yes" or "no")
    end
    lines[#lines + 1] = "Persistence: none"
    lines[#lines + 1] = "Execution authority: disabled"
    return table.concat(lines, "\n")
end

function ResearchConsumerInvalidation:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.persisted ~= false then
        errors[#errors + 1] = "research consumer invalidation boundary invalid"
    end
    if not JLP:GetModule("ResearchPlannerConsumerBridge") then
        errors[#errors + 1] = "research consumer invalidation consumer bridge missing"
    end
    if not JLP:GetModule("ResearchRouteAuthorityBridge") then
        errors[#errors + 1] = "research consumer invalidation route authority bridge missing"
    end
    return errors, warnings
end

JLP:RegisterModule("ResearchConsumerInvalidation", ResearchConsumerInvalidation)
