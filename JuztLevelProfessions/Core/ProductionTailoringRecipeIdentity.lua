local _, JLP = ...

-- Alpha97 separates public Forever recipe-ID staging from live native authority.
-- The route may carry exact public IDs, but no ID becomes execution authority until
-- the currently open Tailoring window corroborates exact ID/name on the live client.
local ProductionTailoringRecipeIdentity = {
    contract = "production-tailoring-recipe-identity-evidence-v1",
    corroborationContract = "production-tailoring-live-recipe-corroboration-v1",
    promotionContract = "production-tailoring-controlled-promotion-readiness-v1",
    authority = "read-only-staged-plus-live-current-build-corroboration",
    expectedRecipeCount = 21,
    expectedSegmentCount = 31,
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

local function reagentIdentity(materials)
    if type(materials) ~= "table" then return nil end
    local counts, rows = {}, {}
    for _, material in ipairs(materials) do
        local id, quantity = tonumber(material.itemID), tonumber(material.quantity)
        if not id or id < 1 or id ~= math.floor(id) or not quantity or quantity < 1 or quantity ~= math.floor(quantity) then return nil end
        counts[id] = (counts[id] or 0) + quantity
    end
    for id, quantity in pairs(counts) do rows[#rows+1] = tostring(id)..":"..tostring(quantity) end
    table.sort(rows)
    return table.concat(rows, ";")
end

-- Intervals, access evidence and craft estimates belong to the segment. These
-- fields describe the recipe itself and must agree whenever both are supplied.
local RECIPE_FIELDS = {"recipe", "outputItemID", "outputPerCraft", "outputQuantityReference",
    "requiredSkill", "rawYellowThreshold", "rawGreyThreshold", "rawMinSkillLineRank",
    "enchantmentID", "recipeIdentitySource", "recipeIdentityURL", "recipeIdentityBuildPinned",
    "liveCurrentBuildCorroborationRequired"}

function ProductionTailoringRecipeIdentity:RecipeFieldsMatch(first, second)
    if type(first) ~= "table" or type(second) ~= "table" or tonumber(first.recipeID) ~= tonumber(second.recipeID) then return false end
    local reagents = reagentIdentity(first.materials)
    if not reagents or reagents ~= reagentIdentity(second.materials) then return false end
    for _, field in ipairs(RECIPE_FIELDS) do
        if first[field] ~= nil and second[field] ~= nil and first[field] ~= second[field] then return false end
    end
    return true
end

function ProductionTailoringRecipeIdentity:AuditStaged()
    local dataset = JLP.data and JLP.data.tailoring or nil
    local model = {
        contract = self.contract,
        promotionContract = self.promotionContract,
        professionKey = "TAILORING",
        expectedRecipeCount = self.expectedRecipeCount,
        expectedSegmentCount = self.expectedSegmentCount,
        stagedRecipeCount = 0,
        externallyReferencedCount = 0,
        liveCorroborationRequiredCount = 0,
        buildPinnedCount = 0,
        duplicateIDs = {},
        repeatedRecipeIDs = {},
        segments = {},
        missing = {},
        malformed = {},
        currentBuild = currentBuild(),
        datasetBuild = dataset and tonumber(dataset.sourceBuild) or nil,
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
    }
    if not dataset or type(dataset.route) ~= "table" then
        model.state = "tailoring-recipe-identity-dataset-unavailable"
        model.stagedComplete = false
        return model
    end
    local seen, byName = {}, {}
    local previousTarget
    for index, step in ipairs(dataset.route) do
        local minimum, target = tonumber(step.skillMin), tonumber(step.skillTarget)
        local segmentID = "TAILORING:"..tostring(index)..":"..tostring(minimum).."-"..tostring(target)
        model.segments[#model.segments+1] = {segmentID=segmentID,index=index,recipeID=tonumber(step.recipeID),skillMin=minimum,skillTarget=target}
        if not minimum or not target or minimum ~= math.floor(minimum) or target ~= math.floor(target)
            or minimum < 1 or target <= minimum or (previousTarget and minimum ~= previousTarget) then
            model.malformed[#model.malformed+1] = {index=index,reason="invalid-or-disconnected-segment-interval"}
        end
        previousTarget = target
        local recipeID = tonumber(step.recipeID)
        if not recipeID or recipeID < 1 or recipeID ~= math.floor(recipeID) then
            model.missing[#model.missing+1] = { index=index, recipe=step.recipe }
        else
            if seen[recipeID] then
                local prior = seen[recipeID]
                if not self:RecipeFieldsMatch(prior.fields, step) then
                    model.duplicateIDs[#model.duplicateIDs+1] = { recipeID=recipeID, first=prior.index, second=index, reason="conflicting-recipe-identity" }
                else
                    model.repeatedRecipeIDs[#model.repeatedRecipeIDs+1] = {recipeID=recipeID,first=prior.index,second=index,segmentID=segmentID}
                end
                for _, field in ipairs(RECIPE_FIELDS) do if prior.fields[field] == nil then prior.fields[field] = step[field] end end
            else
                local fields = {recipeID=recipeID,materials=step.materials}
                for _, field in ipairs(RECIPE_FIELDS) do fields[field] = step[field] end
                seen[recipeID] = {index=index,fields=fields}
                model.stagedRecipeCount = model.stagedRecipeCount + 1
            end
            local name = normalizeText(step.recipe)
            if name == "" or (byName[name] and byName[name] ~= recipeID) or not reagentIdentity(step.materials) then
                model.malformed[#model.malformed+1] = {index=index,reason="recipe-name-or-reagents-conflict"}
            end
            byName[name] = recipeID
            local url = tostring(step.recipeIdentityURL or "")
            if step.recipeIdentitySource == "wowhead-forever" and url:find("wowhead.com/forever/spell="..tostring(recipeID),1,true) then
                if seen[recipeID].index == index then model.externallyReferencedCount = model.externallyReferencedCount + 1 end
            else
                model.malformed[#model.malformed+1] = { index=index, recipe=step.recipe, reason="external-reference-mismatch" }
            end
            if step.recipeIdentityBuildPinned == true then model.buildPinnedCount = model.buildPinnedCount + 1 end
            if step.liveCurrentBuildCorroborationRequired == true then
                if seen[recipeID].index == index then model.liveCorroborationRequiredCount = model.liveCorroborationRequiredCount + 1 end
            else
                model.malformed[#model.malformed+1] = {index=index,reason="live-corroboration-required"}
            end
        end
    end
    model.routeStepCount = #dataset.route
    if tonumber(dataset.route[1] and dataset.route[1].skillMin) ~= 1 or previousTarget ~= 300 then
        model.malformed[#model.malformed+1] = {reason="route-segment-endpoints-incomplete"}
    end
    -- Historical source-build is provenance. Never require it to equal the live
    -- client's build: actual recipe visibility/identity is corroborated below.
    model.sourceBuildQualified = model.datasetBuild == 70009
    model.liveBuildObserved = type(model.currentBuild) == "number" and model.currentBuild > 0
    model.buildCoherent = model.sourceBuildQualified and model.liveBuildObserved
    model.stagedComplete = model.routeStepCount == self.expectedSegmentCount
        and model.stagedRecipeCount == self.expectedRecipeCount
        and model.externallyReferencedCount == self.expectedRecipeCount
        and model.liveCorroborationRequiredCount == self.expectedRecipeCount
        and model.buildPinnedCount == 0
        and #model.duplicateIDs == 0 and #model.missing == 0 and #model.malformed == 0
    model.state = model.stagedComplete and "tailoring-recipe-identity-staging-complete" or "tailoring-recipe-identity-staging-incomplete"
    return model
end

function ProductionTailoringRecipeIdentity:AssessCurrent()
    local staged = self:AuditStaged()
    local model = {
        contract = self.contract,
        corroborationContract = self.corroborationContract,
        promotionContract = self.promotionContract,
        professionKey = "TAILORING",
        staged = staged,
        state = "tailoring-promotion-readiness-blocked",
        routeIdentityReady = staged.stagedComplete == true,
        liveCurrentStepCorroborated = false,
        controlledPromotionCandidate = false,
        nativeAuthorityEnabled = false,
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
        currentBuild = currentBuild(),
        gates = {},
    }
    local dataset = JLP.data and JLP.data.tailoring or nil
    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get("TAILORING") or nil
    local planner = JLP:GetModule("Planner")
    local plan = planner and profession and dataset and planner:GetCurrentStep("TAILORING", profession, dataset) or nil
    model.plan = plan
    model.profession = profession

    local function gate(key, ready, detail)
        model.gates[key] = { ready=ready and true or false, detail=detail }
        return ready and true or false
    end

    local routeReady = gate("staged-route-identity", staged.stagedComplete == true,
        string.format("staged=%d/%d external=%d/%d buildPinned=%d", staged.stagedRecipeCount or 0, staged.expectedRecipeCount or 0, staged.externallyReferencedCount or 0, staged.expectedRecipeCount or 0, staged.buildPinnedCount or 0))
    local buildReady = gate("source-provenance-and-live-client", staged.buildCoherent == true and type(model.currentBuild)=="number" and model.currentBuild>0,
        string.format("live=%s historicalDatasetSource=%s", tostring(model.currentBuild), tostring(staged.datasetBuild)))
    local craftStep = plan and plan.kind == "craft" and plan.rawStep or nil
    local stepReady = gate("current-craft-step", craftStep ~= nil, plan and tostring(plan.kind) or "planner-step-unavailable")

    model.recipe = craftStep and craftStep.recipe or nil
    model.stagedRecipeID = tonumber(craftStep and craftStep.recipeID)
    local stagedIDReady = gate("current-staged-id", model.stagedRecipeID ~= nil,
        string.format("recipe=%s stagedID=%s", tostring(model.recipe), tostring(model.stagedRecipeID)))

    local context=api and type(api.GetRecipeContext)=="function"
        and model.stagedRecipeID and api:GetRecipeContext(model.stagedRecipeID,"TAILORING") or nil
    model.recipeContext=context
    local window={available=context and context.panel and context.panel.verified==true or false,
        skillLineID=context and context.skillLineID or nil,
        name=context and context.panel and context.panel.displayName or nil}
    model.window=window
    local windowReady=gate("tailoring-window",window.available==true and context.professionKey=="TAILORING",
        context and tostring(context.reason) or "common-profession-context-unavailable")
    local visible=context and context.verified==true and context.visible==true or false
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

    -- Live corroboration deliberately ignores KnowledgeCache/ResolveRecipeID so a
    -- stale persisted mapping cannot satisfy alpha97.  The staged ID itself must
    -- be present in the currently open Tailoring recipe list and its native name
    -- must match the production route step exactly.
    model.liveResolvedRecipeID = (visible and nameReady) and model.stagedRecipeID or nil
    local resolverReady = model.stagedRecipeID ~= nil and model.liveResolvedRecipeID == model.stagedRecipeID
    gate("live-current-list-match", resolverReady,
        string.format("staged=%s live-list=%s", tostring(model.stagedRecipeID), tostring(model.liveResolvedRecipeID)))

    model.liveCurrentStepCorroborated = routeReady and buildReady and stepReady and stagedIDReady and windowReady and visible and nameReady and learnedReady and resolverReady
    model.controlledPromotionCandidate = model.liveCurrentStepCorroborated == true
    if model.controlledPromotionCandidate then
        model.state = "tailoring-controlled-promotion-candidate-live-corroborated"
    elseif routeReady and buildReady then
        model.state = "tailoring-route-identity-ready-live-corroboration-pending"
    end
    return model
end

function ProductionTailoringRecipeIdentity:GetSummary()
    local staged = self:AuditStaged()
    local current = self:AssessCurrent()
    local lines = {
        "TAILORING / RECIPE IDENTITY + PROMOTION READINESS",
        "Contract: "..self.contract,
        "Corroboration: "..self.corroborationContract,
        "Promotion: "..self.promotionContract,
        "State: "..tostring(current.state),
        string.format("Staged identities: %d / %d", staged.stagedRecipeCount or 0, staged.expectedRecipeCount or 0),
        string.format("Route segments: %d / %d", staged.routeStepCount or 0, staged.expectedSegmentCount or 0),
        string.format("External Forever references: %d / %d", staged.externallyReferencedCount or 0, staged.expectedRecipeCount or 0),
        "Build-pinned external identities: "..tostring(staged.buildPinnedCount or 0).." (expected 0; live corroboration is authoritative)",
        "Source provenance and live build observed: "..(staged.buildCoherent and "yes" or "no"),
        "Current recipe: "..tostring(current.recipe or "non-craft/unavailable"),
        "Staged recipe ID: "..tostring(current.stagedRecipeID or "n/a"),
        "Live resolved recipe ID: "..tostring(current.liveResolvedRecipeID or "n/a"),
        "Visible in current Tailoring list: "..(current.visibleInCurrentRecipeList and "yes" or "no"),
        "Exact live ID/name corroboration: "..(current.liveCurrentStepCorroborated and "yes" or "no"),
        "Controlled promotion candidate: "..(current.controlledPromotionCandidate and "yes" or "no"),
        "Native execution authority: disabled by this module",
        "Native dispatch: forbidden",
        "Persistence: none",
    }
    return table.concat(lines, "\n")
end

function ProductionTailoringRecipeIdentity:Validate()
    local errors, warnings = {}, {}
    local staged = self:AuditStaged()
    if self.nativeDispatchAllowed ~= false or self.automaticExecutionAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "Tailoring recipe identity module safety boundary invalid"
    end
    if not staged.stagedComplete then errors[#errors+1] = "Tailoring staged recipe identity coverage is incomplete" end
    if tonumber(staged.stagedRecipeCount) ~= self.expectedRecipeCount then errors[#errors+1] = "Tailoring staged recipe identity count mismatch" end
    if tonumber(staged.buildPinnedCount) ~= 0 then errors[#errors+1] = "External Tailoring recipe IDs must not be treated as build-pinned native authority" end
    if not staged.buildCoherent then warnings[#warnings+1] = "Tailoring recipe identity source baseline invalid or current client build unavailable" end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringRecipeIdentity", ProductionTailoringRecipeIdentity)
