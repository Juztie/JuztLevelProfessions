local _, JLP = ...
local CostOptimizer = {}

local function getItemCount(itemID)
    local inventory = JLP:GetModule("Inventory")
    if inventory then return inventory:GetItemCount(itemID) end
    if type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        local ok, value = pcall(C_Item.GetItemCount, itemID, true, false, true)
        if ok then return tonumber(value) or 0 end
    end
    if type(GetItemCount) == "function" then
        local ok, value = pcall(GetItemCount, itemID, true, false, true)
        if ok then return tonumber(value) or 0 end
    end
    return 0
end

local function money(copper)
    copper = math.max(0, math.floor((tonumber(copper) or 0) + 0.5))
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%dg %ds %dc", g, s, c)
end

local function materialName(itemID)
    local data = JLP.data and JLP.data.tailoring
    for _, material in pairs((data and data.materials) or {}) do
        if material.itemID == itemID then return material.name end
    end
    local de = JLP.data and JLP.data.disenchant
    return de and de.itemNames and de.itemNames[itemID] or ("Item " .. tostring(itemID))
end

local function routeStepByRecipe(recipe)
    local data = JLP.data and JLP.data.tailoring
    for _, step in ipairs((data and data.route) or {}) do
        if step.recipe == recipe then return step end
    end
    return nil
end

local function addRequirement(requirements, itemID, name, source, quantity)
    quantity = tonumber(quantity) or 0
    if quantity <= 0 or not itemID then return end
    local row = requirements[itemID]
    if not row then
        row = { itemID=itemID, name=name or materialName(itemID), source=source or "auction", required=0 }
        requirements[itemID] = row
    end
    row.required = row.required + quantity
    if row.source ~= source and source == "vendor" then row.source = "vendor" end
end

local function expandMaterial(requirements, crafted, material, quantity)
    quantity = tonumber(quantity) or 0
    if quantity <= 0 then return end
    if material.craftedFrom then
        addRequirement(crafted,material.itemID,material.name,"crafted",quantity)
        crafted[material.itemID].craftedFrom=material.craftedFrom
    else
        addRequirement(requirements, material.itemID, material.name, material.source or "auction", quantity)
    end
end

function CostOptimizer:GetCandidateMap()
    return (JLP.data and JLP.data.tailoringDisenchant and JLP.data.tailoringDisenchant.candidates) or {}
end

function CostOptimizer:GetVendorUnitPrice(itemID)
    local data = JLP.data and JLP.data.vendorPrices
    local row = data and data.items and data.items[tonumber(itemID)]
    return row and tonumber(row.price) or nil
end

function CostOptimizer:GetCraftCost(candidate, craftCount, context)
    craftCount = math.max(1, math.ceil(tonumber(craftCount) or 1))
    local step = candidate and routeStepByRecipe(candidate.recipe)
    if not step then
        return { complete=false, cost=0, craftCount=craftCount, reason="recipe-not-in-tailoring-route", unpriced={} }
    end

    local requirements,crafted,materials = {},{},{}
    for _, material in ipairs(step.materials or {}) do
        local required=(tonumber(material.quantity) or 0)*craftCount
        expandMaterial(requirements,crafted,material,required)
        materials[#materials+1]={material=material,required=required}
    end
    local function available(itemID)
        local inventory=JLP:GetModule("Inventory")
        local storage=inventory and inventory:GetOwned(itemID) or {total=getItemCount(itemID)}
        return math.max(0,(tonumber(storage.total) or 0)-
            (context and context.reservedStock and tonumber(context.reservedStock[itemID]) or 0)),storage
    end
    local intermediates={}
    for itemID,row in pairs(crafted) do
        local owned=available(itemID)
        local missing=math.max(0,row.required-owned)
        intermediates[#intermediates+1]={itemID=itemID,name=row.name,required=row.required,owned=owned,missing=missing,craftedFrom=row.craftedFrom}
        if missing>0 then
            addRequirement(requirements,row.craftedFrom.itemID,materialName(row.craftedFrom.itemID),
                row.craftedFrom.source or "auction",missing*(tonumber(row.craftedFrom.quantity) or 0))
        end
    end

    local resolver = JLP:GetModule("PriceResolver")
    local total = 0
    local complete = true
    local breakdown = {}
    local unpriced = {}

    for _, row in pairs(requirements) do
        local owned,storage=available(row.itemID)
        local missing = math.max(0, (tonumber(row.required) or 0) - owned)
        local cost = 0
        local priced = true
        local quote = nil

        if missing > 0 then
            if row.source == "vendor" then
                local unit = self:GetVendorUnitPrice(row.itemID)
                if unit then cost = unit * missing else priced = false end
            else
                quote = resolver and resolver:GetFulfillmentCost(row.itemID, missing) or nil
                if quote and quote.complete==true and quote.trustedForCostEstimate==true and
                    type(quote.cost)=="number" and quote.cost>=0 and quote.cost<math.huge then cost=quote.cost else priced=false end
            end
        end

        if not priced then
            complete = false
            unpriced[#unpriced+1] = { itemID=row.itemID, name=row.name, missing=missing, source=row.source, quote=quote }
        else
            total = total + cost
        end
        breakdown[#breakdown+1] = {
            itemID=row.itemID,
            name=row.name,
            source=row.source,
            required=row.required,
            owned=owned,
            missing=missing,
            storage=storage,
            cost=cost,
            complete=priced,
            priceKnown=priced,
            quote=quote,
        }
    end

    table.sort(breakdown, function(a,b) return tostring(a.name) < tostring(b.name) end)
    return {
        complete=complete,
        cost=total,
        craftCount=craftCount,
        candidate=candidate,
        recipe=step.recipe,
        breakdown=breakdown,
        materials=materials,
        intermediates=intermediates,
        unpriced=unpriced,
    }
end

function CostOptimizer:GetExpectedYield(candidate, materialID)
    local disenchant = JLP:GetModule("Disenchant")
    if not disenchant or not candidate then return 0 end
    for _, output in ipairs(disenchant:GetExpectedOutputs(candidate.itemLevel, candidate.kind or "armor")) do
        if output.itemID == materialID then return tonumber(output.expected) or 0 end
    end
    return 0
end

function CostOptimizer:GetTailoringDisenchantFeasibility(candidate)
    local result={feasible=false,advisory=true,reason="LIVE_PROFESSION_CONTEXT_UNAVAILABLE",nativeDispatchAllowed=false}
    local api=JLP:GetModule("ProfessionAPI")
    if not api or type(api.GetDetected)~="function" then return result end
    local ok,detected=pcall(api.GetDetected,api)
    if not ok or type(detected)~="table" then return result end
    if not detected.TAILORING then result.reason="TAILORING_NOT_LEARNED";return result end
    if not detected.ENCHANTING then result.reason="ENCHANTING_NOT_LEARNED";return result end
    local enchantingSkill=tonumber(detected.ENCHANTING.skill)
    if not enchantingSkill or enchantingSkill~=enchantingSkill or enchantingSkill<1 or enchantingSkill==math.huge then
        result.reason="ENCHANTING_SKILL_UNVERIFIED";return result
    end
    local step=candidate and routeStepByRecipe(candidate.recipe)
    if not step then result.reason="RECIPE_NOT_IN_TAILORING_ROUTE";return result end
    local requiredSkill=tonumber(step.requiredSkill or step.skillMin)
    local skill=tonumber(detected.TAILORING.skill)
    if not requiredSkill or requiredSkill~=requiredSkill or requiredSkill<0 or requiredSkill==math.huge or
        not skill or skill~=skill or skill==math.huge or skill<requiredSkill then result.reason="TAILORING_SKILL_UNVERIFIED_OR_TOO_LOW";return result end
    local data=JLP.data and JLP.data.tailoring
    local reference=data and data.recipeIdentities and data.recipeIdentities[candidate.recipe]
    local recipeID=tonumber(candidate.recipeID or step.recipeID or step.spellID or reference and reference.recipeID)
    if not recipeID or type(api.GetRecipeContext)~="function" then result.reason="RECIPE_LEARNED_STATE_UNVERIFIED";return result end
    local recipeOK,recipe=pcall(api.GetRecipeContext,api,recipeID,"TAILORING")
    if not recipeOK or type(recipe)~="table" or recipe.verified~=true or recipe.learned~=true or
        recipe.professionKey~="TAILORING" or tonumber(recipe.recipeID)~=recipeID then result.reason="RECIPE_NOT_CONFIRMED_LEARNED";return result end
    -- The historical yield table has no client-qualified disenchant access
    -- rules. Only a live item feasibility observation can qualify that step.
    local disenchant=JLP:GetModule("Disenchant")
    if not disenchant or type(disenchant.GetFeasibility)~="function" then result.reason="DISENCHANT_FEASIBILITY_UNVERIFIED";return result end
    local deOK,de=pcall(disenchant.GetFeasibility,disenchant,candidate)
    if not deOK or type(de)~="table" or de.verified~=true or de.feasible~=true then
        result.reason=deOK and type(de)=="table" and de.reason or "DISENCHANT_FEASIBILITY_UNVERIFIED";return result
    end
    result.feasible=true;result.advisory=false;result.reason="LIVE_REQUIREMENTS_VERIFIED"
    return result
end

function CostOptimizer:GetBestTailoringDisenchant(materialID, quantity, context)
    quantity = math.max(1, tonumber(quantity) or 1)
    local best = nil
    local evaluated = {}
    for _, candidate in ipairs(self:GetCandidateMap()) do
        local expectedPerCraft = self:GetExpectedYield(candidate, materialID)
        if expectedPerCraft > 0 then
            local crafts = math.max(1, math.ceil(quantity / expectedPerCraft))
            local feasibility=self:GetTailoringDisenchantFeasibility(candidate)
            local quote = self:GetCraftCost(candidate, crafts, context)
            if feasibility.feasible then
                local api=JLP:GetModule("ProfessionAPI")
                local identities=JLP.data and JLP.data.tailoring and JLP.data.tailoring.recipeIdentities or {}
                for _,intermediate in ipairs(quote.intermediates or {}) do
                    if intermediate.missing>0 then
                        local reference=identities[intermediate.name]
                        local recipeID=reference and tonumber(reference.recipeID)
                        local ok,learned=false,nil
                        if recipeID and api and type(api.GetRecipeContext)=="function" then ok,learned=pcall(api.GetRecipeContext,api,recipeID,"TAILORING") end
                        if not ok or type(learned)~="table" or learned.verified~=true or learned.learned~=true or learned.professionKey~="TAILORING" or tonumber(learned.recipeID)~=recipeID then
                            feasibility={feasible=false,advisory=true,reason="INTERMEDIATE_RECIPE_LEARNED_STATE_UNVERIFIED",nativeDispatchAllowed=false};break
                        end
                    end
                end
            end
            local row = {
                candidate=candidate,
                expectedPerCraft=expectedPerCraft,
                expectedTotal=crafts * expectedPerCraft,
                crafts=crafts,
                quote=quote,
                complete=quote.complete and feasibility.feasible,
                feasibility=feasibility,
                advisory=not feasibility.feasible,
                cost=quote.cost or 0,
            }
            evaluated[#evaluated+1] = row
            local balance=nil
            if type(GetMoney)=="function" then
                local moneyOK,value=pcall(GetMoney)
                if moneyOK and type(value)=="number" and value==value and value>=0 and value<math.huge then balance=value end
            end
            row.affordability=balance==nil and "UNKNOWN" or row.complete and
                (row.cost<=balance and "AFFORDABLE" or "INSUFFICIENT_FUNDS") or "UNKNOWN"
            if row.complete and row.affordability~="INSUFFICIENT_FUNDS" and (not best or row.cost < best.cost) then best = row end
        end
    end
    table.sort(evaluated, function(a,b)
        if a.complete ~= b.complete then return a.complete end
        return (a.cost or math.huge) < (b.cost or math.huge)
    end)
    return best, evaluated
end

-- Strategy is not a native permission. Source decisions may be advisory but
-- Self-found AH exceptions require an independent user decision; never infer one
-- from an AH snapshot, an available quote or a lack of alternatives.
function CostOptimizer:ClassifyMaterialSource(source, strategy)
    strategy = strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"
    local needsConsent = strategy == "self_found" and
        (source == "auction" or source == "disenchant-or-auction")
    return {
        allowed = not needsConsent,
        exceptionPending = needsConsent,
        source = source,
        strategy = strategy,
        reason = needsConsent and "SELF_FOUND_AH_EXCEPTION_NOT_ACCEPTED" or nil,
        nativeDispatchAllowed = false,
    }
end

-- Conservative route comparison. Only observed bag stock and qualified current
-- acquisition prices enter a ranking. Cached bank stock remains a separate
-- withdrawal action; vendor references without price receipts are advisory.
function CostOptimizer:QuoteRouteCandidate(step, fromSkill, toSkill, sourceBuild)
    local result={complete=false,knownCost=nil,reason="COST_EVIDENCE_UNAVAILABLE",
        costOptimal=false,optimizationStatus="UNKNOWN",readOnly=true,nativeDispatchAllowed=false}
    if type(step)~="table" then return result end
    local lo,hi=tonumber(step.skillMin),tonumber(step.skillTarget)
    local crafts=tonumber(step.expectedCrafts)
    if not lo or not hi or hi<=lo or not crafts or crafts<=0 then return result end
    local first=math.max(lo,tonumber(fromSkill) or lo)
    local last=math.min(hi,tonumber(toSkill) or hi)
    if last<=first then result.complete=true;result.knownCost=0;result.costOptimal=true;result.optimizationStatus="EXACT";result.reason="NO_REMAINING_CRAFTS";return result end
    crafts=math.max(1,math.ceil(crafts*(last-first)/(hi-lo)))
    if type(step.materials)~="table" or #step.materials==0 then
        result.reason="MATERIAL_REQUIREMENTS_UNAVAILABLE";return result
    end
    local totals={}
    for _,material in ipairs(step.materials or {}) do
        local id=tonumber(material.itemID)
        local qty=tonumber(material.quantity)
        if not id or id<1 or id~=math.floor(id) or not qty or qty<=0 or qty~=math.floor(qty) or
            type(material.craftedFrom)=="table" or type(material.craftedRecipe)=="table" then
            result.reason="MATERIAL_GRAPH_NOT_COMPARABLE";return result
        end
        local row=totals[id]
        if not row then row={id=id,required=0,source=material.source};totals[id]=row end
        if row.source~=material.source then result.reason="SOURCE_CONFLICT";return result end
        row.required=row.required+qty*crafts
    end
    local inventory=JLP:GetModule("Inventory")
    local resolver=JLP:GetModule("PriceResolver")
    local vendorPrices=JLP.data and JLP.data.vendorPrices and JLP.data.vendorPrices.items
    local total=0
    local costOptimal,optimizationStatus=true,"EXACT"
    for id,row in pairs(totals) do
        local storage=inventory and inventory.GetOwned and inventory:GetOwned(id) or nil
        -- Q119: a cached or missing numeric bag count is NOT a live bag
        -- observation. Do not price a route alternative or treat stock as
        -- available until current-character bag evidence is explicit.
        local bags=storage and tonumber(storage.bags) or nil
        if not (storage and storage.bagKnown==true and type(bags)=="number" and
            bags==bags and bags>=0 and bags==math.floor(bags) and bags<math.huge) then
            result.reason="BAG_STOCK_UNVERIFIED";return result
        end
        local missing=math.max(0,row.required-math.max(0,bags))
        if missing>0 then
            if row.source=="vendor" then
                local vendor=vendorPrices and vendorPrices[id]
                if not (vendor and vendor.priceVerified==true and
                    tonumber(vendor.sourceBuild)==tonumber(sourceBuild) and
                    type(vendor.price)=="number" and vendor.price>=0 and vendor.price<math.huge) then
                    result.reason="VENDOR_PRICE_UNQUALIFIED";return result
                end
                total=total+vendor.price*missing
            elseif row.source=="auction" or row.source=="disenchant-or-auction" then
                local quote=resolver and resolver.GetFulfillmentCost and resolver:GetFulfillmentCost(id,missing)
                if not (quote and quote.complete==true and quote.trustedForCostEstimate==true and
                    type(quote.snapshotKey)=="string" and quote.snapshotKey~="" and
                    tonumber(quote.requested)==missing and tonumber(quote.fulfilled)==missing and
                    type(quote.cost)=="number" and quote.cost>=0 and quote.cost<math.huge) then
                    result.reason="AH_PRICE_UNQUALIFIED";return result
                end
                total=total+quote.cost
                if quote.costOptimal~=true then
                    costOptimal=false
                    optimizationStatus=quote.optimizationStatus or "OPTIMALITY_UNVERIFIED"
                end
            else
                result.reason="SOURCE_COST_UNQUALIFIED";return result
            end
        end
        if total==math.huge or total~=total then result.reason="COST_OVERFLOW";return result end
    end
    result.complete=true;result.knownCost=total;result.reason="QUALIFIED_COST_ESTIMATE"
    result.costOptimal=costOptimal;result.optimizationStatus=optimizationStatus
    return result
end

function CostOptimizer:GetComparison(materialID, quantity, strategy, context)
    quantity = math.max(1, math.ceil(tonumber(quantity) or 1))
    strategy = strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"
    local scanner = JLP:GetModule("AuctionScanner")
    local snapshot = scanner and scanner:GetSnapshot()
    local resolver = JLP:GetModule("PriceResolver")
    local direct = resolver and resolver:GetFulfillmentCost(materialID, quantity) or {complete=false, requested=quantity, cost=0}
    local bestCraft, evaluated = self:GetBestTailoringDisenchant(materialID, quantity, context)
    local balance=nil
    if type(GetMoney)=="function" then
        local ok,value=pcall(GetMoney)
        if ok and type(value)=="number" and value==value and value>=0 and value<math.huge then balance=value end
    end
    local directKnown=direct.complete==true and direct.trustedForCostEstimate==true and
        type(direct.cost)=="number" and direct.cost>=0 and direct.cost<math.huge
    local directAffordable=directKnown and (balance==nil or direct.cost<=balance)

    local recommended = "insufficient-data"
    if strategy == "fastest" then
        if directAffordable then recommended = "direct-ah"
        elseif bestCraft then recommended = "tailoring-disenchant" end
    elseif strategy == "self_found" then
        -- An otherwise cheap Tailoring+DE route is not Self-found when its
        -- material quote silently purchases missing inputs on the AH.
        local selfFoundCraft=nil
        for _,craft in ipairs(evaluated or {}) do
            local acceptable=craft.complete==true and craft.affordability~="INSUFFICIENT_FUNDS" and type(craft.quote)=="table"
            for _,reagent in ipairs(craft.quote and craft.quote.breakdown or {}) do
                if (tonumber(reagent.missing) or 0)>0 and reagent.source~="vendor" then
                    acceptable=false
                    break
                end
            end
            if acceptable and (not selfFoundCraft or craft.cost<selfFoundCraft.cost) then
                selfFoundCraft=craft
            end
        end
        bestCraft=selfFoundCraft
        if bestCraft then recommended = "tailoring-disenchant"
        elseif directAffordable then recommended = "self-found-exception-pending" end
    else
        if directAffordable and bestCraft then
            recommended = (bestCraft.cost < (direct.cost or 0)) and "tailoring-disenchant" or "direct-ah"
        elseif bestCraft then recommended = "tailoring-disenchant"
        elseif directAffordable then recommended = "direct-ah" end
    end

    return {
        itemID=materialID,
        name=materialName(materialID),
        quantity=quantity,
        strategy=strategy,
        snapshotAvailable=snapshot ~= nil,
        direct=direct,
        tailoring=bestCraft,
        evaluated=evaluated,
        recommended=recommended,
        exceptionPending=recommended == "self-found-exception-pending",
        approvalGranted=false,
        availableMoney=balance,
        directAffordability=(not directKnown or balance==nil) and "UNKNOWN" or
            (direct.cost<=balance and "AFFORDABLE" or "INSUFFICIENT_FUNDS"),
        evidence="ah-snapshot-plus-expected-disenchant-yield",
    }
end

function CostOptimizer:Money(copper)
    return money(copper)
end

JLP:RegisterModule("CostOptimizer", CostOptimizer)
