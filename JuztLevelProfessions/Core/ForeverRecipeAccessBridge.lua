local _, JLP = ...
-- Public item/access identity can be verified without inventing a vendor or
-- requiring an NPC snapshot. Acquisition remains advisory.
local S={contract="forever-access-proof-bridge-v1",executionEligible=false,
    nativeDispatchAllowed=false,persisted=false,requiresLiveQA=false}
function S:Resolve(key,step)
    local root=JLP.data and JLP.data.foreverRecipeAccessProof
    if type(root)~="table" or root.sourceBuild~=70245 then
        return nil,"ACCESS_EVIDENCE_BUILD_UNAVAILABLE"
    end
    key=tostring(key or ""):upper()
    local matched
    for _,row in ipairs(root.rows or {}) do
        if row.professionKey==key and row.recipeID==(step and step.recipeID) then
            if matched then return nil,"DUPLICATE_ACCESS_IDENTITY" end
            matched=row
        end
    end
    if not matched then return nil,"ACCESS_ITEM_NOT_CURATED" end
    local authority=JLP:GetModule("ForeverRecipeAuthority")
    local recipe=authority and authority:GetReference(key,matched.recipeID)
    local requirement=step and step.sourceRequirement
    if not recipe or matched.recipeName~=recipe.name or
        not requirement or requirement.kind~="recipe" or
        (requirement.itemID~=nil and tonumber(requirement.itemID)~=matched.recipeItemID) or
        matched.itemURL~="https://www.wowhead.com/forever/item="..tostring(matched.recipeItemID) or
        matched.recipeURL~=recipe.sourceURL or
        matched.evidenceClass~="WOWHEAD_FOREVER_RECIPE_ITEM" or
        type(matched.requiredSkillToLearn)~="number" or
        matched.requiredSkillToLearn<1 or matched.requiredSkillToLearn>300 or
        (tonumber(step.skillMin) or 0)<matched.requiredSkillToLearn then
        return nil,"ACCESS_ITEM_REFERENCE_MISMATCH"
    end
    return {status="WOWHEAD_ACCESS_ITEM_VERIFIED",recipeID=matched.recipeID,
        recipe=matched.recipeName,recipeItemID=matched.recipeItemID,
        requiredSkillToLearn=matched.requiredSkillToLearn,
        itemURL=matched.itemURL,recipeURL=matched.recipeURL,
        requirement=requirement,sourceVerified=true,
        vendorStock="UNKNOWN",trainerAvailability="UNVERIFIED",
        learnedState="NOT_OBSERVED",nativeDispatchAllowed=false},nil
end
JLP:RegisterModule("ForeverRecipeAccessBridge",S)
