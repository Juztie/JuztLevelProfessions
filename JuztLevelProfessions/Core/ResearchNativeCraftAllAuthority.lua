local _, JLP = ...

-- Alpha84 adds a dedicated research-native Craft All authority path. Unlike
-- Auto Route, this authority is permanently locked to the exact recipe that was
-- visible when the user clicked Craft All. Alpha87 keeps the aggregate Craft
-- All request but native dispatch is one ordinal at a time: after each confirmed
-- item the target/material/current-build boundaries are revalidated before the
-- next CraftRecipe(recipeID, 1) is authorized. It never follows a Planner route
-- change.
local ResearchNativeCraftAllAuthority = {
    contract = "guarded-native-current-recipe-craft-all-authority-v1",
    clickOriginContract = "research-craft-all-click-origin-v1",
    authorizationContract = "research-current-recipe-craft-all-authorization-v1",
    boundaryContract = "native-current-recipe-craft-all-boundary-v1",
    provenanceContract = "research-native-craft-all-provenance-v1",
    authority = "feature-gated-current-recipe-native-repeat-v1",
    persistedAuthorization = false,
    automaticRouteAdvance = false,
    targetPriority = "skill-target-first",
    fallbackStop = "current-recipe-material-exhaustion",
    originTTLSeconds = 3,
    authorizationTTLSeconds = 5,
    originSerial = 0,
    authorizationSerial = 0,
    origins = {},
    authorizations = {},
    activeAuthorizationByProfession = {},
    lastByProfession = {},
    initialized = false,
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
    for index = 1, #value do hash = (hash * 33 + string.byte(value, index)) % 2147483647 end
    return string.format("%08x", hash)
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function profile()
    local root = JLP.DB and JLP.DB.profile
    return root and root.researchCraftAllAuthority or nil
end

local function enabled()
    local p = profile()
    return p and p.enabled == true or false
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

function ResearchNativeCraftAllAuthority:IsFeatureEnabled()
    return enabled()
end

function ResearchNativeCraftAllAuthority:IsEffectiveEnabled()
    if not enabled() then return false end
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local native = JLP:GetModule("ResearchNativeExecutionAuthority")
    return eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()
        and native and native.IsFeatureEnabled and native:IsFeatureEnabled() or false
end

function ResearchNativeCraftAllAuthority:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    if not professionKey or professionKey == "ENCHANTING" then return false end
    local native = JLP:GetModule("ResearchNativeExecutionAuthority")
    return native and native.IsSupported and native:IsSupported(professionKey) or false
end

function ResearchNativeCraftAllAuthority:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if professionKey and type(report) == "table" then self.lastByProfession[professionKey] = shallowCopy(report) end
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_AUTHORITY_UPDATED", shallowCopy(report))
    end
    return report
end

function ResearchNativeCraftAllAuthority:_Sweep(nowValue)
    nowValue = tonumber(nowValue) or monotonicNow()
    for token, origin in pairs(self.origins or {}) do
        if type(origin) ~= "table" or (tonumber(origin.expiresAt) and nowValue > tonumber(origin.expiresAt)) then
            self.origins[token] = nil
        end
    end
    for token, authorization in pairs(self.authorizations or {}) do
        if type(authorization) ~= "table" or (tonumber(authorization.expiresAt) and nowValue > tonumber(authorization.expiresAt)) then
            if type(authorization) == "table" then
                local key = normalizeKey(authorization.professionKey)
                if key and self.activeAuthorizationByProfession[key] == token then self.activeAuthorizationByProfession[key] = nil end
            end
            self.authorizations[token] = nil
        end
    end
end

function ResearchNativeCraftAllAuthority:RevokeAuthorization(authorizationOrToken, reason)
    local token = type(authorizationOrToken) == "table" and authorizationOrToken.token or authorizationOrToken
    token = tostring(token or "")
    if token == "" then return false end
    local stored = self.authorizations[token]
    if not stored then return false end
    self.authorizations[token] = nil
    local key = normalizeKey(stored.professionKey)
    if key and self.activeAuthorizationByProfession[key] == token then self.activeAuthorizationByProfession[key] = nil end
    return true, reason or "revoked"
end

function ResearchNativeCraftAllAuthority:RevokeAll(reason)
    local count = 0
    for token in pairs(self.authorizations or {}) do
        if self:RevokeAuthorization(token, reason or "revoked-all") then count = count + 1 end
    end
    self.origins = {}
    return count
end

function ResearchNativeCraftAllAuthority:_Disarm(reason)
    local p = profile()
    if p then p.enabled = false end
    self:RevokeAll(reason or "dependency-disabled")
    local settlement = JLP:GetModule("ResearchNativeCraftAllSettlement")
    if settlement and settlement.OnKillSwitch then
        settlement:OnKillSwitch(reason or "research Craft All authority disabled")
    else
        local crafting = JLP:GetModule("Crafting")
        local pending = crafting and crafting.pendingCraft or nil
        local provenance = pending and pending.authorityProvenance or nil
        if crafting and crafting.StopRepeat and pending and pending.mode == "all"
            and type(provenance) == "table" and provenance.contract == self.provenanceContract then
            crafting:StopRepeat("research Craft All authority disabled", "success")
        end
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_AUTHORITY_UPDATED", {enabled=false,state=tostring(reason or "disabled")})
        JLP.EventBus:Emit("SETTINGS_CHANGED", "researchCraftAllAuthority", false)
    end
    return true
end

function ResearchNativeCraftAllAuthority:SetFeatureEnabled(value)
    local p = profile()
    if not p then return false, "profile-unavailable" end
    if value == true then
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        local native = JLP:GetModule("ResearchNativeExecutionAuthority")
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
        if not (native and native.IsFeatureEnabled and native:IsFeatureEnabled()) then
            return false, "native-execution-feature-gate-disabled"
        end
    end
    p.enabled = value == true
    self:RevokeAll("feature-gate-changed")
    if not p.enabled then
        local settlement = JLP:GetModule("ResearchNativeCraftAllSettlement")
        if settlement and settlement.OnKillSwitch then
            settlement:OnKillSwitch("research Craft All feature gate disabled")
        else
            local crafting = JLP:GetModule("Crafting")
            local pending = crafting and crafting.pendingCraft or nil
            local provenance = pending and pending.authorityProvenance or nil
            if crafting and crafting.StopRepeat and pending and pending.mode == "all"
                and type(provenance) == "table" and provenance.contract == self.provenanceContract then
                crafting:StopRepeat("research Craft All feature gate disabled", "success")
            end
        end
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_AUTHORITY_UPDATED", {enabled=p.enabled})
        JLP.EventBus:Emit("SETTINGS_CHANGED", "researchCraftAllAuthority", p.enabled)
    end
    return true, p.enabled and "enabled" or "disabled"
end

function ResearchNativeCraftAllAuthority:BeginClickOrigin(professionKey, mode, source)
    professionKey = normalizeKey(professionKey)
    mode = normalizeMode(mode)
    source = tostring(source or "")
    if not professionKey or source ~= "profession-guide" then return nil, "craft-all-click-origin-invalid" end
    if not self:IsEffectiveEnabled() then return nil, "research-craft-all-authority-disabled" end
    local nowValue = monotonicNow()
    self:_Sweep(nowValue)
    self.originSerial = (tonumber(self.originSerial) or 0) + 1
    local token = "craft-all-origin-" .. stateHash({professionKey, mode, source, tostring(self.originSerial), tostring(nowValue)})
    local origin = {
        contract=self.clickOriginContract,token=token,professionKey=professionKey,mode=mode,source=source,
        createdAt=nowValue,expiresAt=nowValue+self.originTTLSeconds,singleUse=true,persisted=false,
    }
    self.origins[token] = origin
    return shallowCopy(origin), "craft-all-click-origin-prepared"
end

function ResearchNativeCraftAllAuthority:_ConsumeOrigin(origin, professionKey, mode)
    if type(origin) ~= "table" or origin.contract ~= self.clickOriginContract then return false, "craft-all-click-origin-invalid", nil end
    local token = tostring(origin.token or "")
    self:_Sweep(monotonicNow())
    local stored = self.origins[token]
    if type(stored) ~= "table" then return false, "craft-all-click-origin-expired-or-unknown", nil end
    self.origins[token] = nil
    local exact = normalizeKey(stored.professionKey) == normalizeKey(professionKey)
        and normalizeMode(stored.mode) == normalizeMode(mode)
        and stored.source == "profession-guide"
        and tostring(origin.professionKey or "") == tostring(stored.professionKey or "")
        and tostring(origin.mode or "") == tostring(stored.mode or "")
        and tostring(origin.source or "") == tostring(stored.source or "")
    if not exact then return false, "craft-all-click-origin-tampered", shallowCopy(stored) end
    return true, "craft-all-click-origin-consumed", shallowCopy(stored)
end

function ResearchNativeCraftAllAuthority:PrepareAuthorization(professionKey, mode, clickOrigin, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    if not self:IsEffectiveEnabled() then return nil, "research-craft-all-authority-disabled", nil end
    if not self:IsSupported(professionKey) then return nil, "research-craft-all-profession-unsupported", nil end
    if self.activeAuthorizationByProfession[professionKey] then return nil, "research-craft-all-authorization-active", nil end

    local originOK, originState, storedOrigin = self:_ConsumeOrigin(clickOrigin, professionKey, mode)
    if not originOK then return nil, originState, nil end

    local restartStored = nil
    if type(options.restartAuthorization) == "table" then
        local restart = JLP:GetModule("ResearchNativeCraftAllRestart")
        if not restart or not restart.ValidateAuthorization then
            return nil, "craft-all-restart-boundary-unavailable", nil
        end
        local restartOK, restartState, _, validatedRestart = restart:ValidateAuthorization(options.restartAuthorization, professionKey, mode, storedOrigin, options)
        if not restartOK then return nil, restartState, nil end
        restartStored = validatedRestart
    end

    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local model = readiness and readiness.Evaluate and readiness:Evaluate(professionKey, mode, options) or nil
    if not model or model.executionReadinessReady ~= true then
        return nil, model and model.state or "execution-readiness-unavailable", model
    end
    local step = currentStep(model)
    local recipeID = currentRecipeID(model)
    local skillTarget = tonumber(step and step.skillTarget)
    local professionSkill = tonumber(model.professionSkill)
    local nativeCraftable = math.max(0, math.floor(tonumber(model.nativeCraftable) or 0))
    if not step or model.plan.actionKind ~= "craft" or not recipeID or tostring(step.recipe or "") == "" then
        return nil, "research-craft-all-recipe-unresolved", model
    end
    if not skillTarget or not professionSkill or professionSkill >= skillTarget then
        return nil, "research-craft-all-target-already-reached", model
    end
    if nativeCraftable < 1 then return nil, "research-craft-all-materials-unavailable", model end

    local nowValue = monotonicNow()
    self.authorizationSerial = (tonumber(self.authorizationSerial) or 0) + 1
    local token = "craft-all-authorization-" .. stateHash({
        professionKey, mode, tostring(model.currentBuild or ""), tostring(model.snapshotToken or ""),
        tostring(model.stateFingerprint or ""), tostring(recipeID), tostring(skillTarget), tostring(nativeCraftable),
        tostring(self.authorizationSerial), tostring(nowValue),
    })
    local authorization = {
        contract=self.authorizationContract,boundaryContract=self.boundaryContract,token=token,
        professionKey=professionKey,mode=mode,currentBuild=model.currentBuild,
        snapshotToken=model.snapshotToken,stateFingerprint=model.stateFingerprint,
        recipe=tostring(step.recipe),recipeID=recipeID,routeIndex=tonumber(step.routeIndex),skillTarget=skillTarget,
        startedSkill=professionSkill,requestedCount=nativeCraftable,nativeCraftable=nativeCraftable,
        clickOriginToken=storedOrigin and storedOrigin.token or nil,clickOriginSource="profession-guide",
        restartCandidateToken=restartStored and restartStored.candidateToken or nil,
        restartAuthorizationToken=restartStored and restartStored.token or nil,
        restartedFromInterruptionToken=restartStored and restartStored.interruptionToken or nil,
        restartedFromInterruptionCategory=restartStored and restartStored.interruptionCategory or nil,
        restartedFromInterruptionState=restartStored and restartStored.interruptionState or nil,
        restartedFromLedgerID=restartStored and restartStored.priorLedgerID or nil,
        restartPriorRecipeID=restartStored and tonumber(restartStored.priorRecipeID) or nil,
        restartPriorRouteIndex=restartStored and tonumber(restartStored.priorRouteIndex) or nil,
        restartPriorSkillTarget=restartStored and tonumber(restartStored.priorSkillTarget) or nil,
        restartExplicitUserClick=restartStored and restartStored.explicitUserClick==true or false,
        freshRestartTransaction=restartStored~=nil,
        recipeLocked=true,targetFirst=true,materialExhaustionSecond=true,automaticRouteAdvance=false,
        strictTargetSafeCraftAll=true,nativeDispatchPerOrdinal=1,
        createdAt=nowValue,expiresAt=nowValue+self.authorizationTTLSeconds,singleUse=true,persisted=false,
    }
    if restartStored then
        local restart = JLP:GetModule("ResearchNativeCraftAllRestart")
        local consumed = restart and restart.ConsumeAuthorization and select(1, restart:ConsumeAuthorization(restartStored.token, "fresh-craft-all-authorization-created")) or false
        if not consumed then return nil, "craft-all-restart-authorization-consume-failed", model end
    end
    self.authorizations[token] = authorization
    self.activeAuthorizationByProfession[professionKey] = token
    return shallowCopy(authorization), "research-craft-all-authorization-prepared", model
end

function ResearchNativeCraftAllAuthority:ValidateAuthorization(submitted, options)
    if type(submitted) ~= "table" or submitted.contract ~= self.authorizationContract then
        return false, "research-craft-all-authorization-invalid", nil, nil
    end
    local token = tostring(submitted.token or "")
    self:_Sweep(monotonicNow())
    local stored = self.authorizations[token]
    if type(stored) ~= "table" then return false, "research-craft-all-authorization-expired-or-unknown", nil, nil end
    local exact = tostring(submitted.professionKey or "") == tostring(stored.professionKey or "")
        and tostring(submitted.mode or "") == tostring(stored.mode or "")
        and tonumber(submitted.currentBuild) == tonumber(stored.currentBuild)
        and tostring(submitted.snapshotToken or "") == tostring(stored.snapshotToken or "")
        and tostring(submitted.stateFingerprint or "") == tostring(stored.stateFingerprint or "")
        and tostring(submitted.recipe or "") == tostring(stored.recipe or "")
        and tonumber(submitted.recipeID) == tonumber(stored.recipeID)
        and tonumber(submitted.routeIndex) == tonumber(stored.routeIndex)
        and tonumber(submitted.skillTarget) == tonumber(stored.skillTarget)
        and tonumber(submitted.requestedCount) == tonumber(stored.requestedCount)
        and submitted.recipeLocked == true and submitted.targetFirst == true
        and submitted.materialExhaustionSecond == true and submitted.automaticRouteAdvance == false
        and submitted.strictTargetSafeCraftAll == true and tonumber(submitted.nativeDispatchPerOrdinal) == 1
        and tostring(submitted.restartCandidateToken or "") == tostring(stored.restartCandidateToken or "")
        and tostring(submitted.restartAuthorizationToken or "") == tostring(stored.restartAuthorizationToken or "")
        and tostring(submitted.restartedFromInterruptionToken or "") == tostring(stored.restartedFromInterruptionToken or "")
        and tostring(submitted.restartedFromInterruptionCategory or "") == tostring(stored.restartedFromInterruptionCategory or "")
        and tostring(submitted.restartedFromLedgerID or "") == tostring(stored.restartedFromLedgerID or "")
        and submitted.restartExplicitUserClick == stored.restartExplicitUserClick
        and submitted.freshRestartTransaction == stored.freshRestartTransaction
    if not exact then return false, "research-craft-all-authorization-tampered", nil, shallowCopy(stored) end
    if not self:IsEffectiveEnabled() then return false, "research-craft-all-authorization-revoked", nil, shallowCopy(stored) end

    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local current = readiness and readiness.Evaluate and readiness:Evaluate(stored.professionKey, stored.mode, options or {}) or nil
    if not current or current.executionReadinessReady ~= true then
        return false, "research-craft-all-authorization-revoked", current, shallowCopy(stored)
    end
    local step = currentStep(current)
    local same = tonumber(current.currentBuild) == tonumber(stored.currentBuild)
        and tostring(current.snapshotToken or "") == tostring(stored.snapshotToken or "")
        and tostring(current.stateFingerprint or "") == tostring(stored.stateFingerprint or "")
        and tostring(current.recipe or "") == tostring(stored.recipe or "")
        and tonumber(currentRecipeID(current)) == tonumber(stored.recipeID)
        and tonumber(step and step.routeIndex) == tonumber(stored.routeIndex)
        and tonumber(step and step.skillTarget) == tonumber(stored.skillTarget)
        and tonumber(current.professionSkill) < tonumber(stored.skillTarget)
        and tonumber(current.nativeCraftable) == tonumber(stored.requestedCount)
        and tonumber(current.nativeCraftable) >= 1
    if not same then return false, "research-craft-all-authorization-stale", current, shallowCopy(stored) end
    return true, "research-craft-all-authorization-current", current, shallowCopy(stored)
end

function ResearchNativeCraftAllAuthority:Request(professionKey, mode, clickOrigin, options)
    local authorization, state, model = self:PrepareAuthorization(professionKey, mode, clickOrigin, options)
    if not authorization then
        local report = type(model) == "table" and {
            contract=self.contract,boundaryContract=self.boundaryContract,professionKey=normalizeKey(professionKey),mode=normalizeMode(mode),
            state=state,recipe=model.recipe,recipeID=model.recipeID,skillTarget=model.plan and model.plan.step and model.plan.step.skillTarget or nil,
            nativeCraftable=model.nativeCraftable,executionReadinessState=model.state,persistedAuthorization=false,
        } or {contract=self.contract,boundaryContract=self.boundaryContract,professionKey=normalizeKey(professionKey),mode=normalizeMode(mode),state=state,persistedAuthorization=false}
        self:_Record(professionKey, report)
        return false, state, report
    end
    local crafting = JLP:GetModule("Crafting")
    if not crafting or not crafting.NativeResearchCraftAllBoundary then
        self:RevokeAuthorization(authorization, "crafting-boundary-unavailable")
        local report={contract=self.contract,boundaryContract=self.boundaryContract,professionKey=authorization.professionKey,mode=authorization.mode,state="native-current-recipe-craft-all-boundary-unavailable",persistedAuthorization=false}
        self:_Record(professionKey,report)
        return false,report.state,report
    end
    local ok, boundaryState, report = crafting:NativeResearchCraftAllBoundary(authorization, options)
    report = type(report) == "table" and report or {}
    report.contract = self.contract
    report.boundaryContract = self.boundaryContract
    report.state = boundaryState or report.state
    self:_Record(professionKey, report)
    return ok and true or false, report.state, report
end

function ResearchNativeCraftAllAuthority:ObserveCraftAction(action)
    local provenance = type(action) == "table" and action.authorityProvenance or nil
    if type(provenance) ~= "table" or provenance.contract ~= self.provenanceContract then return false end
    local key = normalizeKey(action.key or provenance.professionKey)
    local report = {
        contract=self.contract,boundaryContract=self.boundaryContract,provenanceContract=self.provenanceContract,
        professionKey=key,mode=provenance.mode or "normal",
        state=action.status == "success" and "research-craft-all-complete" or (action.status == "failed" and "research-craft-all-failed" or "research-craft-all-in-flight"),
        transactionStatus=action.status,recipe=action.recipeName,recipeID=tonumber(action.recipeID),
        skillTarget=tonumber(action.targetSkill),startedSkill=tonumber(action.startedSkill),endingSkill=tonumber(action.endingSkill),
        targetReached=action.targetReached==true,requestedCount=tonumber(action.requestedCount) or 0,completedCount=tonumber(action.completedCount) or 0,
        ledgerID=action.ledgerID or action.transactionID,snapshotToken=provenance.snapshotToken,stateFingerprint=provenance.stateFingerprint,
        recipeLocked=true,automaticRouteAdvance=false,persistedAuthorization=false,
    }
    self:_Record(key, report)
    return true, report.state, report
end

function ResearchNativeCraftAllAuthority:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and shallowCopy(row) or nil
end

function ResearchNativeCraftAllAuthority:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local current = readiness and readiness.Evaluate and readiness:Evaluate(professionKey, mode, options or {}) or nil
    local last = self:GetLast(professionKey)
    local lines = {
        "RESEARCH CRAFT ALL / CURRENT RECIPE ONLY",
        professionKey .. " / " .. mode,
        "Contract: " .. self.contract,
        "Boundary: " .. self.boundaryContract,
        "Feature gate: " .. (self:IsFeatureEnabled() and "enabled" or "disabled"),
        "Effective authority: " .. (self:IsEffectiveEnabled() and "enabled" or "disabled"),
        "Recipe policy: exact recipeID locked at click",
        "Stop priority: target skill first · current-recipe material exhaustion second",
        "Native dispatch policy: one CraftRecipe(recipeID, 1) ordinal at a time",
        "Next ordinal policy: revalidate only after previous ordinal is confirmed",
        "Planner route changes during Craft All: ignored",
        "Automatic next-recipe dispatch: forbidden",
        "Authorization persistence: none",
        "Current readiness: " .. tostring(current and current.state or "unavailable"),
        "Current recipe: " .. tostring(current and current.recipe or "unknown") .. " / " .. tostring(current and current.recipeID or "unresolved"),
        "Current native craftable: " .. tostring(current and current.nativeCraftable or 0),
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines+1] = "Last progress: " .. tostring(last.completedCount or 0) .. " / " .. tostring(last.requestedCount or 0)
        lines[#lines+1] = "Last target reached: " .. (last.targetReached and "yes" or "no")
        lines[#lines+1] = "Last ledger: " .. tostring(last.ledgerID or "none")
    end
    return table.concat(lines, "\n")
end

function ResearchNativeCraftAllAuthority:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:_Disarm("execution-eligibility-gate-disabled") end
        end)
        JLP.EventBus:On("RESEARCH_NATIVE_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:_Disarm("native-execution-gate-disabled") end
        end)
    end
    return true
end

function ResearchNativeCraftAllAuthority:Validate()
    local errors, warnings = {}, {}
    if self.persistedAuthorization ~= false or self.automaticRouteAdvance ~= false then errors[#errors+1] = "research Craft All authority boundary invalid" end
    if self.targetPriority ~= "skill-target-first" or self.fallbackStop ~= "current-recipe-material-exhaustion" then errors[#errors+1] = "research Craft All stop priority invalid" end
    for _, name in ipairs({"ResearchExecutionReadiness","ResearchExecutionAuthorityGate","ResearchNativeExecutionAuthority","Crafting","TransactionLedger","TransactionRecovery","ResearchNativeCraftAllSettlement"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "research Craft All dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeCraftAllAuthority", ResearchNativeCraftAllAuthority)
