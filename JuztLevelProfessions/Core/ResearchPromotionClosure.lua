local _, JLP = ...

-- Resolves the complete upstream promotion closure for a research route step.
-- Alpha60 validates the step's own current-build properties; this layer adds the
-- missing dependency rule: every retained/supplemental producer used by the step
-- must independently pass the same intrinsic promotion policy. Closure success
-- is still a staging state only and never enters the live Planner or execution.
local ResearchPromotionClosure = {
    contract = "recursive-research-promotion-closure-v1",
    authority = "promotion-closure-only",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
}


local function addEdge(map, consumerStep, producerStep, kind, detail)
    consumerStep, producerStep = tonumber(consumerStep), tonumber(producerStep)
    if not consumerStep or not producerStep then return end
    map[consumerStep] = map[consumerStep] or {}
    local row = map[consumerStep][producerStep]
    if not row then
        row = {
            producerStepIndex = producerStep,
            relationKinds = {},
            details = {},
        }
        map[consumerStep][producerStep] = row
    end
    if kind and not row.relationKinds[kind] then row.relationKinds[kind] = true end
    if detail then
        detail.relationKind = kind
        row.details[#row.details + 1] = detail
    end
end

local function relationList(map)
    local out = {}
    for kind in pairs(map or {}) do out[#out + 1] = kind end
    table.sort(out)
    return out
end

local function buildDependencyMap(graph, supplement)
    local map = {}
    for _, dep in ipairs(graph and graph.intermediateDependencies or {}) do
        local producer = graph.nodeByID and graph.nodeByID[dep.producer]
        local consumer = graph.nodeByID and graph.nodeByID[dep.consumer]
        if producer and consumer then
            addEdge(map, consumer.stepIndex, producer.stepIndex, "retained-intermediate", {
                item = dep.item,
                quantity = dep.quantity,
                producerRecipe = dep.producerRecipe,
                consumerRecipe = dep.consumerRecipe,
                quantityAuthority = dep.quantityAuthority == true,
            })
        end
    end
    for _, action in ipairs(supplement and supplement.craftActions or {}) do
        for _, consumerStep in ipairs(action.requiredByRouteSteps or {}) do
            addEdge(map, consumerStep, action.producerStepIndex, "supplemental-craft", {
                recipe = action.recipe,
                extraCrafts = action.extraCrafts,
                requiredOutput = action.requiredOutput,
                outputPerCraft = action.outputPerCraft,
                yieldStatus = action.yieldStatus,
            })
        end
    end
    return map
end

local function collectClosure(dependencyMap, targetStep)
    local visited, active = {}, {}
    local order, edges = {}, {}
    local invalidOrder, cycle = false, false

    local function walk(consumerStep)
        consumerStep = tonumber(consumerStep)
        if not consumerStep then return end
        if active[consumerStep] then cycle = true return end
        active[consumerStep] = true
        local producers = dependencyMap[consumerStep] or {}
        local indices = {}
        for producerStep in pairs(producers) do indices[#indices + 1] = producerStep end
        table.sort(indices)
        for _, producerStep in ipairs(indices) do
            local relation = producers[producerStep]
            if producerStep >= consumerStep then invalidOrder = true end
            edges[#edges + 1] = {
                consumerStepIndex = consumerStep,
                producerStepIndex = producerStep,
                relationKinds = relationList(relation.relationKinds),
                details = relation.details,
            }
            if not visited[producerStep] then
                visited[producerStep] = true
                walk(producerStep)
                order[#order + 1] = producerStep
            end
        end
        active[consumerStep] = nil
    end

    walk(targetStep)
    table.sort(edges, function(a, b)
        if a.consumerStepIndex ~= b.consumerStepIndex then return a.consumerStepIndex < b.consumerStepIndex end
        return a.producerStepIndex < b.producerStepIndex
    end)
    return order, edges, invalidOrder, cycle
end

local function classifyUpstream(status)
    status = tostring(status or "")
    if status:match("^blocked") or status == "unresolved-dependency-evidence" then return "blocked" end
    return "awaiting"
end

function ResearchPromotionClosure:EvaluateStep(professionKey, mode, selector)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"

    local verifier = JLP:GetModule("ResearchCandidateVerifier")
    local policy = JLP:GetModule("ResearchPromotionPolicy")
    local graphModule = JLP:GetModule("ProfessionDependencyGraph")
    local supplementModule = JLP:GetModule("ResearchSupplementPlanner")
    if not verifier or not policy or not graphModule or not supplementModule then return nil end

    local candidate, candidateModel = verifier:GetStep(professionKey, mode, selector)
    if not candidate then return nil, candidateModel end
    local target = policy:EvaluateIntrinsicStep(professionKey, mode, candidate.routeStepIndex)
    local graph = graphModule:Build(professionKey, mode)
    local supplement = supplementModule:Build(professionKey, mode)
    if not target or not graph or not supplement then return nil, candidateModel end

    local dependencyMap = buildDependencyMap(graph, supplement)
    local upstreamIndices, edges, invalidOrder, cycle = collectClosure(dependencyMap, candidate.routeStepIndex)
    -- Defense in depth: a retained edge with an unqualified quantity must
    -- never become a successful promotion dependency, even from stale graph data.
    local unverifiedQuantityEdges = 0
    for _, edge in ipairs(edges) do
        for _, detail in ipairs(edge.details or {}) do
            if detail.relationKind == "retained-intermediate" and
                detail.quantityAuthority ~= true then
                unverifiedQuantityEdges = unverifiedQuantityEdges + 1
            end
        end
    end
    local out = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        routeStepIndex = candidate.routeStepIndex,
        kind = candidate.kind,
        recipe = candidate.recipe,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        closureCandidateEligible = false,
        target = target,
        dependencySteps = {},
        dependencyEdges = edges,
        stats = {
            upstreamSteps = #upstreamIndices,
            readyUpstreamSteps = 0,
            awaitingUpstreamSteps = 0,
            blockedUpstreamSteps = 0,
        },
        cycleDetected = cycle,
        invalidOrdering = invalidOrder,
        unverifiedQuantityEdges = unverifiedQuantityEdges,
    }

    local allReady = true
    for _, stepIndex in ipairs(upstreamIndices) do
        local row = policy:EvaluateIntrinsicStep(professionKey, mode, stepIndex)
        local ready = row and row.intrinsicCandidateEligible == true or false
        local dep = {
            routeStepIndex = stepIndex,
            recipe = row and row.recipe or nil,
            status = row and row.status or "promotion-policy-unavailable",
            intrinsicCandidateEligible = ready,
            observedBuild = row and row.recipeObservation and row.recipeObservation.observedBuild or nil,
            currentBuild = row and row.recipeObservation and row.recipeObservation.currentBuild or nil,
            currentBuildObserved = row and row.recipeObservation and row.recipeObservation.currentBuildObserved == true or false,
            plannerEligible = false,
            executionEligible = false,
        }
        out.dependencySteps[#out.dependencySteps + 1] = dep
        if ready then
            out.stats.readyUpstreamSteps = out.stats.readyUpstreamSteps + 1
        else
            allReady = false
            local kind = classifyUpstream(dep.status)
            if kind == "blocked" then
                out.stats.blockedUpstreamSteps = out.stats.blockedUpstreamSteps + 1
            else
                out.stats.awaitingUpstreamSteps = out.stats.awaitingUpstreamSteps + 1
            end
        end
    end

    if candidate.kind ~= "craft" then
        out.status = "not-a-craft-candidate"
    elseif not target.intrinsicCandidateEligible then
        out.status = target.status
    elseif cycle then
        out.status = "blocked-promotion-closure-cycle"
    elseif invalidOrder then
        out.status = "blocked-promotion-closure-order"
    elseif unverifiedQuantityEdges > 0 then
        out.status = "blocked-unverified-intermediate-quantity"
    elseif out.stats.blockedUpstreamSteps > 0 then
        out.status = "blocked-upstream-promotion-closure"
    elseif out.stats.awaitingUpstreamSteps > 0 then
        out.status = "awaiting-upstream-promotion-closure"
    elseif not allReady then
        out.status = "awaiting-upstream-promotion-closure"
    elseif #upstreamIndices > 0 then
        out.status = "provisional-dependency-closure-complete"
        out.closureCandidateEligible = true
    else
        out.status = "provisional-closure-not-required"
        out.closureCandidateEligible = target.status == "provisional-planner-candidate"
    end

    return out, candidateModel
end

function ResearchPromotionClosure:Build(professionKey, mode)
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
            closureCandidates = 0,
            closureNotRequired = 0,
            awaitingUpstream = 0,
            blockedUpstream = 0,
            targetGateBlocked = 0,
            upstreamRelations = 0,
        },
    }

    for _, candidate in ipairs(candidates.steps or {}) do
        if candidate.kind == "craft" then
            local row = self:EvaluateStep(professionKey, mode, candidate.routeStepIndex)
            model.steps[#model.steps + 1] = row
            model.stepByRouteIndex[candidate.routeStepIndex] = row
            model.stats.craftSteps = model.stats.craftSteps + 1
            model.stats.upstreamRelations = model.stats.upstreamRelations + #(row.dependencyEdges or {})
            if row.status == "provisional-dependency-closure-complete" then
                model.stats.closureCandidates = model.stats.closureCandidates + 1
            elseif row.status == "provisional-closure-not-required" and row.closureCandidateEligible then
                model.stats.closureCandidates = model.stats.closureCandidates + 1
                model.stats.closureNotRequired = model.stats.closureNotRequired + 1
            elseif row.status == "awaiting-upstream-promotion-closure" then
                model.stats.awaitingUpstream = model.stats.awaitingUpstream + 1
            elseif row.status == "blocked-upstream-promotion-closure" or row.status == "blocked-promotion-closure-cycle" or row.status == "blocked-promotion-closure-order" then
                model.stats.blockedUpstream = model.stats.blockedUpstream + 1
            else
                model.stats.targetGateBlocked = model.stats.targetGateBlocked + 1
            end
        end
    end
    model.state = model.stats.closureCandidates > 0 and "closure-candidates-available" or "learning-promotion-closure"
    return model
end

function ResearchPromotionClosure:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then return {"profession research unavailable"}, warnings end
    for professionKey, modes in pairs(root.professions or {}) do
        if professionKey ~= "HARNESS" then
            for _, mode in ipairs({"normal", "aggressive"}) do
                if modes[mode] then
                    local model = self:Build(professionKey, mode)
                    if not model then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": promotion closure unavailable"
                    else
                        for _, row in ipairs(model.steps or {}) do
                            if row.plannerEligible ~= false or row.executionEligible ~= false or row.transferable ~= false then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": closure escaped staging authority"
                            end
                            if row.closureCandidateEligible then
                                if row.stats.awaitingUpstreamSteps ~= 0 or row.stats.blockedUpstreamSteps ~= 0 or row.cycleDetected or row.invalidOrdering then
                                    errors[#errors + 1] = professionKey .. "/" .. mode .. ": closure candidate retained an unresolved upstream gate"
                                end
                                for _, dep in ipairs(row.dependencySteps or {}) do
                                    if not dep.intrinsicCandidateEligible then
                                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": closure candidate skipped unpromoted upstream step"
                                        break
                                    end
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

local function formatStep(row)
    if not row then return "Promotion closure unavailable." end
    local lines = {
        string.format("Research promotion closure step %d: %s", tonumber(row.routeStepIndex) or 0, tostring(row.recipe or "unknown")),
        "Status: " .. tostring(row.status),
        "Target intrinsic gate: " .. tostring(row.target and row.target.status or "unavailable"),
        string.format("Upstream: %d total · %d ready · %d awaiting · %d blocked", tonumber(row.stats and row.stats.upstreamSteps) or 0, tonumber(row.stats and row.stats.readyUpstreamSteps) or 0, tonumber(row.stats and row.stats.awaitingUpstreamSteps) or 0, tonumber(row.stats and row.stats.blockedUpstreamSteps) or 0),
        "Closure candidate: " .. tostring(row.closureCandidateEligible == true),
        "Planner authority: disabled",
    }
    local shown = 0
    for _, dep in ipairs(row.dependencySteps or {}) do
        lines[#lines + 1] = string.format("· #%d %s · %s", tonumber(dep.routeStepIndex) or 0, tostring(dep.recipe or "unknown"), tostring(dep.status))
        shown = shown + 1
        if shown >= 8 then break end
    end
    return table.concat(lines, "\n")
end

function ResearchPromotionClosure:GetSummary(professionKey, mode, selector)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"
    if selector and tostring(selector) ~= "" then
        return formatStep(self:EvaluateStep(professionKey, mode, selector))
    end
    local model = self:Build(professionKey, mode)
    if not model then return "Research promotion closure unavailable." end
    local s = model.stats
    local lines = {
        string.format("Research promotion closure: %s / %s", professionKey, mode),
        string.format("State: %s · recursive upstream gate · Planner authority disabled", tostring(model.state)),
        string.format("Craft steps: %d · closure-ready %d · no-closure-needed %d", tonumber(s.craftSteps) or 0, tonumber(s.closureCandidates) or 0, tonumber(s.closureNotRequired) or 0),
        string.format("Waiting upstream: %d · blocked upstream: %d · target-gated: %d", tonumber(s.awaitingUpstream) or 0, tonumber(s.blockedUpstream) or 0, tonumber(s.targetGateBlocked) or 0),
        string.format("Dependency relations inspected: %d", tonumber(s.upstreamRelations) or 0),
        "Policy: every retained/supplemental upstream producer must independently pass current-build recipe, exact materials, live keep-yield and access-source gates before the consumer closure can become provisional.",
    }
    local shown = 0
    for _, row in ipairs(model.steps or {}) do
        if row.closureCandidateEligible or shown < 4 then
            lines[#lines + 1] = string.format("· #%d %s · %s", tonumber(row.routeStepIndex) or 0, tostring(row.recipe or "unknown"), tostring(row.status))
            shown = shown + 1
            if shown >= 7 then break end
        end
    end
    lines[#lines + 1] = "Closure-ready remains staging only: no research step is inserted into the live Planner, shopping plan or execution queue."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ResearchPromotionClosure", ResearchPromotionClosure)
