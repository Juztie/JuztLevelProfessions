local _,JLP=...

local function prerequisiteTravelStep(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    if ownership and ownership.owned==true then return nil end
    local state=ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN"
    local reg=JLP:GetModule("ProfessionRegistry")
    local label=reg and reg:GetDisplayNameOrKey(key) or tostring(key)
    local text=state=="PROFESSION_NOT_LEARNED" and
        ("Learn "..label.." before JuztLevel can plan this profession.") or
        ("Verify learned "..label.." ownership before JuztLevel can plan this profession.")
    return {key=ownership and ownership.key or key,ownership=ownership,state=state,
        status=state,terminalReason=state,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,lightweightPrerequisite=true,actionKind="prerequisite",action=text,guidance=text}
end

-- Current Step always carries a travel/arrow handoff description. Only
-- canonical owner-qualified locations can be used for actual navigation;
-- candidate names, old map points and inferred routes are NOT waypoints.
local M={contract="JLP-CURRENT-STEP-TRAVEL-188",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local function eligible(source)
 return type(source)=="table" and source.sourceQualified==true and
  source.state=="SOURCE_QUALIFIED" and type(source.nav)=="table" and
  source.nav.mapDomain=="UI_MAP_ID" and type(source.nav.mapID)=="number" and
  type(source.nav.x)=="number" and type(source.nav.y)=="number"
end
local function travel(source,status,reason)
 return {contract=M.contract,required=true,owner="IntegratedDestinationOwner",
  travelEngine="IntegratedTravelEngine",arrow="IntegratedJuztTom",
  category="CURRENT_STEP",status=status,reason=reason,
  source=eligible(source) and source or nil,
  -- Immutable scalar snapshot: a resolver may reuse/mutate its source table
  -- between a UI render and navigation click/sync. Comparing two aliases
  -- of that table would otherwise miss a changed coordinate/actor.
  sourceIdentity=eligible(source) and {
      serviceID=source.serviceID,mapID=source.nav.mapID,
      x=source.nav.x,y=source.nav.y,recipeID=source.recipeID,
      materialItemID=source.materialItemID,materialRequired=source.materialRequired,teachingItemID=source.teachingItemID} or nil,
  sourceName=source and source.name or nil,
  sourceZone=source and source.zone or nil,
  waypointQualified=eligible(source),
  manualUserActionRequired=true,automaticMovement=false,
  nativeDispatchAllowed=false,readOnly=true}
end
local function ownerService(kind)
 local actions=JLP:GetModule("IntegratedNavigationActions")
 if actions and type(actions.NearestOwnerService)=="function" then
  local ok,row=pcall(actions.NearestOwnerService,actions,kind)
  if ok and eligible(row) then return row,"SAME_MAP" end
 end
 -- Qualified cross-zone alternatives may exist even if the player is not on
 -- the same map. Use the existing TravelRouter *advisory* cost heuristic; do
 -- not present it as a confirmed shortest path or an unlocked flight route.
 local resolver=JLP:GetModule("SourceResolver")
 local router=JLP:GetModule("TravelRouter")
 if not resolver or not resolver.GetOwnerServiceLocations or not router or
    not router.GetPlayerOrigin or not router.GetSourceLocation or not router.Cost then
  return nil,"PLAYER_POSITION_OR_SERVICE_DATA_UNAVAILABLE" end
 local origin=router:GetPlayerOrigin()
 if not origin or type(origin.mapID)~="number" then return nil,"PLAYER_MAP_UNKNOWN" end
 local best,cost
 for _,row in ipairs(resolver:GetOwnerServiceLocations(kind) or {}) do
  if eligible(row) then
   local location=router:GetSourceLocation(row)
   local metric=router:Cost(origin,location)
   if type(metric)=="number" and metric==metric and metric<math.huge and
      (not best or metric<cost or (metric==cost and row.serviceID<best.serviceID)) then
    best,cost=row,metric
   end
  end
 end
 return best,best and "HEURISTIC_CROSS_ZONE_NOT_SHORTEST_PATH_PROOF" or "NO_QUALIFIED_SERVICE"
end
-- Filter exact ordinary-Anvil aliases, prefer local positions, never measure
-- normalized coordinates from different UIMaps as a single distance space.
local function ordinaryAnvil()
 local resolver=JLP:GetModule("SourceResolver")
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin()
 local who=type(UnitFactionGroup)=="function" and UnitFactionGroup("player")
 if who~="Horde" and who~="Alliance" then return nil end
 local best,localBest,cost
 for _,s in ipairs(resolver and resolver:GetOwnerServiceLocations("CRAFT_STATION")or {})do
  if eligible(s)and s.stationFocus==1 and s.trainerServiceID and s.profession=="BLACKSMITHING"and
     (s.faction==who or s.faction=="Neutral")then
   local same=origin and origin.mapID==s.nav.mapID
   local metric=same and type(origin.x)=="number"and type(origin.y)=="number"and
    ((origin.x-s.nav.x)^2+(origin.y-s.nav.y)^2)or nil
   if not best or same and not localBest or same==localBest and
    (metric and (not cost or metric<cost)or (metric==cost and s.serviceID<best.serviceID))then
    best,localBest,cost=s,same,metric
   end
  end
 end
 return best
end
-- Recipe learning and an unlearned craft share the SAME exact source check.
-- A rank trainer or generic Apprentice trainer is not evidence that the
-- selected spell can be taught. Conflicting actor claims fail closed.
local function recipeLearningDestination(key,step)
 local join=JLP:GetModule("RecipeSourcePlanningBridge")
 local pattern=join and join.GetPatternAcquisition and join:GetPatternAcquisition(key,step.recipeID,step.skill) or step.patternAcquisition
 local api=JLP:GetModule("ProfessionAPI")
 if api and api.GetReadOnlyRecipeObservation then
  local ok,observation=pcall(api.GetReadOnlyRecipeObservation,api,step.recipeID,key)
  if ok and type(observation)=="table" and observation.readOnlyObserved==true and observation.learned==true then
   return travel(nil,"WORKSPACE_ACTION","OBSERVED_LEARNING_REPLAN_BEFORE_ACQUISITION_TRAVEL")
  end
 end
 if pattern and pattern.patternPossession=="UNKNOWN" then
  return travel(nil,"WORKSPACE_ACTION","OBSERVE_RECIPE_ITEM_INVENTORY_BEFORE_ACQUISITION_TRAVEL")
 end
 if pattern and pattern.status=="SOURCE_UNAVAILABLE" then
  return travel(nil,"LOCATION_UNVERIFIED","CURRENT_PATTERN_SOURCE_UNAVAILABLE_REPLAN")
 end
 local patternLead=pattern and pattern.primary
 if patternLead and patternLead.currentStock~="AVAILABLE" and patternLead.stockObservation and
    patternLead.stockObservation.recentUnavailable then
  return travel(nil,"LOCATION_UNVERIFIED","RECENT_PATTERN_SOURCE_UNAVAILABLE_RECHECK_OR_ALTERNATIVE")
 end
 if pattern and
    pattern.status=="LEARN_ITEM_MANUALLY" then
  return travel(nil,"WORKSPACE_ACTION","OBSERVED_PATTERN_USE_MANUALLY_THEN_OBSERVE_LEARNED")
 end
 if step.trainerAcquisition and (step.trainerAcquisition.status=="NOT_OFFERED" or step.trainerAcquisition.status=="INELIGIBLE")then
  return travel(nil,"LOCATION_UNVERIFIED","CURRENT_TRAINER_RECIPE_UNAVAILABLE_REPLAN")
 end
 
 local access=pattern and pattern.vendorAccess
 if key=="BLACKSMITHING" and access then
  if access.status=="BANK"then
   local bank=ownerService("BANK")
   if bank then bank.profession=key;bank.recipeID=step.recipeID;bank.accessNPCID=11278;bank.accessItemID=13544;bank.accessStage="BANK"end
   return travel(bank,eligible(bank)and "QUALIFIED"or "LOCATION_UNVERIFIED","WITHDRAW_OBSERVED_SPECTRAL_ESSENCE")
  elseif access.status=="QUEST_START"or access.status=="QUEST_RETURN"then
   local owner=JLP:GetModule("OwnerAuthorizedNavigation")
   local source=owner and owner.GetMagnusQuestWaypoint and owner:GetMagnusQuestWaypoint(step.recipeID,access)
   return travel(source,eligible(source)and "QUALIFIED"or "LOCATION_UNVERIFIED","MAGNUS_QUEST_GIVER_NOT_DUNGEON_OBJECTIVE")
  elseif access.status~="EQUIPPED"and access.status~="EQUIP_MANUALLY"and access.status~="UNKNOWN"and access.status~="CURRENT_USABLE_OFFER"then
   return travel(nil,"WORKSPACE_ACTION","MAGNUS_ACCESS_"..tostring(access.status))
  end
 end

 local recipeID=step.recipeID
 if type(recipeID)~="number" or recipeID~=math.floor(recipeID) or
    recipeID<1 or recipeID>=2147483647 then
  return travel(nil,"LOCATION_UNVERIFIED","EXACT_RECIPE_ID_REQUIRED")
 end
 local evidence=step.recipeSourcePlanning
 if type(evidence)=="table" and (evidence.hasConflictingSource==true or
    evidence.state=="CONFLICT" or evidence.sourceConflict==true) then
  return travel(nil,"LOCATION_UNVERIFIED","RECIPE_SOURCE_ACTOR_CONFLICT")
 end
 local resolver=JLP:GetModule("SourceResolver")
 local source=resolver and resolver.GetRecipeSource and
     resolver:GetRecipeSource(key,recipeID) or nil
 if eligible(source) and resolver and type(resolver.VerifyNavigationWaypoint)=="function" then
  local id=source.recipeID
  if id==recipeID then
   local ok,verified=pcall(resolver.VerifyNavigationWaypoint,resolver,"CURRENT_STEP",source)
   if ok and verified==true then
    local verifiedTravel=travel(source,"QUALIFIED","CANONICAL_RECIPE_SOURCE")
    verifiedTravel.recipeID=recipeID
    return verifiedTravel
   end
  end
 end
 -- Research can point at an already verified owner trainer, but only with
 -- exact profession + recipe + trainer name + zone and compatible faction.
 local join=JLP:GetModule("RecipeSourcePlanningBridge")
 if join and type(join.GetCanonicalTrainerNavigation)=="function" then
  local candidate=join:GetCanonicalTrainerNavigation(key,recipeID)
  if eligible(candidate) then
   local verifiedTravel=travel(candidate,"QUALIFIED","OWNER_CANONICAL_EXACT_RECIPE_TRAINER")
   verifiedTravel.recipeID=recipeID
   return verifiedTravel
  end
 end
 local advisory=evidence and evidence.primary
 if advisory and advisory.conflicted~=true then
  local view=travel({name=advisory.npcName,zone=advisory.zone},
      "SOURCE_REFERENCE_ONLY","RECIPE_SOURCE_HAS_NO_CANONICAL_WAYPOINT")
  view.sourceEvidenceType=advisory.kind
  return view
 end
 return travel(nil,"LOCATION_UNVERIFIED","RECIPE_SOURCE_COORDINATES_UNQUALIFIED")
end
-- Reuses the existing owner/Travel Journey for the qualified outdoor leg.
-- Unqualified instance legs remain manual guidance, never invented graph edges.
function M:ForAnnoraStep(step)
 local api=JLP:GetModule("ProfessionAPI")
 local profession=api and api.Get and api:Get("ENCHANTING")
 local facts=JLP:GetModule("ProfessionPlanningFacts")
 local need=facts and facts.GetAnnoraLearning and facts:GetAnnoraLearning(step,profession)
 if not need then return nil end
 local d=JLP.data.enchanting.annoraAccess
 local stage,status,reason="TRAVEL_APPROACH","QUALIFIED","ANNORA_OUTDOOR_APPROACH_ONLY"
 local bindingReason
 local offer=need.offer or {}
 local mapType,instanceID
 if type(GetInstanceInfo)=="function" then
  local ok,_,kind,_,_,_,_,_,id=pcall(GetInstanceInfo)
  if ok then mapType,instanceID=kind,id end
 end
 local origin=JLP:GetModule("TravelRouter")
 origin=origin and origin.GetPlayerOrigin and origin:GetPlayerOrigin()
 local owner=JLP:GetModule("OwnerAuthorizedNavigation")
 local source=owner and owner.GetAnnoraApproach and owner:GetAnnoraApproach()
 local geometry=JLP:GetModule("IntegratedNavigationHUD")
 local atApproach=false
 if source and origin and origin.mapID==source.nav.mapID and geometry and geometry.GetGeometry then
  local g=geometry:GetGeometry(source.nav)
  atApproach=g and g.instanceVerified==true and type(g.distanceYards)=="number" and g.distanceYards>=0 and g.distanceYards<=5
 end
 if not need.eligible then stage,status,reason="VERIFY_LEVEL_OR_RANK","WORKSPACE_ACTION","ANNORA_CHARACTER_LEVEL_REQUIREMENT"
 elseif need.learnedUnknown then stage,status,reason="OBSERVE_RECIPE_KNOWLEDGE","WORKSPACE_ACTION","ANNORA_LEARNED_STATE_UNKNOWN"
 elseif offer.status=="NOT_OFFERED" or offer.status=="INELIGIBLE" or offer.recentUnavailable then
  stage,status,reason="RECHECK_TRAINER_OFFER","WORKSPACE_ACTION","ANNORA_CURRENT_OFFER_UNAVAILABLE_RECHECK"
 elseif offer.status=="ALREADY_KNOWN_LISTED" then
  stage,status,reason="OBSERVE_LEARNING_OR_CAP","WORKSPACE_ACTION","TRAINER_USED_IS_NOT_LEARNING_RECEIPT"
 elseif offer.status=="AVAILABLE" then
  stage,status,reason="TRAIN_MANUALLY","WORKSPACE_ACTION","ANNORA_EXACT_CURRENT_OFFER_MANUAL_ONLY"
 elseif instanceID==d.instanceMapID and mapType=="party" then
  if owner and owner.GetAnnoraInternal then source,bindingReason=owner:GetAnnoraInternal() else source=nil end
  if source then stage,status,reason="DIRECT_BEARING_INTERNAL","QUALIFIED","ANNORA_DIRECT_BEARING_NOT_PHYSICAL_ROUTE"
  else stage,status,reason="LOCAL_DUNGEON_GUIDANCE","LOCATION_UNVERIFIED",bindingReason or "ANNORA_REFERENCE_UI_MAP_ART_PROJECTION_UNBOUND" end
 elseif mapType~="none" or type(instanceID)~="number" or not origin or
  origin.mapDomain and origin.mapDomain~="UI_MAP_ID" or
  type(origin.mapID)~="number" or origin.mapID==70 or origin.mapID==1337 or origin.mapID==1517 or
  type(origin.x)~="number" or type(origin.y)~="number" then
  stage,status,reason="VERIFY_MAP_CONTEXT","LOCATION_UNVERIFIED","ANNORA_CURRENT_OUTDOOR_POSITION_UNAVAILABLE"
 elseif atApproach then
  stage,status,reason="ENTER_INSTANCE_MANUALLY","WORKSPACE_ACTION","ANNORA_APPROACH_ARRIVAL_IS_NOT_NPC_OR_LEARNING"
 elseif not source then stage,status,reason="VERIFY_APPROACH","LOCATION_UNVERIFIED","ANNORA_CANONICAL_APPROACH_UNAVAILABLE" end
 if stage~="TRAVEL_APPROACH" and stage~="DIRECT_BEARING_INTERNAL" then source=nil end
 if source then
  source.learningKind=need.kind;source.learningRecipeID=need.recipeID
  source.trainingSpellID=need.trainingSpellID
 end
 local nav=travel(source,status,reason)
 nav.annoraAccess={stage=stage,need=need,approachOnly=stage~="DIRECT_BEARING_INTERNAL",npcPositionQualified=stage=="DIRECT_BEARING_INTERNAL",
   positionReference=d.positionReference,bindingReason=bindingReason,
   physicalRouteStatus=d.physicalRouteStatus,
   internalUIMapStatus=stage=="DIRECT_BEARING_INTERNAL" and "REFERENCE_AND_RUNTIME_QUALIFIED" or d.internalUIMapStatus,
   missingFields=stage=="DIRECT_BEARING_INTERNAL" and {} or {"reference UIMap identity", "reference art/projection equivalence", "mapgroup ambiguity assessment (floor only if multiple)", "current player/reference geometry compatibility"},
  localGuidance=d.localGuidance,guideURL=d.guideURL,guideStatus=d.guideStatus,
  instanceMapID=d.instanceMapID,instanceObserved=instanceID==d.instanceMapID and mapType=="party",
  completionProof="OBSERVED_REQUIRED_RECIPE_OR_PROFESSION_CAP_NOT_ARRIVAL_MENU_USED_OR_CAST",
  readOnly=true,nativeDispatchAllowed=false}
 if source then nav.recipeID=need.recipeID end
 return nav
end
function M:ForStep(key,step)
    local prerequisite=prerequisiteTravelStep(key)
    if prerequisite then return nil,prerequisite.terminalReason end
 if type(step)~="table" then return travel(nil,"NO_STEP","CURRENT_STEP_UNAVAILABLE") end
 if step.kind=="complete" then return travel(nil,"NOT_APPLICABLE","PROFESSION_COMPLETE") end
 if step.secondaryAccess then
  local secondary=JLP:GetModule("SecondaryLevelingPlanner");local api=JLP:GetModule("ProfessionAPI")
  local a=secondary and secondary:GetOperationalAccess(key,api and api:Get(key),step.recipeID)
  if not a or a.status~=step.secondaryAccess.status then return travel(nil,"WORKSPACE_ACTION","SECONDARY_ACCESS_CHANGED_REPLAN")end
  local source
  if a.status=="RETRIEVE_BOOK_BANK"then
   source=ownerService("BANK")
   if source then source.profession=key;source.secondaryAccess=true;source.recipeID=a.recipeID;source.teachingItemID=a.itemID;source.accessRank=a.rank;source.accessStage=a.status end
  else source=secondary:GetOperationalWaypoint(a)end
  return travel(source,eligible(source)and "QUALIFIED"or "WORKSPACE_ACTION",key.."_"..a.status.."_SEPARATE_OBSERVATION_REQUIRED")
 end
 if key=="FIRST_AID"and step.firstAidAccess then
  local aid=JLP:GetModule("ForeverFirstAidArtisan232");local api=JLP:GetModule("ProfessionAPI")
  local a=aid and aid:GetOperationalAccess(api and api:Get(key),step.recipeID)
  if not a or a.status~=step.firstAidAccess.status then return travel(nil,"WORKSPACE_ACTION","FIRST_AID_ACCESS_CHANGED_REPLAN")end
  local source
  if a.status=="RETRIEVE_BOOK_BANK"then
   source=ownerService("BANK")
   if source then source.profession=key;source.firstAidAccess=true;source.recipeID=a.recipeID;source.teachingItemID=a.itemID;source.accessRank=a.rank;source.accessStage=a.status end
  else source=aid:GetOperationalWaypoint(a)end
  return travel(source,eligible(source)and "QUALIFIED"or "WORKSPACE_ACTION","FIRST_AID_"..a.status.."_SEPARATE_OBSERVATION_REQUIRED")
 end
 if key=="ENCHANTING" then local annora=self:ForAnnoraStep(step);if annora then return annora end end
 if key=="MINING"and step.miningSource then
  local bridge=JLP:GetModule("GatheringMaterialBridge")
  local api=JLP:GetModule("ProfessionAPI");local prof=api and api:Get("MINING")
  local guide=JLP:GetModule("ForeverMiningNodeProgression210")
  local source=bridge and bridge:GetMiningWaypoint(tonumber(step.miningSource.material),step.miningSource.serviceID)
  local node=source and guide and guide:GetNodeContract(source.resourceKey,source.objectID)
  if source and node and prof and prof.cached~=true and type(prof.skill)=="number"and prof.skill>=node.minimum and
    not (bridge.unavailable and (bridge.unavailable[source.serviceID]or bridge.unavailable[node.resourceKey]))then
   return travel(source,"QUALIFIED","MINING_STATIC_REFERENCE_VERIFY_NODE_DIFFICULTY_ACCESS")
  end
  return travel(nil,"LOCATION_UNVERIFIED","MINING_SOURCE_REQUIRES_REPLAN")
 end
 if key=="HERBALISM"and step.herbalismSource then
  local bridge=JLP:GetModule("GatheringMaterialBridge");local guide=JLP:GetModule("ForeverHerbalismProgression209")
  local api=JLP:GetModule("ProfessionAPI");local p=api and api:Get(key)
  local source=bridge and bridge:GetHerbalismWaypoint(tonumber(step.herbalismSource.material),step.herbalismSource.serviceID)
  local node=source and guide and guide:GetNodeContract(source.resourceKey,source.objectID)
  if source and node and p and p.cached~=true and type(p.skill)=="number"and p.skill>=node.minimum and
    not(bridge.unavailable and (bridge.unavailable[source.serviceID]or bridge.unavailable[node.resourceKey]))then
   return travel(source,"QUALIFIED","HERBALISM_REFERENCE_VERIFY_CURRENT_NODE_ACCESS")
  end
  return travel(nil,"LOCATION_UNVERIFIED","HERBALISM_SOURCE_REQUIRES_REPLAN")
 end
 if key=="SKINNING" and step.skinningSource then
  local source=step.skinningSource
  local bridge=JLP:GetModule("GatheringMaterialBridge")
  local eligible=bridge and bridge:GetEligibleSkinningSources(tonumber(source.material)) or {}
  for _,row in ipairs(eligible) do
   if row.id==source.serviceID then
    local current=bridge:GetSkinningWaypoint(tonumber(source.material),row.id)
    return travel(current,"QUALIFIED","SKINNING_REFERENCE_VERIFY_CURRENT_TARGET_DIFFICULTY")
   end
  end
  return travel(nil,"LOCATION_UNVERIFIED","SKINNING_SOURCE_REQUIRES_REPLAN")
 end
 if key=="FISHING"and step.fishingArea then
  local secondary=JLP:GetModule("SecondaryLevelingPlanner")
  local s=secondary and secondary:GetFishingApproach(step.fishingArea.mapID)
  return travel(s,eligible(s)and "QUALIFIED"or "MAP_REFERENCE_ONLY",eligible(s)and "QUALIFIED_FISHING_APPROACH_NOT_POOL_OR_CATCH_RECEIPT"or "FISHING_AREA_HAS_NO_QUALIFIED_APPROACH_POINT")
 end
 if step.materialSupply then
  local supplied=step.materialSupply
  local bridge=JLP:GetModule("GatheringMaterialBridge")
  local current=bridge and bridge:RefreshSupply(supplied)
  if not current or current.status~=supplied.status or current.sourceID~=supplied.sourceID then
   return travel(nil,"LOCATION_UNVERIFIED","SUPPLY_CHANGED_REPLAN")
  end
  if current.professionKey=="MINING"and current.status=="VERIFY_FORGE"then
   return travel(current.source,eligible(current.source)and "QUALIFIED"or "LOCATION_UNVERIFIED","FORGE_GEOGRAPHY_VERIFY_CURRENT_REQUIREMENTS_ON_ARRIVAL")
  elseif current.professionKey=="FISHING"and current.status=="VENDOR"then
   local source={};for k,v in pairs(current.source)do source[k]=v end;source.materialRequired=current.required
   return travel(source,"QUALIFIED","FISH_VENDOR_GEOGRAPHY_CURRENT_OFFER_NOT_DELIVERY")
  elseif current.status=="FISHING_AREA"then
   local secondary=JLP:GetModule("SecondaryLevelingPlanner")
   local s=secondary and secondary:GetFishingApproach(current.mapID,current.itemID,nil,current.required,current.consumerProfession)
   return travel(s,eligible(s)and "QUALIFIED"or "MAP_REFERENCE_ONLY",eligible(s)and "QUALIFIED_FISHING_APPROACH_NOT_POOL_OR_CATCH_RECEIPT"or "FISHING_AREA_HAS_NO_QUALIFIED_SAFE_STANDING_POINT_OR_POOL_COORDINATES")
  elseif current.status=="BAGS_READY"then return travel(nil,"WORKSPACE_ACTION","SUPPLY_DELIVERED_RETURN_TO_CONSUMER")
  elseif current.status=="CLOTH_LOOT"then return travel(current.source,"QUALIFIED","HISTORICAL_CLOTH_DROP_GEOGRAPHY_NOT_GUARANTEED_SPAWN_OR_LOOT")
  elseif current.status=="HERBALISM"then return travel(current.source,"QUALIFIED","HERBALISM_REFERENCE_NOT_LIVE_SPAWN")
  elseif current.status=="MINING"then return travel(current.source,"QUALIFIED","MINING_REFERENCE_NOT_LIVE_SPAWN")
  elseif current.status=="SKINNING" then
   return travel(current.source,"QUALIFIED",current.scope=="STATIC_FOREVER_SKINNING_REFERENCE" and "STATIC_FOREVER_REFERENCE_VERIFY_TARGET_ON_ARRIVAL" or "PERSONAL_SKINNING_HISTORY_VERIFY_TARGET_ON_ARRIVAL")
  elseif current.status=="BANK" or current.status=="VERIFY_BANK" then
   local bank=ownerService("BANK")
   return travel(bank,eligible(bank) and "QUALIFIED" or "LOCATION_UNVERIFIED",
    current.status=="BANK" and "WITHDRAW_OBSERVED_MATERIAL_BEFORE_PURCHASE" or "VERIFY_BANK_STOCK_QUANTITY_UNKNOWN")
  elseif current.status=="AUCTION" then
   local auction=ownerService("AUCTION_HOUSE")
   return travel(auction,eligible(auction) and "QUALIFIED" or "LOCATION_UNVERIFIED","RECHECK_QUALIFIED_MATERIAL_QUOTE")
  end
  return travel(nil,"MAP_REFERENCE_ONLY",current.reason or current.status)
 end
 if step.materialService then
  local acquisition=JLP:GetModule("AcquisitionPlanner")
  local old=step.materialService
  local service=acquisition and acquisition:SelectMaterialService(key,old.itemID,old.required)
  if not service or service.status=="BAGS_READY" then return travel(nil,"WORKSPACE_ACTION","SERVICE_DELIVERY_REPLAN_SELECTED_CRAFT") end
  if service.status=="BANK" or service.status=="VERIFY_BANK" then
   local bank=ownerService("BANK")
   if bank and step.stationPreparation and step.stationPreparation.status=="RETRIEVE_KIT_BANK" then
    local scoped={};for k,v in pairs(bank)do scoped[k]=v end;bank=scoped
    bank.cookingKitBank=true;bank.materialConsumer=key
    bank.consumerRecipeID=step.recipeID;bank.materialItemID=service.itemID;bank.materialRequired=service.required
    bank.observerGUID=type(UnitGUID)=="function"and UnitGUID("player")or nil
   end
   return travel(bank,eligible(bank)and "QUALIFIED"or "LOCATION_UNVERIFIED","VERIFY_OR_WITHDRAW_MATERIAL_BEFORE_NEW_PURCHASE")
  elseif service.source then
   local source={};for k,v in pairs(service.source)do source[k]=v end
   source.materialRequired=service.required
   return travel(source,"QUALIFIED","VENDOR_GEOGRAPHY_NOT_CURRENT_STOCK_OR_PURCHASE_RECEIPT")
  end
  return travel(nil,"LOCATION_UNVERIFIED",service.status)
 end
 if (key=="ENCHANTING" or key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING") and step.learningMethod=="automatic" and step.learned~=true then
  return travel(nil,"WORKSPACE_ACTION","AUTOMATIC_RECIPE_REQUIRES_CURRENT_PANEL_OBSERVATION")end
 if key=="ENCHANTING" and step.ordinaryRodAcquisition then
  local rod=step.ordinaryRodAcquisition
  if rod.status=="BANK_OBSERVED" then
   local bank=ownerService("BANK")
   return travel(bank,eligible(bank) and "QUALIFIED" or "LOCATION_UNVERIFIED","WITHDRAW_OBSERVED_ORDINARY_ROD")
  elseif rod.selectedSource=="auction" then
   local auction=ownerService("AUCTION_HOUSE")
   return travel(auction,eligible(auction) and "QUALIFIED" or "LOCATION_UNVERIFIED","OBSERVED_ROD_AH_QUOTE_RECHECK_REQUIRED")
  else return travel(nil,"LOCATION_UNVERIFIED","ORDINARY_ROD_VERIFY_OR_MANUAL_BLACKSMITH_NO_NPC_DESTINATION")end
 end
 if step.dungeonAccessUnverified or (key=="ENCHANTING" and step.kind=="train" and
    (step.rank=="Artisan" or step.trainer and step.trainer.rank=="Artisan")) then
  return travel(nil,"LOCATION_UNVERIFIED","ANNORA_DUNGEON_ACCESS_AND_POSITION_UNVERIFIED")end
 local resolver=JLP:GetModule("SourceResolver")
 if step.patternAcquisition and step.patternAcquisition.status=="RETRIEVE_PATTERN_FROM_BANK" then
  local bank,choice=ownerService("BANK")
  return travel(bank,eligible(bank) and "QUALIFIED" or "LOCATION_UNVERIFIED",
      eligible(bank) and "WITHDRAW_OBSERVED_RECIPE_ITEM" or "CANONICAL_BANK_UNKNOWN")
 end
 if key=="ENCHANTING" and step.toolRequirement and step.toolRequirement.status=="bank" then
  local bank=ownerService("BANK")
  return travel(bank,eligible(bank) and "QUALIFIED" or "LOCATION_UNVERIFIED",
      eligible(bank) and "WITHDRAW_OBSERVED_ENCHANTING_TOOL" or "CANONICAL_BANK_UNKNOWN")
 end
 if step.kind=="craft" and step.learned==true and step.bagReady==true and step.ordinaryAnvil==true then
  if step.stationStatus=="MET" then return travel(nil,"WORKSPACE_ACTION","ANVIL_READINESS_OBSERVED_CRAFT_GOAL_UNCHANGED")end
  local station=ordinaryAnvil()
  return travel(station,eligible(station)and "QUALIFIED"or "LOCATION_UNVERIFIED",
   eligible(station)and "USER_ORDINARY_ANVIL_TRAINER_ACCESS_POINT"or "NO_QUALIFIED_BLACKSMITH_TRAINER_GEOGRAPHY")
 end
 -- No invented gathering point: Gathering Map selects an existing user-verified
 -- stop. The map/zone resource is reference data, not a spawn coordinate.
 if (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING") and step.learned==true and (step.stationStatus and step.stationStatus~="MET" and not step.ordinaryAnvil or step.cooldownStatus) then return travel(nil,"LOCATION_UNVERIFIED",key.."_STATION_OR_COOLDOWN_REQUIRES_CURRENT_VERIFICATION")end
 if step.kind=="gather" then
  return travel(nil,"MAP_REFERENCE_ONLY","SELECT_QUALIFIED_GATHERING_STOP_IN_EXISTING_MAP")
 end
 if step.kind=="learn" then
  -- A recipe-specific LEARN must never silently become rank training.
  if step.recipeID~=nil then return recipeLearningDestination(key,step) end
  local trainer=resolver and resolver.GetOwnerTrainerForRank and
      resolver:GetOwnerTrainerForRank(key,step.rank or "Apprentice") or nil
  return travel(trainer,eligible(trainer) and "QUALIFIED" or "LOCATION_UNVERIFIED",
      eligible(trainer) and "CANONICAL_PROFESSION_TRAINER" or "PROFESSION_TRAINER_NOT_QUALIFIED")
 end
 if step.kind=="verify-inventory" or step.kind=="acquire-material" then
  local bank,choice=ownerService("BANK")
  if bank then return travel(bank,"QUALIFIED",choice=="SAME_MAP" and
    "VERIFY_OR_WITHDRAW_MATERIALS" or "BANK_CROSS_ZONE_TRAVEL_HEURISTIC") end
  if step.auctionPriceAvailable==true or step.kind=="acquire-material" then
   local auction,auctionChoice=ownerService("AUCTION_HOUSE")
   if auction then return travel(auction,"QUALIFIED",auctionChoice=="SAME_MAP" and
      "OPTIONAL_AUCTION_MATERIAL_SOURCE" or "AUCTION_CROSS_ZONE_TRAVEL_HEURISTIC") end
  end
  return travel(nil,"LOCATION_UNVERIFIED","CANONICAL_MATERIAL_SERVICE_UNKNOWN")
 end
 if step.kind=="train" then
  local rank=step.rank or (step.trainerLead and step.trainerLead.rank)
  local trainer=resolver and resolver.GetOwnerTrainerForRank and rank and
      resolver:GetOwnerTrainerForRank(key,rank) or nil
  return travel(trainer,eligible(trainer) and "QUALIFIED" or "LOCATION_UNVERIFIED",
    eligible(trainer) and "CANONICAL_TRAINER" or "TRAINER_COORDINATES_UNAVAILABLE")
 end
 if step.kind=="craft" then
  if step.learned==false then
   return recipeLearningDestination(key,step)
  end
  if step.bagReady~=true then
   local bank,choice=ownerService("BANK")
   if bank then return travel(bank,"QUALIFIED",choice=="SAME_MAP" and
    "CHECK_BANK_FIRST" or "BANK_CROSS_ZONE_TRAVEL_HEURISTIC") end
   if step.auctionPriceAvailable==true then
    local auction,choice=ownerService("AUCTION_HOUSE")
    if auction then return travel(auction,"QUALIFIED",choice=="SAME_MAP" and
     "SOURCE_AUCTION_MATERIALS" or "AUCTION_CROSS_ZONE_TRAVEL_HEURISTIC") end
   end
   return travel(nil,"LOCATION_UNVERIFIED","BANK_AH_LOCATION_NOT_CANONICAL")
  end
  return travel(nil,"WORKSPACE_ACTION","CRAFT_IN_PROFESSION_WORKSPACE")
 end
 return travel(nil,"LOCATION_UNVERIFIED","GATHERING_OR_SOURCE_WAYPOINT_NOT_QUALIFIED")
end
function M:Attach(key,step)
    local prerequisite=prerequisiteTravelStep(key)
    if prerequisite then return prerequisite end
 if type(step)=="table" then
  step.navigation=self:ForStep(key,step)
  step.annoraAccess=step.navigation.annoraAccess
  if step.annoraAccess then
   step.annoraBaseAction=step.annoraBaseAction or step.nextAction or step.action or "Verify Annora learning."
   local a=step.annoraAccess
   local instruction=a.stage=="TRAVEL_APPROACH" and "Travel to the qualified Uldaman rear entrance; this is an OUTDOOR approach, not Annora's position." or
    a.stage=="RECHECK_TRAINER_OFFER" and "Recheck Annora's exact offering/access; the unavailable offer does not justify another automatic journey to the same source." or
    a.stage=="TRAIN_MANUALLY" and "Use the exact available Annora trainer service manually, then observe the required recipe/cap separately." or
    a.stage=="OBSERVE_LEARNING_OR_CAP" and "Observe the required learned-state or profession cap; a trainer used-status is not completion." or
    a.stage=="DIRECT_BEARING_INTERNAL" and "Follow the qualified direct bearing to Annora; this is not a corridor, door or floor route. Learning/rank still needs its own observation." or
     a.stage=="LOCAL_DUNGEON_GUIDANCE" and (a.localGuidance.." Binding: "..tostring(a.bindingReason)) or
    a.stage=="ENTER_INSTANCE_MANUALLY" and "Rear entrance reached; enter Uldaman manually. Entry/arrival is not learning or rank completion." or
    a.stage=="OBSERVE_RECIPE_KNOWLEDGE" and "Inspect current recipe learned-state before travelling; UNKNOWN is not unlearned." or
    "Verify character level, rank and current map/position; no direction arrow is qualified."
   step.nextAction=step.annoraBaseAction.." "..instruction
   step.action=step.nextAction
  end
 end
 return step
end
function M:AttachPlan(key,plan)
    local prerequisite=prerequisiteTravelStep(key)
    if prerequisite then return prerequisite end
 if type(plan)~="table" then return plan end
 local step=plan.recommendedCurrentStep
 if type(step)=="table" then
  self:Attach(key,step)
  plan.currentStepNavigation=step.navigation
  if step.annoraAccess then plan.action=step.nextAction end
 elseif plan.actionKind=="train" then
  local info=plan.step and plan.step.trainer
  plan.currentStepNavigation=self:ForStep(key,{kind="train",rank=info and info.rank})
 elseif plan.actionKind=="learn" then
  plan.currentStepNavigation=self:ForStep(key,{kind="learn",rank="Apprentice"})
 end
 return plan
end
-- Check the SAME source, recipe and coordinates at handoff time for
-- explicit Request AND automatic Current Step Sync. The owner revalidates
-- context/Stop/Pause afterwards; a stale view may never bypass this boundary.
local function checkHandoff(self,key,step)
 local nav=type(step)=="table" and step.navigation or nil
 if not nav or nav.waypointQualified~=true or not eligible(nav.source) then
  return nil,nav and nav.reason or "CURRENT_STEP_WAYPOINT_UNQUALIFIED" end
 if nav.source.fishingApproach==true then
  local resolver=JLP:GetModule("SourceResolver");local fresh=self:ForStep(key,step)
  if not fresh.source or fresh.source.serviceID~=nav.source.serviceID or not resolver or not resolver:VerifyNavigationWaypoint("CURRENT_STEP",nav.source)then return nil,"STALE_FISHING_APPROACH"end
  return nav.source
 end
 if nav.source.secondaryAccess==true then
  local fresh=self:ForStep(key,step);local source=fresh and fresh.source;local resolver=JLP:GetModule("SourceResolver")
  if not source or source.serviceID~=nav.source.serviceID or source.accessStage~=nav.source.accessStage or source.teachingItemID~=nav.source.teachingItemID or source.accessQuestID~=nav.source.accessQuestID or not resolver or not resolver:VerifyNavigationWaypoint("CURRENT_STEP",nav.source)then return nil,"STALE_SECONDARY_ACQUISITION"end
  return nav.source
 end
 if nav.source.firstAidAccess==true then
  local fresh=self:ForStep(key,step);local source=fresh and fresh.source
  local resolver=JLP:GetModule("SourceResolver")
  if not source or source.serviceID~=nav.source.serviceID or source.accessStage~=nav.source.accessStage or source.teachingItemID~=nav.source.teachingItemID or source.accessQuestID~=nav.source.accessQuestID or not resolver or not resolver:VerifyNavigationWaypoint("CURRENT_STEP",nav.source)then return nil,"STALE_FIRST_AID_ACQUISITION"end
  return nav.source
 end
 if nav.source.accessNPCID==11278 then
  local fresh=self:ForStep(key,step)
  local current=fresh and fresh.source
  local resolver=JLP:GetModule("SourceResolver")
  if not current or current.serviceID~=nav.source.serviceID or current.recipeID~=nav.source.recipeID or
   current.nav.mapID~=nav.source.nav.mapID or current.nav.x~=nav.source.nav.x or current.nav.y~=nav.source.nav.y or
   current.accessItemID~=nav.source.accessItemID or current.accessQuestID~=nav.source.accessQuestID or current.accessStage~=nav.source.accessStage then
   return nil,"STALE_MAGNUS_ACCESS_DESTINATION" end
  if not resolver or not resolver:VerifyNavigationWaypoint("CURRENT_STEP",nav.source)then return nil,"MAGNUS_CANONICAL_REVALIDATION_FAILED"end
  return nav.source
 end
 if nav.source.serviceID=="ULDAMAN_REAR" or nav.source.serviceID=="ULDAMAN_ANNORA" then
  local fresh=self:ForAnnoraStep(step)
  if not fresh or not fresh.source or fresh.source.learningKind~=nav.source.learningKind or
    fresh.source.learningRecipeID~=nav.source.learningRecipeID then return nil,"STALE_ANNORA_LEARNING_OR_APPROACH" end
  local resolver=JLP:GetModule("SourceResolver")
  if not resolver or not resolver:VerifyNavigationWaypoint("CURRENT_STEP",nav.source) then return nil,"ANNORA_CANONICAL_REVALIDATION_FAILED" end
  return nav.source
 end
 if step.ordinaryAnvil or step.materialService or step.materialSupply or step.skinningSource or step.miningSource or step.herbalismSource then
  local refreshed=self:ForStep(key,step)
  local current=refreshed and refreshed.source
  if not current or current.serviceID~=nav.source.serviceID or current.nav.mapID~=nav.source.nav.mapID or
     current.nav.x~=nav.source.nav.x or current.nav.y~=nav.source.nav.y then return nil,"STALE_SUPPLY_NAVIGATION" end
 end
 -- The cached navigation must still match the original scalar source
 -- identity, even when the original source table was edited in place.
 local pinned=nav.sourceIdentity
 if pinned and (pinned.serviceID~=nav.source.serviceID or
    pinned.mapID~=nav.source.nav.mapID or pinned.x~=nav.source.nav.x or
    pinned.y~=nav.source.nav.y or pinned.recipeID~=nav.source.recipeID or
    pinned.materialItemID~=nav.source.materialItemID or pinned.materialRequired~=nav.source.materialRequired or
    pinned.teachingItemID~=nav.source.teachingItemID) then
  return nil,"STALE_CANONICAL_SOURCE_SNAPSHOT" end
 local retrievingPattern=step.patternAcquisition and step.patternAcquisition.status=="RETRIEVE_PATTERN_FROM_BANK"
 local recipeLearning=not retrievingPattern and (step.kind=="learn" or (step.kind=="craft" and step.learned==false))
 if recipeLearning and step.recipeID~=nil then
  if nav.recipeID~=step.recipeID or
     (nav.reason~="CANONICAL_RECIPE_SOURCE" and
      nav.reason~="OWNER_CANONICAL_EXACT_RECIPE_TRAINER") then
   return nil,"STALE_RECIPE_NAVIGATION" end
  local refreshed=self:ForStep(key,step)
  local current=refreshed and refreshed.source
  local old=nav.source
  if not refreshed or refreshed.waypointQualified~=true or
      refreshed.recipeID~=step.recipeID or not eligible(current) or
      not current.serviceID or not old.serviceID or
      current.serviceID~=old.serviceID or
      current.nav.mapID~=old.nav.mapID or
      current.nav.x~=old.nav.x or current.nav.y~=old.nav.y then
   return nil,"STALE_RECIPE_NAVIGATION" end
 elseif recipeLearning and step.recipeID==nil and nav.recipeID~=nil then
  -- An old recipe-specific waypoint cannot become a generic trainer route.
  return nil,"STALE_RECIPE_NAVIGATION" end
 local resolver=JLP:GetModule("SourceResolver")
 if not resolver or type(resolver.VerifyNavigationWaypoint)~="function" then
  -- Generic canonical owner services may be installed without the optional
  -- source-verifier adapter. Do not broaden this fallback to recipe learning.
  if recipeLearning and step.recipeID~=nil then
   return nil,"CANONICAL_SOURCE_REVALIDATION_UNAVAILABLE" end
  return nav.source
 end
 local ok,verified,why=pcall(resolver.VerifyNavigationWaypoint,resolver,"CURRENT_STEP",nav.source)
 if not ok or verified~=true then
  return nil,why or "CANONICAL_SOURCE_REVALIDATION_FAILED" end
 return nav.source
end
local function supplySourceContext(key,step,source)
 local tagged={};for field,value in pairs(source)do tagged[field]=value end
 tagged.workflowProfessionKey=key;source=tagged
 local supply=step and step.materialSupply
 local shared=supply and JLP:GetModule("GatheringSharedMapState")
 local snapshot=shared and shared:GetSnapshot()
 local goal=snapshot and snapshot.supplyGoal
 if goal and goal.origin=="AUTOMATIC_PLAN" and goal.itemID==supply.itemID and goal.required==supply.required and
    (key==goal.ownerProfession and step.recipeID==goal.ownerRecipeID or key==goal.professionKey) then
  local pinned={};for k,v in pairs(source)do pinned[k]=v end
  pinned.supplyOwnerToken=goal.ownerToken
  return pinned
 end
 return source
end
-- Exposes the EXISTING owner/Travel/Tom path, never an independent waypoint.
-- UI must supply fresh, explicit click context and the owner revalidates it.
function M:Request(key,step,context)
 local prerequisite=prerequisiteTravelStep(key)
 if prerequisite then return false,prerequisite.terminalReason end
 if type(context)~="table" or context.explicit~=true then
  return false,"EXPLICIT_USER_CLICK_REQUIRED" end
 local source,reason=checkHandoff(self,key,step)
 if not source then return false,reason end
 local service=JLP:GetModule("UnifiedDestinationNavigation")
 if not service or type(service.Request)~="function" then
  return false,"UNIFIED_NAVIGATION_UNAVAILABLE" end
 return service:Request("CURRENT_STEP",supplySourceContext(key,step,source),context)
end
-- Automatic Current Step updates must pass the same recipe/source/coordinate
-- preflight as Request. Stop/Pause, manual waypoint and plan-revision rules
-- remain owned by the existing UnifiedDestinationNavigation/owner.
function M:Sync(key,step,context)
 local prerequisite=prerequisiteTravelStep(key)
 if prerequisite then return false,prerequisite.terminalReason end
 if type(context)~="table" then return false,"INVALID_CONTEXT" end
 local source,reason=checkHandoff(self,key,step)
 if not source then return false,reason end
 local service=JLP:GetModule("UnifiedDestinationNavigation")
 if not service or type(service.SyncCurrentStep)~="function" then
  return false,"UNIFIED_CURRENT_STEP_SYNC_UNAVAILABLE" end
 return service:SyncCurrentStep(supplySourceContext(key,step,source),context)
end
JLP:RegisterModule("CurrentStepTravelBridge",M)
