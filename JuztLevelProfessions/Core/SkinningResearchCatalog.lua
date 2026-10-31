local _,JLP=...
-- Alpha163: advisory textual Skinning *research leads*, never verified farming geometry.
local M={contract="jlp-skinning-zone-research-v1",nativeDispatchAllowed=false}
local function positive(n) return type(n)=="number" and n>0 and n==math.floor(n) end
function M:GetMapLeads(mapID)
 if not positive(mapID) then return nil,"MAP_ID_INVALID" end
 local source=JLP.data and JLP.data.skinningResearchLeads
 local result={mapID=mapID,status="NO_RESEARCH_LEADS",leads={},hasVerifiedFarmGeometry=false,
  hasVerifiedMobOutputJoin=false,notLiveSpawn=true,nativeDispatchAllowed=false}
 for _,lead in ipairs(source and source.leads or {}) do
  if lead.mapID==mapID and type(lead.sourceURL)=="string" and
    lead.sourceURL:find("https://www.wowhead.com/forever/",1,true)==1 and
    (lead.type=="NPC_SKINNING_TAB" or lead.type=="COMMUNITY_FARMING_REPORT") then
    result.leads[#result.leads+1]={name=lead.name,mapID=mapID,mobID=lead.mobID,
      type=lead.type,sourceURL=lead.sourceURL,sourceConfidence=lead.sourceConfidence,
      reportedItemID=lead.reportedItemID,claim=lead.claim,
      geometryStatus="UNVERIFIED",outputJoinStatus="UNVERIFIED",notLiveSpawn=true}
  end
 end
 if #result.leads>0 then result.status="TEXTUAL_RESEARCH_LEADS_ONLY" end
 result.leadCount=#result.leads
 return result
end
function M:GetCoverageSummary()
 local source=JLP.data and JLP.data.skinningResearchLeads
 local summary={total=0,npcWithSkinningTab=0,communityReports=0,verifiedAreas=0,
  verifiedMobOutputPairs=0,notLiveSpawn=true,nativeDispatchAllowed=false}
 for _,lead in ipairs(source and source.leads or {}) do
  if lead.type=="NPC_SKINNING_TAB" or lead.type=="COMMUNITY_FARMING_REPORT" then
   summary.total=summary.total+1
   if lead.type=="NPC_SKINNING_TAB" then summary.npcWithSkinningTab=summary.npcWithSkinningTab+1
   else summary.communityReports=summary.communityReports+1 end
  end
 end
 return summary
end
-- Source-qualified NPC identities only. Never reinterpret the NPC Drops table
-- as Skinning loot: tabs are separate, and the actual Skinning tab output has
-- not been extracted/verified in the current client build.
function M:GetMobIdentitySummary(mapID)
 if mapID~=nil and not positive(mapID) then return nil,"MAP_ID_INVALID" end
 local data=JLP.data and JLP.data.skinningMobIdentityEvidence
 local result={status="NPC_SKINNING_TAB_REFERENCE_ONLY",count=0,mobs={},
   verifiedMobOutputPairs=0,verifiedAreas=0,notLiveSpawn=true,
   hasGeometry=false,nativeDispatchAllowed=false}
 local seen={}
 for _,entry in ipairs(data and data.mobs or {}) do
  if (not mapID or entry.mapID==mapID) and positive(entry.mobID) and
    type(entry.sourceURL)=="string" and
    entry.sourceURL:find("https://www.wowhead.com/forever/npc=",1,true)==1 and
    entry.tabLabel=="Skinning" and not seen[entry.mobID] then
    seen[entry.mobID]=true
    result.count=result.count+1
    result.mobs[#result.mobs+1]={mobID=entry.mobID,name=entry.name,
      mapID=entry.mapID,sourceURL=entry.sourceURL,
      evidence="PUBLIC_NPC_SKINNING_TAB_ONLY",outputJoinStatus="UNVERIFIED",
      geometryStatus="UNVERIFIED",notLiveSpawn=true}
  end
 end
 table.sort(result.mobs,function(a,b) return a.mobID<b.mobID end)
 if mapID and result.count==0 then result.status="NO_MOB_IDENTITY_RESEARCH" end
 return result
end
-- Source-qualified zone AREA *advice* only; no polygon/point primitives.
-- A source showing a zone for a skill band is not a verified coordinate.
local ZONE_ADVICE = {
 contract="jlp-forever-skinning-zone-area-advice-v1",faction="HORDE",
 sourceURL="https://www.wowhead.com/forever/guide/professions/skinning/overview-leveling",
 capturedAt="2026-10-13",sourceType="WOWHEAD_FOREVER_GUIDE",
 geometryType="AREA",areaExtent="ZONE_LEVEL_ONLY",hasVerifiedPolygon=false,
 hasVerifiedMobOutputJoin=false,notLiveSpawn=true,nativeDispatchAllowed=false,
 bands={
  {fromSkill=1,toSkill=75,zones={{1411,"Durotar"},{1412,"Mulgore"},{1420,"Tirisfal Glades"}},description="Horde starting zones; no density verified"},
  {fromSkill=75,toSkill=125,zones={{1413,"The Barrens"}},description="Suggested Barrens progression north to south"},
  {fromSkill=125,toSkill=175,zones={{1440,"Ashenvale"},{1424,"Hillsbrad Foothills"}},description="Zone only, no verified mob concentration"},
  {fromSkill=175,toSkill=225,zones={{1417,"Arathi Highlands"},{1434,"Stranglethorn Vale"},{1441,"Thousand Needles"}},description="Zone only, no precise coordinates"},
 }
}

function M:GetQualifiedZoneAreaAdvice(mapID,skill)
 if not positive(mapID) then return nil,"MAP_ID_INVALID" end
 if type(skill)~="number" or skill~=skill or skill==math.huge or
    skill==-math.huge or skill<1 or skill~=math.floor(skill) then
    return nil,"SKILL_UNKNOWN" end
 local data=ZONE_ADVICE
 if not data or data.faction~="HORDE" or data.geometryType~="AREA" or
    data.hasVerifiedPolygon~=false or type(data.sourceURL)~="string" then
    return nil,"SOURCE_UNAVAILABLE" end
 local out={geometryType="AREA",areaExtent="ZONE_LEVEL_ONLY",mapID=mapID,
    sourceURL=data.sourceURL,sourceType=data.sourceType,
    hasVerifiedPolygon=false,nativeDispatchAllowed=false,
    notLiveSpawn=true,skill=skill,status="SOURCE_UNAVAILABLE",suggestions={}}
 for _,band in ipairs(data.bands or {}) do
  if type(band.fromSkill)=="number" and type(band.toSkill)=="number" and
     skill>=band.fromSkill and skill<band.toSkill then
   for _,zone in ipairs(band.zones or {}) do
    if zone[1]==mapID then
     out.suggestions[#out.suggestions+1]={zone=zone[2],fromSkill=band.fromSkill,
      toSkill=band.toSkill,description=band.description,sourceURL=data.sourceURL,
      geometryType="AREA",geometryStatus="ZONE_ONLY_NO_POLYGON",
      nativeDispatchAllowed=false}
    end
   end
  end
 end
 if #out.suggestions>0 then out.status="ZONE_AREA_SOURCE_ADVICE" end
 return out
end
JLP:RegisterModule("SkinningResearchCatalog",M)
