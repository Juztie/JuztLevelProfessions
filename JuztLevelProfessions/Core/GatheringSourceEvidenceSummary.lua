local _,JLP=...
-- One read-only, source-qualified summary for primary profession guides.
local M={contract="jlp-gathering-source-evidence-summary-v1",nativeDispatchAllowed=false}
function M:Get()
 if self._cachedSummary then return self._cachedSummary end
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local skin=JLP:GetModule("SkinningResearchCatalog")
 local coverage=bridge and bridge:GetCoverageSnapshot() or {}
 local mobs=skin and skin:GetMobIdentitySummary() or {}
 local result={total=coverage.total or 0,smartEligible=coverage.EXPLICIT_ITEM_ID or 0,
   questRestricted=coverage.questRestrictedIdentityCount or 0,
   identityUnknown=coverage.identityUnknownCount or 0,
   encounterConditional=coverage.encounterConditionalCount or 0,
   documentedPrimary=coverage.documentedPrimaryCount or 0,
   npcSkinningTabs=mobs.count or 0,
   skinningMaterialResearchCount=(JLP:GetModule("SkinningMaterialIntelligence") and
     JLP:GetModule("SkinningMaterialIntelligence"):GetCoverage().materialCount) or 0,
   hideScaleResearchCount=(JLP:GetModule("SkinningMaterialIntelligence") and
     JLP:GetModule("SkinningMaterialIntelligence"):GetCoverage().hideScaleMaterialCount) or 0,
   scaleResearchExpansionCount=(JLP:GetModule("SkinningMaterialIntelligence") and
     JLP:GetModule("SkinningMaterialIntelligence"):GetCoverage().scaleExpansionCount) or 0,
   verifiedSkinningOutputs=0,verifiedSkinningAreas=0,
   status="RESEARCH_ADVISORY_ONLY",notLiveSpawn=true,nativeDispatchAllowed=false}
 self._cachedSummary=result
 return result
end
function M:Label()
 local v=self:Get()
 return "Smart materials "..v.smartEligible.."/"..v.total.." | "..v.questRestricted..
  " restricted | "..v.encounterConditional.." conditional | "..v.identityUnknown.." unknown"
end
function M:SkinningLabel()
 local v=self:Get()
 return "Skinning: "..v.npcSkinningTabs.." NPC leads | "..
  tostring(v.skinningMaterialResearchCount).." leather research items | "..tostring(v.hideScaleResearchCount).." hides/scales + "..tostring(v.scaleResearchExpansionCount).." researched scales | 0 verified farming areas"
end
JLP:RegisterModule("GatheringSourceEvidenceSummary",M)
