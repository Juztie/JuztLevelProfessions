local _, JLP = ...

-- Alpha113 is a read-only release coverage audit for the complete production
-- Enchanting route.  It does not grant execution authority and never calls
-- CraftEnchant.  Its purpose is to pin the eight production route identities to
-- the already-promoted target-aware Enchant One + settlement contracts so a
-- release cannot silently lose one recipe while still passing a single fixture.
local ProductionEnchantingNativeRouteCoverage = {
    contract = "production-enchanting-native-all-route-coverage-audit-v1",
    enduranceContract = "production-enchanting-native-single-enchant-route-endurance-v1",
    authorityContract = "production-enchanting-native-single-enchant-authority-v1",
    settlementContract = "production-enchanting-native-single-enchant-settlement-v1",
    professionKey = "ENCHANTING",
    expectedRouteCount = 8,
    readOnly = true,
    nativeDispatchAllowed = false,
    executionAuthorityEnabled = false,
    craftAllAllowed = false,
    autoRouteAllowed = false,
    confirmationAutomationAllowed = false,
    persisted = false,
    expected = {
        { index=1, skillMin=1,   skillTarget=15,  recipeID=7418,  recipe="Enchant Bracer - Inferior Stamina" },
        { index=2, skillMin=15,  skillTarget=90,  recipeID=7420,  recipe="Enchant Chest - Inferior Stamina" },
        { index=3, skillMin=90,  skillTarget=130, recipeID=7771,  recipe="Enchant Cloak - Minor Protection" },
        { index=4, skillMin=130, skillTarget=180, recipeID=13501, recipe="Enchant Bracer - Lesser Stamina" },
        { index=5, skillMin=180, skillTarget=210, recipeID=13661, recipe="Enchant Bracer - Strength" },
        { index=6, skillMin=210, skillTarget=259, recipeID=13815, recipe="Enchant Gloves - Agility" },
        { index=7, skillMin=259, skillTarget=272, recipeID=13939, recipe="Enchant Bracer - Greater Strength" },
        { index=8, skillMin=272, skillTarget=300, recipeID=20017, recipe="Enchant Shield - Greater Stamina" },
    },
}

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    return value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

function ProductionEnchantingNativeRouteCoverage:Audit()
    local dataset = JLP.data and JLP.data.enchanting or nil
    local route = dataset and (dataset.route or dataset.steps) or nil
    local identity = JLP:GetModule("ProductionEnchantingRecipeIdentity")
    local identityAudit = identity and identity.AuditStaged and identity:AuditStaged() or nil
    local native = JLP:GetModule("ProductionEnchantingNativeExecutionAuthority")
    local settlement = JLP:GetModule("ProductionEnchantingNativeSettlement")
    local model = {
        contract = self.contract,
        enduranceContract = self.enduranceContract,
        professionKey = self.professionKey,
        state = "production-enchanting-native-route-coverage-blocked",
        routeReady = false,
        expectedRouteCount = self.expectedRouteCount,
        routeStepCount = type(route) == "table" and #route or 0,
        exactIdentityCount = 0,
        targetedBoundaryCount = 0,
        materialPlanCount = 0,
        toolPlanCount = 0,
        -- Read-only source/route coverage is build-independent; this is NOT
        -- permission to invoke CraftEnchant on the current client.
        buildReady = dataset ~= nil and tonumber(dataset.sourceBuild) == 70009
            and tonumber(dataset.productionBaselineBuild) == 70009
            and dataset.legacyProductionBaseline == true,
        clientBuild = currentBuild(),
        identityStagingReady = identityAudit ~= nil and identityAudit.stagedComplete == true,
        authorityContractReady = native ~= nil and native.contract == self.authorityContract,
        settlementContractReady = settlement ~= nil and settlement.settlementContract == self.settlementContract,
        errors = {},
        rows = {},
        readOnly = true,
        nativeDispatchAllowed = false,
        executionAuthorityEnabled = false,
        craftAllAllowed = false,
        autoRouteAllowed = false,
        confirmationAutomationAllowed = false,
        persisted = false,
    }

    if type(route) ~= "table" then
        model.errors[#model.errors + 1] = "production-enchanting-route-unavailable"
        return model
    end
    if #route ~= self.expectedRouteCount then
        model.errors[#model.errors + 1] = string.format("route-count-%d-expected-%d", #route, self.expectedRouteCount)
    end

    for index, expected in ipairs(self.expected) do
        local step = route[index]
        local row = {
            index = index,
            expectedRecipeID = expected.recipeID,
            expectedRecipe = expected.recipe,
            recipeID = step and tonumber(step.recipeID) or nil,
            recipe = step and step.recipe or nil,
            skillMin = step and tonumber(step.skillMin) or nil,
            skillTarget = step and tonumber(step.skillTarget) or nil,
            exactIdentity = false,
            targetedBoundary = false,
            materialPlan = false,
            toolPlan = false,
            ready = false,
        }
        if step then
            row.exactIdentity = row.recipeID == expected.recipeID
                and normalizeText(row.recipe) == normalizeText(expected.recipe)
                and row.skillMin == expected.skillMin
                and row.skillTarget == expected.skillTarget
                and step.recipeIdentitySource == "wowhead-forever"
                and step.liveCurrentBuildCorroborationRequired == true
            row.targetedBoundary = step.targetedExecutionRequired == true
                and step.targetedExecutionAPI == "C_TradeSkillUI.CraftEnchant"
                and step.targetIdentity == "item-guid"
                and step.targetLocationAuthority == "live-item-location"
            row.materialPlan = type(step.materials) == "table" and #step.materials > 0
            row.toolPlan = type(step.requiredTool) == "table"
                and tonumber(step.requiredTool.itemID) ~= nil
                and tostring(step.requiredTool.name or "") ~= ""
            if row.exactIdentity then model.exactIdentityCount = model.exactIdentityCount + 1 end
            if row.targetedBoundary then model.targetedBoundaryCount = model.targetedBoundaryCount + 1 end
            if row.materialPlan then model.materialPlanCount = model.materialPlanCount + 1 end
            if row.toolPlan then model.toolPlanCount = model.toolPlanCount + 1 end
            row.ready = row.exactIdentity and row.targetedBoundary and row.materialPlan and row.toolPlan
        end
        if not row.ready then
            model.errors[#model.errors + 1] = string.format("route-%d-coverage-mismatch", index)
        end
        model.rows[#model.rows + 1] = row
    end

    if not model.buildReady then model.errors[#model.errors + 1] = "dataset-source-provenance-invalid" end
    if not model.identityStagingReady then model.errors[#model.errors + 1] = "recipe-identity-staging-incomplete" end
    if not model.authorityContractReady then model.errors[#model.errors + 1] = "native-enchant-one-authority-contract-mismatch" end
    if not model.settlementContractReady then model.errors[#model.errors + 1] = "native-enchant-one-settlement-contract-mismatch" end

    model.routeReady = #model.errors == 0
        and model.exactIdentityCount == self.expectedRouteCount
        and model.targetedBoundaryCount == self.expectedRouteCount
        and model.materialPlanCount == self.expectedRouteCount
        and model.toolPlanCount == self.expectedRouteCount
    model.state = model.routeReady
        and "production-enchanting-native-route-coverage-ready"
        or "production-enchanting-native-route-coverage-blocked"
    return model
end

function ProductionEnchantingNativeRouteCoverage:GetSummary()
    local model = self:Audit()
    local lines = {
        "PRODUCTION ENCHANTING / NATIVE ENCHANT ONE ALL-ROUTE COVERAGE",
        "Contract: " .. self.contract,
        "Endurance contract: " .. self.enduranceContract,
        "State: " .. tostring(model.state),
        string.format("Exact recipe identities: %d / %d", model.exactIdentityCount or 0, self.expectedRouteCount),
        string.format("Target-aware boundaries: %d / %d", model.targetedBoundaryCount or 0, self.expectedRouteCount),
        string.format("Material plans: %d / %d", model.materialPlanCount or 0, self.expectedRouteCount),
        string.format("Required-tool plans: %d / %d", model.toolPlanCount or 0, self.expectedRouteCount),
        "Historical source provenance qualified: " .. (model.buildReady and "yes" or "no") .. " · client " .. tostring(model.clientBuild or "unknown"),
        "Recipe identity staging: " .. (model.identityStagingReady and "ready" or "blocked"),
        "Native Enchant One authority contract: " .. (model.authorityContractReady and "ready" or "blocked"),
        "Settlement contract: " .. (model.settlementContractReady and "ready" or "blocked"),
        "Release endurance proof: runtime-harness matrix; live dispatch still requires a fresh explicit click and target proof",
        "Craft All: disabled",
        "Auto Route: disabled",
        "Protected Replace/Bind automation: forbidden",
        "Native dispatch from coverage audit: forbidden",
        "Persistence: none",
    }
    if #(model.errors or {}) > 0 then
        lines[#lines + 1] = "Coverage errors:"
        for _, value in ipairs(model.errors) do lines[#lines + 1] = "- " .. tostring(value) end
    end
    return table.concat(lines, "\n")
end

function ProductionEnchantingNativeRouteCoverage:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.nativeDispatchAllowed ~= false or self.executionAuthorityEnabled ~= false
        or self.craftAllAllowed ~= false or self.autoRouteAllowed ~= false
        or self.confirmationAutomationAllowed ~= false or self.persisted ~= false then
        errors[#errors + 1] = "production Enchanting native route coverage safety boundary invalid"
    end
    if #self.expected ~= self.expectedRouteCount then errors[#errors + 1] = "production Enchanting expected route matrix count mismatch" end
    local audit = self:Audit()
    if not audit.routeReady then
        for _, value in ipairs(audit.errors or {}) do errors[#errors + 1] = "route coverage: " .. tostring(value) end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingNativeRouteCoverage", ProductionEnchantingNativeRouteCoverage)
