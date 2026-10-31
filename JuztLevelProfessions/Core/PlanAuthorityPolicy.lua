local _, JLP = ...

local Policy = {
    contract = "plan-authority-policy-v1",
    categories = {
        PRODUCTION = "PRODUCTION",
        RESEARCH_SHADOW = "RESEARCH_SHADOW",
        CONTROLLED_RESEARCH = "CONTROLLED_RESEARCH",
        PRODUCTION_CANDIDATE_READONLY = "PRODUCTION_CANDIDATE_READONLY",
        HISTORICAL_REFERENCE_READONLY = "HISTORICAL_REFERENCE_READONLY",
        PUBLIC_REFERENCE_READONLY = "PUBLIC_REFERENCE_READONLY",
        BLOCKED = "BLOCKED",
    },
}

function Policy:Classify(plan)
    if type(plan)=="table" and plan.actionKind=="complete" and
        plan.goalObserved==true and plan.readOnly==true and
        plan.executionEligible==false and plan.nativeDispatchAllowed==false then
        return {contract=self.contract,category=self.categories.PUBLIC_REFERENCE_READONLY,
            readOnly=true,reason="observed-skill-goal-no-native-action"}
    end
    if type(plan)=="table" and plan.actionKind=="reference" and
        plan.referenceOnly==true and plan.readOnly==true and
        plan.executionEligible==false and plan.nativeDispatchAllowed==false then
        return {contract=self.contract,category=self.categories.PUBLIC_REFERENCE_READONLY,
            readOnly=true,reason="advisory-reference-no-verified-route"}
    end
    local dataset = plan and plan.step and plan.step.dataset
    if type(plan) ~= "table" or type(dataset) ~= "table" then
        return {contract=self.contract,category=self.categories.BLOCKED,readOnly=true,reason="plan-or-dataset-missing"}
    end

    if plan.readOnlyRouteFallback == true and plan.readOnly == true and
        plan.executionEligible == false and plan.nativeDispatchAllowed == false and
        dataset.readOnlyRouteFallback == true and dataset.readOnly == true and
        dataset.executionEligible == false and dataset.nativeDispatchAllowed == false then
        return {contract=self.contract,category=self.categories.HISTORICAL_REFERENCE_READONLY,
            readOnly=true,reason=dataset.fallbackReason,sourceBuild=dataset.originalSourceBuild}
    end

    if plan.executionEligible == true and dataset.executionEligible ~= false then
        return {contract=self.contract,category=self.categories.PRODUCTION,readOnly=false,reason=nil}
    end

    if plan.shadow == true and plan.readOnly == true and plan.plannerEligible == false
        and dataset.shadow == true and dataset.plannerEligible == false then
        return {contract=self.contract,category=self.categories.RESEARCH_SHADOW,readOnly=true,reason=nil}
    end

    if plan.plannerEligible == true and plan.routeAuthorityEnabled == true
        and dataset.readOnly == true and dataset.plannerEligible == true and dataset.executionEligible == false then
        return {contract=self.contract,category=self.categories.CONTROLLED_RESEARCH,readOnly=true,reason=nil}
    end

    if plan.productionCandidate == true and plan.readOnly == true and plan.plannerEligible == true
        and plan.routeAuthorityEnabled ~= true and dataset.productionCandidate == true
        and dataset.readOnly == true and dataset.plannerEligible == true
        and dataset.executionEligible == false and dataset.nativeDispatchAllowed == false then
        return {contract=self.contract,category=self.categories.PRODUCTION_CANDIDATE_READONLY,readOnly=true,reason=nil}
    end

    return {contract=self.contract,category=self.categories.BLOCKED,readOnly=true,reason="unclassified-plan-authority"}
end

function Policy:IsReadOnlyConsumable(plan)
    local row = self:Classify(plan)
    return row.category == self.categories.PUBLIC_REFERENCE_READONLY
        or row.category == self.categories.HISTORICAL_REFERENCE_READONLY
        or row.category == self.categories.RESEARCH_SHADOW
        or row.category == self.categories.CONTROLLED_RESEARCH
        or row.category == self.categories.PRODUCTION_CANDIDATE_READONLY, row
end

JLP:RegisterModule("PlanAuthorityPolicy", Policy)
