local _, JLP = ...

-- Alpha82 converts an alpha81 terminal non-craft sequence boundary into a new,
-- explicit restart candidate only after the boundary has genuinely resolved and
-- the current Planner/consumer/execution snapshot is craft-ready again.  The
-- old sequence is never reopened.  A candidate is in-memory, single-use and may
-- only authorize creation of a brand-new alpha80 session from a new Profession
-- Guide click.
local ResearchBoundaryResolutionRestart = {
    contract = "controlled-boundary-resolution-restart-planner-v1",
    candidateContract = "research-bounded-sequence-restart-candidate-v1",
    authorizationContract = "research-bounded-sequence-restart-authorization-v1",
    authority = "explicit-user-click-new-sequence-restart-only",
    persisted = false,
    automaticResume = false,
    priorSessionReusable = false,
    candidates = {},
    consumedByProfession = {},
    lastByProfession = {},
    serial = 0,
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

local function stepIdentity(consumer)
    local step = consumer and consumer.plan and consumer.plan.step or nil
    if not step then return nil, nil, nil, nil end
    local recipeID = tonumber(step.recipeID)
        or tonumber(step.rawStep and step.rawStep.recipeID)
        or tonumber(step.datasetStep and step.datasetStep.recipeID)
    return step.recipe, recipeID, tonumber(step.routeIndex), tonumber(step.skillTarget)
end

function ResearchBoundaryResolutionRestart:_Sequence()
    local autoRoute = JLP:GetModule("ResearchAutoRouteOrchestrator")
    if autoRoute and ((autoRoute.GetSession and autoRoute:GetSession("HARNESSSEGMENT")) or next(autoRoute.lastByProfession or {}) ~= nil) then
        return autoRoute
    end
    return JLP:GetModule("ResearchBoundedSequentialCraft")
end

function ResearchBoundaryResolutionRestart:_StoppedSequence(professionKey)
    local autoRoute = JLP:GetModule("ResearchAutoRouteOrchestrator")
    if autoRoute then
        local active = autoRoute.GetSession and autoRoute:GetSession(professionKey) or nil
        if active and active.active == true then return nil, active end
        local last = autoRoute.GetLast and autoRoute:GetLast(professionKey) or nil
        if type(last) == "table" and last.state == "auto-route-stopped-boundary" and type(last.stopBoundary) == "table" then
            return last, nil
        end
    end
    local sequence = JLP:GetModule("ResearchBoundedSequentialCraft")
    if not sequence then return nil, nil end
    local active = sequence.GetSession and sequence:GetSession(professionKey) or nil
    if active and active.active == true then return nil, active end
    local last = sequence.GetLast and sequence:GetLast(professionKey) or nil
    if type(last) ~= "table" or last.state ~= "bounded-sequence-stopped-boundary" or type(last.stopBoundary) ~= "table" then return nil, nil end
    return last, nil
end

function ResearchBoundaryResolutionRestart:_ClearCandidate(professionKey, reason)
    professionKey = normalizeKey(professionKey)
    if not professionKey then return end
    local existing = self.candidates[professionKey]
    if existing then
        existing.state = reason or "boundary-restart-candidate-invalidated"
        existing.invalidatedAt = monotonicNow()
        self.lastByProfession[professionKey] = shallowCopy(existing)
    end
    self.candidates[professionKey] = nil
end

function ResearchBoundaryResolutionRestart:_Model(professionKey, mode)
    return {
        contract = self.contract,
        candidateContract = self.candidateContract,
        authorizationContract = self.authorizationContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        state = "boundary-restart-evaluating",
        restartRequired = false,
        restartReady = false,
        explicitUserClickRequired = true,
        automaticResume = false,
        priorSessionReusable = false,
        persisted = false,
    }
end

function ResearchBoundaryResolutionRestart:Evaluate(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    local model = self:_Model(professionKey, mode)

    local stopped, active = self:_StoppedSequence(professionKey)
    if active then
        self:_ClearCandidate(professionKey, "boundary-restart-new-sequence-active")
        model.state = "boundary-restart-new-sequence-active"
        model.activeSessionToken = active.sessionToken
        return model
    end
    if not stopped then
        self:_ClearCandidate(professionKey, "boundary-restart-not-applicable")
        model.state = "boundary-restart-not-applicable"
        return model
    end

    model.restartRequired = true
    model.priorSessionToken = stopped.sessionToken
    model.priorRequestedCount = tonumber(stopped.requestedCount)
    model.priorSettledCount = tonumber(stopped.settledCount)
    model.priorBoundaryState = stopped.stopBoundary.state
    model.priorBoundaryCategory = stopped.stopBoundary.category
    model.priorBoundaryLabel = stopped.stopBoundary.label
    model.priorBoundaryText = stopped.stopBoundary.nextActionText
    model.priorSnapshotToken = stopped.stopBoundary.snapshotToken
    model.priorStateFingerprint = stopped.stopBoundary.stateFingerprint
    model.priorRecipe = stopped.stopBoundary.recipe or stopped.currentRecipe
    model.priorRecipeID = tonumber(stopped.stopBoundary.recipeID) or tonumber(stopped.currentRecipeID)
    model.priorRouteIndex = tonumber(stopped.stopBoundary.routeIndex) or tonumber(stopped.currentRouteIndex)
    model.priorSkillTarget = tonumber(stopped.stopBoundary.skillTarget)

    local policy = JLP:GetModule("ResearchSequentialStopPolicy")
    local current, consumer
    if policy and policy.Evaluate then current, consumer = policy:Evaluate(professionKey, mode, options) end
    if not current then
        self:_ClearCandidate(professionKey, "boundary-restart-policy-unavailable")
        model.state = "boundary-restart-policy-unavailable"
        return model
    end

    model.currentBoundaryState = current.state
    model.currentBoundaryCategory = current.category
    model.currentBoundaryText = current.nextActionText

    if current.terminal == true then
        self:_ClearCandidate(professionKey, "boundary-restart-still-blocked")
        model.state = tostring(current.category or "") == tostring(model.priorBoundaryCategory or "")
            and "boundary-restart-still-blocked"
            or "boundary-restart-boundary-shifted"
        model.currentBoundary = current
        return model
    end

    local consumerReady = consumer ~= nil
        and consumer.state == "consumer-authority-active"
        and consumer.consumerAuthorityEnabled == true
        and consumer.routeAuthorityEnabled == true
        and consumer.plannerEligible == true
        and consumer.executionEligible == false
        and current.sequenceMayContinue == true
        and current.category == "CRAFT"
    if not consumerReady then
        self:_ClearCandidate(professionKey, "boundary-restart-consumer-not-ready")
        model.state = "boundary-restart-consumer-not-ready"
        return model
    end

    local recipe, recipeID, routeIndex, skillTarget = stepIdentity(consumer)
    local currentSnapshot = tostring(consumer.snapshotToken or "")
    local currentFingerprint = tostring(consumer.stateFingerprint or "")
    local priorSnapshot = tostring(model.priorSnapshotToken or "")
    local priorFingerprint = tostring(model.priorStateFingerprint or "")
    local snapshotChanged = currentSnapshot ~= "" and currentSnapshot ~= priorSnapshot
    local fingerprintChanged = currentFingerprint ~= "" and currentFingerprint ~= priorFingerprint
    model.snapshotChanged = snapshotChanged
    model.stateFingerprintChanged = fingerprintChanged
    model.currentSnapshotToken = consumer.snapshotToken
    model.currentStateFingerprint = consumer.stateFingerprint
    model.currentRecipe = recipe
    model.currentRecipeID = recipeID
    model.currentRouteIndex = routeIndex
    model.currentSkillTarget = skillTarget
    model.currentBuild = consumer.currentBuild

    if not snapshotChanged and not fingerprintChanged then
        self:_ClearCandidate(professionKey, "boundary-restart-stale-snapshot")
        model.state = "boundary-restart-stale-snapshot"
        return model
    end
    if not recipe or not recipeID or not routeIndex then
        self:_ClearCandidate(professionKey, "boundary-restart-identity-unresolved")
        model.state = "boundary-restart-identity-unresolved"
        return model
    end

    local transitionModule = JLP:GetModule("ResearchRouteChangingRestart")
    local transitionOK, transitionState, transition
    if transitionModule and transitionModule.Harden then
        transitionOK, transitionState, transition = transitionModule:Harden(model)
        if not transitionOK then
            self:_ClearCandidate(professionKey, transitionState or "boundary-restart-route-transition-blocked")
            model.state = transitionState or "boundary-restart-route-transition-blocked"
            model.routeTransition = transition
            return model
        end
    else
        transition = {
            contract = "research-boundary-route-transition-v1",
            transitionKind = "same-route",
            routeChanged = false,
            ready = true,
            state = "same-route-restart-verified",
        }
    end
    model.routeTransition = transition
    model.routeTransitionKind = transition.transitionKind
    model.routeChanged = transition.routeChanged == true
    model.oldExecutionArtifactsPurged = transition.oldExecutionArtifactsPurged == true

    local candidateToken = "sequence-restart-" .. stateHash({
        professionKey, mode, tostring(model.priorSessionToken or ""), tostring(model.priorBoundaryState or ""),
        currentSnapshot, currentFingerprint, tostring(recipeID), tostring(routeIndex), tostring(model.currentBuild or ""),
    })
    local consumedToken = self.consumedByProfession[professionKey]
    if consumedToken == candidateToken then
        model.state = "boundary-restart-candidate-consumed"
        model.candidateConsumed = true
        self.candidates[professionKey] = nil
        return model
    end

    local candidate = self.candidates[professionKey]
    if not candidate or candidate.token ~= candidateToken then
        candidate = {
            contract = self.candidateContract,
            token = candidateToken,
            professionKey = professionKey,
            mode = mode,
            priorSessionToken = model.priorSessionToken,
            priorBoundaryState = model.priorBoundaryState,
            priorBoundaryCategory = model.priorBoundaryCategory,
            priorBoundaryLabel = model.priorBoundaryLabel,
            priorBoundaryText = model.priorBoundaryText,
            priorSnapshotToken = model.priorSnapshotToken,
            priorStateFingerprint = model.priorStateFingerprint,
            priorRecipe = model.priorRecipe,
            priorRecipeID = model.priorRecipeID,
            priorRouteIndex = model.priorRouteIndex,
            priorSkillTarget = model.priorSkillTarget,
            currentSnapshotToken = consumer.snapshotToken,
            currentStateFingerprint = consumer.stateFingerprint,
            currentRecipe = recipe,
            currentRecipeID = recipeID,
            currentRouteIndex = routeIndex,
            currentSkillTarget = skillTarget,
            currentBuild = consumer.currentBuild,
            routeTransitionKind = model.routeTransitionKind,
            routeChanged = model.routeChanged == true,
            oldExecutionArtifactsPurged = model.oldExecutionArtifactsPurged == true,
            routeTransitionContract = transition and transition.transitionContract or nil,
            createdAt = monotonicNow(),
            singleUse = true,
            consumed = false,
            explicitUserClickRequired = true,
            automaticResume = false,
            persisted = false,
            state = "boundary-resolved-restart-candidate",
        }
        self.candidates[professionKey] = candidate
        self.lastByProfession[professionKey] = shallowCopy(candidate)
    end

    model.state = "boundary-resolved-restart-candidate"
    model.restartReady = true
    model.candidateToken = candidate.token
    model.candidate = shallowCopy(candidate)
    return model
end

function ResearchBoundaryResolutionRestart:GetCandidate(professionKey, mode, options)
    local model = self:Evaluate(professionKey, mode, options)
    return model.restartReady and model.candidate or nil, model.state, model
end

function ResearchBoundaryResolutionRestart:AuthorizeExplicitRestart(professionKey, mode, source, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    source = tostring(source or "")
    if source ~= "profession-guide" then
        return nil, "boundary-restart-explicit-guide-click-required"
    end

    local model = self:Evaluate(professionKey, mode, options)
    if model.restartRequired ~= true then
        return false, "boundary-restart-not-required", model
    end
    if model.restartReady ~= true or type(model.candidate) ~= "table" then
        return nil, model.state or "boundary-restart-not-ready", model
    end

    local candidate = self.candidates[professionKey]
    if not candidate or candidate.token ~= model.candidateToken or candidate.consumed == true then
        return nil, "boundary-restart-candidate-expired-or-unknown", model
    end

    candidate.consumed = true
    candidate.consumedAt = monotonicNow()
    candidate.state = "boundary-restart-candidate-consumed"
    self.consumedByProfession[professionKey] = candidate.token
    self.candidates[professionKey] = nil
    self.lastByProfession[professionKey] = shallowCopy(candidate)
    self.serial = (tonumber(self.serial) or 0) + 1
    local authorization = {
        contract = self.authorizationContract,
        token = "sequence-restart-auth-" .. stateHash({candidate.token, professionKey, mode, tostring(self.serial), tostring(candidate.consumedAt)}),
        candidateToken = candidate.token,
        professionKey = professionKey,
        mode = mode,
        source = source,
        priorSessionToken = candidate.priorSessionToken,
        priorBoundaryState = candidate.priorBoundaryState,
        priorBoundaryCategory = candidate.priorBoundaryCategory,
        priorSnapshotToken = candidate.priorSnapshotToken,
        priorRecipe = candidate.priorRecipe,
        priorRecipeID = candidate.priorRecipeID,
        priorRouteIndex = candidate.priorRouteIndex,
        priorSkillTarget = candidate.priorSkillTarget,
        currentSnapshotToken = candidate.currentSnapshotToken,
        currentStateFingerprint = candidate.currentStateFingerprint,
        currentRecipe = candidate.currentRecipe,
        currentRecipeID = candidate.currentRecipeID,
        currentRouteIndex = candidate.currentRouteIndex,
        currentBuild = candidate.currentBuild,
        routeTransitionKind = candidate.routeTransitionKind,
        routeChanged = candidate.routeChanged == true,
        oldExecutionArtifactsPurged = candidate.oldExecutionArtifactsPurged == true,
        routeTransitionContract = candidate.routeTransitionContract,
        explicitUserClick = true,
        singleUse = true,
        consumed = true,
        persisted = false,
        automaticResume = false,
    }
    return authorization, "boundary-restart-explicitly-authorized", model
end

function ResearchBoundaryResolutionRestart:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and shallowCopy(row) or nil
end

function ResearchBoundaryResolutionRestart:GetSummary(professionKey, mode, options)
    local model = self:Evaluate(professionKey, mode, options)
    local lines = {
        "RESEARCH BOUNDED SEQUENCE / BOUNDARY RESOLUTION RESTART",
        tostring(model.professionKey) .. " / " .. tostring(model.mode),
        "Contract: " .. self.contract,
        "Candidate contract: " .. self.candidateContract,
        "Authority: explicit new Profession Guide click only",
        "State: " .. tostring(model.state),
        "Restart required: " .. (model.restartRequired and "yes" or "no"),
        "Restart ready: " .. (model.restartReady and "yes" or "no"),
        "Automatic resume: disabled",
        "Prior session reuse: forbidden",
        "Persistence: none",
    }
    if model.priorSessionToken then lines[#lines + 1] = "Prior sequence: " .. tostring(model.priorSessionToken) end
    if model.priorBoundaryCategory then lines[#lines + 1] = "Resolved boundary: " .. tostring(model.priorBoundaryCategory) end
    if model.candidateToken then lines[#lines + 1] = "Restart candidate: " .. tostring(model.candidateToken) end
    if model.currentRecipe then lines[#lines + 1] = "Verified route: " .. tostring(model.currentRecipe) .. " / " .. tostring(model.currentRecipeID or "unresolved") end
    if model.currentRouteIndex then lines[#lines + 1] = "Verified route index: " .. tostring(model.currentRouteIndex) end
    if model.routeTransitionKind then lines[#lines + 1] = "Restart route transition: " .. tostring(model.routeTransitionKind) end
    if model.routeChanged then lines[#lines + 1] = "Old route artifacts: purged before new restart authority" end
    if model.currentSnapshotToken then lines[#lines + 1] = "New snapshot: " .. tostring(model.currentSnapshotToken) end
    return table.concat(lines, "\n")
end

function ResearchBoundaryResolutionRestart:Validate()
    local errors, warnings = {}, {}
    if self.persisted ~= false then errors[#errors + 1] = "boundary restart candidates must not persist" end
    if self.automaticResume ~= false then errors[#errors + 1] = "boundary restart planner must never auto-resume sequences" end
    if self.priorSessionReusable ~= false then errors[#errors + 1] = "boundary restart planner must never reopen a prior sequence session" end
    for _, name in ipairs({"ResearchSequentialStopPolicy", "ResearchAutoRouteOrchestrator", "ResearchBoundedSequentialCraft", "ResearchPlannerConsumerBridge", "ResearchRouteChangingRestart"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "boundary restart dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchBoundaryResolutionRestart", ResearchBoundaryResolutionRestart)
