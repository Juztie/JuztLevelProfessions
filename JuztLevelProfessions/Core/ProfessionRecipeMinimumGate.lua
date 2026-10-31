local _, JLP = ...
-- Planning-only access gate. The DB70450 SkillLineAbility MinRank is nearly
-- universally 1: it is NOT the actual recipe learning/crafting requirement.
-- A cached LEARNED flag or a synthetic all-learned fixture cannot authorize
-- future-skill usage of an otherwise unqualified DB-only recipe.
local M={contract="JLP-RECIPE-ACCESS-MINIMUM-192",readOnly=true,
  nativeDispatchAllowed=false,executionEligible=false}
local function skill(v)
 local n=tonumber(v)
 return n and n==math.floor(n) and n>=0 and n<=300 and n or nil
end
-- P0-218: Blacksmithing/Leatherworking source minima MUST be reconciled
-- against the exact DB70450 recipe + source-authored reagent reference.
-- Route windows and DB difficulty cutoffs are not learning requirements.
-- This is a read-only, revocable source join; no client or native permission.
local function exactLegacyPrimaryMinimum(key,id,display)
 if key~="BLACKSMITHING" and key~="LEATHERWORKING" then return nil end
 local selected=JLP.data and JLP.data.foreverSelectedRecipeFacts194
 local fact=selected and selected.rows and selected.rows[key] and selected.rows[key][id]
 local source=JLP.data and JLP.data.publicCraftingRouteEvidence
 local db=JLP.data and JLP.data.build70450Recipes
 local packed=db and db.professions and db.professions[key] and db.professions[key].packed
 if not (fact and source and source.professions and source.professions[key] and
   type(packed)=="string" and type(display)=="string" and fact.name==display and
   type(fact.source)=="string" and fact.source:find(
     "https://www.wowhead.com/forever/spell="..tostring(id).."/",1,true)==1) then
  return nil
 end
 local minimum=skill(fact.requiredSkill)
 if minimum==nil then return nil end
 local route,found=nil,0
 for _,r in ipairs(source.professions[key].recipes or {}) do
  if r.recipeID==id then route=r;found=found+1 end
 end
 if found~=1 or not route or route.name~=display or
  route.requiredSkill~=minimum or type(route.reagents)~="table" then return nil end
 local dbLine,dbCount=nil,0
 for line in packed:gmatch("[^\n]+") do
  if tonumber(line:match("^(%d+)%^"))==id then dbLine=line;dbCount=dbCount+1 end
 end
 if dbCount~=1 then return nil end
 local fields={}
 for v in (dbLine.."^"):gmatch("([^%^]*)%^") do fields[#fields+1]=v end
 if #fields~=12 or fields[12]~=display then return nil end
 local expected,count={},0
 for token in fields[10]:gmatch("[^,]+") do
  local item,qty=token:match("^(%d+):(%d+)$")
  item,qty=tonumber(item),tonumber(qty)
  if not item or not qty or item<=0 or qty<=0 or expected[item] then return nil end
  expected[item]=qty;count=count+1
 end
 if count==0 or count~=#route.reagents then return nil end
 for _,m in ipairs(route.reagents) do
  if expected[m.itemID]~=m.quantity then return nil end
  expected[m.itemID]=nil
 end
 if next(expected) then return nil end
 return {minimum=minimum,sourceURL=fact.source,recipeID=id,
  evidence="FOREVER_SELECTED_SPELL_AND_DB70450_ROUTE_PARITY",
  navigationQualified=false,nativeDispatchAllowed=false}
end
-- P0-219: Build-neutral exact spell-page minimum, independent of historical
-- recipe difficulty, yellow/grey cutoffs and route-window placement.
-- Fail closed if ANY canonical source input drifts. This proof is never
-- native or navigation authority; a missing DB/route remains UNKNOWN.
local function exactHighSkill219(key,recipe)
 local facts=JLP.data and JLP.data.foreverExactBSLWSourceSkills219
 if not (facts and facts.contract=="JLP-EXACT-BSLW-FOREVER-SPELL-SKILLS-219") then return nil,false end
 local row=facts.rows and facts.rows[key] and facts.rows[key][recipe.recipeID]
 if not row then return nil,false end
 local db=JLP.data and JLP.data.build70450Recipes
 local public=JLP.data and JLP.data.publicCraftingRouteEvidence
 if not (db and public and db.professions and public.professions) then return nil,true end
 local packed=db.professions[key] and db.professions[key].packed
 local routes=public.professions[key] and public.professions[key].recipes
 local id=tonumber(recipe.recipeID)
 if not (type(packed)=="string" and type(routes)=="table" and
   type(recipe.recipe or recipe.recipeName)=="string") then return nil,true end
 local display=recipe.recipe or recipe.recipeName
 if row.recipeID~=id or row.name~=display or skill(row.requiredSkill)==nil or
   type(row.source)~="string" or
   row.source:find("https://www.wowhead.com/forever/spell="..tostring(id).."/",1,true)~=1 or
   row.waypointQualified~=false or facts.nativeDispatchAllowed~=false then return nil,true end
 local matching,count=nil,0
 for _,r in ipairs(routes) do
  if r.recipeID==id then matching=r;count=count+1 end
 end
 if count~=1 or not matching or matching.name~=display or
   skill(matching.requiredSkill)~=row.requiredSkill or
   type(matching.reagents)~="table" then return nil,true end
 local line,occurrences=nil,0
 for ln in packed:gmatch("[^\n]+") do
  if tonumber(ln:match("^(%d+)%^"))==id then line=ln;occurrences=occurrences+1 end
 end
 if occurrences~=1 then return nil,true end
 local fields={}
 for v in (line.."^"):gmatch("([^%^]*)%^") do fields[#fields+1]=v end
 if #fields~=12 or fields[12]~=display then return nil,true end
 -- The historical DB output-yield can differ; verify identity only and
 -- retain source-yield as an unelevated reference value.
 local outputID=tonumber(fields[11]:match("^(%d+):"))
 if outputID~=row.outputItemID then return nil,true end
 local wanted,n={},0
 for token in fields[10]:gmatch("[^,]+") do
  local item,qty=token:match("^(%d+):(%d+)$")
  item,qty=tonumber(item),tonumber(qty)
  if not item or not qty or item<1 or qty<1 or wanted[item] then return nil,true end
  wanted[item]=qty;n=n+1
 end
 if n==0 or n~=#matching.reagents then return nil,true end
 for _,mat in ipairs(matching.reagents) do
  if wanted[mat.itemID]~=mat.quantity then return nil,true end
  wanted[mat.itemID]=nil
 end
 if next(wanted)~=nil then return nil,true end
 local actor=row.trainerActor
 -- An exact Forever NPC page may establish ID/name/faction without proving
 -- stock, a waypoint, or live teacher entitlement. Drift hides actor only.
 if type(actor)=="table" and not (type(actor.npcID)=="number" and
   type(actor.name)=="string" and actor.faction=="Horde" and
   actor.stockVerified==false and actor.coordinateQualified==false and
   type(actor.source)=="string" and actor.source:find(
     "https://www.wowhead.com/forever/npc="..tostring(actor.npcID).."/",1,true)==1) then
  actor=nil
 end
 return {minimum=row.requiredSkill,source="FOREVER_EXACT_SPELL_DB_ROUTE_MINIMUM_219",
  sourceURL=row.source,sourceProofCurrent=true,exactPrimaryDBRouteQualified=true,
  sourceYieldReference=row.sourceYield,yieldAuthorizesMaterialCredit=false,
  learningSourceStatus=row.acquisition,trainerIdentityReference=actor,
  nativeDispatchAllowed=false,
  waypointQualified=false,trainerLocationQualified=false,
  advisory=true,referenceKind="EXACT_SPELL_ID_REAGENTS_SKILL",
  -- A historical DB grey cutoff at/below a documented recipe learning
  -- minimum is a DATA CONFLICT, not proof of a viable leveling cast.
  -- Keep the strict learning floor; never infer client skill-up from DB grey.
  historicalDifficultyConflict=tonumber(fields[5])~=nil and
   tonumber(fields[5])<=row.requiredSkill or false,
  historicalGreyReference=tonumber(fields[5]),
  historicalRouteWindowConflict=recipe.route==true and
   skill(recipe.routeSkillMin)~=nil and skill(recipe.routeSkillMin)~=row.requiredSkill},true
end
function M:Resolve(key,recipe)
 if type(recipe)~="table" or not tonumber(recipe.recipeID) then
  return nil,"RECIPE_ID_UNKNOWN" end
 -- Exact current-task pattern linkage plus Forever minimum evidence takes
 -- precedence over the contradicted, older product-category value.
 if key=="TAILORING" then
  local q=JLP:GetModule("TailoringRecipeQualification")
  local f=q and q.GetVendorPatternContract and q:GetVendorPatternContract(JLP.data and JLP.data.tailoring,recipe.recipeID)
  if f then return {minimum=f.minimum,source="FOREVER_PATTERN_DB2_70532",
   sourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
   categoryMinimumConflict=f.categoryMinimumConflict,liveVerified=false,
   advisory=true,nativeDispatchAllowed=false},nil end
 end
 if key=="LEATHERWORKING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local f=facts and facts:GetLeatherworkingContract(recipe.recipeID)
  if f then return {minimum=f.minimum,source="LEATHERWORKING_70532_QUALIFIED_FLOOR",sourceURL=f.minimumURL,exactLearningMinimum=f.learningMinimum,learningMinimumStatus=f.minimumStatus,readOnly=true}end
 end
 if key=="ENGINEERING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local f=facts and facts:GetEngineeringContract(recipe.recipeID)
  if f then return {minimum=f.minimum,source="ENGINEERING_70532_QUALIFIED_FLOOR",sourceURL=f.minimumURL,exactLearningMinimum=f.learningMinimum,learningMinimumStatus=f.minimumStatus,readOnly=true}end
 end
 if key=="BLACKSMITHING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local f=facts and facts.GetBlacksmithingContract and facts:GetBlacksmithingContract(recipe.recipeID)
  if f then return {minimum=f.minimum,source="BLACKSMITHING_70532_QUALIFIED_FLOOR",sourceURL=f.minimumURL,
   exactLearningMinimum=f.learningMinimum,learningMinimumStatus=f.learningMinimum and f.minimumStatus or "UNKNOWN",readOnly=true}end
 end
 if key=="FIRST_AID" or key=="COOKING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local f=facts and facts:GetAlchemyContract(recipe.recipeID,key)
  if f then return {minimum=f.minimum,source=key.."_70532_SAFE_PLANNING_FLOOR",sourceURL=f.minimumURL,
   exactLearningMinimum=f.learningMinimum,learningMinimumStatus=f.minimumStatus,readOnly=true}end
 end
 if key=="ALCHEMY" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local f=facts and facts.GetAlchemyContract and facts:GetAlchemyContract(recipe.recipeID)
  if f then return {minimum=f.minimum,source="ALCHEMY_70532_QUALIFIED_FLOOR",sourceURL=f.minimumURL,
   actualLearningMinimum=f.learningMinimum,learningMinimumStatus=f.minimumStatus,
   advisory=true,liveVerified=false,nativeDispatchAllowed=false},nil end
 end
 if key=="ENCHANTING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local f=facts and facts.GetEnchantingContract and facts:GetEnchantingContract(recipe.recipeID)
  if f then return {minimum=f.minimum,source="ENCHANTING_70532_QUALIFIED_FLOOR",sourceURL=f.minimumURL,
   actualLearningMinimum=f.learningMinimum,learningMinimumStatus=f.learningMinimumStatus or f.minimumStatus,
   advisory=true,liveVerified=false,nativeDispatchAllowed=false},nil end
 end
 -- Explicit user-confirmed spell requirement supersedes category125.
 -- Keep conflict provenance visible; never label it LIVE or native authority.
 if key=="TAILORING" and tonumber(recipe.recipeID)==3839 then
  local q=JLP:GetModule("TailoringRecipeQualification")
  local fact=q and q.GetSilkContract and q:GetSilkContract(JLP.data and JLP.data.tailoring)
  if fact then return {minimum=100,source=fact.minimumAuthority,sourceURL=fact.sourceURL,
   categoryMinimumConflict=125,minimumSourceConflict=true,liveVerified=false,
   actualLearningMinimumKnown=true,trainerStockQualified=false,
   advisory=true,nativeDispatchAllowed=false},nil end
 end
 local exact219,attempted219=exactHighSkill219(key,recipe)
 if attempted219 then
  if exact219 then return exact219,nil end
  return nil,"SOURCE_RECEIPT_REVOKED_OR_INCOMPLETE_219"
 end
 local db=JLP.data and JLP.data.foreverRecipeMinimums192
 local ref=db and db.rows and db.rows[key] and db.rows[key][recipe.recipeID]
 local curated=JLP.data and JLP.data.foreverSelectedRecipeFacts193
 local newest=curated and curated.rows and curated.rows[key] and curated.rows[key][recipe.recipeID]
 -- Admit only an exact spell/profession identity with sourced skill facts.
 if newest and (type(newest.source)~="string" or not newest.source:match("^https://www%.wowhead%.com/forever/")) then newest=nil end
 local cross=JLP.data and JLP.data.foreverSelectedRecipeFacts194
 local qualified194=cross and cross.rows and cross.rows[key] and cross.rows[key][recipe.recipeID]
 if qualified194 and (type(qualified194.source)~="string" or
   not qualified194.source:match("^https://www%.wowhead%.com/forever/")) then qualified194=nil end
 -- P0-196: externally documented name-level guide minima. Accept only an
 -- exact case-sensitive identity joined to the DB70450 SPELL row, never a
 -- fuzzy name match or a recipe-learning/actor authority. External guide
 -- does not independently assert the ID; show that lower evidentiary tier.
 local guideData=JLP.data and JLP.data.foreverEngineeringGuideFacts196
 local guide=guideData and guideData.contract==
     "JLP-FOREVER-ENGINEERING-GUIDE-NAME-JOIN-196" and
     guideData.rows and guideData.rows[key] and guideData.rows[key][recipe.recipeID]
 if not (key=="ENGINEERING" and type(guide)=="table" and
     recipe.sourceBuild==70450 and recipe.recipe==guide.name and
     guide.recipeID==recipe.recipeID and
     guide.source==guideData.sourceURL and
     type(guide.source)=="string" and
     guide.source:match("^https://www%.wowhead%.com/forever/guide/professions/") and
     guide.evidenceKind=="FOREVER_GUIDE_NAME_JOIN_ONLY") then guide=nil end
 -- P0-217: a PRIMARY spell-page minimum is admissible only while the full
 -- exact-name, output, reagent and yield receipt remains valid. A curated
 -- name-level engineering guide is NOT an exact same-SpellID admission.
 local primary=JLP.data and JLP.data.foreverPrimaryRecipeParity212
 local primaryProof=primary and primary.rows and primary.rows[recipe.recipeID]
 local sourceName=recipe.recipe or recipe.recipeName
 local exactSkill=nil
 local verifiedProducer=nil
 if primaryProof and primaryProof.professionKey==key and primaryProof.recipeID==recipe.recipeID and
    primaryProof.recipeName==sourceName and
    primaryProof.status=="EXACT_FOREVER_SPELL_AND_DB70450_PARITY" and
    type(primaryProof.source)=="string" and
    primaryProof.source:find("https://www.wowhead.com/forever/spell="..tostring(recipe.recipeID),1,true)==1 and
    not (primary.conflicts and primary.conflicts[recipe.recipeID]) then
    local graph=JLP.GetModule and JLP:GetModule("CrossProfessionDependencyPlanner")
    if graph and type(graph.Resolve)=="function" then
      verifiedProducer=graph:Resolve(key,recipe.recipeID)
    end
    if verifiedProducer and verifiedProducer.primarySourceURL==primaryProof.source and
       verifiedProducer.recipeName==sourceName and
       verifiedProducer.outputItemID==primaryProof.outputItemID then
      exactSkill=skill(primaryProof.sourceSkillMinimum)
    end
 end
 local guideMinimum=guide and skill(guide.requiredSkill)
 local earlier=ref and skill(ref.requiredSkill)
 local latest=newest and skill(newest.requiredSkill)
 local source218=recipe.sourceBuild==70450 and
   exactLegacyPrimaryMinimum(key,recipe.recipeID,recipe.recipe or recipe.recipeName) or nil
 -- For Blacksmithing/Leatherworking the historical selected fact alone
 -- cannot grant source skill rights: exact spelling/reagent parity is required.
 local minimum194=qualified194 and skill(qualified194.requiredSkill)
 if key=="BLACKSMITHING" or key=="LEATHERWORKING" then
  -- Historical sparse adapters load the v194 facts alone. Preserve their
  -- read-only fallback but never call it the new strict DB/route receipt.
  -- When all three catalogues are available, invalid/parity-drifted facts
  -- are revoked instead of silently falling back to a weaker source.
  local public=JLP.data and JLP.data.publicCraftingRouteEvidence
  local db70450=JLP.data and JLP.data.build70450Recipes
  local display=recipe.recipe or recipe.recipeName
  if public and db70450 and type(display)=="string" then
   minimum194=source218 and source218.minimum or nil
  end
 end
 -- The strongest exact-source floor wins. Never label an older, stricter
 -- value as a v194 fact, and report disagreements across ALL source tiers.
 local precise=math.max(minimum194 or 0,latest or 0,earlier or 0,exactSkill or 0)
 if precise==0 then precise=nil end
 local authored=skill(recipe.requiredSkill)
 local route=recipe.route==true and skill(recipe.routeSkillMin) or nil
 -- Exact SpellID evidence outranks a lower-confidence name-join, even if
 -- the guide's required skill differs; expose any mismatch as conflict.
 local minimum=math.max(precise or guideMinimum or 0,authored or 0,route or 0)
 if minimum==0 and not (earlier==0 or latest==0 or minimum194==0 or authored==0 or route==0) then minimum=nil end
 local source,sourceURL=nil,nil
 if minimum then
  if exactSkill==minimum then source="FOREVER_EXACT_PRIMARY_SOURCE_MINIMUM";sourceURL=verifiedProducer.primarySourceURL
  elseif source218 and minimum194==minimum then
    source="FOREVER_EXACT_PRIMARY_DB_ROUTE_MINIMUM_218";sourceURL=source218.sourceURL
  elseif minimum194==minimum then source="FOREVER_SELECTED_RECIPE_MINIMUM_194";sourceURL=qualified194.source
  elseif latest==minimum then source="FOREVER_SELECTED_RECIPE_MINIMUM_193";sourceURL=newest.source
  elseif earlier==minimum then source="FOREVER_EXACT_SPELL_OR_ITEM";sourceURL=ref.source
  elseif authored==minimum then source="EXPLICIT_RECIPE_REQUIREMENT"
  elseif route==minimum then source="LEVELING_ROUTE_START_REFERENCE"
  elseif guideMinimum==minimum then source="FOREVER_GUIDE_NAME_JOIN_ADVISORY";sourceURL=guide.source end
 end
 local distinct={};local different=0
 for _,v in ipairs({earlier or -1,latest or -1,minimum194 or -1,exactSkill or -1}) do
  if v>=0 and not distinct[v] then distinct[v]=true;different=different+1 end
 end
 if minimum then
  return {minimum=minimum,source=source,sourceURL=sourceURL,
   guideRequiredSkill=guideMinimum,guideSpellIDNotExternallyVerified=guideMinimum~=nil,
   guideMinimumConflict=guideMinimum~=nil and precise~=nil and guideMinimum~=precise,
   exactPrimarySourceMinimum=exactSkill,
   exactPrimarySourceQualified=exactSkill~=nil,
   exactPrimaryDBRouteMinimum=source218 and source218.minimum or nil,
   exactPrimaryDBRouteQualified=source218~=nil,
   sourceProofCurrent=verifiedProducer~=nil,
   trainerNameReferences=exactSkill and primaryProof.trainerNames or nil,
   trainerLocationQualified=false,trainerStockQualified=false,
   referenceKind194=qualified194 and qualified194.referenceKind,
   teachingItemID=ref and ref.teachingItemID,
   legacyMinimum=earlier,minimumSourceConflict=different>1,
   referenceKind=newest and newest.referenceKind,advisory=true,
   nativeDispatchAllowed=false},nil
 end
 -- The yellow transition is NOT the recipe learning minimum; however a
 -- currently learned recipe at/above its yellow transition cannot be below
 -- the actual learning requirement under the normal profession difficulty
 -- ordering. Treat this as a *conservative planning eligibility bound*,
 -- never a claim that the character could learn at this skill.
 local yellow=skill(recipe.rawYellow)
 if recipe.sourceBuild==70450 and yellow and yellow>0 and
     skill(recipe.rawGrey) and yellow<skill(recipe.rawGrey) then
  return {minimum=yellow,source="YELLOW_CONSERVATIVE_ELIGIBILITY_BOUND",
    actualLearningMinimumKnown=false,advisory=true,nativeDispatchAllowed=false},nil
 end
 -- Standalone synthetic / legacy caller rows are explicit test inputs with
 -- NO sourceBuild. They are NOT the historical DB and retain API compatibility.
 if recipe.sourceBuild==nil and skill(recipe.rawMinRank) then
  return {minimum=skill(recipe.rawMinRank),source="EXPLICIT_CALLER_ROW",
   advisory=true,nativeDispatchAllowed=false},nil
 end
 return nil,"RECIPE_REQUIRED_SKILL_UNQUALIFIED"
end
function M:Permits(key,recipe,currentSkill,learned,learnedSource)
 local result,reason=self:Resolve(key,recipe)
 local now=skill(currentSkill)
 if not now then return false,"SKILL_UNKNOWN",result end
 if result then
  if result.source=="YELLOW_CONSERVATIVE_ELIGIBILITY_BOUND" and learned~=true then
   return false,"UNLEARNED_OR_UNKNOWN_WITHOUT_ACTUAL_MINIMUM",result
  end
  if now<result.minimum then return false,"BELOW_RECIPE_REQUIRED_SKILL",result end
  return true,"SOURCE_MINIMUM_MET",result
 end
 -- A stable and *current* recipe panel positively identifying the recipe as
 -- learned permits manual present-skill advisory. It does NOT qualify future
 -- simulated skills, source gates, or native execution.
 if learned==true and learnedSource=="CURRENT_PANEL" then
  return true,"CURRENT_PANEL_LEARNED_REFERENCE",nil end
 return false,reason,nil
end
JLP:RegisterModule("ProfessionRecipeMinimumGate",M)
