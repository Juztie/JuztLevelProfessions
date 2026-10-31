local _, JLP = ...
-- Alpha161: compare *documented raw fish item IDs* against the read-only
-- Cooking 1-225 guide-estimate shopping list. No catch-rate/loot or craft authority.
local M={contract="jlp-fishing-cooking-demand-v1",nativeDispatchAllowed=false}
local function fishIDs()
    local source=JLP.data and JLP.data.fishingCatchAreaReference
    local found={}
    for _,entries in pairs(source and source.maps or {}) do
        for _,entry in ipairs(entries) do
            if type(entry.itemID)=="number" and entry.itemID>0 then found[entry.itemID]=true end
        end
    end
    return found
end
function M:GetNeedSnapshot(options)
    local result={status="COOKING_NOT_LEARNED",byItemID={},totalShortage=0,
        matchedFishTypes=0,guideEstimate=true,notCatchRate=true,nativeDispatchAllowed=false,
        source="FOREVER_COOKING_GUIDE_SPELL_ITEM_IDS"}
    local activePlanner=JLP:GetModule("Planner");local api=JLP:GetModule("ProfessionAPI")
    if JLP.data and JLP.data.cooking and activePlanner and activePlanner.GetProfessionPlan and api then
        result.guideEstimate=false;result.source="CURRENT_CONSUMER_CAST_INPUTS_NOT_GUIDE_TOTAL"
        local shared=JLP:GetModule("GatheringSharedMapState");local state=shared and shared:GetSnapshot()
        local goal=state and state.supplyGoal
        if goal and goal.professionKey=="FISHING"then
            result.status=goal.status;result.consumerProfession=goal.ownerProfession;result.recipeID=goal.ownerRecipeID
            result.originalRequired=goal.required;result.totalShortage=goal.quantity
            if type(goal.quantity)=="number"and goal.quantity>0 then result.byItemID[goal.itemID]=goal.quantity;result.matchedFishTypes=1 end
            return result
        end
        local prof=api:Get("COOKING")
        if not prof or prof.cached or type(prof.skill)~="number"then return result end
        if prof.skill>=300 then result.status="COOKING_GOAL_COMPLETE";return result end
        local plan=activePlanner:GetProfessionPlan("COOKING",{preview=true})
        local c=plan and plan.recommendedCurrentStep;local ids=fishIDs();local inv=JLP:GetModule("Inventory")
        result.status="NO_CURRENT_FISH_DEMAND"
        for _,m in ipairs(c and c.materials or {})do
            if ids[m.itemID]then
                local r=inv and inv:GetOwned(m.itemID)or {};local required=m.perCraft or m.quantity
                if type(required)=="number"and r.bagKnown==true and type(r.bags)=="number"and r.bankKnown==true and type(r.bank)=="number"and not r.bankStale then
                    local n=math.max(0,required-r.bags-r.bank)
                    if n>0 then result.byItemID[m.itemID]=n;result.totalShortage=(result.totalShortage or 0)+n;result.matchedFishTypes=result.matchedFishTypes+1;result.status="CURRENT_CAST_FISH_SHORTAGE"end
                else result.status="UNKNOWN_FISH_INVENTORY";result.totalShortage=nil end
            end
        end
        return result
    end
    local workspace=JLP:GetModule("SecondaryWorkspace")
    local current=workspace and workspace:GetSnapshot("COOKING")
    if not current or not current.learned or current.cached or type(current.skill)~="number" then return result end
    local planner=JLP:GetModule("SecondaryLevelingPlanner")
    local plan,reason=planner and planner:Build("COOKING",current.skill,options)
    if not plan or type(plan.materials)~="table" then
        result.status=reason or "COOKING_PLAN_UNAVAILABLE"
        return result
    end
    result.status="NO_FISH_SHORTAGE_IN_GUIDE_ESTIMATE"
    local known=fishIDs()
    for _,r in ipairs(plan.materials) do
        local id=tonumber(r.itemID)
        local missing=tonumber(r.externalNeededIfGuideEstimateHolds)
        if id and known[id] and missing and missing>0 then
            missing=math.floor(missing)
            result.byItemID[id]=missing
            result.totalShortage=result.totalShortage+missing
            result.matchedFishTypes=result.matchedFishTypes+1
        end
    end
    if result.matchedFishTypes>0 then result.status="GUIDE_ESTIMATED_FISH_SHORTAGE" end
    return result
end
function M:GetZoneCoverage(mapID,needs)
    local source=JLP.data and JLP.data.fishingCatchAreaReference
    local entries=source and source.maps and source.maps[mapID] or {}
    needs=needs or self:GetNeedSnapshot()
    local r={mapID=mapID,status=needs.status,eligibleFishTypes=0,eligibleObservedTypes=0,
        supportedSamples=0,unplacedFishTypes=0,byItemID={},guideEstimate=true,nativeDispatchAllowed=false}
    for _,fish in ipairs(entries) do
        local n=needs.byItemID[fish.itemID]
        if n then
            r.eligibleFishTypes=r.eligibleFishTypes+1
            r.byItemID[fish.itemID]={name=fish.name,missing=n,sourceSampleCount=fish.sampleCount or 0}
            if (fish.sampleCount or 0)>0 and fish.cells~="" then
                r.eligibleObservedTypes=r.eligibleObservedTypes+1
                r.supportedSamples=r.supportedSamples+fish.sampleCount
            else r.unplacedFishTypes=r.unplacedFishTypes+1 end
        end
    end
    return r
end
JLP:RegisterModule("FishingCookingIntelligence",M)
