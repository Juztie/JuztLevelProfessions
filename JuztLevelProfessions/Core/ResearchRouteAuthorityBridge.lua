local _, JLP = ...

-- First controlled route-authority bridge for research-derived profession routes.
-- Authority is intentionally limited to Planner reads. Every call rebuilds the
-- current-build evidence chain; no promoted route is cached or persisted. This
-- makes authority self-revoking when build/evidence/live qualification changes.
local ResearchRouteAuthorityBridge = {
    contract = "controlled-route-authority-bridge-v1",
    datasetContract = "controlled-research-planner-dataset-v1",
    authority = "feature-gated-current-build-planner-route-authority",
    executionEligible = false,
    transferableToExecution = false,
    readOnly = true,
}

local PRODUCTION_KEYS = {
    ALCHEMY = true,
    BLACKSMITHING = true,
    ENGINEERING = true,
    LEATHERWORKING = true,
}

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function copyArray(rows)
    local out = {}
    for index, row in ipairs(rows or {}) do out[index] = row end
    return out
end

-- Returned planning snapshots must not let UI consumers mutate the cached
-- evidence graph. Demand entries are copied as well as their parent rows.
local function copyPlanningRows(rows)
    local out = {}
    for index, row in ipairs(rows or {}) do
        local item = shallowCopy(row)
        if type(item.demands) == "table" then
            item.demands = {}
            for i, demand in ipairs(row.demands) do item.demands[i] = shallowCopy(demand) end
        end
        out[index] = item
    end
    return out
end

local function featureProfile()
    local profile = JLP.DB and JLP.DB.profile
    return profile and profile.researchRouteAuthority or nil
end

local function featureEnabled()
    local profile = featureProfile()
    -- Planner promotion can be automatic, but remains read-only. An explicit
    -- disable through SetFeatureEnabled(false) clears autoPlannerPromotion.
    -- Existing SavedVariables with enabled=false may receive the new setting
    -- through normal default merging; native execution gates stay untouched.
    return profile ~= nil and (profile.enabled == true or profile.autoPlannerPromotion == true)
end

local function configuredMode()
    local profile = featureProfile()
    return normalizeMode(profile and profile.mode or "normal")
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function professionName(professionKey, liveProfession)
    if liveProfession and liveProfession.name then return liveProfession.name end
    local definitions = JLP.data and JLP.data.professions
    if definitions and definitions[professionKey] and definitions[professionKey].name then
        return definitions[professionKey].name
    end
    local text = tostring(professionKey or "Profession"):lower()
    return text:gsub("^%l", string.upper)
end

local function scalarEqual(a, b)
    if type(a) == "number" or type(b) == "number" then
        return tonumber(a) == tonumber(b)
    end
    return a == b
end

local function addGap(gaps, surface, path, left, right)
    gaps[#gaps + 1] = {
        surface = surface,
        path = path,
        live = left,
        shadow = right,
    }
end

local function compareScalar(gaps, surface, path, left, right)
    if not scalarEqual(left, right) then addGap(gaps, surface, path, left, right) end
end

local function compareCraftedRecipe(gaps, surface, path, live, shadow, depth)
    depth = tonumber(depth) or 0
    if depth > 12 then
        addGap(gaps, surface, path .. ".depth", "max-depth", "max-depth")
        return
    end
    if (live == nil) ~= (shadow == nil) then
        addGap(gaps, surface, path, live and "present" or "missing", shadow and "present" or "missing")
        return
    end
    if not live then return end
    for _, key in ipairs({"itemID", "recipe", "recipeID", "producerStepIndex", "outputPerCraft", "outputNeeded", "craftsNeeded", "producedOutput", "resolved"}) do
        compareScalar(gaps, surface, path .. "." .. key, live[key], shadow[key])
    end
    local liveRows, shadowRows = live.materials or {}, shadow.materials or {}
    compareScalar(gaps, surface, path .. ".materials.count", #liveRows, #shadowRows)
    local count = math.min(#liveRows, #shadowRows)
    for index = 1, count do
        local a, b = liveRows[index], shadowRows[index]
        local rowPath = string.format("%s.materials[%d]", path, index)
        for _, key in ipairs({"itemID", "name", "source", "perCraft", "required", "owned", "missing", "relation", "producerStepIndex"}) do
            compareScalar(gaps, surface, rowPath .. "." .. key, a[key], b[key])
        end
        compareCraftedRecipe(gaps, surface, rowPath .. ".craftedRecipe", a.craftedRecipe, b.craftedRecipe, depth + 1)
    end
end

local function compareMaterialRows(gaps, surface, liveRows, shadowRows, path)
    liveRows, shadowRows = liveRows or {}, shadowRows or {}
    compareScalar(gaps, surface, path .. ".count", #liveRows, #shadowRows)
    local count = math.min(#liveRows, #shadowRows)
    for index = 1, count do
        local live, shadow = liveRows[index], shadowRows[index]
        local rowPath = string.format("%s[%d]", path, index)
        for _, key in ipairs({"itemID", "name", "source", "required", "owned", "missing"}) do
            compareScalar(gaps, surface, rowPath .. "." .. key, live[key], shadow[key])
        end
        if live.perCraft ~= nil or shadow.perCraft ~= nil then
            compareScalar(gaps, surface, rowPath .. ".perCraft", live.perCraft, shadow.perCraft)
        end
        compareCraftedRecipe(gaps, surface, rowPath .. ".craftedRecipe", live.craftedRecipe, shadow.craftedRecipe, 0)
    end
end

local function compareActions(gaps, live, shadow)
    live, shadow = live or {}, shadow or {}
    compareScalar(gaps, "action-queue", "status", live.status, shadow.status)
    local liveRows, shadowRows = live.actions or {}, shadow.actions or {}
    compareScalar(gaps, "action-queue", "actions.count", #liveRows, #shadowRows)
    local count = math.min(#liveRows, #shadowRows)
    for index = 1, count do
        local a, b = liveRows[index], shadowRows[index]
        local path = string.format("actions[%d]", index)
        for _, key in ipairs({"kind", "text", "status"}) do
            compareScalar(gaps, "action-queue", path .. "." .. key, a[key], b[key])
        end
    end
end

local function compareLiveShadow(live, shadowStep)
    local gaps = {}
    local shadowPlan = shadowStep and shadowStep.planner or nil
    if not live or not shadowPlan then
        addGap(gaps, "planner", "plan", live and "present" or "missing", shadowPlan and "present" or "missing")
        return {
            ready = false,
            planner = false,
            requirements = false,
            readiness = false,
            actions = false,
            gaps = gaps,
        }
    end

    compareScalar(gaps, "planner", "status", live.plan and live.plan.status, shadowPlan.status)
    compareScalar(gaps, "planner", "actionKind", live.plan and live.plan.actionKind, shadowPlan.actionKind)
    for _, key in ipairs({"recipe", "routeIndex", "skillTarget", "remainingCrafts"}) do
        compareScalar(gaps, "planner", "step." .. key, live.plan and live.plan.step and live.plan.step[key], shadowPlan.step and shadowPlan.step[key])
    end
    compareMaterialRows(gaps, "planner", live.plan and live.plan.materials, shadowPlan.materials, "materials")
    local plannerGapCount = #gaps

    local liveReq, shadowReq = live.requirementPlan or {}, shadowStep.requirementPlan or {}
    compareScalar(gaps, "requirement-plan", "status", liveReq.status, shadowReq.status)
    compareScalar(gaps, "requirement-plan", "materialTypes", liveReq.materialTypes, shadowReq.materialTypes)
    compareScalar(gaps, "requirement-plan", "missingTypes", liveReq.missingTypes, shadowReq.missingTypes)
    compareScalar(gaps, "requirement-plan", "totalMissingUnits", liveReq.totalMissingUnits, shadowReq.totalMissingUnits)
    compareMaterialRows(gaps, "requirement-plan", liveReq.rows, shadowReq.rows, "rows")
    local requirementGapCount = #gaps - plannerGapCount

    local liveReady, shadowReady = live.readiness or {}, shadowStep.readiness or {}
    for _, key in ipairs({"status", "recipe", "remainingCrafts", "immediateBags", "immediateStorage", "preparedBags", "preparedStorage"}) do
        compareScalar(gaps, "craft-readiness", key, liveReady[key], shadowReady[key])
    end
    local readinessGapCount = #gaps - plannerGapCount - requirementGapCount

    local beforeActions = #gaps
    compareActions(gaps, live.actionQueue, shadowStep.actionQueue)
    local actionGapCount = #gaps - beforeActions

    return {
        ready = #gaps == 0,
        planner = plannerGapCount == 0,
        requirements = requirementGapCount == 0,
        readiness = readinessGapCount == 0,
        actions = actionGapCount == 0,
        gaps = gaps,
    }
end

local function findShadowStep(shadowSegment, recipe, routeIndex)
    -- Recipe names are not unique within a progression route. A Planner step
    -- must match one and only one *route ordinal* in its qualified segment.
    local wanted = tonumber(routeIndex)
    if not wanted then return nil end
    local found
    for _, step in ipairs(shadowSegment and shadowSegment.steps or {}) do
        if tonumber(step.routeIndex) == wanted then
            if found or tostring(step.recipe or "") ~= tostring(recipe or "") then return nil end
            found = step
        end
    end
    return found
end

local function findBlockedAdaptiveTelemetry(shadow)
    for _, segment in ipairs(shadow and shadow.segments or {}) do
        for _, step in ipairs(segment.steps or {}) do
            local adaptive = step.adaptiveTelemetry
            if adaptive and adaptive.productionTelemetryActive == true and adaptive.ready == false then
                return adaptive, segment.segmentIndex, step.recipe
            end
        end
    end
    return nil
end

local function attachAuthorityStep(professionKey, mode, stagedStep)
    local step = shallowCopy(stagedStep)
    local adapter = JLP:GetModule("ResearchRecursiveMaterialAdapter")
    if adapter and adapter.AttachToStep then
        local materials, model = adapter:AttachToStep(professionKey, mode, stagedStep)
        if materials then step.materials = materials end
        step.recursiveAdapter = model
    else
        step.materials = copyArray(stagedStep.materials)
    end
    step.authority = ResearchRouteAuthorityBridge.authority
    step.craftCountAuthority = "authority-ready-research-route"
    step.plannerEligible = true
    step.executionEligible = false
    step.transferable = false
    step.readOnly = true
    step.routeAuthorityEnabled = true
    step.researchAuthority = true
    return step
end

local function buildDataset(professionKey, mode, segment, readinessRow, activeBuild)
    local dataset = {
        contract = ResearchRouteAuthorityBridge.datasetContract,
        name = professionName(professionKey, segment and segment.liveProfession),
        professionKey = professionKey,
        mode = mode,
        evidence = "planner-authority-readiness-ready",
        authority = ResearchRouteAuthorityBridge.authority,
        currentBuild = activeBuild,
        segmentIndex = segment.segmentIndex,
        segmentID = segment.segmentID,
        startSkill = segment.startSkill,
        endSkill = segment.endSkill,
        route = {},
        steps = nil,
        trainerGates = {},
        plannerEligible = true,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        routeAuthorityEnabled = true,
        trainerAuthorityEnabled = false,
        acquisitionAuthorityEnabled = false,
        authorityReadiness = readinessRow,
    }
    for _, stagedStep in ipairs(segment.pendingSteps or {}) do
        dataset.route[#dataset.route + 1] = attachAuthorityStep(professionKey, mode, stagedStep)
    end
    dataset.steps = dataset.route
    return dataset
end

local function buildLiveSurfaces(professionKey, professionState, dataset)
    local planner = JLP:GetModule("Planner")
    if not planner or not planner.BuildProfessionPlanForDataset then return nil end
    local plan = planner:BuildProfessionPlanForDataset(professionKey, professionState, dataset)
    if not plan then return nil end
    local requirement = JLP:GetModule("RequirementPlan")
    local readinessModule = JLP:GetModule("CraftReadiness")
    local queue = JLP:GetModule("ActionQueue")
    local readiness = readinessModule and readinessModule.Get and readinessModule:Get(professionKey, plan) or nil
    return {
        plan = plan,
        requirementPlan = requirement and requirement.Build and requirement:Build(professionKey, plan) or nil,
        readiness = readiness,
        actionQueue = queue and queue.Build and queue:Build(professionKey, plan, readiness) or nil,
    }
end

-- Build-neutral reference view. Research evidence is useful for comparing
-- routes across client builds, but MUST NOT produce a Planner dataset or a
-- promotion/dispatch credential. The controlled route-authority bridge above
-- retains all of its existing live gates and explicit user opt-in.
function ResearchRouteAuthorityBridge:GetPlanningReference(professionKey, mode)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode or configuredMode())
    local graphModule = JLP:GetModule("ProfessionDependencyGraph")
    local supplementModule = JLP:GetModule("ResearchSupplementPlanner")
    local graph = graphModule and graphModule.Build and graphModule:Build(professionKey, mode) or nil
    local supplement = supplementModule and supplementModule.Build and supplementModule:Build(professionKey, mode) or nil
    return {
        contract = "build-neutral-research-planning-reference-v1",
        professionKey = professionKey, mode = mode,
        state = graph and "research-planning-reference-available" or "research-planning-reference-unavailable",
        authority = "research-reference-only", readOnly = true,
        planningOnly = true, plannerEligible = false,
        routeAuthorityEnabled = false, executionEligible = false,
        transferable = false, acquisitionAuthorityEnabled = false,
        sourceEvidence = graph and graph.evidence or nil,
        dependencyState = graph and graph.candidateState or "unavailable",
        supplementalState = supplement and supplement.candidateState or "unavailable",
        dependencyStats = graph and shallowCopy(graph.stats) or nil,
        supplementalStats = supplement and shallowCopy(supplement.stats) or nil,
        planningReferenceOutputs = copyPlanningRows(graph and graph.planningReferenceOutputs),
        unresolvedIntermediateRequirements = copyPlanningRows(graph and graph.unresolvedIntermediateRequirements),
        supplementalRequirements = copyPlanningRows(graph and graph.supplementalRequirements),
    }
end

function ResearchRouteAuthorityBridge:IsSupported(professionKey)
    return PRODUCTION_KEYS[tostring(professionKey or ""):upper()] == true
end

function ResearchRouteAuthorityBridge:IsFeatureEnabled()
    return featureEnabled()
end

function ResearchRouteAuthorityBridge:GetConfiguredMode()
    return configuredMode()
end

function ResearchRouteAuthorityBridge:SetFeatureEnabled(enabled)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    profile.enabled = enabled == true
    profile.autoPlannerPromotion = enabled == true
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_ROUTE_AUTHORITY_UPDATED", { enabled=featureEnabled(), mode=normalizeMode(profile.mode) })
    end
    return true, featureEnabled() and "enabled" or "disabled"
end

function ResearchRouteAuthorityBridge:SetMode(mode)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    profile.mode = normalizeMode(mode)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_ROUTE_AUTHORITY_UPDATED", { enabled=featureEnabled(), mode=profile.mode })
    end
    return true, profile.mode
end

function ResearchRouteAuthorityBridge:Build(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode or configuredMode())
    options = type(options) == "table" and options or {}

    local enabled = featureEnabled()
    local activeBuild = currentBuild()
    local readiness, handoff, shadow

    local model = {
        contract = self.contract,
        datasetContract = self.datasetContract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        featureGateEnabled = enabled,
        currentBuild = activeBuild,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        routeAuthorityEnabled = false,
        planningReference = self:GetPlanningReference(professionKey, mode),
        executionAuthorityEnabled = false,
        trainerAuthorityEnabled = false,
        acquisitionAuthorityEnabled = false,
        sourceReadinessState = "not-evaluated",
        sourceHandoffState = "not-evaluated",
        sourceShadowState = "not-evaluated",
        candidates = {},
        stats = {
            readinessSegments = readiness and readiness.stats and readiness.stats.evaluatedSegments or 0,
            authorityReadySegments = readiness and readiness.stats and readiness.stats.authorityReadySegments or 0,
            authorityCandidates = 0,
            dualRunGaps = 0,
            adaptiveTelemetrySteps = 0,
            adaptiveTelemetryBlocked = 0,
        },
    }

    if not enabled then
        model.state = "route-authority-feature-gate-disabled"
        model.blockedReason = "feature-gate-disabled"
        return model
    end

    local qualificationModule = JLP:GetModule("ResearchRouteSegmentQualification")
    local readinessModule = JLP:GetModule("ResearchPlannerAuthorityReadiness")
    local handoffModule = JLP:GetModule("ResearchRouteSegmentHandoff")
    local shadowModule = JLP:GetModule("ResearchShadowPlanner")
    local qualification = qualificationModule and qualificationModule:Build(professionKey, mode, options) or nil
    model.sourceQualificationState = qualification and qualification.state or "unavailable"
    model.qualifiedPlannerHandoffs = 0
    readiness = readinessModule and readinessModule:Build(professionKey, mode, options) or nil
    handoff = handoffModule and handoffModule:Build(professionKey, mode, options) or nil
    shadow = shadowModule and shadowModule:Build(professionKey, mode, options) or nil
    model.sourceReadinessState = readiness and readiness.state or "unavailable"
    model.sourceHandoffState = handoff and handoff.state or "unavailable"
    model.sourceShadowState = shadow and shadow.state or "unavailable"
    model.stats.readinessSegments = readiness and readiness.stats and readiness.stats.evaluatedSegments or 0
    model.stats.authorityReadySegments = readiness and readiness.stats and readiness.stats.authorityReadySegments or 0
    model.stats.adaptiveTelemetrySteps = shadow and shadow.stats and shadow.stats.telemetryAdaptiveSteps or 0
    model.stats.adaptiveTelemetryBlocked = shadow and shadow.stats and shadow.stats.telemetryBlockedSteps or 0

    if not qualification or not readiness or not handoff or not shadow then
        model.state = "route-authority-dependency-unavailable"
        model.blockedReason = "authority-dependency-unavailable"
        return model
    end

    for _, readyRow in ipairs(readiness.segments or {}) do
        if readyRow.authorityReady == true then
            local staged = handoff.segmentByIndex and handoff.segmentByIndex[readyRow.segmentIndex] or nil
            local shadowSegment = shadow.segmentByIndex and shadow.segmentByIndex[readyRow.segmentIndex] or nil
            local buildReady = staged and staged.buildProvenance
                and staged.buildProvenance.coherent == true
                and staged.buildProvenance.currentBuildOnly == true
                and activeBuild ~= nil
                and tonumber(staged.buildProvenance.currentBuild) == tonumber(activeBuild)
            local qualified = qualification.segmentByIndex and qualification.segmentByIndex[readyRow.segmentIndex] or nil
            local handoffReady = qualified ~= nil
                and qualified.plannerHandoffEligible == true
                and staged ~= nil and qualified.segmentID == staged.segmentID
                and qualification.runtimeCapabilitySessionStable == true
                and tonumber(qualification.currentBuild) == tonumber(activeBuild)
            if staged and shadowSegment and buildReady and handoffReady then
                model.qualifiedPlannerHandoffs = model.qualifiedPlannerHandoffs + 1
                model.candidates[#model.candidates + 1] = {
                    segmentIndex = readyRow.segmentIndex,
                    readiness = readyRow,
                    staged = staged,
                    shadow = shadowSegment,
                }
            end
        end
    end
    model.stats.authorityCandidates = #model.candidates

    if #model.candidates == 0 then
        local adaptive, segmentIndex, recipe = findBlockedAdaptiveTelemetry(shadow)
        if adaptive then
            model.state = "blocked-adaptive-telemetry-provenance"
            model.blockedReason = adaptive.blockedReason or adaptive.state
            model.adaptiveTelemetry = adaptive
            model.selectedSegment = segmentIndex
            model.blockedRecipe = recipe
            return model
        end
        model.state = "awaiting-authority-ready-segment"
        model.blockedReason = (qualification.stats and qualification.stats.qualified or 0) == 0
            and "no-live-qualified-route-segment" or "no-segment-with-full-planner-readiness"
        return model
    end
    if #model.candidates ~= 1 then
        model.state = "blocked-authority-segment-ambiguity"
        model.blockedReason = "multiple-authority-ready-segments"
        return model
    end

    local candidate = model.candidates[1]
    local staged = candidate.staged
    local dataset = buildDataset(professionKey, mode, staged, candidate.readiness, activeBuild)
    dataset.name = professionName(professionKey, handoff.liveProfession)
    local live = buildLiveSurfaces(professionKey, handoff.liveProfession, dataset)
    local shadowStep = live and live.plan and live.plan.step and findShadowStep(candidate.shadow, live.plan.step.recipe, live.plan.step.routeIndex) or nil
    local parity = compareLiveShadow(live, shadowStep)
    model.stats.dualRunGaps = #(parity.gaps or {})
    model.selectedSegment = candidate.segmentIndex
    -- The speculative Planner-compatible dataset contains authority-shaped
    -- steps for read-only parity checks. Never publish it on a blocked model.
    model.dualRunParity = parity

    local livePlanReady = live and live.plan and live.plan.status == "craft"
        and live.plan.plannerEligible == true
        and live.plan.executionEligible == false
        and live.plan.step and live.plan.step.plannerEligible == true
        and live.plan.step.executionEligible == false
    if not livePlanReady then
        model.state = "blocked-live-planner-authority-shape"
        model.blockedReason = "live-planner-authority-shape"
        return model
    end
    if not parity.ready then
        model.state = "blocked-live-shadow-parity"
        model.blockedReason = "live-shadow-parity-mismatch"
        return model
    end

    local finalQualification = qualificationModule and qualificationModule:Build(professionKey, mode, options) or nil
    local finalRow = finalQualification and finalQualification.segmentByIndex
        and finalQualification.segmentByIndex[candidate.segmentIndex] or nil
    if activeBuild == nil or currentBuild() ~= activeBuild or not featureEnabled()
        or not finalQualification or finalQualification.runtimeCapabilitySessionStable ~= true
        or not finalRow or finalRow.plannerHandoffEligible ~= true
        or finalRow.segmentID ~= staged.segmentID then
        model.state = "blocked-live-session-changed-during-parity"
        model.blockedReason = "live-session-or-authority-opt-in-changed"
        return model
    end

    model.state = "controlled-route-authority-active"
    model.dataset = dataset
    model.live = live
    model.shadowStep = shadowStep
    model.adaptiveTelemetry = shadowStep and shadowStep.adaptiveTelemetry or nil
    model.plannerEligible = true
    model.routeAuthorityEnabled = true
    model.dataset.routeAuthorityEnabled = true
    model.dataset.plannerEligible = true
    return model
end

function ResearchRouteAuthorityBridge:GetPlannerDataset(professionKey, mode, options)
    professionKey = tostring(professionKey or ""):upper()
    options = type(options) == "table" and options or {}
    if not self:IsSupported(professionKey) and not options.allowHarness then return nil, "unsupported-profession" end
    local model = self:Build(professionKey, mode or configuredMode(), options)
    if not model or model.routeAuthorityEnabled ~= true or model.plannerEligible ~= true then
        return nil, model and model.state or "bridge-unavailable", model
    end
    return model.dataset, model.state, model
end

function ResearchRouteAuthorityBridge:GetSummary(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode or configuredMode())
    local model = self:Build(professionKey, mode, options)
    if not model then return "Controlled route-authority bridge unavailable." end
    local lines = {
        "CONTROLLED RESEARCH ROUTE AUTHORITY / PLANNER ONLY",
        string.format("%s / %s", professionKey, mode),
        "State: " .. tostring(model.state),
        "Read-only Planner auto-promotion: " .. (model.featureGateEnabled and "enabled" or "disabled"),
        "Qualification handoff state: " .. tostring(model.sourceQualificationState or "not-evaluated"),
        "Current build: " .. tostring(model.currentBuild or "unknown"),
        "Cross-build research reference: " .. tostring(model.planningReference and model.planningReference.state or "unavailable") .. " (analysis only)",
        string.format("Authority-ready segments: %d · candidates: %d", tonumber(model.stats.authorityReadySegments) or 0, tonumber(model.stats.authorityCandidates) or 0),
    }
    if model.selectedSegment then
        lines[#lines + 1] = "Selected segment: " .. tostring(model.selectedSegment)
    end
    if model.dualRunParity then
        lines[#lines + 1] = string.format("Live/shadow parity: planner %s · requirements %s · readiness %s · actions %s",
            model.dualRunParity.planner and "pass" or "gap",
            model.dualRunParity.requirements and "pass" or "gap",
            model.dualRunParity.readiness and "pass" or "gap",
            model.dualRunParity.actions and "pass" or "gap")
        lines[#lines + 1] = "Dual-run gaps: " .. tostring(model.stats.dualRunGaps or 0)
        for index, gap in ipairs(model.dualRunParity.gaps or {}) do
            if index > 8 then
                lines[#lines + 1] = string.format("· ... %d additional gap(s)", #model.dualRunParity.gaps - 8)
                break
            end
            lines[#lines + 1] = string.format("· %s/%s · live=%s · shadow=%s", tostring(gap.surface), tostring(gap.path), tostring(gap.live), tostring(gap.shadow))
        end
    end
    if model.adaptiveTelemetry then
        lines[#lines + 1] = string.format("Adaptive telemetry: %s · static %s · production %s · shadow %s",
            tostring(model.adaptiveTelemetry.state),
            tostring(model.adaptiveTelemetry.staticRemainingCrafts),
            tostring(model.adaptiveTelemetry.productionRemainingCrafts),
            tostring(model.adaptiveTelemetry.shadowRemainingCrafts))
        lines[#lines + 1] = "Telemetry provenance: " .. (model.adaptiveTelemetry.currentBuildOnly and "current-build local" or tostring(model.adaptiveTelemetry.blockedReason or "static/no active telemetry"))
    end
    lines[#lines + 1] = "Planner route authority: " .. (model.routeAuthorityEnabled and "enabled" or "disabled")
    lines[#lines + 1] = "Execution authority: disabled"
    lines[#lines + 1] = "Trainer authority: disabled"
    lines[#lines + 1] = "Acquisition execution authority: disabled"
    lines[#lines + 1] = "Fallback to research assumptions: forbidden"
    lines[#lines + 1] = "Authority persistence: none · evidence/build changes demote on next read"
    return table.concat(lines, "\n")
end

function ResearchRouteAuthorityBridge:Validate()
    local errors, warnings = {}, {}
    if self.executionEligible ~= false or self.transferableToExecution ~= false or self.readOnly ~= true then
        errors[#errors + 1] = "controlled route-authority execution boundary invalid"
    end
    for _, name in ipairs({"ResearchPlannerAuthorityReadiness", "ResearchRouteSegmentHandoff", "ResearchShadowPlanner", "Planner", "RequirementPlan", "CraftReadiness", "ActionQueue"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "controlled route-authority dependency missing: " .. name end
    end
    return errors, warnings
end

-- Fresh authority/qualification on EVERY top-level call; only its immutable
-- candidate inputs are reused during this synchronous evaluation.
local buildAuthority=ResearchRouteAuthorityBridge.Build
function ResearchRouteAuthorityBridge:Build(professionKey,mode,options)
    local verifier=JLP:GetModule("ResearchCandidateVerifier")
    if verifier and verifier.WithEvaluation then
        return verifier:WithEvaluation(professionKey,mode or configuredMode(),function()
            return buildAuthority(self,professionKey,mode,options)
        end)
    end
    return buildAuthority(self,professionKey,mode,options)
end
JLP:RegisterModule("ResearchRouteAuthorityBridge", ResearchRouteAuthorityBridge)
