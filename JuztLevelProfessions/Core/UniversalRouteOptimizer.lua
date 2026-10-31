local _, JLP = ...
-- P1 Phase 24. Advisory, source-based multi-step forecasting only.
-- No event receipt, build whitelist, client attestation or native permission.
-- Expected crafts, skill chances, prices and output quantities are modelled
-- separately. The result MUST NOT be dispatched as a crafting queue.
local O={contract="JLP-UNIVERSAL-ROUTE-FORECAST-V2",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false,forecastOnly=true}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
local function whole(x)
 local n=tonumber(x)
 return n and n==n and n>=0 and n<math.huge and n==floor(n) and n or nil
end
local function known(x) local n=whole(x);return n and n>0 and n or nil end
local function validRows(key,rows)
 local out={};local rejected=0;local gate=JLP:GetModule("ProfessionRecipeMinimumGate")
 for _,r in ipairs(rows or {}) do
  local id=known(r.recipeID);local resolution=gate and gate.Resolve and gate:Resolve(key,r)
  local rmin=resolution and whole(resolution.minimum) or (not gate and whole(r.requiredSkill or r.routeSkillMin or r.rawMinRank))
  local grey=whole(r.rawGrey)
  if id and rmin and grey and (grey>rmin or r.preparationOnly) and type(r.materials)=="table" and #r.materials>0 then
   local ok=true
   for _,m in ipairs(r.materials) do
    if not known(m.itemID) or not known(m.quantity) then ok=false;break end
   end
   if ok then out[#out+1]={data=r,id=id,minimum=rmin,minimumEvidence=resolution and resolution.source or "LEGACY",grey=grey,
     yellow=whole(r.rawYellow) or 0} end
  else rejected=rejected+1 end
 end
 return out,rejected
end
local function fixedOutputs(key)
 local outputs={};local original=JLP.data and JLP.data.recipeOutputYields
 local external=original and original.recipes
 for _,r in pairs(external or {}) do
  if r.fixed==true and r.dependencyQuantityEligible==true and
     r.externalVerified==true and r.liveVerified==false and
     known(r.spellID) and known(r.outputQuantity) then
   outputs[r.spellID]={quantity=r.outputQuantity,source="FOREVER_EXTERNAL_FIXED_REFERENCE"}
  end
 end
 local curated=JLP.data and JLP.data.foreverIntermediateOutputs
 for _,r in ipairs(curated and curated.rows or {}) do
  if r.professionKey==key and known(r.recipeID) and known(r.outputQuantity) and
      known(r.outputItemID) then
   -- Both curated and fixed-reference tables derive from Forever source
   -- research. They must agree, but neither is a live output receipt.
   -- A curated-only or conflicting yield is NOT a material credit.
   local pinned=outputs[r.recipeID]
   if pinned and pinned.quantity==r.outputQuantity then
    outputs[r.recipeID]={itemID=r.outputItemID,quantity=r.outputQuantity,
      source="FOREVER_CURATED_AND_FIXED_REFERENCE_AGREE"}
   else outputs[r.recipeID]=nil end
  end
 end
 if key=="TAILORING" then
  local q=JLP:GetModule("TailoringRecipeQualification")
  local producer=q and q.GetWoolProducer and q:GetWoolProducer(JLP.data and JLP.data.tailoring)
  -- Replace/revoke the older public yield, never retain it after source conflict.
  outputs[2964]=producer and {itemID=2997,quantity=producer.outputPerCraft,
   source=producer.sourceQualificationContract} or nil
 end
 if key=="TAILORING" then
  local f=JLP.data and JLP.data.tailoring and JLP.data.tailoring.woolProgression
  for _,r in ipairs(f and f.recipes or {})do
   if ((r.expert or r.artisan) and r.outputQuantityConflict) or r.outputQuantityStatus=="UNKNOWN" then outputs[r.id]=nil end
  end
 end
 -- A known contradictory receipt revokes hypothetical intermediate credit.
 -- This does not subtract from physical inventory or alter actual receipts.
 local evidence=JLP:GetModule("RecipeOutputEvidence")
 if evidence and evidence.Resolve then
  for _,r in pairs(external or {}) do
   if r.productFixedOutput==true and outputs[r.spellID] then
    local result=evidence:Resolve(r.recipe,r.spellID)
    if not result.planningUsable then outputs[r.spellID]=nil end
   end
  end
 end
 if key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local dataset=JLP.data and JLP.data[key:lower()]
  local root=dataset and dataset.progression
  for id,f in pairs(root and root.recipes or {})do
   outputs[id]=nil -- replace older public conflicts; never let stale2 override schematic1
   local producer=facts and facts.GetAlchemyProducer and facts:GetAlchemyProducer(f.output,key)
   if producer and producer.id==id then outputs[id]={itemID=f.output,quantity=producer.outputQuantity,source=producer.outputStatus}end
  end
 end
 return outputs
end
-- One static identity index per profession/packed-string value. Strings are
-- immutable; replacing the packed source rebuilds it. No runtime fact is cached.
local packedOutputIndexes={}
local function packedOutputIDs(key,packed)
 if type(packed)~="string"then return {}end
 local cached=packedOutputIndexes[key]
 if cached and cached.packed==packed then return cached.bySpell end
 local bySpell={}
 for line in string.gmatch(packed,"[^\n]+")do
  local id,rest=line:match("^(%d+)%^(.+)$")
  if id and rest then
   local cols={};for part in string.gmatch(rest.."^","([^%^]*)%^")do cols[#cols+1]=part end
   local raw=cols[10] -- original f[11], after removing the first field
   local outputID=raw and raw:match("^(%d+):[%-%d%.]+:%d+$")
   if outputID and known(outputID)then bySpell[tonumber(id)]=tonumber(outputID)end
  end
 end
 packedOutputIndexes[key]={packed=packed,bySpell=bySpell}
 return bySpell
end
local function outputItemIDs(key,rows,knownOutput)
 -- Only SpellEffect item identity is indexed, never a yield or permission.
 local source=JLP.data and JLP.data.build70450Recipes
 local prof=source and source.professions and source.professions[key]
 local bySpell=packedOutputIDs(key,prof and prof.packed)
 local byItem={}
 for _,r in ipairs(rows) do
  local fixed=knownOutput[r.id]
  if fixed then
   local rawItem=bySpell[r.id]
   local curatedItem=known(fixed.itemID)
   -- SpellEffect is used ONLY as an item identity cross-check, NEVER as
   -- quantity evidence. Conflicting item IDs must not mint hypothetical stock.
   -- External yield rows without a DB item ID are not intermediate suppliers.
   if not (rawItem and curatedItem and rawItem~=curatedItem) then
    local item=curatedItem or rawItem
    if item then
     local producer={recipe=r,outputItemID=item,quantity=fixed.quantity,source=fixed.source}
     byItem[item]=byItem[item] or {};byItem[item][#byItem[item]+1]=producer
    end
   end
  end
 end
 return byItem
end
local function stateLearning(id,learned)
 if type(learned)~="table" then return "UNKNOWN" end
 if learned[id]==true then return "LEARNED" end
 if learned[id]==false then return "UNLEARNED" end
 if learned[id]=="CACHED_KNOWN" then return "CACHED_ADVISORY" end
 return "UNKNOWN"
end
local function odds(ctx,r,skill)
 local model=JLP:GetModule("SkillUpProbabilityPlanner")
 -- The historical minimum is unqualified for most DB-only recipes. A
 -- conservative yellow-bound gate therefore starts IN the yellow band;
 -- treating yellow==minimum as invalid would make the route disappear.
 if r.minimumEvidence=="YELLOW_CONSERVATIVE_ELIGIBILITY_BOUND" and
     skill>=r.minimum and skill<r.grey then
  local midpoint=r.yellow+floor((r.grey-r.yellow)/2)
  local color=skill<midpoint and "YELLOW" or "GREEN"
  if model and type(model.ForTier)=="function" then
   local row=model:ForTier(color,ctx.options)
   return row.probability,row.source,color,"CONSERVATIVE_YELLOW_BOUND"
  end
  return color=="YELLOW" and 0.60 or 0.25,
    "USER_APPROVED_YELLOW_OR_GREEN_ASSUMPTION",color,"CONSERVATIVE_YELLOW_BOUND"
 end
 if model and type(model.ForRecipe)=="function" then
  if not ctx.telemetryChecked[r.id] then
   ctx.telemetryChecked[r.id]=true
   ctx.telemetryOdds[r.id]=model:GetOptionalTelemetry(ctx.key,r.id,r.data.recipe)
  end
  -- Cached nil means fallback, not missing recipe access.
  local value=model:ForRecipe(ctx.key,r.id,r.data.recipe,skill,r.minimum,r.yellow,r.grey,
    nil,ctx.options,ctx.telemetryOdds[r.id] or false)
  if type(value)=="table" then return value.probability,value.source,value.tier,value.tierSource end
 end
 -- Safe fallback for older partially installed deployments.
 if skill<r.minimum or skill>=r.grey then return nil end
 if skill<r.yellow then return 1,"LEGACY_ORANGE_SCENARIO","ORANGE" end
 local midpoint=r.yellow+floor((r.grey-r.yellow)/2)
 return skill<midpoint and 0.6 or 0.25,"USER_APPROVED_FALLBACK_SCENARIO",
   skill<midpoint and "YELLOW" or "GREEN","INFERRED_GREEN_BOUNDARY"
end
local function tableCopy(t)
 local r={};for k,v in pairs(t or {}) do r[k]=v end;return r
end
local function shortQuote(id,unitPrice,quoteMemo)
 if quoteMemo[id]~=nil then return quoteMemo[id]~=false and quoteMemo[id] or nil end
 local row=type(unitPrice)=="table" and unitPrice[id] or nil
 if row==nil then
  local prices=JLP:GetModule("PriceResolver")
  if prices and type(prices.GetItemSnapshot)=="function" then
   local ok,item,scope=pcall(prices.GetItemSnapshot,prices,id,true)
   if ok and type(item)=="table" and scope and scope.displayableAdvisory==true then
    row=item.minUnitBuyout or item.minUnitPrice
   end
  end
 end
 local n=whole(row)
 quoteMemo[id]=n or false
 return n
end
local function bagCount(id,stock,stockMemo,reserved)
 if stockMemo[id]~=nil then return stockMemo[id]~=false and stockMemo[id] or nil end
 local n=type(stock)=="table" and whole(stock[id]) or nil
 if n==nil then
  local inventory=JLP:GetModule("Inventory")
  if inventory and type(inventory.GetOwned)=="function" then
   local ok,owned=pcall(inventory.GetOwned,inventory,id)
   if ok and type(owned)=="table" and owned.bagKnown==true then n=whole(owned.bags) end
  end
 end
 if n~=nil then n=max(0,n-(whole(reserved and reserved[id]) or 0)) end
 stockMemo[id]=n or false
 return n
end
local function buildContext(key,rows,learned,options)
 -- Current Step's qualified consumer shortlist need not contain the producer.
 -- Add the same qualified preparation node to the existing dependency graph.
 if key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  local present,expanded={},{}
  for _,r in ipairs(rows or {})do present[r.recipeID]=true;expanded[#expanded+1]=r end
  for _,r in ipairs(expanded)do for _,mat in ipairs(r.materials or {})do
   local f=facts and facts.GetAlchemyProducer and facts:GetAlchemyProducer(mat.itemID,key)
   if f and not present[f.id]then
    present[f.id]=true
    expanded[#expanded+1]={recipeID=f.id,recipe=f.name,requiredSkill=f.minimum,
     routeSkillMin=f.minimum,rawYellow=f.yellow,rawGreen=f.green,rawGrey=f.gray,
     materials=f.referenceMaterials,preparationOnly=true}
   end
  end end
  rows=expanded
 end
 if key=="TAILORING" then
  local contains,needs=false,false
  for _,r in ipairs(rows or {})do
   if r.recipeID==2964 then contains=true end
   if (r.sourceQualificationContract=="tailoring-77-102-wool-v1" or (r.sourceQualificationContract=="tailoring-102-107-source-v1" or (r.sourceQualificationContract=="tailoring-107-125-source-v1" or (r.sourceQualificationContract=="tailoring-125-225-source-v1" or r.sourceQualificationContract=="tailoring-225-300-source-v1")))) then
    for _,m in ipairs(r.materials or {})do if m.itemID==2997 and m.craftedFrom then needs=true end end
   end
  end
  local q=JLP:GetModule("TailoringRecipeQualification")
  local producer=needs and not contains and q and q:GetWoolProducer(JLP.data and JLP.data.tailoring)
  if producer then
   local expanded={};for _,r in ipairs(rows)do expanded[#expanded+1]=r end
   expanded[#expanded+1]={recipeID=2964,recipe="Bolt of Woolen Cloth",requiredSkill=75,
    route=true,routeSkillMin=75,rawYellow=75,rawGreen=77,rawGrey=85,
    materials={{itemID=2592,quantity=3,source="auction"}},preparationOnly=true}
   rows=expanded
  end
  local present={}
  local extra={};for _,r in ipairs(rows)do for _,m in ipairs(r.materials or {})do
   local prod=m.craftedFrom
   if prod and prod.producerRecipeID and (m.itemID==4305 or m.itemID==4339 or m.itemID==14048) and not present[prod.producerRecipeID] then
    present[prod.producerRecipeID]=true
    extra[#extra+1]={recipeID=prod.producerRecipeID,recipe=m.name or "Cloth Bolt",requiredSkill=prod.minimum,
      route=true,routeSkillMin=prod.minimum,rawYellow=0,rawGrey=prod.producerRecipeID==3839 and 120 or prod.producerRecipeID==18401 and 215 or 150,
      materials={{itemID=prod.itemID,quantity=prod.quantity,source="auction"}},preparationOnly=true}
   end
  end end
  if #extra>0 then local all={};for _,r in ipairs(rows)do if not present[r.recipeID] then all[#all+1]=r end end;for _,r in ipairs(extra)do all[#all+1]=r end;rows=all end
 end
 local normalized,rejected=validRows(key,rows)
 local output=fixedOutputs(key)
 local ids={}
 local curatedByRecipe={}
 local curated=JLP.data and JLP.data.foreverIntermediateOutputs
 for _,r in ipairs(curated and curated.rows or {}) do
  if r.professionKey==key and known(r.recipeID) then curatedByRecipe[r.recipeID]=r end
 end
 local byItem=outputItemIDs(key,normalized,output)
 for id,producers in pairs(byItem) do for _,prod in ipairs(producers) do ids[prod.recipe.id]=id end end
 return {key=key,rows=normalized,rejectedMinimumCandidates=rejected,byItem=byItem,outputs=output,curatedByRecipe=curatedByRecipe,outputIDs=ids,
  learned=learned,options=options or {},quotes={},stock={},missingQuotes={},
  maxDependencyDepth=math.max(3,#normalized)}
end
local function unitSupply(ctx,itemID,level,visiting)
 -- Minimum marginal cost to obtain ONE output item. Completely unknown AH
 -- prices remain UNKNOWN: resource-unit fallback is never labelled as gold.
 if level>ctx.maxDependencyDepth or visiting[itemID] then
  return {metric=1,known=false,method="UNRESOLVED",itemID=itemID}
 end
 local bid=shortQuote(itemID,ctx.options.prices,ctx.quotes)
 local best=bid and {metric=bid,known=true,method="BUY",itemID=itemID,price=bid} or
  {metric=1,known=false,method="PRICE_UNKNOWN",itemID=itemID}
 visiting[itemID]=true
 for _,producer in ipairs(ctx.byItem[itemID] or {}) do
  local r=producer.recipe
  if stateLearning(r.id,ctx.learned)=="LEARNED" and (ctx.materialSkill or ctx.options.skill)>=r.minimum then
   local metric=0;local all=true
   for _,m in ipairs(r.data.materials or {}) do
    local part=unitSupply(ctx,m.itemID,level+1,visiting)
    metric=metric+part.metric*m.quantity
    all=all and part.known
   end
   local actual=metric/producer.quantity
   -- Compare prices only when BOTH sides have priced estimates.
   if (all and best.known and actual<best.metric) or
     (not best.known and (ctx.options.strategy=="self_found" or
       (bid==nil and level<=1) or all)) then
    best={metric=actual,known=all,method="CRAFT",itemID=itemID,
     recipeID=r.id,outputPerCraft=producer.quantity,
     outputSource=producer.source}
   end
  end
 end
 visiting[itemID]=nil
 return best
end
local function recipeScore(ctx,r,skill,strategy)
 local oddsValue,oddsSource,skillTier,tierSource=odds(ctx,r,skill)
 if type(oddsValue)~="number" or oddsValue~=oddsValue or oddsValue<=0 then return nil end
 local learnedState=stateLearning(r.id,ctx.learned)
 if learnedState=="UNLEARNED" then return nil end
 -- Synthetic all-learned scenarios remain advisory; an unknown or cached
 -- recipe cannot be promoted by a yellow fallback alone.
 if r.minimumEvidence=="YELLOW_CONSERVATIVE_ELIGIBILITY_BOUND" and
    learnedState~="LEARNED" then return nil end
 local total,complete=0,true
 for _,m in ipairs(r.data.materials) do
  local supply=unitSupply(ctx,m.itemID,0,{})
  total=total+supply.metric*m.quantity
  complete=complete and supply.known
 end
 -- Planned crafts / skillup are a planning scenario, not receipt evidence.
 local referenceCrafts=ceil(1/oddsValue)
 local base=total*referenceCrafts
 local accessPenalty=learnedState=="LEARNED" and 0 or 20
 if strategy=="fastest" then base=referenceCrafts*12+total*0.1+accessPenalty end
 if strategy=="self_found" then base=referenceCrafts*3+total+accessPenalty end
 -- UNKNOWN access/price entails a warning and model penalty; does not prohibit guidance.
 if not complete and strategy=="economical" then base=base+5 end
 if (ctx.key=="ENCHANTING" or ctx.key=="ALCHEMY" or ctx.key=="BLACKSMITHING" or ctx.key=="ENGINEERING" or ctx.key=="LEATHERWORKING" or ctx.key=="FIRST_AID" or ctx.key=="COOKING") and r.data.qualifiedProgression then
  -- Enchanting has qualified cast times, not a synthetic twelve-second cost.
  -- An incomplete quote is a score fallback, never gold or a free reagent.
  local missingUnits,quotedOutlay,knownOutlay=0,0,true
  for _,m in ipairs(r.data.materials)do
   local stock=bagCount(m.itemID,ctx.options.inventory,ctx.stock,ctx.options.reservedStock)
   local need=stock and max(0,m.quantity*referenceCrafts-stock) or nil
   local quote=shortQuote(m.itemID,ctx.options.prices,ctx.quotes)
   if need==nil then knownOutlay=false;missingUnits=missingUnits+10000
   else missingUnits=missingUnits+need
    if need>0 then if quote==nil then knownOutlay=false else quotedOutlay=quotedOutlay+need*quote end end
   end
  end
  complete=knownOutlay
  if strategy=="fastest" then base=r.data.castSeconds and referenceCrafts*r.data.castSeconds or 100000000+referenceCrafts
  elseif strategy=="economical" and knownOutlay then base=quotedOutlay
  elseif strategy=="self_found" then base=missingUnits+referenceCrafts
  else base=100000000+referenceCrafts end -- explicit unpriced ranking penalty, not money
 end
 return {metric=base,estimatedCrafts=referenceCrafts,skillChanceAssumption=oddsValue,
  probabilitySource=oddsSource,skillTier=skillTier,skillTierSource=tierSource,allPricesKnown=complete,learnedState=learnedState,
  resourceMetric=total,receiptQualified=false}
end
-- Simulate consumption of a scenario route in skill order. Generated intermediate
-- outputs are carried forward once, rather than purchased again at each step.
-- If bag quantity is unknown, provisional requirements are NOT verified shortage.
local function rollup(ctx,path)
 local balance,initial,unknown,purchase,produced,recipes={},{},{},{},{},{}
 local withheld,accessGaps={},{}
 local allQuoted=#path>0;local estimatedCost=0
 local function stock(id)
  if balance[id]~=nil then return balance[id] end
  local observed=bagCount(id,ctx.options.inventory,ctx.stock,ctx.options.reservedStock)
  initial[id]=observed
  if observed==nil then unknown[id]=true;balance[id]=0 else balance[id]=observed end
  return balance[id]
 end
 local function acquire(id,required,depth,seen,conversion)
  if required<=0 then return end
  local available=stock(id)
  local used=min(available,required)
  balance[id]=available-used
  local remaining=required-used
  if remaining<=0 then return end
  local supplier=unitSupply(ctx,id,0,{})
  local producer=nil
  if depth<ctx.maxDependencyDepth and not seen[id] and supplier.method=="CRAFT" then
   for _,p in ipairs(ctx.byItem[id] or {}) do
    if p.recipe.id==supplier.recipeID then producer=p;break end
   end
  end
  if conversion and conversion.sourceQualificationContract=="wool-2964-client-schematic-70532-v1" and
      ctx.outputs[2964] and ctx.outputs[2964].quantity==1 then
   for _,p in ipairs(ctx.byItem[id] or {})do if p.recipe.id==2964 then producer=p;break end end
  end
  if producer then
   local amount=ceil(remaining/producer.quantity)
   recipes[producer.recipe.id]=(recipes[producer.recipe.id] or 0)+amount
   seen[id]=true
   for _,m in ipairs(producer.recipe.data.materials) do
    acquire(m.itemID,m.quantity*amount,depth+1,seen)
   end
   seen[id]=nil
   produced[id]=(produced[id] or 0)+amount*producer.quantity
   balance[id]=(balance[id] or 0)+amount*producer.quantity-remaining
  else
   purchase[id]=(purchase[id] or 0)+remaining
   local unit=shortQuote(id,ctx.options.prices,ctx.quotes)
   if unit==nil then allQuoted=false else estimatedCost=estimatedCost+unit*remaining end
  end
 end
 -- An outcome of the current/previous craft can be reused only AFTER the
 -- inputs of that craft have been procured; no future-item double spending.
 for _,step in ipairs(path) do
  ctx.materialSkill=step.skillStart or ctx.options.skill
  for _,m in ipairs(step.materials) do
   acquire(m.itemID,step.estimatedCrafts*m.quantity,0,{},m.craftedFrom)
  end
  local fixed=ctx.outputs and ctx.outputs[step.recipeID]
  local outputID=fixed and (fixed.itemID or ctx.outputIDs[step.recipeID])
  local producerQualified=false
  if outputID and fixed and known(fixed.quantity) then
   -- The recipe-to-output item link must also be accepted by the source
   -- graph. In particular, reject a conflicting curated item ID/DB SpellEffect.
   for _,candidate in ipairs(ctx.byItem[outputID] or {}) do
    if candidate.recipe.id==step.recipeID and candidate.quantity==fixed.quantity then
     producerQualified=true;break
    end
   end
  end
  if not fixed and ctx.curatedByRecipe[step.recipeID] then
   withheld[#withheld+1]={recipeID=step.recipeID,
    itemID=ctx.curatedByRecipe[step.recipeID].outputItemID,
    reason="OUTPUT_YIELD_NOT_FIXED_REFERENCE_QUALIFIED",
    estimatedCrafts=step.estimatedCrafts}
  elseif outputID and not producerQualified then
   -- A source conflict is NEVER allowed to reduce forecast shopping needs.
   withheld[#withheld+1]={recipeID=step.recipeID,itemID=outputID,
    reason="OUTPUT_ITEM_IDENTITY_UNQUALIFIED",estimatedCrafts=step.estimatedCrafts}
  elseif producerQualified then
   local learned=stateLearning(step.recipeID,ctx.learned)
   -- Recipe access must be positively observed (or explicitly provided as a
   -- known test/character fact). Unknown/unlearned steps are useful advice but
   -- NOT supply credits: otherwise later crafts could spend items never made.
   if learned~="LEARNED" or (step.learnedState and step.learnedState~="LEARNED") then
    accessGaps[step.recipeID]=learned
    withheld[#withheld+1]={recipeID=step.recipeID,itemID=outputID,
     estimatedQuantity=step.estimatedCrafts*fixed.quantity,
     reason="RECIPE_ACCESS_NOT_CONFIRMED",learnedState=learned}
   else
    stock(outputID)
    local qty=step.estimatedCrafts*fixed.quantity
    balance[outputID]=balance[outputID]+qty
    produced[outputID]=(produced[outputID] or 0)+qty
   end
  end
 end
 local items={};local unverified=0
 for id,amount in pairs(purchase) do
  if unknown[id] then unverified=unverified+1 end
  local unit=shortQuote(id,ctx.options.prices,ctx.quotes)
  items[#items+1]={itemID=id,provisionalAcquireQuantity=amount,
   confirmedShortage=nil,inventoryKnown=not unknown[id],
   auctionUnitPrice=unit,estimatedCost=unit and unit*amount or nil,
   priceKnown=unit~=nil}
 end
 table.sort(items,function(a,b)return a.itemID<b.itemID end)
 local intermediates={}
 for id,n in pairs(recipes) do intermediates[#intermediates+1]={recipeID=id,estimatedCrafts=n} end
 table.sort(intermediates,function(a,b)return a.recipeID<b.recipeID end)
 table.sort(withheld,function(a,b)
  if a.recipeID==b.recipeID then return (a.itemID or 0)<(b.itemID or 0) end
  return a.recipeID<b.recipeID
 end)
 local learning={}
 for id,state in pairs(accessGaps) do learning[#learning+1]={recipeID=id,state=state} end
 table.sort(learning,function(a,b)return a.recipeID<b.recipeID end)
 local complete=allQuoted and unverified==0 and #withheld==0
 -- Account-level possible transfers are separate from the spendable bag pool.
 -- They never reduce the current-character material shortage or gold total.
 local accountPlanner=JLP:GetModule("AccountMaterialReservations")
 local accountPlan=accountPlanner and accountPlanner.Plan and accountPlanner:Plan(items,{
  characters=ctx.options.accountCharacters,aliases=ctx.options.accountAliases,
  currentKey=ctx.options.currentCharacterKey,currentRealm=ctx.options.currentRealm,
  currentFaction=ctx.options.currentFaction,
  existingReservations=ctx.options.existingAccountReservations,
  producerCandidates=ctx.options.accountProducerCandidates}) or nil
 return {accountMaterialReservations=accountPlan,
  provisionalShoppingList=items,intermediateCrafts=intermediates,
  generatedIntermediateUnits=produced,
  withheldOutputCredits=withheld,recipeLearningGaps=learning,
  outputCreditsConditionallyExcluded=#withheld,
  requiresLearningOrOutputVerification=#withheld>0,
  -- Even if the remaining items are priced, the complete bill of materials
  -- cannot be declared resolved while a conditional output is outstanding.
  completePriceCoverage=complete,
  estimatedTotalGold=complete and estimatedCost or nil,
  inventoryUnknownCount=unverified,provisionalOnly=true,
  sourceOutputIdentityChecked=true,
  recipeOutputsExternallyReferenced=true,
  replanAfter={"SKILL_CHANGE","RECIPE_LEARNED","BAG_SNAPSHOT_CHANGE",
   "PRICE_SNAPSHOT_CHANGE","VERIFIED_CRAFT_RECEIPT"}}
end
local function annotateToolBudget(result,tools)
 if not tools then return end
 result.nonConsumedTools=tools;result.toolBudgetStatus="SCENARIO_TOOL_REQUIREMENTS_LISTED"
 for _,tool in ipairs(tools)do
  if tool.status=="unknown" or tool.requiredAction=="VERIFY_TOOL_RECIPE_REQUIREMENTS" then
   result.toolBudgetStatus="UNKNOWN_TOOL_CONTRACT_OR_INVENTORY"
   result.requiresToolVerification=true;result.completePriceCoverage=false;result.estimatedTotalGold=nil
  end
 end
end
function O:Forecast(key,skill,candidates,learned,options)
 options=type(options)=="table" and options or {}
 local start=whole(skill)
 if not start or start>=300 then return nil,"INVALID_OR_COMPLETE_SKILL" end
 local cap=whole(options.maxSkill) or 300
 local goal=min(300,cap,whole(options.goalSkill) or (start+20))
 if goal<=start then return nil,"TRAINER_RANK_GATE" end
 local sharedProjection
 if key=="TAILORING" and start>=77 and start<300 then
  local q=JLP:GetModule("TailoringRecipeQualification")
  sharedProjection=q and q:GetPlanningSteps(JLP.data and JLP.data.tailoring,{skill=start,strategy=options.strategy,boundedForecast=true,goalSkill=goal,
   inventory=options.inventory,reservedStock=options.reservedStock,learnedRecipes=learned})
  local qualified={};local extras={}
  for _,r in ipairs(sharedProjection or {})do
   if (r.sourceQualificationContract=="tailoring-125-225-source-v1" or r.sourceQualificationContract=="tailoring-225-300-source-v1") and not qualified[r.recipeID] then
    qualified[r.recipeID]=r;extras[#extras+1]=r
   end
  end
  if #extras>0 then
   local rows={};for _,r in ipairs(candidates or {})do if not qualified[r.recipeID] then rows[#rows+1]=r end end
   for _,r in ipairs(extras)do rows[#rows+1]=r end;candidates=rows
  end
 end
 local ctx=buildContext(key,candidates,learned,options);ctx.options.skill=start
 ctx.key=key;ctx.telemetryOdds={};ctx.telemetryChecked={}
 local strategy=options.strategy or "economical"
 local dp={[goal]={metric=0,known=true}}
 for s=goal-1,start,-1 do
  local best=nil
  for _,r in ipairs(ctx.rows) do
   local current=recipeScore(ctx,r,s,strategy)
   if current and (not best or
      current.metric+dp[s+1].metric < best.metric) then
    best={metric=current.metric+dp[s+1].metric,row=r,
     state=current,stepScore=current.metric}
   end
  end
  dp[s]=best or {metric=dp[s+1].metric+200,row=nil}
 end
 local path={};local uncovered={};local byRecipe={}
 for s=start,goal-1 do
  local entry=dp[s]
  if not entry or not entry.row then uncovered[#uncovered+1]=s
  else
   local id=entry.row.id
   local previous=byRecipe[id]
   if previous and previous.skillEnd==s then
    previous.skillEnd=s+1;previous.estimatedCrafts=previous.estimatedCrafts+entry.state.estimatedCrafts
   else
    local step={recipeID=id,recipe=entry.row.data.recipe,
      skillStart=s,skillEnd=s+1,estimatedCrafts=entry.state.estimatedCrafts,
      learnedState=entry.state.learnedState,
      fullAuctionPricing=entry.state.allPricesKnown,
      skillChanceAssumption=entry.state.skillChanceAssumption,
      skillChanceSource=entry.state.probabilitySource,
      skillTier=entry.state.skillTier,skillTierSource=entry.state.skillTierSource,
      materials=entry.row.data.materials,sourceBuild=entry.row.data.sourceBuild,
      recipeAccessSource=entry.row.data.recipeSource or
        entry.row.data.acquireMethod or "UNQUALIFIED_SOURCE",
      recipeRequiredSkill=entry.row.minimum,
      recipeMinimumEvidence=entry.row.minimumEvidence,
      expectedCraftsQualified=false,skillGainGuaranteed=false,
      nativeDispatchAllowed=false,readOnly=true}
    path[#path+1]=step;byRecipe[id]=step
   end
  end
 end
 -- Reuse the authoritative qualified Wool scenario, including preparation
 -- skill potential and projected reservations. Do not run a competing 12s/
 -- inferred-green route through this interval.
 local qualifiedEnd=JLP.data and JLP.data.tailoring and JLP.data.tailoring.woolProgression and (JLP.data.tailoring.woolProgression.artisanTarget or JLP.data.tailoring.woolProgression.expertTarget) or 125
 if key=="TAILORING" and start>=77 and start<qualifiedEnd then
  local q=JLP:GetModule("TailoringRecipeQualification")
  local dataset=JLP.data and JLP.data.tailoring
  local projection=sharedProjection or q and q:GetPlanningSteps(dataset,{skill=start,strategy=strategy,inventory=options.inventory,
   reservedStock=options.reservedStock,learnedRecipes=learned})
  local replacements={};local qualified={}
  for _,r in ipairs(projection or {})do
   if (r.sourceQualificationContract=="tailoring-77-102-wool-v1" or (r.sourceQualificationContract=="tailoring-102-107-source-v1" or (r.sourceQualificationContract=="tailoring-107-125-source-v1" or (r.sourceQualificationContract=="tailoring-125-225-source-v1" or r.sourceQualificationContract=="tailoring-225-300-source-v1")))) and not r.requiresLearningVerification then
    local a=max(start,r.skillMin);local b=min(goal,r.skillTarget)
    if b>a then
     local count=q:ScenarioCrafts(r,a,b)
     replacements[#replacements+1]={recipeID=r.recipeID,recipe=r.recipe,skillStart=a,skillEnd=b,
      estimatedCrafts=count,materials=r.materials,sourceBuild=r.sourceBuild,
      sourceQualificationContract=r.sourceQualificationContract,woolScenario=r.woolScenario,
      expectedCraftsQualified=false,skillGainGuaranteed=false,readOnly=true,nativeDispatchAllowed=false}
     for point=a,b-1 do qualified[point]=true end
    end
   end
  end
  if #replacements>0 then
   local revised={}
   for _,r in ipairs(path)do
    if r.skillEnd<=77 or r.skillStart>=qualifiedEnd then revised[#revised+1]=r
    elseif r.skillEnd>qualifiedEnd then
     local copy=tableCopy(r);copy.estimatedCrafts=r.estimatedCrafts*(r.skillEnd-qualifiedEnd)/(r.skillEnd-r.skillStart)
     copy.skillStart=qualifiedEnd;revised[#revised+1]=copy
    end
   end
   for _,r in ipairs(replacements)do revised[#revised+1]=r end
   table.sort(revised,function(a,b)return a.skillStart<b.skillStart end);path=revised
   local gaps={};for _,point in ipairs(uncovered)do if not qualified[point] then gaps[#gaps+1]=point end end
   uncovered=gaps
  end
 end
 local toolRequirements
 if key=="ENCHANTING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  if facts and facts.PlanEnchantingTools then path,toolRequirements=facts:PlanEnchantingTools(path)end
 elseif key=="ENGINEERING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  if facts and facts.PlanPhysicalTools then path,toolRequirements=facts:PlanPhysicalTools(path,key)end
 end
 local requirements={};local totalEstimatedCrafts=0
 for _,step in ipairs(path) do
  totalEstimatedCrafts=totalEstimatedCrafts+step.estimatedCrafts
  for _,m in ipairs(step.materials) do
   requirements[m.itemID]=(requirements[m.itemID] or 0)+m.quantity*step.estimatedCrafts
  end
 end
 local purchaseRows={};local unknownInventory=0;local allCosts=true;local cost=0
 for itemID,required in pairs(requirements) do
  local stock=bagCount(itemID,options.inventory,ctx.stock,options.reservedStock)
  local missing=stock and max(0,required-stock) or nil
  local supply=unitSupply(ctx,itemID,0,{})
  local quote=shortQuote(itemID,options.prices,ctx.quotes)
  if stock==nil then unknownInventory=unknownInventory+1 end
  if missing==nil or not supply.known then allCosts=false
  else cost=cost+missing*supply.metric end
  purchaseRows[#purchaseRows+1]={itemID=itemID,required=required,
    stockKnown=stock~=nil,stock=stock,missing=missing,
    unitAuctionPrice=quote,acquisitionChoice=supply.method,
    craftRecipeID=supply.recipeID,outputPerCraft=supply.outputPerCraft,
    outputEvidence=supply.outputSource,
    estimatedCost=(missing and supply.known) and missing*supply.metric or nil}
 end
 table.sort(purchaseRows,function(a,b)return a.itemID<b.itemID end)
 local rolled=rollup(ctx,path)
 annotateToolBudget(rolled,toolRequirements)
 return {contract=self.contract,profession=key,skillStart=start,skillGoal=goal,
  strategy=strategy,skillRangeCovered=goal-start-#uncovered,
  uncoveredSkillPoints=uncovered,route=path,estimatedCrafts=totalEstimatedCrafts,
  materialNeeds=rolled.provisionalShoppingList,
  grossMaterialsBeforeReuse=purchaseRows,materialAcquisitionPlan=rolled,
  estimatedTotalAcquisitionCost=rolled.estimatedTotalGold,
  auctionPricesComplete=rolled.completePriceCoverage,unknownInventoryItems=rolled.inventoryUnknownCount,
  dataStatus=#uncovered==0 and "SCENARIO_COVERED" or "SOURCE_GAPS",
  recipeMinimumExcludedCandidates=ctx.rejectedMinimumCandidates,
  skillProbabilityModel="USER_APPROVED_100_60_25_0_WITH_INFERRED_GREEN_THRESHOLD",
  missingAccessQualification=true,routeGloballyOptimal=false,
  sourceProvenance=(key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and "DB70532_PLUS_FIELD_QUALIFIED_FOREVER_AND_HISTORICAL_SCHEMATICS" or key=="ENCHANTING" and "DB70532_FIELD_PROVENANCE_PLUS_CONSERVATIVE_FOREVER_GUIDE_FLOORS" or "DB70450_PLUS_FOREVER_CURATED_OUTPUTS",
  nonConsumedTools=toolRequirements,
  toolBudgetStatus=rolled.toolBudgetStatus,requiresToolVerification=rolled.requiresToolVerification,
  strategyScope=(key=="ENCHANTING" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and "ADVISORY_CAST_OR_KNOWN_OUTLAY_OR_STOCK_HEURISTIC_WITH_UNKNOWN_ACCESS_TRAVEL_RESALE" or nil,
  forecastOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  readOnly=true},nil
end
function O:PlanMaterials(key,skill,route,rows,learned,options)
 -- Exposed for audit and dedicated intermediate-product regressions.
 -- The caller passes a proposed route; nothing here executes crafts.
 options=type(options)=="table" and tableCopy(options) or {}
 options.skill=skill
 local ctx=buildContext(key,rows,learned,options)
 local tools
 if key=="ENCHANTING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  if facts and facts.PlanEnchantingTools then route,tools=facts:PlanEnchantingTools(route)end
 elseif key=="ENGINEERING" then
  local facts=JLP:GetModule("ProfessionPlanningFacts")
  if facts and facts.PlanPhysicalTools then route,tools=facts:PlanPhysicalTools(route,key)end
 end
 local result=rollup(ctx,route or {})
 annotateToolBudget(result,tools)
 return result
end
function O:PlanTo300(key,skill,rows,learned,options)
 options=type(options)=="table" and tableCopy(options) or {}
 options.goalSkill=300
 return self:Forecast(key,skill,rows,learned,options)
end
JLP:RegisterModule("UniversalRouteOptimizer",O)
