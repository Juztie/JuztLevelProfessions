local _, JLP = ...
-- Alpha160. Read-only historical catch-grid areas. There are no exact pool pins.
-- Skinning has no source-verified mob/area positions: fail closed rather than invent.
local C={contract="jlp-spatial-gathering-areas-v1",nativeDispatchAllowed=false,maxVisibleSectors=48}
local function learned(key)
    local api=JLP:GetModule("ProfessionAPI")
    local p=api and api:Get(key)
    return type(p)=="table" and p.key==key and p.cached~=true and type(p.skill)=="number"
end
function C:GetMapSnapshot(mapID)
    if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then return nil,"MAP_ID_INVALID" end
    local state=JLP:GetModule("GatheringSharedMapState")
    local prefs=state and state:GetSnapshot()
    local fishLearned=learned("FISHING")
    local skinLearned=learned("SKINNING")
    local enabled=fishLearned and prefs and prefs.showFishingAreas~=false
    local source=JLP.data and JLP.data.fishingCatchAreaReference
    local entries=source and source.maps and source.maps[mapID]
    local filter=prefs and prefs.fishingAreaFilter or "ALL"
    local selectedID=prefs and prefs.fishingSelectedItemID
    local needService=JLP:GetModule("FishingCookingIntelligence")
    local needs=filter=="COOKING_NEEDS" and needService and needService:GetNeedSnapshot() or nil
    local needKey=""
    if needs then
        local ids={}
        for id,quantity in pairs(needs.byItemID) do ids[#ids+1]=tostring(id).."="..tostring(quantity) end
        table.sort(ids);needKey=needs.status..":"..table.concat(ids,",")
    end
    local cacheKey=tostring(mapID)..":"..tostring(fishLearned)..":"..tostring(skinLearned)..":"..tostring(enabled)..":"..filter..":"..tostring(selectedID)..":"..needKey
    if self._cacheKey==cacheKey and self._cache then return self._cache end
    local result={mapID=mapID,geometryType="GRID_AREA",source="GATHERLITE_FISHING_FOREVER",
        fishingLearned=fishLearned,skinningLearned=skinLearned,fishingEnabled=enabled==true,
        skinningStatus="NO_REFERENCE_COVERAGE",fishCount=0,fishNames={},sampleCount=0,
        areaCount=0,areas={},zoneOnlyCount=0,nativeDispatchAllowed=false,
        fishingStatus="NO_REFERENCE_COVERAGE",fishingAreaFilter=filter,
        fishingSelectedItemID=selectedID,cookingNeedStatus=needs and needs.status or "FILTER_NOT_REQUESTED",
        cookingMissingFish=needs and needs.matchedFishTypes or 0,
        eligibleFishCount=0,selectedFishNames={},selectedSampleCount=0,
        needsAreGuideEstimates=true}
    local skin=JLP:GetModule("GatheringSkinningEvidence")
    result.skinningEvidence=skin and skin:GetMapSnapshot(mapID) or nil
    result.skinningStatus=result.skinningEvidence and result.skinningEvidence.status or "NO_REFERENCE_COVERAGE"
    local research=JLP:GetModule("SkinningResearchCatalog")
    result.skinningResearch=research and research:GetMapLeads(mapID) or nil
    result.skinningLeadCount=result.skinningResearch and result.skinningResearch.leadCount or 0
    result.skinningMobIdentities=research and research:GetMobIdentitySummary(mapID) or nil
    result.skinningMobIdentityCount=result.skinningMobIdentities and result.skinningMobIdentities.count or 0

    if not entries then
        local intel=JLP:GetModule("FishingAreaIntelligence")
        result.historicalCoverage=intel and intel:Assess(mapID,filter,selectedID,needs) or nil
        result.fishingExplanation=intel and intel:Explain(mapID,filter,selectedID,needs) or nil
        self._cacheKey=cacheKey;self._cache=result;return result
    end
    local cells={}
    for _,entry in ipairs(entries) do
        result.fishCount=result.fishCount+1
        result.fishNames[#result.fishNames+1]=entry.name
        result.sampleCount=result.sampleCount+(entry.sampleCount or 0)
        if entry.cells=="" then result.zoneOnlyCount=result.zoneOnlyCount+1 end
        local eligible=filter=="ALL" or filter=="SINGLE_FISH" and entry.itemID==selectedID or
            filter=="COOKING_NEEDS" and needs and (needs.byItemID[entry.itemID] or 0)>0
        if eligible then
            result.eligibleFishCount=result.eligibleFishCount+1
            result.selectedFishNames[#result.selectedFishNames+1]=entry.name
            result.selectedSampleCount=result.selectedSampleCount+(entry.sampleCount or 0)
        end
        if enabled and eligible then
            for id,count in string.gmatch(entry.cells or "","(%d+):(%d+)") do
                id=tonumber(id);count=tonumber(count)
                if id and id>=1 and id<=144 and count and count>0 then
                    local c=cells[id] or {cellID=id,count=0,fish={},itemIDs={}}
                    c.count=c.count+count;c.fish[entry.name]=true;c.itemIDs[entry.itemID]=true;cells[id]=c
                end
            end
        end
    end
    result.fishingStatus=result.sampleCount>0 and "HISTORICAL_CATCH_GRID" or "ZONE_CATCH_REFERENCE_ONLY"
    if filter=="COOKING_NEEDS" and needs and needs.status=="COOKING_NOT_LEARNED" then
        result.fishingStatus="COOKING_NOT_LEARNED"
    elseif filter~="ALL" and result.eligibleFishCount==0 then
        result.fishingStatus="NO_MATCHING_FISH_AREAS"
    elseif filter~="ALL" and result.selectedSampleCount==0 then
        result.fishingStatus="MATCHED_FISH_WITHOUT_SPATIAL_SAMPLES"
    end
    local all={}
    for _,c in pairs(cells) do all[#all+1]=c end
    table.sort(all,function(a,b)
        if a.count~=b.count then return a.count>b.count end
        return a.cellID<b.cellID
    end)
    result.areaCount=#all
    local cap=math.min(self.maxVisibleSectors,#all)
    -- Aggregate overlapping fish identities into one coloured *area*, never one pinpoint.
    for i=1,cap do
        local c=all[i]
        local fish={}
        for name in pairs(c.fish) do fish[#fish+1]=name end
        table.sort(fish)
        local itemIDs={}
        for id in pairs(c.itemIDs) do itemIDs[#itemIDs+1]=id end
        table.sort(itemIDs)
        local x=((c.cellID-1)%12)/12
        local y=math.floor((c.cellID-1)/12)/12
        result.areas[#result.areas+1]={geometryType="GRID_AREA",x=x,y=y,width=1/12,height=1/12,
            fish=fish,itemIDs=itemIDs,cellID=c.cellID,observations=c.count,source="GATHERLITE_FISHING_FOREVER",
            confidence="HISTORICAL_APPROXIMATE",notLiveSpawn=true}
    end
    result.truncated=#all>cap
    local intel=JLP:GetModule("FishingAreaIntelligence")
    result.historicalCoverage=intel and intel:Assess(mapID,filter,selectedID,needs) or nil
    result.fishingExplanation=intel and intel:Explain(mapID,filter,selectedID,needs) or nil
    self._cacheKey=cacheKey;self._cache=result
    return result
end
JLP:RegisterModule("GatheringSpatialAreaCatalog",C)
