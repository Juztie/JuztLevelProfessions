local _, JLP = ...

local function prerequisiteAcquisition(key)
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

local AcquisitionPlanner = {}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function activeAcquisitionKeys()
    local reg=registry()
    local workspace=JLP:GetModule("ProfessionWorkspace")
    local out, excluded={},{}
    local primary=workspace and workspace:GetPrimaryLearned() or {}
    for _,profession in ipairs(primary) do
        if type(profession)=="table" and profession.key then
            if reg and reg:HasCapability(profession.key,"acquisition") then
                out[#out+1]=profession.key
            else
                excluded[#excluded+1]=profession.key
            end
        end
    end
    local api=JLP:GetModule("ProfessionAPI")
    for _,profession in ipairs(api and api.GetSecondaryProfessions and api:GetSecondaryProfessions() or {})do
        if (profession.key=="FIRST_AID" or profession.key=="COOKING") and reg and reg:HasCapability(profession.key,"acquisition")then out[#out+1]=profession.key end
    end
    return out, excluded, #primary
end

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

local function itemName(itemID, fallback)
    local catalog=JLP:GetModule("MaterialCatalog")
    return catalog and catalog:GetName(itemID,fallback) or fallback or ("Item "..tostring(itemID))
end

local function addReason(row, reason)
    if not reason or reason == "" then return end
    row.reasons = row.reasons or {}
    for _, existing in ipairs(row.reasons) do
        if existing == reason then return end
    end
    row.reasons[#row.reasons + 1] = reason
end

local function addNeed(map, itemID, name, source, quantity, reason)
    quantity = tonumber(quantity) or 0
    if not itemID or quantity <= 0 then return end
    local row = map[itemID]
    if not row then
        row = {
            itemID = itemID,
            name = name or ("Item " .. tostring(itemID)),
            source = source or "auction",
            required = 0,
            reasons = {},
        }
        map[itemID] = row
    end
    row.required = row.required + quantity
    -- Prefer vendor when the same reagent is explicitly vendor-sourced.
    if source == "vendor" then row.source = "vendor" end
    addReason(row, reason)
end

local function addCraftedNeed(map, material, quantity, reason)
    quantity = tonumber(quantity) or 0
    if quantity <= 0 then return end
    local row = map[material.itemID]
    if not row then
        row = {
            itemID = material.itemID,
            name = material.name,
            required = 0,
            craftedFrom = material.craftedFrom,
            reasons = {},
        }
        map[material.itemID] = row
    end
    row.required = row.required + quantity
    addReason(row, reason)
end

local function collectMaterial(baseNeeds, craftedNeeds, material, quantity, reason)
    quantity = tonumber(quantity) or 0
    if quantity <= 0 or not material then return end
    if material.craftedFrom then
        addCraftedNeed(craftedNeeds, material, quantity, reason)
    else
        addNeed(baseNeeds, material.itemID, material.name, material.source, quantity, reason)
    end
end

local function collectStepNeeds(baseNeeds, craftedNeeds, actions, key, professionName, step, seenTools)
    if not step or step.kind ~= "craft" then return end
    local crafts = tonumber(step.remainingCrafts) or 0
    if crafts <= 0 then return end
    local reason = tostring(professionName or key or step.profession or "Profession") .. ": " .. tostring(step.recipe or "route step")

    local sourceResolver = JLP:GetModule("SourceResolver")
    -- Attempt qualified typed catalogue acquisition first, but preserve the
    -- historical name-based advisory route for unqualified IDs. Neither grants
    -- a vendor/learned/stock entitlement or native execution permission.
    local typedSource=sourceResolver and type(step.recipeID or step.spellID)=="number" and
        sourceResolver:GetRecipeSource(key,step.recipeID or step.spellID) or nil
    local sourceInfo=typedSource or step.sourceInfo or
        (sourceResolver and sourceResolver:GetRecipeSource(key,step.recipe))
    actions[#actions + 1] = {
        kind = "profession-step",
        profession = key,
        name = string.format(step.planningEstimateQualified and "Scenario: %s x%d toward skill %d; recheck actual skill" or
            "Craft %s x%d to skill %d", tostring(step.recipe or "recommended recipe"), crafts, tonumber(step.skillTarget) or 0),
        estimated=step.planningEstimateQualified==true,
        craftCountQualified=step.craftCountQualified,
        recipe = step.recipe,
        crafts = crafts,
        skillTarget = step.skillTarget,
        requiredSkill = tonumber(step.skill) or tonumber(step.rawStep and step.rawStep.skillMin) or 0,
        sourceInfo = sourceInfo,
        catalogueAcquisitionQualified=typedSource~=nil,
        catalogueAcquisitionStatus=typedSource and "SOURCE_QUALIFIED" or "UNKNOWN",
        sourceText = sourceInfo and sourceResolver and sourceResolver:Format(sourceInfo, false) or nil,
    }

    -- One explicitly selected station preparation is independent of the
    -- consumer cast count. Inventory is deducted once by buildRequirements.
    for _,material in ipairs(step.stationPreparation and step.stationPreparation.materials or {})do
        collectMaterial(baseNeeds,craftedNeeds,material,material.required or material.quantity,reason..": selected station preparation")
    end
    for _, material in ipairs(step.materials or {}) do
        collectMaterial(baseNeeds, craftedNeeds, material, (tonumber(material.quantity) or 0) * crafts, reason)
    end

    local tool = tostring(key or "") == "ENCHANTING" and step.requiredTool
    local resolvedTool = nil
    local toolSatisfied = false
    if tool and tostring(key or "") == "ENCHANTING" then
        local resolver = JLP:GetModule("EnchantingToolResolver")
        if resolver and resolver.IsSatisfied then
            toolSatisfied, resolvedTool = resolver:IsSatisfied(tool, false)
        end
    end
    if tool and toolSatisfied then
        if resolvedTool and resolvedTool.status == "bank" then
            actions[#actions + 1] = {
                kind = "retrieve-tool",
                name = "Retrieve " .. tostring(resolvedTool.name or tool.name or "required tool") .. " from the bank.",
                quantity = 1,
                itemID = resolvedTool.itemID,
                profession = key,
                satisfiesToolItemID = tool.itemID,
                toolSatisfaction = resolvedTool.satisfaction,
            }
        end
    elseif tool and getItemCount(tool.itemID) <= 0 and not (seenTools and seenTools[tool.itemID]) then
        if seenTools then seenTools[tool.itemID] = true end
        actions[#actions + 1] = {
            kind = "craft-tool",
            name = "Craft " .. tostring(tool.name or "required tool"),
            quantity = 1,
            profession = key,
        }
        for _, material in ipairs(tool.materials or {}) do
            collectMaterial(baseNeeds, craftedNeeds, material, tonumber(material.quantity) or 0, "Tool: " .. tostring(tool.name or "required tool"))
        end
    end
end

local function expandCraftedNeeds(baseNeeds, craftedNeeds, actions)
    for _, row in pairs(craftedNeeds) do
        local owned = getItemCount(row.itemID)
        local missing = math.max(0, (tonumber(row.required) or 0) - owned)
        if row.craftedFrom and (row.craftedFrom.sourceQualificationContract=="linen-2963-client-schematic-70532-v1" or row.craftedFrom.sourceQualificationContract=="wool-2964-client-schematic-70532-v1" or row.craftedFrom.sourceQualificationContract=="cloth-user-output-db2-70532-v1") then
            local inventory=JLP:GetModule("Inventory")
            local quantities=JLP:GetModule("AcquisitionQuantities")
            local storage=inventory and inventory.GetOwned and inventory:GetOwned(row.itemID)
            local quantity=quantities and quantities.Compute and quantities:Compute(row.required,storage)
            local covered=quantity and quantity.bagKnown and quantity.immediateMissing==0
            if quantity and (quantity.inventoryKnown or covered) then
                missing=covered and 0 or quantity.externalRequired
                row.inventoryUnknownForConversion=false
            else
                -- Keep the finished-bolt requirement UNKNOWN instead of
                -- manufacturing a definite raw-cloth shortage from absent stock.
                row.inventoryUnknownForConversion=true
                addNeed(baseNeeds,row.itemID,row.name,"crafted",row.required,"Verify Bolt inventory before raw conversion")
                missing=nil
            end
        end
        if missing and missing > 0 and row.craftedFrom then
            if not row.intermediateAction then
                row.intermediateAction={
                kind = "craft-intermediate",
                name = "Craft " .. tostring(row.name),
                quantity = missing,
                itemID = row.itemID,
                producerRecipeID=row.craftedFrom.producerRecipeID,
                quantityAuthority=row.craftedFrom.authority,
                verifyLearningRequired=true,readOnly=true,nativeDispatchAllowed=false,
                }
                actions[#actions+1]=row.intermediateAction
            else row.intermediateAction.quantity=missing end
            addNeed(
                baseNeeds,
                row.craftedFrom.itemID,
                itemName(row.craftedFrom.itemID, "Raw material for " .. tostring(row.name)),
                "auction",
                math.max(0,missing-(row.expandedQuantity or 0)) * (tonumber(row.craftedFrom.quantity) or 0),
                "Craft " .. tostring(row.name)
            )
            row.expandedQuantity=missing
        end
    end
end

local function addCandidateRequirements(baseNeeds, craftedNeeds, quote, reason)
    if not quote then return end
    if type(quote.materials)=="table" then
        for _,row in ipairs(quote.materials) do collectMaterial(baseNeeds,craftedNeeds,row.material,row.required,reason) end
        return
    end
    for _, row in ipairs(quote.breakdown or {}) do
        addNeed(baseNeeds, row.itemID, row.name, row.source, tonumber(row.required) or 0, reason)
    end
end

-- Price information must have explicit coverage. An accumulator initialized to
-- zero is not evidence of a zero-copper quote. This is advisory only.
local function finiteNonnegative(value)
    if type(value)~="number" or value~=value or value==math.huge or
        value==-math.huge or value<0 then return nil end
    return value
end

-- One qualification boundary for every new AcquisitionPlanner cost consumer.
-- Older injected/pre-provenance plans remain unverified and never gain authority.
function AcquisitionPlanner:QualifyCost(plan, snapshotQualification)
    if type(plan)~="table" then return {status="UNKNOWN", readOnly=true} end
    local knowledge=plan.costKnowledge
    local amount=finiteNonnegative(plan.totalKnownCost)
    if type(knowledge)~="table" then
        return {status=amount and amount>0 and "UNVERIFIED" or "UNKNOWN",
            amount=amount and amount>0 and amount or nil,
            readOnly=true, trustedForCostEstimate=false, legacy=true}
    end
    if plan.routeCoverageIncomplete==true or
        (knowledge.routeCoverageGapCount and knowledge.routeCoverageGapCount>0) or
        (knowledge.routeCoverageIssueCount and knowledge.routeCoverageIssueCount>0) then
        return {status="ROUTE_INCOMPLETE",readOnly=true,
            routeCoverageGapCount=knowledge.routeCoverageGapCount or 0,
            routeCoverageIssueCount=knowledge.routeCoverageIssueCount or 0,
            trustedForCostEstimate=false}
    end
    local priced=finiteNonnegative(knowledge.pricedQuantity)
    local needed=finiteNonnegative(knowledge.requiredQuantity)
    local unpriced=finiteNonnegative(knowledge.unpricedQuantity)
    local coveredCost=finiteNonnegative(knowledge.knownCost)
    local coverage=finiteNonnegative(knowledge.knownPriceCoverage)
    -- Both nil == nil and a fractional item count can otherwise qualify a
    -- malformed receipt as trusted. Every cost requires numeric provenance.
    if amount==nil or coveredCost==nil or not priced or not needed or not unpriced or
        priced~=math.floor(priced) or needed~=math.floor(needed) or
        unpriced~=math.floor(unpriced) or priced+unpriced~=needed or
        coveredCost~=amount or coverage==nil or coverage>1 or
        coverage~=(needed>0 and priced/needed or 1) or
        (needed>0 and priced==0) then
        return {status="UNKNOWN", readOnly=true, trustedForCostEstimate=false}
    end
    if needed==0 then
        return {status="NO_NEEDS", readOnly=true, trustedForCostEstimate=false}
    end
    if knowledge.selfFoundExceptionsPending and knowledge.selfFoundExceptionsPending>0 then
        return {status="EXCEPTION_PENDING",amount=amount,readOnly=true,
            exceptionCount=knowledge.selfFoundExceptionsPending,
            trustedForCostEstimate=false}
    end
    if unpriced>0 then
        return {status="PARTIAL", amount=amount, readOnly=true,
            pricedQuantity=priced, requiredQuantity=needed, trustedForCostEstimate=false}
    end
    local trusted=type(snapshotQualification)=="table" and
        snapshotQualification.trustedForCostEstimate==true and plan.complete==true and
        knowledge.hasAuctionPrice==true and
        knowledge.hasUnverifiedVendorPrice~=true and
        knowledge.stockQualified==true and
        type(knowledge.snapshotKey)=="string" and knowledge.snapshotKey~="" and
        type(snapshotQualification.snapshotKey)=="string" and
        knowledge.snapshotKey==snapshotQualification.snapshotKey and
        knowledge.snapshotConflict~=true
    -- Validate the SAME priced items, not merely a scan-ID shared by a new
    -- or mutated table. Legacy receipts without bounded item proofs cannot
    -- become TRUSTED. This loops over priced plan rows; each lookup is O(B).
    if trusted then
        local resolver=JLP:GetModule("PriceResolver")
        local receipts=knowledge.itemPriceReceipts
        if type(resolver)~="table" or type(resolver.ItemPriceReceiptMatches)~="function" or
            type(receipts)~="table" or #receipts~=knowledge.auctionPricedRows or
            #receipts==0 then
            trusted=false
        else
            for _,entry in ipairs(receipts) do
                if type(entry)~="table" or type(entry.itemID)~="number" or
                    type(entry.receipt)~="string" then
                    trusted=false; break
                end
                local ok,matches=pcall(resolver.ItemPriceReceiptMatches,resolver,entry.itemID,entry.receipt)
                if not ok or matches~=true then trusted=false; break end
            end
        end
    end
    return {status=trusted and "TRUSTED" or "UNVERIFIED", amount=amount,
        pricedQuantity=priced, requiredQuantity=needed, readOnly=true,
        trustedForCostEstimate=trusted == true}
end

local function sortRows(rows)
    local order = { vendor=1, auction=2, unresolved=3 }
    table.sort(rows, function(a,b)
        local ao, bo = order[a.source] or 9, order[b.source] or 9
        if ao ~= bo then return ao < bo end
        return tostring(a.name) < tostring(b.name)
    end)
end

local function buildRequirements(baseNeeds, craftedNeeds)
    local rows = {}
    local inventory = JLP:GetModule("Inventory")
    local function append(need, kind)
        local storage = inventory and inventory:GetOwned(need.itemID) or { bags=getItemCount(need.itemID), bank=0, total=getItemCount(need.itemID), bankKnown=false }
        local required=tonumber(need.required) or 0
        local name=need.name or itemName(need.itemID)
        local source=need.source or (kind == "crafted" and "crafted" or "auction")
        local catalog=JLP:GetModule("MaterialCatalog")
        local options=catalog and catalog:GetAcquisitionOptions(need.itemID,name,source,storage) or {}
        local quant=JLP:GetModule("AcquisitionQuantities")
        local quantity=quant and quant:Compute(required,storage) or nil
        local bagCovered=quantity and quantity.bagKnown and quantity.immediateMissing==0
        local known=quantity and quantity.inventoryKnown==true or bagCovered
        rows[#rows + 1] = {
            itemID = need.itemID,
            name = name,
            source = source,
            required = required,
            owned = known and ((quantity.bagsAvailable or 0)+(quantity.currentBankAvailable or 0)) or nil,
            missing = bagCovered and 0 or (quantity and quantity.externalRequired or nil),
            inventoryKnown=quantity and quantity.inventoryKnown==true or false,
            inventoryState=bagCovered and "BAGS_COVER_DEMAND" or known and "KNOWN" or "UNKNOWN",
            storage = storage,
            kind = kind,
            reasons = need.reasons,
            options = options,
            optionsText = catalog and catalog:FormatOptions(options) or "",
        }
    end
    for _, need in pairs(baseNeeds or {}) do append(need, "base") end
    for _, need in pairs(craftedNeeds or {}) do
        if not need.inventoryUnknownForConversion then append(need, "crafted") end
    end
    table.sort(rows, function(a,b) return tostring(a.name) < tostring(b.name) end)
    return rows
end

local function normalizeScope(scope)
    if scope == "next_trainer" or scope == "to_300" then return scope end
    return "current"
end

local function scopeLabel(scope)
    scope = normalizeScope(scope)
    if scope == "next_trainer" then return "To Next Trainer" end
    if scope == "to_300" then return "To 300" end
    return "Current Segment"
end

function AcquisitionPlanner:GetSelectedScope()
    local profile=JLP.DB and JLP.DB.profile
    return normalizeScope(type(profile)=="table" and profile.shoppingScope or nil)
end

function AcquisitionPlanner:SetSelectedScope(scope)
    scope = normalizeScope(scope)
    -- A missing/incomplete profile cannot persist a preference. Never report
    -- success or create a replacement SavedVariable implicitly.
    local profile=JLP.DB and JLP.DB.profile
    if type(profile)~="table" then return nil,"profile-unavailable" end
    profile.shoppingScope=scope
    if self:GetSelectedScope()~=scope then return nil,"scope-not-persisted" end
    return scope
end

local function allocateAltBank(itemID,name,missing,actions,reason)
    missing=math.max(0,math.floor(tonumber(missing) or 0))
    if missing<=0 then return 0,{} end
    local inventory=JLP:GetModule("Inventory")
    local allocated={}
    for _,alt in ipairs(inventory and inventory.GetAltBankAvailability and inventory:GetAltBankAvailability(itemID,{sameRealm=true}) or {}) do
        if missing<=0 then break end
        local take=math.min(missing,math.max(0,tonumber(alt.count) or 0))
        if take>0 then
            local row={kind="transfer-alt-bank",itemID=itemID,name=name,quantity=take,characterKey=alt.characterKey,characterName=alt.name,freshness=alt.freshness,updatedAt=alt.updatedAt,requiresTransfer=true,currentAccessible=false,reason=reason}
            actions[#actions+1]=row; allocated[#allocated+1]=row; missing=missing-take
        end
    end
    return missing,allocated
end

function AcquisitionPlanner:Build(scope, strategyOverride)
    scope = normalizeScope(scope or self:GetSelectedScope())
    local planner = JLP:GetModule("Planner")
    local optimizer = JLP:GetModule("CostOptimizer")
    local resolver = JLP:GetModule("PriceResolver")
    local api = JLP:GetModule("ProfessionAPI")
    local detected = api and api:GetDetected() or {}
    local strategy = strategyOverride or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"
    if strategy~="fastest" and strategy~="economical" and strategy~="self_found" then strategy="economical" end

    local baseNeeds, craftedNeeds, purchaseNeeds = {}, {}, {}
    local actions, decisions, professionPlans = {}, {}, {}
    local routeCoverageGaps,routeCoverageIssues,coverageEnvelopes={},{},{}
    local seenTools = {}
    local keys,excluded,primaryCount=activeAcquisitionKeys()
    local function unresolvedRoute(key,status,reason,profession,evidence)
        local issue={profession=key,status=status,reason=reason,readOnly=true,
            currentSkill=profession and tonumber(profession.skill) or nil,
            nextAction=evidence and evidence.nextAction or
                status=="NO_ACTIVE_PRIMARY_PROFESSION" and "Learn or select a Primary profession, then refresh the plan." or
                status=="PROFESSION_STATE_UNAVAILABLE" and "Refresh the character's profession skill and retry planning." or
                status=="ACQUISITION_CAPABILITY_UNAVAILABLE" and "Review this profession's supported planning capabilities." or
                "Review qualified profession data and available progression steps; refresh the plan.",
            nextActionCode=evidence and evidence.nextActionCode,
            datasetStatus=evidence and evidence.datasetStatus,
            coverageStatus=evidence and evidence.coverageStatus,
            routeQualification=evidence and evidence.routeQualification,
            strategyComparisonStatus=evidence and evidence.strategyComparisonStatus}
        routeCoverageIssues[#routeCoverageIssues+1]=issue
        actions[#actions+1]={kind="verify-route-coverage",profession=key,
            name="Verify profession progression: "..tostring(reason),reason=reason,
            status=status,source="unresolved",readOnly=true,nativeDispatchAllowed=false,
            nextAction=issue.nextAction}
    end
    if #keys==0 then
        unresolvedRoute(nil,"NO_ACTIVE_PRIMARY_PROFESSION","no-active-primary-profession")
    end
    for _,key in ipairs(excluded) do
        unresolvedRoute(key,"ACQUISITION_CAPABILITY_UNAVAILABLE","acquisition-capability-unavailable",detected[key])
    end
    for _, key in ipairs(keys) do
        local profession = detected[key]
        if not profession then
            unresolvedRoute(key,"PROFESSION_STATE_UNAVAILABLE","profession-state-unavailable")
        else
            local scopePlan = planner and planner:GetScopePlan(key, profession, scope, strategy)
            professionPlans[key] = scopePlan
            if type(scopePlan)=="table" and type(scopePlan.coverageEnvelope)=="table" then
                coverageEnvelopes[key]=scopePlan.coverageEnvelope
            end
            if type(scopePlan)~="table" then
                unresolvedRoute(key,"SCOPE_PLAN_UNAVAILABLE",planner and "scope-plan-unavailable" or "planner-unavailable",profession)
            else
                local evidence=coverageEnvelopes[key]
                -- Reached skill 300 is observed goal completion, independently
                -- of a missing historical/recipe dataset. It grants no route,
                -- procurement, or native authority; skip only false route issues.
                local goalComplete=evidence and evidence.coverageStatus=="COMPLETE" and
                    evidence.nextActionCode=="COMPLETE"
                if not goalComplete and scopePlan.routeCoverageComplete==false and
                    scopePlan.routeCoverageStatus~="COVERAGE_INCOMPLETE" then
                    unresolvedRoute(key,scopePlan.routeCoverageStatus or "SCOPE_PLAN_UNAVAILABLE",
                        scopePlan.routeCoverageReason or "scope-plan-unavailable",profession,evidence)
                elseif not goalComplete and evidence and scopePlan.routeCoverageComplete==true and
                    evidence.routeQualification~="QUALIFIED" and
                    evidence.routeQualification~="NOT_APPLICABLE" then
                    -- Interval coverage is not qualified recipe, cost or quantity
                    -- coverage. This issue prevents an empty shopping list from
                    -- becoming false completion or a zero-material budget.
                    unresolvedRoute(key,"ROUTE_EVIDENCE_UNVERIFIED",
                        evidence.recipeEvidenceStatus or evidence.datasetStatus,profession,evidence)
                end
                -- Preserve missing 1-300 route intervals. They are not purchasable
                -- material needs and cannot be silently counted as completed.
                for _,gap in ipairs(not goalComplete and scopePlan.routeCoverageGaps or {}) do
                    local row={profession=key,fromSkill=gap.fromSkill,toSkill=gap.toSkill,
                        reason=gap.reason or "NO_QUALIFIED_ROUTE_STEP",readOnly=true,
                        nextAction=evidence and evidence.nextAction or
                            "Verify qualified progression steps for this skill interval."}
                    routeCoverageGaps[#routeCoverageGaps+1]=row
                    actions[#actions+1]={kind="verify-route-coverage",profession=key,
                        name=string.format("Verify %s progression %d-%d: no qualified route step.",
                            tostring(key),tonumber(gap.fromSkill) or 0,tonumber(gap.toSkill) or 0),
                        fromSkill=gap.fromSkill,toSkill=gap.toSkill,source="unresolved",
                        readOnly=true,nativeDispatchAllowed=false}
                end
                -- Build a progression timeline per profession. Trainer gates are inserted
                -- before route segments that start at the newly unlocked cap; this keeps
                -- source routing dependency-safe while still allowing the route layer to
                -- interleave independent profession stops for travel efficiency.
                local events = {}
                for _, step in ipairs(scopePlan.segments or {}) do
                    events[#events + 1] = {
                        kind = "step",
                        atSkill = tonumber(step.skill) or tonumber(step.rawStep and step.rawStep.skillMin) or 0,
                        priority = 1,
                        step = step,
                    }
                end
                for _, gate in ipairs(scopePlan.trainers or {}) do
                    events[#events + 1] = {
                        kind = "gate",
                        atSkill = tonumber(gate.cap) or 0,
                        priority = 0,
                        gate = gate,
                    }
                end
                table.sort(events, function(a,b)
                    if a.atSkill ~= b.atSkill then return a.atSkill < b.atSkill end
                    return a.priority < b.priority
                end)

                for _, event in ipairs(events) do
                    if event.kind == "step" then
                        collectStepNeeds(baseNeeds, craftedNeeds, actions, key, profession.name or key, event.step, seenTools)
                    else
                        local gate = event.gate
                        local sourceResolver = JLP:GetModule("SourceResolver")
                        local sourceInfo = sourceResolver and sourceResolver:GetTrainerForGate(key, gate) or nil
                        actions[#actions + 1] = {
                            kind = "train",
                            profession = key,
                            rank = gate.rank,
                            name = string.format("Train %s to unlock skill %d", tostring(gate.rank or "next profession rank"), tonumber(gate.nextCap) or 300),
                            skillCap = gate.cap,
                            nextCap = gate.nextCap,
                            requiredSkill = tonumber(gate.cap) or 0,
                            sourceInfo = sourceInfo,
                            sourceText = sourceInfo and sourceResolver and sourceResolver:Format(sourceInfo, false) or nil,
                        }
                    end
                end
            end
        end
    end

    expandCraftedNeeds(baseNeeds, craftedNeeds, actions)
    local generatedNeeds,reservedStock,decisionNeeds={},{},{}
    local function reserveStock()
        for itemID,need in pairs(baseNeeds) do
            reservedStock[itemID]=math.min(getItemCount(itemID),math.max(0,need.required-(generatedNeeds[itemID] or 0)))
        end
        for itemID,need in pairs(craftedNeeds) do reservedStock[itemID]=math.min(getItemCount(itemID),need.required) end
    end
    reserveStock()
    for _,need in pairs(baseNeeds) do decisionNeeds[#decisionNeeds+1]=need end
    table.sort(decisionNeeds,function(a,b) return a.itemID<b.itemID end)
    -- Decide transformations against already reserved ordinary stock. Keep
    -- every gross requirement, including fulfilled ones, until all chosen DE
    -- input graphs have been merged. Procurement then deducts each stock once.
    for _, need in ipairs(decisionNeeds) do
        local inventory = JLP:GetModule("Inventory")
        local storage = inventory and inventory:GetOwned(need.itemID) or { bags=getItemCount(need.itemID), bank=0, total=getItemCount(need.itemID), bankKnown=false }
        local owned = storage.total or 0
        local missing = math.max(0, (tonumber(need.required) or 0) - owned)
        if missing > 0 then
            local reasonText=table.concat(need.reasons or {}, "; ")
            -- Transfer suggestions are advisory. Cached alt-bank stock must not
            -- lower guaranteed procurement quantities without a live transfer.
            allocateAltBank(need.itemID,need.name,missing,actions,reasonText)
            if missing > 0 and need.source == "disenchant-or-auction" and optimizer then
                local comparison = optimizer:GetComparison(need.itemID, missing, strategy,{reservedStock=reservedStock})
                decisions[#decisions + 1] = comparison
                if comparison.recommended == "tailoring-disenchant" and comparison.tailoring then
                    local t = comparison.tailoring
                    actions[#actions + 1] = {
                        kind = "tailoring-disenchant",
                        name = string.format("Craft %s x%d, then disenchant", tostring(t.candidate.recipe), tonumber(t.crafts) or 0),
                        materialID = need.itemID,
                        crafts = t.crafts,
                        expected = t.expectedTotal,
                    }
                    generatedNeeds[need.itemID]=(generatedNeeds[need.itemID] or 0)+missing
                    addCandidateRequirements(baseNeeds,craftedNeeds,t.quote,"Tailor+DE for "..tostring(need.name))
                    expandCraftedNeeds(baseNeeds,craftedNeeds,actions)
                    reserveStock()
                end
            end
        end
    end
    local requirements=buildRequirements(baseNeeds,craftedNeeds)
    for _,need in pairs(baseNeeds) do
        local required=math.max(0,need.required-(generatedNeeds[need.itemID] or 0))
        addNeed(purchaseNeeds,need.itemID,need.name,need.source=="disenchant-or-auction" and "auction" or need.source,
            required,table.concat(need.reasons or {},"; "))
    end

    local shopping = {}
    local totalKnown = 0
    local routeIncomplete=(#routeCoverageGaps>0 or #routeCoverageIssues>0)
    local complete = not routeIncomplete
    local unresolved = #routeCoverageGaps+#routeCoverageIssues
    local requiredPriceQuantity, pricedQuantity, pricedRows = 0, 0, 0
    local selfFoundExceptionsPending = 0
    local hasAuctionPrice = false
    local hasUnverifiedVendorPrice = false
    local stockQualified = true
    local qualifiedSnapshotKey=nil
    local snapshotConflict=false
    local itemPriceReceipts={}
    local auctionPricedRows=0
    local unknownInventoryRows=0

    for _, need in pairs(purchaseNeeds) do
        local inventory = JLP:GetModule("Inventory")
        local storage = inventory and inventory:GetOwned(need.itemID) or { bags=getItemCount(need.itemID), bank=0, total=getItemCount(need.itemID), bankKnown=false }
        local owned = storage.total or 0
        -- Cached/generic bank counts are useful context, not currently
        -- verified procurement availability. Never certify a price on them.
        if storage.bagKnown~=true or storage.bankEvidence~="SAVED_ORDINARY_BANK_SNAPSHOT" or
            storage.bankOpenedAt==nil or
            type(storage.bankCacheUpdatedAt)~="number" or
            storage.bankCacheUpdatedAt<storage.bankOpenedAt then
            stockQualified=false
        end
        local missing = math.max(0, (tonumber(need.required) or 0) - owned)
        local quantities=JLP:GetModule("AcquisitionQuantities")
        local observed=quantities and quantities:Compute(need.required,storage) or nil
        local bagCovered=observed and observed.bagKnown and observed.immediateMissing==0
        if bagCovered then missing=0 end
        if observed and observed.inventoryKnown~=true and not bagCovered then
            -- UNKNOWN must not become a concrete shopping quantity or quote.
            unknownInventoryRows=unknownInventoryRows+1
            stockQualified=false;complete=false;unresolved=unresolved+1
            shopping[#shopping+1]={itemID=need.itemID,name=need.name,source=need.source,
                required=need.required,storage=storage,inventoryKnown=false,inventoryState="UNKNOWN",
                complete=false,priceKnown=false,pricedQuantity=0,
                note="Verify bag and bank quantities before computing a purchase need.",
                readOnly=true,nativeDispatchAllowed=false}
            actions[#actions+1]={kind="verify-inventory",itemID=need.itemID,
                name="Verify inventory for "..tostring(need.name),source="unresolved",
                readOnly=true,nativeDispatchAllowed=false}
        elseif missing > 0 then
            local row = {
                itemID = need.itemID,
                name = need.name,
                source = need.source,
                required = need.required,
                grossRequired = need.required,
                owned = owned,
                currentOwned = owned,
                bagsAvailable = tonumber(storage.bags) or 0,
                currentBankAvailable = tonumber(storage.bank) or 0,
                immediateMissing = math.max(0,(tonumber(need.required) or 0)-(tonumber(storage.bags) or 0)),
                preparedMissing = missing,
                externalRequired = missing,
                missing = missing,
                storage = storage,
                reasons = need.reasons,
                complete = true,
                cost = 0, -- historical numeric compatibility; row.priceKnown is authoritative
                priceKnown = false,
                pricedQuantity = 0,
            }
            local catalog=JLP:GetModule("MaterialCatalog")
            row.options=catalog and catalog:GetAcquisitionOptions(need.itemID,need.name,need.source,storage) or {}
            local advisory=0
            for _,option in ipairs(row.options) do
                if option.source=="alt-bank" then advisory=advisory+math.max(0,tonumber(option.count) or 0) end
            end
            local quant=JLP:GetModule("AcquisitionQuantities")
            if quant then
                local result=quant:Compute(need.required,storage,advisory)
                for field,value in pairs(result) do row[field]=value end
            else
                row.altBankAdvisory=math.min(missing,advisory)
                row.externalRequiredIfTransferred=math.max(0,missing-row.altBankAdvisory)
            end
            row.optionsText=catalog and catalog:FormatOptions(row.options) or ""
            requiredPriceQuantity=requiredPriceQuantity+missing
            if need.source == "vendor" then
                local unit = optimizer and optimizer:GetVendorUnitPrice(need.itemID)
                unit=finiteNonnegative(unit)
                local cost=unit and finiteNonnegative(unit*missing) or nil
                if cost then
                    row.unitPrice=unit
                    row.cost=cost
                    row.priceKnown=true
                    row.pricedQuantity=missing
                    row.priceEvidence="VENDOR_REFERENCE_PRICE_UNVERIFIED"
                    hasUnverifiedVendorPrice=true
                else
                    row.complete=false
                    row.note="Vendor price not yet modeled"
                end
            else
                local quote=nil
                if type(resolver)=="table" and type(resolver.GetFulfillmentCost)=="function" then
                    local ok,result=pcall(resolver.GetFulfillmentCost,resolver,need.itemID,missing)
                    if ok and type(result)=="table" then quote=result end
                end
                row.quote=quote
                row.purchasedQuantity=quote and quote.complete==true and quote.purchasedQuantity or nil
                row.excessQuantity=quote and quote.complete==true and quote.excessQuantity or nil
                row.purchaseSelection=quote and quote.selection or nil
                local qCost=quote and finiteNonnegative(quote.cost)
                local fulfilled=quote and finiteNonnegative(quote.fulfilled)
                local requested=quote and finiteNonnegative(quote.requested)
                -- A qualified snapshot and matching requested quantity are needed
                -- even to show a partial known sum. Non-finite/malformed results
                -- cannot manufacture zero-price evidence.
                local valid=quote and quote.trustedForCostEstimate==true and
                    qCost~=nil and fulfilled~=nil and requested==missing and
                    fulfilled<=missing and fulfilled==math.floor(fulfilled)
                if valid and fulfilled>0 then
                    row.priceKnown=true
                    row.pricedQuantity=fulfilled
                    row.cost=qCost
                    row.priceEvidence="QUALIFIED_AH_QUOTE"
                    hasAuctionPrice=true
                    auctionPricedRows=auctionPricedRows+1
                    if type(quote.itemPriceReceipt)=="string" and quote.itemPriceReceipt~="" then
                        itemPriceReceipts[#itemPriceReceipts+1]={itemID=need.itemID,receipt=quote.itemPriceReceipt}
                    end
                    local key=type(quote.snapshotKey)=="string" and quote.snapshotKey~="" and quote.snapshotKey or nil
                    if not key or (qualifiedSnapshotKey and qualifiedSnapshotKey~=key) then
                        snapshotConflict=true
                    elseif not qualifiedSnapshotKey then
                        qualifiedSnapshotKey=key
                    end
                end
                if not valid or quote.complete~=true or fulfilled~=missing then
                    row.complete=false
                    row.note=valid and string.format("AH fulfills %d/%d",fulfilled,missing) or
                        "No qualified AH snapshot price"
                end
            end
            -- An AH quote may remain visible as advisory price evidence, but
            -- its existence never counts as Self-found purchase consent.
            local sourcePolicy=optimizer and optimizer.ClassifyMaterialSource and
                optimizer:ClassifyMaterialSource(need.source,strategy) or nil
            if sourcePolicy and sourcePolicy.exceptionPending then
                selfFoundExceptionsPending=selfFoundExceptionsPending+1
                row.exceptionPending=true
                row.approvalGranted=false
                row.exceptionReason=sourcePolicy.reason
                row.complete=false
                row.note="Self-found: AH is not approved. Find a qualified non-AH source or request explicit user acceptance."
                actions[#actions+1]={kind="verify-self-found-source",itemID=need.itemID,
                    quantity=missing,source="unresolved",exceptionSource=need.source,
                    exceptionPending=true,approvalGranted=false,readOnly=true,
                    name="Verify a non-AH source for "..tostring(need.name).." x"..tostring(missing),
                    reason=sourcePolicy.reason}
            end
            if row.priceKnown then
                totalKnown=totalKnown+row.cost
                pricedQuantity=pricedQuantity+row.pricedQuantity
                pricedRows=pricedRows+1
            end
            if not row.complete then
                complete = false
                unresolved = unresolved + 1
            end
            shopping[#shopping + 1] = row
        end
    end

    sortRows(shopping)

    local economy=JLP:GetModule("EconomyIntegration70450")
    local currentStepEconomy70450={}
    if type(economy)=="table" and type(economy.GetCurrentStep)=="function" then
        for key in pairs(professionPlans) do
            local ok,receipt=pcall(economy.GetCurrentStep,economy,key,70450)
            if ok and type(receipt)=="table" then
                currentStepEconomy70450[key]={status=receipt.status,
                    spellID=receipt.spellID,sourceBuild=70450,
                    materialTypes=receipt.materialTypes,
                    externalKnown=receipt.externalKnown,priceState=receipt.priceState,
                    readOnly=true,nativeDispatchAllowed=false}
            end
        end
    end

    local scanner = JLP:GetModule("AuctionScanner")
    local snapshotAvailable=false
    if type(scanner)=="table" and type(scanner.GetSnapshot)=="function" then
        local ok,snapshot=pcall(scanner.GetSnapshot,scanner)
        snapshotAvailable=ok and type(snapshot)=="table"
    end
    local availableMoney=nil
    if type(GetMoney)=="function" then
        local ok,value=pcall(GetMoney)
        if ok then
            value=finiteNonnegative(value)
            if value and value==math.floor(value) and value<=9007199254740991 then availableMoney=value end
        end
    end
    local affordabilityStatus="UNKNOWN"
    if complete and requiredPriceQuantity==pricedQuantity and availableMoney~=nil then
        affordabilityStatus=availableMoney>=totalKnown and "AFFORDABLE" or "INSUFFICIENT_FUNDS"
    end
    return {
        scope = scope,
        scopeLabel = scopeLabel(scope),
        strategy = strategy,
        snapshotAvailable = snapshotAvailable,
        professionPlans = professionPlans,
        coverageEnvelopes=coverageEnvelopes,
        routeCoverageIncomplete=routeIncomplete,
        routeCoverageGaps=routeCoverageGaps,
        routeCoverageIssues=routeCoverageIssues,
        currentStepEconomy70450=currentStepEconomy70450,
        shopping = shopping,
        selfFoundExceptionsPending=selfFoundExceptionsPending,
        requirements = requirements,
        actions = actions,
        decisions = decisions,
        totalKnownCost = totalKnown, -- numeric backward compatibility, NOT price proof
        affordability={status=affordabilityStatus,availableMoney=availableMoney,
            knownCost=totalKnown,shortfall=affordabilityStatus=="INSUFFICIENT_FUNDS" and totalKnown-availableMoney or nil,
            observedAt=availableMoney~=nil and type(time)=="function" and time() or nil,
            readOnly=true,nativeDispatchAllowed=false},
        costKnowledge = {
            status=unknownInventoryRows>0 and "INVENTORY_UNKNOWN" or routeIncomplete and "ROUTE_INCOMPLETE" or
                selfFoundExceptionsPending>0 and "EXCEPTION_PENDING" or
                requiredPriceQuantity==0 and "NO_NEEDS" or
                pricedQuantity==0 and "UNKNOWN" or
                pricedQuantity<requiredPriceQuantity and "PARTIAL" or "COMPLETE",
            knownCost=totalKnown,
            pricedQuantity=pricedQuantity,
            requiredQuantity=requiredPriceQuantity,
            unpricedQuantity=requiredPriceQuantity-pricedQuantity,
            pricedRows=pricedRows,
            knownPriceCoverage=requiredPriceQuantity>0 and pricedQuantity/requiredPriceQuantity or 1,
            hasAuctionPrice=hasAuctionPrice,
            hasUnverifiedVendorPrice=hasUnverifiedVendorPrice,
            stockQualified=stockQualified,
            snapshotKey=not snapshotConflict and qualifiedSnapshotKey or nil,
            snapshotConflict=snapshotConflict,
            auctionPricedRows=auctionPricedRows,
            itemPriceReceipts=itemPriceReceipts,
            selfFoundExceptionsPending=selfFoundExceptionsPending,
            routeCoverageGapCount=#routeCoverageGaps,
            routeCoverageIssueCount=#routeCoverageIssues,
            readOnly=true, nativeDispatchAllowed=false,
        },
        complete = complete,
        unresolved = unresolved,
        evidence = "combined-scoped-acquisition-plan",
    }
end

-- Explicit non-procurement preview. Never append these candidates to
-- BuildReadOnlyForPlan actions; unqualified quantities cannot imply purchases.
function AcquisitionPlanner:GetPrivateResearchAcquisitionPreview(key,spellOrName,clientBuild)
    local resolver=JLP:GetModule("SourceResolver")
    if not resolver or type(resolver.GetPrivateResearchAcquisitionPreview)~="function" then
        return nil,"SOURCE_ADVISORY_UNAVAILABLE"
    end
    return resolver:GetPrivateResearchAcquisitionPreview(key,spellOrName,clientBuild)
end

-- The existing acquisition owner also projects vendor consumables/reusable
-- tools. This is not a second gathering target or an inventory reservation.
function AcquisitionPlanner:SelectMaterialService(key,itemID,required)
    local prerequisite=prerequisiteAcquisition(key)
    if prerequisite then return nil,prerequisite.terminalReason end
    local function count(n)return type(n)=="number" and n>=0 and n<math.huge and n==math.floor(n)end
    if not count(required) or required<1 then return nil end
    local inventory=JLP:GetModule("Inventory")
    local owned=inventory and inventory.GetOwned and inventory:GetOwned(itemID) or {}
    local bags=owned.bagKnown==true and count(owned.bags) and owned.bags or nil
    local bank=owned.bankKnown==true and not owned.bankStale and not owned.snapshotStale and
        count(owned.bank) and owned.bank or nil
    local resolver=JLP:GetModule("SourceResolver")
    local candidates=resolver and resolver.GetMaterialVendorSources and resolver:GetMaterialVendorSources(key,itemID) or {}
    -- Observed possessions need no vendor or production recipe. Keep unknown
    -- non-vendor sourcing with its existing caller; do not invent a supplier.
    if #candidates==0 and not (bags and (bags>=required or bank and bank>0)) then return nil end
    local result={contract="CURRENT_MATERIAL_SERVICE",consumerProfession=key,itemID=itemID,
        required=required,bags=bags,bank=bank,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,observedOutputCredit=0,candidates={}}
    if bags==nil then result.status="UNKNOWN_INVENTORY"
    elseif bags>=required then result.status="BAGS_READY";result.quantity=0
    elseif bank and bank>0 then result.status="BANK";result.quantity=math.min(required-bags,bank)
    elseif bank==nil then result.status="VERIFY_BANK"
    else
        result.quantity=required-bags;result.status="VERIFY_VENDOR"
        local evidence=JLP:GetModule("RecipeAccessEvidence")
        for _,source in ipairs(candidates)do
            local offer=evidence and evidence.GetMerchantPlanningHint and evidence:GetMerchantPlanningHint(itemID,source.npcID) or {status="UNKNOWN"}
            local negative=offer.recentUnavailable or offer.status=="OUT_OF_STOCK" or offer.status=="NOT_OFFERED" or offer.status=="INELIGIBLE"
            result.candidates[#result.candidates+1]={source=source,offer=offer,unavailable=negative==true}
            if not negative and (not result.source or offer.status=="AVAILABLE" and result.offer.status~="AVAILABLE")then
                result.source=source;result.offer=offer
            end
        end
        if not result.source then result.status="RECHECK_OR_ALTERNATIVE"
        elseif result.offer.status=="AVAILABLE" and evidence and evidence.GetMerchantPurchaseAdvice then
            result.purchase=evidence:GetMerchantPurchaseAdvice(itemID,result.source.npcID,result.quantity)
            result.status=result.purchase.status=="READY_MANUAL_PURCHASE" and "BUY_MANUALLY" or "VERIFY_VENDOR"
        end
    end
    result.sourceID=result.source and result.source.serviceID
    local label="item "..tostring(itemID)
    result.nextAction=(result.status=="UNKNOWN_INVENTORY" and "Observe bags before determining the shortage of "..label or
        result.status=="BAGS_READY" and "Materials observed in bags; return to the selected craft" or
        result.status=="BANK" and "Withdraw "..result.quantity.." observed bank "..label.." manually; recheck bags before buying" or
        result.status=="VERIFY_BANK" and "Check bank inventory before calculating a purchase for "..label or
        result.status=="RECHECK_OR_ALTERNATIVE" and "The inspected suppliers are unavailable; recheck stock/access or arrange qualified manual trade. Do not repeat the same trip" or
        result.status=="BUY_MANUALLY" and "Buy "..result.purchase.purchaseUnits.." purchase units ("..result.purchase.expectedItems.." items) of "..label.." manually; observe delivery in bags" or
        "Visit "..tostring(result.source and result.source.name).." and verify the current offer, purchase unit, stock, currency, funds and usability for "..label.."; known shortage "..tostring(result.quantity).." items")..
        ". Purchase intent, arrival and price are not material receipts."
    return result
end
function AcquisitionPlanner:ApplyServiceToStep(key,current)
    if type(current)~="table" then return current end
    local pattern=current.patternAcquisition
    -- An owned pattern no longer needs the vendor visibility prerequisite.
    local ownedMagnusPattern=pattern and pattern.vendorAccess and
        (pattern.status=="RETRIEVE_PATTERN_FROM_BANK" or pattern.patternPossession=="BAGS_OBSERVED" or pattern.patternPossession=="BANK_OBSERVED")
    local access=current.learned==false and pattern and not ownedMagnusPattern and pattern.accessNote
    if type(access)=="string" and type(current.nextAction)=="string" and not current.nextAction:find(access,1,true)then
        current.nextAction=current.nextAction.." Access: "..access
    end
    if current.learned==false and current.patternAcquisition and current.patternAcquisition.status=="VERIFY_DROP_OR_TRADE_ACCESS" then
        local resolver=JLP:GetModule("SourceResolver")
        local source=resolver and resolver:GetRecipeSource(key,current.recipeID)
        if source and source.kind=="drop"then
            current.nextAction="Visit the reported "..source.name.." pattern-source reference in "..source.zone..
                "; verify safe manual combat, current spawn and loot. No drop rate or guaranteed pattern is assumed. Observe the recipe item in bags, then learn manually and observe learned-state separately."
        end
    end
    current.materialService=nil
    local prep=current.stationPreparation
    if key=="COOKING"and prep and prep.mode=="KIT"then
        local item,required
        if prep.status=="RETRIEVE_KIT_BANK"then item,required=prep.itemID,1
        elseif prep.status=="ACQUIRE_PREPARATION_MATERIALS"or prep.status=="RETRIEVE_PREPARATION_BANK"then
            for _,r in ipairs(prep.materials)do if r.bagsKnown and r.bags<r.required then item,required=r.itemID,r.required;break end end
        end
        local service=item and self:SelectMaterialService(key,item,required)
        if service and service.status~="BAGS_READY"then
            current.materialService=service
            current.requiredNextAction="verify" -- sourcing advice never authorizes consumer crafting
            current.nextAction=(current.craftInstruction or current.nextAction)..". Station preparation: "..service.nextAction
        end
        return current
    end
    -- The ordinary-rod owner already supplies its own bank action and exact
    -- prerequisite context. Do not replace it with a generic material service.
    if current.ordinaryRodAcquisition and current.ordinaryRodAcquisition.status=="BANK_OBSERVED" then return current end
    if current.kind~="craft" or current.learned~=true or current.materialSupply or current.bagReady==true and
        not current.hammerStatus and not current.engineeringToolStatus and not current.ordinaryRodAcquisition then return current end
    local chosen
    local function choose(id,required,reusable)
        local s=self:SelectMaterialService(key,id,required)
        if s and s.status~="BAGS_READY" then s.reusable=reusable==true;chosen=s;return true end
    end
    -- Only a consumed ordinary rod reagent remains an acquisition input.
    if current.ordinaryRodAcquisition and current.ordinaryRodAcquisition.status~="BAGS_OBSERVED" then
        choose(current.ordinaryRodAcquisition.itemID,current.ordinaryRodAcquisition.required)
    elseif not current.manualCraftBlockedByRecipePrerequisite then
        for _,row in ipairs(current.materials or {})do if choose(row.itemID,row.required)then break end end
    end
    if chosen then
        current.materialService=chosen
        -- A known consumable shortage can lead to an advisory vendor visit.
        -- The visit still requires a fresh offer check, not a purchase grant.
        -- Missing reusable tools retain their explicit prerequisite Verify.
        current.requiredNextAction=(chosen.status=="BANK" or chosen.status=="BUY_MANUALLY" or
            chosen.status=="VERIFY_VENDOR" and not chosen.reusable) and "acquire" or "verify"
        current.nextAction=chosen.nextAction
    end
    return current
end
function AcquisitionPlanner:ApplyServicesToPlan(key,plan,context)
    local prerequisite=prerequisiteAcquisition(key)
    if prerequisite then return prerequisite end
    local current=type(plan)=="table" and plan.recommendedCurrentStep
    self:ApplyServiceToStep(key,current)
    if current and current.materialService then
        plan.action=current.nextAction;plan.actionKind=current.requiredNextAction;plan.p1OneCraft=false
        plan.status="MATERIAL_SERVICE_"..current.materialService.status
        if plan.step then plan.step.materialService=current.materialService end
    end
    local bridge=JLP:GetModule("GatheringMaterialBridge")
    local publish=bridge and bridge.CanPublishSupply and bridge:CanPublishSupply(key,context) or
        not bridge and not(context and context.preview==true)
    if publish then
        local old=self.materialServiceWatch
        local service=current and current.materialService
        local next=service and {key=key,itemID=service.itemID,required=service.required,
            quantity=service.quantity,status=service.status,sourceID=service.sourceID} or nil
        if old and old.key==key and (not next or old.itemID~=next.itemID or old.required~=next.required or old.sourceID~=next.sourceID) then
            local owner=JLP:GetModule("IntegratedDestinationOwner")
            if owner and owner.InvalidateSupplySource then owner:InvalidateSupplySource(old.sourceID,"MATERIAL_SERVICE_REPLANNED")end
        end
        if next or old and old.key==key then self.materialServiceWatch=next end
        local prior=self.recipeServiceWatch
        local pattern=current and current.learned==false and current.patternAcquisition
        local source=current and current.navigation and current.navigation.source
        local recipeWatch=pattern and source and {key=key,recipeID=current.recipeID,
            skill=current.skill,itemID=pattern.itemID,possession=pattern.patternPossession,
            sourceID=source.serviceID} or nil
        if prior and prior.key==key and (not recipeWatch or prior.recipeID~=recipeWatch.recipeID or prior.sourceID~=recipeWatch.sourceID) then
            local owner=JLP:GetModule("IntegratedDestinationOwner")
            if owner and owner.InvalidateSupplySource then owner:InvalidateSupplySource(prior.sourceID,"RECIPE_ACQUISITION_REPLANNED")end
        end
        if recipeWatch or prior and prior.key==key then self.recipeServiceWatch=recipeWatch end
    end
    return plan
end
function AcquisitionPlanner:ObserveMaterialServiceInventory()
    local recipe=self.recipeServiceWatch
    if recipe then
        local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
        local fresh=bridge and bridge:GetPatternAcquisition(recipe.key,recipe.recipeID,recipe.skill)
        local api=JLP:GetModule("ProfessionAPI")
        local observed=api and api.GetReadOnlyRecipeObservation and api:GetReadOnlyRecipeObservation(recipe.recipeID,recipe.key)
        if not fresh or fresh.patternPossession~=recipe.possession or
            observed and observed.readOnlyObserved==true and observed.learned==true then
            local owner=JLP:GetModule("IntegratedDestinationOwner")
            if owner and owner.InvalidateSupplySource then owner:InvalidateSupplySource(recipe.sourceID,"OBSERVED_RECIPE_ACQUISITION_CHANGED")end
            self.recipeServiceWatch=nil
        end
    end
    local old=self.materialServiceWatch
    if not old then return end
    local fresh=self:SelectMaterialService(old.key,old.itemID,old.required)
    if not fresh or fresh.status~=old.status or fresh.quantity~=old.quantity or fresh.sourceID~=old.sourceID then
        local owner=JLP:GetModule("IntegratedDestinationOwner")
        if owner and owner.InvalidateSupplySource then owner:InvalidateSupplySource(old.sourceID,"OBSERVED_MATERIAL_SERVICE_CHANGED")end
        if not fresh or fresh.status=="BAGS_READY" then self.materialServiceWatch=nil
        else old.status=fresh.status;old.quantity=fresh.quantity;old.sourceID=fresh.sourceID end
    end
end
function AcquisitionPlanner:BuildReadOnlyForPlan(key, plan)
    local prerequisite=prerequisiteAcquisition(key)
    if prerequisite then return prerequisite end
    if type(plan) ~= "table" or plan.readOnly ~= true or plan.executionEligible ~= false then
        return {contract="read-only-profession-acquisition-preview-v1", key=key, readOnly=true, status="blocked", terminalReason="READ_ONLY_PLAN_REQUIRED", actions={}}
    end
    local current=plan.recommendedCurrentStep
    if current and current.firstAidAccess then
        local a=current.firstAidAccess
        return {contract="read-only-profession-acquisition-preview-v1",key=key,status="first-aid-prerequisite",readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
          actions={{kind=a.status=="RETRIEVE_BOOK_BANK"and "retrieve-current-bank"or a.status=="USE_BOOK_MANUALLY"and "learn-book-manually"or a.status=="BUY_BOOK_MANUALLY"and "buy-book-manually"or a.questID and "quest-manually"or "verify-learning-source",
           itemID=a.itemID,recipeID=a.recipeID,questID=a.questID,quantity=a.bags~=nil and a.bank~=nil and a.itemID and 1 or nil,observation=a,navigation=current.navigation,readOnly=true,nativeDispatchAllowed=false}}}
    end
    local pattern=current and current.learned~=true and current.patternAcquisition
    if pattern and current.learned==false and pattern.patternPossession~="UNKNOWN"and pattern.vendorAccess and (pattern.status=="RETRIEVE_ACCESS_ITEM_FROM_BANK"or pattern.status=="EQUIP_ACCESS_ITEM_MANUALLY"or pattern.status=="VENDOR_ACCESS_QUEST_MANUALLY"or pattern.status=="VERIFY_DUNGEON_QUEST_OBJECTIVES"or pattern.status=="VERIFY_VENDOR_ACCESS_PREREQUISITE")then
        local access=pattern.vendorAccess
        return {contract="read-only-profession-acquisition-preview-v1",key=key,
            status="vendor-access-prerequisite",readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
            actions={{kind=access.status=="BANK"and "retrieve-current-bank"or access.status=="EQUIP_MANUALLY"and "equip-access-item-manually"or
                (access.status=="QUEST_START"or access.status=="QUEST_RETURN")and "quest-access-manually"or "verify-vendor-access",
                itemID=access.itemID,recipeID=current.recipeID,questID=access.questID,
                quantity=access.status=="BANK"and 1 or nil,consumed=false,prerequisite=true,
                observation=access,navigation=current.navigation,requiresManualVerification=true,readOnly=true,nativeDispatchAllowed=false}}}
    end
    if pattern then
        return {contract="read-only-profession-acquisition-preview-v1",key=key,
            status="recipe-acquisition",readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
            actions={{kind=pattern.status=="RETRIEVE_PATTERN_FROM_BANK" and "retrieve-recipe-bank" or
                current.requiredNextAction=="learn-recipe" and "learn-recipe-item" or
                current.requiredNextAction=="acquire-recipe" and "acquire-recipe-item" or "verify-recipe-source",
                itemID=pattern.itemID,recipeID=current.recipeID,sourceInfo=pattern.primary,
                available=pattern.primary and pattern.primary.currentStock or "UNKNOWN",
                quantity=(pattern.patternPossession=="ABSENT_FROM_BAGS" or pattern.patternPossession=="BANK_OBSERVED") and 1 or nil,
                requiresManualVerification=true,readOnly=true,nativeDispatchAllowed=false}}}
    end
    if current and current.materialService then
        local old=current.materialService
        local service=self:SelectMaterialService(key,old.itemID,old.required)
        if service then service.reusable=old.reusable end
        local requirementPlan=JLP:GetModule("RequirementPlan")
        local requirements=requirementPlan and requirementPlan:Build(key,plan)
        return {contract="read-only-profession-acquisition-preview-v1",key=key,status="material-service",
            readOnly=true,executionEligible=false,nativeDispatchAllowed=false,requirements=requirements,
            actions=service and service.status~="BAGS_READY" and {{kind=service.status=="BANK" and "retrieve-current-bank" or
                service.status=="BUY_MANUALLY" and "buy-material-manually" or "verify-material-source",
                itemID=service.itemID,quantity=service.quantity,service=service,sourceInfo=service.source,
                consumed=service.reusable~=true,
                readOnly=true,nativeDispatchAllowed=false,requiresManualVerification=true}} or {}}
    end
    if current and current.secondaryAccess then
        local a=current.secondaryAccess
        return {contract="read-only-profession-acquisition-preview-v1",key=key,status="secondary-access",readOnly=true,nativeDispatchAllowed=false,executionEligible=false,actions={{kind="manual-secondary-access",itemID=a.itemID,recipeID=a.recipeID,questID=a.questID,quantity=a.itemID and a.bags==0 and a.bank==0 and 1 or nil,access=a,navigation=current.navigation,readOnly=true,nativeDispatchAllowed=false}}}
    end
    if current and current.materialSupply and current.materialSupply.professionKey=="FISHING"then
        local s=current.materialSupply
        return {contract="read-only-profession-acquisition-preview-v1",key=key,status="fishing-supply",readOnly=true,nativeDispatchAllowed=false,executionEligible=false,actions={{kind=s.status=="BANK"and "retrieve-current-bank"or s.status=="FISHING_AREA"and "manual-fishing-area"or "verify-fish-supply",itemID=s.itemID,quantity=s.quantity,supply=s,navigation=current.navigation,readOnly=true,nativeDispatchAllowed=false}}}
    end
    if key=="FIRST_AID"and current and current.materialSupply then
        local supply=current.materialSupply
        return {contract="read-only-profession-acquisition-preview-v1",key=key,status="cloth-supply",readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
         actions={{kind=supply.status=="BANK"and "retrieve-current-bank"or supply.status=="CLOTH_LOOT"and "manual-combat-loot"or "verify-cloth-supply",
          itemID=supply.itemID,quantity=supply.quantity,supply=supply,sourceInfo=supply.source,navigation=current.navigation,readOnly=true,nativeDispatchAllowed=false}}}
    end
    local tool=key=="ENCHANTING" and current and current.toolRequirement
    local rod=key=="ENCHANTING" and current and current.ordinaryRodAcquisition
    if rod and rod.status~="BAGS_OBSERVED" then
        return {contract="read-only-profession-acquisition-preview-v1",key=key,
            status="ordinary-rod-prerequisite",readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
            actions={{kind=rod.status=="UNKNOWN_INVENTORY" and "verify-rod-inventory" or
                rod.status=="BANK_OBSERVED" and "retrieve-current-bank" or
                rod.selectedSource=="craft" and "craft-intermediate" or
                rod.selectedSource=="auction" and "acquire-material" or "manual-player-commission",
                itemID=rod.itemID,recipeID=rod.recipeID,professionKey="BLACKSMITHING",
                quantity=rod.status~="UNKNOWN_INVENTORY" and math.max(0,rod.required-(rod.bags or 0)) or nil,
                source=rod.selectedSource,options=rod.options,producer=rod.producer,
                craftedRecipe=rod.selectedSource=="craft" and rod.craftedRecipe or nil,
                requiresManualVerification=true,observedOutputCredit=0,
                readOnly=true,nativeDispatchAllowed=false}}}
    end
    if tool and (tool.status=="bank" or tool.status=="unknown") then
        return {contract="read-only-profession-acquisition-preview-v1",key=key,
            status="tool-prerequisite",readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
            actions={{kind=tool.status=="bank" and "retrieve-tool" or "verify-tool-inventory",
                itemID=tool.itemID,quantity=tool.status=="bank" and 1 or nil,consumed=false,
                requiresManualVerification=true,readOnly=true,nativeDispatchAllowed=false}}}
    end
    local requirementPlan = JLP:GetModule("RequirementPlan")
    local requirements = requirementPlan and requirementPlan:Build(key, plan) or nil
    local actions = {}
    -- Source is a separate advisory receipt; never infer stock, learned state,
    -- travel reachability or permission to buy/craft from an actor's identity.
    local resolver=JLP:GetModule("SourceResolver")
    local step=plan.step
    local id=type(step)=="table" and (step.recipeID or step.spellID)
    local qualifiedSource=resolver and type(id)=="number" and
        resolver:GetRecipeSource(key,id) or nil
    if qualifiedSource then
        actions[#actions+1]={kind="recipe-source",recipeID=id,
            sourceInfo=qualifiedSource,sourceText=resolver:Format(qualifiedSource,false),
            catalogueAcquisitionStatus="SOURCE_QUALIFIED",available="UNKNOWN",
            readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
    end
    for _, row in ipairs(requirements and requirements.rows or {}) do
        local bags = math.max(0, tonumber(row.storage and row.storage.bags) or 0)
        local bank = math.max(0, tonumber(row.storage and row.storage.bank) or 0)
        local gross = math.max(0, tonumber(row.required) or 0)
        local immediateMissing = math.max(0,gross-bags)
        local preparedMissing = math.max(0,gross-bags-bank)
        row.grossRequired=gross
        row.bagsAvailable=bags
        row.currentBankAvailable=bank
        row.currentOwned=bags+bank
        row.immediateMissing=immediateMissing
        row.preparedMissing=preparedMissing
        row.externalRequired=preparedMissing
        local bankRetrieval=math.min(bank,immediateMissing)
        if bankRetrieval>0 and row.storage and row.storage.bagKnown==true and row.storage.bankKnown==true then
            actions[#actions+1]={kind="retrieve-current-bank",itemID=row.itemID,name=row.name,quantity=bankRetrieval,source="bank",requiresRetrieve=true,readOnly=true}
        end
        local advisory=0
        for _,option in ipairs(row.options or {}) do
            if option.source=="alt-bank" and preparedMissing>advisory then
                local take=math.min(preparedMissing-advisory,math.max(0,tonumber(option.count) or 0))
                if take>0 then
                    actions[#actions+1]={kind="transfer-alt-bank",itemID=row.itemID,name=row.name,quantity=take,source="alt-bank",characterKey=option.characterKey,characterName=option.characterName,freshness=option.freshness,requiresTransfer=true,currentAccessible=false,confirmed=false,advisory=true,readOnly=true}
                    advisory=advisory+take
                end
            end
        end
        local quant=JLP:GetModule("AcquisitionQuantities")
        if quant then
            for field,value in pairs(quant:Compute(gross,row.storage,advisory)) do row[field]=value end
        else
            row.altBankAdvisory=advisory
            row.externalRequiredIfTransferred=math.max(0,preparedMissing-advisory)
        end
        -- Withdraw observed stock first; the budget may still show a future remainder.
        if bankRetrieval>0 then preparedMissing=0 end
        if preparedMissing>0 then
            local preferred=nil
            for _,option in ipairs(row.options or {}) do
                if option.source~="bags" and option.source~="bank" and option.source~="alt-bank" and option.eligible~=false then
                    preferred=option
                    break
                end
            end
            actions[#actions+1]={kind="acquire-material",itemID=row.itemID,name=row.name,
                quantity=(type(row.availability)=="table" and
                    row.availability.unknownBags==false and
                    row.availability.unknownBank==false) and preparedMissing or nil,
                quantityUpperBound=preparedMissing,source=preferred and (preferred.source or preferred.key) or "unavailable",
                options=row.options,readOnly=true,guaranteed=false,
                requiresManualVerification=true,externalRequiredIfTransferred=row.externalRequiredIfTransferred}
        end
    end
    if current and current.materialSupply then
        local supply=current.materialSupply
        local bridge=JLP:GetModule("GatheringMaterialBridge")
        if bridge and bridge.RefreshSupply then
            supply=bridge:RefreshSupply(supply) or {itemID=supply.itemID,status="VERIFY_SOURCE"}
        end
        local shared=JLP:GetModule("GatheringSharedMapState")
        local snapshot=shared and shared:GetSnapshot()
        local automatic=snapshot and snapshot.automaticSupplyGoal
        if automatic and automatic.status=="VERIFY_OWNER" and automatic.itemID==supply.itemID and
            automatic.required==supply.required and automatic.ownerProfession==(supply.consumerProfession or key) and
            (current.recipeID==automatic.ownerRecipeID or key==automatic.professionKey) then
            supply={itemID=supply.itemID,status="VERIFY_OWNER",required=supply.required}
        end
        for index=#actions,1,-1 do
            local action=actions[index]
            if action.itemID==supply.itemID and action.kind=="acquire-material" then
                if supply.status=="BAGS_READY" then table.remove(actions,index)
                else
                action.supply=supply;action.quantity=supply.quantity
                action.productionScenario=supply.production;action.alternativeToPurchase=supply.production and true or nil
                action.actionItemID=supply.actionItemID;action.actionQuantity=supply.actionQuantity
                action.source=supply.status=="HERBALISM"and "herbalism"or supply.status=="MINING"and "mining"or supply.status=="SMELT"and "smelting"or supply.status=="SKINNING" and "skinning" or supply.status=="AUCTION" and "auction" or
                    supply.status=="BANK" and "bank" or "verify"
                action.kind=(supply.status=="UNKNOWN_INVENTORY" or supply.status=="VERIFY_BANK" or supply.status=="VERIFY_SOURCE"or type(supply.status)=="string"and supply.status:find("VERIFY",1,true)==1) and
                    "verify-material-source" or "acquire-material"
                end
            end
        end
    end
    return {contract="read-only-profession-acquisition-preview-v1", key=key, readOnly=true, executionEligible=false, nativeDispatchAllowed=false, requirements=requirements, actions=actions, status="preview",
        catalogueAcquisitionStatus=qualifiedSource and "SOURCE_QUALIFIED" or "UNKNOWN",
        catalogueAcquisition=qualifiedSource}
end

function AcquisitionPlanner:BuildSelected()
    return self:Build(self:GetSelectedScope())
end

JLP:RegisterModule("AcquisitionPlanner", AcquisitionPlanner)
