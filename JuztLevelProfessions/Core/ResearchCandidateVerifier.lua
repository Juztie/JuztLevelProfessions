local _, JLP = ...

-- Evaluates each user-research route step independently. The result is a
-- verification/candidate model only: it can identify structurally strong steps,
-- disconnected steps, current-character access state and unresolved evidence,
-- but it never promotes research content into the audited Planner by itself.
local ResearchCandidateVerifier = {
    contract = "per-step-research-candidate-verification-v1",
    authority = "research-reference-only",
    plannerEligible = false,
    transferable = false,
}

-- One synchronous route-authority evaluation owns one read-only candidate
-- snapshot. Never retain current-character knowledge across top-level calls.
-- Policy/qualification/native checks are deliberately NOT memoized.
local evaluation
local function identity()
    local info=JLP:GetModule("ClientBuildInfo")
    local build=info and info.GetBuildNumber and info:GetBuildNumber()
    local guid
    if type(UnitGUID)=="function" then
        local ok,value=pcall(UnitGUID,"player")
        if ok and type(value)=="string" then guid=value end
    end
    return tostring(build or "UNKNOWN").."|"..tostring(guid or "UNKNOWN")
end
local function pack(...) return {n=select("#",...),...} end
local unpackValues=unpack or table.unpack
local function errorStack(message)
    if type(debugstack)=="function" then return tostring(message).."\n"..debugstack(2) end
    if type(debug)=="table" and type(debug.traceback)=="function" then return debug.traceback(tostring(message),2) end
    return message
end
function ResearchCandidateVerifier:WithEvaluation(professionKey,mode,evaluate)
    local key=tostring(professionKey or "ENGINEERING"):upper()
    mode=mode=="aggressive" and "aggressive" or "normal"
    local session=identity()
    if evaluation and evaluation.key==key and evaluation.mode==mode and evaluation.session==session then
        return evaluate()
    end
    local previous=evaluation
    evaluation={key=key,mode=mode,session=session}
    -- Graph/supplement have older source caches. Give this pass fresh private
    -- maps, sharing them only inside this evaluation, then restore the caller.
    local graph=JLP:GetModule("ProfessionDependencyGraph")
    local supplement=JLP:GetModule("ResearchSupplementPlanner")
    local graphCache=graph and graph.cache
    local supplementCache=supplement and supplement.cache
    if graph then graph.cache={} end
    if supplement then supplement.cache={} end
    local result=pack(xpcall(evaluate,errorStack))
    if graph then graph.cache=graphCache end
    if supplement then supplement.cache=supplementCache end
    evaluation=previous
    if not result[1] then error(result[2],0) end
    return unpackValues(result,2,result.n)
end

local VALID_ACCESS_KINDS = {
    recipe = true,
    formula = true,
    pattern = true,
    schematic = true,
}

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function nearInteger(value)
    value = tonumber(value)
    if not value then return nil, false end
    local rounded = math.floor(value + 0.5)
    if math.abs(value - rounded) <= 0.000001 then return rounded, true end
    return value, false
end

local function gapBeforeStep(graph, step)
    local skillMin = tonumber(step and step.skillMin)
    if not skillMin then return nil end
    for _, gap in ipairs(graph and graph.sourceGaps or {}) do
        if tonumber(gap.toSkill) == skillMin then return gap end
    end
    return nil
end

local function demandMap(rows)
    local map = {}
    for _, row in ipairs(rows or {}) do
        for _, demand in ipairs(row.demands or {}) do
            local index = tonumber(demand.consumerStepIndex)
            if index then
                map[index] = map[index] or {}
                map[index][#map[index] + 1] = {
                    name = row.name,
                    quantity = tonumber(demand.quantity) or tonumber(row.quantity) or 0,
                    reason = row.reason,
                    evidence = demand.evidence or row.evidence,
                }
            end
        end
    end
    return map
end

local function craftNodeByStep(graph)
    local map = {}
    for _, node in ipairs(graph and graph.craftNodes or {}) do
        if tonumber(node.stepIndex) then map[tonumber(node.stepIndex)] = node end
    end
    return map
end

local function accessState(step, professionKey)
    if not step.sourceRequirement then
        return {
            required = false,
            recognized = true,
            kind = nil,
            name = nil,
            knowledge = "not-required",
            state = "not-required",
            currentCharacterReady = true,
        }
    end

    local kind = tostring(step.sourceRequirement.kind or ""):lower()
    local knowledge = "unknown"
    local cache = JLP:GetModule("KnowledgeCache")
    if cache and cache.GetRecipeKnowledge and step.recipe then
        knowledge = cache:GetRecipeKnowledge(step.recipe, professionKey)
    end
    local state
    if not VALID_ACCESS_KINDS[kind] then
        state = "unrecognized-access-kind"
    elseif knowledge == "known" then
        state = "known-current-character"
    elseif knowledge == "not-known" then
        state = "required-not-known"
    else
        state = "required-availability-unverified"
    end
    return {
        required = true,
        recognized = VALID_ACCESS_KINDS[kind] and true or false,
        kind = kind,
        name = step.sourceRequirement.name,
        evidence = step.sourceRequirement.evidence or step.evidence,
        knowledge = knowledge,
        state = state,
        currentCharacterReady = knowledge == "known",
    }
end

local function reagentState(step)
    local expectedCrafts = math.max(0, tonumber(step.expectedCrafts) or 0)
    local rows = {}
    local resolved = expectedCrafts > 0
    local reason = expectedCrafts > 0 and nil or "zero-expected-crafts"
    for _, requirement in ipairs(step.requirements or {}) do
        local total = math.max(0, tonumber(requirement.quantity) or 0)
        local ratio = expectedCrafts > 0 and (total / expectedCrafts) or nil
        local perCraft, exact = nearInteger(ratio)
        if not exact then
            resolved = false
            reason = reason or "non-integral-research-reagent-ratio"
        end
        rows[#rows + 1] = {
            name = tostring(requirement.name or ""),
            routeQuantity = total,
            perCraft = perCraft,
            exact = exact,
            evidence = requirement.evidence or step.evidence,
        }
    end
    return {
        resolved = resolved,
        reason = reason,
        basis = "research-route-per-craft-ratio",
        reagents = rows,
    }
end

local function yieldState(step, node)
    if not step.keep then
        return {
            required = false,
            resolved = true,
            state = "not-required-for-non-keep-step",
            outputPerCraft = nil,
            source = nil,
        }
    end
    local output = node and node.outputYield or nil
    local resolved = output and output.dependencyQuantityEligible == true and tonumber(output.outputQuantity) ~= nil
    return {
        required = true,
        resolved = resolved and true or false,
        state = output and output.status or "yield-unresolved",
        outputPerCraft = resolved and tonumber(output.outputQuantity) or nil,
        source = output and output.source or "unknown",
        confidence = output and output.confidence or "unknown",
        liveVerified = output and output.liveVerified == true or false,
        externalVerified = output and output.externalVerified == true or false,
    }
end

local function statusFor(row)
    if not row.provenance.valid then return "blocked-provenance" end
    if not row.skillRange.valid then return "blocked-skill-range" end
    if row.kind == "train" then
        return row.routeContinuity.connected and "trainer-gate-reference" or "trainer-gate-after-source-gap"
    end
    if not row.reagentRatio.resolved then return "blocked-reagent-ratio" end
    if not row.outputYield.resolved then return "blocked-output-yield" end
    if row.access.required and not row.access.recognized then return "blocked-access-kind" end
    if row.dependencies.unresolved then return "blocked-dependency-evidence" end
    if not row.routeContinuity.connected then return "candidate-isolated-by-source-gap" end
    if row.access.required and not row.access.currentCharacterReady then return "candidate-access-gated" end
    if row.dependencies.supplemental then return "candidate-verified-with-supplemental-analysis" end
    return "candidate-verified-analysis-only"
end

local function buildCandidate(self,professionKey, mode)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"

    local research = JLP:GetModule("ProfessionResearch")
    local graphModule = JLP:GetModule("ProfessionDependencyGraph")
    local supplementModule = JLP:GetModule("ResearchSupplementPlanner")
    local route = research and research:Get(professionKey, mode)
    local graph = graphModule and graphModule:Build(professionKey, mode)
    local supplement = supplementModule and supplementModule:Build(professionKey, mode)
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not route or not graph or not root then return nil end

    local unresolvedByStep = demandMap(graph.unresolvedIntermediateRequirements)
    local supplementalByStep = demandMap(graph.supplementalRequirements)
    local nodes = craftNodeByStep(graph)
    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        evidence = route.evidence or root.evidence,
        authority = self.authority,
        plannerEligible = false,
        transferable = false,
        analysisOnly = true,
        routeCandidateState = graph.candidateState,
        supplementalCandidateState = supplement and supplement.candidateState or "unavailable",
        steps = {},
        stepByRouteIndex = {},
        stats = {
            totalSteps = 0,
            craftSteps = 0,
            trainSteps = 0,
            evidenceQualifiedCrafts = 0,
            routeConnectedCandidates = 0,
            isolatedCandidates = 0,
            blockedCrafts = 0,
            accessGatedCrafts = 0,
            currentCharacterAccessReady = 0,
            supplementalCraftSteps = 0,
            unresolvedDependencySteps = 0,
            sourceGapEntries = 0,
        },
    }

    for stepIndex, step in ipairs(route.steps or {}) do
        local kind = tostring(step.kind or "unknown")
        local gap = gapBeforeStep(graph, step)
        local provenance = {
            expected = model.evidence,
            actual = step.evidence,
            valid = step.evidence == model.evidence,
        }
        local skillRange = { valid = true }
        if kind == "craft" then
            local skillMin = tonumber(step.skillMin)
            local skillTarget = tonumber(step.skillTarget)
            skillRange = {
                skillMin = skillMin,
                skillTarget = skillTarget,
                valid = skillMin ~= nil and skillTarget ~= nil and skillTarget > skillMin,
            }
        elseif kind == "train" then
            local capFrom = tonumber(step.skillCapFrom)
            local capTo = tonumber(step.skillCapTo)
            skillRange = {
                skillCapFrom = capFrom,
                skillCapTo = capTo,
                minCharacterLevel = tonumber(step.minCharacterLevel),
                valid = capFrom ~= nil and capTo ~= nil and capTo > capFrom,
            }
        else
            skillRange.valid = false
        end

        local row = {
            routeStepIndex = stepIndex,
            kind = kind,
            recipe = step.recipe,
            tier = step.tier,
            text = step.text,
            expectedCrafts = tonumber(step.expectedCrafts),
            estimated = step.estimated and true or false,
            keep = step.keep and true or false,
            evidence = step.evidence,
            provenance = provenance,
            skillRange = skillRange,
            routeContinuity = {
                connected = gap == nil,
                entryGap = gap,
            },
            plannerEligible = false,
            transferable = false,
            analysisOnly = true,
        }

        if gap then model.stats.sourceGapEntries = model.stats.sourceGapEntries + 1 end

        if kind == "craft" then
            model.stats.craftSteps = model.stats.craftSteps + 1
            local node = nodes[stepIndex]
            row.reagentRatio = reagentState(step)
            row.outputYield = yieldState(step, node)
            row.access = accessState(step, professionKey)
            local unresolved = unresolvedByStep[stepIndex]
            local supplemental = supplementalByStep[stepIndex]
            local supplementResolved = not supplemental or (supplement and supplement.stats and tonumber(supplement.stats.unresolvedKinds) == 0)
            row.dependencies = {
                unresolved = unresolved ~= nil,
                unresolvedRequirements = unresolved or {},
                supplemental = supplemental ~= nil,
                supplementalRequirements = supplemental or {},
                supplementalExpansionResolved = supplementResolved and true or false,
                state = unresolved and "unresolved-intermediate"
                    or (supplemental and supplementResolved and "supplemental-expanded-analysis-only")
                    or (supplemental and "supplemental-expansion-unresolved")
                    or "direct-or-external",
            }
            if supplemental then model.stats.supplementalCraftSteps = model.stats.supplementalCraftSteps + 1 end
            if unresolved or (supplemental and not supplementResolved) then
                row.dependencies.unresolved = true
                model.stats.unresolvedDependencySteps = model.stats.unresolvedDependencySteps + 1
            end

            row.evidenceQualified = provenance.valid
                and skillRange.valid
                and row.reagentRatio.resolved
                and row.outputYield.resolved
                and (not row.access.required or row.access.recognized)
                and not row.dependencies.unresolved
            row.routeCandidateEligible = row.evidenceQualified and row.routeContinuity.connected
            row.currentCharacterReady = row.routeCandidateEligible and row.access.currentCharacterReady
            if row.evidenceQualified then model.stats.evidenceQualifiedCrafts = model.stats.evidenceQualifiedCrafts + 1 end
            if row.routeCandidateEligible then model.stats.routeConnectedCandidates = model.stats.routeConnectedCandidates + 1 end
            if row.evidenceQualified and not row.routeContinuity.connected then model.stats.isolatedCandidates = model.stats.isolatedCandidates + 1 end
            if not row.evidenceQualified then model.stats.blockedCrafts = model.stats.blockedCrafts + 1 end
            if row.access.required then
                model.stats.accessGatedCrafts = model.stats.accessGatedCrafts + 1
                if row.access.currentCharacterReady then model.stats.currentCharacterAccessReady = model.stats.currentCharacterAccessReady + 1 end
            end
        else
            model.stats.trainSteps = model.stats.trainSteps + 1
            row.reagentRatio = { resolved = true, state = "not-applicable" }
            row.outputYield = { resolved = true, state = "not-applicable" }
            row.access = { required = false, recognized = true, state = "not-applicable", currentCharacterReady = true }
            row.dependencies = { unresolved = false, supplemental = false, state = "not-applicable" }
            row.evidenceQualified = provenance.valid and skillRange.valid
            row.routeCandidateEligible = false
            row.currentCharacterReady = false
        end

        row.status = statusFor(row)
        model.steps[#model.steps + 1] = row
        model.stepByRouteIndex[stepIndex] = row
        model.stats.totalSteps = model.stats.totalSteps + 1
    end

    model.candidateState = model.stats.blockedCrafts > 0 and "mixed-step-evidence"
        or (model.stats.isolatedCandidates > 0 and "qualified-steps-with-source-gaps")
        or "step-candidates-verified-analysis-only"
    return model
end

function ResearchCandidateVerifier:Build(professionKey,mode)
    local key=tostring(professionKey or "ENGINEERING"):upper()
    mode=mode=="aggressive" and "aggressive" or "normal"
    local pass=evaluation
    if pass and pass.key==key and pass.mode==mode and pass.session==identity() then
        if not pass.built then
            pass.model=buildCandidate(self,key,mode)
            pass.built=true
        end
        return pass.model
    end
    return buildCandidate(self,key,mode)
end

function ResearchCandidateVerifier:GetStep(professionKey, mode, selector)
    local model = self:Build(professionKey, mode)
    if not model then return nil, nil end
    local index = tonumber(selector)
    if index then return model.stepByRouteIndex[index], model end
    local key = normalize(selector)
    if key ~= "" then
        for _, row in ipairs(model.steps or {}) do
            if normalize(row.recipe or row.tier or row.text) == key then return row, model end
        end
    end
    return nil, model
end

function ResearchCandidateVerifier:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then
        errors[#errors + 1] = "profession research unavailable"
        return errors, warnings
    end
    for professionKey, modes in pairs(root.professions or {}) do
        if professionKey ~= "HARNESS" then
            for _, mode in ipairs({"normal", "aggressive"}) do
                if modes[mode] then
                    local model = self:Build(professionKey, mode)
                    if not model then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": candidate model unavailable"
                    elseif model.plannerEligible ~= false or model.authority ~= "research-reference-only" then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": authority policy mismatch"
                    else
                        for _, row in ipairs(model.steps or {}) do
                            if row.kind == "craft" and not row.provenance.valid then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": provenance mismatch at route step " .. tostring(row.routeStepIndex)
                            end
                            if row.kind == "craft" and row.status == "blocked-reagent-ratio" then
                                warnings[#warnings + 1] = professionKey .. "/" .. mode .. ": reagent ratio unresolved for " .. tostring(row.recipe)
                            elseif row.kind == "craft" and row.status == "blocked-output-yield" then
                                warnings[#warnings + 1] = professionKey .. "/" .. mode .. ": output yield unresolved for " .. tostring(row.recipe)
                            elseif row.status == "candidate-isolated-by-source-gap" then
                                warnings[#warnings + 1] = professionKey .. "/" .. mode .. ": source gap before " .. tostring(row.recipe)
                            end
                        end
                    end
                end
            end
        end
    end
    return errors, warnings
end

local function formatStep(row)
    if not row then return "Step unavailable." end
    local label = row.recipe or row.tier or row.text or ("step " .. tostring(row.routeStepIndex))
    local lines = {
        string.format("Research candidate step %d: %s", tonumber(row.routeStepIndex) or 0, tostring(label)),
        "Status: " .. tostring(row.status),
        "Evidence qualified: " .. tostring(row.evidenceQualified == true),
        "Route-connected candidate: " .. tostring(row.routeCandidateEligible == true),
        "Planner authority: disabled",
    }
    if row.kind == "craft" then
        lines[#lines + 1] = string.format("Reagent ratio: %s", row.reagentRatio.resolved and "resolved" or tostring(row.reagentRatio.reason or "unresolved"))
        lines[#lines + 1] = string.format("Output yield: %s", tostring(row.outputYield.state))
        lines[#lines + 1] = string.format("Dependencies: %s", tostring(row.dependencies.state))
        lines[#lines + 1] = string.format("Access: %s", tostring(row.access.state))
    end
    if row.routeContinuity and row.routeContinuity.entryGap then
        lines[#lines + 1] = string.format("Source gap before step: %d-%d", tonumber(row.routeContinuity.entryGap.fromSkill) or 0, tonumber(row.routeContinuity.entryGap.toSkill) or 0)
    end
    return table.concat(lines, "\n")
end

function ResearchCandidateVerifier:GetSummary(professionKey, mode, selector)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"
    if selector and tostring(selector) ~= "" then
        local row = self:GetStep(professionKey, mode, selector)
        return formatStep(row)
    end
    local model = self:Build(professionKey, mode)
    if not model then return "Research candidate verification unavailable." end
    local lines = {
        string.format("Research candidates: %s / %s", professionKey, mode),
        string.format("State: %s · analysis only · Planner authority disabled", tostring(model.candidateState)),
        string.format(
            "Craft steps: %d · evidence-qualified %d · route-connected %d · isolated %d · blocked %d",
            tonumber(model.stats.craftSteps) or 0,
            tonumber(model.stats.evidenceQualifiedCrafts) or 0,
            tonumber(model.stats.routeConnectedCandidates) or 0,
            tonumber(model.stats.isolatedCandidates) or 0,
            tonumber(model.stats.blockedCrafts) or 0
        ),
        string.format(
            "Access gates: %d · known now %d · supplemental consumers %d · unresolved dependency steps %d · source-gap entries %d",
            tonumber(model.stats.accessGatedCrafts) or 0,
            tonumber(model.stats.currentCharacterAccessReady) or 0,
            tonumber(model.stats.supplementalCraftSteps) or 0,
            tonumber(model.stats.unresolvedDependencySteps) or 0,
            tonumber(model.stats.sourceGapEntries) or 0
        ),
    }
    local shown = 0
    for _, row in ipairs(model.steps or {}) do
        if row.kind == "craft" and (row.status ~= "candidate-verified-analysis-only" or shown < 3) then
            lines[#lines + 1] = string.format("· #%d %s · %s", tonumber(row.routeStepIndex) or 0, tostring(row.recipe), tostring(row.status))
            shown = shown + 1
            if shown >= 6 then break end
        end
    end
    lines[#lines + 1] = "A verified research candidate is still not a live Planner step. Promotion remains explicitly disabled until a later policy layer grants authority property-by-property."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ResearchCandidateVerifier", ResearchCandidateVerifier)
