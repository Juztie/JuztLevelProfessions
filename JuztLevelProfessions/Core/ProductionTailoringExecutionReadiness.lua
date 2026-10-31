local _, JLP = ...

-- Alpha99 source-specific execution-readiness policy for the real production
-- Tailoring route.  This policy is evaluation-only: it binds the alpha98 atomic
-- consumer snapshot to alpha97 live recipe identity evidence and exposes a
-- deterministic proof to ResearchExecutionReadiness.  It never grants native
-- execution authority and never calls CraftRecipe/CraftEnchant.
local ProductionTailoringExecutionReadiness = {
    contract = "production-tailoring-execution-readiness-policy-v1",
    proofContract = "production-tailoring-live-readiness-proof-v1",
    authority = "evaluation-only-live-corroborated-production-tailoring-readiness-v1",
    professionKey = "TAILORING",
    readOnly = true,
    executionEligible = false,
    executionAuthorityEnabled = false,
    nativeDispatchAllowed = false,
    persisted = false,
}

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

local function stateHash(parts)
    local value = table.concat(parts or {}, "\31")
    local hash = 5381
    for index = 1, #value do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return string.format("%08x", hash)
end

function ProductionTailoringExecutionReadiness:IsSupported(professionKey)
    return tostring(professionKey or ""):upper() == self.professionKey
end

function ProductionTailoringExecutionReadiness:Assess(consumer)
    local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
    local identity = JLP:GetModule("ProductionTailoringRecipeIdentity")
    local model = {
        contract = self.contract,
        proofContract = self.proofContract,
        authority = self.authority,
        professionKey = self.professionKey,
        state = "production-tailoring-execution-readiness-policy-blocked",
        ready = false,
        readOnly = true,
        executionEligible = false,
        executionAuthorityEnabled = false,
        nativeDispatchAllowed = false,
        persisted = false,
        currentBuild = currentBuild(),
        sourceAuthorityContract = adapter and adapter.contract or nil,
        sourceDatasetContract = adapter and adapter.datasetContract or nil,
    }

    local snapshot = consumer and consumer.snapshot or nil
    model.snapshotToken = consumer and consumer.snapshotToken or nil
    model.consumerStateFingerprint = consumer and consumer.stateFingerprint or nil
    model.consumerReady = consumer ~= nil
        and consumer.state == "consumer-authority-active"
        and consumer.consumerAuthorityEnabled == true
        and snapshot ~= nil
    model.sourceReady = model.consumerReady
        and snapshot.sourceAuthorityContract == model.sourceAuthorityContract
        and snapshot.sourceDatasetContract == model.sourceDatasetContract
        and tostring(snapshot.professionKey or ""):upper() == self.professionKey
    model.clientSessionToken=currentSessionReceipt()
    model.snapshotBuildReady = model.sourceReady
        and model.currentBuild ~= nil and tonumber(snapshot.currentBuild) == tonumber(model.currentBuild)
        and model.clientSessionToken ~= nil
        and consumer.clientSessionToken == model.clientSessionToken
        and snapshot.clientSessionToken == model.clientSessionToken

    local live = identity and identity.AssessCurrent and identity:AssessCurrent() or nil
    model.identity = live
    model.recipe = snapshot and snapshot.recipe or nil
    model.recipeID = tonumber(snapshot and snapshot.recipeID)
    model.routeIndex = tonumber(snapshot and snapshot.routeIndex)
    model.skillTarget = tonumber(snapshot and snapshot.skillTarget)
    model.liveRecipe = live and live.recipe or nil
    model.liveRecipeID = tonumber(live and live.liveResolvedRecipeID)
    model.nativeRecipeName = live and live.nativeRecipeName or nil
    model.liveRecipeLearned = live and live.nativeRecipeInfo and live.nativeRecipeInfo.learned == true or false
    model.liveIdentityReady = live ~= nil and live.liveCurrentStepCorroborated == true
    model.recipeIdentityReady = model.snapshotBuildReady
        and model.liveIdentityReady
        and model.recipeID ~= nil
        and model.liveRecipeID == model.recipeID
        and normalizeText(model.recipe) == normalizeText(model.liveRecipe)
        and normalizeText(model.recipe) == normalizeText(model.nativeRecipeName)
        and tonumber(live and live.plan and live.plan.rawStep and live.plan.rawStep.recipeID or live and live.stagedRecipeID) == model.recipeID

    -- Proof evaluation can invoke multiple client APIs. Recheck the full
    -- receipt after the final observation, not only before the first one.
    local finalSessionReceipt=currentSessionReceipt()
    model.clientSessionStable = model.clientSessionToken~=nil
        and finalSessionReceipt==model.clientSessionToken
    if not model.clientSessionStable then
        model.snapshotBuildReady=false
        model.recipeIdentityReady=false
    end

    model.stateFingerprint = stateHash({
        self.contract,
        self.proofContract,
        tostring(model.currentBuild or ""),
        tostring(model.clientSessionToken or ""),
        model.clientSessionStable and "1" or "0",
        tostring(model.snapshotToken or ""),
        tostring(model.consumerStateFingerprint or ""),
        tostring(model.sourceAuthorityContract or ""),
        tostring(model.sourceDatasetContract or ""),
        tostring(model.recipe or ""),
        tostring(model.recipeID or ""),
        tostring(model.routeIndex or ""),
        tostring(model.skillTarget or ""),
        tostring(model.liveRecipe or ""),
        tostring(model.liveRecipeID or ""),
        model.liveRecipeLearned and "1" or "0",
        model.recipeIdentityReady and "1" or "0",
    })

    model.ready = model.consumerReady and model.sourceReady and model.snapshotBuildReady
        and model.recipeIdentityReady and model.liveRecipeLearned
    if model.ready then
        model.state = "production-tailoring-execution-readiness-policy-ready"
    elseif not model.consumerReady then
        model.blockedReason = "tailoring-consumer-authority-unavailable"
    elseif not model.sourceReady then
        model.blockedReason = "tailoring-consumer-source-mismatch"
    elseif not model.snapshotBuildReady then
        model.blockedReason = "tailoring-consumer-build-mismatch"
    else
        model.blockedReason = "tailoring-live-recipe-identity-not-corroborated"
    end
    return model
end

function ProductionTailoringExecutionReadiness:GetSummary(consumer)
    local model = self:Assess(consumer)
    return table.concat({
        "TAILORING / PRODUCTION EXECUTION READINESS POLICY",
        "Contract: "..self.contract,
        "Proof contract: "..self.proofContract,
        "State: "..tostring(model.state),
        "Consumer source bound: "..(model.sourceReady and "yes" or "no"),
        "Current build bound: "..(model.snapshotBuildReady and "yes" or "no"),
        "Recipe: "..tostring(model.recipe or "unknown").." / "..tostring(model.recipeID or "unresolved"),
        "Exact live recipe identity: "..(model.recipeIdentityReady and "yes" or "no"),
        "Live recipe learned: "..(model.liveRecipeLearned and "yes" or "no"),
        "Execution authority: disabled",
        "Native dispatch: forbidden",
        "Persistence: none",
    }, "\n")
end

function ProductionTailoringExecutionReadiness:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.executionAuthorityEnabled ~= false
        or self.nativeDispatchAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "Production Tailoring execution-readiness policy safety boundary invalid"
    end
    for _, name in ipairs({"ProductionTailoringAuthorityAdapter", "ProductionTailoringRecipeIdentity", "ResearchPlannerConsumerBridge"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "Production Tailoring execution-readiness dependency missing: "..name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringExecutionReadiness", ProductionTailoringExecutionReadiness)
