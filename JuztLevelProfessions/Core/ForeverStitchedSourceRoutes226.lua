local _,JLP=...
-- P0-226: first concrete, bounded research stitches. A source-backed alternative
-- is NOT a skill gain, trainer stock, live recipe access or native permission.
-- Source references are checked on every call; no persistent source cache.
local M={contract="JLP-STITCHED-SOURCE-ROUTES-226",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local GUIDE="https://mobalytics.gg/wow-forever/guides/leatherworking-profession-guide"
local BS_GUIDE="https://www.mmojugg.com/news/wow-forever-blacksmithing-guide.html"
local profiles={
 BLACKSMITHING={
  {id=2660,name="Rough Sharpening Stone",lo=1,hi=25,kind="GUIDE_RANGE_NOT_LIVE_DIFFICULTY",guide=BS_GUIDE},
  {id=3320,name="Rough Grinding Stone",lo=25,hi=65,min=25,yellow=45,green=65,gray=85,kind="FOREVER_PUBLISHED_DIFFICULTY",guide="https://www.wowhead.com/forever/spell=3320/rough-grinding-stone"},
  {id=7408,name="Heavy Copper Maul",lo=65,hi=120,min=65,yellow=80,green=100,gray=120,kind="FOREVER_PUBLISHED_DIFFICULTY",guide="https://www.wowhead.com/forever/spell=7408/heavy-copper-maul"},
 },
 LEATHERWORKING={
  {id=2152,name="Light Armor Kit",lo=1,hi=55,min=1,yellow=30,green=45,gray=60,kind="FOREVER_PUBLISHED_DIFFICULTY",guide="https://www.wowhead.com/forever/spell=2152/light-armor-kit"},
  {id=3756,name="Embossed Leather Gloves",lo=55,hi=75,kind="FOREVER_GUIDE_RANGE_DIFFICULTY_UNVERIFIED",guide=GUIDE},
 },
}
local alternatives={
 BLACKSMITHING={
  {id=3320,name="Rough Grinding Stone",lo=65,hi=85,min=25,gray=85,
   kind="FOREVER_PUBLISHED_DIFFICULTY",guide="https://www.wowhead.com/forever/spell=3320/rough-grinding-stone"},
 },
 LEATHERWORKING={
  {id=2881,name="Light Leather",lo=1,hi=30,kind="FOREVER_GUIDE_RANGE_DIFFICULTY_UNVERIFIED",guide=GUIDE},
  {id=3816,name="Cured Light Hide",lo=30,hi=55,kind="GUIDE_RANGE_MINIMUM_UNVERIFIED",guide=GUIDE},
  {id=2152,name="Light Armor Kit",lo=55,hi=60,min=1,gray=60,
   kind="FOREVER_PUBLISHED_DIFFICULTY",guide="https://www.wowhead.com/forever/spell=2152/light-armor-kit"},
 },
}
local function integer(x)return type(x)=="number" and x==math.floor(x) and x>0 end
local function cloneReagents(input)
 local out,seen={},{}
 if type(input)~="table" or #input==0 then return nil end
 for _,r in ipairs(input) do
  if type(r)~="table" or not integer(r.itemID) or not integer(r.quantity) or seen[r.itemID] then return nil end
  seen[r.itemID]=true;out[#out+1]={itemID=r.itemID,quantity=r.quantity,perCraft=r.quantity}
 end
 table.sort(out,function(a,b)return a.itemID<b.itemID end)
 return out
end
local function packedRow(key,id)
 local db=JLP.data and JLP.data.build70450Recipes
 local src=db and db.professions and db.professions[key]
 if not src or type(src.packed)~="string" then return nil,"DB70450_UNAVAILABLE" end
 local found=nil
 for line in src.packed:gmatch("[^\n]+") do
  line=line:gsub("^.*%[==%[","")
  if tonumber(line:match("^(%d+)%^"))==id then
   if found then return nil,"DUPLICATE_DB70450_SPELL" end
   local cols={};for v in (line.."^"):gmatch("([^%^]*)%^") do cols[#cols+1]=v end
   if #cols~=12 then return nil,"INVALID_DB70450_RECORD" end
   local m={};local seen={}
   for t in cols[10]:gmatch("[^,]+") do
    local iid,qty=t:match("^(%d+):(%d+)$");iid=tonumber(iid);qty=tonumber(qty)
    if not integer(iid) or not integer(qty) or seen[iid] then return nil,"INVALID_DB70450_REAGENTS" end
    seen[iid]=true;m[#m+1]={itemID=iid,quantity=qty}
   end
   found={recipeID=id,name=cols[12],materials=cloneReagents(m),outputItemID=tonumber(cols[11]:match("^(%d+):"))}
  end
 end
 if not found then return nil,"DB70450_RECIPE_NOT_FOUND" end
 return found
end
local function sourced(key,c)
 local db,reason=packedRow(key,c.id)
 if not db then return nil,reason end
 if db.name~=c.name or not db.materials then return nil,"DB70450_RECIPE_IDENTITY_CONFLICT" end
 local row,source
 local refs=JLP:GetModule("ForeverRecipeAuthority")
 if refs and type(refs.GetReference)=="function" then
  local ok,value=pcall(refs.GetReference,refs,key,c.id,c.name)
  if ok and type(value)=="table" and value.recipeID==c.id and value.name==c.name then
   row=value;source=value.sourceURL
  end
 end
 if not row then
  local parent=JLP.data and JLP.data.foreverPrimaryRecipeParity212
  local v=parent and parent.rows and parent.rows[c.id]
  if parent and parent.conflicts and parent.conflicts[c.id] then return nil,"EXTERNAL_SOURCE_CONFLICT" end
  if type(v)=="table" and v.professionKey==key and v.recipeID==c.id and v.recipeName==c.name and
     v.status=="EXACT_FOREVER_SPELL_AND_DB70450_PARITY" then
   row={reagents=v.materials,outputItemID=v.outputItemID,outputQuantity=v.outputQuantity};source=v.source
  end
 end
 if not row then return nil,"EXACT_FOREVER_SOURCE_NOT_LOADED" end
 if type(source)~="string" or not source:find("^https://www%.wowhead%.com/forever/spell="..c.id) then
  return nil,"UNTRUSTED_RECIPE_SOURCE_URL" end
 local m=cloneReagents(row.reagents)
 if not m or #m~=#db.materials then return nil,"EXTERNAL_DB70450_REAGENT_COUNT_CONFLICT" end
 for i,r in ipairs(m) do
  if not db.materials[i] or db.materials[i].itemID~=r.itemID or db.materials[i].quantity~=r.quantity then
   return nil,"EXTERNAL_DB70450_REAGENT_QUANTITY_CONFLICT" end
 end
 -- Output yield is independently source-pinned only through exact graph parity.
 local outID,outQty=nil,nil
 local graph=JLP:GetModule("CrossProfessionDependencyPlanner")
 if graph and type(graph.Resolve)=="function" then
  local ok,producer=pcall(graph.Resolve,graph,key,c.id)
  if ok and type(producer)=="table" and
   producer.primarySourceParity=="EXACT_SPELL_OUTPUT_REAGENTS_NAME" and
   type(producer.primarySourceURL)=="string" and
   tonumber(producer.primarySourceURL:match("^https://www%.wowhead%.com/forever/spell=(%d+)[/%w%-]*$"))==c.id then
   outID,outQty=producer.outputItemID,producer.outputPerCraft
  end
 end
 return {recipeID=c.id,recipe=c.name,reagentsPerCraft=m,recipeSourceURL=source,
   outputEvidence=integer(outID) and integer(outQty) and
     {itemID=outID,quantityPerCraft=outQty,source="EXACT_FOREVER_DB_OUTPUT"} or nil,
   recipeProvenance="EXACT_FOREVER_DB70450_REAGENT_PARITY",researchWindowSource=c.guide,
   rangeEvidence=c.kind,sourceMinimumSkill=c.min,referenceYellow=c.yellow,
   referenceGreen=c.green,referenceGray=c.gray,learningSourceStatus="NOT_VERIFIED_FOR_THIS_CHARACTER",
   trainerStockVerified=false,learnedObserved=false,liveDifficultyObserved=false,
   stationLocationQualified=false,navigationQualified=false,
   craftReceiptObserved=false,skillUpReceiptObserved=false,
   craftCountForecast=nil,materialBudgetForecast=nil,
   nativeDispatchAllowed=false,executionEligible=false,readOnly=true}
end
local function active(c,skill) return skill>=c.lo and skill<c.hi end
function M:AtSkill(key,skill)
 key=tostring(key or ""):upper()
 if not integer(skill) or skill>=300 then return nil,"SKILL_OUTSIDE_1_299" end
 local profile=profiles[key]
 local result={contract=self.contract,professionKey=key,skill=skill,
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  verifiedSkillUps=0,continuousClientRoute=false,
  actionableNow=false,candidates={},sourceGap=true,
  nextRequiredEvidence="EXACT_RECIPE_SOURCE_AND_LIVE_PROGRESSION_OBSERVATION"}
 if not profile then result.reason="NO_STITCHED_RESEARCH_SEGMENT";return result end
 local primary
 for _,c in ipairs(profile) do if active(c,skill) then primary=c;break end end
 if primary then
  local row,why=sourced(key,primary)
  if row and (not primary.min or skill>=primary.min) then
   row.primary=true;result.candidates[#result.candidates+1]=row
   result.sourceGap=false;result.nextRequiredEvidence="LIVE_LEARNED_INVENTORY_DIFFICULTY_CRAFT_SKILLUP"
  else result.reason=why or "REFERENCE_MINIMUM_NOT_MET" end
 end
 for _,c in ipairs(alternatives[key] or {}) do
  if active(c,skill) then
   local row=sourced(key,c)
   if row and (not c.min or skill>=c.min) then
    row.primary=false;result.candidates[#result.candidates+1]=row
   end
  end
 end
 if not primary then result.reason="NO_CURATED_CONTIGUOUS_SKILL_WINDOW" end
 -- Even source-backed research intervals never count as verified skill coverage.
 return result
end
function M:Build(key,startSkill,stopSkill)
 startSkill=tonumber(startSkill);stopSkill=tonumber(stopSkill) or 300
 if not integer(startSkill) or not integer(stopSkill) or stopSkill>300 or startSkill>=stopSkill then
  return nil,"INVALID_SKILL_INTERVAL" end
 local r={contract=self.contract,professionKey=tostring(key or ""):upper(),
  fromSkill=startSkill,toSkill=stopSkill,readOnly=true,nativeDispatchAllowed=false,
  executionEligible=false,continuousClientRoute=false,verifiedSkillUps=0,
  positions={},sourceCandidatePositions=0,sourceGaps=0,firstSourceGap=nil}
 for skill=startSkill,stopSkill-1 do
  local state=self:AtSkill(key,skill)
  r.positions[#r.positions+1]=state
  if state and not state.sourceGap then r.sourceCandidatePositions=r.sourceCandidatePositions+1
  else r.sourceGaps=r.sourceGaps+1;r.firstSourceGap=r.firstSourceGap or skill end
 end
 return r
end
JLP:RegisterModule("ForeverStitchedSourceRoutes226",M)
