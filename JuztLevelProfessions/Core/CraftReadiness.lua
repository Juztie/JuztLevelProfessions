local _, JLP = ...
local CraftReadiness = {}

local function registry() return JLP:GetModule("ProfessionRegistry") end

local function isReadOnlyResearchPlan(plan)
    local policy=JLP:GetModule("PlanAuthorityPolicy")
    if not policy or not policy.IsReadOnlyConsumable then return false end
    return policy:IsReadOnlyConsumable(plan)
end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end
local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local INF = 1000000000
local MAX_COUNT = 9007199254740991

local function clampCrafts(value, remaining)
    value = math.max(0, math.floor(tonumber(value) or 0))
    remaining = math.max(0, math.floor(tonumber(remaining) or 0))
    if remaining > 0 then return math.min(value, remaining) end
    return value
end

local function owned(itemID)
    local inventory = JLP:GetModule("Inventory")
    if inventory and inventory.GetOwned then
        local value=inventory:GetOwned(itemID)
        if type(value)=="table" then return value end
    end
    -- An unavailable inventory module is UNKNOWN, not a known empty bag.
    return { itemID=tonumber(itemID), bags=0, bank=0, total=0,
        bagKnown=false, bankKnown=false, bagEvidence="INVENTORY_UNAVAILABLE" }
end

local function integralCount(value, allowZero, fallback)
    if value == nil then return fallback end
    value = tonumber(value)
    if not value or value ~= value or value > MAX_COUNT or value < (allowZero and 0 or 1)
        or value ~= math.floor(value) then return nil end
    return value
end

local function denseArray(value)
    if type(value)~="table" then return false end
    local length=#value
    for key in pairs(value) do
        if type(key)~="number" or key~=math.floor(key) or key<1 or key>length then return false end
    end
    for index=1,length do if value[index]==nil then return false end end
    return true
end

local function itemKey(value)
    value = tonumber(value)
    return value and value > 0 and value <= MAX_COUNT and value == math.floor(value) and value or nil
end

local function materialQuantity(material)
    return integralCount(material and (material.quantity or material.perCraft), false, 1)
end

local function producerFor(material)
    if type(material.craftedRecipe) == "table" then
        return {materials=material.craftedRecipe.materials,
            output=integralCount(material.craftedRecipe.outputPerCraft, false, 1),node=material.craftedRecipe}
    end
    if type(material.craftedFrom) == "table" then
        return {materials={material.craftedFrom},output=1,node={itemID=material.itemID,name=material.name,recipe=material.name}}
    end
end

local function producerSignature(producer)
    if not producer.output or not denseArray(producer.materials) or #producer.materials == 0 then return nil end
    local quantities, parts = {}, {}
    for _, child in ipairs(producer.materials) do
        if type(child)~="table" then return nil end
        local id,quantity = itemKey(child.itemID),materialQuantity(child)
        if not id or not quantity then return nil end
        quantities[id] = (quantities[id] or 0) + quantity
        if quantities[id]>MAX_COUNT then return nil end
    end
    for id, quantity in pairs(quantities) do parts[#parts+1] = tostring(id)..":"..tostring(quantity) end
    table.sort(parts)
    return tostring(producer.output).."/"..table.concat(parts, ";")
end

-- One inventory pool is shared by the complete requirement graph. Reserve all
-- direct demands before expanding shortages, so a raw reagent cannot also be
-- spent on a sibling intermediate. Produced batch surplus remains available to
-- other demands; recipes with conflicting producers stay unresolved.
-- options: useStorage=true includes bank stock; prepare=true permits dependencies.
-- rows preserve input order and report required, allocated (owned stock reserved
-- for that row), and missing (before preparation). This is also used by Planner.
function CraftReadiness:AllocateMaterials(materials, craftCount, options)
    options = options or {}
    craftCount = integralCount(craftCount, true, 0)
    local result = {feasible=true,rows={},reason=nil,prepared=options.prepare == true,
        requirements={},requirementOrder={},production={},
        inventoryKnown=true,unknownBagItems={},unknownBankItems={}}
    if not craftCount or not denseArray(materials or {}) then
        result.feasible=false;result.reason=not craftCount and "invalid-craft-count" or "invalid-material-array";return result
    end
    local stocks, observed, producers, conflicts, collected, producing, materialByID = {}, {}, {}, {}, {}, {}, {}
    local function stock(id)
        if stocks[id] == nil then
            local storage = owned(id)
            -- A numeric zero returned alongside bagKnown=false is a lower bound,
            -- never evidence of an empty bag. Bank snapshots may be advisory.
            if storage.bagKnown ~= true then
                result.inventoryKnown=false
                result.unknownBagItems[id]=true
            end
            -- A SavedVariables bank snapshot is a source reference when the
            -- bank is closed. Do not call its cached zero a live shortage.
            local bankLive = storage.bankKnown == true and
                (storage.bankEvidence ~= "SAVED_ORDINARY_BANK_SNAPSHOT" or storage.bankOpenedAt ~= nil)
            if options.useStorage and not bankLive then
                result.inventoryKnown=false
                result.unknownBankItems[id]=true
            end
            local count = integralCount(options.useStorage and storage.total or storage.bags,true,0)
            if not count then result.feasible=false;result.reason="invalid-inventory-count" end
            stocks[id] = count or 0
            observed[id] = stocks[id]
        end
        return stocks[id]
    end
    local function reserve(id, quantity)
        local available=stock(id)
        local allocated=math.min(quantity,available)
        local physical=math.min(allocated,observed[id] or 0)
        stocks[id],observed[id]=available-allocated,(observed[id] or 0)-physical
        return allocated,physical
    end
    local function requirement(id, quantity, physical, prepared)
        local row=result.requirements[id]
        if not row then
            row={itemID=id,required=0,allocated=0,preparedAllocated=0,missing=0,material=materialByID[id]}
            result.requirements[id]=row;result.requirementOrder[#result.requirementOrder+1]=id
        end
        row.required=row.required+quantity;row.allocated=row.allocated+physical;row.preparedAllocated=row.preparedAllocated+prepared
        return row
    end
    local function collect(material, depth, active)
        if type(material) ~= "table" or depth > 12 then return end
        local id = itemKey(material.itemID)
        if id then materialByID[id]=materialByID[id] or material end
        if not id or active[id] then return end
        local producer = producerFor(material)
        if not producer then return end
        local signature = producerSignature(producer)
        if not signature then conflicts[id] = "invalid-producer"; return end
        if producers[id] and producers[id].signature ~= signature then conflicts[id] = "conflicting-producers"; return end
        producer.signature = signature
        producers[id] = producers[id] or producer
        if collected[material] and collected[material] <= depth then return end
        collected[material] = depth
        active[id] = true
        for _, child in ipairs(producer.materials) do collect(child, depth+1, active) end
        active[id] = nil
    end
    if options.prepare then for _, material in ipairs(materials or {}) do collect(material,0,{}) end end

    local demands, order = {}, {}
    local function demand(target, ids, id, quantity, depth, ancestors)
        if not integralCount(quantity,true) then result.feasible=false;result.reason="invalid-expanded-quantity";return end
        if quantity <= 0 then return end
        local row = target[id]
        if not row then row={quantity=0,depth=depth,ancestors={}};target[id]=row;ids[#ids+1]=id end
        row.quantity = row.quantity + quantity
        if row.quantity>MAX_COUNT then result.feasible=false;result.reason="invalid-expanded-quantity";return end
        row.depth = math.max(row.depth, depth)
        for ancestor in pairs(ancestors or {}) do row.ancestors[ancestor] = true end
    end
    for _, material in ipairs(materials or {}) do
        if type(material)~="table" then result.feasible=false;result.reason="invalid-material";return result end
        local id = itemKey(material.itemID)
        local perCraft=materialQuantity(material)
        if not id or not perCraft then result.feasible=false;result.reason="invalid-material-identity-or-quantity";return result end
        local quantity = perCraft*craftCount
        if quantity>MAX_COUNT then result.feasible=false;result.reason="invalid-expanded-quantity";return result end
        if id then materialByID[id]=materialByID[id] or material end
        local allocated = id and reserve(id,quantity) or 0
        result.rows[#result.rows+1] = {itemID=id,material=material,perCraft=materialQuantity(material),
            required=quantity,allocated=allocated,missing=quantity-allocated}
        if not id and quantity > 0 then result.feasible=false;result.reason="invalid-material-identity";return result end
        if id then requirement(id,quantity,allocated,0);demand(demands,order,id,quantity-allocated,0,{}) end
    end
    while #order > 0 do
        local nextDemands, nextOrder = {}, {}
        -- Reserve every existing stock unit at this depth before scheduling any
        -- producer. Table iteration order cannot change which stock is spent.
        for _, id in ipairs(order) do
            local row = demands[id]
            if row.ancestors[id] then result.feasible=false;result.reason="dependency-cycle";return result end
            local allocated,physical = reserve(id,row.quantity)
            if row.depth > 0 then requirement(id,row.quantity,physical,allocated-physical) end
            row.quantity = row.quantity-allocated
        end
        for _, id in ipairs(order) do
            local row = demands[id]
            if row.quantity > 0 then
                local producer = options.prepare and producers[id] or nil
                if not producer or conflicts[id] or row.depth >= 12 then
                    result.feasible=false
                    result.reason=conflicts[id] or (row.depth >= 12 and "dependency-depth-limit" or "insufficient-materials")
                    local needed=requirement(id,0,0,0)
                    needed.missing=needed.missing+row.quantity
                else
                    local crafts = math.ceil(row.quantity/producer.output)
                    producing[id] = (producing[id] or 0)+crafts
                    stocks[id] = stock(id)+crafts*producer.output-row.quantity
                    local ancestors = {}
                    for ancestor in pairs(row.ancestors) do ancestors[ancestor] = true end
                    ancestors[id] = true
                    for _, child in ipairs(producer.materials) do
                        demand(nextDemands,nextOrder,itemKey(child.itemID),crafts*materialQuantity(child),row.depth+1,ancestors)
                    end
                end
            end
        end
        demands,order=nextDemands,nextOrder
    end
    -- Surplus from planned output must not bootstrap two cyclic producers with
    -- no real starting stock. Check the producers actually used, including
    -- cycles whose final demand was covered by another planned surplus.
    local visiting, visited = {}, {}
    local function acyclic(id)
        if visiting[id] then return false end
        if visited[id] or not producing[id] then return true end
        visiting[id] = true
        for _, child in ipairs(producers[id].materials) do if not acyclic(itemKey(child.itemID)) then return false end end
        visiting[id],visited[id]=nil,true
        local producer=producers[id]
        result.production[#result.production+1]={itemID=id,crafts=producing[id],outputPerCraft=producer.output,
            outputUnits=producing[id]*producer.output,node=producer.node,materials=producer.materials}
        return true
    end
    for id in pairs(producing) do
        if not acyclic(id) then result.feasible=false;result.reason="dependency-cycle";return result end
    end
    return result
end

-- The feasibility predicate is monotonic, including whole output batches. Binary
-- search finds the actual shared-stock maximum, capped by the caller's limit.
function CraftReadiness:GetMaterialCapacity(materials, limit, options)
    limit = integralCount(limit,true,0) or 0
    local low, high = 0, limit
    while low < high do
        local middle = low+math.floor((high-low+1)/2)
        if self:AllocateMaterials(materials,middle,options).feasible then low=middle else high=middle-1 end
    end
    return low
end

local function materialCapacity(material)
    local perCraft = materialQuantity(material) or 0
    local storage = owned(material and material.itemID)
    return {itemID=material and material.itemID,name=material and material.name or "Material",perCraft=perCraft,
        bags=storage.bags or 0,bank=storage.bank or 0,total=storage.total or 0,
        bagKnown=storage.bagKnown == true,bankKnown=storage.bankKnown == true,
        bagEvidence=storage.bagEvidence,bankEvidence=storage.bankEvidence,
        craftedRecipe=material and material.craftedRecipe,craftedFrom=material and material.craftedFrom}
end

local function recipeKnowledge(key, recipe)
    local progress = JLP:GetModule("RouteProgress")
    if not progress or not recipe then return "unknown" end
    if progress.GetRecipeKnowledge then
        local state = progress:GetRecipeKnowledge(recipe, key, false)
        return state or "unknown"
    end
    if progress.Initialize then progress:Initialize() end
    if progress.IsRecipeKnown and progress:IsRecipeKnown(recipe) then return "known" end
    return "unknown"
end

local function toolState(tool, professionKey)
    if not tool or tostring(professionKey or "") ~= "ENCHANTING" then
        return { required=false, status="not-required", bags=0, bank=0, total=0 }
    end
    if tostring(professionKey or "") == "ENCHANTING" then
        local resolver = JLP:GetModule("EnchantingToolResolver")
        if resolver and resolver.Resolve then
            return resolver:Resolve(tool)
        end
    end
    local storage = owned(tool.itemID)
    local bankLive=storage.bankKnown==true and
        (storage.bankEvidence ~= "SAVED_ORDINARY_BANK_SNAPSHOT" or storage.bankOpenedAt ~= nil)
    local status
    if storage.bagKnown ~= true then status = "unknown"
    elseif (storage.bags or 0) > 0 then status = "bags"
    elseif not bankLive then status = "unknown"
    elseif (storage.total or 0) > 0 then status = "bank"
    else status = "missing" end
    return {
        required = true,
        itemID = tool.itemID,
        name = tool.name or "Required tool",
        bags = storage.bags or 0,
        bank = storage.bank or 0,
        total = storage.total or 0,
        bagKnown = storage.bagKnown == true,
        bankKnown = storage.bankKnown == true,
        bankLive = bankLive,
        status = status,
    }
end

function CraftReadiness:Get(key, plan)
    local reg=registry()
    local planner=JLP:GetModule("Planner")
    plan=plan or (planner and planner:GetProfessionPlan(key))
    if plan and (plan.actionKind=="reference" or plan.readOnlyRouteFallback==true) then
        -- Materials may still be inspected via Planner:GetMaterialStates, but
        -- bag counts never qualify a historical guide as a native craft CTA.
        return {key=key,status="reference",blocker="native-unqualified",
            readOnly=true,nativeDispatchAllowed=false,
            action=plan.action or "Inspect the source reference and verify current recipe access."}
    end
    local availability=reg and reg:ResolveWorkflowAvailability(key,"executionFlow") or nil
    if availability and availability.state~="available" and not isReadOnlyResearchPlan(plan) then
        return {key=availability.key or key,status=availability.state,blocker="production",terminalReason=availability.terminalReason,action=availability.state=="not-production-enabled" and "Profession is staged but not production-enabled." or "Profession is unsupported."}
    end
    local planner = JLP:GetModule("Planner")
    plan = plan or (planner and planner:GetProfessionPlan(key))
    if not plan then
        return { key=key, status="blocked", blocker="planner", action="Planner unavailable." }
    end

    if plan.actionKind == "learn" then
        return { key=key, status="blocked", blocker="profession", action="Learn the profession before continuing." }
    end
    if plan.actionKind == "train" then
        return { key=key, status="blocked", blocker="trainer", action=plan.action or "Train the next profession rank." }
    end
    if plan.actionKind == "complete" then
        return { key=key, status="complete", blocker=nil, action="Profession route complete." }
    end
    if plan.actionKind ~= "craft" or not plan.step then
        return { key=key, status="blocked", blocker="route", action=plan.action or "No craft step is available." }
    end

    local step = plan.step
    local remaining = math.max(0, tonumber(step.remainingCrafts) or 0)
    local recipeState = recipeKnowledge(key, step.recipe)
    local tool = toolState(step.requiredTool, key)
    local rows = {}
    -- All four limits use a complete shared allocation, including duplicate
    -- direct reagent rows and stock shared by different dependency branches.
    local immediateBags = self:GetMaterialCapacity(step.materials,remaining,{})
    local immediateStorage = self:GetMaterialCapacity(step.materials,remaining,{useStorage=true})
    local preparedBags = self:GetMaterialCapacity(step.materials,remaining,{prepare=true})
    local preparedStorage = self:GetMaterialCapacity(step.materials,remaining,{useStorage=true,prepare=true})
    -- Capability (a lower bound) and observation completeness are independent.
    -- A failed API or unreadable bag is not a verified material shortage.
    local bagsEvidence=self:AllocateMaterials(step.materials,1,{})
    local storageEvidence=self:AllocateMaterials(step.materials,1,{useStorage=true,prepare=true})
    local bagsKnown=bagsEvidence.inventoryKnown==true and bagsEvidence.reason~="invalid-inventory-count"
    local storageKnown=storageEvidence.inventoryKnown==true and storageEvidence.reason~="invalid-inventory-count"
    if tool.required and tool.status~="confirmed" then
        if tool.bags <= 0 then
            immediateBags = 0
            preparedBags = 0
        end
        if tool.total <= 0 then
            immediateStorage = 0
            preparedStorage = 0
        end
    end

    immediateBags = clampCrafts(immediateBags == INF and remaining or immediateBags, remaining)
    immediateStorage = clampCrafts(immediateStorage == INF and remaining or immediateStorage, remaining)
    preparedBags = clampCrafts(preparedBags == INF and remaining or preparedBags, remaining)
    preparedStorage = clampCrafts(preparedStorage == INF and remaining or preparedStorage, remaining)

    local availableBatch = immediateBags > 0 and immediateBags or (preparedBags > 0 and preparedBags or (preparedStorage > 0 and preparedStorage or 1))
    local batchCrafts = math.max(1, math.min(math.max(1, math.floor(remaining)),availableBatch))
    local bagRows = self:AllocateMaterials(step.materials,batchCrafts,{}).rows
    local storageRows = self:AllocateMaterials(step.materials,batchCrafts,{useStorage=true}).rows
    for index, material in ipairs(step.materials or {}) do
        local row = materialCapacity(material)
        local bags, storage = bagRows[index], storageRows[index]
        row.observedBags,row.observedBank,row.observedTotal=row.bags,row.bank,row.total
        row.required = bags and bags.required or 0
        row.allocatedBags = bags and bags.allocated or 0
        row.allocatedStorage = storage and storage.allocated or 0
        row.bags,row.total=row.allocatedBags,row.allocatedStorage
        row.bank=math.max(0,row.allocatedStorage-row.allocatedBags)
        row.missingBags = bags and bags.missing or row.required
        row.missingStorage = storage and storage.missing or row.required
        row.allocationCrafts=batchCrafts
        row.immediateBags,row.immediateStorage=immediateBags,immediateStorage
        row.preparedBags,row.preparedStorage=preparedBags,preparedStorage
        if material.craftedFrom then
            local raw=owned(material.craftedFrom.itemID)
            row.craftedFrom={itemID=material.craftedFrom.itemID,quantityPerUnit=materialQuantity(material.craftedFrom),
                bags=raw.bags or 0,bank=raw.bank or 0,total=raw.total or 0,bankKnown=raw.bankKnown==true}
        end
        rows[#rows+1]=row
    end

    local status, blocker, action
    local toolUnknown = tool.required and tool.status == "unknown"
    local missingBagEvidence = not bagsKnown
    local missingStorageEvidence = not storageKnown
    if recipeState == "not-known" then
        status, blocker = "blocked", "recipe"
        action = "Learn the recommended recipe before crafting."
    elseif toolUnknown then
        status, blocker = "verify", "inventory-unknown"
        action = "Refresh current bag and bank observations to verify the required tool; stock is UNKNOWN, not missing."
    elseif tool.required and tool.status~="confirmed" and tool.total <= 0 then
        status, blocker = "blocked", "tool"
        action = "Obtain or craft " .. tostring(tool.name or "the required tool") .. "."
    elseif missingBagEvidence then
        status, blocker = "verify", "inventory-unknown"
        action = "Refresh bag inventory before deciding whether reagents are available or missing."
    elseif immediateBags > 0 then
        status, blocker = "ready", nil
        action = "Ready to craft from materials currently in bags."
    elseif preparedBags > 0 then
        status, blocker = "prepare", "intermediate"
        action = "Craft the required intermediate materials first."
    elseif preparedStorage > 0 and not missingStorageEvidence then
        status, blocker = "bank", "bank"
        action = "Verify the last-known bank inventory, retrieve reagents, then refresh live bag counts."
    elseif missingStorageEvidence then
        status, blocker = "verify", "inventory-unknown"
        action = "Bag stock is insufficient; refresh the bank observation before reporting a material shortage."
    elseif recipeState == "unknown" then
        status, blocker = "verify", "recipe-unknown"
        action = "Open the profession window once to verify recipe knowledge; additional materials are also required."
    else
        status, blocker = "materials", "materials"
        action = "Acquire additional materials before crafting."
    end

    if recipeState == "unknown" and status == "ready" then
        status, blocker = "verify", "recipe-unknown"
        action = "Materials are ready; open the profession window once to verify that the recipe is learned."
    elseif recipeState == "unknown" and (status == "prepare" or status == "bank") then
        action = action .. " Recipe knowledge is not verified yet."
    end

    return {
        key = key,
        status = status,
        blocker = blocker,
        action = action,
        recipe = step.recipe,
        recipeKnowledge = recipeState,
        remainingCrafts = remaining,
        immediateBags = immediateBags,
        immediateBagsKnown = bagsKnown,
        immediateStorage = immediateStorage,
        preparedBags = preparedBags,
        preparedStorage = preparedStorage,
        preparedStorageKnown = storageKnown,
        inventoryEvidence = {
            contract="craft-readiness-inventory-evidence-v1",bagKnown=bagsKnown,
            storageKnown=storageKnown,unknownBagItems=bagsEvidence.unknownBagItems,
            unknownBankItems=storageEvidence.unknownBankItems,
            advisoryOnly=true,nativeDispatchAllowed=false,
        },
        tool = tool,
        materials = rows,
    }
end

function CraftReadiness:FormatCompact(readiness)
    if not readiness then return "Readiness: unavailable" end
    if readiness.status == "complete" then return "Readiness: route complete" end
    if readiness.blocker == "trainer" then return "Readiness: blocked by profession trainer" end
    if readiness.blocker == "profession" then return "Readiness: profession not learned" end
    if not readiness.recipe then return "Readiness: " .. tostring(readiness.action or readiness.status or "unavailable") end

    local recipeText = readiness.recipeKnowledge == "known" and "recipe learned"
        or readiness.recipeKnowledge == "not-known" and "recipe not learned"
        or "recipe unverified"
    local immediate = readiness.immediateBagsKnown == false and "UNKNOWN" or tostring(readiness.immediateBags or 0)
    local storage = readiness.preparedStorageKnown == false and "UNKNOWN" or tostring(readiness.preparedStorage or 0)
    return string.format("Readiness: %s - %s - %s from bags / %s with bags+bank",
        string.upper(tostring(readiness.status or "unknown")),recipeText,immediate,storage)
end

function CraftReadiness:Format(readiness)
    if not readiness then return "CRAFT READINESS\nUnavailable." end
    if not readiness.recipe then
        return "CRAFT READINESS\n" .. tostring(readiness.action or "Unavailable.")
    end

    local recipeText = readiness.recipeKnowledge == "known" and "Learned"
        or readiness.recipeKnowledge == "not-known" and "Not learned"
        or "Unverified - open profession window"
    local toolText = "Not required"
    if readiness.tool and readiness.tool.required then
        if readiness.tool.status == "bags" then
            toolText = tostring(readiness.tool.name) .. " - in bags"
        elseif readiness.tool.status == "bank" then
            toolText = tostring(readiness.tool.name) .. " - in bank"
        elseif readiness.tool.status == "unknown" then
            toolText = tostring(readiness.tool.name) .. " - stock UNKNOWN"
        else
            toolText = tostring(readiness.tool.name) .. " - missing"
        end
    end

    return table.concat({
        "CRAFT READINESS",
        "Status: " .. string.upper(tostring(readiness.status or "unknown")),
        "Recipe: " .. recipeText,
        string.format("Craftable from bags (advisory): %s / %d remaining", readiness.immediateBagsKnown == false and "UNKNOWN" or tostring(readiness.immediateBags or 0), tonumber(readiness.remainingCrafts) or 0),
        string.format("After intermediate prep (bags): %s", readiness.immediateBagsKnown == false and "UNKNOWN" or tostring(readiness.preparedBags or 0)),
        string.format("Potential with bags + bank (advisory): %s", readiness.preparedStorageKnown == false and "UNKNOWN" or tostring(readiness.preparedStorage or 0)),
        "Tool: " .. toolText,
        "Next: " .. tostring(readiness.action or "Continue the current plan."),
    }, "\n")
end

function CraftReadiness:GetSummary()
    local lines = {}
    for _, key in ipairs(productionKeys()) do
        local ready = self:Get(key)
        local label = professionLabel(key)
        lines[#lines + 1] = label .. ": " .. self:FormatCompact(ready):gsub("^Readiness:%s*", "")
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("CraftReadiness", CraftReadiness)
