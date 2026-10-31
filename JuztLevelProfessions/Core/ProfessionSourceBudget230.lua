local _,JLP=...
-- P0-230: independently revalidated source receipts for a proposed multi-step
-- plan. Forecast outputs are CONDITIONAL, not confirmed bag stock/craft receipts.
-- Unknown inventory and prices can never become zero or free. No native calls.
local M={contract="JLP-P0-230-SOURCE-CONDITIONAL-MULTISTEP-BOM",
 readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
local function whole(n)
 return type(n)=="number" and n==n and n==math.floor(n) and n>=0 and n<2147483647
end
local function positive(n)return whole(n) and n>0 end
local function sortedItems(map,field)
 local result={}
 for id,quantity in pairs(map) do result[#result+1]={itemID=id,[field]=quantity} end
 table.sort(result,function(a,b)return a.itemID<b.itemID end)
 return result
end
function M:ReviewRoute(key,route,options)
 options=type(options)=="table" and options or {}
 local out={contract=self.contract,professionKey=key,readOnly=true,
  nativeDispatchAllowed=false,executionEligible=false,
  scenarioOnly=true,receiptBasedStockCredits=false,
  actualCraftReceipts=0,actualSkillUpReceipts=0,
  qualifiedSteps=0,withheldSteps={},steps={},grossRequirements={},
  conditionalIntermediateCredits={},knownStockUsed={},unknownInventoryItems={},
  acquisition={},unknownPriceItems={},estimatedCost=nil,
  result="NO_SOURCE_QUALIFIED_SEQUENCE",fullSourceCoverage=false,
  navigationStatus="LOCATION_UNVERIFIED",automaticWaypointAllowed=false}
 if type(route)~="table" or #route==0 or #route>100 or type(key)~="string" then
  out.result="INVALID_OR_EMPTY_SEQUENCE";return out
 end
 local field=JLP:GetModule("ProfessionFieldChain229")
 if not field or type(field.Review)~="function" then
  out.result="SOURCE_REVIEW_UNAVAILABLE";return out end
 local inventory=options.inventory;local learned=options.learnedRecipes
 local balances,gross,conditional,stockUsed,unknown={}, {}, {}, {}, {}
 local acquire={};local qualified=0;local allOK=true
 for i,entry in ipairs(route) do
  local units=type(entry)=="table" and (entry.estimatedCrafts or entry.craftCount) or nil
  if not positive(units) or units>10000 or not positive(entry.recipeID) or
      type(entry.recipe)~="string" or entry.recipe=="" then
   out.withheldSteps[#out.withheldSteps+1]={index=i,reason="INVALID_RECIPE_OR_COUNT"}
   allOK=false
  else
   local rows={};local valid=true
   for _,r in ipairs(type(entry.materials)=="table" and entry.materials or {}) do
    local q=r.quantity or r.perCraft
    if not positive(r.itemID) or not positive(q) then valid=false;break end
    local owned=type(inventory)=="table" and inventory[r.itemID]
    rows[#rows+1]={itemID=r.itemID,perCraft=q,
     bagsKnown=whole(owned)==true,bags=whole(owned) and owned or nil}
   end
   if #rows==0 then valid=false end
   local review=nil
   if valid then
    local ok,r=pcall(field.Review,field,key,{recipeID=entry.recipeID,
     recipe=entry.recipe,materials=rows,
     learned=type(learned)=="table" and learned[entry.recipeID] or nil,
     learnedSource="INPUT_CURRENT_CHARACTER_ONLY"},options.currentFaction)
    if ok and type(r)=="table" then review=r end
   end
   local verified=review and review.exactReagentsQualified==true and
       review.outputYieldQualified==true and positive(review.outputPerCraft) and
       positive(review.outputItemID) and
       (review.sourceStatus=="PUBLIC_AND_FIXED_YIELD_GRAPH_PARITY" or
        review.sourceStatus=="PUBLIC_FOREVER_REAGENTS" or
        review.sourceStatus=="FIXED_YIELD_GRAPH_EXACT_PARITY")
   if not verified then
    out.withheldSteps[#out.withheldSteps+1]={index=i,recipeID=entry.recipeID,
      reason=review and (review.sourceStatus or "YIELD_UNKNOWN") or "SOURCE_REVIEW_FAILED"}
    allOK=false
   else
    qualified=qualified+1
    local step={index=i,recipeID=entry.recipeID,recipe=entry.recipe,
      scenarioCrafts=units,outputItemID=review.outputItemID,
      fixedOutputPerCraft=review.outputPerCraft,
      outputCreditStatus="CONDITIONAL_NOT_CRAFT_RECEIPT",readOnly=true}
    for _,m in ipairs(review.materials) do
     local id,needed=m.itemID,m.required*units
     if not whole(needed) then allOK=false;step.overflow=true;break end
     gross[id]=(gross[id] or 0)+needed
     if not whole(gross[id]) then allOK=false;step.overflow=true;break end
     -- A source-produced item may already be in balances, but the original
     -- bag observation must still be known to call a SHORTAGE confirmed.
     if not (type(inventory)=="table" and whole(inventory[id])) then unknown[id]=true end
     if balances[id]==nil then
      local owned=type(inventory)=="table" and inventory[id]
      balances[id]=whole(owned) and owned or 0
      if not whole(owned) then unknown[id]=true end
     end
     local use=math.min(balances[id],needed)
     balances[id]=balances[id]-use
     stockUsed[id]=(stockUsed[id] or 0)+use
     local deficit=needed-use
     if deficit>0 then
      acquire[id]=(acquire[id] or 0)+deficit
      if not whole(acquire[id]) then allOK=false;step.overflow=true;break end
     end
    end
    if not step.overflow then
     -- This credit exists ONLY in a scenario where the recipe is positively
     -- marked as learned. Never mutate actual Inventory or persist this value.
     if type(learned)=="table" and learned[entry.recipeID]==true then
      local qty=review.outputPerCraft*units
      if whole(qty) then
       local id=review.outputItemID
       if balances[id]==nil then
        local owned=type(inventory)=="table" and inventory[id]
        balances[id]=whole(owned) and owned or 0
        -- An output item which is never used as a material does not require
        -- a bag observation to price the requested input basket.
       end
       balances[id]=balances[id]+qty
       conditional[id]=(conditional[id] or 0)+qty
       if not whole(balances[id]) or not whole(conditional[id]) then
        allOK=false;step.overflow=true
        step.outputCreditStatus="OUTPUT_OVERFLOW_WITHHELD"
       else step.conditionalOutputUnits=qty end
      else step.outputCreditStatus="OUTPUT_OVERFLOW_WITHHELD";allOK=false end
     else
      step.outputCreditStatus="LEARNED_STATE_UNKNOWN_CREDIT_WITHHELD"
     end
    end
    out.steps[#out.steps+1]=step
   end
  end
 end
 out.qualifiedSteps=qualified;out.grossRequirements=sortedItems(gross,"quantity")
 out.conditionalIntermediateCredits=sortedItems(conditional,"scenarioUnits")
 out.knownStockUsed=sortedItems(stockUsed,"quantity")
 out.unknownInventoryItems=sortedItems(unknown,"unknown")
 local priced,priceMissing=true,{}
 for _,r in ipairs(sortedItems(acquire,"provisionalQuantity")) do
  local unit=type(options.prices)=="table" and options.prices[r.itemID]
  if not whole(unit) then unit=nil end
  r.confirmedShortage=nil;r.inventoryKnown=not unknown[r.itemID]
  r.unitPrice=unit;r.estimatedCost=unit and r.provisionalQuantity*unit or nil
  if not unit then priced=false;priceMissing[r.itemID]=true end
  out.acquisition[#out.acquisition+1]=r
 end
 out.unknownPriceItems=sortedItems(priceMissing,"unknown")
 out.fullSourceCoverage=allOK and #out.withheldSteps==0
 out.result=out.fullSourceCoverage and "CONDITIONAL_SOURCE_BOM" or "INCOMPLETE_SOURCE_BOM"
 if out.fullSourceCoverage and priced and #out.unknownInventoryItems==0 then
  local cost=0
  for _,r in ipairs(out.acquisition) do cost=cost+r.estimatedCost end
  out.estimatedCost=cost
 end
 return out
end
JLP:RegisterModule("ProfessionSourceBudget230",M)
