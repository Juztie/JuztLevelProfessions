local _, JLP = ...
-- Unified, transient source-first read-only Alchemy candidate route. Original
-- registered dataset and 13 historical rows remain untouched/auditable.
local View={contract="forever-alchemy-candidate-view-v1",nativeDispatchAllowed=false,
    executionEligible=false,persisted=false,requiresLiveQA=false}
local function clone(x,depth)
    if type(x)~="table" then return x end
    depth=(depth or 0)+1
    if depth>20 then return nil end
    local out={}
    for k,v in pairs(x) do out[k]=clone(v,depth) end
    return out
end
local function goodInt(n)
    return type(n)=="number" and n>0 and n==math.floor(n)
end
function View:Build(key,dataset)
    if key~="ALCHEMY" or type(dataset)~="table" or dataset.key~="ALCHEMY"
        or dataset.sourceBuild~=70245 or dataset.productionCandidate~=true
        or dataset.readOnly~=true or dataset.nativeDispatchAllowed~=false
        or dataset.executionEligible~=false or dataset.routeAuthorityEnabled~=false then
        return nil,"ALCHEMY_CANDIDATE_AUTHORITY_INVALID"
    end
    local authority=JLP:GetModule("ForeverRecipeAuthority")
    local raw,why=authority and authority:GetEffectiveRoute(key,"normal")
    if not raw then return nil,why or "ALCHEMY_EFFECTIVE_ROUTE_MISSING" end
    if not raw.starterCorrection or raw.starterCorrection.status~="SOURCE_BACKED"
        or raw.unverifiedCraftSteps~=0 then
        return nil,"ALCHEMY_SOURCE_ROUTE_INCOMPLETE"
    end
    local steps,expected={},1
    for i,s in ipairs(raw.steps) do
      if s.kind=="craft" then
        if s.referenceStatus~="WOWHEAD_FOREVER_AUTHORITATIVE"
            or s.skillGateConflict or not goodInt(s.expectedCrafts)
            or type(s.skillMin)~="number" or s.skillMin~=expected
            or type(s.skillTarget)~="number" or s.skillTarget<=s.skillMin
            or s.skillTarget>300 then
            return nil,"ALCHEMY_SOURCE_STEP_INVALID:"..tostring(i)
        end
        local reference=authority:GetReference(key,s.recipeID)
        if not reference or reference.name~=s.recipe
            or not goodInt(s.recipeID) or #reference.reagents~=#(s.requirements or {}) then
            return nil,"ALCHEMY_RECIPE_REFERENCE_INVALID:"..tostring(i)
        end
        if reference.requiredSkill and s.skillMin<reference.requiredSkill then
            return nil,"ALCHEMY_SKILL_GATE_INVALID:"..tostring(i)
        end
        local sourceByID={}
        for _,material in pairs(dataset.materials or {}) do
            if type(material)=="table" then sourceByID[material.itemID]=material.source end
        end
        local mats,seen={},{}
        for _,reagent in ipairs(reference.reagents) do
            if not goodInt(reagent.itemID) or not goodInt(reagent.quantity)
                or seen[reagent.itemID] then
                return nil,"ALCHEMY_MATERIAL_REFERENCE_INVALID:"..tostring(i)
            end
            seen[reagent.itemID]=true
            mats[#mats+1]={itemID=reagent.itemID,name=reagent.name,
                quantity=reagent.quantity,source=sourceByID[reagent.itemID] or "auction",
                authority="WOWHEAD_FOREVER",sourceURL=reference.sourceURL}
        end
        local step={kind="craft",recipe=s.recipe,recipeID=s.recipeID,
            routeIndex=i,skillMin=s.skillMin,skillTarget=s.skillTarget,
            expectedCrafts=s.expectedCrafts,materials=mats,
            recipeSource=clone(s.recipeSource or "trainer"),
            sourceRequirement=clone(s.sourceRequirement),
            requiredSkill=reference.requiredSkill,
            requiredSkillAuthority=reference.skillBasis=="WOWHEAD_FOREVER" and "WOWHEAD_FOREVER" or "UNVERIFIED",
            referenceStatus="WOWHEAD_FOREVER_AUTHORITATIVE",
            referenceURL=reference.sourceURL,sourceBuild=reference.sourceBuild,
            estimatedCrafts=true,plannerEligible=true,readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false,
            routeAuthorityEnabled=false,starterCorrection=s.starterCorrection==true}
        if step.sourceRequirement then
            local access=JLP:GetModule("ForeverRecipeAccessBridge")
            local proof=access and access:Resolve(key,s)
            if step.recipeID==17553 and not proof then
                return nil,"ALCHEMY_ACCESS_ITEM_SOURCE_UNRESOLVED"
            end
            if proof then
                step.sourceRequirement={kind="recipe",name=step.recipe,
                    itemID=proof.recipeItemID,requiredSkill=proof.requiredSkillToLearn,
                    sourceURL=proof.itemURL,sourceVerified=true,
                    vendorStock="UNKNOWN",learnedState="NOT_OBSERVED"}
            end
        end
        steps[#steps+1]=step
        expected=s.skillTarget
      elseif s.kind~="train" then
        return nil,"ALCHEMY_UNKNOWN_ROUTE_STEP:"..tostring(i)
      end
    end
    if #steps~=14 then return nil,"ALCHEMY_SOURCE_ROUTE_CRAFT_COUNT" end
    if expected~=300 then return nil,"ALCHEMY_300_COVERAGE_GAP" end
    return {contract=self.contract,professionKey="ALCHEMY",sourceBuild=70245,
        route=steps,steps=steps,trainerGates=clone(dataset.trainerGates),
        readOnly=true,productionCandidate=true,executionEligible=false,
        nativeDispatchAllowed=false,routeAuthorityEnabled=false,
        originalDatasetUnchanged=true,estimatedCraftsOnly=true,
        sourceBackedRecipeCount=#steps},nil
end
function View:GetAtSkill(key,dataset,skill)
    local view,why=self:Build(key,dataset)
    if not view then return nil,nil,why end
    skill=tonumber(skill)
    if not skill then return nil,nil,"SKILL_MISSING" end
    if skill<1 then skill=1 end
    for i,step in ipairs(view.steps) do
        if skill>=step.skillMin and skill<step.skillTarget then
            return clone(step),i,nil
        end
    end
    return nil,nil,"ALCHEMY_SKILL_OUTSIDE_SOURCE_ROUTE"
end
JLP:RegisterModule("ForeverAlchemyCandidateView",View)
