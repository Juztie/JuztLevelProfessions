local _, JLP = ...
-- Reference-backed, advisory material accounting. Every craft step runs in
-- research order. Only output explicitly published in Forever is credited.
-- Historical craft counts remain estimates: no readiness or dispatch authority.
local Flow={contract="forever-material-flow-v1",persisted=false,
    nativeDispatchAllowed=false,executionEligible=false,requiresLiveQA=false}
local function integer(n) return type(n)=="number" and n>=0 and n==math.floor(n) end
local function copy(t)
    local r={}
    for k,v in pairs(t or {}) do r[k]=v end
    return r
end
local function sorted(map)
    local r={}
    for id,qty in pairs(map or {}) do if qty>0 then r[#r+1]={itemID=id,quantity=qty} end end
    table.sort(r,function(a,b)return a.itemID<b.itemID end)
    return r
end
local function source()
    return JLP.data and JLP.data.foreverIntermediateOutputs
end
function Flow:GetOutputRecipe(professionKey,outputItemID)
    local data=source()
    if not data or data.build~=70245 then return nil,"OUTPUT_EVIDENCE_UNAVAILABLE" end
    local authority=JLP:GetModule("ForeverRecipeAuthority")
    local found
    for _,item in ipairs(data.rows or {}) do
        if item.professionKey==professionKey and item.outputItemID==outputItemID then
            if found then return nil,"AMBIGUOUS_OUTPUT" end
            found=item
        end
    end
    if not found then return nil,"NO_PUBLISHED_OUTPUT" end
    local row=authority and authority:GetReference(professionKey,found.recipeID)
    if not row or not integer(found.outputQuantity) or found.outputQuantity==0 or
       row.sourceURL~="https://www.wowhead.com/forever/spell="..found.recipeID then
        return nil,"OUTPUT_RECIPE_EVIDENCE_INVALID"
    end
    local result=copy(found)
    result.reagents=row.reagents
    result.sourceURL=row.sourceURL
    result.sourceBuild=row.sourceBuild
    result.outputAuthority="WOWHEAD_FOREVER_OUTPUT"
    return result
end
function Flow:ValidateOutputs()
    local errors,ids={},{}
    local data=source()
    for _,row in ipairs(data and data.rows or {}) do
        if ids[row.professionKey..":"..tostring(row.outputItemID)] then
            errors[#errors+1]="DUPLICATE_OUTPUT:"..tostring(row.outputItemID)
        end
        ids[row.professionKey..":"..tostring(row.outputItemID)]=true
        local found,why=self:GetOutputRecipe(row.professionKey,row.outputItemID)
        if not found then errors[#errors+1]=row.professionKey..":"..tostring(row.recipeID)..":"..tostring(why) end
    end
    return errors
end
function Flow:Build(professionKey,mode)
    local planner=JLP:GetModule("ForeverSkillBandPlanner")
    local plan,err=planner and planner:Build(professionKey,mode)
    if not plan then return nil,err or "SKILL_BAND_PLAN_MISSING" end
    local pending,external,gross,internallyUsed,produced={},{},{},{},{}
    local rows,unknownOutputs={},0
    for _,step in ipairs(plan.steps) do
        local detail={recipe=step.recipe,recipeID=step.recipeID,sourceStatus=step.state,
            estimatedCrafts=step.expectedCrafts,inputsVerified=step.materialTotalsVerified==true,
            nativeDispatchAllowed=false}
        if detail.inputsVerified then
            for _,reagent in ipairs(step.materials or {}) do
                local id,qty=reagent.itemID,reagent.quantity
                if not integer(qty) then detail.inputsVerified=false;break end
                gross[id]=(gross[id] or 0)+qty
                local use=math.min(pending[id] or 0,qty)
                pending[id]=(pending[id] or 0)-use
                internallyUsed[id]=(internallyUsed[id] or 0)+use
                external[id]=(external[id] or 0)+(qty-use)
            end
        end
        if detail.inputsVerified and not step.gateConflict then
            -- Match outputs by recipe identity, never by translated name.
            local data=source()
            for _,candidate in ipairs(data and data.rows or {}) do
                if candidate.professionKey==plan.professionKey and candidate.recipeID==step.recipeID then
                    local verified=self:GetOutputRecipe(plan.professionKey,candidate.outputItemID)
                    if verified and integer(step.expectedCrafts) then
                        local qty=verified.outputQuantity*step.expectedCrafts
                        pending[candidate.outputItemID]=(pending[candidate.outputItemID] or 0)+qty
                        produced[candidate.outputItemID]=(produced[candidate.outputItemID] or 0)+qty
                        detail.outputItemID=candidate.outputItemID
                        detail.outputQuantity=qty
                        detail.outputReference=verified.sourceURL
                    else unknownOutputs=unknownOutputs+1 end
                    break
                end
            end
        end
        rows[#rows+1]=detail
    end
    -- Previous-step output is not proof of items in the player's bags; it is
    -- only an estimated sequential research route supply credit.
    return {contract=self.contract,professionKey=plan.professionKey,mode=plan.mode,
        basis="HISTORICAL_CRAFT_COUNTS_WITH_FOREVER_INPUTS_OUTPUTS",estimated=true,
        nativeDispatchAllowed=false,executionEligible=false,production=false,
        planComplete=plan.knownMaterialsComplete,unverifiedSteps=plan.researchOnly+plan.invalidSteps,
        unknownOutputs=unknownOutputs,steps=rows,
        grossDirect=sorted(gross),internalProduced=sorted(produced),internalConsumed=sorted(internallyUsed),
        externalDirect=sorted(external),surplusFromEarlierCrafts=sorted(pending),
        externalDirectByItemID=external,grossDirectByItemID=gross,
        internalConsumedByItemID=internallyUsed}
end
-- Analyze one deficit. Incomplete prices cause UNKNOWN, never zero-cost.
-- Pricing is a read-only what-if; profession learning, recipe access, vendor
-- supply and actual AH availability are independent and not verified here.
function Flow:QuoteMaterial(key,id,quantity,prices,stack)
    if not integer(quantity) or quantity<=0 then return nil,"INVALID_QUANTITY" end
    prices=type(prices)=="table" and prices or {}
    stack=stack or {}
    if stack[id] then return {itemID=id,quantity=quantity,status="CYCLE",complete=false} end
    local quoted={itemID=id,quantity=quantity,complete=false,alternatives={}}
    local buy=tonumber(prices[id])
    if buy and buy>=0 then
        quoted.alternatives[#quoted.alternatives+1]={source="AUCTION",complete=true,estimatedCost=buy*quantity}
    else quoted.alternatives[#quoted.alternatives+1]={source="AUCTION",complete=false,reason="MISSING_MARKET_PRICE"} end
    local recipe=self:GetOutputRecipe(key,id)
    if recipe then
        local casts=math.ceil(quantity/recipe.outputQuantity)
        local inputCost=0
        local valid=true
        stack[id]=true
        local materialParts={}
        for _,mat in ipairs(recipe.reagents) do
            local part=self:QuoteMaterial(key,mat.itemID,casts*mat.quantity,prices,stack)
            if not part or not part.complete then valid=false end
            if part and part.complete then inputCost=inputCost+part.estimatedCost end
            materialParts[#materialParts+1]=part or {itemID=mat.itemID,complete=false}
        end
        stack[id]=nil
        quoted.alternatives[#quoted.alternatives+1]={source="CRAFT",recipeID=recipe.recipeID,
            estimatedCrafts=casts,produced=casts*recipe.outputQuantity,leftover=casts*recipe.outputQuantity-quantity,
            complete=valid,estimatedCost=valid and inputCost or nil,inputs=materialParts,
            accessVerified=false,sourceURL=recipe.sourceURL}
    end
    for _,option in ipairs(quoted.alternatives) do
        if option.complete and (not quoted.complete or option.estimatedCost<quoted.estimatedCost) then
            quoted.complete=true;quoted.estimatedCost=option.estimatedCost
            quoted.preferredSource=option.source
        end
    end
    quoted.priceComparisonComplete=#quoted.alternatives>=2 and quoted.alternatives[1].complete and quoted.alternatives[2].complete
    -- A price is only the cheapest *known* option unless buy and craft are
    -- both fully priced. Never imply best price when one side is UNKNOWN.
    if not quoted.priceComparisonComplete then
        quoted.onlyPricedSource=quoted.preferredSource
        quoted.preferredSource=nil
    end
    return quoted
end
function Flow:Compare(professionKey,prices)
    local result={contract="forever-advisory-strategy-comparison-v1",professionKey=tostring(professionKey or ""):upper(),
        strategies={},optimalLevelingRouteProven=false,nativeDispatchAllowed=false}
    for _,mode in ipairs({"normal","aggressive"}) do
        local plan,err=self:Build(professionKey,mode)
        if not plan then return nil,err end
        local quote={mode=mode,plan=plan,items={},knownSubtotal=0,
            pricedNeeds=0,unpricedNeeds=0,allExternalPricesKnown=true}
        for _,row in ipairs(plan.externalDirect) do
            local offer=self:QuoteMaterial(plan.professionKey,row.itemID,row.quantity,prices)
            quote.items[#quote.items+1]=offer
            if offer and offer.complete then
                quote.knownSubtotal=quote.knownSubtotal+offer.estimatedCost
                quote.pricedNeeds=quote.pricedNeeds+1
            else quote.allExternalPricesKnown=false;quote.unpricedNeeds=quote.unpricedNeeds+1 end
        end
        quote.materialQuoteComplete=quote.allExternalPricesKnown and plan.planComplete and plan.unknownOutputs==0
        quote.cost=quote.materialQuoteComplete and quote.knownSubtotal or nil
        quote.expectedSkillUps="UNKNOWN"
        result.strategies[mode]=quote
    end
    -- Never claim an optimal leveling route from research craft counts, even
    -- if both hypothetical material quotes can be calculated.
    return result
end
function Flow:GetSummary(key,prices)
    local compare,err=self:Compare(key,prices)
    if not compare then return "Forever material flow: "..tostring(err) end
    local lines={compare.professionKey.." · Forever output-adjusted, advisory only"}
    for _,mode in ipairs({"normal","aggressive"}) do
        local r=compare.strategies[mode]
        lines[#lines+1]=string.format("%s: %d external direct items; %d internally reused; %d research-only steps; priced %d / unpriced %d",
            mode,#r.plan.externalDirect,#r.plan.internalConsumed,r.plan.unverifiedSteps,r.pricedNeeds,r.unpricedNeeds)
    end
    lines[#lines+1]="No optimal leveling claim: research craft counts and source/access coverage are incomplete; no native execution"
    return table.concat(lines,"\n")
end
JLP:RegisterModule("ForeverMaterialFlow",Flow)
