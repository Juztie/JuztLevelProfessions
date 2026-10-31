local _, JLP = ...

-- Alpha100 introduced the production Tailoring native Craft One boundary. Alpha103
-- allows the target-aware Auto Route orchestrator to delegate one ordinal at a time
-- through that exact same boundary. The module never accepts batch native counts: each
-- reservation still authorizes exactly one CraftRecipe(recipeID, 1). Craft All remains
-- owned by its separate alpha101 authority.
local ProductionTailoringNativeExecutionAuthority = {
    contract = "production-tailoring-native-single-craft-authority-v1",
    boundaryContract = "production-tailoring-native-single-craft-boundary-v1",
    provenanceContract = "production-tailoring-native-dispatch-provenance-v1",
    authority = "feature-gated-explicit-guide-click-production-tailoring-craft-one-v1",
    professionKey = "TAILORING",
    maxCraftCount = 1,
    persistedAuthorization = false,
    automaticExecutionAllowed = false,
    craftAllAllowed = false,
    autoRouteAllowed = true,
    lastByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function featureProfile()
    local profile = JLP.DB and JLP.DB.profile
    return profile and profile.productionTailoringNativeExecutionAuthority or nil
end

local function featureEnabled()
    local profile = featureProfile()
    return profile and profile.enabled == true or false
end

local function addGate(model, key, ready, state, detail)
    local row = {
        key = key,
        ready = ready and true or false,
        state = tostring(state or (ready and "pass" or "blocked")),
        detail = detail,
    }
    model.gates[key] = row
    model.stats.totalGates = model.stats.totalGates + 1
    if row.ready then
        model.stats.passedGates = model.stats.passedGates + 1
    elseif not model.blockedGate then
        model.blockedGate = key
        model.blockedState = row.state
    end
    return row
end

function ProductionTailoringNativeExecutionAuthority:IsFeatureEnabled()
    return featureEnabled()
end

function ProductionTailoringNativeExecutionAuthority:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    if professionKey ~= self.professionKey then return false end
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    return readiness and readiness.IsSupported and readiness:IsSupported(professionKey) or false
end

function ProductionTailoringNativeExecutionAuthority:IsEffectiveEnabled()
    if not featureEnabled() then return false end
    local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
    if not (adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) then return false end
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    return eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled() or false
end

function ProductionTailoringNativeExecutionAuthority:SetFeatureEnabled(enabled)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    if enabled == true then
        local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
        if not (adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) then
            return false, "production-tailoring-authority-gate-disabled"
        end
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
    end
    profile.enabled = enabled == true
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if eligibility and eligibility.InvalidateProfession then
        eligibility:InvalidateProfession(self.professionKey, "production-tailoring-native-feature-gate-changed")
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_TAILORING_NATIVE_EXECUTION_AUTHORITY_UPDATED", { enabled=profile.enabled })
        JLP.EventBus:Emit("SETTINGS_CHANGED", "productionTailoringNativeExecutionAuthority", profile.enabled)
    end
    return true, profile.enabled and "enabled" or "disabled"
end

function ProductionTailoringNativeExecutionAuthority:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if professionKey and type(report) == "table" then self.lastByProfession[professionKey] = shallowCopy(report) end
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("PRODUCTION_TAILORING_NATIVE_EXECUTION_UPDATED", shallowCopy(report))
    end
    return report
end

function ProductionTailoringNativeExecutionAuthority:EvaluateReservation(reservation, options)
    local professionKey = normalizeKey(type(reservation) == "table" and reservation.professionKey or nil) or self.professionKey
    local mode = normalizeMode(type(reservation) == "table" and reservation.mode or nil)
    local model = {
        contract = self.contract,
        boundaryContract = self.boundaryContract,
        provenanceContract = self.provenanceContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        state = "production-tailoring-native-single-craft-authority-blocked",
        nativeExecutionAuthorityReady = false,
        executionEligible = false,
        executionAuthorityEnabled = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        nativeDispatchAttempted = false,
        persistedAuthorization = false,
        gates = {},
        stats = { passedGates=0, totalGates=0 },
    }

    local nativeGate = featureEnabled()
    addGate(model, "native-feature-gate", nativeGate,
        nativeGate and "production-tailoring-native-feature-gate-enabled" or "production-tailoring-native-feature-gate-disabled",
        "separate default-off production Tailoring native Craft One gate")

    local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
    local productionAuthorityEnabled = adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled() or false
    addGate(model, "production-authority-gate", productionAuthorityEnabled,
        productionAuthorityEnabled and "production-tailoring-authority-enabled" or "production-tailoring-authority-disabled",
        "alpha98 production Tailoring consumer authority must remain enabled")

    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local eligibilityEnabled = eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled() or false
    addGate(model, "eligibility-feature-gate", eligibilityEnabled,
        eligibilityEnabled and "execution-authority-eligibility-gate-enabled" or "execution-authority-eligibility-gate-disabled",
        "shared single-use execution eligibility gate must remain enabled")

    local supported = self:IsSupported(professionKey)
    addGate(model, "supported-profession", supported,
        supported and "production-tailoring-native-profession-supported" or "production-tailoring-native-profession-unsupported",
        "Tailoring only")

    local shapeReady = type(reservation) == "table"
        and reservation.contract == "research-native-dispatch-reservation-v1"
        and reservation.boundaryContract == "guarded-native-dispatch-boundary-v1"
        and reservation.candidateEligible == true
        and reservation.executionEligible == false
        and reservation.executionAuthorityEnabled == false
        and reservation.dispatchAllowed == false
        and reservation.nativeDispatchAllowed == false
        and reservation.persisted == false
        and tostring(reservation.craftMode or "") == "one"
        and tonumber(reservation.requestedCount) == 1
    addGate(model, "single-craft-reservation", shapeReady,
        shapeReady and "production-tailoring-single-craft-reservation-valid" or "production-tailoring-single-craft-reservation-invalid",
        "exactly one candidate craft from the shared single-use reservation layer")

    local nativeAPI = type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.CraftRecipe) == "function"
    addGate(model, "native-craft-api", nativeAPI,
        nativeAPI and "native-craft-api-available" or "native-craft-api-unavailable",
        "C_TradeSkillUI.CraftRecipe must be present")

    local crafting = JLP:GetModule("Crafting")
    local transactionClear = crafting ~= nil and crafting.pendingCraft == nil and crafting.pendingEnchant == nil and crafting.activeRepeat == nil
    local recovery = JLP:GetModule("TransactionRecovery")
    local recoveryState = "transaction-recovery-clear"
    if transactionClear and recovery and recovery.CanStart then
        local allowed, message = recovery:CanStart("craft", professionKey)
        transactionClear = allowed and true or false
        if not transactionClear then recoveryState = tostring(message or "transaction-recovery-blocked") end
    end
    addGate(model, "transaction-clear", transactionClear,
        transactionClear and "transaction-boundary-clear" or recoveryState,
        "no craft/enchant/repeat or unresolved recovery may be active")

    local ledger = JLP:GetModule("TransactionLedger")
    local durableBoundary = ledger and type(ledger.Begin) == "function" and recovery and type(recovery.CapturePending) == "function"
    addGate(model, "durable-transaction-boundary", durableBoundary,
        durableBoundary and "ledger-and-recovery-boundary-available" or "ledger-or-recovery-boundary-unavailable",
        "ledger and reload-recovery checkpoint must be available before native dispatch")

    local reservationCurrent, reservationState, current, stored = false, "execution-reservation-unvalidated", nil, nil
    if nativeGate and productionAuthorityEnabled and eligibilityEnabled and supported and shapeReady and nativeAPI and transactionClear and durableBoundary
        and eligibility and eligibility.ValidateReservation then
        reservationCurrent, reservationState, current, stored = eligibility:ValidateReservation(reservation, professionKey, mode, options)
    end
    model.reservationValidationState = reservationState
    addGate(model, "reservation-current", reservationCurrent,
        reservationCurrent and "production-tailoring-execution-reservation-current" or tostring(reservationState or "execution-reservation-unavailable"),
        "single-use reservation must still match current snapshot/fingerprint/recipe/craftability")

    local policy = JLP:GetModule("ProductionTailoringExecutionReadiness")
    local sourceReady = reservationCurrent
        and current ~= nil
        and policy ~= nil
        and tostring(current.sourceReadinessPolicyContract or "") == tostring(policy.contract or "")
        and tostring(current.sourceReadinessProofContract or "") == tostring(policy.proofContract or "")
        and type(current.sourceReadinessFingerprint) == "string" and current.sourceReadinessFingerprint ~= ""
        and type(current.sourceReadiness) == "table" and current.sourceReadiness.ready == true
        and current.sourceReadiness.recipeIdentityReady == true
        and tonumber(current.recipeID) == tonumber(current.sourceReadiness.recipeID)
    addGate(model, "production-readiness-proof", sourceReady,
        sourceReady and "production-tailoring-readiness-proof-current" or "production-tailoring-readiness-proof-invalid",
        "alpha99 live Tailoring readiness proof must still bind the exact consumer recipe")

    local boundaryPresent = crafting and type(crafting.NativeTailoringSingleCraftBoundary) == "function"
    addGate(model, "native-boundary", boundaryPresent,
        boundaryPresent and "production-tailoring-native-boundary-present" or "production-tailoring-native-boundary-missing",
        "all irreversible Tailoring dispatch must cross the dedicated Crafting boundary")

    model.stats.blockedGates = model.stats.totalGates - model.stats.passedGates
    model.recipe = current and current.recipe or (stored and stored.recipe) or (reservation and reservation.recipe)
    model.recipeID = tonumber(current and current.recipeID) or tonumber(stored and stored.recipeID) or tonumber(reservation and reservation.recipeID)
    model.snapshotToken = current and current.snapshotToken or (stored and stored.snapshotToken)
    model.stateFingerprint = current and current.stateFingerprint or (stored and stored.stateFingerprint)
    model.sourceReadinessPolicyContract = current and current.sourceReadinessPolicyContract or (stored and stored.sourceReadinessPolicyContract)
    model.sourceReadinessProofContract = current and current.sourceReadinessProofContract or (stored and stored.sourceReadinessProofContract)
    model.sourceReadinessFingerprint = current and current.sourceReadinessFingerprint or (stored and stored.sourceReadinessFingerprint)
    model.reservationToken = stored and stored.token or (reservation and reservation.token)
    model.currentBuild = current and current.currentBuild or (stored and stored.currentBuild)
    model.craftabilityStatus = current and current.craftabilityStatus or "UNKNOWN"
    model.craftabilityReason = current and current.craftabilityReason or "live-readiness-unavailable"
    -- Historic reservations are reference evidence, never current craftability.
    model.nativeCraftable = model.craftabilityStatus == "KNOWN"
        and tonumber(current and current.nativeCraftable) or nil
    model.priorReservationCraftable = tonumber(stored and stored.nativeCraftable)

    if model.stats.totalGates == 11 and model.stats.passedGates == 11 then
        model.state = "production-tailoring-native-single-craft-authority-ready"
        model.nativeExecutionAuthorityReady = true
        model.executionEligible = true
        model.executionAuthorityEnabled = true
        model.dispatchAllowed = true
        model.nativeDispatchAllowed = true
    end

    return model, current, stored
end

function ProductionTailoringNativeExecutionAuthority:Request(professionKey, mode, clickOrigin, options)
    professionKey = normalizeKey(professionKey) or self.professionKey
    mode = normalizeMode(mode)
    if professionKey ~= self.professionKey then
        local report = self:_Record(professionKey, {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=professionKey,mode=mode,
            state="production-tailoring-native-profession-unsupported",nativeExecutionAuthorityReady=false,
            executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            nativeDispatchAttempted=false,persistedAuthorization=false,
        })
        return false, report.state, report
    end
    if not featureEnabled() then
        local report = self:_Record(professionKey, {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=professionKey,mode=mode,
            state="production-tailoring-native-feature-gate-disabled",nativeExecutionAuthorityReady=false,
            executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            nativeDispatchAttempted=false,persistedAuthorization=false,
        })
        return false, report.state, report
    end

    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if not eligibility or not eligibility.PrepareReservation then
        local report = self:_Record(professionKey, {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=professionKey,mode=mode,
            state="execution-authority-eligibility-gate-unavailable",nativeExecutionAuthorityReady=false,
            executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            nativeDispatchAttempted=false,persistedAuthorization=false,
        })
        return false, report.state, report
    end

    local reservation, state, eligibilityModel = eligibility:PrepareReservation(professionKey, mode, "one", clickOrigin, options)
    if not reservation then
        local report = type(eligibilityModel) == "table" and shallowCopy(eligibilityModel) or {}
        report.contract = self.contract
        report.boundaryContract = self.boundaryContract
        report.professionKey = professionKey
        report.mode = mode
        report.state = state or "execution-authority-reservation-unavailable"
        report.nativeExecutionAuthorityReady = false
        report.executionEligible = false
        report.executionAuthorityEnabled = false
        report.dispatchAllowed = false
        report.nativeDispatchAllowed = false
        report.nativeDispatchAttempted = false
        report.persistedAuthorization = false
        self:_Record(professionKey, report)
        return false, report.state, report
    end

    local model = self:EvaluateReservation(reservation, options)
    if not model.nativeExecutionAuthorityReady then
        if eligibility.RevokeReservation then eligibility:RevokeReservation(reservation.token, "production-tailoring-native-authority-evaluation-blocked") end
        self:_Record(professionKey, model)
        return false, model.state, model
    end

    local crafting = JLP:GetModule("Crafting")
    local ok, boundaryState, report = crafting:NativeTailoringSingleCraftBoundary(reservation, options)
    report = type(report) == "table" and report or model
    report.contract = self.contract
    report.boundaryContract = self.boundaryContract
    report.provenanceContract = self.provenanceContract
    report.state = boundaryState or report.state or (ok and "production-tailoring-native-single-craft-dispatched" or "production-tailoring-native-single-craft-blocked")
    self:_Record(professionKey, report)
    return ok and true or false, report.state, report
end

function ProductionTailoringNativeExecutionAuthority:ObserveCraftAction(action)
    local provenance = type(action) == "table" and action.authorityProvenance or nil
    if type(provenance) ~= "table" or provenance.contract ~= self.provenanceContract then return false end
    local professionKey = normalizeKey(action.key or provenance.professionKey)
    if professionKey ~= self.professionKey then return false end
    local status = tostring(action.status or "unknown")
    local state
    if status == "success" then state = "production-tailoring-native-single-craft-confirmed"
    elseif status == "failed" or status == "timeout" then state = "production-tailoring-native-single-craft-failed"
    else state = "production-tailoring-native-single-craft-in-flight" end
    self:_Record(professionKey, {
        contract=self.contract,
        boundaryContract=self.boundaryContract,
        provenanceContract=self.provenanceContract,
        professionKey=professionKey,
        mode=action.mode or "one",
        state=state,
        transactionStatus=status,
        recipe=action.recipeName,
        recipeID=tonumber(action.recipeID),
        reservationToken=provenance.reservationToken,
        clickOriginToken=provenance.clickOriginToken,
        snapshotToken=provenance.snapshotToken,
        stateFingerprint=provenance.stateFingerprint,
        sourceReadinessPolicyContract=provenance.sourceReadinessPolicyContract,
        sourceReadinessProofContract=provenance.sourceReadinessProofContract,
        sourceReadinessFingerprint=provenance.sourceReadinessFingerprint,
        currentBuild=provenance.currentBuild,
        ledgerID=action.ledgerID or action.transactionID,
        requestedCount=tonumber(action.requestedCount) or 1,
        completedCount=tonumber(action.completedCount) or 0,
        nativeDispatchAttempted=true,
        nativeDispatchAllowed=true,
        executionEligible=true,
        executionAuthorityEnabled=true,
        dispatchAllowed=true,
        persistedAuthorization=false,
    })
    return true
end

function ProductionTailoringNativeExecutionAuthority:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        local function autoDemote(reason)
            if not featureEnabled() then return end
            local profile = featureProfile()
            if profile then profile.enabled = false end
            local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
            if eligibility and eligibility.InvalidateProfession then eligibility:InvalidateProfession(self.professionKey, reason) end
            self:_Record(self.professionKey, {
                contract=self.contract,boundaryContract=self.boundaryContract,provenanceContract=self.provenanceContract,
                professionKey=self.professionKey,state="production-tailoring-native-auto-demoted",reason=reason,
                nativeExecutionAuthorityReady=false,executionEligible=false,executionAuthorityEnabled=false,
                dispatchAllowed=false,nativeDispatchAllowed=false,nativeDispatchAttempted=false,persistedAuthorization=false,
            })
        end
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload)=="table" and payload.enabled==false then autoDemote("execution-authority-eligibility-disabled") end
        end)
        JLP.EventBus:On("PRODUCTION_TAILORING_AUTHORITY_UPDATED", function(payload)
            if type(payload)=="table" and payload.enabled==false then autoDemote("production-tailoring-authority-disabled") end
        end)
    end
    return true
end

function ProductionTailoringNativeExecutionAuthority:GetLast(professionKey)
    professionKey = normalizeKey(professionKey) or self.professionKey
    local row = self.lastByProfession[professionKey]
    return row and shallowCopy(row) or nil
end

function ProductionTailoringNativeExecutionAuthority:GetSummary()
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
    local last = self:GetLast(self.professionKey)
    local lines = {
        "PRODUCTION TAILORING / GUARDED NATIVE CRAFT ONE",
        "TAILORING / normal",
        "Contract: " .. self.contract,
        "Native feature gate: " .. (featureEnabled() and "enabled" or "disabled"),
        "Production Tailoring authority: " .. ((adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) and "enabled" or "disabled"),
        "Execution eligibility gate: " .. ((eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) and "enabled" or "disabled"),
        "Scope: one explicit Guide click -> exactly one CraftRecipe(recipeID, 1)",
        "Craft All: separate alpha101 production Tailoring authority",
        "Auto Route: allowed only as alpha103 single-craft ordinal delegation",
        "Authorization persistence: none",
        "Native execution authority: " .. (self:IsEffectiveEnabled() and "armed (fresh reservation still required)" or "disabled"),
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines + 1] = "Native dispatch attempted: " .. tostring(last.nativeDispatchAttempted == true and "yes" or "no")
        lines[#lines + 1] = "Ledger: " .. tostring(last.ledgerID or "none")
        lines[#lines + 1] = "Reservation: " .. tostring(last.reservationToken or "none")
        if last.blockedGate then lines[#lines + 1] = "Blocked gate: " .. tostring(last.blockedGate) .. " · " .. tostring(last.blockedState or "blocked") end
    end
    return table.concat(lines, "\n")
end

function ProductionTailoringNativeExecutionAuthority:Validate()
    local errors, warnings = {}, {}
    if self.maxCraftCount ~= 1 then errors[#errors + 1] = "production Tailoring native max craft count must remain one" end
    if self.persistedAuthorization ~= false then errors[#errors + 1] = "production Tailoring native authorization must not persist" end
    if self.automaticExecutionAllowed ~= false or self.craftAllAllowed ~= false or self.autoRouteAllowed ~= true then
        errors[#errors + 1] = "alpha103 production Tailoring native scope must remain Craft One plus single-ordinal Auto Route delegation only"
    end
    for _, name in ipairs({"ProductionTailoringAuthorityAdapter","ProductionTailoringExecutionReadiness","ResearchExecutionAuthorityGate","ResearchExecutionReadiness","TransactionLedger","TransactionRecovery","Crafting"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "production Tailoring native dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringNativeExecutionAuthority", ProductionTailoringNativeExecutionAuthority)
