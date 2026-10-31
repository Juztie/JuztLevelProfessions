local _,JLP=...
-- P0-235: additional explicitly sourced, read-only Forever spell windows.
-- No candidate can override negative live facts, create a native click, or authorize
-- a travel waypoint. Skill colours are public reference thresholds, not receipts.
local M={contract="JLP-P0-235-EXACT-SPELL-WINDOW-ALTERNATIVES",
 readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
-- min=nil means no independent learning-minimum proof: the row is still
-- useful for reagent conflict detection but never becomes a skillup candidate.
local specs={
 ALCHEMY={
  {2329,"Elixir of Minor Strength",1,55,75,95,{{2449,1},{765,1},{3371,1}},"TRAINER_CATEGORY"},
  {2334,"Elixir of Minor Fortitude",50,80,100,120,{{2449,2},{2447,1},{3371,1}},"TRAINER_CATEGORY"}},
 BLACKSMITHING={
  {2660,"Rough Sharpening Stone",1,15,35,55,{{2835,1}},"STARTER_CATEGORY"},
  {3326,"Coarse Grinding Stone",nil,50,65,75,{{2836,2}},"TRAINER_CATEGORY"}},
 ENGINEERING={
  {3918,"Rough Blasting Powder",1,20,30,40,{{2835,1}},"STARTER_CATEGORY"},
  {3924,"Copper Tube",50,80,95,110,{{2840,2},{2880,1}},"TRAINER_CATEGORY", "ANVIL"}},
 LEATHERWORKING={
  {2881,"Light Leather",1,20,30,40,{{2934,3}},"TRAINER_CATEGORY"},
  {3816,"Cured Light Hide",30,50,60,70,{{783,1},{4289,1}},"TRAINER_CATEGORY"}},
 TAILORING={
  {8776,"Linen Belt",15,50,67,85,{{2996,1},{2320,1}},"TRAINER_CATEGORY"},
  {3839,"Bolt of Silk Cloth",nil,110,115,120,{{4306,4}},"TRAINER_CATEGORY"}},
 ENCHANTING={
  {14293,"Lesser Magic Wand",10,75,95,115,{{4470,1},{10938,1}},"TRAINER_CATEGORY",nil,6218},
  -- Contemporary identity conflict with historic 7418 "Minor Health": do not
  -- transform it into a positive native/advisory recommendation.
  {7418,"Enchant Bracer - Minor Health",nil,nil,nil,nil,{{10940,1}},"HISTORICAL_CONFLICT"}},
}
local slugs={ALCHEMY={[2329]="elixir-of-minor-strength",[2334]="elixir-of-minor-fortitude"},
 BLACKSMITHING={[2660]="rough-sharpening-stone",[3326]="coarse-grinding-stone"},
 ENGINEERING={[3918]="rough-blasting-powder",[3924]="copper-tube"},
 LEATHERWORKING={[2881]="light-leather",[3816]="cured-light-hide"},
 TAILORING={[8776]="linen-belt",[3839]="bolt-of-silk-cloth"},
 ENCHANTING={[14293]="lesser-magic-wand",[7418]="enchant-bracer-minor-health"}}
local cache,identity={},{}
local function whole(v) return type(v)=="number" and v==v and v>=0 and v<2147483647 and v==math.floor(v) end
local function canon(s)return type(s)=="string" and s:lower():gsub("[^%w]","") or nil end
local function dbrow(key,id)
 local p=JLP.data and JLP.data.build70450Recipes and JLP.data.build70450Recipes.professions
 local packed=p and p[key] and p[key].packed
 if type(packed)~="string" then return nil,"DB70450_SOURCE_MISSING" end
 if identity[key]~=packed then
  local rows={}
  for line in packed:gmatch("[^\n]+") do
   local f={};for v in (line.."^"):gmatch("([^%^]*)%^") do f[#f+1]=v end
   if #f==12 then
    local id=tonumber(f[1]);if id then rows[id]=rows[id] and false or f end
   end
  end
  identity[key]=packed;cache[key]=rows
 end
 local f=cache[key][id]
 if f==false then return nil,"DB_RECIPE_DUPLICATE" end
 return f,f and nil or "DB_RECIPE_ABSENT"
end
local function verify(s,f)
 if not f then return "DB_RECIPE_ABSENT" end
 if canon(s[2])~=canon(f[12]) then return "SOURCE_RECIPE_NAME_CONFLICT" end
 local packed=f[10]
 if packed=="?" or packed=="-" or packed=="" then return "DB_REAGENTS_UNKNOWN" end
 local a={};local count=0
 for pair in packed:gmatch("[^,]+") do
  local i,n=pair:match("^(%d+):(%d+)$");i=tonumber(i);n=tonumber(n)
  if not i or not whole(n) or n==0 or a[i] then return "DB_REAGENTS_INVALID" end
  a[i]=n;count=count+1
 end
 for _,r in ipairs(s[7]) do if a[r[1]]~=r[2] then return "SOURCE_REAGENT_CONFLICT" end end
 if count~=#s[7] then return "SOURCE_REAGENT_CONFLICT" end
 if s[4] and tonumber(f[4])~=s[4] then return "SOURCE_YELLOW_CONFLICT" end
 if s[6] and tonumber(f[5])~=s[6] then return "SOURCE_GRAY_CONFLICT" end
 if not s[3] or not s[4] or not s[5] or not s[6] then return "LEARNING_MINIMUM_OR_DIFFICULTY_NOT_QUALIFIED" end
 return "FOREVER_PUBLIC_DB70450_REAGENT_THRESHOLD_PARITY"
end
local function color(s,skill)
 if not s[3] then return "UNKNOWN" end
 if skill<s[3] then return "NOT_YET_ELIGIBLE" end
 if skill<s[4] then return "ORANGE_REFERENCE" end
 if skill<s[5] then return "YELLOW_REFERENCE" end
 if skill<s[6] then return "GREEN_REFERENCE" end
 return "GRAY_REFERENCE"
end
local function sourceURL(key,s)
 return "https://www.wowhead.com/forever/spell="..s[1].."/"..slugs[key][s[1]]
end
function M:AtSkill(key,skill,options)
 key=tostring(key or ""):upper();options=type(options)=="table" and options or {}
 if not specs[key] or not whole(skill) or skill<1 or skill>=300 then return nil,"INVALID_PROFESSION_SKILL" end
 local out={contract=self.contract,professionKey=key,skill=skill,recipes={},candidates={},
  readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
  verifiedSkillUps=0,complete1300=false,canonicalWaypointQualified=false}
 for _,s in ipairs(specs[key]) do
  local f=dbrow(key,s[1]);local parity=verify(s,f);local shade=color(s,skill)
  local qualified=parity=="FOREVER_PUBLIC_DB70450_REAGENT_THRESHOLD_PARITY"
  local active=qualified and shade~="NOT_YET_ELIGIBLE" and shade~="GRAY_REFERENCE"
  local known=nil
  if type(options.learnedRecipes)=="table" then known=options.learnedRecipes[s[1]] end
  if type(known)~="boolean" then known=nil end
  local mats={};local unknown,shortage=false,false;local total=0
  for _,v in ipairs(s[7]) do
   local bags=type(options.inventory)=="table" and options.inventory[v[1]] or nil
   local observed=whole(bags)
   local missing=observed and math.max(0,v[2]-bags) or nil
   mats[#mats+1]={itemID=v[1],perCraft=v[2],bagsKnown=observed,
    bags=observed and bags or nil,missing=missing}
   if not observed then unknown=true else
    if missing>0 then shortage=true end
    total=total+missing
   end
  end
  local action=not qualified and "VERIFY_SOURCE_CONFLICT" or
   not active and "SEEK_ELIGIBLE_ALTERNATIVE" or
   known==false and "VERIFY_LEARNING_SOURCE" or
   known==nil and "VERIFY_LEARNED_STATE" or
   unknown and "VERIFY_BAG_COUNTS" or shortage and "ACQUIRE_REAGENTS_MANUALLY" or
   "REVIEW_MANUAL_ONE_CRAFT"
  local r={recipeID=s[1],recipe=s[2],sourceURL=sourceURL(key,s),sourceStatus=parity,
   minimumSkill=s[3],yellow=s[4],green=s[5],gray=s[6],referenceDifficulty=shade,
   reagentsPerCraft=mats,learningCategory=s[8],learningActorID=nil,
   currentActorAccess="UNKNOWN",trainingAvailability="UNKNOWN",
   workstation=s[9],workstationVerified=s[9]==nil and "NOT_SPECIFIED_IN_SOURCE" or "FACILITY_NOT_LOCATED",
   requiredToolItemID=s[10],toolAvailability="UNKNOWN",
   learned=known,inventoryKnown=not unknown,knownMissingPerCraft=not unknown and total or nil,
   nextRequiredAction=action,eligibleReferenceCandidate=active,
   exactReagentsQualified=qualified,outputYieldQualified=false,
   expectedCrafts=nil,readOnly=true,nativeDispatchAllowed=false,
   executionEligible=false,canonicalWaypointQualified=false}
  out.recipes[#out.recipes+1]=r
  if active then out.candidates[#out.candidates+1]=r end
 end
 return out
end
local weights={ORANGE_REFERENCE=3,YELLOW_REFERENCE=2,GREEN_REFERENCE=1}
-- A scenario comparison, NEVER an assertion of global cost optimality.
-- Material costs are comparable only with observed unit prices for every
-- candidate. No quote is interpreted as zero, and cached bank is not spendable.
function M:Select(key,skill,options)
 local report,why=self:AtSkill(key,skill,options)
 if not report then return nil,why end
 options=type(options)=="table" and options or {}
 local mode=options.strategy or options.mode or "Fastest"
 local prices=options.prices
 local priceComplete=type(prices)=="table" and #report.candidates>0
 local inventoryComplete=#report.candidates>0
 for _,c in ipairs(report.candidates) do
  local cost=0
  for _,m in ipairs(c.reagentsPerCraft) do
   local unit=type(prices)=="table" and prices[m.itemID] or nil
   if not whole(unit) then priceComplete=false
   else cost=cost+unit*m.perCraft end
   if not m.bagsKnown then inventoryComplete=false end
  end
  c.sourceUnitCost=priceComplete and cost or nil
 end
 if not priceComplete then
  for _,c in ipairs(report.candidates) do c.sourceUnitCost=nil end
 end
 report.strategy=mode
 report.priceComparisonQualified=priceComplete
 report.inventoryComparisonQualified=inventoryComplete
 report.strategyFallback=(mode=="Economical" and not priceComplete) and
   "PRICE_EVIDENCE_INCOMPLETE_USE_DIFFICULTY" or
   (mode=="Self-found" and not inventoryComplete) and
   "INVENTORY_EVIDENCE_INCOMPLETE_USE_DIFFICULTY" or nil
 local function rank(c)
  local learned=c.learned==true and 2 or c.learned==nil and 1 or 0
  local difficulty=weights[c.referenceDifficulty] or 0
  if mode=="Economical" and priceComplete then
   return learned,-c.sourceUnitCost,difficulty
  elseif mode=="Self-found" and inventoryComplete then
   return learned,-c.knownMissingPerCraft,difficulty
  end
  return learned,difficulty,0
 end
 local winner,first,second,third
 for _,c in ipairs(report.candidates) do
  local a,b,d=rank(c)
  if not winner or a>first or (a==first and (b>second or
   (b==second and (d>third or (d==third and c.recipeID<winner.recipeID))))) then
   winner,first,second,third=c,a,b,d
  end
 end
 return winner,report
end
function M:Continuity(key,startSkill)
 key=tostring(key or ""):upper()
 if not specs[key] or not whole(startSkill) or startSkill<1 or startSkill>300 then
  return nil,"INVALID_PROFESSION_START" end
 local out={contract=self.contract,professionKey=key,fromSkill=startSkill,toSkill=300,
  segments={},sourceReferencePositions=0,unqualifiedPositions=0,firstGap=nil,
  readOnly=true,complete1300=false,verifiedSkillUps=0,nativeDispatchAllowed=false}
 local previous
 for skill=startSkill,299 do
  local winner=self:Select(key,skill,{strategy="Fastest"})
  local id=winner and winner.recipeID;local status=id and "QUALIFIED_READ_ONLY_RECIPE_WINDOW" or "UNQUALIFIED_SOURCE_GAP"
  if id then out.sourceReferencePositions=out.sourceReferencePositions+1
  else out.unqualifiedPositions=out.unqualifiedPositions+1;out.firstGap=out.firstGap or skill end
  if previous and previous.toSkill==skill and previous.recipeID==id then previous.toSkill=skill+1
  else previous={fromSkill=skill,toSkill=skill+1,recipeID=id,recipe=winner and winner.recipe,
   status=status,readOnly=true,nativeDispatchAllowed=false};out.segments[#out.segments+1]=previous end
 end
 return out
end
JLP:RegisterModule("ForeverProgressionWindows235",M)
