local _, JLP = ...

-- Alpha83 classifies boundary-resolution restarts as either same-route or
-- route-changing.  It never creates execution authority.  Its job is to prove
-- that a restart which lands on a different route step has a fresh, coherent
-- identity and to purge any stale in-memory execution artifacts from the old
-- step before a new explicit-click restart candidate may be consumed.
local ResearchRouteChangingRestart = {
    contract = "route-changing-boundary-restart-matrix-v1",
    transitionContract = "research-boundary-route-transition-v1",
    authority = "restart-transition-classification-and-stale-artifact-revocation-only",
    persisted = false,
    automaticResume = false,
    lastByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function identityChanged(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) ~= tostring(b)
end

function ResearchRouteChangingRestart:Assess(model)
    model = type(model) == "table" and model or {}
    local professionKey = normalizeKey(model.professionKey)
    local report = {
        contract = self.contract,
        transitionContract = self.transitionContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = model.mode,
        state = "restart-transition-evaluating",
        persisted = false,
        automaticResume = false,
        priorRecipe = model.priorRecipe,
        priorRecipeID = tonumber(model.priorRecipeID),
        priorRouteIndex = tonumber(model.priorRouteIndex),
        priorSkillTarget = tonumber(model.priorSkillTarget),
        currentRecipe = model.currentRecipe,
        currentRecipeID = tonumber(model.currentRecipeID),
        currentRouteIndex = tonumber(model.currentRouteIndex),
        currentSkillTarget = tonumber(model.currentSkillTarget),
        currentBuild = tonumber(model.currentBuild),
    }

    local recipeChanged = identityChanged(report.priorRecipeID or report.priorRecipe, report.currentRecipeID or report.currentRecipe)
    local routeChanged = identityChanged(report.priorRouteIndex, report.currentRouteIndex)
    local targetChanged = identityChanged(report.priorSkillTarget, report.currentSkillTarget)
    report.recipeChanged = recipeChanged
    report.routeIndexChanged = routeChanged
    report.skillTargetChanged = targetChanged
    report.routeChanged = recipeChanged or routeChanged
    report.transitionKind = report.routeChanged and "route-changing" or "same-route"

    if report.routeChanged then
        if not report.currentRecipe or not report.currentRecipeID or not report.currentRouteIndex then
            report.state = "route-changing-restart-identity-unresolved"
            report.ready = false
            return report
        end
        if report.priorRecipeID and report.currentRecipeID == report.priorRecipeID and report.priorRouteIndex and report.currentRouteIndex == report.priorRouteIndex then
            report.state = "route-changing-restart-identity-not-changed"
            report.ready = false
            return report
        end
        report.state = "route-changing-restart-verified"
        report.ready = true
    else
        report.state = "same-route-restart-verified"
        report.ready = true
    end
    return report
end

function ResearchRouteChangingRestart:Harden(model)
    local report = self:Assess(model)
    if report.ready ~= true then return false, report.state, report end
    if report.routeChanged == true then
        local readiness = JLP:GetModule("ResearchExecutionReadiness")
        if readiness and readiness.RevokeIntentsForProfession then
            readiness:RevokeIntentsForProfession(report.professionKey, "alpha83-route-changing-restart")
        end
        local gate = JLP:GetModule("ResearchExecutionAuthorityGate")
        if gate and gate.InvalidateProfession then
            gate:InvalidateProfession(report.professionKey, "alpha83-route-changing-restart")
        end
        report.oldExecutionArtifactsPurged = true
    else
        report.oldExecutionArtifactsPurged = false
    end
    if report.professionKey then self.lastByProfession[report.professionKey] = shallowCopy(report) end
    return true, report.state, report
end

function ResearchRouteChangingRestart:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and shallowCopy(row) or nil
end

function ResearchRouteChangingRestart:GetSummary(professionKey)
    local row = self:GetLast(professionKey)
    local lines = {
        "RESEARCH BOUNDARY RESTART / ROUTE TRANSITION MATRIX",
        tostring(normalizeKey(professionKey) or "UNKNOWN"),
        "Contract: " .. self.contract,
        "Authority: classification + stale-artifact revocation only",
        "Automatic resume: disabled",
        "Persistence: none",
        "Last transition: " .. tostring(row and row.transitionKind or "none"),
        "Last state: " .. tostring(row and row.state or "none"),
    }
    if row then
        lines[#lines + 1] = "Old route: " .. tostring(row.priorRouteIndex or "?") .. " / " .. tostring(row.priorRecipe or row.priorRecipeID or "unknown")
        lines[#lines + 1] = "New route: " .. tostring(row.currentRouteIndex or "?") .. " / " .. tostring(row.currentRecipe or row.currentRecipeID or "unknown")
        lines[#lines + 1] = "Old execution artifacts purged: " .. (row.oldExecutionArtifactsPurged and "yes" or "no")
    end
    return table.concat(lines, "\n")
end

function ResearchRouteChangingRestart:Validate()
    local errors, warnings = {}, {}
    if self.persisted ~= false then errors[#errors + 1] = "route-changing restart matrix must not persist" end
    if self.automaticResume ~= false then errors[#errors + 1] = "route-changing restart matrix must never auto-resume" end
    for _, name in ipairs({"ResearchExecutionReadiness", "ResearchExecutionAuthorityGate"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "route-changing restart dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchRouteChangingRestart", ResearchRouteChangingRestart)
