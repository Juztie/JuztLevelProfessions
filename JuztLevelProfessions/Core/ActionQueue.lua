local _, JLP = ...

local function prerequisiteQueuePlan(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    if ownership and ownership.owned==true then return nil end
    local state=ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN"
    local reg=JLP:GetModule("ProfessionRegistry")
    local label=reg and reg:GetDisplayNameOrKey(key) or tostring(key)
    local text=state=="PROFESSION_NOT_LEARNED" and
        ("Learn "..label.." before JuztLevel can plan this profession.") or
        ("Verify learned "..label.." ownership before JuztLevel can plan this profession.")
    return {key=ownership and ownership.key or key,ownership=ownership,state=state,
        status=state,terminalReason=state,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,lightweightPrerequisite=true,actionKind="prerequisite",action=text,guidance=text}
end

local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end
local function memoObservation(group,key,fn)
    if JLP.MemoObservation then return JLP:MemoObservation(group,key,fn) end
    return fn()
end
local ActionQueue = {}

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

-- P0.1D: One semantic action identity for queue, workspace and progress consumers.
-- Character/profession/route/recipe/source/operation are identity.  List index,
-- current quantity, bag counts, price snapshots and mutable plan revisions are not.
local ID_CONTRACT = "semantic-plan-action-v1"
local function identityAtom(value)
    local text = tostring(value == nil and "" or value)
    return tostring(#text) .. ":" .. text
end
local function stableMaterials(step)
    local result={}
    for _,m in ipairs(type(step)=="table" and type(step.materials)=="table" and step.materials or {}) do
        if type(m)=="table" then
            result[#result+1]=table.concat({identityAtom(m.itemID),identityAtom(m.quantity),identityAtom(m.source)}, "")
        end
    end
    table.sort(result)
    return table.concat(result,";")
end

function ActionQueue:GetActionID(key, action, plan, occurrence)
    if type(action)~="table" then return nil end
    local character=JLP:GetModule("CharacterIdentity")
    local function characterValue() return character and character.GetKey and character:GetKey() or "UnknownRealm:UnknownCharacter" end
    local characterKey=memoObservation("action-identity","character",characterValue)
    local reg=registry()
    local professionKey=memoObservation("action-identity-key",key or "UNKNOWN",function() return reg and reg.NormalizeKey and reg:NormalizeKey(key) or key end)
    local step=type(plan)=="table" and type(plan.step)=="table" and plan.step or nil
    local source=type(action.sourceInfo)=="table" and action.sourceInfo or {}
    local recipe=action.recipeID or action.recipe or action.recipeName or
        (step and (step.recipeID or step.recipe)) or ""
    local routeRecipe=step and (step.recipeID or step.recipe) or ""
    local context=action.identityContext or ""
    -- P0.1D-QAFix: Inventory supplies the registered alt characterKey.  It is
    -- the SOURCE owner, distinct from the currently played character above.
    -- Only alt-bank actions extend the v1 context atom: all other v1 IDs stay
    -- byte-identical, while pre-fix alt-bank receipts cannot match new IDs.
    if action.kind=="transfer-alt-material" or action.source=="alt-bank" then
        local owner=action.characterKey
        if type(owner)~="string" or owner=="" then return nil end
        context=identityAtom(context)..identityAtom(owner)
    end
    local fields={ID_CONTRACT,characterKey,professionKey or "UNKNOWN",action.kind or "unknown",
        action.itemID or "",action.source or "",recipe,routeRecipe,
        step and step.skillMin or "",step and step.skillTarget or "",
        step and step.dataset and step.dataset.sourceBuild or "",
        stableMaterials(step),
        source.kind or "",source.name or "",source.zone or "",source.id or source.npcID or "",
        context,action.exceptionSource or "",
        action.targetCap or (plan and plan.actionKind=="train" and step and step.trainer and step.trainer.nextCap) or "",
        occurrence or action.identityOccurrence or 1}
    local tokens={}
    for _,value in ipairs(fields) do tokens[#tokens+1]=identityAtom(value) end
    return table.concat(tokens,"|")
end

local function assignIdentities(key, plan, actions)
    local seen={}
    for index,action in ipairs(actions) do
        action.index=index -- UI ordering is not identity.
        local semantic=ActionQueue:GetActionID(key, action, plan, 1)
        action.identityContract=ID_CONTRACT
        if semantic then
            local ordinal=(seen[semantic] or 0)+1
            seen[semantic]=ordinal
            action.identityOccurrence=ordinal
            action.actionID=ActionQueue:GetActionID(key,action,plan,ordinal)
        else
            -- No stable source identity: never manufacture a reusable receipt.
            action.identityOccurrence=nil
            action.actionID=nil
            action.identityUnresolved=true
        end
    end
end

local function add(actions, kind, text, detail, itemID, quantity, meta)
    -- Guard the action handoff, including nested inputs and tool materials.
    -- Static route sourcing must not silently authorize AH in Self-found mode.
    local optimizer=JLP:GetModule("CostOptimizer")
    local sourcePolicy=kind and kind:match("^acquire") and optimizer and
        optimizer.ClassifyMaterialSource and
        optimizer:ClassifyMaterialSource(meta and meta.source) or nil
    if sourcePolicy and sourcePolicy.exceptionPending then
        local name=tostring(meta and meta.itemName or (itemID and ("item "..tostring(itemID)) or "material"))
        text=string.format("Self-found: verify non-AH source for %s x%d; AH requires explicit acceptance.",
            name,math.max(1,math.floor(tonumber(quantity) or 1)))
        detail="Source unresolved; do not treat AH pricing or travel as purchase approval."
        kind="verify-self-found-source"
        local updated={}
        for k,v in pairs(meta or {}) do updated[k]=v end
        updated.exceptionSource=meta and meta.source
        updated.source="unresolved"
        updated.exceptionPending=true
        updated.approvalGranted=false
        updated.nativeDispatchAllowed=false
        meta=updated
    end
    local row = {
        index = #actions + 1,
        kind = kind,
        text = text,
        detail = detail,
        itemID = itemID,
        quantity = quantity,
        status = "pending",
    }
    for key, value in pairs(meta or {}) do row[key] = value end
    actions[#actions + 1] = row
end

local function inventory()
    return JLP:GetModule("Inventory")
end

local function owned(itemID)
    local inv = inventory()
    if inv and inv.GetOwned then return inv:GetOwned(itemID) end
    return { bags=0, bank=0, total=0, bankKnown=false }
end

local function stockReservation()
    local used={}
    local function count(value)
        value=tonumber(value)
        return value and value==value and value>=0 and value<math.huge and math.floor(value) or 0
    end
    return function(itemID,required)
        if itemID==nil then return {bags=0,bank=0,total=0} end
        local actual=owned(itemID)
        actual=type(actual)=="table" and actual or {}
        local prior=used[itemID] or {bags=0,bank=0}
        local bags=math.max(0,count(actual.bags)-prior.bags)
        local bank=math.max(0,count(actual.bank)-prior.bank)
        local take=math.min(count(required),bags+bank)
        local bagTake=math.min(take,bags)
        local bankTake=take-bagTake
        used[itemID]={bags=prior.bags+bagTake,bank=prior.bank+bankTake}
        return {bags=bagTake,bank=bankTake,total=take}
    end
end

local function professionLabel(key, plan)
    if plan and plan.profession and plan.profession.name then return plan.profession.name end
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local function itemName(itemID)
    local catalog=JLP:GetModule("MaterialCatalog")
    return catalog and catalog:GetName(itemID) or (itemID and ("item "..tostring(itemID)) or "material")
end

local function addAltBankActions(actions,itemID,name,missing,detail,identityContext)
    missing=math.max(0,math.floor(tonumber(missing) or 0))
    if missing<=0 then return 0 end
    local inv=inventory()
    local remaining=missing
    for _,alt in ipairs(inv and inv.GetAltBankAvailability and inv:GetAltBankAvailability(itemID,{sameRealm=true}) or {}) do
        if remaining<=0 then break end
        local take=math.min(remaining,math.max(0,tonumber(alt.count) or 0))
        -- A cached alt without a registered key is not a qualified transfer
        -- source; leave those units unresolved for normal source verification.
        if take>0 and type(alt.characterKey)=="string" and alt.characterKey~="" then
            add(actions,"transfer-alt-material",string.format("Retrieve %s x%d from %s's bank.",name,take,tostring(alt.name or alt.characterKey or "another character")),detail or ("Last-known snapshot: "..tostring(alt.freshness or "UNKNOWN")),itemID,take,{source="alt-bank",itemName=name,characterKey=alt.characterKey,characterName=alt.name,freshness=alt.freshness,updatedAt=alt.updatedAt,requiresTransfer=true,currentAccessible=false,identityContext=identityContext or detail})
            remaining=remaining-take
        end
    end
    return remaining
end

local function acquireText(name, quantity, source)
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    source = tostring(source or "unknown")
    if source == "vendor" then
        return string.format("Buy %s x%d from a vendor.", name, quantity)
    elseif source == "auction" then
        return string.format("Acquire %s x%d (Auction House or other source).", name, quantity)
    elseif source == "disenchant-or-auction" then
        return string.format("Obtain %s x%d via Auction House or the disenchant plan.", name, quantity)
    end
    return string.format("Acquire %s x%d.", name, quantity)
end

local function recipeSourceText(key, step)
    local resolver = JLP:GetModule("SourceResolver")
    if resolver and step then
        local text = resolver:DescribeRecipe(key, step.recipe, step.recipeSource)
        if text then return text end
    end
    return tostring(step and step.recipeSource or "profession trainer")
end

local function addToolActions(actions, step, readiness, reserveStock)
    local tool = readiness and readiness.tool
    if not tool or not tool.required or tool.status == "bags" or tool.status == "confirmed" then return end

    if tool.status == "bank" then
        add(actions, "retrieve-tool", "Retrieve " .. tostring(tool.name) .. " from the bank.", nil, tool.itemID, 1, { source="bank", itemName=tool.name })
        return
    end

    local definition = step and step.requiredTool
    for _, material in ipairs(definition and definition.materials or {}) do
        local required = math.max(1, math.floor(tonumber(material.quantity) or 1))
        local store = reserveStock(material.itemID,required)
        local bagShort = math.max(0, required - (store.bags or 0))
        local retrieve = math.min(store.bank or 0, bagShort)
        if retrieve > 0 then
            add(actions, "retrieve-tool-material", string.format("Retrieve %s x%d from the bank for %s.", material.name or itemName(material.itemID), retrieve, tool.name), nil, material.itemID, retrieve, { source="bank", itemName=material.name or itemName(material.itemID) })
        end
        local missing = math.max(0, required - (store.total or 0))
        missing = addAltBankActions(actions,material.itemID,material.name or itemName(material.itemID),missing,"Required to craft "..tostring(tool.name))
        if missing > 0 then
            add(actions, "acquire-tool-material", acquireText(material.name or itemName(material.itemID), missing, material.source), "Required to craft " .. tostring(tool.name), material.itemID, missing, { source=material.source or "unknown", itemName=material.name or itemName(material.itemID) })
        end
    end
    add(actions, "craft-tool", "Craft " .. tostring(tool.name) .. ".", "Required Enchanting tool.", tool.itemID, 1, { source="craft", itemName=tool.name })
end

local function addRecursiveCraftActions(actions, node, outputUnitsNeeded, parentName, batchCrafts, depth, active, reserveStock)
    if type(node) ~= "table" then return false end
    outputUnitsNeeded = math.max(0, math.floor(tonumber(outputUnitsNeeded) or 0))
    if outputUnitsNeeded <= 0 then return true end
    depth = tonumber(depth) or 0
    if depth > 12 then return false end
    local token = tostring(node.producerStepIndex or node.recipe or node.name or depth)
    active = active or {}
    if active[token] then return false end
    active[token] = true

    local outputPerCraft = math.max(1, math.floor(tonumber(node.outputPerCraft) or 1))
    local craftsNeeded = math.ceil(outputUnitsNeeded / outputPerCraft)
    local stores={}
    for index,reagent in ipairs(node.materials or {}) do
        local perCraft=math.max(1,tonumber(reagent.quantity) or tonumber(reagent.perCraft) or 1)
        stores[index]=reserveStock(reagent.itemID,math.ceil(perCraft*craftsNeeded))
    end
    for reagentIndex, reagent in ipairs(node.materials or {}) do
        local perCraft = math.max(1, tonumber(reagent.quantity) or tonumber(reagent.perCraft) or 1)
        local required = math.ceil(perCraft * craftsNeeded)
        local store = stores[reagentIndex]
        local name = reagent.name or itemName(reagent.itemID)
        local bags = tonumber(store.bags) or 0
        local bank = tonumber(store.bank) or 0
        local bagShort = math.max(0, required - bags)
        local retrieve = math.min(bank, bagShort)
        if retrieve > 0 then
            add(actions, "retrieve-recursive-material", string.format("Retrieve %s x%d from the bank.", name, retrieve), "Input for " .. tostring(node.recipe or node.name or parentName or "intermediate craft"), reagent.itemID, retrieve, { source="bank", itemName=name, recursiveDepth=depth, identityContext=tostring(parentName or "")..":"..tostring(node.recipeID or node.recipe or node.name or "")..":reagent:"..tostring(reagentIndex) })
        end
        local missing = math.max(0, required - (tonumber(store.total) or 0))
        missing = addAltBankActions(actions,reagent.itemID,name,missing,"Input for "..tostring(node.recipe or node.name or parentName or "intermediate craft"),tostring(parentName or "")..":"..tostring(node.recipeID or node.recipe or node.name or "")..":reagent:"..tostring(reagentIndex))
        if missing > 0 then
            if reagent.craftedRecipe then
                if not addRecursiveCraftActions(actions, reagent.craftedRecipe, missing, node.recipe or node.name, batchCrafts, depth + 1, active, reserveStock) then
                    active[token] = nil
                    return false
                end
            else
                local source = reagent.source or "unknown"
                add(actions, "acquire-recursive-material", acquireText(name, missing, source), "Input for " .. tostring(node.recipe or node.name or parentName or "intermediate craft"), reagent.itemID, missing, { source=source, itemName=name, recursiveDepth=depth, identityContext=tostring(parentName or "")..":"..tostring(node.recipeID or node.recipe or node.name or "")..":reagent:"..tostring(reagentIndex) })
            end
        end
    end

    local produced = craftsNeeded * outputPerCraft
    add(actions, "craft-intermediate", string.format("Craft %s x%d craft%s.", tostring(node.recipe or node.name or "intermediate"), craftsNeeded, craftsNeeded == 1 and "" or "s"), string.format("Produces %d %s for %s.", produced, tostring(node.name or "intermediate units"), tostring(parentName or "the current batch")), node.itemID, craftsNeeded, { source="craft", itemName=node.name, recipe=node.recipe, recipeID=node.recipeID, batchCrafts=batchCrafts, outputUnits=produced, outputPerCraft=outputPerCraft, producerStepIndex=node.producerStepIndex, recursiveDepth=depth, identityContext=parentName })
    active[token] = nil
    return true
end

local function addMaterialActions(actions, step, readiness, batchCrafts, reserveStock, stores)
    batchCrafts = math.max(1, math.floor(tonumber(batchCrafts) or 1))
    for index, row in ipairs(readiness and readiness.materials or {}) do
        local material = step and step.materials and step.materials[index]
        local perCraft = math.max(1, math.floor(tonumber(row.perCraft) or tonumber(material and material.quantity) or 1))
        local name = row.name or (material and material.name) or itemName(row.itemID)
        local assigned=stores[index] or {bags=0,bank=0}
        local bags = tonumber(assigned.bags) or 0
        local bank = tonumber(assigned.bank) or 0

        local batchRequired = perCraft * batchCrafts
        local bagShort = math.max(0, batchRequired - bags)
        local retrieveDirect = math.min(bank, bagShort)
        if retrieveDirect > 0 then
            add(actions, "retrieve-material", string.format("Retrieve %s x%d from the bank.", name, retrieveDirect), nil, row.itemID, retrieveDirect, { source="bank", itemName=name, identityContext="reagent:"..tostring(index) })
        end

        local directAfterStorage = bags + bank
        local finalUnitsMissing = math.max(0, batchRequired - directAfterStorage)
        if finalUnitsMissing > 0 and (row.craftedRecipe or (material and material.craftedRecipe)) then
            if not addRecursiveCraftActions(actions, row.craftedRecipe or material.craftedRecipe, finalUnitsMissing, name, batchCrafts, 1, {}, reserveStock) then
                add(actions,"verify-dependency","Review the intermediate recipe dependencies before crafting.",
                    "A cyclic or unsupported material dependency cannot be used as a preparation plan.")
            end
        elseif finalUnitsMissing > 0 and row.craftedFrom then
            local raw = row.craftedFrom
            local rawName = itemName(raw.itemID)
            local rawPerUnit = math.max(1, math.floor(tonumber(raw.quantityPerUnit) or 1))
            local rawRequired = finalUnitsMissing * rawPerUnit
            local rawStore=reserveStock(raw.itemID,rawRequired)
            local rawBags = tonumber(rawStore.bags) or 0
            local rawBank = tonumber(rawStore.bank) or 0
            local rawBagShort = math.max(0, rawRequired - rawBags)
            local rawRetrieve = math.min(rawBank, rawBagShort)
            if rawRetrieve > 0 then
                add(actions, "retrieve-raw", string.format("Retrieve %s x%d from the bank.", rawName, rawRetrieve), "Raw input for " .. name, raw.itemID, rawRetrieve, { source="bank", itemName=rawName, identityContext="reagent:"..tostring(index)..":raw" })
            end
            local rawMissing = math.max(0, rawRequired - (tonumber(rawStore.total) or 0))
            rawMissing = addAltBankActions(actions,raw.itemID,rawName,rawMissing,"Raw input for "..name,"reagent:"..tostring(index)..":raw")
            if rawMissing > 0 then
                add(actions, "acquire-raw", acquireText(rawName, rawMissing, "auction"), "Raw input for " .. name, raw.itemID, rawMissing, { source="auction", itemName=rawName, identityContext="reagent:"..tostring(index)..":raw" })
            end
            add(actions, "craft-intermediate", string.format("Craft %s x%d.", name, finalUnitsMissing), string.format("Uses %s x%d for the current batch.", rawName, rawRequired), row.itemID, finalUnitsMissing, { source="craft", itemName=name, batchCrafts=batchCrafts, identityContext="reagent:"..tostring(index) })
        elseif finalUnitsMissing > 0 then
            local source = material and material.source or "unknown"
            finalUnitsMissing = addAltBankActions(actions,row.itemID,name,finalUnitsMissing,nil,"reagent:"..tostring(index))
            if finalUnitsMissing > 0 then
                add(actions, "acquire-material", acquireText(name, finalUnitsMissing, source), nil, row.itemID, finalUnitsMissing, { source=source, itemName=name, identityContext="reagent:"..tostring(index) })
            end
        end
    end
end

-- The common allocation graph owns every physical unit and produced surplus.
-- Presentation derives actions from its aggregate requirements, never performs
-- a second stock allocation for a sibling, raw input or required tool.
local function addAllocatedActions(actions,step,readiness,batchCrafts)
    local allocator=JLP:GetModule("CraftReadiness")
    if not allocator or type(allocator.AllocateMaterials)~="function" then return false,true end
    local inputs,roles={},{}
    local function count(value)
        value=tonumber(value)
        return value and value==value and value>=0 and value<math.huge and math.floor(value) or 0
    end
    local function identify(material,kind,context,parent,priority,depth,active)
        if type(material)~="table" or depth>12 then return end
        local id=material.itemID
        if not id then return end
        local prior=roles[id]
        if not prior or priority<prior.priority then
            roles[id]={kind=kind,context=context,parent=parent,priority=priority,material=material}
        end
        if active[id] then return end
        active[id]=true
        local node=material.craftedRecipe
        if type(node)=="table" then
            for index,child in ipairs(node.materials or {}) do
                identify(child,(kind=="tool" or kind=="tool-material") and "tool-material" or "recursive-material",
                    tostring(parent or material.name or "")..":"..tostring(node.recipeID or node.recipe or node.name or "")..":reagent:"..index,
                    node.recipe or node.name or material.name,kind=="tool" and 1 or 3,depth+1,active)
            end
        elseif type(material.craftedFrom)=="table" then
            identify(material.craftedFrom,(kind=="tool" or kind=="tool-material") and "tool-material" or "raw",
                tostring(context or "")..":raw",material.name,kind=="tool" and 1 or 2,depth+1,active)
        end
        active[id]=nil
    end
    for index,material in ipairs(step.materials or {}) do
        if type(material)~="table" then
            add(actions,"verify-dependency","Verify the current recipe's material requirements before crafting.",
                "A material identity is unavailable.",nil,nil,{readOnly=true,nativeDispatchAllowed=false})
            return true,false
        end
        local scaled={};for field,value in pairs(material) do scaled[field]=value end
        scaled.quantity=math.max(1,count(material.quantity or material.perCraft))*batchCrafts
        inputs[#inputs+1]=scaled
        identify(material,"material","reagent:"..index,nil,0,0,{})
    end
    local tool=readiness and readiness.tool
    if tool and tool.required and tool.status~="bags" and tool.status~="confirmed" then
        local definition=step.requiredTool
        local id=tool.itemID or definition and definition.itemID
        if not id or (tool.status~="bank" and
            (type(definition)~="table" or type(definition.materials)~="table" or #definition.materials==0)) then
            add(actions,"verify-dependency","Verify the required tool and its material requirements before crafting.",
                "No qualified tool producer is available.",nil,nil,{readOnly=true,nativeDispatchAllowed=false})
            return true,false
        end
        local material={itemID=id,name=tool.name or definition and definition.name,quantity=1,source="craft"}
        if type(definition)=="table" and type(definition.materials)=="table" and #definition.materials>0 then
            material.craftedRecipe={itemID=id,name=material.name,recipe=definition.recipe,
                recipeID=definition.recipeID,outputPerCraft=1,materials=definition.materials}
        end
        inputs[#inputs+1]=material
        identify(material,"tool",nil,nil,-1,0,{})
    end
    local ok,graph=pcall(allocator.AllocateMaterials,allocator,inputs,1,{useStorage=true,prepare=true})
    if not ok or type(graph)~="table" or type(graph.requirements)~="table" or
        type(graph.requirementOrder)~="table" or type(graph.production)~="table" or
        (graph.reason~=nil and graph.reason~="insufficient-materials") then
        add(actions,"verify-dependency","Review the intermediate recipe dependencies before crafting.",
            "A cyclic, conflicting or unsupported dependency cannot be used as a preparation plan.",
            nil,nil,{readOnly=true,nativeDispatchAllowed=false,dependencyReason=type(graph)=="table" and graph.reason or "ALLOCATION_UNAVAILABLE"})
        return true,false
    end
    -- An allocator can encounter several failures; a later ordinary shortage
    -- must not hide an earlier unresolved producer behind the summary reason.
    for _,id in ipairs(graph.requirementOrder) do
        local requirement=graph.requirements[id]
        local role=roles[id]
        local material=role and role.material or requirement.material
        if count(requirement.missing)>0 and type(material)=="table" and
            (type(material.craftedRecipe)=="table" or type(material.craftedFrom)=="table") then
            add(actions,"verify-dependency","Review the intermediate recipe dependencies before crafting.",
                "A declared producer could not be resolved into a valid preparation plan.",
                id,nil,{readOnly=true,nativeDispatchAllowed=false})
            return true,false
        end
    end
    local productions={}
    for _,production in ipairs(graph.production) do productions[production.itemID]=production end
    -- Stable dependency-first order, even when independent graph roots were
    -- collected by pairs(). A cycle never becomes a crafting instruction.
    local ordered,visiting,visited={},{},{}
    local function visit(id)
        if visiting[id] then return false end
        if visited[id] or not productions[id] then return true end
        visiting[id]=true
        local dependencies={}
        for _,child in ipairs(productions[id].materials or {}) do
            if productions[child.itemID] then dependencies[#dependencies+1]=child.itemID end
        end
        table.sort(dependencies,function(a,b) return tostring(a)<tostring(b) end)
        for _,child in ipairs(dependencies) do if not visit(child) then return false end end
        visiting[id],visited[id]=nil,true
        ordered[#ordered+1]=productions[id]
        return true
    end
    local ids={};for id in pairs(productions) do ids[#ids+1]=id end
    table.sort(ids,function(a,b) return tostring(a)<tostring(b) end)
    for _,id in ipairs(ids) do
        if not visit(id) then
            add(actions,"verify-dependency","Review the intermediate recipe dependencies before crafting.",
                "A cyclic dependency cannot be used as a preparation plan.",nil,nil,{readOnly=true,nativeDispatchAllowed=false})
            return true,false
        end
    end
    for id,role in pairs(roles) do
        if role.kind=="tool" and count(graph.requirements[id] and graph.requirements[id].missing)>0 then
            add(actions,"verify-dependency","Verify the required tool and its material requirements before crafting.",
                "The required tool is unavailable and has no qualified producer.",id,1,{readOnly=true,nativeDispatchAllowed=false})
            return true,false
        end
    end
    for _,id in ipairs(graph.requirementOrder) do
        local requirement=graph.requirements[id]
        local role=roles[id] or {kind="recursive-material",material=requirement.material or {}}
        local material=role.material or requirement.material or {}
        local name=material.name or itemName(id)
        local actual=owned(id)
        local retrieve=math.max(0,count(requirement.allocated)-count(actual and actual.bags))
        local detail=role.parent and ("Input for "..tostring(role.parent)) or nil
        local context=role.context
        if retrieve>0 then
            local kind=role.kind=="tool" and "retrieve-tool" or "retrieve-"..role.kind
            add(actions,kind,string.format("Retrieve %s x%d from the bank.",name,retrieve),detail,id,retrieve,
                {source="bank",itemName=name,identityContext=context})
        end
        local missing=count(requirement.missing)
        if missing>0 then
            missing=addAltBankActions(actions,id,name,missing,detail,context)
            if missing>0 then
                add(actions,"acquire-"..role.kind,acquireText(name,missing,material.source),detail,id,missing,
                    {source=material.source or "unknown",itemName=name,identityContext=context})
            end
        end
    end
    for _,production in ipairs(ordered) do
        local role=roles[production.itemID] or {}
        local material=role.material or {}
        local node=production.node or {}
        local name=node.name or material.name or itemName(production.itemID)
        local isTool=role.kind=="tool"
        local simple=type(material.craftedFrom)=="table" and type(material.craftedRecipe)~="table"
        local context
        if not isTool then context=simple and role.context or material.name or role.parent end
        add(actions,isTool and "craft-tool" or "craft-intermediate",
            string.format("Craft %s x%d craft%s.",tostring(node.recipe or name),production.crafts,production.crafts==1 and "" or "s"),
            string.format("Produces %d %s for the current batch.",production.outputUnits,tostring(name)),
            production.itemID,production.crafts,{source="craft",itemName=name,
                recipe=not isTool and not simple and node.recipe or nil,
                recipeID=not isTool and not simple and node.recipeID or nil,
                outputUnits=production.outputUnits,outputPerCraft=production.outputPerCraft,
                producerStepIndex=node.producerStepIndex,batchCrafts=batchCrafts,
                identityContext=context,
                nativeDispatchAllowed=false})
    end
    return true,true
end

function ActionQueue:Build(key, plan, readiness)
    local planner = JLP:GetModule("Planner")
    plan = plan or (planner and planner:GetProfessionPlan(key))
    local reg=registry()
    local availability=reg and reg:ResolveWorkflowAvailability(key,"executionFlow") or nil
    if availability and availability.state~="available" and not isReadOnlyResearchPlan(plan) then
        return {key=availability.key or key,status=availability.state,terminalReason=availability.terminalReason,
            currentIndex=0,actions={},plan=nil,
            strategy=(plan and plan.strategy) or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"}
    end
    -- Missing plans must never become synthetic completed or travel-eligible
    -- routes. Reference data remains visible from Planner/ProfessionState.
    if not plan then
        return {key=key,status="unqualified",terminalReason="NO_QUALIFIED_ROUTE",
            currentIndex=0,actions={},plan=nil,readOnly=true,nativeDispatchAllowed=false,
            strategy=(JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"}
    end
    local actions = {}

    -- A historical route FALLBACK is not itself an action kind. In particular,
    -- it may coexist with independent, useful manual LEARN/TRAIN/VERIFY and
    -- currently attested ONE-craft suggestions. Do not erase those actions.
    if plan.actionKind == "reference" and type(plan.recommendedCurrentStep)=="table" and
        plan.recommendedCurrentStep.kind=="gather" then
        local rec=plan.recommendedCurrentStep
        add(actions,"gather-resource",tostring(rec.action or plan.action or
            "Inspect existing Gathering Map for a skill-appropriate source."),
            "Map references are not guaranteed spawns; recheck current skill after gathering.",
            nil,nil,{readOnly=true,nativeDispatchAllowed=false,professionKey=key,
                navigation=rec.navigation,skill=rec.skill,reference=rec.resourceReference})
    elseif plan.actionKind == "reference" then
        add(actions,"verify-reference",tostring(plan.action or
            "Inspect the advisory reference and verify live recipe access."),
            "This is a source reference, not a learned recipe or native crafting permission.",
            nil,nil,{readOnly=true,nativeDispatchAllowed=false,professionKey=key,
                referencePosition=plan.referencePosition,referenceGap=plan.referenceGap})
    elseif plan.actionKind == "learn" then
        local sourceInfo = plan.sourceInfo
        local detail = sourceInfo and sourceInfo.name or nil
        add(actions, "learn-profession", "Learn " .. professionLabel(key, plan) .. " before continuing.", detail, nil, nil, { source="profession-trainer", sourceInfo=sourceInfo, professionKey=key, professionName=professionLabel(key, plan) })
    elseif plan.actionKind == "train" then
        add(actions, "train-rank", tostring(plan.action or "Train the next profession rank."), plan.step and plan.step.sourceInfo and plan.step.sourceInfo.name or nil, nil, nil, { source="trainer", sourceInfo=plan.step and plan.step.sourceInfo or nil })
    elseif plan.actionKind == "complete" then
        return { key=key, status="complete", currentIndex=0, actions={}, plan=plan,
            strategy=plan.strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical",
            routeSelection=plan.routeSelection }
    elseif plan.actionKind == "verify" then
        local current=plan.recommendedCurrentStep
        local acquisition=type(current)=="table" and current.recipeSourcePlanning or nil
        if current and current.kind=="craft" and current.learned==false and
           type(acquisition)=="table" and acquisition.recipeID==current.recipeID then
            local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
            local description=bridge and bridge.Describe and bridge:Describe(acquisition) or
                "Verify the exact recipe source before travelling."
            add(actions,"learn-recipe",tostring(plan.action or ("Learn "..tostring(current.recipe))),
                description,nil,nil,{source="recipe-advisory",readOnly=true,
                nativeDispatchAllowed=false,professionKey=key,recipeID=current.recipeID,
                recipeSourcePlanning=acquisition,navigation=current.navigation,
                requiresManualConfirmation=true})
        else
            add(actions,"verify-step",tostring(plan.action or "Verify the current recipe in game."),
                "Verification is manual; no recipe count, craft execution or purchase is authorized.",
                nil,nil,{readOnly=true,nativeDispatchAllowed=false,professionKey=key})
        end
    elseif plan.actionKind == "craft" and
        plan.p1OneCraft==true and type(plan.recommendedCurrentStep)=="table" and
        plan.recommendedCurrentStep.bagReady~=true then
        local rec=plan.recommendedCurrentStep
        local unresolved=false
        for _,material in ipairs(rec.materials or {}) do
            if material.missing==nil then
                unresolved=true
                add(actions,"verify-inventory",string.format("Check current bags for %s (item %d), need %d for ONE craft.",
                    tostring(material.name or ("Item "..material.itemID)),material.itemID,material.required),
                    "Inventory is UNKNOWN, not zero.",material.itemID,material.required,
                    {readOnly=true,nativeDispatchAllowed=false,professionKey=key,
                     navigation=rec.navigation})
            elseif material.missing>0 then
                add(actions,"acquire-material",string.format("Acquire %s x%d for %s.",
                    tostring(material.name or ("Item "..material.itemID)),material.missing,tostring(rec.recipe)),
                    material.price and ("AH reference estimate: "..tostring(material.price).." copper") or
                        "No AH scan required; price unknown. Vendor/gathering alternatives may be used.",
                    material.itemID,material.missing,
                    {source=material.source or "unknown",readOnly=true,nativeDispatchAllowed=false,professionKey=key,
                     navigation=rec.navigation,
                     sourceInfo=rec.navigation and rec.navigation.waypointQualified and rec.navigation.source or nil})
            end
        end
        if #actions==0 then
            add(actions,"verify-inventory",tostring(rec.nextAction),nil,nil,nil,
                {readOnly=true,nativeDispatchAllowed=false,professionKey=key})
        end
        assignIdentities(key,plan,actions)
        return {key=key,status="active",currentIndex=1,actions=actions,plan=plan,
            readOnly=true,nativeDispatchAllowed=false,
            strategy=plan.strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"}
    elseif plan.actionKind == "craft" and
        (plan.readOnlyRouteFallback == true or plan.p1OneCraft == true) then
        if plan.p1OneCraft==true and type(plan.step)=="table" then
            -- The source-specific P1 attestation authorizes advice for ONE
            -- manual player-controlled craft only. No generic batch queue.
            add(actions,"verify-one-craft",tostring(plan.action or "Prepare ONE manual craft."),
                "Use the normal profession window; refresh observed skill and materials afterwards.",
                nil,nil,{readOnly=true,nativeDispatchAllowed=false,professionKey=key,
                    requiresManualConfirmation=true,recipe=plan.step.recipe,
                    recipeID=plan.step.recipeID})
        else
            add(actions,"verify-reference",tostring(plan.action or
                "Verify source-backed recipe and current skill."),
                "Historical craft totals and requirements are not verified for native execution.",
                nil,nil,{readOnly=true,nativeDispatchAllowed=false,professionKey=key})
        end
    elseif plan.actionKind ~= "craft" or not plan.step then
        add(actions, "route", tostring(plan.action or "No actionable profession step is available."))
    else
        if readiness == nil then
            local readinessModule = JLP:GetModule("CraftReadiness")
            readiness = readinessModule and readinessModule:Get(key, plan) or nil
        end
        local step = plan.step

        if readiness and readiness.recipeKnowledge == "unknown" then
            add(actions, "verify-recipe", string.format("Open the %s profession window to verify %s.", professionLabel(key, plan), tostring(step.recipe or "the recommended recipe")), nil, nil, nil, { source="profession-window", recipe=step.recipe })
        elseif readiness and readiness.recipeKnowledge == "not-known" then
            add(actions, "learn-recipe", "Learn " .. tostring(step.recipe or "the recommended recipe") .. ".", "Source: " .. recipeSourceText(key, step), nil, nil, { source="recipe", sourceInfo=step.sourceInfo, recipe=step.recipe })
        end

        local remaining = readiness and tonumber(readiness.remainingCrafts) or tonumber(step.remainingCrafts) or 1
        local immediate = readiness and tonumber(readiness.immediateBags) or 0
        local preparedBags = readiness and tonumber(readiness.preparedBags) or 0
        local preparedStorage = readiness and tonumber(readiness.preparedStorage) or 0
        local availableBatch = immediate > 0 and immediate or (preparedBags > 0 and preparedBags or (preparedStorage > 0 and preparedStorage or 1))
        local batchCrafts = math.max(1, math.min(math.max(1, math.floor(remaining or 1)), math.max(1, math.floor(availableBatch))))
        if readiness and (readiness.immediateBagsKnown == false or readiness.blocker == "inventory-unknown") then
            add(actions,"verify-inventory","Refresh bag and bank counts for this recipe before acquiring reagents.",
                "Unobserved stock is UNKNOWN, not confirmed zero. Historical requirements are advisory only.",
                nil,nil,{readOnly=true,nativeDispatchAllowed=false,professionKey=key})
            assignIdentities(key,plan,actions)
            return {key=key,status="active",currentIndex=1,actions=actions,plan=plan,
                readOnly=true,nativeDispatchAllowed=false,
                strategy=plan.strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical",
                routeSelection=plan.routeSelection}
        end
        local graphUsed,dependenciesValid=addAllocatedActions(actions,step,readiness,batchCrafts)
        if not graphUsed then
            local reserveStock=stockReservation()
            local assigned={}
            for index,row in ipairs(readiness and readiness.materials or {}) do
                local material=step.materials and step.materials[index]
                local perCraft=math.max(1,tonumber(row.perCraft) or tonumber(material and material.quantity) or 1)
                assigned[index]=reserveStock(row.itemID,perCraft*batchCrafts)
            end
            addToolActions(actions, step, readiness, reserveStock)
            addMaterialActions(actions, step, readiness, batchCrafts, reserveStock, assigned)
        end

        local craftNow = readiness and tonumber(readiness.immediateBags) or 0
        local detail
        if craftNow > 0 then
            detail = string.format("Up to %d craft%s currently available from bags.", craftNow, craftNow == 1 and "" or "s")
        else
            detail = "This becomes available after the prerequisite actions above are satisfied."
        end
        if dependenciesValid then
            add(actions, "craft-leveling", string.format("Craft %s x%d and continue toward skill %d.", tostring(step.recipe or "the recommended recipe"), batchCrafts, tonumber(step.skillTarget) or 0), detail, nil, batchCrafts, { source="craft", itemName=step.recipe, batchCrafts=batchCrafts })
        end
    end

    assignIdentities(key, plan, actions)
    return {
        key = key,
        status = #actions > 0 and "active" or "complete",
        currentIndex = #actions > 0 and 1 or 0,
        actions = actions,
        plan = plan,
        strategy = plan and plan.strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical",
        routeSelection = plan and plan.routeSelection or nil,
    }
end

function ActionQueue:GetCurrent(key, plan)
    local queue = self:Build(key, plan)
    return queue.actions[queue.currentIndex], queue
end

function ActionQueue:FormatCompact(queue)
    if not queue then return "Action queue: unavailable" end
    if queue.status == "unqualified" then return "Action queue: no qualified route" end
    if queue.status == "complete" or queue.currentIndex == 0 then return "Action queue: complete" end
    local action = queue.actions[queue.currentIndex]
    return "Next action: " .. tostring(action and action.text or "Continue current profession plan.")
end

function ActionQueue:Format(queue, limit)
    if not queue then return "ACTION QUEUE\nUnavailable." end
    if queue.status == "unqualified" then return "ACTION QUEUE\nNo qualified route; verify profession source data." end
    if queue.status == "complete" or #queue.actions == 0 then return "ACTION QUEUE\nRoute complete." end
    limit = math.max(1, math.floor(tonumber(limit) or 5))
    local lines = {"ACTION QUEUE"}
    for index, action in ipairs(queue.actions) do
        if index > limit then
            lines[#lines + 1] = string.format("  + %d more action%s", #queue.actions - limit, (#queue.actions - limit) == 1 and "" or "s")
            break
        end
        local marker = index == queue.currentIndex and ">" or " "
        lines[#lines + 1] = string.format("%s %d. %s", marker, index, tostring(action.text or "Continue."))
        if action.detail and action.detail ~= "" and index == queue.currentIndex then
            lines[#lines + 1] = "    " .. tostring(action.detail)
        end
    end
    return table.concat(lines, "\n")
end

function ActionQueue:GetSummary()
    local lines = {}
    for _, key in ipairs(productionKeys()) do
        local queue = self:Build(key)
        local label = professionLabel(key)
        lines[#lines + 1] = label .. ": " .. self:FormatCompact(queue):gsub("^Action queue:%s*", "")
    end
    return table.concat(lines, "\n")
end

do
    local build=ActionQueue.Build
    function ActionQueue:Build(key,plan,readiness)
        return withObservationPass("ActionQueue.request",function()
            local prerequisite=prerequisiteQueuePlan(key)
            if prerequisite then return {key=key,status=prerequisite.status,terminalReason=prerequisite.terminalReason,
                currentIndex=0,actions={},readOnly=true,nativeDispatchAllowed=false,plan=prerequisite} end
            local planner=JLP:GetModule("Planner")
            plan=plan or (planner and planner:GetProfessionPlan(key))
            -- Explicit readiness is a separate projection; default queues share by plan identity.
            return memoObservation("queue:"..tostring(key),readiness or plan or "empty",function() return build(self,key,plan,readiness) end)
        end)
    end
end

JLP:RegisterModule("ActionQueue", ActionQueue)
