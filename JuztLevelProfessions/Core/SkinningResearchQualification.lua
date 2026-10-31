local _,JLP=...
-- Evidence gates for the historical text leads. Nothing here promotes a research lead
-- into build-70009 mob output, live spawns, source geometry, or native actions.
local M={contract="jlp-skinning-research-qualification-v1",nativeDispatchAllowed=false}
function M:AssessLead(lead)
 if type(lead)~="table" or type(lead.itemID)~="number" or lead.itemID<=0 then return nil,"INVALID_LEAD" end
 local missing={}
 if type(lead.mobID)~="number" then missing[#missing+1]="VERIFIED_MOB_ID" end
 if lead.sourceScope~="BUILD_70009_SKINNING_OUTPUT" then missing[#missing+1]="BUILD_70009_SKINNING_TAB_OUTPUT" end
 if lead.currentBuildObserved~=true then missing[#missing+1]="CLIENT_OBSERVATION" end
 if not (type(lead.geometry)=="table" and lead.geometry.sourceVerified==true) then
  missing[#missing+1]="SOURCE_QUALIFIED_AREA_GEOMETRY"
 end
 return {itemID=lead.itemID,mobLabel=lead.mobLabel,zone=lead.zone,
  evidence=lead.evidence or "UNVERIFIED",sourceURL=lead.sourceURL,
  status="RESEARCH_ONLY",missingRequirements=missing,
  verifiedMobOutput=false,verifiedFarmArea=false,notLiveSpawn=true,nativeDispatchAllowed=false}
end
JLP:RegisterModule("SkinningResearchQualification",M)
