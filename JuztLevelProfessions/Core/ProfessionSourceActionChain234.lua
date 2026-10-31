local _,JLP=...
-- P0-234: one evidence-separated next-action REVIEW for all twelve professions.
-- Reads the existing source modules, never creates a competing Planner, route,
-- secure click, or world waypoint. Read-only does NOT mean 'known learned'.
local M={contract="JLP-P0-234-TWELVE-PROFESSION-SOURCE-ACTION-CHAIN",
 readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
local keys={ALCHEMY="PRIMARY",BLACKSMITHING="PRIMARY",ENGINEERING="PRIMARY",
 LEATHERWORKING="PRIMARY",TAILORING="PRIMARY",ENCHANTING="PRIMARY",
 COOKING="SECONDARY",FIRST_AID="SECONDARY",HERBALISM="GATHER",
 MINING="GATHER",SKINNING="GATHER",FISHING="FISH"}
local function whole(n) return type(n)=="number" and n==n and n==math.floor(n) and n>=0 and n<=300 end
local function copyMaterials(rows)
 local out={}
 for _,m in ipairs(type(rows)=="table" and rows or {}) do
  if type(m.itemID)=="number" then
   out[#out+1]={itemID=m.itemID,perCraft=m.perCraft or m.quantity,
    bagsKnown=m.bagsKnown==true,bags=m.bagsKnown==true and m.bags or nil,
    missing=m.bagsKnown==true and m.missing or nil,readOnly=true}
  end
 end
 return out
end
local function base(key,skill)
 return {contract=M.contract,professionKey=key,professionType=keys[key],skill=skill,
  actionKind="verify",stage="VERIFY_SOURCE_GAP",sourceStatus="UNQUALIFIED_SOURCE_GAP",
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  verifiedSkillUps=0,expectedCrafts=nil,skillUpGuaranteed=false,
  learned=nil,learnedEvidence="UNKNOWN",materials={},inventoryKnown=false,
  teachingItemID=nil,teachingActorID=nil,actorCurrentAccess="UNKNOWN",
  navigationStatus="LOCATION_UNVERIFIED",waypointQualified=false,
  outputCreditAllowed=false,sourceRevision="P0-234-2026-10-24"}
end
local function eligibleRecipe(r)
 return r and r.eligibleReferenceCandidate==true and
    r.exactReagentsQualified==true and r.minimumSkill~=nil and
    r.referenceDifficulty~="GRAY_REFERENCE" and
    r.referenceDifficulty~="UNKNOWN"
end
local function selectRecipe(proof)
 local best,score
 local weight={ORANGE_REFERENCE=3,YELLOW_REFERENCE=2,GREEN_REFERENCE=1}
 for _,r in ipairs(proof and proof.recipes or {}) do
  if eligibleRecipe(r) then
   local n=(r.learned==true and 30 or r.learned==nil and 20 or 10)+
    (weight[r.referenceDifficulty] or 0)
   if not best or n>score or (n==score and r.recipeID<best.recipeID) then
    best,score=r,n
   end
  end
 end
 return best
end
-- Existing Forever secondary gate catalogue is a teaching/quest reference;
-- public vendor coordinates are NOT canonical Owner map coordinates.
-- Scoped negative source review. DB build is provenance, never a client gate.
-- Never add this conflict to the P0-233 confirmed source-window catalogue.
local function woolenBoltConflict(out)
 if out.professionKey~="TAILORING" or out.skill<75 or out.skill>=85 then return end
 local root=JLP.data and JLP.data.build70450Recipes
 local db=root and root.professions and root.professions.TAILORING
 local observed=nil
 if db and type(db.packed)=="string" then
  for line in db.packed:gmatch("[^\n]+") do
   if line:match("^2964%^") then
    local f={};for part in (line.."^"):gmatch("([^%^]*)%^") do f[#f+1]=part end
    observed={yellow=tonumber(f[4]),gray=tonumber(f[5]),
     reagents=f[10],name=f[12]};break
   end
  end
 end
 local conflict=observed and observed.yellow==70 and observed.gray==85 and
     observed.reagents=="2592:3" and observed.name=="Bolt of Woolen Cloth"
 out.supplementalSourceConflict234={recipeID=2964,recipe="Bolt of Woolen Cloth",
  sourceURL="https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth",
  publishedMin=75,publishedYellow=75,publishedGreen=77,publishedGray=85,
  sourceReagents={{itemID=2592,quantity=3}},dbYellow=observed and observed.yellow,
  dbGray=observed and observed.gray,
  status=conflict and "SOURCE_YELLOW_THRESHOLD_CONFLICT" or
    "INDEPENDENT_SOURCE_RECHECK_REQUIRED",readOnly=true,nativeDispatchAllowed=false}
 out.sourceStatus=out.supplementalSourceConflict234.status
 out.instruction="Verify Bolt of Woolen Cloth skill/difficulty against the live panel: published Forever and DB70450 source fields disagree; it is not an authorized progression window."
end
local function rankGateReference(out,options)
 local key=out.professionKey
 local data=JLP.data and JLP.data.foreverSecondaryLeveling
 local source=data and data.professions and data.professions[key]
 local gate
 for _,r in ipairs(source and source.gates or {}) do
  if r.skill==out.skill and (r.kind=="VENDOR_BOOK" or r.kind=="ARTISAN_QUEST") then
   gate=r;break
  end
 end
 if key=="FISHING" and out.skill==225 then
  gate=data and data.fishing and data.fishing.artisanQuest
 end
 if not gate then return end
 local f=options.currentFaction
 if gate.faction and f~=gate.faction then
  out.rankLearningLead={status=f and "FACTION_SOURCE_REJECTED" or "FACTION_UNOBSERVED",
   actorID=nil,teachingItemID=nil,waypointQualified=false}
  return
 end
 local actor=gate.verifiedVendors and f and gate.verifiedVendors[string.upper(f)]
 local id=actor and actor.npcID or gate.npcID
 out.rankLearningLead={status="PUBLIC_SOURCE_REFERENCE_NOT_CLIENT_ATTESTED",
  kind=gate.kind or "ARTISAN_QUEST",requiredSkill=gate.skill,
  name=gate.name,teachingItemID=gate.itemID,questID=gate.questID,
  actorID=id,actorName=actor and actor.npcName or gate.npcName,
  actorZone=actor and actor.zone or gate.zone,
  faction=gate.faction or f,sourceURL=gate.itemSourceURL or gate.questSourceURL or gate.questURL,
  waypointQualified=false,currentAccess="UNKNOWN",vendorStock="UNKNOWN"}
end
local function verifyRank(out,cap,options)
 if whole(cap) and cap<300 and out.skill>=cap then
  out.stage="VERIFY_RANK_OR_ARTISAN_QUEST"
  out.actionKind="verify"
  out.instruction="Verify the current profession skill cap and its rank/quest requirement before continuing."
  out.rankCapObservedInput=cap
  rankGateReference(out,options or {})
  return true
 end
 return false
end
local function setKnownMaterials(out,materials)
 out.materials=copyMaterials(materials)
 if #out.materials==0 then return false,false end
 local unknown=false;local shortages=false
 for _,m in ipairs(out.materials) do
  if not m.bagsKnown then unknown=true
  elseif type(m.missing)=="number" and m.missing>0 then shortages=true end
 end
 out.inventoryKnown=not unknown
 return unknown,shortages
end
local function sourceLearning(out,key,options)
 if not out.recipeID or not out.recipe then return end
 local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
 if not bridge or type(bridge.ForRecipe)~="function" then return end
 local ok,source=pcall(bridge.ForRecipe,bridge,key,out.recipeID,out.recipe,options.currentFaction)
 if not ok or type(source)~="table" then return end
 out.learningSourceReview=source
 out.learningSourceState=source.state or "UNKNOWN"
 out.teachingItemCount=source.teachingItemCount or 0
 -- Never infer live vendor stock or convert a research actor into a waypoint.
 out.navigationStatus="LOCATION_UNVERIFIED";out.waypointQualified=false
end
function M:AtSkill(key,skill,options)
 key=tostring(key or ""):upper();options=type(options)=="table" and options or {}
 if not keys[key] or not whole(skill) or skill<1 or skill>=300 then
  return nil,"INVALID_PROFESSION_OR_SKILL" end
 local out=base(key,skill)
 if keys[key]=="PRIMARY" then
  local source=JLP:GetModule("ForeverPrimarySourceWindows233")
  local ok,proof=false,nil
  if source and type(source.AtSkill)=="function" then ok,proof=pcall(source.AtSkill,source,key,skill,options) end
  local recipe=ok and type(proof)=="table" and selectRecipe(proof) or nil
  out.primarySourceWindow233=type(proof)=="table" and proof or nil
  -- P0-235: exact additional spell windows are only used if earlier planner
  -- evidence has no qualified candidate. No competing Current Step publisher.
  local additional=JLP:GetModule("ForeverProgressionWindows235")
  local alternative,alternativeReview=nil,nil
  if additional and type(additional.Select)=="function" then
   local more,value=pcall(additional.Select,additional,key,skill,options)
   if more and type(value)=="table" then alternative,alternativeReview=value,nil end
   -- pcall delivers the first return (winner) as value. Preserve an explicit
   -- separate review even when there are no active candidates.
   local reviewed,full=pcall(additional.AtSkill,additional,key,skill,options)
   if reviewed and type(full)=="table" then out.primaryAlternatives235=full end
  end
  if not recipe and alternative then recipe={recipeID=alternative.recipeID,
   recipe=alternative.recipe,sourceURL=alternative.sourceURL,
   sourceStatus=alternative.sourceStatus,
   referenceDifficulty=alternative.referenceDifficulty,
   minimumSkill=alternative.minimumSkill,learned=alternative.learned,
   learnedEvidence="INPUT_ADVISORY_NOT_LIVE_RECEIPT",
   reagentsPerCraft=alternative.reagentsPerCraft}
   out.sourceAlternative235=true
  end
  if recipe then
   out.recipeID=recipe.recipeID;out.recipe=recipe.recipe
   out.sourceURL=recipe.sourceURL
   out.sourceStatus=recipe.sourceStatus
   out.referenceDifficulty=recipe.referenceDifficulty
   out.requiredProfessionSkill=recipe.minimumSkill
   out.learned=recipe.learned;out.learnedEvidence=recipe.learnedEvidence
   local unknown,short=setKnownMaterials(out,recipe.reagentsPerCraft)
   if recipe.learned==false then out.stage="VERIFY_LEARNING_SOURCE";out.actionKind="learn"
   elseif recipe.learned~=true then out.stage="VERIFY_LEARNED_STATE"
   elseif unknown then out.stage="VERIFY_BAG_COUNTS"
   elseif short then out.stage="REVIEW_MANUAL_ACQUISITION";out.actionKind="acquire"
   else out.stage="REVIEW_MANUAL_ONE_CRAFT" end
   out.instruction="Verify "..recipe.recipe.." in the current profession panel and follow the documented reagent requirement; independently confirm any actual skill gain."
   sourceLearning(out,key,options)
   -- Forever Alchemy source publishes Merchant's Favor + Friendly access,
   -- but does not prove a specific faction NPC, available stock or waypoint.
   if key=="ALCHEMY" and recipe.recipeID==1250784 then
    out.publicLearningLead={mode="REPUTATION_VENDOR",requiredStanding="Friendly",
     reputation=options.currentFaction=="Horde" and "Durotar Supply and Logistics" or
       options.currentFaction=="Alliance" and "Azeroth Commerce Authority" or nil,
     merchantFavor=120,actorID=nil,stock="UNKNOWN",
     sourceURL="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",
     navigationQualified=false}
   end
  else
   out.sourceStatus="PRIMARY_SOURCE_WINDOW_NOT_QUALIFIED"
   out.instruction="Verify an accessible recipe with current skill color and a documented learning source; the current source windows do not prove one."
   woolenBoltConflict(out)
  end
 elseif key=="FIRST_AID" then
  local fa=JLP:GetModule("ForeverFirstAidArtisan232")
  local ok,f=false,nil
  if fa and type(fa.AtAnySkill)=="function" then ok,f=pcall(fa.AtAnySkill,fa,skill,options) end
  if ok and type(f)=="table" then
   out.recipeID=f.recipeID;out.recipe=f.recipe
   out.sourceStatus=f.sourceProvenance or f.sourceStatus;out.sourceURL=f.reference or f.recipeURL
   out.learned=f.learned;out.learnedEvidence=f.learnedSource
   out.materials=copyMaterials(f.perCraftMaterials)
   out.inventoryKnown=f.bagsKnown==true
   out.stage=f.stage or out.stage
   out.actionKind=f.actionKind or "verify"
   out.instruction=f.nextAction
   out.learningSourceReview=f.learningSourceReview or f.surgeon
   out.expectedCrafts=nil;out.outputCreditAllowed=false
  end
 else
  local audit=JLP:GetModule("ProfessionProgressionCoverage228")
  local ok,f=false,nil
  if audit and type(audit.AtSkill)=="function" then ok,f=pcall(audit.AtSkill,audit,key,skill) end
  if ok and type(f)=="table" then
   out.sourceStatus=f.sourceLevel or "UNQUALIFIED_SOURCE_GAP"
   out.recipeID=f.recipeID;out.recipe=f.recipe
   out.sourceURL=f.recipeSourceURL
   out.resourceReference=f.resource
   out.sourceProvenance=f.sourceProvenance
  end
  if key=="FISHING" then
   out.stage="VERIFY_FISHING_AREA_AND_RANK"
   out.instruction="Choose a documented Fishing area and verify catch eligibility, current rank and actual skill gains; no pool spawn or waypoint is assumed."
  elseif keys[key]=="GATHER" then
   out.stage="VERIFY_GATHERING_NODE_OR_MOB"
   out.instruction="Review a source-referenced resource/mob and its skill requirement on the existing Gathering Map; confirm a reachable spawn manually."
  else
   out.stage="VERIFY_GUIDE_RECIPE_ACCESS"
   out.instruction="Check the referenced guide recipe and its trainer/manual/quest requirement; guide shopping quantities are not per-craft receipts."
  end
 end
 -- A rank ceiling always takes precedence over an assumed ordinary craft.
 verifyRank(out,options.maxSkill,options)
 return out
end
-- Called ONLY from explicit PlanTo300. This is a gap/action work register,
-- never a substitute for the actual optimizer route or evidence of skill-ups.
function M:Continuity(key,skill,options)
 key=tostring(key or ""):upper();options=type(options)=="table" and options or {}
 if not keys[key] or not whole(skill) or skill<1 or skill>300 then
  return nil,"INVALID_PROFESSION_OR_START" end
 local out={contract=self.contract,professionKey=key,fromSkill=skill,toSkill=300,
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  complete1300=false,verifiedSkillUps=0,segments={},gapCount=0,
  firstGap=nil,actionAtStart=nil,scenarioBudget=nil,
  navigationStatus="LOCATION_UNVERIFIED"}
 if skill==300 then return out end
 out.actionAtStart=self:AtSkill(key,skill,options)
 local audit=JLP:GetModule("ProfessionProgressionCoverage228")
 local ok,coverage=false,nil
 if audit and type(audit.Audit)=="function" then ok,coverage=pcall(audit.Audit,audit,key,skill,300) end
 if ok and type(coverage)=="table" then
  out.earlierSourceCoverage228=coverage
  out.gapCount=coverage.unverifiedPositions or 0
  out.firstGap=coverage.firstUnverifiedSourceSkill
  for _,r in ipairs(coverage.segments or {}) do
   local gap=not r.sourceLevel or r.sourceLevel=="UNQUALIFIED_RESEARCH_WINDOW" or
       r.sourceLevel=="UNVERIFIED_SOURCE_GAP"
   out.segments[#out.segments+1]={fromSkill=r.fromSkill,toSkill=r.toSkill,
    recipeID=r.recipeID,recipe=r.recipe,sourceLevel=r.sourceLevel,
    skillGainGuaranteed=false,readOnly=true,
    requiredNextCheck=gap and "QUALIFY_RECIPE_OR_RESOURCE" or
      "VERIFY_LEARNING_MATERIALS_AND_CURRENT_SKILL_COLOR",
    nativeDispatchAllowed=false,navigationStatus="LOCATION_UNVERIFIED"}
  end
 end
 -- Optional, EXPLICIT user-owned scenario only. Existing BOM performs all
 -- actual source/yield/learned/unknown inventory checks; no competing ledger.
 if type(options.scenarioRoute234)=="table" then
  local budget=JLP:GetModule("ProfessionSourceBudget230")
  if budget and type(budget.ReviewRoute)=="function" then
   local good,value=pcall(budget.ReviewRoute,budget,key,options.scenarioRoute234,{
    learnedRecipes=options.learnedRecipes,inventory=options.inventory,
    prices=options.prices,currentFaction=options.currentFaction})
   if good and type(value)=="table" then out.scenarioBudget=value end
  end
 end
 return out
end
JLP:RegisterModule("ProfessionSourceActionChain234",M)
