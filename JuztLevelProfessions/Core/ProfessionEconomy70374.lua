local _, JLP = ...
-- Build-scoped, non-executing economics and progression calculations.
-- Exact owner-supplied DB2 reagent counts do NOT certify recipe access,
-- learned state, output yield, AH liquidity or a guaranteed leveling route.
local Engine={contract="JLP-ECONOMY-70374-1",sourceBuild=70374,
    readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
local BUILD=70374
local MAX_CRAFTS=9999
local MAX_TOTAL=9007199254740991 -- maximum exactly representable IEEE754 integer
local function uint(n,allowZero)
    return type(n)=="number" and n==n and n<math.huge and n>= (allowZero and 0 or 1) and n==math.floor(n) and n<=MAX_TOTAL
end
local function fail(code) return nil,code end
local function buildOK(build) return build==BUILD end
local function ref() return JLP:GetModule("Build70374ProfessionReference") end
local function registry() return JLP:GetModule("ProfessionRegistry") end
local function copyRows(items)
    local result={}
    for _,r in ipairs(items or {}) do
        result[#result+1]={itemID=r.itemID,name=r.name,perCraft=r.perCraft,rawTotal=r.rawTotal}
    end
    return result
end
local function validCrafts(count)
    return uint(count) and count<=MAX_CRAFTS
end
local function boundedSum(a,b)
    if not uint(a,true) or not uint(b,true) or a>MAX_TOTAL-b then return nil end
    return a+b
end
local function basisPoints(amount,bps)
    -- Divide first: avoid imprecise >2^53 intermediates in copper accounting.
    local q,r=math.floor(amount/10000),amount%10000
    return q*bps+math.floor(r*bps/10000)
end
local function formatCopper(amount)
    if not uint(amount,true) then return "unknown" end
    local gold=math.floor(amount/10000)
    local silver=math.floor((amount%10000)/100)
    local copper=amount%100
    return string.format("%dg %ds %dc",gold,silver,copper)
end
local function validateBuildAndKey(key,build)
    if not buildOK(build) then return nil,"EXPLICIT_BUILD_70374_REQUIRED" end
    local r=registry()
    local normalized=r and r:NormalizeKey(key)
    if not normalized then return nil,"UNKNOWN_PROFESSION" end
    return normalized
end
local function inventory(itemID,opts)
    opts=opts or {}
    local observation=type(opts.stockByItemID)=="table" and opts.stockByItemID[itemID] or nil
    if observation==nil and opts.stockByItemID==nil then
        local inv=JLP:GetModule("Inventory")
        if inv and type(inv.GetOwned)=="function" then
            local ok,owned=pcall(inv.GetOwned,inv,itemID)
            if ok and type(owned)=="table" then observation=owned end
        end
    end
    if type(observation)~="table" then return {state="STOCK_UNKNOWN",bagsKnown=false,bankKnown=false} end
    local bags=observation.bags
    local bank=observation.bank
    local bagsKnown=observation.bagKnown==true and uint(bags,true) and observation.snapshotStale~=true
    local bankKnown=observation.bankKnown==true and uint(bank,true) and
        observation.bankStale~=true and observation.snapshotStale~=true
    return {state=not bagsKnown and "BAGS_UNKNOWN" or
        (opts.includeBank==true and not bankKnown and "BANK_UNKNOWN" or "KNOWN"),
        bagsKnown=bagsKnown and true or false, bankKnown=bankKnown and true or false,
        bags=bagsKnown and bags or nil,bank=bankKnown and bank or nil,
        -- Bank stock is not immediately craft-ready. A quote including it
        -- describes a future retrieval plan, not an immediate craft action.
        bankRetrievalRequired=opts.includeBank==true and bankKnown and bank>0 or false}
end
local function priceFor(itemID,qty,opts)
    if qty==0 then return {complete=true,amount=0,basis="NOT_REQUIRED",marketVerified=true} end
    local resolver=JLP:GetModule("PriceResolver")
    local quote=resolver and resolver.GetFulfillmentCost and resolver:GetFulfillmentCost(itemID,qty)
    local ahOK=type(quote)=="table" and quote.complete==true and
        quote.trustedForCostEstimate==true and uint(quote.cost,true)
    local historicalVendor=nil
    local co=JLP:GetModule("CostOptimizer")
    if co and type(co.GetVendorUnitPrice)=="function" then
        local ok,p=pcall(co.GetVendorUnitPrice,co,itemID)
        if ok and uint(p,true) and p>0 and p<=math.floor(MAX_TOTAL/qty) then historicalVendor=p*qty end
    end
    local strategy=opts.priceStrategy or "LOWEST_INDICATIVE"
    if strategy~="LOWEST_INDICATIVE" and strategy~="AH_ONLY" and strategy~="VENDOR_REFERENCE" then
        return {complete=false,basis="INVALID_PRICE_STRATEGY"}
    end
    if strategy=="VENDOR_REFERENCE" then ahOK=false end
    local vendorEligible=historicalVendor and strategy~="AH_ONLY"
    -- Historic item vendor pricing is not proof of a current-build vendor
    -- stocking this item, and is NEVER promoted to a verified purchase.
    if ahOK and (not vendorEligible or quote.cost<=historicalVendor) then
        return {complete=true,amount=quote.cost,basis="AH_FULFILLMENT_DEPTH",
            marketVerified=true,sourceSnapshot=quote.snapshotKey,
            receipt=quote.itemPriceReceipt,unitMin=quote.minUnitBuyout}
    end
    if vendorEligible then
        return {complete=true,amount=historicalVendor,basis="HISTORIC_VENDOR_REFERENCE",
            marketVerified=false,historicalVendor=true,
            sourceState="STOCK_AND_PRICE_NOT_VERIFIED_IN_BUILD_70374"}
    end
    return {complete=false,amount=nil,basis=quote and quote.status or "PRICE_NOT_AVAILABLE",
        marketVerified=false,fulfilled=quote and quote.fulfilled or 0,
        missing=quote and quote.missing or qty}
end
function Engine:GetRecipeMaterials(key,spellID,crafts,build)
    local normalized,reason=validateBuildAndKey(key,build)
    if not normalized then return fail(reason) end
    if not uint(spellID) then return fail("INVALID_SPELL_ID") end
    if not validCrafts(crafts) then return fail("INVALID_CRAFT_COUNT") end
    local reference=ref()
    if not reference then return fail("REFERENCE_UNAVAILABLE") end
    local row,err=reference:GetRecipe(normalized,spellID,build)
    if not row then return fail(err) end
    if not row.reagents then return fail(row.reagentStatus or "REAGENTS_UNKNOWN") end
    local materials,why=reference:GetMaterialRequirements(normalized,spellID,crafts,build)
    if not materials then return fail(why) end
    return {contract="JLP-70374-MATERIALS-1",professionKey=normalized,spellID=spellID,
        recipeName=row.name,crafts=crafts,sourceBuild=BUILD,
        reagentDataState=row.reagentStatus,requirements=copyRows(materials.requirements),
        -- Empty DB2 reagent slots are not proof of free production.
        emptyReagents=#materials.requirements==0,
        craftingReady=false,recipeAccessVerified=false,outputYieldVerified=false,
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end
function Engine:BuildBill(steps,build,opts)
    if not buildOK(build) then return fail("EXPLICIT_BUILD_70374_REQUIRED") end
    if type(steps)~="table" or #steps<1 or #steps>200 then return fail("INVALID_STEP_LIST") end
    opts=type(opts)=="table" and opts or {}
    local totals,normalizedSteps={},{}
    for i,step in ipairs(steps) do
        if type(step)~="table" then return fail("INVALID_STEP_"..i) end
        local name,why=validateBuildAndKey(step.professionKey,build)
        if not name then return fail(why) end
        local materials,err=self:GetRecipeMaterials(name,step.spellID,step.crafts,build)
        if not materials then return fail("STEP_"..i.."_"..tostring(err)) end
        if materials.emptyReagents then return fail("STEP_"..i.."_EMPTY_REAGENT_EVIDENCE") end
        normalizedSteps[#normalizedSteps+1]={professionKey=name,spellID=step.spellID,
            recipeName=materials.recipeName,crafts=step.crafts}
        for _,part in ipairs(materials.requirements) do
            local row=totals[part.itemID]
            if not row then
                row={itemID=part.itemID,name=part.name,required=0,usedBy={}}
                totals[part.itemID]=row
            end
            local total=boundedSum(row.required,part.rawTotal)
            if not total then return fail("QUANTITY_OVERFLOW") end
            row.required=total
            row.usedBy[#row.usedBy+1]={professionKey=name,spellID=step.spellID,
                crafts=step.crafts,quantity=part.rawTotal}
        end
    end
    local rows={}
    local stockComplete=true
    for _,row in pairs(totals) do
        local owned=inventory(row.itemID,opts)
        row.inventory=owned
        if owned.state=="KNOWN" then
            local available=owned.bags+(opts.includeBank==true and owned.bank or 0)
            row.available=available
            row.missing=math.max(0,row.required-available)
            row.bankRetrievalNeeded=opts.includeBank==true and
                math.min(owned.bank or 0,math.max(0,row.required-owned.bags)) or 0
        else
            row.available=nil;row.missing=nil;stockComplete=false
        end
        rows[#rows+1]=row
    end
    table.sort(rows,function(a,b) return a.itemID<b.itemID end)
    return {contract="JLP-70374-BATCH-BILL-1",sourceBuild=BUILD,
        steps=normalizedSteps,materials=rows,itemTypes=#rows,
        stockComplete=stockComplete,assumeZeroStock=false,
        totalsAreExactForListedRawReagents=true,intermediateCraftNettingApplied=false,
        outputYieldsKnown=false,progressionSuccessGuaranteed=false,
        materialEvidenceState="OWNER_DB2_REAGENT_REFERENCE",
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end
function Engine:QuoteBill(bill,opts)
    if type(bill)~="table" or bill.contract~="JLP-70374-BATCH-BILL-1" or
       bill.sourceBuild~=BUILD or bill.nativeDispatchAllowed~=false or
       type(bill.materials)~="table" then return fail("UNQUALIFIED_BILL") end
    opts=type(opts)=="table" and opts or {}
    local totalGross,totalCash=0,0
    local grossComplete,cashComplete=true,true
    local grossVerified,cashVerified=true,true
    local rows={}
    for _,row in ipairs(bill.materials) do
        if not uint(row.itemID) or not uint(row.required,true) or
           (row.missing~=nil and (not uint(row.missing,true) or row.missing>row.required)) then
           return fail("BILL_MUTATED") end
        local gross=priceFor(row.itemID,row.required,opts)
        local cash=row.missing~=nil and priceFor(row.itemID,row.missing,opts) or nil
        local report={itemID=row.itemID,name=row.name,required=row.required,missing=row.missing,
            gross=gross,cash=cash,inventoryState=row.inventory and row.inventory.state or "UNKNOWN"}
        rows[#rows+1]=report
        if not gross.complete then grossComplete=false else
            local nextTotal=boundedSum(totalGross,gross.amount)
            if not nextTotal then return fail("COPPER_OVERFLOW") end
            totalGross=nextTotal
            if not gross.marketVerified then grossVerified=false end
        end
        if not cash or not cash.complete then cashComplete=false else
            local nextTotal=boundedSum(totalCash,cash.amount)
            if not nextTotal then return fail("COPPER_OVERFLOW") end
            totalCash=nextTotal
            if not cash.marketVerified then cashVerified=false end
        end
    end
    return {contract="JLP-70374-COST-QUOTE-1",sourceBuild=BUILD,
        grossComplete=grossComplete,cashComplete=cashComplete,
        grossCostCopper=grossComplete and totalGross or nil,
        cashRequiredCopper=cashComplete and totalCash or nil,
        grossVerified=grossComplete and grossVerified,
        cashVerified=cashComplete and cashVerified,
        knownGrossPartialCopper=totalGross,knownCashPartialCopper=totalCash,
        strategy=opts.priceStrategy or "LOWEST_INDICATIVE",rows=rows,
        -- AH listings are asks; missing depth is not free, vendor stock is unverified.
        snapshotSensitive=true,needsReceiptRecheck=true,
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end
function Engine:QuoteRecipe(key,spellID,crafts,build,opts)
    local bill,reason=self:BuildBill({{professionKey=key,spellID=spellID,crafts=crafts}},build,opts)
    if not bill then return fail(reason) end
    local quote,err=self:QuoteBill(bill,opts)
    if not quote then return fail(err) end
    local recipe=assert(ref():GetRecipe(key,spellID,build))
    local value={contract="JLP-70374-RECIPE-ECONOMICS-1",
        professionKey=recipe.professionKey,spellID=spellID,recipeName=recipe.name,
        crafts=crafts,materials=bill,cost=quote,
        outputItems=recipe.outputs,outputQuantity=nil,outputRevenueCopper=nil,
        ahCutCopper=nil,projectedProfitCopper=nil,
        profitabilityState="OUTPUT_YIELD_UNVERIFIED",
        sourceBuild=BUILD,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false}
    -- Client SpellEffectBasePoints are not an audited craft yield. A known
    -- output ItemID alone cannot turn an unknown yield into a profit number.
    return value
end
-- Only a what-if margin against present AH ASK prices, never a realized sale.
-- A raw DB2 effect does not establish the number of resulting items.
function Engine:ProjectSaleScenario(key,spellID,crafts,build,options)
    options=type(options)=="table" and options or {}
    local quantity=options.outputUnitsPerCraft
    local feeBps=options.saleFeeBps
    local sellFraction=options.saleFractionBps or 10000
    if not validCrafts(crafts) or not uint(quantity) or quantity>9999 or
       not uint(feeBps,true) or feeBps>10000 or
       not uint(sellFraction,true) or sellFraction>10000 then
        return fail("SCENARIO_INPUT_REQUIRED")
    end
    local scenario,reason=self:QuoteRecipe(key,spellID,crafts,build,options)
    if not scenario then return fail(reason) end
    local outputs=scenario.outputItems or {}
    if #outputs~=1 or not uint(outputs[1].itemID) then
        return fail("UNIQUE_OUTPUT_ITEM_UNKNOWN")
    end
    local resolver=JLP:GetModule("PriceResolver")
    local row,q=nil,nil
    if resolver and type(resolver.GetItemSnapshot)=="function" then
        row,q=resolver:GetItemSnapshot(outputs[1].itemID)
    end
    if type(q)~="table" or q.trustedForCostEstimate~=true or
       type(row)~="table" or not uint(row.minUnitBuyout) or row.priceMalformed then
        return fail("OUTPUT_AH_ASK_UNAVAILABLE")
    end
    if crafts>math.floor(MAX_TOTAL/quantity) then return fail("OUTPUT_OVERFLOW") end
    local amount=crafts*quantity
    if row.minUnitBuyout>math.floor(MAX_TOTAL/amount) then return fail("COPPER_OVERFLOW") end
    local gross=amount*row.minUnitBuyout
    local realized=basisPoints(gross,sellFraction)
    local fee=basisPoints(realized,feeBps)
    local costs=scenario.cost
    -- Gross material quote is used for a comparable all-purchased-inputs scenario.
    -- Never silently subtract unknown bag opportunity costs.
    local ingredientCost=costs.grossCostCopper
    local projected=ingredientCost and (realized-fee-ingredientCost) or nil
    return {contract="JLP-70374-AH-WHATIF-1",professionKey=scenario.professionKey,
        spellID=spellID,crafts=crafts,outputItemID=outputs[1].itemID,
        assumedOutputUnitsPerCraft=quantity,assumedSoldFractionBps=sellFraction,
        assumedFeeBps=feeBps,observedAHAskCopper=row.minUnitBuyout,
        projectedGrossCopper=realized,projectedFeeCopper=fee,
        materialGrossCopper=ingredientCost,projectedMarginCopper=projected,
        marginKnown=projected~=nil,sourceCostAllCurrentAH=costs.grossVerified,
        liquidityVerified=false,outputYieldVerified=false,
        depositIncluded=false,vendorPriceVerified=false,
        status=projected and "WHAT_IF_NOT_REALIZED_PROFIT" or "COST_INCOMPLETE",
        sourceBuild=BUILD,readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end

-- Even a previously verified price receipt must be rechecked against the current
-- scoped snapshot prior to presenting it as current. Vendor references never pass.
function Engine:RecheckQuoteReceipts(quote)
    if type(quote)~="table" or quote.contract~="JLP-70374-COST-QUOTE-1" or
       quote.sourceBuild~=BUILD or type(quote.rows)~="table" then
        return false,"INVALID_QUOTE"
    end
    local resolver=JLP:GetModule("PriceResolver")
    if not resolver or type(resolver.ItemPriceReceiptMatches)~="function" then
        return false,"PRICE_RESOLVER_UNAVAILABLE"
    end
    if not quote.grossComplete or not quote.grossVerified then return false,"NON_VERIFIED_GROSS_QUOTE" end
    for _,row in ipairs(quote.rows) do
        local item=row.gross
        if type(item)~="table" or item.basis=="NOT_REQUIRED" then
            if type(item)~="table" or item.basis~="NOT_REQUIRED" then return false,"MISSING_RECEIPT" end
        elseif item.basis~="AH_FULFILLMENT_DEPTH" or
            not resolver:ItemPriceReceiptMatches(row.itemID,item.receipt) then
            return false,"SNAPSHOT_RECEIPT_CHANGED"
        end
    end
    return true,"AH_RECEIPTS_CURRENT"
end
function Engine:GetProgressionCandidates(key,skill,build,offset,limit)
    local normalized,reason=validateBuildAndKey(key,build)
    if not normalized then return fail(reason) end
    if not uint(skill,true) or skill>999 then return fail("INVALID_SKILL") end
    offset=offset or 0;limit=limit or 10
    if not uint(offset,true) or offset>10000 or not uint(limit) or limit>30 then return fail("INVALID_PAGE") end
    local reference=ref();if not reference then return fail("REFERENCE_UNAVAILABLE") end
    local candidates,err=reference:GetSkillCandidates(normalized,skill,offset,limit,build)
    if not candidates then return fail(err) end
    local all={}
    for _,recipe in ipairs(candidates.rows) do
        all[#all+1]={professionKey=normalized,spellID=recipe.spellID,
            name=recipe.name,skill=skill,rawLow=recipe.trivialRankLowRaw,
            rawHigh=recipe.trivialRankHighRaw,reagentTypes=#recipe.reagents,
            candidateOnly=true,learnedState="UNKNOWN",
            skillUpProbabilityKnown=false,trainerGateKnown=false,
            outputYieldKnown=false,acquisitionVerified=false,
            nativeDispatchAllowed=false}
    end
    local total=candidates.total
    local reg=registry();local def=reg and reg:Get(normalized)
    local kind=def and def.progressionStrategies and def.progressionStrategies[1] or "UNKNOWN"
    return {contract="JLP-70374-PROGRESSION-CANDIDATES-1",professionKey=normalized,
        skill=skill,sourceBuild=BUILD,professionStrategy=kind,
        rows=all,total=total,offset=offset,limit=limit,
        completeLevelingRoute=false,skillUpCountsVerified=false,
        thresholdsAreRawDB2NotFourColorProof=true,
        notALearningOrCraftExecutionAuthorization=true,
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end
-- Coarse skill checkpoints for ALL profession strategies. This is a
-- research worksheet, not a 1-300 recipe order or a quantity forecast.
function Engine:BuildProgressionWorksheet(key,startSkill,targetSkill,build,options)
    local normalized,reason=validateBuildAndKey(key,build)
    if not normalized then return fail(reason) end
    if not uint(startSkill,true) or not uint(targetSkill,true) or
       startSkill>=targetSkill or targetSkill>300 then return fail("INVALID_SKILL_RANGE") end
    options=type(options)=="table" and options or {}
    local interval=options.interval or 25
    if not uint(interval) or interval<5 or interval>100 then return fail("INVALID_INTERVAL") end
    if math.ceil((targetSkill-startSkill)/interval)>60 then return fail("TOO_MANY_CHECKPOINTS") end
    local reg=registry()
    local def=reg and reg:Get(normalized)
    local kind=def and def.progressionStrategies and def.progressionStrategies[1] or "UNKNOWN"
    local checkpoints={}
    local s=startSkill
    while s<targetSkill do
        local ending=math.min(s+interval,targetSkill)
        local found,err=self:GetProgressionCandidates(normalized,s,build,0,3)
        if not found then return fail(err) end
        local activity=(kind=="NODE_GATHERING" or kind=="AREA_GATHERING" or kind=="FISHING_AREA")
            and "GATHER_IN_SUITABLE_ZONES" or "RESEARCH_RECIPE_CHOICES"
        checkpoints[#checkpoints+1]={fromSkill=s,toSkill=ending,
            activityKind=activity,candidates=found.rows,rawBandCandidateCount=found.total,
            -- No training gates, learned recipes, drop rates or skill-up odds
            -- have been verified from the owner's static DB2 export.
            craftCount=nil,skillUpsExpected=nil,materialTotal=nil,
            skillUpProbabilityVerified=false,sourceAccessVerified=false,
            mapContextRequired=activity=="GATHER_IN_SUITABLE_ZONES"}
        s=ending
    end
    return {contract="JLP-70374-PROGRESSION-WORKSHEET-1",
        professionKey=normalized,startSkill=startSkill,targetSkill=targetSkill,
        sourceBuild=BUILD,strategy=kind,checkpoints=checkpoints,
        skillRangeCoveredByCheckpoints=true,
        endToEndExecutableRoute=false,recipeAccessQualified=false,
        skillUpCountsVerified=false,trainerGatesVerified=false,
        estimatedCraftTotals=nil,estimatedTotalGold=nil,
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end
function Engine:GetSummary(key,spellID,crafts,build)
    if not key then
        return "Economics 70374 (read-only): /jlp econ PROFESSION SPELL_ID [CRAFTS] | "..
            "/jlp mats PROFESSION SPELL_ID [CRAFTS] | /jlp progress70374 PROFESSION SKILL. "..
            "Use current matching client build; no purchase/skill-up guarantees."
    end
    if spellID then
        local recipe,err=self:QuoteRecipe(key,spellID,crafts or 1,build)
        if not recipe then return "Economics unavailable: "..tostring(err) end
        local q=recipe.cost
        local label=q.grossComplete and formatCopper(q.grossCostCopper) or "UNKNOWN"
        local cash=q.cashComplete and formatCopper(q.cashRequiredCopper) or "UNKNOWN"
        return string.format("%s / %d x %s: %d reagent item types | gross %s (%s) | cash %s (%s) | profit UNKNOWN (yield not certified). Reference only.",
            key,crafts or 1,recipe.recipeName,#recipe.materials.materials,label,
            q.grossVerified and "current AH" or "partial/historic/unverified",
            cash,q.cashVerified and "current AH" or "unknown/historic/unverified")
    end
    return self:GetSummary()
end
function Engine:FormatCopper(amount) return formatCopper(amount) end
JLP:RegisterModule("ProfessionEconomy70374",Engine)
