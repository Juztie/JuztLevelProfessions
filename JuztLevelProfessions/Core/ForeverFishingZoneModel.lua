local _, JLP = ...
local M={contract="forever-fishing-zone-model-v1",nativeDispatchAllowed=false}
local function number(v)
    v=tonumber(v)
    if not v or v~=v or v<0 or v==math.huge then return nil end
    return math.floor(v)
end
function M:Lookup(name,rawSkill,bonus)
    local data=JLP.data and JLP.data.foreverFishingZoneEvidence
    if not data or type(data.tiers)~="table" then return nil,"ZONE_REFERENCE_UNAVAILABLE" end
    local base=number(rawSkill)
    if not base then return nil,"SKILL_UNAVAILABLE" end
    local boost=number(bonus or 0)
    if not boost then return nil,"BOOST_INVALID" end
    local effective=base+boost
    local result={contract=self.contract,baseSkill=base,effectiveSkill=effective,
        sourceURL=data.sourceURL,pinsAvailable=false,mapCoordinatesVerified=false,
        zoneMapID=nil,sourceCoverageComplete=false,fullLevelingRoute=false,
        tiers={},selected=nil,nativeDispatchAllowed=false}
    for _,t in ipairs(data.tiers) do
        for _,z in ipairs(t.zones or {}) do
            local r={name=z,minSkill=t.minSkill,guaranteedCatchSkill=t.guaranteedCatchSkill,
                meetsMinimum=effective>=t.minSkill,below100PercentThreshold=effective<t.guaranteedCatchSkill,
                boostNeededToAccess=math.max(0,t.minSkill-effective),
                boostNeededFor100Percent=math.max(0,t.guaranteedCatchSkill-effective),
                sourceURL=data.sourceURL,hasMapPin=false}
            result.tiers[#result.tiers+1]=r
            if name and z==name then result.selected=r end
        end
    end
    if name and not result.selected then return nil,"ZONE_NOT_IN_FOREVER_REFERENCE" end
    return result
end
-- Strict source-backed identity: localized C_Map names are display text only.
-- An unknown or subzone-sensitive uiMapID has UNKNOWN requirements (fail closed).
function M:LookupMap(mapID,rawSkill,bonus)
 if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then
  return nil,"MAP_ID_INVALID" end
 local idData=JLP.data and JLP.data.foreverFishingMapIdentity
 local canonical=idData and idData.byMapID and idData.byMapID[mapID]
 if not canonical then return nil,"MAP_ID_UNVERIFIED" end
 local result,why=self:Lookup(canonical,rawSkill,bonus)
 if result and result.selected then
  result.zoneMapID=mapID
  result.identitySource=idData.source
  return result,"MAP_ID_MATCH"
 end
 return nil,why or "ZONE_REFERENCE_UNAVAILABLE"
end
function M:Validate()
    local d=JLP.data and JLP.data.foreverFishingZoneEvidence
    if not d or type(d.tiers)~="table" or #d.tiers~=6 then return false,"TIER_COUNT_INVALID" end
    local names={}
    local last=-1
    for _,tier in ipairs(d.tiers) do
        if type(tier.minSkill)~="number" or tier.minSkill<last or
           type(tier.guaranteedCatchSkill)~="number" or tier.guaranteedCatchSkill<tier.minSkill or
           type(tier.zones)~="table" or #tier.zones<1 then return false,"TIER_INVALID" end
        last=tier.minSkill
        for _,n in ipairs(tier.zones) do
            if type(n)~="string" or names[n] then return false,"DUPLICATE_ZONE" end
            names[n]=true
        end
    end
    return true
end
JLP:RegisterModule("ForeverFishingZoneModel",M)
