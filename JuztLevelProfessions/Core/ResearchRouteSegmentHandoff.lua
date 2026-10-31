local _, JLP = ...

-- Converts live-qualified research route segments into a read-only structure
-- that deliberately mirrors the audited Planner's craft-step shape. This is a
-- compatibility/staging bridge only: no result is registered with Planner,
-- ActionQueue, Shopping/Acquisition or execution modules.
local ResearchRouteSegmentHandoff = {
    contract = "qualified-route-segment-handoff-v1",
    plannerStepContract = "planner-compatible-research-step-v1",
    authority = "planner-compatible-read-only-staging",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
    readOnly = true,
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

local function recipeState(professionKey, recipe)
    local cache = JLP:GetModule("KnowledgeCache")
    if not cache or not cache.GetRecipeKnowledgeState then return nil end
    return cache:GetRecipeKnowledgeState(recipe, professionKey)
end

local function itemRecord(name, observed)
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

local function materialEvidenceMap(policyRow)
    local map = {}
    local evidence = policyRow and policyRow.materialEvidence and policyRow.materialEvidence.evidence or nil
    for _, material in pairs(evidence and evidence.materials or {}) do
        local key = normalize(material.name)
        if key ~= "" then map[key] = material end
    end
    return map
end

local function dependencyMaterialMap(closureRow)
    local map = {}
    for _, edge in ipairs(closureRow and closureRow.dependencyEdges or {}) do
        for _, detail in ipairs(edge.details or {}) do
            local item = detail.item or detail.recipe
            local key = normalize(item)
            if key ~= "" then
                map[key] = {
                    producerStepIndex = edge.producerStepIndex,
                    consumerStepIndex = edge.consumerStepIndex,
                    relationKinds = edge.relationKinds,
                    detail = detail,
                }
            end
        end
    end
    return map
end

local function staticRemainingCrafts(rawStep, liveSkill)
    local total = math.max(0, tonumber(rawStep and rawStep.expectedCrafts) or 0)
    local skillMin = tonumber(rawStep and rawStep.skillMin) or 0
    local skillTarget = tonumber(rawStep and rawStep.skillTarget) or skillMin
    local current = tonumber(liveSkill) or skillMin
    if current <= skillMin then return total end
    if current >= skillTarget then return 0 end
    local span = math.max(1, skillTarget - skillMin)
    local remaining = skillTarget - current
    if total <= 0 then return 0 end
    return math.max(1, math.ceil(total * remaining / span))
end

local function stepRelevance(rawStep, liveSkill)
    local current = tonumber(liveSkill) or 0
    local skillMin = tonumber(rawStep and rawStep.skillMin) or 0
    local skillTarget = tonumber(rawStep and rawStep.skillTarget) or skillMin
    if current >= skillTarget then return "passed" end
    if current < skillMin then return "future" end
    return "active"
end

local function normalizedMaterial(requirement, candidateRow, policyRow, closureRow)
    local requirementName = tostring(requirement and requirement.name or "")
    local key = normalize(requirementName)
    local perCraft = nil
    for _, reagent in ipairs(candidateRow and candidateRow.reagentRatio and candidateRow.reagentRatio.reagents or {}) do
        if normalize(reagent.name) == key then
            perCraft = tonumber(reagent.perCraft)
            break
        end
    end
    local evidenceByName = materialEvidenceMap(policyRow)
    local observed = evidenceByName[key]
    local identity = itemRecord(requirementName, observed)
    local dep = dependencyMaterialMap(closureRow)[key]
    local acquisitionModule = JLP:GetModule("MaterialAcquisitionEvidence")
    local acquisition = (not dep and acquisitionModule and acquisitionModule.Resolve) and acquisitionModule:Resolve(requirementName, identity.itemID) or nil
    local source = dep and "crafted" or (acquisition and acquisition.sourceResolved and acquisition.plannerSource or "research-unresolved")
    local sourceResolved = dep ~= nil or (acquisition and acquisition.sourceResolved == true) or false
    local relation = dep and "upstream-intermediate" or (acquisition and acquisition.sourceClass and ("external-" .. tostring(acquisition.sourceClass)) or "external-unclassified")
    return {
        itemID = identity.itemID,
        name = identity.name or requirementName,
        quantity = perCraft,
        source = source,
        itemResolved = identity.itemID ~= nil,
        sourceResolved = sourceResolved,
        relation = relation,
        producerStepIndex = dep and tonumber(dep.producerStepIndex) or nil,
        evidence = requirement and requirement.evidence or nil,
        exactSamples = observed and tonumber(observed.exactUnits) or nil,
        observedPerCraft = observed and tonumber(observed.consumedPerCraft) or nil,
        currentBuildCorroborated = observed and observed.allReconciledExact == true or false,
        acquisition = acquisition and {
            status = acquisition.status,
            sourceClass = acquisition.sourceClass,
            plannerSource = acquisition.plannerSource,
            acquisitionKinds = acquisition.acquisitionKinds,
            confidence = acquisition.confidence,
            evidence = acquisition.evidence,
            currentBuild = acquisition.currentBuild,
            referenceCapturedBuild = acquisition.referenceCapturedBuild,
            liveVerified = acquisition.liveVerified == true,
            externalVerified = acquisition.externalVerified == true,
            conflict = acquisition.conflict == true,
            conflictReason = acquisition.conflictReason,
        } or nil,
    }
end

local function buildNormalizedStep(professionKey, mode, rawStep, candidateRow, policyRow, closureRow, liveSkill)
    local observation = policyRow and policyRow.recipeObservation or recipeState(professionKey, rawStep.recipe) or {}
    local materials = {}
    local unresolvedItemIDs, unresolvedSources = 0, 0
    for _, requirement in ipairs(rawStep.requirements or {}) do
        local material = normalizedMaterial(requirement, candidateRow, policyRow, closureRow)
        materials[#materials + 1] = material
        if not material.itemResolved then unresolvedItemIDs = unresolvedItemIDs + 1 end
        if not material.sourceResolved then unresolvedSources = unresolvedSources + 1 end
    end

    local remaining = staticRemainingCrafts(rawStep, liveSkill)
    local relevance = stepRelevance(rawStep, liveSkill)
    local access = policyRow and policyRow.accessSource or { required=false, ready=true, state="not-required" }
    local normalized = {
        contract = ResearchRouteSegmentHandoff.plannerStepContract,
        kind = "craft",
        profession = professionKey,
        mode = mode,
        skill = tonumber(rawStep.skillMin) or 0,
        skillMin = tonumber(rawStep.skillMin) or 0,
        skillTarget = tonumber(rawStep.skillTarget) or 0,
        routeIndex = tonumber(candidateRow and candidateRow.routeStepIndex),
        recipe = rawStep.recipe,
        recipeID = tonumber(observation.recipeID),
        recipeSource = access.required and (access.kind or "access-gated") or "known-current-build",
        sourceInfo = access.required and shallowCopy(access) or nil,
        expectedCrafts = tonumber(rawStep.expectedCrafts) or 0,
        staticRemainingCrafts = remaining,
        remainingCrafts = remaining,
        estimateSource = "research-staging-static",
        estimateSourceDetail = rawStep.estimated and "research-estimated-craft-count" or "research-fixed-craft-count",
        estimateWeight = 0,
        telemetryEstimate = nil,
        telemetry = nil,
        materials = materials,
        requiredTool = nil,
        evidence = rawStep.evidence,
        rawStep = rawStep,
        relevance = relevance,
        estimated = rawStep.estimated == true,
        keep = rawStep.keep == true,
        craftCountAuthority = "research-route-staging-only",
        materialRateAuthority = "current-build-corroborated-research-ratio",
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        compatibility = {
            shapeReady = rawStep.recipe ~= nil and tonumber(rawStep.skillTarget) ~= nil and tonumber(candidateRow and candidateRow.routeStepIndex) ~= nil,
            unresolvedItemIDs = unresolvedItemIDs,
            unresolvedMaterialSources = unresolvedSources,
        },
    }
    normalized.compatibility.dataComplete = normalized.compatibility.shapeReady
        and unresolvedItemIDs == 0
        and unresolvedSources == 0
        and normalized.recipeID ~= nil
    return normalized
end

local function aggregateMaterials(steps)
    local byKey, order = {}, {}
    for _, step in ipairs(steps or {}) do
        local crafts = math.max(0, tonumber(step.remainingCrafts) or 0)
        if crafts > 0 then
            for _, material in ipairs(step.materials or {}) do
                local key = tostring(material.itemID or normalize(material.name))
                local row = byKey[key]
                if not row then
                    row = {
                        itemID = material.itemID,
                        name = material.name,
                        source = material.source,
                        relation = material.relation,
                        required = 0,
                        itemResolved = material.itemResolved == true,
                        sourceResolved = material.sourceResolved == true,
                        consumers = {},
                        plannerEligible = false,
                    }
                    byKey[key] = row
                    order[#order + 1] = key
                end
                row.required = row.required + (tonumber(material.quantity) or 0) * crafts
                row.itemResolved = row.itemResolved and material.itemResolved == true
                row.sourceResolved = row.sourceResolved and material.sourceResolved == true
                row.consumers[#row.consumers + 1] = {
                    routeIndex = step.routeIndex,
                    recipe = step.recipe,
                    crafts = crafts,
                    perCraft = tonumber(material.quantity) or 0,
                }
            end
        end
    end
    local out = {}
    table.sort(order, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(order) do out[#out + 1] = byKey[key] end
    return out
end

local function copyGate(gate)
    return {
        routeStepIndex = gate.routeStepIndex,
        tier = gate.tier,
        state = gate.state,
        ready = gate.ready == true,
        requiredSkill = gate.requiredSkill,
        skillCapFrom = gate.skillCapFrom,
        skillCapTo = gate.skillCapTo,
        minCharacterLevel = gate.minCharacterLevel,
        trainerSourceCount = gate.trainerSourceCount,
        trainerSources = gate.trainerSources,
        requirementEvidence = gate.requirementEvidence,
    }
end

local function copyAccess(access)
    return {
        routeStepIndex = access.routeStepIndex,
        recipe = access.recipe,
        kind = access.kind,
        state = access.state,
        sourceKind = access.sourceKind,
        evidence = access.evidence,
        liveVerified = access.liveVerified == true,
        externalVerified = access.externalVerified == true,
        currentBuild = access.currentBuild,
        ready = access.ready == true,
    }
end

local function copyDependency(dep)
    return {
        routeStepIndex = dep.routeStepIndex,
        recipe = dep.recipe,
        status = dep.status,
        observedBuild = dep.observedBuild,
        currentBuild = dep.currentBuild,
        intrinsicCandidateEligible = dep.intrinsicCandidateEligible == true,
    }
end

function ResearchRouteSegmentHandoff:Build(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}

    local qualificationModule = JLP:GetModule("ResearchRouteSegmentQualification")
    local bridgeModule = JLP:GetModule("ResearchRouteSegmentBridge")
    local candidateModule = JLP:GetModule("ResearchCandidateVerifier")
    local policyModule = JLP:GetModule("ResearchPromotionPolicy")
    local closureModule = JLP:GetModule("ResearchPromotionClosure")
    local route = routeFor(professionKey, mode)
    if not qualificationModule or not bridgeModule or not candidateModule or not policyModule or not closureModule or not route then return nil end

    local qualification = qualificationModule:Build(professionKey, mode, options)
    local bridge = bridgeModule:Build(professionKey, mode)
    local candidates = candidateModule:Build(professionKey, mode)
    if not qualification or not bridge or not candidates then return nil end

    local model = {
        contract = self.contract,
        plannerStepContract = self.plannerStepContract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        currentBuild = qualification.currentBuild,
        liveProfession = qualification.liveProfession,
        segments = {},
        segmentByIndex = {},
        stats = {
            qualificationSegments = qualification.stats and qualification.stats.segments or 0,
            qualifiedSegments = qualification.stats and qualification.stats.qualified or 0,
            stagedSegments = 0,
            normalizedCraftSteps = 0,
            pendingCraftSteps = 0,
            passedCraftSteps = 0,
            materialKinds = 0,
            unresolvedItemIDs = 0,
            unresolvedMaterialSources = 0,
            materialSourceConflicts = 0,
            staleMaterialSources = 0,
            liveMaterialSources = 0,
            externalMaterialSources = 0,
            shapeReadySegments = 0,
            dataCompleteSegments = 0,
            skippedSegments = 0,
        },
    }

    for _, qualificationRow in ipairs(qualification.segments or {}) do
        if qualificationRow.qualificationEligible == true and qualificationRow.status == "qualified-live-route-segment" then
            local sourceSegment = bridge.segmentByIndex[qualificationRow.segmentIndex]
            if sourceSegment then
                local staged = {
                    segmentIndex = sourceSegment.segmentIndex,
                    segmentID = sourceSegment.segmentID,
                    professionKey = professionKey,
                    mode = mode,
                    status = "qualified-route-segment-handoff-ready",
                    authority = self.authority,
                    qualificationStatus = qualificationRow.status,
                    qualificationClass = qualificationRow.qualificationClass,
                    startSkill = sourceSegment.startSkill,
                    endSkill = sourceSegment.endSkill,
                    currentSkill = qualification.liveProfession and tonumber(qualification.liveProfession.skill) or nil,
                    currentCap = qualification.liveProfession and tonumber(qualification.liveProfession.maxSkill) or nil,
                    startRouteStepIndex = sourceSegment.startRouteStepIndex,
                    endRouteStepIndex = sourceSegment.endRouteStepIndex,
                    buildProvenance = shallowCopy(sourceSegment.buildProvenance),
                    trainerGates = {},
                    accessRequirements = {},
                    dependencies = {},
                    steps = {},
                    pendingSteps = {},
                    materialRequirements = {},
                    plannerEligible = false,
                    executionEligible = false,
                    transferable = false,
                    readOnly = true,
                    handoffEligible = true,
                    compatibility = {
                        plannerShapeReady = true,
                        plannerDataComplete = true,
                        unresolvedItemIDs = 0,
                        unresolvedMaterialSources = 0,
                        materialSourceConflicts = 0,
                        staleMaterialSources = 0,
                        liveMaterialSources = 0,
                        externalMaterialSources = 0,
                        missingRecipeIDs = 0,
                    },
                }

                for _, gate in ipairs(sourceSegment.trainerGates or {}) do staged.trainerGates[#staged.trainerGates + 1] = copyGate(gate) end
                for _, access in ipairs(sourceSegment.accessRequirements or {}) do staged.accessRequirements[#staged.accessRequirements + 1] = copyAccess(access) end
                for _, dep in ipairs(sourceSegment.dependencies or {}) do staged.dependencies[#staged.dependencies + 1] = copyDependency(dep) end

                for _, stepRef in ipairs(sourceSegment.steps or {}) do
                    local rawStep = route.steps and route.steps[tonumber(stepRef.routeStepIndex)] or nil
                    local candidate = candidates.stepByRouteIndex and candidates.stepByRouteIndex[tonumber(stepRef.routeStepIndex)] or nil
                    local policy = policyModule:EvaluateIntrinsicStep(professionKey, mode, stepRef.routeStepIndex)
                    local closure = closureModule:EvaluateStep(professionKey, mode, stepRef.routeStepIndex)
                    if rawStep and candidate and policy and closure then
                        local normalized = buildNormalizedStep(professionKey, mode, rawStep, candidate, policy, closure, staged.currentSkill)
                        staged.steps[#staged.steps + 1] = normalized
                        model.stats.normalizedCraftSteps = model.stats.normalizedCraftSteps + 1
                        if normalized.relevance == "passed" then
                            model.stats.passedCraftSteps = model.stats.passedCraftSteps + 1
                        else
                            staged.pendingSteps[#staged.pendingSteps + 1] = normalized
                            model.stats.pendingCraftSteps = model.stats.pendingCraftSteps + 1
                        end
                        staged.compatibility.unresolvedItemIDs = staged.compatibility.unresolvedItemIDs + normalized.compatibility.unresolvedItemIDs
                        staged.compatibility.unresolvedMaterialSources = staged.compatibility.unresolvedMaterialSources + normalized.compatibility.unresolvedMaterialSources
                        for _, material in ipairs(normalized.materials or {}) do
                            local acquisition = material.acquisition
                            if acquisition then
                                if acquisition.conflict == true or acquisition.status == "external-material-source-conflict" then
                                    staged.compatibility.materialSourceConflicts = staged.compatibility.materialSourceConflicts + 1
                                elseif acquisition.status == "external-material-source-stale-build" then
                                    staged.compatibility.staleMaterialSources = staged.compatibility.staleMaterialSources + 1
                                elseif acquisition.liveVerified == true then
                                    staged.compatibility.liveMaterialSources = staged.compatibility.liveMaterialSources + 1
                                elseif acquisition.externalVerified == true then
                                    staged.compatibility.externalMaterialSources = staged.compatibility.externalMaterialSources + 1
                                end
                            end
                        end
                        if not normalized.recipeID then staged.compatibility.missingRecipeIDs = staged.compatibility.missingRecipeIDs + 1 end
                        if not normalized.compatibility.shapeReady then staged.compatibility.plannerShapeReady = false end
                    else
                        staged.compatibility.plannerShapeReady = false
                    end
                end

                staged.materialRequirements = aggregateMaterials(staged.pendingSteps)
                model.stats.materialKinds = model.stats.materialKinds + #staged.materialRequirements
                staged.compatibility.plannerDataComplete = staged.compatibility.plannerShapeReady
                    and staged.compatibility.unresolvedItemIDs == 0
                    and staged.compatibility.unresolvedMaterialSources == 0
                    and staged.compatibility.missingRecipeIDs == 0
                staged.compatibility.state = staged.compatibility.plannerDataComplete and "planner-data-staging-ready" or (staged.compatibility.plannerShapeReady and "planner-contract-shape-ready-data-incomplete" or "planner-contract-shape-incomplete")

                model.stats.unresolvedItemIDs = model.stats.unresolvedItemIDs + staged.compatibility.unresolvedItemIDs
                model.stats.unresolvedMaterialSources = model.stats.unresolvedMaterialSources + staged.compatibility.unresolvedMaterialSources
                model.stats.materialSourceConflicts = model.stats.materialSourceConflicts + staged.compatibility.materialSourceConflicts
                model.stats.staleMaterialSources = model.stats.staleMaterialSources + staged.compatibility.staleMaterialSources
                model.stats.liveMaterialSources = model.stats.liveMaterialSources + staged.compatibility.liveMaterialSources
                model.stats.externalMaterialSources = model.stats.externalMaterialSources + staged.compatibility.externalMaterialSources
                if staged.compatibility.plannerShapeReady then model.stats.shapeReadySegments = model.stats.shapeReadySegments + 1 end
                if staged.compatibility.plannerDataComplete then model.stats.dataCompleteSegments = model.stats.dataCompleteSegments + 1 end
                model.segments[#model.segments + 1] = staged
                model.segmentByIndex[staged.segmentIndex] = staged
                model.stats.stagedSegments = model.stats.stagedSegments + 1
            end
        else
            model.stats.skippedSegments = model.stats.skippedSegments + 1
        end
    end

    if model.stats.stagedSegments > 0 then
        model.state = model.stats.dataCompleteSegments == model.stats.stagedSegments and "qualified-handoff-data-complete" or "qualified-handoff-staging-available"
    elseif model.stats.qualifiedSegments > 0 then
        model.state = "qualified-segment-normalization-unavailable"
    else
        model.state = "awaiting-qualified-live-route-segment"
    end
    return model
end

function ResearchRouteSegmentHandoff:GetSegment(professionKey, mode, selector, options)
    local model = self:Build(professionKey, mode, options)
    if not model then return nil, nil end
    local index = tonumber(selector)
    if index then return model.segmentByIndex[index], model end
    local wanted = tostring(selector or ""):lower()
    if wanted ~= "" then
        for _, segment in ipairs(model.segments or {}) do
            for _, step in ipairs(segment.steps or {}) do
                if tostring(step.recipe or ""):lower() == wanted then return segment, model end
            end
        end
    end
    return nil, model
end

function ResearchRouteSegmentHandoff:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then return {"profession research unavailable"}, warnings end
    for professionKey, modes in pairs(root.professions or {}) do
        if professionKey ~= "HARNESS" and professionKey ~= "HARNESSCLOSURE" and professionKey ~= "HARNESSSEGMENT" and professionKey ~= "HARNESSQUAL" then
            for _, mode in ipairs({"normal", "aggressive"}) do
                if modes[mode] then
                    local model = self:Build(professionKey, mode)
                    if not model then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": qualified handoff unavailable"
                    else
                        if model.plannerEligible ~= false or model.executionEligible ~= false or model.transferable ~= false or model.readOnly ~= true then
                            errors[#errors + 1] = professionKey .. "/" .. mode .. ": handoff escaped read-only staging authority"
                        end
                        for _, segment in ipairs(model.segments or {}) do
                            if segment.plannerEligible ~= false or segment.executionEligible ~= false or segment.transferable ~= false or segment.readOnly ~= true then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": staged segment escaped authority boundary"
                            end
                            if segment.status ~= "qualified-route-segment-handoff-ready" or segment.qualificationStatus ~= "qualified-live-route-segment" then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": non-qualified segment entered handoff staging"
                            end
                            for _, step in ipairs(segment.steps or {}) do
                                if step.kind ~= "craft" or step.profession ~= professionKey or step.plannerEligible ~= false or step.executionEligible ~= false then
                                    errors[#errors + 1] = professionKey .. "/" .. mode .. ": normalized step violated Planner-compatible staging contract"
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return errors, warnings
end

local function formatSegment(segment)
    if not segment then return "Qualified route-segment handoff unavailable." end
    local lines = {
        string.format("Qualified route-segment handoff %d: %s / %s", tonumber(segment.segmentIndex) or 0, tostring(segment.professionKey), tostring(segment.mode)),
        "Status: " .. tostring(segment.status),
        string.format("Skill: %d-%d · live %s/%s · pending crafts %d/%d", tonumber(segment.startSkill) or 0, tonumber(segment.endSkill) or 0, tostring(segment.currentSkill or "?"), tostring(segment.currentCap or "?"), #(segment.pendingSteps or {}), #(segment.steps or {})),
        string.format("Metadata: trainer gates %d · access gates %d · dependencies %d", #(segment.trainerGates or {}), #(segment.accessRequirements or {}), #(segment.dependencies or {})),
        string.format("Materials: %d kinds · unresolved item IDs %d · unresolved sources %d", #(segment.materialRequirements or {}), tonumber(segment.compatibility.unresolvedItemIDs) or 0, tonumber(segment.compatibility.unresolvedMaterialSources) or 0),
        string.format("Acquisition evidence: live %d · external %d · stale %d · conflicts %d", tonumber(segment.compatibility.liveMaterialSources) or 0, tonumber(segment.compatibility.externalMaterialSources) or 0, tonumber(segment.compatibility.staleMaterialSources) or 0, tonumber(segment.compatibility.materialSourceConflicts) or 0),
        "Planner compatibility: " .. tostring(segment.compatibility.state),
        "Read-only handoff: true",
        "Planner authority: disabled",
    }
    for _, step in ipairs(segment.steps or {}) do
        lines[#lines + 1] = string.format("· %s · %d-%d · %s · %d craft(s) remaining", tostring(step.recipe or "unknown"), tonumber(step.skillMin) or 0, tonumber(step.skillTarget) or 0, tostring(step.relevance), tonumber(step.remainingCrafts) or 0)
    end
    return table.concat(lines, "\n")
end

function ResearchRouteSegmentHandoff:GetSummary(professionKey, mode, selector, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    if selector and tostring(selector) ~= "" then
        return formatSegment(self:GetSegment(professionKey, mode, selector, options))
    end
    local model = self:Build(professionKey, mode, options)
    if not model then return "Qualified route-segment handoff unavailable." end
    local s = model.stats
    local lines = {
        string.format("Qualified route-segment handoff: %s / %s", professionKey, mode),
        string.format("State: %s · read-only Planner-compatible staging", tostring(model.state)),
        string.format("Qualified segments: %d · staged %d · skipped %d", tonumber(s.qualifiedSegments) or 0, tonumber(s.stagedSegments) or 0, tonumber(s.skippedSegments) or 0),
        string.format("Craft steps: %d normalized · %d pending · %d already passed", tonumber(s.normalizedCraftSteps) or 0, tonumber(s.pendingCraftSteps) or 0, tonumber(s.passedCraftSteps) or 0),
        string.format("Planner compatibility: shape-ready %d · data-complete %d", tonumber(s.shapeReadySegments) or 0, tonumber(s.dataCompleteSegments) or 0),
        string.format("Material gaps: item IDs %d · source classifications %d", tonumber(s.unresolvedItemIDs) or 0, tonumber(s.unresolvedMaterialSources) or 0),
        string.format("Acquisition evidence: live %d · external %d · stale %d · conflicts %d", tonumber(s.liveMaterialSources) or 0, tonumber(s.externalMaterialSources) or 0, tonumber(s.staleMaterialSources) or 0, tonumber(s.materialSourceConflicts) or 0),
    }
    for _, segment in ipairs(model.segments or {}) do
        lines[#lines + 1] = string.format("· segment %d · %d-%d · %d pending crafts · %s", tonumber(segment.segmentIndex) or 0, tonumber(segment.startSkill) or 0, tonumber(segment.endSkill) or 0, #(segment.pendingSteps or {}), tostring(segment.compatibility.state))
    end
    lines[#lines + 1] = "Staged objects are never registered with the live Planner, Shopping/Acquisition, ActionQueue or execution pipeline."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ResearchRouteSegmentHandoff", ResearchRouteSegmentHandoff)
