local _,JLP=...
-- Source-tier-aware immutable facade: legacy research and separately qualified
-- external Skinning references. Neither is a current client/spawn observation.
local M={contract="jlp-skinning-material-evidence-readmodel-v1",nativeDispatchAllowed=false}
local function positive(n) return type(n)=="number" and n>0 and n==math.floor(n) end
local function source() return JLP.data and JLP.data.skinningMaterialResearch end
local function additional() return JLP.data and JLP.data.skinningHideScaleResearch end
local function scales() return JLP.data and JLP.data.skinningScaleResearch end
local function combinedMaterials()
 local rows={}
 for _,r in ipairs(source() and source().materials or {}) do rows[#rows+1]=r end
 for _,r in ipairs(additional() and additional().materials or {}) do rows[#rows+1]=r end
 for _,r in ipairs(scales() and scales().materials or {}) do rows[#rows+1]=r end
 return rows
end
local function combinedLeads()
 local rows={}
 for _,r in ipairs(source() and source().leads or {}) do rows[#rows+1]=r end
 for _,r in ipairs(additional() and additional().leads or {}) do rows[#rows+1]=r end
 for _,r in ipairs(scales() and scales().leads or {}) do rows[#rows+1]=r end
 return rows
end
-- Inspect an independently qualified ITEM ID against a ZONE-level advisory.
-- Neither the item page nor zone guide asserts an actual mob->item drop or
-- a farm polygon. Manual Bank/AH lookup does not imply source qualification.
function M:BuildManualAcquisition(mapID,skill,itemID)
 local catalog=JLP:GetModule("SkinningResearchCatalog")
 local area,reason=catalog and catalog:GetQualifiedZoneAreaAdvice(mapID,skill)
 local material,materialReason=self:GetMaterial(itemID)
 if not material then return nil,materialReason end
 local scope=area and area.status=="ZONE_AREA_SOURCE_ADVICE"
 local status=scope and "AREA_ADVICE_ITEM_OUTPUT_UNVERIFIED" or "SOURCE_UNAVAILABLE"
 return {status=status,materialName=material.name,itemID=material.itemID,
     itemSource=material.sourceURL,tabRequested=material.tabRequested,
     skinningRelationQualified=false,mobOutputQualified=false,
     zoneSource=scope and area.sourceURL or nil,mapID=mapID,skill=skill,
     geometryType="AREA",geometryStatus="ZONE_ONLY_NO_POLYGON",
     bankAction="MANUAL_ITEM_INSPECTION_ONLY",ahAction="MANUAL_LOOKUP_NO_PRICE",
     sourceJoin="MOB_OUTPUT_UNVERIFIED",nativeDispatchAllowed=false,
     returnContext={mapID=mapID,skill=skill,itemID=itemID}}
end
function M:GetMaterial(itemID)
 if not positive(itemID) then return nil,"ITEM_ID_INVALID" end
 for _,r in ipairs(combinedMaterials()) do
  if r.itemID==itemID then return {itemID=r.itemID,name=r.name,category=r.category or "LEATHER",
   tabRequested=r.tabRequested,sourceURL=r.sourceURL,evidence=r.evidence,
   scope=r.scope or "ITEM_IDENTITY",alternativeSource=r.alternativeSource or "UNKNOWN",
   mobOutputVerified=false,geometryVerified=false,notLiveSpawn=true,
   nativeDispatchAllowed=false} end
 end
 return nil,"MATERIAL_NOT_CATALOGUED"
end
function M:ListMaterialResearch(itemID)
 if not positive(itemID) then return nil,"ITEM_ID_INVALID" end
 local out={itemID=itemID,leads={},status="NO_HISTORICAL_LEADS",notLiveSpawn=true,
  verifiedMobOutputPairs=0,verifiedAreas=0,nativeDispatchAllowed=false}
 for _,r in ipairs(combinedLeads()) do
  if r.itemID==itemID then
   out.leads[#out.leads+1]={itemID=r.itemID,mapID=r.mapID,zone=r.zone,
    mobLabel=r.mobLabel,levelMin=r.levelMin,levelMax=r.levelMax,
    sourceURL=r.sourceURL,sourceType=r.sourceType,evidence=r.evidence,
    mobOutputVerified=false,geometryVerified=false,notLiveSpawn=true}
  end
 end
 if #out.leads>0 then out.status="HISTORICAL_TEXT_ONLY" end
 out.leadCount=#out.leads
 return out
end
function M:GetMapResearch(mapID)
 if not positive(mapID) then return nil,"MAP_ID_INVALID" end
 local out={mapID=mapID,materialCount=0,leadCount=0,materials={},
  status="NO_HISTORICAL_LEADS",verifiedMobOutputPairs=0,verifiedAreas=0,
  hasGeometry=false,notLiveSpawn=true,nativeDispatchAllowed=false}
 local seen={}
 for _,r in ipairs(source() and source().leads or {}) do
  if r.mapID==mapID then
   out.leadCount=out.leadCount+1
   if not seen[r.itemID] then
    seen[r.itemID]=true
    out.materialCount=out.materialCount+1
    local material=self:GetMaterial(r.itemID)
    out.materials[#out.materials+1]={itemID=r.itemID,name=material and material.name or "Unknown",
      evidence="HISTORICAL_TEXT_ONLY",mobOutputVerified=false,notLiveSpawn=true}
   end
  end
 end
 table.sort(out.materials,function(a,b) return a.itemID<b.itemID end)
 if out.leadCount>0 then out.status="HISTORICAL_TEXT_ONLY" end
 return out
end
function M:GetHideScaleMapResearch(mapID)
 if not positive(mapID) then return nil,"MAP_ID_INVALID" end
 local items,seen,leads={},{},0
 for _,r in ipairs(additional() and additional().leads or {}) do
  if r.mapID==mapID then
   leads=leads+1
   if not seen[r.itemID] then
    seen[r.itemID]=true
    local material=self:GetMaterial(r.itemID)
    items[#items+1]={itemID=r.itemID,name=material and material.name or "Unknown",evidence="HISTORICAL_TEXT_ONLY",mobOutputVerified=false}
   end
  end
 end
 table.sort(items,function(a,b) return a.itemID<b.itemID end)
 return {mapID=mapID,leadCount=leads,materials=items,verifiedAreas=0,hasGeometry=false,notLiveSpawn=true,
  status=leads>0 and "HISTORICAL_TEXT_ONLY" or "NO_HISTORICAL_LEADS"}
end
function M:GetCoverage()
 local d=source() or {}
 local stats={materialCount=0,itemPages=0,leadCount=0,
  withLeads=0,withoutLeads=0,verifiedMobOutputPairs=0,verifiedAreas=0,
  hideScaleMaterialCount=0,hideScaleLeadCount=0,scaleExpansionCount=0,scaleExpansionLeadCount=0,allMaterialsCount=0,
  caveat="Historical source leads only; no build-70009 tab output or spawn proof",
  nativeDispatchAllowed=false,notLiveSpawn=true}
 local seen={}
 for _,row in ipairs(d.materials or {}) do
  if positive(row.itemID) and type(row.sourceURL)=="string" and
     row.sourceURL:find("https://www.wowhead.com/forever/item=",1,true)==1 then
   stats.materialCount=stats.materialCount+1
   stats.itemPages=stats.itemPages+1
  end
 end
 for _,row in ipairs(d.leads or {}) do
  stats.leadCount=stats.leadCount+1
  seen[row.itemID]=true
 end
 for _,row in ipairs(d.materials or {}) do
  if seen[row.itemID] then stats.withLeads=stats.withLeads+1
  else stats.withoutLeads=stats.withoutLeads+1 end
 end
 local added=additional() or {}
 for _,r in ipairs(added.materials or {}) do
  if positive(r.itemID) then stats.hideScaleMaterialCount=stats.hideScaleMaterialCount+1 end
 end
 stats.hideScaleLeadCount=#(added.leads or {})
 stats.scaleExpansionCount=#(scales() and scales().materials or {})
 stats.scaleExpansionLeadCount=#(scales() and scales().leads or {})
 stats.allMaterialsCount=stats.materialCount+stats.hideScaleMaterialCount+stats.scaleExpansionCount
 local references=self:GetStaticSupplies();local materials={}
 stats.staticReferenceCount=#references;stats.staticMaterialPairs=0;stats.staticMaterialCount=0
 for _,r in ipairs(references) do
  for _,id in ipairs(r.itemIDs) do materials[id]=true;stats.staticMaterialPairs=stats.staticMaterialPairs+1 end
 end
 for _ in pairs(materials) do stats.staticMaterialCount=stats.staticMaterialCount+1 end
 stats.currentSpawnVerified=false
 return stats
end
function M:ListMaterials(category,offset,limit)
 local accepted={LEATHER=true,HIDE=true,SCALE=true,ALL=true}
 category=category or "ALL"
 if not accepted[category] then return nil,"CATEGORY_UNSUPPORTED" end
 offset=tonumber(offset) or 0
 limit=tonumber(limit) or 6
 if offset~=math.floor(offset) or offset<0 or limit~=math.floor(limit) or limit<1 then
  return nil,"PAGE_INVALID"
 end
 limit=math.min(limit,10)
 local selected={}
 for _,r in ipairs(combinedMaterials()) do
  local kind=r.category or "LEATHER"
  if category=="ALL" or category==kind then selected[#selected+1]=r end
 end
 table.sort(selected,function(a,b)
  if (a.category or "LEATHER")== (b.category or "LEATHER") then return a.itemID<b.itemID end
  return (a.category or "LEATHER")<(b.category or "LEATHER")
 end)
 local page={category=category,total=#selected,offset=offset,limit=limit,items={},
  nextOffset=nil,previousOffset=offset>=limit and offset-limit or nil,
  verifiedMobOutputPairs=0,verifiedFarmAreas=0,notLiveSpawn=true,nativeDispatchAllowed=false}
 for i=offset+1,math.min(offset+limit,#selected) do
  local r=selected[i]
  local lead=self:ListMaterialResearch(r.itemID)
  page.items[#page.items+1]={itemID=r.itemID,name=r.name,category=r.category or "LEATHER",
   sourceURL=r.sourceURL,evidence="ITEM_PAGE_IDENTITY_ONLY",tabRequested=r.tabRequested,
   scope=r.scope or "ITEM_IDENTITY",alternativeSource=r.alternativeSource or "UNKNOWN",
   historicalLeadCount=lead.leadCount,mobOutputVerified=false,geometryVerified=false,notLiveSpawn=true}
 end
 if offset+limit<#selected then page.nextOffset=offset+limit end
 return page
end
function M:GetOutputQualification(itemID)
 local mat,err=self:GetMaterial(itemID)
 if not mat then return nil,err end
 local leads=self:ListMaterialResearch(itemID)
 local external=self:GetStaticSupplies(itemID)
 return {itemID=itemID,category=mat.category,scope=mat.scope,externalSkinningSourceCount=#external,
  externalGeometrySourceCount=#external,currentSpawnVerified=false,
  alternativeSource=mat.alternativeSource,sourceURL=mat.sourceURL,
  historicalMobLeads=leads.leadCount,verifiedMobOutputPairs=0,verifiedAreas=0,
  state="SOURCE_RESEARCH_ONLY",notLiveSpawn=true,nativeDispatchAllowed=false}
end
function M:ExplainMaterial(itemID)
 local material,err=self:GetMaterial(itemID)
 if not material then return nil,err end
 local research=self:ListMaterialResearch(itemID)
 return {itemID=itemID,name=material.name,leadCount=research.leadCount,
  summary=material.name.." · "..tostring(research.leadCount)..
   " historical zone/mob leads; no verified build-70009 Skinning drop", 
  sourceURL=material.sourceURL,scope=material.scope,alternativeSource=material.alternativeSource,
  notLiveSpawn=true,nativeDispatchAllowed=false}
end
-- Canonical compact references are separate from legacy item-page leads and
-- from the observation store. Qualification never accepts caller-supplied pins.
local function detached(v)
 if type(v)~="table" then return v end
 local out={};for k,x in pairs(v) do out[k]=detached(x) end;return out
end
function M:GetStaticSupplies(itemID)
 if itemID~=nil and not positive(itemID) then return {} end
 local out={}
 for _,r in ipairs(source() and source().staticSupplies or {}) do
  local url=type(r.sourceURL)=="string" and tonumber(r.sourceURL:match("^https://www%.wowhead%.com/forever/npc=(%d+)/[^#]+#skinning$"))
  local pinMap,pinX,pinY
  if type(r.coordinateProof)=="string" then pinMap,pinX,pinY=r.coordinateProof:match("^/way #(%d+) ([%d.]+) ([%d.]+) ") end
  local qualified=positive(r.mobID) and url==r.mobID and r.id=="FOREVER_SKIN_"..r.mobID and
   r.lootScope=="SKINNING_TAB" and r.evidence=="EXTERNAL_FOREVER_REFERENCE" and
   r.sourceType=="WOWHEAD_FOREVER_NPC_SKINNING_TAB" and r.mapDomain=="UI_MAP_ID" and
   r.geometryScope=="PUBLISHED_MOB_LOCATION_NOT_LIVE_SPAWN" and
   positive(r.mapID) and positive(r.levelMin) and positive(r.levelMax) and r.levelMax>=r.levelMin and
   type(r.x)=="number" and r.x>0 and r.x<1 and type(r.y)=="number" and r.y>0 and r.y<1 and
   tonumber(pinMap)==r.mapID and tonumber(pinX) and math.abs(tonumber(pinX)-r.x*100)<0.00001 and tonumber(pinY) and math.abs(tonumber(pinY)-r.y*100)<0.00001
  local includes=itemID==nil
  for _,id in ipairs(type(r.itemIDs)=="table" and r.itemIDs or {}) do if id==itemID then includes=true end end
  if qualified and includes then
   local copy=detached(r);copy.scope="STATIC_FOREVER_SKINNING_REFERENCE"
   copy.notLiveSpawn=true;copy.notGuaranteedLoot=true;copy.nativeDispatchAllowed=false
   out[#out+1]=copy
  end
 end
 return out
end
function M:GetProgressionSource(skill,unavailable)
 local eligibility=JLP:GetModule("ForeverSkinningEligibility230")
 local best
 for _,r in ipairs(self:GetStaticSupplies()) do
  local minimum=eligibility and eligibility:RequiredSkill(r.levelMax)
  if type(skill)=="number" and minimum and skill>=minimum and not (unavailable and unavailable[r.id]) and
    (not best or r.levelMax>best.levelMax or r.levelMax==best.levelMax and r.id<best.id) then best=r end
 end
 return best -- Eligibility is not positive skill-up probability: check corpse color on arrival.
end
JLP:RegisterModule("SkinningMaterialIntelligence",M)
