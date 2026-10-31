local _, JLP = ...

-- Read-only contract-parity simulator for live-qualified research segments.
-- It deliberately reuses the production Planner/RequirementPlan/CraftReadiness/
-- ActionQueue read paths but never registers a research step with Planner and
-- never writes SavedVariables. Acquisition shaping is simulated locally because
-- the production AcquisitionPlanner is intentionally scoped to Tailoring and
-- Enchanting until a later authority bridge explicitly expands it.
local ResearchShadowPlanner = {
    contract = "read-only-planner-contract-parity-shadow-v2",
    authority = "planner-shadow-read-only-audit",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
    readOnly = true,
}

local REQUIRED = {
    plannerStep = {
        "kind", "profession", "skill", "skillTarget", "routeIndex", "recipe",
        "recipeSource", "expectedCrafts", "staticRemainingCrafts", "remainingCrafts",
        "estimateSource", "estimateSourceDetail", "estimateWeight", "materials",
        "evidence", "dataset", "rawStep",
    },
    professionPlan = {
        "status", "key", "profession", "step", "action", "actionKind", "materials",
    },
    materialState = {
        "itemID", "name", "source", "perCraft", "required", "owned", "missing", "storage",
    },
    requirementPlan = {
        "key", "plan", "recipe", "status", "rows", "materialTypes", "missingTypes", "totalMissingUnits",
    },
    requirementRow = {
        "itemID", "name", "source", "required", "owned", "missing", "storage", "options", "optionsText",
    },
    readiness = {
        "key", "status", "action", "recipe", "recipeKnowledge", "remainingCrafts",
        "immediateBags", "immediateStorage", "preparedBags", "preparedStorage", "tool", "materials",
    },
    actionQueue = { "key", "status", "currentIndex", "actions", "plan" },
    action = { "index", "kind", "text", "status" },
    acquisition = { "requirements", "shopping", "actions", "complete", "unresolved" },
    acquisitionRow = { "itemID", "name", "source", "required", "owned", "missing", "storage", "complete", "reasons" },
}

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function arrayCopy(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = row end
    return out
end

local function missingFields(row, required)
    local missing = {}
    for _, key in ipairs(required or {}) do
        if row == nil or row[key] == nil then missing[#missing + 1] = key end
    end
    return missing
end

local function appendGap(gaps, code, detail)
    gaps[#gaps + 1] = { code=code, detail=detail }
end


local function professionName(professionKey, liveProfession)
    if liveProfession and liveProfession.name then return liveProfession.name end
    local definitions = JLP.data and JLP.data.professions
    if definitions and definitions[professionKey] and definitions[professionKey].name then
        return definitions[professionKey].name
    end
    local fallback = tostring(professionKey or "Profession"):lower()
    return fallback:gsub("^%l", string.upper)
end

local function buildSyntheticDataset(professionKey, segment, step)
    local materials = {}
    for index, material in ipairs(step.materials or {}) do
        materials[index] = shallowCopy(material)
    end
    return {
        contract = "research-shadow-dataset-v1",
        name = professionName(professionKey, segment and segment.liveProfession),
        professionKey = professionKey,
        evidence = step.evidence,
        materials = materials,
        trainerGates = arrayCopy(segment and segment.trainerGates or {}),
        shadow = true,
        plannerEligible = false,
    }
end

local function buildPlannerStep(professionKey, mode, segment, stagedStep, options)
    local step = shallowCopy(stagedStep)
    local adapter = JLP:GetModule("ResearchRecursiveMaterialAdapter")
    local adaptedMaterials, adapterModel
    if adapter and adapter.AttachToStep then
        adaptedMaterials, adapterModel = adapter:AttachToStep(professionKey, mode, stagedStep)
    end
    if adaptedMaterials then step.materials = adaptedMaterials end
    step.recursiveAdapter = adapterModel
    local adaptive = JLP:GetModule("ResearchAdaptivePlannerParity")
    local adaptiveModel
    if adaptive and adaptive.ApplyToStep then
        step, adaptiveModel = adaptive:ApplyToStep(professionKey, mode, step, segment and segment.currentSkill, options)
    end
    step.adaptiveTelemetry = adaptiveModel
    step.dataset = buildSyntheticDataset(professionKey, segment, step)
    step.recipeSource = step.recipeSource or "known-current-build"
    step.requiredTool = step.requiredTool
    step.telemetryEstimate = nil
    step.telemetry = nil
    step.plannerEligible = false
    step.executionEligible = false
    step.transferable = false
    step.readOnly = true
    step.shadow = true
    return step
end

local function buildProfessionPlan(professionKey, segment, step)
    local planner = JLP:GetModule("Planner")
    local materials = planner and planner.GetMaterialStates and planner:GetMaterialStates(step) or {}
    local liveProfession = segment and segment.liveProfession or nil
    local name = professionName(professionKey, liveProfession)
    return {
        status = "craft",
        key = professionKey,
        profession = liveProfession or {
            name = name,
            skill = segment and segment.currentSkill or step.skill,
            maxSkill = segment and segment.currentCap or step.skillTarget,
            detected = true,
            cached = false,
        },
        step = step,
        action = string.format("Craft %s until %s %d.", tostring(step.recipe or "the recommended recipe"), name, tonumber(step.skillTarget) or 0),
        actionKind = "craft",
        materials = materials,
        shadow = true,
        readOnly = true,
        plannerEligible = false,
        executionEligible = false,
    }
end

local function requirementParity(requirementPlan)
    local gaps = {}
    local missing = missingFields(requirementPlan, REQUIRED.requirementPlan)
    if #missing > 0 then appendGap(gaps, "requirement-plan-shape", table.concat(missing, ",")) end
    for index, row in ipairs(requirementPlan and requirementPlan.rows or {}) do
        local rowMissing = missingFields(row, REQUIRED.requirementRow)
        if #rowMissing > 0 then appendGap(gaps, "requirement-row-shape", tostring(index) .. ":" .. table.concat(rowMissing, ",")) end
    end
    return #gaps == 0, gaps
end

local function plannerParity(plan)
    local gaps = {}
    local stepMissing = missingFields(plan and plan.step, REQUIRED.plannerStep)
    if #stepMissing > 0 then appendGap(gaps, "planner-step-shape", table.concat(stepMissing, ",")) end
    local planMissing = missingFields(plan, REQUIRED.professionPlan)
    if #planMissing > 0 then appendGap(gaps, "profession-plan-shape", table.concat(planMissing, ",")) end
    for index, row in ipairs(plan and plan.materials or {}) do
        local rowMissing = missingFields(row, REQUIRED.materialState)
        if #rowMissing > 0 then appendGap(gaps, "material-state-shape", tostring(index) .. ":" .. table.concat(rowMissing, ",")) end
    end
    return #gaps == 0, gaps
end

local function readinessParity(readiness)
    local gaps = {}
    local missing = missingFields(readiness, REQUIRED.readiness)
    if #missing > 0 then appendGap(gaps, "readiness-shape", table.concat(missing, ",")) end
    return #gaps == 0, gaps
end

local function queueParity(queue)
    local gaps = {}
    local missing = missingFields(queue, REQUIRED.actionQueue)
    if #missing > 0 then appendGap(gaps, "action-queue-shape", table.concat(missing, ",")) end
    for index, action in ipairs(queue and queue.actions or {}) do
        local actionMissing = missingFields(action, REQUIRED.action)
        if #actionMissing > 0 then appendGap(gaps, "action-shape", tostring(index) .. ":" .. table.concat(actionMissing, ",")) end
    end
    return #gaps == 0, gaps
end

local function acquisitionAction(source, row)
    if row.missing <= 0 then return nil, nil end
    if source == "vendor" then return "vendor-purchase", nil end
    if source == "auction" then return "auction-acquire", nil end
    if source == "disenchant-or-auction" then return "disenchant-or-auction", nil end
    if source == "crafted" or source == "craft" then
        if row.craftedRecipe then return "craft-intermediate", nil end
        if row.craftedFrom then return "craft-intermediate", nil end
        return nil, "recursive-crafted-material-adapter-required"
    end
    return nil, "unsupported-acquisition-source:" .. tostring(source or "unknown")
end

local function appendRequirement(model, material, reason)
    local row = {
        itemID = material.itemID,
        name = material.name,
        source = material.source,
        required = tonumber(material.required) or 0,
        owned = tonumber(material.owned) or 0,
        missing = tonumber(material.missing) or 0,
        storage = material.storage or {},
        craftedFrom = material.craftedFrom,
        craftedRecipe = material.craftedRecipe,
        complete = true,
        reasons = { reason or "shadow craft" },
    }
    model.requirements[#model.requirements + 1] = row
    return row
end

local function appendExternalAcquisition(model, row, reason)
    if row.missing <= 0 then return true end
    local kind, gap = acquisitionAction(row.source, row)
    if not kind then
        row.complete = false
        model.complete = false
        model.unresolved[#model.unresolved + 1] = {
            itemID = row.itemID, name = row.name, source = row.source, reason = gap,
        }
        return false
    end
    local shopping = shallowCopy(row)
    shopping.actionKind = kind
    model.shopping[#model.shopping + 1] = shopping
    model.actions[#model.actions + 1] = {
        kind = kind, itemID = row.itemID, name = row.name, source = row.source,
        quantity = row.missing, reason = reason, readOnly = true,
    }
    return true
end

local function expandCraftedAcquisition(model, node, reason, depth, active)
    if type(node) ~= "table" then
        model.complete = false
        model.unresolved[#model.unresolved + 1] = { reason="recursive-crafted-material-adapter-required", name=reason }
        return false
    end
    depth = tonumber(depth) or 0
    if depth > 12 then
        model.complete = false
        model.unresolved[#model.unresolved + 1] = { reason="max-recursion-depth", name=node.name }
        return false
    end
    local token = tostring(node.producerStepIndex or node.recipe or node.name or depth)
    active = active or {}
    if active[token] then
        model.complete = false
        model.unresolved[#model.unresolved + 1] = { reason="dependency-cycle", name=node.name }
        return false
    end
    active[token] = true

    local ok = node.resolved ~= false
    if not ok then
        model.complete = false
        model.unresolved[#model.unresolved + 1] = { reason="recursive-crafted-material-adapter-incomplete", name=node.name }
    end
    for _, material in ipairs(node.materials or {}) do
        local row = appendRequirement(model, material, "Input for " .. tostring(node.recipe or node.name or reason or "intermediate"))
        if row.missing > 0 then
            if material.craftedRecipe then
                if not expandCraftedAcquisition(model, material.craftedRecipe, node.recipe or node.name, depth + 1, active) then ok = false end
            elseif not appendExternalAcquisition(model, row, node.recipe or node.name) then
                ok = false
            end
        end
    end
    model.actions[#model.actions + 1] = {
        kind = "craft-intermediate",
        itemID = node.itemID,
        name = node.name,
        recipe = node.recipe,
        recipeID = node.recipeID,
        source = "crafted",
        quantity = tonumber(node.craftsNeeded) or 0,
        outputUnits = tonumber(node.producedOutput) or 0,
        outputPerCraft = tonumber(node.outputPerCraft) or 1,
        producerStepIndex = node.producerStepIndex,
        recursiveDepth = depth,
        readOnly = true,
    }
    active[token] = nil
    return ok
end

local function buildShadowAcquisition(plan)
    local model = {
        contract = "shadow-acquisition-plan-v2",
        requirements = {}, shopping = {}, actions = {}, complete = true, unresolved = {},
        readOnly = true, plannerEligible = false, executionEligible = false,
    }
    for _, material in ipairs(plan and plan.materials or {}) do
        local row = appendRequirement(model, material, tostring(plan.step and plan.step.recipe or "shadow craft"))
        if row.missing > 0 then
            if material.craftedRecipe then
                expandCraftedAcquisition(model, material.craftedRecipe, row.name, 1, {})
            else
                appendExternalAcquisition(model, row, row.name)
            end
        end
    end
    return model
end

local function acquisitionParity(acquisition)
    local gaps = {}
    local missing = missingFields(acquisition, REQUIRED.acquisition)
    if #missing > 0 then appendGap(gaps, "acquisition-shape", table.concat(missing, ",")) end
    for index, row in ipairs(acquisition and acquisition.requirements or {}) do
        local rowMissing = missingFields(row, REQUIRED.acquisitionRow)
        if #rowMissing > 0 then appendGap(gaps, "acquisition-row-shape", tostring(index) .. ":" .. table.concat(rowMissing, ",")) end
    end
    for _, unresolved in ipairs(acquisition and acquisition.unresolved or {}) do
        appendGap(gaps, unresolved.reason or "acquisition-unresolved", unresolved.name)
    end
    return #gaps == 0 and acquisition.complete == true, gaps
end

local function appendGaps(target, source)
    for _, gap in ipairs(source or {}) do target[#target + 1] = gap end
end

local function auditStep(professionKey, mode, segment, stagedStep, options)
    local plannerStep = buildPlannerStep(professionKey, mode, segment, stagedStep, options)
    local plan = buildProfessionPlan(professionKey, segment, plannerStep)
    local requirementModule = JLP:GetModule("RequirementPlan")
    local readinessModule = JLP:GetModule("CraftReadiness")
    local queueModule = JLP:GetModule("ActionQueue")
    local requirementPlan = requirementModule and requirementModule:Build(professionKey, plan) or nil
    local readiness = readinessModule and readinessModule:Get(professionKey, plan) or nil
    local queue = queueModule and queueModule:Build(professionKey, plan, readiness) or nil
    local acquisition = buildShadowAcquisition(plan)

    local plannerOK, plannerGaps = plannerParity(plan)
    local adaptiveTelemetry = plannerStep.adaptiveTelemetry
    if adaptiveTelemetry and adaptiveTelemetry.ready == false then
        plannerOK = false
        appendGap(plannerGaps, "adaptive-telemetry-provenance", adaptiveTelemetry.blockedReason or adaptiveTelemetry.state)
    end
    local requirementOK, requirementGaps = requirementParity(requirementPlan)
    local readinessOK, readinessGaps = readinessParity(readiness)
    local queueOK, queueGaps = queueParity(queue)
    local acquisitionOK, acquisitionGaps = acquisitionParity(acquisition)
    local gaps = {}
    appendGaps(gaps, plannerGaps)
    appendGaps(gaps, requirementGaps)
    appendGaps(gaps, readinessGaps)
    appendGaps(gaps, queueGaps)
    appendGaps(gaps, acquisitionGaps)

    local recursiveGaps = 0
    local recursiveNodes = 0
    local function inspectNode(node, active)
        if type(node) ~= "table" then return false end
        local token = tostring(node.producerStepIndex or node.recipe or node.name or recursiveNodes)
        active = active or {}
        if active[token] then return false end
        active[token] = true
        recursiveNodes = recursiveNodes + 1
        local ok = node.resolved ~= false and tonumber(node.outputPerCraft) ~= nil
        for _, child in ipairs(node.materials or {}) do
            if child.source == "crafted" or child.source == "craft" then
                if not child.craftedRecipe or not inspectNode(child.craftedRecipe, active) then ok = false end
            end
        end
        active[token] = nil
        return ok
    end
    for _, material in ipairs(plannerStep.materials or {}) do
        if material.source == "crafted" or material.source == "craft" then
            if not material.craftedRecipe or not inspectNode(material.craftedRecipe, {}) then
                recursiveGaps = recursiveGaps + 1
                appendGap(gaps, "recursive-crafted-material-adapter-incomplete", material.name)
            end
        end
    end

    local ready = plannerOK and requirementOK and readinessOK and queueOK and acquisitionOK and recursiveGaps == 0
    return {
        routeIndex = stagedStep.routeIndex,
        recipe = stagedStep.recipe,
        recipeID = stagedStep.recipeID,
        status = ready and "shadow-planner-parity-ready" or "shadow-planner-contract-gap",
        parityReady = ready,
        planner = plan,
        requirementPlan = requirementPlan,
        readiness = readiness,
        actionQueue = queue,
        acquisition = acquisition,
        adaptiveTelemetry = adaptiveTelemetry,
        parity = {
            planner = plannerOK,
            requirements = requirementOK,
            readiness = readinessOK,
            actions = queueOK,
            acquisition = acquisitionOK,
            recursiveAdapterGaps = recursiveGaps,
            recursiveAdapterNodes = recursiveNodes,
            gaps = gaps,
        },
        authority = ResearchShadowPlanner.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
    }
end

function ResearchShadowPlanner:GetContractManifest()
    return REQUIRED
end

function ResearchShadowPlanner:Build(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    local handoffModule = JLP:GetModule("ResearchRouteSegmentHandoff")
    local handoff = handoffModule and handoffModule:Build(professionKey, mode, options) or nil
    if not handoff then return nil end

    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        sourceHandoffState = handoff.state,
        currentBuild = handoff.currentBuild,
        liveProfession = handoff.liveProfession,
        segments = {},
        segmentByIndex = {},
        stats = {
            handoffSegments = handoff.stats and handoff.stats.stagedSegments or 0,
            dataCompleteSegments = handoff.stats and handoff.stats.dataCompleteSegments or 0,
            shadowSegments = 0,
            auditedSteps = 0,
            parityReadySteps = 0,
            contractGapSteps = 0,
            recursiveAdapterGaps = 0,
            recursiveAdapterNodes = 0,
            requirementRows = 0,
            acquisitionRows = 0,
            actionRows = 0,
            telemetryAdaptiveSteps = 0,
            telemetryStaticSteps = 0,
            telemetryBlockedSteps = 0,
        },
    }

    for _, segment in ipairs(handoff.segments or {}) do
        local shadowSegment = {
            segmentIndex = segment.segmentIndex,
            segmentID = segment.segmentID,
            startSkill = segment.startSkill,
            endSkill = segment.endSkill,
            currentSkill = segment.currentSkill,
            currentCap = segment.currentCap,
            sourceCompatibility = shallowCopy(segment.compatibility),
            steps = {},
            parityReady = true,
            readOnly = true,
            plannerEligible = false,
            executionEligible = false,
        }
        for _, stagedStep in ipairs(segment.pendingSteps or {}) do
            local audited = auditStep(professionKey, mode, {
                liveProfession = handoff.liveProfession,
                currentSkill = segment.currentSkill,
                currentCap = segment.currentCap,
                trainerGates = segment.trainerGates,
            }, stagedStep, options)
            shadowSegment.steps[#shadowSegment.steps + 1] = audited
            model.stats.auditedSteps = model.stats.auditedSteps + 1
            model.stats.requirementRows = model.stats.requirementRows + #(audited.requirementPlan and audited.requirementPlan.rows or {})
            model.stats.acquisitionRows = model.stats.acquisitionRows + #(audited.acquisition and audited.acquisition.requirements or {})
            model.stats.actionRows = model.stats.actionRows + #(audited.actionQueue and audited.actionQueue.actions or {})
            model.stats.recursiveAdapterGaps = model.stats.recursiveAdapterGaps + (audited.parity and audited.parity.recursiveAdapterGaps or 0)
            model.stats.recursiveAdapterNodes = model.stats.recursiveAdapterNodes + (audited.parity and audited.parity.recursiveAdapterNodes or 0)
            if audited.adaptiveTelemetry then
                if audited.adaptiveTelemetry.ready == false then
                    model.stats.telemetryBlockedSteps = model.stats.telemetryBlockedSteps + 1
                elseif audited.adaptiveTelemetry.adaptiveApplied then
                    model.stats.telemetryAdaptiveSteps = model.stats.telemetryAdaptiveSteps + 1
                else
                    model.stats.telemetryStaticSteps = model.stats.telemetryStaticSteps + 1
                end
            end
            if audited.parityReady then
                model.stats.parityReadySteps = model.stats.parityReadySteps + 1
            else
                shadowSegment.parityReady = false
                model.stats.contractGapSteps = model.stats.contractGapSteps + 1
            end
        end
        shadowSegment.status = shadowSegment.parityReady and "shadow-planner-segment-parity-ready" or "shadow-planner-segment-contract-gaps"
        model.segments[#model.segments + 1] = shadowSegment
        model.segmentByIndex[shadowSegment.segmentIndex] = shadowSegment
        model.stats.shadowSegments = model.stats.shadowSegments + 1
    end

    if model.stats.shadowSegments == 0 then
        model.state = "awaiting-planner-data-complete-segment"
    elseif model.stats.contractGapSteps > 0 then
        model.state = "shadow-planner-contract-gaps"
    else
        model.state = "shadow-planner-parity-ready"
    end
    return model
end

function ResearchShadowPlanner:GetSegment(professionKey, mode, selector, options)
    local model = self:Build(professionKey, mode, options)
    if not model then return nil, nil end
    local index = tonumber(selector)
    if index then return model.segmentByIndex[index], model end
    local wanted = tostring(selector or ""):lower()
    if wanted ~= "" then
        for _, segment in ipairs(model.segments or {}) do
            for _, step in ipairs(segment.steps or {}) do
                if tostring(step.recipe or ""):lower() == wanted then return segment, model, step end
            end
        end
    end
    return nil, model
end

function ResearchShadowPlanner:GetSummary(professionKey, mode, selector, options)
    local selected, model, selectedStep = self:GetSegment(professionKey, mode, selector, options)
    model = model or self:Build(professionKey, mode, options)
    if not model then return "Shadow Planner audit unavailable." end
    local lines = {
        "PLANNER CONTRACT PARITY / SHADOW AUDIT",
        string.format("%s / %s", tostring(model.professionKey), tostring(model.mode)),
        "State: " .. tostring(model.state),
        string.format("Segments: %d shadow / %d handoff", tonumber(model.stats.shadowSegments) or 0, tonumber(model.stats.handoffSegments) or 0),
        string.format("Steps: %d ready / %d audited", tonumber(model.stats.parityReadySteps) or 0, tonumber(model.stats.auditedSteps) or 0),
        string.format("Contract gaps: %d steps · recursive adapter gaps %d · nodes %d", tonumber(model.stats.contractGapSteps) or 0, tonumber(model.stats.recursiveAdapterGaps) or 0, tonumber(model.stats.recursiveAdapterNodes) or 0),
        string.format("Rows: %d requirements · %d acquisition · %d actions", tonumber(model.stats.requirementRows) or 0, tonumber(model.stats.acquisitionRows) or 0, tonumber(model.stats.actionRows) or 0),
        string.format("Telemetry parity: %d adaptive · %d static · %d blocked", tonumber(model.stats.telemetryAdaptiveSteps) or 0, tonumber(model.stats.telemetryStaticSteps) or 0, tonumber(model.stats.telemetryBlockedSteps) or 0),
    }
    if selected then
        lines[#lines + 1] = string.format("Selected segment %d: %s", tonumber(selected.segmentIndex) or 0, tostring(selected.status))
        local step = selectedStep or selected.steps[1]
        if step then
            lines[#lines + 1] = string.format("Recipe: %s", tostring(step.recipe or "unknown"))
            lines[#lines + 1] = "Step parity: " .. tostring(step.status)
            lines[#lines + 1] = string.format("Requirement/readiness/actions/acquisition: %s/%s/%s/%s",
                step.parity.requirements and "pass" or "gap",
                step.parity.readiness and "pass" or "gap",
                step.parity.actions and "pass" or "gap",
                step.parity.acquisition and "pass" or "gap")
            if step.adaptiveTelemetry then
                lines[#lines + 1] = string.format("Adaptive telemetry: %s · static %s · production %s · shadow %s",
                    tostring(step.adaptiveTelemetry.state),
                    tostring(step.adaptiveTelemetry.staticRemainingCrafts),
                    tostring(step.adaptiveTelemetry.productionRemainingCrafts),
                    tostring(step.adaptiveTelemetry.shadowRemainingCrafts))
            end
            for _, gap in ipairs(step.parity.gaps or {}) do
                lines[#lines + 1] = string.format("· %s%s", tostring(gap.code), gap.detail and (" - " .. tostring(gap.detail)) or "")
            end
        end
    end
    lines[#lines + 1] = "Side effects: none · SavedVariables writes: 0"
    lines[#lines + 1] = "Planner authority: disabled"
    lines[#lines + 1] = "Execution authority: disabled"
    return table.concat(lines, "\n")
end

function ResearchShadowPlanner:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then return {"profession research unavailable"}, warnings end
    if self.plannerEligible ~= false or self.executionEligible ~= false or self.transferable ~= false or self.readOnly ~= true then
        errors[#errors + 1] = "shadow planner authority boundary invalid"
    end
    local handoffModule = JLP:GetModule("ResearchRouteSegmentHandoff")
    local requirementModule = JLP:GetModule("RequirementPlan")
    local readinessModule = JLP:GetModule("CraftReadiness")
    local queueModule = JLP:GetModule("ActionQueue")
    local planner = JLP:GetModule("Planner")
    local adaptive = JLP:GetModule("ResearchAdaptivePlannerParity")
    if not handoffModule or not requirementModule or not readinessModule or not queueModule or not planner or not adaptive then
        errors[#errors + 1] = "shadow planner production-contract dependency missing"
    end
    return errors, warnings
end

JLP:RegisterModule("ResearchShadowPlanner", ResearchShadowPlanner)
