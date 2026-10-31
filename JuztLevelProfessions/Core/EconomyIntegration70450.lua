local _,JLP=...
-- M28: advisory, build-scoped multi-profession acquisition worksheet.
-- This module does NOT grant recipe, inventory, quote, vendor, route or native rights.
local S={contract="JLP-ECONOMY-COHERENCE-70450-1",sourceBuild=70450,
    readOnly=true,nativeDispatchAllowed=false,purchaseAllowed=false,
    productionAuthority=false,maxEntries=24,maxUnits=1000000000}
local BUILD=70450
local MAX_SAFE=9007199254740991
local function integer(v,low,high)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge and
        v==math.floor(v) and v>=(low or 0) and v<=(high or MAX_SAFE)
end
local function call(obj,fn,...)
    if type(obj)~="table" or type(obj[fn])~="function" then return nil end
    local ok,val=pcall(obj[fn],obj,...)
    return ok and val or nil
end
local function now()
    if type(time)~="function" then return nil end
    local ok,t=pcall(time)
    return ok and integer(t,1) and t or nil
end
local function scope()
    local inv=JLP:GetModule("Inventory")
    local id=call(inv,"GetCurrentCharacterIdentity")
    if type(id)~="table" or type(id.key)~="string" or id.key=="" or
       id.key:find("Unknown",1,true) then return nil end
    return id.key
end
local function cleanName(v)
    return type(v)=="string" and v~="" and v or nil
end
local function copyRequirements(entry,aggregated)
    for _,r in ipairs(entry.itemRows or {}) do
        if not integer(r.itemID,1) or not integer(r.required,1) or
           not integer(r.perCraft,1) or r.perCraft*entry.crafts~=r.required then
            return false,"MATERIAL_ID_OR_QUANTITY_INVALID"
        end
        local dst=aggregated[r.itemID]
        if not dst then
            dst={itemID=r.itemID,name=cleanName(r.name),required=0,recipes={}}
            aggregated[r.itemID]=dst
        end
        if dst.required>S.maxUnits-r.required then return false,"MATERIAL_TOTAL_OVERFLOW" end
        dst.required=dst.required+r.required
        dst.recipes[#dst.recipes+1]={professionKey=entry.professionKey,
            spellID=entry.spellID,crafts=entry.crafts,required=r.required,
            perCraft=r.perCraft}
    end
    return true
end
-- Treat a bank from another session as a historical observation, never as
-- currently accessible stock. No automatic bank opening or withdrawal occurs.
local function stockFor(itemID,required)
    local inv=JLP:GetModule("Inventory")
    local owned=call(inv,"GetOwned",itemID)
    owned=type(owned)=="table" and owned or {}
    local t=now()
    local key=scope()
    local bags=integer(owned.bags,0) and owned.bags or nil
    local bagStamp=owned.bagCacheUpdatedAt
    local bagRecent=t and integer(bagStamp,1) and bagStamp<=t and t-bagStamp<=60
    local bagKnown=owned.bagKnown==true and bags~=nil and key~=nil and
        (owned.bagEvidence=="CLIENT_ITEM_COUNT_API" or
         owned.bagEvidence=="CONTAINER_SCAN" or
         (owned.bagEvidence=="SAVED_BAG_CACHE" and bagRecent))
    local bank=integer(owned.bank,0) and owned.bank or nil
    local bankKnown=owned.bankKnown==true and bank~=nil
    local open=call(inv,"IsBankOpen")==true
    local stamp=owned.bankCacheUpdatedAt
    local timeOK=t and integer(stamp,1) and stamp<=t and t-stamp<=300
    local openedAt=owned.bankOpenedAt
    local bankLive=bankKnown and open and timeOK and key~=nil and
        integer(openedAt,1) and integer(stamp,1) and stamp>=openedAt and
        owned.bankEvidence=="SAVED_ORDINARY_BANK_SNAPSHOT"
    -- Stored bank rows, including recent rows after closing the UI, do not
    -- establish the quantity that can be retrieved for this plan right now.
    local currentBags=bagKnown and bags or nil
    local currentBank=bankLive and bank or nil
    local missing=(currentBags~=nil and currentBank~=nil) and
        math.max(0,required-currentBags-currentBank) or nil
    local upper=bagKnown and math.max(0,required-bags) or required
    local lower=missing or 0 -- unknown bank can cover any remainder
    return {itemID=itemID,bagKnown=bagKnown,currentBags=currentBags,
        bagsEvidence=bagKnown and owned.bagEvidence or "UNKNOWN",
        bankKnown=bankLive,currentBank=currentBank,
        savedBankAdvisory=bankKnown and bank or nil,
        bankEvidence=bankLive and "LIVE_OPEN_ORDINARY_BANK" or
            bankKnown and "SAVED_BANK_ADVISORY" or "BANK_UNKNOWN",
        bankSnapshotAt=integer(stamp,1) and stamp or nil,
        bankOpen=open,bankLive=bankLive,characterKey=key,
        externalRequired=missing,lowerExternalBound=lower,upperExternalBound=upper,
        retrieveFromBank=(bagKnown and bankLive) and math.min(bank,math.max(0,required-bags)) or nil}
end
local function priceFor(id,quantity)
    if quantity==0 then return {state="NO_PURCHASE_NEEDED",cost=0,priced=0,
        costOptimal=true,optimizationStatus="EXACT",purchasedQuantity=0,excessQuantity=0} end
    if not integer(quantity,1,S.maxUnits) then return {state="QUANTITY_UNKNOWN",cost=nil,priced=0} end
    local resolver=JLP:GetModule("PriceResolver")
    local scanner=JLP:GetModule("AuctionScanner")
    local snapshot=call(scanner,"GetSnapshot")
    -- A price scan must belong to the LIVE client, not to the 70450 recipe
    -- reference dataset. PriceResolver verifies scope, freshness and build.
    if type(snapshot)~="table" then
        return {state="AH_BUILD_NOT_VERIFIED",cost=nil,priced=0}
    end
    local qualification=call(resolver,"QualifySnapshot",snapshot)
    if type(qualification)~="table" or qualification.trustedForCostEstimate~=true or
        qualification.snapshotBuild~=snapshot.clientBuild or qualification.buildVerified~=true then
        return {state="AH_SNAPSHOT_UNQUALIFIED",cost=nil,priced=0}
    end
    local quote=call(resolver,"GetFulfillmentCost",id,quantity)
    -- Preserve the distinct depth-shortage diagnosis without turning a
    -- partial quantity into a trusted or zero-copper cost estimate.
    if type(quote)=="table" and quote.complete==false and
       quote.status=="INSUFFICIENT_BUYOUT_DEPTH" and
       quote.snapshotKey==qualification.snapshotKey and
       quote.requested==quantity and integer(quote.fulfilled,0) and
       quote.fulfilled<quantity and quote.cost==nil then
        return {state="AH_DEPTH_INSUFFICIENT",cost=nil,priced=quote.fulfilled,
            snapshotKey=qualification.snapshotKey}
    end
    if type(quote)~="table" or quote.trustedForCostEstimate~=true or
       quote.snapshotKey~=qualification.snapshotKey or
       not integer(quote.requested,1) or quote.requested~=quantity or
       not integer(quote.fulfilled,0) or quote.fulfilled>quantity or
       not integer(quote.cost,0,MAX_SAFE) or type(quote.itemPriceReceipt)~="string" or
       call(resolver,"ItemPriceReceiptMatches",id,quote.itemPriceReceipt)~=true then
        return {state="AH_ITEM_PRICE_UNVERIFIED",cost=nil,priced=0}
    end
    if quote.complete~=true or quote.fulfilled~=quantity then
        return {state="AH_DEPTH_INSUFFICIENT",cost=nil,priced=quote.fulfilled,
            snapshotKey=qualification.snapshotKey,itemPriceReceipt=quote.itemPriceReceipt}
    end
    return {state="AH_FULL_DEPTH_ESTIMATE",cost=quote.cost,priced=quantity,
        snapshotKey=qualification.snapshotKey,itemPriceReceipt=quote.itemPriceReceipt,
        source="REPLICATE_WHOLE_BUYOUT_LISTINGS",costOptimal=quote.costOptimal==true,
        optimizationStatus=type(quote.optimizationStatus)=="string" and quote.optimizationStatus or "OPTIMALITY_UNVERIFIED",
        purchasedQuantity=integer(quote.purchasedQuantity,quantity) and quote.purchasedQuantity or nil,
        excessQuantity=integer(quote.excessQuantity,0) and quote.excessQuantity or nil,readOnly=true}
end
function S:GetBasket(entries,build)
    if build~=nil and not integer(build,1) then return nil,"INVALID_CLIENT_OR_REFERENCE_BUILD" end
    if type(entries)~="table" or #entries<1 or #entries>self.maxEntries then
        return nil,"ENTRY_COUNT_INVALID"
    end
    local count=0
    for index in pairs(entries) do
        count=count+1
        if not integer(index,1,self.maxEntries) then return nil,"ENTRY_LIST_NOT_DENSE" end
    end
    if count~=#entries then return nil,"ENTRY_LIST_NOT_DENSE" end
    for index=1,count do
        if type(rawget(entries,index))~="table" then return nil,"ENTRY_LIST_NOT_DENSE" end
    end
    -- Historic recipe/reagent data remain advisory on every live client;
    -- never mistake their 70450 source tag for this session's build number.
    local owner=scope()
    if not owner then return nil,"CURRENT_CHARACTER_UNVERIFIED" end
    local materials=JLP:GetModule("MaterialsSources70450")
    if type(materials)~="table" then return nil,"MATERIAL_SOURCE_UNAVAILABLE" end
    local aggregate,sourceRows,unresolved={}, {},false
    for _,entry in ipairs(entries) do
        if type(entry)~="table" or type(entry.professionKey)~="string" or
           not integer(entry.spellID,1) or not integer(entry.crafts,1,9999) then
            return nil,"INVALID_RECIPE_REQUEST"
        end
        local recipe,why=materials:GetRecipe(entry.professionKey,entry.spellID,entry.crafts,BUILD)
        if not recipe then return nil,why or "RECIPE_UNAVAILABLE" end
        if recipe.professionKey~=entry.professionKey or recipe.spellID~=entry.spellID or
           recipe.crafts~=entry.crafts or recipe.sourceBuild~=BUILD or
           recipe.nativeDispatchAllowed~=false or recipe.productionAuthority~=false then
            return nil,"MATERIAL_RECEIPT_NOT_READ_ONLY_OR_IDENTITY_CONFLICT"
        end
        if recipe.materialState~="SOURCE_REAGENTS_PRESENT" then unresolved=true end
        local row={professionKey=recipe.professionKey,spellID=recipe.spellID,
            crafts=recipe.crafts,recipeName=cleanName(recipe.recipeName),
            materialState=recipe.materialState,sourceStatus=recipe.sourceStatus,
            readOnly=true}
        sourceRows[#sourceRows+1]=row
        local ok,err=copyRequirements(recipe,aggregate)
        if not ok then return nil,err end
    end
    local rows={};for _,v in pairs(aggregate) do rows[#rows+1]=v end
    table.sort(rows,function(a,b) return a.itemID<b.itemID end)
    local allStockKnown,allPricesKnown=true,true
    local total,external=0,0
    local costOptimal,optimizationStatus=true,"EXACT"
    local fingerprint={self.contract,tostring(BUILD),owner}
    for _,entry in ipairs(sourceRows) do
        fingerprint[#fingerprint+1]=table.concat({entry.professionKey,entry.spellID,
            entry.crafts,entry.materialState},":")
    end
    for _,row in ipairs(rows) do
        row.stock=stockFor(row.itemID,row.required)
        row.externalRequired=row.stock.externalRequired
        row.externalLowerBound=row.stock.lowerExternalBound
        row.externalUpperBound=row.stock.upperExternalBound
        row.currentOwnedKnown=row.stock.bagKnown and row.stock.bankKnown
        row.price=row.externalRequired and priceFor(row.itemID,row.externalRequired) or
            {state="STORAGE_NOT_VERIFIED",cost=nil,priced=0}
        if row.externalRequired==nil then allStockKnown=false
        else external=external+row.externalRequired end
        if row.price.cost==nil then allPricesKnown=false
        else
            if row.price.cost>MAX_SAFE-total then return nil,"COST_TOTAL_OVERFLOW" end
            total=total+row.price.cost
        end
        if row.price.costOptimal~=true then
            costOptimal=false
            local status=row.price.optimizationStatus or "OPTIMALITY_UNVERIFIED"
            if optimizationStatus~="BOUNDED_HEURISTIC" then optimizationStatus=status end
        end
        row.readOnly=true;row.nativeDispatchAllowed=false;row.purchaseAllowed=false
        fingerprint[#fingerprint+1]=table.concat({row.itemID,row.required,
            tostring(row.stock.currentBags),tostring(row.stock.currentBank),
            tostring(row.stock.bankSnapshotAt),row.stock.bankEvidence,
            row.price.state,tostring(row.price.cost),
            tostring(row.price.itemPriceReceipt),tostring(row.price.costOptimal),
            tostring(row.price.optimizationStatus)},":")
    end
    local ready=not unresolved and allStockKnown
    local priced=ready and allPricesKnown
    return {contract=self.contract,sourceBuild=BUILD,characterKey=owner,
        recipes=sourceRows,materialTypes=#rows,rows=rows,
        materialsComplete=not unresolved,stockComplete=ready,
        totalExternalRequired=ready and external or nil,
        totalCostEstimate=priced and total or nil,
        costOptimal=priced and costOptimal or false,
        optimizationStatus=priced and optimizationStatus or "UNKNOWN",
        priceState=priced and "COMPLETE_ADVISORY" or
            not ready and "REQUIREMENTS_OR_STORAGE_UNKNOWN" or "MARKET_PRICE_UNKNOWN",
        status=unresolved and "REAGENT_SOURCE_UNRESOLVED" or
            not allStockKnown and "STORAGE_VERIFICATION_REQUIRED" or
            not allPricesKnown and "PRICE_VERIFICATION_REQUIRED" or "ADVISORY_ESTIMATE_READY",
        receipt=table.concat(fingerprint,"||"),
        quoteAssumptions="Whole buyout listings from a qualified scan; purchase-time availability unverified; optimization limits disclosed per quote",
        canBuy=false,canCraft=false,readOnly=true,nativeDispatchAllowed=false,
        purchaseAllowed=false,productionAuthority=false},nil
end
function S:GetRecipePlan(key,spell,crafts,build)
    return self:GetBasket({{professionKey=key,spellID=spell,crafts=crafts or 1}},build)
end
function S:GetCurrentStep(key,build,crafts)
    if build~=nil and not integer(build,1) then return nil,"INVALID_CLIENT_OR_REFERENCE_BUILD" end
    local planner=JLP:GetModule("Planner")
    local plan=call(planner,"GetProfessionPlan",key)
    if type(plan)~="table" or plan.actionKind~="craft" or
        type(plan.step)~="table" then return nil,"CURRENT_STEP_NOT_A_CRAFT" end
    local id=plan.step.recipeID or plan.step.spellID
    if not integer(id,1) then return nil,"CURRENT_STEP_RECIPE_ID_UNVERIFIED" end
    local output,reason=self:GetRecipePlan(key,id,crafts or 1,build)
    if not output then return nil,reason end
    output.currentStep=true
    output.currentStepSkillTarget=plan.step.skillTarget
    output.craftCountBasis=crafts and "EXPLICIT_USER_COUNT" or "SINGLE_CRAFT_PREVIEW"
    return output
end
function S:ReceiptStillCurrent(previous,entries,build)
    if type(previous)~="table" or previous.contract~=self.contract or
        type(previous.receipt)~="string" or previous.readOnly~=true then
        return false,"RECEIPT_INVALID"
    end
    local current,why=self:GetBasket(entries,build)
    if not current then return false,why end
    return current.receipt==previous.receipt,
        current.receipt==previous.receipt and "CURRENT_READ_ONLY" or "INPUT_OR_SNAPSHOT_CHANGED"
end
JLP:RegisterModule("EconomyIntegration70450",S)
