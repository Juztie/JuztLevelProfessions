local _, JLP = ...

-- Alpha102 gives production Tailoring Craft All its own fresh-click restart
-- lifecycle.  It never revives the prior aggregate transaction, authorization
-- or ledger.  Only a settled production-Tailoring interruption may become a
-- candidate, and only when the exact same recipe, route target and route index
-- are current again under fresh production readiness.  A new Profession Guide
-- click is mandatory and the resulting Craft All request creates a new ledger.
local ProductionTailoringCraftAllRestart = {
    contract = "production-tailoring-current-recipe-craft-all-restart-planner-v1",
    candidateContract = "production-tailoring-current-recipe-craft-all-restart-candidate-v1",
    authorizationContract = "production-tailoring-current-recipe-craft-all-restart-authorization-v1",
    interruptionContract = "production-tailoring-current-recipe-craft-all-interruption-v1",
    provenanceContract = "production-tailoring-native-craft-all-provenance-v1",
    authority = "explicit-user-click-fresh-production-tailoring-current-recipe-craft-all-restart-only",
    automaticResume = false,
    priorTransactionReusable = false,
    sameRecipeRequired = true,
    sameTargetRequired = true,
    sameRouteRequired = true,
    persisted = false,
    authorizationTTLSeconds = 3,
    candidateSerial = 0,
    authorizationSerial = 0,
    candidates = {},
    authorizations = {},
    consumedInterruptionByProfession = {},
    lastByProfession = {},
}

local RESTARTABLE = {
    WINDOW_LOST = true,
    MATERIALS = true,
    BUILD_CHANGED = true,
    AUTHORITY_REVOKED = true,
    API_FAILURE = true,
    RELOAD_NO_RESUME = true,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function now()
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
    for index = 1, #value do hash = (hash * 33 + string.byte(value, index)) % 2147483647 end
    return string.format("%08x", hash)
end

local function copy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function currentStep(model)
    return model and model.plan and model.plan.step or nil
end

local function currentRecipeID(model)
    local step = currentStep(model)
    return tonumber(model and model.recipeID)
        or tonumber(step and step.recipeID)
        or tonumber(step and step.rawStep and step.rawStep.recipeID)
        or tonumber(step and step.datasetStep and step.datasetStep.recipeID)
end

function ProductionTailoringCraftAllRestart:IsRestartableCategory(category)
    return RESTARTABLE[tostring(category or ""):upper()] == true
end

function ProductionTailoringCraftAllRestart:_Sweep(nowValue)
    nowValue = tonumber(nowValue) or now()
    for token, row in pairs(self.authorizations or {}) do
        if type(row) ~= "table" or row.consumed == true or (tonumber(row.expiresAt) and nowValue > tonumber(row.expiresAt)) then
            self.authorizations[token] = nil
        end
    end
end

function ProductionTailoringCraftAllRestart:_InvalidateCandidate(professionKey, reason)
    professionKey = normalizeKey(professionKey)
    if not professionKey then return end
    local existing = self.candidates[professionKey]
    if existing then
        existing.state = tostring(reason or "production-tailoring-craft-all-restart-candidate-invalidated")
        existing.restartReady = false
        existing.invalidatedAt = now()
        self.lastByProfession[professionKey] = copy(existing)
    end
    self.candidates[professionKey] = nil
end

function ProductionTailoringCraftAllRestart:_BaseModel(professionKey, mode)
    return {
        contract = self.contract,
        candidateContract = self.candidateContract,
        authorizationContract = self.authorizationContract,
        interruptionContract = self.interruptionContract,
        provenanceContract = self.provenanceContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        state = "production-tailoring-craft-all-restart-evaluating",
        restartRequired = false,
        restartReady = false,
        explicitUserClickRequired = true,
        automaticResume = false,
        priorTransactionReusable = false,
        sameRecipeRequired = true,
        sameTargetRequired = true,
        sameRouteRequired = true,
        persisted = false,
    }
end

function ProductionTailoringCraftAllRestart:Evaluate(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "TAILORING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    self:_Sweep(now())
    local model = self:_BaseModel(professionKey, mode)
    if professionKey ~= "TAILORING" then
        model.state = "production-tailoring-craft-all-restart-profession-unsupported"
        return model
    end

    local interruptionModule = JLP:GetModule("ResearchNativeCraftAllInterruption")
    local interruption = interruptionModule and interruptionModule.GetLast and interruptionModule:GetLast(professionKey) or nil
    if type(interruption) ~= "table" or not self:IsRestartableCategory(interruption.category) then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-not-applicable")
        model.state = "production-tailoring-craft-all-restart-not-applicable"
        return model
    end
    if tostring(interruption.provenanceContract or "") ~= self.provenanceContract
        or tostring(interruption.interruptionContract or "") ~= self.interruptionContract then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-source-unproven")
        model.state = "production-tailoring-craft-all-restart-source-unproven"
        return model
    end

    local interruptionToken = tostring(interruption.interruptionToken or "")
    if interruptionToken == "" then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-interruption-identity-missing")
        model.state = "production-tailoring-craft-all-restart-interruption-identity-missing"
        return model
    end
    model.restartRequired = true
    model.interruptionToken = interruptionToken
    model.interruptionCategory = interruption.category
    model.interruptionState = interruption.state
    model.interruptionDetail = interruption.detail
    model.priorLedgerID = interruption.ledgerID
    model.priorRecipe = interruption.recipe
    model.priorRecipeID = tonumber(interruption.recipeID)
    model.priorRouteIndex = tonumber(interruption.routeIndex)
    model.priorSkillTarget = tonumber(interruption.targetSkill)
    model.priorCompletedCount = tonumber(interruption.completedCount) or 0
    model.priorRequestedCount = tonumber(interruption.requestedCount) or 0
    model.priorBuild = tonumber(interruption.currentBuild)
    model.priorSnapshotToken = interruption.snapshotToken
    model.priorStateFingerprint = interruption.stateFingerprint
    model.priorProvenanceContract = interruption.provenanceContract

    if self.consumedInterruptionByProfession[professionKey] == interruptionToken then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-interruption-consumed")
        model.state = "production-tailoring-craft-all-restart-interruption-consumed"
        return model
    end

    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and crafting.pendingCraft or nil
    if pending and normalizeKey(pending.key) == professionKey then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-transaction-active")
        model.state = "production-tailoring-craft-all-restart-transaction-active"
        return model
    end

    local authority = JLP:GetModule("ProductionTailoringCraftAllAuthority")
    local authorityReady = authority and authority.IsEffectiveEnabled and authority:IsEffectiveEnabled() or false
    if not authorityReady then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-authority-not-ready")
        model.state = "production-tailoring-craft-all-restart-authority-not-ready"
        return model
    end

    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local current = readiness and readiness.Evaluate and readiness:Evaluate(professionKey, mode, options) or nil
    model.readinessState = current and current.state or "execution-readiness-unavailable"
    model.blockedGate = current and current.blockedGate or nil
    model.blockedState = current and current.blockedState or nil
    model.craftabilityStatus = current and current.craftabilityStatus or "UNKNOWN"
    model.craftabilityReason = current and current.craftabilityReason or "readiness-unavailable"
    model.currentNativeCraftable = model.craftabilityStatus == "KNOWN" and current and current.nativeCraftable or nil
    if not current or current.executionReadinessReady ~= true then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-still-blocked")
        model.state = "production-tailoring-craft-all-restart-still-blocked"
        return model
    end

    local step = currentStep(current)
    local recipeID = currentRecipeID(current)
    local recipe = step and step.recipe or current.recipe
    local routeIndex = tonumber(step and step.routeIndex)
    local skillTarget = tonumber(step and step.skillTarget)
    local currentSkill = tonumber(current.professionSkill)
    -- The restart path MUST preserve UNKNOWN/ERROR from Crafting.lua; only
    -- KNOWN(0) may be described as material/craft exhaustion.
    local craftable = tonumber(current.nativeCraftable)
    local knownCount = current.craftabilityStatus == "KNOWN" and craftable ~= nil
        and craftable == craftable and craftable ~= math.huge and craftable ~= -math.huge
        and craftable >= 0 and craftable % 1 == 0
    if not knownCount then craftable = nil end
    model.currentBuild = tonumber(current.currentBuild)
    model.currentSnapshotToken = current.snapshotToken
    model.currentStateFingerprint = current.stateFingerprint
    model.currentRecipe = recipe
    model.currentRecipeID = recipeID
    model.currentRouteIndex = routeIndex
    model.currentSkillTarget = skillTarget
    model.currentSkill = currentSkill
    model.currentNativeCraftable = craftable
    model.buildChanged = model.priorBuild ~= nil and model.currentBuild ~= nil and model.priorBuild ~= model.currentBuild or false

    if not recipeID or not model.priorRecipeID or recipeID ~= model.priorRecipeID
        or tostring(recipe or "") ~= tostring(model.priorRecipe or "") then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-recipe-changed")
        model.state = "production-tailoring-craft-all-restart-recipe-changed"
        return model
    end
    if not skillTarget or not model.priorSkillTarget or skillTarget ~= model.priorSkillTarget then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-target-changed")
        model.state = "production-tailoring-craft-all-restart-target-changed"
        return model
    end
    if model.priorRouteIndex and routeIndex and routeIndex ~= model.priorRouteIndex then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-route-changed")
        model.state = "production-tailoring-craft-all-restart-route-changed"
        return model
    end
    if not currentSkill or currentSkill >= skillTarget then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-target-reached")
        model.state = "production-tailoring-craft-all-restart-target-reached"
        return model
    end
    if not knownCount then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-craftability-unavailable")
        model.state = "production-tailoring-craft-all-restart-craftability-unavailable"
        return model
    end
    if craftable < 1 then
        self:_InvalidateCandidate(professionKey, "production-tailoring-craft-all-restart-materials-unavailable")
        model.state = "production-tailoring-craft-all-restart-materials-unavailable"
        return model
    end

    local existing = self.candidates[professionKey]
    local candidateIdentity = table.concat({
        interruptionToken,
        tostring(model.priorLedgerID or ""),
        tostring(current.currentBuild or ""),
        tostring(current.snapshotToken or ""),
        tostring(current.stateFingerprint or ""),
        tostring(recipeID or ""),
        tostring(routeIndex or ""),
        tostring(skillTarget or ""),
        tostring(currentSkill or ""),
        tostring(craftable),
    }, "\31")
    if type(existing) == "table" and existing.identity == candidateIdentity and existing.restartReady == true then
        for key, value in pairs(existing) do model[key] = value end
        self.lastByProfession[professionKey] = copy(model)
        return model
    end

    self.candidateSerial = (tonumber(self.candidateSerial) or 0) + 1
    local candidateToken = "tailoring-craftall-restart-candidate-" .. stateHash({candidateIdentity, tostring(self.candidateSerial), tostring(now())})
    local candidate = copy(model)
    candidate.identity = candidateIdentity
    candidate.candidateToken = candidateToken
    candidate.state = "production-tailoring-craft-all-restart-ready"
    candidate.restartReady = true
    candidate.createdAt = now()
    self.candidates[professionKey] = candidate
    self.lastByProfession[professionKey] = copy(candidate)
    return copy(candidate)
end

function ProductionTailoringCraftAllRestart:PrepareAuthorization(professionKey, mode, clickOrigin, options)
    professionKey = normalizeKey(professionKey) or "TAILORING"
    mode = normalizeMode(mode)
    local candidate = self:Evaluate(professionKey, mode, options)
    if not candidate or candidate.restartReady ~= true then
        return nil, candidate and candidate.state or "production-tailoring-craft-all-restart-not-ready", candidate
    end
    local clickToken = type(clickOrigin) == "table" and tostring(clickOrigin.token or "") or ""
    if clickToken == "" or tostring(clickOrigin.contract or "") ~= "production-tailoring-craft-all-click-origin-v1" then
        return nil, "production-tailoring-craft-all-restart-explicit-click-required", candidate
    end

    self.authorizationSerial = (tonumber(self.authorizationSerial) or 0) + 1
    local createdAt = now()
    local token = "tailoring-craftall-restart-authorization-" .. stateHash({
        candidate.candidateToken, clickToken, tostring(candidate.currentBuild or ""),
        tostring(candidate.currentSnapshotToken or ""), tostring(candidate.currentStateFingerprint or ""),
        tostring(self.authorizationSerial), tostring(createdAt),
    })
    local authorization = {
        contract = self.authorizationContract,
        provenanceContract = self.provenanceContract,
        token = token,
        candidateToken = candidate.candidateToken,
        professionKey = professionKey,
        mode = mode,
        clickOriginToken = clickToken,
        interruptionToken = candidate.interruptionToken,
        interruptionCategory = candidate.interruptionCategory,
        interruptionState = candidate.interruptionState,
        priorLedgerID = candidate.priorLedgerID,
        priorRecipe = candidate.priorRecipe,
        priorRecipeID = candidate.priorRecipeID,
        priorRouteIndex = candidate.priorRouteIndex,
        priorSkillTarget = candidate.priorSkillTarget,
        currentBuild = candidate.currentBuild,
        snapshotToken = candidate.currentSnapshotToken,
        stateFingerprint = candidate.currentStateFingerprint,
        recipe = candidate.currentRecipe,
        recipeID = candidate.currentRecipeID,
        routeIndex = candidate.currentRouteIndex,
        skillTarget = candidate.currentSkillTarget,
        currentSkill = candidate.currentSkill,
        nativeCraftable = candidate.currentNativeCraftable,
        explicitUserClick = true,
        freshTransactionRequired = true,
        automaticResume = false,
        priorTransactionReusable = false,
        sameRecipeRequired = true,
        sameTargetRequired = true,
        sameRouteRequired = true,
        createdAt = createdAt,
        expiresAt = createdAt + self.authorizationTTLSeconds,
        singleUse = true,
        persisted = false,
    }
    self.authorizations[token] = authorization
    return copy(authorization), "production-tailoring-craft-all-restart-authorization-prepared", candidate
end

function ProductionTailoringCraftAllRestart:ValidateAuthorization(submitted, professionKey, mode, clickOrigin, options)
    if type(submitted) ~= "table" or submitted.contract ~= self.authorizationContract then
        return false, "production-tailoring-craft-all-restart-authorization-invalid", nil, nil
    end
    self:_Sweep(now())
    local token = tostring(submitted.token or "")
    local stored = self.authorizations[token]
    if type(stored) ~= "table" then return false, "production-tailoring-craft-all-restart-authorization-expired-or-unknown", nil, nil end
    professionKey = normalizeKey(professionKey)
    mode = normalizeMode(mode)
    local clickToken = type(clickOrigin) == "table" and tostring(clickOrigin.token or "") or ""
    local exact = professionKey == "TAILORING"
        and normalizeKey(stored.professionKey) == professionKey
        and normalizeMode(stored.mode) == mode
        and clickToken ~= "" and tostring(stored.clickOriginToken or "") == clickToken
        and tostring(submitted.candidateToken or "") == tostring(stored.candidateToken or "")
        and tostring(submitted.interruptionToken or "") == tostring(stored.interruptionToken or "")
        and tostring(submitted.interruptionCategory or "") == tostring(stored.interruptionCategory or "")
        and tostring(submitted.priorLedgerID or "") == tostring(stored.priorLedgerID or "")
        and tonumber(submitted.priorRecipeID) == tonumber(stored.priorRecipeID)
        and tonumber(submitted.priorRouteIndex) == tonumber(stored.priorRouteIndex)
        and tonumber(submitted.priorSkillTarget) == tonumber(stored.priorSkillTarget)
        and tonumber(submitted.currentBuild) == tonumber(stored.currentBuild)
        and tostring(submitted.snapshotToken or "") == tostring(stored.snapshotToken or "")
        and tostring(submitted.stateFingerprint or "") == tostring(stored.stateFingerprint or "")
        and tonumber(submitted.recipeID) == tonumber(stored.recipeID)
        and tonumber(submitted.routeIndex) == tonumber(stored.routeIndex)
        and tonumber(submitted.skillTarget) == tonumber(stored.skillTarget)
        and submitted.explicitUserClick == true
        and submitted.freshTransactionRequired == true
        and submitted.automaticResume == false
        and submitted.priorTransactionReusable == false
        and submitted.sameRecipeRequired == true
        and submitted.sameTargetRequired == true
        and submitted.sameRouteRequired == true
        and tostring(submitted.provenanceContract or "") == self.provenanceContract
    if not exact then return false, "production-tailoring-craft-all-restart-authorization-tampered", nil, copy(stored) end

    local current = self:Evaluate(professionKey, mode, options)
    local currentExact = current and current.restartReady == true
        and tostring(current.candidateToken or "") == tostring(stored.candidateToken or "")
        and tostring(current.interruptionToken or "") == tostring(stored.interruptionToken or "")
        and tonumber(current.currentBuild) == tonumber(stored.currentBuild)
        and tostring(current.currentSnapshotToken or "") == tostring(stored.snapshotToken or "")
        and tostring(current.currentStateFingerprint or "") == tostring(stored.stateFingerprint or "")
        and tonumber(current.currentRecipeID) == tonumber(stored.recipeID)
        and tonumber(current.currentRouteIndex) == tonumber(stored.routeIndex)
        and tonumber(current.currentSkillTarget) == tonumber(stored.skillTarget)
    if not currentExact then return false, "production-tailoring-craft-all-restart-authorization-stale", current, copy(stored) end
    return true, "production-tailoring-craft-all-restart-authorization-current", current, copy(stored)
end

function ProductionTailoringCraftAllRestart:ConsumeAuthorization(authorizationOrToken, reason)
    local token = type(authorizationOrToken) == "table" and authorizationOrToken.token or authorizationOrToken
    token = tostring(token or "")
    local stored = self.authorizations[token]
    if not stored then return false, "production-tailoring-craft-all-restart-authorization-expired-or-unknown" end
    self.authorizations[token] = nil
    stored.consumed = true
    stored.consumedAt = now()
    stored.consumeReason = tostring(reason or "fresh-production-tailoring-craft-all-created")
    local key = normalizeKey(stored.professionKey)
    if key then
        self.consumedInterruptionByProfession[key] = stored.interruptionToken
        self.candidates[key] = nil
        local last = copy(stored)
        last.state = "production-tailoring-craft-all-restart-authorization-consumed"
        last.restartReady = false
        self.lastByProfession[key] = last
    end
    return true, "production-tailoring-craft-all-restart-authorization-consumed", copy(stored)
end

function ProductionTailoringCraftAllRestart:GetCandidate(professionKey, mode, options)
    local model = self:Evaluate(professionKey, mode, options)
    return model and model.restartReady == true and model or nil, model and model.state or "production-tailoring-craft-all-restart-unavailable", model
end

function ProductionTailoringCraftAllRestart:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ProductionTailoringCraftAllRestart:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "TAILORING"
    local model = self:Evaluate(professionKey, mode, options)
    local lines = {
        "PRODUCTION TAILORING CRAFT ALL / FRESH-CLICK RESTART",
        professionKey .. " / " .. normalizeMode(mode),
        "Contract: " .. self.contract,
        "State: " .. tostring(model.state),
        "Restart required: " .. (model.restartRequired and "yes" or "no"),
        "Restart ready: " .. (model.restartReady and "yes" or "no"),
        "Interruption: " .. tostring(model.interruptionCategory or "none"),
        "Prior ledger: " .. tostring(model.priorLedgerID or "none"),
        "Prior recipe: " .. tostring(model.priorRecipe or "none") .. " / " .. tostring(model.priorRecipeID or "unresolved"),
        "Current recipe: " .. tostring(model.currentRecipe or "none") .. " / " .. tostring(model.currentRecipeID or "unresolved"),
        "Route index: " .. tostring(model.currentRouteIndex or model.priorRouteIndex or "unknown"),
        "Target: " .. tostring(model.currentSkillTarget or model.priorSkillTarget or "unknown"),
        "Current skill: " .. tostring(model.currentSkill or "unknown"),
        "Explicit new Guide click: required",
        "Fresh ledger: required",
        "Same recipe / target / route: required",
        "Automatic resume after /reload: disabled",
        "Prior transaction reuse: forbidden",
        "Auto Route promotion: none",
        "Persistence: none",
    }
    return table.concat(lines, "\n")
end

function ProductionTailoringCraftAllRestart:Validate()
    local errors, warnings = {}, {}
    if self.automaticResume ~= false or self.priorTransactionReusable ~= false or self.sameRecipeRequired ~= true
        or self.sameTargetRequired ~= true or self.sameRouteRequired ~= true or self.persisted ~= false then
        errors[#errors+1] = "production Tailoring Craft All restart safety boundary invalid"
    end
    for _, name in ipairs({"ResearchNativeCraftAllInterruption","ProductionTailoringCraftAllAuthority","ResearchExecutionReadiness","Crafting"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "production Tailoring Craft All restart dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringCraftAllRestart", ProductionTailoringCraftAllRestart)
