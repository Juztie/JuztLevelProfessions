local _, JLP = ...

-- Alpha78: current-build telemetry reconciliation for the research shadow
-- Planner.  Production Planner telemetry is intentionally broader than research
-- authority: it may use account priors or carefully revalidated cross-build
-- rates.  Those sources are useful to a normal player-facing estimate, but they
-- are not sufficient evidence to mutate an authority-bearing research shadow.
--
-- This module therefore asks the production Planner for the *exact same*
-- adaptive craft-count calculation and then applies it to the shadow only when
-- the estimate is provably character-local and current-build.  It never writes
-- SavedVariables and never grants Planner/execution authority itself.
local ResearchAdaptivePlannerParity = {
    contract = "adaptive-current-build-planner-parity-v1",
    reconciliationContract = "research-shadow-telemetry-reconciliation-v1",
    authority = "current-build-local-telemetry-shadow-reconciliation-only",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
    readOnly = true,
    persisted = false,
    initialized = false,
    revision = 0,
    dirty = {},
    lastByRecipe = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(value)
    return value == "aggressive" and "aggressive" or "normal"
end

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("%s+", " ")
    return value
end

local function currentBuild()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    -- An unobserved build must not be substituted from historical constants.
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function recipeKey(professionKey, recipe)
    return tostring(normalizeKey(professionKey) or "UNKNOWN") .. "|" .. normalizeText(recipe)
end

local function externalPriorUsed(estimate)
    if type(estimate) ~= "table" then return false end
    if estimate.usedAccountPrior == true
        or estimate.usedHistoricalBuild == true
        or estimate.usedHistoricalAccount == true
        or estimate.usedBuildRevalidation == true
        or estimate.usedAccountBuildConsensus == true then
        return true
    end
    local function disallowed(text)
        text = string.lower(tostring(text or ""))
        return text:find("account", 1, true) ~= nil
            or text:find("historical", 1, true) ~= nil
            or text:find("cross-build", 1, true) ~= nil
            or text:find("build-revalidated", 1, true) ~= nil
    end
    if disallowed(estimate.source) or disallowed(estimate.sourceDetail) then return true end
    for _, band in ipairs(estimate.bandEstimates or {}) do
        if disallowed(band and band.source) then return true end
    end
    return false
end

local function currentBuildLocal(estimate, activeBuild)
    local telemetry = estimate and estimate.telemetry or nil
    if type(telemetry) ~= "table" then return false, "local-current-build-telemetry-missing" end
    if telemetry.historicalBuild == true then return false, "historical-local-telemetry" end
    if tostring(telemetry.buildScope or "") ~= "current-build-local" then
        return false, "telemetry-build-scope-not-local-current"
    end
    local provenance = telemetry.buildProvenance
    if type(provenance) ~= "table" or tonumber(provenance.build) == nil then
        return false, "telemetry-build-provenance-missing"
    end
    if activeBuild == nil or tonumber(provenance.build) ~= tonumber(activeBuild) then
        return false, "telemetry-build-provenance-stale"
    end
    if telemetry.buildToken and telemetry.currentBuildToken
        and tostring(telemetry.buildToken) ~= tostring(telemetry.currentBuildToken) then
        return false, "telemetry-build-token-stale"
    end
    if externalPriorUsed(estimate) then return false, "non-local-telemetry-prior-used" end
    return true, "current-build-local-telemetry"
end

local function fingerprint(model)
    return table.concat({
        tostring(model.professionKey or ""),
        tostring(model.mode or ""),
        tostring(model.currentBuild or ""),
        tostring(model.recipe or ""),
        tostring(model.recipeID or ""),
        tostring(model.staticRemainingCrafts or ""),
        tostring(model.productionRemainingCrafts or ""),
        tostring(model.shadowRemainingCrafts or ""),
        tostring(model.estimateSource or ""),
        tostring(model.estimateSourceDetail or ""),
        tostring(model.estimateWeight or ""),
        tostring(model.telemetrySamples or ""),
        tostring(model.telemetrySkillUps or ""),
        tostring(model.telemetryBuildToken or ""),
        tostring(model.state or ""),
    }, "|")
end

function ResearchAdaptivePlannerParity:MarkDirty(professionKey, recipe, reason)
    professionKey = normalizeKey(professionKey)
    if not professionKey then return false end
    local token = recipeKey(professionKey, recipe)
    self.dirty[token] = {
        professionKey = professionKey,
        recipe = recipe,
        reason = tostring(reason or "telemetry-updated"),
    }
    return true
end

function ResearchAdaptivePlannerParity:IsEstimateEligible(estimate, activeBuild)
    if type(estimate) ~= "table" or estimate.plannerEligible ~= true then
        return false, "production-telemetry-not-active"
    end
    return currentBuildLocal(estimate, activeBuild or currentBuild())
end

function ResearchAdaptivePlannerParity:Evaluate(professionKey, mode, stagedStep, liveSkill, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    stagedStep = type(stagedStep) == "table" and stagedStep or {}

    local activeBuild = currentBuild()
    local staticRemaining = math.max(0, tonumber(stagedStep.staticRemainingCrafts) or tonumber(stagedStep.remainingCrafts) or 0)
    local currentSkill = tonumber(liveSkill) or tonumber(stagedStep.skill) or tonumber(stagedStep.skillMin) or 0
    local targetSkill = tonumber(stagedStep.skillTarget) or currentSkill
    local planner = JLP:GetModule("Planner")
    local productionRemaining, estimate
    if planner and planner.GetTelemetryCraftEstimate then
        productionRemaining, estimate = planner:GetTelemetryCraftEstimate(
            professionKey,
            stagedStep,
            currentSkill,
            targetSkill,
            staticRemaining,
            true
        )
    else
        productionRemaining = staticRemaining
    end
    productionRemaining = math.max(0, tonumber(productionRemaining) or staticRemaining)

    local token = recipeKey(professionKey, stagedStep.recipe)
    local dirty = self.dirty[token]
    local model = {
        contract = self.reconciliationContract,
        professionKey = professionKey,
        mode = mode,
        currentBuild = activeBuild,
        recipe = stagedStep.recipe,
        recipeID = tonumber(stagedStep.recipeID),
        staticRemainingCrafts = staticRemaining,
        productionRemainingCrafts = productionRemaining,
        shadowRemainingCrafts = staticRemaining,
        productionTelemetryActive = estimate and estimate.plannerEligible == true or false,
        estimateSource = estimate and estimate.source or "route-static",
        estimateSourceDetail = estimate and estimate.sourceDetail or "route-static",
        estimateWeight = estimate and tonumber(estimate.weight) or 0,
        telemetryBuildScope = estimate and estimate.telemetry and estimate.telemetry.buildScope or nil,
        telemetryBuildToken = estimate and estimate.telemetry and estimate.telemetry.buildToken or nil,
        telemetrySamples = estimate and estimate.telemetry and tonumber(estimate.telemetry.skillObservedCrafts) or 0,
        telemetrySkillUps = estimate and estimate.telemetry and tonumber(estimate.telemetry.skillUps) or 0,
        telemetryEstimate = estimate,
        currentBuildOnly = false,
        adaptiveApplied = false,
        ready = true,
        dirtyBeforeReconcile = dirty ~= nil,
        dirtyReason = dirty and dirty.reason or nil,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        readOnly = true,
        persisted = false,
    }

    if options.shadowTelemetryMode == "static-audit" then
        model.state = "adaptive-parity-static-audit"
        model.auditStatic = true
        model.ready = true
    elseif not model.productionTelemetryActive then
        model.state = "adaptive-parity-static"
        model.ready = true
    else
        local eligible, reason = self:IsEstimateEligible(estimate, activeBuild)
        model.currentBuildOnly = eligible == true
        model.eligibilityState = reason
        if eligible then
            model.shadowRemainingCrafts = productionRemaining
            model.adaptiveApplied = true
            model.ready = true
            model.state = dirty and "adaptive-parity-reacquired" or "adaptive-parity-current-build"
        else
            model.ready = false
            model.state = "adaptive-parity-source-ineligible"
            model.blockedReason = reason
        end
    end

    model.fingerprint = fingerprint(model)
    local previous = self.lastByRecipe[token]
    if not previous or tostring(previous.fingerprint) ~= tostring(model.fingerprint) then
        self.revision = self.revision + 1
        model.revision = self.revision
        if model.state == "adaptive-parity-reacquired" then
            model.transition = "reacquired"
        elseif previous and previous.ready == true and model.ready == false then
            model.transition = "blocked"
        elseif previous and previous.ready == false and model.ready == true then
            model.transition = "reacquired"
        elseif model.adaptiveApplied then
            model.transition = previous and "reconciled" or "adapted"
        else
            model.transition = previous and "updated" or "baseline"
        end
    else
        model.revision = previous.revision or self.revision
        model.transition = "unchanged"
    end
    self.lastByRecipe[token] = model
    if model.ready then self.dirty[token] = nil end
    return model
end

function ResearchAdaptivePlannerParity:ApplyToStep(professionKey, mode, stagedStep, liveSkill, options)
    local model = self:Evaluate(professionKey, mode, stagedStep, liveSkill, options)
    local step = stagedStep
    if model and model.adaptiveApplied then
        step.remainingCrafts = model.shadowRemainingCrafts
        step.estimateSource = model.estimateSource
        step.estimateSourceDetail = model.estimateSourceDetail
        step.estimateWeight = model.estimateWeight or 0
        step.telemetryEstimate = model.telemetryEstimate
        step.telemetry = model.telemetryEstimate and model.telemetryEstimate.telemetry or nil
        step.craftCountAuthority = "current-build-local-telemetry-shadow-parity"
    end
    step.adaptiveTelemetry = model
    return step, model
end

function ResearchAdaptivePlannerParity:GetLast(professionKey, recipe)
    if recipe then return self.lastByRecipe[recipeKey(professionKey, recipe)] end
    professionKey = normalizeKey(professionKey)
    local newest
    for _, row in pairs(self.lastByRecipe) do
        if row.professionKey == professionKey and (not newest or (tonumber(row.revision) or 0) > (tonumber(newest.revision) or 0)) then
            newest = row
        end
    end
    return newest
end

function ResearchAdaptivePlannerParity:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("RECIPE_TELEMETRY_UPDATED", function(professionKey, recipe)
            self:MarkDirty(professionKey, recipe, "RECIPE_TELEMETRY_UPDATED")
        end)
    end
    return true
end

function ResearchAdaptivePlannerParity:GetSummary(professionKey, mode, selector, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    local shadow = JLP:GetModule("ResearchShadowPlanner")
    local model = shadow and shadow:Build(professionKey, mode, options) or nil
    local selected
    local numeric = tonumber(selector)
    local wanted = normalizeText(selector)
    for _, segment in ipairs(model and model.segments or {}) do
        if not numeric or tonumber(segment.segmentIndex) == numeric then
            for _, step in ipairs(segment.steps or {}) do
                if not selector or numeric or normalizeText(step.recipe) == wanted then
                    selected = step.adaptiveTelemetry
                    if selected then break end
                end
            end
        end
        if selected then break end
    end
    selected = selected or self:GetLast(professionKey)
    local lines = {
        "ADAPTIVE RESEARCH PLANNER PARITY / CURRENT-BUILD TELEMETRY",
        string.format("%s / %s", professionKey, mode),
        "Contract: " .. self.contract,
        "Reconciliation: " .. self.reconciliationContract,
        "Revision: " .. tostring(self.revision or 0),
    }
    if selected then
        lines[#lines + 1] = "State: " .. tostring(selected.state)
        lines[#lines + 1] = "Recipe: " .. tostring(selected.recipe or "unknown")
        lines[#lines + 1] = string.format("Craft estimate: static %s · production %s · shadow %s", tostring(selected.staticRemainingCrafts), tostring(selected.productionRemainingCrafts), tostring(selected.shadowRemainingCrafts))
        lines[#lines + 1] = "Source: " .. tostring(selected.estimateSource or "route-static") .. " / " .. tostring(selected.estimateSourceDetail or "route-static")
        lines[#lines + 1] = "Current-build local telemetry: " .. (selected.currentBuildOnly and "yes" or "no")
        lines[#lines + 1] = "Adaptive shadow applied: " .. (selected.adaptiveApplied and "yes" or "no")
        lines[#lines + 1] = "Reacquired after telemetry update: " .. ((selected.state == "adaptive-parity-reacquired" or selected.transition == "reacquired") and "yes" or "no")
        if selected.blockedReason then lines[#lines + 1] = "Blocked reason: " .. tostring(selected.blockedReason) end
        lines[#lines + 1] = "Current build: " .. tostring(selected.currentBuild or "unknown")
        lines[#lines + 1] = "Telemetry build scope: " .. tostring(selected.telemetryBuildScope or "none")
        lines[#lines + 1] = "Samples: " .. tostring(selected.telemetrySamples or 0) .. " · skill-ups: " .. tostring(selected.telemetrySkillUps or 0)
    else
        lines[#lines + 1] = "State: no evaluated research step"
    end
    lines[#lines + 1] = "Historical/account/cross-build priors: non-transferable"
    lines[#lines + 1] = "SavedVariables writes: 0"
    lines[#lines + 1] = "Planner authority: not granted by this module"
    lines[#lines + 1] = "Execution authority: disabled"
    return table.concat(lines, "\n")
end

function ResearchAdaptivePlannerParity:Validate()
    local errors, warnings = {}, {}
    if self.plannerEligible ~= false or self.executionEligible ~= false or self.transferable ~= false or self.readOnly ~= true or self.persisted ~= false then
        errors[#errors + 1] = "adaptive Planner parity authority boundary invalid"
    end
    local planner = JLP:GetModule("Planner")
    local telemetry = JLP:GetModule("RecipeTelemetry")
    if not planner or not planner.GetTelemetryCraftEstimate then errors[#errors + 1] = "adaptive Planner parity shared Planner estimator missing" end
    if not telemetry or not telemetry.GetPlannerEstimate then errors[#errors + 1] = "adaptive Planner parity RecipeTelemetry dependency missing" end
    return errors, warnings
end

JLP:RegisterModule("ResearchAdaptivePlannerParity", ResearchAdaptivePlannerParity)
