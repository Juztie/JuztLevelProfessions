local _, JLP = ...

-- Alpha96 validates the actual production Tailoring/Enchanting datasets against
-- the live Planner contract without granting any execution authority.  This is
-- deliberately read-only: the audit may prove route continuity and identify the
-- exact reasons a route is not yet eligible for Production Auto Route, but it
-- must never relax staged recipe identity, target-aware Enchant One safety or native
-- execution gates in order to make a route pass.
local ProductionRouteEnduranceAudit = {
    contract = "production-real-route-1-300-endurance-audit-v1",
    eligibilityContract = "production-auto-route-real-route-eligibility-audit-v1",
    authority = "read-only-real-route-endurance-validation-v1",
    nativeDispatchAllowed = false,
    automaticExecutionAllowed = false,
    persisted = false,
    supportedProfessions = { TAILORING=true, ENCHANTING=true },
}

local function normalizeKey(value)
    local key=tostring(value or ""):upper()
    return key~="" and key or nil
end

local function currentBuild()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    -- An unobserved build must not be substituted from historical constants.
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function addBlocker(model, code, detail)
    model.executionBlockers[#model.executionBlockers+1]={code=code,detail=detail}
end

local function routeRows(dataset)
    return dataset and (dataset.route or dataset.steps) or nil
end

local function plannerState(key,dataset,skill,maxSkill)
    return {
        key=key,
        name=dataset and dataset.name or key,
        skill=tonumber(skill) or 0,
        maxSkill=tonumber(maxSkill) or 300,
        cached=false,
    }
end

function ProductionRouteEnduranceAudit:IsSupported(professionKey)
    return self.supportedProfessions[normalizeKey(professionKey) or ""]==true
end

function ProductionRouteEnduranceAudit:AuditProfession(professionKey)
    professionKey=normalizeKey(professionKey) or "TAILORING"
    local planner=JLP:GetModule("Planner")
    local dataset=planner and planner.GetDataset and planner:GetDataset(professionKey) or nil
    local route=routeRows(dataset) or {}
    local model={
        contract=self.contract,
        eligibilityContract=self.eligibilityContract,
        authority=self.authority,
        professionKey=professionKey,
        currentBuild=currentBuild(),
        sourceBuild=dataset and tonumber(dataset.sourceBuild) or nil,
        datasetStatus=dataset and dataset.datasetStatus or nil,
        routeStepCount=#route,
        trainerGateCount=dataset and #(dataset.trainerGates or {}) or 0,
        skillMin=dataset and tonumber(dataset.skillMin) or nil,
        skillMax=dataset and tonumber(dataset.skillMax) or nil,
        structuralErrors={},
        plannerMismatches={},
        trainerErrors={},
        executionBlockers={},
        stagedRecipeIDCount=0,
        missingRecipeIDCount=0,
        targetTransitionChecks=0,
        sameRecipeChecks=0,
        sourceRecipeSteps=0,
        nativeDispatchAllowed=false,
        automaticExecutionAllowed=false,
        persisted=false,
        targetedExecutionRequired=professionKey=="ENCHANTING",
    }

    if not self:IsSupported(professionKey) then
        model.state="production-route-endurance-unsupported-profession"
        model.routeReady=false
        addBlocker(model,"unsupported-profession","alpha96 audits only production Tailoring and Enchanting")
        return model
    end
    if not planner or not dataset or #route==0 then
        model.state="production-route-endurance-dataset-unavailable"
        model.routeReady=false
        addBlocker(model,"dataset-unavailable","production Planner dataset is unavailable")
        return model
    end

    if tonumber(dataset.skillMin)~=1 then model.structuralErrors[#model.structuralErrors+1]="dataset-skill-min-not-1" end
    if tonumber(dataset.skillMax)~=300 then model.structuralErrors[#model.structuralErrors+1]="dataset-skill-max-not-300" end
    -- A production route is an archived source contract. Its structural validity
    -- never depends on the running client's build number. Fresh recipes and
    -- native actions are evaluated separately by their own live safety gates.
    if tonumber(dataset.sourceBuild)~=70009 or
       tonumber(dataset.productionBaselineBuild)~=70009 or
       dataset.legacyProductionBaseline~=true then
        model.structuralErrors[#model.structuralErrors+1]="dataset-source-provenance-invalid"
    end
    if tostring(dataset.datasetStatus or "")~="route-1-300-integrated" then model.structuralErrors[#model.structuralErrors+1]="dataset-status-not-integrated" end

    local expectedMin=1
    for index,step in ipairs(route) do
        local a=tonumber(step.skillMin)
        local b=tonumber(step.skillTarget)
        if not a or not b or b<=a then
            model.structuralErrors[#model.structuralErrors+1]=string.format("step-%d-invalid-skill-range",index)
        else
            if a~=expectedMin then
                model.structuralErrors[#model.structuralErrors+1]=string.format("step-%d-noncontiguous-%s-expected-%s",index,tostring(a),tostring(expectedMin))
            end
            expectedMin=b
        end
        if tostring(step.recipe or "")=="" then model.structuralErrors[#model.structuralErrors+1]=string.format("step-%d-recipe-missing",index) end
        if tonumber(step.recipeID) then model.stagedRecipeIDCount=model.stagedRecipeIDCount+1 else model.missingRecipeIDCount=model.missingRecipeIDCount+1 end
        if step.recipeSource and step.recipeSource~="trainer" then model.sourceRecipeSteps=model.sourceRecipeSteps+1 end
    end
    if expectedMin~=300 then model.structuralErrors[#model.structuralErrors+1]="route-does-not-end-at-300" end

    -- Exhaustively validate every production skill point against the actual
    -- Planner dataset. maxSkill=300 intentionally suppresses trainer boundaries
    -- here so this loop isolates recipe/target/route-index continuity.
    local prior
    for skill=1,299 do
        local expectedStep,expectedIndex
        for index,step in ipairs(route) do
            if skill>=(tonumber(step.skillMin) or 0) and skill<(tonumber(step.skillTarget) or 0) then expectedStep,expectedIndex=step,index; break end
        end
        local planned=planner:GetCurrentStep(professionKey,plannerState(professionKey,dataset,skill,300),dataset)
        local mismatch=not expectedStep or not planned or planned.kind~="craft"
            or tostring(planned.recipe or "")~=tostring(expectedStep and expectedStep.recipe or "")
            or tonumber(planned.skillTarget)~=tonumber(expectedStep and expectedStep.skillTarget)
            or tonumber(planned.routeIndex)~=tonumber(expectedIndex)
        if mismatch then
            model.plannerMismatches[#model.plannerMismatches+1]={skill=skill,expectedRecipe=expectedStep and expectedStep.recipe or nil,expectedRouteIndex=expectedIndex,actualKind=planned and planned.kind or nil,actualRecipe=planned and planned.recipe or nil,actualRouteIndex=planned and planned.routeIndex or nil}
        end
        if prior and expectedStep then
            if expectedIndex==prior.index then
                model.sameRecipeChecks=model.sameRecipeChecks+1
                if skill>=prior.target then model.structuralErrors[#model.structuralErrors+1]=string.format("same-recipe-after-target-at-%d",skill) end
            elseif expectedIndex==prior.index+1 then
                model.targetTransitionChecks=model.targetTransitionChecks+1
                if skill~=prior.target then model.structuralErrors[#model.structuralErrors+1]=string.format("route-transition-before-or-after-target-at-%d",skill) end
            else
                model.structuralErrors[#model.structuralErrors+1]=string.format("route-index-jump-at-%d",skill)
            end
        end
        if expectedStep then prior={index=expectedIndex,target=tonumber(expectedStep.skillTarget) or skill,recipe=expectedStep.recipe} end
    end

    local complete=planner:GetCurrentStep(professionKey,plannerState(professionKey,dataset,300,300),dataset)
    if not complete or complete.kind~="complete" then model.plannerMismatches[#model.plannerMismatches+1]={skill=300,actualKind=complete and complete.kind or nil} end

    -- Trainer boundaries are validated independently at the mandatory cap. This
    -- remains deterministic even when TrainerOptimizer recommends an earlier
    -- visit in the real client.
    for index,gate in ipairs(dataset.trainerGates or {}) do
        local cap=tonumber(gate.cap)
        local nextCap=tonumber(gate.nextCap)
        local atCap=cap and planner:GetCurrentStep(professionKey,plannerState(professionKey,dataset,cap,cap),dataset) or nil
        if not atCap or atCap.kind~="train" or not atCap.trainer or tonumber(atCap.trainer.nextCap)~=nextCap then
            model.trainerErrors[#model.trainerErrors+1]=string.format("trainer-gate-%d-not-mandatory-at-cap-%s",index,tostring(cap))
        end
        local after=cap and nextCap and planner:GetCurrentStep(professionKey,plannerState(professionKey,dataset,cap,nextCap),dataset) or nil
        if not after or after.kind=="train" then model.trainerErrors[#model.trainerErrors+1]=string.format("trainer-gate-%d-did-not-release-after-training",index) end
    end

    model.routeReady=#model.structuralErrors==0 and #model.plannerMismatches==0 and #model.trainerErrors==0
    model.coverageSkills=299
    model.expectedTargetTransitions=math.max(0,#route-1)

    -- Native Auto Route eligibility is intentionally stricter than route
    -- continuity.  Do not infer/guess recipe IDs and never reinterpret targeted
    -- Enchanting as CraftRecipe-compatible execution.
    local consumerBridge=JLP:GetModule("ResearchPlannerConsumerBridge")
    local executionReadiness=JLP:GetModule("ResearchExecutionReadiness")
    local nativeAuthority=JLP:GetModule("ResearchNativeExecutionAuthority")
    local tailoringCraftOne=JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    local enchantingCraftOne=JLP:GetModule("ProductionEnchantingNativeExecutionAuthority")
    local tailoringCraftAll=JLP:GetModule("ProductionTailoringCraftAllAuthority")
    local tailoringAutoRoute=JLP:GetModule("ProductionTailoringAutoRouteAuthority")
    local enchantingRouteCoverage=JLP:GetModule("ProductionEnchantingNativeRouteCoverage")
    local enchantingCraftAll=JLP:GetModule("ProductionEnchantingCraftAllAuthority")
    model.consumerAuthoritySupported=consumerBridge and consumerBridge.IsSupported and consumerBridge:IsSupported(professionKey) or false
    model.executionReadinessSupported=executionReadiness and executionReadiness.IsSupported and executionReadiness:IsSupported(professionKey) or false
    model.nativeCraftOneAuthoritySupported=(professionKey=="TAILORING")
        and (tailoringCraftOne and tailoringCraftOne.IsSupported and tailoringCraftOne:IsSupported(professionKey) or false)
        or ((professionKey=="ENCHANTING")
            and (enchantingCraftOne and enchantingCraftOne.IsSupported and enchantingCraftOne:IsSupported(professionKey) or false)
            or (nativeAuthority and nativeAuthority.IsSupported and nativeAuthority:IsSupported(professionKey) or false))
    model.nativeCraftAllAuthoritySupported=(professionKey=="TAILORING")
        and (tailoringCraftAll and tailoringCraftAll.IsSupported and tailoringCraftAll:IsSupported(professionKey) or false)
        or false
    model.enchantingCraftAllPlanningSupported=(professionKey=="ENCHANTING")
        and (enchantingCraftAll and enchantingCraftAll.IsSupported and enchantingCraftAll:IsSupported(professionKey) or false)
        or false
    model.enchantingCraftAllNativeExecutionSupported=false
    model.enchantingCraftAllExplicitTargetBatchRequired=professionKey=="ENCHANTING"
    model.enchantingCraftAllAutomaticTargetSelectionAllowed=false
    local enchantingCoverageModel=(professionKey=="ENCHANTING" and enchantingRouteCoverage and enchantingRouteCoverage.Audit)
        and enchantingRouteCoverage:Audit() or nil
    model.nativeEnchantOneRouteCoverageReady=professionKey~="ENCHANTING"
        or (enchantingCoverageModel and enchantingCoverageModel.routeReady==true)
    model.nativeEnchantOneRouteCoverageCount=enchantingCoverageModel and tonumber(enchantingCoverageModel.exactIdentityCount) or 0
    -- Tailoring remains the only production profession promoted into native Auto Route.
    -- Alpha111 promotes Enchanting only through target-aware Craft One; automatic
    -- target selection and Enchanting Auto Route deliberately remain unpromoted.
    model.nativeAuthoritySupported=(professionKey=="TAILORING")
        and (tailoringAutoRoute and tailoringAutoRoute.IsSupported and tailoringAutoRoute:IsSupported(professionKey) or false)
        or (nativeAuthority and nativeAuthority.IsSupported and nativeAuthority:IsSupported(professionKey) or false)
    if model.missingRecipeIDCount>0 then addBlocker(model,"missing-staged-recipe-ids",string.format("%d/%d route steps do not carry an exact staged recipeID",model.missingRecipeIDCount,#route)) end
    if not model.consumerAuthoritySupported then addBlocker(model,"consumer-authority-unsupported","production dataset is not currently promoted into the controlled Auto Route consumer authority") end
    if not model.executionReadinessSupported then addBlocker(model,"execution-readiness-unsupported","production dataset is not currently promoted into the controlled execution-readiness evaluator") end
    if not model.nativeAuthoritySupported then addBlocker(model,"native-auto-route-authority-unsupported","current guarded native Auto Route authority does not support this production profession") end
    if model.targetedExecutionRequired and not model.nativeCraftOneAuthoritySupported then addBlocker(model,"targeted-enchant-execution-required","Enchanting requires Optional Target + CraftEnchant semantics and must not be coerced through CraftRecipe") end
    if model.targetedExecutionRequired and not model.nativeEnchantOneRouteCoverageReady then addBlocker(model,"native-enchant-one-all-route-coverage-incomplete","All eight production Enchanting route identities must pass the read-only native Enchant One coverage audit") end
    if model.targetedExecutionRequired and model.enchantingCraftAllPlanningSupported and not model.enchantingCraftAllNativeExecutionSupported then addBlocker(model,"targeted-enchant-craft-all-native-unpromoted","Target-aware Enchanting sequence planning uses an explicit ordered target batch, but native multi-target queuing/execution remains intentionally unpromoted") end
    if model.targetedExecutionRequired and model.nativeCraftOneAuthoritySupported then addBlocker(model,"targeted-enchant-auto-route-unpromoted","Target-aware Craft One is supported, but automatic target selection/Auto Route remains intentionally unpromoted") end
    if not model.routeReady then addBlocker(model,"route-endurance-validation-failed","route/Planner/trainer continuity must pass before any execution promotion") end

    model.autoRouteExecutionEligible=model.routeReady and #model.executionBlockers==0
    model.state=model.routeReady and (model.autoRouteExecutionEligible and "production-route-endurance-pass-auto-route-eligible" or "production-route-endurance-pass-execution-blocked") or "production-route-endurance-failed"
    return model
end

function ProductionRouteEnduranceAudit:AuditAll()
    local results={}
    local passed=0
    for _,key in ipairs({"TAILORING","ENCHANTING"}) do
        local model=self:AuditProfession(key)
        results[key]=model
        if model.routeReady then passed=passed+1 end
    end
    return {
        contract=self.contract,
        eligibilityContract=self.eligibilityContract,
        state=passed==2 and "production-route-endurance-all-pass" or "production-route-endurance-partial-or-failed",
        passedProfessions=passed,
        totalProfessions=2,
        results=results,
        nativeDispatchAllowed=false,
        automaticExecutionAllowed=false,
        persisted=false,
    }
end

function ProductionRouteEnduranceAudit:GetSummary(professionKey)
    local model=self:AuditProfession(professionKey)
    local lines={
        "PRODUCTION ROUTE / 1-300 ENDURANCE AUDIT",
        tostring(model.professionKey or professionKey or "unknown"),
        "Contract: "..self.contract,
        "Eligibility contract: "..self.eligibilityContract,
        "State: "..tostring(model.state or "unknown"),
        "Dataset: "..tostring(model.datasetStatus or "unavailable").." · build "..tostring(model.sourceBuild or "?"),
        "Route steps: "..tostring(model.routeStepCount or 0),
        "Planner skill coverage: "..tostring(model.coverageSkills or 0).." / 299",
        "Target transitions verified: "..tostring(model.targetTransitionChecks or 0).." / "..tostring(model.expectedTargetTransitions or 0),
        "Trainer gates: "..tostring(model.trainerGateCount or 0).." · errors "..tostring(#(model.trainerErrors or {})),
        "Structural errors: "..tostring(#(model.structuralErrors or {})),
        "Planner mismatches: "..tostring(#(model.plannerMismatches or {})),
        "Exact staged recipe IDs: "..tostring(model.stagedRecipeIDCount or 0).." / "..tostring(model.routeStepCount or 0),
        "Controlled consumer support: "..(model.consumerAuthoritySupported and "yes" or "no"),
        "Execution readiness support: "..(model.executionReadinessSupported and "yes" or "no"),
        "Guarded native Craft One support: "..(model.nativeCraftOneAuthoritySupported and "yes" or "no"),
        "Native Enchant One route coverage: "..(model.nativeEnchantOneRouteCoverageReady and "yes" or "no")..(model.professionKey=="ENCHANTING" and (" · "..tostring(model.nativeEnchantOneRouteCoverageCount or 0).." / 8") or ""),
        "Guarded native Craft All support: "..(model.nativeCraftAllAuthoritySupported and "yes" or "no"),
        "Enchanting target-sequence readiness/planning: "..(model.enchantingCraftAllPlanningSupported and "yes" or "no"),
        "Enchanting explicit target batch required: "..(model.enchantingCraftAllExplicitTargetBatchRequired and "yes" or "no"),
        "Enchanting automatic target selection: "..(model.enchantingCraftAllAutomaticTargetSelectionAllowed and "yes" or "no"),
        "Enchanting native multi-target queue/execution: "..(model.enchantingCraftAllNativeExecutionSupported and "yes" or "no"),
        "Guarded native Auto Route support: "..(model.nativeAuthoritySupported and "yes" or "no"),
        "Targeted execution required: "..(model.targetedExecutionRequired and "yes" or "no"),
        "Production Auto Route eligible now: "..(model.autoRouteExecutionEligible and "yes" or "no"),
        "Native dispatch from audit: forbidden",
        "Persistence: none",
    }
    if #(model.executionBlockers or {})>0 then
        lines[#lines+1]="Execution blockers:"
        for _,row in ipairs(model.executionBlockers) do lines[#lines+1]="- "..tostring(row.code)..": "..tostring(row.detail or "") end
    end
    return table.concat(lines,"\n")
end

function ProductionRouteEnduranceAudit:Validate()
    local errors,warnings={},{}
    if self.nativeDispatchAllowed~=false or self.automaticExecutionAllowed~=false or self.persisted~=false then errors[#errors+1]="Production route endurance audit safety boundary invalid" end
    local all=self:AuditAll()
    if not all or tonumber(all.passedProfessions)~=2 then errors[#errors+1]="Production Tailoring/Enchanting 1-300 route endurance validation failed" end
    for _,key in ipairs({"TAILORING","ENCHANTING"}) do
        local model=all.results and all.results[key] or nil
        if not model or model.routeReady~=true then errors[#errors+1]=key.." production route is not 1-300 endurance ready" end
        if model and model.autoRouteExecutionEligible==true then
            local expectedPromotion = key=="TAILORING" and JLP:GetModule("ProductionTailoringAutoRouteAuthority") or nil
            if not (expectedPromotion and expectedPromotion.contract=="production-tailoring-auto-route-authority-v1") then
                warnings[#warnings+1]=key.." production Auto Route execution became eligible without a recognized controlled promotion authority"
            end
        end
    end
    return #errors==0,errors,warnings
end

JLP:RegisterModule("ProductionRouteEnduranceAudit",ProductionRouteEnduranceAudit)
