local _, JLP = ...

-- Alpha98 controlled read-authority adapter for the real production Tailoring
-- dataset.  This module never dispatches native work and never reuses the
-- research-derived segment pipeline.  It projects Data/Tailoring.lua through
-- the production Planner surfaces, verifies parity against the unwrapped
-- production dataset, and exposes a revocable non-persistent dataset to the
-- existing atomic Planner consumer bridge.
local ProductionTailoringAuthorityAdapter = {
    contract = "production-tailoring-route-authority-adapter-v1",
    datasetContract = "production-tailoring-planner-dataset-v1",
    parityContract = "production-tailoring-consumer-surface-parity-v1",
    authority = "feature-gated-current-build-production-tailoring-read-authority",
    readOnly = true,
    executionEligible = false,
    transferableToExecution = false,
    nativeDispatchAllowed = false,
    persisted = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(value)
    return value == "aggressive" and "aggressive" or "normal"
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function featureProfile()
    local profile = JLP.DB and JLP.DB.profile
    return profile and profile.productionTailoringAuthority or nil
end

local function featureEnabled()
    local profile = featureProfile()
    return profile and profile.enabled == true or false
end

local function shallowCopy(source)
    local out = {}
    for key, value in pairs(source or {}) do out[key] = value end
    return out
end


local function copyMaterial(row)
    local out = shallowCopy(row)
    if type(row and row.craftedFrom) == "table" then out.craftedFrom = shallowCopy(row.craftedFrom) end
    if type(row and row.craftedRecipe) == "table" then out.craftedRecipe = shallowCopy(row.craftedRecipe) end
    return out
end

local function buildDataset(source, activeBuild)
    local dataset = {
        contract = ProductionTailoringAuthorityAdapter.datasetContract,
        professionKey = "TAILORING",
        key = "TAILORING",
        name = source.name or "Tailoring",
        evidence = source.evidence,
        sourceBuild = source.sourceBuild,
        currentBuild = activeBuild,
        datasetStatus = source.datasetStatus,
        recipeIdentityContract = source.recipeIdentityContract,
        recipeIdentityEvidence = source.recipeIdentityEvidence,
        route = {},
        steps = nil,
        trainerGates = {},
        materials = source.materials,
        authority = ProductionTailoringAuthorityAdapter.authority,
        plannerEligible = true,
        routeAuthorityEnabled = true,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        productionAuthority = true,
        researchAuthority = false,
        trainerAuthorityEnabled = false,
        acquisitionAuthorityEnabled = false,
        nativeDispatchAllowed = false,
    }
    for index, raw in ipairs(source.route or source.steps or {}) do
        local step = shallowCopy(raw)
        step.routeIndex = tonumber(raw.routeIndex) or index
        step.materials = {}
        for materialIndex, material in ipairs(raw.materials or {}) do step.materials[materialIndex] = copyMaterial(material) end
        step.authority = ProductionTailoringAuthorityAdapter.authority
        step.plannerEligible = true
        step.routeAuthorityEnabled = true
        step.executionEligible = false
        step.transferable = false
        step.readOnly = true
        step.productionAuthority = true
        step.researchAuthority = false
        dataset.route[index] = step
    end
    dataset.steps = dataset.route
    for index, gate in ipairs(source.trainerGates or {}) do dataset.trainerGates[index] = shallowCopy(gate) end
    return dataset
end

local function buildSurfaces(profession, dataset)
    local planner = JLP:GetModule("Planner")
    if not planner or not planner.BuildProfessionPlanForDataset then return nil end
    local plan = planner:BuildProfessionPlanForDataset("TAILORING", profession, dataset)
    if not plan then return nil end
    local requirement = JLP:GetModule("RequirementPlan")
    local readinessModule = JLP:GetModule("CraftReadiness")
    local queueModule = JLP:GetModule("ActionQueue")
    local readiness = readinessModule and readinessModule.Get and readinessModule:Get("TAILORING", plan) or nil
    return {
        plan = plan,
        requirementPlan = requirement and requirement.Build and requirement:Build("TAILORING", plan) or nil,
        readiness = readiness,
        actionQueue = queueModule and queueModule.Build and queueModule:Build("TAILORING", plan, readiness) or nil,
    }
end

local function scalarEqual(a, b)
    if type(a) == "number" or type(b) == "number" then return tonumber(a) == tonumber(b) end
    return a == b
end

local function addGap(gaps, surface, field, baseline, authority)
    gaps[#gaps + 1] = { surface=surface, field=field, baseline=baseline, authority=authority }
end

local function compare(gaps, surface, field, baseline, authority)
    if not scalarEqual(baseline, authority) then addGap(gaps, surface, field, baseline, authority) end
end

local function compareRows(gaps, surface, prefix, baselineRows, authorityRows, fields)
    baselineRows, authorityRows = baselineRows or {}, authorityRows or {}
    compare(gaps, surface, prefix..".count", #baselineRows, #authorityRows)
    for index = 1, math.min(#baselineRows, #authorityRows) do
        local a, b = baselineRows[index], authorityRows[index]
        for _, field in ipairs(fields or {}) do compare(gaps, surface, prefix.."["..index.."]."..field, a and a[field], b and b[field]) end
    end
end

local function compareSurfaces(baseline, authority)
    local gaps = {}
    if not baseline or not authority then
        addGap(gaps, "surfaces", "available", baseline and true or false, authority and true or false)
        return { ready=false, gaps=gaps, planner=false, requirements=false, readiness=false, actions=false }
    end
    local bp, ap = baseline.plan or {}, authority.plan or {}
    local bs, as = bp.step or {}, ap.step or {}
    for _, field in ipairs({"status","actionKind"}) do compare(gaps,"planner",field,bp[field],ap[field]) end
    for _, field in ipairs({"kind","routeIndex","recipe","recipeID","skillTarget","remainingCrafts","staticRemainingCrafts"}) do
        local bv = field == "recipeID" and (bs.rawStep and bs.rawStep.recipeID or bs.recipeID) or bs[field]
        local av = field == "recipeID" and (as.rawStep and as.rawStep.recipeID or as.recipeID) or as[field]
        compare(gaps,"planner","step."..field,bv,av)
    end
    compareRows(gaps,"planner","materials",bp.materials,ap.materials,{"itemID","name","source","required","owned","missing"})
    local plannerGapCount = #gaps

    local br, ar = baseline.requirementPlan or {}, authority.requirementPlan or {}
    for _, field in ipairs({"status","materialTypes","missingTypes","totalRequired","totalOwned","totalMissing","totalMissingUnits"}) do compare(gaps,"requirements",field,br[field],ar[field]) end
    compareRows(gaps,"requirements","rows",br.rows,ar.rows,{"itemID","name","source","required","owned","missing"})
    local requirementsGapCount = #gaps - plannerGapCount

    local bc, ac = baseline.readiness or {}, authority.readiness or {}
    for _, field in ipairs({"status","blocker","recipeKnowledge","remainingCrafts","immediateBags","immediateStorage","preparedBags","preparedStorage","craftableNow","craftablePrepared"}) do compare(gaps,"readiness",field,bc[field],ac[field]) end
    local readinessGapCount = #gaps - plannerGapCount - requirementsGapCount

    local beforeActions = #gaps
    local bq, aq = baseline.actionQueue or {}, authority.actionQueue or {}
    for _, field in ipairs({"status","currentIndex"}) do compare(gaps,"actions",field,bq[field],aq[field]) end
    compareRows(gaps,"actions","actions",bq.actions,aq.actions,{"kind","itemID","itemName","quantity","source","text","detail","status"})
    local actionGapCount = #gaps - beforeActions

    return {
        ready = #gaps == 0,
        planner = plannerGapCount == 0,
        requirements = requirementsGapCount == 0,
        readiness = readinessGapCount == 0,
        actions = actionGapCount == 0,
        gaps = gaps,
    }
end

function ProductionTailoringAuthorityAdapter:IsSupported(professionKey)
    return normalizeKey(professionKey) == "TAILORING"
end

function ProductionTailoringAuthorityAdapter:IsFeatureEnabled()
    return featureEnabled()
end

function ProductionTailoringAuthorityAdapter:GetConfiguredMode()
    return "normal"
end

function ProductionTailoringAuthorityAdapter:SetFeatureEnabled(enabled)
    local profile = featureProfile()
    if not profile then return false, "profile-unavailable" end
    profile.enabled = enabled == true
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_TAILORING_AUTHORITY_UPDATED", { enabled=profile.enabled, professionKey="TAILORING" })
    end
    return true, profile.enabled and "enabled" or "disabled"
end

function ProductionTailoringAuthorityAdapter:IsAuthorityActive(model)
    return type(model) == "table"
        and model.state == "production-tailoring-route-authority-active"
        and model.routeAuthorityEnabled == true
        and model.plannerEligible == true
        and model.executionEligible == false
end

function ProductionTailoringAuthorityAdapter:Build(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "TAILORING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    local activeBuild = currentBuild()
    local model = {
        contract = self.contract,
        datasetContract = self.datasetContract,
        parityContract = self.parityContract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        featureGateEnabled = featureEnabled(),
        currentBuild = activeBuild,
        plannerEligible = false,
        routeAuthorityEnabled = false,
        executionEligible = false,
        executionAuthorityEnabled = false,
        transferable = false,
        readOnly = true,
        nativeDispatchAllowed = false,
        persisted = false,
        selectedSegment = nil,
        stats = { parityGaps=0, routeSteps=0, stagedRecipeIDs=0 },
    }
    if professionKey ~= "TAILORING" then
        model.state = "production-tailoring-authority-unsupported-profession"
        model.blockedReason = "unsupported-profession"
        return model
    end
    if not model.featureGateEnabled and not options.allowHarness then
        model.state = "production-tailoring-authority-feature-gate-disabled"
        model.blockedReason = "feature-gate-disabled"
        return model
    end

    local source = JLP.data and JLP.data.tailoring or nil
    if not source or type(source.route) ~= "table" then
        model.state = "production-tailoring-authority-dataset-unavailable"
        model.blockedReason = "tailoring-dataset-unavailable"
        return model
    end
    model.stats.routeSteps = #source.route

    local identity = JLP:GetModule("ProductionTailoringRecipeIdentity")
    local staged = identity and identity.AuditStaged and identity:AuditStaged() or nil
    model.identity = staged
    model.stats.stagedRecipeIDs = staged and tonumber(staged.stagedRecipeCount) or 0
    if not staged or staged.stagedComplete ~= true then
        model.state = "production-tailoring-authority-identity-incomplete"
        model.blockedReason = "recipe-identity-staging-incomplete"
        return model
    end
    -- The production source is qualified against its own historical baseline.
    -- A valid LIVE client identity is required for revocable current snapshots,
    -- but equality between archive-build and client-build is NOT required.
    if type(activeBuild)~="number" or activeBuild<=0 or
       activeBuild~=math.floor(activeBuild) or
       tonumber(source.sourceBuild)~=70009 or
       tonumber(source.productionBaselineBuild)~=70009 or
       source.legacyProductionBaseline~=true or staged.buildCoherent~=true then
        model.state = "production-tailoring-authority-provenance-unverified"
        model.blockedReason = "source-provenance-or-live-client-unverified"
        return model
    end

    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get("TAILORING") or nil
    model.liveProfession = profession
    if not profession or profession.cached == true or normalizeKey(profession.key or "TAILORING") ~= "TAILORING" then
        model.state = "production-tailoring-authority-live-profession-unavailable"
        model.blockedReason = "live-tailoring-state-unavailable"
        return model
    end

    local dataset = buildDataset(source, activeBuild)
    local baseline = buildSurfaces(profession, source)
    local live = buildSurfaces(profession, dataset)
    local parity = compareSurfaces(baseline, live)
    model.dataset = dataset
    model.baseline = baseline
    model.live = live
    model.parity = parity
    model.stats.parityGaps = #(parity.gaps or {})
    model.selectedSegment = live and live.plan and live.plan.step and live.plan.step.routeIndex or nil

    local plan = live and live.plan or nil
    local authorityShapeReady = plan ~= nil
        and plan.routeAuthorityEnabled == true
        and plan.plannerEligible == true
        and plan.executionEligible == false
        and (plan.actionKind ~= "craft" or (plan.step and plan.step.plannerEligible == true and plan.step.executionEligible == false))
    if not authorityShapeReady then
        model.state = "production-tailoring-authority-shape-blocked"
        model.blockedReason = "planner-read-authority-shape"
        return model
    end
    if parity.ready ~= true then
        model.state = "production-tailoring-authority-parity-blocked"
        model.blockedReason = "production-surface-parity-mismatch"
        return model
    end

    model.state = "production-tailoring-route-authority-active"
    model.plannerEligible = true
    model.routeAuthorityEnabled = true
    return model
end

function ProductionTailoringAuthorityAdapter:GetPlannerDataset(professionKey, mode, options)
    if not self:IsSupported(professionKey) then return nil, "unsupported-profession" end
    local model = self:Build(professionKey, mode, options)
    if not self:IsAuthorityActive(model) then return nil, model and model.state or "adapter-unavailable", model end
    return model.dataset, model.state, model
end

function ProductionTailoringAuthorityAdapter:GetSummary(options)
    local model = self:Build("TAILORING", "normal", options)
    local parity = model and model.parity or nil
    local lines = {
        "TAILORING / PRODUCTION CONSUMER ROUTE AUTHORITY",
        "Contract: "..self.contract,
        "Dataset contract: "..self.datasetContract,
        "Parity contract: "..self.parityContract,
        "State: "..tostring(model and model.state or "unavailable"),
        "Feature gate: "..(model and model.featureGateEnabled and "enabled" or "disabled"),
        "Current build: "..tostring(model and model.currentBuild or "unknown"),
        string.format("Staged recipe identities: %d / 21", tonumber(model and model.stats and model.stats.stagedRecipeIDs) or 0),
        string.format("Production route steps: %d", tonumber(model and model.stats and model.stats.routeSteps) or 0),
        "Production surface parity: "..(parity and parity.ready and "pass" or "not active/pass unavailable"),
        "Parity gaps: "..tostring(model and model.stats and model.stats.parityGaps or 0),
        "Planner read authority: "..(model and model.routeAuthorityEnabled and "enabled" or "disabled"),
        "Consumer transfer: read-only only",
        "Execution readiness support: disabled",
        "Native execution authority: disabled",
        "Native dispatch: forbidden",
        "Persistence: none",
    }
    if parity and #(parity.gaps or {}) > 0 then
        for index, gap in ipairs(parity.gaps) do
            if index > 6 then lines[#lines+1] = string.format("- ... %d additional gap(s)", #parity.gaps-6); break end
            lines[#lines+1] = string.format("- %s/%s baseline=%s authority=%s", tostring(gap.surface), tostring(gap.field), tostring(gap.baseline), tostring(gap.authority))
        end
    end
    return table.concat(lines, "\n")
end

function ProductionTailoringAuthorityAdapter:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.transferableToExecution ~= false or self.nativeDispatchAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "Production Tailoring authority safety boundary invalid"
    end
    for _, name in ipairs({"ProductionTailoringRecipeIdentity","Planner","RequirementPlan","CraftReadiness","ActionQueue","ProfessionAPI"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "Production Tailoring authority dependency missing: "..name end
    end
    local identity = JLP:GetModule("ProductionTailoringRecipeIdentity")
    local staged = identity and identity.AuditStaged and identity:AuditStaged() or nil
    if not staged or staged.stagedComplete ~= true then errors[#errors+1] = "Production Tailoring authority requires complete staged recipe identity" end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringAuthorityAdapter", ProductionTailoringAuthorityAdapter)
