local _,JLP=...
-- P0-233: independently reviewed Forever spell pages + preserved DB70450
-- recipe/reagent provenance. Advisory ONLY. No learning, skill-up, quantity
-- of crafted outputs, source NPC, travel waypoint or native dispatch proof.
local M={contract="JLP-P0-233-PRIMARY-FOREVER-SOURCE-WINDOWS",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
-- Yellow/green/gray values are PUBLIC Forever reference thresholds, not
-- runtime observations. A gap is retained when public learning data is absent.
-- Reagents are direct per-craft only; web dependency expansion is NOT a reagent.
local specs={
 ALCHEMY={
  {id=2330,name="Minor Healing Potion",min=nil,yellow=nil,green=nil,gray=nil,
   reagents={{2447,1},{765,1},{3371,1}},
   url="https://www.wowhead.com/forever/spell=2330/minor-healing-potion"},
  {id=2335,name="Swiftness Potion",min=60,yellow=90,green=110,gray=130,
   reagents={{2452,1},{2450,1},{3371,1}},
   url="https://www.wowhead.com/forever/spell=2335/swiftness-potion"},
  {id=3173,name="Lesser Mana Potion",min=120,yellow=145,green=165,gray=185,
   reagents={{785,1},{3820,1},{3371,1}},
   url="https://www.wowhead.com/forever/spell=3173/lesser-mana-potion"},
  {id=1250784,name="Elixir of Greater Fortitude",min=200,yellow=205,green=207,gray=210,
   reagents={{8838,4},{8925,1}},
   url="https://www.wowhead.com/forever/spell=1250784/elixir-of-greater-fortitude"},
  {id=17553,name="Superior Mana Potion",min=260,yellow=275,green=295,gray=315,
   reagents={{8838,2},{8839,2},{8925,1}},
   url="https://www.wowhead.com/forever/spell=17553/superior-mana-potion"},
  {id=17571,name="Elixir of the Mongoose",min=280,yellow=295,green=315,gray=335,
   reagents={{13465,2},{13466,2},{8925,1}},
   url="https://www.wowhead.com/forever/spell=17571/elixir-of-the-mongoose"}},
 BLACKSMITHING={
  {id=3320,name="Rough Grinding Stone",min=25,yellow=45,green=65,gray=85,
   reagents={{2835,2}},url="https://www.wowhead.com/forever/spell=3320/rough-grinding-stone"},
  {id=7408,name="Heavy Copper Maul",min=65,yellow=80,green=100,gray=120,
   reagents={{2840,12},{2880,2},{2318,2}},url="https://www.wowhead.com/forever/spell=7408/heavy-copper-maul"}},
 ENGINEERING={{id=3953,name="Bronze Framework",min=145,yellow=145,green=170,gray=195,
   reagents={{2841,2},{2319,1},{2592,1}},url="https://www.wowhead.com/forever/spell=3953/bronze-framework"}},
 LEATHERWORKING={{id=2152,name="Light Armor Kit",min=1,yellow=30,green=45,gray=60,
   reagents={{2318,1}},url="https://www.wowhead.com/forever/spell=2152/light-armor-kit"}},
 TAILORING={{id=2963,name="Bolt of Linen Cloth",min=1,yellow=25,green=37,gray=50,
   reagents={{2589,2}},url="https://www.wowhead.com/forever/spell=2963/bolt-of-linen-cloth"}},
 ENCHANTING={
  {id=7421,name="Runed Copper Rod",min=nil,yellow=nil,green=nil,gray=nil,
   reagents={{6217,1},{247786,1}},url="https://www.wowhead.com/forever/spell=7421/runed-copper-rod"},
  {id=7420,name="Enchant Chest - Inferior Stamina",min=15,yellow=70,green=90,gray=110,
   reagents={{10940,1}},url="https://www.wowhead.com/forever/spell=7420/enchant-chest-inferior-stamina"},
  {id=14807,name="Greater Magic Wand",min=70,yellow=110,green=130,gray=150,
   reagents={{4470,1},{10938,2}},url="https://www.wowhead.com/forever/spell=14807/greater-magic-wand"},
  {id=7793,name="Enchant 2H Weapon - Lesser Intellect",min=100,yellow=130,green=150,gray=170,
   reagents={{10938,4}},url="https://www.wowhead.com/forever/spell=7793/enchant-2h-weapon-lesser-intellect"}},
}
local function whole(v) return type(v)=="number" and v==v and v>=0 and v<2147483647 and v==math.floor(v) end
local function canon(s) return type(s)=="string" and s:lower():gsub("[^%w]", "") or nil end
local function parsePackedLine(line)
 local f={};for part in (line.."^"):gmatch("([^%^]*)%^") do f[#f+1]=part end
 if #f~=12 then return nil end
 return f
end
local packedIndex,packedIdentity={},{ }
local function dbFor(key,id)
 local root=JLP.data and JLP.data.build70450Recipes
 local source=root and root.professions and root.professions[key]
 local packed=source and source.packed
 if type(packed)~="string" then return nil,"DB70450_SOURCE_MISSING" end
 if packedIdentity[key]~=packed then
  local byID={}
  for line in packed:gmatch("[^\n]+") do
   local f=parsePackedLine(line)
   local recipeID=f and tonumber(f[1])
   if recipeID then
    if byID[recipeID] then byID[recipeID]=false else byID[recipeID]=f end
   end
  end
  packedIndex[key]=byID;packedIdentity[key]=packed
 end
 local f=packedIndex[key][id]
 if f==false then return nil,"DUPLICATE_DB_RECIPE_ID" end
 if not f then return nil,"DB_RECIPE_NOT_FOUND" end
 return f
end
local function reagentsFromDB(value)
 if value=="?" or value=="-" or value=="" then return nil,"DB_REAGENTS_UNAVAILABLE" end
 local out,seen={},{}
 for part in value:gmatch("[^,]+") do
  local id,qty=part:match("^(%d+):(%d+)$")
  id,qty=tonumber(id),tonumber(qty)
  if not id or not whole(qty) or qty==0 or seen[id] then return nil,"DB_REAGENTS_INVALID" end
  seen[id]=true;out[id]=qty
 end
 return next(out) and out or nil,"DB_REAGENTS_UNAVAILABLE"
end
local function parity(spec,db)
 if not db then return "DB_RECIPE_NOT_VERIFIED" end
 if not db[12] or db[12]=="" then return "DB_RECIPE_NAME_UNAVAILABLE" end
 if canon(db[12])~=canon(spec.name) then return "SOURCE_RECIPE_NAME_CONFLICT" end
 local dbM,reason=reagentsFromDB(db[10])
 if not dbM then return reason end
 local count=0
 for _,r in ipairs(spec.reagents) do
  if dbM[r[1]]~=r[2] then return "SOURCE_REAGENT_CONFLICT" end
  count=count+1
 end
 local n=0;for _ in pairs(dbM) do n=n+1 end
 if n~=count then return "SOURCE_REAGENT_CONFLICT" end
 if spec.yellow and tonumber(db[4])~=spec.yellow then return "SOURCE_YELLOW_THRESHOLD_CONFLICT" end
 if spec.gray and tonumber(db[5])~=spec.gray then return "SOURCE_GRAY_THRESHOLD_CONFLICT" end
 return spec.yellow and "EXACT_FOREVER_DB70450_REAGENT_AND_THRESHOLD_PARITY" or
  "EXACT_FOREVER_DB70450_REAGENT_PARITY_DIFFICULTY_UNKNOWN"
end
local function color(r,skill)
 if not r.min then return "UNKNOWN" end
 if skill<r.min then return "NOT_YET_ELIGIBLE" end
 if skill<r.yellow then return "ORANGE_REFERENCE" end
 if skill<r.green then return "YELLOW_REFERENCE" end
 if skill<r.gray then return "GREEN_REFERENCE" end
 return "GRAY_REFERENCE"
end
local function preferred(a,b)
 if not a or not a.eligibleReferenceCandidate then return b end
 if not b or not b.eligibleReferenceCandidate then return a end
 local weight={ORANGE_REFERENCE=3,YELLOW_REFERENCE=2,GREEN_REFERENCE=1}
 local x,y=weight[a.referenceDifficulty] or 0,weight[b.referenceDifficulty] or 0
 if y>x then return b end
 if y==x and (b.minimumSkill or 0)>(a.minimumSkill or 0) then return b end
 return a
end
local function copyMaterials(rows,inventory)
 local out={}
 for _,r in ipairs(rows) do
  local known=type(inventory)=="table" and whole(inventory[r[1]]) or false
  local owned=known and inventory[r[1]] or nil
  out[#out+1]={itemID=r[1],perCraft=r[2],bagsKnown=known,
   bags=owned,missing=known and math.max(0,r[2]-owned) or nil,
   readOnly=true}
 end
 table.sort(out,function(a,b)return a.itemID<b.itemID end)
 return out
end
function M:AtSkill(key,skill,opts)
 key=tostring(key or ""):upper();opts=type(opts)=="table" and opts or {}
 if not whole(skill) or skill<1 or skill>=300 or not specs[key] then
  return nil,"UNSUPPORTED_OR_INVALID_PROFESSION_SKILL" end
 local result={contract=self.contract,professionKey=key,skill=skill,
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  continuousClientRoute=false,verifiedSkillUps=0,recipes={},qualifiedCurrentWindows=0,
  sourceGaps=0,sourceProvenance="WOWHEAD_FOREVER_AND_DB70450_FIELD_PARITY"}
 for _,s in ipairs(specs[key]) do
  local db,dbreason=dbFor(key,s.id)
  local state=db and parity(s,db) or dbreason
  local sourceColor=color(s,skill)
  local learned=opts.learnedRecipes and opts.learnedRecipes[s.id]
  if type(learned)~="boolean" then learned=nil end
  local materials=copyMaterials(s.reagents,opts.inventory)
  local matched=state=="EXACT_FOREVER_DB70450_REAGENT_AND_THRESHOLD_PARITY" or
     state=="EXACT_FOREVER_DB70450_REAGENT_PARITY_DIFFICULTY_UNKNOWN"
  local active=matched and (sourceColor=="ORANGE_REFERENCE" or
   sourceColor=="YELLOW_REFERENCE" or sourceColor=="GREEN_REFERENCE")
  local action="VERIFY_RECIPE_SOURCE"
  if not matched then action="VERIFY_SOURCE_CONFLICT_OR_MISSING_DB" 
  elseif sourceColor=="NOT_YET_ELIGIBLE" then action="VERIFY_REQUIRED_PROFESSION_SKILL"
  elseif sourceColor=="GRAY_REFERENCE" then action="SEEK_OTHER_SKILLUP_RECIPE"
  elseif sourceColor=="UNKNOWN" then action="VERIFY_RECIPE_DIFFICULTY_AND_MINIMUM"
  elseif learned==false then action="VERIFY_LEARNING_SOURCE"
  elseif learned==nil then action="VERIFY_LEARNED_STATE"
  else
   local unknown,missing=false,0
   for _,m in ipairs(materials) do
    if not m.bagsKnown then unknown=true else missing=missing+(m.missing or 0) end
   end
   action=unknown and "VERIFY_BAG_COUNTS" or
      (missing>0 and "ACQUIRE_REAGENTS_MANUALLY" or "REVIEW_MANUAL_ONE_CRAFT")
  end
  local r={recipeID=s.id,recipe=s.name,sourceURL=s.url,
   minimumSkill=s.min,minimumEvidence=s.min and "WOWHEAD_FOREVER_SPELL" or "UNKNOWN",
   referenceYellow=s.yellow,referenceGreen=s.green,referenceGray=s.gray,
   referenceDifficulty=sourceColor,sourceStatus=state,exactReagentsQualified=matched,
   reagentsPerCraft=materials,learned=learned,
   learnedEvidence=learned==nil and "UNKNOWN" or "INPUT_ADVISORY_NOT_LIVE_RECEIPT",
   teachingSourceStatus="NPC_OR_TEACHING_ITEM_NOT_VERIFIED",
   outputYieldStatus="NOT_INDEPENDENTLY_QUALIFIED",
   navigationStatus="LOCATION_UNVERIFIED",canonicalWaypointVerified=false,
   nextRequiredAction=action,readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
   canGuaranteeNextSkill=false,craftReceiptObserved=false,skillUpReceiptObserved=false,
   eligibleReferenceCandidate=active}
  result.recipes[#result.recipes+1]=r
  if active then result.qualifiedCurrentWindows=result.qualifiedCurrentWindows+1
  else result.sourceGaps=result.sourceGaps+1 end
 end
 return result
end
function M:Continuity(key,startSkill)
 key=tostring(key or ""):upper();startSkill=tonumber(startSkill)
 if not specs[key] or not whole(startSkill) or startSkill<1 or startSkill>300 then
  return nil,"INVALID_PROFESSION_OR_START" end
 local result={contract=self.contract,professionKey=key,skillStart=startSkill,skillGoal=300,
  readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
  complete1300=false,verifiedSkillUps=0,segments={},referencePositions=0,
  unqualifiedPositions=0,firstGap=nil}
 if startSkill==300 then return result end
 local prev
 for skill=startSkill,299 do
  local snapshot=self:AtSkill(key,skill)
  local winner
  for _,r in ipairs(snapshot.recipes) do winner=preferred(winner,r) end
  if winner and not winner.eligibleReferenceCandidate then winner=nil end
  local status=winner and "FOREVER_DB_REFERENCE_WINDOW_NOT_SKILLUP_PROOF" or "UNQUALIFIED_SOURCE_GAP"
  if winner then result.referencePositions=result.referencePositions+1
  else result.unqualifiedPositions=result.unqualifiedPositions+1;result.firstGap=result.firstGap or skill end
  if prev and prev.toSkill==skill and prev.recipeID==(winner and winner.recipeID) and prev.status==status then
   prev.toSkill=skill+1
  else
   prev={fromSkill=skill,toSkill=skill+1,recipeID=winner and winner.recipeID,
    recipe=winner and winner.recipe,status=status,nativeDispatchAllowed=false,
    verifiedSkillUps=0}
   result.segments[#result.segments+1]=prev
  end
 end
 return result
end
JLP:RegisterModule("ForeverPrimarySourceWindows233",M)
