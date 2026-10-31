local _, JLP = ...
-- Strict, read-only translation from reference-node identities to planner reagents.
-- Never infer a resource identity from a localized UI label; fallback names here are
-- canonical source/catalog lookups, not authority to create a missing item ID.
local Bridge={contract="jlp-smart-gathering-material-bridge-v1",nativeDispatchAllowed=false}
local herbIDs={SILVERLEAF=765,MAGEROYAL=785,PEACEBLOOM=2447,EARTHROOT=2449,
 BRIARTHORN=2450}

herbIDs.BRUISEWEED=2453;herbIDs.WILD_STEELBLOOM=3355
herbIDs.STRANGLEKELP=3820;herbIDs.GOLDTHORN=3821
herbIDs.ARTHAS_TEARS=8836;herbIDs.SUNGRASS=8838;herbIDs.BLINDWEED=8839
-- Verified Forever item IDs: each entry is the primary ore output only.
-- Not a promise of exclusive yield: gems, stones and bonus outputs are not modeled.
-- Source: Wowhead Forever item pages (2770,2771,2772,2775,2776,3858,7911,10620).
local oreOutputIDs={COPPER_VEIN=2770,TIN_VEIN=2771,SILVER_VEIN=2775,
 GOLD_VEIN=2776,IRON_DEPOSIT=2772,MITHRIL_DEPOSIT=3858,
 TRUESILVER_DEPOSIT=7911,THORIUM_VEIN=10620,
 SMALL_THORIUM_VEIN=10620,RICH_THORIUM_VEIN=10620,DARK_IRON_DEPOSIT=11370}
function Bridge:ResolveItem(profession,resource)
 local catalog=JLP:GetModule("MaterialCatalog")
 if profession=="HERBALISM" then
  local evidence=JLP.data and JLP.data.gatheringResourceOutputEvidence
  local evidenceRow=evidence and evidence.HERBALISM and evidence.HERBALISM[resource]
  local id=herbIDs[resource] or (evidenceRow and evidenceRow.itemID)
  if not id then return nil,"UNMAPPED_RESOURCE" end
  local row=catalog and catalog:Resolve(id)
  if row and row.itemID and row.itemID~=id then return nil,"IDENTITY_CONFLICT" end
  return id,evidenceRow and "EXPLICIT_FOREVER_HERB_ITEM_ID" or "EXPLICIT_ALCHEMY_DATASET_ID"
 elseif profession=="MINING" then
  local id=oreOutputIDs[resource]
  if not id then return nil,"UNMAPPED_RESOURCE" end
  local row=catalog and catalog:Resolve(id)
  if row and row.itemID and row.itemID~=id then return nil,"IDENTITY_CONFLICT" end
  return id,resource=="DARK_IRON_DEPOSIT" and "EXPLICIT_FOREVER_DARK_IRON_ITEM_ID" or "EXPLICIT_FOREVER_ORE_ITEM_ID"
 end
 return nil,"UNMAPPED_RESOURCE"
end
-- Enumerate candidate identities without pretending every candidate is an
-- accessible generic material output. Caller receives an independent snapshot.
function Bridge:GetOutputCandidates(profession,resource)
 local sourced=JLP.data and JLP.data.gatheringOutputCandidates
 local row=sourced and sourced[profession] and sourced[profession][resource]
 local primary,reason=self:ResolveItem(profession,resource)
 local out={professionKey=profession,resourceKey=resource,
   sourceStatus=row and row.status or (primary and "DOCUMENTED_PRIMARY" or "UNKNOWN"),
   sourceURL=row and row.sourceURL or nil,outputs={},
   notLiveSpawn=true,nativeDispatchAllowed=false}
 if row and type(row.outputs)=="table" then
   local seen={}
   for _,entry in ipairs(row.outputs) do
     local id=entry.itemID
     if type(id)=="number" and id==math.floor(id) and id>0 and not seen[id] then
       seen[id]=true
       out.outputs[#out.outputs+1]={itemID=id,kind=entry.kind,
        smartAllowed=entry.smartAllowed==true and (entry.kind=="PRIMARY" or entry.kind=="POSSIBLE_BYPRODUCT"),
        weight=entry.smartAllowed==true and math.max(0,math.min(1,tonumber(entry.weight) or 0)) or 0,
        sourceURL=row.sourceURL,notGuaranteedLoot=true}
     end
   end
 end
 if profession=="MINING"or profession=="HERBALISM"then
   local guide=JLP:GetModule(profession=="MINING"and "ForeverMiningNodeProgression210"or "ForeverHerbalismProgression209")
   local n=guide and guide:GetNodeContract(resource)
   if n then
    local seen={};for _,x in ipairs(out.outputs)do seen[x.itemID]=true end
    for _,id in ipairs(n.itemIDs)do if not seen[id]then
     out.outputs[#out.outputs+1]={itemID=id,kind=id==primary and "PRIMARY"or "POSSIBLE_BYPRODUCT",smartAllowed=true,
      weight=1,weightSemantics="DEMAND_SIGNAL_NOT_LOOT_PROBABILITY",sourceURL=n.sourceURL,notGuaranteedLoot=true}
    end end
   end
 end
 if primary then
   local found=false
   for _,entry in ipairs(out.outputs) do if entry.itemID==primary and entry.smartAllowed then found=true;break end end
   if not found then table.insert(out.outputs,1,{itemID=primary,kind="PRIMARY",
     smartAllowed=true,weight=1,notGuaranteedLoot=true,sourceURL=out.sourceURL}) end
 end
 out.primaryItemID=primary
 return out,reason
end
-- Generic-material fallback for Materials when planner has no shortages.
-- Only a qualified documented primary output counts, never quest-only
-- contextual loot or fabricated node yield probabilities.
function Bridge:HasQualifiedGenericOutput(profession,resource)
 local candidates=self:GetOutputCandidates(profession,resource)
 for _,row in ipairs(candidates and candidates.outputs or {}) do
  if row.smartAllowed==true and row.kind=="PRIMARY" and
    type(row.itemID)=="number" and row.itemID>0 then
    return true
  end
 end
 return false
end
-- Conservative score: choose ONE strongest documented demand signal per
-- reference; never add or multiply independent possible output yields.
function Bridge:MatchMaterialNeeds(profession,resource,needs)
 local catalog=self:GetOutputCandidates(profession,resource)
 local result={missing=0,weightedDemand=0,itemID=nil,outputKind=nil,
    qualified=false,notGuaranteedLoot=true,sourceStatus=catalog.sourceStatus}
 for _,out in ipairs(catalog.outputs) do
  local missing=type(needs)=="table" and math.max(0,tonumber(needs[out.itemID]) or 0) or 0
  if out.smartAllowed and missing>0 and out.weight>0 then
   local score=math.min(1,math.log(1+missing)/math.log(35))*out.weight
   if score>result.weightedDemand then
    result.weightedDemand=score;result.missing=missing;result.itemID=out.itemID
    result.outputKind=out.kind;result.qualified=true
   end
  end
 end
 return result
end
-- Coverage is a typed diagnostic, not authority to infer unverified loot.
-- All known reference resource identities are enumerated, even when a
-- planner material output cannot be established in the current dataset.
function Bridge:GetCoverageSnapshot()
 local packed=JLP.data and JLP.data.gatheringReferencePacked
 local unique={}
 for _,zone in pairs(type(packed)=="table" and packed.maps or {}) do
  for _,rec in ipairs(zone) do
   local prof,key=rec[2],rec[3]
   if (prof=="HERBALISM" or prof=="MINING") and type(key)=="string" then
    unique[prof..":"..key]={professionKey=prof,resourceKey=key}
   end
  end
 end
 local restricted=JLP.data and JLP.data.gatheringRestrictedResourceIdentity
 local list={};local stats={total=0,EXPLICIT_ITEM_ID=0,CATALOG_NAME_LOOKUP=0,
  questRestrictedIdentityCount=0,identityUnknownCount=0,
  encounterConditionalCount=0,documentedPrimaryCount=0,
  UNMAPPED_RESOURCE=0,IDENTITY_CONFLICT=0}
 for _,row in pairs(unique) do
  local id,reason=self:ResolveItem(row.professionKey,row.resourceKey)
  local status=(id and (reason=="EXPLICIT_ALCHEMY_DATASET_ID" or reason=="EXPLICIT_FOREVER_ORE_ITEM_ID" or reason=="EXPLICIT_FOREVER_DARK_IRON_ITEM_ID" or reason=="EXPLICIT_FOREVER_HERB_ITEM_ID") and "EXPLICIT_ITEM_ID") or
   (id and reason=="MATERIAL_CATALOG_ID" and "CATALOG_NAME_LOOKUP") or
   (reason=="IDENTITY_CONFLICT" and "IDENTITY_CONFLICT") or "UNMAPPED_RESOURCE"
  row.status=status
  row.itemID=id
  local restrictedRow=restricted and restricted[row.professionKey] and restricted[row.professionKey][row.resourceKey]
  if restrictedRow and not id and status=="UNMAPPED_RESOURCE" and
     restrictedRow.identityStatus=="QUEST_RESTRICTED" and restrictedRow.notGenericPlannerMaterial then
     row.itemIdentityID=restrictedRow.itemID
     row.itemIdentityStatus="QUEST_RESTRICTED_NOT_GENERIC_MATERIAL"
     row.identitySourceURL=restrictedRow.sourceURL
     row.smartMaterialsEligible=false
     stats.questRestrictedIdentityCount=stats.questRestrictedIdentityCount+1
  elseif id then
     row.itemIdentityID=id
     row.itemIdentityStatus="IDENTIFIED_PLANNER_PRIMARY_OUTPUT"
     row.smartMaterialsEligible=true
  else
     row.itemIdentityStatus="UNKNOWN"
     row.smartMaterialsEligible=false
     stats.identityUnknownCount=stats.identityUnknownCount+1
  end
  local evidenceCatalog=JLP.data and JLP.data.gatheringOutputCandidates
  local candidateRow=evidenceCatalog and evidenceCatalog[row.professionKey] and evidenceCatalog[row.professionKey][row.resourceKey]
  if candidateRow then
   row.candidateStatus=candidateRow.status
   row.candidateSourceURL=candidateRow.sourceURL
   row.candidateOutputCount=#(candidateRow.outputs or {})
   if candidateRow.status=="ENCOUNTER_CONDITIONAL_MULTI_OUTPUT" then
    stats.encounterConditionalCount=stats.encounterConditionalCount+1
    stats.identityUnknownCount=stats.identityUnknownCount-1
    row.smartMaterialsEligible=false
    row.itemIdentityStatus="ENCOUNTER_CONDITIONAL_NOT_GENERIC"
   elseif candidateRow.status=="QUEST_CONTEXT_ONLY" or candidateRow.status=="EPHEMERAL_CONTEXT_ONLY" then
    stats.questRestrictedIdentityCount=stats.questRestrictedIdentityCount+1
    stats.identityUnknownCount=stats.identityUnknownCount-1
    row.itemIdentityID=candidateRow.itemIdentityID
    row.itemIdentityStatus="RESTRICTED_NOT_GENERIC_MATERIAL"
    row.identitySourceURL=candidateRow.sourceURL
    row.smartMaterialsEligible=false
   elseif candidateRow.status=="DOCUMENTED_PRIMARY" then
    stats.documentedPrimaryCount=stats.documentedPrimaryCount+1
   end
  end
  row.reason=reason
  if candidateRow and not row.sourceURL then row.sourceURL=candidateRow.sourceURL end
  row.outputSemantics=id and "PRIMARY_OUTPUT_ONLY_NOT_EXCLUSIVE_LOOT" or "OUTPUT_UNKNOWN"
  local cited=JLP.data and JLP.data.gatheringResourceOutputEvidence
  local evidence=cited and cited[row.professionKey] and cited[row.professionKey][row.resourceKey]
  row.sourceURL=(evidence and evidence.sourceURL) or
    (candidateRow and candidateRow.sourceURL) or (restrictedRow and restrictedRow.sourceURL) or nil
  row.identityEvidenceStatus=evidence and evidence.confidence or
    candidateRow and candidateRow.status or (id and "LEGACY_EXPLICIT_ID" or "UNKNOWN")
  row.sourceAuthority=status=="EXPLICIT_ITEM_ID" and (evidence and "WOWHEAD_FOREVER_HERB_ITEM_ID" or
   row.professionKey=="MINING" and "WOWHEAD_FOREVER_ORE_ITEM_ID" or "EXPLICIT_DATASET") or
   status=="CATALOG_NAME_LOOKUP" and "CATALOG_NAME_DEPENDENCY" or "UNKNOWN"
  stats.total=stats.total+1
  stats[status]=stats[status]+1
  list[#list+1]=row
 end
 table.sort(list,function(a,b)
  if a.professionKey~=b.professionKey then return a.professionKey<b.professionKey end
  return a.resourceKey<b.resourceKey
 end)
 stats.resources=list
 stats.nativeDispatchAllowed=false
 return stats
end
function Bridge:FromRequirements(rows)
 local needs={};local total=0
 for _,r in ipairs(type(rows)=="table" and rows or {}) do
  local id=tonumber(r.itemID);local missing=tonumber(r.preparedMissing or r.missing)
  if id and id>0 and r.kind~="crafted" and missing and missing>0 then
   -- Current bank stock is counted as owned. Stale alt-bank snapshots are not
   -- treated as carried inventory or a guaranteed available reagent.
   -- Do not subtract advisory alt-bank amounts from missing. Only stable item
   -- identities can be matched to a gatherable node by ResolveItem.
   local amount=math.max(0,math.floor(missing))
   needs[id]=(needs[id] or 0)+amount
   total=total+amount
  end
 end
 return needs,total
end
-- Supply decisions consume observed stock for the selected immediate craft,
-- not the recursively expanded forecast (which may contain hypothetical outputs).
local skinItems={[2934]=true,[2318]=true,[2319]=true,[4234]=true,[4304]=true,[8170]=true,
 [783]=true,[4232]=true,[4235]=true,[8169]=true,[8171]=true}
function Bridge:GetSkinningWaypoint(itemID,id)
 local store=JLP:GetModule("GatheringObservationStore")
 for _,r in ipairs(store and store:GetSkinningSupplies(itemID) or {}) do
  if r.id==id then
   return {kind="gather",profession="SKINNING",material=tostring(itemID),serviceID=r.id,
    name="Previously observed Skinning supply",zone="UIMap "..r.mapID,
    sourceQualified=true,state="SOURCE_QUALIFIED",nativeDispatchAllowed=false,
    ownerAuthority="PERSONAL_SKINNING_HISTORY_NOT_LIVE_SPAWN",sourceRow=r.observedAt,
    nav={mapID=r.mapID,x=r.x,y=r.y,mapDomain="UI_MAP_ID",evidence=r.evidenceKind..":"..r.id},
    scope=r.scope,clientBuild=r.clientBuild,notGuaranteedLoot=true}
  end
 end
 local intel=JLP:GetModule("SkinningMaterialIntelligence")
 for _,r in ipairs(intel and intel:GetStaticSupplies(itemID) or {}) do
  if r.id==id then
   return {kind="gather",profession="SKINNING",material=tostring(itemID),serviceID=r.id,npcID=r.mobID,
    name=r.name.." (public location; verify on arrival)",zone=r.zone,
    sourceQualified=true,state="SOURCE_QUALIFIED",nativeDispatchAllowed=false,
    ownerAuthority="STATIC_FOREVER_SKINNING_REFERENCE",sourceURL=r.sourceURL,sourceRow=r.id,
    nav={mapID=r.mapID,x=r.x,y=r.y,mapDomain="UI_MAP_ID",evidence=r.evidence..":"..r.id},
    scope=r.scope,geometryScope=r.geometryScope,notGuaranteedLoot=true,notLiveSpawn=true}
  end
 end
end
function Bridge:GetEligibleSkinningSources(itemID)
 local api=JLP:GetModule("ProfessionAPI")
 local ownership=api and api.GetOwnership and api:GetOwnership("SKINNING")
 if not (ownership and ownership.owned==true)then return {}end
 local api=JLP:GetModule("ProfessionAPI")
 local prof=api and api:Get("SKINNING")
 local eligibility=JLP:GetModule("ForeverSkinningEligibility230")
 local options={}
 if not (prof and prof.cached~=true and type(prof.skill)=="number" and eligibility) then return options end
 local store=JLP:GetModule("GatheringObservationStore")
 local intel=JLP:GetModule("SkinningMaterialIntelligence")
 local candidates=store and store:GetSkinningSupplies(itemID) or {}
 for _,r in ipairs(intel and intel:GetStaticSupplies(itemID) or {}) do candidates[#candidates+1]=r end
 for _,r in ipairs(candidates) do
  local minimum=eligibility:RequiredSkill(r.levelMax or r.mobLevel)
  if minimum and prof.skill>=minimum and not (self.unavailable and self.unavailable[r.id]) then options[#options+1]=r end
 end
 local map=JLP:GetModule("ForeverFishingMapCanvas")
 local zone=map and map:GetCurrentZone();local currentMap=zone and zone.mapID
 table.sort(options,function(a,b)
  local al,bl=a.mapID==currentMap,b.mapID==currentMap
  if al~=bl then return al end -- Relevant local references before cross-zone travel.
  local ah,bh=a.scope~="STATIC_FOREVER_SKINNING_REFERENCE",b.scope~="STATIC_FOREVER_SKINNING_REFERENCE"
  if ah~=bh then return ah end
  return a.id<b.id
 end)
 return options
end
function Bridge:SelectSkinningSupply(itemID,required,strategy)
 if not skinItems[itemID] or type(required)~="number" or required~=required or required<0 or
     required==math.huge then return nil end
 local inventory=JLP:GetModule("Inventory")
 local stock=inventory and inventory:GetOwned(itemID) or {}
 local result={itemID=itemID,required=required,strategy=strategy,readOnly=true,
  nativeDispatchAllowed=false,guaranteed=false,mobCount=nil,
  optimization="LOCAL_CONDITIONAL_NO_QUALIFIED_TOTAL_TIME_OR_GLOBAL_COST",
  priceStatus="UNKNOWN",timeStatus="UNKNOWN",bankEvidence=stock.bankEvidence,
  bankCacheUpdatedAt=stock.bankCacheUpdatedAt}
 if stock.bagKnown~=true then result.status="UNKNOWN_INVENTORY";return result end
 local missing=math.max(0,required-(stock.bags or 0))
 if missing==0 then result.status="BAGS_READY";result.quantity=0;return result end
 -- Even a historical bank observation is displayed with its freshness; it
 -- must be withdrawn/observed before the craft can use it.
 if stock.bankKnown==true and (stock.bank or 0)>0 then
  result.status="BANK";result.quantity=math.min(missing,stock.bank);return result
 end
 if stock.bankKnown~=true then result.status="VERIFY_BANK";return result end
 result.quantity=missing
 local api=JLP:GetModule("ProfessionAPI")
 local prof=api and api:Get("SKINNING")
 local options=self:GetEligibleSkinningSources(itemID)
 local resolver=JLP:GetModule("PriceResolver")
 local quote=resolver and resolver.GetFulfillmentCost and resolver:GetFulfillmentCost(itemID,missing)
 local quoteKnown=quote and quote.complete==true and quote.trustedForCostEstimate==true and
   type(quote.cost)=="number" and quote.cost>=0 and quote.cost<math.huge
 local money
 if type(GetMoney)=="function" then
  local ok,value=pcall(GetMoney)
  if ok and type(value)=="number" and value==value and value>=0 and value<math.huge then money=value end
 end
 result.affordability=not quoteKnown and "UNKNOWN" or money==nil and "UNKNOWN" or
  quote.cost>money and "INSUFFICIENT_FUNDS" or "AFFORDABLE"
 result.auctionQuote=quoteKnown and quote or nil
 result.priceStatus=quoteKnown and "QUALIFIED_QUOTE_RECHECK_OFFER" or "UNKNOWN"
 if strategy=="fastest" and quoteKnown and result.affordability~="INSUFFICIENT_FUNDS" then
  result.status="AUCTION";result.selectionReason="DIRECT_QUOTED_PURCHASE_FALLBACK_TOTAL_TIME_UNKNOWN"
 elseif options[1] then
  result.status="SKINNING";result.sourceID=options[1].id;result.mapID=options[1].mapID
  result.scope=options[1].scope;result.source=self:GetSkinningWaypoint(itemID,result.sourceID)
  result.selectionReason=strategy=="self_found" and "QUALIFIED_OWN_SUPPLY_NOT_GUARANTEED_YIELD" or "NO_PURCHASE_OUTLAY_NOT_TOTAL_COST_PROOF"
 elseif quoteKnown and result.affordability~="INSUFFICIENT_FUNDS" and strategy~="self_found" then result.status="AUCTION"
 else
  result.status="VERIFY_SOURCE";result.scope="AREA_OR_RESEARCH_ONLY_NO_QUALIFIED_STOP"
  result.reason=not prof and "SKINNING_NOT_OBSERVED" or
   (prof.cached==true or type(prof.skill)~="number") and "SKINNING_STATE_NOT_CURRENTLY_OBSERVED" or
   (JLP:GetModule("SkinningMaterialIntelligence") and #JLP:GetModule("SkinningMaterialIntelligence"):GetStaticSupplies(itemID)>0) and
    "NO_ELIGIBLE_OR_AVAILABLE_QUALIFIED_SKINNING_SOURCE" or "NO_ELIGIBLE_OBSERVED_MATERIAL_STOP"
 end
 return result
end
function Bridge:SetSupplyUnavailable(id,unavailable)
 if type(id)~="string" then return false end
 self.unavailable=self.unavailable or {};self.unavailable[id]=unavailable==true or nil
 return true
end
local function qualifiedQuote(id,n)
 local prices=JLP:GetModule("PriceResolver")
 local q=prices and prices.GetFulfillmentCost and prices:GetFulfillmentCost(id,n)
 return q and q.complete==true and q.trustedForCostEstimate==true and type(q.cost)=="number"and
  q.cost==q.cost and q.cost>=0 and q.cost<math.huge and q or nil
end

local nodeModules={MINING="ForeverMiningNodeProgression210",HERBALISM="ForeverHerbalismProgression209"}
local nodeData={MINING="foreverMiningNodeProgression210",HERBALISM="foreverHerbalismProgression209"}
local function nodeGuide(prof)return nodeModules[prof]and JLP:GetModule(nodeModules[prof])end
local function nodeHasItem(n,itemID)
 if not itemID then return true end
 for _,id in ipairs(n.itemIDs or {})do if id==itemID then return true end end
 return false
end
local function nodeReferenceID(r,prof)
 return table.concat({prof=="MINING"and "MINE"or "HERB",r.uiMapID,r.resourceKey,r.objectID,math.floor(r.x*10000+.5),math.floor(r.y*10000+.5)},":")
end
local function nodeWaypoint(r,n,itemID,prof,observed)
 local id=observed and "HERB_OBS:"..r.id or nodeReferenceID(r,prof)
 return {kind="gather",profession=prof,material=tostring(itemID or n.itemIDs[1]),serviceID=id,
  objectID=n.objectID,resourceKey=n.resourceKey,name=n.name..(observed and " (personal historical harvest stop)"or " (historical reference; verify node)"),zone="UIMap "..(r.uiMapID or r.mapID),
  scope=observed and "PERSONAL_HERBALISM_OBJECT_LOOT_HISTORY"or "STATIC_FOREVER_"..prof.."_REFERENCE",
  ownerAuthority=observed and "PERSONAL_HERBALISM_HISTORY_NOT_LIVE_SPAWN"or "CANONICAL_GATHERING_REGISTRY_HISTORICAL_POINT",
  sourceQualified=true,state="SOURCE_QUALIFIED",sourceURL=n.sourceURL,geometryScope=observed and "PERSONAL_HARVEST_POSITION_NOT_SPAWN"or "HISTORICAL_RESOURCE_POINT_NOT_LIVE_NODE",
  notLiveSpawn=true,notGuaranteedLoot=true,
  nav={mapID=r.uiMapID or r.mapID,x=r.x,y=r.y,mapDomain="UI_MAP_ID",evidence="QUALIFIED_GATHERING_REFERENCE:"..id},nativeDispatchAllowed=false}
end
function Bridge:GetNodeWaypoint(prof,itemID,id)
 if not nodeModules[prof]or type(id)~="string"or type(itemID)~="number"then return nil end
 local guide=nodeGuide(prof)
 if prof=="HERBALISM"and id:match("^HERB_OBS:")then
  local store=JLP:GetModule("GatheringObservationStore")
  for _,r in ipairs(store and store:GetNodeSupplies(prof,itemID)or {})do
   local n=guide and guide:GetNodeContract(r.resourceKey,r.objectID)
   if n and nodeHasItem(n,itemID)and "HERB_OBS:"..r.id==id then return nodeWaypoint(r,n,itemID,prof,true)end
  end
  return nil
 end
 local prefix=prof=="MINING"and "MINE"or "HERB"
 local mapID=tonumber(id:match("^"..prefix..":(%d+):"))
 local registry=JLP:GetModule("GatheringDataRegistry")
 local snap=mapID and registry and registry:GetZoneSnapshot(mapID,prof)
 for _,r in ipairs(snap and snap.references or {})do
  local n=guide and guide:GetNodeContract(r.resourceKey,r.objectID)
  if n and nodeHasItem(n,itemID)and r.geometryType=="POINT"and nodeReferenceID(r,prof)==id then return nodeWaypoint(r,n,itemID,prof)end
 end
end
function Bridge:SelectNodeSource(prof,itemID,skill,progression,unavailable)
 local api=JLP:GetModule("ProfessionAPI")
 local ownership=api and api.GetOwnership and api:GetOwnership(prof)
 if not (ownership and ownership.owned==true)then return nil end
 if not nodeModules[prof]or type(skill)~="number"or skill<1 or skill>300 or skill~=math.floor(skill)then return nil,"SKILL_UNKNOWN"end
 local guide=nodeGuide(prof);local registry=JLP:GetModule("GatheringDataRegistry")
 local packed=JLP.data and JLP.data.gatheringReferencePacked
 if not guide or not registry or not packed or not packed.maps then return nil,"REFERENCE_DATA_UNAVAILABLE"end
 local contracts=JLP.data[nodeData[prof]]and JLP.data[nodeData[prof]].nodeContracts or {}
 local positive=false
 for _,n in ipairs(contracts)do if n.minimum<=skill and n.gray and skill<n.gray then positive=true end end
 local function eligible(n)return n and nodeHasItem(n,itemID)and n.minimum<=skill and (not progression or n.gray and skill<n.gray or not positive and not n.gray)end
 local store=prof=="HERBALISM"and JLP:GetModule("GatheringObservationStore")
 local personal=store and itemID and store:GetNodeSupplies(prof,itemID)or {}
 local maps,set={},{}
 for id in pairs(packed.maps)do set[id]=true end
 for _,v in ipairs(personal)do set[v.mapID]=true end
 for id in pairs(set)do maps[#maps+1]=id end
 local canvas=JLP:GetModule("ForeverFishingMapCanvas");local current=canvas and canvas:GetCurrentZone();local currentMap=current and current.mapID
 table.sort(maps,function(a,b)if (a==currentMap)~=(b==currentMap)then return a==currentMap end;return a<b end)
 for _,mapID in ipairs(maps)do
  local best,bestRank,bestObserved
  local function offer(r,n,observed)
   local id=observed and "HERB_OBS:"..r.id or nodeReferenceID(r,prof)
   if not(unavailable and (unavailable[id]or unavailable[n.resourceKey]))then
    local rank=progression and n.minimum or 0
    if not best or rank>bestRank or rank==bestRank and observed and not bestObserved or rank==bestRank and observed==bestObserved and id<best.serviceID then
     best=nodeWaypoint(r,n,itemID,prof,observed);bestRank=rank;bestObserved=observed
    end
   end
  end
  for _,v in ipairs(personal)do local n=guide:GetNodeContract(v.resourceKey,v.objectID);if v.mapID==mapID and eligible(n)then offer(v,n,true)end end
  local summary=registry:GetZoneResourceSummary(mapID,prof);local wanted={}
  for _,v in ipairs(summary and summary.resources or {})do local n=guide:GetNodeContract(v.resourceKey);if eligible(n)then wanted[v.resourceKey]=n end end
  if next(wanted)then
   local snap=registry:GetZoneSnapshot(mapID,prof)
   for _,v in ipairs(snap and snap.references or {})do local n=wanted[v.resourceKey];if n and v.objectID==n.objectID and v.geometryType=="POINT"then offer(v,n,false)end end
  end
  if best then return best,"QUALIFIED_REFERENCE_VERIFY_CURRENT_NODE"end
 end
 return nil,"NO_ELIGIBLE_AVAILABLE_REFERENCE"
end
function Bridge:IsHerbalismMaterial(itemID)
 if type(itemID)~="number"then return false end
 local data=JLP.data and JLP.data.foreverHerbalismProgression209
 for _,n in ipairs(data and data.nodeContracts or {})do if nodeHasItem(n,itemID)then return true end end
 return false
end
function Bridge:GetHerbalismWaypoint(itemID,id)return self:GetNodeWaypoint("HERBALISM",itemID,id)end
function Bridge:SelectHerbalismSupply(itemID,required,strategy,consumer)
 if not self:IsHerbalismMaterial(itemID)or type(required)~="number"or required<0 or required~=math.floor(required)or required==math.huge then return nil end
 local out={itemID=itemID,required=required,professionKey="HERBALISM",consumerProfession=consumer or "ALCHEMY",strategy=strategy,
  readOnly=true,nativeDispatchAllowed=false,observedOutputCredit=0,skillUpCredit=0,expectedGathers=nil,yieldStatus="UNKNOWN",timeStatus="UNKNOWN",priceStatus="UNKNOWN",optimization="LOCAL_CONDITIONAL_NO_GLOBAL_OPTIMUM"}
 local function finish(status,text)out.status=status;out.nextAction=text;return out end
 local inv=JLP:GetModule("Inventory");local stock=inv and inv:GetOwned(itemID)or {}
 if stock.bagKnown~=true then return finish("UNKNOWN_INVENTORY","Observe bags; UNKNOWN is not a definite herb shortage.")end
 out.quantity=math.max(0,required-(stock.bags or 0));out.actionItemID=itemID
 if out.quantity==0 then return finish("BAGS_READY","Required herb is observed in bags; resume Alchemy.")end
 if stock.bankKnown~=true then out.quantity=nil;return finish("VERIFY_BANK","Verify bank stock before a definite herb gathering or purchase amount.")end
 if(stock.bank or 0)>0 then out.actionQuantity=math.min(out.quantity,stock.bank);return finish("BANK","Withdraw the observed Alchemy material from bank; observe bags before crafting.")end
 local quote=qualifiedQuote(itemID,out.quantity);out.purchaseAlternative=quote
 local affordable=quote~=nil
 if quote and type(GetMoney)=="function"then local ok,n=pcall(GetMoney);if ok and type(n)=="number"and n<quote.cost then affordable=false end end
 out.priceStatus=quote and "QUALIFIED_QUOTE_VERIFY_CURRENT_OFFER_AND_FUNDS"or "UNKNOWN"
 local api=JLP:GetModule("ProfessionAPI");local herb=api and api:Get("HERBALISM")
 local cap=herb and herb.maxSkill;local known=herb and herb.cached~=true and type(herb.skill)=="number"and (cap==75 or cap==150 or cap==225 or cap==300)
 local source=known and self:SelectNodeSource("HERBALISM",itemID,herb.skill,false,self.unavailable)
 if strategy=="economical"and affordable then
  out.actionQuantity=out.quantity;out.selectionReason="QUALIFIED_PURCHASE_OUTLAY_GATHERING_TIME_AND_OPPORTUNITY_COST_UNKNOWN"
  return finish("AUCTION","Recheck the qualified herb quote and funds; buy manually, observe bags. This is not a proven total net-cost optimum.")
 end
 if source then
  out.source=source;out.sourceID=source.serviceID;out.mapID=source.nav.mapID;out.scope=source.scope;out.gatherItemID=itemID;out.gatherQuantity=out.quantity;out.actionQuantity=out.quantity
  out.selectionReason="QUALIFIED_OWN_SOURCE_LOCAL_FIRST_RATE_AND_TOTAL_TIME_UNKNOWN"
  local guide=nodeGuide("HERBALISM");local n=guide:GetNodeContract(source.resourceKey,source.objectID)
  return finish("HERBALISM","Visit "..source.name.."; harvest manually for item "..itemID.." (remaining "..out.quantity.."). "..n.accessNote.." Observe loot, bags and skill separately.")
 end
 if affordable and strategy~="self_found"then out.actionQuantity=out.quantity;return finish("AUCTION","Own gathering is not qualified; recheck the herb offer or arrange manual trade. No automatic purchase or fastest-time claim.")end
 out.reason=not herb and "HERBALISM_NOT_OBSERVED"or not known and "HERBALISM_STATE_UNKNOWN"or "NO_ELIGIBLE_AVAILABLE_HERBALISM_SOURCE"
 return finish("VERIFY_SOURCE","Verify Herbalism ownership/skill and an eligible source, or arrange qualified manual trade. No herb is credited.")
end
function Bridge:IsMiningMaterial(itemID)
 local nodes=JLP.data and JLP.data.foreverMiningNodeProgression210
 for _,n in ipairs(nodes and nodes.nodeContracts or {})do for _,id in ipairs(n.itemIDs or {})do if id==itemID then return true end end end
 local smelt=JLP:GetModule("MiningSmeltingProgression")
 return smelt and smelt:GetProducer(itemID)~=nil or false
end
function Bridge:GetMiningWaypoint(itemID,id)
 local guide=JLP:GetModule("ForeverMiningNodeProgression210")
 return guide and guide:GetWaypoint(itemID,id)
end
function Bridge:SelectMiningSupply(itemID,required,strategy,consumer)
 if not self:IsMiningMaterial(itemID)or type(required)~="number"or required<0 or required~=math.floor(required)or required==math.huge then return nil end
 local inv=JLP:GetModule("Inventory");local stock=inv and inv:GetOwned(itemID)or {}
 local out={itemID=itemID,required=required,strategy=strategy,consumerProfession=consumer,professionKey="MINING",
  readOnly=true,nativeDispatchAllowed=false,observedOutputCredit=0,mobCount=nil,nodeCount=nil,
  timeStatus="UNKNOWN",priceStatus="UNKNOWN",optimization="LOCAL_CONDITIONAL_NO_GLOBAL_OPTIMUM"}
 local function finish(status,text)out.status=status;out.nextAction=text;return out end
 if stock.bagKnown~=true then return finish("UNKNOWN_INVENTORY","Observe bags before calculating a mineral shortage.")end
 out.quantity=math.max(0,required-(stock.bags or 0))
 if out.quantity==0 then return finish("BAGS_READY","Selected consumer material is already observed in bags.")end
 if stock.bankKnown~=true then out.quantity=nil;return finish("VERIFY_BANK","Verify unknown bank stock before a precise gathering or purchase order.")end
 if (stock.bank or 0)>0 then out.actionItemID=itemID;out.actionQuantity=math.min(out.quantity,stock.bank);return finish("BANK","Withdraw the observed material from bank; recheck bags before crafting.")end
 local api=JLP:GetModule("ProfessionAPI");local mining=api and api:Get("MINING")
 local smelt=JLP:GetModule("MiningSmeltingProgression")
 local scenario=smelt and smelt:BuildSupplyScenario(itemID,required)
 out.production=scenario
 local next=scenario and scenario.next or {status="VERIFY_MINING",itemID=itemID}
 out.actionItemID=next.itemID;out.actionQuantity=next.quantity;out.producer=next.producer
 local quote=qualifiedQuote(itemID,out.quantity)
 local function affordable(q)
  if not q then return false end
  if type(GetMoney)=="function"then local ok,n=pcall(GetMoney);if ok and type(n)=="number"and n<q.cost then return false end end
  return true -- Unknown money requires a manual check, not a paid transaction.
 end
 out.purchaseAlternative=quote;out.priceStatus=quote and "QUALIFIED_QUOTE_VERIFY_OFFER_AND_FUNDS"or "UNKNOWN"
 local rawCost,rawKnown,rawCount=0,true,0
 for id,n in pairs(scenario and scenario.requirements or {})do
  rawCount=rawCount+1
  local q=qualifiedQuote(id,n);if not q then rawKnown=false else rawCost=rawCost+q.cost end
 end
 if rawCount==0 then rawKnown=false end
 out.quotedRawPurchaseCost=rawKnown and rawCost or nil
 -- Compare only qualified purchase outlays. Owned materials are not assigned
 -- a fictitious opportunity cost, and gathering time/rates remain unknown.
 if strategy=="economical"and affordable(quote)and rawKnown and quote.cost<=rawCost then
  out.actionItemID=itemID;out.actionQuantity=out.quantity
  out.selectionReason="LOWER_QUALIFIED_PURCHASE_OUTLAY_NOT_TOTAL_NET_COST"
  return finish("AUCTION","Recheck the qualified finished-material quote and funds; buy manually, then observe bags.")
 end
 if next.status=="ACQUIRE_RAW"then
  if not self:IsMiningMaterial(next.itemID)then
   return finish("VERIFY_EXTERNAL_INPUT","Acquire producer input item "..next.itemID.." through a qualified vendor, AH or manual trade. It is not inferred to be mined.")
  end
  local guide=JLP:GetModule("ForeverMiningNodeProgression210")
  local source=mining and mining.cached~=true and type(mining.skill)=="number"and
   guide and guide:SelectSource(next.itemID,mining.skill,false,self.unavailable)
  local rawQuote=qualifiedQuote(next.itemID,next.quantity)
  if strategy=="economical"and rawKnown and affordable(rawQuote)and quote and rawCost<quote.cost and smelt and smelt:GetProducer(itemID)then
   out.actionItemID=next.itemID;out.actionQuantity=next.quantity
   out.selectionReason="LOWER_QUALIFIED_RAW_PURCHASE_OUTLAY_SMELTING_TIME_AND_OPPORTUNITY_COST_UNKNOWN"
   return finish("AUCTION","Recheck the qualified raw-material quote; buy manually, then prepare the qualified producer chain.")
  end
  if source then
   out.source=source;out.sourceID=source.serviceID;out.mapID=source.nav.mapID;out.scope=source.scope
   out.gatherItemID=next.itemID;out.gatherQuantity=next.quantity
   out.selectionReason="QUALIFIED_OWN_SOURCE_LOCAL_FIRST_TOTAL_TIME_COST_UNKNOWN"
   return finish("MINING","Visit "..source.name.."; mine manually for item "..next.itemID.." (remaining "..next.quantity.."). Verify node/access; observe loot, bags and skill separately.")
  end
  if affordable(quote)and strategy~="self_found"then out.actionItemID=itemID;out.actionQuantity=out.quantity
   return finish("AUCTION","Own supply is not currently qualified. Recheck the quoted finished material or arrange manual trade; no fastest-time claim.")end
  out.reason=not mining and "MINING_NOT_OBSERVED"or "NO_ELIGIBLE_AVAILABLE_MINING_SOURCE"
  return finish("VERIFY_SOURCE","Verify Mining ownership and skill, another qualified source, or manual trade; no ore or bar is credited.")
 elseif next.status=="SMELT"then
  return finish("SMELT","Manually "..next.producer.recipeName.." at "..next.producer.stationName.." (expected casts "..next.producer.expectedCasts..
   ", output per cast "..next.producer.outputPerCraft.."). This is an expectation; observe actual bars and skill separately, then replan the consumer.")
 elseif next.status=="BANK"then return finish("BANK","Withdraw observed producer input item "..next.itemID.."; recheck bags before smelting.")
 elseif next.status=="VERIFY_FORGE"then
  local recipe=smelt:GetProducer(next.itemID)
  local station=recipe and smelt:GetForgeDestination(recipe)
  if station then out.source=station;out.sourceID=station.serviceID;out.mapID=station.nav.mapID;out.scope="EXTERNAL_FORGE_GEOGRAPHIC_REFERENCE"end
  return finish("VERIFY_FORGE","Visit the qualified "..next.producer.stationName.." reference when needed; open Mining and verify this exact recipe's current requirements before one manual smelt. Arrival is not readiness or output.")
 elseif next.status=="VERIFY_BANK"then out.actionQuantity=nil;return finish("VERIFY_BANK","Verify bank stock for producer input item "..next.itemID.."; no precise raw-material order is qualified.")
 elseif next.status=="UNKNOWN_INVENTORY"then out.actionQuantity=nil;return finish("UNKNOWN_INVENTORY","Observe producer input bags; UNKNOWN is not a definite shortage.")
 elseif next.status=="BAGS_READY"then return finish("BAGS_READY","Materials observed; resume the consumer plan.")
 else
  out.reason=next.status
  if affordable(quote)and strategy~="self_found"then out.actionItemID=itemID;out.actionQuantity=out.quantity
   return finish("AUCTION","Own smelting is not qualified; recheck the finished-material quote or manual trade. Unknown time is not zero.")end
  return finish(next.status,"Open Mining to verify producer learning, minimum, exact inputs and fixed output-yield. Preserve UNKNOWN/conflicts; no guessed ore order.")
 end
end
function Bridge:RefreshSupply(supply)
 if supply and supply.professionKey=="FISHING"then return self:SelectFishingSupply(supply.itemID,supply.required,supply.strategy,supply.consumerProfession or supply.ownerProfession)end
 if supply and supply.professionKey=="CLOTH"then return self:SelectClothSupply(supply.itemID,supply.required,supply.strategy,supply.consumerProfession or supply.ownerProfession)end
 if supply and supply.professionKey=="HERBALISM"then return self:SelectHerbalismSupply(supply.itemID,supply.required,supply.strategy,supply.consumerProfession)end
 if supply and supply.professionKey=="MINING"then return self:SelectMiningSupply(supply.itemID,supply.required,supply.strategy,supply.consumerProfession)end
 return supply and self:SelectSkinningSupply(supply.itemID,supply.required,supply.strategy)
end
function Bridge:CanPublishSupply(key,context)
 if context and context.preview==true then return false end
 local mode=JLP.DB and JLP.DB.profile and JLP.DB.profile.guideMode
 if (key=="FIRST_AID"or key=="COOKING")and JLP.DB and JLP.DB.profile and JLP.DB.profile.activeSecondaryCurrentStep==key then mode=key end
 if type(mode)=="string" and mode~="dual" and mode~="SKINNING" and mode~="MINING" and mode~="HERBALISM" and mode~="FISHING" and mode~="" and mode~=key then return false end
 if mode=="MINING"or mode=="SKINNING"or mode=="HERBALISM"or mode=="FISHING"then
  local shared=JLP:GetModule("GatheringSharedMapState")
  local snapshot=shared and shared:GetSnapshot()
  local active=snapshot and snapshot.automaticSupplyGoal
  if not active or active.ownerProfession~=key then return false end
 end
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if owner and owner.stopped then return false end
 return true
end
function Bridge:RetirePlanSupply(key,reason,context)
 if context and context.preview==true then return end
 local shared=JLP:GetModule("GatheringSharedMapState")
 if shared and shared.ClearAutomaticSupplyGoal then shared:ClearAutomaticSupplyGoal(key,reason) end
end
function Bridge:ApplyToPlan(key,plan,context)
 if (key=="COOKING"or key=="ALCHEMY")and type(plan)=="table"then
  local publish=self:CanPublishSupply(key,context);local shared=JLP:GetModule("GatheringSharedMapState")
  if publish and shared then shared:ClearAutomaticSupplyGoal(key,"OWNER_PLAN_REQUALIFIED")end
  self:ApplyFishingToPlan(key,plan,context)
  if key=="COOKING"or plan.materialSupply and plan.materialSupply.professionKey=="FISHING"then return plan end
 end
 if key=="FIRST_AID"and type(plan)=="table"then return self:ApplyClothToPlan(key,plan,context)end
 if (key~="LEATHERWORKING" and key~="BLACKSMITHING"and key~="ENGINEERING"and key~="ALCHEMY")or type(plan)~="table" then return plan end
 local shared=JLP:GetModule("GatheringSharedMapState")
 local publish=self:CanPublishSupply(key,context)
 local current=plan.recommendedCurrentStep
 -- A panel switch can make learned-state UNKNOWN. That is not observed
 -- cancellation of the owner's material intent; keep it for the Mining workspace.
 if not current or current.kind~="craft"or current.learned==nil then
  if publish and current and (current.kind=="train"or current.kind=="complete")and shared then shared:ClearAutomaticSupplyGoal(key,"OWNER_PREREQUISITE_CHANGED")end
  return plan
 end
 if publish and shared and shared.ClearAutomaticSupplyGoal then shared:ClearAutomaticSupplyGoal(key,"OWNER_PLAN_REQUALIFIED") end
 if current.learned~=true or current.bagReady==true or
    current.manualCraftBlockedByRecipePrerequisite==true then return plan end
 local chosen
 for _,r in ipairs(current.materials or {}) do
  if (key=="LEATHERWORKING"and skinItems[r.itemID]or key=="ALCHEMY"and self:IsHerbalismMaterial(r.itemID)or (key=="BLACKSMITHING"or key=="ENGINEERING")and self:IsMiningMaterial(r.itemID))and type(r.required)=="number"then
   local candidate=key=="LEATHERWORKING"and self:SelectSkinningSupply(r.itemID,r.perCraft or r.quantity or r.required,plan.strategy)or key=="ALCHEMY"and self:SelectHerbalismSupply(r.itemID,r.perCraft or r.quantity or r.required,plan.strategy,key)or self:SelectMiningSupply(r.itemID,r.perCraft or r.quantity or r.required,plan.strategy,key)
   if candidate and candidate.status~="BAGS_READY" then chosen=candidate;break end
  end
 end
 if not chosen then return plan end
 current.materialSupply=chosen;plan.materialSupply=chosen
 if key~="LEATHERWORKING"then
  current.nextAction=chosen.nextAction;plan.action=chosen.nextAction;plan.actionKind=chosen.status=="SMELT"and "smelt"or "acquire"
  if publish and shared and shared.SelectSupplyGoal then shared:SelectSupplyGoal(chosen,{profession=key,recipeID=current.recipeID})end
  return plan
 end
 local action=chosen.status=="SKINNING" and "Visit the qualified Skinning reference; verify a fully looted skinnable target and skin manually" or
  chosen.status=="BANK" and "Withdraw the observed bank material; verify current stock" or
  chosen.status=="AUCTION" and "Recheck the quoted material offer at the Auction House; buy manually" or
  chosen.status=="UNKNOWN_INVENTORY" and "Observe bags before calculating a material shortage" or
  chosen.status=="VERIFY_BANK" and "Verify bank stock before gathering or buying" or
  chosen.reason=="SKINNING_NOT_OBSERVED" and "Skinning ownership is not observed; verify profession or arrange manual trade" or
  chosen.reason=="TOOL_UNKNOWN" and "Observe a Skinning Knife in bags or choose another supply method" or
  chosen.reason=="SKINNING_KNIFE_REQUIRED" and "Obtain/withdraw a Skinning Knife before gathering, or arrange manual trade" or
  "Verify a Skinning material source or arrange manual trade; no qualified stop is known"
 current.nextAction=action.." [item "..chosen.itemID..(chosen.quantity and ", remaining "..chosen.quantity or ", quantity UNKNOWN").."]. Replan after observed inventory."
 plan.action=current.nextAction;plan.actionKind="acquire"
 if publish and shared and shared.SelectSupplyGoal then shared:SelectSupplyGoal(chosen,{profession=key,recipeID=current.recipeID}) end
 return plan
end
function Bridge:ReadPlannerNeeds()
 local planner=JLP:GetModule("AcquisitionPlanner")
 if not planner or type(planner.BuildSelected)~="function" then return {},0,"PLANNER_UNAVAILABLE" end
 local ok,plan=pcall(planner.BuildSelected,planner)
 if not ok or type(plan)~="table" or type(plan.requirements)~="table" then
  return {},0,"PLAN_REQUIREMENTS_UNAVAILABLE" end
 for _,action in ipairs(plan.actions or {})do
  local s=action.supply
  if s and s.professionKey=="MINING"and s.production and s.status=="MINING"then
   local needs,total={},0
   for id,n in pairs(s.production.requirements or {})do if n>0 then needs[id]=n;total=total+n end end
   return needs,total,"CURRENT_SUPPLY_RAW_ALTERNATIVE_NOT_ADDITIVE_PURCHASE"
  end
 end
 local needs,total=self:FromRequirements(plan.requirements)
 return needs,total,"PLANNER_CURRENT_SCOPE"
end
-- Cloth is ordinary kill-loot, not a gathering profession or a gathering cast.
local clothIDs={[2589]=true,[2592]=true,[4306]=true,[4338]=true,[14047]=true}
function Bridge:IsClothMaterial(id)return clothIDs[id]==true end
function Bridge:GetClothWaypoint(itemID,sourceID)
 local root=JLP.data and JLP.data.materialAcquisitionSources
 for _,r in ipairs(root and root.clothSupplies or {})do
  local has=false;for _,id in ipairs(r.itemIDs)do if id==itemID then has=true end end
  if has and r.id==sourceID and r.sourceQualifiedForAdvisory==true then
   return {serviceID=r.id,kind="drop",profession="CLOTH",material=tostring(itemID),materialItemID=itemID,
    npcID=r.npcID,name=r.name.." (historical cloth reference; verify)",zone=r.zone,
    sourceQualified=true,state="SOURCE_QUALIFIED",ownerAuthority="CANONICAL_CLOTH_SOURCE_HISTORICAL_GEOGRAPHY_NOT_CURRENT_LOOT",
    sourceURL=r.relationURL,positionURL=r.positionURL,relationEvidence=r.relationEvidence,positionEvidence=r.positionEvidence,
    scope="STATIC_HISTORICAL_CLOTH_REFERENCE",notLiveSpawn=true,notGuaranteedLoot=true,nativeDispatchAllowed=false,
    nav={mapID=r.mapID,x=r.x,y=r.y,mapDomain="UI_MAP_ID",evidence=r.mapBinding}}
  end
 end
end
function Bridge:SelectClothSupply(itemID,required,strategy,consumer)
 if not clothIDs[itemID]or type(required)~="number"or required<=0 or required~=math.floor(required)or required==math.huge then return nil end
 local result={professionKey="CLOTH",consumerProfession=consumer or "FIRST_AID",itemID=itemID,required=required,
  strategy=strategy or "economical",status="UNKNOWN_INVENTORY",readOnly=true,nativeDispatchAllowed=false}
 local inventory=JLP:GetModule("Inventory");local stock=inventory and inventory:GetOwned(itemID)or {}
 local valid=stock.bagKnown==true and type(stock.bags)=="number"and stock.bags>=0 and stock.bags<math.huge and stock.bags==math.floor(stock.bags)
 if valid then
  result.quantity=math.max(0,required-stock.bags)
  if result.quantity==0 then result.status="BAGS_READY"
  elseif stock.bankKnown~=true then result.status="VERIFY_BANK"
  elseif type(stock.bank)=="number"and stock.bank>0 and stock.bank<math.huge and stock.bank==math.floor(stock.bank)then
   result.status="BANK";result.actionQuantity=math.min(result.quantity,stock.bank)
  elseif stock.bank~=0 then result.status="VERIFY_BANK"
  else
   local quote=qualifiedQuote(itemID,result.quantity);local root=JLP.data and JLP.data.materialAcquisitionSources
   local map=JLP:GetModule("ForeverFishingMapCanvas");local current=map and map:GetCurrentZone();local candidates={}
   for _,r in ipairs(root and root.clothSupplies or {})do
    local source=self:GetClothWaypoint(itemID,r.id)
    if source and not(self.unavailable and self.unavailable[r.id])then candidates[#candidates+1]=source end
   end
   table.sort(candidates,function(a,b)
    local al=current and current.mapID==a.nav.mapID;local bl=current and current.mapID==b.nav.mapID
    if al~=bl then return al==true end;return a.serviceID<b.serviceID
   end)
   if strategy=="fastest"and quote then result.status="AUCTION";result.auctionQuote=quote;result.selectionReason="QUALIFIED_PURCHASE_QUOTE_TOTAL_TIME_UNKNOWN"
   elseif candidates[1]then
    result.status="CLOTH_LOOT";result.source=candidates[1];result.sourceID=result.source.serviceID;result.mapID=result.source.nav.mapID
    result.scope="STATIC_HISTORICAL_CLOTH_REFERENCE";result.selectionReason="LOCAL_FIRST_DETERMINISTIC_REFERENCE_NOT_GLOBAL_OPTIMUM"
   elseif quote and strategy~="self_found"then result.status="AUCTION";result.auctionQuote=quote
   else result.status="MANUAL_TRADE_OR_VERIFY_SOURCE"end
  end
 end
 local name=(JLP:GetModule("MaterialCatalog")and JLP:GetModule("MaterialCatalog"):GetName(itemID))or("item "..itemID)
 result.nextAction=result.status=="BAGS_READY"and "Cloth observed in bags; return to First Aid and replan the next manual craft."or
  result.status=="UNKNOWN_INVENTORY"and "Inspect current bags; cloth quantity is UNKNOWN, not a definite shortage."or
  result.status=="VERIFY_BANK"and "Verify bank stock before farming, buying or trading cloth; bags alone do not establish external demand."or
  result.status=="BANK"and ("Withdraw "..result.actionQuantity.." observed bank "..name.." manually; observe bags before a First Aid craft.")or
  result.status=="CLOTH_LOOT"and ("Visit "..result.source.name.." in "..result.source.zone.."; verify current spawn and safe manual combat/loot for "..name..". Remaining next-cast need "..result.quantity..". Historical geography/drop references do not guarantee loot or a physical route. No gathering profession/cast/tool is required; bags update separately.")or
  result.status=="AUCTION"and "Recheck the qualified cloth quote/offer and funds at the Auction House; buy manually and observe delivery. Total travel time is UNKNOWN."or
  "Arrange manual cloth trade/external delivery or verify another qualified source; no existing offer or price is assumed. Observe bags before crafting."
 return result
end
function Bridge:ApplyClothToPlan(key,plan,context)
 local c=plan.recommendedCurrentStep;local publish=self:CanPublishSupply(key,context);local shared=JLP:GetModule("GatheringSharedMapState")
 if not c or c.kind~="craft"or c.learned~=true then
  if publish and c and (c.kind=="train"or c.kind=="complete")and shared then shared:ClearAutomaticSupplyGoal(key,"OWNER_PREREQUISITE_CHANGED")end
  return plan
 end
 if publish and shared then shared:ClearAutomaticSupplyGoal(key,"OWNER_PLAN_REQUALIFIED")end
 -- An unknown output or bag count does not invalidate independently qualified inputs.
 local req=c.firstAidPrerequisites or {}
 if c.bagReady==true or c.manualCraftBlockedBySourceConflict or
    c.reagentEvidence=="CONFLICT_CURRENT_SCHEMATIC_VS_DB2_70532" or
    (req.focusID or 0)>0 or (req.cooldownMilliseconds or 0)>0 then return plan end
 for _,r in ipairs(c.materials or {})do
  if clothIDs[r.itemID]then
   local supply=self:SelectClothSupply(r.itemID,r.perCraft or r.quantity,plan.strategy,key)
   if supply and supply.status~="BAGS_READY"then
    c.materialSupply=supply;plan.materialSupply=supply;c.nextAction=supply.nextAction;plan.action=c.nextAction
    plan.actionKind=supply.status=="UNKNOWN_INVENTORY"and "verify"or "acquire"
    if publish and shared then shared:SelectSupplyGoal(supply,{profession=key,recipeID=c.recipeID})end
    break
   end
  end
 end
 return plan
end
-- Passive, precisely attributed kill-loot history only. Never modifies Inventory.
function Bridge:ObserveClothLoot()
 local map=JLP:GetModule("ForeverFishingMapCanvas");local zone=map and map:GetCurrentZone()
 if not zone or not zone.playerPosition then return end
 if type(IsInInstance)=="function"then local ok,inside=pcall(IsInInstance);if not ok or inside then return end end
 local function public(v)return not(type(issecretvalue)=="function"and issecretvalue(v))end
 local ok,count=pcall(function()return GetNumLootItems()end)
 if not ok or not public(count)or type(count)~="number"or count<0 or count>100 then return end
 local store=JLP:GetModule("GatheringObservationStore");local bucket=store and store:GetBucket();if not bucket then return end
 bucket.clothLoot=type(bucket.clothLoot)=="table"and bucket.clothLoot or {}
 for slot=1,count do
  local good,link=pcall(function()return GetLootSlotLink(slot)end)
  local id=good and public(link)and type(link)=="string"and tonumber(link:match('item:(%d+)'))
  if clothIDs[id]then
   local sources={pcall(function()return GetLootSourceInfo(slot)end)}
   if sources[1]==true and #sources==3 then
    local guid,n=sources[2],sources[3]
    local npc=public(guid)and type(guid)=="string"and tonumber(guid:match('^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-'))
    if npc and public(n)and type(n)=="number"and n>0 and n==math.floor(n)and n<10000 then
     local identity=guid..":"..id;local duplicate=false
     for _,r in ipairs(bucket.clothLoot)do if r.identity==identity then duplicate=true end end
     if not duplicate then
      bucket.clothLoot[#bucket.clothLoot+1]={identity=identity,npcID=npc,itemID=id,quantity=n,mapID=zone.mapID,x=zone.playerPosition.x,y=zone.playerPosition.y,
       evidence="EXACT_CREATURE_GUID_SLOT_LOOT_NOT_BAG_OR_SKILL_RECEIPT",observedAt=type(time)=="function"and time()or nil}
      if #bucket.clothLoot>240 then table.remove(bucket.clothLoot,1)end
      bucket.revision=(bucket.revision or 0)+1
     end
    end
   end
  end
 end
end

-- A fish ID remains a raw item, not its cooked meal or derived oil.
function Bridge:IsFishingMaterial(id)
 local root=JLP.data and JLP.data.fishingCatchAreaReference
 for _,rows in pairs(root and root.maps or {})do for _,r in ipairs(rows)do if r.itemID==id then return true end end end
 return false
end
function Bridge:SelectFishingSupply(itemID,required,strategy,consumer)
 if not self:IsFishingMaterial(itemID)or type(required)~="number"or required<=0 or required~=math.floor(required)or required==math.huge then return nil end
 local r={professionKey="FISHING",consumerProfession=consumer,itemID=itemID,required=required,strategy=strategy or "economical",status="UNKNOWN_INVENTORY",readOnly=true,nativeDispatchAllowed=false}
 local inv=JLP:GetModule("Inventory");local stock=inv and inv:GetOwned(itemID)or {}
 local function count(n)return type(n)=="number"and n>=0 and n<math.huge and n==math.floor(n)end
 if stock.bagKnown==true and count(stock.bags)then
  r.quantity=math.max(0,required-stock.bags)
  if r.quantity==0 then r.status="BAGS_READY"
  elseif stock.bankKnown~=true or not count(stock.bank)or stock.bankStale then r.status="VERIFY_BANK"
  elseif stock.bank>0 then r.status="BANK";r.actionQuantity=math.min(r.quantity,stock.bank)
  else
   local api=JLP:GetModule("ProfessionAPI");local p=api and api:Get("FISHING")
   local ctx=JLP:GetModule("FishingSkillContext");local observation=ctx and p and ctx:FromSnapshot(p)
   local map=JLP:GetModule("ForeverFishingMapCanvas");local current=map and map:GetCurrentZone()
   local model=JLP:GetModule("ForeverFishingZoneModel");local data=JLP.data and JLP.data.fishingCatchAreaReference;local areas={}
   local secondary=JLP:GetModule("SecondaryLevelingPlanner");local maps={}
   for mapID,rows in pairs(data and data.maps or {})do maps[mapID]={};for _,row in ipairs(rows)do maps[mapID][#maps[mapID]+1]=row end end
   for _,row in ipairs(secondary and secondary.GetFishingSpeciesZones and secondary:GetFishingSpeciesZones(itemID)or {})do
    maps[row.mapID]=maps[row.mapID]or {};maps[row.mapID][#maps[row.mapID]+1]=row
   end
   if p and not p.cached and count(p.skill)then
    for mapID,rows in pairs(maps)do
     local has=false;local species;for _,fish in ipairs(rows)do if fish.itemID==itemID and (type(fish.sampleCount)=="number"and fish.sampleCount>0 and type(fish.cells)=="string"and fish.cells~=""or fish.zoneRelationQualified==true and type(fish.zoneRelationURL)=="string"and fish.geometryType=="NAMED_ZONE_AREA")then has=true;species=fish end end
     local ref=has and model and model:LookupMap(mapID,p.skill,observation and observation.observedBonus or 0)
     if ref and ref.selected and ref.selected.meetsMinimum then areas[#areas+1]={mapID=mapID,name=species.documentedArea or ref.selected.name,zone=ref.selected.name,minimum=ref.selected.minSkill,sourceURL=species.zoneRelationURL,evidence=species.zoneRelationEvidence or "HISTORICAL_GRID_AREA",
      approach=secondary and secondary:GetFishingApproach(mapID,itemID,nil,required,consumer)}end
    end
   end
   table.sort(areas,function(a,b)
    local al=current and a.mapID==current.mapID;local bl=current and b.mapID==current.mapID
    if al~=bl then return al==true end
    if (a.approach~=nil)~=(b.approach~=nil)then return a.approach~=nil end
    return a.mapID<b.mapID
   end)
   local quote=qualifiedQuote(itemID,r.quantity)
   local acquisition=JLP:GetModule("AcquisitionPlanner")
   local service=acquisition and acquisition:SelectMaterialService(consumer,itemID,required)
   local offered=service and service.offer and service.offer.status=="AVAILABLE"and service.purchase and
    (service.purchase.status=="READY_MANUAL_PURCHASE"or service.purchase.status=="VERIFY_LIMITED_STOCK")
   local vendorPreferred=offered and (strategy=="fastest"or strategy=="self_found"and not areas[1]or strategy=="economical"and (not quote or service.purchase.totalCopper<=quote.cost))
   if vendorPreferred then
    r.status="VENDOR";r.source=service.source;r.service=service;r.sourceID=service.sourceID;r.mapID=r.source.nav.mapID
    r.selectionReason="EXACT_CURRENT_VENDOR_OFFER_NOT_GUARANTEED_STOCK_OR_GLOBAL_FISHING_COST"
   elseif quote and strategy=="economical"then r.status="AUCTION";r.auctionQuote=quote;r.selectionReason="QUALIFIED_PURCHASE_QUOTE_FISHING_TIME_UNKNOWN"
   elseif areas[1]then
    r.status="FISHING_AREA";r.area=areas[1];r.mapID=r.area.mapID;r.scope="STATIC_HISTORICAL_FISHING_AREA_NOT_POOL"
    if r.area.approach and r.area.approach.zoneApproach then r.scope="QUALIFIED_ZONE_APPROACH_NOT_SPECIES_PIN"end
    r.sourceID="FISH_AREA_"..r.mapID.."_"..itemID;r.source={serviceID=r.sourceID,name=r.area.name,kind="fishing_area",geometryType="GRID_AREA",mapID=r.mapID,materialItemID=itemID,profession="FISHING",nativeDispatchAllowed=false}
    r.fishingContext=observation;r.selectionReason="LOCAL_FIRST_ELIGIBLE_AREA_NOT_CATCH_RATE_OR_GLOBAL_OPTIMUM"
   elseif quote and strategy~="self_found"then r.status="AUCTION";r.auctionQuote=quote
   else r.status="MANUAL_TRADE_OR_VERIFY_SOURCE";r.reason=p and "QUALIFIED_ELIGIBLE_FISH_AREA_UNAVAILABLE"or "FISHING_NOT_OBSERVED"end
  end
 end
 local secondary=JLP:GetModule("SecondaryLevelingPlanner")
 local approach=r.status=="FISHING_AREA"and secondary and secondary:GetFishingApproach(r.mapID,itemID,nil,required,consumer)
 local approachText=approach and (" Use the qualified approach at "..approach.name.."; it is not a pool/cast point or a safe transport guarantee. Inspect the water locally.")or " Safe standing-point/pool coordinates are unqualified; no fake waypoint."
 local label="item "..itemID
 r.nextAction=r.status=="BAGS_READY"and ("Required fish observed in bags; return to "..tostring(consumer or "the consumer").." and replan. No new Fishing skill order.")or
  r.status=="BANK"and ("Withdraw "..r.actionQuantity.." observed bank "..label.." manually; observe bags before consumer crafting. Fishing rank/gear is irrelevant to withdrawal.")or
  r.status=="UNKNOWN_INVENTORY"and "Observe fish inventory; UNKNOWN is not a definite shortage."or
  r.status=="VERIFY_BANK"and "Verify bank stock before fishing/buying/trading; unknown bank is not empty."or
  r.status=="FISHING_AREA"and ("Gather "..r.quantity.." remaining "..label.." by manual Fishing in "..r.area.name..". Historical area guidance requires no personal history; current catches/amounts are not guaranteed. "..approachText.." Observe loot, bags and skill separately.")or
  r.status=="VENDOR"and ("Inspect/buy the exact current fish offer manually at "..r.source.name..". Verify limited stock and purchase units; availability is not guaranteed delivery. Observe bags separately.")or
  r.status=="AUCTION"and "Recheck the qualified fish quote, funds and actual offer; purchase manually and observe delivery. Fishing time/expected catches remain UNKNOWN."or
  "Arrange manual fish trade/delivery or verify an eligible source. No Fishing ownership, rank, active offer, price or catch is assumed."
 return r
end
function Bridge:ApplyFishingToPlan(key,plan,context)
 local c=plan and plan.recommendedCurrentStep;if not c or c.kind~="craft"or c.learned~=true then return plan end
 if c.manualCraftBlockedBySourceConflict or c.reagentEvidence=="CONFLICT_CURRENT_SCHEMATIC_VS_DB2_70532"then return plan end
 local publish=self:CanPublishSupply(key,context);local shared=JLP:GetModule("GatheringSharedMapState")
 for _,mat in ipairs(c.materials or {})do
  if self:IsFishingMaterial(mat.itemID)then
   local s=self:SelectFishingSupply(mat.itemID,mat.perCraft or mat.quantity,plan.strategy,key)
   if s and s.status~="BAGS_READY"then
    c.materialSupply=s;plan.materialSupply=s;c.nextAction=s.nextAction;plan.action=s.nextAction
    c.requiredNextAction=s.status=="UNKNOWN_INVENTORY"and "verify"or "acquire";plan.actionKind=c.requiredNextAction
    if publish and shared then shared:SelectSupplyGoal(s,{profession=key,recipeID=c.recipeID})end
    local travel=JLP:GetModule("CurrentStepTravelBridge");if travel then travel:Attach(key,c)end
    break
   end
  end
 end
 return plan
end

JLP:RegisterModule("GatheringMaterialBridge",Bridge)
