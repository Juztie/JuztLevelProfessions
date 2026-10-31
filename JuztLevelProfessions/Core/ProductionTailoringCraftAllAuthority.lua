local _, JLP = ...

-- Alpha101 promotes the production Tailoring route into dedicated Craft All authority. Unlike
-- Auto Route, this authority is permanently locked to the exact recipe that was
-- visible when the user clicked Craft All. Alpha87 keeps the aggregate Craft
-- All request but native dispatch is one ordinal at a time: after each confirmed
-- item the target/material/current-build boundaries are revalidated before the
-- next CraftRecipe(recipeID, 1) is authorized. It never follows a Planner route
-- change.
local ProductionTailoringCraftAllAuthority = {
    contract = "production-tailoring-native-current-recipe-craft-all-authority-v1",
    clickOriginContract = "production-tailoring-craft-all-click-origin-v1",
    authorizationContract = "production-tailoring-current-recipe-craft-all-authorization-v1",
    boundaryContract = "production-tailoring-native-current-recipe-craft-all-boundary-v1",
    provenanceContract = "production-tailoring-native-craft-all-provenance-v1",
    authority = "feature-gated-explicit-guide-click-production-tailoring-craft-all-v1",
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
    return root and root.productionTailoringCraftAllAuthority or nil
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

function ProductionTailoringCraftAllAuthority:IsFeatureEnabled()
    return enabled()
end

function ProductionTailoringCraftAllAuthority:IsEffectiveEnabled()
    if not enabled() then return false end
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    return eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()
        and native and native.IsEffectiveEnabled and native:IsEffectiveEnabled() or false
end

function ProductionTailoringCraftAllAuthority:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    if professionKey ~= "TAILORING" then return false end
    local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    return native and native.IsSupported and native:IsSupported(professionKey) or false
end

function ProductionTailoringCraftAllAuthority:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if professionKey and type(report) == "table" then self.lastByProfession[professionKey] = shallowCopy(report) end
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("PRODUCTION_TAILORING_CRAFT_ALL_AUTHORITY_UPDATED", shallowCopy(report))
    end
    return report
end

function ProductionTailoringCraftAllAuthority:_Sweep(nowValue)
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

function ProductionTailoringCraftAllAuthority:RevokeAuthorization(authorizationOrToken, reason)
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

function ProductionTailoringCraftAllAuthority:RevokeAll(reason)
    local count = 0
    for token in pairs(self.authorizations or {}) do
        if self:RevokeAuthorization(token, reason or "revoked-all") then count = count + 1 end
    end
    self.origins = {}
    return count
end

function ProductionTailoringCraftAllAuthority:_Disarm(reason)
    local p = profile()
    if p then p.enabled = false end
    self:RevokeAll(reason or "dependency-disabled")
    local settlement = JLP:GetModule("ResearchNativeCraftAllSettlement")
    if settlement and settlement.OnKillSwitch then
        settlement:OnKillSwitch(reason or "production Tailoring Craft All authority disabled")
    else
        local crafting = JLP:GetModule("Crafting")
        local pending = crafting and crafting.pendingCraft or nil
        local provenance = pending and pending.authorityProvenance or nil
        if crafting and crafting.StopRepeat and pending and pending.mode == "all"
            and type(provenance) == "table" and provenance.contract == self.provenanceContract then
            crafting:StopRepeat("production Tailoring Craft All authority disabled", "success")
        end
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_TAILORING_CRAFT_ALL_AUTHORITY_UPDATED", {enabled=false,state=tostring(reason or "disabled")})
        JLP.EventBus:Emit("SETTINGS_CHANGED", "productionTailoringCraftAllAuthority", false)
    end
    return true
end

function ProductionTailoringCraftAllAuthority:SetFeatureEnabled(value)
    local p = profile()
    if not p then return false, "profile-unavailable" end
    if value == true then
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
        if not (native and native.IsEffectiveEnabled and native:IsEffectiveEnabled()) then
            return false, "production-tailoring-native-execution-not-effective"
        end
    end
    p.enabled = value == true
    self:RevokeAll("feature-gate-changed")
    if not p.enabled then
        local settlement = JLP:GetModule("ResearchNativeCraftAllSettlement")
        if settlement and settlement.OnKillSwitch then
            settlement:OnKillSwitch("production Tailoring Craft All feature gate disabled")
        else
            local crafting = JLP:GetModule("Crafting")
            local pending = crafting and crafting.pendingCraft or nil
            local provenance = pending and pending.authorityProvenance or nil
            if crafting and crafting.StopRepeat and pending and pending.mode == "all"
                and type(provenance) == "table" and provenance.contract == self.provenanceContract then
                crafting:StopRepeat("production Tailoring Craft All feature gate disabled", "success")
            end
        end
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_TAILORING_CRAFT_ALL_AUTHORITY_UPDATED", {enabled=p.enabled})
        JLP.EventBus:Emit("SETTINGS_CHANGED", "productionTailoringCraftAllAuthority", p.enabled)
    end
    return true, p.enabled and "enabled" or "disabled"
end

function ProductionTailoringCraftAllAuthority:BeginClickOrigin(professionKey, mode, source)
    professionKey = normalizeKey(professionKey)
    mode = normalizeMode(mode)
    source = tostring(source or "")
    if not professionKey or source ~= "profession-guide" then return nil, "craft-all-click-origin-invalid" end
    if not self:IsEffectiveEnabled() then return nil, "production-tailoring-craft-all-authority-disabled" end
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

function ProductionTailoringCraftAllAuthority:_ConsumeOrigin(origin, professionKey, mode)
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

function ProductionTailoringCraftAllAuthority:PrepareAuthorization(professionKey, mode, clickOrigin, options)
    professionKey = normalizeKey(professionKey) or "TAILORING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    if not self:IsEffectiveEnabled() then return nil, "production-tailoring-craft-all-authority-disabled", nil end
    if not self:IsSupported(professionKey) then return nil, "production-tailoring-craft-all-profession-unsupported", nil end
    if self.activeAuthorizationByProfession[professionKey] then return nil, "production-tailoring-craft-all-authorization-active", nil end

    local originOK, originState, storedOrigin = self:_ConsumeOrigin(clickOrigin, professionKey, mode)
    if not originOK then return nil, originState, nil end

    local restartStored = nil
    if type(options.restartAuthorization) == "table" then
        local restart = JLP:GetModule("ProductionTailoringCraftAllRestart")
        if not restart or not restart.ValidateAuthorization then
            return nil, "production-tailoring-craft-all-restart-boundary-unavailable", nil
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
        return nil, "production-tailoring-craft-all-recipe-unresolved", model
    end
    if not skillTarget or not professionSkill or professionSkill >= skillTarget then
        return nil, "production-tailoring-craft-all-target-already-reached", model
    end
    if nativeCraftable < 1 then return nil, "production-tailoring-craft-all-materials-unavailable", model end

    local requestedCrafts=nativeCraftable
    if options and options.requestedCrafts ~= nil then
        local amount=tonumber(options.requestedCrafts)
        if type(options.requestedCrafts)~="number" or not amount or amount~=amount or
            amount==math.huge or amount==-math.huge or amount%1~=0 or amount<1 or amount>nativeCraftable or amount>9999 then
            return nil,"CRAFT_X_INVALID_OR_UNAFFORDABLE",model
        end
        requestedCrafts=amount
    end
    local nowValue = monotonicNow()
    self.authorizationSerial = (tonumber(self.authorizationSerial) or 0) + 1
    local token = "craft-all-authorization-" .. stateHash({
        professionKey, mode, tostring(model.currentBuild or ""), tostring(model.snapshotToken or ""),
        tostring(model.stateFingerprint or ""), tostring(recipeID), tostring(skillTarget), tostring(nativeCraftable), tostring(requestedCrafts),
        tostring(self.authorizationSerial), tostring(nowValue),
    })
    local authorization = {
        contract=self.authorizationContract,boundaryContract=self.boundaryContract,token=token,
        professionKey=professionKey,mode=mode,currentBuild=model.currentBuild,
        snapshotToken=model.snapshotToken,stateFingerprint=model.stateFingerprint,
        recipe=tostring(step.recipe),recipeID=recipeID,routeIndex=tonumber(step.routeIndex),skillTarget=skillTarget,
        startedSkill=professionSkill,requestedCount=requestedCrafts,nativeCraftable=nativeCraftable,
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
        local restart = JLP:GetModule("ProductionTailoringCraftAllRestart")
        local consumed = restart and restart.ConsumeAuthorization and select(1, restart:ConsumeAuthorization(restartStored.token, "fresh-production-tailoring-craft-all-authorization-created")) or false
        if not consumed then return nil, "production-tailoring-craft-all-restart-authorization-consume-failed", model end
    end
    self.authorizations[token] = authorization
    self.activeAuthorizationByProfession[professionKey] = token
    return shallowCopy(authorization), "production-tailoring-craft-all-authorization-prepared", model
end

function ProductionTailoringCraftAllAuthority:ValidateAuthorization(submitted, options)
    if type(submitted) ~= "table" or submitted.contract ~= self.authorizationContract then
        return false, "production-tailoring-craft-all-authorization-invalid", nil, nil
    end
    local token = tostring(submitted.token or "")
    self:_Sweep(monotonicNow())
    local stored = self.authorizations[token]
    if type(stored) ~= "table" then return false, "production-tailoring-craft-all-authorization-expired-or-unknown", nil, nil end
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
        and tonumber(submitted.nativeCraftable) == tonumber(stored.nativeCraftable)
        and tonumber(stored.requestedCount) >= 1 and tonumber(stored.requestedCount) <= tonumber(stored.nativeCraftable)
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
    if not exact then return false, "production-tailoring-craft-all-authorization-tampered", nil, shallowCopy(stored) end
    if not self:IsEffectiveEnabled() then return false, "production-tailoring-craft-all-authorization-revoked", nil, shallowCopy(stored) end

    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local current = readiness and readiness.Evaluate and readiness:Evaluate(stored.professionKey, stored.mode, options or {}) or nil
    if not current or current.executionReadinessReady ~= true then
        return false, "production-tailoring-craft-all-authorization-revoked", current, shallowCopy(stored)
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
        and tonumber(current.nativeCraftable) == tonumber(stored.nativeCraftable)
        and tonumber(current.nativeCraftable) >= 1
    if not same then return false, "production-tailoring-craft-all-authorization-stale", current, shallowCopy(stored) end
    return true, "production-tailoring-craft-all-authorization-current", current, shallowCopy(stored)
end

function ProductionTailoringCraftAllAuthority:Request(professionKey, mode, clickOrigin, options)
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
    if not crafting or not crafting.NativeTailoringCraftAllBoundary then
        self:RevokeAuthorization(authorization, "crafting-boundary-unavailable")
        local report={contract=self.contract,boundaryContract=self.boundaryContract,professionKey=authorization.professionKey,mode=authorization.mode,state="native-current-recipe-craft-all-boundary-unavailable",persistedAuthorization=false}
        self:_Record(professionKey,report)
        return false,report.state,report
    end
    local ok, boundaryState, report = crafting:NativeTailoringCraftAllBoundary(authorization, options)
    report = type(report) == "table" and report or {}
    report.contract = self.contract
    report.boundaryContract = self.boundaryContract
    report.state = boundaryState or report.state
    self:_Record(professionKey, report)
    return ok and true or false, report.state, report
end

function ProductionTailoringCraftAllAuthority:ObserveCraftAction(action)
    local provenance = type(action) == "table" and action.authorityProvenance or nil
    if type(provenance) ~= "table" or provenance.contract ~= self.provenanceContract then return false end
    local key = normalizeKey(action.key or provenance.professionKey)
    local report = {
        contract=self.contract,boundaryContract=self.boundaryContract,provenanceContract=self.provenanceContract,
        professionKey=key,mode=provenance.mode or "normal",
        state=action.status == "success" and "production-tailoring-craft-all-complete" or (action.status == "failed" and "production-tailoring-craft-all-failed" or "production-tailoring-craft-all-in-flight"),
        transactionStatus=action.status,recipe=action.recipeName,recipeID=tonumber(action.recipeID),
        skillTarget=tonumber(action.targetSkill),startedSkill=tonumber(action.startedSkill),endingSkill=tonumber(action.endingSkill),
        targetReached=action.targetReached==true,requestedCount=tonumber(action.requestedCount) or 0,completedCount=tonumber(action.completedCount) or 0,
        ledgerID=action.ledgerID or action.transactionID,snapshotToken=provenance.snapshotToken,stateFingerprint=provenance.stateFingerprint,
        recipeLocked=true,automaticRouteAdvance=false,persistedAuthorization=false,
    }
    self:_Record(key, report)
    return true, report.state, report
end

function ProductionTailoringCraftAllAuthority:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and shallowCopy(row) or nil
end

function ProductionTailoringCraftAllAuthority:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "TAILORING"
    mode = normalizeMode(mode)
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    local current = readiness and readiness.Evaluate and readiness:Evaluate(professionKey, mode, options or {}) or nil
    local last = self:GetLast(professionKey)
    local lines = {
        "PRODUCTION TAILORING CRAFT ALL / CURRENT RECIPE ONLY",
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
        "Restart policy: fresh explicit click + fresh ledger; old Craft All transaction never resumes",
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

function ProductionTailoringCraftAllAuthority:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:_Disarm("execution-eligibility-gate-disabled") end
        end)
        JLP.EventBus:On("PRODUCTION_TAILORING_NATIVE_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:_Disarm("production-tailoring-native-execution-gate-disabled") end
        end)
    end
    return true
end

function ProductionTailoringCraftAllAuthority:Validate()
    local errors, warnings = {}, {}
    if self.persistedAuthorization ~= false or self.automaticRouteAdvance ~= false then errors[#errors+1] = "production Tailoring Craft All authority boundary invalid" end
    if self.targetPriority ~= "skill-target-first" or self.fallbackStop ~= "current-recipe-material-exhaustion" then errors[#errors+1] = "production Tailoring Craft All stop priority invalid" end
    for _, name in ipairs({"ResearchExecutionReadiness","ResearchExecutionAuthorityGate","ProductionTailoringNativeExecutionAuthority","ProductionTailoringCraftAllRestart","Crafting","TransactionLedger","TransactionRecovery","ResearchNativeCraftAllSettlement"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "production Tailoring Craft All dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringCraftAllAuthority", ProductionTailoringCraftAllAuthority)
