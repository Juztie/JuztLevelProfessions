local _, JLP = ...
-- Alchemy has the same reference-first route and MaterialFlow contracts as the
-- other research professions. Existing Forever evidence is the input; never
-- treat the historical route as reagent authority. No network/client QA gate.
local public=JLP.data and JLP.data.publicCraftingRouteEvidence
local evidence=JLP.data and JLP.data.currentBuildEvidence
local dataset=JLP.data and JLP.data.alchemy
local ev=evidence and evidence.professions and evidence.professions.ALCHEMY
local function ingredients(items)
    local map={}
    for _,v in ipairs(items or {}) do
        if type(v.itemID)~="number" or type(v.quantity)~="number" or map[v.itemID] then return nil end
        map[v.itemID]=v.quantity
    end
    return map
end
local function exact(step,row)
    if not step or not row or step.recipeID~=row.recipeID then return false end
    local a=ingredients(step.materials)
    if not a then return false end
    local count=0
    for _,item in ipairs(row.materials or {}) do
        if a[item[1]]~=item[2] then return false end
        count=count+1
    end
    local total=0
    for _ in pairs(a) do total=total+1 end
    return total==count
end
local index={}
for _,step in ipairs(dataset and dataset.route or {}) do
    if not index[step.recipeID] then index[step.recipeID]=step end
end
local recipes={}
for _,row in ipairs(ev and ev.rows or {}) do
    local step=index[row.recipeID]
    if exact(step,row) and row.capturedBuild==70245 and
       row.sourceKey=="wowheadAlchemy" then
        local reagents={}
        for _,item in ipairs(step.materials or {}) do
            reagents[#reagents+1]={itemID=item.itemID,name=item.name,quantity=item.quantity}
        end
        local gate,skillBasis=nil,"FOREVER_REAGENTS_ONLY"
        if row.recipeID==1245246 then gate=10;skillBasis="WOWHEAD_FOREVER" end
        if row.recipeID==7183 then gate=1;skillBasis="WOWHEAD_FOREVER" end
        recipes[#recipes+1]={recipeID=row.recipeID,name=step.recipe,
            requiredSkill=gate,skillBasis=skillBasis,reagents=reagents,
            sourceURL="https://www.wowhead.com/forever/spell="..row.recipeID,
            sourceBuild=70245,evidenceClass="PUBLIC_FOREVER_RECIPE_REAGENTS",
            status="REFERENCE_VERIFIED",researchRoute=true,
            outputPerCraft=(row.recipeID==1245246 or row.recipeID==7183) and 2 or nil,
            notes="Direct materials from Forever current-build evidence; historical skill bands/craft counts are estimates."}
    end
end
-- A missing or changed evidence row is an incomplete catalogue, not an excuse
-- to silently promote unverified materials. Validators flag partial coverage.
if public and public.professions then
    public.professions.ALCHEMY={skillLineID=171,recipes=recipes,
        evidenceBuild=70245,expectedRecipeCount=13,
        referencePolicy="WOWHEAD_FOREVER_OVER_HISTORICAL_RESEARCH",
        nativeDispatchAllowed=false}
end
