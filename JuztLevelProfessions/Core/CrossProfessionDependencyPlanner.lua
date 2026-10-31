local _, JLP = ...
-- Source-pinned account BOM graph. Never treats another character's inventory
-- or possible future crafts as current-character spendable stock. Each edge
-- joins exact profession + SpellID + CreateItem itemID + independent fixed yield.
-- DB70450 reagents are historical recipe facts, not live recipe access.
local M={contract="JLP-CROSS-PROFESSION-DEPENDENCIES-200",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local floor,ceil=math.floor,math.ceil
local function pos(n)
 return type(n)=="number" and n==n and n>0 and n==floor(n) and n<2147483647 and n~=math.huge
end
local function integer(n)
 return type(n)=="number" and n==n and n>=0 and n==floor(n) and n<2147483647
end
local function parsePackedRow(line)
 local fields={};for v in (line.."^"):gmatch("([^%^]*)%^") do fields[#fields+1]=v end
 if #fields~=12 then return nil end
 local id=tonumber(fields[1]);if not pos(id) then return nil end
 local reagents={};local seen={};local raw=fields[10]
 if raw=="?" or raw=="-" or raw=="" then return nil end
 for segment in raw:gmatch("[^,]+") do
  local item,qty=segment:match("^(%d+):(%d+)$")
  item,qty=tonumber(item),tonumber(qty)
  if not pos(item) or not pos(qty) then return nil end
  seen[item]=(seen[item] or 0)+qty
  if not integer(seen[item]) then return nil end
 end
 for item,qty in pairs(seen) do reagents[#reagents+1]={itemID=item,quantity=qty} end
 table.sort(reagents,function(a,b)return a.itemID<b.itemID end)
 if #reagents==0 then return nil end
 local item,base,effect=fields[11]:match("^(%d+):([%-%d%.]+):(%d+)$")
 item=tonumber(item)
 if not pos(item) or not base or not effect then return nil end
 return {recipeID=id,outputItemID=item,materials=reagents,recipeName=fields[12],
  historicalEffectBase=tonumber(base),historicalEffectNotYieldAuthority=true,
  sourceBuild=70450,materialSource="DB70450_REAGENT_REFERENCE",outputIdentitySource="DB70450_SPELL_EFFECT_ITEM"}
end
-- P0-212 require independently source-pinned item, name, reagent quantity and
-- output identity for newly curated primary references. A spell/name conflict is
-- quarantined; historical DB effect bases never override external fixed yields.
local function exactPrimaryProof(recipe, curated)
 local evidence=JLP.data and JLP.data.foreverPrimaryRecipeParity212
 local proof=evidence and evidence.rows and evidence.rows[recipe.recipeID]
 if not proof then return nil,"NO_PRIMARY_PROOF" end
 if evidence.conflicts and evidence.conflicts[recipe.recipeID] then return nil,"SOURCE_NAME_CONFLICT" end
 if proof.professionKey~=recipe.professionKey or proof.recipeName~=recipe.recipeName or
    proof.recipeID~=recipe.recipeID or proof.outputItemID~=recipe.outputItemID or
    proof.outputQuantity~=recipe.outputPerCraft or
    proof.outputItemID~=curated.outputItemID or proof.outputQuantity~=curated.outputQuantity or
    proof.recipeName~=curated.outputName then return nil,"SOURCE_IDENTITY_CONFLICT" end
 local expected={};local count=0
 for _,r in ipairs(proof.materials or {}) do
  if not pos(r.itemID) or not pos(r.quantity) or expected[r.itemID] then
   return nil,"INVALID_EXTERNAL_REAGENT_REFERENCE" end
  expected[r.itemID]=r.quantity;count=count+1
 end
 if count~=#recipe.materials then return nil,"REAGENT_COUNT_CONFLICT" end
 for _,r in ipairs(recipe.materials) do
  if expected[r.itemID]~=r.quantity then return nil,"REAGENT_QUANTITY_CONFLICT" end
 end
 return proof
end
local byItem=nil
local byProfessionSpell=nil -- compact source identity index; each hit revalidates receipt
local function buildIndex()
 if byItem then return byItem end
 local out={};local raw=JLP.data and JLP.data.build70450Recipes
 local knownYield=JLP.data and JLP.data.recipeOutputYields
 local curated=JLP.data and JLP.data.foreverIntermediateOutputs
 if not (raw and raw.professions and knownYield and knownYield.recipes and curated and curated.rows) then return {} end
 local exactYield={};local yieldConflict={}
 for _,y in pairs(knownYield.recipes) do
  if type(y)=="table" and pos(y.spellID) and y.fixed==true and y.externalVerified==true and
     y.dependencyQuantityEligible==true and pos(y.outputQuantity) and
     y.outputMin==y.outputQuantity and y.outputMax==y.outputQuantity then
   local old=exactYield[y.spellID]
   if old and old~=y.outputQuantity then yieldConflict[y.spellID]=true end
   exactYield[y.spellID]=y.outputQuantity
  end
 end
 local catalog={};local disagreements={}
 for _,row in ipairs(curated.rows) do
  if type(row)=="table" and pos(row.recipeID) and pos(row.outputItemID) and pos(row.outputQuantity) and
       type(row.professionKey)=="string" then
   local token=row.professionKey..":"..row.recipeID
   if catalog[token] and (catalog[token].outputItemID~=row.outputItemID or
       catalog[token].outputQuantity~=row.outputQuantity) then disagreements[token]=true end
   catalog[token]=row
  end
 end
 -- Only scan the exact curated SpellIDs, not an unbounded fuzzy name join.
 for key,source in pairs(raw.professions) do
  if type(source)=="table" and type(source.packed)=="string" then
   for line in source.packed:gmatch("[^\n]+") do
    -- In DB70450 packed data the first row is embedded after [==[.
    line=line:gsub("^.*%[==%[", "")
    local ident=line:match("^(%d+)%^")
    if ident then
     local token=key..":"..ident
     local c=catalog[token]
     if c and not disagreements[token] and not yieldConflict[c.recipeID] and
        exactYield[c.recipeID]==c.outputQuantity then
      local recipe=parsePackedRow(line)
      if recipe and recipe.recipeID==c.recipeID and recipe.outputItemID==c.outputItemID then
       recipe.professionKey=key;recipe.outputPerCraft=c.outputQuantity
       recipe.historicalEffectBaseDiffersFromForeverYield=
        recipe.historicalEffectBase~=recipe.outputPerCraft
       recipe.yieldSource="INDEPENDENT_FOREVER_FIXED_AND_CURATED_MATCH"
       recipe.learnedState="UNKNOWN";recipe.nativeDispatchAllowed=false;recipe.readOnly=true
       -- Every new 212 row is admitted ONLY when its independently pinned
       -- source proof agrees with the DB reagent and output join.
       local primary=JLP.data and JLP.data.foreverPrimaryRecipeParity212
       local proofRequired=c.requiresPrimarySourceParity==true
       recipe.requiresPrimaryProof=proofRequired
       local proof,why=exactPrimaryProof(recipe,c)
       if proofRequired and not proof then
        recipe=nil -- conflict: no advisory producer edge either
       elseif proofRequired then
        recipe.primarySourceParity="EXACT_SPELL_OUTPUT_REAGENTS_NAME"
        recipe.primarySourceURL=proof.source
        recipe.primarySourceSkillMinimum=proof.sourceSkillMinimum
        recipe.primarySourceTrainerNames=proof.trainerNames
        recipe.primarySourceStationKind=proof.sourceStationKind
        recipe.guideSkillReference=proof.guideSkillMinimum
        recipe.guideSkillReferenceOnly=proof.guideSkillOnlyNameJoin==true
        recipe.primarySourcePartialNPCReferences=proof.partialExactActorReferences
        recipe.trainerIDsVerified=false;recipe.trainerStockVerified=false
        recipe.learningStatus="UNKNOWN";recipe.navigationStatus="LOCATION_UNVERIFIED"
       end
       if recipe then
       local bucket=out[recipe.outputItemID] or {}
       bucket[#bucket+1]=recipe;out[recipe.outputItemID]=bucket
       end
      end
     end
    end
   end
  end
 end
 for _,bucket in pairs(out) do table.sort(bucket,function(a,b)
  if a.professionKey~=b.professionKey then return a.professionKey<b.professionKey end
  return a.recipeID<b.recipeID end) end
 local spell={}
 for _,bucket in pairs(out) do
  for _,r in ipairs(bucket) do
   local key=r.professionKey..":"..r.recipeID
   if spell[key] then spell[key]=false -- ambiguity: fail closed
   else spell[key]=r end
  end
 end
 byProfessionSpell=spell;byItem=out;return out
end
-- A cached index is only a candidate index. Every read must recheck active
-- source receipts: source rows may be revoked, conflict flags added, or external
-- fixed yields withdrawn after the first view. No stale advisory BOM credit.
local function liveSourceReceipt(recipe)
 local data=JLP.data or {}
 local outputs=data.foreverIntermediateOutputs
 local yields=data.recipeOutputYields
 if not (outputs and type(outputs.rows)=="table" and yields and type(yields.recipes)=="table") then
  return false,"SOURCE_CATALOGUE_UNAVAILABLE" end
 local match,count=nil,0
 for _,r in ipairs(outputs.rows) do
  if r.professionKey==recipe.professionKey and r.recipeID==recipe.recipeID then
   count=count+1;match=r end
 end
 if count~=1 or match.outputItemID~=recipe.outputItemID or
    match.outputQuantity~=recipe.outputPerCraft or
    match.outputName~=recipe.recipeName or
    (match.requiresPrimarySourceParity==true)~= (recipe.requiresPrimaryProof==true) then
  return false,"SOURCE_CURATED_DRIFT" end
 local verified=0
 for _,y in pairs(yields.recipes) do
  if type(y)=="table" and y.spellID==recipe.recipeID and
     y.fixed==true and y.externalVerified==true and
     y.dependencyQuantityEligible==true and y.outputMin==recipe.outputPerCraft and
     y.outputMax==recipe.outputPerCraft and y.outputQuantity==recipe.outputPerCraft then
   verified=verified+1 end
 end
 if verified~=1 then return false,"SOURCE_YIELD_REVOKED" end
 local evidence=JLP:GetModule("RecipeOutputEvidence")
 if evidence and evidence.GetReference and evidence.Resolve then
  local reference=evidence:GetReference(recipe.recipeName,recipe.recipeID)
  if reference and reference.productFixedOutput==true then
   local resolved=evidence:Resolve(recipe.recipeName,recipe.recipeID)
   if not resolved.planningUsable then return false,resolved.status end
  end
 end
 if recipe.requiresPrimaryProof then
  local proof,reason=exactPrimaryProof(recipe,match)
  if not proof or proof.source~=recipe.primarySourceURL or
     proof.status~="EXACT_FOREVER_SPELL_AND_DB70450_PARITY" then
   return false,reason or "SOURCE_RECEIPT_CHANGED" end
 end
 return true,"SOURCE_RECONFIRMED"
end

function M:Resolve(key,recipeID)
 if type(key)~="string" or not pos(recipeID) then return nil,"INVALID_IDENTITY" end
 buildIndex()
 local candidate=byProfessionSpell and byProfessionSpell[key..":"..recipeID]
 if candidate==false then return nil,"AMBIGUOUS_SOURCE_RECIPE_ID" end
 if candidate then
  local valid,reason=liveSourceReceipt(candidate)
  if not valid then return nil,reason end
  return candidate
 end
 return nil,"EXACT_CROSSCHECK_UNAVAILABLE"
end
local function safeMultiply(a,b)
 local value=a*b
 return integer(value) and value or nil
end
function M:Plan(requests,opts)
 opts=type(opts)=="table" and opts or {}
 local catalog=buildIndex();local total={};local rejected=0
 for _,r in ipairs(type(requests)=="table" and requests or {}) do
  local id=type(r)=="table" and r.itemID
  local n=type(r)=="table" and (r.provisionalAcquireQuantity or r.quantity)
  if pos(id) and pos(n) and integer((total[id] or 0)+n) then
   total[id]=(total[id] or 0)+n
  else rejected=rejected+1 end
 end
 local outputs={};local maxDepth=4;local maxRows=256
 local emitted=0
 local function makeNode(itemID,quantity,depth,path)
  local node={itemID=itemID,required=quantity,readOnly=true,spendableStock=0,
   nativeDispatchAllowed=false,status="EXTERNAL_ACQUISITION_OR_VERIFY",producers={}}
  if depth>=maxDepth then node.status="DEPTH_LIMIT_VERIFY_MANUALLY";return node end
  if path[itemID] then node.status="CYCLE_VERIFY_MANUALLY";return node end
  path[itemID]=true
  for _,recipe in ipairs(catalog[itemID] or {}) do
   local sourceValid=liveSourceReceipt(recipe)
   if not sourceValid then
    node.sourceReceiptRevoked=true
    node.status="SOURCE_RECEIPT_REVOKED_VERIFY_MANUALLY"
   else
   if emitted>=maxRows then node.status="COMPLEXITY_LIMIT_VERIFY_MANUALLY";break end
   emitted=emitted+1
   local crafts=ceil(quantity/recipe.outputPerCraft)
   local output=safeMultiply(crafts,recipe.outputPerCraft)
   if output then
    local producer={professionKey=recipe.professionKey,recipeID=recipe.recipeID,
     recipeName=recipe.recipeName,outputItemID=itemID,
     outputPerCraft=recipe.outputPerCraft,estimatedCrafts=crafts,
     estimatedOutput=output,estimatedRemainder=output-quantity,
     ingredients={},learnedState="UNKNOWN",ownerCharacter="UNVERIFIED",
     sourceBuild=recipe.sourceBuild,reagentSource=recipe.materialSource,
     yieldSource=recipe.yieldSource,actualYieldObserved=false,
     historicalEffectBase=recipe.historicalEffectBase,
     historicalEffectBaseDiffersFromForeverYield=recipe.historicalEffectBaseDiffersFromForeverYield,
     historicalEffectNotYieldAuthority=true,
     sourceSkillMinimum=recipe.primarySourceSkillMinimum,
     sourceSkillMinimumVerified=recipe.primarySourceSkillMinimum~=nil,
     guideSkillReference=recipe.guideSkillReference,
     guideSkillReferenceOnly=recipe.guideSkillReferenceOnly,
     sourceRecipeURL=recipe.primarySourceURL,
     sourceProofStatus=recipe.primarySourceParity or "HISTORICAL_RECIPE_AND_EXTERNAL_YIELD",
     sourceTrainerNames=recipe.primarySourceTrainerNames,
     sourceTrainerNPCsQualified=false,
     sourceStationKind=recipe.primarySourceStationKind,sourceStationLocationVerified=false,
     sourcePartialNPCReferences=recipe.primarySourcePartialNPCReferences,
     accessStatus="REQUIRES_FRESH_RECIPE_LEARNING_AND_MATERIAL_CHECK",
     navigationStatus="LOCATION_UNVERIFIED",completionReceipt="REQUIRED",
     readOnly=true,nativeDispatchAllowed=false}
    for _,reagent in ipairs(recipe.materials) do
     local required=safeMultiply(crafts,reagent.quantity)
     if required then
      local child=makeNode(reagent.itemID,required,depth+1,path)
      producer.ingredients[#producer.ingredients+1]=child
     else
      producer.accessStatus="QUANTITY_OVERFLOW_VERIFY_MANUALLY"
     end
    end
    node.producers[#node.producers+1]=producer
   end
   end -- revalidated source receipt
  end
  path[itemID]=nil
  if #node.producers>0 then node.status="CONDITIONAL_CROSS_PROFESSION_PRODUCTION" end
  return node
 end
 for itemID,n in pairs(total) do outputs[#outputs+1]=makeNode(itemID,n,0,{}) end
 table.sort(outputs,function(a,b)return a.itemID<b.itemID end)
 return {contract=self.contract,rows=outputs,invalidRequests=rejected,
  producerNodes=emitted,maxDepth=maxDepth,maxProducerNodes=maxRows,
  stockAvailableForCurrentCraft=0,physicalMaterialsReserved=0,
  priceAuthority=false,learningAuthority=false,coordinatesAuthority=false,
  replanAfter={"RECIPE_LEARNED","SKILL_CHANGE","CURRENT_BAGS_OBSERVED",
    "ALT_CHARACTER_LOGIN","TRANSFER_RECEIPT","CRAFT_OUTPUT_RECEIPT"},
  status="READ_ONLY_CONDITIONAL_DEPENDENCIES",readOnly=true,
  nativeDispatchAllowed=false,executionEligible=false}
end
JLP:RegisterModule("CrossProfessionDependencyPlanner",M)
