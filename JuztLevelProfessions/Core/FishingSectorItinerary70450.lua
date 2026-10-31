local _, JLP = ...
-- Orders historical 12x12 CATCH AREAS for map review only. These are not
-- fishing-pool waypoints, terrain-safe paths, or native navigation instructions.
local M={contract="jlp-fishing-sector-itinerary-70450-v1",nativeDispatchAllowed=false}
local function coord(n) return type(n)=="number" and n==n and n>=0 and n<=1 end
function M:Build(mapID,shape,player)
    if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then return nil,"MAP_ID_INVALID" end
    if shape~="LOOP" and shape~="FROM_PLAYER" then return nil,"SHAPE_INVALID" end
    local spatialService=JLP:GetModule("GatheringSpatialAreaCatalog")
    local spatial=spatialService and spatialService:GetMapSnapshot(mapID)
    if not spatial or not spatial.fishingLearned then return nil,"FISHING_NOT_LEARNED" end
    if not spatial.fishingEnabled then return nil,"FISHING_LAYER_DISABLED" end
    if not spatial.areas or #spatial.areas==0 then return nil,"NO_DOCUMENTED_CATCH_SECTORS" end
    if shape=="FROM_PLAYER" and not (type(player)=="table" and player.mapID==mapID and
        coord(player.x) and coord(player.y)) then return nil,"PLAYER_POSITION_UNVERIFIED" end
    local pool={}
    for _,area in ipairs(spatial.areas) do
        if type(area.cellID)=="number" and area.geometryType=="GRID_AREA" and
            coord(area.x) and coord(area.y) and type(area.width)=="number" and type(area.height)=="number" then
            pool[#pool+1]={cellID=area.cellID,cx=area.x+area.width/2,
                cy=area.y+area.height/2,observations=area.observations}
        end
    end
    -- Fishing skill comes from the live profession API. Zone skill guidance
    -- is attached only when its uiMapID-to-Forever-zone identity is known.
    local api=JLP:GetModule("ProfessionAPI")
    local observed=api and api.Get and api:Get("FISHING")
    local fishingContext=JLP:GetModule("FishingSkillContext")
    local skill=fishingContext and fishingContext:FromSnapshot(observed)
    local model=JLP:GetModule("ForeverFishingZoneModel")
    local guide=model and skill and skill.rawSkill and
        model:LookupMap(mapID,skill.rawSkill,skill.observedBonus)
    local requirement=guide and guide.selected
    local access="UNKNOWN_ZONE_REQUIREMENT"
    if requirement then
        if skill.effectiveSkill and skill.effectiveSkill>=requirement.minSkill then
            access="ZONE_MINIMUM_MET_OBSERVED_SKILL"
        elseif skill.effectiveSkill then access="BELOW_ZONE_MINIMUM_OBSERVED_SKILL"
        elseif skill.rawSkill>=requirement.minSkill then access="ZONE_MINIMUM_MET_RAW_ONLY"
        else access="RAW_BELOW_MINIMUM_BONUS_UNKNOWN" end
    end
    local order={};local x,y
    if shape=="FROM_PLAYER" then x,y=player.x,player.y
    else
        table.sort(pool,function(a,b) return a.cellID<b.cellID end)
        x,y=pool[1].cx,pool[1].cy
    end
    for _=1,math.min(20,#pool) do
        local best,idx,score
        for i,entry in ipairs(pool) do
            local dx,dy=entry.cx-x,entry.cy-y
            local d=dx*dx+dy*dy
            if not score or d<score or (d==score and entry.cellID<best.cellID) then
                best,idx,score=entry,i,d
            end
        end
        if not best then break end
        order[#order+1]={cellID=best.cellID,observations=best.observations,
            geometryType="GRID_AREA",notWaypoint=true}
        x,y=best.cx,best.cy
        table.remove(pool,idx)
    end
    return {mapID=mapID,shape=shape,sectors=order,status="HISTORICAL_SECTOR_REVIEW_ONLY",
        filter=spatial.fishingAreaFilter,selectedItemID=spatial.fishingSelectedItemID,
        source="GATHERLITE_FISHING_FOREVER",sourceAuthority="HISTORICAL_APPROXIMATE",
        skillRequirementStatus=access,
        minimumZoneSkill=requirement and requirement.minSkill or nil,
        guaranteedZoneCatchSkill=requirement and requirement.guaranteedCatchSkill or nil,
        rawFishingSkill=skill and skill.rawSkill or nil,
        effectiveFishingSkill=skill and skill.effectiveSkill or nil,
        walkability="UNKNOWN",liveCatchProven=false,hasVerifiedPoolPoints=false,
        nativeNavigationAllowed=false,nativeDispatchAllowed=false}
end
function M:Describe(plan)
    if not plan or not plan.sectors then return "No verified fishing-pool coordinates; navigation unavailable" end
    local ids={}
    for i=1,math.min(6,#plan.sectors) do ids[#ids+1]=tostring(plan.sectors[i].cellID) end
    local skillInfo=plan.minimumZoneSkill and
        (" · zone guide min "..tostring(plan.minimumZoneSkill).." / observed "..
            tostring(plan.effectiveFishingSkill or plan.rawFishingSkill or "UNKNOWN")..
            " ("..tostring(plan.skillRequirementStatus)..")") or
        " · zone skill requirement UNKNOWN"
    return "Historical fishing sectors: "..table.concat(ids," → ")..
        (#plan.sectors>6 and " …" or "")..skillInfo..
        " · visual review only; no verified pools or walkable route"
end
JLP:RegisterModule("FishingSectorItinerary70450",M)
