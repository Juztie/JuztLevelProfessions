local _, JLP = ...

-- Lossless read-only adapter from the research dependency graph into a nested
-- crafted-recipe material tree. The tree preserves every producer step,
-- current-build recipe/material evidence, output yield and acquisition source.
-- It exists to exercise production Planner read contracts in shadow mode; it
-- never registers research data with the live Planner or execution pipeline.
local ResearchRecursiveMaterialAdapter = {
    contract = "lossless-recursive-crafted-material-planner-adapter-v1",
    nodeContract = "recursive-crafted-recipe-node-v1",
    materialContract = "recursive-crafted-recipe-material-v1",
    authority = "planner-shadow-recursive-adapter-only",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
    readOnly = true,
    maxDepth = 12,
}

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function routeFor(professionKey, mode)
    local research = JLP:GetModule("ProfessionResearch")
    return research and research:Get(professionKey, mode) or nil
end

local function materialEvidenceMap(policyRow)
    local map = {}
    local evidence = policyRow and policyRow.materialEvidence and policyRow.materialEvidence.evidence or nil
    for _, material in pairs(evidence and evidence.materials or {}) do
        local key = normalize(material.name)
        if key ~= "" then map[key] = material end
    end
    return map
end

local function reagentRatioMap(candidateRow)
    local map = {}
    for _, reagent in ipairs(candidateRow and candidateRow.reagentRatio and candidateRow.reagentRatio.reagents or {}) do
        local key = normalize(reagent.name)
        if key ~= "" then map[key] = reagent end
    end
    return map
end

local function itemIdentity(name, observed)
    local itemID = observed and tonumber(observed.itemID) or nil
    local cache = JLP:GetModule("KnowledgeCache")
    local item = cache and cache.GetItem and cache:GetItem(itemID, name) or nil
    return {
        itemID = itemID or (item and tonumber(item.itemID)) or nil,
        name = (item and item.name) or name,
        icon = item and item.icon or nil,
        quality = item and item.quality or nil,
    }
end

local function acquisitionFor(name, itemID)
    local module = JLP:GetModule("MaterialAcquisitionEvidence")
    local resolved = module and module.Resolve and module:Resolve(name, itemID) or nil
    return resolved and {
        status = resolved.status,
        sourceClass = resolved.sourceClass,
        plannerSource = resolved.plannerSource,
        acquisitionKinds = resolved.acquisitionKinds,
        confidence = resolved.confidence,
        evidence = resolved.evidence,
        currentBuild = resolved.currentBuild,
        referenceCapturedBuild = resolved.referenceCapturedBuild,
        liveVerified = resolved.liveVerified == true,
        externalVerified = resolved.externalVerified == true,
        conflict = resolved.conflict == true,
        conflictReason = resolved.conflictReason,
        sourceResolved = resolved.sourceResolved == true,
    } or nil
end

local function edgeMap(closure)
    local map = {}
    for _, edge in ipairs(closure and closure.dependencyEdges or {}) do
        local consumer = tonumber(edge.consumerStepIndex)
        local producer = tonumber(edge.producerStepIndex)
        if consumer and producer then
            map[consumer] = map[consumer] or {}
            for _, detail in ipairs(edge.details or {}) do
                local key = normalize(detail.item or detail.recipe)
                if key ~= "" then
                    local existing = map[consumer][key]
                    if not existing or producer > (tonumber(existing.producerStepIndex) or 0) then
                        map[consumer][key] = {
                            consumerStepIndex = consumer,
                            producerStepIndex = producer,
                            relationKinds = edge.relationKinds or {},
                            detail = detail,
                        }
                    end
                end
            end
        end
    end
    return map
end

local function dependencyFor(map, consumerStepIndex, materialName)
    local rows = map[tonumber(consumerStepIndex)]
    return rows and rows[normalize(materialName)] or nil
end

local function copyAcquisition(acquisition)
    if not acquisition then return nil end
    return shallowCopy(acquisition)
end

function ResearchRecursiveMaterialAdapter:_BuildProducerNode(context, producerStepIndex, outputMaterial, depth, active)
    depth = tonumber(depth) or 0
    producerStepIndex = tonumber(producerStepIndex)
    if not producerStepIndex then return nil, "producer-step-missing" end
    if depth > self.maxDepth then return nil, "max-recursion-depth" end
    if active[producerStepIndex] then return nil, "dependency-cycle" end

    local rawStep = context.route.steps and context.route.steps[producerStepIndex] or nil
    local candidate = context.candidates.stepByRouteIndex and context.candidates.stepByRouteIndex[producerStepIndex] or nil
    local policy = context.policy:EvaluateIntrinsicStep(context.professionKey, context.mode, producerStepIndex)
    if not rawStep or rawStep.kind ~= "craft" or not candidate or not policy then
        return nil, "producer-step-unavailable"
    end
    if policy.intrinsicCandidateEligible ~= true then
        return nil, "producer-promotion-not-ready:" .. tostring(policy.status)
    end

    local recipeID = policy.recipeObservation and tonumber(policy.recipeObservation.recipeID) or nil
    local yieldEvidence = context.yields and context.yields:Resolve(rawStep.recipe, recipeID) or nil
    local outputPerCraft = yieldEvidence and tonumber(yieldEvidence.outputQuantity) or nil
    if not yieldEvidence or yieldEvidence.dependencyQuantityEligible ~= true or not outputPerCraft or outputPerCraft <= 0 then
        return nil, "producer-yield-not-ready:" .. tostring(yieldEvidence and yieldEvidence.status or "unavailable")
    end

    active[producerStepIndex] = true
    local evidenceByName = materialEvidenceMap(policy)
    local ratios = reagentRatioMap(candidate)
    local node = {
        contract = self.nodeContract,
        itemID = tonumber(outputMaterial and outputMaterial.itemID),
        name = outputMaterial and outputMaterial.name or rawStep.recipe,
        source = "crafted",
        producerStepIndex = producerStepIndex,
        recipe = rawStep.recipe,
        recipeID = recipeID,
        outputPerCraft = outputPerCraft,
        yieldStatus = yieldEvidence.status,
        yieldSource = yieldEvidence.source,
        yieldEvidence = {
            status = yieldEvidence.status,
            source = yieldEvidence.source,
            outputQuantity = outputPerCraft,
            currentBuild = yieldEvidence.currentBuild,
            liveVerified = yieldEvidence.liveVerified == true,
            externalVerified = yieldEvidence.externalVerified == true,
            referenceConflict = yieldEvidence.referenceConflict == true,
        },
        promotionStatus = policy.status,
        currentBuildObserved = policy.recipeObservation and policy.recipeObservation.currentBuildObserved == true or false,
        observedBuild = policy.recipeObservation and policy.recipeObservation.observedBuild or nil,
        currentBuild = policy.recipeObservation and policy.recipeObservation.currentBuild or nil,
        materials = {},
        resolved = true,
        readOnly = true,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
    }

    for _, requirement in ipairs(rawStep.requirements or {}) do
        local name = tostring(requirement.name or "")
        local key = normalize(name)
        local observed = evidenceByName[key]
        local identity = itemIdentity(name, observed)
        local ratio = ratios[key]
        local perCraft = ratio and tonumber(ratio.perCraft) or nil
        local dep = dependencyFor(context.edges, producerStepIndex, name)
        local acquisition = not dep and acquisitionFor(name, identity.itemID) or nil
        local material = {
            contract = self.materialContract,
            itemID = identity.itemID,
            name = identity.name or name,
            quantity = perCraft,
            source = dep and "crafted" or (acquisition and acquisition.sourceResolved and acquisition.plannerSource or "research-unresolved"),
            itemResolved = identity.itemID ~= nil,
            sourceResolved = dep ~= nil or (acquisition and acquisition.sourceResolved == true) or false,
            relation = dep and "upstream-intermediate" or (acquisition and acquisition.sourceClass and ("external-" .. tostring(acquisition.sourceClass)) or "external-unclassified"),
            producerStepIndex = dep and tonumber(dep.producerStepIndex) or nil,
            consumerStepIndex = producerStepIndex,
            relationKinds = dep and dep.relationKinds or nil,
            evidence = requirement.evidence,
            exactSamples = observed and tonumber(observed.exactUnits) or nil,
            observedPerCraft = observed and tonumber(observed.consumedPerCraft) or nil,
            currentBuildCorroborated = observed and observed.allReconciledExact == true or false,
            acquisition = copyAcquisition(acquisition),
            readOnly = true,
            plannerEligible = false,
        }
        if not perCraft or perCraft <= 0 or not material.itemResolved or not material.sourceResolved then
            node.resolved = false
        end
        if dep then
            local child, reason = self:_BuildProducerNode(context, dep.producerStepIndex, material, depth + 1, active)
            material.craftedRecipe = child
            material.adapterError = reason
            if not child or child.resolved ~= true then node.resolved = false end
        end
        node.materials[#node.materials + 1] = material
    end

    active[producerStepIndex] = nil
    return node, nil
end

function ResearchRecursiveMaterialAdapter:BuildForStep(professionKey, mode, selector)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    local route = routeFor(professionKey, mode)
    local verifier = JLP:GetModule("ResearchCandidateVerifier")
    local policy = JLP:GetModule("ResearchPromotionPolicy")
    local closureModule = JLP:GetModule("ResearchPromotionClosure")
    local yields = JLP:GetModule("RecipeOutputEvidence")
    if not route or not verifier or not policy or not closureModule or not yields then return nil end

    local candidate, candidateModel = verifier:GetStep(professionKey, mode, selector)
    if not candidate then return nil, candidateModel end
    local closure = closureModule:EvaluateStep(professionKey, mode, candidate.routeStepIndex)
    if not closure then return nil, candidateModel end
    local candidates = verifier:Build(professionKey, mode)
    if not candidates then return nil, candidateModel end

    local context = {
        professionKey = professionKey,
        mode = mode,
        route = route,
        candidates = candidates,
        policy = policy,
        yields = yields,
        edges = edgeMap(closure),
    }
    local rawStep = route.steps and route.steps[candidate.routeStepIndex] or nil
    local policyRow = policy:EvaluateIntrinsicStep(professionKey, mode, candidate.routeStepIndex)
    if not rawStep or not policyRow then return nil, candidateModel end
    local evidenceByName = materialEvidenceMap(policyRow)
    local ratios = reagentRatioMap(candidate)

    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        routeStepIndex = candidate.routeStepIndex,
        recipe = candidate.recipe,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        materials = {},
        materialByName = {},
        stats = { craftedRoots=0, recursiveNodes=0, maxDepth=0, unresolved=0 },
    }

    local function countNode(node, depth)
        if not node then return end
        model.stats.recursiveNodes = model.stats.recursiveNodes + 1
        model.stats.maxDepth = math.max(model.stats.maxDepth, depth or 1)
        if node.resolved ~= true then model.stats.unresolved = model.stats.unresolved + 1 end
        for _, material in ipairs(node.materials or {}) do
            if material.craftedRecipe then countNode(material.craftedRecipe, (depth or 1) + 1) end
        end
    end

    for _, requirement in ipairs(rawStep.requirements or {}) do
        local name = tostring(requirement.name or "")
        local key = normalize(name)
        local observed = evidenceByName[key]
        local identity = itemIdentity(name, observed)
        local ratio = ratios[key]
        local dep = dependencyFor(context.edges, candidate.routeStepIndex, name)
        local row = {
            itemID = identity.itemID,
            name = identity.name or name,
            quantity = ratio and tonumber(ratio.perCraft) or nil,
            source = dep and "crafted" or nil,
            producerStepIndex = dep and tonumber(dep.producerStepIndex) or nil,
            readOnly = true,
            plannerEligible = false,
        }
        if dep then
            local node, reason = self:_BuildProducerNode(context, dep.producerStepIndex, row, 1, {})
            row.craftedRecipe = node
            row.adapterError = reason
            model.stats.craftedRoots = model.stats.craftedRoots + 1
            countNode(node, 1)
            if not node then model.stats.unresolved = model.stats.unresolved + 1 end
        end
        model.materials[#model.materials + 1] = row
        model.materialByName[key] = row
    end

    model.state = model.stats.unresolved == 0 and "recursive-crafted-material-adapter-ready" or "recursive-crafted-material-adapter-incomplete"
    return model, candidateModel
end

function ResearchRecursiveMaterialAdapter:AttachToStep(professionKey, mode, stagedStep)
    if type(stagedStep) ~= "table" then return nil end
    local model = self:BuildForStep(professionKey, mode, stagedStep.routeIndex or stagedStep.recipe)
    if not model then return nil end
    local out = {}
    for _, material in ipairs(stagedStep.materials or {}) do
        local copy = shallowCopy(material)
        local adapted = model.materialByName[normalize(material.name)]
        if adapted and adapted.craftedRecipe then
            copy.craftedRecipe = adapted.craftedRecipe
            copy.adapterState = model.state
        end
        out[#out + 1] = copy
    end
    return out, model
end

function ResearchRecursiveMaterialAdapter:GetSummary(professionKey, mode, selector)
    local model = self:BuildForStep(professionKey, mode, selector)
    if not model then return "Recursive crafted-material adapter unavailable." end
    local lines = {
        "RECURSIVE CRAFTED-MATERIAL ADAPTER",
        string.format("%s / %s", tostring(model.professionKey), tostring(model.mode)),
        "Recipe: " .. tostring(model.recipe or "unknown"),
        "State: " .. tostring(model.state),
        string.format("Crafted roots: %d · recursive nodes: %d · max depth: %d · unresolved: %d", tonumber(model.stats.craftedRoots) or 0, tonumber(model.stats.recursiveNodes) or 0, tonumber(model.stats.maxDepth) or 0, tonumber(model.stats.unresolved) or 0),
    }
    local function appendNode(node, depth)
        if not node or depth > 6 then return end
        lines[#lines + 1] = string.format("%s· %s → %s · output %s/craft · step %s", string.rep("  ", depth - 1), tostring(node.recipe or "craft"), tostring(node.name or "output"), tostring(node.outputPerCraft or "?"), tostring(node.producerStepIndex or "?"))
        for _, material in ipairs(node.materials or {}) do
            if material.craftedRecipe then appendNode(material.craftedRecipe, depth + 1)
            else
                lines[#lines + 1] = string.format("%s  raw: %s x%s/craft · %s", string.rep("  ", depth - 1), tostring(material.name or "material"), tostring(material.quantity or "?"), tostring(material.source or "unknown"))
            end
        end
    end
    for _, material in ipairs(model.materials or {}) do
        if material.craftedRecipe then appendNode(material.craftedRecipe, 1) end
    end
    lines[#lines + 1] = "Planner authority: disabled"
    lines[#lines + 1] = "Execution authority: disabled"
    return table.concat(lines, "\n")
end

function ResearchRecursiveMaterialAdapter:Validate()
    local errors, warnings = {}, {}
    if self.plannerEligible ~= false or self.executionEligible ~= false or self.transferable ~= false or self.readOnly ~= true then
        errors[#errors + 1] = "recursive crafted-material adapter authority policy mismatch"
    end
    if self.maxDepth < 2 then errors[#errors + 1] = "recursive crafted-material adapter depth guard invalid" end
    return errors, warnings
end

JLP:RegisterModule("ResearchRecursiveMaterialAdapter", ResearchRecursiveMaterialAdapter)
