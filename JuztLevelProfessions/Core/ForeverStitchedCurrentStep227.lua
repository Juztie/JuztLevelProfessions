local _,JLP=...
-- P0-227: source-backed, read-only bridge from a curated early research
-- segment to an actual Current Step review. A candidate is neither a
-- verified skill-up route nor native/UI authorization. Re-evaluate every call.
local M={contract="JLP-STITCHED-CURRENT-REVIEW-227",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local function integer(v)
 return type(v)=="number" and v==v and v>0 and v<math.huge and v==math.floor(v)
end
local function whole(v)
 return type(v)=="number" and v==v and v>=0 and v<math.huge and v==math.floor(v)
end
-- Learned-state is only classified as OBSERVED when the current panel's
-- read-only identity and recipe-list API are stable before and after the call.
local function learnedState(key,skill,recipeID)
 local api=JLP:GetModule("ProfessionAPI")
 local get=api and api.GetReadOnlyProfessionObservation
 if type(get)~="function" then return nil,"PANEL_UNAVAILABLE" end
 local ok,p=pcall(get,api)
 if not ok or type(p)~="table" or p.observed~=true or
  p.professionKey~=key or p.skill~=skill or
  type(p.observationToken)~="string" or p.observationToken=="" then
  return nil,"PANEL_NOT_VERIFIED"
 end
 local t=C_TradeSkillUI
 local all=t and t.GetAllRecipeIDs
 local info=t and t.GetRecipeInfo
 if type(all)~="function" or type(info)~="function" then return nil,"RECIPE_API_UNAVAILABLE" end
 local good,list=pcall(all)
 if not good or type(list)~="table" then return nil,"RECIPE_LIST_UNAVAILABLE" end
 -- 1,600 is the existing reader's upper bound; a truncated list is not a
 -- reliable negative learned proof.
 local inList=false
 for i=1,math.min(#list,1600) do if list[i]==recipeID then inList=true;break end end
 if #list>1600 then return nil,"RECIPE_LIST_TRUNCATED" end
 local known=nil
 if inList then
  local success,detail=pcall(info,recipeID)
  if success and type(detail)=="table" and type(detail.learned)=="boolean" and
    (detail.recipeID==nil or detail.recipeID==recipeID) then
   known=detail.learned
  end
 end
 local stable,p2=pcall(get,api)
 if not stable or type(p2)~="table" or p2.observed~=true or
  p2.professionKey~=key or p2.skill~=skill or p2.observationToken~=p.observationToken or
  not C_TradeSkillUI or C_TradeSkillUI.GetAllRecipeIDs~=all or
  C_TradeSkillUI.GetRecipeInfo~=info then
  return nil,"PANEL_CHANGED"
 end
 if not inList then return nil,"RECIPE_NOT_IN_CURRENT_LIST" end
 if known==nil then return nil,"LEARNED_STATE_UNKNOWN" end
 return known,"CURRENT_PANEL_STABLE"
end
local function materialStates(rows)
 local inv=JLP:GetModule("Inventory")
 local result={};local anyUnknown=false;local needed=0
 for _,r in ipairs(rows or {}) do
  -- Source validation happens in ForeverStitchedSourceRoutes226, but the
  -- bridge validates its own copy to refuse a malformed/mutated result.
  if type(r)~="table" or not integer(r.itemID) or not integer(r.perCraft) then
   return nil,"INVALID_SOURCE_REAGENT"
  end
  local observed=nil
  if inv and type(inv.GetOwned)=="function" then
   local ok,value=pcall(inv.GetOwned,inv,r.itemID)
   if ok and type(value)=="table" and value.bagKnown==true and whole(value.bags) then
    observed=value.bags
   end
  end
  local missing=observed and math.max(0,r.perCraft-observed) or nil
  if missing==nil then anyUnknown=true else needed=needed+missing end
  result[#result+1]={itemID=r.itemID,perCraft=r.perCraft,required=r.perCraft,
   bagsKnown=observed~=nil,bags=observed,missing=missing,
   provenance="EXACT_FOREVER_DB70450_REAGENT_PER_CRAFT",readOnly=true}
 end
 if #result==0 then return nil,"SOURCE_REAGENTS_UNAVAILABLE" end
 local knownMissing=nil
 if not anyUnknown then knownMissing=needed end
 return result,anyUnknown and "INVENTORY_UNKNOWN" or
    (needed>0 and "MATERIALS_MISSING" or "MATERIALS_PRESENT"),knownMissing
end
local function travelStatus(key,recipeID,name,kind,materialReady)
 local bridge=JLP:GetModule("CurrentStepTravelBridge")
 local lookup=JLP:GetModule("RecipeSourcePlanningBridge")
 local evidence=lookup and type(lookup.ForRecipe)=="function" and
  lookup:ForRecipe(key,recipeID,name) or nil
 local step={kind=kind,recipeID=recipeID,recipeSourcePlanning=evidence,
  learned=kind=="learn" and false or nil,bagReady=materialReady==true,
  auctionPriceAvailable=false}
 -- Existing CurrentStepTravelBridge performs owner/recipe/canonical checks;
 -- this is a description only and NEVER calls owner.Navigate/SyncCurrentStep.
 local nav=bridge and type(bridge.ForStep)=="function" and
  bridge:ForStep(key,step) or nil
 return {owner="IntegratedDestinationOwner",engine="IntegratedTravelEngine",
  arrow="IntegratedJuztTom",status=nav and nav.status or "LOCATION_UNVERIFIED",
  reason=nav and nav.reason or "CANONICAL_OWNER_UNAVAILABLE",
  waypointQualified=nav and nav.waypointQualified==true or false,
  source=nav and nav.waypointQualified==true and nav.source or nil,
  userActionRequired=true,automaticMovement=false,readOnly=true},evidence
end
function M:Review(key,skill)
 local stitch=JLP:GetModule("ForeverStitchedSourceRoutes226")
 if not stitch or type(stitch.AtSkill)~="function" then return nil,"STITCH_MODULE_UNAVAILABLE" end
 local ok,source=pcall(stitch.AtSkill,stitch,key,skill)
 if not ok or type(source)~="table" then return nil,"SOURCE_REFERENCE_UNAVAILABLE" end
 local result={contract=self.contract,professionKey=key,skill=skill,
  researchSource=source.contract,sourceGap=source.sourceGap==true,
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  clientRouteQualified=false,craftCountForecast=nil,materialBudgetForecast=nil,
  learnedObserved=false,skillUpReceiptObserved=false,craftReceiptObserved=false,
  navigationQualified=false,stepKind="verify",nextRequiredEvidence=source.nextRequiredEvidence}
 local candidate=source.candidates and source.candidates[1]
 if source.sourceGap or type(candidate)~="table" then
  result.stage="VERIFY_RESEARCH_SOURCE"
  result.reason=source.reason or "NO_SOURCE_QUALIFIED_CURRENT_RECIPE"
  return result
 end
 local rows,state,missing=materialStates(candidate.reagentsPerCraft)
 if not rows then
  result.sourceGap=true;result.stage="VERIFY_RESEARCH_SOURCE"
  result.reason=state
  return result
 end
 local learned,learnedProof=learnedState(key,skill,candidate.recipeID)
 result.recipeID=candidate.recipeID;result.recipe=candidate.recipe
 result.recipeSourceURL=candidate.recipeSourceURL;result.rangeEvidence=candidate.rangeEvidence
 result.minimumSkillEvidence=candidate.sourceMinimumSkill
 result.referenceYellow=candidate.referenceYellow;result.referenceGreen=candidate.referenceGreen
 result.referenceGray=candidate.referenceGray;result.researchWindowSource=candidate.researchWindowSource
 result.outputEvidence=candidate.outputEvidence
 result.materials=rows;result.materialObservationState=state
 result.missingKnown=missing~=nil;result.missing=missing
 result.learned=learned;result.learnedEvidence=learnedProof
 result.learnedObserved=type(learned)=="boolean"
 if learned==false then
  result.stage="LEARN_RECIPE";result.nextAction="Verify exact source and learn "..candidate.recipe.." manually."
 elseif learned==nil then
  result.stage="VERIFY_RECIPE_LEARNED"
  result.nextAction="Open the correct profession panel and verify whether "..candidate.recipe.." is learned."
 elseif state=="INVENTORY_UNKNOWN" then
  result.stage="VERIFY_INVENTORY"
  result.nextAction="Verify bag reagent counts for one "..candidate.recipe.."."
 elseif state=="MATERIALS_MISSING" then
  result.stage="ACQUIRE_MATERIALS"
  result.nextAction="Acquire the verified missing reagents for one "..candidate.recipe.."; reassess inventory."
 else
  result.stage="VERIFY_LIVE_DIFFICULTY"
  result.nextAction="Check current recipe difficulty and prerequisites before one manual "..candidate.recipe.." craft."
  local factsModule=JLP:GetModule("ProfessionPlanningFacts")
  if factsModule and type(factsModule.Observe)=="function" then
   local good,facts=pcall(factsModule.Observe,factsModule,key,candidate.recipeID)
   if good and type(facts)=="table" and facts.observed==true and facts.learned==true and
     type(facts.skillup)=="table" and facts.skillup.canSkillUp==true and
     facts.skillup.tier~="GRAY" then
    result.stage="REVIEW_MANUAL_ONE_CRAFT"
    result.nextAction="Review one MANUAL "..candidate.recipe.." craft, then observe actual craft and skill-up separately."
   end
  end
 end
 local targetKind=result.stage=="LEARN_RECIPE" and "learn" or
  (result.stage=="VERIFY_INVENTORY" or result.stage=="ACQUIRE_MATERIALS") and
  "acquire-material" or "craft"
 local nav,sourcePlanning=travelStatus(key,candidate.recipeID,candidate.recipe,targetKind,
  state=="MATERIALS_PRESENT")
 result.navigation=nav
 result.recipeSourcePlanning=sourcePlanning
 result.navigationQualified=nav.waypointQualified==true
 -- A derived preview is not an authorization for automatic Current Step sync
 -- or any native route, even if its qualified canonical owner exists.
 result.automaticNavigationAllowed=false
 return result
end
JLP:RegisterModule("ForeverStitchedCurrentStep227",M)
