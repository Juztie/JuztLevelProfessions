local _, JLP = ...

-- Alpha107 observes bounded target-edge fixtures across every real production
-- Tailoring route step.  It never dispatches crafting itself.  A coverage run is
-- complete only when all 21 staged recipe identities have crossed the guarded
-- production Craft One boundary and all 20 adjacent route transitions have been
-- proven by the post-settlement step-transition orchestrator.
local Coverage = {
    contract = "production-tailoring-auto-route-all-step-native-coverage-v1",
    recipeCoverageContract = "production-tailoring-auto-route-native-recipe-coverage-v1",
    transitionCoverageContract = "production-tailoring-auto-route-native-transition-coverage-v1",
    authority = "observational-production-tailoring-all-step-native-coverage-only",
    professionKey = "TAILORING",
    nativeDispatchAllowed = false,
    automaticExecutionAllowed = false,
    persisted = false,
    initialized = false,
    run = nil,
    lastAudit = nil,
}

local function copy(row)
    local out = {}
    for k,v in pairs(row or {}) do out[k] = v end
    return out
end

local function productionSourceContract()
    local source = JLP:GetModule("ProductionTailoringAutoRouteAuthority")
    return source and source.contract or "production-tailoring-auto-route-authority-v1"
end

local function productionNativeProvenance()
    local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    return native and native.provenanceContract or "production-tailoring-native-dispatch-provenance-v1"
end

local function productionTransitionContract()
    local transition = JLP:GetModule("ResearchNativeStepTransition")
    return transition and transition.productionTailoringTransitionContract or "production-tailoring-native-route-step-handoff-v1"
end

local function terminal(status)
    status = tostring(status or "")
    return status == "success" or status == "failed" or status == "timeout" or status == "aborted_unknown"
end

function Coverage:Reset(label)
    self.run = {
        contract = self.contract,
        recipeCoverageContract = self.recipeCoverageContract,
        transitionCoverageContract = self.transitionCoverageContract,
        authority = self.authority,
        professionKey = self.professionKey,
        label = tostring(label or "runtime"),
        terminalActions = 0,
        duplicateTerminalActions = 0,
        recipeCoverage = {},
        transitionCoverage = {},
        terminalLedgers = {},
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
    }
    self.lastAudit = nil
    return self.run
end

function Coverage:_EnsureRun()
    return self.run or self:Reset("runtime")
end

function Coverage:ObserveCraftAction(action)
    if type(action) ~= "table" or tostring(action.key or ""):upper() ~= self.professionKey then return false end
    if not terminal(action.status) then return false end
    local provenance = type(action.authorityProvenance) == "table" and action.authorityProvenance or nil
    if not provenance
        or tostring(provenance.contract or "") ~= tostring(productionNativeProvenance())
        or tostring(provenance.autoRouteSourceAuthorityContract or "") ~= tostring(productionSourceContract())
        or not provenance.autoRouteSessionToken then
        return false
    end

    local ledgerID = tostring(action.ledgerID or action.transactionID or "")
    if ledgerID == "" then return false end
    local run = self:_EnsureRun()
    if run.terminalLedgers[ledgerID] then
        run.duplicateTerminalActions = run.duplicateTerminalActions + 1
        return false
    end

    local routeIndex = tonumber(provenance.autoRouteRouteIndex or provenance.routeIndex)
    local recipeID = tonumber(action.recipeID or provenance.autoRouteRecipeID or provenance.recipeID)
    run.terminalLedgers[ledgerID] = true
    run.terminalActions = run.terminalActions + 1
    if routeIndex then
        run.recipeCoverage[routeIndex] = {
            contract = self.recipeCoverageContract,
            routeIndex = routeIndex,
            recipe = action.recipeName or provenance.recipe,
            recipeID = recipeID,
            ledgerID = ledgerID,
            status = tostring(action.status or "unknown"),
            confirmedCount = tonumber(action.completedCount) or 0,
            startedSkill = tonumber(action.startedSkill),
            endingSkill = tonumber(action.endingSkill),
            sessionToken = provenance.autoRouteSessionToken,
            ordinal = tonumber(provenance.autoRouteOrdinal),
            sourceAuthorityContract = provenance.autoRouteSourceAuthorityContract,
        }
    end
    return true
end

function Coverage:ObserveStepTransition(report)
    if type(report) ~= "table" or tostring(report.professionKey or ""):upper() ~= self.professionKey then return false end
    if report.transitionReady ~= true or tostring(report.transitionContract or "") ~= tostring(productionTransitionContract()) then return false end
    local fromIndex,toIndex = tonumber(report.fromRouteIndex),tonumber(report.toRouteIndex)
    if not fromIndex or not toIndex then return false end
    local run = self:_EnsureRun()
    run.transitionCoverage[fromIndex] = {
        contract = self.transitionCoverageContract,
        ledgerID = report.ledgerID,
        fromRouteIndex = fromIndex,
        toRouteIndex = toIndex,
        fromRecipe = report.fromRecipe,
        fromRecipeID = tonumber(report.fromRecipeID),
        toRecipe = report.toRecipe,
        toRecipeID = tonumber(report.toRecipeID),
        sourceProvenanceContract = report.sourceProvenanceContract,
        snapshotChanged = report.snapshotChanged == true,
        routeAuthorityReacquired = report.routeAuthorityReacquired == true,
    }
    return true
end

function Coverage:Audit()
    local run = self:_EnsureRun()
    local dataset = JLP.data and JLP.data.tailoring or nil
    local route = dataset and (dataset.route or dataset.steps) or nil
    local ledger = JLP:GetModule("TransactionLedger")
    local report = {
        contract = self.contract,
        recipeCoverageContract = self.recipeCoverageContract,
        transitionCoverageContract = self.transitionCoverageContract,
        authority = self.authority,
        professionKey = self.professionKey,
        label = run.label,
        expectedRecipes = type(route) == "table" and #route or 0,
        recipesCovered = 0,
        expectedTransitions = type(route) == "table" and math.max(0,#route-1) or 0,
        transitionsCovered = 0,
        terminalActions = run.terminalActions,
        duplicateTerminalActions = run.duplicateTerminalActions,
        recipeIdentityErrors = 0,
        transitionIdentityErrors = 0,
        ledgerErrors = 0,
        missingRecipeRoutes = {},
        missingTransitionRoutes = {},
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
    }

    if type(route) ~= "table" or #route == 0 then
        report.state = "production-tailoring-native-coverage-route-unavailable"
        report.coverageComplete = false
        self.lastAudit = report
        return copy(report)
    end

    for i,step in ipairs(route) do
        local expectedID = tonumber(step.recipeID)
        local observed = run.recipeCoverage[i]
        if observed then
            report.recipesCovered = report.recipesCovered + 1
            if tonumber(observed.recipeID) ~= expectedID or tostring(observed.status or "") ~= "success" or tonumber(observed.confirmedCount) ~= 1 then
                report.recipeIdentityErrors = report.recipeIdentityErrors + 1
            end
            local tx = ledger and ledger.GetTransaction and ledger:GetTransaction(observed.ledgerID) or nil
            if not tx or tostring(tx.status or "") ~= "success" or tonumber(tx.confirmedCount) ~= 1 or tonumber(tx.recipeID) ~= expectedID then
                report.ledgerErrors = report.ledgerErrors + 1
            end
        else
            report.missingRecipeRoutes[#report.missingRecipeRoutes + 1] = i
        end

        if i < #route then
            local nextStep = route[i+1]
            local transition = run.transitionCoverage[i]
            if transition then
                report.transitionsCovered = report.transitionsCovered + 1
                if tonumber(transition.fromRouteIndex) ~= i
                    or tonumber(transition.toRouteIndex) ~= i + 1
                    or tonumber(transition.fromRecipeID) ~= expectedID
                    or tonumber(transition.toRecipeID) ~= tonumber(nextStep.recipeID)
                    or transition.snapshotChanged ~= true
                    or transition.routeAuthorityReacquired ~= true
                    or tostring(transition.sourceProvenanceContract or "") ~= tostring(productionNativeProvenance())
                    or not run.terminalLedgers[tostring(transition.ledgerID or "")] then
                    report.transitionIdentityErrors = report.transitionIdentityErrors + 1
                end
            else
                report.missingTransitionRoutes[#report.missingTransitionRoutes + 1] = i
            end
        end
    end

    report.coverageComplete = report.recipesCovered == report.expectedRecipes
        and report.transitionsCovered == report.expectedTransitions
        and report.duplicateTerminalActions == 0
        and report.recipeIdentityErrors == 0
        and report.transitionIdentityErrors == 0
        and report.ledgerErrors == 0
    report.state = report.coverageComplete and "production-tailoring-auto-route-all-step-native-coverage-complete" or "production-tailoring-auto-route-all-step-native-coverage-incomplete"
    self.lastAudit = report
    return copy(report)
end

function Coverage:GetLast()
    return self.lastAudit and copy(self.lastAudit) or nil
end

function Coverage:GetSummary()
    local r = self:Audit()
    local lines = {
        "PRODUCTION TAILORING / ALL-STEP NATIVE AUTO ROUTE COVERAGE",
        "Contract: "..self.contract,
        "Recipe coverage: "..tostring(r.recipesCovered).." / "..tostring(r.expectedRecipes),
        "Route transition coverage: "..tostring(r.transitionsCovered).." / "..tostring(r.expectedTransitions),
        "Terminal Craft One ledgers observed: "..tostring(r.terminalActions),
        "Duplicate terminal observations: "..tostring(r.duplicateTerminalActions),
        "Recipe identity errors: "..tostring(r.recipeIdentityErrors),
        "Transition identity errors: "..tostring(r.transitionIdentityErrors),
        "Ledger errors: "..tostring(r.ledgerErrors),
        "Coverage state: "..tostring(r.state),
        "Native dispatch from coverage monitor: forbidden",
        "Automatic execution from coverage monitor: forbidden",
        "Persistence: none",
    }
    return table.concat(lines,"\n")
end

function Coverage:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("RESEARCH_NATIVE_STEP_TRANSITION_UPDATED", function(report) self:ObserveStepTransition(report) end)
    end
    return true
end

function Coverage:Validate()
    local errors,warnings = {},{}
    if self.nativeDispatchAllowed ~= false or self.automaticExecutionAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "production Tailoring native coverage monitor crossed observational authority boundary"
    end
    for _,name in ipairs({"ProductionTailoringAutoRouteAuthority","ProductionTailoringNativeExecutionAuthority","ResearchNativeStepTransition","TransactionLedger"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "production Tailoring native coverage dependency missing: "..name end
    end
    return #errors == 0,errors,warnings
end

JLP:RegisterModule("ProductionTailoringAutoRouteNativeCoverage", Coverage)
