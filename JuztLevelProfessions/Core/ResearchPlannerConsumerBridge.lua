local _, JLP = ...

-- Atomic, read-only consumer projection for research-derived Planner authority.
-- A snapshot is rebuilt from ResearchRouteAuthorityBridge on every request and
-- is never persisted. This keeps Planner/requirements/readiness/action/guide
-- consumers on one authority evaluation and gives callers an explicit token
-- they can revalidate before reusing a previously rendered snapshot.
local ResearchPlannerConsumerBridge = {
    contract = "revocable-read-only-planner-consumer-bridge-v1",
    snapshotContract = "research-planner-consumer-snapshot-v1",
    authority = "current-build-revalidated-consumer-read-authority",
    readOnly = true,
    executionEligible = false,
    transferableToExecution = false,
}

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function currentSessionReceipt()
    local runtime=JLP:GetModule("RuntimeCompatibility")
    return runtime and type(runtime.GetSessionReceipt)=="function"
        and runtime:GetSessionReceipt() or nil
end

local function authoritySource(professionKey)
    professionKey = tostring(professionKey or ""):upper()
    if professionKey == "TAILORING" then
        return JLP:GetModule("ProductionTailoringAuthorityAdapter")
    end
    if professionKey == "ENCHANTING" then
        return JLP:GetModule("ProductionEnchantingAuthorityAdapter")
    end
    return JLP:GetModule("ResearchRouteAuthorityBridge")
end

local function authorityModelActive(source, model)
    if source and source.IsAuthorityActive then return source:IsAuthorityActive(model) end
    return type(model) == "table"
        and model.state == "controlled-route-authority-active"
        and model.routeAuthorityEnabled == true
        and model.plannerEligible == true
end

local function stateHash(parts)
    local value = table.concat(parts or {}, "\31")
    local hash = 5381
    for index = 1, #value do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return string.format("%08x", hash)
end

local function addState(parts, prefix, row, fields)
    parts[#parts + 1] = tostring(prefix or "")
    for _, field in ipairs(fields or {}) do
        parts[#parts + 1] = tostring(row and row[field] or "")
    end
end

local function consumerStateFingerprint(model)
    local parts = {}
    local plan = model and model.plan or nil
    local step = plan and plan.step or nil
    addState(parts, "plan", plan, {"actionKind", "status", "plannerEligible", "executionEligible"})
    addState(parts, "step", step, {"routeIndex", "recipe", "recipeID", "skillTarget", "remainingCrafts", "staticRemainingCrafts"})
    parts[#parts + 1] = "step.rawRecipeID"
    parts[#parts + 1] = tostring(step and step.rawStep and step.rawStep.recipeID or "")
    local dataset = model and model.dataset or nil
    addState(parts, "dataset", dataset, {"contract", "authority", "currentBuild", "sourceBuild", "datasetStatus"})
    local requirements = model and model.requirementPlan or nil
    addState(parts, "requirements", requirements, {"materialTypes", "totalRequired", "totalOwned", "totalMissing"})
    for index, row in ipairs(requirements and requirements.rows or {}) do
        addState(parts, "requirement:" .. index, row, {"itemID", "name", "required", "bags", "bank", "owned", "missing", "source"})
    end
    local readiness = model and model.readiness or nil
    addState(parts, "readiness", readiness, {"status", "blocker", "recipeKnowledge", "immediateBags", "preparedStorage", "craftableNow", "craftablePrepared"})
    local queue = model and model.actionQueue or nil
    addState(parts, "queue", queue, {"currentIndex", "status", "readOnly", "executionEligible"})
    for index, action in ipairs(queue and queue.actions or {}) do
        addState(parts, "action:" .. index, action, {"kind", "itemID", "itemName", "quantity", "source", "text", "detail", "executionEligible"})
    end
    local guide = model and model.guideSteps or nil
    addState(parts, "guide", guide, {"status", "currentIndex", "totalSteps", "routeAuthorityEnabled", "executionEligible"})
    local current = guide and guide.current or nil
    addState(parts, "guide-current", current, {"routeIndex", "recipe", "skillTarget", "status"})
    local target = model and model.targetFoundation or nil
    local proof = model and model.targetProof or nil
    addState(parts, "target", target, {"targetGUID", "targetItemID", "targetValidationSource", "targetLocationKey", "targetProofFingerprint", "targetFoundationReady"})
    addState(parts, "target-proof", proof, {"contract", "fingerprint", "recipeID", "targetGUID", "targetItemID", "targetValidationSource", "targetLocationKey", "currentBuild"})
    return stateHash(parts)
end

local function snapshotToken(model)
    local plan = model and model.plan or nil
    local step = plan and plan.step or nil
    local dataset = model and model.dataset or nil
    local fingerprint = consumerStateFingerprint(model)
    return table.concat({
        tostring(model and model.clientSessionToken or ""),
        tostring(model and model.professionKey or ""),
        tostring(model and model.mode or ""),
        tostring(model and model.currentBuild or ""),
        tostring(model and model.selectedSegment or ""),
        tostring(dataset and (dataset.segmentID or dataset.contract) or ""),
        tostring(step and step.routeIndex or ""),
        tostring(step and step.recipe or ""),
        tostring(step and (step.recipeID or (step.rawStep and step.rawStep.recipeID)) or ""),
        tostring(step and step.skillTarget or ""),
        fingerprint,
    }, "|"), fingerprint
end

local function decorateRequirement(source)
    if type(source) ~= "table" then return nil end
    local out = shallowCopy(source)
    out.readOnly = true
    out.executionEligible = false
    out.consumerAuthority = ResearchPlannerConsumerBridge.authority
    return out
end

local function decorateReadiness(source)
    if type(source) ~= "table" then return nil end
    local out = shallowCopy(source)
    out.readOnly = true
    out.executionEligible = false
    out.consumerAuthority = ResearchPlannerConsumerBridge.authority
    return out
end

local function decorateActionQueue(source)
    if type(source) ~= "table" then return nil end
    local out = shallowCopy(source)
    out.actions = {}
    for index, action in ipairs(source.actions or {}) do
        local row = shallowCopy(action)
        row.index = index
        row.readOnly = true
        row.executionEligible = false
        row.consumerAuthority = ResearchPlannerConsumerBridge.authority
        out.actions[index] = row
    end
    out.readOnly = true
    out.executionEligible = false
    out.consumerAuthority = ResearchPlannerConsumerBridge.authority
    return out
end

local function decorateGuide(source)
    if type(source) ~= "table" then return nil end
    local out = shallowCopy(source)
    out.readOnly = true
    out.executionEligible = false
    out.consumerAuthority = ResearchPlannerConsumerBridge.authority
    return out
end

local function consumerSurfaceState(plan, requirements, readiness, queue, guide)
    local surfaces = {
        planner = plan and plan.routeAuthorityEnabled == true and plan.plannerEligible == true and plan.executionEligible == false,
        requirements = requirements ~= nil,
        readiness = readiness ~= nil,
        actions = queue ~= nil,
        guide = guide ~= nil and guide.status ~= "unavailable",
    }
    local total, passed = 0, 0
    for _, key in ipairs({"planner", "requirements", "readiness", "actions", "guide"}) do
        total = total + 1
        if surfaces[key] then passed = passed + 1 end
    end
    return surfaces, passed, total
end

function ResearchPlannerConsumerBridge:IsSupported(professionKey)
    local source = authoritySource(professionKey)
    return source and source.IsSupported and source:IsSupported(professionKey) or false
end

function ResearchPlannerConsumerBridge:GetAuthoritySource(professionKey)
    return authoritySource(professionKey)
end

function ResearchPlannerConsumerBridge:Build(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    options = type(options) == "table" and options or {}
    local routeAuthority = authoritySource(professionKey)
    local startSessionToken = currentSessionReceipt()
    mode = normalizeMode(mode or (routeAuthority and routeAuthority.GetConfiguredMode and routeAuthority:GetConfiguredMode()) or "normal")

    local model = {
        contract = self.contract,
        snapshotContract = self.snapshotContract,
        professionKey = professionKey,
        mode = mode,
        currentBuild = currentBuild(),
        authority = self.authority,
        sourceAuthority = routeAuthority and routeAuthority.authority or nil,
        sourceAuthorityState = "unavailable",
        targetBound = false,
        targetFoundation = nil,
        targetProof = nil,
        targetProofFingerprint = nil,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        routeAuthorityEnabled = false,
        consumerAuthorityEnabled = false,
        uiExecutionControlsEnabled = false,
        snapshotPersisted = false,
        revocationPolicy = "rebuild-before-consume",
        stats = { passedConsumers=0, totalConsumers=5 },
    }

    if not routeAuthority then
        model.state = "consumer-authority-dependency-unavailable"
        model.blockedReason = "route-authority-bridge-unavailable"
        return model
    end
    if not routeAuthority.IsSupported or (not routeAuthority:IsSupported(professionKey) and not options.allowHarness) then
        model.state = "consumer-authority-unsupported-profession"
        model.blockedReason = "unsupported-profession"
        return model
    end

    local authorityModel = routeAuthority:Build(professionKey, mode, options)
    model.source = authorityModel
    model.sourceAuthorityState = authorityModel and authorityModel.state or "unavailable"
    model.currentBuild = authorityModel and authorityModel.currentBuild or model.currentBuild
    model.targetBound = authorityModel and authorityModel.targetBound == true or false
    model.targetFoundation = authorityModel and authorityModel.targetFoundation or nil
    model.targetProof = authorityModel and authorityModel.targetProof or nil
    model.targetProofFingerprint = authorityModel and authorityModel.targetProofFingerprint or nil

    if not authorityModelActive(routeAuthority, authorityModel)
        or authorityModel.routeAuthorityEnabled ~= true or authorityModel.plannerEligible ~= true then
        model.state = "consumer-authority-revoked"
        model.blockedReason = authorityModel and authorityModel.state or "route-authority-unavailable"
        return model
    end

    local dataset = authorityModel.dataset
    local live = authorityModel.live
    local plan = live and live.plan or nil
    local requirements = live and live.requirementPlan or nil
    local readiness = live and live.readiness or nil
    local queue = live and live.actionQueue or nil

    local authorityShapeReady = dataset and dataset.routeAuthorityEnabled == true
        and dataset.plannerEligible == true and dataset.executionEligible == false
        and plan and plan.routeAuthorityEnabled == true and plan.plannerEligible == true
        and plan.executionEligible == false
        and (plan.actionKind ~= "craft" or (plan.step and plan.step.executionEligible == false))
    if not authorityShapeReady then
        model.state = "blocked-consumer-authority-shape"
        model.blockedReason = "planner-read-authority-shape"
        return model
    end

    local guideSteps = JLP:GetModule("GuideSteps")
    local guide = guideSteps and guideSteps.Build and guideSteps:Build(professionKey, plan, dataset) or nil
    requirements = decorateRequirement(requirements)
    readiness = decorateReadiness(readiness)
    queue = decorateActionQueue(queue)
    guide = decorateGuide(guide)

    local surfaces, passed, total = consumerSurfaceState(plan, requirements, readiness, queue, guide)
    model.consumerSurfaces = surfaces
    model.stats.passedConsumers = passed
    model.stats.totalConsumers = total
    model.selectedSegment = authorityModel.selectedSegment or (plan and plan.step and plan.step.routeIndex)
    model.dataset = dataset
    model.plan = plan
    model.requirementPlan = requirements
    model.readiness = readiness
    model.actionQueue = queue
    model.guideSteps = guide

    if passed ~= total then
        model.state = "blocked-consumer-surface-gap"
        model.blockedReason = "consumer-surface-incomplete"
        return model
    end

    -- Read-only reference surfaces remain available without live identity,
    -- but are NOT entitled to native execution. A changed session during
    -- assembly cannot become a current-consumer receipt.
    local endSessionToken=currentSessionReceipt()
    model.clientSessionToken=(startSessionToken and startSessionToken==endSessionToken)
        and startSessionToken or nil
    model.clientSessionVerified=model.clientSessionToken~=nil
    model.state = "consumer-authority-active"
    model.plannerEligible = true
    model.routeAuthorityEnabled = true
    model.consumerAuthorityEnabled = true
    model.snapshotToken, model.stateFingerprint = snapshotToken(model)
    model.snapshot = {
        contract = self.snapshotContract,
        token = model.snapshotToken,
        stateFingerprint = model.stateFingerprint,
        professionKey = professionKey,
        mode = mode,
        currentBuild = model.currentBuild,
        clientSessionToken = model.clientSessionToken,
        clientSessionVerified = model.clientSessionVerified,
        selectedSegment = model.selectedSegment,
        segmentID = dataset.segmentID or dataset.contract,
        recipe = plan.step and plan.step.recipe or nil,
        recipeID = plan.step and (plan.step.recipeID or (plan.step.rawStep and plan.step.rawStep.recipeID)) or nil,
        routeIndex = plan.step and plan.step.routeIndex or nil,
        skillTarget = plan.step and plan.step.skillTarget or nil,
        authority = self.authority,
        sourceAuthority = model.sourceAuthority,
        sourceAuthorityContract = authorityModel and authorityModel.contract or nil,
        sourceDatasetContract = dataset and dataset.contract or nil,
        targetBoundContract = authorityModel and authorityModel.targetBoundContract or nil,
        targetBound = model.targetBound == true,
        targetProofContract = model.targetProof and model.targetProof.contract or nil,
        targetProofFingerprint = model.targetProofFingerprint,
        targetGUID = model.targetFoundation and model.targetFoundation.targetGUID or nil,
        targetItemID = model.targetFoundation and model.targetFoundation.targetItemID or nil,
        targetValidationSource = model.targetFoundation and model.targetFoundation.targetValidationSource or nil,
        targetLocationKey = model.targetFoundation and model.targetFoundation.targetLocationKey or nil,
        targetLocation = model.targetFoundation and model.targetFoundation.targetLocation or nil,
        readOnly = true,
        executionEligible = false,
        persisted = false,
    }
    return model
end

function ResearchPlannerConsumerBridge:GetSnapshot(professionKey, mode, options)
    local model = self:Build(professionKey, mode, options)
    if not model or model.consumerAuthorityEnabled ~= true then
        return nil, model and model.state or "consumer-bridge-unavailable", model
    end
    return model, model.state
end

function ResearchPlannerConsumerBridge:ValidateSnapshot(snapshot, professionKey, mode, options)
    if type(snapshot) ~= "table" or snapshot.contract ~= self.snapshotContract or not snapshot.token then
        return false, "invalid-consumer-snapshot", nil
    end
    professionKey = tostring(professionKey or snapshot.professionKey or ""):upper()
    if professionKey == "" or professionKey ~= tostring(snapshot.professionKey or ""):upper() then
        return false, "consumer-snapshot-profession-mismatch", nil
    end
    local current = self:Build(professionKey, mode or snapshot.mode, options)
    if not current or current.consumerAuthorityEnabled ~= true then
        return false, "consumer-snapshot-revoked", current
    end
    if tonumber(snapshot.currentBuild) ~= tonumber(current.currentBuild) or
        tostring(snapshot.clientSessionToken or "") ~= tostring(current.clientSessionToken or "") or
        snapshot.token ~= current.snapshotToken then
        return false, "consumer-snapshot-stale", current
    end
    return true, "consumer-snapshot-current", current
end

function ResearchPlannerConsumerBridge:GetSummary(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    local model = self:Build(professionKey, mode, options)
    if not model then return "Planner consumer authority unavailable." end
    local lines = {
        "PLANNER CONSUMER AUTHORITY / READ ONLY",
        string.format("%s / %s", professionKey, tostring(model.mode or "normal")),
        "State: " .. tostring(model.state),
        "Source route authority: " .. tostring(model.sourceAuthorityState),
        "Current build: " .. tostring(model.currentBuild or "unknown"),
        string.format("Consumer surfaces: %d pass / %d total", tonumber(model.stats and model.stats.passedConsumers) or 0, tonumber(model.stats and model.stats.totalConsumers) or 0),
    }
    if model.consumerSurfaces then
        for _, row in ipairs({
            {"planner", "Planner"}, {"requirements", "RequirementPlan"}, {"readiness", "CraftReadiness"}, {"actions", "ActionQueue"}, {"guide", "GuideSteps"},
        }) do
            lines[#lines + 1] = string.format("· %s: %s", row[2], model.consumerSurfaces[row[1]] and "pass" or "blocked")
        end
    end
    if model.snapshot then
        lines[#lines + 1] = "Snapshot token: " .. tostring(model.snapshot.token)
        lines[#lines + 1] = "Selected segment: " .. tostring(model.snapshot.selectedSegment or "unknown")
        lines[#lines + 1] = "Recipe: " .. tostring(model.snapshot.recipe or "unknown")
        if model.snapshot.targetBound then
            lines[#lines + 1] = "Target bound: yes"
            lines[#lines + 1] = "Target GUID: " .. tostring(model.snapshot.targetGUID or "none")
            lines[#lines + 1] = "Target item ID: " .. tostring(model.snapshot.targetItemID or "n/a")
            lines[#lines + 1] = "Target ItemLocation key: " .. tostring(model.snapshot.targetLocationKey or "none")
            lines[#lines + 1] = "Target proof fingerprint: " .. tostring(model.snapshot.targetProofFingerprint or "none")
        end
    end
    lines[#lines + 1] = "UI execution controls: disabled"
    lines[#lines + 1] = "Execution authority: disabled"
    lines[#lines + 1] = "Snapshot persistence: none"
    lines[#lines + 1] = "Revocation: rebuild before consume · build/evidence/profession drift fails closed"
    return table.concat(lines, "\n")
end

function ResearchPlannerConsumerBridge:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.transferableToExecution ~= false then
        errors[#errors + 1] = "research Planner consumer execution boundary invalid"
    end
    for _, name in ipairs({"ResearchRouteAuthorityBridge", "ProductionTailoringAuthorityAdapter", "ProductionEnchantingAuthorityAdapter", "GuideSteps", "RequirementPlan", "CraftReadiness", "ActionQueue"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "research Planner consumer dependency missing: " .. name end
    end
    return errors, warnings
end

JLP:RegisterModule("ResearchPlannerConsumerBridge", ResearchPlannerConsumerBridge)
