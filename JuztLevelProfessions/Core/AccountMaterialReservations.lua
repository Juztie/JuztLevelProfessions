local _, JLP = ...
-- Account inventory is historical advisory evidence. Planning reservations are
-- local to this calculation; nothing here mutates SavedVariables, authorises a
-- bank transfer, changes a destination, or grants native crafting permission.
local M={contract="JLP-ACCOUNT-MATERIAL-RESERVATIONS-199",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local floor,min,max=math.floor,math.min,math.max
local function uint(x,positive)
 if type(x)~="number" or x~=x or x==math.huge or x==-math.huge or
    x~=floor(x) or x< (positive and 1 or 0) or x>9007199254740991 then return nil end
 return x
end
local function canonical(key,aliases)
 if type(key)~="string" or key=="" then return nil end
 local value=type(aliases)=="table" and aliases[key] or nil
 if type(value)=="string" and value~="" then return value end
 return key
end
local function sourceRows(options)
 if type(options.characters)=="table" then return options.characters,"EXPLICIT_SCENARIO" end
 local root=JLP.DB and JLP.DB.account and JLP.DB.account.inventory
 return (root and root.characters) or {},"SAVED_ACCOUNT_INVENTORY"
end
local function identity(options)
 local ci=JLP:GetModule("CharacterIdentity")
 local current=ci and ci.GetCurrent and ci:GetCurrent() or {}
 local unitFaction=nil
 if type(UnitFactionGroup)=="function" then
  local ok,f=pcall(UnitFactionGroup,"player")
  if ok and (f=="Alliance" or f=="Horde") then unitFaction=f end
 end
 return options.currentKey or current.key,options.currentRealm or current.realm,
     options.currentFaction or unitFaction
end
local function validSnapshot(snapshot)
 if type(snapshot)~="table" or snapshot.known~=true or
     type(snapshot.items)~="table" or not uint(snapshot.updatedAt,true) then return false end
 for id,n in pairs(snapshot.items) do
  if not uint(id,true) or not uint(n,false) then return false end
 end
 return true
end
local function candidateStock(snapshot,itemID)
 if not validSnapshot(snapshot) then return nil end
 return snapshot.items[itemID] or 0
end
local function normalizedRealm(realm)
 if type(realm)~="string" or realm=="" or realm=="UnknownRealm" then return nil end
 return realm:lower():gsub("[%s%-']","")
end
local function normalizeOffers(options,knownOwners)
 local result={}
 local curated=JLP.data and JLP.data.foreverIntermediateOutputs
 local yields=JLP.data and JLP.data.recipeOutputYields
 local known={}
 for _,r in ipairs(curated and curated.rows or {}) do
  if uint(r.recipeID,true) and uint(r.outputItemID,true) and uint(r.outputQuantity,true) then
   known[tostring(r.professionKey)..":"..r.recipeID]=r
  end
 end
 local pinned={}
 for _,r in pairs(yields and yields.recipes or {}) do
  if r.fixed==true and r.externalVerified==true and
       r.dependencyQuantityEligible==true and uint(r.spellID,true) and
       uint(r.outputQuantity,true) then pinned[r.spellID]=r.outputQuantity end
 end
 for _,c in ipairs(type(options.producerCandidates)=="table" and options.producerCandidates or {}) do
  if type(c)=="table" then
   local owner=knownOwners[canonical(c.characterKey,options.aliases)]
   local row=known[tostring(c.professionKey)..":"..tostring(c.recipeID)]
   local proofAllowed=true
   if row and row.requiresPrimarySourceParity then
    -- A cached alternate-character recipe is still only a conditional lead.
    -- New primary source rows require the same exact provenance/reagent join
    -- as the local dependency graph, not just matching spell+yield integers.
    local graph=JLP:GetModule("CrossProfessionDependencyPlanner")
    local exact=graph and graph.Resolve and graph:Resolve(c.professionKey,c.recipeID)
    proofAllowed=exact and exact.primarySourceParity=="EXACT_SPELL_OUTPUT_REAGENTS_NAME" or false
   end
   local evidence=JLP:GetModule("RecipeOutputEvidence")
   local ref=evidence and evidence.GetReference and evidence:GetReference(nil,c.recipeID)
   if ref and ref.productFixedOutput then
    proofAllowed=proofAllowed and evidence:Resolve(nil,c.recipeID).planningUsable
   end
   if owner and owner.identityQualified and row and proofAllowed and
       pinned[c.recipeID]==row.outputQuantity then
    result[#result+1]={characterKey=owner.key,professionKey=c.professionKey,
     recipeID=c.recipeID,outputItemID=row.outputItemID,
     outputPerCraft=row.outputQuantity,
     learnedState=c.learned==true and "HISTORICAL_OR_SCENARIO_NOT_LIVE" or "UNKNOWN",
     materialRequirementsVerified=false,
     status="VERIFY_OWNER_RECIPE_MATERIALS_AND_YIELD_BEFORE_CRAFT",
     generatedStock=0,readOnly=true,nativeDispatchAllowed=false}
   end
  end
 end
 table.sort(result,function(a,b)
  if a.characterKey~=b.characterKey then return a.characterKey<b.characterKey end
  return a.recipeID<b.recipeID
 end)
 return result
end
function M:Plan(requests,options)
 options=type(options)=="table" and options or {}
 local account=JLP.DB and JLP.DB.account or {}
 local identityRoot=account and account.characterIdentity or {}
 local aliases=options.aliases or identityRoot.aliases or {}
 -- Caller-supplied aliases are test/advisory inputs, never an authority.
 local rows,origin=sourceRows(options)
 local currentKey,currentRealm,currentFaction=identity(options)
 currentKey=canonical(currentKey,aliases)
 local realm=normalizedRealm(currentRealm)
 local owners={}
 for rawKey,c in pairs(rows) do
  local key=canonical(rawKey,aliases)
  if key and key~=currentKey and type(c)=="table" then
   local meta=c.meta or {}
   local observedRealm=normalizedRealm(meta.realm)
   local owner=owners[key] or {key=key,meta=meta,bags={},bank={}}
   local old=owner.meta or {}
   if owners[key] and (old.realm~=meta.realm or old.faction~=meta.faction) then
    owner.conflictingIdentity=true
   end
   local function register(slot,snapshot)
    if validSnapshot(snapshot) and
       (not validSnapshot(owner[slot]) or snapshot.updatedAt>owner[slot].updatedAt) then
       owner[slot]=snapshot
    end
   end
   register("bags",c.bags);register("bank",c.bank)
   if not owners[key] or (meta.guid and not owner.meta.guid) then owner.meta=meta end
   owner.identityQualified=not owner.conflictingIdentity and realm~=nil and
      normalizedRealm(owner.meta.realm)==realm and observedRealm==realm and
      currentFaction~=nil and owner.meta.faction==currentFaction and meta.faction==currentFaction
   owner.sameRealm=realm~=nil and observedRealm==realm
   owner.sameFaction=currentFaction~=nil and meta.faction==currentFaction
   owners[key]=owner
  end
 end
 local normalized={};local rejected=0
 for _,r in ipairs(type(requests)=="table" and requests or {}) do
  local itemID=type(r)=="table" and uint(r.itemID,true)
  local qty=type(r)=="table" and uint(r.provisionalAcquireQuantity or r.quantity,true)
  if itemID and qty and uint((normalized[itemID] or 0)+qty,true) then
   normalized[itemID]=(normalized[itemID] or 0)+qty
  else rejected=rejected+1 end
 end
 local out={}
 for itemID,wanted in pairs(normalized) do
  local remaining=wanted;local available={}
  local reservationBalance={}
  for key,owner in pairs(owners) do
   for _,slot in ipairs({"bags","bank"}) do
    local observed=candidateStock(owner[slot],itemID)
    if observed and observed>0 then
     local reserved=options.existingReservations and options.existingReservations[key] and
       options.existingReservations[key][itemID]
     if reservationBalance[key]==nil then reservationBalance[key]=uint(reserved,false) or 0 end
     local reservedCount=min(observed,reservationBalance[key])
     reservationBalance[key]=reservationBalance[key]-reservedCount
     local free=max(0,observed-reservedCount)
     available[#available+1]={characterKey=key,location=slot,observed=observed,
       previouslyReserved=reservedCount,uncommitted=free,
       snapshotAt=owner[slot].updatedAt,
       transferEligible=owner.identityQualified==true,
       status=owner.identityQualified and "CACHED_TRANSFER_REQUIRES_CHARACTER_LOGIN" or
         "REALM_OR_FACTION_NOT_VERIFIED",source="SAVED_SNAPSHOT_NOT_LIVE"}
    end
   end
  end
  table.sort(available,function(a,b)
   if a.transferEligible~=b.transferEligible then return a.transferEligible end
   if a.characterKey~=b.characterKey then return a.characterKey<b.characterKey end
   return a.location<b.location
  end)
  local holds={};local referenceOnly=0
  for _,s in ipairs(available) do
   if s.transferEligible then
    local allocate=min(remaining,s.uncommitted)
    if allocate>0 then
     holds[#holds+1]={characterKey=s.characterKey,location=s.location,
       itemID=itemID,quantity=allocate,status=s.status,
       snapshotAt=s.snapshotAt,readOnly=true}
     remaining=remaining-allocate
    end
   else referenceOnly=referenceOnly+s.uncommitted end
  end
  out[#out+1]={itemID=itemID,requested=wanted,
   conditionalTransferUnits=wanted-remaining,
   remainingIfTransfersVerified=remaining,
   observedButIneligibleUnits=referenceOnly,
   holds=holds,observations=available,
   confirmedShortage=nil,readOnly=true,
   transferReceiptRequired=true}
 end
 table.sort(out,function(a,b)return a.itemID<b.itemID end)
 local dependencyPlanner=JLP:GetModule("CrossProfessionDependencyPlanner")
 local dependencyBlueprint=dependencyPlanner and dependencyPlanner.Plan and
  dependencyPlanner:Plan(requests,options) or nil
 return {contract=self.contract,inventorySource=origin,rows=out,
  dependencyBlueprint=dependencyBlueprint,
  accountProductionOffers=normalizeOffers(options,owners),
  invalidRequests=rejected,provisionalOnly=true,
  stockAvailableForCurrentCraft=0,
  requiresCharacterSwitchAndFreshInventory=true,
  reason="SAVED_ALT_INVENTORY_IS_NOT_LIVE_OR_TRANSFERRED",
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  replanAfter={"ALT_CHARACTER_LOGIN","TRANSFER_RECEIPT","BAG_SNAPSHOT_CHANGE",
   "BANK_SNAPSHOT_CHANGE","RECIPE_LEARNED","VERIFIED_CRAFT_RECEIPT"}}
end
JLP:RegisterModule("AccountMaterialReservations",M)
