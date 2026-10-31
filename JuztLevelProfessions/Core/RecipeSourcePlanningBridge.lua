local _, JLP = ...
-- Read-only bridge between the *exact* DB70450 recipe/teaching-item links,
-- existing actor research and Current Step. Historical source build is data
-- provenance, never a client allowlist. This module does not grant vendor
-- access, learned status, native crafting or navigable coordinates.
local M={contract="JLP-RECIPE-SOURCE-PLANNING-190",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local SOURCE_BUILD=70450
local kinds={vendor=true,trainer=true,drop=true,quest=true,npc=true}
-- Bounded lookup over the independently curated pattern/formula/recipe research.
-- Never join by a fuzzy spell name: a DB item-to-spell teaching link is mandatory.
local legacyIndex,legacyRoot=nil,nil
local function legacyByItem()
 local root=JLP.data and JLP.data.recipeAccessSources
 if root==legacyRoot and legacyIndex then return legacyIndex end
 local idx={}
 if type(root)=="table" and root.contract==nil and type(root.requirements)=="table" then
  for _,reference in pairs(root.requirements) do
   if type(reference)=="table" and type(reference.itemID)=="number" and
       reference.itemID==math.floor(reference.itemID) and reference.itemID>0 and
       reference.conflict~=true then
    local entries=idx[reference.itemID] or {}
    entries[#entries+1]=reference
    idx[reference.itemID]=entries
   end
  end
 elseif type(root)=="table" and type(root.requirements)=="table" then
  -- Retain the exact same admission policy for versioned research roots.
  for _,reference in pairs(root.requirements) do
   local id=reference and reference.itemID
   if type(id)=="number" and id>0 and id==math.floor(id) and
      reference.conflict~=true then
    idx[id]=idx[id] or {};idx[id][#idx[id]+1]=reference
   end
  end
 end
 legacyRoot,legacyIndex=root,idx
 return idx
end
local function legacySourceMode(kind)
 return (kind=="vendor" or kind=="drop" or kind=="quest" or kind=="trainer") and kind or nil
end
local function positive(v)
 return type(v)=="number" and v>0 and v==math.floor(v) and v<2147483647
end
local function validText(v)
 return type(v)=="string" and v~="" and #v<=220
end
local function copyLead(row)
 return {kind=row.sourceType,npcName=row.npcName,npcID=row.npcID,
  questID=row.questID,teachingItemID=row.teachingItemID,
  zone=row.zone,faction=row.factionReference or row.documentedVendorFaction,
  referenceURL=row.externalReference or row.referenceURL or row.itemReferenceURL,
  researchOrigin=row.researchOrigin or "DB70450_EXACT_ACTOR",
  evidenceTier=row.evidenceTier,conflicted=row.conflicted==true,
  sourceVerifiedLive=false,navigationQualified=false,readOnly=true,
  guideSkillRequired=row.guideSkillRequired,merchantFavorCost=row.merchantFavorCost,
  sourceJoinStrength=row.sourceJoinStrength or "EXACT_TEACHING_ITEM",
  questCompletionVerified=false,actualVendorStock="UNKNOWN",
  nativeDispatchAllowed=false}
end
local function accessible(row,characterFaction)
 local f=row.factionReference or row.documentedVendorFaction
 if f=="Alliance" or f=="Horde" then
  return characterFaction==nil or f==characterFaction
 end
 return true
end
local function unitFaction()
 if type(UnitFactionGroup)~="function" then return nil end
 local ok,f=pcall(UnitFactionGroup,"player")
 return ok and (f=="Alliance" or f=="Horde") and f or nil
end
-- A bounded extension of the existing exact teaching-item/source bridge.
-- User-facing acquisition is conditional; all purchases/learning remain manual.
function M:GetTrainerAcquisition(key,spellID)
 local facts=JLP:GetModule("ProfessionPlanningFacts")
 local f=facts and (key=="LEATHERWORKING" and facts:GetLeatherworkingContract(spellID) or key=="ENGINEERING" and facts:GetEngineeringContract(spellID) or key=="BLACKSMITHING" and facts.GetBlacksmithingContract and facts:GetBlacksmithingContract(spellID))
 if not f or not f.requiresTrainerOfferingObservation then return nil end
 local evidence=JLP:GetModule("RecipeAccessEvidence")
 local result={status="UNKNOWN",recipeID=spellID,minimum=f.learningMinimum,candidates={},availabilityRank=0,readOnly=true,nativeDispatchAllowed=false}
 for _,lead in ipairs(f.trainerReferences or {})do
  if accessible({factionReference=lead.faction},unitFaction())then
   local current=evidence and evidence.GetTrainerPlanningHint and evidence:GetTrainerPlanningHint(spellID,lead.npcID)or {status="UNKNOWN"}
   local rank=current.status=="AVAILABLE" and 4 or (current.status=="NOT_OFFERED" or current.status=="INELIGIBLE")and -1 or 3
   local candidate={npcID=lead.npcID,npcName=lead.npc,zone=lead.zone,referenceURL=lead.referenceURL,
    evidence=lead.evidence,current=current,availabilityRank=rank,readOnly=true}
   result.candidates[#result.candidates+1]=candidate
   if not result.primary or rank>result.availabilityRank then result.primary=candidate;result.availabilityRank=rank;result.status=current.status end
  end
 end
 return result
end
function M:GetPatternAcquisition(key,spellID,skill)
 if key~="TAILORING" and key~="ENCHANTING" and key~="ALCHEMY" and key~="BLACKSMITHING" and key~="ENGINEERING" and key~="LEATHERWORKING" then return nil end
 local q=JLP:GetModule("TailoringRecipeQualification")
 local f,db
 if key=="TAILORING" and q and q.GetVendorPatternContract then f,db=q:GetVendorPatternContract(JLP.data and JLP.data.tailoring,spellID) end
 if key=="ENCHANTING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  if facts and facts.GetEnchantingContract then f,db=facts:GetEnchantingContract(spellID) end
  if f and not f.recipeItemID then return nil end
 end
 if key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  if facts and facts.GetAlchemyContract then f,db=facts:GetAlchemyContract(spellID,key)end
  if f and not f.recipeItemID then return nil end
 end
 if not f then return nil end
 local root=JLP.data and JLP.data.recipeAccessSources
 local reference
 for _,r in pairs(root and root.requirements or {})do
  if r.professionKey==key and r.recipeID==spellID and r.itemID==db.patternItemID and r.capturedBuild==70532 then
   if reference then return nil end;reference=r
  end
 end
 if not reference and (key=="ENCHANTING" or key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING") and f.vendor then
  reference={itemID=f.recipeItemID,recipeID=spellID,professionKey=key,capturedBuild=70532,sources={}}
  for _,v in ipairs((key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING") and f.vendors or {f.vendor})do
   reference.sources[#reference.sources+1]={sourceType="vendor",npc=v.npc,npcID=v.npcID,zone=v.zone,faction=v.faction,
    referenceEligible=true,acquisitionPlanningQualified=(key~="BLACKSMITHING" and key~="ENGINEERING" and key~="LEATHERWORKING") or v.acquisitionPlanningQualified==true,evidence=v.referenceURL,
    evidenceQuality="FOREVER_GUIDE_PLUS_EXACT_70532_FORMULA_LINK_NOT_LIVE_STOCK",
    accessNote=v.accessNote,accessReferenceURL=v.accessReferenceURL,accessEvidence=v.accessEvidence,
    limitedSupply=v.limitedSupply,documentedStock=v.documentedStock}
  end
 end
 if not reference and (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING") and f.recipeItemID then
  reference={itemID=f.recipeItemID,recipeID=spellID,professionKey=key,capturedBuild=70532,sources={}}
 end
 if not reference then return nil end
 local result={itemID=db.patternItemID,recipeID=spellID,minimum=f.minimum,
  requiredLevel=db.patternRequiredLevel,itemFactionRequirement=db.patternMinFactionID,
  itemReputationRequirement=db.patternMinReputation,patternPossession="UNKNOWN",
  status="VERIFY_SOURCE",availabilityRank=0,candidates={},readOnly=true,nativeDispatchAllowed=false,
  learningReceipt="CURRENT_PROFESSION_OBSERVATION_REQUIRED",navigationQualified=false}
 if key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" then
  result.merchantFavorRequired=f.merchantFavorRequired
  result.reputationReference=f.reputationReference
  result.accessRequirementsStatus=f.acquisitionStatus or "VERIFY_CURRENT_OFFERING"
  result.bindOnPickup=f.patternBonding==1
 end
 local inventory=JLP:GetModule("Inventory")
 local owned=inventory and inventory.GetOwned and inventory:GetOwned(result.itemID)
 local function knownCount(n)return type(n)=="number" and n>=0 and n<math.huge and n==math.floor(n) end
 if owned and owned.bagKnown==true and knownCount(owned.bags) then
  result.observedBagQuantity=owned.bags
  if owned.bags>0 then result.patternPossession="BAGS_OBSERVED"
  elseif owned.bankKnown==true and knownCount(owned.bank) then
   result.observedBankQuantity=owned.bank
   result.patternPossession=owned.bank>0 and "BANK_OBSERVED" or "ABSENT_FROM_BAGS"
  end
 end
 local who=unitFaction()
 local evidence=JLP:GetModule("RecipeAccessEvidence")
 for _,actor in ipairs(reference.sources or {})do
  if actor.sourceType=="vendor" and positive(actor.npcID) and validText(actor.npc) and
      actor.referenceEligible==true and accessible({factionReference=actor.faction},who) then
   local stock=evidence and evidence.GetMerchantPlanningHint and evidence:GetMerchantPlanningHint(result.itemID,actor.npcID) or {status="UNKNOWN"}
   local resolver=JLP:GetModule("SourceResolver")
   local geography=resolver and resolver.GetRecipeVendorWaypoint and
       resolver:GetRecipeVendorWaypoint(key,result.itemID,actor.npcID)
   -- The DB item-to-spell link above is still required. The new exact
   -- item/vendor page witness qualifies only this source field, not learning,
   -- access, stock, or any recipe minimum/difficulty/output field.
   local access=key=="BLACKSMITHING" and actor.npcID==11278 and evidence and evidence.GetVendorAccessPlanningHint and evidence:GetVendorAccessPlanningHint(actor.npcID,stock)
   local qualified=actor.acquisitionPlanningQualified==true or geography~=nil and not geography.accessStatus or access and access.status=="EQUIPPED"
   local rank=qualified and 3 or 0
   if stock.status=="AVAILABLE" then rank=4
   elseif stock.status=="OUT_OF_STOCK" or stock.status=="NOT_OFFERED" or stock.status=="INELIGIBLE" then rank=-1 end
   if stock.status=="UNKNOWN" and stock.recentUnavailable and rank>2 then rank=2 end
   if who~="Horde" and who~="Alliance" then rank=0 end
   local lead={npcID=actor.npcID,npcName=actor.npc,kind="vendor",zone=actor.zone,faction=actor.faction,
    referenceURL=actor.evidence,evidenceTier=actor.evidenceQuality,teachingItemID=result.itemID,
    currentStock=stock.status,availabilityRank=rank,stockObservation=stock,
    limitedSupply=actor.limitedSupply,documentedStock=actor.documentedStock,
    accessNote=geography and geography.accessNote or actor.accessNote,accessReferenceURL=actor.accessReferenceURL,accessEvidence=actor.accessEvidence,
    navigationQualified=geography~=nil,vendorAccess=access,sameMap=geography and geography.sameMap==true,readOnly=true,nativeDispatchAllowed=false}
   result.candidates[#result.candidates+1]=lead
   if not result.primary or rank>result.availabilityRank or rank==result.availabilityRank and
       lead.sameMap==true and result.primary.sameMap~=true then result.primary=lead;result.availabilityRank=rank end
  end
 end
 if key=="LEATHERWORKING" and f.dropResearch and not result.primary then
  local d=f.dropResearch
  result.primary={npcID=d.npcID,npcName=d.npc,zone=d.zone,kind="drop",referenceURL=d.referenceURL,
   availabilityRank=0,teachingItemID=result.itemID,navigationQualified=false,readOnly=true,
   evidenceTier="FOREVER_RELATED_DROP_NOT_CURRENT_LOOT_OR_GUARANTEED_SOURCE"}
  result.candidates[#result.candidates+1]=result.primary
 end
 local lead=result.primary
 if result.observedBagQuantity and result.observedBagQuantity>0 then
  result.status="LEARN_ITEM_MANUALLY";result.availabilityRank=5
 elseif result.patternPossession=="BANK_OBSERVED" then
  result.status="RETRIEVE_PATTERN_FROM_BANK";result.availabilityRank=5
 elseif lead and lead.kind=="drop" then
  result.status="VERIFY_DROP_OR_TRADE_ACCESS"
 elseif lead and lead.vendorAccess and lead.currentStock~="AVAILABLE" and lead.availabilityRank>=0 then
  local access=lead.vendorAccess;result.vendorAccess=access
  result.status=access.status=="BANK" and "RETRIEVE_ACCESS_ITEM_FROM_BANK" or
   access.status=="EQUIP_MANUALLY" and "EQUIP_ACCESS_ITEM_MANUALLY" or
   (access.status=="QUEST_START"or access.status=="QUEST_RETURN")and "VENDOR_ACCESS_QUEST_MANUALLY" or
   access.status=="QUEST_OBJECTIVES"and "VERIFY_DUNGEON_QUEST_OBJECTIVES" or
   access.status=="EQUIPPED"and "VERIFY_VENDOR_STOCK_AND_ACCESS"or "VERIFY_VENDOR_ACCESS_PREREQUISITE"
 elseif lead then
  result.status=lead.currentStock=="AVAILABLE" and "ACQUIRE_ITEM_MANUALLY" or
      lead.availabilityRank<0 and "SOURCE_UNAVAILABLE" or "VERIFY_VENDOR_STOCK_AND_ACCESS"
 end
 if skill and skill<f.minimum then result.status="SKILL_REQUIREMENT_UNMET";result.availabilityRank=-1 end
 if lead and lead.vendorAccess and result.status=="ACQUIRE_ITEM_MANUALLY"and evidence and evidence.GetMerchantPurchaseAdvice then
  result.purchaseAdvice=evidence:GetMerchantPurchaseAdvice(result.itemID,lead.npcID,result.patternPossession=="ABSENT_FROM_BAGS"and 1 or nil)
  local status=result.purchaseAdvice.status
  if status=="INSUFFICIENT_FUNDS"or status=="VERIFY_CURRENCY_REQUIREMENTS"or status=="VERIFY_CHANGED_OFFER"then result.status="VERIFY_PURCHASE_REQUIREMENTS"end
 end
 result.sourceQualifiedForPlanning=lead and lead.availabilityRank>=3 or result.availabilityRank==5
 result.vendorAccess=result.vendorAccess or lead and lead.vendorAccess
 result.accessNote=lead and lead.accessNote
 return result
end
function M:ForRecipe(key,spellID,recipeName,characterFaction)
 local result={contract=self.contract,professionKey=key,recipeID=spellID,
  state="UNKNOWN",reason="EXACT_SOURCE_UNAVAILABLE",sourceBuild=SOURCE_BUILD,
  candidates={},teachingItems={},teachingItemCount=0,sourceCandidateCount=0,
  legacySourceCount=0,publicModeCount=0,
  usableForPlanning=true,sourceQualifiedForNavigation=false,
  learnedStatus="UNKNOWN",readOnly=true,nativeDispatchAllowed=false,
  executionEligible=false,productionAuthority=false}
 if not positive(spellID) or not validText(key) then
  result.reason="INVALID_RECIPE_IDENTITY";return result
 end
 if key=="ENCHANTING" or key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local recipe=facts and ((key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING") and facts.GetAlchemyContract and facts:GetAlchemyContract(spellID,key) or key=="ENCHANTING" and facts:GetEnchantingContract(spellID))
  if recipe and recipe.learning=="automatic" then
   result.state="AUTOMATIC_REFERENCE";result.reason="OBSERVE_PROFESSION_RECIPE_NOT_TRAINER_TRAVEL"
   result.learningMethod="automatic";result.sourceBuild=70532
   result.fieldEvidence={learning=recipe.minimumStatus,learned="UNKNOWN_CURRENT_OBSERVATION_REQUIRED"}
   return result
  end
  if (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING") and recipe and recipe.trainerReferences then
   for _,actor in ipairs(recipe.trainerReferences)do
    if accessible({factionReference=actor.faction},characterFaction or unitFaction())then
     result.candidates[#result.candidates+1]={kind="trainer",npcName=actor.npc,npcID=actor.npcID,
      zone=actor.zone,faction=actor.faction,referenceURL=actor.referenceURL,evidenceTier=actor.evidence,
      sourceJoinStrength="EXACT_FOREVER_NPC_TEACHES_RECIPE",sourceVerifiedLive=false,
      navigationQualified=false,readOnly=true,nativeDispatchAllowed=false}
    end
   end
  end
 end
 local f=characterFaction
 if f==nil then f=unitFaction() end
 if f~=nil and f~="Alliance" and f~="Horde" then
  result.reason="INVALID_FACTION";return result
 end
 local service=JLP:GetModule("Build70450RecipeAcquisition")
 if service and type(service.GetRecipeSources)=="function" then
  local ok,record,reason=pcall(service.GetRecipeSources,service,key,spellID,SOURCE_BUILD)
  if ok and type(record)=="table" and record.spellID==spellID and
     record.professionKey==key and record.sourceBuild==SOURCE_BUILD then
   result.dbRecipeIdentityQualified=true
   result.acquisitionEvidenceState=record.sourceState
   result.clientBuildRelation=record.clientBuildRelation
   result.hasConflictingSource=record.hasConflictingSource==true
   local seen={}
   for _,item in ipairs(record.teachingItems or {}) do
    if positive(item.itemID) and not seen[item.itemID] then
     seen[item.itemID]=true
     result.teachingItems[#result.teachingItems+1]={itemID=item.itemID,
      name=item.name,source="70450_EXACT_ITEM_TO_SPELL_LINK",readOnly=true}
    end
   end
   result.teachingItemCount=#result.teachingItems
   local unique={}
   for _,actor in ipairs(record.researchSources or {}) do
    if type(actor)=="table" and kinds[actor.sourceType] and
       accessible(actor,f) and (validText(actor.npcName) or positive(actor.npcID) or
       positive(actor.questID)) and (not actor.teachingItemID or
       seen[actor.teachingItemID]) then
     -- A conflict is still displayable as evidence, NEVER actionable.
     local token=actor.sourceType..":"..tostring(actor.npcID or actor.questID or
          actor.npcName or "UNKNOWN")..":"..tostring(actor.teachingItemID or "")
     if not unique[token] then
      unique[token]=true
      result.candidates[#result.candidates+1]=copyLead(actor)
     end
    end
   end
   result.sourceCandidateCount=#result.candidates
  else
   result.reason=ok and (reason or "DB70450_RELATION_UNKNOWN") or
     "DB70450_ACQUISITION_ERROR"
  end
 else result.reason="DB70450_ACQUISITION_MODULE_UNAVAILABLE" end
 -- External Forever reference is joined ONLY after the historical
 -- DB has independently asserted the EXACT SpellID -> teaching item link.
 -- No fuzzy name matching, faction relaxation, waypoints or source promotion.
 local exactData=JLP.data and JLP.data.foreverExactAcquisition192
 local evidence=exactData and exactData.contract=="JLP-FOREVER-EXACT-ACQUISITION-192" and
     exactData.rows and exactData.rows[key] and exactData.rows[key][spellID]
 if type(evidence)=="table" and evidence.recipeID==spellID and
     evidence.kind=="vendor" and validText(evidence.npcName) and
     validText(evidence.zone) and
     type(evidence.sourceURL)=="string" and
     evidence.sourceURL:match("^https://www%.wowhead%.com/forever/spell=") and
     accessible({factionReference=evidence.faction},f) then
  for _,item in ipairs(result.teachingItems) do
   if item.itemID==evidence.teachingItemID then
    local duplicate=false
    for _,a in ipairs(result.candidates) do
     if a.kind==evidence.kind and a.npcName==evidence.npcName and
        a.teachingItemID==item.itemID then duplicate=true;break end
    end
    if not duplicate then
     result.candidates[#result.candidates+1]={kind=evidence.kind,
      npcName=evidence.npcName,zone=evidence.zone,faction=evidence.faction,
      teachingItemID=item.itemID,referenceURL=evidence.sourceURL,
      evidenceTier="WOWHEAD_FOREVER_NAMED_ACTOR_WITH_DB_ITEM_JOIN",
      sourceJoinStrength="EXACT_RECIPE_AND_TEACHING_ITEM",
      researchOrigin=evidence.source,sourceVerifiedLive=false,
      navigationQualified=false,readOnly=true,nativeDispatchAllowed=false}
    end
    break
   end
  end
 end
 -- A separately qualified exact actor may exist in the current catalogue.
 -- Preserve it as advisory identity; SourceResolver itself never certifies a
 -- navigable location from an acquisition relation.
 local resolver=JLP:GetModule("SourceResolver")
 if resolver and type(resolver.GetRecipeSource)=="function" then
  local ok,qualified=pcall(resolver.GetRecipeSource,resolver,key,spellID,f)
  if ok and type(qualified)=="table" and qualified.recipeID==spellID then
   result.qualifiedActorReference={kind=qualified.kind,name=qualified.name or
     qualified.npcName,npcID=qualified.npcID or qualified.vendorID or
     qualified.trainerID,sourceBuild=qualified.sourceBuild,
     readOnly=true,navigationQualified=false}
  end
 end
 -- Separate named research references can close previously invisible exact
 -- item-to-source gaps. They are strictly advisory and never a waypoint proof.
 -- Do not search the research table by recipe name, since that can cross-link
 -- similar recipe names or profession variants.
 local candidateDedup={}
 for _,candidate in ipairs(result.candidates) do
  candidateDedup[tostring(candidate.kind)..":"..tostring(candidate.npcID or candidate.npcName)..
   ":"..tostring(candidate.teachingItemID or "")]=true
 end
 local legacy=legacyByItem()
 for _,item in ipairs(result.teachingItems) do
  for _,reference in ipairs(legacy[item.itemID] or {}) do
   for _,actor in ipairs(reference.sources or {}) do
    local kind=legacySourceMode(actor.sourceType)
    local name=actor.npc
    if kind and actor.referenceEligible==true and
       type(name)=="string" and #name>0 and #name<=220 and
       accessible({factionReference=actor.faction},f) then
      local id=positive(actor.npcID) and actor.npcID or nil
      local token=kind..":"..tostring(id or name)..":"..tostring(item.itemID)
      if not candidateDedup[token] then
       candidateDedup[token]=true
       result.candidates[#result.candidates+1]={kind=kind,npcName=name,
        npcID=id,teachingItemID=item.itemID,zone=actor.zone,
        faction=actor.faction,referenceURL=actor.evidence,
        evidenceTier=actor.evidenceQuality or "LEGACY_FOREVER_RESEARCH",
        researchOrigin="RECIPE_ACCESS_ITEM_ID_JOIN",sourceVerifiedLive=false,
        navigationQualified=false,readOnly=true,nativeDispatchAllowed=false,
        limitedSupplyAdvisory=actor.limitedSupply==true}
       result.legacySourceCount=result.legacySourceCount+1
      end
     end
    end
   end
  end
 -- Legacy profession research sometimes has exact recipe-name NPC options but
 -- no numeric teaching-item linkage. Preserve those as LOW-CONFIDENCE hints,
 -- never as a navigable waypoint or proven shop stock. Exact ID takes priority.
 local old=JLP.data and JLP.data.professionSources
 local named=old and old.recipes and old.recipes[key] and old.recipes[key][recipeName]
 if type(named)=="table" then
  local itemMatch=not positive(named.itemID)
  for _,item in ipairs(result.teachingItems) do
   if item.itemID==named.itemID then itemMatch=true end
  end
  if itemMatch then
   local lowerKind=type(named.kind)=="string" and named.kind:lower() or ""
   local kind=lowerKind:find("vendor",1,true) and "vendor" or
      (lowerKind:find("drop",1,true) and "drop" or nil)
   if kind then
    result.professionResearchMode=kind
    for faction,options in pairs(named.options or {}) do
     if faction=="Neutral" or f==nil or f==faction then
      for _,actor in ipairs(options) do
       if validText(actor.name) and validText(actor.zone) then
        local token=kind..":"..actor.name..":"..tostring(named.itemID or "")
        if not candidateDedup[token] then
         candidateDedup[token]=true
         result.candidates[#result.candidates+1]={kind=kind,npcName=actor.name,
          zone=actor.zone,faction=faction,teachingItemID=named.itemID,
          evidenceTier="LEGACY_NAMED_RESEARCH_NOT_CLIENT_VERIFIED",
          researchOrigin="PROFESSION_SOURCE_EXACT_RECIPE_NAME",
          sourceJoinStrength=positive(named.itemID) and "ITEM_ID" or "NAME_ONLY",
          readOnly=true,nativeDispatchAllowed=false,navigationQualified=false}
         result.professionResearchActorCount=(result.professionResearchActorCount or 0)+1
        end
       end
      end
     end
    end
   end
  end
 end
 -- Wowhead item-page source modes are independent corroboration, not an
 -- assignment of any particular mob or vendor to a spawn coordinate.
 local public=JLP.data and JLP.data.foreverAcquisitionModes190
 if type(public)=="table" and public.contract=="JLP-FOREVER-ACQUISITION-MODES-190" then
  for _,item in ipairs(result.teachingItems) do
   local row=public.items and public.items[item.itemID]
   if row and row.itemID==item.itemID and row.recipeID==spellID and
       row.professionKey==key and type(row.referenceURL)=="string" and
       row.referenceURL:match("^https://www%.wowhead%.com/forever/item") then
    result.publicModes=result.publicModes or {}
    for _,mode in ipairs(row.modes or {}) do
     if mode=="drop" or mode=="fished" or mode=="pickpocketed" then
      result.publicModes[#result.publicModes+1]=mode
     end
    end
    result.publicModeCount=#result.publicModes
    result.publicModeReference=row.referenceURL
   end
  end
 end
 -- Public guide acquisition is advice only: spell-name cross-reference does
 -- NOT establish an exact teaching-item identity or an owner waypoint.
 local f193=JLP.data and JLP.data.foreverSelectedRecipeFacts193
 local hint=f193 and f193.acquisition and f193.acquisition[key] and f193.acquisition[key][spellID]
 local f194=JLP.data and JLP.data.foreverSelectedRecipeFacts194
 if not hint then hint=f194 and f194.acquisition and f194.acquisition[key] and f194.acquisition[key][spellID] end
 if type(hint)=="table" and type(hint.source)=="string" and
    hint.source:match("^https://www%.wowhead%.com/forever/") then
  result.guideAcquisitionHint={kind=hint.kind,npcName=hint.actor,zone=hint.zone,
   identityStrength=hint.identityStrength,referenceURL=hint.source,
   workstation=hint.workstation,campWorkstation=false,
   teachingItemVerified=false,navigationQualified=false,
   readOnly=true,nativeDispatchAllowed=false}
 end
 -- Exact Forever spell-page "Taught by" names may be shown as cautious
 -- learner hints. Names are NOT numeric NPC IDs, current trainer stock, or
 -- owner waypoints; keep them outside actionable actor candidates.
 local trainerRoot=JLP.data and JLP.data.foreverTrainerNameReferences200
 local trainerRows=trainerRoot and trainerRoot.contract=="JLP-FOREVER-TRAINER-NAME-REFERENCE-200"
  and trainerRoot.rows and trainerRoot.rows[key] and trainerRoot.rows[key][spellID]
 if type(trainerRows)=="table" then
  result.referenceTrainerHints={}
  for _,r in ipairs(trainerRows) do
   local url=r.sourceURL or trainerRoot.sourceURL
   -- Spell-page identity is an exact equality, not a fuzzy name or
   -- profession match. The suffix is retained as original provenance.
   local exactURL=type(url)=="string" and
       url:match("^https://www%.wowhead%.com/forever/spell=(%d+)/[%w%-]+$")
   if tonumber(exactURL)==spellID and validText(r.npcName) and validText(r.zone) and
       (r.faction=="Horde" or r.faction=="Alliance" or r.faction=="Neutral") and
       accessible({factionReference=r.faction},f) then
    -- A positive NPC ID requires a second exact Forever NPC URL; spell-page
    -- trainer names alone never justify numeric identities or locations.
    local id=nil
    if positive(r.npcID) and type(r.npcURL)=="string" and
       r.npcURL=="https://www.wowhead.com/forever/npc="..tostring(r.npcID)..
       "/"..string.lower(r.npcName):gsub("[^%w ]", ""):gsub(" +", "-") then
     id=r.npcID
    end
    result.referenceTrainerHints[#result.referenceTrainerHints+1]={
     npcName=r.npcName,zone=r.zone,faction=r.faction,
     npcID=id,npcIdentityEvidence=id and "EXACT_FOREVER_NPC_PAGE_WITH_SPELL_TRAINER_NAME" or "NAME_ONLY",
     npcURL=id and r.npcURL or nil,
     sourceURL=url,kind="trainer",recipeID=spellID,
     trainingAvailability="UNKNOWN",navigationQualified=false,
     sourceVerifiedLive=false,readOnly=true,nativeDispatchAllowed=false}
   end
  end
 end
 result.sourceCandidateCount=#result.candidates
 if #result.candidates>0 then
  result.state=result.hasConflictingSource and "CONFLICTED_ACTOR_REFERENCES" or
    "ACTOR_REFERENCE_AVAILABLE"
  result.reason=result.hasConflictingSource and "REVIEW_CONFLICT_BEFORE_ACCESS" or
    "VERIFY_VENDOR_TRAINER_DROP_OR_QUEST_IN_GAME"
 elseif result.publicModeCount>0 then
  result.state="PUBLIC_ITEM_ACQUISITION_MODES_ONLY"
  result.reason="WOWHEAD_MODES_KNOWN_NPC_UNRESOLVED"
 elseif result.teachingItemCount>0 then
  result.state="TEACHING_ITEM_LINK_ONLY"
  result.reason="ITEM_TO_RECIPE_LINK_KNOWN_ACTOR_UNRESOLVED"
 elseif result.qualifiedActorReference then
  result.state="QUALIFIED_HISTORICAL_ACTOR_REFERENCE"
  result.reason="ACTOR_REFERENCE_NOT_LIVE_OR_NAVIGATION_PROOF"
 end
 -- Exact Forever quest objectives are advisory prerequisites, never proof of
 -- reward, NPC spawn, current completion or native purchase authorization.
 local questRefs=JLP.data and JLP.data.foreverQuestAcquisition191
 if type(questRefs)=="table" and questRefs.contract=="JLP-FOREVER-QUEST-ACCESS-191" then
  for _,candidate in ipairs(result.candidates) do
   local row=questRefs.quests and questRefs.quests[candidate.questID]
   if row and candidate.kind=="quest" and row.questID==candidate.questID and
      row.recipeID==spellID and row.professionKey==key and
      row.teachingItemID==candidate.teachingItemID and
      (row.faction==nil or row.faction==candidate.faction) and
      type(row.referenceURL)=="string" and
      row.referenceURL:match("^https://www%.wowhead%.com/forever/quest=") then
    candidate.questPrerequisites={}
    for _,v in ipairs(row.deliver or {}) do
     if validText(v.name) and positive(v.quantity) then
      candidate.questPrerequisites[#candidate.questPrerequisites+1]={
       name=v.name,quantity=v.quantity,source="WOWHEAD_FOREVER_QUEST_TEXT",
       itemID=v.itemID,inventoryQualified=false,readOnly=true}
     end
    end
    candidate.questURL=row.referenceURL
    candidate.questCompletion="UNKNOWN"
    candidate.questEligibility="UNKNOWN"
    result.questRequirementCount=(result.questRequirementCount or 0)+1
   end
  end
 end
 -- Independent Forever NPC+item spell crosscheck is bound to EXISTING exact
 -- teaching-item and actor identities. It can qualify a displayed NPC ID but
 -- cannot create an actor from an unverified item/name/coordinate alone.
 local public197=JLP.data and JLP.data.foreverNPCExactCrosschecks197
 local cross=public197 and public197.contract=="JLP-FOREVER-NPC-EXACT-CROSSCHECK-197" and
  public197.rows and public197.rows[key] and public197.rows[key][spellID]
 if type(cross)=="table" and cross.recipeID==spellID and
     positive(cross.npcID) and positive(cross.teachingItemID) and
     validText(cross.npcName) and validText(cross.zone) and
     cross.kind=="vendor" and cross.navigationQualified==false and
     cross.nativeDispatchAllowed==false and
     cross.npcURL=="https://www.wowhead.com/forever/npc="..tostring(cross.npcID) and
     cross.spellURL=="https://www.wowhead.com/forever/spell="..tostring(spellID) then
  local knownItem=false
  for _,item in ipairs(result.teachingItems) do
   if item.itemID==cross.teachingItemID then knownItem=true end
  end
  if knownItem then
   for _,a in ipairs(result.candidates) do
    if a.kind==cross.kind and a.npcName==cross.npcName and
        type(a.zone)=="string" and (a.zone==cross.zone or
          a.zone:find(", "..cross.zone,1,true)~=nil) and
        a.teachingItemID==cross.teachingItemID and
        (a.npcID==nil or a.npcID==cross.npcID) then
     a.npcID=cross.npcID
     a.npcIDSource=cross.npcURL
     a.npcIDCrosschecked=true
     a.sourceJoinStrength="FOREVER_EXACT_SPELL_TEACHING_ITEM_NPC_CROSSCHECK"
     a.sourceVerifiedLive=false
     a.navigationQualified=false
     result.exactPublicNPCCount=(result.exactPublicNPCCount or 0)+1
    end
   end
  end
 end
 -- Stable preferred display order does not claim availability. Unknown-source
 -- candidates never turn into automatic waypoint, vendor availability or loot.
 table.sort(result.candidates,function(a,b)
  local priority={trainer=1,vendor=2,quest=3,drop=4,npc=5}
  local pa,pb=priority[a.kind] or 9,priority[b.kind] or 9
  if pa~=pb then return pa<pb end
  local ia,ib=a.npcID or 0,b.npcID or 0
  if ia~=ib then return ia<ib end
  return tostring(a.npcName or "")<tostring(b.npcName or "")
 end)
 result.primary=result.candidates[1]
 -- P0-197: field-level source proof. An ID relation, named research actor,
 -- faction hint and canonical waypoint have different evidence strengths.
 -- Public research never confirms current server inventory or acquisition.
 local actor=result.primary
 local exactActorID=actor and positive(actor.npcID) or false
 local actorIdentity=actor and (exactActorID and "NPC_ID_REFERENCE" or
     validText(actor.npcName) and "NAME_REFERENCE_ONLY") or "UNKNOWN"
 local factionKnown=actor and
     (actor.faction=="Horde" or actor.faction=="Alliance" or actor.faction=="Neutral")
 result.fieldEvidence={
  recipeID=result.dbRecipeIdentityQualified and "EXACT_DB70450_SPELL_ID" or "UNKNOWN_DB_RECIPE_IDENTITY",
  teachingItem=result.teachingItemCount>0 and "DB70450_ITEM_EFFECT_LINK" or "UNKNOWN",
  acquisitionMode=actor and (actor.kind or "UNKNOWN") or
     result.publicModeCount>0 and "PUBLIC_MODE_REFERENCE" or "UNKNOWN",
  actorIdentity=result.hasConflictingSource and "CONFLICTED" or
    (actor and actor.npcIDCrosschecked and "NPC_ID_FOREVER_PUBLIC_CROSSCHECK" or actorIdentity),
  faction=factionKnown and "REFERENCE_NOT_LIVE" or "UNKNOWN",
  currentVendorStock="UNKNOWN",currentTrainerOffering="UNKNOWN",
  questCompletion="UNKNOWN",dropChance="UNKNOWN",
  liveAcquisition="UNKNOWN",canonicalWaypoint="UNQUALIFIED",
  nativeDispatch="NOT_AUTHORIZED_BY_SOURCES",
 }
 local missing={}
 if result.teachingItemCount==0 then missing[#missing+1]="TEACHING_ITEM_OR_DIRECT_TRAINER" end
 if not actor then missing[#missing+1]="NPC_OR_ACQUISITION_ACTOR" end
 if actor and not exactActorID then missing[#missing+1]="NPC_ID" end
 if actor and not factionKnown then missing[#missing+1]="FACTION_ELIGIBILITY" end
 if result.hasConflictingSource then missing[#missing+1]="RESOLVE_SOURCE_CONFLICT" end
 missing[#missing+1]="CURRENT_CLIENT_OFFERING_OR_DROP"
 missing[#missing+1]="CANONICAL_OWNER_WAYPOINT"
 result.unresolvedSourceFields=missing
 if key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local recipe=facts and facts:GetAlchemyContract(spellID,key)
  if recipe then
   result.sourceBuild=70532;result.dbRecipeIdentityQualified=true
   result.fieldEvidence.recipeID=key=="LEATHERWORKING" and "EXACT_DB2_70532_SKILLLINE165_SPELL" or key=="ENGINEERING" and "EXACT_DB2_70532_SKILLLINE202_SPELL" or key=="ALCHEMY" and "EXACT_DB2_70532_SKILLLINE171_SPELL" or "EXACT_DB2_70532_SKILLLINE164_SPELL"
   if recipe.trainerReferences then result.fieldEvidence.acquisitionMode="EXACT_FOREVER_NPC_TEACHES_REFERENCE_NOT_CURRENT_OFFER"end
  end
 end
 local pattern=self:GetPatternAcquisition(key,spellID)
 if pattern then
  result.patternAcquisition=pattern
  result.sourceBuild=70532;result.dbRecipeIdentityQualified=true
  result.fieldEvidence.recipeID="EXACT_DB2_70532_SPELL_ID"
  -- Exact70532 joins remain useful when the optional70450 service is absent.
  result.teachingItems={{itemID=pattern.itemID,source="EXACT_DB2_70532_ITEM_EFFECT",readOnly=true}}
  result.teachingItemCount=1
  if pattern.primary then result.primary=pattern.primary;result.candidates=pattern.candidates end
  result.state=pattern.sourceQualifiedForPlanning and "SOURCE_REFERENCE_QUALIFIED" or "UNKNOWN"
  result.fieldEvidence.teachingItem="DB2_70532_ITEM_EFFECT_LINK"
  result.fieldEvidence.currentVendorStock=pattern.primary and pattern.primary.currentStock or "UNKNOWN"
 end
 result.sourceFieldContract="JLP-SOURCE-FIELD-EVIDENCE-197"
 return result
end
-- Authoritative waypoint binding is possible ONLY when an exact candidate
-- resolves to one existing canonical owner TRAINER for this profession.
-- Vendor/drop/quest research never upgrades into a fabricated waypoint.
function M:GetCanonicalTrainerNavigation(key,spellID,characterFaction)
 local evidence=self:ForRecipe(key,spellID,nil,characterFaction)
 if evidence.hasConflictingSource then return nil,"SOURCE_ACTOR_CONFLICT" end
 local owner=JLP:GetModule("OwnerAuthorizedNavigation")
 local resolver=JLP:GetModule("SourceResolver")
 if not owner or type(owner.GetServiceList)~="function" or
    not resolver or type(resolver.VerifyNavigationWaypoint)~="function" then
  return nil,"CANONICAL_NAVIGATION_SERVICES_UNAVAILABLE" end
 local matches={}
 local actualFaction=characterFaction or unitFaction()
 for _,lead in ipairs(evidence.candidates or {}) do
  local requiredFaction=lead.faction
  local factionSafe=(requiredFaction~= "Horde" and requiredFaction~="Alliance") or
      (actualFaction~=nil and requiredFaction==actualFaction)
  if factionSafe and lead.kind=="trainer" and type(lead.npcName)=="string" and
      type(lead.zone)=="string" and #lead.zone>0 and
      lead.conflicted~=true then
   for _,candidate in ipairs(owner:GetServiceList("TRAINER") or {}) do
    if candidate.profession==key and candidate.kind=="trainer" and
        candidate.name==lead.npcName and type(candidate.zone)=="string" and
        candidate.zone==lead.zone then
     local ok=resolver:VerifyNavigationWaypoint("CURRENT_STEP",candidate)
     if ok==true then matches[candidate.serviceID]=candidate end
    end
   end
  end
 end
 -- With several exact trainers, a unique qualified local trainer avoids an
 -- unnecessary zone change. Unknown map or multiple local matches stay open.
 local map
 if type(C_Map)=="table" and type(C_Map.GetBestMapForUnit)=="function" then
  local ok,id=pcall(C_Map.GetBestMapForUnit,"player");if ok and positive(id)then map=id end
 end
 if map then
  local localChoice,count=nil,0
  for _,candidate in pairs(matches)do
   if candidate.nav and candidate.nav.mapID==map then
    if not localChoice or tostring(candidate.serviceID)<tostring(localChoice.serviceID)then localChoice=candidate end
    count=count+1
   end
  end
  if count==1 or (key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING") and count>0 then return localChoice,"OWNER_CANONICAL_EXACT_LOCAL_TRAINER"end
 end
 local chosen
 for _,candidate in pairs(matches) do
  if chosen then return nil,"MULTIPLE_OWNER_TRAINER_IDENTITIES" end
  chosen=candidate
 end
 return chosen,chosen and "OWNER_CANONICAL_EXACT_TRAINER" or "NO_OWNER_TRAINER_MATCH"
end
function M:Describe(result)
 if type(result)~="table" then return "Verify recipe acquisition source." end
 local actor=result.primary
 if result.hasConflictingSource or (actor and actor.conflicted) then
  return "Conflicting acquisition references: verify exact source before travelling." end
 if actor and validText(actor.npcName) then
  local typeLabel=actor.kind=="vendor" and "Vendor" or
   actor.kind=="trainer" and "Trainer" or actor.kind=="drop" and "Drop" or
   actor.kind=="quest" and "Quest" or "NPC"
  local guidance=typeLabel..": "..actor.npcName..(validText(actor.zone) and " ("..actor.zone..")" or "")
  if actor.kind=="vendor" and positive(actor.merchantFavorCost) then
   guidance=guidance.."; documented Merchant's Favor cost "..tostring(actor.merchantFavorCost)
  end
  if positive(actor.guideSkillRequired) then
   guidance=guidance.."; documented profession skill "..tostring(actor.guideSkillRequired)
  end
  if actor.kind=="quest" and positive(actor.questID) then
   guidance=guidance.."; quest "..tostring(actor.questID)
   if type(actor.questPrerequisites)=="table" and #actor.questPrerequisites>0 then
    local needed={}
    for _,r in ipairs(actor.questPrerequisites) do
     needed[#needed+1]=tostring(r.quantity).." x "..r.name
    end
    guidance=guidance.."; bring "..table.concat(needed,", ")
   end
  end
  return guidance..". Verify availability and eligibility."
 end
 if result.referenceTrainerHints and #result.referenceTrainerHints>0 then
  local hint=result.referenceTrainerHints[1]
  return "Forever spell reference lists "..hint.npcName.." ("..hint.zone..
   ") among possible trainers; current offering, NPC ID and waypoint remain unverified."
 end
 if result.guideAcquisitionHint then
  local hint=result.guideAcquisitionHint
  local lead=hint.npcName and (hint.npcName..(hint.zone and " ("..hint.zone..")" or "")) or "an unnamed source"
  return "Wowhead Forever lists "..tostring(hint.kind).." acquisition via "..lead..
    "; teaching-item, faction access and waypoint still require exact verification."
 end
 if result.professionResearchMode=="drop" then
  return "Research indicates a possible world/drop pattern; verify source on Wowhead Forever or in game."
 end
 if result.publicModeCount and result.publicModeCount>0 then
  return "Teaching item acquisition modes: "..table.concat(result.publicModes,", ")..
    ". Exact NPC or location unresolved; consult Wowhead Forever item page."
 end
 if result.teachingItemCount>0 then
  local item=result.teachingItems[1]
  return "Teaching item "..tostring(item.itemID).." is linked to this recipe; exact vendor/drop source unresolved."
 end
 return "Recipe source not qualified; consult existing research or Wowhead Forever."
end
JLP:RegisterModule("RecipeSourcePlanningBridge",M)
