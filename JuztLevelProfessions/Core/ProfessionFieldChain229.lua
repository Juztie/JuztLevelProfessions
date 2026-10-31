local _,JLP=...
-- P0-229: per-field, source-revalidated advisory from a concrete recipe to
-- learning, exact single-craft reagents, conditional intermediate acquisition
-- and MANUAL next action. No client receipt is inferred from a 70450 source.
local M={contract="JLP-P0-229-PER-FIELD-CURRENT-CHAIN",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local craft={ALCHEMY=true,BLACKSMITHING=true,ENGINEERING=true,
 LEATHERWORKING=true,TAILORING=true,ENCHANTING=true,COOKING=true,FIRST_AID=true}
local function positive(n)
 return type(n)=="number" and n==n and n>0 and n<2147483647 and n==math.floor(n)
end
local function nonnegative(n)
 return type(n)=="number" and n==n and n>=0 and n<2147483647 and n==math.floor(n)
end
local function sourceURL(id,v)
 return type(v)=="string" and
  tonumber(v:match("^https://www%.wowhead%.com/forever/spell=(%d+)[/%w%-]*$"))==id
end
local function copyMaterials(rows)
 if type(rows)~="table" or #rows==0 then return nil end
 local out,seen={},{}
 for _,r in ipairs(rows) do
  local id=r.itemID;local qty=r.quantity or r.perCraft
  if not positive(id) or not positive(qty) or seen[id] then return nil end
  seen[id]=true;out[#out+1]={itemID=id,perCraft=qty,readOnly=true}
 end
 table.sort(out,function(a,b)return a.itemID<b.itemID end)
 return out
end
local function equalMaterials(a,b)
 a=copyMaterials(a);b=copyMaterials(b)
 if not a or not b or #a~=#b then return false end
 for i=1,#a do
  if a[i].itemID~=b[i].itemID or a[i].perCraft~=b[i].perCraft then return false end
 end
 return true
end
local function exactRecipe(key,recipeID,name)
 local authority=JLP:GetModule("ForeverRecipeAuthority")
 local graph=JLP:GetModule("CrossProfessionDependencyPlanner")
 local public,producer=nil,nil
 if authority and type(authority.GetReference)=="function" then
  local ok,r=pcall(authority.GetReference,authority,key,recipeID,name)
  if ok and type(r)=="table" and r.recipeID==recipeID and r.name==name and
    sourceURL(recipeID,r.sourceURL) then public=r end
 end
 if graph and type(graph.Resolve)=="function" then
  local ok,r=pcall(graph.Resolve,graph,key,recipeID)
  if ok and type(r)=="table" and r.professionKey==key and
     r.recipeID==recipeID and r.recipeName==name and
     r.primarySourceParity=="EXACT_SPELL_OUTPUT_REAGENTS_NAME" and
     sourceURL(recipeID,r.primarySourceURL) then producer=r end
 end
 local pm=public and copyMaterials(public.reagents)
 local gm=producer and copyMaterials(producer.materials)
 if pm and gm and not equalMaterials(pm,gm) then
  return nil,"INDEPENDENT_SOURCE_REAGENT_CONFLICT",public,producer
 end
 local materials=pm or gm
 if not materials then return nil,"NO_INDEPENDENT_REAGENT_PROOF",public,producer end
 return materials,pm and gm and "PUBLIC_AND_FIXED_YIELD_GRAPH_PARITY" or
  pm and "PUBLIC_FOREVER_REAGENTS" or "FIXED_YIELD_GRAPH_EXACT_PARITY",public,producer
end
-- Source identity index is invalidated on table/revision replacement. In-place
-- revocations remain checked against the live conflicts table on every read.
local skillIndex,skillRows,skillRevision=nil,nil,nil
local function minimumSourceIndex(root)
 local rows=root and root.rows
 local revision=root and root.sourceRevision
 if skillIndex and rows==skillRows and revision==skillRevision then return skillIndex end
 local bySkill={}
 for id,row in pairs(rows or {}) do
  if type(row)=="table" and positive(id) and id==row.recipeID and
    type(row.professionKey)=="string" and positive(row.sourceSkillMinimum) then
   local byProfession=bySkill[row.professionKey] or {}
   local bucket=byProfession[row.sourceSkillMinimum] or {}
   bucket[#bucket+1]={id=id,row=row}
   byProfession[row.sourceSkillMinimum]=bucket
   bySkill[row.professionKey]=byProfession
  end
 end
 skillIndex,skillRows,skillRevision=bySkill,rows,revision
 return bySkill
end
-- A verified skill minimum is a SINGLE research lead. Neither the next
-- skill point nor the whole interval is thereby a proven progression window.
function M:MinimumLeads(key,skill)
 key=tostring(key or ""):upper()
 if not craft[key] or not positive(skill) or skill>=300 then return {} end
 local root=JLP.data and JLP.data.foreverPrimaryRecipeParity212
 local candidates={}
 local indexed=minimumSourceIndex(root)
 for _,entry in ipairs(indexed[key] and indexed[key][skill] or {}) do
  local id,row=entry.id,entry.row
  if type(row)=="table" and row.professionKey==key and
    row.sourceSkillMinimum==skill and positive(id) and id==row.recipeID and
    type(row.recipeName)=="string" and row.recipeName~="" and
    row.status=="EXACT_FOREVER_SPELL_AND_DB70450_PARITY" and
    sourceURL(id,row.source) and not (root.conflicts and root.conflicts[id]) then
   local materials,proof,_,producer=exactRecipe(key,id,row.recipeName)
   if materials and producer and producer.primarySourceSkillMinimum==skill and
      producer.primarySourceURL==row.source then
    candidates[#candidates+1]={professionKey=key,recipeID=id,recipe=row.recipeName,
     sourceMinimumSkill=skill,recipeSourceURL=row.source,reagentsPerCraft=materials,
     outputItemID=positive(producer.outputItemID) and producer.outputItemID or nil,
     outputPerCraft=positive(producer.outputPerCraft) and producer.outputPerCraft or nil,
     proof=proof,coverageClass="EXACT_MINIMUM_LEAD_NOT_VERIFIED_WINDOW",
     readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
   end
  end
 end
 table.sort(candidates,function(a,b)return a.recipeID<b.recipeID end)
 return candidates
end
function M:Review(key,step,faction)
 key=tostring(key or ""):upper()
 local result={contract=self.contract,professionKey=key,readOnly=true,
  nativeDispatchAllowed=false,executionEligible=false,
  skillUpReceiptObserved=false,craftReceiptObserved=false,
  actualLearningConfirmed=false,liveVendorStockConfirmed=false,
  navigationQualified=false,automaticWaypointAllowed=false,
  fixedPriceQualified=false,exactReagentsQualified=false,
  materialBudgetQualified=false,outputYieldQualified=false,
  learningSourceStatus="UNKNOWN",requiredAction="VERIFY_SOURCE",sourceStatus="UNKNOWN",
  materials={},missingKnown=false,missing=nil,unknownItems=0}
 if not craft[key] then
  result.requiredAction="GATHER_OR_FISH_MANUALLY";result.sourceStatus="NO_CRAFT_RECIPE"
  return result
 end
 local id=type(step)=="table" and step.recipeID
 local name=type(step)=="table" and step.recipe
 if not positive(id) or type(name)~="string" or name=="" then
  result.sourceStatus="NO_EXACT_CURRENT_RECIPE";result.requiredAction="VERIFY_RECIPE"
  return result
 end
 result.recipeID=id;result.recipe=name
 local required,proof,public,producer=exactRecipe(key,id,name)
 result.sourceStatus=proof
 result.recipeSourceURL=public and public.sourceURL or
  producer and producer.primarySourceURL or nil
 if producer and required then
  if positive(producer.outputItemID) and positive(producer.outputPerCraft) then
   result.outputYieldQualified=true;result.outputItemID=producer.outputItemID
   result.outputPerCraft=producer.outputPerCraft
   result.outputEvidence="SOURCE_FIXED_OUTPUT_NOT_CLIENT_RECEIPT"
  end
  if positive(producer.primarySourceSkillMinimum) then
   result.minimumSkillSource=producer.primarySourceSkillMinimum
   result.skillMinimumEvidence="FOREVER_EXACT_PRIMARY_DB_SOURCE"
  end
 end
 local sourceModule=JLP:GetModule("RecipeSourcePlanningBridge")
 if sourceModule and type(sourceModule.ForRecipe)=="function" then
  local ok,s=pcall(sourceModule.ForRecipe,sourceModule,key,id,name,faction)
  if ok and type(s)=="table" and s.recipeID==id and s.professionKey==key then
   result.learningSourceStatus=s.state or "UNKNOWN"
   result.learningSourceReason=s.reason
   result.teachingItems=s.teachingItems
   result.learningCandidates=s.candidates
   result.trainerNameReferences=s.referenceTrainerHints
   result.recipeSourcePlanning=s
  end
 end
 if not required then
  result.requiredAction=proof=="INDEPENDENT_SOURCE_REAGENT_CONFLICT" and
   "RESOLVE_SOURCE_CONFLICT" or "VERIFY_EXACT_REAGENTS"
  return result
 end
 local current=type(step.materials)=="table" and step.materials or nil
 if not equalMaterials(required,current) then
  -- A current-step catalogue mismatch is an advisory hard stop; never
  -- silently replace one source's materials with another source's numbers.
  result.sourceStatus="CURRENT_STEP_REAGENT_CONFLICT"
  result.requiredAction="RESOLVE_SOURCE_CONFLICT"
  return result
 end
 result.exactReagentsQualified=true
 local input={};local anyUnknown=false;local shortage=0
 for _,r in ipairs(required) do
  local observed
  for _,s in ipairs(current or {}) do
   if s.itemID==r.itemID then observed=s;break end
  end
  local known=observed and observed.bagsKnown==true and nonnegative(observed.bags)
  local missing=known and math.max(0,r.perCraft-observed.bags) or nil
  if not known then anyUnknown=true;result.unknownItems=result.unknownItems+1
  else shortage=shortage+missing end
  result.materials[#result.materials+1]={itemID=r.itemID,required=r.perCraft,
   bagsKnown=known==true,bags=known and observed.bags or nil,
   missing=missing,sourceReceipt=proof,readOnly=true,
   nativeDispatchAllowed=false}
  if known and missing>0 then input[#input+1]={itemID=r.itemID,quantity=missing} end
 end
 result.missingKnown=not anyUnknown
 result.missing=not anyUnknown and shortage or nil
 result.materialBudgetQualified=not anyUnknown -- exactly ONE craft, not to 300
 local graph=JLP:GetModule("CrossProfessionDependencyPlanner")
 if graph and type(graph.Plan)=="function" and #input>0 then
  local ok,deps=pcall(graph.Plan,graph,input,{})
  if ok and type(deps)=="table" and deps.nativeDispatchAllowed==false then
   result.conditionalMaterialProducers=deps
  end
 end
 local learned=step.learned
 if learned~=true and learned~=false then learned=nil end
 result.learned=learned;result.learnedEvidence=step.learnedSource or "UNKNOWN"
 if learned~=true then
  result.requiredAction=learned==false and "VERIFY_LEARNING_SOURCE" or "VERIFY_LEARNED_STATE"
 elseif anyUnknown then result.requiredAction="VERIFY_BAG_COUNTS"
 elseif shortage>0 then result.requiredAction="ACQUIRE_EXACT_MISSING_REAGENTS"
 else result.requiredAction="REVIEW_MANUAL_SINGLE_CRAFT_AND_DIFFICULTY" end
 -- Existing CurrentStepTravelBridge remains the only authority for previews.
 -- Do not call owner.SyncCurrentStep or create a waypoint from an NPC name.
 result.navigationStatus=type(step.navigation)=="table" and step.navigation.status or
  "LOCATION_UNVERIFIED"
 result.navigationQualified=type(step.navigation)=="table" and
  step.navigation.waypointQualified==true or false
 return result
end
JLP:RegisterModule("ProfessionFieldChain229",M)
