local _, JLP = ...
-- Advisory branch of Mining progression: never executes or claims a skill-up.
local Smelting={contract="jlp-mining-smelting-progression-v1",nativeDispatchAllowed=false}
function Smelting:Evaluate(skill,context)
 local src=JLP.data and JLP.data.foreverMiningSmeltingBands
 local value=tonumber(skill)
 if not src or not value or value~=value or value==math.huge or value==-math.huge or
   value<0 or value~=math.floor(value) then
  return {state="SKILL_UNAVAILABLE",eligible=false,actionable=false,
    explanation="Mining skill unavailable; gather ore until skill can be read."}
 end
 local row
 for _,candidate in ipairs(src.entries) do
  if value>=candidate.from and value<candidate.to then row=candidate;break end
 end
 if not row then
  local message=value>=140 and value<155 and "No supported smelting skill-ups at 140-154; gather ore." or
    value>=185 and "No source-backed smelting progression from skill 185; gather ore." or
    "No source-backed smelting band at this skill; gather ore."
  return {state="GATHER_ONLY",eligible=false,actionable=false,explanation=message,
   skill=value,sourceURL=src.sourceURL,sourceQualifier=src.sourceQualifier}
 end
 local ctx=type(context)=="table" and context or {}
 local recipe=ctx.recipeKnown==true
 local forge=ctx.atForge==true
 local reagents=ctx.reagentsAvailable==true
 local ready=recipe and forge and reagents
 return {state=ready and "CONDITIONALLY_AVAILABLE" or "REQUIRES_CLIENT_CHECKS",
   eligible=true,actionable=ready,skill=value,skillMin=row.from,skillMax=row.to,
   recipe=row.label,materials=row.materials,
   explanation=row.label.." is a source-backed option for Mining "..row.from.."-"..(row.to-1)..
    ". Verify learned recipe, materials and forge in your client; skill-ups are not guaranteed.",
   requirements={recipeKnown=recipe,atForge=forge,reagentsAvailable=reagents},
   sourceURL=src.sourceURL,sourceQualifier=src.sourceQualifier}
end
-- Read-only reagent inspection. Smelting band rows verify recipe labels and
-- amounts, NOT the item identity or whether a recipe was learned. A material
-- ID is accepted only if an independent Forever recipe reagent explicitly
-- identifies the same named item. Never infer ore IDs from vein IDs.
local function sourceItem(name)
 local root=JLP.data and JLP.data.publicCraftingRouteEvidence
 if not root or root.nativeDispatchAllowed~=false then return nil,nil end
 local found,source
 for _,profession in pairs(root and root.professions or {}) do
  for _,recipe in ipairs(profession.recipes or {}) do
   if recipe.evidenceClass=="PUBLIC_FOREVER_RECIPE_REAGENTS" and
      type(recipe.sourceURL)=="string" and recipe.sourceURL~="" then
    for _,reagent in ipairs(recipe.reagents or {}) do
     if reagent.name==name and type(reagent.itemID)=="number" and
         reagent.itemID>0 and reagent.itemID==math.floor(reagent.itemID) then
      if found and found~=reagent.itemID then return nil,nil end
      found=reagent.itemID
      if not source or recipe.sourceURL<source then source=recipe.sourceURL end
     end
    end
   end
  end
 end
 return found,source
end
function Smelting:BuildMaterialAdvice(skill,context)
 local selected=self:Evaluate(skill,context)
 local result={state=selected.state,skill=selected.skill,recipe=selected.recipe,
   materials={},sourceURL=selected.sourceURL,sourceQualifier=selected.sourceQualifier,
   explanation=selected.explanation,requirements=selected.requirements,
   comparisonState="UNRANKED_EVIDENCE_INSUFFICIENT",nativeDispatchAllowed=false,
   actionable=false,readOnly=true}
 if not selected.eligible or type(selected.materials)~="table" then
  return result
 end
 for _,material in ipairs(selected.materials) do
  local id,identitySource=sourceItem(material.name)
  local qty=tonumber(material.count)
  local qualified=type(id)=="number" and type(qty)=="number" and
    type(selected.sourceURL)=="string" and selected.sourceURL~="" and
    type(identitySource)=="string" and identitySource~="" and
    qty>0 and qty==math.floor(qty)
  result.materials[#result.materials+1]={name=material.name,
    perSmelt=qty,estimatedCrafts=nil,gross=nil,missing=nil,
    itemID=qualified and id or nil,identitySourceURL=qualified and identitySource or nil,
    state=qualified and "SOURCE_QUALIFIED_ID" or "UNAVAILABLE",
    sourceURL=selected.sourceURL,readOnly=true,nativeDispatchAllowed=false}
 end
 return result
end
function Smelting:CompareWithGathering(skill,context)
 local option=self:Evaluate(skill,context)
 local gather={strategy="NODE_GATHERING",eligible=true,action="Gather skill-eligible nodes manually",
  confidence="HISTORICAL_REFERENCE_ONLY"}
 local smelt={strategy="SMELTING",eligible=option.eligible==true,
  readiness=option.state,action=option.explanation,confidence="PUBLIC_GUIDE_ADVISORY",
  requirements=option.requirements or {recipeKnown=false,atForge=false,reagentsAvailable=false}}
 -- Neither node rates nor smelt skill-up probabilities are qualified enough
 -- for an XP/time or gold/time ranking. Gathering stays the safe default.
 return {recommended="NODE_GATHERING",comparisonState="UNRANKED_EVIDENCE_INSUFFICIENT",
  alternatives={gather,smelt},smelting=option,nativeDispatchAllowed=false}
end
-- Qualified producer inspection for the existing consumer supply/BOM path.
-- Cache is volatile and character-scoped. It can support a labeled advisory
-- forecast after changing panels, NEVER current craft/native authorization.
local function whole(n) return type(n)=="number"and n==n and n>=0 and n<math.huge and n==math.floor(n)end
function Smelting:GetProducer(itemID)
 local data=JLP.data and JLP.data.foreverMiningSmeltingBands
 for _,f in ipairs(data and data.recipes or {})do if f.output==itemID then return f end end
end
local function sameInputs(required,recipe)
 if type(required)~="table"then return false end
 local expected={};for _,r in ipairs(recipe.reagents)do expected[r.itemID]=r.quantity end
 for id,n in pairs(required)do if expected[id]~=n then return false end;expected[id]=nil end
 return next(expected)==nil
end
function Smelting:InspectProducer(f)
 local api=JLP:GetModule("ProfessionAPI");local profession=api and api:Get("MINING")
 local guid=type(UnitGUID)=="function"and UnitGUID("player")or nil
 if not profession or profession.cached==true or type(profession.skill)~="number"then return {status="MINING_OWNERSHIP_UNKNOWN"}end
 if self.observer~=guid then self.observer=guid;self.observedProducers={}end
 self.observedProducers=self.observedProducers or {}
 local facts=JLP:GetModule("ProfessionPlanningFacts")
 local live=facts and facts:Observe("MINING",f.id)
 if live and live.observed then
  local value={live=live,learned=live.learned,currentPanel=true,source="CURRENT_STABLE_RECIPE_READ_ONLY",
   inputQualified=sameInputs(live.requiredReagents,f),status="OUTPUT_UNKNOWN"}
  local output=live.output
  if output and output.fixed and output.itemID==f.output and whole(output.minimum)and output.minimum>0 and value.inputQualified then
   value.outputPerCraft=output.minimum;value.status="CURRENT_FIXED_SCHEMATIC_EXPECTATION_NOT_RECEIPT"
  end
  self.observedProducers[f.id]=value
  return value
 end
 local old=self.observedProducers[f.id]
 if old then
  local value={};for k,v in pairs(old)do value[k]=v end
  value.currentPanel=false;value.source="PREVIOUS_CURRENT_SESSION_ADVISORY_REOPEN_MINING_BEFORE_SMELT"
  return value
 end
 return {status="OUTPUT_CONFLICT_OPEN_MINING_TO_VERIFY",learned=nil,inputQualified=false,currentPanel=false}
end
function Smelting:ObserveCurrentPanel()
 local data=JLP.data and JLP.data.foreverMiningSmeltingBands
 for _,f in ipairs(data and data.recipes or {})do self:InspectProducer(f)end
end
function Smelting:StationStatus(f,observation)
 if not observation.currentPanel then return "UNKNOWN_REOPEN_MINING"end
 local t=type(C_TradeSkillUI)=="table"and C_TradeSkillUI
 if not t or type(t.GetRecipeRequirements)~="function"then return "UNKNOWN"end
 local ok,rows=pcall(t.GetRecipeRequirements,f.id)
 if not ok or type(rows)~="table"or #rows==0 then return "UNKNOWN"end
 for _,row in ipairs(rows)do if row.met==false then return "NOT_MET"elseif row.met~=true then return "UNKNOWN"end end
 return "CURRENT_REQUIREMENTS_MET"
end
function Smelting:GetForgeDestination(f)
 local resolver=JLP:GetModule("SourceResolver")
 local canvas=JLP:GetModule("ForeverFishingMapCanvas");local current=canvas and canvas:GetCurrentZone()
 local faction=type(UnitFactionGroup)=="function"and UnitFactionGroup("player")
 local bridge=JLP:GetModule("GatheringMaterialBridge");local best,bestLocal
 for _,r in ipairs(resolver and resolver:GetOwnerServiceLocations("CRAFT_STATION")or {})do
  local localMap=current and r.nav and current.mapID==r.nav.mapID
  if r.sourceQualified and r.stationFocus==f.stationFocus and (r.faction==faction or r.faction=="Neutral")and
   not (bridge and bridge.unavailable and bridge.unavailable[r.serviceID])and
   (not best or localMap and not bestLocal or localMap==bestLocal and r.serviceID<best.serviceID)then best=r;bestLocal=localMap end
 end
 return best
end
function Smelting:BuildSupplyScenario(itemID,required)
 local api=JLP:GetModule("ProfessionAPI");local mining=api and api:Get("MINING")
 local inventory=JLP:GetModule("Inventory")
 local out={itemID=itemID,required=required,requirements={},operations={},hypotheticalRemainders={},
  observedUsed={},readOnly=true,nativeDispatchAllowed=false,observedOutputCredit=0,
  contract="mining-producer-bom-current-fixed-output-v1",alternativeToPurchase=true,additiveWithPurchase=false,
  status="VERIFY",quantity=nil,skillUpCredit=0}
 if not whole(required)then out.reason="REQUIREMENT_UNKNOWN";return out end
 local available,known,active={},{},{}
 local pending
 local function block(status,id,quantity,extra)
  if not pending then pending={status=status,itemID=id,quantity=quantity,producer=extra}end
 end
 local function visit(id,n,depth)
  if depth>12 or active[id]then block("VERIFY_PRODUCER_CYCLE",id);return end
  local stock=inventory and inventory:GetOwned(id)or {}
  if not stock.bagKnown or not whole(stock.bags)then block("UNKNOWN_INVENTORY",id);return end
  if available[id]==nil then available[id]=stock.bags;known[id]=stock.bags end
  local used=math.min(n,available[id]);available[id]=available[id]-used;n=n-used
  out.observedUsed[id]=(out.observedUsed[id]or 0)+math.min(used,math.max(0,(known[id]or 0)-(out.observedUsed[id]or 0)))
  if n==0 then return end
  if stock.bankKnown~=true then block("VERIFY_BANK",id);return end
  if (stock.bank or 0)>0 then block("BANK",id,math.min(n,stock.bank));return end
  local f=self:GetProducer(id)
  if not f then
   out.requirements[id]=(out.requirements[id]or 0)+n
   block("ACQUIRE_RAW",id,n);return
  end
  local observation=self:InspectProducer(f)
  local op={recipeID=f.id,recipeName=f.name,itemID=id,required=n,inputs=f.reagents,observation=observation,
   stationName=f.stationName,stationFocus=f.stationFocus,skillUpCredit=0,observedOutputCredit=0}
  if not mining or mining.cached==true or type(mining.skill)~="number"then block("VERIFY_MINING",id,nil,op);return end
  if not f.minimum or mining.skill<f.minimum then block("VERIFY_SMELTING_SKILL",id,nil,op);return end
  if observation.learned~=true then block("VERIFY_SMELTING_LEARNED",id,nil,op);return end
  if not observation.outputPerCraft or observation.inputQualified~=true then block("VERIFY_SMELTING_YIELD",id,nil,op);return end
  local casts=math.ceil(n/observation.outputPerCraft)
  op.expectedCasts=casts;op.outputPerCraft=observation.outputPerCraft
  op.expectedOutput=casts*observation.outputPerCraft
  op.progression=type(f.gray)=="number"and mining.skill>=f.gray and "GRAY_PREPARATION_NO_SKILL_CREDIT"or "SEPARATE_CURRENT_COLOR_AND_SKILL_RECEIPT_REQUIRED"
  active[id]=true
  for _,r in ipairs(f.reagents)do visit(r.itemID,casts*r.quantity,depth+1)end
  active[id]=nil
  available[id]=(available[id]or 0)+casts*observation.outputPerCraft-n
  out.hypotheticalRemainders[id]=available[id]
  out.operations[#out.operations+1]=op
  if not pending then
   local station=self:StationStatus(f,observation);op.stationStatus=station
   block(station=="CURRENT_REQUIREMENTS_MET"and "SMELT"or "VERIFY_FORGE",id,n,op)
  end
 end
 visit(itemID,required,0)
 out.next=pending or {status="BAGS_READY",itemID=itemID,quantity=0}
 out.status=out.next.status;out.quantity=out.next.quantity
 out.reason=out.next.producer and out.next.producer.observation and out.next.producer.observation.status
 return out
end
JLP:RegisterModule("MiningSmeltingProgression",Smelting)
