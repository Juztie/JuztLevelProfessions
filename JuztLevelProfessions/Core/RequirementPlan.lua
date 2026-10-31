local _, JLP = ...

-- Builds a profession-agnostic requirement/acquisition model for the current
-- crafting step. The UI consumes this instead of assuming a single next item.
local RequirementPlan = {}

local function safeNumber(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end


local function datasetMaterial(plan, itemID)
    local materials = plan and plan.step and plan.step.dataset and plan.step.dataset.materials
    if type(materials) ~= "table" then return nil end
    for _, definition in pairs(materials) do
        if tonumber(definition and definition.itemID) == tonumber(itemID) then return definition end
    end
    return nil
end

local function catalogOptions(itemID, name, source, storage)
    local catalog = JLP:GetModule("MaterialCatalog")
    if catalog and catalog.GetAcquisitionOptions then
        local ok,resolved=pcall(catalog.GetAcquisitionOptions,catalog,itemID,name,source,storage)
        -- A malformed or unavailable catalog must not block the plan UI.
        -- Preserve the unresolved source instead of inventing options.
        if not ok or type(resolved)~="table" then return {} end
        local options, seen = {}, {}
        for _, option in ipairs(resolved or {}) do
            if type(option)=="table" then
            local key = tostring(option.kind or option.source or "external")
            local token = key .. "|" .. tostring(option.characterKey or "") .. "|" .. tostring(option.professionKey or "")
            if not seen[token] then
                seen[token] = true
                options[#options+1] = {
                    key=key,
                    source=option.source or key,
                    label=option.label or key,
                    currentAccessible=option.currentAccessible,
                    requiresRetrieve=option.requiresRetrieve,
                    requiresTransfer=option.requiresTransfer,
                    characterKey=option.characterKey,
                    characterName=option.characterName,
                    freshness=option.freshness,
                    confidence=option.confidence,
                    updatedAt=option.updatedAt,
                    realm=option.realm,
                    count=option.count,
                    professionKey=option.professionKey,
                    professionLearned=option.professionLearned,
                    eligible=option.eligible,
                    availabilityState=option.availabilityState,
                    reason=option.reason,
                    recipeID=option.recipeID,recipeLearned=option.recipeLearned,
                    materials=option.materials,outputPerCraft=option.outputPerCraft,
                    price=option.price,snapshotKey=option.snapshotKey,
                    requiresManualVerification=option.requiresManualVerification,
                    observedOutputCredit=option.observedOutputCredit,
                }
            end
            end
        end
        return options
    end
    return {}
end

local function sourceOptions(row, plan)
    local options = catalogOptions(row.itemID, row.name, row.source, row.storage)
    -- Preserve recipe-specific craft context ahead of the generic source list.
    if (row.source == "crafted" or row.source == "craft") and row.craftedRecipe then
        table.insert(options, 1, {key="craft-recipe",source="craft",label="Craft via "..tostring(row.craftedRecipe.recipe or row.name or "intermediate")})
    elseif (row.source == "crafted" or row.source == "craft") and row.craftedFrom then
        local rawName = row.craftedFrom.name or ("Item " .. tostring(row.craftedFrom.itemID or "?"))
        local rawNeed = safeNumber(row.craftedFrom.required)
        table.insert(options, 1, {key="craft-recipe",source="craft",label="Craft from "..tostring(rawName)..(rawNeed > 0 and (" x"..tostring(rawNeed)) or "")})
    end
    return options
end

local function rawOptions(raw, plan)
    local def = datasetMaterial(plan, raw.itemID)
    return catalogOptions(raw.itemID, raw.name, def and def.source or "auction", raw.storage)
end

local function optionText(options)
    local parts = {}
    for _, option in ipairs(options or {}) do parts[#parts + 1] = tostring(option.label) end
    return table.concat(parts, "  |  ")
end

local function buildCraftTree(node, plan, depth, active)
    if type(node) ~= "table" then return nil end
    depth = tonumber(depth) or 0
    if depth > 12 then return { status="max-recursion-depth", resolved=false, materials={} } end
    local token = tostring(node.producerStepIndex or node.recipe or node.name or depth)
    active = active or {}
    if active[token] then return { status="dependency-cycle", resolved=false, materials={} } end
    active[token] = true
    local out = {
        contract = node.contract,
        itemID = node.itemID,
        name = node.name,
        recipe = node.recipe,
        recipeID = node.recipeID,
        producerStepIndex = node.producerStepIndex,
        outputPerCraft = safeNumber(node.outputPerCraft),
        outputNeeded = safeNumber(node.outputNeeded),
        craftsNeeded = safeNumber(node.craftsNeeded),
        producedOutput = safeNumber(node.producedOutput),
        yieldStatus = node.yieldStatus,
        resolved = node.resolved ~= false,
        observedOutputCredit=node.observedOutputCredit,
        materials = {},
        readOnly = true,
    }
    for _, material in ipairs(node.materials or {}) do
        local row = {
            itemID = material.itemID,
            name = material.name or ("Item " .. tostring(material.itemID or "?")),
            source = material.source,
            perCraft = tonumber(material.perCraft) or 0,
            required = safeNumber(material.required),
            owned = safeNumber(material.owned),
            missing = safeNumber(material.missing),
            storage = material.storage or {},
            relation = material.relation,
            producerStepIndex = material.producerStepIndex,
        }
        if material.inventoryKnown==false then
            row.inventoryKnown=false;row.owned=nil;row.missing=nil
        end
        row.options = sourceOptions(row, plan)
        row.optionsText = optionText(row.options)
        if material.craftedRecipe then
            row.craftedRecipe = buildCraftTree(material.craftedRecipe, plan, depth + 1, active)
            if not row.craftedRecipe or row.craftedRecipe.resolved == false then out.resolved = false end
        end
        out.materials[#out.materials + 1] = row
    end
    active[token] = nil
    return out
end

function RequirementPlan:Build(key, plan)
    local planner = JLP:GetModule("Planner")
    plan = plan or (planner and planner:GetProfessionPlan(key))
    local model = {
        key = key,
        plan = plan,
        recipe = plan and plan.step and plan.step.recipe or nil,
        status = plan and plan.actionKind or "unavailable",
        rows = {},
        materialTypes = 0,
        missingTypes = 0,
        totalMissingUnits = 0,
    }
    local advisoryCraft=plan and plan.readOnly==true and plan.executionEligible==false and
        plan.step and plan.step.kind=="craft" and plan.recommendedCurrentStep and
        (plan.actionKind=="acquire" or plan.actionKind=="verify")
    if not plan or (plan.actionKind ~= "craft" and not advisoryCraft) then return model end

    for _, material in ipairs(plan.materials or {}) do
        local storage=material.storage
        if type(storage)~="table" and plan.readOnly==true then
            local inventory=JLP:GetModule("Inventory")
            storage=inventory and inventory.GetOwned and inventory:GetOwned(material.itemID)
        end
        local row = {
            itemID = material.itemID,
            name = material.name or ("Item " .. tostring(material.itemID or "?")),
            source = material.source,
            context = material.context,
            required = safeNumber(material.required or material.perCraft or material.quantity),
            owned = safeNumber(material.owned),
            missing = safeNumber(material.missing),
            storage = storage or {},
            craftedFrom = material.craftedFrom,
            craftedRecipe = material.craftedRecipe,
        }
        row.options = sourceOptions(row, plan)
        row.optionsText = optionText(row.options)
        local storage=row.storage
        local sources=JLP:GetModule("SourceResolver")
        local rod=sources and sources.GetOrdinaryRodAcquisition and sources:GetOrdinaryRodAcquisition(row.itemID,row.required)
        if rod then
            row.ordinaryRodAcquisition=rod
            if rod.selectedSource=="craft" and rod.craftedRecipe then row.craftedRecipe=rod.craftedRecipe end
        end
        local bagsKnown=storage.bagKnown==true and tonumber(storage.bags)~=nil
        local bankKnown=storage.bankKnown==true and tonumber(storage.bank)~=nil
        local bags=bagsKnown and safeNumber(storage.bags) or nil
        local bank=bankKnown and safeNumber(storage.bank) or nil
        row.availability={contract="jlp-material-availability-v2",required=row.required,
            bags=bags,bank=bank,unknownBags=not bagsKnown,unknownBank=not bankKnown,
            knownOwned=(bags or 0)+(bank or 0),
            needed=(bagsKnown and bankKnown) and math.max(0,row.required-bags-bank) or nil,
            minimumExternal=math.max(0,row.required-(bags or 0)-(bank or 0)),
            sourceCount=#row.options,sourceStatus=#row.options>0 and "SOURCE_LISTED_ADVISORY" or "SOURCE_UNVERIFIED",
            sourceFreshness=(row.options[1] and row.options[1].freshness) or "UNKNOWN",
            readOnly=true,nativeDispatchAllowed=false}
        -- The next material action is advisory; no quote, purchase, withdrawal
        -- or protected native crafting can be inferred from this UI field.
        local a=row.availability
        if a.unknownBags then
            a.nextManualAction="Check bag quantities manually"
        elseif a.unknownBank then
            a.nextManualAction="Check current-character bank manually"
        elseif a.needed and a.needed>0 then
            a.nextManualAction=a.sourceCount>0 and "Review listed sources; verify price and access manually" or
                "Identify a material source manually"
        else
            a.nextManualAction="Verify recipe, tools and station readiness"
        end
        a.sourceConfidence=(row.options[1] and row.options[1].confidence) or "UNVERIFIED"
        if row.craftedRecipe then
            row.craftTree = buildCraftTree(row.craftedRecipe, plan, 1, {})
        end
        if row.craftedFrom then
            local raw = row.craftedFrom
            row.raw = {
                itemID = raw.itemID,
                name = raw.name or ("Item " .. tostring(raw.itemID or "?")),
                required = safeNumber(raw.required),
                owned = safeNumber(raw.owned),
                missing = safeNumber(raw.missing),
                storage = raw.storage or {},
            }
            row.raw.options = rawOptions(row.raw, plan)
            row.raw.optionsText = optionText(row.raw.options)
        end
        model.rows[#model.rows + 1] = row
        model.materialTypes = model.materialTypes + 1
        if row.missing > 0 then
            model.missingTypes = model.missingTypes + 1
            model.totalMissingUnits = model.totalMissingUnits + row.missing
        end
    end
    -- Sidecar communication only; the current Guide plan never inherits
    -- acquisition prices, purchase permissions or execution readiness.
    local economy=JLP:GetModule("EconomyIntegration70450")
    local step=plan and plan.step
    local spellID=step and (step.recipeID or step.spellID)
    if type(economy)=="table" and type(economy.GetRecipePlan)=="function" and
       type(spellID)=="number" and spellID>0 and spellID==math.floor(spellID) then
        local ok,receipt=pcall(economy.GetRecipePlan,economy,key,spellID,1,70450)
        if ok and type(receipt)=="table" and receipt.readOnly==true and
            receipt.nativeDispatchAllowed==false then
            model.economy70450={status=receipt.status,spellID=spellID,
                priceState=receipt.priceState,materialTypes=receipt.materialTypes,
                totalExternalRequired=receipt.totalExternalRequired,
                totalCostEstimate=receipt.totalCostEstimate,
                readOnly=true,nativeDispatchAllowed=false}
        end
    end
    local sourceResolver=JLP:GetModule("SourceResolver")
    for _,row in ipairs(model.rows or {})do
        local vendors=sourceResolver and sourceResolver.GetMaterialVendorSources and
            sourceResolver:GetMaterialVendorSources(key,row.itemID) or {}
        if #vendors>0 then
            row.vendorCandidates=vendors -- static references, never current offers
            local vendorOption
            for _,o in ipairs(row.options or {})do if o.source=="vendor" then vendorOption=o;break end end
            if not vendorOption then
                vendorOption={key="vendor",source="vendor",readOnly=true,nativeDispatchAllowed=false}
                row.options=row.options or {};row.options[#row.options+1]=vendorOption
            end
            vendorOption.label="Verify supplier: "..vendors[1].name
            vendorOption.sourceInfo=vendors[1];vendorOption.candidates=vendors
            vendorOption.eligible=false;vendorOption.currentAccessible=false
            vendorOption.availabilityState="REFERENCE_ONLY";vendorOption.requiresManualVerification=true
        end
    end
    return model
end

-- Read-only, per-current-step qualification; never determines execution authority.
-- Unknown storage is not silently counted as zero available or as a firm deficit.
function RequirementPlan:ExplainAvailability(model)
    local summary={contract="jlp-requirement-availability-v2",readOnly=true,
        nativeDispatchAllowed=false,types=0,required=0,bags=0,bankKnown=0,
        externalKnown=0,unknownBankTypes=0,unknownBagTypes=0,sourceUnknown=0}
    for _,row in ipairs(type(model)=="table" and model.rows or {}) do
        local a=row.availability
        if type(a)~="table" then
            local storage=type(row.storage)=="table" and row.storage or {}
            local bagsKnown=storage.bagKnown==true and tonumber(storage.bags)~=nil
            local bankKnown=storage.bankKnown==true and tonumber(storage.bank)~=nil
            local bags=bagsKnown and safeNumber(storage.bags) or nil
            local bank=bankKnown and safeNumber(storage.bank) or nil
            a={bags=bags,bank=bank,unknownBags=not bagsKnown,unknownBank=not bankKnown,
                needed=bagsKnown and bankKnown and math.max(0,safeNumber(row.required)-bags-bank) or nil}
        end
        summary.types=summary.types+1;summary.required=summary.required+safeNumber(row.required)
        if a.unknownBags then summary.unknownBagTypes=summary.unknownBagTypes+1
        else summary.bags=summary.bags+safeNumber(a.bags) end
        if a.unknownBank then summary.unknownBankTypes=summary.unknownBankTypes+1
        else summary.bankKnown=summary.bankKnown+safeNumber(a.bank) end
        if a.needed then summary.externalKnown=summary.externalKnown+a.needed end
        if not row.options or #row.options==0 then summary.sourceUnknown=summary.sourceUnknown+1 end
    end
    summary.qualified=summary.unknownBagTypes==0 and summary.unknownBankTypes==0
    return summary
end
function RequirementPlan:NextSafeAction(model)
    local q=self:ExplainAvailability(model)
    local action="REVIEW_PLAN"
    local text="Review the current profession step; no automatic crafting action is authorized."
    if q.types==0 then action="REVIEW_RECIPE";text="No craft materials are available for this step; review the trainer or recipe."
    elseif q.unknownBagTypes>0 then action="CHECK_BAGS";text="Inspect your bags to verify quantities before estimating purchases."
    elseif q.unknownBankTypes>0 then action="CHECK_BANK";text="Open the current character's bank manually to verify unknown quantities."
    elseif q.externalKnown>0 then
        local resolver=JLP:GetModule("PriceResolver")
        local quote=nil
        if type(resolver)=="table" and type(resolver.QualifySnapshot)=="function" then
            local ok,result=pcall(resolver.QualifySnapshot,resolver)
            if ok and type(result)=="table" then quote=result end
        end
        if not quote or not quote.trustedForCostEstimate then
            action="SCAN_AH_MANUALLY";text="Review gathering/vendor sources or manually refresh a scope-verified complete Auction House scan."
        else action="REVIEW_SOURCES";text="Review qualified material sources and availability before any manual acquisition." end
    else action="REVIEW_READINESS";text="Materials appear sufficient; verify trainer, recipe, tool and station readiness before crafting." end
    return {contract="jlp-next-safe-material-action-v1",code=action,text=text,
        readOnly=true,nativeDispatchAllowed=false,eligibleForNative=false,
        qualified=q.qualified}
end
function RequirementPlan:FormatAvailability(model)
    local q=self:ExplainAvailability(model)
    if q.types==0 then return "Material quantities unavailable",q end
    local bags=q.unknownBagTypes>0 and (q.bags.." verified + unknown") or tostring(q.bags)
    local bank=q.unknownBankTypes>0 and (q.bankKnown.." verified + unknown") or tostring(q.bankKnown)
    local missing=q.qualified and ("External need "..q.externalKnown) or "External need unknown (unverified)"
    local sources=q.sourceUnknown>0 and (" | "..q.sourceUnknown.." source(s) unverified") or ""
    return "Required "..q.required.." | Bags "..bags.." | Bank "..bank.." | "..missing..sources,q
end
JLP:RegisterModule("RequirementPlan", RequirementPlan)
