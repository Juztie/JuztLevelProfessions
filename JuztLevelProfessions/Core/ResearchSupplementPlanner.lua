local _, JLP = ...

-- Expands yield-resolved supplemental intermediate requirements from the
-- research dependency graph into extra craft actions and their upstream raw
-- requirements. This is deliberately analysis-only: research route reagent
-- ratios are useful for candidate analysis, but they do not grant authority to
-- mutate the audited live Planner, shopping quantities or craft execution.
local ResearchSupplementPlanner = {
    contract = "recursive-supplemental-intermediate-analysis-v1",
    authority = "research-reference-only",
    plannerEligible = false,
    cache = {},
    maxDepth = 12,
}

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function roundNearInteger(value)
    value = tonumber(value)
    if not value then return nil, false end
    local rounded = math.floor(value + 0.5)
    if math.abs(value - rounded) <= 0.000001 then return rounded, true end
    return value, false
end

local function addAggregate(map, name, quantity, source)
    local key = normalize(name)
    if key == "" then return nil end
    local row = map[key]
    if not row then
        row = { name = tostring(name), quantity = 0, sources = {} }
        map[key] = row
    end
    row.quantity = row.quantity + math.max(0, tonumber(quantity) or 0)
    if source then row.sources[#row.sources + 1] = source end
    return row
end

local function mapToSortedArray(map)
    local out = {}
    for _, row in pairs(map or {}) do out[#out + 1] = row end
    table.sort(out, function(a, b)
        if tostring(a.name) ~= tostring(b.name) then return tostring(a.name) < tostring(b.name) end
        return (tonumber(a.quantity) or 0) < (tonumber(b.quantity) or 0)
    end)
    return out
end

local function copyMapQuantities(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
        addAggregate(out, row.name, row.quantity, {
            kind = "base-route-external",
            evidence = row.evidence,
        })
    end
    return out
end

local function subtractAggregate(map, name, quantity)
    local key = normalize(name)
    local row = map[key]
    if not row then return 0 end
    local requested = math.max(0, tonumber(quantity) or 0)
    local available = math.max(0, tonumber(row.quantity) or 0)
    local removed = math.min(requested, available)
    row.quantity = available - removed
    if row.quantity <= 0 then map[key] = nil end
    return removed
end

local function appendUniqueAccess(plan, access)
    if not access or not access.name then return end
    local key = tostring(access.kind or "") .. ":" .. normalize(access.name)
    if plan._accessSeen[key] then return end
    plan._accessSeen[key] = true
    plan.accessRequirements[#plan.accessRequirements + 1] = {
        kind = tostring(access.kind or ""),
        name = tostring(access.name),
        evidence = access.evidence or plan.evidence,
        plannerEligible = false,
    }
end

local function addUnresolved(plan, name, quantity, reason, context)
    local row = addAggregate(plan._unresolvedMap, name, quantity, {
        kind = reason,
        context = context,
    })
    row.reason = row.reason or reason
    row.plannerEligible = false
    row.quantityAuthority = false
    return row
end

local function getEarliestDemandBoundary(row)
    local boundary = nil
    for _, demand in ipairs(row and row.demands or {}) do
        local index = tonumber(demand.consumerStepIndex)
        if index and (not boundary or index < boundary) then boundary = index end
    end
    return boundary
end

function ResearchSupplementPlanner:Invalidate()
    self.cache = {}
end

function ResearchSupplementPlanner:_BuildProducerCatalogue(route)
    local evidence = JLP:GetModule("RecipeOutputEvidence")
    local catalogue = {}
    for stepIndex, step in ipairs(route and route.steps or {}) do
        if step.kind == "craft" and step.keep and step.recipe then
            local expectedCrafts = math.max(0, tonumber(step.expectedCrafts) or 0)
            local resolved = evidence and evidence.Resolve and evidence:Resolve(step.recipe) or nil
            local outputPerCraft = resolved and resolved.dependencyQuantityEligible and tonumber(resolved.outputQuantity) or nil
            local producer = {
                recipe = tostring(step.recipe),
                key = normalize(step.recipe),
                stepIndex = stepIndex,
                expectedCrafts = expectedCrafts,
                estimated = step.estimated and true or false,
                evidence = step.evidence,
                outputEvidence = resolved,
                outputPerCraft = outputPerCraft,
                -- Informational estimate only; does not satisfy dependency closure.
                referenceOutputPerCraft = resolved and resolved.planningUsable == true
                    and tonumber(resolved.planningQuantity) or nil,
                referencePlanningOnly = resolved and resolved.planningOnly == true or false,
                yieldResolved = outputPerCraft ~= nil and outputPerCraft > 0,
                sourceRequirement = step.sourceRequirement,
                reagents = {},
                reagentRatioResolved = expectedCrafts > 0,
            }
            if expectedCrafts <= 0 then
                producer.reagentRatioResolved = false
                producer.ratioReason = "zero-expected-crafts"
            end
            for _, requirement in ipairs(step.requirements or {}) do
                local total = math.max(0, tonumber(requirement.quantity) or 0)
                local perCraft = expectedCrafts > 0 and (total / expectedCrafts) or nil
                local normalizedPerCraft, exact = roundNearInteger(perCraft)
                if not exact then
                    producer.reagentRatioResolved = false
                    producer.ratioReason = "non-integral-research-reagent-ratio"
                end
                producer.reagents[#producer.reagents + 1] = {
                    name = tostring(requirement.name or ""),
                    routeQuantity = total,
                    perCraft = normalizedPerCraft,
                    exact = exact,
                    evidence = requirement.evidence or step.evidence,
                }
            end
            catalogue[producer.key] = catalogue[producer.key] or {}
            catalogue[producer.key][#catalogue[producer.key] + 1] = producer
        end
    end
    for _, rows in pairs(catalogue) do
        table.sort(rows, function(a, b) return (a.stepIndex or 0) < (b.stepIndex or 0) end)
    end
    return catalogue
end

function ResearchSupplementPlanner:_FindProducer(catalogue, name, beforeStepIndex)
    local rows = catalogue[normalize(name)]
    if not rows then return nil, "no-route-producer" end
    local selected = nil
    for _, producer in ipairs(rows) do
        if not beforeStepIndex or (tonumber(producer.stepIndex) or 0) < beforeStepIndex then
            selected = producer
        end
    end
    if not selected then return nil, "producer-not-available-before-demand" end
    if not selected.yieldResolved then return selected, "producer-yield-unresolved" end
    if not selected.reagentRatioResolved then return selected, selected.ratioReason or "producer-reagent-ratio-unresolved" end
    return selected, nil
end

local function buildRouteSurplus(graph)
    local pool = {}
    for _, retained in ipairs(graph and graph.retainedOutputs or {}) do
        local node = graph.nodeByID and graph.nodeByID[retained.producedBy]
        local key = normalize(retained.name)
        if key ~= "" and node and retained.quantityAuthority == true then
            pool[key] = pool[key] or {}
            pool[key][#pool[key] + 1] = {
                quantity = math.max(0, tonumber(retained.quantity) or 0),
                stepIndex = tonumber(node.stepIndex) or 0,
                recipe = retained.name,
                source = "route-retained-surplus",
            }
        end
    end
    for _, rows in pairs(pool) do
        table.sort(rows, function(a, b) return (a.stepIndex or 0) < (b.stepIndex or 0) end)
    end
    return pool
end

local function consumeEligiblePool(pool, name, quantity, beforeStepIndex)
    local key = normalize(name)
    local rows = pool[key]
    if not rows then return 0 end
    local remaining = math.max(0, tonumber(quantity) or 0)
    local consumed = 0
    for _, row in ipairs(rows) do
        if remaining <= 0 then break end
        if (not beforeStepIndex) or (tonumber(row.stepIndex) or 0) < beforeStepIndex then
            local available = math.max(0, tonumber(row.quantity) or 0)
            local used = math.min(remaining, available)
            if used > 0 then
                row.quantity = available - used
                remaining = remaining - used
                consumed = consumed + used
            end
        end
    end
    return consumed
end


local function rootConsumerSteps(demands)
    local seen, out = {}, {}
    for _, demand in ipairs(demands or {}) do
        local index = tonumber(demand.consumerStepIndex)
        if index and not seen[index] then
            seen[index] = true
            out[#out + 1] = index
        end
    end
    table.sort(out)
    return out
end

local function attachRootConsumers(action, rows)
    action._requiredBySeen = action._requiredBySeen or {}
    action.requiredByRouteSteps = action.requiredByRouteSteps or {}
    for _, index in ipairs(rows or {}) do
        index = tonumber(index)
        if index and not action._requiredBySeen[index] then
            action._requiredBySeen[index] = true
            action.requiredByRouteSteps[#action.requiredByRouteSteps + 1] = index
        end
    end
end

local function getAction(plan, producer)
    local key = tostring(producer.stepIndex) .. ":" .. producer.key
    local action = plan._actionMap[key]
    if not action then
        action = {
            kind = "supplemental-craft",
            recipe = producer.recipe,
            producerStepIndex = producer.stepIndex,
            extraCrafts = 0,
            requiredOutput = 0,
            producedOutput = 0,
            surplusOutput = 0,
            outputPerCraft = producer.outputPerCraft,
            yieldStatus = producer.outputEvidence and producer.outputEvidence.status or "yield-unresolved",
            yieldSource = producer.outputEvidence and producer.outputEvidence.source or "unknown",
            reagentBasis = "research-route-per-craft-ratio",
            evidence = producer.evidence or plan.evidence,
            analysisOnly = true,
            plannerEligible = false,
            requiredByRouteSteps = {},
            _requiredBySeen = {},
        }
        plan._actionMap[key] = action
        plan.craftActions[#plan.craftActions + 1] = action
    end
    return action
end

function ResearchSupplementPlanner:_Expand(plan, catalogue, itemName, quantity, beforeStepIndex, depth, path, context)
    quantity = math.max(0, tonumber(quantity) or 0)
    if quantity <= 0 then return true end
    depth = tonumber(depth) or 0
    plan.stats.maxDepth = math.max(plan.stats.maxDepth or 0, depth)
    if depth > self.maxDepth then
        addUnresolved(plan, itemName, quantity, "max-recursion-depth", context)
        return false
    end

    local key = normalize(itemName)
    if key == "" then
        addUnresolved(plan, itemName, quantity, "empty-intermediate-name", context)
        return false
    end
    if path[key] then
        addUnresolved(plan, itemName, quantity, "dependency-cycle", context)
        return false
    end

    local remaining = quantity
    local routeUsed = consumeEligiblePool(plan._routeSurplusPool, itemName, remaining, beforeStepIndex)
    if routeUsed > 0 then
        remaining = remaining - routeUsed
        plan.stats.routeSurplusUnitsUsed = plan.stats.routeSurplusUnitsUsed + routeUsed
    end
    local plannedUsed = consumeEligiblePool(plan._plannedSurplusPool, itemName, remaining, beforeStepIndex)
    if plannedUsed > 0 then
        remaining = remaining - plannedUsed
        plan.stats.plannedSurplusUnitsUsed = plan.stats.plannedSurplusUnitsUsed + plannedUsed
    end
    if remaining <= 0 then return true end

    local producer, producerReason = self:_FindProducer(catalogue, itemName, beforeStepIndex)
    if not producer then
        if context and context.rootSupplemental then
            addUnresolved(plan, itemName, remaining, producerReason or "no-route-producer", context)
            return false
        end
        addAggregate(plan._rawMap, itemName, remaining, {
            kind = "supplemental-raw-input",
            parentRecipe = context and context.parentRecipe,
            depth = depth,
            evidence = context and context.evidence or plan.evidence,
        })
        addAggregate(plan._supplementalRawMap, itemName, remaining, {
            kind = "supplemental-raw-input",
            parentRecipe = context and context.parentRecipe,
            depth = depth,
        })
        plan.stats.recursiveRawEdges = plan.stats.recursiveRawEdges + 1
        return true
    end
    if producerReason then
        addUnresolved(plan, itemName, remaining, producerReason, {
            parentRecipe = context and context.parentRecipe,
            producerRecipe = producer.recipe,
            producerStepIndex = producer.stepIndex,
            depth = depth,
        })
        return false
    end

    local outputPerCraft = tonumber(producer.outputPerCraft) or 0
    if outputPerCraft <= 0 then
        addUnresolved(plan, itemName, remaining, "non-positive-output-yield", context)
        return false
    end

    local crafts = math.ceil(remaining / outputPerCraft)
    local produced = crafts * outputPerCraft
    local surplus = produced - remaining
    local action = getAction(plan, producer)
    attachRootConsumers(action, context and context.rootConsumerSteps or nil)
    action.extraCrafts = action.extraCrafts + crafts
    action.requiredOutput = action.requiredOutput + remaining
    action.producedOutput = action.producedOutput + produced
    action.surplusOutput = action.surplusOutput + surplus
    plan.stats.extraCrafts = plan.stats.extraCrafts + crafts
    plan.stats.expandedIntermediateUnits = plan.stats.expandedIntermediateUnits + remaining

    if producer.sourceRequirement then
        appendUniqueAccess(plan, {
            kind = producer.sourceRequirement.kind,
            name = producer.sourceRequirement.name,
            evidence = producer.sourceRequirement.evidence or producer.evidence,
        })
    end

    if surplus > 0 then
        local surplusKey = normalize(itemName)
        plan._plannedSurplusPool[surplusKey] = plan._plannedSurplusPool[surplusKey] or {}
        plan._plannedSurplusPool[surplusKey][#plan._plannedSurplusPool[surplusKey] + 1] = {
            quantity = surplus,
            stepIndex = producer.stepIndex,
            recipe = producer.recipe,
            source = "supplemental-craft-surplus",
        }
        plan.stats.plannedSurplusUnits = plan.stats.plannedSurplusUnits + surplus
    end

    path[key] = true
    for _, reagent in ipairs(producer.reagents or {}) do
        local needed = math.max(0, tonumber(reagent.perCraft) or 0) * crafts
        if needed > 0 then
            plan.stats.recursiveEdges = plan.stats.recursiveEdges + 1
            self:_Expand(plan, catalogue, reagent.name, needed, producer.stepIndex, depth + 1, path, {
                parentRecipe = producer.recipe,
                producerStepIndex = producer.stepIndex,
                evidence = reagent.evidence or producer.evidence,
                rootSupplemental = false,
                rootConsumerSteps = context and context.rootConsumerSteps or nil,
            })
        end
    end
    path[key] = nil
    return true
end

function ResearchSupplementPlanner:Build(professionKey, mode)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"
    local cacheKey = professionKey .. ":" .. mode
    if self.cache[cacheKey] then return self.cache[cacheKey] end

    local research = JLP:GetModule("ProfessionResearch")
    local dependencyGraph = JLP:GetModule("ProfessionDependencyGraph")
    local route = research and research:Get(professionKey, mode)
    local graph = dependencyGraph and dependencyGraph:Build(professionKey, mode)
    if not route or not graph then return nil end

    local plan = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        evidence = graph.evidence,
        authority = self.authority,
        plannerEligible = false,
        transferable = false,
        analysisOnly = true,
        quantityModel = "verified-output-yield+research-route-reagent-ratio",
        graphCandidateState = graph.candidateState,
        sourceGaps = graph.sourceGaps,
        supplementalDemands = graph.supplementalRequirements,
        unresolvedGraphRequirements = graph.unresolvedIntermediateRequirements,
        craftActions = {},
        accessRequirements = {},
        rawRequirements = {},
        supplementalRawRequirements = {},
        unresolvedRequirements = {},
        plannedSurplus = {},
        stats = {
            rootSupplementalKinds = #(graph.supplementalRequirements or {}),
            rootSupplementalUnits = 0,
            extraCraftKinds = 0,
            extraCrafts = 0,
            expandedIntermediateUnits = 0,
            recursiveEdges = 0,
            recursiveRawEdges = 0,
            rawRequirementKinds = 0,
            supplementalRawKinds = 0,
            unresolvedKinds = 0,
            accessGates = 0,
            maxDepth = 0,
            routeSurplusUnitsUsed = 0,
            plannedSurplusUnitsUsed = 0,
            plannedSurplusUnits = 0,
        },
        _actionMap = {},
        _accessSeen = {},
        _unresolvedMap = {},
        _rawMap = copyMapQuantities(graph.externalRequirements),
        _supplementalRawMap = {},
        _routeSurplusPool = buildRouteSurplus(graph),
        _plannedSurplusPool = {},
    }

    -- Resolved supplemental intermediates are removed from the base external
    -- requirement list before being recursively expanded into extra crafts.
    for _, row in ipairs(graph.supplementalRequirements or {}) do
        plan.stats.rootSupplementalUnits = plan.stats.rootSupplementalUnits + math.max(0, tonumber(row.quantity) or 0)
        subtractAggregate(plan._rawMap, row.name, row.quantity)
    end

    local catalogue = self:_BuildProducerCatalogue(route)
    local roots = {}
    for _, row in ipairs(graph.supplementalRequirements or {}) do
        roots[#roots + 1] = {
            name = row.name,
            quantity = row.quantity,
            boundary = getEarliestDemandBoundary(row),
            evidence = row.evidence,
            demands = row.demands,
            rootConsumerSteps = rootConsumerSteps(row.demands),
        }
    end
    table.sort(roots, function(a, b)
        local ab = tonumber(a.boundary) or 999999
        local bb = tonumber(b.boundary) or 999999
        if ab ~= bb then return ab < bb end
        return tostring(a.name) < tostring(b.name)
    end)

    for _, root in ipairs(roots) do
        self:_Expand(plan, catalogue, root.name, root.quantity, root.boundary, 0, {}, {
            rootSupplemental = true,
            evidence = root.evidence,
            demands = root.demands,
            rootConsumerSteps = root.rootConsumerSteps,
        })
    end

    for _, action in ipairs(plan.craftActions) do
        table.sort(action.requiredByRouteSteps or {})
        action._requiredBySeen = nil
    end

    table.sort(plan.craftActions, function(a, b)
        if (a.producerStepIndex or 0) ~= (b.producerStepIndex or 0) then return (a.producerStepIndex or 0) < (b.producerStepIndex or 0) end
        return tostring(a.recipe) < tostring(b.recipe)
    end)
    plan.stats.extraCraftKinds = #plan.craftActions
    plan.accessRequirements = plan.accessRequirements or {}
    table.sort(plan.accessRequirements, function(a, b)
        if tostring(a.kind) ~= tostring(b.kind) then return tostring(a.kind) < tostring(b.kind) end
        return tostring(a.name) < tostring(b.name)
    end)
    plan.stats.accessGates = #plan.accessRequirements

    plan.rawRequirements = mapToSortedArray(plan._rawMap)
    plan.supplementalRawRequirements = mapToSortedArray(plan._supplementalRawMap)
    plan.unresolvedRequirements = mapToSortedArray(plan._unresolvedMap)
    plan.stats.rawRequirementKinds = #plan.rawRequirements
    plan.stats.supplementalRawKinds = #plan.supplementalRawRequirements
    plan.stats.unresolvedKinds = #plan.unresolvedRequirements + #(graph.unresolvedIntermediateRequirements or {})

    for key, rows in pairs(plan._plannedSurplusPool) do
        local total = 0
        local name = key
        for _, row in ipairs(rows) do
            total = total + math.max(0, tonumber(row.quantity) or 0)
            name = row.recipe or name
        end
        if total > 0 then
            plan.plannedSurplus[#plan.plannedSurplus + 1] = {
                name = name,
                quantity = total,
                plannerEligible = false,
            }
        end
    end
    table.sort(plan.plannedSurplus, function(a, b) return tostring(a.name) < tostring(b.name) end)

    if #(graph.sourceGaps or {}) > 0 then
        plan.candidateState = "source-gapped"
    elseif #(graph.unresolvedIntermediateRequirements or {}) > 0 then
        plan.candidateState = "yield-unresolved"
    elseif #plan.unresolvedRequirements > 0 then
        plan.candidateState = "supplement-expansion-unresolved"
    elseif #(graph.supplementalRequirements or {}) > 0 then
        plan.candidateState = "supplemental-expanded-analysis-only"
    else
        plan.candidateState = "no-supplemental-analysis-only"
    end

    -- Remove internal scratch state from the public result so diagnostics and
    -- future consumers cannot accidentally treat mutable planning pools as API.
    plan._actionMap = nil
    plan._accessSeen = nil
    plan._unresolvedMap = nil
    plan._rawMap = nil
    plan._supplementalRawMap = nil
    plan._routeSurplusPool = nil
    plan._plannedSurplusPool = nil

    self.cache[cacheKey] = plan
    return plan
end

function ResearchSupplementPlanner:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then
        errors[#errors + 1] = "profession research catalogue unavailable"
        return errors, warnings
    end
    for professionKey, modes in pairs(root.professions or {}) do
        for _, mode in ipairs({"normal", "aggressive"}) do
            if modes[mode] then
                local plan = self:Build(professionKey, mode)
                if not plan then
                    errors[#errors + 1] = professionKey .. "/" .. mode .. ": supplemental plan unavailable"
                else
                    if plan.plannerEligible ~= false or plan.authority ~= "research-reference-only" or plan.analysisOnly ~= true then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": supplemental authority policy mismatch"
                    end
                    for _, action in ipairs(plan.craftActions or {}) do
                        if (tonumber(action.extraCrafts) or 0) <= 0 or (tonumber(action.outputPerCraft) or 0) <= 0 then
                            errors[#errors + 1] = professionKey .. "/" .. mode .. ": invalid supplemental craft action"
                        end
                        if action.plannerEligible ~= false then
                            errors[#errors + 1] = professionKey .. "/" .. mode .. ": supplemental craft gained Planner authority"
                        end
                    end
                    for _, unresolved in ipairs(plan.unresolvedRequirements or {}) do
                        warnings[#warnings + 1] = string.format(
                            "%s/%s supplemental expansion unresolved: %s x%s (%s)",
                            professionKey, mode, tostring(unresolved.name), tostring(unresolved.quantity), tostring(unresolved.reason)
                        )
                    end
                end
            end
        end
    end
    return errors, warnings
end

function ResearchSupplementPlanner:GetSummary(professionKey, mode)
    professionKey = professionKey and tostring(professionKey):upper() or "ENGINEERING"
    mode = mode == "aggressive" and "aggressive" or "normal"
    local plan = self:Build(professionKey, mode)
    if not plan then return "Research supplemental planner unavailable." end

    local lines = {
        string.format("Research supplemental plan: %s / %s", professionKey, mode),
        string.format("State: %s · analysis only · Planner authority disabled", tostring(plan.candidateState)),
        string.format(
            "Supplemental: %d kinds / %d units -> %d extra craft kinds / %d crafts",
            tonumber(plan.stats.rootSupplementalKinds) or 0,
            tonumber(plan.stats.rootSupplementalUnits) or 0,
            tonumber(plan.stats.extraCraftKinds) or 0,
            tonumber(plan.stats.extraCrafts) or 0
        ),
        string.format(
            "Expansion: %d recursive edges · max depth %d · route surplus used %d · planned surplus %d",
            tonumber(plan.stats.recursiveEdges) or 0,
            tonumber(plan.stats.maxDepth) or 0,
            tonumber(plan.stats.routeSurplusUnitsUsed) or 0,
            tonumber(plan.stats.plannedSurplusUnits) or 0
        ),
        string.format(
            "Net external: %d kinds · supplemental raw: %d kinds · unresolved: %d · access gates: %d",
            tonumber(plan.stats.rawRequirementKinds) or 0,
            tonumber(plan.stats.supplementalRawKinds) or 0,
            tonumber(plan.stats.unresolvedKinds) or 0,
            tonumber(plan.stats.accessGates) or 0
        ),
    }

    for index, action in ipairs(plan.craftActions or {}) do
        if index > 5 then break end
        lines[#lines + 1] = string.format(
            "· +%d %s crafts -> %d output (yield %s, surplus %d)",
            tonumber(action.extraCrafts) or 0,
            tostring(action.recipe),
            tonumber(action.producedOutput) or 0,
            tostring(action.outputPerCraft),
            tonumber(action.surplusOutput) or 0
        )
    end
    if #(plan.craftActions or {}) > 5 then
        lines[#lines + 1] = string.format("· +%d more supplemental craft actions", #(plan.craftActions or {}) - 5)
    end
    for index, row in ipairs(plan.supplementalRawRequirements or {}) do
        if index > 4 then break end
        lines[#lines + 1] = string.format("· supplemental raw: %s x%s", tostring(row.name), tostring(row.quantity))
    end
    if #plan.unresolvedRequirements > 0 then
        local row = plan.unresolvedRequirements[1]
        lines[#lines + 1] = string.format("Unresolved example: %s x%s · %s", tostring(row.name), tostring(row.quantity), tostring(row.reason))
    end
    if #(plan.sourceGaps or {}) > 0 then
        lines[#lines + 1] = string.format("Source gaps preserved: %d", #(plan.sourceGaps or {}))
    end
    lines[#lines + 1] = "Recursive quantities are candidate analysis only; audited Planner, shopping and execution quantities are unchanged."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ResearchSupplementPlanner", ResearchSupplementPlanner)
