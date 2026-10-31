local _, JLP = ...

-- Alpha115 keeps Enchanting sequence orchestration read-only, but removes all
-- caller authority over progression. The next ordinal is derived exclusively
-- from ProductionEnchantingCraftAllSession, whose settled prefix is backed by
-- terminal TransactionLedger success proofs. Enchanting remains one separate
-- target-bound enchant per explicit user action; there is no native multi-target
-- queue and this module never calls CraftEnchant.
local ProductionEnchantingCraftAllOrchestrator = {
    contract = "production-enchanting-proof-driven-single-target-orchestrator-v1",
    ordinalContract = "production-enchanting-craft-all-target-ordinal-plan-v2",
    authorityContract = "production-enchanting-current-recipe-craft-all-planning-authority-v1",
    batchContract = "production-enchanting-explicit-target-batch-v1",
    targetProofContract = "production-enchanting-craft-all-target-proof-v1",
    sessionContract = "production-enchanting-proof-driven-craft-all-session-v1",
    settlementProofContract = "production-enchanting-craft-all-ledger-settlement-proof-v1",
    authority = "read-only-proof-driven-explicit-target-sequence-v1",
    professionKey = "ENCHANTING",
    readOnly = true,
    executionEligible = false,
    executionAuthorityEnabled = false,
    nativeDispatchAllowed = false,
    nativeDispatchPerOrdinal = 0,
    futureNativeDispatchPerOrdinal = 1,
    nativeNumCastsPerAction = 1,
    automaticQueueAllowed = false,
    requiresExplicitUserActionPerOrdinal = true,
    automaticTargetSelectionAllowed = false,
    automaticTargetSkippingAllowed = false,
    automaticRouteAdvance = false,
    automaticResume = false,
    confirmationAutomationAllowed = false,
    persisted = false,
    maxActivePlans = 32,
    serial = 0,
    plans = {},
    planOrder = {},
    activePlanByBatch = {},
    lastByProfession = {},
    initialized = false,
}

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

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, row in pairs(value) do out[copy(key, seen)] = copy(row, seen) end
    return out
end

local function addGate(model, key, ready, state, detail)
    local row = {key=key,ready=ready and true or false,state=tostring(state or (ready and "pass" or "blocked")),detail=detail}
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

local function planToken(serial, batch, session, ordinal)
    local raw = table.concat({
        tostring(serial),
        tostring(batch and batch.token or ""),
        tostring(batch and batch.fingerprint or ""),
        tostring(session and session.sessionToken or ""),
        tostring(session and session.sessionFingerprint or ""),
        tostring(session and session.authorityGeneration or ""),
        tostring(ordinal or ""),
        tostring(now()),
    }, "|")
    local hash = 5381
    for index = 1, #raw do hash = (hash * 33 + string.byte(raw, index)) % 2147483647 end
    return string.format("enchant-sequence-ordinal-%08x", hash)
end

function ProductionEnchantingCraftAllOrchestrator:_DropPlan(token, reason)
    token = tostring(token or "")
    local stored = self.plans[token]
    if not stored then return false end
    self.plans[token] = nil
    if stored.batchToken and self.activePlanByBatch[stored.batchToken] == token then
        self.activePlanByBatch[stored.batchToken] = nil
    end
    stored.revoked = true
    stored.revokedReason = tostring(reason or "revoked")
    return true
end

function ProductionEnchantingCraftAllOrchestrator:_SweepPlans()
    local kept = {}
    for _, token in ipairs(self.planOrder or {}) do
        if self.plans[token] then kept[#kept + 1] = token end
    end
    self.planOrder = kept
    while #self.planOrder > self.maxActivePlans do
        local token = table.remove(self.planOrder, 1)
        self:_DropPlan(token, "plan-store-cap")
    end
end

function ProductionEnchantingCraftAllOrchestrator:RevokeAll(reason)
    local tokens = {}
    for token in pairs(self.plans or {}) do tokens[#tokens + 1] = token end
    local count = 0
    for _, token in ipairs(tokens) do if self:_DropPlan(token, reason or "revoked-all") then count = count + 1 end end
    self.planOrder = {}
    self.activePlanByBatch = {}
    return count
end

function ProductionEnchantingCraftAllOrchestrator:Evaluate(batch, sessionOrToken, options)
    options = type(options) == "table" and options or {}
    if options.completedCount ~= nil then
        return {
            contract=self.contract,
            professionKey=self.professionKey,
            state="production-enchanting-craft-all-caller-completed-count-forbidden",
            ordinalReady=false,
            readOnly=true,executionEligible=false,executionAuthorityEnabled=false,dispatchAllowed=false,nativeDispatchAllowed=false,
            gates={},stats={passedGates=0,totalGates=0},
        }
    end
    local authority = JLP:GetModule("ProductionEnchantingCraftAllAuthority")
    local sessionModule = JLP:GetModule("ProductionEnchantingCraftAllSession")
    local progress, progressState
    if sessionModule and sessionModule.GetVerifiedProgress and type(batch) == "table" then
        progress, progressState = sessionModule:GetVerifiedProgress(batch.token, sessionOrToken)
    end
    local completedCount = math.max(0, math.floor(tonumber(progress and progress.settledCount) or 0))
    local nextOrdinal = tonumber(progress and progress.nextOrdinal) or (completedCount + 1)
    local model = {
        contract=self.contract,
        ordinalContract=self.ordinalContract,
        sessionContract=self.sessionContract,
        settlementProofContract=self.settlementProofContract,
        authority=self.authority,
        professionKey=self.professionKey,
        state="production-enchanting-craft-all-ordinal-blocked",
        ordinalReady=false,
        completedCount=completedCount,
        nextOrdinal=nextOrdinal,
        requestedCount=tonumber(batch and batch.requestedCount) or 0,
        recipe=batch and batch.recipe or nil,
        recipeID=tonumber(batch and batch.recipeID),
        routeIndex=tonumber(batch and batch.routeIndex),
        skillTarget=tonumber(batch and batch.skillTarget),
        authorityGeneration=tonumber(batch and batch.authorityGeneration),
        sessionToken=progress and progress.sessionToken or nil,
        sessionFingerprint=progress and progress.sessionFingerprint or nil,
        readOnly=true,
        executionEligible=false,
        executionAuthorityEnabled=false,
        dispatchAllowed=false,
        nativeDispatchAllowed=false,
        nativeDispatchPerOrdinal=0,
        futureNativeDispatchPerOrdinal=1,
        nativeNumCastsPerAction=1,
        automaticQueueAllowed=false,
        requiresExplicitUserActionPerOrdinal=true,
        automaticTargetSelectionAllowed=false,
        automaticTargetSkippingAllowed=false,
        automaticRouteAdvance=false,
        automaticResume=false,
        confirmationAutomationAllowed=false,
        persisted=false,
        gates={},
        stats={passedGates=0,totalGates=0},
    }

    local shapeReady = type(batch) == "table" and batch.contract == self.batchContract
        and batch.authorityContract == self.authorityContract and batch.readOnly == true
        and batch.nativeDispatchAllowed == false and batch.automaticTargetSelection == false
        and batch.automaticTargetSkipping == false and batch.automaticRouteAdvance == false
        and batch.automaticQueueAllowed == false and batch.requiresExplicitUserActionPerOrdinal == true
        and tonumber(batch.nativeNumCastsPerAction) == 1
    addGate(model, "batch-contract", shapeReady, shapeReady and "production-enchanting-craft-all-batch-valid" or "production-enchanting-craft-all-batch-invalid", "explicit read-only target sequence required")

    local sessionReady = progress ~= nil and progress.contract == self.sessionContract
        and tonumber(progress.authorityGeneration) == tonumber(batch and batch.authorityGeneration)
        and tostring(progress.batchToken or "") == tostring(batch and batch.token or "")
    addGate(model, "proof-driven-session", sessionReady, sessionReady and "production-enchanting-craft-all-session-current" or tostring(progressState or "production-enchanting-craft-all-session-required"), "progress must come from verified ledger-backed session state")

    local current, batchState, consumer
    if authority and authority.ValidateTargetBatch and shapeReady and sessionReady then
        current, batchState, consumer = authority:ValidateTargetBatch(batch, {sessionToken=progress.sessionToken, consumerOptions=options.consumerOptions})
    end
    model.batchValidationState = batchState
    model.consumer = consumer
    addGate(model, "batch-current", current == true, current == true and "production-enchanting-craft-all-batch-current" or tostring(batchState or "production-enchanting-craft-all-batch-stale"), "unsettled suffix must remain live/current")

    local budgetReady = model.requestedCount >= 1 and completedCount < model.requestedCount and progress and progress.terminal ~= true
    addGate(model, "ordinal-budget", budgetReady, budgetReady and "production-enchanting-craft-all-ordinal-budget-open" or "production-enchanting-craft-all-target-batch-exhausted", string.format("settled=%d requested=%d", completedCount, model.requestedCount))

    local target = budgetReady and batch and batch.targets and batch.targets[model.nextOrdinal] or nil
    model.target = target and copy(target) or nil
    model.targetGUID = target and target.targetGUID or nil
    model.targetItemID = target and tonumber(target.targetItemID) or nil
    model.targetLocationKey = target and target.targetLocationKey or nil
    model.targetProofFingerprint = target and target.fingerprint or nil
    local exactOrdinal = target ~= nil and tonumber(target.ordinal) == model.nextOrdinal and target.singleUseTarget == true
    addGate(model, "exact-next-target", exactOrdinal, exactOrdinal and "production-enchanting-craft-all-next-explicit-target-bound" or "production-enchanting-craft-all-next-target-missing", "next ordinal is derived from settled ledger prefix; caller cannot skip")

    local targetCurrent = false
    local targetState = "production-enchanting-craft-all-next-target-unavailable"
    if authority and authority.CaptureTargetProof and target then
        local live, state = authority:CaptureTargetProof(model.recipeID, target.targetGUID)
        targetState = state or targetState
        targetCurrent = live ~= nil
            and tostring(live.fingerprint or "") == tostring(target.fingerprint or "")
            and tonumber(live.targetItemID) == tonumber(target.targetItemID)
            and tostring(live.targetLocationKey or "") == tostring(target.targetLocationKey or "")
            and tostring(live.targetValidationSource or "") == tostring(target.targetValidationSource or "")
        model.liveTarget = live
    end
    addGate(model, "next-target-proof-current", targetCurrent, targetCurrent and "production-enchanting-craft-all-next-target-current" or tostring(targetState), "ItemLocation/validity drift stops the sequence instead of skipping")

    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get(self.professionKey) or nil
    model.currentSkill = tonumber(profession and profession.skill)
    local skillReady = model.currentSkill ~= nil and model.skillTarget ~= nil and model.currentSkill < model.skillTarget
    addGate(model, "skill-target-open", skillReady, skillReady and "production-enchanting-craft-all-skill-target-open" or "production-enchanting-craft-all-skill-target-reached", string.format("skill=%s target=%s", tostring(model.currentSkill), tostring(model.skillTarget)))

    local flow = JLP:GetModule("ExecutionFlow")
    local windowKey = flow and flow.CaptureProfessionWindow and tostring(flow:CaptureProfessionWindow() or ""):upper() or ""
    model.professionWindowKey = windowKey
    local windowReady = windowKey == self.professionKey
    addGate(model, "profession-window", windowReady, windowReady and "production-enchanting-craft-all-profession-window-current" or "production-enchanting-craft-all-profession-window-lost", "Enchanting window must remain open")

    local crafting = JLP:GetModule("Crafting")
    local recovery = JLP:GetModule("TransactionRecovery")
    local recoveryReady, recoveryMessage = true, nil
    if recovery and recovery.CanStart then recoveryReady, recoveryMessage = recovery:CanStart("enchant", self.professionKey) end
    local transactionReady = crafting ~= nil and crafting.pendingCraft == nil and crafting.pendingEnchant == nil and recoveryReady == true
    addGate(model, "transaction-clear", transactionReady, transactionReady and "production-enchanting-craft-all-transaction-clear" or "production-enchanting-craft-all-transaction-blocked", tostring(recoveryMessage or "no live craft/enchant transaction"))

    local routeLock = batch and batch.recipeLocked == true and batch.automaticRouteAdvance == false
        and batch.targetOrderLocked == true and batch.automaticTargetSelection == false and batch.automaticTargetSkipping == false
    addGate(model, "route-target-lock", routeLock, routeLock and "production-enchanting-craft-all-route-target-lock-current" or "production-enchanting-craft-all-route-target-lock-invalid", "same recipe + exact ordered targets only")

    local clickModel = batch and batch.requiresExplicitUserActionPerOrdinal == true and batch.automaticQueueAllowed == false
        and tonumber(batch.nativeNumCastsPerAction) == 1
    addGate(model, "one-enchant-per-user-action", clickModel, clickModel and "production-enchanting-one-enchant-per-user-action" or "production-enchanting-native-queue-semantics-rejected", "Forever Enchanting sequence is one target-bound enchant per explicit action")

    if model.stats.passedGates == model.stats.totalGates then
        model.ordinalReady = true
        model.state = "production-enchanting-craft-all-ordinal-preflight-ready"
    else
        model.state = model.blockedState or "production-enchanting-craft-all-ordinal-blocked"
    end
    self.lastByProfession[self.professionKey] = copy(model)
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("PRODUCTION_ENCHANTING_CRAFT_ALL_ORCHESTRATOR_UPDATED", copy(model)) end
    return model
end

function ProductionEnchantingCraftAllOrchestrator:PrepareNextOrdinal(batch, sessionOrToken, options)
    local model = self:Evaluate(batch, sessionOrToken, options)
    if not model.ordinalReady then return nil, model.state, model end
    local existing = self.activePlanByBatch[tostring(batch.token or "")]
    if existing then self:_DropPlan(existing, "replaced-by-fresh-preflight") end
    self.serial = (tonumber(self.serial) or 0) + 1
    local progress = JLP:GetModule("ProductionEnchantingCraftAllSession"):GetVerifiedProgress(batch.token, sessionOrToken)
    local token = planToken(self.serial, batch, progress, model.nextOrdinal)
    local plan = {
        contract=self.ordinalContract,
        orchestratorContract=self.contract,
        authorityContract=self.authorityContract,
        batchContract=self.batchContract,
        targetProofContract=self.targetProofContract,
        sessionContract=self.sessionContract,
        settlementProofContract=self.settlementProofContract,
        token=token,
        batchToken=batch.token,
        batchFingerprint=batch.fingerprint,
        authorityGeneration=batch.authorityGeneration,
        sessionToken=progress and progress.sessionToken or nil,
        sessionFingerprint=progress and progress.sessionFingerprint or nil,
        professionKey=self.professionKey,
        mode=batch.mode,
        currentBuild=batch.currentBuild,
        recipe=batch.recipe,
        recipeID=batch.recipeID,
        routeIndex=batch.routeIndex,
        skillTarget=batch.skillTarget,
        requestedCount=batch.requestedCount,
        verifiedSettledCount=model.completedCount,
        ordinal=model.nextOrdinal,
        targetGUID=model.targetGUID,
        targetItemID=model.targetItemID,
        targetLocationKey=model.targetLocationKey,
        targetValidationSource=model.target and model.target.targetValidationSource or nil,
        targetProofFingerprint=model.targetProofFingerprint,
        singleUse=true,
        targetSingleUse=true,
        targetOrderLocked=true,
        recipeLocked=true,
        automaticQueue=false,
        requiresExplicitUserAction=true,
        nativeNumCasts=1,
        automaticTargetSelection=false,
        automaticTargetSkipping=false,
        automaticRouteAdvance=false,
        nativeDispatchPerOrdinal=0,
        futureNativeDispatchPerOrdinal=1,
        wouldDispatchCount=1,
        readOnly=true,
        executionEligible=false,
        executionAuthorityEnabled=false,
        dispatchAllowed=false,
        nativeDispatchAllowed=false,
        requiresFutureNativePromotion=true,
        confirmationAutomationAllowed=false,
        persisted=false,
        createdAt=now(),
    }
    self.plans[token] = copy(plan)
    self.planOrder[#self.planOrder + 1] = token
    self.activePlanByBatch[tostring(batch.token or "")] = token
    self:_SweepPlans()
    local sessionModule = JLP:GetModule("ProductionEnchantingCraftAllSession")
    local registered, registerState = false, "production-enchanting-sequence-origin-session-unavailable"
    if sessionModule and sessionModule.RegisterOrdinalPlan then
        registered, registerState = sessionModule:RegisterOrdinalPlan(sessionOrToken, batch, plan)
    end
    if registered ~= true then
        self:_DropPlan(token, registerState or "production-enchanting-sequence-origin-registration-failed")
        return nil, registerState or "production-enchanting-sequence-origin-registration-failed", model
    end
    plan.sequenceOriginContract = sessionModule.ordinalOriginContract
    self.plans[token] = copy(plan)
    return copy(plan), "production-enchanting-craft-all-ordinal-plan-prepared", model
end

function ProductionEnchantingCraftAllOrchestrator:ValidateOrdinalPlan(submitted, batch, sessionOrToken, options)
    if type(submitted) ~= "table" or submitted.contract ~= self.ordinalContract then
        return false, "production-enchanting-craft-all-ordinal-plan-invalid", nil
    end
    local stored = self.plans[tostring(submitted.token or "")]
    if type(stored) ~= "table" then return false, "production-enchanting-craft-all-ordinal-plan-expired-or-unknown", nil end
    local exact = tostring(submitted.batchToken or "") == tostring(stored.batchToken or "")
        and tostring(submitted.batchFingerprint or "") == tostring(stored.batchFingerprint or "")
        and tonumber(submitted.authorityGeneration) == tonumber(stored.authorityGeneration)
        and tostring(submitted.sessionToken or "") == tostring(stored.sessionToken or "")
        and tostring(submitted.sessionFingerprint or "") == tostring(stored.sessionFingerprint or "")
        and tonumber(submitted.recipeID) == tonumber(stored.recipeID)
        and tonumber(submitted.routeIndex) == tonumber(stored.routeIndex)
        and tonumber(submitted.skillTarget) == tonumber(stored.skillTarget)
        and tonumber(submitted.requestedCount) == tonumber(stored.requestedCount)
        and tonumber(submitted.verifiedSettledCount) == tonumber(stored.verifiedSettledCount)
        and tonumber(submitted.ordinal) == tonumber(stored.ordinal)
        and tostring(submitted.targetGUID or "") == tostring(stored.targetGUID or "")
        and tonumber(submitted.targetItemID) == tonumber(stored.targetItemID)
        and tostring(submitted.targetLocationKey or "") == tostring(stored.targetLocationKey or "")
        and tostring(submitted.targetProofFingerprint or "") == tostring(stored.targetProofFingerprint or "")
        and submitted.singleUse == true and submitted.readOnly == true
        and submitted.automaticQueue == false and submitted.requiresExplicitUserAction == true and tonumber(submitted.nativeNumCasts) == 1
        and submitted.executionEligible == false and submitted.dispatchAllowed == false and submitted.nativeDispatchAllowed == false
    if not exact then return false, "production-enchanting-craft-all-ordinal-plan-tampered", nil end

    local model = self:Evaluate(batch, sessionOrToken, options)
    local current = model.ordinalReady == true
        and tostring(batch and batch.token or "") == tostring(stored.batchToken or "")
        and tostring(batch and batch.fingerprint or "") == tostring(stored.batchFingerprint or "")
        and tonumber(batch and batch.authorityGeneration) == tonumber(stored.authorityGeneration)
        and tostring(model.sessionToken or "") == tostring(stored.sessionToken or "")
        and tonumber(model.nextOrdinal) == tonumber(stored.ordinal)
        and tonumber(model.completedCount) == tonumber(stored.verifiedSettledCount)
        and tostring(model.targetGUID or "") == tostring(stored.targetGUID or "")
        and tonumber(model.targetItemID) == tonumber(stored.targetItemID)
        and tostring(model.targetLocationKey or "") == tostring(stored.targetLocationKey or "")
        and tostring(model.targetProofFingerprint or "") == tostring(stored.targetProofFingerprint or "")
    if not current then return false, "production-enchanting-craft-all-ordinal-plan-stale", model end
    return true, "production-enchanting-craft-all-ordinal-plan-current", model, copy(stored)
end

function ProductionEnchantingCraftAllOrchestrator:ConsumeOrdinalPlan(token, reason)
    token = tostring(token or "")
    local stored = self.plans[token]
    if not stored then return false end
    return self:_DropPlan(token, reason or "consumed")
end

function ProductionEnchantingCraftAllOrchestrator:GetSummary()
    local last = self.lastByProfession[self.professionKey]
    local active = 0
    for _ in pairs(self.plans or {}) do active = active + 1 end
    local lines = {
        "PRODUCTION ENCHANTING / PROOF-DRIVEN TARGET-SEQUENCE ORCHESTRATOR",
        "Contract: " .. self.contract,
        "Ordinal plan: " .. self.ordinalContract,
        "Session contract: " .. self.sessionContract,
        "Progress authority: terminal TransactionLedger success only",
        "Caller-supplied completedCount: forbidden",
        "Policy: exactly one explicit target ordinal is projected at a time",
        "Native casts per explicit action: 1",
        "Automatic enchant queue: disabled",
        "New explicit user action required per ordinal: yes",
        "Target order: immutable",
        "Invalid/stale next target: stop; do not skip",
        "Recipe changes: forbidden",
        "Automatic target selection: forbidden",
        "Automatic route advance: forbidden",
        "Native dispatch per ordinal in alpha115: 0",
        "CraftEnchant from orchestrator: forbidden",
        "Protected confirmation automation: not implemented; secure client boundary",
        "Persistence / automatic resume: none",
        "Active plan store: " .. tostring(active) .. " / " .. tostring(self.maxActivePlans),
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = string.format("Last verified progress: %d / %d", tonumber(last.completedCount) or 0, tonumber(last.requestedCount) or 0)
        lines[#lines + 1] = "Last next target GUID: " .. tostring(last.targetGUID or "none")
        lines[#lines + 1] = "Last gates: " .. tostring(last.stats and last.stats.passedGates or 0) .. " / " .. tostring(last.stats and last.stats.totalGates or 0)
    end
    return table.concat(lines, "\n")
end

function ProductionEnchantingCraftAllOrchestrator:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("PRODUCTION_ENCHANTING_CRAFT_ALL_AUTHORITY_REVOKED", function(payload)
            self:RevokeAll(type(payload) == "table" and payload.reason or "authority-revoked")
        end)
    end
    return true
end

function ProductionEnchantingCraftAllOrchestrator:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.executionAuthorityEnabled ~= false
        or self.nativeDispatchAllowed ~= false or self.nativeDispatchPerOrdinal ~= 0
        or self.futureNativeDispatchPerOrdinal ~= 1 or self.nativeNumCastsPerAction ~= 1
        or self.automaticQueueAllowed ~= false or self.requiresExplicitUserActionPerOrdinal ~= true
        or self.automaticTargetSelectionAllowed ~= false or self.automaticTargetSkippingAllowed ~= false
        or self.automaticRouteAdvance ~= false or self.automaticResume ~= false
        or self.confirmationAutomationAllowed ~= false or self.persisted ~= false then
        errors[#errors + 1] = "production Enchanting target-sequence orchestrator safety boundary invalid"
    end
    for _, name in ipairs({"ProductionEnchantingCraftAllAuthority","ProductionEnchantingCraftAllSession","ProfessionAPI","ExecutionFlow","Crafting","TransactionRecovery"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "production Enchanting target-sequence orchestrator dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingCraftAllOrchestrator", ProductionEnchantingCraftAllOrchestrator)
