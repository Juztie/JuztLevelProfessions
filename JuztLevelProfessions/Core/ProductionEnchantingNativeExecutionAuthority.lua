local _, JLP = ...

-- Alpha111 is the first production Enchanting layer allowed to cross the native
-- CraftEnchant boundary. The authority is deliberately narrower than direct
-- Enchanting: one explicit Profession Guide click, one target-bound reservation,
-- one freshly revalidated Optional Target and exactly one CraftEnchant call.
-- Protected replace/bind confirmation remains a Blizzard secure-click boundary.
local ProductionEnchantingNativeExecutionAuthority = {
    contract = "production-enchanting-native-single-enchant-authority-v1",
    boundaryContract = "production-enchanting-native-single-enchant-boundary-v1",
    provenanceContract = "production-enchanting-native-dispatch-provenance-v1",
    confirmationContract = "production-enchanting-protected-confirmation-boundary-v1",
    authority = "feature-gated-explicit-guide-click-target-bound-enchant-one-v1",
    professionKey = "ENCHANTING",
    maxEnchantCount = 1,
    persistedAuthorization = false,
    automaticExecutionAllowed = false,
    craftAllAllowed = false,
    autoRouteAllowed = false,
    confirmationAutomationAllowed = false,
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
    return profile and profile.productionEnchantingNativeExecutionAuthority or nil
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

function ProductionEnchantingNativeExecutionAuthority:IsFeatureEnabled()
    return featureEnabled()
end

function ProductionEnchantingNativeExecutionAuthority:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    if professionKey ~= self.professionKey then return false end
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    return readiness and readiness.IsSupported and readiness:IsSupported(professionKey) or false
end

function ProductionEnchantingNativeExecutionAuthority:IsEffectiveEnabled()
    if not featureEnabled() then return false end
    local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
    if not (adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) then return false end
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    return eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled() or false
end

function ProductionEnchantingNativeExecutionAuthority:SetFeatureEnabled(enabled)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    if enabled == true then
        local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
        if not (adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) then
            return false, "production-enchanting-authority-gate-disabled"
        end
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
    end
    profile.enabled = enabled == true
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if eligibility and eligibility.InvalidateProfession then
        eligibility:InvalidateProfession(self.professionKey, "production-enchanting-native-feature-gate-changed")
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_NATIVE_EXECUTION_AUTHORITY_UPDATED", { enabled=profile.enabled })
        JLP.EventBus:Emit("SETTINGS_CHANGED", "productionEnchantingNativeExecutionAuthority", profile.enabled)
    end
    return true, profile.enabled and "enabled" or "disabled"
end

function ProductionEnchantingNativeExecutionAuthority:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if professionKey and type(report) == "table" then self.lastByProfession[professionKey] = shallowCopy(report) end
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_NATIVE_EXECUTION_UPDATED", shallowCopy(report))
    end
    return report
end

function ProductionEnchantingNativeExecutionAuthority:EvaluateReservation(reservation, options)
    local professionKey = normalizeKey(type(reservation) == "table" and reservation.professionKey or nil) or self.professionKey
    local mode = normalizeMode(type(reservation) == "table" and reservation.mode or nil)
    local model = {
        contract = self.contract,
        boundaryContract = self.boundaryContract,
        provenanceContract = self.provenanceContract,
        confirmationContract = self.confirmationContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        state = "production-enchanting-native-single-enchant-authority-blocked",
        nativeExecutionAuthorityReady = false,
        executionEligible = false,
        executionAuthorityEnabled = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        nativeDispatchAttempted = false,
        confirmationAutomationAllowed = false,
        persistedAuthorization = false,
        gates = {},
        stats = { passedGates=0, totalGates=0 },
    }

    local nativeGate = featureEnabled()
    addGate(model, "native-feature-gate", nativeGate,
        nativeGate and "production-enchanting-native-feature-gate-enabled" or "production-enchanting-native-feature-gate-disabled",
        "separate default-off production Enchanting native Enchant One gate")

    local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
    local productionAuthorityEnabled = adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled() or false
    addGate(model, "production-authority-gate", productionAuthorityEnabled,
        productionAuthorityEnabled and "production-enchanting-authority-enabled" or "production-enchanting-authority-disabled",
        "target-bound production Enchanting consumer authority must remain enabled")

    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local eligibilityEnabled = eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled() or false
    addGate(model, "eligibility-feature-gate", eligibilityEnabled,
        eligibilityEnabled and "execution-authority-eligibility-gate-enabled" or "execution-authority-eligibility-gate-disabled",
        "shared single-use execution eligibility gate must remain enabled")

    local supported = self:IsSupported(professionKey)
    addGate(model, "supported-profession", supported,
        supported and "production-enchanting-native-profession-supported" or "production-enchanting-native-profession-unsupported",
        "Enchanting only")

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
        and tostring(reservation.targetGUID or "") ~= ""
        and tonumber(reservation.targetItemID) ~= nil
        and tostring(reservation.targetLocationKey or "") ~= ""
        and tostring(reservation.targetValidationSource or "") ~= ""
        and tostring(reservation.targetProofContract or "") ~= ""
        and tostring(reservation.targetProofFingerprint or "") ~= ""
    addGate(model, "single-enchant-reservation", shapeReady,
        shapeReady and "production-enchanting-single-enchant-reservation-valid" or "production-enchanting-single-enchant-reservation-invalid",
        "exactly one target-bound candidate enchant from the shared single-use reservation layer")

    local nativeAPI = type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.CraftEnchant) == "function"
    addGate(model, "native-enchant-api", nativeAPI,
        nativeAPI and "native-enchant-api-available" or "native-enchant-api-unavailable",
        "C_TradeSkillUI.CraftEnchant must be present")

    local crafting = JLP:GetModule("Crafting")
    local transactionClear = crafting ~= nil and crafting.pendingCraft == nil and crafting.pendingEnchant == nil and crafting.activeRepeat == nil
    local recovery = JLP:GetModule("TransactionRecovery")
    local recoveryState = "transaction-recovery-clear"
    if transactionClear and recovery and recovery.CanStart then
        local allowed, message = recovery:CanStart("enchant", professionKey)
        transactionClear = allowed and true or false
        if not transactionClear then recoveryState = tostring(message or "transaction-recovery-blocked") end
    end
    addGate(model, "transaction-clear", transactionClear,
        transactionClear and "transaction-boundary-clear" or recoveryState,
        "no craft/enchant/repeat or unresolved enchant recovery may be active")

    local ledger = JLP:GetModule("TransactionLedger")
    local durableBoundary = ledger and type(ledger.Begin) == "function" and recovery and type(recovery.CapturePending) == "function"
    addGate(model, "durable-transaction-boundary", durableBoundary,
        durableBoundary and "ledger-and-recovery-boundary-available" or "ledger-or-recovery-boundary-unavailable",
        "ledger and reload-recovery checkpoint must exist before CraftEnchant")

    local settlement = JLP:GetModule("ProductionEnchantingNativeSettlement")
    local settlementReady = settlement
        and type(settlement.ObserveConfirmation) == "function"
        and type(settlement.HandleProvisionalFailure) == "function"
        and type(settlement.ConfirmFromCraftResult) == "function"
        and type(settlement.ConfirmFromSpellcastSuccess) == "function"
        and type(settlement.HandleTimeout) == "function"
    addGate(model, "settlement-orchestrator", settlementReady,
        settlementReady and "production-enchanting-native-settlement-ready" or "production-enchanting-native-settlement-unavailable",
        "alpha112 settlement/confirmation endurance layer must exist before irreversible dispatch")

    local routeCoverage = JLP:GetModule("ProductionEnchantingNativeRouteCoverage")
    local routeCoverageModel = routeCoverage and routeCoverage.Audit and routeCoverage:Audit() or nil
    local routeCoverageReady = routeCoverageModel ~= nil and routeCoverageModel.routeReady == true
    model.routeCoverage = routeCoverageModel
    addGate(model, "all-route-coverage", routeCoverageReady,
        routeCoverageReady and "production-enchanting-native-all-route-coverage-ready" or "production-enchanting-native-all-route-coverage-blocked",
        "alpha113 all eight production Enchanting route identities must remain bound to the target-aware Enchant One contracts")

    local reservationCurrent, reservationState, current, stored = false, "execution-reservation-unvalidated", nil, nil
    if nativeGate and productionAuthorityEnabled and eligibilityEnabled and supported and shapeReady and nativeAPI and transactionClear and durableBoundary and settlementReady and routeCoverageReady
        and eligibility and eligibility.ValidateReservation then
        reservationCurrent, reservationState, current, stored = eligibility:ValidateReservation(reservation, professionKey, mode, options)
    end
    model.reservationValidationState = reservationState
    addGate(model, "reservation-current", reservationCurrent,
        reservationCurrent and "production-enchanting-execution-reservation-current" or tostring(reservationState or "execution-reservation-unavailable"),
        "single-use reservation must still match current target-bound readiness")

    local policy = JLP:GetModule("ProductionEnchantingExecutionReadiness")
    local sourceReady = reservationCurrent
        and current ~= nil
        and policy ~= nil
        and tostring(current.sourceReadinessPolicyContract or "") == tostring(policy.contract or "")
        and tostring(current.sourceReadinessProofContract or "") == tostring(policy.proofContract or "")
        and type(current.sourceReadinessFingerprint) == "string" and current.sourceReadinessFingerprint ~= ""
        and type(current.sourceReadiness) == "table" and current.sourceReadiness.ready == true
        and current.sourceReadiness.recipeIdentityReady == true
        and current.sourceReadiness.targetIdentityReady == true
        and tonumber(current.recipeID) == tonumber(current.sourceReadiness.recipeID)
    addGate(model, "production-readiness-proof", sourceReady,
        sourceReady and "production-enchanting-readiness-proof-current" or "production-enchanting-readiness-proof-invalid",
        "alpha110 live target-aware readiness proof must still bind recipe and Optional Target")

    local targetBound = sourceReady and stored ~= nil
        and tostring(stored.targetGUID or "") == tostring(current.targetGUID or "")
        and tonumber(stored.targetItemID) == tonumber(current.targetItemID)
        and tostring(stored.targetLocationKey or "") == tostring(current.targetLocationKey or "")
        and tostring(stored.targetValidationSource or "") == tostring(current.targetValidationSource or "")
        and tostring(stored.targetProofContract or "") == tostring(current.targetProofContract or "")
        and tostring(stored.targetProofFingerprint or "") == tostring(current.targetProofFingerprint or "")
    addGate(model, "target-bound-reservation", targetBound,
        targetBound and "production-enchanting-target-bound-reservation-current" or "production-enchanting-target-bound-reservation-stale",
        "reservation must bind exact GUID, itemID, live ItemLocation and target proof")

    local boundaryPresent = crafting and type(crafting.NativeEnchantingSingleCraftBoundary) == "function"
    addGate(model, "native-boundary", boundaryPresent,
        boundaryPresent and "production-enchanting-native-boundary-present" or "production-enchanting-native-boundary-missing",
        "all irreversible Enchanting dispatch must cross the dedicated target-aware Crafting boundary")

    model.stats.blockedGates = model.stats.totalGates - model.stats.passedGates
    model.recipe = current and current.recipe or (stored and stored.recipe) or (reservation and reservation.recipe)
    model.recipeID = tonumber(current and current.recipeID) or tonumber(stored and stored.recipeID) or tonumber(reservation and reservation.recipeID)
    model.targetGUID = current and current.targetGUID or (stored and stored.targetGUID) or (reservation and reservation.targetGUID)
    model.targetItemID = tonumber(current and current.targetItemID) or tonumber(stored and stored.targetItemID) or tonumber(reservation and reservation.targetItemID)
    model.targetLocationKey = current and current.targetLocationKey or (stored and stored.targetLocationKey) or (reservation and reservation.targetLocationKey)
    model.targetValidationSource = current and current.targetValidationSource or (stored and stored.targetValidationSource) or (reservation and reservation.targetValidationSource)
    model.targetProofContract = current and current.targetProofContract or (stored and stored.targetProofContract) or (reservation and reservation.targetProofContract)
    model.targetProofFingerprint = current and current.targetProofFingerprint or (stored and stored.targetProofFingerprint) or (reservation and reservation.targetProofFingerprint)
    model.snapshotToken = current and current.snapshotToken or (stored and stored.snapshotToken)
    model.stateFingerprint = current and current.stateFingerprint or (stored and stored.stateFingerprint)
    model.sourceReadinessPolicyContract = current and current.sourceReadinessPolicyContract or (stored and stored.sourceReadinessPolicyContract)
    model.sourceReadinessProofContract = current and current.sourceReadinessProofContract or (stored and stored.sourceReadinessProofContract)
    model.sourceReadinessFingerprint = current and current.sourceReadinessFingerprint or (stored and stored.sourceReadinessFingerprint)
    model.reservationToken = stored and stored.token or (reservation and reservation.token)
    model.currentBuild = current and current.currentBuild or (stored and stored.currentBuild)

    if model.stats.totalGates == 14 and model.stats.passedGates == 14 then
        model.state = "production-enchanting-native-single-enchant-authority-ready"
        model.nativeExecutionAuthorityReady = true
        model.executionEligible = true
        model.executionAuthorityEnabled = true
        model.dispatchAllowed = true
        model.nativeDispatchAllowed = true
    end

    return model, current, stored
end

function ProductionEnchantingNativeExecutionAuthority:Request(professionKey, mode, clickOrigin, options)
    professionKey = normalizeKey(professionKey) or self.professionKey
    mode = normalizeMode(mode)
    if professionKey ~= self.professionKey then
        local report = self:_Record(professionKey, {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=professionKey,mode=mode,
            state="production-enchanting-native-profession-unsupported",nativeExecutionAuthorityReady=false,
            executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            nativeDispatchAttempted=false,confirmationAutomationAllowed=false,persistedAuthorization=false,
        })
        return false, report.state, report
    end
    if not featureEnabled() then
        local report = self:_Record(professionKey, {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=professionKey,mode=mode,
            state="production-enchanting-native-feature-gate-disabled",nativeExecutionAuthorityReady=false,
            executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            nativeDispatchAttempted=false,confirmationAutomationAllowed=false,persistedAuthorization=false,
        })
        return false, report.state, report
    end

    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if not eligibility or not eligibility.PrepareReservation then
        local report = self:_Record(professionKey, {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=professionKey,mode=mode,
            state="execution-authority-eligibility-gate-unavailable",nativeExecutionAuthorityReady=false,
            executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            nativeDispatchAttempted=false,confirmationAutomationAllowed=false,persistedAuthorization=false,
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
        report.confirmationAutomationAllowed = false
        report.persistedAuthorization = false
        self:_Record(professionKey, report)
        return false, report.state, report
    end

    local model = self:EvaluateReservation(reservation, options)
    if not model.nativeExecutionAuthorityReady then
        if eligibility.RevokeReservation then eligibility:RevokeReservation(reservation.token, "production-enchanting-native-authority-evaluation-blocked") end
        self:_Record(professionKey, model)
        return false, model.state, model
    end

    local crafting = JLP:GetModule("Crafting")
    local ok, boundaryState, report = crafting:NativeEnchantingSingleCraftBoundary(reservation, options)
    report = type(report) == "table" and report or model
    report.contract = self.contract
    report.boundaryContract = self.boundaryContract
    report.provenanceContract = self.provenanceContract
    report.confirmationContract = self.confirmationContract
    report.confirmationAutomationAllowed = false
    report.state = boundaryState or report.state or (ok and "production-enchanting-native-single-enchant-dispatched" or "production-enchanting-native-single-enchant-blocked")
    self:_Record(professionKey, report)
    return ok and true or false, report.state, report
end

function ProductionEnchantingNativeExecutionAuthority:ObserveEnchantAction(action)
    local provenance = type(action) == "table" and action.authorityProvenance or nil
    if type(provenance) ~= "table" or provenance.contract ~= self.provenanceContract then return false end
    local professionKey = normalizeKey(action.key or provenance.professionKey)
    if professionKey ~= self.professionKey then return false end
    local status = tostring(action.status or "unknown")
    local state
    if status == "success" then state = "production-enchanting-native-single-enchant-confirmed"
    elseif status == "confirmation-required" then state = "production-enchanting-native-protected-confirmation-required"
    elseif status == "failed" or status == "timeout" then state = "production-enchanting-native-single-enchant-failed"
    else state = "production-enchanting-native-single-enchant-in-flight" end
    self:_Record(professionKey, {
        contract=self.contract,
        boundaryContract=self.boundaryContract,
        provenanceContract=self.provenanceContract,
        confirmationContract=self.confirmationContract,
        professionKey=professionKey,
        mode=action.mode or "one",
        state=state,
        transactionStatus=status,
        recipe=action.recipeName,
        recipeID=tonumber(action.recipeID),
        targetGUID=action.targetGUID or provenance.targetGUID,
        targetItemID=tonumber(action.targetItemID) or tonumber(provenance.targetItemID),
        targetLocationKey=action.targetLocationKey or provenance.targetLocationKey,
        targetProofFingerprint=provenance.targetProofFingerprint,
        confirmationRequired=action.confirmationRequired==true,
        confirmationEvent=action.confirmationEvent,
        confirmationReason=action.confirmationReason,
        confirmationAutomationAllowed=false,
        reservationToken=provenance.reservationToken,
        clickOriginToken=provenance.clickOriginToken,
        snapshotToken=provenance.snapshotToken,
        stateFingerprint=provenance.stateFingerprint,
        sourceReadinessPolicyContract=provenance.sourceReadinessPolicyContract,
        sourceReadinessProofContract=provenance.sourceReadinessProofContract,
        sourceReadinessFingerprint=provenance.sourceReadinessFingerprint,
        currentBuild=provenance.currentBuild,
        ledgerID=action.ledgerID or action.transactionID,
        requestedCount=1,
        nativeDispatchAttempted=true,
        nativeDispatchAllowed=true,
        executionEligible=true,
        executionAuthorityEnabled=true,
        dispatchAllowed=true,
        persistedAuthorization=false,
    })
    return true
end

function ProductionEnchantingNativeExecutionAuthority:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("ENCHANT_ACTION_UPDATED", function(action) self:ObserveEnchantAction(action) end)
        local function autoDemote(reason)
            if not featureEnabled() then return end
            local profile = featureProfile()
            if profile then profile.enabled = false end
            local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
            if eligibility and eligibility.InvalidateProfession then eligibility:InvalidateProfession(self.professionKey, reason) end
            self:_Record(self.professionKey, {
                contract=self.contract,boundaryContract=self.boundaryContract,provenanceContract=self.provenanceContract,
                confirmationContract=self.confirmationContract,professionKey=self.professionKey,
                state="production-enchanting-native-auto-demoted",reason=reason,
                nativeExecutionAuthorityReady=false,executionEligible=false,executionAuthorityEnabled=false,
                dispatchAllowed=false,nativeDispatchAllowed=false,nativeDispatchAttempted=false,
                confirmationAutomationAllowed=false,persistedAuthorization=false,
            })
        end
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload)=="table" and payload.enabled==false then autoDemote("execution-authority-eligibility-disabled") end
        end)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_AUTHORITY_UPDATED", function(payload)
            if type(payload)=="table" and payload.enabled==false then autoDemote("production-enchanting-authority-disabled") end
        end)
    end
    return true
end

function ProductionEnchantingNativeExecutionAuthority:GetLast(professionKey)
    professionKey = normalizeKey(professionKey) or self.professionKey
    local row = self.lastByProfession[professionKey]
    return row and shallowCopy(row) or nil
end

function ProductionEnchantingNativeExecutionAuthority:GetSummary()
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
    local last = self:GetLast(self.professionKey)
    local lines = {
        "PRODUCTION ENCHANTING / GUARDED NATIVE ENCHANT ONE",
        "ENCHANTING / normal",
        "Contract: " .. self.contract,
        "Confirmation boundary: " .. self.confirmationContract,
        "Native feature gate: " .. (featureEnabled() and "enabled" or "disabled"),
        "Production Enchanting authority: " .. ((adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) and "enabled" or "disabled"),
        "Execution eligibility gate: " .. ((eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) and "enabled" or "disabled"),
        "Scope: one explicit Guide click -> exactly one CraftEnchant(recipeID, 1, nil, ItemLocation)",
        "Target identity: GUID + itemID + fresh ItemLocation + target-proof fingerprint",
        "Craft All: disabled",
        "Auto Route: disabled",
        "Protected Replace/Bind automation: forbidden; Blizzard secure confirmation only",
        "Authorization persistence: none",
        "Native execution authority: " .. (self:IsEffectiveEnabled() and "armed (fresh reservation still required)" or "disabled"),
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines + 1] = "Target GUID: " .. tostring(last.targetGUID or "none")
        lines[#lines + 1] = "Target itemID: " .. tostring(last.targetItemID or "none")
        lines[#lines + 1] = "Target ItemLocation: " .. tostring(last.targetLocationKey or "none")
        lines[#lines + 1] = "Confirmation required: " .. (last.confirmationRequired and ("yes · "..tostring(last.confirmationReason or last.confirmationEvent or "native")) or "no")
        lines[#lines + 1] = "Native dispatch attempted: " .. tostring(last.nativeDispatchAttempted == true and "yes" or "no")
        lines[#lines + 1] = "Ledger: " .. tostring(last.ledgerID or "none")
        lines[#lines + 1] = "Reservation: " .. tostring(last.reservationToken or "none")
        if last.blockedGate then lines[#lines + 1] = "Blocked gate: " .. tostring(last.blockedGate) .. " · " .. tostring(last.blockedState or "blocked") end
    end
    return table.concat(lines, "\n")
end

function ProductionEnchantingNativeExecutionAuthority:Validate()
    local errors, warnings = {}, {}
    if self.maxEnchantCount ~= 1 then errors[#errors + 1] = "production Enchanting native max enchant count must remain one" end
    if self.persistedAuthorization ~= false then errors[#errors + 1] = "production Enchanting native authorization must not persist" end
    if self.automaticExecutionAllowed ~= false or self.craftAllAllowed ~= false or self.autoRouteAllowed ~= false or self.confirmationAutomationAllowed ~= false then
        errors[#errors + 1] = "production Enchanting native scope must remain explicit Enchant One only with protected confirmation automation forbidden"
    end
    for _, name in ipairs({"ProductionEnchantingAuthorityAdapter","ProductionEnchantingExecutionReadiness","ResearchExecutionAuthorityGate","ResearchExecutionReadiness","TransactionLedger","TransactionRecovery","ProductionEnchantingNativeSettlement","ProductionEnchantingNativeRouteCoverage","Crafting"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "production Enchanting native dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingNativeExecutionAuthority", ProductionEnchantingNativeExecutionAuthority)
