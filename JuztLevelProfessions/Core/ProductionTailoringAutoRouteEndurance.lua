local _, JLP = ...

-- Alpha105 performs a deterministic, read-only endurance simulation over the real
-- production Tailoring route.  It deliberately never calls a native crafting API.
-- Every route `expectedCrafts` unit is modeled as one Craft One ordinal and skill
-- gains are distributed deterministically across those ordinals, preserving both
-- no-skill-up settlements and exact target transitions.
local Endurance = {
    contract = "production-tailoring-auto-route-1-300-endurance-v1",
    simulationContract = "production-tailoring-auto-route-deterministic-settlement-simulation-v1",
    boundaryContract = "production-tailoring-auto-route-endurance-boundary-v1",
    authority = "read-only-real-production-route-endurance-simulation-only",
    professionKey = "TAILORING",
    nativeDispatchAllowed = false,
    automaticExecutionAllowed = false,
    automaticTrainerActions = false,
    automaticMaterialActions = false,
    persisted = false,
    last = nil,
}


local function recipeID(plan)
    local step = plan and plan.rawStep or nil
    return tonumber(plan and plan.recipeID)
        or tonumber(step and step.recipeID)
        or tonumber(plan and plan.datasetStep and plan.datasetStep.recipeID)
end

local function addError(report, code, detail)
    report.errors[#report.errors + 1] = { code=code, detail=detail }
end

local function addBoundary(report, category, skill, routeIndex, recipe, extra)
    local row = {
        contract = Endurance.boundaryContract,
        category = category,
        skill = tonumber(skill),
        routeIndex = tonumber(routeIndex),
        recipe = recipe,
        automaticAction = false,
    }
    for k,v in pairs(extra or {}) do row[k] = v end
    report.boundaries[#report.boundaries + 1] = row
    return row
end

local INJECTED = {
    -- Real lifecycle mechanics for these categories are independently covered by
    -- alpha103/104 native regressions.  Alpha105 injects them into the long route
    -- to prove repeated fresh-session segmentation does not alter route/target order.
    [4]  = { ordinal=7, category="WINDOW_LOST" },
    [12] = { ordinal=4, category="MATERIALS" },
    [18] = { ordinal=5, category="AUTHORITY_REVOKED" },
}

function Endurance:Simulate(datasetOverride)
    local planner = JLP:GetModule("Planner")
    local dataset = datasetOverride or (planner and planner.GetDataset and planner:GetDataset(self.professionKey)) or (JLP.data and JLP.data.tailoring)
    local route = dataset and (dataset.route or dataset.steps) or nil
    local report = {
        contract = self.contract,
        simulationContract = self.simulationContract,
        boundaryContract = self.boundaryContract,
        authority = self.authority,
        professionKey = self.professionKey,
        sourceBuild = tonumber(dataset and dataset.sourceBuild),
        routeStepCount = type(route)=="table" and #route or 0,
        expectedCraftOrdinals = 0,
        simulatedCraftOrdinals = 0,
        skillGainOrdinals = 0,
        zeroGainOrdinals = 0,
        routeTransitions = 0,
        targetOvershoots = 0,
        prematureRouteTransitions = 0,
        recipeDriftErrors = 0,
        trainerBoundaries = 0,
        injectedBoundaries = 0,
        freshRestarts = 0,
        reloadRestarts = 0,
        sessionCount = 0,
        currentSessionCrafts = 0,
        maxSessionCrafts = 0,
        startSkill = 1,
        endingSkill = nil,
        finalState = nil,
        boundaries = {},
        steps = {},
        errors = {},
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        automaticTrainerActions = false,
        automaticMaterialActions = false,
        persisted = false,
    }

    if not planner or type(route) ~= "table" or #route == 0 then
        addError(report, "tailoring-endurance-route-unavailable", "production Planner/Tailoring route unavailable")
        report.state = "production-tailoring-auto-route-endurance-failed"
        self.last = report
        return report
    end

    local promotion = JLP:GetModule("ProductionTailoringAutoRouteAuthority")
    local identity = JLP:GetModule("ProductionTailoringRecipeIdentity")
    local staged = identity and identity.AuditStaged and dataset == (JLP.data and JLP.data.tailoring) and identity:AuditStaged() or nil
    report.uniqueRecipeCount = staged and staged.stagedRecipeCount or 0
    report.structuralReady = staged and staged.stagedComplete == true or false
    local craftOne = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    local consumer = JLP:GetModule("ResearchPlannerConsumerBridge")
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    if not (promotion and promotion.IsSupported and promotion:IsSupported(self.professionKey)) then
        addError(report, "tailoring-endurance-auto-route-capability-missing", "production Tailoring Auto Route capability unavailable")
    end
    if not (craftOne and craftOne.IsSupported and craftOne:IsSupported(self.professionKey)) then
        addError(report, "tailoring-endurance-craft-one-capability-missing", "production Tailoring Craft One capability unavailable")
    end
    if not (consumer and consumer.IsSupported and consumer:IsSupported(self.professionKey)) then
        addError(report, "tailoring-endurance-consumer-capability-missing", "production Tailoring consumer authority unavailable")
    end
    if not (readiness and readiness.IsSupported and readiness:IsSupported(self.professionKey)) then
        addError(report, "tailoring-endurance-readiness-capability-missing", "production Tailoring execution readiness unavailable")
    end

    local trainerByCap = {}
    for _,gate in ipairs(dataset.trainerGates or {}) do trainerByCap[tonumber(gate.cap)] = gate end

    local skill = 1
    local cap = 75
    local sessionSerial = 1
    report.sessionCount = 1

    local function closeSession(category, routeIndex, recipe, extra)
        report.maxSessionCrafts = math.max(report.maxSessionCrafts, report.currentSessionCrafts)
        report.currentSessionCrafts = 0
        addBoundary(report, category, skill, routeIndex, recipe, extra)
        report.freshRestarts = report.freshRestarts + 1
        report.sessionCount = report.sessionCount + 1
        sessionSerial = sessionSerial + 1
    end

    local function resolveMandatoryTrainer(routeIndex, recipe)
        if skill < cap or cap >= 300 then return true end
        local gate = trainerByCap[cap]
        if not gate then
            addError(report, "tailoring-endurance-trainer-gate-missing", "missing trainer gate at cap "..tostring(cap))
            return false
        end
        local trainPlan = planner:GetCurrentStep(self.professionKey, {skill=skill,maxSkill=cap}, dataset)
        if not trainPlan or trainPlan.kind ~= "train" or tonumber(trainPlan.trainer and trainPlan.trainer.nextCap) ~= tonumber(gate.nextCap) then
            addError(report, "tailoring-endurance-trainer-planner-mismatch", "Planner did not return mandatory TRAIN at "..tostring(cap))
            return false
        end
        report.trainerBoundaries = report.trainerBoundaries + 1
        closeSession("TRAIN", routeIndex, recipe, { fromCap=cap, nextCap=tonumber(gate.nextCap), session=sessionSerial })
        cap = tonumber(gate.nextCap) or cap
        return true
    end

    for routeIndex, step in ipairs(route) do
        local stepMin = tonumber(step.skillMin)
        local target = tonumber(step.skillTarget)
        local crafts = math.floor(tonumber(step.expectedCrafts) or 0)
        local rid = tonumber(step.recipeID)
        local delta = target and stepMin and (target - stepMin) or -1
        local stepReport = {
            routeIndex=routeIndex, recipe=step.recipe, recipeID=rid,
            skillMin=stepMin, skillTarget=target, expectedCrafts=crafts,
            simulatedCrafts=0, skillGains=0, zeroGains=0,
            startSession=sessionSerial, endSession=nil,
        }
        report.steps[#report.steps + 1] = stepReport

        if stepMin ~= skill then
            addError(report, "tailoring-endurance-step-start-skill-mismatch", string.format("route %d expected skill %s but simulation is %s",routeIndex,tostring(stepMin),tostring(skill)))
            skill = stepMin or skill
        end
        if not rid then addError(report, "tailoring-endurance-missing-recipe-id", "route "..routeIndex.." has no staged recipeID") end
        if crafts < 1 or delta < 1 or crafts < delta then
            addError(report, "tailoring-endurance-invalid-craft-budget", string.format("route %d invalid expectedCrafts=%s delta=%s",routeIndex,tostring(crafts),tostring(delta)))
        end
        report.expectedCraftOrdinals = report.expectedCraftOrdinals + math.max(0,crafts)

        local injected = INJECTED[routeIndex]
        for ordinal=1,crafts do
            if not resolveMandatoryTrainer(routeIndex, step.recipe) then break end

            -- Use maxSkill=300 for deterministic route identity. Mandatory trainer
            -- behavior is verified separately above, avoiding location-dependent
            -- early-trainer recommendations from changing the endurance result.
            local plan = planner:GetCurrentStep(self.professionKey, {skill=skill,maxSkill=300}, dataset)
            local planID = recipeID(plan)
            if not plan or plan.kind ~= "craft" or tonumber(plan.routeIndex) ~= routeIndex or tostring(plan.recipe or "") ~= tostring(step.recipe or "") or planID ~= rid then
                report.recipeDriftErrors = report.recipeDriftErrors + 1
                addError(report, "tailoring-endurance-planner-recipe-drift", string.format("route %d ordinal %d planner=%s/%s/%s expected=%s/%s",routeIndex,ordinal,tostring(plan and plan.routeIndex),tostring(plan and plan.recipe),tostring(planID),tostring(step.recipe),tostring(rid)))
                break
            end

            report.simulatedCraftOrdinals = report.simulatedCraftOrdinals + 1
            report.currentSessionCrafts = report.currentSessionCrafts + 1
            stepReport.simulatedCrafts = stepReport.simulatedCrafts + 1

            local before = math.floor(((ordinal - 1) * delta) / crafts)
            local after = math.floor((ordinal * delta) / crafts)
            local gain = after - before
            if gain < 0 or gain > 1 then
                addError(report, "tailoring-endurance-invalid-skill-gain-model", string.format("route %d ordinal %d gain=%d",routeIndex,ordinal,gain))
                gain = math.max(0,math.min(1,gain))
            end
            skill = skill + gain
            if gain > 0 then
                report.skillGainOrdinals = report.skillGainOrdinals + 1
                stepReport.skillGains = stepReport.skillGains + 1
            else
                report.zeroGainOrdinals = report.zeroGainOrdinals + 1
                stepReport.zeroGains = stepReport.zeroGains + 1
            end

            if skill > target then
                report.targetOvershoots = report.targetOvershoots + 1
                addError(report, "tailoring-endurance-target-overshoot", string.format("route %d ordinal %d skill %d > target %d",routeIndex,ordinal,skill,target))
            end
            if skill >= target and ordinal < crafts then
                report.prematureRouteTransitions = report.prematureRouteTransitions + 1
                addError(report, "tailoring-endurance-target-reached-before-budget-end", string.format("route %d target reached at ordinal %d/%d",routeIndex,ordinal,crafts))
            end

            if injected and ordinal == injected.ordinal and skill < target then
                report.injectedBoundaries = report.injectedBoundaries + 1
                closeSession(injected.category, routeIndex, step.recipe, { recipeID=rid, target=target, ordinal=ordinal, injected=true, session=sessionSerial })
            end
        end

        stepReport.endSession = sessionSerial
        if skill ~= target then
            addError(report, "tailoring-endurance-target-not-reached", string.format("route %d ended at skill %d instead of %d",routeIndex,skill,target))
        end

        if target == 153 then
            -- Mirror the alpha104 production /reload-at-target case in the long
            -- simulation: old session is terminal and the next route starts fresh.
            report.reloadRestarts = report.reloadRestarts + 1
            closeSession("RELOAD_NO_RESUME", routeIndex, step.recipe, { recipeID=rid, target=target, routeChanging=true, injected=true, session=sessionSerial })
        end

        -- If the target is itself a profession rank cap (225), TRAIN takes
        -- precedence before the next recipe can be considered current.
        if skill >= cap and cap < 300 then resolveMandatoryTrainer(routeIndex, step.recipe) end

        if routeIndex < #route then
            local nextStep = route[routeIndex + 1]
            local plan = planner:GetCurrentStep(self.professionKey, {skill=skill,maxSkill=300}, dataset)
            local nextID = recipeID(plan)
            if plan and plan.kind=="craft" and tonumber(plan.routeIndex)==routeIndex+1 and tostring(plan.recipe or "")==tostring(nextStep.recipe or "") and nextID==tonumber(nextStep.recipeID) then
                report.routeTransitions = report.routeTransitions + 1
            else
                report.prematureRouteTransitions = report.prematureRouteTransitions + 1
                addError(report, "tailoring-endurance-route-transition-mismatch", string.format("after route %d planner did not move exactly to route %d",routeIndex,routeIndex+1))
            end
        end
    end

    report.maxSessionCrafts = math.max(report.maxSessionCrafts, report.currentSessionCrafts)
    report.endingSkill = skill
    local complete = planner:GetCurrentStep(self.professionKey, {skill=skill,maxSkill=300}, dataset)
    report.finalState = complete and complete.kind or nil
    if skill ~= 300 or report.finalState ~= "complete" then
        addError(report, "tailoring-endurance-not-complete", "simulation did not terminate at skill 300 / complete")
    end
    local capValue = promotion and promotion.GetSafetyCraftCap and promotion:GetSafetyCraftCap() or 250
    report.safetyCraftCap = tonumber(capValue) or 250
    report.safetyCapExceeded = report.maxSessionCrafts > report.safetyCraftCap
    if report.safetyCapExceeded then
        addError(report, "tailoring-endurance-safety-cap-exceeded", string.format("max session crafts %d > cap %d",report.maxSessionCrafts,report.safetyCraftCap))
    end

    report.passed = #report.errors == 0
        and report.routeStepCount == 31
        and report.simulatedCraftOrdinals == report.expectedCraftOrdinals
        and report.skillGainOrdinals == 299
        and report.zeroGainOrdinals == (report.expectedCraftOrdinals - 299)
        and report.routeTransitions == 30
        and report.trainerBoundaries == 3
        and report.targetOvershoots == 0
        and report.recipeDriftErrors == 0
        and report.endingSkill == 300
        and report.finalState == "complete"
    report.state = report.passed and "production-tailoring-auto-route-endurance-pass" or "production-tailoring-auto-route-endurance-failed"
    self.last = report
    return report
end

function Endurance:GetLast()
    return self.last
end

function Endurance:GetSummary()
    local r = self:Simulate()
    local lines = {
        "PRODUCTION TAILORING / AUTO ROUTE 1-300 ENDURANCE",
        "Contract: "..self.contract,
        "Simulation: "..self.simulationContract,
        "State: "..tostring(r.state),
        "Route segments: "..tostring(r.routeStepCount).." / 31",
        "Unique recipe identities: "..tostring(r.uniqueRecipeCount or 0).." / 21",
        "Segment identity/interval structure: "..(r.structuralReady and "valid" or "unverified"),
        "Craft ordinals: "..tostring(r.simulatedCraftOrdinals).." / "..tostring(r.expectedCraftOrdinals),
        "Skill-gain ordinals: "..tostring(r.skillGainOrdinals).." / 299",
        "No-skill-gain settlements: "..tostring(r.zeroGainOrdinals),
        "Route transitions: "..tostring(r.routeTransitions).." / 30",
        "Trainer boundaries: "..tostring(r.trainerBoundaries).." / 3",
        "Injected fresh boundaries: "..tostring(r.injectedBoundaries),
        "Reload no-resume boundaries: "..tostring(r.reloadRestarts),
        "Fresh session generations: "..tostring(r.sessionCount),
        "Max crafts in one simulated session: "..tostring(r.maxSessionCrafts).." / safety cap "..tostring(r.safetyCraftCap),
        "Target overshoots: "..tostring(r.targetOvershoots),
        "Planner/recipe drift errors: "..tostring(r.recipeDriftErrors),
        "Ending skill: "..tostring(r.endingSkill).." / 300",
        "Native dispatch from endurance simulator: forbidden",
        "Automatic trainer/material actions: forbidden",
        "Persistence: none",
    }
    if #r.errors > 0 then
        lines[#lines+1] = "Errors:"
        for _,row in ipairs(r.errors) do lines[#lines+1] = "- "..tostring(row.code)..": "..tostring(row.detail or "") end
    end
    return table.concat(lines,"\n")
end

function Endurance:Validate()
    local errors,warnings = {},{}
    if self.nativeDispatchAllowed~=false or self.automaticExecutionAllowed~=false or self.automaticTrainerActions~=false or self.automaticMaterialActions~=false or self.persisted~=false then
        errors[#errors+1] = "production Tailoring Auto Route endurance safety boundary invalid"
    end
    for _,name in ipairs({"Planner","ProductionTailoringAutoRouteAuthority","ProductionTailoringNativeExecutionAuthority","ResearchPlannerConsumerBridge","ResearchExecutionReadiness","ProductionTailoringAutoRouteRestart"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "production Tailoring Auto Route endurance dependency missing: "..name end
    end
    local r = self:Simulate()
    if not r.passed then errors[#errors+1] = "production Tailoring Auto Route 1-300 endurance simulation failed" end
    return #errors==0,errors,warnings
end

JLP:RegisterModule("ProductionTailoringAutoRouteEndurance", Endurance)
