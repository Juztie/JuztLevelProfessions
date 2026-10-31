local _, JLP = ...

-- Final read-only readiness gate before any future research route segment may
-- be considered for a controlled Planner-authority bridge. This module does
-- not grant authority. It only proves that every prerequisite layer agrees on
-- the same current-build segment and that the production read contracts can
-- represent the segment without loss or side effects.
local ResearchPlannerAuthorityReadiness = {
    contract = "planner-authority-readiness-gate-v1",
    authority = "planner-authority-readiness-evaluation-only",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
    readOnly = true,
    routeAuthorityEnabled = false,
}

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function newGate(name, ready, state, detail, stats)
    return {
        name = name,
        ready = ready == true,
        state = state or (ready and "ready" or "blocked"),
        detail = detail,
        stats = stats,
    }
end

local function currentRecipeEvidence(professionKey, pendingSteps, activeBuild)
    local cache = JLP:GetModule("KnowledgeCache")
    local state = {
        total = 0,
        ready = 0,
        historical = 0,
        notKnown = 0,
        unknown = 0,
        rows = {},
    }
    for _, step in ipairs(pendingSteps or {}) do
        state.total = state.total + 1
        local knowledge = cache and cache.GetRecipeKnowledgeState and cache:GetRecipeKnowledgeState(step.recipe, professionKey) or nil
        local observedBuild = knowledge and tonumber(knowledge.observedBuild) or nil
        local currentObserved = knowledge and knowledge.currentBuildObserved == true or false
        local buildReady = activeBuild ~= nil and observedBuild ~= nil and tonumber(activeBuild) == observedBuild
        local recipeReady = knowledge and knowledge.knowledge == "known" and currentObserved and buildReady and knowledge.sessionIdentityConflict ~= true and tonumber(step.recipeID) ~= nil
        if recipeReady then
            state.ready = state.ready + 1
        elseif knowledge and knowledge.knowledge == "known" then
            state.historical = state.historical + 1
        elseif knowledge and knowledge.knowledge == "not-known" then
            state.notKnown = state.notKnown + 1
        else
            state.unknown = state.unknown + 1
        end
        state.rows[#state.rows + 1] = {
            recipe = step.recipe,
            recipeID = tonumber(step.recipeID),
            knowledge = knowledge and knowledge.knowledge or "unknown",
            observedBuild = observedBuild,
            currentBuild = activeBuild,
            currentBuildObserved = currentObserved,
            sessionIdentityConflict = knowledge and knowledge.sessionIdentityConflict == true or false,
            ready = recipeReady,
        }
    end
    state.allReady = state.total > 0 and state.ready == state.total
    return state
end

local function materialEvidence(pendingSteps, activeBuild)
    local state = {
        total = 0,
        ready = 0,
        unresolvedItems = 0,
        unresolvedSources = 0,
        insufficientSamples = 0,
        staleSources = 0,
        conflicts = 0,
        rows = {},
    }
    for _, step in ipairs(pendingSteps or {}) do
        for _, material in ipairs(step.materials or {}) do
            state.total = state.total + 1
            local acquisition = material.acquisition
            local isCrafted = material.source == "crafted" or material.source == "craft"
            local itemReady = material.itemResolved == true and tonumber(material.itemID) ~= nil
            local sourceReady = material.sourceResolved == true and material.source ~= "research-unresolved"
            local samples = tonumber(material.exactSamples) or 0
            local rateReady = tonumber(material.quantity) ~= nil and samples >= 4 and material.currentBuildCorroborated == true
            local stale = false
            local conflict = false
            if not isCrafted and acquisition then
                stale = acquisition.status == "external-material-source-stale-build"
                conflict = acquisition.conflict == true or acquisition.status == "external-material-source-conflict"
                if acquisition.currentBuild and activeBuild and tonumber(acquisition.currentBuild) ~= tonumber(activeBuild) then stale = true end
            end
            local ready = itemReady and sourceReady and rateReady and not stale and not conflict
            if ready then state.ready = state.ready + 1 end
            if not itemReady then state.unresolvedItems = state.unresolvedItems + 1 end
            if not sourceReady then state.unresolvedSources = state.unresolvedSources + 1 end
            if not rateReady then state.insufficientSamples = state.insufficientSamples + 1 end
            if stale then state.staleSources = state.staleSources + 1 end
            if conflict then state.conflicts = state.conflicts + 1 end
            state.rows[#state.rows + 1] = {
                recipe = step.recipe,
                itemID = material.itemID,
                name = material.name,
                source = material.source,
                exactSamples = samples,
                currentBuildCorroborated = material.currentBuildCorroborated == true,
                acquisitionStatus = acquisition and acquisition.status or nil,
                ready = ready,
            }
        end
    end
    state.allReady = state.total == 0 or state.ready == state.total
    return state
end

local function trainerEvidence(segment)
    local state = { total = #(segment.trainerGates or {}), ready = 0, rows = {} }
    for _, gate in ipairs(segment.trainerGates or {}) do
        local ready = gate.ready == true
        if ready then state.ready = state.ready + 1 end
        state.rows[#state.rows + 1] = {
            tier = gate.tier,
            requiredSkill = gate.requiredSkill,
            skillCapTo = gate.skillCapTo,
            minCharacterLevel = gate.minCharacterLevel,
            ready = ready,
            state = gate.state,
        }
    end
    state.allReady = state.ready == state.total
    return state
end

local function accessEvidence(segment, activeBuild)
    local state = { total = #(segment.accessRequirements or {}), ready = 0, stale = 0, conflicts = 0, rows = {} }
    for _, access in ipairs(segment.accessRequirements or {}) do
        local stale = access.currentBuild and activeBuild and tonumber(access.currentBuild) ~= tonumber(activeBuild) or false
        local conflict = tostring(access.state or ""):find("conflict", 1, true) ~= nil
        local ready = access.ready == true and not stale and not conflict
        if ready then state.ready = state.ready + 1 end
        if stale then state.stale = state.stale + 1 end
        if conflict then state.conflicts = state.conflicts + 1 end
        state.rows[#state.rows + 1] = {
            recipe = access.recipe,
            kind = access.kind,
            state = access.state,
            sourceKind = access.sourceKind,
            currentBuild = access.currentBuild,
            ready = ready,
        }
    end
    state.allReady = state.ready == state.total
    return state
end

local function dependencyEvidence(segment, activeBuild)
    local state = { total = #(segment.dependencies or {}), ready = 0, stale = 0, rows = {} }
    for _, dep in ipairs(segment.dependencies or {}) do
        local buildReady = true
        if activeBuild and dep.observedBuild then buildReady = tonumber(activeBuild) == tonumber(dep.observedBuild) end
        if activeBuild and dep.currentBuild then buildReady = buildReady and tonumber(activeBuild) == tonumber(dep.currentBuild) end
        local ready = dep.intrinsicCandidateEligible == true and buildReady
        if ready then state.ready = state.ready + 1 end
        if not buildReady then state.stale = state.stale + 1 end
        state.rows[#state.rows + 1] = {
            routeStepIndex = dep.routeStepIndex,
            recipe = dep.recipe,
            status = dep.status,
            observedBuild = dep.observedBuild,
            currentBuild = dep.currentBuild,
            ready = ready,
        }
    end
    state.allReady = state.ready == state.total
    return state
end

local function shadowParity(shadowSegment, expectedSteps)
    local state = {
        present = shadowSegment ~= nil,
        expectedSteps = tonumber(expectedSteps) or 0,
        auditedSteps = shadowSegment and #(shadowSegment.steps or {}) or 0,
        planner = true,
        requirements = true,
        readiness = true,
        actions = true,
        acquisition = true,
        recursive = true,
        individualSteps = true,
        contractGaps = 0,
        recursiveAdapterGaps = 0,
        rows = {},
    }
    if not shadowSegment then
        state.planner = false
        state.requirements = false
        state.readiness = false
        state.actions = false
        state.acquisition = false
        state.recursive = false
        state.allReady = false
        return state
    end
    for _, step in ipairs(shadowSegment.steps or {}) do
        local parity = step.parity or {}
        local recursiveReady = (tonumber(parity.recursiveAdapterGaps) or 0) == 0
        state.planner = state.planner and parity.planner == true
        state.requirements = state.requirements and parity.requirements == true
        state.readiness = state.readiness and parity.readiness == true
        state.actions = state.actions and parity.actions == true
        state.acquisition = state.acquisition and parity.acquisition == true
        state.recursive = state.recursive and recursiveReady
        state.individualSteps = state.individualSteps and step.parityReady == true
            and step.status == "shadow-planner-parity-ready"
            and #(parity.gaps or {}) == 0
            and not (step.adaptiveTelemetry and step.adaptiveTelemetry.ready == false)
        state.contractGaps = state.contractGaps + #(parity.gaps or {})
        state.recursiveAdapterGaps = state.recursiveAdapterGaps + (tonumber(parity.recursiveAdapterGaps) or 0)
        state.rows[#state.rows + 1] = {
            recipe = step.recipe,
            status = step.status,
            parityReady = step.parityReady == true,
            planner = parity.planner == true,
            requirements = parity.requirements == true,
            readiness = parity.readiness == true,
            actions = parity.actions == true,
            acquisition = parity.acquisition == true,
            recursiveAdapterGaps = tonumber(parity.recursiveAdapterGaps) or 0,
        }
    end
    local coverageReady = state.expectedSteps > 0 and state.auditedSteps == state.expectedSteps
    state.coverageReady = coverageReady
    state.allReady = shadowSegment.parityReady == true and coverageReady and state.planner and state.requirements
        and state.readiness and state.actions and state.acquisition and state.recursive
        and state.individualSteps and state.contractGaps == 0
    return state
end

-- Build-neutral research visibility must not be confused with current-build
-- native/promotion authority. Independently assess reference usefulness while
-- preserving every existing authority gate and result verbatim.
local function planningReferences(segment, professionKey)
    local cache = JLP:GetModule("KnowledgeCache")
    local materials = JLP:GetModule("MaterialAcquisitionEvidence")
    local access = JLP:GetModule("RecipeAccessEvidence")
    local yields = JLP:GetModule("RecipeOutputEvidence")
    local state = { contract="historical-planning-evidence-v1", readOnly=true,
        plannerEligible=false, executionEligible=false, transferable=false,
        total=0, usable=0, unresolved=0, conflicts=0, rows={} }
    local function observe(kind, name, value, usable, conflict, sourceBuild, currentBuild)
        state.total = state.total + 1
        if usable then state.usable = state.usable + 1 else state.unresolved = state.unresolved + 1 end
        if conflict then state.conflicts = state.conflicts + 1 end
        state.rows[#state.rows + 1] = {kind=kind, name=name,
            status=value, usable=usable == true, conflict=conflict == true,
            sourceBuild=sourceBuild, currentBuild=currentBuild,
            plannerEligible=false, executionEligible=false}
    end
    for _, step in ipairs(segment.pendingSteps or {}) do
        local knowledge = cache and cache.GetRecipeKnowledgeState
            and cache:GetRecipeKnowledgeState(step.recipe, professionKey) or nil
        -- An explicit learned recipe from history is informative; an explicit
        -- not-known/identity-conflict is not a license to recommend execution.
        local conflict = knowledge and knowledge.sessionIdentityConflict == true or false
        local known = knowledge and knowledge.knowledge == "known" and not conflict or false
        observe("recipe", step.recipe, knowledge and knowledge.knowledge or "unknown",
            known, conflict, knowledge and knowledge.observedBuild, knowledge and knowledge.currentBuild)
        for _, material in ipairs(step.materials or {}) do
            local resolved = materials and materials.Resolve
                and materials:Resolve(material.name, material.itemID) or nil
            local usable = resolved and resolved.planningUsable == true and material.itemID ~= nil
            observe("material", material.name, resolved and resolved.status or "unresolved",
                usable, resolved and resolved.conflict == true,
                resolved and resolved.referenceCapturedBuild, resolved and resolved.currentBuild)
        end
        if step.keep == true then
            local resolved = yields and yields.Resolve
                and yields:Resolve(step.recipe, step.recipeID) or nil
            observe("output-yield", step.recipe, resolved and resolved.status or "unresolved",
                resolved and resolved.planningUsable == true,
                resolved and resolved.referenceConflict == true,
                resolved and resolved.referenceCapturedBuild, resolved and resolved.currentBuild)
        end
    end
    for _, requirement in ipairs(segment.accessRequirements or {}) do
        if requirement.kind and requirement.recipe then
            local resolved = access and access.Resolve
                and access:Resolve(requirement.kind, requirement.recipe) or nil
            observe("access", requirement.recipe, resolved and resolved.status or "unresolved",
                resolved and resolved.planningUsable == true,
                resolved and resolved.conflict == true,
                resolved and resolved.referenceCapturedBuild, resolved and resolved.currentBuild)
        end
    end
    state.available = state.total > 0 and state.unresolved == 0 and state.conflicts == 0
    state.state = state.available and "historical-plan-reference-available"
        or state.usable > 0 and "historical-plan-reference-partial"
        or "historical-plan-reference-unavailable"
    return state
end

local function buildGateList(segment, shadowSegment, professionKey, activeBuild)
    local recipes = currentRecipeEvidence(professionKey, segment.pendingSteps, activeBuild)
    local materials = materialEvidence(segment.pendingSteps, activeBuild)
    local trainers = trainerEvidence(segment)
    local access = accessEvidence(segment, activeBuild)
    local dependencies = dependencyEvidence(segment, activeBuild)
    local shadow = shadowParity(shadowSegment, #(segment.pendingSteps or {}))
    local buildReady = segment.buildProvenance and segment.buildProvenance.coherent == true
        and segment.buildProvenance.currentBuildOnly == true
        and activeBuild ~= nil
        and tonumber(segment.buildProvenance.currentBuild) == tonumber(activeBuild)
    local liveReady = segment.status == "qualified-route-segment-handoff-ready"
        and segment.qualificationStatus == "qualified-live-route-segment"
        and segment.qualificationClass == "qualified"
    local plannerDataReady = segment.compatibility
        and segment.compatibility.plannerShapeReady == true
        and segment.compatibility.plannerDataComplete == true
        and (tonumber(segment.compatibility.unresolvedItemIDs) or 0) == 0
        and (tonumber(segment.compatibility.unresolvedMaterialSources) or 0) == 0
        and (tonumber(segment.compatibility.materialSourceConflicts) or 0) == 0
        and (tonumber(segment.compatibility.staleMaterialSources) or 0) == 0
        and (tonumber(segment.compatibility.missingRecipeIDs) or 0) == 0

    local gates = {
        liveQualification = newGate("live-qualification", liveReady, liveReady and "qualified-live-route-segment" or "blocked-live-qualification"),
        buildProvenance = newGate("build-provenance", buildReady, buildReady and "current-build-coherent" or "blocked-build-provenance", nil, segment.buildProvenance),
        recipes = newGate("recipe-evidence", recipes.allReady, recipes.allReady and "current-build-recipes-ready" or "blocked-recipe-evidence", nil, recipes),
        materials = newGate("material-evidence", materials.allReady, materials.allReady and "current-build-materials-ready" or "blocked-material-evidence", nil, materials),
        trainers = newGate("trainer-gates", trainers.allReady, trainers.allReady and "trainer-gates-ready" or "blocked-trainer-gate", nil, trainers),
        access = newGate("access-gates", access.allReady, access.allReady and "access-gates-ready" or "blocked-access-gate", nil, access),
        dependencies = newGate("dependency-closure", dependencies.allReady, dependencies.allReady and "dependency-closure-ready" or "blocked-dependency-closure", nil, dependencies),
        plannerData = newGate("planner-data", plannerDataReady, plannerDataReady and "planner-data-staging-ready" or "blocked-planner-data", nil, segment.compatibility),
        shadowCoverage = newGate("shadow-coverage", shadow.coverageReady == true, shadow.coverageReady and "shadow-step-coverage-ready" or "blocked-shadow-step-coverage", nil, shadow),
        plannerParity = newGate("planner-parity", shadow.planner, shadow.planner and "planner-parity-ready" or "blocked-planner-parity"),
        requirementParity = newGate("requirement-parity", shadow.requirements, shadow.requirements and "requirement-parity-ready" or "blocked-requirement-parity"),
        readinessParity = newGate("readiness-parity", shadow.readiness, shadow.readiness and "readiness-parity-ready" or "blocked-readiness-parity"),
        actionParity = newGate("action-parity", shadow.actions, shadow.actions and "action-parity-ready" or "blocked-action-parity"),
        acquisitionParity = newGate("acquisition-parity", shadow.acquisition, shadow.acquisition and "acquisition-parity-ready" or "blocked-acquisition-parity"),
        recursiveParity = newGate("recursive-parity", shadow.recursive, shadow.recursive and "recursive-parity-ready" or "blocked-recursive-parity", nil, shadow),
        shadowStepIntegrity = newGate("shadow-step-integrity", shadow.individualSteps and shadow.contractGaps == 0,
            shadow.individualSteps and shadow.contractGaps == 0 and "shadow-steps-consistent" or "blocked-shadow-step-inconsistency", nil, shadow),
    }
    local order = {
        "liveQualification", "buildProvenance", "recipes", "materials", "trainers", "access", "dependencies",
        "plannerData", "shadowCoverage", "plannerParity", "requirementParity", "readinessParity", "actionParity",
        "acquisitionParity", "recursiveParity", "shadowStepIntegrity",
    }
    local passed = 0
    for _, key in ipairs(order) do if gates[key].ready then passed = passed + 1 end end
    return gates, order, passed
end

local function firstBlockedGate(gates, order)
    for _, key in ipairs(order or {}) do
        local gate = gates and gates[key]
        if gate and not gate.ready then return gate end
    end
    return nil
end

function ResearchPlannerAuthorityReadiness:Build(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}

    local handoffModule = JLP:GetModule("ResearchRouteSegmentHandoff")
    local shadowModule = JLP:GetModule("ResearchShadowPlanner")
    local handoff = handoffModule and handoffModule:Build(professionKey, mode, options) or nil
    local shadow = shadowModule and shadowModule:Build(professionKey, mode, options) or nil
    if not handoff or not shadow then return nil end

    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        routeAuthorityEnabled = false,
        currentBuild = handoff.currentBuild,
        liveProfession = handoff.liveProfession,
        sourceHandoffState = handoff.state,
        sourceShadowState = shadow.state,
        segments = {},
        segmentByIndex = {},
        stats = {
            handoffSegments = handoff.stats and handoff.stats.stagedSegments or 0,
            shadowSegments = shadow.stats and shadow.stats.shadowSegments or 0,
            evaluatedSegments = 0,
            authorityReadySegments = 0,
            blockedSegments = 0,
            totalGates = 0,
            passedGates = 0,
            blockedGates = 0,
            planningReferenceAvailableSegments = 0,
            planningReferencePartialSegments = 0,
        },
    }

    for _, segment in ipairs(handoff.segments or {}) do
        local shadowSegment = shadow.segmentByIndex and shadow.segmentByIndex[segment.segmentIndex] or nil
        local gates, gateOrder, passed = buildGateList(segment, shadowSegment, professionKey, model.currentBuild)
        local total = #gateOrder
        local planning = planningReferences(segment, professionKey)
        local blocked = firstBlockedGate(gates, gateOrder)
        local ready = blocked == nil and total > 0 and passed == total
        local row = {
            segmentIndex = segment.segmentIndex,
            segmentID = segment.segmentID,
            startSkill = segment.startSkill,
            endSkill = segment.endSkill,
            currentSkill = segment.currentSkill,
            currentCap = segment.currentCap,
            pendingSteps = #(segment.pendingSteps or {}),
            status = ready and "planner-authority-readiness-ready" or "planner-authority-readiness-blocked",
            blockedGate = blocked and blocked.name or nil,
            blockedState = blocked and blocked.state or nil,
            authorityReady = ready,
            -- Build-neutral reference availability does not change authorityReady.
            planningReferenceAvailable = planning.available,
            planningEvidence = planning,
            authorityReadinessOnly = true,
            routeAuthorityEnabled = false,
            plannerEligible = false,
            executionEligible = false,
            transferable = false,
            readOnly = true,
            gates = gates,
            gateOrder = gateOrder,
            stats = {
                totalGates = total,
                passedGates = passed,
                blockedGates = total - passed,
            },
            source = {
                handoffStatus = segment.status,
                handoffCompatibility = shallowCopy(segment.compatibility),
                shadowStatus = shadowSegment and shadowSegment.status or "missing-shadow-segment",
            },
        }
        model.segments[#model.segments + 1] = row
        model.segmentByIndex[row.segmentIndex] = row
        model.stats.evaluatedSegments = model.stats.evaluatedSegments + 1
        model.stats.totalGates = model.stats.totalGates + total
        model.stats.passedGates = model.stats.passedGates + passed
        model.stats.blockedGates = model.stats.blockedGates + (total - passed)
        if planning.available then model.stats.planningReferenceAvailableSegments = model.stats.planningReferenceAvailableSegments + 1
        elseif planning.usable > 0 then model.stats.planningReferencePartialSegments = model.stats.planningReferencePartialSegments + 1 end
        if ready then model.stats.authorityReadySegments = model.stats.authorityReadySegments + 1
        else model.stats.blockedSegments = model.stats.blockedSegments + 1 end
    end

    if model.stats.evaluatedSegments == 0 then
        model.state = "awaiting-qualified-shadow-parity-segment"
    elseif model.stats.authorityReadySegments == model.stats.evaluatedSegments then
        model.state = "planner-authority-readiness-ready"
    elseif model.stats.authorityReadySegments > 0 then
        model.state = "planner-authority-readiness-partial"
    else
        model.state = "planner-authority-readiness-blocked"
    end
    return model
end

function ResearchPlannerAuthorityReadiness:GetSegment(professionKey, mode, selector, options)
    local model = self:Build(professionKey, mode, options)
    if not model then return nil, nil end
    local index = tonumber(selector)
    if index then return model.segmentByIndex[index], model end
    local wanted = tostring(selector or ""):lower()
    if wanted ~= "" then
        local handoff = JLP:GetModule("ResearchRouteSegmentHandoff")
        local staged = handoff and handoff:GetSegment(professionKey, mode, selector, options) or nil
        if staged then return model.segmentByIndex[staged.segmentIndex], model end
    end
    return nil, model
end

function ResearchPlannerAuthorityReadiness:GetSummary(professionKey, mode, selector, options)
    local selected, model = self:GetSegment(professionKey, mode, selector, options)
    model = model or self:Build(professionKey, mode, options)
    if not model then return "Planner authority-readiness gate unavailable." end
    local lines = {
        "PLANNER AUTHORITY READINESS / READ-ONLY GATE",
        string.format("%s / %s", tostring(model.professionKey), tostring(model.mode)),
        "State: " .. tostring(model.state),
        string.format("Segments: %d ready / %d evaluated", tonumber(model.stats.authorityReadySegments) or 0, tonumber(model.stats.evaluatedSegments) or 0),
        string.format("Gates: %d pass / %d total", tonumber(model.stats.passedGates) or 0, tonumber(model.stats.totalGates) or 0),
        "Current build: " .. tostring(model.currentBuild or "unknown"),
        string.format("Historical planning references: %d available / %d partial (read-only, not authority)",
            tonumber(model.stats.planningReferenceAvailableSegments) or 0,
            tonumber(model.stats.planningReferencePartialSegments) or 0),
    }
    if selected then
        lines[#lines + 1] = string.format("Selected segment %d: %s", tonumber(selected.segmentIndex) or 0, tostring(selected.status))
        lines[#lines + 1] = string.format("Skill: %s-%s · live %s/%s", tostring(selected.startSkill or "?"), tostring(selected.endSkill or "?"), tostring(selected.currentSkill or "?"), tostring(selected.currentCap or "?"))
        lines[#lines + 1] = string.format("Segment gates: %d/%d", tonumber(selected.stats.passedGates) or 0, tonumber(selected.stats.totalGates) or 0)
        for _, key in ipairs(selected.gateOrder or {}) do
            local gate = selected.gates[key]
            lines[#lines + 1] = string.format("· %s: %s", tostring(gate.name), gate.ready and "pass" or tostring(gate.state or "blocked"))
        end
    end
    lines[#lines + 1] = "Authority-ready means evidence/parity-ready only."
    lines[#lines + 1] = "Planner route authority: disabled in readiness gate"
    lines[#lines + 1] = "Execution authority: disabled"
    lines[#lines + 1] = "Route-authority bridge: implemented separately and feature-gated"
    return table.concat(lines, "\n")
end

function ResearchPlannerAuthorityReadiness:Validate()
    local errors, warnings = {}, {}
    if self.plannerEligible ~= false or self.executionEligible ~= false or self.transferable ~= false or self.readOnly ~= true or self.routeAuthorityEnabled ~= false then
        errors[#errors + 1] = "authority-readiness gate escaped read-only authority boundary"
    end
    local requiredModules = {
        "ResearchRouteSegmentHandoff", "ResearchShadowPlanner", "KnowledgeCache",
    }
    for _, name in ipairs(requiredModules) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "authority-readiness dependency missing: " .. name end
    end
    return errors, warnings
end

JLP:RegisterModule("ResearchPlannerAuthorityReadiness", ResearchPlannerAuthorityReadiness)
