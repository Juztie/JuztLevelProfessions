local _, JLP = ...

-- Builds an analysis-only dependency graph from the user-research profession
-- routes. The graph deliberately does not grant Planner authority: source
-- routes can contain gaps, estimated crafts and implicit/underspecified output
-- yields. Those limitations are surfaced instead of guessed away.
local ProfessionDependencyGraph = {
    contract = "yield-evidence-aware-research-dependency-graph-v4",
    authority = "research-reference-only",
    plannerEligible = false,
    cache = {},
}

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

local function addAggregate(map, name, quantity)
    local key = normalize(name)
    if key == "" then return nil end
    local row = map[key]
    if not row then
        row = { name = tostring(name), quantity = 0 }
        map[key] = row
    end
    row.quantity = row.quantity + math.max(0, tonumber(quantity) or 0)
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

local function nextNodeID(graph, prefix)
    graph._nodeSequence = (graph._nodeSequence or 0) + 1
    return string.format("%s:%d", prefix or "node", graph._nodeSequence)
end

local function addNode(graph, node)
    graph.nodes[#graph.nodes + 1] = node
    graph.nodeByID[node.id] = node
    return node
end

local function addEdge(graph, edge)
    graph.edges[#graph.edges + 1] = edge
    return edge
end

function ProfessionDependencyGraph:Invalidate()
    self.cache = {}
end

function ProfessionDependencyGraph:Build(professionKey, mode)
    professionKey = tostring(professionKey or ""):upper()
    mode = mode == "aggressive" and "aggressive" or "normal"
    local cacheKey = professionKey .. ":" .. mode
    if self.cache[cacheKey] then return self.cache[cacheKey] end

    local research = JLP:GetModule("ProfessionResearch")
    local route = research and research:Get(professionKey, mode)
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not route or not root then return nil end

    local graph = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        evidence = route.evidence or root.evidence,
        authority = self.authority,
        plannerEligible = false,
        transferable = false,
        analysisOnly = true,
        quantityModel = "qualified-dependency-quantities-separate-from-planning-references",
        nodes = {},
        nodeByID = {},
        edges = {},
        craftNodes = {},
        accessRequirements = {},
        intermediateDependencies = {},
        externalRequirements = {},
        retainedOutputs = {},
        planningReferenceOutputs = {}, -- informational only; never consumed as dependency inventory
        supplementalRequirements = {},
        unresolvedIntermediateRequirements = {},
        deficits = {}, -- compatibility alias populated from unresolved intermediate requirements
        sourceGaps = {},
        stats = {
            craftSteps = 0,
            trainSteps = 0,
            keepProducers = 0,
            internalEdges = 0,
            accessGates = 0,
            externalRequirementKinds = 0,
            deficitKinds = 0,
            supplementalKinds = 0,
            unresolvedYieldKinds = 0,
            retainedKinds = 0,
            yieldResolvedProducers = 0,
            yieldUnresolvedProducers = 0,
            planningReferenceProducers = 0,
            liveYieldProducers = 0,
            externalYieldProducers = 0,
        },
    }

    for _, gap in ipairs(route.stats and route.stats.gaps or {}) do
        graph.sourceGaps[#graph.sourceGaps + 1] = {
            fromSkill = tonumber(gap.fromSkill) or 0,
            toSkill = tonumber(gap.toSkill) or 0,
            evidence = gap.evidence or graph.evidence,
        }
    end

    local producers = {}
    local external = {}
    local supplemental = {}
    local unresolved = {}
    local outputEvidence = JLP:GetModule("RecipeOutputEvidence")

    for stepIndex, step in ipairs(route.steps or {}) do
        if step.kind == "train" then
            graph.stats.trainSteps = graph.stats.trainSteps + 1
        elseif step.kind == "craft" then
            graph.stats.craftSteps = graph.stats.craftSteps + 1
            local resolvedYield = outputEvidence and outputEvidence.Resolve and outputEvidence:Resolve(step.recipe) or nil
            local craft = addNode(graph, {
                id = nextNodeID(graph, "craft"),
                kind = "craft",
                stepIndex = stepIndex,
                recipe = step.recipe,
                skillMin = tonumber(step.skillMin),
                skillTarget = tonumber(step.skillTarget),
                expectedCrafts = tonumber(step.expectedCrafts) or 0,
                estimated = step.estimated and true or false,
                keep = step.keep and true or false,
                evidence = step.evidence or graph.evidence,
                outputYield = resolvedYield,
                outputPerCraft = resolvedYield and resolvedYield.dependencyQuantityEligible and tonumber(resolvedYield.outputQuantity) or nil,
            })
            graph.craftNodes[#graph.craftNodes + 1] = craft

            if step.sourceRequirement then
                local accessKind = tostring(step.sourceRequirement.kind or ""):lower()
                local access = addNode(graph, {
                    id = nextNodeID(graph, "access"),
                    kind = "access",
                    accessKind = accessKind,
                    name = step.sourceRequirement.name,
                    recognized = VALID_ACCESS_KINDS[accessKind] and true or false,
                    evidence = step.sourceRequirement.evidence or graph.evidence,
                })
                graph.accessRequirements[#graph.accessRequirements + 1] = access
                graph.stats.accessGates = graph.stats.accessGates + 1
                addEdge(graph, {
                    kind = "access-gate",
                    from = access.id,
                    to = craft.id,
                    accessKind = accessKind,
                    name = access.name,
                    evidence = access.evidence,
                })
            end

            for _, requirement in ipairs(step.requirements or {}) do
                local name = tostring(requirement.name or "")
                local required = math.max(0, tonumber(requirement.quantity) or 0)
                local key = normalize(name)
                local producerList = producers[key]
                local residual = required

                if producerList and required > 0 then
                    -- Consume the newest retained batch first. Multiple producer
                    -- batches are supported, but only already-completed keep
                    -- steps may satisfy a later dependency.
                    for producerIndex = #producerList, 1, -1 do
                        local producer = producerList[producerIndex]
                        local available = math.max(0, tonumber(producer.remaining) or 0)
                        local internal = math.min(residual, available)
                        if internal > 0 then
                            producer.remaining = available - internal
                            producer.consumed = (producer.consumed or 0) + internal
                            residual = residual - internal
                            graph.stats.internalEdges = graph.stats.internalEdges + 1
                            local dep = {
                                kind = "intermediate",
                                item = name,
                                quantity = internal,
                                requiredQuantity = required,
                                producer = producer.node.id,
                                consumer = craft.id,
                                producerRecipe = producer.node.recipe,
                                consumerRecipe = craft.recipe,
                                evidence = graph.evidence,
                                quantityAuthority = producer.yieldResolved and true or false,
                                yieldStatus = producer.yieldStatus,
                                outputPerCraft = producer.outputPerCraft,
                            }
                            graph.intermediateDependencies[#graph.intermediateDependencies + 1] = dep
                            addEdge(graph, {
                                kind = "intermediate",
                                from = producer.node.id,
                                to = craft.id,
                                item = name,
                                quantity = internal,
                                evidence = graph.evidence,
                                quantityAuthority = producer.yieldResolved and true or false,
                                yieldStatus = producer.yieldStatus,
                                outputPerCraft = producer.outputPerCraft,
                            })
                            if residual <= 0 then break end
                        end
                    end
                end

                if residual > 0 then
                    addAggregate(external, name, residual)
                    if producerList and #producerList > 0 then
                        local allResolved = true
                        for _, producer in ipairs(producerList) do
                            if not producer.yieldResolved then allResolved = false break end
                        end
                        if allResolved then
                            local row = addAggregate(supplemental, name, residual)
                            row.reason = "verified-yield-supplemental-intermediate"
                            row.evidence = graph.evidence
                            row.quantityAuthority = true
                            row.demands = row.demands or {}
                            row.demands[#row.demands + 1] = {
                                quantity = residual,
                                consumerRecipe = craft.recipe,
                                consumerStepIndex = stepIndex,
                                consumerNode = craft.id,
                                evidence = graph.evidence,
                            }
                        else
                            local row = addAggregate(unresolved, name, residual)
                            row.reason = "keep-output-insufficient-under-unresolved-yield"
                            row.evidence = graph.evidence
                            row.quantityAuthority = false
                            row.demands = row.demands or {}
                            row.demands[#row.demands + 1] = {
                                quantity = residual,
                                consumerRecipe = craft.recipe,
                                consumerStepIndex = stepIndex,
                                consumerNode = craft.id,
                                evidence = graph.evidence,
                            }
                        end
                    end
                end
            end

            -- Register a keep producer only after processing the craft's own
            -- requirements, preventing a step from satisfying itself.
            if step.keep and step.recipe then
                local key = normalize(step.recipe)
                local plannedCrafts = math.max(0, tonumber(step.expectedCrafts) or 0)
                local yieldResolution = craft.outputYield
                local eligibleYield = yieldResolution and yieldResolution.dependencyQuantityEligible == true
                    and tonumber(yieldResolution.outputQuantity) or nil
                local yieldResolved = eligibleYield ~= nil and eligibleYield > 0
                -- Only a qualified yield may enter the consumable producer pool.
                -- Historical/nominal estimates belong in a separate read-only view.
                local outputPerCraft = yieldResolved and eligibleYield or nil
                local plannedOutput = yieldResolved and (plannedCrafts * outputPerCraft) or 0
                local referencePerCraft = yieldResolution and yieldResolution.planningUsable == true
                    and tonumber(yieldResolution.planningQuantity) or nil
                if referencePerCraft and referencePerCraft <= 0 then referencePerCraft = nil end
                if not yieldResolved and referencePerCraft then
                    graph.planningReferenceOutputs[#graph.planningReferenceOutputs + 1] = {
                        name = step.recipe, quantity = plannedCrafts * referencePerCraft,
                        producedBy = craft.id, outputPerCraft = referencePerCraft,
                        yieldStatus = yieldResolution.status, yieldSource = yieldResolution.source,
                        quantityAuthority = false, plannerEligible = false,
                        readOnly = true, planningOnly = true,
                    }
                    graph.stats.planningReferenceProducers = graph.stats.planningReferenceProducers + 1
                end
                local producer = {
                    node = craft,
                    plannedCrafts = plannedCrafts,
                    plannedOutput = plannedOutput,
                    outputPerCraft = outputPerCraft,
                    yieldResolved = yieldResolved and true or false,
                    yieldStatus = yieldResolution and yieldResolution.status or "yield-unresolved",
                    yieldSource = yieldResolution and yieldResolution.source or "nominal-fallback",
                    remaining = plannedOutput,
                    consumed = 0,
                }
                producers[key] = producers[key] or {}
                producers[key][#producers[key] + 1] = producer
                graph.stats.keepProducers = graph.stats.keepProducers + 1
                if producer.yieldResolved then
                    graph.stats.yieldResolvedProducers = graph.stats.yieldResolvedProducers + 1
                    if producer.yieldSource == "live-current-build" or producer.yieldSource == "live+external" then
                        graph.stats.liveYieldProducers = graph.stats.liveYieldProducers + 1
                    else
                        graph.stats.externalYieldProducers = graph.stats.externalYieldProducers + 1
                    end
                else
                    graph.stats.yieldUnresolvedProducers = graph.stats.yieldUnresolvedProducers + 1
                end
            end
        end
    end

    graph.externalRequirements = mapToSortedArray(external)
    graph.supplementalRequirements = mapToSortedArray(supplemental)
    graph.unresolvedIntermediateRequirements = mapToSortedArray(unresolved)
    graph.deficits = graph.unresolvedIntermediateRequirements
    graph.stats.externalRequirementKinds = #graph.externalRequirements
    graph.stats.supplementalKinds = #graph.supplementalRequirements
    graph.stats.unresolvedYieldKinds = #graph.unresolvedIntermediateRequirements
    graph.stats.deficitKinds = #graph.deficits

    for _, list in pairs(producers) do
        for _, producer in ipairs(list) do
            if (producer.remaining or 0) > 0 then
                graph.retainedOutputs[#graph.retainedOutputs + 1] = {
                    name = producer.node.recipe,
                    quantity = producer.remaining,
                    producedBy = producer.node.id,
                    evidence = graph.evidence,
                    quantityAuthority = producer.yieldResolved and true or false,
                    outputPerCraft = producer.outputPerCraft,
                    yieldStatus = producer.yieldStatus,
                    yieldSource = producer.yieldSource,
                }
            end
        end
    end
    table.sort(graph.retainedOutputs, function(a, b) return tostring(a.name) < tostring(b.name) end)
    graph.stats.retainedKinds = #graph.retainedOutputs

    if #graph.sourceGaps > 0 then
        graph.candidateState = "source-gapped"
    elseif graph.stats.yieldUnresolvedProducers > 0 or #graph.unresolvedIntermediateRequirements > 0 then
        graph.candidateState = "yield-unresolved"
    elseif #graph.supplementalRequirements > 0 then
        graph.candidateState = "yield-resolved-with-supplemental-intermediates"
    else
        graph.candidateState = "yield-resolved-analysis-only"
    end

    self.cache[cacheKey] = graph
    return graph
end

function ProfessionDependencyGraph:Validate()
    local errors, warnings = {}, {}
    local research = JLP:GetModule("ProfessionResearch")
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not research or not root then
        errors[#errors + 1] = "profession research unavailable"
        return errors, warnings
    end

    for professionKey, modes in pairs(root.professions or {}) do
        for _, mode in ipairs({"normal", "aggressive"}) do
            if modes[mode] then
                local graph = self:Build(professionKey, mode)
                if not graph then
                    errors[#errors + 1] = professionKey .. "/" .. mode .. ": graph unavailable"
                else
                    if graph.plannerEligible ~= false or graph.authority ~= "research-reference-only" then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": authority policy mismatch"
                    end
                    for _, access in ipairs(graph.accessRequirements or {}) do
                        if not access.recognized then
                            errors[#errors + 1] = professionKey .. "/" .. mode .. ": unknown access kind " .. tostring(access.accessKind)
                        end
                    end
                    for _, row in ipairs(graph.unresolvedIntermediateRequirements or {}) do
                        warnings[#warnings + 1] = string.format(
                            "%s/%s unresolved intermediate yield: %s x%d",
                            professionKey, mode, tostring(row.name), tonumber(row.quantity) or 0
                        )
                    end
                    for _, row in ipairs(graph.supplementalRequirements or {}) do
                        warnings[#warnings + 1] = string.format(
                            "%s/%s verified-yield supplemental intermediate: %s x%d",
                            professionKey, mode, tostring(row.name), tonumber(row.quantity) or 0
                        )
                    end
                    for _, gap in ipairs(graph.sourceGaps or {}) do
                        warnings[#warnings + 1] = string.format(
                            "%s/%s source gap %d-%d",
                            professionKey, mode, tonumber(gap.fromSkill) or 0, tonumber(gap.toSkill) or 0
                        )
                    end
                end
            end
        end
    end
    return errors, warnings
end

function ProfessionDependencyGraph:GetSummary(professionKey, mode)
    professionKey = professionKey and tostring(professionKey):upper() or "ENGINEERING"
    mode = mode == "aggressive" and "aggressive" or "normal"
    local graph = self:Build(professionKey, mode)
    if not graph then return "Profession dependency graph unavailable." end

    local lines = {
        string.format("Research dependencies: %s / %s", professionKey, mode),
        string.format("State: %s · analysis only · Planner authority disabled", tostring(graph.candidateState)),
        string.format(
            "Graph: %d crafts · %d keep producers · %d internal links · %d access gates",
            tonumber(graph.stats.craftSteps) or 0,
            tonumber(graph.stats.keepProducers) or 0,
            tonumber(graph.stats.internalEdges) or 0,
            tonumber(graph.stats.accessGates) or 0
        ),
        string.format(
            "Yield evidence: %d resolved · %d unresolved · %d live · %d external",
            tonumber(graph.stats.yieldResolvedProducers) or 0,
            tonumber(graph.stats.yieldUnresolvedProducers) or 0,
            tonumber(graph.stats.liveYieldProducers) or 0,
            tonumber(graph.stats.externalYieldProducers) or 0
        ),
        string.format(
            "External kinds: %d · supplemental intermediates: %d · unresolved yields: %d · retained outputs: %d · source gaps: %d",
            tonumber(graph.stats.externalRequirementKinds) or 0,
            tonumber(graph.stats.supplementalKinds) or 0,
            tonumber(graph.stats.unresolvedYieldKinds) or 0,
            tonumber(graph.stats.retainedKinds) or 0,
            #(graph.sourceGaps or {})
        ),
    }

    local maxRows = 4
    for index, dep in ipairs(graph.intermediateDependencies or {}) do
        if index > maxRows then break end
        lines[#lines + 1] = string.format(
            "· %s -> %s · %s x%d",
            tostring(dep.producerRecipe), tostring(dep.consumerRecipe), tostring(dep.item), tonumber(dep.quantity) or 0
        )
    end
    if #(graph.intermediateDependencies or {}) > maxRows then
        lines[#lines + 1] = string.format("· +%d more intermediate links", #(graph.intermediateDependencies or {}) - maxRows)
    end

    for index, access in ipairs(graph.accessRequirements or {}) do
        if index > 3 then break end
        lines[#lines + 1] = string.format("· %s required: %s", tostring(access.accessKind), tostring(access.name))
    end
    if #(graph.accessRequirements or {}) > 3 then
        lines[#lines + 1] = string.format("· +%d more access gates", #(graph.accessRequirements or {}) - 3)
    end

    if #graph.supplementalRequirements > 0 then
        local row = graph.supplementalRequirements[1]
        lines[#lines + 1] = string.format(
            "Supplemental example: %s x%d beyond route-produced keep output",
            tostring(row.name), tonumber(row.quantity) or 0
        )
    end
    if #graph.unresolvedIntermediateRequirements > 0 then
        local row = graph.unresolvedIntermediateRequirements[1]
        lines[#lines + 1] = string.format(
            "Unresolved yield example: %s x%d (no unqualified quantity credited)",
            tostring(row.name), tonumber(row.quantity) or 0
        )
    end
    lines[#lines + 1] = string.format("Read-only historical yield estimates: %d (excluded from dependency inventory)", tonumber(graph.stats.planningReferenceProducers) or 0)
    lines[#lines + 1] = "Only qualified positive output yields reduce downstream dependency demand; historical quantities remain informational. Planner and execution authority are disabled."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ProfessionDependencyGraph", ProfessionDependencyGraph)
