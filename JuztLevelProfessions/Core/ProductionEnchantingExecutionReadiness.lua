local _, JLP = ...

-- Alpha110 source-specific execution-readiness policy for the real production
-- Enchanting route.  Enchanting differs from CraftRecipe professions because a
-- valid Optional Target is part of the execution identity.  This policy binds
-- the alpha109 atomic consumer snapshot to alpha108 live recipe/target evidence,
-- including GUID, itemID, native target validity and freshly resolved
-- ItemLocation.  It is evaluation-only and never calls CraftEnchant or protected
-- confirmation APIs.
local ProductionEnchantingExecutionReadiness = {
    contract = "production-enchanting-execution-readiness-policy-v1",
    proofContract = "production-enchanting-target-aware-readiness-proof-v1",
    authority = "evaluation-only-live-target-bound-production-enchanting-readiness-v1",
    professionKey = "ENCHANTING",
    readOnly = true,
    executionEligible = false,
    executionAuthorityEnabled = false,
    nativeDispatchAllowed = false,
    confirmationAutomationAllowed = false,
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

function ProductionEnchantingExecutionReadiness:IsSupported(professionKey)
    return tostring(professionKey or ""):upper() == self.professionKey
end

function ProductionEnchantingExecutionReadiness:Assess(consumer)
    local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
    local identity = JLP:GetModule("ProductionEnchantingRecipeIdentity")
    local foundation = JLP:GetModule("ProductionEnchantingTargetedExecutionFoundation")
    local model = {
        contract = self.contract,
        proofContract = self.proofContract,
        authority = self.authority,
        professionKey = self.professionKey,
        state = "production-enchanting-execution-readiness-policy-blocked",
        ready = false,
        readOnly = true,
        executionEligible = false,
        executionAuthorityEnabled = false,
        nativeDispatchAllowed = false,
        confirmationAutomationAllowed = false,
        persisted = false,
        currentBuild = currentBuild(),
        sourceAuthorityContract = adapter and adapter.contract or nil,
        sourceDatasetContract = adapter and adapter.datasetContract or nil,
        sourceTargetBoundContract = adapter and adapter.targetBoundContract or nil,
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
        and snapshot.targetBoundContract == model.sourceTargetBoundContract
        and snapshot.targetBound == true
        and tostring(snapshot.professionKey or ""):upper() == self.professionKey
    model.clientSessionToken=currentSessionReceipt()
    model.snapshotBuildReady = model.sourceReady
        and model.currentBuild ~= nil and tonumber(snapshot.currentBuild) == tonumber(model.currentBuild)
        and model.clientSessionToken ~= nil
        and consumer.clientSessionToken == model.clientSessionToken
        and snapshot.clientSessionToken == model.clientSessionToken

    local liveIdentity = identity and identity.AssessCurrent and identity:AssessCurrent() or nil
    local liveTarget = foundation and foundation.AssessCurrent and foundation:AssessCurrent() or nil
    model.identity = liveIdentity
    model.targetFoundation = liveTarget

    model.recipe = snapshot and snapshot.recipe or nil
    model.recipeID = tonumber(snapshot and snapshot.recipeID)
    model.routeIndex = tonumber(snapshot and snapshot.routeIndex)
    model.skillTarget = tonumber(snapshot and snapshot.skillTarget)
    model.liveRecipe = liveIdentity and liveIdentity.recipe or nil
    model.liveRecipeID = tonumber(liveIdentity and liveIdentity.liveResolvedRecipeID)
    model.nativeRecipeName = liveIdentity and liveIdentity.nativeRecipeName or nil
    model.liveRecipeLearned = liveIdentity and liveIdentity.nativeRecipeInfo and liveIdentity.nativeRecipeInfo.learned == true or false
    model.liveIdentityReady = liveIdentity ~= nil and liveIdentity.liveCurrentStepCorroborated == true
    model.recipeIdentityReady = model.snapshotBuildReady
        and model.liveIdentityReady
        and model.recipeID ~= nil
        and model.liveRecipeID == model.recipeID
        and normalizeText(model.recipe) == normalizeText(model.liveRecipe)
        and normalizeText(model.recipe) == normalizeText(model.nativeRecipeName)
        and tonumber(liveIdentity and liveIdentity.plan and liveIdentity.plan.rawStep and liveIdentity.plan.rawStep.recipeID or liveIdentity and liveIdentity.stagedRecipeID) == model.recipeID

    model.targetGUID = snapshot and snapshot.targetGUID or nil
    model.targetItemID = tonumber(snapshot and snapshot.targetItemID)
    model.targetValidationSource = snapshot and snapshot.targetValidationSource or nil
    model.targetLocationKey = snapshot and snapshot.targetLocationKey or nil
    model.targetProofContract = snapshot and snapshot.targetProofContract or nil
    model.targetProofFingerprint = snapshot and snapshot.targetProofFingerprint or nil

    model.liveTargetGUID = liveTarget and liveTarget.targetGUID or nil
    model.liveTargetItemID = tonumber(liveTarget and liveTarget.targetItemID)
    model.liveTargetValidationSource = liveTarget and liveTarget.targetValidationSource or nil
    model.liveTargetLocationKey = liveTarget and liveTarget.targetLocationKey or nil
    model.liveTargetProofContract = liveTarget and liveTarget.targetProof and liveTarget.targetProof.contract or nil
    model.liveTargetProofFingerprint = liveTarget and liveTarget.targetProofFingerprint or nil
    model.targetFoundationReady = liveTarget ~= nil and liveTarget.targetFoundationReady == true

    model.targetIdentityReady = model.recipeIdentityReady
        and model.targetFoundationReady
        and tonumber(liveTarget and liveTarget.recipeID) == model.recipeID
        and tostring(model.targetGUID or "") ~= ""
        and tostring(model.targetGUID or "") == tostring(model.liveTargetGUID or "")
        and model.targetItemID ~= nil
        and model.targetItemID == model.liveTargetItemID
        and tostring(model.targetValidationSource or "") == tostring(model.liveTargetValidationSource or "")
        and tostring(model.targetLocationKey or "") ~= ""
        and tostring(model.targetLocationKey or "") == tostring(model.liveTargetLocationKey or "")
        and tostring(model.targetProofContract or "") == tostring(model.liveTargetProofContract or "")
        and tostring(model.targetProofFingerprint or "") ~= ""
        and tostring(model.targetProofFingerprint or "") == tostring(model.liveTargetProofFingerprint or "")

    -- Proof evaluation can invoke multiple client APIs. Recheck the full
    -- receipt after the final observation, not only before the first one.
    local finalSessionReceipt=currentSessionReceipt()
    model.clientSessionStable = model.clientSessionToken~=nil
        and finalSessionReceipt==model.clientSessionToken
    if not model.clientSessionStable then
        model.snapshotBuildReady=false
        model.recipeIdentityReady=false
        model.targetIdentityReady=false
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
        tostring(model.sourceTargetBoundContract or ""),
        tostring(model.recipe or ""),
        tostring(model.recipeID or ""),
        tostring(model.routeIndex or ""),
        tostring(model.skillTarget or ""),
        tostring(model.liveRecipeID or ""),
        model.liveRecipeLearned and "1" or "0",
        tostring(model.targetGUID or ""),
        tostring(model.targetItemID or ""),
        tostring(model.targetValidationSource or ""),
        tostring(model.targetLocationKey or ""),
        tostring(model.targetProofContract or ""),
        tostring(model.targetProofFingerprint or ""),
        model.targetIdentityReady and "1" or "0",
    })

    model.ready = model.consumerReady and model.sourceReady and model.snapshotBuildReady
        and model.recipeIdentityReady and model.liveRecipeLearned and model.targetIdentityReady
    if model.ready then
        model.state = "production-enchanting-execution-readiness-policy-ready"
    elseif not model.consumerReady then
        model.blockedReason = "enchanting-consumer-authority-unavailable"
    elseif not model.sourceReady then
        model.blockedReason = "enchanting-consumer-source-mismatch"
    elseif not model.snapshotBuildReady then
        model.blockedReason = "enchanting-consumer-build-mismatch"
    elseif not model.recipeIdentityReady then
        model.blockedReason = "enchanting-live-recipe-identity-not-corroborated"
    else
        model.blockedReason = "enchanting-optional-target-proof-not-current"
    end
    return model
end

function ProductionEnchantingExecutionReadiness:GetSummary(consumer)
    local model = self:Assess(consumer)
    return table.concat({
        "ENCHANTING / PRODUCTION TARGET-AWARE EXECUTION READINESS POLICY",
        "Contract: "..self.contract,
        "Proof contract: "..self.proofContract,
        "State: "..tostring(model.state),
        "Consumer source bound: "..(model.sourceReady and "yes" or "no"),
        "Current build bound: "..(model.snapshotBuildReady and "yes" or "no"),
        "Recipe: "..tostring(model.recipe or "unknown").." / "..tostring(model.recipeID or "unresolved"),
        "Exact live recipe identity: "..(model.recipeIdentityReady and "yes" or "no"),
        "Target GUID: "..tostring(model.targetGUID or "none"),
        "Target item ID: "..tostring(model.targetItemID or "n/a"),
        "Target ItemLocation key: "..tostring(model.targetLocationKey or "none"),
        "Target proof current: "..(model.targetIdentityReady and "yes" or "no"),
        "Execution authority: disabled",
        "CraftEnchant dispatch: forbidden",
        "Protected confirmation automation: forbidden",
        "Persistence: none",
    }, "\n")
end

function ProductionEnchantingExecutionReadiness:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.executionAuthorityEnabled ~= false
        or self.nativeDispatchAllowed ~= false or self.confirmationAutomationAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "Production Enchanting execution-readiness policy safety boundary invalid"
    end
    for _, name in ipairs({"ProductionEnchantingAuthorityAdapter", "ProductionEnchantingRecipeIdentity", "ProductionEnchantingTargetedExecutionFoundation", "ResearchPlannerConsumerBridge"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "Production Enchanting execution-readiness dependency missing: "..name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingExecutionReadiness", ProductionEnchantingExecutionReadiness)
