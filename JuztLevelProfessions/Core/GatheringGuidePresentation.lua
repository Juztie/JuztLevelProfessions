local _, JLP = ...
-- Presentation policy only; no craft recipes, native action, or live spawn claim.
local Presenter={contract="jlp-gathering-guide-presentation-v1",nativeDispatchAllowed=false}
local function pretty(key)
    local s=tostring(key or "Resource"):gsub("_"," "):lower()
    return (s:gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end))
end
function Presenter:Build(key,skill,maxSkill)
    if key~="HERBALISM" and key~="MINING" then return nil,"NOT_NODE_GATHERING" end
    skill=math.max(0,tonumber(skill) or 0)
    local state=JLP:GetModule("GatheringSharedMapState")
    local choices=state and state:GetSnapshot()
    local canvas=JLP:GetModule("ForeverFishingMapCanvas")
    local current=canvas and canvas:GetCurrentZone()
    local mapID=choices and choices.selectedMapID or current and current.mapID
    local mapName=current and current.mapID==mapID and current.name or nil
    if not mapName and mapID and C_Map and C_Map.GetMapInfo then
        local ok,info=pcall(C_Map.GetMapInfo,mapID)
        if ok and type(info)=="table" then mapName=info.name end
    end
    local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
    local observedBuild=catalogue and catalogue.GetObservedClientBuild and catalogue:GetObservedClientBuild()
    local references=mapID and catalogue and
        catalogue:GetGatheringReferenceCoverage(key,mapID,observedBuild)
    local eligible={}
    for _,row in ipairs(references and references.resources or {}) do
        local required=tonumber(row.requiredSkill)
        if required and required<=skill and required>=0 then
            eligible[#eligible+1]={name=pretty(row.resourceKey),resourceKey=row.resourceKey,
                requiredSkill=required,referenceCount=row.referenceCount}
        end
    end
    table.sort(eligible,function(a,b)
        if a.requiredSkill~=b.requiredSkill then return a.requiredSkill>b.requiredSkill end
        return a.name<b.name
    end)
    local list={}
    for i=1,math.min(4,#eligible) do list[#list+1]=eligible[i].name.." ("..eligible[i].requiredSkill..")" end
    local names=#list>0 and table.concat(list,", ") or "No verified eligible zone references"
    local route=JLP:GetModule("GatheringRouteService")
    local routes,status=route and route:GetRoutes(mapID)
    local currentRoute=routes and routes[key]
    local stopCount=currentRoute and currentRoute.points and #currentRoute.points or 0
    local selected=0
    local selections=choices and choices.resourceSelectionsByMap and choices.resourceSelectionsByMap[mapID]
    for _,enabled in pairs(selections and selections[key] or {}) do
        if enabled==true then selected=selected+1 end
    end
    local mode=choices and choices.mode=="SMART_PROFESSION" and "Smart Profession" or "Custom Gathering"
    -- Typed text contract: never use an ungrouped boolean OR chain here.
    local action
    if stopCount>0 then
        action="Follow the advisory route; gather nodes manually."
    elseif selected>0 or (choices and choices.mode=="SMART_PROFESSION") then
        action="Generate an advisory gathering route."
    else
        action="Select resource types, then Generate Route."
    end
    local herbalism=key=="HERBALISM" and JLP:GetModule("ForeverHerbalismProgression209")
    local mining=key=="MINING" and JLP:GetModule("ForeverMiningNodeProgression210")
    local sourceProgression=(herbalism and herbalism:AtSkill(key,math.floor(skill))) or
        (mining and mining:AtSkill(key,math.floor(skill)))
    local sourceSummary=nil
    if sourceProgression then
        local parts={}
        for _,resource in ipairs(sourceProgression.resources or sourceProgression.nodes or {}) do
            parts[#parts+1]=resource.name.." ("..resource.minimumSkill..")"
        end
        local mode=sourceProgression.coverage=="FOREVER_GUIDE_RECOMMENDED_BAND" and
            "Forever guide" or "Forever node requirements only"
        local zones=table.concat(sourceProgression.suggestedZones or {},", ")
        sourceSummary=mode.." "..tostring(sourceProgression.bandStart or skill).."-"..
            tostring(sourceProgression.bandEnd or 300)..": "..table.concat(parts,", ")..
            (zones~="" and " | Suggested areas: "..zones or "")..
            ". Manual node check; skill-ups and spawns UNVERIFIED."
    end
    local smelting=key=="MINING" and JLP:GetModule("MiningSmeltingProgression")
    local progressionComparison=smelting and smelting:CompareWithGathering(skill)
    local smeltingCandidate=progressionComparison and progressionComparison.smelting
    -- Mining's concrete next action may be bank, preparation or training.
    -- Present the same read-only Planner decision instead of imposing a node route.
    local planner=(key=="MINING"or key=="HERBALISM") and JLP:GetModule("Planner")
    local plan=planner and planner:GetProfessionPlan(key,{preview=true})
    local current=plan and plan.recommendedCurrentStep
    local label=key=="HERBALISM"and "Herbalism"or "Mining"
    local titles={smelt="Prepare "..label.." materials",bank="Withdraw "..label.." materials",
        acquire="Acquire "..label.." materials",gather="Gather "..label.." resources",
        verify="Verify "..label.." requirements",train="Train "..label.." rank",complete=label.." skill goal reached"}
    if current then action=current.nextAction end
    return {sourceProgression=sourceProgression,sourceSummary=sourceSummary,
        currentStep=current,currentPlan=plan,objectiveTitle=current and titles[current.kind],
        progressionComparison=progressionComparison,smeltingCandidate=smeltingCandidate,kind="NODE_GATHERING",profession=key,skill=skill,maxSkill=maxSkill or 300,
        mapID=mapID,zoneName=mapName or "No verified zone selected",resourceText=names,
        resourceCount=#eligible,routeMode=mode,selectedResourceCount=selected,
        routeStopCount=stopCount,routeStatus=status or "IDLE",nextAction=action,
        qualification="Historical reference positions; no live spawn or guaranteed skill-up verification.",
        available=mapID~=nil and #eligible>0,nativeDispatchAllowed=false}
end
JLP:RegisterModule("GatheringGuidePresentation",Presenter)
