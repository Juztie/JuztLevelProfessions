local _, JLP = ...

-- Alpha108 stages exact public Forever Enchanting recipe identities but keeps
-- execution authority closed until the open Enchanting window corroborates the
-- exact ID/name on the target build. Public IDs are evidence, not dispatch authority.
local ProductionEnchantingRecipeIdentity = {
    contract = "production-enchanting-recipe-identity-evidence-v1",
    corroborationContract = "production-enchanting-live-recipe-corroboration-v1",
    promotionContract = "production-enchanting-targeted-promotion-readiness-v1",
    authority = "read-only-staged-plus-live-current-build-corroboration",
    expectedRecipeCount = 8,
    nativeDispatchAllowed = false,
    automaticExecutionAllowed = false,
    persisted = false,
}

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    return value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

function ProductionEnchantingRecipeIdentity:AuditStaged()
    local dataset = JLP.data and JLP.data.enchanting or nil
    local model = {
        contract = self.contract,
        promotionContract = self.promotionContract,
        professionKey = "ENCHANTING",
        expectedRecipeCount = self.expectedRecipeCount,
        stagedRecipeCount = 0,
        externallyReferencedCount = 0,
        liveCorroborationRequiredCount = 0,
        buildPinnedCount = 0,
        targetedExecutionCount = 0,
        duplicateIDs = {},
        missing = {},
        malformed = {},
        currentBuild = currentBuild(),
        datasetBuild = dataset and tonumber(dataset.sourceBuild) or nil,
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
    }
    if not dataset or type(dataset.route) ~= "table" then
        model.state = "enchanting-recipe-identity-dataset-unavailable"
        model.stagedComplete = false
        return model
    end
    local seen = {}
    for index, step in ipairs(dataset.route) do
        local recipeID = tonumber(step.recipeID)
        if not recipeID then
            model.missing[#model.missing+1] = { index=index, recipe=step.recipe }
        else
            model.stagedRecipeCount = model.stagedRecipeCount + 1
            if seen[recipeID] then
                model.duplicateIDs[#model.duplicateIDs+1] = { recipeID=recipeID, first=seen[recipeID], second=index }
            else
                seen[recipeID] = index
            end
            local url = tostring(step.recipeIdentityURL or "")
            if step.recipeIdentitySource == "wowhead-forever" and url:find("wowhead.com/forever/spell="..tostring(recipeID),1,true) then
                model.externallyReferencedCount = model.externallyReferencedCount + 1
            else
                model.malformed[#model.malformed+1] = { index=index, recipe=step.recipe, reason="external-reference-mismatch" }
            end
            if step.recipeIdentityBuildPinned == true then model.buildPinnedCount = model.buildPinnedCount + 1 end
            if step.liveCurrentBuildCorroborationRequired == true then model.liveCorroborationRequiredCount = model.liveCorroborationRequiredCount + 1 end
            if step.targetedExecutionRequired == true and step.targetedExecutionAPI == "C_TradeSkillUI.CraftEnchant" and step.targetIdentity == "item-guid" and step.targetLocationAuthority == "live-item-location" then
                model.targetedExecutionCount = model.targetedExecutionCount + 1
            end
        end
    end
    model.routeStepCount = #dataset.route
    -- Historical source-build is provenance. Never require it to equal the live
    -- client's build: actual recipe visibility/identity is corroborated below.
    model.sourceBuildQualified = model.datasetBuild == 70009
    model.liveBuildObserved = type(model.currentBuild) == "number" and model.currentBuild > 0
    model.buildCoherent = model.sourceBuildQualified and model.liveBuildObserved
    model.stagedComplete = model.routeStepCount == self.expectedRecipeCount
        and model.stagedRecipeCount == self.expectedRecipeCount
        and model.externallyReferencedCount == self.expectedRecipeCount
        and model.liveCorroborationRequiredCount == self.expectedRecipeCount
        and model.targetedExecutionCount == self.expectedRecipeCount
        and model.buildPinnedCount == 0
        and #model.duplicateIDs == 0 and #model.missing == 0 and #model.malformed == 0
    model.state = model.stagedComplete and "enchanting-recipe-identity-staging-complete" or "enchanting-recipe-identity-staging-incomplete"
    return model
end

function ProductionEnchantingRecipeIdentity:AssessCurrent()
    local staged = self:AuditStaged()
    local model = {
        contract = self.contract,
        corroborationContract = self.corroborationContract,
        promotionContract = self.promotionContract,
        professionKey = "ENCHANTING",
        staged = staged,
        state = "enchanting-targeted-promotion-readiness-blocked",
        routeIdentityReady = staged.stagedComplete == true,
        liveCurrentStepCorroborated = false,
        targetedPromotionCandidate = false,
        nativeAuthorityEnabled = false,
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
        currentBuild = currentBuild(),
        gates = {},
    }
    local dataset = JLP.data and JLP.data.enchanting or nil
    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get("ENCHANTING") or nil
    local planner = JLP:GetModule("Planner")
    local plan = planner and profession and dataset and planner:GetCurrentStep("ENCHANTING", profession, dataset) or nil
    model.plan = plan
    model.profession = profession

    local function gate(key, ready, detail)
        model.gates[key] = { ready=ready and true or false, detail=detail }
        return ready and true or false
    end

    local routeReady = gate("staged-route-identity", staged.stagedComplete == true,
        string.format("staged=%d/%d external=%d/%d targeted=%d/%d buildPinned=%d", staged.stagedRecipeCount or 0, staged.expectedRecipeCount or 0, staged.externallyReferencedCount or 0, staged.expectedRecipeCount or 0, staged.targetedExecutionCount or 0, staged.expectedRecipeCount or 0, staged.buildPinnedCount or 0))
    local buildReady = gate("source-provenance-and-live-client", staged.buildCoherent == true and type(model.currentBuild)=="number" and model.currentBuild>0,
        string.format("live=%s historicalDatasetSource=%s", tostring(model.currentBuild), tostring(staged.datasetBuild)))
    local craftStep = plan and plan.kind == "craft" and plan.rawStep or nil
    local stepReady = gate("current-craft-step", craftStep ~= nil, plan and tostring(plan.kind) or "planner-step-unavailable")

    model.recipe = craftStep and craftStep.recipe or nil
    model.stagedRecipeID = tonumber(craftStep and craftStep.recipeID)
    local stagedIDReady = gate("current-staged-id", model.stagedRecipeID ~= nil,
        string.format("recipe=%s stagedID=%s", tostring(model.recipe), tostring(model.stagedRecipeID)))

    local context=api and type(api.GetRecipeContext)=="function"
        and model.stagedRecipeID and api:GetRecipeContext(model.stagedRecipeID,"ENCHANTING") or nil
    model.recipeContext=context
    local window={available=context~=nil and context.panel~=nil and context.panel.verified==true,
        skillLineID=context and context.skillLineID or nil,
        name=context and context.panel and context.panel.displayName or nil}
    model.window=window
    local windowReady=gate("enchanting-window",window.available and context.professionKey=="ENCHANTING",
        context and tostring(context.reason) or "common-profession-context-unavailable")
    local visible=context~=nil and context.verified==true and context.visible==true
    model.visibleInCurrentRecipeList=visible
    gate("current-recipe-list",visible,context and tostring(context.reason) or "common-recipe-context-unavailable")
    local info=visible and context.recipeInfo or nil
    model.nativeRecipeInfo=info
    model.nativeRecipeName=info and info.name or nil
    local nameReady=info~=nil and normalizeText(info.name)==normalizeText(model.recipe)
    gate("native-id-name",nameReady,
        string.format("staged=%s/%s native=%s",tostring(model.recipe),tostring(model.stagedRecipeID),tostring(model.nativeRecipeName)))
    local learnedReady=context~=nil and context.learned==true
    gate("learned",learnedReady,context and tostring(context.learned) or "recipe-context-unavailable")

    model.liveResolvedRecipeID = (visible and nameReady) and model.stagedRecipeID or nil
    local resolverReady = model.stagedRecipeID ~= nil and model.liveResolvedRecipeID == model.stagedRecipeID
    gate("live-current-list-match", resolverReady,
        string.format("staged=%s live-list=%s", tostring(model.stagedRecipeID), tostring(model.liveResolvedRecipeID)))

    local targetModelReady = craftStep and craftStep.targetedExecutionRequired == true
        and craftStep.targetedExecutionAPI == "C_TradeSkillUI.CraftEnchant"
        and craftStep.targetIdentity == "item-guid"
        and craftStep.targetLocationAuthority == "live-item-location"
    gate("targeted-execution-model", targetModelReady,
        targetModelReady and "Optional Target GUID + live ItemLocation + CraftEnchant required" or "production route step does not carry the required targeted execution contract")

    model.liveCurrentStepCorroborated = routeReady and buildReady and stepReady and stagedIDReady and windowReady and visible and nameReady and learnedReady and resolverReady and targetModelReady
    model.targetedPromotionCandidate = model.liveCurrentStepCorroborated == true
    if model.targetedPromotionCandidate then
        model.state = "enchanting-targeted-promotion-candidate-live-corroborated"
    elseif routeReady and buildReady then
        model.state = "enchanting-route-identity-ready-live-corroboration-pending"
    end
    return model
end

function ProductionEnchantingRecipeIdentity:GetSummary()
    local staged = self:AuditStaged()
    local current = self:AssessCurrent()
    local lines = {
        "ENCHANTING / RECIPE IDENTITY + TARGETED PROMOTION READINESS",
        "Contract: "..self.contract,
        "Corroboration: "..self.corroborationContract,
        "Promotion: "..self.promotionContract,
        "State: "..tostring(current.state),
        string.format("Staged identities: %d / %d", staged.stagedRecipeCount or 0, staged.expectedRecipeCount or 0),
        string.format("External Forever references: %d / %d", staged.externallyReferencedCount or 0, staged.expectedRecipeCount or 0),
        string.format("Targeted execution contracts: %d / %d", staged.targetedExecutionCount or 0, staged.expectedRecipeCount or 0),
        "Build-pinned external identities: "..tostring(staged.buildPinnedCount or 0).." (expected 0; live corroboration is authoritative)",
        "Source provenance and live build observed: "..(staged.buildCoherent and "yes" or "no"),
        "Current recipe: "..tostring(current.recipe or "non-craft/unavailable"),
        "Staged recipe ID: "..tostring(current.stagedRecipeID or "n/a"),
        "Live resolved recipe ID: "..tostring(current.liveResolvedRecipeID or "n/a"),
        "Visible in current Enchanting list: "..(current.visibleInCurrentRecipeList and "yes" or "no"),
        "Exact live ID/name corroboration: "..(current.liveCurrentStepCorroborated and "yes" or "no"),
        "Targeted promotion candidate: "..(current.targetedPromotionCandidate and "yes" or "no"),
        "Native execution authority: disabled by this module",
        "Native dispatch: forbidden",
        "Persistence: none",
    }
    return table.concat(lines, "\n")
end

function ProductionEnchantingRecipeIdentity:Validate()
    local errors, warnings = {}, {}
    local staged = self:AuditStaged()
    if self.nativeDispatchAllowed ~= false or self.automaticExecutionAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "Enchanting recipe identity module safety boundary invalid"
    end
    if not staged.stagedComplete then errors[#errors+1] = "Enchanting staged recipe identity coverage is incomplete" end
    if tonumber(staged.stagedRecipeCount) ~= self.expectedRecipeCount then errors[#errors+1] = "Enchanting staged recipe identity count mismatch" end
    if tonumber(staged.targetedExecutionCount) ~= self.expectedRecipeCount then errors[#errors+1] = "Enchanting targeted execution metadata coverage mismatch" end
    if tonumber(staged.buildPinnedCount) ~= 0 then errors[#errors+1] = "External Enchanting recipe IDs must not be treated as build-pinned native authority" end
    if not staged.buildCoherent then warnings[#warnings+1] = "Enchanting recipe identity source baseline invalid or current client build unavailable" end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingRecipeIdentity", ProductionEnchantingRecipeIdentity)
