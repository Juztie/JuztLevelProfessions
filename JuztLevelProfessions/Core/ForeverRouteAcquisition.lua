local _, JLP = ...
-- Advisory acquisition for *referenced* research steps only. This is not a
-- production Planner, shopping commitment, live stock proof, or dispatch path.
local A={contract="forever-route-acquisition-v1",persisted=false,production=false,
    executionEligible=false,nativeDispatchAllowed=false,requiresLiveQA=false}
local function nat(n)
    n=tonumber(n)
    if not n or n~=n or n<0 or n==math.huge then return 0 end
    return math.floor(n)
end
local function optionSummary(options)
    local result,seen={},{}
    for _,v in ipairs(options or {}) do
        if v.kind~="bags" and v.kind~="bank" and v.kind~="alt-bank" and not seen[v.kind] then
            seen[v.kind]=true
            result[#result+1]={kind=v.kind,label=v.label,eligible=v.eligible~=false,
                availabilityState=v.availabilityState or "UNKNOWN",professionKey=v.professionKey,
                -- Availability is never established by a source catalogue.
                inventoryConfirmed=false,priceKnown=false}
        end
    end
    return result
end
function A:Build(key,mode,options)
    options=type(options)=="table" and options or {}
    local flow=JLP:GetModule("ForeverMaterialFlow")
    local skillBands=JLP:GetModule("ForeverSkillBandPlanner")
    local materialCatalog=JLP:GetModule("MaterialCatalog")
    local inventory=JLP:GetModule("Inventory")
    local quantities=JLP:GetModule("AcquisitionQuantities")
    local plan,reason=flow and flow:Build(key,mode)
    if not plan then return nil,reason or "REFERENCE_FLOW_UNAVAILABLE" end
    local band=skillBands and skillBands:Build(key,mode)
    if not quantities or not materialCatalog or not band then return nil,"ADVISORY_DEPENDENCY_MISSING" end
    local result={contract=self.contract,professionKey=plan.professionKey,mode=plan.mode,
        planningBasis="FOREVER_REFERENCED_INPUTS_WITH_HISTORICAL_CRAFT_COUNTS",
        partial=true,estimated=true,verifiedWholeRoute=false,
        sourceCoverageComplete=plan.planComplete==true,
        nativeDispatchAllowed=false,executionEligible=false,production=false,
        materials={},trainerGates={},recipeAccess={},unknownReferenceSteps=plan.unverifiedSteps,
        unknownOutputs=plan.unknownOutputs,inventoryObserved=true,
        externalRequiredConditionalTotal=0,conditionalTotalKnown=true,
        unverifiedInventoryRows=0}
    for _,row in ipairs(plan.externalDirect or {}) do
        local id,required=tonumber(row.itemID),nat(row.quantity)
        if id and required>0 then
            local overridden=options.inventoryByItemID and options.inventoryByItemID[id]
            local owned=type(overridden)=="table" and overridden or
                (inventory and inventory.GetOwned and inventory:GetOwned(id)) or {}
            local bagKnown=owned.bagKnown==true or
                (owned.bagKnown==nil and type(owned.bags)=="number")
            local bags=bagKnown and nat(owned.bags) or nil
            -- A cached/closed bank is not a current spendable observation.
            local bankKnown=owned.bankKnown==true or
                (owned.bankKnown==nil and type(owned.bank)=="number")
            local bank=bankKnown and nat(owned.bank) or nil
            local alts=options.altByItemID and options.altByItemID[id] or
                (inventory and inventory.GetAltBankAvailability and inventory:GetAltBankAvailability(id,{sameRealm=true})) or {}
            local advisory=0
            for _,alt in ipairs(alts or {}) do
                if alt.requiresTransfer~=false and alt.currentAccessible~=true then
                    advisory=advisory+nat(alt.count)
                end
            end
            local q=quantities:Compute(required,{bags=bags,bank=bank,
                bagKnown=bagKnown,bankKnown=bankKnown},advisory)
            local sources=optionSummary(materialCatalog:GetAcquisitionOptions(id,nil,nil,
                {bags=bags,bank=bank,bagKnown=bagKnown,bankKnown=bankKnown}))
            local output=flow:GetOutputRecipe(plan.professionKey,id)
            if output then
                local present=false
                for _,candidate in ipairs(sources) do if candidate.kind=="craft" then present=true end end
                if not present then sources[#sources+1]={kind="craft",label="Craft intermediate (recipe reference)",eligible=true,
                    availabilityState="EXTERNAL",inventoryConfirmed=false,priceKnown=false} end
            end
            local priced
            if options.prices and q.externalRequired and q.externalRequired>0 then
                priced=flow:QuoteMaterial(plan.professionKey,id,q.externalRequired,options.prices)
            end
            local item={itemID=id,name=materialCatalog:GetName(id,"Item "..id),
                grossRouteExternal=required,quantity=q,
                bagsAvailable=bags,currentBankAvailable=bank,
                bagKnown=bagKnown,unknownBagStock=not bagKnown,
                bankKnown=bankKnown,unknownBankStock=not bankKnown,
                inventoryQuantityState=q.state,
                currentBankRetrieve=(bankKnown and q.immediateMissing) and
                    math.min(bank,q.immediateMissing) or nil,
                altBankAdvisory=alts,altBankAdvisoryQuantity=q.altBankAdvisory,
                externalRequiredConditional=q.externalRequired,
                externalRequiredIfTransferred=q.externalRequiredIfTransferred,
                alternatives=sources,priceQuote=priced,
                craftReadyNow=false,sourceEligibleOnly=false,
                -- The ordered research route must be performed as estimated before
                -- internal output credits become physically real.
                conditionalOnEstimatedPriorCrafts=true}
            result.materials[#result.materials+1]=item
            if q.externalRequired~=nil then
                result.externalRequiredConditionalTotal=result.externalRequiredConditionalTotal+q.externalRequired
            else
                result.conditionalTotalKnown=false
                result.inventoryObserved=false
            end
            if not bankKnown or not bagKnown then
                result.unverifiedInventoryRows=result.unverifiedInventoryRows+1
            end
        end
    end
    if not result.conditionalTotalKnown then result.externalRequiredConditionalTotal=nil end
    for _,gate in ipairs(band.trainers or {}) do
        result.trainerGates[#result.trainerGates+1]={tier=gate.tier,skillCapFrom=gate.skillCapFrom,
            skillCapTo=gate.skillCapTo,minCharacterLevel=gate.minCharacterLevel,
            authority="HISTORICAL_GUIDE_NOT_FOREVER_VERIFIED",requirementVerified=false}
    end
    for _,step in ipairs(band.steps or {}) do
        if step.sourceRequirement then
            local bridge=JLP:GetModule("ForeverRecipeAccessBridge")
            local verified,reason
            if bridge then verified,reason=bridge:Resolve(plan.professionKey,step) end
            result.recipeAccess[#result.recipeAccess+1]=verified or {
                recipeID=step.recipeID,recipe=step.recipe,requirement=step.sourceRequirement,
                status="REFERENCE_LOOKUP_REQUIRED",sourceVerified=false,
                evidenceReason=reason or "ACCESS_ITEM_NOT_CURATED",learnedState="NOT_OBSERVED"}
        end
    end
    return result
end
function A:GetSummary(key,mode)
    local model,err=self:Build(key,mode)
    if not model then return "Forever route acquisition: "..tostring(err) end
    local lines={string.format("%s %s · partial reference-backed acquisition · %d material IDs",
        model.professionKey,model.mode,#model.materials),
        "Quantities are CONDITIONAL on historical craft estimates and earlier intermediate outputs; not a complete 1-300 shopping list"}
    for i,row in ipairs(model.materials) do
        if i>8 then lines[#lines+1]="... "..(#model.materials-8).." more material IDs (advisory)";break end
        local q=row.quantity
        lines[#lines+1]=string.format("%s [%d] direct external %d · bags %s · bank %s · need %s · alt advisory %s",
            row.name,row.itemID,row.grossRouteExternal,
            q.bagsAvailable==nil and "UNKNOWN" or tostring(q.bagsAvailable),
            q.currentBankAvailable==nil and "UNKNOWN" or tostring(q.currentBankAvailable),
            q.externalRequired==nil and "UNKNOWN" or tostring(q.externalRequired),
            q.altBankAdvisory==nil and "UNKNOWN" or tostring(q.altBankAdvisory))
    end
    lines[#lines+1]=string.format("Research-only steps %d · historical trainer gates %d · access checks %d · inventory-unknown rows %d",
        model.unknownReferenceSteps,#model.trainerGates,#model.recipeAccess,model.unverifiedInventoryRows)
    lines[#lines+1]="No Live-QA, NPC snapshot, native dispatch, guaranteed AH stock or fully qualified 1-300 route"
    return table.concat(lines,"\n")
end
JLP:RegisterModule("ForeverRouteAcquisition",A)
