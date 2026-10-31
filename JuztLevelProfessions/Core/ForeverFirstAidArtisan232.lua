local _, JLP = ...
-- P0-232: Forever 225-300 FIRST AID source-to-action bridge.
-- Bands are reference choices, not documented guaranteed skill-up windows.
-- Source pages support recipe identifiers/minima/reagents; DB70450 confirms
-- spell/output identities but does NOT prove Forever output yields or live access.
-- No native dispatch and no non-canonical map coordinate publication.
local M = {contract="JLP-P0-232-FOREVER-FIRST-AID-ARTISAN",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local prefix="https://www.wowhead.com/forever/"
local sources={
 {fromSkill=225,toSkill=240,recipeID=10840,recipe="Mageweave Bandage",requiredSkill=210,
  reagentID=4338,reagent="Mageweave Cloth",perCraft=1,outputID=8544,
  publicOutputReference=2,db70450OutputReference=1,learning="MANUAL_PRIOR_TO_225_OR_VERIFIED_LEARNED",
  reference="https://www.wowhead.com/forever/spell=10840/mageweave-bandage"},
 {fromSkill=240,toSkill=260,recipeID=10841,recipe="Heavy Mageweave Bandage",requiredSkill=240,
  reagentID=4338,reagent="Mageweave Cloth",perCraft=2,outputID=8545,
  db70450OutputReference=1,learning="ARTISAN_QUEST_SURGEON_RESEARCH_LEAD",
  reference="https://www.wowhead.com/forever/spell=10841/heavy-mageweave-bandage"},
 {fromSkill=260,toSkill=290,recipeID=18629,recipe="Runecloth Bandage",requiredSkill=260,
  reagentID=14047,reagent="Runecloth",perCraft=1,outputID=14529,
  publicOutputReference=2,db70450OutputReference=1,learning="ARTISAN_QUEST_SURGEON_RESEARCH_LEAD",
  reference="https://www.wowhead.com/forever/spell=18629/runecloth-bandage"},
 {fromSkill=290,toSkill=300,recipeID=18630,recipe="Heavy Runecloth Bandage",requiredSkill=290,
  reagentID=14047,reagent="Runecloth",perCraft=2,outputID=14530,
  db70450OutputReference=1,learning="ARTISAN_QUEST_SURGEON_RESEARCH_LEAD",
  reference="https://www.wowhead.com/forever/spell=18630/heavy-runecloth-bandage"},
}
local surgeon={
 Horde={npcID=12920,name="Doctor Gregory Victor",zone="Arathi Highlands",
  reference=prefix.."npc=12920",questID=6622},
 Alliance={npcID=12939,name="Doctor Gustaf VanHowzen",zone="Dustwallow Marsh",
  reference=prefix.."npc=12939",questID=6624},
}
local function whole(v)
 return type(v)=="number" and v==v and v>=0 and v<2147483647 and v==math.floor(v)
end
local function copy(s)
 local out={};for k,v in pairs(s) do out[k]=v end;return out
end
local function currentRecipe(skill)
 for _,source in ipairs(sources) do
  if skill>=source.fromSkill and skill<source.toSkill then return source end
 end
end
local function factLearned(recipeID,options)
 local provided=nil
 if type(options.learnedRecipes)=="table" then
  provided=options.learnedRecipes[recipeID]
 end
 if type(provided)=="boolean" then return provided,"CALLER_CURRENT_STATE" end
 local p=JLP:GetModule("ProfessionPlanningFacts")
 if p and type(p.Observe)=="function" then
  local ok,f=pcall(p.Observe,p,"FIRST_AID",recipeID)
  if ok and type(f)=="table" and f.observed==true then
   if f.skillup and (f.skillup.tier=="GRAY" or f.skillup.canSkillUp==false) then
    return f.learned,"CURRENT_PANEL",true
   end
   if type(f.learned)=="boolean" then return f.learned,"CURRENT_PANEL",false end
  end
 end
 return nil,"UNKNOWN"
end
function M:AtSkill(skill,options)
 options=type(options)=="table" and options or {}
 if not whole(skill) or skill<225 or skill>=300 then return nil,"OUTSIDE_ARTISAN_REFERENCE" end
 local source=currentRecipe(skill)
 if not source then return nil,"SOURCE_GAP" end
 local result=copy(source)
 result.contract=self.contract;result.professionKey="FIRST_AID"
 result.readOnly=true;result.nativeDispatchAllowed=false;result.executionEligible=false
 result.referenceOnly=true;result.skillWindowStatus="SOURCE_GUIDE_REFERENCE_NOT_SKILLUP_PROOF"
 result.verifiedSkillUps=0;result.expectedCrafts=nil;result.outputCreditAllowed=false
 result.outputYieldStatus=source.publicOutputReference and
    source.db70450OutputReference and
    source.publicOutputReference~=source.db70450OutputReference and
    "SOURCE_OUTPUT_CONFLICT" or "NOT_PUBLICLY_CROSS_VERIFIED"
 result.learningStatus="SOURCE_LEARNING_LEAD_NOT_CURRENT_LEARNED"
 result.sourceProvenance="FOREVER_SPELL_AND_BUILD70450_REAGENT_PARITY"
 result.sourceRevision="P0-232-2026-10-24"
 result.waypointQualified=false;result.navigationStatus="LOCATION_UNVERIFIED"
 local faction=options.currentFaction
 result.surgeon=faction and surgeon[faction] and copy(surgeon[faction]) or nil
 result.surgeonActorStatus=result.surgeon and "FACTION_PUBLIC_ACTOR_REFERENCE" or
  "FACTION_UNKNOWN_ACTOR_WITHHELD"
 local learned,learnedSource,liveGray=factLearned(source.recipeID,options)
 result.learned=learned;result.learnedSource=learnedSource
 result.liveGray=liveGray==true
 local bags=type(options.inventory)=="table" and options.inventory[source.reagentID] or nil
 result.bagsKnown=whole(bags)==true;result.bags=result.bagsKnown and bags or nil
 result.perCraftMaterials={{itemID=source.reagentID,name=source.reagent,
   quantity=source.perCraft,perCraft=source.perCraft,
   bagsKnown=result.bagsKnown,bags=result.bags,readOnly=true}}
 result.shortageKnown=result.bagsKnown
 result.missing=result.bagsKnown and math.max(0,source.perCraft-bags) or nil
 local cap=options.maxSkill
 if whole(cap) and cap<300 then
  result.actionKind="verify";result.stage="VERIFY_ARTISAN_RANK"
  result.nextAction="Complete and verify the faction-specific Artisan First Aid Triage quest before planning 225-300 crafts."
 elseif result.liveGray then
  result.actionKind="verify";result.stage="VERIFY_LIVE_GRAY"
  result.nextAction="Current profession panel shows this bandage cannot grant skill; verify an alternative recipe."
 elseif learned==false then
  result.actionKind="learn";result.stage="VERIFY_LEARNING_SOURCE"
  result.nextAction="Learn "..source.recipe.." from a currently available source; the Artisan surgeon is a faction-specific research lead, not a confirmed service waypoint."
 elseif learned~=true then
  result.actionKind="verify";result.stage="VERIFY_RECIPE_KNOWLEDGE"
  result.nextAction="Open First Aid and verify that "..source.recipe.." is learned before crafting."
 elseif not result.bagsKnown then
  result.actionKind="verify";result.stage="VERIFY_INVENTORY"
  result.nextAction="Verify current bag quantity of "..source.reagent.." before planning a craft."
 elseif result.missing>0 then
  result.actionKind="acquire";result.stage="ACQUIRE_REAGENTS"
  result.nextAction="Obtain "..result.missing.." "..source.reagent.." for one manual "..source.recipe.." craft; actual acquisition and prices are unknown."
 else
  result.actionKind="verify";result.stage="MANUAL_ONE_CRAFT_REFERENCE"
  result.nextAction="Manually craft ONE "..source.recipe.." if current recipe color permits a skill-up; verify separate craft and skill receipts and replan."
 end
 return result,nil
end
-- A future route is a list of transparent, unexecuted segments. No estimated
-- craft count is fabricated. Only user-supplied counts may create a scenario BOM.
function M:PlanTo300(skill,options)
 options=type(options)=="table" and options or {}
 if not whole(skill) or skill>300 then return nil,"INVALID_SKILL" end
 local out={contract=self.contract,professionKey="FIRST_AID",fromSkill=skill,toSkill=300,
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  continuousClientRoute=false,skillUpReceipts=0,craftReceipts=0,
  forecastOnly=true,segments={},requirements={},estimatedCrafts=nil,
  fixedOutputCredits=0,sourceQualifiedReagentWindows=0,
  result="SOURCE_BANDS_NOT_CLIENT_VERIFIED"}
 local total={};local unknownCount=false
 for _,s in ipairs(sources) do
  if s.toSkill>skill then
   local r=self:AtSkill(math.max(s.fromSkill,225),options)
   -- Rebuild segments from immutable source and verified input facts only.
   local segment={fromSkill=math.max(skill,s.fromSkill),toSkill=s.toSkill,
    recipeID=s.recipeID,recipe=s.recipe,requiredSkill=s.requiredSkill,
    recipeURL=s.reference,sourceStatus="FOREVER_SPELL_REAGENT_REFERENCE",
    learningStatus=s.learning,trainer=r and r.surgeon or nil,
    sourceOutputConflict=r and r.outputYieldStatus=="SOURCE_OUTPUT_CONFLICT",
    reagentID=s.reagentID,perCraft=s.perCraft,expectedCrafts=nil,
    learned=r and r.learned,actionStage=r and r.stage,
    skillGainGuaranteed=false,readOnly=true,nativeDispatchAllowed=false,
    navigationStatus="LOCATION_UNVERIFIED"}
   local explicit=type(options.scenarioCraftCounts)=="table" and options.scenarioCraftCounts[s.recipeID]
   if explicit~=nil then
    if whole(explicit) and explicit<=10000 then
     segment.scenarioCrafts=explicit;segment.scenarioOnly=true
     total[s.reagentID]=(total[s.reagentID] or 0)+s.perCraft*explicit
    else segment.countRejected="INVALID_SCENARIO_CRAFT_COUNT";unknownCount=true end
   else unknownCount=true end
   out.sourceQualifiedReagentWindows=out.sourceQualifiedReagentWindows+1
   out.segments[#out.segments+1]=segment
  end
 end
 for id,quantity in pairs(total) do
  local held=type(options.inventory)=="table" and options.inventory[id] or nil
  local known=whole(held)==true
  out.requirements[#out.requirements+1]={itemID=id,scenarioQuantity=quantity,
   bagsKnown=known,bags=known and held or nil,
   conditionalShortage=known and math.max(0,quantity-held) or nil,
   readOnly=true,notConfirmedPurchase=true}
 end
 table.sort(out.requirements,function(a,b)return a.itemID<b.itemID end)
 out.scenarioBudgetComplete=not unknownCount
 return out,nil
end

-- P0-236: complete 1-300 advisory First Aid band continuity in the *existing*
-- First Aid evidence service. The lower guide bands were previously visible
-- only through aggregate SecondaryLevelingPlanner references. Spell identity
-- and per-craft reagents are rechecked against the current immutable DB70450
-- catalogue on every call; guide quantities are NEVER treated as guaranteed
-- crafts or skill gains. 225-300 retains the P0-232 per-field authorization.
local preArtisan236={
 {1,40,3275,"Linen Bandage",2589,1,"TRAINER_REFERENCE"},
 {40,80,3276,"Heavy Linen Bandage",2589,2,"TRAINER_REFERENCE"},
 {80,115,3277,"Wool Bandage",2592,1,"TRAINER_REFERENCE"},
 {115,150,3278,"Heavy Wool Bandage",2592,2,"TRAINER_REFERENCE"},
 {150,180,7928,"Silk Bandage",4306,1,"EXPERT_BOOK_GATE"},
 {180,210,7929,"Heavy Silk Bandage",4306,2,"MANUAL_HEAVY_SILK"},
 {210,225,10840,"Mageweave Bandage",4338,1,"MANUAL_MAGEWEAVE"},
}
local vendorLead236={
 Horde={npcID=13476,name="Balai Lok'Wein",zone="Dustwallow Marsh",
  sourceURL="https://www.wowhead.com/forever/npc=13476/balai-lokwein"},
 Alliance={npcID=2805,name="Deneb Walker",zone="Arathi Highlands",
  sourceURL="https://www.wowhead.com/forever/npc=2805/deneb-walker"},
}
local learningItem236={EXPERT_BOOK_GATE=16084,MANUAL_HEAVY_SILK=16112,
 MANUAL_MAGEWEAVE=16113}
local function canon236(v)
 return type(v)=="string" and v:lower():gsub("[^%w]","") or nil
end
local function dbParity236(id,name,reagentID,reagentCount)
 local root=JLP.data and JLP.data.build70450Recipes
 local records=root and root.professions and root.professions.FIRST_AID
 local packed=records and records.packed
 if type(packed)~="string" then return false,"DB70450_SOURCE_NOT_LOADED" end
 local row=nil
 for line in packed:gmatch("[^\n]+") do
  if line:match("^"..id.."%^") then
   if row then return false,"DUPLICATE_RECIPE_ID_IN_DB" end
   row=line
  end
 end
 if not row then return false,"RECIPE_NOT_IN_DB70450" end
 local f={};for value in (row.."^"):gmatch("([^%^]*)%^") do f[#f+1]=value end
 if #f~=12 or tonumber(f[1])~=id or canon236(f[12])~=canon236(name) then
  return false,"RECIPE_ID_OR_NAME_MISMATCH" end
 if f[10]~=tostring(reagentID)..":"..tostring(reagentCount) then
  return false,"DB_REAGENT_PARITY_FAILED" end
 return true,"FOREVER_GUIDE_AND_DB70450_RECIPE_REAGENT_PARITY"
end
local function sourceLead236(gate,faction)
 if gate=="ARTISAN_QUEST" then
  local actor=surgeon[faction]
  return {kind="ARTISAN_QUEST",questID=actor and actor.questID or nil,
   actorID=actor and actor.npcID or nil,actorName=actor and actor.name or nil,
   actorZone=actor and actor.zone or nil,
   actorSourceURL=actor and actor.reference or nil,
   actorStatus=actor and "FOREVER_PUBLIC_ACTOR_REFERENCE" or "FACTION_UNVERIFIED",
   currentAccess="UNKNOWN",questCompletion="UNKNOWN",waypointQualified=false,
   coordinateAuthority="NOT_CANONICAL_OWNER_PROOF"}
 end
 local id=learningItem236[gate]
 if not id then return {kind="TRAINER_CATEGORY",actorStatus="NOT_SOURCE_VERIFIED",
  waypointQualified=false,currentAccess="UNKNOWN"} end
 local v=vendorLead236[faction]
 return {kind="VENDOR_MANUAL",teachingItemID=id,
  teachingItemURL="https://www.wowhead.com/forever/item="..id,
  actorID=v and v.npcID or nil,actorName=v and v.name or nil,
  actorZone=v and v.zone or nil,actorSourceURL=v and v.sourceURL or nil,
  actorStatus=v and "FOREVER_PUBLIC_VENDOR_IDENTITY_ONLY" or "FACTION_UNVERIFIED",
  vendorStock="UNKNOWN",currentAccess="UNKNOWN",waypointQualified=false,
  coordinateAuthority="NOT_CANONICAL_OWNER_PROOF"}
end
local function readLearned236(recipeID,options)
 local observed=nil
 if type(options.learnedRecipes)=="table" then observed=options.learnedRecipes[recipeID] end
 if type(observed)=="boolean" then return observed,"CALLER_CURRENT_STATE" end
 return nil,"UNKNOWN"
end
function M:AtAnySkill(skill,options)
 options=type(options)=="table" and options or {}
 if not whole(skill) or skill<1 or skill>=300 then return nil,"INVALID_SKILL" end
 if skill>=225 then return self:AtSkill(skill,options) end
 local row
 for _,r in ipairs(preArtisan236) do if skill>=r[1] and skill<r[2] then row=r;break end end
 if not row then return nil,"UNQUALIFIED_GUIDE_WINDOW" end
 local valid,proof=dbParity236(row[3],row[4],row[5],row[6])
 local learned,learnedSource=readLearned236(row[3],options)
 local quantity=type(options.inventory)=="table" and options.inventory[row[5]] or nil
 local known=whole(quantity)
 local missing=known and math.max(0,row[6]-quantity) or nil
 local lead=sourceLead236(row[7],options.currentFaction)
 local out={contract="JLP-P0-236-FIRST-AID-1-300-BAND-CONTINUITY",
  professionKey="FIRST_AID",skill=skill,fromSkill=row[1],toSkill=row[2],
  recipeID=row[3],recipe=row[4],reagentID=row[5],perCraft=row[6],
  recipeURL="https://www.wowhead.com/forever/spell="..row[3],
  sourceURL="https://www.wowhead.com/forever/guide/professions/first-aid/overview",
  sourceStatus=proof,sourceFieldsQualified=valid,
  skillWindowStatus="FOREVER_GUIDE_BAND_NOT_SKILLUP_PROOF",
  exactLearningMinimumQualified=false,referenceDifficulty="UNKNOWN",
  guideBandStart=row[1],guideBandEnd=row[2],
  learned=learned,learnedSource=learnedSource,
  perCraftMaterials={{itemID=row[5],perCraft=row[6],quantity=row[6],
     bagsKnown=known,bags=known and quantity or nil,missing=missing,readOnly=true}},
  bagsKnown=known,missing=missing,learningSourceReview=lead,
  navigationStatus="LOCATION_UNVERIFIED",waypointQualified=false,
  nativeDispatchAllowed=false,executionEligible=false,readOnly=true,
  outputCreditAllowed=false,verifiedSkillUps=0,expectedCrafts=nil,
  complete1300=false,skillUpGuaranteed=false}
 local cap=options.maxSkill
 if whole(cap) and cap<=skill and cap<300 then
  out.stage="VERIFY_PROFESSION_RANK";out.actionKind="verify"
  if cap==150 then out.learningSourceReview=sourceLead236("EXPERT_BOOK_GATE",options.currentFaction) end
  out.nextAction="Verify and learn the next First Aid rank using an appropriately sourced book or quest before continuing."
 elseif not valid then
  out.stage="VERIFY_RECIPE_SOURCE_PARITY";out.actionKind="verify"
  out.nextAction="Recipe identity or direct reagent fields conflict with DB70450; do not qualify this guide step."
 elseif learned==false then
  out.stage="VERIFY_LEARNING_SOURCE";out.actionKind="learn"
  out.nextAction="Acquire/learn "..row[4].." using its current trainer or manual source; verify the character's learned state."
 elseif learned==nil then
  out.stage="VERIFY_LEARNED_STATE";out.actionKind="verify"
  out.nextAction="Open First Aid and verify whether "..row[4].." is learned."
 elseif not known then
  out.stage="VERIFY_INVENTORY";out.actionKind="verify"
  out.nextAction="Verify bag quantity; unknown inventory is not zero."
 elseif missing>0 then
  out.stage="ACQUIRE_REAGENT";out.actionKind="acquire"
  out.nextAction="Acquire "..missing.." unit(s) of item "..row[5].." for a manual craft; price and stock are unverified."
 else
  out.stage="REVIEW_MANUAL_ONE_CRAFT";out.actionKind="verify"
  out.nextAction="Review current recipe color, manually craft ONE "..row[4]..", then verify separate craft and skill-up receipts."
 end
 return out,nil
end
-- Join the already documented seven 1-225 guide rows to P0-232's four
-- 225-300 records. The same recipe 10840 occurs in two adjacent *guide*
-- bands, not as two different spells. Caller-supplied per-band counts are
-- required for any scenario material calculation; defaults are all UNKNOWN.
function M:PlanFullTo300(skill,options)
 options=type(options)=="table" and options or {}
 if not whole(skill) or skill<1 or skill>300 then return nil,"INVALID_SKILL" end
 local out={contract="JLP-P0-236-FIRST-AID-1-300-BAND-CONTINUITY",
  professionKey="FIRST_AID",fromSkill=skill,toSkill=300,
  bands={},sourceQualifiedBands=0,sourceConflicts=0,
  unqualifiedSkillPositions=0,referencePositions=0,
  readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
  clientVerifiedSkillUps=0,clientVerifiedCrafts=0,
  complete1300=false,scenarioBudgetComplete=false,
  scenarioRequirements={},outputCredits=0,
  currentAction=skill<300 and self:AtAnySkill(skill,options) or nil}
 local references={}
 for _,r in ipairs(preArtisan236) do references[#references+1]={from=r[1],to=r[2],id=r[3],name=r[4],mat=r[5],per=r[6]} end
 for _,r in ipairs(sources) do references[#references+1]={from=r.fromSkill,to=r.toSkill,id=r.recipeID,
  name=r.recipe,mat=r.reagentID,per=r.perCraft} end
 local quantities,allSpecified={},true
 for _,r in ipairs(references) do
  if r.to>skill then
   local ok,reason=dbParity236(r.id,r.name,r.mat,r.per)
   local begin=math.max(skill,r.from)
   local explicit=type(options.scenarioCraftCountsByBand)=="table" and
     options.scenarioCraftCountsByBand[r.from] or nil
   local count=whole(explicit) and explicit<=10000 and explicit or nil
   local band={fromSkill=begin,toSkill=r.to,recipeID=r.id,recipe=r.name,
    reagentID=r.mat,perCraft=r.per,sourceStatus=reason,sourceQualified=ok,
    knownLearningMethod=sourceLead236(r.from>=225 and "ARTISAN_QUEST" or
      (r.from==150 and "EXPERT_BOOK_GATE" or r.from==180 and "MANUAL_HEAVY_SILK" or
      r.from==210 and "MANUAL_MAGEWEAVE" or "TRAINER_CATEGORY"),options.currentFaction),
    scenarioCrafts=count,craftCountGuaranteed=false,
    skillUpGuaranteed=false,outputCreditAllowed=false,
    navigationStatus="LOCATION_UNVERIFIED",nativeDispatchAllowed=false}
   out.bands[#out.bands+1]=band
   if ok then
    out.sourceQualifiedBands=out.sourceQualifiedBands+1
    out.referencePositions=out.referencePositions+r.to-begin
   else
    out.sourceConflicts=out.sourceConflicts+1
    out.unqualifiedSkillPositions=out.unqualifiedSkillPositions+r.to-begin
   end
   if count==nil or not ok then allSpecified=false
   else quantities[r.mat]=(quantities[r.mat] or 0)+r.per*count end
  end
 end
 for id,units in pairs(quantities) do
  local owned=type(options.inventory)=="table" and options.inventory[id] or nil
  local known=whole(owned)
  out.scenarioRequirements[#out.scenarioRequirements+1]={itemID=id,
   scenarioQuantity=units,bagsKnown=known,bags=known and owned or nil,
   conditionalShortage=known and math.max(0,units-owned) or nil}
 end
 table.sort(out.scenarioRequirements,function(a,b)return a.itemID<b.itemID end)
 out.scenarioBudgetComplete=allSpecified and #out.bands>0
 return out,nil
end
-- Operational First Aid constraints reuse the same qualified candidates and Planner.
-- Historical AtSkill/FullAtSkill/PlanFullTo300 retain their reference-only contracts.
local function data70532()return JLP.data and JLP.data.first_aid end
local function runtimeProfession()
 local api=JLP:GetModule("ProfessionAPI");return api and api:Get("FIRST_AID")
end
local function factionHorde()return type(UnitFactionGroup)=="function"and UnitFactionGroup("player")=="Horde"end
local function accessItem(id)
 local inv=JLP:GetModule("Inventory");local r=inv and inv:GetOwned(id)or {}
 local bags=r.bagKnown==true and whole(r.bags)and r.bags or nil
 local bank=r.bankKnown==true and whole(r.bank)and r.bank or nil
 return bags,bank
end
local function questField(fn,id)
 local q=type(C_QuestLog)=="table"and C_QuestLog
 if q and type(q[fn])=="function"then local ok,v=pcall(q[fn],id);if ok and type(v)=="boolean"then return v end end
end
local actors={
 ARNOK={npcID=3373,name="Arnok",zone="Orgrimmar",mapID=1454,x=.34,y=.844,kind="trainer"},
 BALAI={npcID=13476,name="Balai Lok'Wein",zone="Dustwallow Marsh",mapID=1445,x=.364,y=.304,kind="vendor"},
 GREGORY={npcID=12920,name="Doctor Gregory Victor",zone="Arathi Highlands",mapID=1417,x=.734,y=.368,kind="trainer"},
}
function M:GetOperationalAccess(profession,recipeID)
 local d=data70532();local f=d and d.progression.recipes[recipeID]
 local a={profession="FIRST_AID",recipeID=recipeID,readOnly=true,nativeDispatchAllowed=false,status="VERIFY",waypointQualified=false}
 if not profession or profession.cached or not whole(profession.skill)then a.status="OBSERVE_PROFESSION";return a end
 if not factionHorde()then a.status="VERIFY_FACTION_SOURCE";return a end
 if recipeID then
  if not f then return a end
  local facts=JLP:GetModule("ProfessionPlanningFacts");local live=facts and facts:Observe("FIRST_AID",recipeID)
  if not live or not live.observed or type(live.learned)~="boolean"then a.status="OBSERVE_LEARNED";return a end
  if live.learned then a.status="LEARNED";return a end
  a.minimum=f.minimum;a.learningMinimum=f.learningMinimum
  if profession.skill<f.minimum then a.status="SKILL_UNMET";return a end
  if f.learning=="automatic"then a.status="OBSERVE_AUTOMATIC";return a end
  if f.recipeItemID then
   a.itemID=f.recipeItemID;a.actor=next(f.vendors or {})and "BALAI"or nil
   if not a.actor then a.status="VERIFY_MANUAL_SOURCE";return a end
  else
   a.actor=f.minimum<=150 and "ARNOK"or "GREGORY";a.trainingSpellID=recipeID
   a.teachingRelation=facts and facts.GetQualifiedTeachingRelation and facts:GetQualifiedTeachingRelation("FIRST_AID",recipeID)
   a.teachingSpellID=a.teachingRelation and a.teachingRelation.spellID
   a.learningChannel="UNKNOWN_TRAINER_OR_MANUAL_INTERACTION"
  end
 else
  local cap=profession.maxSkill
  if cap~=75 and cap~=150 and cap~=225 and cap~=300 then a.status="OBSERVE_CAP";return a end
  if profession.skill<cap or cap==300 then return nil end
  a.rank=cap==75 and "Journeyman"or cap==150 and "Expert"or "Artisan"
  if cap==75 then a.actor="ARNOK";a.trainingSpellID=3274;a.minimum=50
  elseif cap==150 then a.actor="BALAI";a.itemID=16084;a.minimum=125
  else
   a.actor="GREGORY";a.questID=6622;a.minimum=225;a.requiredCharacterLevel=35
   local level=type(UnitLevel)=="function"and UnitLevel("player")
   if not whole(level)or level<35 then a.status="VERIFY_LEVEL_35";a.actor=nil;return a end
   local done=questField("IsQuestFlaggedCompleted",6622)
   if done==true then a.status="OBSERVE_CAP_AFTER_QUEST";a.actor=nil;return a end
   if done==nil then a.status="VERIFY_QUEST_STATUS";return a end
   local active=questField("IsOnQuest",6622)
   if active==false then a.status="INSPECT_ACCEPT_TRIAGE"
   elseif active==true then a.status=questField("ReadyForTurnIn",6622)==true and "RETURN_TRIAGE"or "MANUAL_TRIAGE_PATIENTS"
   else a.status="VERIFY_QUEST_LOG"end
   return a
  end
 end
 local evidence=JLP:GetModule("RecipeAccessEvidence");local actor=actors[a.actor]
 if a.itemID then
  local bags,bank=accessItem(a.itemID);a.bags=bags;a.bank=bank
  if bags and bags>0 then a.status="USE_BOOK_MANUALLY";a.actor=nil
  elseif bags==0 and bank and bank>0 then a.status="RETRIEVE_BOOK_BANK";a.actor=nil
  elseif bags~=0 or bank~=0 then a.status="OBSERVE_BOOK_INVENTORY";a.actor=nil
  else
   a.offer=evidence and evidence:GetMerchantPlanningHint(a.itemID,actor.npcID)or {status="UNKNOWN"}
   if a.offer.status=="OUT_OF_STOCK"or a.offer.status=="NOT_OFFERED"or a.offer.status=="INELIGIBLE"or a.offer.recentUnavailable then a.status="RECHECK_BOOK_SOURCE";a.actor=nil
   elseif a.offer.status=="AVAILABLE"then
    a.purchase=evidence:GetMerchantPurchaseAdvice(a.itemID,actor.npcID,1)
    a.status=(a.purchase.status=="INSUFFICIENT_FUNDS"or a.purchase.status=="VERIFY_CURRENCY_REQUIREMENTS"or a.purchase.status=="VERIFY_CHANGED_OFFER")and "VERIFY_BOOK_PURCHASE_REQUIREMENTS"or "BUY_BOOK_MANUALLY"
   else a.status="VERIFY_CURRENT_BOOK_OFFER"end
  end
 else
  if a.teachingSpellID and evidence and evidence.GetRecipeLearningPlanningHint then
   a.offer=evidence:GetRecipeLearningPlanningHint("FIRST_AID",recipeID,actor.npcID)
  else a.offer=evidence and evidence:GetTrainerPlanningHint(a.trainingSpellID,actor.npcID,recipeID and "FIRST_AID"or nil)or {status="UNKNOWN"}end
  a.learningChannel=a.offer.channel or a.learningChannel
  a.status=a.offer.status=="AVAILABLE"and "LEARN_MANUALLY"or "VERIFY_CURRENT_TRAINER_OFFER"
  -- Standard-menu absence is scoped to that menu, not all gossip/manual channels.
  if a.teachingSpellID and a.offer.status=="ALREADY_KNOWN_LISTED"then a.status="OBSERVE_LEARNED_AFTER_TRAINER";a.actor=nil
  elseif a.offer.status=="NOT_OFFERED"or a.offer.status=="INELIGIBLE"or a.offer.recentUnavailable then
   a.status=a.teachingSpellID and "RECHECK_SCOPED_TRAINER_OR_MANUAL_CHANNEL"or a.status;a.actor=nil
  end
 end
 return a
end
local function instruction(a)
 local name=a.itemID and ("book/manual "..a.itemID)or a.recipeID and ("recipe "..a.recipeID)or a.rank or "First Aid"
 return a.status=="USE_BOOK_MANUALLY"and ("Use the observed "..name.." manually; observe the recipe/rank separately. Book possession or use intent is not learning.")or
 a.status=="RETRIEVE_BOOK_BANK"and ("Withdraw the observed "..name.." from bank; observe bags, then use manually and observe recipe/rank.")or
 a.status=="BUY_BOOK_MANUALLY"and ("Buy ONE currently offered "..name.." manually; verify price/currency/funds/limited stock, then observe delivery, use and learning separately.")or
 a.status=="INSPECT_ACCEPT_TRIAGE"and "Visit Doctor Gregory Victor, Hammerfall; inspect/accept Horde Triage6622 manually (First Aid225, level35). Breadcrumb is optional. Observe quest log separately."or
 a.status=="MANUAL_TRIAGE_PATIENTS"and "Perform Triage manually using the quest's supplied Triage Bandages on the patients. This is item use, not bandage crafting. No automated targeting/healing; observe ready-to-turn-in separately."or
 a.status=="RETURN_TRIAGE"and "Return/turn in Triage6622 manually to Doctor Gregory Victor; observe quest completion and profession cap300 separately."or
 a.status=="OBSERVE_CAP_AFTER_QUEST"and "Quest completion is observed; verify First Aid cap300 before crafting past225. No rank is credited from quest flags alone."or
 a.status=="VERIFY_LEVEL_35"and "Reach/verify character level35 before Horde Artisan First Aid Triage; do not craft for skill past cap225."or
 a.status=="LEARN_MANUALLY"and (a.learningChannel=="GOSSIP"and
  ("Inspect/use the exact current spell-associated gossip option for "..name.." manually; associated spell is not a learning receipt. Observe recipe change separately.")or
  ("Learn "..name.." manually from the exact current trainer menu; observe recipe/rank change separately."))or
 a.teachingSpellID and ("Verify "..name.." with Doctor Gregory Victor. Craft "..a.recipeID.." is taught by spell "..a.teachingSpellID.." (70532). "..
  (a.status=="OBSERVE_LEARNED_AFTER_TRAINER"and "The menu lists it as used; observe the profession recipe separately. "or
   "Inspect the current trainer or manual/gossip interaction; channel and option identity are not qualified. A standard-menu negative is not absence from all channels. ")..
  "No automatic selection or learned-state credit; recheck character access and actual offering.")or
 ("Verify First Aid prerequisite: "..a.status.." for "..name..". UNKNOWN is not missing or complete; check current source/inventory and profession panel. No native action is authorized.")
end
function M:GetOperationalRankStep(profession)
 local a=self:GetOperationalAccess(profession,nil);if not a then return nil end
 return {kind=a.rank and "train"or "verify",profession="FIRST_AID",skill=profession and profession.skill,
  cap=profession and profession.maxSkill,rank=a.rank,firstAidAccess=a,nextAction=instruction(a),
  requiredNextAction="verify",readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end
function M:AnnotateOperational(output,row,profession)
 output.firstAidPrerequisites=output.alchemyPrerequisites;output.alchemyPrerequisites=nil
 output.learningMinimum=row.sourceFact.learningMinimum;output.minimumStatus=row.sourceFact.minimumStatus
 if output.learned~=true then
  local a=self:GetOperationalAccess(profession,row.recipeID)
  output.firstAidAccess=a;output.nextAction=instruction(a)
  -- Explicit strings; boolean combinations must never become an action enum.
  if a.status=="USE_BOOK_MANUALLY"or a.status=="LEARN_MANUALLY"then output.requiredNextAction="learn-recipe"
  elseif a.status=="BUY_BOOK_MANUALLY"or a.status=="RETRIEVE_BOOK_BANK"then output.requiredNextAction="acquire-recipe"
  else output.requiredNextAction="verify"end
  output.manualCraftBlockedByRecipePrerequisite=true
 end
 output.skillGainGuaranteed=false;output.inventoryOutputAllowed=false
end
function M:GetOperationalWaypoint(a)
 if type(a)~="table"or not factionHorde()or not a.actor then return nil end
 local r=actors[a.actor];if not r then return nil end
 return {serviceID="FA_"..a.actor,kind=a.questID and "quest_giver"or r.kind,name=r.name,zone=r.zone,
  npcID=r.npcID,faction="Horde",profession="FIRST_AID",recipeID=a.recipeID,teachingItemID=a.itemID,
  firstAidAccess=true,accessStage=a.status,accessQuestID=a.questID,accessRank=a.rank,
  sourceQualified=true,state="SOURCE_QUALIFIED",ownerAuthority="FOREVER_FIRST_AID_GUIDE_EXACT_ACTOR_GEOGRAPHY_NOT_CURRENT_OFFER",
  sourceURL="https://www.wowhead.com/forever/guide/professions/first-aid/overview",nativeDispatchAllowed=false,
  nav={mapID=r.mapID,x=r.x,y=r.y,mapDomain="UI_MAP_ID",evidence="FOREVER_FIRST_AID_GUIDE_UI_MAP_70532"}}
end
function M:GetCanonicalWaypoint(source)
 local a=self:GetOperationalAccess(runtimeProfession(),source.recipeID)
 if not a or a.status~=source.accessStage or a.rank~=source.accessRank or a.questID~=source.accessQuestID or a.itemID~=source.teachingItemID then return nil end
 return self:GetOperationalWaypoint(a)
end

JLP:RegisterModule("ForeverFirstAidArtisan232",M)
