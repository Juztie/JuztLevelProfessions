local _, JLP = ...

-- Alpha80 turns the guarded native Craft One path into a tightly bounded
-- sequential orchestrator. One explicit Profession Guide click authorizes an
-- in-memory sequence of at most three crafts, but every ordinal still traverses
-- the complete alpha73 -> alpha79 chain as its own single-use Craft One.
-- No CraftRecipe(recipeID, N) call is permitted, no session is persisted, and a
-- reload may settle an already-dispatched craft but never auto-resume the batch.
-- Alpha81 adds a separate stop-policy classifier so post-settlement states that
-- are not immediately craftable terminate as explicit Guide handoffs instead of
-- falling through to a generic dispatch rejection.
local ResearchBoundedSequentialCraft = {
    contract = "bounded-sequential-native-craft-orchestrator-v1",
    sessionContract = "research-bounded-sequential-session-v1",
    delegationContract = "research-sequential-dispatch-delegation-v1",
    authority = "feature-gated-user-click-bounded-sequential-craft-one-v1",
    persisted = false,
    automaticResume = false,
    maxCraftsHard = 3,
    minCrafts = 2,
    serial = 0,
    sessions = {},
    lastByProfession = {},
    initialized = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(value)
    return value == "aggressive" and "aggressive" or "normal"
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

local function featureProfile()
    local profile = JLP.DB and JLP.DB.profile
    return profile and profile.researchSequentialExecutionAuthority or nil
end

local function terminalStatus(status)
    status = tostring(status or "")
    return status == "success" or status == "failed" or status == "timeout" or status == "aborted_unknown"
end

function ResearchBoundedSequentialCraft:IsFeatureEnabled()
    local profile = featureProfile()
    return profile and profile.enabled == true or false
end

function ResearchBoundedSequentialCraft:GetConfiguredLimit()
    local profile = featureProfile()
    local requested = tonumber(profile and profile.maxCrafts) or self.maxCraftsHard
    requested = math.floor(requested)
    if requested < self.minCrafts then requested = self.minCrafts end
    if requested > self.maxCraftsHard then requested = self.maxCraftsHard end
    return requested
end

function ResearchBoundedSequentialCraft:IsEffectiveEnabled()
    if not self:IsFeatureEnabled() then return false end
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local native = JLP:GetModule("ResearchNativeExecutionAuthority")
    return eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()
        and native and native.IsEffectiveEnabled and native:IsEffectiveEnabled()
        or false
end

function ResearchBoundedSequentialCraft:_Emit(report)
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("RESEARCH_BOUNDED_SEQUENCE_UPDATED", shallowCopy(report))
    end
end

function ResearchBoundedSequentialCraft:_Snapshot(session, override)
    local report = {
        contract = self.contract,
        sessionContract = self.sessionContract,
        delegationContract = self.delegationContract,
        authority = self.authority,
        professionKey = session and session.professionKey or nil,
        mode = session and session.mode or nil,
        sessionToken = session and session.token or nil,
        state = session and session.state or "bounded-sequence-unavailable",
        requestedCount = session and tonumber(session.requestedCount) or 0,
        dispatchedCount = session and tonumber(session.dispatchedCount) or 0,
        settledCount = session and tonumber(session.settledCount) or 0,
        currentOrdinal = session and tonumber(session.currentOrdinal) or nil,
        currentLedgerID = session and session.currentLedgerID or nil,
        currentRecipe = session and session.currentRecipe or nil,
        currentRecipeID = session and tonumber(session.currentRecipeID) or nil,
        currentRouteIndex = session and tonumber(session.currentRouteIndex) or nil,
        currentSnapshotToken = session and session.currentSnapshotToken or nil,
        initialRecipe = session and session.initialRecipe or nil,
        initialRecipeID = session and tonumber(session.initialRecipeID) or nil,
        initialRouteIndex = session and tonumber(session.initialRouteIndex) or nil,
        initialSnapshotToken = session and session.initialSnapshotToken or nil,
        routeTransitions = session and tonumber(session.routeTransitions) or 0,
        cancelRequested = session and session.cancelRequested == true or false,
        stopReason = session and session.stopReason or nil,
        stopBoundary = session and session.stopBoundary or nil,
        stopCategory = session and session.stopBoundary and session.stopBoundary.category or nil,
        nextActionText = session and session.stopBoundary and session.stopBoundary.nextActionText or nil,
        nextActionLabel = session and session.stopBoundary and session.stopBoundary.label or nil,
        active = session and session.active == true or false,
        persisted = false,
        automaticResume = false,
        nativeBatchDispatch = false,
        perCraftRevalidation = true,
        restartCandidateToken = session and session.restartCandidateToken or nil,
        restartAuthorizationToken = session and session.restartAuthorizationToken or nil,
        restartedFromSessionToken = session and session.restartedFromSessionToken or nil,
        restartedFromBoundaryState = session and session.restartedFromBoundaryState or nil,
        restartedFromBoundaryCategory = session and session.restartedFromBoundaryCategory or nil,
        restartRouteTransitionKind = session and session.restartRouteTransitionKind or nil,
        restartRouteChanged = session and session.restartRouteChanged == true or false,
        restartPriorRecipeID = session and tonumber(session.restartPriorRecipeID) or nil,
        restartPriorRouteIndex = session and tonumber(session.restartPriorRouteIndex) or nil,
        restartCurrentRecipeID = session and tonumber(session.restartCurrentRecipeID) or nil,
        restartCurrentRouteIndex = session and tonumber(session.restartCurrentRouteIndex) or nil,
        restartExplicitUserClick = session and session.restartExplicitUserClick == true or false,
    }
    for key, value in pairs(override or {}) do report[key] = value end
    return report
end

function ResearchBoundedSequentialCraft:_Record(session, override)
    local report = self:_Snapshot(session, override)
    local key = normalizeKey(report.professionKey)
    if key then self.lastByProfession[key] = shallowCopy(report) end
    self:_Emit(report)
    return report
end

function ResearchBoundedSequentialCraft:SetFeatureEnabled(enabled)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    if enabled == true then
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        local native = JLP:GetModule("ResearchNativeExecutionAuthority")
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
        if not (native and native.IsEffectiveEnabled and native:IsEffectiveEnabled()) then
            return false, "native-execution-authority-gate-disabled"
        end
    end
    profile.enabled = enabled == true
    if not profile.enabled then self:CancelAll("sequential-feature-gate-disabled") end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_SEQUENTIAL_EXECUTION_AUTHORITY_UPDATED", { enabled=profile.enabled })
        JLP.EventBus:Emit("SETTINGS_CHANGED", "researchSequentialExecutionAuthority", profile.enabled)
    end
    return true, profile.enabled and "enabled" or "disabled"
end

function ResearchBoundedSequentialCraft:SetConfiguredLimit(value)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    value = math.floor(tonumber(value) or 0)
    if value < self.minCrafts or value > self.maxCraftsHard then
        return false, "sequential-limit-out-of-range"
    end
    profile.maxCrafts = value
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("SETTINGS_CHANGED", "researchSequentialExecutionAuthority.maxCrafts", value)
    end
    return true, value
end

function ResearchBoundedSequentialCraft:GetSession(professionKey)
    local row = self.sessions[normalizeKey(professionKey)]
    return row and self:_Snapshot(row) or nil
end

function ResearchBoundedSequentialCraft:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and shallowCopy(row) or nil
end

function ResearchBoundedSequentialCraft:_Close(session, state, reason)
    if not session then return nil end
    session.state = state or "bounded-sequence-stopped"
    session.stopReason = reason
    session.active = false
    session.finishedAt = monotonicNow()
    local key = normalizeKey(session.professionKey)
    if key and self.sessions[key] == session then self.sessions[key] = nil end
    return self:_Record(session)
end

function ResearchBoundedSequentialCraft:Cancel(professionKey, reason)
    professionKey = normalizeKey(professionKey)
    local session = professionKey and self.sessions[professionKey] or nil
    if not session then return false, "bounded-sequence-not-active" end
    session.cancelRequested = true
    session.cancelReason = reason or "user-cancelled"
    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and crafting.pendingCraft or nil
    local provenance = pending and pending.authorityProvenance or nil
    local inFlight = pending and provenance and tostring(provenance.sequenceSessionToken or "") == tostring(session.token or "")
    if inFlight then
        session.state = "bounded-sequence-stopping-after-current"
        self:_Record(session)
        return true, session.state
    end
    self:_Close(session, "bounded-sequence-cancelled", session.cancelReason)
    return true, "bounded-sequence-cancelled"
end

function ResearchBoundedSequentialCraft:CancelAll(reason)
    local keys = {}
    for key in pairs(self.sessions or {}) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do self:Cancel(key, reason or "cancel-all") end
    return true
end

function ResearchBoundedSequentialCraft:ValidateDelegation(delegation, professionKey, mode)
    if type(delegation) ~= "table" or delegation.contract ~= self.delegationContract then
        return false, "bounded-sequence-delegation-invalid"
    end
    professionKey = normalizeKey(professionKey or delegation.professionKey)
    mode = normalizeMode(mode or delegation.mode)
    local session = professionKey and self.sessions[professionKey] or nil
    if not session or session.active ~= true then return false, "bounded-sequence-session-expired-or-unknown" end
    if tostring(delegation.sessionToken or "") ~= tostring(session.token or "") then
        return false, "bounded-sequence-session-token-mismatch"
    end
    if mode ~= normalizeMode(session.mode) then return false, "bounded-sequence-mode-mismatch" end
    local ordinal = tonumber(delegation.ordinal)
    local expected = (tonumber(session.settledCount) or 0) + 1
    if tonumber(delegation.requestedCount) ~= tonumber(session.requestedCount) then
        return false, "bounded-sequence-request-count-mismatch"
    end
    if ordinal ~= expected or ordinal < 1 or ordinal > tonumber(session.requestedCount or 0) then
        return false, "bounded-sequence-ordinal-mismatch"
    end
    local shouldBeDirect = ordinal == 1
    if (delegation.directGuideClick == true) ~= shouldBeDirect then
        return false, "bounded-sequence-origin-kind-mismatch"
    end
    if tostring(delegation.restartCandidateToken or "") ~= tostring(session.restartCandidateToken or "")
        or tostring(delegation.restartAuthorizationToken or "") ~= tostring(session.restartAuthorizationToken or "")
        or tostring(delegation.restartedFromSessionToken or "") ~= tostring(session.restartedFromSessionToken or "")
        or tostring(delegation.restartedFromBoundaryState or "") ~= tostring(session.restartedFromBoundaryState or "")
        or tostring(delegation.restartedFromBoundaryCategory or "") ~= tostring(session.restartedFromBoundaryCategory or "")
        or tostring(delegation.restartRouteTransitionKind or "") ~= tostring(session.restartRouteTransitionKind or "")
        or (delegation.restartRouteChanged == true) ~= (session.restartRouteChanged == true)
        or tonumber(delegation.restartPriorRecipeID) ~= tonumber(session.restartPriorRecipeID)
        or tonumber(delegation.restartPriorRouteIndex) ~= tonumber(session.restartPriorRouteIndex)
        or tonumber(delegation.restartCurrentRecipeID) ~= tonumber(session.restartCurrentRecipeID)
        or tonumber(delegation.restartCurrentRouteIndex) ~= tonumber(session.restartCurrentRouteIndex)
        or (delegation.restartExplicitUserClick == true) ~= (session.restartExplicitUserClick == true) then
        return false, "bounded-sequence-restart-provenance-mismatch"
    end
    if session.cancelRequested then return false, "bounded-sequence-cancel-requested" end
    if not self:IsEffectiveEnabled() then return false, "bounded-sequence-authority-disabled" end
    return true, "bounded-sequence-delegation-current", session
end

function ResearchBoundedSequentialCraft:_CreateDelegation(session, ordinal, direct)
    return {
        contract = self.delegationContract,
        sessionToken = session.token,
        professionKey = session.professionKey,
        mode = session.mode,
        ordinal = ordinal,
        requestedCount = session.requestedCount,
        directGuideClick = direct == true,
        source = direct and "profession-guide" or "bounded-sequential-orchestrator",
        restartCandidateToken = session.restartCandidateToken,
        restartAuthorizationToken = session.restartAuthorizationToken,
        restartedFromSessionToken = session.restartedFromSessionToken,
        restartedFromBoundaryState = session.restartedFromBoundaryState,
        restartedFromBoundaryCategory = session.restartedFromBoundaryCategory,
        restartRouteTransitionKind = session.restartRouteTransitionKind,
        restartRouteChanged = session.restartRouteChanged == true,
        restartPriorRecipeID = session.restartPriorRecipeID,
        restartPriorRouteIndex = session.restartPriorRouteIndex,
        restartCurrentRecipeID = session.restartCurrentRecipeID,
        restartCurrentRouteIndex = session.restartCurrentRouteIndex,
        restartExplicitUserClick = session.restartExplicitUserClick == true,
        persisted = false,
    }
end

function ResearchBoundedSequentialCraft:_DispatchNext(session, direct)
    if not session or session.active ~= true then return false, "bounded-sequence-not-active" end
    if session.cancelRequested then
        self:_Close(session, "bounded-sequence-cancelled", session.cancelReason or "cancel-requested")
        return false, "bounded-sequence-cancelled"
    end
    if not self:IsEffectiveEnabled() then
        self:_Close(session, "bounded-sequence-stopped-authority-disabled", "sequential-or-native-authority-disabled")
        return false, "bounded-sequence-stopped-authority-disabled"
    end

    local ordinal = (tonumber(session.settledCount) or 0) + 1
    if ordinal > tonumber(session.requestedCount or 0) then
        self:_Close(session, "bounded-sequence-complete", "requested-count-settled")
        return true, "bounded-sequence-complete"
    end

    local gate = JLP:GetModule("ResearchExecutionAuthorityGate")
    local native = JLP:GetModule("ResearchNativeExecutionAuthority")
    if not gate or not gate.BeginSequentialClickOrigin or not native or not native.Request then
        self:_Close(session, "bounded-sequence-stopped-dependency-unavailable", "execution-boundary-unavailable")
        return false, "bounded-sequence-stopped-dependency-unavailable"
    end

    local delegation = self:_CreateDelegation(session, ordinal, direct)
    local origin, originState = gate:BeginSequentialClickOrigin(session.professionKey, session.mode, delegation)
    if not origin then
        self:_Close(session, "bounded-sequence-stopped-origin-rejected", originState)
        return false, originState
    end

    session.currentOrdinal = ordinal
    session.state = "bounded-sequence-authorizing-craft"
    session.dispatchInProgress = true
    session.dispatchedCount = math.max(tonumber(session.dispatchedCount) or 0, ordinal)
    session.currentOriginToken = origin.token
    session.lastDelegationSource = delegation.source
    self:_Record(session, { originState=originState })

    local ok, state, report = native:Request(session.professionKey, session.mode, origin, session.options)
    session.dispatchInProgress = false
    session.currentLedgerID = report and (report.ledgerID or report.transactionID) or session.currentLedgerID
    session.currentRecipe = report and report.recipe or session.currentRecipe
    session.currentRecipeID = tonumber(report and report.recipeID) or session.currentRecipeID
    session.currentSnapshotToken = report and report.snapshotToken or session.currentSnapshotToken

    if not ok then
        if session.active then self:_Close(session, "bounded-sequence-stopped-dispatch-rejected", state) end
        return false, state, report
    end

    if session.active and (tonumber(session.settledCount) or 0) < ordinal then
        session.state = "bounded-sequence-awaiting-settlement"
        self:_Record(session, {
            dispatchState=state,
            nativeDispatchAttempted=report and report.nativeDispatchAttempted == true or false,
            nativeDispatchAccepted=report and report.nativeDispatchAccepted == true or false,
        })
    end

    if session.active and session.continuePending then
        session.continuePending = false
        return self:_Continue(session)
    end
    return true, state, report
end

function ResearchBoundedSequentialCraft:_StopForBoundary(session, boundary)
    if not session or type(boundary) ~= "table" or boundary.terminal ~= true then return false end
    session.stopBoundary = {
        contract = boundary.boundaryContract,
        state = boundary.state,
        category = boundary.category,
        label = boundary.label,
        nextActionText = boundary.nextActionText,
        detail = boundary.detail,
        actionKind = boundary.actionKind,
        blockedGate = boundary.blockedGate,
        blockedState = boundary.blockedState,
        consumerState = boundary.consumerState,
        sourceAuthorityState = boundary.sourceAuthorityState,
        snapshotToken = boundary.snapshotToken,
        stateFingerprint = boundary.stateFingerprint,
        recipe = boundary.recipe,
        recipeID = boundary.recipeID,
        persisted = false,
    }
    self:_Close(session, "bounded-sequence-stopped-boundary", boundary.state or boundary.category or "non-craft-boundary")
    return true
end

function ResearchBoundedSequentialCraft:_CurrentConsumer(session)
    local bridge = JLP:GetModule("ResearchPlannerConsumerBridge")
    return bridge and bridge.Build and bridge:Build(session.professionKey, session.mode, session.options) or nil
end

function ResearchBoundedSequentialCraft:_Continue(session)
    if not session or session.active ~= true then return false, "bounded-sequence-not-active" end
    if session.cancelRequested then
        self:_Close(session, "bounded-sequence-cancelled-after-settlement", session.cancelReason or "cancel-requested")
        return false, "bounded-sequence-cancelled-after-settlement"
    end
    if (tonumber(session.settledCount) or 0) >= tonumber(session.requestedCount or 0) then
        self:_Close(session, "bounded-sequence-complete", "requested-count-settled")
        return true, "bounded-sequence-complete"
    end
    if not self:IsEffectiveEnabled() then
        self:_Close(session, "bounded-sequence-stopped-authority-disabled", "authority-disabled-after-settlement")
        return false, "bounded-sequence-stopped-authority-disabled"
    end

    session.state = "bounded-sequence-revalidating"
    local stopPolicy = JLP:GetModule("ResearchSequentialStopPolicy")
    local boundary, consumer
    if stopPolicy and stopPolicy.Evaluate then
        boundary, consumer = stopPolicy:Evaluate(session.professionKey, session.mode, session.options)
        if boundary and boundary.terminal == true then
            self:_StopForBoundary(session, boundary)
            return false, "bounded-sequence-stopped-boundary", boundary
        end
    end
    consumer = consumer or self:_CurrentConsumer(session)
    if not consumer or consumer.state ~= "consumer-authority-active" or consumer.consumerAuthorityEnabled ~= true
        or consumer.routeAuthorityEnabled ~= true or consumer.plannerEligible ~= true or consumer.executionEligible ~= false then
        self:_Close(session, "bounded-sequence-stopped-revalidation", consumer and consumer.state or "consumer-authority-unavailable")
        return false, "bounded-sequence-stopped-revalidation"
    end

    local plan = consumer.plan
    local step = plan and plan.step or nil
    local recipe = step and step.recipe or nil
    local recipeID = step and (tonumber(step.recipeID) or tonumber(step.rawStep and step.rawStep.recipeID) or tonumber(step.datasetStep and step.datasetStep.recipeID)) or nil
    local routeIndex = step and tonumber(step.routeIndex) or nil
    local previousRoute = tonumber(session.currentRouteIndex)
    local previousRecipeID = tonumber(session.currentRecipeID)
    local routeChanged = previousRoute ~= nil and routeIndex ~= nil and previousRoute ~= routeIndex
    local recipeChanged = previousRecipeID ~= nil and recipeID ~= nil and previousRecipeID ~= recipeID

    if routeChanged or recipeChanged then
        local transition = JLP:GetModule("ResearchNativeStepTransition")
        local lastTransition = transition and transition.GetLast and transition:GetLast(session.professionKey) or nil
        local handoffReady = lastTransition and lastTransition.transitionReady == true
            and tostring(lastTransition.ledgerID or "") == tostring(session.lastSettledLedgerID or "")
            and tonumber(lastTransition.toRouteIndex) == tonumber(routeIndex)
            and tonumber(lastTransition.toRecipeID) == tonumber(recipeID)
        if not handoffReady then
            self:_Close(session, "bounded-sequence-stopped-route-handoff-not-ready", lastTransition and lastTransition.state or "route-step-handoff-unavailable")
            return false, "bounded-sequence-stopped-route-handoff-not-ready"
        end
        session.routeTransitions = (tonumber(session.routeTransitions) or 0) + 1
    end

    session.currentRecipe = recipe
    session.currentRecipeID = recipeID
    session.currentRouteIndex = routeIndex
    session.currentSnapshotToken = consumer.snapshotToken
    session.state = "bounded-sequence-revalidated"
    self:_Record(session, {
        routeChanged=routeChanged,
        recipeChanged=recipeChanged,
        revalidatedSnapshotToken=consumer.snapshotToken,
    })
    return self:_DispatchNext(session, false)
end

function ResearchBoundedSequentialCraft:_ScheduleContinue(session)
    if not session or session.active ~= true then return end
    if session.dispatchInProgress then
        session.continuePending = true
        return
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local token = session.token
        C_Timer.After(0, function()
            local current = ResearchBoundedSequentialCraft.sessions[session.professionKey]
            if current and current.active and current.token == token then
                ResearchBoundedSequentialCraft:_Continue(current)
            end
        end)
    else
        self:_Continue(session)
    end
end

function ResearchBoundedSequentialCraft:ObserveCraftAction(action)
    local provenance = type(action) == "table" and action.authorityProvenance or nil
    local sessionToken = provenance and provenance.sequenceSessionToken or nil
    if not sessionToken or not terminalStatus(action and action.status) then return false, "not-bounded-sequence-terminal" end
    local professionKey = normalizeKey(action.key or provenance.professionKey)
    local session = professionKey and self.sessions[professionKey] or nil
    if not session or session.active ~= true or tostring(session.token or "") ~= tostring(sessionToken or "") then
        return false, "bounded-sequence-session-expired-or-unknown"
    end

    local ledgerKey = tostring(action.ledgerID or action.transactionID or action.token or "")
    session.settledLedgers = session.settledLedgers or {}
    if ledgerKey ~= "" and session.settledLedgers[ledgerKey] then return false, "bounded-sequence-terminal-duplicate" end
    if ledgerKey ~= "" then session.settledLedgers[ledgerKey] = true end

    local ordinal = tonumber(provenance.sequenceOrdinal)
    local expectedOrdinal = (tonumber(session.settledCount) or 0) + 1
    if ordinal ~= expectedOrdinal then
        self:_Close(session, "bounded-sequence-stopped-ordinal-mismatch", "terminal-ordinal-mismatch")
        return false, "bounded-sequence-stopped-ordinal-mismatch"
    end

    session.lastSettledLedgerID = action.ledgerID or action.transactionID
    session.lastSettledRecipe = action.recipeName or provenance.recipe
    session.lastSettledRecipeID = tonumber(action.recipeID or provenance.recipeID)
    session.lastSettledRouteIndex = tonumber(provenance.routeIndex)
    session.lastSettlementStatus = tostring(action.status or "unknown")

    if tostring(action.status or "") ~= "success" then
        self:_Close(session, "bounded-sequence-stopped-settlement-failure", tostring(action.status or "failed"))
        return true, "bounded-sequence-stopped-settlement-failure"
    end

    session.settledCount = expectedOrdinal
    session.currentRecipe = session.lastSettledRecipe
    session.currentRecipeID = session.lastSettledRecipeID
    session.currentRouteIndex = session.lastSettledRouteIndex
    session.state = "bounded-sequence-craft-settled"
    self:_Record(session, {
        settledLedgerID=session.lastSettledLedgerID,
        settledOrdinal=ordinal,
        settlementStatus="success",
    })

    if session.cancelRequested then
        self:_Close(session, "bounded-sequence-cancelled-after-settlement", session.cancelReason or "cancel-requested")
        return true, "bounded-sequence-cancelled-after-settlement"
    end
    if session.settledCount >= tonumber(session.requestedCount or 0) then
        self:_Close(session, "bounded-sequence-complete", "requested-count-settled")
        return true, "bounded-sequence-complete"
    end

    self:_ScheduleContinue(session)
    return true, "bounded-sequence-continuing"
end

function ResearchBoundedSequentialCraft:Request(professionKey, mode, requestedCount, source, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    source = tostring(source or "profession-guide")
    options = type(options) == "table" and options or nil

    if not self:IsFeatureEnabled() then return false, "bounded-sequence-feature-gate-disabled" end
    if not self:IsEffectiveEnabled() then return false, "bounded-sequence-authority-disabled" end
    if source ~= "profession-guide" then return false, "bounded-sequence-user-origin-required" end
    if self.sessions[professionKey] and self.sessions[professionKey].active then return false, "bounded-sequence-already-active" end

    local native = JLP:GetModule("ResearchNativeExecutionAuthority")
    if not native or not native.IsSupported or not native:IsSupported(professionKey) then
        return false, "bounded-sequence-profession-unsupported"
    end

    local limit = self:GetConfiguredLimit()
    local count = math.floor(tonumber(requestedCount) or limit)
    if count < self.minCrafts or count > limit or count > self.maxCraftsHard then
        return false, "bounded-sequence-count-out-of-range"
    end

    local consumer = self:_CurrentConsumer({ professionKey=professionKey, mode=mode, options=options })
    if not consumer or consumer.state ~= "consumer-authority-active" or not consumer.plan or not consumer.plan.step then
        return false, consumer and consumer.state or "consumer-authority-unavailable"
    end
    local stopPolicy = JLP:GetModule("ResearchSequentialStopPolicy")
    if stopPolicy and stopPolicy.Evaluate then
        local startBoundary, currentConsumer = stopPolicy:Evaluate(professionKey, mode, options, consumer)
        consumer = currentConsumer or consumer
        if startBoundary and startBoundary.terminal == true then
            return false, "bounded-sequence-start-boundary", startBoundary
        end
    end

    -- Alpha82 never reopens a sequence that stopped on an alpha81 boundary. If
    -- that historical boundary has resolved, a new explicit Guide click must
    -- consume the current restart candidate before a brand-new session exists.
    local restartAuthorization
    local restart = JLP:GetModule("ResearchBoundaryResolutionRestart")
    if restart and restart.AuthorizeExplicitRestart then
        local authorization, restartState, restartModel = restart:AuthorizeExplicitRestart(professionKey, mode, source, options)
        if authorization == nil then
            return false, restartState or "boundary-restart-not-ready", restartModel
        elseif authorization ~= false then
            restartAuthorization = authorization
        end
    end
    if restartAuthorization then
        local currentStep = consumer and consumer.plan and consumer.plan.step or nil
        local currentRecipeID = currentStep and (tonumber(currentStep.recipeID) or tonumber(currentStep.rawStep and currentStep.rawStep.recipeID) or tonumber(currentStep.datasetStep and currentStep.datasetStep.recipeID)) or nil
        local exactRestart = tostring(restartAuthorization.currentSnapshotToken or "") == tostring(consumer and consumer.snapshotToken or "")
            and tostring(restartAuthorization.currentStateFingerprint or "") == tostring(consumer and consumer.stateFingerprint or "")
            and tonumber(restartAuthorization.currentRecipeID) == tonumber(currentRecipeID)
            and tonumber(restartAuthorization.currentRouteIndex) == tonumber(currentStep and currentStep.routeIndex)
            and tonumber(restartAuthorization.currentBuild) == tonumber(consumer and consumer.currentBuild)
        if not exactRestart then
            return false, "boundary-restart-authorization-stale", restartAuthorization
        end
    end

    self.serial = (tonumber(self.serial) or 0) + 1
    local nowValue = monotonicNow()
    local step = consumer.plan.step
    local recipeID = tonumber(step.recipeID) or tonumber(step.rawStep and step.rawStep.recipeID) or tonumber(step.datasetStep and step.datasetStep.recipeID)
    local token = "bounded-sequence-" .. stateHash({
        professionKey, mode, tostring(consumer.snapshotToken or ""), tostring(recipeID or ""), tostring(self.serial), tostring(nowValue),
    })
    local session = {
        contract = self.sessionContract,
        token = token,
        professionKey = professionKey,
        mode = mode,
        requestedCount = count,
        dispatchedCount = 0,
        settledCount = 0,
        routeTransitions = 0,
        state = "bounded-sequence-prepared",
        source = source,
        initialRecipe = step.recipe,
        initialRecipeID = recipeID,
        initialRouteIndex = tonumber(step.routeIndex),
        initialSnapshotToken = consumer.snapshotToken,
        currentRecipe = step.recipe,
        currentRecipeID = recipeID,
        currentRouteIndex = tonumber(step.routeIndex),
        currentSnapshotToken = consumer.snapshotToken,
        createdAt = nowValue,
        active = true,
        persisted = false,
        options = options,
        settledLedgers = {},
        restartCandidateToken = restartAuthorization and restartAuthorization.candidateToken or nil,
        restartAuthorizationToken = restartAuthorization and restartAuthorization.token or nil,
        restartedFromSessionToken = restartAuthorization and restartAuthorization.priorSessionToken or nil,
        restartedFromBoundaryState = restartAuthorization and restartAuthorization.priorBoundaryState or nil,
        restartedFromBoundaryCategory = restartAuthorization and restartAuthorization.priorBoundaryCategory or nil,
        restartRouteTransitionKind = restartAuthorization and restartAuthorization.routeTransitionKind or nil,
        restartRouteChanged = restartAuthorization and restartAuthorization.routeChanged == true or false,
        restartPriorRecipeID = restartAuthorization and restartAuthorization.priorRecipeID or nil,
        restartPriorRouteIndex = restartAuthorization and restartAuthorization.priorRouteIndex or nil,
        restartCurrentRecipeID = restartAuthorization and restartAuthorization.currentRecipeID or nil,
        restartCurrentRouteIndex = restartAuthorization and restartAuthorization.currentRouteIndex or nil,
        restartExplicitUserClick = restartAuthorization and restartAuthorization.explicitUserClick == true or false,
    }
    self.sessions[professionKey] = session
    self:_Record(session)
    local ok, state, report = self:_DispatchNext(session, true)
    return ok, state, report or self:GetSession(professionKey)
end

function ResearchBoundedSequentialCraft:GetSummary(professionKey)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local active = self:GetSession(professionKey)
    local last = active or self:GetLast(professionKey)
    local lines = {
        "RESEARCH BOUNDED SEQUENTIAL CRAFT / REVALIDATED CRAFT ONE LOOP",
        professionKey,
        "Contract: " .. self.contract,
        "Session contract: " .. self.sessionContract,
        "Authority: one explicit Guide click delegates only bounded, revalidated Craft One ordinals",
        "Feature gate: " .. (self:IsFeatureEnabled() and "enabled" or "disabled"),
        "Effective authority: " .. (self:IsEffectiveEnabled() and "enabled" or "disabled"),
        "Configured bound: " .. tostring(self:GetConfiguredLimit()) .. " crafts · hard max " .. tostring(self.maxCraftsHard),
        "Native batch API: forbidden · every dispatch count = 1",
        "Per-craft revalidation: required",
        "Reload behavior: settle current craft only · sequence never auto-resumes",
        "Persistence: none",
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = "Progress: " .. tostring(last.settledCount or 0) .. " / " .. tostring(last.requestedCount or 0) .. " settled"
        lines[#lines + 1] = "Dispatched: " .. tostring(last.dispatchedCount or 0)
        lines[#lines + 1] = "Current recipe: " .. tostring(last.currentRecipe or "unknown") .. " / " .. tostring(last.currentRecipeID or "unresolved")
        lines[#lines + 1] = "Current route index: " .. tostring(last.currentRouteIndex or "unknown")
        lines[#lines + 1] = "Route-step handoffs: " .. tostring(last.routeTransitions or 0)
        lines[#lines + 1] = "Session active: " .. (last.active and "yes" or "no")
        if last.stopReason then lines[#lines + 1] = "Stop reason: " .. tostring(last.stopReason) end
        if last.stopBoundary then
            lines[#lines + 1] = "Boundary category: " .. tostring(last.stopBoundary.category or "unknown")
            lines[#lines + 1] = "Next action handoff: " .. tostring(last.stopBoundary.nextActionText or "unknown")
            lines[#lines + 1] = "Boundary auto-resume: disabled"
        end
        if last.restartCandidateToken then
            lines[#lines + 1] = "Restart candidate: " .. tostring(last.restartCandidateToken)
            lines[#lines + 1] = "Restart transition: " .. tostring(last.restartRouteTransitionKind or "same-route")
            lines[#lines + 1] = "Restarted from sequence: " .. tostring(last.restartedFromSessionToken or "unknown")
            lines[#lines + 1] = "Restarted from boundary: " .. tostring(last.restartedFromBoundaryCategory or "unknown")
            lines[#lines + 1] = "Restart origin: explicit new Profession Guide click"
        end
    end
    return table.concat(lines, "\n")
end

function ResearchBoundedSequentialCraft:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("RESEARCH_NATIVE_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false and self:IsFeatureEnabled() then
                local profile = featureProfile()
                if profile then profile.enabled = false end
                self:CancelAll("native-execution-authority-disabled")
                self:_Emit({contract=self.contract,state="bounded-sequence-auto-demoted",reason="native-execution-authority-disabled",persisted=false})
            end
        end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false and self:IsFeatureEnabled() then
                local profile = featureProfile()
                if profile then profile.enabled = false end
                self:CancelAll("execution-authority-eligibility-disabled")
                self:_Emit({contract=self.contract,state="bounded-sequence-auto-demoted",reason="execution-authority-eligibility-disabled",persisted=false})
            end
        end)
    end
    return true
end

function ResearchBoundedSequentialCraft:Validate()
    local errors, warnings = {}, {}
    if self.persisted ~= false then errors[#errors + 1] = "bounded sequential execution must not persist sessions" end
    if self.automaticResume ~= false then errors[#errors + 1] = "bounded sequential execution must not auto-resume after reload" end
    if tonumber(self.maxCraftsHard) ~= 3 then errors[#errors + 1] = "alpha80 hard sequential bound must remain three crafts" end
    if tonumber(self.minCrafts) ~= 2 then errors[#errors + 1] = "alpha80 minimum sequence size must remain two crafts" end
    for _, name in ipairs({"ResearchExecutionAuthorityGate", "ResearchNativeExecutionAuthority", "ResearchPlannerConsumerBridge", "ResearchNativeStepTransition", "ResearchSequentialStopPolicy", "ResearchBoundaryResolutionRestart", "Crafting"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "bounded sequential dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchBoundedSequentialCraft", ResearchBoundedSequentialCraft)
