local _, JLP = ...

-- Alpha76 is the first research route layer allowed to cross the native
-- CraftRecipe boundary. It is deliberately narrower than normal direct crafting:
-- only one non-enchant craft, only from the Profession Guide click-origin chain,
-- only while both alpha75 eligibility and this separate default-off native gate
-- are enabled, and only after the alpha75 reservation is revalidated again at the
-- Crafting boundary. No Craft All, Enchant or automatic dispatch is permitted.
local ResearchNativeExecutionAuthority = {
    contract = "guarded-native-single-craft-execution-authority-v1",
    boundaryContract = "native-single-craft-dispatch-boundary-v1",
    provenanceContract = "research-native-dispatch-provenance-v1",
    authority = "feature-gated-live-single-craft-native-dispatch-v1",
    maxCraftCount = 1,
    persistedAuthorization = false,
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
    return profile and profile.researchNativeExecutionAuthority or nil
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

function ResearchNativeExecutionAuthority:IsFeatureEnabled()
    return featureEnabled()
end

function ResearchNativeExecutionAuthority:IsEffectiveEnabled()
    if not featureEnabled() then return false end
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    return eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled() or false
end

function ResearchNativeExecutionAuthority:SetFeatureEnabled(enabled)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    if enabled == true then
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
    end
    profile.enabled = enabled == true
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if eligibility and eligibility.Invalidate then eligibility:Invalidate("native-execution-feature-gate-changed") end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_NATIVE_EXECUTION_AUTHORITY_UPDATED", { enabled=profile.enabled })
        JLP.EventBus:Emit("SETTINGS_CHANGED", "researchNativeExecutionAuthority", profile.enabled)
    end
    return true, profile.enabled and "enabled" or "disabled"
end

function ResearchNativeExecutionAuthority:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    if not professionKey or professionKey == "ENCHANTING" then return false end
    local routeAuthority = JLP:GetModule("ResearchRouteAuthorityBridge")
    return routeAuthority and routeAuthority.IsSupported and routeAuthority:IsSupported(professionKey) or false
end

function ResearchNativeExecutionAuthority:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if professionKey and type(report) == "table" then
        self.lastByProfession[professionKey] = shallowCopy(report)
    end
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("RESEARCH_NATIVE_EXECUTION_UPDATED", shallowCopy(report))
    end
    return report
end

function ResearchNativeExecutionAuthority:EvaluateReservation(reservation, options)
    local professionKey = normalizeKey(type(reservation) == "table" and reservation.professionKey or nil) or "ENGINEERING"
    local mode = normalizeMode(type(reservation) == "table" and reservation.mode or nil)
    local model = {
        contract = self.contract,
        boundaryContract = self.boundaryContract,
        provenanceContract = self.provenanceContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        state = "native-single-craft-authority-blocked",
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
        nativeGate and "native-execution-feature-gate-enabled" or "native-execution-feature-gate-disabled",
        "separate default-off alpha76 native execution gate")

    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local eligibilityEnabled = eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled() or false
    addGate(model, "eligibility-feature-gate", eligibilityEnabled,
        eligibilityEnabled and "execution-authority-eligibility-gate-enabled" or "execution-authority-eligibility-gate-disabled",
        "alpha75 eligibility gate must remain enabled")

    local supported = self:IsSupported(professionKey)
    addGate(model, "supported-profession", supported,
        supported and "native-research-profession-supported" or "native-research-profession-unsupported",
        "Alchemy, Blacksmithing, Engineering and Leatherworking only; research Enchanting execution is excluded")

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
        shapeReady and "single-craft-reservation-valid" or "single-craft-reservation-invalid",
        "alpha76 accepts exactly one alpha75 candidate craft")

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
        "transaction provenance and reload recovery must be reservable before native dispatch")

    local reservationCurrent, reservationState, current, stored = false, "execution-reservation-unvalidated", nil, nil
    if nativeGate and eligibilityEnabled and supported and shapeReady and nativeAPI and transactionClear and durableBoundary
        and eligibility and eligibility.ValidateReservation then
        reservationCurrent, reservationState, current, stored = eligibility:ValidateReservation(reservation, professionKey, mode, options)
    end
    model.reservationValidationState = reservationState
    addGate(model, "reservation-current", reservationCurrent,
        reservationCurrent and "execution-reservation-current" or tostring(reservationState or "execution-reservation-unavailable"),
        "alpha75 reservation must still match current build/snapshot/fingerprint/recipe/craftability")

    local boundaryPresent = crafting and type(crafting.NativeResearchSingleCraftBoundary) == "function"
    addGate(model, "native-boundary", boundaryPresent,
        boundaryPresent and "native-single-craft-boundary-present" or "native-single-craft-boundary-missing",
        "all native dispatch must cross the dedicated Crafting boundary")

    model.stats.blockedGates = model.stats.totalGates - model.stats.passedGates
    model.recipe = current and current.recipe or (stored and stored.recipe) or (reservation and reservation.recipe)
    model.recipeID = tonumber(current and current.recipeID) or tonumber(stored and stored.recipeID) or tonumber(reservation and reservation.recipeID)
    model.snapshotToken = current and current.snapshotToken or (stored and stored.snapshotToken)
    model.stateFingerprint = current and current.stateFingerprint or (stored and stored.stateFingerprint)
    model.reservationToken = stored and stored.token or (reservation and reservation.token)
    model.currentBuild = current and current.currentBuild or (stored and stored.currentBuild)
    model.craftabilityStatus = current and current.craftabilityStatus or "UNKNOWN"
    model.craftabilityReason = current and current.craftabilityReason or "live-readiness-unavailable"
    -- Historic reservations are reference evidence, never current craftability.
    model.nativeCraftable = model.craftabilityStatus == "KNOWN"
        and tonumber(current and current.nativeCraftable) or nil
    model.priorReservationCraftable = tonumber(stored and stored.nativeCraftable)

    if model.stats.totalGates == 9 and model.stats.passedGates == 9 then
        model.state = "native-single-craft-authority-ready"
        model.nativeExecutionAuthorityReady = true
        model.executionEligible = true
        model.executionAuthorityEnabled = true
        model.dispatchAllowed = true
        model.nativeDispatchAllowed = true
    end

    return model, current, stored
end

function ResearchNativeExecutionAuthority:Request(professionKey, mode, clickOrigin, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if not featureEnabled() then
        local report = self:_Record(professionKey, {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=professionKey,mode=mode,
            state="native-execution-feature-gate-disabled",nativeExecutionAuthorityReady=false,
            executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            nativeDispatchAttempted=false,persistedAuthorization=false,
        })
        return false, report.state, report
    end
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
        if eligibility.RevokeReservation then eligibility:RevokeReservation(reservation.token, "native-authority-evaluation-blocked") end
        self:_Record(professionKey, model)
        return false, model.state, model
    end

    local crafting = JLP:GetModule("Crafting")
    local ok, boundaryState, report = crafting:NativeResearchSingleCraftBoundary(reservation, options)
    report = type(report) == "table" and report or model
    report.contract = self.contract
    report.boundaryContract = self.boundaryContract
    report.state = boundaryState or report.state or (ok and "native-single-craft-dispatched" or "native-single-craft-dispatch-blocked")
    self:_Record(professionKey, report)
    return ok and true or false, report.state, report
end

function ResearchNativeExecutionAuthority:ObserveCraftAction(action)
    local provenance = type(action) == "table" and action.authorityProvenance or nil
    if type(provenance) ~= "table" or provenance.contract ~= self.provenanceContract then return false end
    local professionKey = normalizeKey(action.key or provenance.professionKey)
    if not professionKey then return false end
    local status = tostring(action.status or "unknown")
    local state
    if status == "success" then state = "native-single-craft-confirmed"
    elseif status == "failed" or status == "timeout" then state = "native-single-craft-failed"
    else state = "native-single-craft-in-flight" end
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

function ResearchNativeExecutionAuthority:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false and featureEnabled() then
                local profile = featureProfile()
                if profile then profile.enabled = false end
                self:_Record("ENGINEERING", {
                    contract=self.contract,boundaryContract=self.boundaryContract,state="native-execution-auto-demoted",
                    reason="execution-authority-eligibility-disabled",nativeExecutionAuthorityReady=false,
                    executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
                    nativeDispatchAttempted=false,persistedAuthorization=false,
                })
            end
        end)
    end
    return true
end

function ResearchNativeExecutionAuthority:GetLast(professionKey)
    professionKey = normalizeKey(professionKey)
    local row = professionKey and self.lastByProfession[professionKey] or nil
    return row and shallowCopy(row) or nil
end

function ResearchNativeExecutionAuthority:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local last = self:GetLast(professionKey)
    local lines = {
        "RESEARCH NATIVE EXECUTION / GUARDED SINGLE CRAFT",
        professionKey .. " / " .. mode,
        "Native feature gate: " .. (featureEnabled() and "enabled" or "disabled"),
        "Alpha75 eligibility gate: " .. ((eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) and "enabled" or "disabled"),
        "Scope: Craft One only · research Enchanting excluded · no automatic execution",
        "Transaction ordering: reservation -> ledger/recovery checkpoint -> CraftRecipe(recipeID, 1)",
        "Native execution authority: " .. (self:IsEffectiveEnabled() and "armed (still requires current reservation)" or "disabled"),
        "Authorization persistence: none",
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

function ResearchNativeExecutionAuthority:Validate()
    local errors, warnings = {}, {}
    if self.maxCraftCount ~= 1 then errors[#errors + 1] = "research native execution max craft count must remain one" end
    if self.persistedAuthorization ~= false then errors[#errors + 1] = "research native execution authorization must not persist" end
    for _, name in ipairs({"ResearchExecutionAuthorityGate", "ResearchExecutionReadiness", "TransactionLedger", "TransactionRecovery", "Crafting"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "research native execution dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeExecutionAuthority", ResearchNativeExecutionAuthority)
