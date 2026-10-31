local _, JLP = ...
-- Presentation-only adapter for the alpha138 source-prioritized acquisition preview.
-- Does not create shopping commitments, modify inventory, or grant craft authority.
local View={contract="forever-route-guide-view-v1",persisted=false,production=false,
    nativeDispatchAllowed=false,executionEligible=false,requiresLiveQA=false}
local supported={ALCHEMY=true,BLACKSMITHING=true,ENGINEERING=true,LEATHERWORKING=true}
local function nonnegative(n)
    n=tonumber(n)
    if not n or n~=n or n<0 or n==math.huge then return 0 end
    return math.floor(n)
end
local function rank(a,b)
    if a.externalRequired~=b.externalRequired then return a.externalRequired>b.externalRequired end
    return a.itemID<b.itemID
end
local function sourceText(row)
    local parts={}
    if row.currentBankRetrieve>0 then
        parts[#parts+1]="RETRIEVE "..row.currentBankRetrieve.." from your bank"
    end
    local alt=row.altBankAdvisoryQuantity
    if alt>0 then
        local freshness="UNKNOWN"
        for _,v in ipairs(row.altBankAdvisory or {}) do
            if v.freshness=="STALE" or v.freshness=="UNKNOWN" then freshness=v.freshness break end
            if v.freshness then freshness=v.freshness end
        end
        parts[#parts+1]="ALT TRANSFER? "..alt.." ["..freshness.."]"
    end
    if type(row.externalRequired)=="number" and row.externalRequired>0 then
        local candidates={}
        for _,v in ipairs(row.alternatives or {}) do
            if v.eligible~=false then
                candidates[#candidates+1]=tostring(v.label or v.kind or "External")
                if #candidates==2 then break end
            end
        end
        local extra=#candidates>0 and table.concat(candidates," / ") or "source not established"
        parts[#parts+1]="EXTERNAL? "..row.externalRequired.." ("..extra..")"
    end
    if #parts==0 then
        parts[1]=(row.externalRequired==nil and "Stock UNKNOWN · verify inventory manually" or
            "Current-character stock covers this conditional row")
    end
    return table.concat(parts,"  |  ")
end
local function compactSource(row)
    local parts={}
    if row.currentBankRetrieve>0 then parts[#parts+1]="BANK x"..row.currentBankRetrieve end
    if row.altBankAdvisoryQuantity>0 then
        local status="UNKNOWN"
        for _,alt in ipairs(row.altBankAdvisory or {}) do
            if alt.freshness=="STALE" or alt.freshness=="UNKNOWN" then status=alt.freshness break end
            if alt.freshness then status=alt.freshness end
        end
        parts[#parts+1]="ALT? x"..row.altBankAdvisoryQuantity.." ["..status.."]"
    end
    if type(row.externalRequired)=="number" and row.externalRequired>0 then
        local kind="unverified source"
        for _,v in ipairs(row.alternatives or {}) do
            if v.eligible~=false then
                kind=tostring(v.label or v.kind or "external")
                local widgets=JLP.UIWidgets
                if widgets and type(widgets.BoundedUTF8Label)=="function" then
                    kind=widgets:BoundedUTF8Label(kind,20)
                elseif #kind>20 then kind="source available (manual)" end
                break
            end
        end
        parts[#parts+1]="EXTERNAL? x"..row.externalRequired.." "..kind
    end
    if #parts==0 then parts[1]=row.externalRequired==nil and
        "Stock UNKNOWN · verify manually" or "Current supply covers conditional need" end
    return table.concat(parts," · ")
end
function View:IsSupported(key)
    return supported[tostring(key or ""):upper()]==true
end
function View:Build(key,skill,mode,options)
    key=tostring(key or ""):upper()
    if not self:IsSupported(key) then return nil,"NO_ADVISORY_ROUTE" end
    mode=(mode=="aggressive" or mode=="fastest") and "aggressive" or "normal"
    local acquisition=JLP:GetModule("ForeverRouteAcquisition")
    local bands=JLP:GetModule("ForeverSkillBandPlanner")
    local report,reason=acquisition and acquisition:Build(key,mode,options)
    if not report then return nil,reason or "REFERENCE_ACQUISITION_UNAVAILABLE" end
    local point= bands and bands:GetAtSkill(key,skill or 1,mode)
    local all={}
    for _,row in ipairs(report.materials or {}) do
        local q=row.quantity or {}
        local item={itemID=row.itemID,name=row.name or ("Item "..tostring(row.itemID)),
            grossRequired=nonnegative(q.grossRequired),bagsAvailable=nonnegative(q.bagsAvailable),
            bankKnown=row.bankKnown==true,currentBankAvailable=nonnegative(q.currentBankAvailable),
            currentBankRetrieve=nonnegative(row.currentBankRetrieve),
            externalRequired=nonnegative(q.externalRequired),
            externalIfTransferred=nonnegative(q.externalRequiredIfTransferred),
            altBankAdvisoryQuantity=nonnegative(row.altBankAdvisoryQuantity),
            altBankAdvisory=row.altBankAdvisory,alternatives=row.alternatives,
            estimated=true,ready=false}
        item.referenceProfessionKey=key -- read-only evidence classification; never a craft gate
        item.sourceText=sourceText(item)
        item.sourceShort=compactSource(item)
        all[#all+1]=item
    end
    -- Engineering research must show the SELECTED source-qualified skillband,
    -- not aggregate all material requirements over an estimated 1-225 route.
    -- A missing Forever item row does not inherit another recipe's demand.
    local bandRows={}
    local step=point and point.step
    if (key=="ENGINEERING" or key=="BLACKSMITHING" or key=="LEATHERWORKING") and type(step)=="table" and
        step.materialTotalsVerified==true and type(step.materials)=="table" and
        step.nativeDispatchAllowed==false then
        local optionsByID={}
        for _,item in ipairs(all) do optionsByID[item.itemID]=item end
        local catalog=JLP:GetModule("MaterialCatalog")
        for _,material in ipairs(step.materials) do
            local id,qty=type(material)=="table" and material.itemID or nil,
                type(material)=="table" and tonumber(material.quantity) or nil
            if type(id)=="number" and id>0 and id==math.floor(id) and
                type(step.recipeID)=="number" and step.recipeID>0 and
                type(step.sourceURL)=="string" and step.sourceURL~="" and
                qty and qty>0 and qty==math.floor(qty) and
                type(material.perCraft)=="number" and material.perCraft>0 and
                material.perCraft==math.floor(material.perCraft) and
                type(step.expectedCrafts)=="number" and step.expectedCrafts>0 and
                step.expectedCrafts==math.floor(step.expectedCrafts) and
                qty==material.perCraft*step.expectedCrafts and
                type(material.sourceURL)=="string" and material.sourceURL~="" then
                local prior=optionsByID[id]
                -- Compute quantities from the same selected skillband input.
                -- Existing inventory stock is advisory, never an action grant.
                local inventory=JLP:GetModule("Inventory")
                local owned=nil
                if type(inventory)=="table" and type(inventory.GetOwned)=="function" then
                    local ok,value=pcall(inventory.GetOwned,inventory,id)
                    if ok and type(value)=="table" then owned=value end
                end
                local rawBags=owned and owned.bags
                local bagsQualified=(not owned or (owned.bagKnown~=false and
                    owned.snapshotStale~=true)) and
                    type(rawBags)=="number" and rawBags==rawBags and
                    rawBags>=0 and rawBags<math.huge and rawBags==math.floor(rawBags)
                local bags=bagsQualified and rawBags or 0
                local rawBank=owned and owned.bank
                local stale=type(owned)=="table" and
                    (owned.bankStale==true or owned.snapshotStale==true or owned.freshness=="STALE")
                local known=type(owned)=="table" and owned.bankKnown==true and not stale and
                    type(rawBank)=="number" and rawBank==rawBank and
                    rawBank>=0 and rawBank<math.huge and rawBank==math.floor(rawBank)
                local bank=known and rawBank or 0
                local q=JLP:GetModule("AcquisitionQuantities")
                local counts=q and q:Compute(qty,{bags=bags,bank=bank},0)
                local entry={itemID=id,name=material.name or (prior and prior.name) or
                    (catalog and catalog:GetName(id,"Item "..tostring(id))) or ("Item "..tostring(id)),
                    grossRequired=qty,bagsAvailable=bagsQualified and bags or nil,bagsKnown=bagsQualified,bankKnown=known,
                    bankStale=stale,snapshotStale=type(owned)=="table" and owned.snapshotStale==true,
                    sourceVerifiedPerCraft=true,perCraft=material.perCraft,
                    selectedRecipeID=step.recipeID,selectedRecipeName=step.recipe,
                    selectedSkillMin=step.skillMin,selectedSkillTarget=step.skillTarget,
                    estimatedCraftCount=step.expectedCrafts,estimatedGross=true,
                    craftCountAuthority="HISTORICAL_RESEARCH_ESTIMATE",
                    reagentAuthority="WOWHEAD_FOREVER",
                    currentBankAvailable=bank,currentBankRetrieve=math.min(bank,math.max(0,qty-bags)),
                    externalRequired=(known and bagsQualified) and
                        (counts and counts.externalRequired or math.max(0,qty-bags-bank)) or nil,
                    externalIfTransferred=(known and bagsQualified) and
                        (counts and counts.externalRequired or math.max(0,qty-bags-bank)) or nil,
                    altBankAdvisoryQuantity=0,alternatives=prior and prior.alternatives or {},
                    sourceURL=material.sourceURL or step.sourceURL,
                    recipeBands={{recipe=step.recipe,recipeID=step.recipeID,
                        skillMin=step.skillMin,skillMax=step.skillTarget,
                        perCraft=material.perCraft,estimatedCrafts=step.expectedCrafts,
                        sourceURL=step.sourceURL}},
                    estimated=true,ready=false,referenceProfessionKey=key,
                    itemPointLink="UNAVAILABLE",nativeDispatchAllowed=false}
                entry.sourceText=sourceText(entry)
                entry.sourceShort=compactSource(entry)
                bandRows[#bandRows+1]=entry
            end
        end
    end
    -- Preserve the existing aggregate 1-225 research preview for legacy
    -- callers; only the drill-down MaterialPage is selected-skillband scoped.
    table.sort(all,rank)
    local max=math.min(#all,3)
    local top={}
    for i=1,max do top[i]=all[i] end
    local result={contract=self.contract,professionKey=key,mode=mode,
        referenceBacked=true,partial=true,estimated=true,production=false,
        nativeDispatchAllowed=false,executionEligible=false,craftReady=false,
        verifiedWholeRoute=false,materialCount=#all,materials=top,allMaterials=all,
        hiddenMaterialCount=#all-max,unverifiedInventoryRows=report.unverifiedInventoryRows or 0,
        unknownReferenceSteps=report.unknownReferenceSteps or 0,
        trainerGateCount=#(report.trainerGates or {}),recipeAccessCount=#(report.recipeAccess or {}),
        verifiedRecipeAccess={},
        skillBandState=point and point.state or "SKILL_BAND_UNRESOLVED",
        skillBandRecipe=point and point.step and point.step.recipe or nil,
        skillBandMaterialScope=(key=="ENGINEERING" or key=="BLACKSMITHING" or key=="LEATHERWORKING") and
            (step and step.materialTotalsVerified==true and "SOURCE_QUALIFIED_SKILLBAND" or
            "UNAVAILABLE") or "CONDITIONAL_ROUTE_ESTIMATE",
        skillBandMaterialCount=#bandRows,
        skillBandMaterials=bandRows,
        skillBandPointLink="UNAVAILABLE",
        skillBandRequiredSkill=point and point.step and point.step.requiredSkill or nil,
        skillGateConflict=point and (point.state=="SOURCE_SKILL_GATE_CONFLICT" or
            point.state=="SKILL_ELIGIBILITY_GAP") or false,
        skillEligibility=point and point.skillEligibility or (point and point.step and point.step.skillEligibility),
        candidateReadOnly=key=="ALCHEMY",
        planningBasis=report.planningBasis}
    for _,access in ipairs(report.recipeAccess or {}) do
        if access.sourceVerified==true then
            result.verifiedRecipeAccess[#result.verifiedRecipeAccess+1]={
                recipe=access.recipe,recipeID=access.recipeID,
                recipeItemID=access.recipeItemID,itemURL=access.itemURL,
                requiredSkillToLearn=access.requiredSkillToLearn,
                learnedState="NOT_OBSERVED",vendorStock="UNKNOWN"}
        end
    end
    return result
end
-- Browsable material receipt for the selected candidate/reference step.
-- Presentation only: no queue, craft-ready signal, inventory mutation or
-- implied recipe ownership. Every index is bounded to the current receipt.
function View:MaterialPage(view,page,pageSize)
    if type(view)~="table" or view.nativeDispatchAllowed~=false or
        view.production~=false then
        return {rows={},page=1,pageCount=1,total=0,status="UNAVAILABLE",
            readOnly=true,nativeDispatchAllowed=false}
    end
    -- For all three selected-step source-qualified research professions, never
    -- fall back to a whole-route shopping list when this step lacks proof.
    local selectedStep=view.professionKey=="ENGINEERING" or
        view.professionKey=="BLACKSMITHING" or view.professionKey=="LEATHERWORKING"
    local all=selectedStep and view.skillBandMaterials or
        (type(view.allMaterials)=="table" and view.allMaterials or view.materials)
    if type(all)~="table" then all={} end
    local size=math.max(1,math.min(6,math.floor(tonumber(pageSize) or 3)))
    local total=#all
    local count=math.max(1,math.ceil(total/size))
    local current=math.max(1,math.min(count,math.floor(tonumber(page) or 1)))
    local rows={}
    for i=(current-1)*size+1,math.min(total,current*size) do
        if type(all[i])=="table" then rows[#rows+1]=all[i] end
    end
    return {rows=rows,page=current,pageCount=count,total=total,
        status=total>0 and "REFERENCE_ONLY" or "NO_QUALIFIED_MATERIALS",
        canPrevious=current>1,canNext=current<count,
        readOnly=true,nativeDispatchAllowed=false}
end

function View:GetSummary(key,skill,mode)
    local view,why=self:Build(key,skill,mode)
    if not view then return "Reference Guide: "..tostring(why) end
    local lines={string.format("%s %s: %d reference-backed conditional material rows; %d shown",
        view.professionKey,view.mode,view.materialCount,#view.materials),
        "Historical craft estimates; no verified full 1-300 shopping or native readiness"}
    for _,row in ipairs(view.materials) do
        lines[#lines+1]=string.format("%s [%s] need %s · bags %s · bank %s · external %s | %s",
            row.name,tostring(row.itemID),row.grossRequired,row.bagsAvailable,
            row.bankKnown and tostring(row.currentBankAvailable) or "UNKNOWN",row.externalRequired,row.sourceText)
    end
    return table.concat(lines,"\n")
end
JLP:RegisterModule("ForeverRouteGuideView",View)
