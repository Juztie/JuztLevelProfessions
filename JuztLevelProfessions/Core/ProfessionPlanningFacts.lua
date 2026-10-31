local _, JLP = ...
-- Non-persistent, build-neutral facts for advisory Current Step. Never native authority.
-- API difficulty is categorical: yellow/green probabilities are NOT supplied by the API.
local M={contract="JLP-PLANNING-FACTS-186",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local names={[0]="ORANGE",[1]="YELLOW",[2]="GREEN",[3]="GRAY"}
local function positive(n)
 return type(n)=="number" and n==n and n>0 and n<math.huge and n==math.floor(n) and n
end
local function observedPanel(key)
 local api=JLP:GetModule("ProfessionAPI")
 if not api or type(api.GetReadOnlyProfessionObservation)~="function" then return nil end
 local ok,p=pcall(api.GetReadOnlyProfessionObservation,api)
 if ok and type(p)=="table" and p.observed==true and p.professionKey==key then return p end
 return nil
end
local function apiInfo(fn,id)
 local ok,value=pcall(fn,id)
 return ok and type(value)=="table" and value or nil
end
local function apiSchematic(fn,id)
 local ok,value=pcall(fn,id,false)
 return ok and type(value)=="table" and value or nil
end
local function skillFact(info)
 local tier=names[info.relativeDifficulty]
 if not tier then return {tier="UNKNOWN",chance=nil,probabilitySource="API_COLOR_UNKNOWN"} end
 local chance=nil
 if tier=="ORANGE" then chance=1 elseif tier=="GRAY" then chance=0 end
 return {tier=tier,chance=chance,
  probabilitySource=chance~=nil and "COLOR_CERTAINTY_RULE" or "API_COLOR_NO_EXACT_CHANCE",
  canSkillUp=nil,
  skillUpsPerCraft=positive(info.numSkillUps),
  maxTrivialLevel=positive(info.maxTrivialLevel)}
end
local function outputs(s)
 if type(s)~="table" then return nil end
 local lower,upper=positive(s.quantityMin),positive(s.quantityMax)
 if not lower or not upper or lower>upper then return nil end
 return {minimum=lower,maximum=upper,fixed=lower==upper,
  itemID=positive(s.outputItemID),source="CURRENT_RECIPE_SCHEMATIC_READ_ONLY"}
end
local function sameInfo(a,b,id)
 return a and b and a.recipeID==id and b.recipeID==id and
 a.learned==b.learned and a.relativeDifficulty==b.relativeDifficulty and
 a.numSkillUps==b.numSkillUps and a.canSkillUp==b.canSkillUp
end
local function sameYield(a,b)
 if not a and not b then return true end
 return a and b and a.quantityMin==b.quantityMin and
  a.quantityMax==b.quantityMax and a.outputItemID==b.outputItemID
end
local function fixedReagents(s)
 if type(s)~="table" or type(s.reagentSlotSchematics)~="table" then return nil end
 local quantities={}
 for _,slot in ipairs(s.reagentSlotSchematics)do
  if slot.required~=false then
   -- Only explicit required slots qualify this optional read-only check.
   -- Unrecognised client slot semantics remain UNKNOWN, never empty reagents.
   if slot.required~=true or not positive(slot.quantityRequired) or
      type(slot.reagents)~="table" or #slot.reagents~=1 or not positive(slot.reagents[1].itemID) then return nil end
   local id=slot.reagents[1].itemID
   quantities[id]=(quantities[id]or 0)+slot.quantityRequired
  end
 end
 if not next(quantities)then return nil end
 local keys={};for id in pairs(quantities)do keys[#keys+1]=id end;table.sort(keys)
 local pieces={};for _,id in ipairs(keys)do pieces[#pieces+1]=id..":"..quantities[id]end
 return quantities,table.concat(pieces,",")
end
function M:Observe(key,recipeID)
 local id=positive(recipeID)
 local result={contract=self.contract,profession=key,recipeID=id,observed=false,
  source="NO_CURRENT_PANEL",readOnly=true,nativeDispatchAllowed=false,
  executionEligible=false,output=nil,skillup=nil}
 if not id then result.reason="INVALID_RECIPE_ID";return result end
 local first=observedPanel(key)
 if not first then result.reason="PANEL_NOT_OBSERVED";return result end
 local t=type(C_TradeSkillUI)=="table" and C_TradeSkillUI or nil
 local fn=t and t.GetRecipeInfo
 if type(fn)~="function" then result.reason="GET_RECIPE_INFO_UNAVAILABLE";return result end
 local sf=t.GetRecipeSchematic
 local a=apiInfo(fn,id)
 local sa=type(sf)=="function" and apiSchematic(sf,id) or nil
 local b=apiInfo(fn,id)
 local sb=type(sf)=="function" and apiSchematic(sf,id) or nil
 local requiredA,signatureA,requiredB,signatureB
 if key=="MINING" or key=="ENCHANTING" or key=="BLACKSMITHING" or key=="ALCHEMY" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID"or key=="COOKING" then requiredA,signatureA=fixedReagents(sa);requiredB,signatureB=fixedReagents(sb)end
 local last=observedPanel(key)
 if not last or first.observationToken~=last.observationToken or
    first.skill~=last.skill or t.GetRecipeInfo~=fn or t.GetRecipeSchematic~=sf or
    not sameInfo(a,b,id) or not sameYield(sa,sb) or signatureA~=signatureB then
  result.reason="RECIPE_OR_PANEL_CHANGED";return result
 end
 result.observed=true;result.source="STABLE_CURRENT_UI_READ_ONLY"
 if type(a.learned)=="boolean" then result.learned=a.learned end
 result.skillup=skillFact(a)
 if type(a.canSkillUp)=="boolean" then result.skillup.canSkillUp=a.canSkillUp end
 result.output=outputs(sa)
 result.requiredReagents=requiredA
 result.outputStatus=result.output and (result.output.fixed and "EXACT_API_QUANTITY" or
  "VARIABLE_API_RANGE") or "OUTPUT_UNKNOWN"
 result.recipeName=a.name;result.skill=first.skill
 -- API success is read-only data and is NEVER an execution ticket.
 return result
end
local function campRelated(v)
 if type(v)~="string" then return false end
 local s=v:lower():gsub("[_%-]"," ")
 return s:find("camp workstation",1,true)~=nil or
  s:find("camp station",1,true)~=nil or s:find("camp crafting",1,true)~=nil
end
function M:AccessLead(key,recipeID,reference,recipeName)
 local sources=JLP:GetModule("SourceResolver")
 local found=sources and type(sources.GetRecipeSource)=="function" and
  sources:GetRecipeSource(key,recipeID) or nil
 if type(found)~="table" and type(recipeName)=="string" and recipeName~="" and
  sources and type(sources.GetRecipeSource)=="function" then
  -- SourceResolver's canonical name-keyed legacy source table is a genuine
  -- source of vendor/trainer NPC names; do not discard it because ID proof is absent.
  found=sources:GetRecipeSource(key,recipeName)
 end
 if type(found)=="table" then
  local out={kind=found.kind or found.sourceType or "REFERENCE",
   npcName=found.npcName or found.name,npcID=found.npcID,
   zone=found.zone,referenceURL=found.referenceURL,
   position=found.navigationQualified==true and found.nav or nil,
   provenance="SOURCE_RESOLVER_READ_ONLY",readOnly=true}
  if campRelated(out.kind) then return nil,"CAMP_WORKSTATION_EXCLUDED" end
  return out,nil
 end
 local kind=type(reference)=="string" and reference or nil
 if not kind or kind=="unknown" or campRelated(kind) then return nil,"EXACT_SOURCE_NOT_DOCUMENTED" end
 return {kind=kind,provenance="ROUTE_CLASS_ONLY",readOnly=true,
  npcName=nil,npcID=nil,position=nil},"EXACT_NPC_UNRESOLVED"
end
function M:Workstation(reference,focus)
 -- Ordinary real game facilities only. Never offer camp workstations.
 local allowed={ANVIL="Anvil",FORGE="Forge",FIREPLACE="Fireplace",
  COOKING_FIRE="Cooking Fire",MOONWELL="Moonwell",SPINNING_WHEEL="Spinning Wheel"}
 if type(reference)=="string" then
  local id=reference:upper():gsub("[%s%-]","_")
  if allowed[id] then return {name=allowed[id],referenceOnly=true} end
  if campRelated(reference) then return nil end
 end
 local canonical={[883]="Moonwell",[2250]="Spinning Wheel"}
 local name=canonical[focus]
 return name and {name=name,referenceOnly=true} or nil
end

-- Qualified Enchanting data stay in the existing profession dataset. Guide-use
-- floors are explicitly distinct from exact learning requirements and live state.
function M:GetEnchantingContract(id)
 local data=JLP.data and JLP.data.enchanting
 local source=data and data.progression
 local f=source and source.contract=="enchanting-70532-progression-v1" and source.recipes[id]
 if not f or f.id~=id or f.sourceBuild~=70532 or type(f.reagents)~="string" or
    not positive(f.minimum) or not positive(f.gray) or f.gray<=f.minimum or
    (f.actionType~="CREATE_ITEM" and f.actionType~="ENCHANT_APPLICATION") then return nil end
 if f.learning=="formula" and (f.patternTriggerType~=6 or f.patternProfessionID~=333 or
    f.patternItemID~=f.recipeItemID or f.patternRequiredSkill~=f.learningMinimum or f.minimum<f.learningMinimum) then return nil end
 return f,f
end
function M:GetEnchantingCandidates(skill,fullRoute,includeTools,professionKey)
 professionKey=professionKey or "ENCHANTING"
 local dataset=JLP.data and JLP.data[professionKey:lower()]
 local source=dataset and dataset.progression
 local out={}
 local odds=JLP:GetModule("SkillUpProbabilityPlanner")
 if not source or not odds then return out end
 for id in pairs(source.recipes)do
  local f=professionKey=="BLACKSMITHING" and self:GetBlacksmithingContract(id) or professionKey=="ALCHEMY" and self:GetAlchemyContract(id) or professionKey=="LEATHERWORKING" and self:GetAlchemyContract(id,"LEATHERWORKING") or professionKey=="ENGINEERING" and self:GetEngineeringContract(id) or professionKey=="FIRST_AID" and self:GetAlchemyContract(id,"FIRST_AID") or professionKey=="COOKING" and self:GetAlchemyContract(id,"COOKING") or professionKey=="ENCHANTING" and self:GetEnchantingContract(id)
  if f and f.researchOnly and (professionKey=="BLACKSMITHING" or professionKey=="ENGINEERING" or professionKey=="LEATHERWORKING" or professionKey=="FIRST_AID" or professionKey=="COOKING") and not f.preparationOnly then
   -- A source with unknown exact learning/access may support an already
   -- observed learned recipe, never a fresh character's assumed acquisition.
   local current=self:Observe(professionKey,id)
   if current.observed and current.learned==true and skill>=f.minimum and
      current.skillup and current.skillup.tier~="UNKNOWN" and current.skillup.tier~="GRAY" and
      (professionKey=="LEATHERWORKING" or current.output and current.output.fixed and current.output.itemID==f.output) then
    local copy={}for k,v in pairs(f)do copy[k]=v end
    copy.researchOnly=false;copy.conditionalCurrentOnly=true;f=copy
   end
  end
  if f and (f.researchOnly or (professionKey=="BLACKSMITHING" or professionKey=="LEATHERWORKING" or professionKey=="FIRST_AID" or professionKey=="COOKING") and f.preparationOnly or professionKey=="ENGINEERING" and (f.specializationRequired and self:GetEngineeringSpecialization()~=f.specializationRequired)) then f=nil end
  -- Rod preparation is driven by the selected consumer requirement, not
  -- by scanning unrelated rod-product candidates on every replan.
  if f and (professionKey~="ENCHANTING" or not f.rodProduct or includeTools) and (fullRoute or skill>=f.minimum and (skill<f.gray or includeTools and f.rodProduct)) then
   local api=JLP:GetModule("ProfessionAPI")
   local profession=api and api.Get and api:Get(professionKey)
   local cap=not fullRoute and profession and positive(profession.maxSkill) or 300
   local endSkill=math.min(cap or 300,300,skill+5,f.gray)
   local casts=0
   if skill>=f.minimum and skill<f.gray then
    for n=skill,endSkill-1 do
     local tier=n<f.yellow and "ORANGE" or n<f.green and "YELLOW" or "GREEN"
     casts=casts+1/odds:ForTier(tier).probability
    end
   end
   local materials={}
   for item,qty in f.reagents:gmatch("(%d+):(%d+)")do
    item,qty=tonumber(item),tonumber(qty)
    local vendor=item==247786 or item==6217 or item==3371 or item==3372 or item==8925 or item==17034 or item==17035
    local definition
    for _,m in pairs(dataset.materials or {})do if m.itemID==item then definition=m;break end end
    materials[#materials+1]={itemID=item,name=definition and definition.name,quantity=qty,
     source=definition and definition.source or vendor and "vendor" or "unknown"}
   end
   if professionKey=="ALCHEMY" or professionKey=="BLACKSMITHING" or professionKey=="ENGINEERING" or professionKey=="LEATHERWORKING" or professionKey=="FIRST_AID" or professionKey=="COOKING" then materials={} for _,m in ipairs(f.referenceMaterials or {})do local copy={}for k,v in pairs(m)do copy[k]=v end;materials[#materials+1]=copy end end
   local row={recipeID=id,recipe=f.name,requiredSkill=f.minimum,requiredSkillAuthority=f.minimumStatus,
    sourceQualificationContract=source.contract,qualifiedProgression=true,route=true,routeSkillMin=f.minimum,
    routeSkillTarget=math.min(f.gray,300),rawYellow=f.yellow,rawGreen=f.green,rawGrey=f.gray,
    rawYellowThreshold=f.yellow,rawGreyThreshold=f.gray,skillTarget=professionKey=="ENCHANTING" and f.rodProduct and math.min(endSkill,skill+1) or endSkill,
    scenarioCrafts=professionKey=="ENCHANTING" and f.rodProduct and 1 or (casts>0 and math.ceil(casts) or nil),
    scenarioEligible=true,craftCountAuthority="SOURCE_COLOR_PLANNING_SCENARIO_NOT_OBSERVED_SKILL",
    recipeSource=f.learning,sourceBuild=70532,sourceFact=f,materials=materials,
    outputItemID=f.output,actionType=f.actionType,castSeconds=f.castSeconds,
    outputYieldStatus=f.outputStatus,readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
   row.conditionalCurrentOnly=f.conditionalCurrentOnly
   if f.toolItemID and professionKey=="ENCHANTING" then row.requiredTool={itemID=f.toolItemID,rodTier=f.toolTier,name="Runed rod tier "..f.toolTier}end
   out[#out+1]=row
  end
 end
 table.sort(out,function(a,b)return a.recipeID<b.recipeID end)
 return out
end
function M:GetEnchantingRankStep(profession,professionKey)
 professionKey=professionKey or "ENCHANTING"
 local label=professionKey=="LEATHERWORKING" and "Leatherworking" or professionKey=="ENGINEERING" and "Engineering" or professionKey=="BLACKSMITHING" and "Blacksmithing" or professionKey=="ALCHEMY" and "Alchemy" or "Enchanting"
 if not profession or profession.cached then return {kind="verify",nextAction="Observe current "..label.." skill/rank/cap in the profession panel.",readOnly=true,nativeDispatchAllowed=false}end
 local skill,cap=profession.skill,profession.maxSkill
 if type(skill)~="number" or skill>=300 then return nil end
 if cap~=75 and cap~=150 and cap~=225 and cap~=300 then return {kind="verify",nextAction="Verify the current "..label.." rank and skill cap; UNKNOWN is not Artisan.",readOnly=true,nativeDispatchAllowed=false}end
 if skill<cap or cap==300 then return nil end
 local rank=cap==75 and "Journeyman" or cap==150 and "Expert" or "Artisan"
 local minimumLevel=cap==75 and 10 or cap==150 and 20 or 35
 local ok,level=false,nil
 if type(UnitLevel)=="function" then ok,level=pcall(UnitLevel,"player")end
 local ready=ok and type(level)=="number" and level>=minimumLevel
 local text=ready and ("Train "..rank.." "..label.." manually; observe the new cap before continuing.") or
  ("Reach/verify character level "..minimumLevel.." before learning "..rank.." "..label.."; do not craft past the observed cap.")
 if rank=="Expert" then text=text..(professionKey=="LEATHERWORKING" and " Horde reference: Una, Thunder Bluff." or professionKey=="BLACKSMITHING" and " Horde reference: Saru Steelfury, Orgrimmar." or professionKey=="ALCHEMY" and " Horde reference: Doctor Herbert Halsey, Undercity." or " Horde reference: Hgarth, Sun Rock Retreat, Stonetalon Mountains.")end
 if rank=="Artisan" and professionKey=="BLACKSMITHING" then text=text.." Neutral reference: Brikk Keencraft, Booty Bay. Observe actual training and cap300."end
 if rank=="Artisan" and professionKey=="LEATHERWORKING" then text=text.." Horde reference: Hahrana Ironhide, Camp Mojache, Feralas; verify actual offering and cap300."end
 if rank=="Artisan" and professionKey=="ALCHEMY" then text=text.." Horde reference: Rogvar, Stonard, Swamp of Sorrows."end
 if rank=="Artisan" and professionKey=="ENCHANTING" then text=text.." Annora is INSIDE Uldaman: dungeon access/party and clearing her area must be verified. An entrance waypoint is not Annora's position."end
 return {kind=ready and "train" or "verify",profession=professionKey,skill=skill,cap=cap,rank=rank,
  nextAction=text,action=text,dungeonAccessUnverified=professionKey=="ENCHANTING" and rank=="Artisan",readOnly=true,nativeDispatchAllowed=false,
  trainerReferenceOnly=true,requiredCharacterLevel=minimumLevel}
end
-- Exact necessary Annora intent, derived from the selected Planner step.
-- This is neither a new rank planner nor a trainer-menu/learning receipt.
function M:GetAnnoraLearning(step,profession)
 local d=JLP.data and JLP.data.enchanting and JLP.data.enchanting.annoraAccess
 if not d or type(step)~="table" or not profession or profession.cached then return nil end
 local rank=step.rank=="Artisan" and (step.kind=="train" or step.kind=="verify")
 local f=step.recipeID and self:GetEnchantingContract(step.recipeID)
 local recipe=step.kind=="craft" and step.learned~=true and type(profession.skill)=="number" and
  profession.skill>=225 and f and f.learning=="trainer" and f.trainerReference and f.trainerReference.npcID==d.npcID
 if rank and (profession.maxSkill~=d.previousCap or type(profession.skill)~="number" or profession.skill<d.previousCap) then return nil end
 if not rank and not recipe then return nil end
 local evidence=JLP:GetModule("RecipeAccessEvidence")
 local offer=evidence and evidence.GetTrainerPlanningHint and evidence:GetTrainerPlanningHint(
  recipe and step.recipeID or d.trainingSpellID,d.npcID) or {status="UNKNOWN"}
 if rank and evidence and evidence.GetTrainerPlanningHint then
  local learnedSpellOffer=evidence:GetTrainerPlanningHint(d.learnedRankSpellID,d.npcID)
  -- DB2 separates teaching13921 from learned rank13920. A complete negative
  -- requires both exact identities absent; neither menu identity proves cap300.
  if learnedSpellOffer.status=="AVAILABLE" or learnedSpellOffer.status=="ALREADY_KNOWN_LISTED" then offer=learnedSpellOffer
  elseif offer.status=="NOT_OFFERED" and learnedSpellOffer.status~="NOT_OFFERED" then offer=learnedSpellOffer end
 end
 local level
 if type(UnitLevel)=="function" then local ok,n=pcall(UnitLevel,"player");if ok then level=n end end
 local eligible=not rank or type(level)=="number" and level>=d.requiredLevel
 if recipe and (type(f.learningMinimum)~="number" or profession.skill<f.learningMinimum) then eligible=false end
 return {npcID=d.npcID,kind=rank and "RANK" or "RECIPE",recipeID=recipe and step.recipeID or nil,
  trainingSpellID=rank and d.trainingSpellID or nil,rank=rank and "Artisan" or nil,
  eligible=eligible,learnedUnknown=recipe and step.learned==nil or false,offer=offer,
  sourceURL=recipe and f.trainerReference.sourceURL or d.guideURL,
  sourceStatus=recipe and "EXISTING_INDEXED_EXACT_TRAINER_REFERENCE_NOT_CURRENT_MENU" or d.rankEvidence,
  readOnly=true,nativeDispatchAllowed=false}
end
function M:GetEnchantingToolPreparation(candidate,skill)
 if not candidate.requiredTool then return nil end
 local resolver=JLP:GetModule("EnchantingToolResolver")
 local status=resolver and resolver:Resolve(candidate.requiredTool)
 if not status or status.status~="missing" then return nil,status end
 for _,row in ipairs(self:GetEnchantingCandidates(skill,false,true))do
  if row.outputItemID==candidate.requiredTool.itemID then
   row.toolPreparation=true;row.preparationOnly=true;row.scenarioCrafts=1;row.skillTarget=skill
   return row,status
  end
 end
 return nil,status
end
function M:AnnotateEnchanting(output,row,professionKey)
 professionKey=professionKey or "ENCHANTING"
 local f=professionKey=="BLACKSMITHING" and self:GetBlacksmithingContract(row.recipeID) or professionKey=="ALCHEMY" and self:GetAlchemyContract(row.recipeID) or professionKey=="LEATHERWORKING" and self:GetAlchemyContract(row.recipeID,"LEATHERWORKING") or professionKey=="ENGINEERING" and self:GetEngineeringContract(row.recipeID) or professionKey=="FIRST_AID" and self:GetAlchemyContract(row.recipeID,"FIRST_AID") or professionKey=="COOKING" and self:GetAlchemyContract(row.recipeID,"COOKING") or professionKey=="ENCHANTING" and self:GetEnchantingContract(row.recipeID)
 if not f then output.requiredNextAction="verify";output.nextAction="Verify exact Enchanting source contract.";return end
 output.actionType=f.actionType;output.requiredSkill=f.minimum;output.minimumStatus=f.minimumStatus
 if row.toolPreparation then output.manualCraftBlockedByLiveDifficulty=false end
 output.learningMinimum=f.learningMinimum
 output.expectedCraftsQualified=false;output.skillGainGuaranteed=false
 output.remainingCrafts=row.scenarioCrafts or 1;output.skillTarget=row.skillTarget
 output.recipePrerequisites={tool=row.requiredTool,learning=f.learning,minimumStatus=f.minimumStatus}
 output.requiredNextAction=output.learned~=true and "verify" or not output.knownInventory and "verify" or not output.bagReady and "acquire" or "manual-craft"
 if output.learned~=true then
  output.nextAction="Verify/learn "..f.name.." manually at a qualified "..f.learning.." source; observe learned-state separately. Planning minimum "..f.minimum.." ("..f.minimumStatus..")."
  if f.learning=="automatic" then
   output.learningMethod="automatic"
   output.nextAction="Inspect "..f.name.." in the current "..(professionKey=="LEATHERWORKING" and "Leatherworking" or professionKey=="ENGINEERING" and "Engineering" or professionKey=="BLACKSMITHING" and "Blacksmithing" or professionKey=="ALCHEMY" and "Alchemy" or "Enchanting").." panel. Forever references list it with the profession; a missing/UNKNOWN learned observation is not a trainer trip or proof of learning."
  end
  if f.minimumStatus=="CONSERVATIVE_FOREVER_GUIDE_FLOOR_NOT_EXACT_LEARNING_MINIMUM" then output.nextAction=output.nextAction.." Exact learning minimum remains UNKNOWN."end
  if f.trainerReference and output.skill>=225 then output.nextAction=output.nextAction.." Annora (11073), inside Uldaman: verify dungeon access and actual trainer offering; no NPC waypoint is qualified.";output.dungeonAccessUnverified=true end
  if f.recipeItemID then output.nextAction=output.nextAction.." Formula item "..f.recipeItemID.."."end
 elseif not output.knownInventory then output.nextAction="Inspect current materials for "..f.name.."; UNKNOWN is not a shortage."
 elseif not output.bagReady then output.nextAction="Acquire/withdraw the observed missing reagents for "..f.name.."; observe bags before one manual action."
 else output.nextAction=(f.actionType=="ENCHANT_APPLICATION" and "Apply ONE " or "Craft ONE ")..f.name.." manually; observe result and skill independently before replanning."end
 local resolver=JLP:GetModule("EnchantingToolResolver")
 local tool=row.requiredTool and resolver and resolver:Resolve(row.requiredTool)
 output.toolRequirement=tool;output.requiredTool=row.requiredTool
 if row.requiredTool and (not tool or tool.status~="bags" and tool.status~="confirmed") and output.learned==true then
  output.requiredNextAction=tool and tool.status=="bank" and "acquire" or "verify"
  output.nextAction=tool and tool.status=="bank" and "Withdraw the observed Runed Rod from your bank; tools are not consumed per enchant." or "Verify/acquire the required Runed Rod; unknown/higher-tier rod inventory is not a definite missing tool."
 end
 if f.actionType=="ENCHANT_APPLICATION" then
  output.currentRecipeOutput=nil;output.currentRecipeOutputStatus="NOT_APPLICABLE_ENCHANTS_EXISTING_ITEM"
  output.expectedOutputQuantity=nil;output.inventoryOutputAllowed=false
  local foundation=JLP:GetModule("ProductionEnchantingTargetedExecutionFoundation")
  local target=foundation and foundation.AssessRecipeTarget and foundation:AssessRecipeTarget(f.id)
  output.enchantTarget=target or {status="UNKNOWN",ready=false}
  if output.learned==true and output.requiredNextAction=="manual-craft" and not (target and target.ready) then
   output.requiredNextAction="verify";output.nextAction="Select and verify an eligible Optional Target item for "..f.name.." in the normal profession window. No bag-item output is expected."
  end
  output.completionProof="OBSERVED_ENCHANT_APPLICATION_TO_SAME_TARGET_GUID_NOT_ITEM_OUTPUT"
 elseif output.learned==true and output.requiredNextAction=="manual-craft" then
  local fact=self:Observe(professionKey,f.id)
  if not (fact.observed and fact.output and fact.output.itemID==f.output and fact.output.fixed) then
   output.requiredNextAction="verify";output.nextAction="Verify current physical item identity/yield for "..f.name.."; charges are not output stacks."
  end
 end
 local live=self:Observe(professionKey,f.id)
 output.reagentEvidence=live.requiredReagents and "CURRENT_EXPLICIT_FIXED_REQUIRED_SLOTS" or "DB2_70532_REFERENCE_RUNTIME_INPUTS_UNVERIFIED"
 if live.requiredReagents then
  local expected={};for id,n in f.reagents:gmatch("(%d+):(%d+)")do expected[tonumber(id)]=tonumber(n)end
  local conflict=false
  for id,n in pairs(live.requiredReagents)do if expected[id]~=n then conflict=true end;expected[id]=nil end
  if next(expected)then conflict=true end
  if conflict then output.requiredNextAction="verify";output.reagentEvidence="CONFLICT_CURRENT_SCHEMATIC_VS_DB2_70532"
   output.nextAction="Resolve the current schematic / build70532 reagent conflict for "..f.name.." before budgeting or a manual craft."end
 end
 -- Ordinary rods are consumed reagents; the Runed Rod remains a reusable tool.
 if output.learned==true and not output.bagReady and output.reagentEvidence~="CONFLICT_CURRENT_SCHEMATIC_VS_DB2_70532" and
    (not row.requiredTool or tool and (tool.status=="bags" or tool.status=="confirmed")) then
  local sources=JLP:GetModule("SourceResolver")
  for _,material in ipairs(row.materials or {})do
   local rod=sources and sources.GetOrdinaryRodAcquisition and sources:GetOrdinaryRodAcquisition(material.itemID,material.quantity)
   if rod and rod.status~="BAGS_OBSERVED" then
    output.ordinaryRodAcquisition=rod
    output.requiredNextAction=rod.status=="UNKNOWN_INVENTORY" and "verify" or "acquire"
    output.nextAction=rod.nextAction
    break
   end
  end
 end
 output.manualCraftBlockedByRecipePrerequisite=output.requiredNextAction=="verify"
 output.strategyEvidence={selection="QUALIFIED_LOCAL_SCENARIO_NOT_GLOBAL_OPTIMUM",totalTimeStatus="UNKNOWN_ACQUISITION_AND_TRAVEL_TIME",netCostStatus="UNKNOWN_SALE_AND_DISENCHANT_YIELDS",craftSeconds=row.castSeconds and row.scenarioCrafts and row.castSeconds*row.scenarioCrafts}
 if output.progressionScenario then output.progressionScenario.outputCreditStatus=f.actionType=="ENCHANT_APPLICATION" and "NOT_APPLICABLE_NON_ITEM_ENCHANT" or "EXPECTED_ONLY_CURRENT_SCHEMATIC_NOT_BAG_CREDIT"end
 local api=JLP:GetModule("ProfessionAPI")
 local profession=api and api.Get and api:Get(professionKey)
 local cap=profession and profession.maxSkill
 local unlock=cap==75 and 50 or cap==150 and 125 or cap==225 and (professionKey=="ENGINEERING" and 225 or 200)
 if professionKey~="COOKING" and unlock and output.skill>=unlock and output.skill<cap then
  output.rankOpportunity={rank=cap==75 and "Journeyman" or cap==150 and "Expert" or "Artisan",
   requiredSkill=unlock,requiredCharacterLevel=cap==75 and 10 or cap==150 and 20 or 35,
   currentCap=cap,necessaryNow=false,trainingObserved=false,readOnly=true}
 end
end

-- One-off tool preparation belongs to the SAME forecast/BOM. These entries
-- have zero skill span and cannot credit either skill or observed inventory.
function M:PlanEnchantingTools(route)
 local expanded,requirements={},{}
 local resolver=JLP:GetModule("EnchantingToolResolver")
 local plannedTier=0
 for _,step in ipairs(route or {})do
  local f=self:GetEnchantingContract(step.recipeID)
  if f and f.toolItemID and f.toolTier>plannedTier then
   local tool={itemID=f.toolItemID,rodTier=f.toolTier}
   local state=resolver and resolver:Resolve(tool)
   local entry={itemID=f.toolItemID,tier=f.toolTier,consumed=false,
    status=state and state.status or "unknown",observed=state,readOnly=true}
   requirements[#requirements+1]=entry
   if state and (state.status=="bags" or state.status=="confirmed") then plannedTier=state.rodTier or f.toolTier
   elseif state and state.status=="bank" then
    entry.requiredAction="WITHDRAW_OBSERVED_TOOL";plannedTier=state.rodTier or f.toolTier
   elseif state and state.status=="missing" then
    for _,producer in ipairs(self:GetEnchantingCandidates(step.skillStart or 1,true,true))do
     if producer.outputItemID==f.toolItemID and producer.requiredSkill<=(step.skillStart or 1) then
      expanded[#expanded+1]={recipeID=producer.recipeID,recipe=producer.recipe,
       skillStart=step.skillStart,skillEnd=step.skillStart,estimatedCrafts=1,
       materials=producer.materials,toolPreparation=true,observedOutputCredit=0,
       sourceBuild=70532,readOnly=true,nativeDispatchAllowed=false}
      entry.requiredAction="LEARN_AND_MANUALLY_PREPARE_ONCE";entry.preparationRecipeID=producer.recipeID
      plannedTier=f.toolTier;break
     end
    end
    if not entry.preparationRecipeID then entry.requiredAction="VERIFY_TOOL_RECIPE_REQUIREMENTS"end
   else entry.requiredAction="VERIFY_UNKNOWN_TOOL_INVENTORY"end
  end
  expanded[#expanded+1]=step
 end
 return expanded,requirements
end


-- Same dataset/facts/candidate pipeline as Enchanting; no parallel Planner.
-- Canonical generated data only; callers cannot supply arbitrary trainer aliases.
-- This relation grants no NPC access, exact minimum, learned-state or native call.
function M:GetQualifiedTeachingRelation(key,id)
 if key=="COOKING"and id==3102 then return {spellID=3412,recipeID=3102,effectID=682182,effect=36,difficultyID=0,sourceBuild=70532,sourceTable="SpellEffect"}end
 if key=="FISHING"and id==7731 then return {spellID=7734,recipeID=7731,effectID=685782,effect=36,difficultyID=0,sourceBuild=70532,sourceTable="SpellEffect"}end
 if key~="FIRST_AID" and key~="COOKING" then return nil end
 local f=self:GetAlchemyContract(id,key);local t=f and f.teaching
 if not f or f.id~=id or f.professionID~=(key=="COOKING" and 185 or 129) or f.sourceBuild~=70532 or
    type(t)~="table"or t.recipeID~=id or not positive(t.spellID)or t.spellID==id or
    not positive(t.effectID)or t.effect~=36 or t.difficultyID~=0 or
    t.sourceBuild~=70532 or t.sourceTable~="SpellEffect"then return nil end
 return t
end
function M:GetAlchemyContract(id,key)
 key=key or "ALCHEMY"
 local professionID=key=="FIRST_AID" and 129 or key=="COOKING" and 185 or key=="LEATHERWORKING" and 165 or key=="ENGINEERING" and 202 or key=="BLACKSMITHING" and 164 or 171
 local dataset=JLP.data and JLP.data[key:lower()]
 local root=dataset and dataset.progression
 local f=root and root.contract==key:lower().."-70532-progression-v1" and root.recipes[id]
 if not f or f.id~=id or f.professionID~=professionID or f.sourceBuild~=70532 or
    not positive(f.minimum) or not positive(f.gray) or (key~="BLACKSMITHING" and f.gray<f.minimum) or
    type(f.reagents)~="string" or not positive(f.output) or f.actionType~="CREATE_ITEM" then return nil end
 if f.recipeItemID and (f.patternProfessionID~=professionID or f.patternItemID~=f.recipeItemID or
    (key~="BLACKSMITHING" and not (key=="LEATHERWORKING" and f.learningConflict) and f.patternRequiredSkill~=f.learningMinimum) or f.patternTriggerType~=6)then return nil end
 local quantities={}
 for token in f.reagents:gmatch("[^,]+")do
  local item,n=token:match("^(%d+):(%d+)$");item,n=tonumber(item),tonumber(n)
  if not positive(item) or not positive(n) or quantities[item]then return nil end
  quantities[item]=n
 end
 if not next(quantities)then return nil end
 for _,m in ipairs(f.referenceMaterials or {})do
  if quantities[m.itemID]~=m.quantity then return nil end;quantities[m.itemID]=nil
 end
 if next(quantities)then return nil end -- no divergent packed/projected reagent contract
 return f,f
end
function M:GetAlchemyCandidates(skill,fullRoute)
 return self:GetEnchantingCandidates(skill,fullRoute,false,"ALCHEMY")
end
function M:GetAlchemyRankStep(profession)
 return self:GetEnchantingRankStep(profession,"ALCHEMY")
end
function M:GetAlchemyProducer(itemID,key)
 key=key or "ALCHEMY"
 local dataset=JLP.data and JLP.data[key:lower()]
 local root=dataset and dataset.progression
 for id in pairs(root and root.recipes or {})do
  local f=self:GetAlchemyContract(id,key)
  if key=="ENGINEERING" and f and f.specializationRequired and self:GetEngineeringSpecialization()~=f.specializationRequired then f=nil end
  if (key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="COOKING") and f and f.output==itemID then
   local live=self:Observe(key,id)
   local expected={};for reagent,n in f.reagents:gmatch("(%d+):(%d+)")do expected[tonumber(reagent)]=tonumber(n)end
   local parity=live.requiredReagents~=nil
   for reagent,n in pairs(live.requiredReagents or {})do if expected[reagent]~=n then parity=false end;expected[reagent]=nil end
   if next(expected)then parity=false end
   if live.observed and live.learned==true and parity and live.output and live.output.fixed and live.output.itemID==itemID then
    local copy={}for k,v in pairs(f)do copy[k]=v end
    copy.outputQuantity=live.output.minimum;copy.outputStatus="CURRENT_FIXED_SCHEMATIC_NOT_OBSERVED_BAG_TRANSACTION"
    return copy,live
   end
   return nil,"CURRENT_FIXED_OUTPUT_REQUIRED"
  end
  if f and f.output==itemID and not f.researchOnly and positive(f.outputQuantity) and not f.outputConflict then
   local live=self:Observe("ALCHEMY",id)
   if live.output and (not live.output.fixed or live.output.itemID~=itemID or live.output.minimum~=f.outputQuantity)then return nil,"CURRENT_OUTPUT_CONFLICT"end
   return f,live
  end
 end
end
function M:GetAlchemyPreparation(candidate,skill,choices,key)
 key=key or "ALCHEMY"
 local inventory=JLP:GetModule("Inventory")
 for _,mat in ipairs(candidate.materials or {})do
  local f,live=self:GetAlchemyProducer(mat.itemID,key)
  local stock=inventory and inventory.GetOwned and inventory:GetOwned(mat.itemID)
  if f and not (choices and choices[mat.itemID]==false) and skill>=f.minimum and stock and stock.bagKnown==true and type(stock.bags)=="number" and stock.bags<mat.quantity and
     stock.bankKnown==true and stock.bank==0 then
   if live and live.observed and live.learned==true then
    local materials={};for _,m in ipairs(f.referenceMaterials)do materials[#materials+1]=m end
    return {recipeID=f.id,recipe=f.name,requiredSkill=f.minimum,routeSkillMin=f.minimum,
     routeSkillTarget=f.gray,route=true,qualifiedProgression=true,
     sourceQualificationContract=key:lower().."-70532-progression-v1",sourceFact=f,
     rawYellow=f.yellow,rawGreen=f.green,rawGrey=f.gray,preparationOnly=true,
     skillTarget=skill,scenarioCrafts=1,materials=materials,recipeSource=f.learning,
     outputItemID=f.output,castSeconds=f.castSeconds,actionType=f.actionType,
     alchemyPreparationFor=candidate.recipeID,readOnly=true,nativeDispatchAllowed=false}
   end
  end
 end
end
function M:AnnotateAlchemy(output,row,key)
 key=key or "ALCHEMY"
 self:AnnotateEnchanting(output,row,key)
 local f=self:GetAlchemyContract(row.recipeID,key);if not f then return end
 output.alchemyPrerequisites={focusID=f.focusID,focusName=f.focusName,
  focusEvidence=f.focusEvidence,cooldownMilliseconds=f.cooldownMilliseconds,
  toolCategoryID=f.toolCategoryID,sourceBuild=70532}
 if row.alchemyPreparationFor then
  output.preparingIntermediate=true;output.preparationForRecipeID=row.alchemyPreparationFor
  output.manualCraftBlockedByLiveDifficulty=false;output.remainingCrafts=1;output.skillTarget=output.skill
 end
 -- A camp/ordinary station reference never proves the player is at that station.
 -- No qualified read-only station observation API contract exists in this baseline.
 local access="NO_SPECIAL_REQUIREMENT"
 if (f.focusID or 0)>0 or (f.cooldownMilliseconds or 0)>0 then
  local q=JLP:GetModule("TailoringRecipeQualification")
  access=q and q.RecipeAccess and q:RecipeAccess({recipeID=f.id,
   sourceSpellFocusReference=f.focusID>0 and f.focusID or nil,
   cooldownMS=f.cooldownMilliseconds>0 and f.cooldownMilliseconds or nil},key) or "UNKNOWN"
 end
 if key=="COOKING"and f.focusID and f.focusID>0 then output.stationStatus=access end
 if f.focusID==1 and (key=="BLACKSMITHING" or key=="ENGINEERING")then output.ordinaryAnvil=true;output.stationStatus=access;output.stationReadiness=access end
 if f.focusID and f.focusID>0 and access~="MET" and (key~="COOKING" or output.learned==true and output.bagReady==true) then
  if f.focusID==1 and (key=="BLACKSMITHING" or key=="ENGINEERING")then
   output.ordinaryAnvil=true;output.stationReadiness=access;output.manualCraftBlockedByStation=true
  else output.requiredNextAction="verify";output.manualCraftBlockedByRecipePrerequisite=true end
  output.nextAction="Verify required "..tostring(f.focusName or f.focusID).." at the current crafting location for "..f.name.."; materials alone do not prove station access. No station waypoint is qualified."
  output.stationStatus=access
 end
 if f.cooldownMilliseconds and f.cooldownMilliseconds>0 and access~="MET" then
  output.requiredNextAction="verify";output.manualCraftBlockedByRecipePrerequisite=true
  output.nextAction="Verify the current cooldown for "..f.name.."; source cooldown is not current readiness and nil is not zero."
  output.cooldownStatus=access
 end
 if key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" then
  output.blacksmithingPrerequisites=output.alchemyPrerequisites;output.alchemyPrerequisites=nil
  output.learningMinimumStatus=f.learningMinimum and f.minimumStatus or "UNKNOWN_EXACT_LEARNING_MINIMUM"
  output.recipeQualification=row.conditionalCurrentOnly and "CURRENT_LEARNED_COLOR_AND_FIXED_OUTPUT_ONLY_SOURCE_LEARNING_UNKNOWN" or f.minimumStatus
  output.acquisitionQualification=f.acquisitionStatus
  output.specializationStatus=f.specializationStatus
  if f.difficultyQualification=="CURRENT_COLOR_REQUIRED" then
   local live=self:Observe(key,f.id)
   if not live.skillup or live.skillup.tier=="UNKNOWN" then
    output.requiredNextAction="verify";output.manualCraftBlockedByRecipePrerequisite=true
    output.nextAction="Verify current recipe color: the public Forever difficulty list is incomplete/conflicts with the build70532 yellow field."
   end
  end
  if f.requiresTrainerOfferingObservation and output.learned~=true then
   local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
   local training=bridge and bridge.GetTrainerAcquisition and bridge:GetTrainerAcquisition(key,f.id)
   output.trainerAcquisition=training
   local status=training and training.status or "UNKNOWN"
   output.requiredNextAction=status=="AVAILABLE" and "learn-trainer" or "verify"
   if output.learned==nil then
    output.requiredNextAction="verify"
    output.nextAction="Inspect the current profession panel to establish learned-state for "..f.name.." before buying training. UNKNOWN is not unlearned."
   elseif status=="AVAILABLE" then
    output.nextAction="Learn "..f.name.." manually from the currently observed exact trainer offering; wait for a separate learned-state observation. Training intent or a closed trainer window is not learning."
   elseif status=="NOT_OFFERED" or status=="INELIGIBLE" then
    output.nextAction="The inspected trainer does not currently offer usable training for "..f.name..". Verify the menu/requirements or choose another qualified recipe; do not assume this recipe is learned."
   else
    local actor=training and training.primary
    output.nextAction="Verify "..(actor and actor.npcName or "the qualified trainer").."'s current offering for "..f.name.." (skill "..f.minimum.."), then learn manually and observe learned-state separately. A recipe-specific reference is not a live trainer menu."
   end
   output.manualCraftBlockedByRecipePrerequisite=output.requiredNextAction=="verify"
  end
 end
 if key=="LEATHERWORKING" then output.leatherworkingPrerequisites=output.blacksmithingPrerequisites;output.blacksmithingPrerequisites=nil end
 if key=="ENGINEERING" then
  output.engineeringPrerequisites=output.blacksmithingPrerequisites;output.blacksmithingPrerequisites=nil
  output.engineeringPrerequisites.tools={};output.itemUseAuthorized=false;output.inventoryOutputAllowed=true
  output.specializationObserved=self:GetEngineeringSpecialization();output.specializationRequired=f.specializationRequired
  if f.specializationRequired and output.specializationObserved~=f.specializationRequired then
   output.requiredNextAction="verify";output.manualCraftBlockedByRecipePrerequisite=true
   output.nextAction="Verify the explicitly chosen and actually learned "..f.specializationRequired.." specialization and recipe access. A preference, quest item or opposite specialization does not grant access."
  end
  output.productUseRequirements={profession=f.productUseProfession,skill=f.productUseSkill,level=f.productUseLevel,binding=f.productBinding,authorized=false}
  output.completionProof="OBSERVED_CRAFT_OUTPUT_AND_SEPARATE_SKILL_NOT_GADGET_USE"
  local profession=JLP:GetModule("ProfessionAPI")
  local current=profession and profession.Get and profession:Get(key)
  if current and current.maxSkill==225 and output.skill>=200 and output.skill<225 then
   output.rankOpportunity={rank="Artisan",requiredSkill=nil,candidateMinima={200,225},requiredCharacterLevel=35,currentCap=225,
    necessaryNow=false,trainingObserved=false,status="SOURCE_CONFLICT_VERIFY_CURRENT_TRAINER",readOnly=true}
  end
 end
 output.strategyEvidence.selection="QUALIFIED_LOCAL_SCENARIO_NOT_GLOBAL_OPTIMUM"
end

-- Engineering shares the physical pipeline; tools and specialization are
-- additional prerequisites, never another route planner or native dispatcher.
function M:GetEngineeringContract(id)return self:GetAlchemyContract(id,"ENGINEERING")end
function M:GetEngineeringCandidates(skill,fullRoute)return self:GetEnchantingCandidates(skill,fullRoute,false,"ENGINEERING")end
function M:GetEngineeringSpecialization()
 local fn=type(IsPlayerSpell)=="function" and IsPlayerSpell or IsSpellKnown
 if type(fn)~="function" then return "UNKNOWN"end
 local a,g=pcall(fn,20219);local b,o=pcall(fn,20222)
 local c,g2=pcall(fn,20219);local d,o2=pcall(fn,20222)
 if not(a and b and c and d)or fn~=(type(IsPlayerSpell)=="function" and IsPlayerSpell or IsSpellKnown)or type(g)~="boolean"or type(o)~="boolean"or g~=g2 or o~=o2 or g and o then return "UNKNOWN"end
 return g and "GNOMISH"or o and "GOBLIN"or "NONE"
end
function M:GetEngineeringRankStep(profession)
 local row=self:GetEnchantingRankStep(profession,"ENGINEERING")
 if row and row.rank=="Expert"then row.nextAction=row.nextAction.." Horde reference: Roxxik, Orgrimmar; observe actual cap225."
 elseif row and row.rank=="Artisan"then
  row.minimumSkill=nil;row.minimumSkillCandidates={200,225};row.minimumStatus="FOREVER_SOURCE_CONFLICT200_VS225"
  row.nextAction=row.nextAction.." Buzzek Bracketswing, Gadgetzan: sources disagree on learning at200 versus225; at the observed cap225 both candidate skill conditions are met. Current offering and cap300 still require observation."
 end
 return row
end
function M:GetEngineeringPreparation(candidate,skill,choices)
 return self:GetAlchemyPreparation(candidate,skill,choices,"ENGINEERING")
end
function M:PlanPhysicalTools(route,key)
 -- Ordinary reusable tools are player-managed, never forecast orders.
 return route or {},{}
end

-- Blacksmithing uses the same physical recipe, prerequisite and BOM contracts.
function M:GetBlacksmithingContract(id)return self:GetAlchemyContract(id,"BLACKSMITHING")end
function M:GetBlacksmithingCandidates(skill,fullRoute)return self:GetEnchantingCandidates(skill,fullRoute,false,"BLACKSMITHING")end
function M:GetBlacksmithingRankStep(profession)return self:GetEnchantingRankStep(profession,"BLACKSMITHING")end
JLP:RegisterModule("ProfessionPlanningFacts",M)

function M:GetLeatherworkingContract(id)return self:GetAlchemyContract(id,"LEATHERWORKING")end
function M:GetLeatherworkingCandidates(skill,fullRoute)return self:GetEnchantingCandidates(skill,fullRoute,false,"LEATHERWORKING")end
function M:GetLeatherworkingRankStep(profession)return self:GetEnchantingRankStep(profession,"LEATHERWORKING")end
