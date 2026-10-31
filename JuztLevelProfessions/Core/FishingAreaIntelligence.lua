local _, JLP = ...
-- Alpha162: compares historical Fishing *coverage*, not catch chance, pool
-- locations, real-world travel time or a verified yield per hour.
local M={contract="jlp-fishing-historical-coverage-intelligence-v1",nativeDispatchAllowed=false}
local function positive(n) return type(n)=="number" and n>0 and n==math.floor(n) end
function M:Assess(mapID,filter,selectedID,needs)
 if not positive(mapID) then return nil,"MAP_ID_INVALID" end
 if filter~="ALL" and filter~="COOKING_NEEDS" and filter~="SINGLE_FISH" then return nil,"FILTER_INVALID" end
 if filter=="SINGLE_FISH" and not positive(selectedID) then return nil,"FISH_ID_INVALID" end
 local data=JLP.data and JLP.data.fishingCatchAreaReference
 local entries=data and data.maps and data.maps[mapID] or {}
 if filter=="COOKING_NEEDS" and not needs then
  local cooking=JLP:GetModule("FishingCookingIntelligence")
  needs=cooking and cooking:GetNeedSnapshot() or {status="NEEDS_UNAVAILABLE",byItemID={}}
 end
 local sectors={}
 local result={mapID=mapID,status="NO_MATCHING_SPATIAL_REFERENCE",filter=filter,
  historicalSamples=0,uniqueSectors=0,supportedFish=0,matchedDemandUnits=0,
  unplacedFish=0,source="GATHERLITE_FISHING_FOREVER",confidence="HISTORICAL_APPROXIMATE",
  guideEstimated=true,notCatchRate=true,notLiveSpawn=true,nativeDispatchAllowed=false}
 local demand=needs and needs.byItemID or {}
 for _,fish in ipairs(entries) do
  local relevant=filter=="ALL" or filter=="SINGLE_FISH" and fish.itemID==selectedID or
   filter=="COOKING_NEEDS" and (demand[fish.itemID] or 0)>0
  if relevant then
   result.supportedFish=result.supportedFish+1
   if filter=="COOKING_NEEDS" then result.matchedDemandUnits=result.matchedDemandUnits+(demand[fish.itemID] or 0) end
   local samples=0
   for id,count in string.gmatch(fish.cells or "","(%d+):(%d+)") do
    id=tonumber(id);count=tonumber(count)
    if id and id>=1 and id<=144 and count and count>0 then sectors[id]=true;samples=samples+count end
   end
   result.historicalSamples=result.historicalSamples+samples
   if samples==0 then result.unplacedFish=result.unplacedFish+1 end
  end
 end
 for _ in pairs(sectors) do result.uniqueSectors=result.uniqueSectors+1 end
 if result.uniqueSectors>0 then result.status="HISTORICAL_AREA_COVERAGE"
 elseif result.supportedFish>0 then result.status="MATCHED_FISH_WITHOUT_SPATIAL_SAMPLES" end
 if filter=="COOKING_NEEDS" and needs and needs.status=="COOKING_NOT_LEARNED" then
  result.status="COOKING_NOT_LEARNED" end
 return result
end
function M:Explain(mapID,filter,selectedID,needs)
 local assessed,reason=self:Assess(mapID,filter,selectedID,needs)
 if not assessed then return nil,reason end
 local label=assessed.uniqueSectors>0 and "HISTORICAL_COVERAGE_ONLY" or
   assessed.supportedFish>0 and "ZONE_REFERENCE_WITHOUT_COORDINATES" or "NO_HISTORICAL_MATCH"
 local caveats={"NOT_LIVE_FISHING_POOLS","NOT_CATCH_RATE","NOT_TRAVEL_TIME"}
 if filter=="COOKING_NEEDS" then caveats[#caveats+1]="COOKING_REQUIREMENTS_ARE_ESTIMATES" end
 return {mapID=mapID,classification=label,filter=filter,
   sectors=assessed.uniqueSectors,historicalSamples=assessed.historicalSamples,
   relevantFishTypes=assessed.supportedFish,estimatedCookingUnits=assessed.matchedDemandUnits,
   evidence="GATHERLITE_HISTORICAL_APPROXIMATE",confidence="HISTORICAL_NOT_BUILD_VERIFIED",
   caveats=caveats,notLiveSpawn=true,notCatchRate=true,nativeDispatchAllowed=false}
end
function M:RecommendZones(filter,selectedID,needs,allowed)
 if filter~="ALL" and filter~="COOKING_NEEDS" and filter~="SINGLE_FISH" then return nil,"FILTER_INVALID" end
 local source=JLP.data and JLP.data.fishingCatchAreaReference
 local maps=source and source.maps or {}
 if filter=="COOKING_NEEDS" and not needs then
  local cooking=JLP:GetModule("FishingCookingIntelligence")
  needs=cooking and cooking:GetNeedSnapshot()
 end
 if filter=="COOKING_NEEDS" and (not needs or needs.status=="COOKING_NOT_LEARNED" or not next(needs.byItemID or {})) then
  return {},"NO_VERIFIED_COOKING_DEMAND" end
 local all={}
 for mapID in pairs(maps) do
  if not allowed or allowed(mapID) then
   local row=self:Assess(mapID,filter,selectedID,needs)
   if row and row.uniqueSectors>0 then all[#all+1]=row end
  end
 end
 table.sort(all,function(a,b)
  if a.supportedFish~=b.supportedFish then return a.supportedFish>b.supportedFish end
  if a.uniqueSectors~=b.uniqueSectors then return a.uniqueSectors>b.uniqueSectors end
  if a.historicalSamples~=b.historicalSamples then return a.historicalSamples>b.historicalSamples end
  return a.mapID<b.mapID
 end)
 local picked={}
 for i=1,math.min(5,#all) do picked[i]=all[i] end
 return picked,#picked>0 and "HISTORICAL_COVERAGE_RANKING" or "NO_MATCHING_SPATIAL_REFERENCE"
end
JLP:RegisterModule("FishingAreaIntelligence",M)
