local _,JLP=...
-- Research-only authorization gate for future mob->skinning item associations.
-- No current candidate has explicit source-scoped tab output evidence in build 70009.
local M={contract="jlp-skinning-output-verification-gate-v1",nativeDispatchAllowed=false}
local function id(n) return type(n)=="number" and n>0 and n==math.floor(n) end
function M:Assess(row)
 if type(row)~="table" or not id(row.mobID) or not id(row.itemID) then
  return {status="INVALID_IDENTITY",verified=false,nativeDispatchAllowed=false} end
 if row.sourceScope~="SKINNING_TAB_ITEM" then
  return {status="NOT_SKINNING_TAB_EVIDENCE",verified=false,nativeDispatchAllowed=false} end
 if type(row.sourceURL)~="string" or
   not row.sourceURL:find("https://www.wowhead.com/forever/",1,true) then
  return {status="SOURCE_UNVERIFIED",verified=false,nativeDispatchAllowed=false} end
 if not id(row.clientBuild) or row.clientObserved~=true or row.skinningLootConfirmed~=true then
  return {status="CLIENT_BUILD_LOOT_UNVERIFIED",verified=false,nativeDispatchAllowed=false} end
 local info=JLP:GetModule("ClientBuildInfo")
 local live=info and info.GetBuildNumber and info:GetBuildNumber() or nil
 return {status=live==row.clientBuild and "CURRENT_OBSERVED_OUTPUT_PAIR" or "HISTORICAL_OBSERVED_OUTPUT_PAIR",
   verified=true,observedBuild=row.clientBuild,currentClientBuild=live,mobID=row.mobID,
   itemID=row.itemID,geometryVerified=false,notLiveSpawn=true,nativeDispatchAllowed=false}
end
function M:GetCoverage()
 local skin=JLP:GetModule("SkinningResearchCatalog")
 local refs=skin and skin:GetMobIdentitySummary() or {}
 return {npcTabResearchCount=refs.count or 0,verifiedPairs=0,verifiedAreas=0,
  reason="No build-70009 confirmed Skinning-tab item observations",
  nativeDispatchAllowed=false}
end
JLP:RegisterModule("SkinningOutputEvidenceGate",M)
