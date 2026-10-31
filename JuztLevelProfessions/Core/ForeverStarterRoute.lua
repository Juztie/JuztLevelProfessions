local _, JLP = ...
-- Source-backed starter route corrections for RESEARCH and READ-ONLY candidate plans.
-- No persistent mutation, no native CraftRecipe/CraftEnchant, no Live-QA requirement.
local S={contract="forever-readonly-starter-route-v1",nativeDispatchAllowed=false,
    executionEligible=false,persisted=false}
local function copy(v,depth)
    if type(v)~="table" then return v end
    depth=(depth or 0)+1
    if depth>18 then return nil end
    local result={}
    for k,x in pairs(v) do result[k]=copy(x,depth) end
    return result
end
local function correction(key)
    local d=JLP.data and JLP.data.foreverStarterCorrections
    return d and d[tostring(key or ""):upper()],d
end
function S:Resolve(key)
    local policy,root=correction(key)
    if not policy then return nil,"NOT_APPLICABLE" end
    if not root or root.sourceBuild~=70245 then return nil,"STARTER_SOURCE_BUILD_MISMATCH" end
    local authority=JLP:GetModule("ForeverRecipeAuthority")
    local old=authority and authority:GetReference(key,policy.blockedRecipeID)
    local alternative=authority and authority:GetReference(key,policy.substituteRecipeID)
    if not old or not alternative or alternative.recipeID==old.recipeID
       or old.requiredSkill~=policy.blockedMinSkill
       or alternative.requiredSkill~=policy.substituteMinSkill
       or alternative.skillBasis~="WOWHEAD_FOREVER"
       or old.skillBasis~="WOWHEAD_FOREVER"
       or policy.correctionEndSkill~=old.requiredSkill
       or policy.substituteOrangeThrough < policy.correctionEndSkill
       or alternative.sourceBuild~=root.sourceBuild or old.sourceBuild~=root.sourceBuild
       then return nil,"STARTER_REFERENCE_UNVERIFIED" end
    return {policy=policy,blocked=old,substitute=alternative},nil
end
local function verifiedMaterials(reference,key)
    local out={}
    local provider=JLP:GetModule("ProfessionDatasetProvider")
    local dataset=provider and provider:GetRegisteredDataset(key)
    local sourceByItemID={}
    for _,material in pairs(dataset and dataset.materials or {}) do
        if type(material)=="table" and tonumber(material.itemID) then
            sourceByItemID[material.itemID]=material.source
        end
    end
    for _,m in ipairs(reference.reagents) do
        out[#out+1]={itemID=m.itemID,name=m.name,quantity=m.quantity,
            source=sourceByItemID[m.itemID] or "auction",
            authority="WOWHEAD_FOREVER",sourceURL=reference.sourceURL}
    end
    return out
end
-- Only the read-only research copy is changed; underlying research steps are not.
function S:CorrectEffectiveRoute(key,route)
    local def,reason=self:Resolve(key)
    if not def then return route,reason end
    local first=route and route.steps and route.steps[1]
    if not first or first.kind~="craft" or first.recipe~=def.blocked.name
       or tonumber(first.skillMin)>def.policy.substituteMinSkill
       or tonumber(first.skillTarget)<=def.policy.correctionEndSkill then
        return route,"STARTER_ROUTE_NOT_MATCHED"
    end
    local oldFrom=math.max(tonumber(first.skillMin) or 1,1)
    local corrected=copy(first)
    corrected.recipe=def.substitute.name
    corrected.recipeID=def.substitute.recipeID
    corrected.skillMin=oldFrom
    corrected.skillTarget=def.policy.correctionEndSkill
    corrected.expectedCrafts=corrected.skillTarget-oldFrom -- orange; source skill threshold recorded
    corrected.estimated=true
    corrected.skillUpBasis="WOWHEAD_FOREVER_ORANGE_SKILL_RANGE"
    corrected.starterCorrection=true
    corrected.sourceProofURL=def.substitute.sourceURL
    first.skillMin=def.policy.correctionEndSkill
    -- Single orange craft is sufficient for the 10->11 research target.
    first.expectedCrafts=first.skillTarget-first.skillMin
    first.estimated=true
    first.starterCorrection=true
    first.skillUpBasis="WOWHEAD_FOREVER_ORANGE_SKILL_RANGE"
    table.insert(route.steps,1,corrected)
    route.starterCorrection={status="SOURCE_BACKED",fromSkill=oldFrom,
        toSkill=def.policy.correctionEndSkill,substituteRecipeID=def.substitute.recipeID,
        formerBlockedRecipeID=def.blocked.recipeID,sourceURLs=copy(def.policy.sourceURLs)}
    return route,nil
end
-- Single-step preview override, restricted to read-only candidate authority.
function S:GetCandidateStep(key,dataset,skill)
    local policy=correction(key)
    if not policy or tonumber(skill)==nil or skill>=policy.correctionEndSkill then
        if policy and tonumber(skill)==policy.correctionEndSkill then
            local def=self:Resolve(key)
            if not def then return nil,true end
            local origin=dataset and dataset.route and dataset.route[1]
            if not origin or origin.recipeID~=def.blocked.recipeID then return nil,true end
            local step=copy(origin)
            step.skillMin=policy.correctionEndSkill
            step.expectedCrafts=math.max(1,step.skillTarget-step.skillMin)
            step.referenceStatus="WOWHEAD_FOREVER_AUTHORITATIVE"
            step.starterCorrection=true
            step.plannerEligible=true
            step.executionEligible=false
            return step,true
        end
        return nil,false
    end
    if skill<policy.substituteMinSkill then return nil,true end
    if not (dataset and dataset.readOnly==true and dataset.productionCandidate==true
        and dataset.nativeDispatchAllowed==false) then return nil,false end
    local def=self:Resolve(key)
    if not def then return nil,true end
    local origin=dataset.route and dataset.route[1]
    if not origin or origin.recipeID~=def.blocked.recipeID then return nil,true end
    return {kind="craft",recipe=def.substitute.name,recipeID=def.substitute.recipeID,
        skillMin=policy.substituteMinSkill,skillTarget=policy.correctionEndSkill,
        expectedCrafts=policy.correctionEndSkill-policy.substituteMinSkill,
        materials=verifiedMaterials(def.substitute,key),routeIndex=0,recipeSource="trainer",
        evidence="WOWHEAD_FOREVER_SKILL_GATE",starterCorrection=true,
        referenceStatus="WOWHEAD_FOREVER_AUTHORITATIVE",readOnly=true,
        plannerEligible=true,executionEligible=false,nativeDispatchAllowed=false},true
end
function S:Validate()
    local errors={}
    local policy=correction("ALCHEMY")
    local resolved,reason=self:Resolve("ALCHEMY")
    if not resolved then errors[#errors+1]=reason or "starter-unresolved" end
    if not policy or policy.substituteOrangeThrough<policy.correctionEndSkill then
        errors[#errors+1]="starter-orange-range-invalid" end
    return errors
end
JLP:RegisterModule("ForeverStarterRoute",S)
