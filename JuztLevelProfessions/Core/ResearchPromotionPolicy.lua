local _, JLP = ...

-- Controlled promotion gate for research-derived route steps. A step can become
-- a provisional Planner candidate only when the *current Forever build* has
-- corroborated the recipe and its material behavior, any quantity-sensitive
-- output yield is current-build live, route continuity is intact, and access
-- requirements have an explicit acquisition source. Provisional candidates are
-- still not inserted into the audited Planner or execution pipeline.
local ResearchPromotionPolicy = {
    contract = "controlled-research-step-promotion-policy-v2",
    authority = "promotion-policy-only",
    minExactMaterialSamples = 4,
    materialRateTolerance = 0.000001,
    plannerEligible = false,
    executionEligible = false,
}

local VALID_ACCESS_KINDS = {
    recipe = true,
    formula = true,
    pattern = true,
    schematic = true,
}

local LIVE_YIELD_STATES = {
    ["live-current-build-corroborated"] = true,
    ["live-current-build-verified+external"] = true,
    ["live-current-build-verified"] = true,
    ["live-current-build-override"] = true,
}

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function closeEnough(a, b, tolerance)
    a, b = tonumber(a), tonumber(b)
    if a == nil or b == nil then return false end
    return math.abs(a - b) <= (tonumber(tolerance) or 0.000001)
end

local function routeStep(professionKey, mode, index)
    local research = JLP:GetModule("ProfessionResearch")
    local route = research and research:Get(professionKey, mode)
    return route and route.steps and route.steps[tonumber(index)] or nil
end

local function recipeObservation(professionKey, row)
    local cache = JLP:GetModule("KnowledgeCache")
    if not cache then
        return { state="knowledge-cache-unavailable", knowledge="unknown", currentBuildObserved=false, ready=false }
    end
    local state
    if cache.GetRecipeKnowledgeState then
        state = cache:GetRecipeKnowledgeState(row.recipe, professionKey)
    else
        state = { knowledge=cache:GetRecipeKnowledge(row.recipe, professionKey), currentBuildObserved=false }
    end
    state = state or { knowledge="unknown", currentBuildObserved=false }
    state.ready = state.knowledge == "known" and state.currentBuildObserved == true and state.sessionIdentityConflict ~= true
    if state.sessionIdentityConflict == true then
        state.state = "conflicting-recipe-identity"
    elseif state.ready then
        state.state = "known-current-build"
    elseif state.knowledge == "known" then
        state.state = "known-historical-build-only"
    elseif state.knowledge == "not-known" and state.currentBuildObserved then
        state.state = "not-known-current-build"
    else
        state.state = "current-build-observation-missing"
    end
    return state
end

local function currentMaterialEvidence(professionKey, row, recipeID)
    local telemetry = JLP:GetModule("RecipeTelemetry")
    local required = row and row.reagentRatio and row.reagentRatio.reagents or {}
    if #required == 0 then
        return { required=false, ready=true, state="not-required", materials={}, exactSamples=nil }
    end
    if not telemetry or not telemetry.GetCurrentMaterialEvidence then
        return { required=true, ready=false, conflict=false, state="current-build-material-evidence-unavailable", materials={} }
    end
    local evidence = telemetry:GetCurrentMaterialEvidence(professionKey, recipeID, row.recipe)
    if not evidence then
        return { required=true, ready=false, conflict=false, state="awaiting-current-build-material-evidence", materials={} }
    end

    local byName = {}
    local extraObserved = {}
    for _, material in pairs(evidence.materials or {}) do
        local key = normalize(material.name)
        if key ~= "" then byName[key] = material end
    end

    local details = {}
    local minimum = ResearchPromotionPolicy.minExactMaterialSamples
    local allReady = true
    local conflict = false
    local minimumSeen = nil
    local expectedNames = {}
    for _, requirement in ipairs(required) do
        local nameKey = normalize(requirement.name)
        expectedNames[nameKey] = true
        local observed = byName[nameKey]
        local samples = observed and math.max(0, tonumber(observed.exactUnits) or 0) or 0
        minimumSeen = minimumSeen and math.min(minimumSeen, samples) or samples
        local expectedPerCraft = tonumber(requirement.perCraft)
        local rateMatches = observed
            and observed.allReconciledExact == true
            and closeEnough(observed.expectedPerCraft, expectedPerCraft, ResearchPromotionPolicy.materialRateTolerance)
            and closeEnough(observed.consumedPerCraft, expectedPerCraft, ResearchPromotionPolicy.materialRateTolerance)
        if observed and samples >= minimum and not rateMatches then conflict = true end
        if not observed or samples < minimum or not rateMatches then allReady = false end
        details[#details + 1] = {
            name = requirement.name,
            expectedPerCraft = expectedPerCraft,
            exactSamples = samples,
            observedExpectedPerCraft = observed and observed.expectedPerCraft or nil,
            observedConsumedPerCraft = observed and observed.consumedPerCraft or nil,
            ready = observed ~= nil and samples >= minimum and rateMatches or false,
            conflict = observed ~= nil and samples >= minimum and not rateMatches or false,
        }
    end

    for _, observed in pairs(evidence.materials or {}) do
        local nameKey = normalize(observed.name)
        local samples = math.max(0, tonumber(observed.exactUnits) or 0)
        if nameKey ~= "" and samples >= minimum and not expectedNames[nameKey] and (tonumber(observed.consumedPerCraft) or 0) > 0 then
            conflict = true
            allReady = false
            extraObserved[#extraObserved + 1] = {
                name = observed.name,
                exactSamples = samples,
                consumedPerCraft = observed.consumedPerCraft,
            }
        end
    end

    local state
    if conflict then state = "current-build-material-conflict"
    elseif allReady then state = "current-build-materials-corroborated"
    else state = "awaiting-current-build-material-evidence" end
    return {
        required = true,
        ready = allReady,
        conflict = conflict,
        state = state,
        minimumSamples = minimum,
        exactSamples = minimumSeen,
        materials = details,
        unexpectedMaterials = extraObserved,
        evidence = evidence,
    }
end

local function outputYieldState(row, recipeID)
    if not row.keep then
        return { required=false, ready=true, conflict=false, state="not-required-for-non-keep-step" }
    end
    local output = JLP:GetModule("RecipeOutputEvidence")
    local resolved = output and output:Resolve(row.recipe, recipeID) or nil
    if not resolved then
        return { required=true, ready=false, conflict=false, state="yield-evidence-unavailable" }
    end
    local ready = resolved.dependencyQuantityEligible == true and LIVE_YIELD_STATES[resolved.status] == true
    local conflict = resolved.status == "live-reference-conflict-learning" or resolved.status == "live-current-build-variable"
    local state
    if ready then state = "current-build-yield-corroborated"
    elseif conflict then state = "current-build-yield-conflict"
    else state = "awaiting-current-build-yield-evidence" end
    return {
        required = true,
        ready = ready,
        conflict = conflict,
        state = state,
        status = resolved.status,
        outputPerCraft = resolved.outputQuantity,
        confidence = resolved.confidence,
        source = resolved.source,
        liveVerified = resolved.liveVerified == true,
        externalVerified = resolved.externalVerified == true,
    }
end

local function explicitAccessSource(step, row)
    if not row.access or not row.access.required then
        return { required=false, ready=true, state="not-required" }
    end
    local requirement = step and step.sourceRequirement or nil
    local kind = requirement and tostring(requirement.kind or ""):lower() or tostring(row.access.kind or ""):lower()
    local name = requirement and requirement.name or row.recipe
    if not VALID_ACCESS_KINDS[kind] then
        return { required=true, ready=false, state="unrecognized-access-kind", kind=kind }
    end

    -- Alpha62: resolve the acquisition source through the dedicated build-aware
    -- evidence layer first. It can accept a same-build external Forever
    -- reference, prefer a live current-build source observation, or explicitly
    -- block stale/conflicted references.
    local accessEvidence = JLP:GetModule("RecipeAccessEvidence")
    if accessEvidence and accessEvidence.Resolve then
        local resolved = accessEvidence:Resolve(kind, name)
        if resolved and (resolved.reference or resolved.live or resolved.status ~= "access-source-reference-missing") then
            return {
                required = true,
                ready = resolved.promotionEligible == true,
                state = resolved.status or resolved.state or "awaiting-explicit-access-source",
                kind = kind,
                sourceKind = resolved.sourceType,
                source = resolved.source,
                evidence = resolved.evidence,
                confidence = resolved.confidence,
                liveVerified = resolved.liveVerified == true,
                externalVerified = resolved.externalVerified == true,
                currentBuild = resolved.currentBuild,
                referenceCapturedBuild = resolved.referenceCapturedBuild,
                conflict = resolved.conflict == true,
                conflictReason = resolved.conflictReason,
            }
        end
    end

    -- Retain the explicit embedded-source path for synthetic harness fixtures
    -- and future authored routes that carry their own acquisition provenance.
    local source = requirement and (requirement.acquisitionSource or requirement.source) or nil
    local evidence = type(source) == "table" and (source.evidence or requirement.evidence) or (requirement and requirement.evidence)
    local sourceKind = type(source) == "table" and tostring(source.kind or source.type or "") or ""
    local identity = type(source) == "table" and (source.name or source.npc or source.zone or source.item or source.note) or nil
    local ready = source ~= nil and sourceKind ~= "" and identity ~= nil and tostring(identity) ~= "" and evidence ~= nil and tostring(evidence) ~= ""
    return {
        required = true,
        ready = ready and true or false,
        state = ready and "explicit-access-source" or "awaiting-explicit-access-source",
        kind = kind,
        sourceKind = sourceKind ~= "" and sourceKind or nil,
        source = source,
        evidence = evidence,
    }
end

local function dependencyPromotionState(row, deferSupplementalClosure)
    local dependencies = row.dependencies or {}
    if dependencies.unresolved then
        return { ready=false, state="unresolved-dependency-evidence" }
    end
    if dependencies.supplemental then
        if deferSupplementalClosure then
            return {
                ready=true,
                closureRequired=true,
                state="supplemental-dependency-closure-required",
                analysisState=dependencies.state,
            }
        end
        return {
            ready=false,
            closureRequired=true,
            state="awaiting-supplemental-dependency-promotion",
            analysisState=dependencies.state,
        }
    end
    return { ready=true, closureRequired=false, state="direct-or-external-dependencies" }
end

local function statusFor(out)
    if out.kind ~= "craft" then return "not-a-craft-candidate" end
    if not out.baseCandidateEligible then return "blocked-research-candidate" end
    if not out.recipeObservation.ready then return "awaiting-current-build-recipe-knowledge" end
    if out.materialEvidence.conflict then return "blocked-current-build-material-conflict" end
    if not out.materialEvidence.ready then return "awaiting-current-build-material-evidence" end
    if out.outputYield.conflict then return "blocked-current-build-yield-conflict" end
    if not out.outputYield.ready then return "awaiting-current-build-yield-evidence" end
    if not out.accessSource.ready then
        if out.accessSource.conflict or out.accessSource.state == "external-access-source-conflict" then return "blocked-access-source-conflict" end
        if out.accessSource.state == "external-access-source-stale-build" then return "awaiting-current-build-access-source-revalidation" end
        return "awaiting-access-source-evidence"
    end
    if not out.dependencies.ready then return out.dependencies.state end
    if out.dependencies.closureRequired then return "provisional-pending-dependency-closure" end
    return "provisional-planner-candidate"
end

local function evaluateStep(self, professionKey, mode, selector, deferSupplementalClosure)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"
    local verifier = JLP:GetModule("ResearchCandidateVerifier")
    local row, model
    if verifier then row, model = verifier:GetStep(professionKey, mode, selector) end
    if not row then return nil, model end
    local rawStep = routeStep(professionKey, mode, row.routeStepIndex)
    local observation = row.kind == "craft" and recipeObservation(professionKey, row) or {ready=false,state="not-applicable"}
    local recipeID = observation.recipeID
    local out = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        routeStepIndex = row.routeStepIndex,
        kind = row.kind,
        recipe = row.recipe,
        tier = row.tier,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        provisionalCandidateEligible = false,
        baseCandidateEligible = row.kind == "craft" and row.routeCandidateEligible == true or false,
        baseCandidateStatus = row.status,
        recipeObservation = observation,
        materialEvidence = row.kind == "craft" and currentMaterialEvidence(professionKey, row, recipeID) or {required=false,ready=false,state="not-applicable"},
        outputYield = row.kind == "craft" and outputYieldState(row, recipeID) or {required=false,ready=false,state="not-applicable"},
        accessSource = explicitAccessSource(rawStep, row),
        dependencies = dependencyPromotionState(row, deferSupplementalClosure),
        candidate = row,
    }
    out.status = statusFor(out)
    out.provisionalCandidateEligible = out.status == "provisional-planner-candidate"
    out.intrinsicCandidateEligible = out.status == "provisional-planner-candidate" or out.status == "provisional-pending-dependency-closure"
    return out, model
end

function ResearchPromotionPolicy:EvaluateStep(professionKey, mode, selector)
    return evaluateStep(self, professionKey, mode, selector, false)
end

-- Evaluates every alpha60 property gate while deferring only the supplemental
-- dependency closure itself. ResearchPromotionClosure is the sole consumer of
-- this staging API; it still grants no Planner or execution authority.
function ResearchPromotionPolicy:EvaluateIntrinsicStep(professionKey, mode, selector)
    return evaluateStep(self, professionKey, mode, selector, true)
end

function ResearchPromotionPolicy:Build(professionKey, mode)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"
    local verifier = JLP:GetModule("ResearchCandidateVerifier")
    local candidates = verifier and verifier:Build(professionKey, mode)
    if not candidates then return nil end
    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        steps = {},
        stepByRouteIndex = {},
        stats = {
            craftSteps = 0,
            provisionalCandidates = 0,
            blockedResearchCandidates = 0,
            awaitingRecipeKnowledge = 0,
            awaitingMaterialEvidence = 0,
            materialConflicts = 0,
            awaitingYieldEvidence = 0,
            yieldConflicts = 0,
            awaitingAccessSource = 0,
            awaitingAccessRevalidation = 0,
            accessConflicts = 0,
            awaitingDependencyPromotion = 0,
        },
    }
    for _, candidate in ipairs(candidates.steps or {}) do
        if candidate.kind == "craft" then
            local row = self:EvaluateStep(professionKey, mode, candidate.routeStepIndex)
            model.steps[#model.steps + 1] = row
            model.stepByRouteIndex[candidate.routeStepIndex] = row
            model.stats.craftSteps = model.stats.craftSteps + 1
            if row.status == "provisional-planner-candidate" then model.stats.provisionalCandidates = model.stats.provisionalCandidates + 1
            elseif row.status == "blocked-research-candidate" then model.stats.blockedResearchCandidates = model.stats.blockedResearchCandidates + 1
            elseif row.status == "awaiting-current-build-recipe-knowledge" then model.stats.awaitingRecipeKnowledge = model.stats.awaitingRecipeKnowledge + 1
            elseif row.status == "awaiting-current-build-material-evidence" then model.stats.awaitingMaterialEvidence = model.stats.awaitingMaterialEvidence + 1
            elseif row.status == "blocked-current-build-material-conflict" then model.stats.materialConflicts = model.stats.materialConflicts + 1
            elseif row.status == "awaiting-current-build-yield-evidence" then model.stats.awaitingYieldEvidence = model.stats.awaitingYieldEvidence + 1
            elseif row.status == "blocked-current-build-yield-conflict" then model.stats.yieldConflicts = model.stats.yieldConflicts + 1
            elseif row.status == "awaiting-access-source-evidence" then model.stats.awaitingAccessSource = model.stats.awaitingAccessSource + 1
            elseif row.status == "awaiting-current-build-access-source-revalidation" then model.stats.awaitingAccessRevalidation = model.stats.awaitingAccessRevalidation + 1
            elseif row.status == "blocked-access-source-conflict" then model.stats.accessConflicts = model.stats.accessConflicts + 1
            elseif row.status == "awaiting-supplemental-dependency-promotion" or row.status == "unresolved-dependency-evidence" then model.stats.awaitingDependencyPromotion = model.stats.awaitingDependencyPromotion + 1 end
        end
    end
    model.state = model.stats.provisionalCandidates > 0 and "provisional-candidates-available" or "learning-current-build-evidence"
    return model
end

function ResearchPromotionPolicy:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then return {"profession research unavailable"}, warnings end
    for professionKey, modes in pairs(root.professions or {}) do
        if professionKey ~= "HARNESS" then
            for _, mode in ipairs({"normal","aggressive"}) do
                if modes[mode] then
                    local model = self:Build(professionKey, mode)
                    if not model then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": promotion policy unavailable"
                    else
                        for _, row in ipairs(model.steps or {}) do
                            if row.plannerEligible ~= false or row.executionEligible ~= false then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": provisional policy escaped Planner authority"
                            end
                            if row.provisionalCandidateEligible and row.status ~= "provisional-planner-candidate" then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": provisional eligibility/status mismatch"
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
    if not row then return "Promotion candidate unavailable." end
    local lines = {
        string.format("Research promotion step %d: %s", tonumber(row.routeStepIndex) or 0, tostring(row.recipe or row.tier or "unknown")),
        "Status: " .. tostring(row.status),
        "Base candidate: " .. tostring(row.baseCandidateStatus),
        "Current-build recipe: " .. tostring(row.recipeObservation and row.recipeObservation.state or "n/a"),
        "Current-build materials: " .. tostring(row.materialEvidence and row.materialEvidence.state or "n/a"),
        "Output yield: " .. tostring(row.outputYield and row.outputYield.state or "n/a"),
        "Access source: " .. tostring(row.accessSource and row.accessSource.state or "n/a"),
        "Dependencies: " .. tostring(row.dependencies and row.dependencies.state or "n/a"),
        "Provisional candidate: " .. tostring(row.provisionalCandidateEligible == true),
        "Planner authority: disabled",
    }
    return table.concat(lines, "\n")
end

function ResearchPromotionPolicy:GetSummary(professionKey, mode, selector)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"
    if selector and tostring(selector) ~= "" then
        return formatStep(self:EvaluateStep(professionKey, mode, selector))
    end
    local model = self:Build(professionKey, mode)
    if not model then return "Research promotion policy unavailable." end
    local s = model.stats
    local lines = {
        string.format("Research promotion policy: %s / %s", professionKey, mode),
        string.format("State: %s · controlled provisional layer · Planner authority disabled", tostring(model.state)),
        string.format("Craft steps: %d · provisional %d · base-blocked %d", tonumber(s.craftSteps) or 0, tonumber(s.provisionalCandidates) or 0, tonumber(s.blockedResearchCandidates) or 0),
        string.format("Awaiting: recipe %d · materials %d · yield %d · access source %d · access revalidation %d · dependency promotion %d", tonumber(s.awaitingRecipeKnowledge) or 0, tonumber(s.awaitingMaterialEvidence) or 0, tonumber(s.awaitingYieldEvidence) or 0, tonumber(s.awaitingAccessSource) or 0, tonumber(s.awaitingAccessRevalidation) or 0, tonumber(s.awaitingDependencyPromotion) or 0),
        string.format("Conflicts: materials %d · yield %d · access %d", tonumber(s.materialConflicts) or 0, tonumber(s.yieldConflicts) or 0, tonumber(s.accessConflicts) or 0),
        string.format("Policy: recipe must be observed known on the current build; materials need %d exact current-build samples; keep-yields need live current-build corroboration/verification; access-gated recipes need an explicit acquisition source.", tonumber(self.minExactMaterialSamples) or 0),
    }
    local shown = 0
    for _, row in ipairs(model.steps or {}) do
        if row.status == "provisional-planner-candidate" or shown < 4 then
            lines[#lines + 1] = string.format("· #%d %s · %s", tonumber(row.routeStepIndex) or 0, tostring(row.recipe), tostring(row.status))
            shown = shown + 1
            if shown >= 7 then break end
        end
    end
    lines[#lines + 1] = "Provisional means evidence-qualified for a later Planner bridge only; this layer never inserts research steps into the live Planner or execution queue."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ResearchPromotionPolicy", ResearchPromotionPolicy)
