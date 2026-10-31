local _, JLP = ...

-- Alpha74 carries an alpha73 execution-intent through the real Crafting module
-- boundary in shadow mode. It never grants native dispatch authority.
local ResearchExecutionIntentHandoff = {
    contract = "controlled-execution-intent-handoff-v1",
    handoffContract = "research-execution-intent-handoff-v1",
    boundaryContract = "shadow-pre-dispatch-boundary-v1",
    authority = "dry-run-current-intent-handoff-only",
    executionEligible = false,
    dispatchAllowed = false,
    nativeDispatchAllowed = false,
    shadowOnly = true,
    persisted = false,
    lastByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function normalizeCraftMode(mode)
    return mode == "all" and "all" or "one"
end

local function monotonicNow()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

function ResearchExecutionIntentHandoff:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if not professionKey or type(report) ~= "table" then return report end
    self.lastByProfession[professionKey] = shallowCopy(report)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_SHADOW_PREDISPATCH_UPDATED", shallowCopy(report))
    end
    return report
end

function ResearchExecutionIntentHandoff:IsSupported(professionKey)
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    return readiness and readiness.IsSupported and readiness:IsSupported(normalizeKey(professionKey)) or false
end

function ResearchExecutionIntentHandoff:PrepareHandoff(professionKey, mode, craftMode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    craftMode = normalizeCraftMode(craftMode)
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    if not readiness or not readiness.PrepareIntent then
        local blocked = {
            contract = self.contract,
            handoffContract = self.handoffContract,
            boundaryContract = self.boundaryContract,
            professionKey = professionKey,
            mode = mode,
            craftMode = craftMode,
            state = "shadow-pre-dispatch-readiness-unavailable",
            shadowOnly = true,
            executionEligible = false,
            dispatchAllowed = false,
            nativeDispatchAllowed = false,
            nativeDispatchAttempted = false,
            persisted = false,
        }
        self:_Record(professionKey, blocked)
        return nil, blocked.state, blocked
    end

    local intent, intentState, model = readiness:PrepareIntent(professionKey, mode, options)
    if not intent then
        local blocked = {
            contract = self.contract,
            handoffContract = self.handoffContract,
            boundaryContract = self.boundaryContract,
            professionKey = professionKey,
            mode = mode,
            craftMode = craftMode,
            state = "shadow-pre-dispatch-readiness-blocked",
            readinessState = model and model.state or intentState,
            blockedGate = model and model.blockedGate or nil,
            blockedState = model and model.blockedState or nil,
            shadowOnly = true,
            executionEligible = false,
            dispatchAllowed = false,
            nativeDispatchAllowed = false,
            nativeDispatchAttempted = false,
            persisted = false,
        }
        self:_Record(professionKey, blocked)
        return nil, blocked.state, blocked
    end

    local handoff = {
        contract = self.handoffContract,
        boundaryContract = self.boundaryContract,
        professionKey = professionKey,
        mode = mode,
        craftMode = craftMode,
        intentToken = intent.token,
        snapshotToken = intent.snapshotToken,
        stateFingerprint = intent.stateFingerprint,
        currentBuild = intent.currentBuild,
        recipe = intent.recipe,
        recipeID = intent.recipeID,
        preparedAt = monotonicNow(),
        shadowOnly = true,
        singleUse = true,
        executionEligible = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        persisted = false,
    }
    return handoff, "execution-intent-handoff-prepared", model
end

function ResearchExecutionIntentHandoff:DispatchShadow(handoff, options)
    if type(handoff) ~= "table" or handoff.contract ~= self.handoffContract then
        local professionKey = normalizeKey(handoff and handoff.professionKey) or "ENGINEERING"
        local invalid = {
            contract = self.contract,
            handoffContract = self.handoffContract,
            boundaryContract = self.boundaryContract,
            professionKey = professionKey,
            state = "shadow-pre-dispatch-invalid-handoff",
            shadowOnly = true,
            executionEligible = false,
            dispatchAllowed = false,
            nativeDispatchAllowed = false,
            nativeDispatchAttempted = false,
            persisted = false,
        }
        self:_Record(professionKey, invalid)
        return false, invalid.state, invalid
    end
    local crafting = JLP:GetModule("Crafting")
    if not crafting or not crafting.ShadowResearchDispatchBoundary then
        local unavailable = shallowCopy(handoff)
        unavailable.contract = self.contract
        unavailable.handoffContract = self.handoffContract
        unavailable.state = "shadow-pre-dispatch-boundary-unavailable"
        unavailable.nativeDispatchAttempted = false
        self:_Record(handoff.professionKey, unavailable)
        return false, unavailable.state, unavailable
    end
    local ok, state, report = crafting:ShadowResearchDispatchBoundary(handoff, options)
    report = type(report) == "table" and report or shallowCopy(handoff)
    report.contract = self.contract
    report.handoffContract = self.handoffContract
    report.boundaryContract = self.boundaryContract
    report.state = state or report.state or (ok and "shadow-pre-dispatch-validated" or "shadow-pre-dispatch-blocked")
    report.shadowOnly = true
    report.executionEligible = false
    report.dispatchAllowed = false
    report.nativeDispatchAllowed = false
    report.nativeDispatchAttempted = false
    report.persisted = false
    self:_Record(handoff.professionKey, report)
    return ok and true or false, report.state, report
end

function ResearchExecutionIntentHandoff:Request(professionKey, mode, craftMode, options)
    local handoff, state, model = self:PrepareHandoff(professionKey, mode, craftMode, options)
    if not handoff then
        return false, state, self:GetLast(professionKey)
    end
    return self:DispatchShadow(handoff, options)
end

function ResearchExecutionIntentHandoff:GetLast(professionKey)
    professionKey = normalizeKey(professionKey)
    local report = professionKey and self.lastByProfession[professionKey] or nil
    return report and shallowCopy(report) or nil
end

function ResearchExecutionIntentHandoff:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    local evaluation = JLP:GetModule("ResearchExecutionReadiness")
    local readiness = evaluation and evaluation.Evaluate and evaluation:Evaluate(professionKey, mode, options) or nil
    local last = self:GetLast(professionKey)
    local lines = {
        "RESEARCH EXECUTION HANDOFF / SHADOW PRE-DISPATCH",
        professionKey .. " / " .. mode,
        "Readiness: " .. tostring(readiness and readiness.state or "unavailable"),
        "Last handoff: " .. tostring(last and last.state or "none"),
        "Boundary contract: " .. self.boundaryContract,
        "Intent transport: in-memory · single-use",
        "Shadow-only: yes",
        "Execution authority: disabled",
        "Native dispatch authority: disabled",
        "Native dispatch calls: forbidden",
        "Persistence: none",
    }
    if last then
        lines[#lines + 1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines + 1] = "Intent validation: " .. tostring(last.intentValidationState or "not-run")
        lines[#lines + 1] = "Boundary validated: " .. tostring(last.boundaryValidated == true and "yes" or "no")
        lines[#lines + 1] = "Single-use consumed: " .. tostring(last.singleUseConsumed == true and "yes" or "no")
        lines[#lines + 1] = "Would dispatch: " .. tostring(last.wouldDispatchCount or 0)
    end
    return table.concat(lines, "\n")
end

function ResearchExecutionIntentHandoff:Validate()
    local errors, warnings = {}, {}
    if self.executionEligible ~= false or self.dispatchAllowed ~= false or self.nativeDispatchAllowed ~= false or self.shadowOnly ~= true or self.persisted ~= false then
        errors[#errors + 1] = "research execution-intent handoff authority boundary invalid"
    end
    for _, name in ipairs({"ResearchExecutionReadiness", "Crafting"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "research execution-intent handoff dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchExecutionIntentHandoff", ResearchExecutionIntentHandoff)
