local _, JLP = ...

-- Alpha75 is the first feature-gated execution-authority eligibility layer for
-- research-derived routes.  It deliberately stops one boundary before native
-- crafting: a current alpha73 intent must first pass the real alpha74 shadow
-- Crafting boundary, then a short-lived single-use dispatch reservation is
-- issued.  The reservation can be revalidated at the guarded Crafting boundary,
-- but alpha75 never grants permission to call CraftRecipe/CraftEnchant.
local ResearchExecutionAuthorityGate = {
    contract = "controlled-execution-authority-eligibility-gate-v1",
    clickOriginContract = "research-execution-click-origin-v1",
    reservationContract = "research-native-dispatch-reservation-v1",
    boundaryContract = "guarded-native-dispatch-boundary-v1",
    authority = "feature-gated-native-dispatch-candidate-only",
    executionEligible = false,
    executionAuthorityEnabled = false,
    dispatchAllowed = false,
    nativeDispatchAllowed = false,
    persisted = false,
    clickOriginTTLSeconds = 3,
    reservationTTLSeconds = 5,
    originSerial = 0,
    reservationSerial = 0,
    clickOrigins = {},
    reservations = {},
    activeReservationByProfession = {},
    lastByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
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

local function stateHash(parts)
    local value = table.concat(parts or {}, "\31")
    local hash = 5381
    for index = 1, #value do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return string.format("%08x", hash)
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local INVALIDATION_EVENTS = {
    "RESEARCH_ROUTE_AUTHORITY_UPDATED",
    "RESEARCH_CONSUMER_AUTHORITY_UPDATED",
    "PROFESSION_PROGRESS_UPDATED",
    "PROFESSION_CRAFT_OBSERVED",
    "PROFESSION_TRANSACTION_UPDATED",
    "CRAFT_ACTION_UPDATED",
    "ENCHANT_ACTION_UPDATED",
    "TRANSACTION_RECOVERY_UPDATED",
    "RECIPE_TELEMETRY_UPDATED",
    "RECIPE_ACCESS_EVIDENCE_UPDATED",
    "MATERIAL_ACQUISITION_EVIDENCE_UPDATED",
    "PRODUCTION_TAILORING_AUTHORITY_UPDATED",
    "PRODUCTION_TAILORING_NATIVE_EXECUTION_AUTHORITY_UPDATED",
    "PRODUCTION_ENCHANTING_AUTHORITY_UPDATED",
    "PRODUCTION_ENCHANTING_TARGET_UPDATED",
    "PRODUCTION_ENCHANTING_NATIVE_EXECUTION_AUTHORITY_UPDATED",
}

local function featureProfile()
    local profile = JLP.DB and JLP.DB.profile
    return profile and profile.researchExecutionAuthority or nil
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

function ResearchExecutionAuthorityGate:IsFeatureEnabled()
    return featureEnabled()
end

function ResearchExecutionAuthorityGate:SetFeatureEnabled(enabled)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    profile.enabled = enabled == true
    self:RevokeAllReservations("feature-gate-changed")
    self.clickOrigins = {}
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_EXECUTION_AUTHORITY_UPDATED", { enabled=profile.enabled })
        JLP.EventBus:Emit("SETTINGS_CHANGED", "researchExecutionAuthority", profile.enabled)
    end
    return true, profile.enabled and "enabled" or "disabled"
end

function ResearchExecutionAuthorityGate:IsSupported(professionKey)
    -- Alpha100 makes the reservation layer source-aware.  Research professions
    -- still enter through ResearchRouteAuthorityBridge indirectly, while
    -- production Tailoring is admitted only because ResearchExecutionReadiness
    -- has an explicit source policy for it.  This does not grant native authority.
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    return readiness and readiness.IsSupported and readiness:IsSupported(normalizeKey(professionKey)) or false
end

function ResearchExecutionAuthorityGate:_Sweep(nowValue)
    nowValue = tonumber(nowValue) or monotonicNow()
    for token, origin in pairs(self.clickOrigins or {}) do
        if type(origin) ~= "table" or (tonumber(origin.expiresAt) and nowValue > tonumber(origin.expiresAt)) then
            self.clickOrigins[token] = nil
        end
    end
    for token, reservation in pairs(self.reservations or {}) do
        if type(reservation) ~= "table" or (tonumber(reservation.expiresAt) and nowValue > tonumber(reservation.expiresAt)) then
            if type(reservation) == "table" then
                local key = normalizeKey(reservation.professionKey)
                if key and self.activeReservationByProfession[key] == token then
                    self.activeReservationByProfession[key] = nil
                end
            end
            self.reservations[token] = nil
        end
    end
end

function ResearchExecutionAuthorityGate:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if not professionKey or type(report) ~= "table" then return report end
    self.lastByProfession[professionKey] = shallowCopy(report)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_EXECUTION_AUTHORITY_EVALUATED", shallowCopy(report))
    end
    return report
end

function ResearchExecutionAuthorityGate:BeginClickOrigin(professionKey, mode, source)
    professionKey = normalizeKey(professionKey)
    mode = normalizeMode(mode)
    source = tostring(source or "")
    if not professionKey or source ~= "profession-guide" then
        return nil, "execution-click-origin-invalid"
    end
    if not featureEnabled() then
        return nil, "execution-authority-feature-gate-disabled"
    end
    local nowValue = monotonicNow()
    self:_Sweep(nowValue)
    self.originSerial = (tonumber(self.originSerial) or 0) + 1
    local token = "exec-origin-" .. stateHash({
        professionKey, mode, source, tostring(self.originSerial), tostring(nowValue),
    })
    local origin = {
        contract = self.clickOriginContract,
        token = token,
        source = source,
        professionKey = professionKey,
        mode = mode,
        createdAt = nowValue,
        expiresAt = nowValue + self.clickOriginTTLSeconds,
        singleUse = true,
        persisted = false,
    }
    self.clickOrigins[token] = origin
    return shallowCopy(origin), "execution-click-origin-prepared"
end

function ResearchExecutionAuthorityGate:BeginSequentialClickOrigin(professionKey, mode, delegation)
    professionKey = normalizeKey(professionKey)
    mode = normalizeMode(mode)
    if not professionKey or type(delegation) ~= "table" then
        return nil, "execution-sequential-origin-invalid"
    end
    if not featureEnabled() then
        return nil, "execution-authority-feature-gate-disabled"
    end
    local sequential = JLP:GetModule("ResearchBoundedSequentialCraft")
    if not sequential or not sequential.ValidateDelegation then
        return nil, "bounded-sequence-delegation-unavailable"
    end
    local valid, state = sequential:ValidateDelegation(delegation, professionKey, mode)
    if not valid then return nil, state end
    local source = delegation.directGuideClick == true and "profession-guide" or "bounded-sequential-orchestrator"
    local nowValue = monotonicNow()
    self:_Sweep(nowValue)
    self.originSerial = (tonumber(self.originSerial) or 0) + 1
    local token = "exec-origin-" .. stateHash({
        professionKey, mode, source, tostring(delegation.sessionToken or ""), tostring(delegation.ordinal or ""),
        tostring(self.originSerial), tostring(nowValue),
    })
    local origin = {
        contract = self.clickOriginContract,
        token = token,
        source = source,
        professionKey = professionKey,
        mode = mode,
        sequenceSessionToken = delegation.sessionToken,
        sequenceOrdinal = tonumber(delegation.ordinal),
        sequenceRequestedCount = tonumber(delegation.requestedCount),
        sequenceDirectGuideClick = delegation.directGuideClick == true,
        sequenceDelegationContract = delegation.contract,
        restartCandidateToken = delegation.restartCandidateToken,
        restartAuthorizationToken = delegation.restartAuthorizationToken,
        restartedFromSessionToken = delegation.restartedFromSessionToken,
        restartedFromBoundaryState = delegation.restartedFromBoundaryState,
        restartedFromBoundaryCategory = delegation.restartedFromBoundaryCategory,
        restartRouteTransitionKind = delegation.restartRouteTransitionKind,
        restartRouteChanged = delegation.restartRouteChanged == true,
        restartPriorRecipeID = delegation.restartPriorRecipeID,
        restartPriorRouteIndex = delegation.restartPriorRouteIndex,
        restartCurrentRecipeID = delegation.restartCurrentRecipeID,
        restartCurrentRouteIndex = delegation.restartCurrentRouteIndex,
        restartExplicitUserClick = delegation.restartExplicitUserClick == true,
        createdAt = nowValue,
        expiresAt = nowValue + self.clickOriginTTLSeconds,
        singleUse = true,
        persisted = false,
    }
    self.clickOrigins[token] = origin
    return shallowCopy(origin), "execution-sequential-click-origin-prepared"
end


function ResearchExecutionAuthorityGate:BeginAutoRouteClickOrigin(professionKey, mode, delegation)
    professionKey = normalizeKey(professionKey)
    mode = normalizeMode(mode)
    if not professionKey or type(delegation) ~= "table" then
        return nil, "execution-auto-route-origin-invalid"
    end
    if not featureEnabled() then return nil, "execution-authority-feature-gate-disabled" end
    local autoRoute = JLP:GetModule("ResearchAutoRouteOrchestrator")
    if not autoRoute or not autoRoute.ValidateDelegation then return nil, "auto-route-delegation-unavailable" end
    local valid, state = autoRoute:ValidateDelegation(delegation, professionKey, mode)
    if not valid then return nil, state end
    local source = delegation.directGuideClick == true and "profession-guide" or "auto-route-orchestrator"
    local nowValue = monotonicNow()
    self:_Sweep(nowValue)
    self.originSerial = (tonumber(self.originSerial) or 0) + 1
    local token = "exec-origin-" .. stateHash({professionKey, mode, source, tostring(delegation.sessionToken or ""), tostring(delegation.ordinal or ""), tostring(self.originSerial), tostring(nowValue)})
    local origin = {
        contract = self.clickOriginContract, token = token, source = source, professionKey = professionKey, mode = mode,
        autoRouteSessionToken = delegation.sessionToken, autoRouteOrdinal = tonumber(delegation.ordinal),
        autoRouteDirectGuideClick = delegation.directGuideClick == true, autoRouteDelegationContract = delegation.contract,
        autoRouteSourceAuthorityContract = delegation.sourceAutoRouteAuthorityContract, autoRouteSourcePromotionContract = delegation.sourceAutoRoutePromotionContract,
        autoRouteRecipeID = tonumber(delegation.recipeID), autoRouteRouteIndex = tonumber(delegation.routeIndex),
        autoRouteSkillTarget = tonumber(delegation.skillTarget), autoRouteSnapshotToken = delegation.snapshotToken,
        restartCandidateToken = delegation.restartCandidateToken, restartAuthorizationToken = delegation.restartAuthorizationToken,
        restartedFromSessionToken = delegation.restartedFromSessionToken, restartedFromBoundaryState = delegation.restartedFromBoundaryState,
        restartedFromBoundaryCategory = delegation.restartedFromBoundaryCategory, restartRouteTransitionKind = delegation.restartRouteTransitionKind,
        restartRouteChanged = delegation.restartRouteChanged == true, restartPriorRecipeID = delegation.restartPriorRecipeID,
        restartPriorRouteIndex = delegation.restartPriorRouteIndex, restartCurrentRecipeID = delegation.restartCurrentRecipeID,
        restartCurrentRouteIndex = delegation.restartCurrentRouteIndex, restartExplicitUserClick = delegation.restartExplicitUserClick == true,
        restartSourceProofContract = delegation.restartSourceProofContract, restartSourceProofToken = delegation.restartSourceProofToken,
        restartSourceAutoRouteAuthorityContract = delegation.restartSourceAutoRouteAuthorityContract, restartSourceAutoRoutePromotionContract = delegation.restartSourceAutoRoutePromotionContract,
        routeChangeBasis = delegation.routeChangeBasis, routeChangeProofToken = delegation.routeChangeProofToken, routeChangePurgeReceiptToken = delegation.routeChangePurgeReceiptToken,
        routeChangePurgeVerified = delegation.routeChangePurgeVerified == true, routeChangePostPurgeRevalidated = delegation.routeChangePostPurgeRevalidated == true,
        routeChangePurgedIntentCount = tonumber(delegation.routeChangePurgedIntentCount) or 0, routeChangePurgedReservationCount = tonumber(delegation.routeChangePurgedReservationCount) or 0, routeChangePurgedClickOriginCount = tonumber(delegation.routeChangePurgedClickOriginCount) or 0,
        autoRouteLineageContract = delegation.lineageContract, autoRouteLineageChainToken = delegation.lineageChainToken, autoRouteLineageRootSessionToken = delegation.lineageRootSessionToken,
        autoRouteLineageParentSessionToken = delegation.lineageParentSessionToken, autoRouteLineageDepth = tonumber(delegation.lineageDepth), autoRouteLineageGeneration = tonumber(delegation.lineageGeneration),
        autoRouteLineagePredecessorProofToken = delegation.lineagePredecessorProofToken, autoRouteLineageSessionProofToken = delegation.lineageSessionProofToken, autoRouteLineageInterruptionToken = delegation.lineageInterruptionToken,
        createdAt = nowValue, expiresAt = nowValue + self.clickOriginTTLSeconds, singleUse = true, persisted = false,
    }
    self.clickOrigins[token] = origin
    return shallowCopy(origin), "execution-auto-route-click-origin-prepared"
end

function ResearchExecutionAuthorityGate:_ConsumeClickOrigin(origin, professionKey, mode)
    if type(origin) ~= "table" or origin.contract ~= self.clickOriginContract then
        return false, "execution-click-origin-invalid"
    end
    local token = tostring(origin.token or "")
    if token == "" then return false, "execution-click-origin-invalid" end
    local nowValue = monotonicNow()
    self:_Sweep(nowValue)
    local stored = self.clickOrigins[token]
    if type(stored) ~= "table" then return false, "execution-click-origin-expired-or-unknown" end
    -- Every submitted click origin is single-use, including malformed attempts.
    self.clickOrigins[token] = nil
    if tonumber(stored.expiresAt) and nowValue > tonumber(stored.expiresAt) then
        return false, "execution-click-origin-expired-or-unknown"
    end
    professionKey = normalizeKey(professionKey)
    mode = normalizeMode(mode)
    local submittedSource = tostring(origin.source or "")
    local storedSource = tostring(stored.source or "")
    local sourceAllowed = submittedSource == "profession-guide" or submittedSource == "bounded-sequential-orchestrator" or submittedSource == "auto-route-orchestrator"
    local exact = origin.contract == stored.contract
        and sourceAllowed
        and submittedSource == storedSource
        and normalizeKey(origin.professionKey) == professionKey
        and normalizeKey(stored.professionKey) == professionKey
        and normalizeMode(origin.mode) == mode
        and normalizeMode(stored.mode) == mode
        and tostring(origin.sequenceSessionToken or "") == tostring(stored.sequenceSessionToken or "")
        and tonumber(origin.sequenceOrdinal) == tonumber(stored.sequenceOrdinal)
        and tonumber(origin.sequenceRequestedCount) == tonumber(stored.sequenceRequestedCount)
        and (origin.sequenceDirectGuideClick == true) == (stored.sequenceDirectGuideClick == true)
        and tostring(origin.sequenceDelegationContract or "") == tostring(stored.sequenceDelegationContract or "")
        and tostring(origin.autoRouteSessionToken or "") == tostring(stored.autoRouteSessionToken or "")
        and tonumber(origin.autoRouteOrdinal) == tonumber(stored.autoRouteOrdinal)
        and (origin.autoRouteDirectGuideClick == true) == (stored.autoRouteDirectGuideClick == true)
        and tostring(origin.autoRouteDelegationContract or "") == tostring(stored.autoRouteDelegationContract or "")
        and tostring(origin.autoRouteSourceAuthorityContract or "") == tostring(stored.autoRouteSourceAuthorityContract or "")
        and tostring(origin.autoRouteSourcePromotionContract or "") == tostring(stored.autoRouteSourcePromotionContract or "")
        and tonumber(origin.autoRouteRecipeID) == tonumber(stored.autoRouteRecipeID)
        and tonumber(origin.autoRouteRouteIndex) == tonumber(stored.autoRouteRouteIndex)
        and tonumber(origin.autoRouteSkillTarget) == tonumber(stored.autoRouteSkillTarget)
        and tostring(origin.autoRouteSnapshotToken or "") == tostring(stored.autoRouteSnapshotToken or "")
        and tostring(origin.restartCandidateToken or "") == tostring(stored.restartCandidateToken or "")
        and tostring(origin.restartAuthorizationToken or "") == tostring(stored.restartAuthorizationToken or "")
        and tostring(origin.restartedFromSessionToken or "") == tostring(stored.restartedFromSessionToken or "")
        and tostring(origin.restartedFromBoundaryState or "") == tostring(stored.restartedFromBoundaryState or "")
        and tostring(origin.restartedFromBoundaryCategory or "") == tostring(stored.restartedFromBoundaryCategory or "")
        and tostring(origin.restartRouteTransitionKind or "") == tostring(stored.restartRouteTransitionKind or "")
        and (origin.restartRouteChanged == true) == (stored.restartRouteChanged == true)
        and tonumber(origin.restartPriorRecipeID) == tonumber(stored.restartPriorRecipeID)
        and tonumber(origin.restartPriorRouteIndex) == tonumber(stored.restartPriorRouteIndex)
        and tonumber(origin.restartCurrentRecipeID) == tonumber(stored.restartCurrentRecipeID)
        and tonumber(origin.restartCurrentRouteIndex) == tonumber(stored.restartCurrentRouteIndex)
        and (origin.restartExplicitUserClick == true) == (stored.restartExplicitUserClick == true)
        and tostring(origin.restartSourceProofContract or "") == tostring(stored.restartSourceProofContract or "")
        and tostring(origin.restartSourceProofToken or "") == tostring(stored.restartSourceProofToken or "")
        and tostring(origin.restartSourceAutoRouteAuthorityContract or "") == tostring(stored.restartSourceAutoRouteAuthorityContract or "")
        and tostring(origin.restartSourceAutoRoutePromotionContract or "") == tostring(stored.restartSourceAutoRoutePromotionContract or "")
        and tostring(origin.routeChangeBasis or "") == tostring(stored.routeChangeBasis or "")
        and tostring(origin.routeChangeProofToken or "") == tostring(stored.routeChangeProofToken or "")
        and tostring(origin.routeChangePurgeReceiptToken or "") == tostring(stored.routeChangePurgeReceiptToken or "")
        and (origin.routeChangePurgeVerified == true) == (stored.routeChangePurgeVerified == true)
        and (origin.routeChangePostPurgeRevalidated == true) == (stored.routeChangePostPurgeRevalidated == true)
        and tonumber(origin.routeChangePurgedIntentCount or 0) == tonumber(stored.routeChangePurgedIntentCount or 0)
        and tonumber(origin.routeChangePurgedReservationCount or 0) == tonumber(stored.routeChangePurgedReservationCount or 0)
        and tonumber(origin.routeChangePurgedClickOriginCount or 0) == tonumber(stored.routeChangePurgedClickOriginCount or 0)
        and tostring(origin.autoRouteLineageContract or "") == tostring(stored.autoRouteLineageContract or "")
        and tostring(origin.autoRouteLineageChainToken or "") == tostring(stored.autoRouteLineageChainToken or "")
        and tostring(origin.autoRouteLineageRootSessionToken or "") == tostring(stored.autoRouteLineageRootSessionToken or "")
        and tostring(origin.autoRouteLineageParentSessionToken or "") == tostring(stored.autoRouteLineageParentSessionToken or "")
        and tonumber(origin.autoRouteLineageDepth) == tonumber(stored.autoRouteLineageDepth)
        and tostring(origin.autoRouteLineagePredecessorProofToken or "") == tostring(stored.autoRouteLineagePredecessorProofToken or "")
        and tostring(origin.autoRouteLineageSessionProofToken or "") == tostring(stored.autoRouteLineageSessionProofToken or "")
        and tostring(origin.autoRouteLineageInterruptionToken or "") == tostring(stored.autoRouteLineageInterruptionToken or "")
    if not exact then return false, "execution-click-origin-mismatch" end
    if stored.autoRouteSessionToken then
        local autoRoute = JLP:GetModule("ResearchAutoRouteOrchestrator")
        local delegation = {
            contract = stored.autoRouteDelegationContract, sessionToken = stored.autoRouteSessionToken,
            professionKey = stored.professionKey, mode = stored.mode, ordinal = stored.autoRouteOrdinal,
            sourceAutoRouteAuthorityContract = stored.autoRouteSourceAuthorityContract, sourceAutoRoutePromotionContract = stored.autoRouteSourcePromotionContract,
            directGuideClick = stored.autoRouteDirectGuideClick == true, recipeID = stored.autoRouteRecipeID,
            routeIndex = stored.autoRouteRouteIndex, skillTarget = stored.autoRouteSkillTarget, snapshotToken = stored.autoRouteSnapshotToken,
            restartCandidateToken = stored.restartCandidateToken, restartAuthorizationToken = stored.restartAuthorizationToken,
            restartedFromSessionToken = stored.restartedFromSessionToken, restartedFromBoundaryState = stored.restartedFromBoundaryState,
            restartedFromBoundaryCategory = stored.restartedFromBoundaryCategory, restartRouteTransitionKind = stored.restartRouteTransitionKind,
            restartRouteChanged = stored.restartRouteChanged == true, restartPriorRecipeID = stored.restartPriorRecipeID,
            restartPriorRouteIndex = stored.restartPriorRouteIndex, restartCurrentRecipeID = stored.restartCurrentRecipeID,
            restartCurrentRouteIndex = stored.restartCurrentRouteIndex, restartExplicitUserClick = stored.restartExplicitUserClick == true,
            restartSourceProofContract = stored.restartSourceProofContract, restartSourceProofToken = stored.restartSourceProofToken,
            restartSourceAutoRouteAuthorityContract = stored.restartSourceAutoRouteAuthorityContract, restartSourceAutoRoutePromotionContract = stored.restartSourceAutoRoutePromotionContract,
            routeChangeBasis = stored.routeChangeBasis, routeChangeProofToken = stored.routeChangeProofToken, routeChangePurgeReceiptToken = stored.routeChangePurgeReceiptToken,
            routeChangePurgeVerified = stored.routeChangePurgeVerified == true, routeChangePostPurgeRevalidated = stored.routeChangePostPurgeRevalidated == true,
            routeChangePurgedIntentCount = stored.routeChangePurgedIntentCount, routeChangePurgedReservationCount = stored.routeChangePurgedReservationCount, routeChangePurgedClickOriginCount = stored.routeChangePurgedClickOriginCount,
            lineageContract = stored.autoRouteLineageContract, lineageChainToken = stored.autoRouteLineageChainToken, lineageRootSessionToken = stored.autoRouteLineageRootSessionToken,
            lineageParentSessionToken = stored.autoRouteLineageParentSessionToken, lineageDepth = stored.autoRouteLineageDepth, lineageGeneration = stored.autoRouteLineageGeneration,
            lineagePredecessorProofToken = stored.autoRouteLineagePredecessorProofToken, lineageSessionProofToken = stored.autoRouteLineageSessionProofToken, lineageInterruptionToken = stored.autoRouteLineageInterruptionToken,
        }
        local delegated, delegatedState = false, "auto-route-delegation-unavailable"
        if autoRoute and autoRoute.ValidateDelegation then delegated, delegatedState = autoRoute:ValidateDelegation(delegation, professionKey, mode) end
        if not delegated then return false, delegatedState end
    end
    if stored.sequenceSessionToken then
        local sequential = JLP:GetModule("ResearchBoundedSequentialCraft")
        local delegation = {
            contract = stored.sequenceDelegationContract,
            sessionToken = stored.sequenceSessionToken,
            professionKey = stored.professionKey,
            mode = stored.mode,
            ordinal = stored.sequenceOrdinal,
            requestedCount = stored.sequenceRequestedCount,
            directGuideClick = stored.sequenceDirectGuideClick == true,
            restartCandidateToken = stored.restartCandidateToken,
            restartAuthorizationToken = stored.restartAuthorizationToken,
            restartedFromSessionToken = stored.restartedFromSessionToken,
            restartedFromBoundaryState = stored.restartedFromBoundaryState,
            restartedFromBoundaryCategory = stored.restartedFromBoundaryCategory,
            restartRouteTransitionKind = stored.restartRouteTransitionKind,
            restartRouteChanged = stored.restartRouteChanged == true,
            restartPriorRecipeID = stored.restartPriorRecipeID,
            restartPriorRouteIndex = stored.restartPriorRouteIndex,
            restartCurrentRecipeID = stored.restartCurrentRecipeID,
            restartCurrentRouteIndex = stored.restartCurrentRouteIndex,
            restartExplicitUserClick = stored.restartExplicitUserClick == true,
        }
        local delegated, delegatedState = false, "bounded-sequence-delegation-unavailable"
        if sequential and sequential.ValidateDelegation then
            delegated, delegatedState = sequential:ValidateDelegation(delegation, professionKey, mode)
        end
        if not delegated then return false, delegatedState end
    end
    return true, stored.autoRouteSessionToken and "execution-auto-route-click-origin-current" or (stored.sequenceSessionToken and "execution-sequential-click-origin-current" or "execution-click-origin-current"), stored
end

function ResearchExecutionAuthorityGate:GetActiveReservation(professionKey)
    professionKey = normalizeKey(professionKey)
    self:_Sweep(monotonicNow())
    local token = professionKey and self.activeReservationByProfession[professionKey] or nil
    local reservation = token and self.reservations[token] or nil
    return reservation and shallowCopy(reservation) or nil
end

function ResearchExecutionAuthorityGate:PrepareReservation(professionKey, mode, craftMode, clickOrigin, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    craftMode = craftMode == "all" and "all" or "one"
    options = type(options) == "table" and options or {}
    local nowValue = monotonicNow()
    self:_Sweep(nowValue)

    local model = {
        contract = self.contract,
        reservationContract = self.reservationContract,
        boundaryContract = self.boundaryContract,
        professionKey = professionKey,
        mode = mode,
        craftMode = craftMode,
        authority = self.authority,
        state = "execution-authority-eligibility-blocked",
        featureGateEnabled = featureEnabled(),
        candidateEligible = false,
        reservationEligible = false,
        executionEligible = false,
        executionAuthorityEnabled = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        nativeDispatchAttempted = false,
        persisted = false,
        gates = {},
        stats = { passedGates=0, totalGates=0 },
    }

    addGate(model, "feature-gate", model.featureGateEnabled,
        model.featureGateEnabled and "execution-authority-feature-gate-enabled" or "execution-authority-feature-gate-disabled",
        "default-off execution-authority eligibility gate")

    local supported = self:IsSupported(professionKey)
    addGate(model, "supported-profession", supported,
        supported and "controlled-research-profession-supported" or "unsupported-research-profession",
        professionKey)

    local originOK, originState, storedOrigin = false, "execution-click-origin-not-consumed", nil
    if model.featureGateEnabled and supported then
        originOK, originState, storedOrigin = self:_ConsumeClickOrigin(clickOrigin, professionKey, mode)
    end
    model.clickOriginState = originState
    model.clickOriginToken = storedOrigin and storedOrigin.token or (clickOrigin and clickOrigin.token or nil)
    model.clickOriginSource = storedOrigin and storedOrigin.source or (clickOrigin and clickOrigin.source or nil)
    model.sequenceSessionToken = storedOrigin and storedOrigin.sequenceSessionToken or (clickOrigin and clickOrigin.sequenceSessionToken or nil)
    model.sequenceOrdinal = tonumber(storedOrigin and storedOrigin.sequenceOrdinal) or tonumber(clickOrigin and clickOrigin.sequenceOrdinal)
    model.sequenceRequestedCount = tonumber(storedOrigin and storedOrigin.sequenceRequestedCount) or tonumber(clickOrigin and clickOrigin.sequenceRequestedCount)
    model.sequenceDirectGuideClick = storedOrigin and storedOrigin.sequenceDirectGuideClick == true or false
    model.autoRouteSessionToken = storedOrigin and storedOrigin.autoRouteSessionToken or (clickOrigin and clickOrigin.autoRouteSessionToken or nil)
    model.autoRouteOrdinal = tonumber(storedOrigin and storedOrigin.autoRouteOrdinal) or tonumber(clickOrigin and clickOrigin.autoRouteOrdinal)
    model.autoRouteDirectGuideClick = storedOrigin and storedOrigin.autoRouteDirectGuideClick == true or false
    model.autoRouteDelegationContract = storedOrigin and storedOrigin.autoRouteDelegationContract or (clickOrigin and clickOrigin.autoRouteDelegationContract or nil)
    model.autoRouteSourceAuthorityContract = storedOrigin and storedOrigin.autoRouteSourceAuthorityContract or (clickOrigin and clickOrigin.autoRouteSourceAuthorityContract or nil)
    model.autoRouteSourcePromotionContract = storedOrigin and storedOrigin.autoRouteSourcePromotionContract or (clickOrigin and clickOrigin.autoRouteSourcePromotionContract or nil)
    model.autoRouteRecipeID = tonumber(storedOrigin and storedOrigin.autoRouteRecipeID) or tonumber(clickOrigin and clickOrigin.autoRouteRecipeID)
    model.autoRouteRouteIndex = tonumber(storedOrigin and storedOrigin.autoRouteRouteIndex) or tonumber(clickOrigin and clickOrigin.autoRouteRouteIndex)
    model.autoRouteSkillTarget = tonumber(storedOrigin and storedOrigin.autoRouteSkillTarget) or tonumber(clickOrigin and clickOrigin.autoRouteSkillTarget)
    model.autoRouteSnapshotToken = storedOrigin and storedOrigin.autoRouteSnapshotToken or (clickOrigin and clickOrigin.autoRouteSnapshotToken or nil)
    model.restartCandidateToken = storedOrigin and storedOrigin.restartCandidateToken or (clickOrigin and clickOrigin.restartCandidateToken or nil)
    model.restartAuthorizationToken = storedOrigin and storedOrigin.restartAuthorizationToken or (clickOrigin and clickOrigin.restartAuthorizationToken or nil)
    model.restartedFromSessionToken = storedOrigin and storedOrigin.restartedFromSessionToken or (clickOrigin and clickOrigin.restartedFromSessionToken or nil)
    model.restartedFromBoundaryState = storedOrigin and storedOrigin.restartedFromBoundaryState or (clickOrigin and clickOrigin.restartedFromBoundaryState or nil)
    model.restartedFromBoundaryCategory = storedOrigin and storedOrigin.restartedFromBoundaryCategory or (clickOrigin and clickOrigin.restartedFromBoundaryCategory or nil)
    model.restartRouteTransitionKind = storedOrigin and storedOrigin.restartRouteTransitionKind or (clickOrigin and clickOrigin.restartRouteTransitionKind or nil)
    model.restartRouteChanged = storedOrigin and storedOrigin.restartRouteChanged == true or false
    model.restartPriorRecipeID = tonumber(storedOrigin and storedOrigin.restartPriorRecipeID) or tonumber(clickOrigin and clickOrigin.restartPriorRecipeID)
    model.restartPriorRouteIndex = tonumber(storedOrigin and storedOrigin.restartPriorRouteIndex) or tonumber(clickOrigin and clickOrigin.restartPriorRouteIndex)
    model.restartCurrentRecipeID = tonumber(storedOrigin and storedOrigin.restartCurrentRecipeID) or tonumber(clickOrigin and clickOrigin.restartCurrentRecipeID)
    model.restartCurrentRouteIndex = tonumber(storedOrigin and storedOrigin.restartCurrentRouteIndex) or tonumber(clickOrigin and clickOrigin.restartCurrentRouteIndex)
    model.restartExplicitUserClick = storedOrigin and storedOrigin.restartExplicitUserClick == true or false
    model.restartSourceProofContract = storedOrigin and storedOrigin.restartSourceProofContract or (clickOrigin and clickOrigin.restartSourceProofContract or nil)
    model.restartSourceProofToken = storedOrigin and storedOrigin.restartSourceProofToken or (clickOrigin and clickOrigin.restartSourceProofToken or nil)
    model.restartSourceAutoRouteAuthorityContract = storedOrigin and storedOrigin.restartSourceAutoRouteAuthorityContract or (clickOrigin and clickOrigin.restartSourceAutoRouteAuthorityContract or nil)
    model.restartSourceAutoRoutePromotionContract = storedOrigin and storedOrigin.restartSourceAutoRoutePromotionContract or (clickOrigin and clickOrigin.restartSourceAutoRoutePromotionContract or nil)
    model.routeChangeBasis = storedOrigin and storedOrigin.routeChangeBasis or (clickOrigin and clickOrigin.routeChangeBasis or nil)
    model.routeChangeProofToken = storedOrigin and storedOrigin.routeChangeProofToken or (clickOrigin and clickOrigin.routeChangeProofToken or nil)
    model.routeChangePurgeReceiptToken = storedOrigin and storedOrigin.routeChangePurgeReceiptToken or (clickOrigin and clickOrigin.routeChangePurgeReceiptToken or nil)
    model.routeChangePurgeVerified = storedOrigin and storedOrigin.routeChangePurgeVerified == true or false
    model.routeChangePostPurgeRevalidated = storedOrigin and storedOrigin.routeChangePostPurgeRevalidated == true or false
    model.routeChangePurgedIntentCount = tonumber(storedOrigin and storedOrigin.routeChangePurgedIntentCount) or tonumber(clickOrigin and clickOrigin.routeChangePurgedIntentCount) or 0
    model.routeChangePurgedReservationCount = tonumber(storedOrigin and storedOrigin.routeChangePurgedReservationCount) or tonumber(clickOrigin and clickOrigin.routeChangePurgedReservationCount) or 0
    model.routeChangePurgedClickOriginCount = tonumber(storedOrigin and storedOrigin.routeChangePurgedClickOriginCount) or tonumber(clickOrigin and clickOrigin.routeChangePurgedClickOriginCount) or 0
    model.autoRouteLineageContract = storedOrigin and storedOrigin.autoRouteLineageContract or (clickOrigin and clickOrigin.autoRouteLineageContract or nil)
    model.autoRouteLineageChainToken = storedOrigin and storedOrigin.autoRouteLineageChainToken or (clickOrigin and clickOrigin.autoRouteLineageChainToken or nil)
    model.autoRouteLineageRootSessionToken = storedOrigin and storedOrigin.autoRouteLineageRootSessionToken or (clickOrigin and clickOrigin.autoRouteLineageRootSessionToken or nil)
    model.autoRouteLineageParentSessionToken = storedOrigin and storedOrigin.autoRouteLineageParentSessionToken or (clickOrigin and clickOrigin.autoRouteLineageParentSessionToken or nil)
    model.autoRouteLineageDepth = tonumber(storedOrigin and storedOrigin.autoRouteLineageDepth) or tonumber(clickOrigin and clickOrigin.autoRouteLineageDepth)
    model.autoRouteLineageGeneration = tonumber(storedOrigin and storedOrigin.autoRouteLineageGeneration) or tonumber(clickOrigin and clickOrigin.autoRouteLineageGeneration)
    model.autoRouteLineagePredecessorProofToken = storedOrigin and storedOrigin.autoRouteLineagePredecessorProofToken or (clickOrigin and clickOrigin.autoRouteLineagePredecessorProofToken or nil)
    model.autoRouteLineageSessionProofToken = storedOrigin and storedOrigin.autoRouteLineageSessionProofToken or (clickOrigin and clickOrigin.autoRouteLineageSessionProofToken or nil)
    model.autoRouteLineageInterruptionToken = storedOrigin and storedOrigin.autoRouteLineageInterruptionToken or (clickOrigin and clickOrigin.autoRouteLineageInterruptionToken or nil)
    addGate(model, "click-origin", originOK, originState,
        originOK and "single-use Profession Guide click origin consumed" or "current Profession Guide click origin required")

    local singleCraft = craftMode == "one"
    addGate(model, "single-craft-cap", singleCraft,
        singleCraft and "single-craft-only" or "craft-all-not-eligible",
        "alpha75 permits at most one hypothetical native craft")

    local active = self:GetActiveReservation(professionKey)
    local reservationClear = active == nil
    addGate(model, "reservation-clear", reservationClear,
        reservationClear and "no-active-dispatch-reservation" or "dispatch-reservation-active",
        active and active.token or nil)

    local handoffModule = JLP:GetModule("ResearchExecutionIntentHandoff")
    local handoff, handoffState, readinessModel
    local shadowOK, shadowState, shadowReport = false, "shadow-pre-dispatch-not-run", nil
    if model.featureGateEnabled and supported and originOK and singleCraft and reservationClear and handoffModule then
        handoff, handoffState, readinessModel = handoffModule:PrepareHandoff(professionKey, mode, "one", options)
        if handoff then
            shadowOK, shadowState, shadowReport = handoffModule:DispatchShadow(handoff, options)
        else
            shadowState = handoffState or "shadow-pre-dispatch-readiness-blocked"
        end
    end

    local readinessReady = readinessModel ~= nil
        and readinessModel.executionReadinessReady == true
        and readinessModel.state == "execution-readiness-ready"
    model.readinessState = readinessModel and readinessModel.state or handoffState
    addGate(model, "execution-readiness", readinessReady,
        readinessReady and "execution-readiness-current" or tostring(model.readinessState or "execution-readiness-unavailable"),
        readinessReady and "alpha73 10/10 gates current" or "execution-readiness did not produce an intent")

    local shadowReady = shadowOK == true
        and shadowReport ~= nil
        and shadowReport.state == "shadow-pre-dispatch-validated"
        and shadowReport.boundaryValidated == true
        and shadowReport.intentValidated == true
        and shadowReport.singleUseConsumed == true
        and shadowReport.nativeDispatchAttempted == false
    model.shadowState = shadowState
    addGate(model, "shadow-pre-dispatch", shadowReady,
        shadowReady and "shadow-pre-dispatch-current" or tostring(shadowState or "shadow-pre-dispatch-unavailable"),
        shadowReady and "alpha74 Crafting boundary validated current intent" or "shadow boundary did not validate")

    local routeCurrent = readinessModel and readinessModel.consumer
        and readinessModel.consumer.routeAuthorityEnabled == true
        and readinessModel.consumer.consumerAuthorityEnabled == true
        and readinessModel.consumer.plannerEligible == true
        and readinessModel.consumer.executionEligible == false
    addGate(model, "route-authority-current", routeCurrent,
        routeCurrent and "controlled-route-authority-current" or "controlled-route-authority-unavailable",
        "current read authority must remain active")

    local crafting = JLP:GetModule("Crafting")
    local boundaryPresent = crafting and type(crafting.GuardedResearchDispatchBoundary) == "function"
    addGate(model, "guarded-boundary", boundaryPresent,
        boundaryPresent and "guarded-native-dispatch-boundary-present" or "guarded-native-dispatch-boundary-missing",
        "alpha75 boundary is candidate-only and hard-locks native dispatch")

    model.stats.blockedGates = model.stats.totalGates - model.stats.passedGates
    if model.stats.totalGates == 9 and model.stats.passedGates == 9 then
        self.reservationSerial = (tonumber(self.reservationSerial) or 0) + 1
        local snapshotToken = shadowReport.snapshotToken or (readinessModel and readinessModel.snapshotToken)
        local fingerprint = shadowReport.stateFingerprint or (readinessModel and readinessModel.stateFingerprint)
        local recipe = shadowReport.recipe or (readinessModel and readinessModel.recipe)
        local recipeID = tonumber(shadowReport.recipeID) or tonumber(readinessModel and readinessModel.recipeID)
        local rawToken = table.concat({
            professionKey, mode, tostring(snapshotToken or ""), tostring(fingerprint or ""),
            tostring(recipeID or ""), tostring(self.reservationSerial), tostring(nowValue),
        }, "|")
        local token = "exec-reservation-" .. stateHash({rawToken})
        local reservation = {
            contract = self.reservationContract,
            boundaryContract = self.boundaryContract,
            token = token,
            professionKey = professionKey,
            mode = mode,
            craftMode = "one",
            requestedCount = 1,
            currentBuild = readinessModel.currentBuild,
            snapshotToken = snapshotToken,
            stateFingerprint = fingerprint,
            recipe = recipe,
            recipeID = recipeID,
            routeIndex = readinessModel.plan and readinessModel.plan.step and tonumber(readinessModel.plan.step.routeIndex) or nil,
            skillTarget = readinessModel.plan and readinessModel.plan.step and tonumber(readinessModel.plan.step.skillTarget) or nil,
            nativeCraftable = readinessModel.craftabilityStatus == "KNOWN" and tonumber(readinessModel.nativeCraftable) or nil,
            craftabilityStatus = readinessModel.craftabilityStatus,
            craftabilityReason = readinessModel.craftabilityReason,
            recoveryRevision = readinessModel.recoveryRevision,
            sourceReadinessPolicyContract = readinessModel.sourceReadinessPolicyContract,
            sourceReadinessProofContract = readinessModel.sourceReadinessProofContract,
            sourceReadinessFingerprint = readinessModel.sourceReadinessFingerprint,
            targetGUID = readinessModel.targetGUID,
            targetItemID = readinessModel.targetItemID,
            targetValidationSource = readinessModel.targetValidationSource,
            targetLocationKey = readinessModel.targetLocationKey,
            targetProofContract = readinessModel.targetProofContract,
            targetProofFingerprint = readinessModel.targetProofFingerprint,
            clickOriginToken = model.clickOriginToken,
            clickOriginSource = model.clickOriginSource,
            sequenceSessionToken = model.sequenceSessionToken,
            sequenceOrdinal = model.sequenceOrdinal,
            sequenceRequestedCount = model.sequenceRequestedCount,
            sequenceDirectGuideClick = model.sequenceDirectGuideClick == true,
            autoRouteSessionToken = model.autoRouteSessionToken,
            autoRouteOrdinal = model.autoRouteOrdinal,
            autoRouteDirectGuideClick = model.autoRouteDirectGuideClick == true,
            autoRouteDelegationContract = model.autoRouteDelegationContract,
            autoRouteSourceAuthorityContract = model.autoRouteSourceAuthorityContract,
            autoRouteSourcePromotionContract = model.autoRouteSourcePromotionContract,
            autoRouteRecipeID = model.autoRouteRecipeID,
            autoRouteRouteIndex = model.autoRouteRouteIndex,
            autoRouteSkillTarget = model.autoRouteSkillTarget,
            autoRouteSnapshotToken = model.autoRouteSnapshotToken,
            restartCandidateToken = model.restartCandidateToken,
            restartAuthorizationToken = model.restartAuthorizationToken,
            restartedFromSessionToken = model.restartedFromSessionToken,
            restartedFromBoundaryState = model.restartedFromBoundaryState,
            restartedFromBoundaryCategory = model.restartedFromBoundaryCategory,
            restartRouteTransitionKind = model.restartRouteTransitionKind,
            restartRouteChanged = model.restartRouteChanged == true,
            restartPriorRecipeID = model.restartPriorRecipeID,
            restartPriorRouteIndex = model.restartPriorRouteIndex,
            restartCurrentRecipeID = model.restartCurrentRecipeID,
            restartCurrentRouteIndex = model.restartCurrentRouteIndex,
            restartExplicitUserClick = model.restartExplicitUserClick == true,
            restartSourceProofContract = model.restartSourceProofContract,
            restartSourceProofToken = model.restartSourceProofToken,
            restartSourceAutoRouteAuthorityContract = model.restartSourceAutoRouteAuthorityContract,
            restartSourceAutoRoutePromotionContract = model.restartSourceAutoRoutePromotionContract,
            routeChangeBasis = model.routeChangeBasis,
            routeChangeProofToken = model.routeChangeProofToken,
            routeChangePurgeReceiptToken = model.routeChangePurgeReceiptToken,
            routeChangePurgeVerified = model.routeChangePurgeVerified == true,
            routeChangePostPurgeRevalidated = model.routeChangePostPurgeRevalidated == true,
            routeChangePurgedIntentCount = model.routeChangePurgedIntentCount,
            routeChangePurgedReservationCount = model.routeChangePurgedReservationCount,
            routeChangePurgedClickOriginCount = model.routeChangePurgedClickOriginCount,
            autoRouteLineageContract = model.autoRouteLineageContract, autoRouteLineageChainToken = model.autoRouteLineageChainToken, autoRouteLineageRootSessionToken = model.autoRouteLineageRootSessionToken,
            autoRouteLineageParentSessionToken = model.autoRouteLineageParentSessionToken, autoRouteLineageDepth = model.autoRouteLineageDepth, autoRouteLineageGeneration = model.autoRouteLineageGeneration,
            autoRouteLineagePredecessorProofToken = model.autoRouteLineagePredecessorProofToken, autoRouteLineageSessionProofToken = model.autoRouteLineageSessionProofToken, autoRouteLineageInterruptionToken = model.autoRouteLineageInterruptionToken,
            shadowState = shadowState,
            createdAt = nowValue,
            expiresAt = nowValue + self.reservationTTLSeconds,
            singleUse = true,
            candidateEligible = true,
            executionEligible = false,
            executionAuthorityEnabled = false,
            dispatchAllowed = false,
            nativeDispatchAllowed = false,
            persisted = false,
        }
        self.reservations[token] = reservation
        self.activeReservationByProfession[professionKey] = token
        model.state = "execution-authority-eligible"
        model.candidateEligible = true
        model.reservationEligible = true
        model.reservationToken = token
        model.recipe = recipe
        model.recipeID = recipeID
        model.snapshotToken = snapshotToken
        model.stateFingerprint = fingerprint
        model.wouldDispatchCount = 1
        self:_Record(professionKey, model)
        return shallowCopy(reservation), "execution-authority-reservation-prepared", model
    end

    self:_Record(professionKey, model)
    return nil, model.state, model
end

function ResearchExecutionAuthorityGate:ValidateReservation(reservationOrToken, professionKey, mode, options)
    local submitted = type(reservationOrToken) == "table" and reservationOrToken or nil
    local token = submitted and submitted.token or reservationOrToken
    token = tostring(token or "")
    if token == "" then return false, "invalid-execution-reservation", nil, nil end
    local nowValue = monotonicNow()
    local stored = self.reservations[token]
    if type(stored) ~= "table" then
        self:_Sweep(nowValue)
        -- If a submitted wrapper names a profession that currently owns a
        -- different reservation token, treat the mismatched token as tampering
        -- and consume the live candidate as well. This prevents a corrected
        -- replay after token substitution at the final boundary.
        if submitted then
            local submittedKey = normalizeKey(submitted.professionKey)
            local activeToken = submittedKey and self.activeReservationByProfession[submittedKey] or nil
            if activeToken and activeToken ~= token then
                self:RevokeReservation(activeToken, "submitted-token-mismatch")
                return false, "execution-reservation-tampered", nil, nil
            end
        end
        return false, "execution-reservation-expired-or-unknown", nil, nil
    end
    if tonumber(stored.expiresAt) and nowValue > tonumber(stored.expiresAt) then
        self:RevokeReservation(token, "expired")
        return false, "execution-reservation-expired-or-unknown", nil, nil
    end

    professionKey = normalizeKey(professionKey or stored.professionKey)
    mode = normalizeMode(mode or stored.mode)
    if submitted then
        local exact = submitted.contract == stored.contract
            and submitted.boundaryContract == stored.boundaryContract
            and normalizeKey(submitted.professionKey) == normalizeKey(stored.professionKey)
            and normalizeMode(submitted.mode) == normalizeMode(stored.mode)
            and tostring(submitted.craftMode or "") == tostring(stored.craftMode or "")
            and tonumber(submitted.requestedCount) == tonumber(stored.requestedCount)
            and tostring(submitted.snapshotToken or "") == tostring(stored.snapshotToken or "")
            and tostring(submitted.stateFingerprint or "") == tostring(stored.stateFingerprint or "")
            and tostring(submitted.recipe or "") == tostring(stored.recipe or "")
            and tonumber(submitted.recipeID) == tonumber(stored.recipeID)
            and tonumber(submitted.routeIndex) == tonumber(stored.routeIndex)
            and tonumber(submitted.skillTarget) == tonumber(stored.skillTarget)
            and tostring(submitted.sourceReadinessPolicyContract or "") == tostring(stored.sourceReadinessPolicyContract or "")
            and tostring(submitted.sourceReadinessProofContract or "") == tostring(stored.sourceReadinessProofContract or "")
            and tostring(submitted.sourceReadinessFingerprint or "") == tostring(stored.sourceReadinessFingerprint or "")
            and tostring(submitted.targetGUID or "") == tostring(stored.targetGUID or "")
            and tonumber(submitted.targetItemID) == tonumber(stored.targetItemID)
            and tostring(submitted.targetValidationSource or "") == tostring(stored.targetValidationSource or "")
            and tostring(submitted.targetLocationKey or "") == tostring(stored.targetLocationKey or "")
            and tostring(submitted.targetProofContract or "") == tostring(stored.targetProofContract or "")
            and tostring(submitted.targetProofFingerprint or "") == tostring(stored.targetProofFingerprint or "")
            and tostring(submitted.sequenceSessionToken or "") == tostring(stored.sequenceSessionToken or "")
            and tonumber(submitted.sequenceOrdinal) == tonumber(stored.sequenceOrdinal)
            and tonumber(submitted.sequenceRequestedCount) == tonumber(stored.sequenceRequestedCount)
            and (submitted.sequenceDirectGuideClick == true) == (stored.sequenceDirectGuideClick == true)
            and tostring(submitted.autoRouteSessionToken or "") == tostring(stored.autoRouteSessionToken or "")
            and tonumber(submitted.autoRouteOrdinal) == tonumber(stored.autoRouteOrdinal)
            and (submitted.autoRouteDirectGuideClick == true) == (stored.autoRouteDirectGuideClick == true)
            and tostring(submitted.autoRouteDelegationContract or "") == tostring(stored.autoRouteDelegationContract or "")
            and tostring(submitted.autoRouteSourceAuthorityContract or "") == tostring(stored.autoRouteSourceAuthorityContract or "")
            and tostring(submitted.autoRouteSourcePromotionContract or "") == tostring(stored.autoRouteSourcePromotionContract or "")
            and tonumber(submitted.autoRouteRecipeID) == tonumber(stored.autoRouteRecipeID)
            and tonumber(submitted.autoRouteRouteIndex) == tonumber(stored.autoRouteRouteIndex)
            and tonumber(submitted.autoRouteSkillTarget) == tonumber(stored.autoRouteSkillTarget)
            and tostring(submitted.autoRouteSnapshotToken or "") == tostring(stored.autoRouteSnapshotToken or "")
            and tostring(submitted.restartCandidateToken or "") == tostring(stored.restartCandidateToken or "")
            and tostring(submitted.restartAuthorizationToken or "") == tostring(stored.restartAuthorizationToken or "")
            and tostring(submitted.restartedFromSessionToken or "") == tostring(stored.restartedFromSessionToken or "")
            and tostring(submitted.restartedFromBoundaryState or "") == tostring(stored.restartedFromBoundaryState or "")
            and tostring(submitted.restartedFromBoundaryCategory or "") == tostring(stored.restartedFromBoundaryCategory or "")
            and tostring(submitted.restartRouteTransitionKind or "") == tostring(stored.restartRouteTransitionKind or "")
            and (submitted.restartRouteChanged == true) == (stored.restartRouteChanged == true)
            and tonumber(submitted.restartPriorRecipeID) == tonumber(stored.restartPriorRecipeID)
            and tonumber(submitted.restartPriorRouteIndex) == tonumber(stored.restartPriorRouteIndex)
            and tonumber(submitted.restartCurrentRecipeID) == tonumber(stored.restartCurrentRecipeID)
            and tonumber(submitted.restartCurrentRouteIndex) == tonumber(stored.restartCurrentRouteIndex)
            and (submitted.restartExplicitUserClick == true) == (stored.restartExplicitUserClick == true)
            and tostring(submitted.restartSourceProofContract or "") == tostring(stored.restartSourceProofContract or "")
            and tostring(submitted.restartSourceProofToken or "") == tostring(stored.restartSourceProofToken or "")
            and tostring(submitted.restartSourceAutoRouteAuthorityContract or "") == tostring(stored.restartSourceAutoRouteAuthorityContract or "")
            and tostring(submitted.restartSourceAutoRoutePromotionContract or "") == tostring(stored.restartSourceAutoRoutePromotionContract or "")
            and tostring(submitted.routeChangeBasis or "") == tostring(stored.routeChangeBasis or "")
            and tostring(submitted.routeChangeProofToken or "") == tostring(stored.routeChangeProofToken or "")
            and tostring(submitted.routeChangePurgeReceiptToken or "") == tostring(stored.routeChangePurgeReceiptToken or "")
            and (submitted.routeChangePurgeVerified == true) == (stored.routeChangePurgeVerified == true)
            and (submitted.routeChangePostPurgeRevalidated == true) == (stored.routeChangePostPurgeRevalidated == true)
            and tonumber(submitted.routeChangePurgedIntentCount or 0) == tonumber(stored.routeChangePurgedIntentCount or 0)
            and tonumber(submitted.routeChangePurgedReservationCount or 0) == tonumber(stored.routeChangePurgedReservationCount or 0)
            and tonumber(submitted.routeChangePurgedClickOriginCount or 0) == tonumber(stored.routeChangePurgedClickOriginCount or 0)
            and tostring(submitted.autoRouteLineageContract or "") == tostring(stored.autoRouteLineageContract or "")
            and tostring(submitted.autoRouteLineageChainToken or "") == tostring(stored.autoRouteLineageChainToken or "")
            and tostring(submitted.autoRouteLineageRootSessionToken or "") == tostring(stored.autoRouteLineageRootSessionToken or "")
            and tostring(submitted.autoRouteLineageParentSessionToken or "") == tostring(stored.autoRouteLineageParentSessionToken or "")
            and tonumber(submitted.autoRouteLineageDepth) == tonumber(stored.autoRouteLineageDepth)
            and tostring(submitted.autoRouteLineagePredecessorProofToken or "") == tostring(stored.autoRouteLineagePredecessorProofToken or "")
            and tostring(submitted.autoRouteLineageSessionProofToken or "") == tostring(stored.autoRouteLineageSessionProofToken or "")
            and tostring(submitted.autoRouteLineageInterruptionToken or "") == tostring(stored.autoRouteLineageInterruptionToken or "")
        if not exact then
            return false, "execution-reservation-tampered", nil, shallowCopy(stored)
        end
    end
    if professionKey ~= normalizeKey(stored.professionKey) then
        return false, "execution-reservation-profession-mismatch", nil, shallowCopy(stored)
    end
    if mode ~= normalizeMode(stored.mode) then
        return false, "execution-reservation-mode-mismatch", nil, shallowCopy(stored)
    end
    if not featureEnabled() then
        return false, "execution-reservation-revoked", nil, shallowCopy(stored)
    end

    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local current = readiness and readiness.Evaluate and readiness:Evaluate(professionKey, mode, options) or nil
    if not current or current.executionReadinessReady ~= true then
        return false, "execution-reservation-revoked", current, shallowCopy(stored)
    end
    local same = tonumber(stored.currentBuild) == tonumber(current.currentBuild)
        and tostring(stored.snapshotToken or "") == tostring(current.snapshotToken or "")
        and tostring(stored.stateFingerprint or "") == tostring(current.stateFingerprint or "")
        and tostring(stored.recipe or "") == tostring(current.recipe or "")
        and tonumber(stored.recipeID) == tonumber(current.recipeID)
        and tonumber(stored.routeIndex) == tonumber(current.plan and current.plan.step and current.plan.step.routeIndex)
        and tonumber(stored.skillTarget) == tonumber(current.plan and current.plan.step and current.plan.step.skillTarget)
        and tostring(stored.sourceReadinessPolicyContract or "") == tostring(current.sourceReadinessPolicyContract or "")
        and tostring(stored.sourceReadinessProofContract or "") == tostring(current.sourceReadinessProofContract or "")
        and tostring(stored.sourceReadinessFingerprint or "") == tostring(current.sourceReadinessFingerprint or "")
        and tostring(stored.targetGUID or "") == tostring(current.targetGUID or "")
        and tonumber(stored.targetItemID) == tonumber(current.targetItemID)
        and tostring(stored.targetValidationSource or "") == tostring(current.targetValidationSource or "")
        and tostring(stored.targetLocationKey or "") == tostring(current.targetLocationKey or "")
        and tostring(stored.targetProofContract or "") == tostring(current.targetProofContract or "")
        and tostring(stored.targetProofFingerprint or "") == tostring(current.targetProofFingerprint or "")
        and tonumber(stored.requestedCount) == 1
        and tostring(stored.craftMode or "") == "one"
        and stored.craftabilityStatus == "KNOWN" and current.craftabilityStatus == "KNOWN"
        and tonumber(stored.nativeCraftable) ~= nil
        and tonumber(stored.nativeCraftable) == tonumber(current.nativeCraftable)
        and tonumber(current.nativeCraftable) >= 1
        and current.consumer and current.consumer.routeAuthorityEnabled == true
    if not same then
        return false, "execution-reservation-stale", current, shallowCopy(stored)
    end
    return true, "execution-reservation-current", current, shallowCopy(stored)
end

function ResearchExecutionAuthorityGate:RevokeReservation(reservationOrToken, reason)
    local token = type(reservationOrToken) == "table" and reservationOrToken.token or reservationOrToken
    token = tostring(token or "")
    if token == "" then return false end
    local stored = self.reservations[token]
    if not stored then return false end
    self.reservations[token] = nil
    local key = normalizeKey(stored.professionKey)
    if key and self.activeReservationByProfession[key] == token then
        self.activeReservationByProfession[key] = nil
    end
    return true, reason or "revoked"
end

function ResearchExecutionAuthorityGate:RevokeAllReservations(reason)
    for token in pairs(self.reservations or {}) do
        self:RevokeReservation(token, reason)
    end
    return true
end

function ResearchExecutionAuthorityGate:DispatchGuarded(reservation, options)
    local crafting = JLP:GetModule("Crafting")
    if not crafting or not crafting.GuardedResearchDispatchBoundary then
        local report = {
            contract = self.contract,
            boundaryContract = self.boundaryContract,
            professionKey = reservation and reservation.professionKey or nil,
            state = "guarded-native-dispatch-boundary-unavailable",
            candidateEligible = false,
            executionEligible = false,
            dispatchAllowed = false,
            nativeDispatchAllowed = false,
            nativeDispatchAttempted = false,
            persisted = false,
        }
        self:_Record(report.professionKey, report)
        return false, report.state, report
    end
    local ok, state, report = crafting:GuardedResearchDispatchBoundary(reservation, options)
    report = type(report) == "table" and report or {}
    report.contract = self.contract
    report.boundaryContract = self.boundaryContract
    report.state = state or report.state or (ok and "guarded-native-dispatch-eligible" or "guarded-native-dispatch-blocked")
    report.executionEligible = false
    report.dispatchAllowed = false
    report.nativeDispatchAllowed = false
    report.nativeDispatchAttempted = false
    report.persisted = false
    self:_Record(report.professionKey or (reservation and reservation.professionKey), report)
    return ok and true or false, report.state, report
end

function ResearchExecutionAuthorityGate:Request(professionKey, mode, craftMode, clickOrigin, options)
    local reservation, state = self:PrepareReservation(professionKey, mode, craftMode, clickOrigin, options)
    if not reservation then return false, state, self:GetLast(professionKey) end
    return self:DispatchGuarded(reservation, options)
end

function ResearchExecutionAuthorityGate:CountArtifactsForProfession(professionKey)
    professionKey = normalizeKey(professionKey)
    local result = { reservations=0, clickOrigins=0, activeReservation=false }
    if not professionKey then return result end
    for _, reservation in pairs(self.reservations or {}) do
        if normalizeKey(reservation and reservation.professionKey) == professionKey then result.reservations = result.reservations + 1 end
    end
    for _, origin in pairs(self.clickOrigins or {}) do
        if normalizeKey(origin and origin.professionKey) == professionKey then result.clickOrigins = result.clickOrigins + 1 end
    end
    local activeToken = self.activeReservationByProfession[professionKey]
    result.activeReservation = activeToken ~= nil and self.reservations[activeToken] ~= nil
    return result
end

function ResearchExecutionAuthorityGate:InvalidateProfession(professionKey, trigger)
    professionKey = normalizeKey(professionKey)
    local result = { reservations=0, clickOrigins=0, reason=trigger or "state-invalidated" }
    if not professionKey then return result end
    local reservationTokens = {}
    for token, reservation in pairs(self.reservations or {}) do
        if normalizeKey(reservation and reservation.professionKey) == professionKey then reservationTokens[#reservationTokens + 1] = token end
    end
    for _, token in ipairs(reservationTokens) do
        if self:RevokeReservation(token, trigger or "state-invalidated") then result.reservations = result.reservations + 1 end
    end
    for token, origin in pairs(self.clickOrigins or {}) do
        if normalizeKey(origin and origin.professionKey) == professionKey then
            self.clickOrigins[token] = nil
            result.clickOrigins = result.clickOrigins + 1
        end
    end
    return result
end

function ResearchExecutionAuthorityGate:Invalidate(trigger)
    self:RevokeAllReservations(trigger or "state-invalidated")
    self.clickOrigins = {}
    return true
end

function ResearchExecutionAuthorityGate:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        for _, eventName in ipairs(INVALIDATION_EVENTS) do
            JLP.EventBus:On(eventName, function() self:Invalidate(eventName) end)
        end
    end
    return true
end

function ResearchExecutionAuthorityGate:GetLast(professionKey)
    professionKey = normalizeKey(professionKey)
    local row = professionKey and self.lastByProfession[professionKey] or nil
    return row and shallowCopy(row) or nil
end

function ResearchExecutionAuthorityGate:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local ready = readiness and readiness.Evaluate and readiness:Evaluate(professionKey, mode, options) or nil
    local active = self:GetActiveReservation(professionKey)
    local last = self:GetLast(professionKey)
    local lines = {
        "CONTROLLED EXECUTION AUTHORITY / GUARDED ELIGIBILITY",
        professionKey .. " / " .. mode,
        "Feature gate: " .. (featureEnabled() and "enabled" or "disabled"),
        "Execution readiness: " .. tostring(ready and ready.state or "unavailable"),
        "Active reservation: " .. tostring(active and active.token or "none"),
        "Last eligibility/boundary state: " .. tostring(last and last.state or "none"),
        "Click origin: Profession Guide · in-memory · single-use · TTL " .. tostring(self.clickOriginTTLSeconds) .. "s",
        "Reservation: in-memory · single-use · TTL " .. tostring(self.reservationTTLSeconds) .. "s · max count 1",
        "Execution authority: disabled",
        "Native dispatch authority: disabled",
        "Native dispatch hard lock: alpha75",
        "Persistence: none",
    }
    if last then
        lines[#lines + 1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines + 1] = "Candidate eligible: " .. tostring(last.candidateEligible == true and "yes" or "no")
        lines[#lines + 1] = "Would dispatch: " .. tostring(last.wouldDispatchCount or 0)
        if last.blockedGate then lines[#lines + 1] = "Blocked gate: " .. tostring(last.blockedGate) .. " · " .. tostring(last.blockedState or "blocked") end
    end
    return table.concat(lines, "\n")
end

function ResearchExecutionAuthorityGate:Validate()
    local errors, warnings = {}, {}
    if self.executionEligible ~= false or self.executionAuthorityEnabled ~= false or self.dispatchAllowed ~= false or self.nativeDispatchAllowed ~= false or self.persisted ~= false then
        errors[#errors + 1] = "research execution-authority eligibility boundary invalid"
    end
    for _, name in ipairs({"ResearchExecutionReadiness", "ResearchExecutionIntentHandoff", "ResearchRouteAuthorityBridge", "Crafting"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "research execution-authority dependency missing: " .. name end
    end
    if tonumber(self.reservationTTLSeconds) == nil or self.reservationTTLSeconds > 5 then
        errors[#errors + 1] = "research execution-authority reservation TTL exceeds alpha75 limit"
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchExecutionAuthorityGate", ResearchExecutionAuthorityGate)
