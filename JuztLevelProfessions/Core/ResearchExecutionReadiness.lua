local _, JLP = ...

-- Alpha73 execution-readiness authority gate for research-derived profession
-- routes. This module is deliberately evaluation-only: it can prove that the
-- current read-authority snapshot, live profession window, exact recipe,
-- materials and transaction state are coherent, and it can issue a short-lived
-- in-memory intent token for a second pre-dispatch validation. It never grants
-- execution authority and never calls CraftRecipe/CraftEnchant.
local ResearchExecutionReadiness = {
    contract = "controlled-execution-readiness-gate-v1",
    intentContract = "research-execution-intent-v1",
    authority = "evaluation-only-current-snapshot-execution-readiness",
    executionEligible = false,
    executionAuthorityEnabled = false,
    transferableToExecution = false,
    readOnly = true,
    persisted = false,
    intentTTLSeconds = 15,
    intentSerial = 0,
    intents = {},
}

local GATE_ORDER = {
    "consumer-authority",
    "snapshot-current",
    "build-provenance",
    "live-profession",
    "profession-window",
    "recipe-identity",
    "native-craft-api",
    "material-readiness",
    "native-craftability",
    "transaction-clear",
}

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return value
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function currentSessionReceipt()
    local runtime=JLP:GetModule("RuntimeCompatibility")
    return runtime and type(runtime.GetSessionReceipt)=="function"
        and runtime:GetSessionReceipt() or nil
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

local function expectedRecipeID(plan)
    local step = plan and plan.step or nil
    if not step then return nil end
    return tonumber(step.recipeID)
        or tonumber(step.rawStep and step.rawStep.recipeID)
        or tonumber(step.datasetStep and step.datasetStep.recipeID)
end

local function nativeProfessionWindow(api)
    local result={available=false,skillLineID=nil,name=nil,key=nil}
    -- Prefer the verified base-panel observation already supplied by
    -- ProfessionAPI. Never use a cached UI key to authorize native execution.
    if api and type(api.GetOpenProfessionContext)=="function" then
        local ok,ctx=pcall(api.GetOpenProfessionContext,api)
        if not ok or type(ctx)~="table" or ctx.verified~=true then return result end
        result.available=true
        result.skillLineID=tonumber(ctx.baseSkillLineID)
        result.name=ctx.displayName
        result.key=ctx.professionKey
        return result
    end
    -- Older clients with the *actual* legacy symbol retain a safe fallback.
    if type(C_TradeSkillUI)~="table" or type(C_TradeSkillUI.GetTradeSkillLine)~="function" then
        return result
    end
    local ok,skillLineID,name=pcall(C_TradeSkillUI.GetTradeSkillLine)
    if not ok or not skillLineID then return result end
    result.available=true
    result.skillLineID=tonumber(skillLineID) or skillLineID
    result.name=name
    result.key=api and api.KeyForSkillLine and api:KeyForSkillLine(name,skillLineID) or nil
    return result
end

local function recoveryState(recovery, professionKey)
    local status = recovery and recovery.GetStatus and recovery:GetStatus(professionKey) or nil
    return {
        state = status and status.state or "unavailable",
        revision = status and tonumber(status.revision) or (recovery and tonumber(recovery.revision)) or 0,
        retryAllowed = status and status.retryAllowed ~= false or true,
        snapshotID = status and status.snapshotID or nil,
    }
end

local function modelFingerprint(model)
    local gates = model and model.gates or {}
    local parts = {
        tostring(model and model.professionKey or ""),
        tostring(model and model.mode or ""),
        tostring(model and model.currentBuild or ""),
        tostring(model and model.clientSessionToken or ""),
        tostring(model and model.snapshotToken or ""),
        tostring(model and model.consumerStateFingerprint or ""),
        tostring(model and model.sourceReadinessPolicyContract or ""),
        tostring(model and model.sourceReadinessProofContract or ""),
        tostring(model and model.sourceReadinessFingerprint or ""),
        tostring(model and model.professionSkill or ""),
        tostring(model and model.professionMaxSkill or ""),
        tostring(model and model.windowKey or ""),
        tostring(model and model.windowSkillLineID or ""),
        tostring(model and model.recipe or ""),
        tostring(model and model.recipeID or ""),
        tostring(model and model.nativeRecipeName or ""),
        tostring(model and model.readinessStatus or ""),
        tostring(model and model.immediateBags or ""),
        tostring(model and model.nativeCraftable or ""),
        tostring(model and model.craftabilityStatus or ""),
        tostring(model and model.craftabilityReason or ""),
        tostring(model and model.targetGUID or ""),
        tostring(model and model.targetItemID or ""),
        tostring(model and model.targetLocationKey or ""),
        tostring(model and model.targetProofFingerprint or ""),
        tostring(model and model.recoveryState or ""),
        tostring(model and model.recoveryRevision or ""),
    }
    for _, key in ipairs(GATE_ORDER) do
        local row = gates[key]
        parts[#parts + 1] = key
        parts[#parts + 1] = row and (row.ready and "1" or "0") or "missing"
        parts[#parts + 1] = row and tostring(row.state or "") or ""
    end
    return stateHash(parts)
end

local function sourceReadinessPolicy(professionKey)
    professionKey = normalizeKey(professionKey)
    if professionKey == "TAILORING" then return JLP:GetModule("ProductionTailoringExecutionReadiness") end
    if professionKey == "ENCHANTING" then return JLP:GetModule("ProductionEnchantingExecutionReadiness") end
    return nil
end

function ResearchExecutionReadiness:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    local policy = sourceReadinessPolicy(professionKey)
    if policy and policy.IsSupported then return policy:IsSupported(professionKey) end
    local bridge = JLP:GetModule("ResearchRouteAuthorityBridge")
    return bridge and bridge.IsSupported and bridge:IsSupported(professionKey) or false
end

function ResearchExecutionReadiness:Evaluate(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    options = type(options) == "table" and options or {}
    local routeAuthority = JLP:GetModule("ResearchRouteAuthorityBridge")
    mode = normalizeMode(mode or (routeAuthority and routeAuthority.GetConfiguredMode and routeAuthority:GetConfiguredMode()) or "normal")

    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        state = "execution-readiness-blocked",
        currentBuild = currentBuild(),
        executionReadinessReady = false,
        candidateEligible = false,
        intentEligible = false,
        executionEligible = false,
        executionAuthorityEnabled = false,
        transferable = false,
        readOnly = true,
        persisted = false,
        dispatchAllowed = false,
        gates = {},
        stats = { passedGates=0, totalGates=0 },
    }

    if not self:IsSupported(professionKey) and not options.allowHarness then
        model.state = "execution-readiness-unsupported-profession"
        model.blockedReason = "execution-readiness-authority-not-promoted"
        return model
    end

    local consumerBridge = JLP:GetModule("ResearchPlannerConsumerBridge")
    local consumer = consumerBridge and consumerBridge.Build and consumerBridge:Build(professionKey, mode, options) or nil
    local consumerReady = consumer and consumer.state == "consumer-authority-active"
        and consumer.consumerAuthorityEnabled == true
        and consumer.routeAuthorityEnabled == true
        and consumer.plannerEligible == true
        and consumer.executionEligible == false
        and consumer.snapshot ~= nil
    addGate(model, "consumer-authority", consumerReady,
        consumer and consumer.state or "consumer-bridge-unavailable",
        consumerReady and "current read-only consumer authority active" or "read-only consumer authority unavailable")

    local snapshotValid, snapshotState, currentConsumer = false, "consumer-snapshot-unavailable", consumer
    if consumerReady and consumerBridge and consumerBridge.ValidateSnapshot then
        snapshotValid, snapshotState, currentConsumer = consumerBridge:ValidateSnapshot(consumer.snapshot, professionKey, mode, options)
        if snapshotValid and currentConsumer then consumer = currentConsumer end
    end
    addGate(model, "snapshot-current", snapshotValid == true, snapshotState,
        snapshotValid and "consumer snapshot rebuilt and matched" or "consumer snapshot was stale or revoked")

    model.consumer = consumer
    model.snapshot = consumer and consumer.snapshot or nil
    model.snapshotToken = consumer and consumer.snapshotToken or nil
    model.consumerStateFingerprint = consumer and consumer.stateFingerprint or nil
    model.plan = consumer and consumer.plan or nil
    model.readiness = consumer and consumer.readiness or nil
    model.dataset = consumer and consumer.dataset or nil

    local sourcePolicy = sourceReadinessPolicy(professionKey)
    local sourceAssessment = sourcePolicy and sourcePolicy.Assess and sourcePolicy:Assess(consumer) or nil
    model.sourceReadinessPolicyContract = sourcePolicy and sourcePolicy.contract or nil
    model.sourceReadinessProofContract = sourcePolicy and sourcePolicy.proofContract or nil
    model.sourceReadinessFingerprint = sourceAssessment and sourceAssessment.stateFingerprint or nil
    model.sourceReadinessState = sourceAssessment and sourceAssessment.state or nil
    model.sourceReadiness = sourceAssessment

    local build = currentBuild()
    model.currentBuild = build
    local snapshotBuild = model.snapshot and tonumber(model.snapshot.currentBuild) or nil
    local datasetBuild = model.dataset and tonumber(model.dataset.currentBuild) or nil
    local liveSessionToken=currentSessionReceipt()
    model.clientSessionToken=liveSessionToken
    local buildReady = snapshotValid and build ~= nil and snapshotBuild == build and datasetBuild == build
        and liveSessionToken~=nil and model.snapshot.clientSessionToken==liveSessionToken
        and currentConsumer and currentConsumer.clientSessionToken==liveSessionToken
    addGate(model, "build-provenance", buildReady,
        buildReady and "current-build-coherent" or "build-provenance-mismatch",
        string.format("live=%s snapshot=%s dataset=%s", tostring(build), tostring(snapshotBuild), tostring(datasetBuild)))

    local api = JLP:GetModule("ProfessionAPI")
    local liveProfession = api and api.Get and api:Get(professionKey) or nil
    model.liveProfession = liveProfession
    model.professionSkill = tonumber(liveProfession and liveProfession.skill)
    model.professionMaxSkill = tonumber(liveProfession and liveProfession.maxSkill)
    local liveProfessionReady = liveProfession ~= nil
        and liveProfession.cached ~= true
        and normalizeKey(liveProfession.key or professionKey) == professionKey
        and model.professionSkill ~= nil
        and model.professionMaxSkill ~= nil
    addGate(model, "live-profession", liveProfessionReady,
        liveProfessionReady and "live-profession-current" or "live-profession-unavailable",
        liveProfessionReady and string.format("%d/%d", model.professionSkill or 0, model.professionMaxSkill or 0) or "cached/missing profession state")

    local flow = JLP:GetModule("ExecutionFlow")
    local flowKey = flow and flow.CaptureProfessionWindow and flow:CaptureProfessionWindow() or nil
    local window = nativeProfessionWindow(api)
    model.windowKey = normalizeKey(window.key or flowKey)
    model.windowSkillLineID = window.skillLineID
    model.windowName = window.name
    local windowReady = window.available == true
        and normalizeKey(window.key) == professionKey
        and normalizeKey(flowKey) == professionKey
    addGate(model, "profession-window", windowReady,
        windowReady and "profession-window-exact" or "profession-window-mismatch",
        string.format("expected=%s live=%s", professionKey, tostring(window.key or flowKey or "closed")))

    local crafting = JLP:GetModule("Crafting")
    local plan = model.plan
    local recipe = plan and plan.step and plan.step.recipe or nil
    local expectedID = expectedRecipeID(plan)
    local resolvedID
    local recipeIdentityReady
    if (professionKey == "TAILORING" or professionKey == "ENCHANTING") and sourceAssessment then
        resolvedID = tonumber(sourceAssessment.liveRecipeID)
        recipeIdentityReady = sourceAssessment.ready == true
            and sourceAssessment.recipeIdentityReady == true
            and tonumber(sourceAssessment.recipeID) == tonumber(expectedID)
            and normalizeText(sourceAssessment.recipe) == normalizeText(recipe)
    else
        resolvedID = crafting and crafting.ResolveRecipeID and recipe and crafting:ResolveRecipeID(professionKey, recipe) or nil
        recipeIdentityReady = recipe ~= nil and expectedID ~= nil and tonumber(resolvedID) ~= nil and expectedID == tonumber(resolvedID)
    end
    model.recipe = recipe
    model.expectedRecipeID = expectedID
    model.recipeID = tonumber(resolvedID)
    local recipeIdentityState = "exact-recipe-identity"
    if professionKey == "TAILORING" then recipeIdentityState = "production-tailoring-live-identity" end
    if professionKey == "ENCHANTING" then recipeIdentityState = "production-enchanting-live-target-bound-identity" end
    addGate(model, "recipe-identity", recipeIdentityReady,
        recipeIdentityReady and recipeIdentityState or "recipe-identity-mismatch",
        string.format("recipe=%s stagedID=%s liveID=%s source=%s", tostring(recipe), tostring(expectedID), tostring(model.recipeID), tostring(model.sourceReadinessState or "generic")))

    local professionAPI=JLP:GetModule("ProfessionAPI")
    local nativeContext=professionAPI and type(professionAPI.GetExecutionRecipeContext)=="function"
        and model.recipeID and professionAPI:GetExecutionRecipeContext(model.recipeID,
            professionKey,professionKey=="ENCHANTING" and "enchant" or "craft") or nil
    model.commonRecipeContext=nativeContext
    local nativeAPIReady=nativeContext~=nil and nativeContext.nativeCapability==true
    local nativeRecipeInfo=nativeContext and nativeContext.verified==true
        and nativeContext.recipeInfo or nil
    model.nativeRecipeName = nativeRecipeInfo and nativeRecipeInfo.name or nil
    local sourceNativeReady = true
    if professionKey == "TAILORING" then
        sourceNativeReady = sourceAssessment and sourceAssessment.ready == true and sourceAssessment.liveRecipeLearned == true
    elseif professionKey == "ENCHANTING" then
        sourceNativeReady = sourceAssessment and sourceAssessment.ready == true
            and sourceAssessment.liveRecipeLearned == true and sourceAssessment.targetIdentityReady == true
    end
    local nativeRecipeReady = nativeAPIReady
        and nativeRecipeInfo ~= nil
        and normalizeText(model.nativeRecipeName) == normalizeText(recipe)
        and nativeContext~=nil and nativeContext.executionReady==true
        and sourceNativeReady
    addGate(model, "native-craft-api", nativeRecipeReady,
        nativeRecipeReady and "native-recipe-visible" or (nativeAPIReady and "native-recipe-mismatch" or "native-craft-api-unavailable"),
        nativeRecipeReady and tostring(model.nativeRecipeName) or "exact recipe not visible through native TradeSkill API")

    local readiness = model.readiness
    model.readinessStatus = readiness and readiness.status or nil
    model.immediateBags = readiness and readiness.immediateBagsKnown ~= false and tonumber(readiness.immediateBags) or nil
    model.materialEvidenceKnown = readiness and readiness.immediateBagsKnown == true or false
    local sourceRecipeLearned = (professionKey == "TAILORING" or professionKey == "ENCHANTING")
        and sourceAssessment and sourceAssessment.liveRecipeLearned == true
    local liveRecipeKnowledgeReady = readiness and readiness.recipeKnowledge == "known" or sourceRecipeLearned
    local readinessMaterialStateReady = readiness and readiness.status == "ready"
        or ((professionKey == "TAILORING" or professionKey == "ENCHANTING") and readiness and readiness.status == "verify" and readiness.blocker == "recipe-unknown" and sourceRecipeLearned)
    local materialReady = readiness ~= nil
        and readinessMaterialStateReady
        and liveRecipeKnowledgeReady
        and model.materialEvidenceKnown
        and model.immediateBags ~= nil and model.immediateBags >= 1
    addGate(model, "material-readiness", materialReady,
        materialReady and "current-bag-materials-ready" or "current-materials-not-ready",
        string.format("status=%s recipe=%s immediate=%s bag-evidence=%s", tostring(model.readinessStatus), tostring(readiness and readiness.recipeKnowledge or "unknown"), tostring(model.immediateBags or "UNKNOWN"), tostring(model.materialEvidenceKnown)))

    local nativeCraftable
    local craftableReady
    if professionKey == "ENCHANTING" then
        nativeCraftable = sourceAssessment and sourceAssessment.targetIdentityReady == true and 1 or 0
        model.nativeCraftable = nativeCraftable
        model.craftabilityStatus = "TARGET_CONTEXT"
        model.craftabilityReason = "target-identity-evidence"
        model.targetGUID = sourceAssessment and sourceAssessment.targetGUID or nil
        model.targetItemID = sourceAssessment and sourceAssessment.targetItemID or nil
        model.targetValidationSource = sourceAssessment and sourceAssessment.targetValidationSource or nil
        model.targetLocationKey = sourceAssessment and sourceAssessment.targetLocationKey or nil
        model.targetProofContract = sourceAssessment and sourceAssessment.targetProofContract or nil
        model.targetProofFingerprint = sourceAssessment and sourceAssessment.targetProofFingerprint or nil
        craftableReady = nativeRecipeReady and nativeCraftable == 1
        addGate(model, "native-craftability", craftableReady,
            craftableReady and "native-enchant-target-ready" or "native-enchant-target-not-ready",
            "target=" .. tostring(model.targetGUID or "none") .. " location=" .. tostring(model.targetLocationKey or "none"))
    else
        local countStatus,countReason="UNKNOWN","craftability-module-unavailable"
        if crafting and type(crafting.GetCraftableCount)=="function" and model.recipeID then
            nativeCraftable,countStatus,countReason=crafting:GetCraftableCount(model.recipeID)
        end
        model.nativeCraftable=nativeCraftable
        model.craftabilityStatus=countStatus
        model.craftabilityReason=countReason
        craftableReady=nativeRecipeReady and countStatus=="KNOWN" and nativeCraftable~=nil and nativeCraftable>=1
        local gateState=craftableReady and "native-craftable-now"
            or (countStatus~="KNOWN" and "native-craftability-unavailable"
            or (nativeCraftable==0 and "native-craftable-zero" or "native-recipe-not-ready"))
        addGate(model,"native-craftability",craftableReady,gateState,
            "status="..tostring(countStatus).." reason="..tostring(countReason).." count="..tostring(nativeCraftable or "unknown"))
    end

    local recovery = JLP:GetModule("TransactionRecovery")
    local allowed, recoveryMessage = true, nil
    local recoveryKind = professionKey == "ENCHANTING" and "enchant" or "craft"
    if recovery and recovery.CanStart then allowed, recoveryMessage = recovery:CanStart(recoveryKind, professionKey) end
    local recoveryInfo = recoveryState(recovery, professionKey)
    model.recoveryState = recoveryInfo.state
    model.recoveryRevision = recoveryInfo.revision
    local noPending = not (crafting and crafting.pendingCraft) and not (crafting and crafting.pendingEnchant)
    local transactionReady = noPending and allowed ~= false and recoveryInfo.state ~= "UNRESOLVED"
    addGate(model, "transaction-clear", transactionReady,
        transactionReady and "transaction-boundary-clear" or "transaction-boundary-blocked",
        recoveryMessage or (noPending and tostring(recoveryInfo.state) or "live craft/enchant already pending"))

    -- Final verification: any API inside this evaluation could change the
    -- interface while the numerical build remains constant. Do not turn an
    -- earlier ready gate into native-intent eligibility after such a change.
    if not model.clientSessionToken or
       currentSessionReceipt()~=model.clientSessionToken then
        local gate=model.gates["build-provenance"]
        if gate and gate.ready then
            gate.ready=false
            gate.state="client-session-changed-during-readiness"
            gate.detail="full build/interface receipt changed or became unknown"
            model.stats.passedGates=model.stats.passedGates-1
            model.blockedGate=model.blockedGate or "build-provenance"
            model.blockedState=model.blockedState or gate.state
        end
        model.clientSessionToken=nil
    end
    model.stateFingerprint = modelFingerprint(model)
    model.stats.blockedGates = model.stats.totalGates - model.stats.passedGates
    if model.stats.totalGates == #GATE_ORDER and model.stats.passedGates == #GATE_ORDER then
        model.state = "execution-readiness-ready"
        model.executionReadinessReady = true
        model.candidateEligible = true
        model.intentEligible = true
    else
        model.state = "execution-readiness-blocked"
    end
    return model
end

function ResearchExecutionReadiness:_SweepIntents(nowValue)
    nowValue = tonumber(nowValue) or monotonicNow()
    for token, intent in pairs(self.intents or {}) do
        if type(intent) ~= "table" or (tonumber(intent.expiresAt) and nowValue > tonumber(intent.expiresAt)) then
            self.intents[token] = nil
        end
    end
end

function ResearchExecutionReadiness:PrepareIntent(professionKey, mode, options)
    local model = self:Evaluate(professionKey, mode, options)
    if not model or model.executionReadinessReady ~= true then
        return nil, model and model.state or "execution-readiness-unavailable", model
    end
    local nowValue = monotonicNow()
    self:_SweepIntents(nowValue)
    self.intentSerial = (tonumber(self.intentSerial) or 0) + 1
    local rawToken = table.concat({
        tostring(model.professionKey), tostring(model.mode), tostring(model.currentBuild),
        tostring(model.clientSessionToken),
        tostring(model.snapshotToken), tostring(model.stateFingerprint), tostring(self.intentSerial), tostring(nowValue),
    }, "|")
    local token = "exec-intent-" .. stateHash({rawToken})
    local intent = {
        contract = self.intentContract,
        token = token,
        professionKey = model.professionKey,
        mode = model.mode,
        currentBuild = model.currentBuild,
        clientSessionToken = model.clientSessionToken,
        snapshotToken = model.snapshotToken,
        stateFingerprint = model.stateFingerprint,
        sourceReadinessPolicyContract = model.sourceReadinessPolicyContract,
        sourceReadinessProofContract = model.sourceReadinessProofContract,
        sourceReadinessFingerprint = model.sourceReadinessFingerprint,
        recipe = model.recipe,
        recipeID = model.recipeID,
        targetGUID = model.targetGUID,
        targetItemID = model.targetItemID,
        targetValidationSource = model.targetValidationSource,
        targetLocationKey = model.targetLocationKey,
        targetProofContract = model.targetProofContract,
        targetProofFingerprint = model.targetProofFingerprint,
        createdAt = nowValue,
        expiresAt = nowValue + self.intentTTLSeconds,
        readOnly = true,
        persisted = false,
        executionEligible = false,
        dispatchAllowed = false,
        singleUseBoundary = true,
    }
    self.intents[token] = intent
    return shallowCopy(intent), "execution-intent-prepared", model
end

function ResearchExecutionReadiness:ValidateIntent(intentOrToken, professionKey, mode, options)
    local token = type(intentOrToken) == "table" and intentOrToken.token or intentOrToken
    token = tostring(token or "")
    if token == "" then return false, "invalid-execution-intent", nil end
    self:_SweepIntents(monotonicNow())
    local intent = self.intents[token]
    if type(intent) ~= "table" or intent.contract ~= self.intentContract then
        return false, "execution-intent-expired-or-unknown", nil
    end
    professionKey = normalizeKey(professionKey or intent.professionKey)
    mode = normalizeMode(mode or intent.mode)
    if professionKey ~= normalizeKey(intent.professionKey) then
        return false, "execution-intent-profession-mismatch", nil
    end
    if mode ~= intent.mode then return false, "execution-intent-mode-mismatch", nil end

    local current = self:Evaluate(professionKey, mode, options)
    if not current or current.executionReadinessReady ~= true then
        return false, "execution-intent-revoked", current
    end
    if tonumber(intent.currentBuild) ~= tonumber(current.currentBuild)
        or type(intent.clientSessionToken)~="string" or intent.clientSessionToken==""
        or intent.clientSessionToken~=current.clientSessionToken
        or tostring(intent.snapshotToken or "") ~= tostring(current.snapshotToken or "")
        or tostring(intent.stateFingerprint or "") ~= tostring(current.stateFingerprint or "")
        or tostring(intent.sourceReadinessPolicyContract or "") ~= tostring(current.sourceReadinessPolicyContract or "")
        or tostring(intent.sourceReadinessProofContract or "") ~= tostring(current.sourceReadinessProofContract or "")
        or tostring(intent.sourceReadinessFingerprint or "") ~= tostring(current.sourceReadinessFingerprint or "")
        or tonumber(intent.recipeID) ~= tonumber(current.recipeID)
        or tostring(intent.targetGUID or "") ~= tostring(current.targetGUID or "")
        or tonumber(intent.targetItemID) ~= tonumber(current.targetItemID)
        or tostring(intent.targetValidationSource or "") ~= tostring(current.targetValidationSource or "")
        or tostring(intent.targetLocationKey or "") ~= tostring(current.targetLocationKey or "")
        or tostring(intent.targetProofContract or "") ~= tostring(current.targetProofContract or "")
        or tostring(intent.targetProofFingerprint or "") ~= tostring(current.targetProofFingerprint or "") then
        return false, "execution-intent-stale", current
    end
    return true, "execution-intent-current", current
end

function ResearchExecutionReadiness:RevokeIntent(intentOrToken)
    local token = type(intentOrToken) == "table" and intentOrToken.token or intentOrToken
    token = tostring(token or "")
    if token == "" or not self.intents[token] then return false end
    self.intents[token] = nil
    return true
end

function ResearchExecutionReadiness:RevokeIntentsForProfession(professionKey, reason)
    professionKey = normalizeKey(professionKey)
    local count = 0
    for token, intent in pairs(self.intents or {}) do
        if professionKey == nil or normalizeKey(intent and intent.professionKey) == professionKey then
            self.intents[token] = nil
            count = count + 1
        end
    end
    return count, reason or "revoked"
end

function ResearchExecutionReadiness:CountIntentsForProfession(professionKey)
    professionKey = normalizeKey(professionKey)
    local count = 0
    for _, intent in pairs(self.intents or {}) do
        if professionKey == nil or normalizeKey(intent and intent.professionKey) == professionKey then
            count = count + 1
        end
    end
    return count
end

function ResearchExecutionReadiness:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local model = self:Evaluate(professionKey, mode, options)
    local lines = {
        "RESEARCH EXECUTION READINESS / EVALUATION ONLY",
        string.format("%s / %s", professionKey, tostring(model.mode or "normal")),
        "State: " .. tostring(model.state),
        string.format("Gates: %d pass / %d total", tonumber(model.stats and model.stats.passedGates) or 0, tonumber(model.stats and model.stats.totalGates) or 0),
    }
    for _, key in ipairs(GATE_ORDER) do
        local row = model.gates and model.gates[key] or nil
        lines[#lines + 1] = string.format("· %s: %s%s", key, row and (row.ready and "pass" or "blocked") or "missing", row and row.state and (" · " .. tostring(row.state)) or "")
    end
    if model.blockedGate then
        lines[#lines + 1] = "Blocked gate: " .. tostring(model.blockedGate)
        lines[#lines + 1] = "Blocked state: " .. tostring(model.blockedState)
    end
    lines[#lines + 1] = "Snapshot token: " .. tostring(model.snapshotToken or "none")
    if model.sourceReadinessPolicyContract then
        lines[#lines + 1] = "Source readiness policy: " .. tostring(model.sourceReadinessPolicyContract)
        lines[#lines + 1] = "Source readiness state: " .. tostring(model.sourceReadinessState or "unavailable")
    end
    lines[#lines + 1] = "Recipe identity: " .. tostring(model.recipe or "unknown") .. " / " .. tostring(model.recipeID or "unresolved")
    lines[#lines + 1] = "Native craftable now: " .. tostring(model.nativeCraftable ~= nil and model.nativeCraftable or "UNKNOWN")
    lines[#lines + 1] = "Craftability status: " .. tostring(model.craftabilityStatus or "UNKNOWN")
    lines[#lines + 1] = "Intent validation: two-phase · in-memory · TTL " .. tostring(self.intentTTLSeconds) .. "s"
    lines[#lines + 1] = "Execution authority: disabled"
    lines[#lines + 1] = "Dispatch authority: disabled"
    lines[#lines + 1] = "SavedVariables writes: 0"
    return table.concat(lines, "\n")
end

function ResearchExecutionReadiness:Validate()
    local errors, warnings = {}, {}
    if self.executionEligible ~= false or self.executionAuthorityEnabled ~= false or self.transferableToExecution ~= false or self.readOnly ~= true or self.persisted ~= false then
        errors[#errors + 1] = "research execution-readiness authority boundary invalid"
    end
    for _, name in ipairs({"ResearchPlannerConsumerBridge", "ResearchRouteAuthorityBridge", "ProductionTailoringExecutionReadiness", "ProductionEnchantingExecutionReadiness", "ProfessionAPI", "ExecutionFlow", "Crafting", "TransactionRecovery"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "research execution-readiness dependency missing: " .. name end
    end
    if #GATE_ORDER ~= 10 then errors[#errors + 1] = "research execution-readiness gate count mismatch" end
    return errors, warnings
end

JLP:RegisterModule("ResearchExecutionReadiness", ResearchExecutionReadiness)
