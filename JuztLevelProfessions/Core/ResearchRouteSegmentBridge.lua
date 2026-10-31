local _, JLP = ...

-- Groups individually closure-ready research crafts into small, atomic route
-- segments. A segment verifies contiguous skill coverage, entry trainer gates,
-- acquisition/dependency closure and current-build recipe provenance as one
-- staging object. It deliberately grants no Planner or execution authority.
local ResearchRouteSegmentBridge = {
    contract = "provisional-route-segment-bridge-v1",
    authority = "route-segment-staging-only",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
}

local function currentBuild()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    local liveBuild = buildInfo and buildInfo:GetBuildNumber() or nil
    return liveBuild, liveBuild and "live-client" or "unknown"
end

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function copyList(list)
    local out = {}
    for _, value in ipairs(list or {}) do out[#out + 1] = value end
    return out
end

local function trainerOptions(professionKey, tier)
    local resolver = JLP:GetModule("SourceResolver")
    if not resolver or not resolver.GetTrainerOptions then return {} end
    local horde = resolver:GetTrainerOptions(professionKey, tier, "Horde")
    if type(horde) == "table" and horde[1] then return horde end
    local neutral = resolver:GetTrainerOptions(professionKey, tier, "Neutral")
    if type(neutral) == "table" and neutral[1] then return neutral end
    local alliance = resolver:GetTrainerOptions(professionKey, tier, "Alliance")
    return type(alliance) == "table" and alliance or {}
end

local function evaluateTrainerGate(professionKey, candidate, priorSkill, nextSkill)
    local resolver = JLP:GetModule("SourceResolver")
    local requirement = resolver and resolver.GetRankRequirement and resolver:GetRankRequirement(professionKey, candidate and candidate.tier) or nil
    local options = trainerOptions(professionKey, candidate and candidate.tier)
    local range = candidate and candidate.skillRange or {}
    local capMatches = requirement and tonumber(requirement.skillCap) == tonumber(range.skillCapTo)
    local levelMatches = requirement and tonumber(requirement.minCharacterLevel or 0) == tonumber(range.minCharacterLevel or 0)
    local requiredSkill = requirement and tonumber(requirement.requiredSkill) or nil
    local prior = tonumber(priorSkill)
    local nextValue = tonumber(nextSkill)
    local routePositionSkill = prior
    if nextValue ~= nil and (routePositionSkill == nil or nextValue > routePositionSkill) then routePositionSkill = nextValue end
    local positionReady = requiredSkill ~= nil and routePositionSkill ~= nil and requiredSkill <= routePositionSkill
    local sourceReady = type(options) == "table" and options[1] ~= nil
    local provenanceReady = candidate and candidate.provenance and candidate.provenance.valid == true
    local rangeReady = candidate and candidate.skillRange and candidate.skillRange.valid == true
    local ready = provenanceReady and rangeReady and capMatches and levelMatches and positionReady and sourceReady

    local state
    if not provenanceReady then state = "blocked-trainer-gate-provenance"
    elseif not rangeReady then state = "blocked-trainer-gate-range"
    elseif not requirement then state = "awaiting-trainer-rank-requirement"
    elseif not capMatches or not levelMatches then state = "blocked-trainer-gate-requirement-mismatch"
    elseif not positionReady then state = "blocked-trainer-gate-route-position"
    elseif not sourceReady then state = "awaiting-trainer-source-evidence"
    else state = "trainer-gate-reference-ready" end

    local sourceNames = {}
    for _, option in ipairs(options or {}) do
        if option and option.name then sourceNames[#sourceNames + 1] = tostring(option.name) end
    end
    return {
        routeStepIndex = candidate and candidate.routeStepIndex,
        tier = candidate and candidate.tier,
        state = state,
        ready = ready and true or false,
        requiredSkill = requiredSkill,
        skillCapFrom = tonumber(range.skillCapFrom),
        skillCapTo = tonumber(range.skillCapTo),
        minCharacterLevel = tonumber(range.minCharacterLevel),
        requirementEvidence = requirement and requirement.evidence or nil,
        trainerSourceCount = #sourceNames,
        trainerSources = sourceNames,
        sourceAuthority = requirement and requirement.evidence or nil,
        currentBuildVerified = false,
    }
end

local function closureBuildState(closureRow, activeBuild)
    if not closureRow or closureRow.closureCandidateEligible ~= true then
        return false, "closure-not-ready"
    end
    if not activeBuild then return false, "current-build-unavailable" end
    local target = closureRow.target or {}
    local observation = target.recipeObservation or {}
    if observation.currentBuildObserved ~= true then return false, "target-current-build-not-observed" end
    if activeBuild and tonumber(observation.observedBuild) ~= tonumber(activeBuild) then
        return false, "target-build-mismatch"
    end
    for _, dependency in ipairs(closureRow.dependencySteps or {}) do
        if dependency.intrinsicCandidateEligible ~= true then return false, "upstream-not-ready" end
        if activeBuild and tonumber(dependency.observedBuild) ~= tonumber(activeBuild) then
            return false, "upstream-build-mismatch"
        end
    end
    return true, "current-build-closure-ready"
end

local function aggregateStepEvidence(segment, closureRow)
    local target = closureRow.target or {}
    local access = target.accessSource or {}
    if access.required then
        segment.accessRequirements[#segment.accessRequirements + 1] = {
            routeStepIndex = closureRow.routeStepIndex,
            recipe = closureRow.recipe,
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

    local seen = segment._dependencySeen
    for _, dependency in ipairs(closureRow.dependencySteps or {}) do
        local index = tonumber(dependency.routeStepIndex)
        if index and not seen[index] then
            seen[index] = true
            segment.dependencies[#segment.dependencies + 1] = {
                routeStepIndex = index,
                recipe = dependency.recipe,
                status = dependency.status,
                observedBuild = dependency.observedBuild,
                currentBuild = dependency.currentBuild,
                intrinsicCandidateEligible = dependency.intrinsicCandidateEligible == true,
            }
        end
    end
end

local function finalizeSegment(segment, activeBuild, buildSource)
    if not segment then return nil end
    segment._dependencySeen = nil
    segment.craftStepCount = #segment.steps
    segment.trainerGateCount = #segment.trainerGates
    segment.accessRequirementCount = #segment.accessRequirements
    segment.dependencyStepCount = #segment.dependencies
    segment.buildProvenance = {
        currentBuild = activeBuild,
        source = buildSource,
        coherent = segment.buildCoherent == true,
        currentBuildOnly = true,
    }

    local trainerReady = true
    for _, gate in ipairs(segment.trainerGates) do
        if not gate.ready then trainerReady = false break end
    end
    local accessReady = true
    for _, access in ipairs(segment.accessRequirements) do
        if not access.ready then accessReady = false break end
        if activeBuild and access.currentBuild and tonumber(access.currentBuild) ~= tonumber(activeBuild) then
            accessReady = false
            break
        end
    end
    local dependencyReady = true
    for _, dependency in ipairs(segment.dependencies) do
        if not dependency.intrinsicCandidateEligible then dependencyReady = false break end
    end

    segment.trainerGatesReady = trainerReady
    segment.accessRequirementsReady = accessReady
    segment.dependenciesReady = dependencyReady
    segment.segmentCandidateEligible = segment.craftStepCount > 0
        and segment.skillContinuity == true
        and segment.buildCoherent == true
        and trainerReady
        and accessReady
        and dependencyReady

    if not segment.skillContinuity then segment.status = "blocked-segment-skill-discontinuity"
    elseif not segment.buildCoherent then segment.status = "blocked-segment-build-provenance"
    elseif not trainerReady then segment.status = "blocked-segment-trainer-gate"
    elseif not accessReady then segment.status = "blocked-segment-access-source"
    elseif not dependencyReady then segment.status = "blocked-segment-dependency-closure"
    elseif segment.segmentCandidateEligible then segment.status = "provisional-route-segment"
    else segment.status = "segment-not-ready" end

    segment.plannerEligible = false
    segment.executionEligible = false
    segment.transferable = false
    return segment
end

local function newSegment(professionKey, mode, index, craftRow, closureRow, pendingGates, activeBuild)
    local skill = craftRow.skillRange or {}
    local segment = {
        segmentIndex = index,
        segmentID = string.format("%s:%s:%d", professionKey, mode, index),
        professionKey = professionKey,
        mode = mode,
        authority = ResearchRouteSegmentBridge.authority,
        steps = {},
        trainerGates = copyList(pendingGates),
        accessRequirements = {},
        dependencies = {},
        _dependencySeen = {},
        startRouteStepIndex = craftRow.routeStepIndex,
        endRouteStepIndex = craftRow.routeStepIndex,
        startSkill = tonumber(skill.skillMin),
        endSkill = tonumber(skill.skillTarget),
        skillContinuity = true,
        buildCoherent = activeBuild ~= nil,
    }
    segment.steps[#segment.steps + 1] = {
        routeStepIndex = craftRow.routeStepIndex,
        recipe = craftRow.recipe,
        skillMin = tonumber(skill.skillMin),
        skillTarget = tonumber(skill.skillTarget),
        closureStatus = closureRow.status,
        observedBuild = closureRow.target and closureRow.target.recipeObservation and closureRow.target.recipeObservation.observedBuild or nil,
        currentBuild = closureRow.target and closureRow.target.recipeObservation and closureRow.target.recipeObservation.currentBuild or nil,
    }
    local observedBuild = segment.steps[1].observedBuild
    if activeBuild and tonumber(observedBuild) ~= tonumber(activeBuild) then segment.buildCoherent = false end
    aggregateStepEvidence(segment, closureRow)
    return segment
end

function ResearchRouteSegmentBridge:Build(professionKey, mode)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    local research = JLP:GetModule("ProfessionResearch")
    local verifier = JLP:GetModule("ResearchCandidateVerifier")
    local closure = JLP:GetModule("ResearchPromotionClosure")
    local route = research and research:Get(professionKey, mode)
    local candidates = verifier and verifier:Build(professionKey, mode)
    local closureModel = closure and closure:Build(professionKey, mode)
    if not route or not candidates or not closureModel then return nil end

    local activeBuild, buildSource = currentBuild()
    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        currentBuild = activeBuild,
        currentBuildSource = buildSource,
        segments = {},
        segmentByIndex = {},
        stats = {
            routeSteps = #(route.steps or {}),
            craftSteps = 0,
            closureReadyCraftSteps = 0,
            buildReadyCraftSteps = 0,
            segments = 0,
            provisionalSegments = 0,
            blockedTrainerSegments = 0,
            blockedBuildSegments = 0,
            blockedSkillSegments = 0,
            trainerGates = 0,
            accessRequirements = 0,
            dependencySteps = 0,
        },
    }

    local current = nil
    local activeTrainerGate = nil
    local priorRouteSkill = nil

    local function closeCurrent()
        if not current then return end
        finalizeSegment(current, activeBuild, buildSource)
        model.segments[#model.segments + 1] = current
        model.segmentByIndex[current.segmentIndex] = current
        model.stats.segments = model.stats.segments + 1
        model.stats.trainerGates = model.stats.trainerGates + current.trainerGateCount
        model.stats.accessRequirements = model.stats.accessRequirements + current.accessRequirementCount
        model.stats.dependencySteps = model.stats.dependencySteps + current.dependencyStepCount
        if current.segmentCandidateEligible then model.stats.provisionalSegments = model.stats.provisionalSegments + 1 end
        if current.status == "blocked-segment-trainer-gate" then model.stats.blockedTrainerSegments = model.stats.blockedTrainerSegments + 1 end
        if current.status == "blocked-segment-build-provenance" then model.stats.blockedBuildSegments = model.stats.blockedBuildSegments + 1 end
        if current.status == "blocked-segment-skill-discontinuity" then model.stats.blockedSkillSegments = model.stats.blockedSkillSegments + 1 end
        current = nil
    end

    for stepIndex, rawStep in ipairs(route.steps or {}) do
        local candidate = candidates.stepByRouteIndex[stepIndex]
        if rawStep.kind == "train" then
            closeCurrent()
            activeTrainerGate = evaluateTrainerGate(professionKey, candidate, priorRouteSkill, nil)
        elseif rawStep.kind == "craft" then
            model.stats.craftSteps = model.stats.craftSteps + 1
            local closureRow = closureModel.stepByRouteIndex[stepIndex]
            local closureReady = closureRow and closureRow.closureCandidateEligible == true
            if closureReady then model.stats.closureReadyCraftSteps = model.stats.closureReadyCraftSteps + 1 end
            local buildReady = false
            if closureReady then buildReady = select(1, closureBuildState(closureRow, activeBuild)) end
            if buildReady then model.stats.buildReadyCraftSteps = model.stats.buildReadyCraftSteps + 1 end

            if not closureReady or not buildReady or not candidate then
                closeCurrent()
            else
                local skill = candidate.skillRange or {}
                if not current then
                    local evaluatedGates = {}
                    local gate = activeTrainerGate
                    if gate then
                        -- Re-evaluate route-position eligibility against the first
                        -- craft after the gate when no prior skill was available.
                        if not gate.ready and gate.state == "blocked-trainer-gate-route-position" then
                            gate = evaluateTrainerGate(professionKey, candidates.stepByRouteIndex[gate.routeStepIndex], priorRouteSkill, skill.skillMin)
                            activeTrainerGate = gate
                        end
                        evaluatedGates[1] = gate
                    end
                    current = newSegment(professionKey, mode, #model.segments + 1, candidate, closureRow, evaluatedGates, activeBuild)
                else
                    local skillMin = tonumber(skill.skillMin)
                    local skillTarget = tonumber(skill.skillTarget)
                    if not skillMin or not skillTarget or skillTarget <= skillMin or not current.endSkill or skillMin > current.endSkill then
                        closeCurrent()
                        current = newSegment(professionKey, mode, #model.segments + 1, candidate, closureRow, {}, activeBuild)
                        if skillMin and priorRouteSkill and skillMin > priorRouteSkill then current.skillContinuity = false end
                    else
                        current.endRouteStepIndex = candidate.routeStepIndex
                        current.endSkill = math.max(tonumber(current.endSkill) or 0, skillTarget)
                        local observedBuild = closureRow.target and closureRow.target.recipeObservation and closureRow.target.recipeObservation.observedBuild or nil
                        if activeBuild and tonumber(observedBuild) ~= tonumber(activeBuild) then current.buildCoherent = false end
                        current.steps[#current.steps + 1] = {
                            routeStepIndex = candidate.routeStepIndex,
                            recipe = candidate.recipe,
                            skillMin = skillMin,
                            skillTarget = skillTarget,
                            closureStatus = closureRow.status,
                            observedBuild = observedBuild,
                            currentBuild = closureRow.target and closureRow.target.recipeObservation and closureRow.target.recipeObservation.currentBuild or nil,
                        }
                        aggregateStepEvidence(current, closureRow)
                    end
                end
            end
            priorRouteSkill = tonumber(rawStep.skillTarget) or priorRouteSkill
        end
    end
    closeCurrent()

    model.state = model.stats.provisionalSegments > 0 and "provisional-route-segments-available" or "learning-route-segment-evidence"
    return model
end

function ResearchRouteSegmentBridge:GetSegment(professionKey, mode, selector)
    local model = self:Build(professionKey, mode)
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

function ResearchRouteSegmentBridge:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then return {"profession research unavailable"}, warnings end
    for professionKey, modes in pairs(root.professions or {}) do
        if professionKey ~= "HARNESS" and professionKey ~= "HARNESSCLOSURE" and professionKey ~= "HARNESSSEGMENT" then
            for _, mode in ipairs({"normal", "aggressive"}) do
                if modes[mode] then
                    local model = self:Build(professionKey, mode)
                    if not model then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": route segment bridge unavailable"
                    else
                        for _, segment in ipairs(model.segments or {}) do
                            if segment.plannerEligible ~= false or segment.executionEligible ~= false or segment.transferable ~= false then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": segment escaped staging authority"
                            end
                            if segment.segmentCandidateEligible then
                                if not segment.skillContinuity or not segment.buildCoherent or not segment.trainerGatesReady or not segment.accessRequirementsReady or not segment.dependenciesReady then
                                    errors[#errors + 1] = professionKey .. "/" .. mode .. ": provisional segment retained an atomic gate failure"
                                end
                                if tonumber(segment.endSkill) <= tonumber(segment.startSkill) then
                                    errors[#errors + 1] = professionKey .. "/" .. mode .. ": provisional segment has invalid skill bounds"
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
    if not segment then return "Provisional route segment unavailable." end
    local lines = {
        string.format("Provisional route segment %d: %s / %s", tonumber(segment.segmentIndex) or 0, tostring(segment.professionKey), tostring(segment.mode)),
        "Status: " .. tostring(segment.status),
        string.format("Skill: %d-%d · route steps %d-%d · crafts %d", tonumber(segment.startSkill) or 0, tonumber(segment.endSkill) or 0, tonumber(segment.startRouteStepIndex) or 0, tonumber(segment.endRouteStepIndex) or 0, tonumber(segment.craftStepCount) or 0),
        string.format("Atomic gates: trainer %s · access %s · dependencies %s · build %s", tostring(segment.trainerGatesReady == true), tostring(segment.accessRequirementsReady == true), tostring(segment.dependenciesReady == true), tostring(segment.buildCoherent == true)),
        string.format("Build provenance: %s via %s", tostring(segment.buildProvenance and segment.buildProvenance.currentBuild or "unknown"), tostring(segment.buildProvenance and segment.buildProvenance.source or "unknown")),
        "Segment candidate: " .. tostring(segment.segmentCandidateEligible == true),
        "Planner authority: disabled",
    }
    for _, gate in ipairs(segment.trainerGates or {}) do
        lines[#lines + 1] = string.format("· trainer #%d %s · %s · req skill %s / L%s", tonumber(gate.routeStepIndex) or 0, tostring(gate.tier or "unknown"), tostring(gate.state), tostring(gate.requiredSkill or "?"), tostring(gate.minCharacterLevel or "?"))
    end
    for _, step in ipairs(segment.steps or {}) do
        lines[#lines + 1] = string.format("· craft #%d %s · %d-%d · %s", tonumber(step.routeStepIndex) or 0, tostring(step.recipe or "unknown"), tonumber(step.skillMin) or 0, tonumber(step.skillTarget) or 0, tostring(step.closureStatus))
    end
    return table.concat(lines, "\n")
end

function ResearchRouteSegmentBridge:GetSummary(professionKey, mode, selector)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    if selector and tostring(selector) ~= "" then
        return formatSegment(self:GetSegment(professionKey, mode, selector))
    end
    local model = self:Build(professionKey, mode)
    if not model then return "Provisional route segment bridge unavailable." end
    local s = model.stats
    local lines = {
        string.format("Provisional route segments: %s / %s", professionKey, mode),
        string.format("State: %s · atomic staging bridge · Planner authority disabled", tostring(model.state)),
        string.format("Build: %s via %s", tostring(model.currentBuild or "unknown"), tostring(model.currentBuildSource or "unknown")),
        string.format("Craft steps: %d · closure-ready %d · current-build ready %d", tonumber(s.craftSteps) or 0, tonumber(s.closureReadyCraftSteps) or 0, tonumber(s.buildReadyCraftSteps) or 0),
        string.format("Segments: %d · provisional %d · trainer-blocked %d · build-blocked %d · skill-blocked %d", tonumber(s.segments) or 0, tonumber(s.provisionalSegments) or 0, tonumber(s.blockedTrainerSegments) or 0, tonumber(s.blockedBuildSegments) or 0, tonumber(s.blockedSkillSegments) or 0),
        string.format("Atomic contents: trainer gates %d · access gates %d · unique upstream dependencies %d", tonumber(s.trainerGates) or 0, tonumber(s.accessRequirements) or 0, tonumber(s.dependencySteps) or 0),
    }
    local shown = 0
    for _, segment in ipairs(model.segments or {}) do
        lines[#lines + 1] = string.format("· segment %d · skill %d-%d · %d crafts · %s", tonumber(segment.segmentIndex) or 0, tonumber(segment.startSkill) or 0, tonumber(segment.endSkill) or 0, tonumber(segment.craftStepCount) or 0, tostring(segment.status))
        shown = shown + 1
        if shown >= 8 then break end
    end
    lines[#lines + 1] = "Segments remain parallel validation artifacts only; they are never inserted into the live Planner, shopping plan or execution queue."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ResearchRouteSegmentBridge", ResearchRouteSegmentBridge)
