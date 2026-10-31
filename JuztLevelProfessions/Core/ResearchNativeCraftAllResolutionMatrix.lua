local _, JLP = ...

-- Alpha90 classifies whether a settled strict Craft All interruption can become
-- a fresh-click restart, must wait for the original blocker to resolve, or must
-- fall back to the normal Planner because recipe/target/build identity drifted.
-- This module never authorizes or dispatches crafting.
local ResearchNativeCraftAllResolutionMatrix = {
    contract = "current-recipe-craft-all-restart-resolution-matrix-v1",
    resolutionContract = "research-current-recipe-craft-all-resolution-v1",
    authority = "classification-only-no-dispatch-planner-handoff-v1",
    automaticResume = false,
    automaticRouteAdvance = false,
    nativeDispatchAllowed = false,
    persisted = false,
    lastByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function copy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function currentBuild()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function restartModuleFor(professionKey, interruption)
    professionKey = normalizeKey(professionKey)
    local provenance = interruption and tostring(interruption.provenanceContract or "") or ""
    if professionKey == "TAILORING" or provenance == "production-tailoring-native-craft-all-provenance-v1" then
        return JLP:GetModule("ProductionTailoringCraftAllRestart")
    end
    return JLP:GetModule("ResearchNativeCraftAllRestart")
end

local function result(disposition, reason, label, detail)
    return disposition, reason, label, detail
end

local function restartStateIs(state, suffix)
    state = tostring(state or "")
    suffix = tostring(suffix or "")
    return state == ("craft-all-restart-" .. suffix)
        or state == ("production-tailoring-craft-all-restart-" .. suffix)
end

function ResearchNativeCraftAllResolutionMatrix:Assess(interruption, restartModel, liveBuild)
    interruption = type(interruption) == "table" and interruption or nil
    restartModel = type(restartModel) == "table" and restartModel or {}
    liveBuild = tonumber(liveBuild) or currentBuild()

    if not interruption then
        return result("not-applicable", "NO_INTERRUPTION", "No Craft All interruption", "There is no settled Craft All interruption to resolve.")
    end

    local state = tostring(restartModel.state or "")
    local category = tostring(interruption.category or "OTHER"):upper()
    local priorBuild = tonumber(interruption.currentBuild or restartModel.priorBuild)

    if restartModel.restartReady == true and restartStateIs(state, "ready") then
        return result("restart-safe", "SAME_RECIPE_TARGET_REVALIDATED", "Ready to continue Craft All", "Same recipe and target are current, craftable and authority-ready. A fresh explicit click may create a new Craft All transaction.")
    end

    if restartStateIs(state, "recipe-changed") then
        return result("planner-handoff-required", "RECIPE_CHANGED", "Craft All route changed", "The verified Planner recipe no longer matches the interrupted Craft All recipe. Use the normal Planner handoff; do not continue the old Craft All intent.")
    end
    if restartStateIs(state, "target-changed") then
        return result("planner-handoff-required", "TARGET_CHANGED", "Craft All target changed", "The verified skill target changed. Treat this as a new plan rather than a continuation of the interrupted Craft All.")
    end
    if restartStateIs(state, "target-reached") then
        return result("planner-handoff-required", "TARGET_ALREADY_REACHED", "Craft All target already reached", "The original target is already satisfied. Use the post-settlement Planner handoff instead of restarting Craft All.")
    end
    if restartStateIs(state, "interruption-consumed") then
        return result("not-applicable", "INTERRUPTION_ALREADY_CONSUMED", "Craft All interruption already consumed", "The interruption already produced a fresh transaction and cannot be reused.")
    end
    if restartStateIs(state, "transaction-active") then
        return result("wait-for-resolution", "TRANSACTION_STILL_ACTIVE", "Craft transaction still active", "Settlement must finish before restart eligibility can be evaluated.")
    end
    if restartStateIs(state, "materials-unavailable") then
        return result("wait-for-resolution", "MATERIALS_STILL_BLOCKED", "Materials still required", "The exact interrupted recipe is still not craftable from current materials.")
    end

    if category == "BUILD_CHANGED" and priorBuild and liveBuild and priorBuild ~= liveBuild then
        return result("wait-for-resolution", "BUILD_EVIDENCE_NOT_REBUILT", "Current-build evidence required", "The Forever build changed and current-build Planner/recipe/material evidence has not yet been re-established for a safe restart.")
    end

    local blockedGate = tostring(restartModel.blockedGate or "")
    local blockedState = tostring(restartModel.blockedState or "")
    local combined = (blockedGate .. " " .. blockedState .. " " .. state):lower()
    if combined:find("profession%-window") or combined:find("window", 1, true) then
        return result("wait-for-resolution", "WINDOW_STILL_BLOCKED", "Profession window required", "The exact profession window is not currently verified open.")
    end
    if combined:find("material", 1, true) or combined:find("craftable", 1, true) then
        return result("wait-for-resolution", "MATERIALS_STILL_BLOCKED", "Materials still required", "The exact interrupted recipe is not currently material-ready/craftable.")
    end
    if combined:find("build", 1, true) then
        return result("wait-for-resolution", "BUILD_EVIDENCE_NOT_REBUILT", "Current-build evidence required", "Current-build provenance is not coherent yet.")
    end
    if restartStateIs(state, "authority-not-ready") or combined:find("consumer%-authority") or combined:find("snapshot%-current") or combined:find("authority", 1, true) then
        return result("wait-for-resolution", "AUTHORITY_STILL_BLOCKED", "Craft All authority still blocked", "Route/consumer/execution authority is not current enough to create a fresh Craft All restart.")
    end
    if restartStateIs(state, "still-blocked") then
        return result("wait-for-resolution", "EXECUTION_STILL_BLOCKED", "Craft All execution still blocked", "At least one current execution-readiness gate is still blocked.")
    end
    if restartStateIs(state, "not-applicable") then
        return result("not-applicable", "INTERRUPTION_NOT_RESTARTABLE", "Craft All restart not applicable", "This interruption is not eligible for a fresh Craft All restart.")
    end

    return result("wait-for-resolution", "RESTART_NOT_READY", "Craft All restart not ready", "The interruption has not yet resolved into a safe fresh-click restart.")
end

function ResearchNativeCraftAllResolutionMatrix:Analyze(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    local interrupt = JLP:GetModule("ResearchNativeCraftAllInterruption")
    local interruption = interrupt and interrupt.GetLast and interrupt:GetLast(professionKey) or nil
    local restart = restartModuleFor(professionKey, interruption)
    local restartModel = restart and restart.Evaluate and restart:Evaluate(professionKey, mode, options) or nil
    local disposition, reason, label, detail = self:Assess(interruption, restartModel, currentBuild())
    local model = {
        contract = self.contract,
        resolutionContract = self.resolutionContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        disposition = disposition,
        reason = reason,
        label = label,
        detail = detail,
        interruptionCategory = interruption and interruption.category or nil,
        interruptionToken = interruption and interruption.interruptionToken or nil,
        priorRecipe = interruption and interruption.recipe or restartModel and restartModel.priorRecipe or nil,
        priorRecipeID = tonumber(interruption and interruption.recipeID or restartModel and restartModel.priorRecipeID),
        priorSkillTarget = tonumber(interruption and interruption.targetSkill or restartModel and restartModel.priorSkillTarget),
        priorBuild = tonumber(interruption and interruption.currentBuild or restartModel and restartModel.priorBuild),
        currentRecipe = restartModel and restartModel.currentRecipe or nil,
        currentRecipeID = tonumber(restartModel and restartModel.currentRecipeID),
        currentSkillTarget = tonumber(restartModel and restartModel.currentSkillTarget),
        currentSkill = tonumber(restartModel and restartModel.currentSkill),
        currentBuild = tonumber(restartModel and restartModel.currentBuild) or currentBuild(),
        restartState = restartModel and restartModel.state or "craft-all-restart-unavailable",
        restartContract = restartModel and restartModel.contract or nil,
        restartReady = restartModel and restartModel.restartReady == true or false,
        plannerHandoffRequired = disposition == "planner-handoff-required",
        waitForResolution = disposition == "wait-for-resolution",
        automaticResume = false,
        automaticRouteAdvance = false,
        nativeDispatchAllowed = false,
        persisted = false,
    }
    self.lastByProfession[professionKey] = copy(model)
    return model
end

function ResearchNativeCraftAllResolutionMatrix:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ResearchNativeCraftAllResolutionMatrix:GetSummary(professionKey, mode, options)
    local model = self:Analyze(professionKey, mode, options)
    local lines = {
        "CRAFT ALL / RESTART-RESOLUTION MATRIX",
        tostring(model.professionKey) .. " / " .. tostring(model.mode),
        "Contract: " .. self.contract,
        "Disposition: " .. tostring(model.disposition),
        "Reason: " .. tostring(model.reason),
        "Interruption: " .. tostring(model.interruptionCategory or "none"),
        "Prior recipe: " .. tostring(model.priorRecipe or "none") .. " / " .. tostring(model.priorRecipeID or "unresolved"),
        "Current recipe: " .. tostring(model.currentRecipe or "none") .. " / " .. tostring(model.currentRecipeID or "unresolved"),
        "Prior target: " .. tostring(model.priorSkillTarget or "unknown"),
        "Current target: " .. tostring(model.currentSkillTarget or "unknown"),
        "Automatic resume: disabled",
        "Automatic route advance: disabled",
        "Native dispatch: forbidden",
        "Persistence: none",
    }
    return table.concat(lines, "\n")
end

function ResearchNativeCraftAllResolutionMatrix:Validate()
    local errors, warnings = {}, {}
    if self.automaticResume ~= false or self.automaticRouteAdvance ~= false or self.nativeDispatchAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "Craft All restart-resolution safety boundary invalid"
    end
    for _, name in ipairs({"ResearchNativeCraftAllInterruption", "ResearchNativeCraftAllRestart", "ProductionTailoringCraftAllRestart"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "Craft All restart-resolution dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeCraftAllResolutionMatrix", ResearchNativeCraftAllResolutionMatrix)
