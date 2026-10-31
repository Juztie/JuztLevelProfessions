local _,JLP=...
-- Explicit read-only current-build evidence gateway, never authorizes gameplay or routes.
local M={contract="jlp-skinning-mob-output-qualification-v1",nativeDispatchAllowed=false}
function M:Assess(itemID,lead)
 local research=JLP:GetModule("SkinningMaterialIntelligence")
 local item,err=research and research:GetMaterial(itemID)
 if not item then return nil,err or "MATERIAL_NOT_CATALOGUED" end
 if lead~=nil and type(lead)~="table" then return nil,"INVALID_LEAD" end
 local missing={}
 if not lead or type(lead.mobID)~="number" or lead.mobID<1 or lead.mobID~=math.floor(lead.mobID) then
  missing[#missing+1]="STABLE_FOREVER_NPC_ID"
 end
 if not lead or lead.sourceScope~="BUILD_70009_SKINNING_OUTPUT" or lead.skinningTabOutputItemID~=itemID then
  missing[#missing+1]="BUILD_70009_SKINNING_OUTPUT_PAIR"
 end
 if not lead or lead.currentBuildObserved~=true then missing[#missing+1]="CLIENT_CONFIRMATION" end
 if not lead or type(lead.geometry)~="table" or lead.geometry.sourceVerified~=true then
  missing[#missing+1]="BUILD_70009_SOURCE_QUALIFIED_AREA"
 end
 -- No database leads satisfy all required evidence stages. A caller-supplied record cannot
 -- mint native route authority: qualification is advisory and a separate verified-data
 -- promotion pipeline would be required.
 return {itemID=itemID,scope=item.scope,alternativeSource=item.alternativeSource,
  status="RESEARCH_ONLY",missingRequirements=missing,
  verifiedMobOutput=false,verifiedFarmArea=false,notLiveSpawn=true,nativeDispatchAllowed=false}
end
JLP:RegisterModule("SkinningMobOutputQualification",M)
