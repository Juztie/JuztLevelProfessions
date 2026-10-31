local _, JLP = ...
-- M15: Single, source-bound 70450 Materials & Sources reference across all
-- twelve professions. No native crafting, purchase, stock or route authority.
local Service={contract="JLP-MATERIALS-SOURCES-70450-1",sourceBuild=70450,
    readOnly=true,nativeDispatchAllowed=false,purchaseAllowed=false,
    routeAllowed=false,productionAuthority=false}
local BUILD=70450
local LIMIT=999999999
local function integer(v,min,max)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
        and v==math.floor(v) and v>=(min or 0) and v<=(max or LIMIT)
end
local function observedBuild()
    local m=JLP:GetModule("ClientBuildInfo")
    if not m or type(m.GetBuildNumber)~="function" then return nil end
    local ok,n=pcall(m.GetBuildNumber,m)
    return ok and integer(n,1) and n or nil
end
local function check(key,spell,crafts,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    -- A missing client build cannot authenticate current inventory, but does
    -- not invalidate the owner-provided read-only material reference.
    if not integer(spell,1) then return nil,"INVALID_SPELL_ID" end
    if not integer(crafts,1,9999) then return nil,"INVALID_CRAFT_COUNT" end
    local registry=JLP:GetModule("ProfessionRegistry")
    local normalized=registry and registry.NormalizeKey and registry:NormalizeKey(key)
    if not normalized then return nil,"UNKNOWN_PROFESSION" end
    return normalized,nil
end
-- An absent enrichment is not an absent recipe; a demonstrably malformed
-- enrichment is different and must retain its hard source-integrity failure.
local function sourceCorrupt(reason)
    if type(reason)~="string" then return false end
    for _,code in ipairs({"INVALID", "MALFORMED", "CORRUPT", "CONFLICT",
        "MISMATCH", "OVERFLOW", "UNSUPPORTED", "SKILLLINE", "SOURCE_SHA"}) do
        if reason:find(code,1,true) then return true end
    end
    return false
end
local function storageFor(inventory,itemID,required)
    local storage=inventory and inventory.GetOwned and inventory:GetOwned(itemID) or nil
    local result={bags=nil,bank=nil,bagKnown=false,bankKnown=false,
        missing=nil,minimumExternal=nil,readOnly=true}
    if type(storage)~="table" then return result end
    if storage.bagKnown==true and integer(storage.bags,0) then
        result.bags=storage.bags; result.bagKnown=true
    end
    if storage.bankKnown==true and integer(storage.bank,0) then
        result.bank=storage.bank; result.bankKnown=true
    end
    if result.bagKnown and result.bankKnown then
        result.missing=math.max(0,required-result.bags-result.bank)
        result.minimumExternal=result.missing
    elseif result.bagKnown or result.bankKnown then
        result.minimumExternal=math.max(0,required-(result.bags or 0)-(result.bank or 0))
        -- This is a lower bound only when one scope is unobserved; it is
        -- never an actionable purchase amount.
    end
    result.bankCacheUpdatedAt=storage.bankCacheUpdatedAt
    result.bagCacheUpdatedAt=storage.bagCacheUpdatedAt
    return result
end
function Service:GetRecipe(key,spellID,crafts,sourceBuild)
    local k,why=check(key,spellID,crafts,sourceBuild)
    if not k then return nil,why end
    local recipe=JLP:GetModule("Build70450RecipeCatalogue")
    local output=JLP:GetModule("Build70450CraftOutput")
    local metadata=JLP:GetModule("Build70450ItemMetadata")
    local acquisition=JLP:GetModule("Build70450RecipeAcquisition")
    if not recipe then return nil,"RECIPE_REFERENCE_MODULE_MISSING" end
    local identity,reason=recipe:GetRecipe(k,spellID,BUILD)
    if not identity then return nil,reason end
    if identity.professionKey~=k or identity.spellID~=spellID or
        identity.sourceBuild~=BUILD then
        return nil,"RECIPE_IDENTITY_OR_BUILD_CONFLICT"
    end
    local materialReceipt,materialReason=recipe:GetMaterialNeeds(k,spellID,crafts,BUILD)
    local yield,yieldReason
    if output and output.GetRecipeOutput then
        yield,yieldReason=output:GetRecipeOutput(k,spellID,crafts,BUILD)
    else yieldReason="OUTPUT_SERVICE_UNAVAILABLE" end
    local sources,sourceReason
    if acquisition and acquisition.GetRecipeSources then
        sources,sourceReason=acquisition:GetRecipeSources(k,spellID,BUILD)
    else sourceReason="ACQUISITION_SERVICE_UNAVAILABLE" end
    if not yield and sourceCorrupt(yieldReason) then
        return nil,"OUTPUT_REFERENCE_"..yieldReason
    end
    if not sources and sourceCorrupt(sourceReason) then
        return nil,"ACQUISITION_REFERENCE_"..sourceReason
    end
    -- A missing *optional* output or acquisition reference must not erase
    -- already source-qualified recipe identity and reagent slots. Retain a
    -- precise per-field gap; do not substitute a fabricated yield/source.
    -- Any PRESENT but contradictory receipt remains a hard identity conflict.
    if (yield and (yield.professionKey~=k or yield.spellID~=spellID or
        yield.sourceBuild~=BUILD)) or
        (sources and (sources.professionKey~=k or sources.spellID~=spellID or
        sources.sourceBuild~=BUILD)) then
        return nil,"SOURCE_RECEIPT_BUILD_OR_IDENTITY_CONFLICT"
    end
    local rows={};local requiredCount=0;local fullStock=true;local external=0
    local inventory=JLP:GetModule("Inventory")
    if materialReceipt then
        if materialReceipt.sourceBuild~=BUILD or materialReceipt.professionKey~=k or
            materialReceipt.spellID~=spellID or materialReceipt.crafts~=crafts then
            return nil,"MATERIAL_RECEIPT_IDENTITY_CONFLICT"
        end
        for _,r in ipairs(materialReceipt.requirements or {}) do
            if not integer(r.itemID,1) or not integer(r.rawTotal,1) or
                not integer(r.perCraft,1) then return nil,"INVALID_REAGENT_QUANTITY" end
            if r.perCraft*crafts~=r.rawTotal then return nil,"REAGENT_MULTIPLICATION_CONFLICT" end
            local m,err
            if metadata and metadata.GetItem then m,err=metadata:GetItem(r.itemID,BUILD) end
            if not m and err and err~="ITEM_NOT_IN_PROFESSION_REFERENCE_SET" then
                return nil,"ITEM_METADATA_CONFLICT:"..tostring(err)
            end
            local stock=storageFor(inventory,r.itemID,r.rawTotal)
            if stock.missing==nil then fullStock=false else external=external+stock.missing end
            if requiredCount+r.rawTotal>LIMIT then return nil,"MATERIAL_TOTAL_OVERFLOW" end
            requiredCount=requiredCount+r.rawTotal
            local name=(m and m.name) or r.itemName
            rows[#rows+1]={itemID=r.itemID,name=name,
                nameStatus=name and (m and m.nameEvidence or r.itemNameState) or "NAME_UNVERIFIED",
                perCraft=r.perCraft,required=r.rawTotal,
                bags=stock.bags,bank=stock.bank,bagKnown=stock.bagKnown,
                bankKnown=stock.bankKnown,missing=stock.missing,
                minimumExternal=stock.minimumExternal,
                sourceStatus="ITEM_ACQUISITION_NOT_VERIFIED_BY_70450_CLIENT_EXPORT",
                priceStatus="NO_CURRENT_70450_PRICE_EVIDENCE",
                optionsActionable=false,readOnly=true,nativeDispatchAllowed=false}
        end
    end
    local kind=materialReceipt and "SOURCE_REAGENTS_PRESENT" or "REAGENTS_UNKNOWN"
    if materialReceipt and #rows==0 then kind="EMPTY_REAGENT_SLOTS_IN_CLIENT_SOURCE" end
    local acquisitionState=sources and sources.sourceState or "SOURCE_REFERENCE_UNAVAILABLE"
    local fullExternal=materialReceipt and fullStock and external or nil
    return {contract=self.contract,sourceBuild=BUILD,observedClientBuild=observedBuild(),
        professionKey=k,spellID=spellID,recipeName=identity.name,crafts=crafts,
        itemRows=rows,itemTypes=#rows,materialState=kind,
        requiredSpellFocusID=identity.requiredSpellFocusID,
        requiredSpellFocusName=identity.requiredSpellFocusName,
        spellFocusRequirementStatus=identity.spellFocusRequirementStatus,
        spellFocusRuntimeAvailable="UNKNOWN",
        materialsError=materialReason,requiredUnits=materialReceipt and requiredCount or nil,
        knownExternalUnits=fullExternal,stockComplete=fullStock and materialReceipt~=nil,
        output=yield,outputStatus=yield and yield.outcome or "OUTPUT_REFERENCE_UNAVAILABLE",
        outputError=yield and nil or (yieldReason or "NO_OUTPUT_RECEIPT"),
        outputQuantityIsLiveVerified=false,
        teachingItems=sources and sources.teachingItems or {},
        researchSources=sources and sources.researchSources or {},
        sourceError=sources and nil or (sourceReason or "NO_ACQUISITION_RECEIPT"),
        sourceStatus=acquisitionState,hasSourceConflict=sources and sources.hasConflictingSource==true or false,
        acquisitionVerifiedLive=false,recipeAccess="UNKNOWN",
        factionEligibility="UNKNOWN",specializationEligibility="UNKNOWN",
        phaseEligibility="UNKNOWN",currentAHStock="UNKNOWN",
        costStatus="NO_70450_MARKET_RECEIPT",totalCost=nil,
        cannotAutoBuy=true,cannotAutoRoute=true,cannotAutoCraft=true,
        referenceOnly=true,readOnly=true,nativeDispatchAllowed=false,
        productionAuthority=false},nil
end
function Service:GetSummary(key,spellID,crafts,build)
    local row,reason=self:GetRecipe(key,spellID,crafts,build)
    if not row then return nil,reason end
    local publicVendor,publicVendors=nil,{}
    local publicQuestReferences={}
    for _,lead in ipairs(row.researchSources or {}) do
        if lead.evidenceTier=="WOWHEAD_FOREVER_ALLIANCE_PUBLIC_REFERENCE" or
           lead.evidenceTier=="WOWHEAD_FOREVER_HORDE_PUBLIC_REFERENCE" then
            local v={npcName=lead.npcName,npcID=lead.npcID,
                teachingItemID=lead.teachingItemID,skillRequired=lead.guideSkillRequired,
                merchantFavorCost=lead.merchantFavorCost,factionReference=lead.factionReference,
                sourceURL=lead.externalReference,liveStockVerified=false,readOnly=true}
            publicVendors[#publicVendors+1]=v
            if not publicVendor then publicVendor=v end
        end
        if lead.sourceType=="quest" and
           lead.evidenceTier=="WOWHEAD_FOREVER_QUEST_REWARD_REFERENCE_NOT_LIVE" then
            publicQuestReferences[#publicQuestReferences+1]={questID=lead.questID,
                teachingItemID=lead.teachingItemID,npcID=lead.npcID,
                npcName=lead.npcName,factionReference=lead.factionReference,
                sourceURL=lead.externalReference,readOnly=true,
                liveCompletionVerified=false,routeEligible=false}
        end
    end
    return {recipe=row.recipeName or ("Spell #"..spellID),materialState=row.materialState,
        materialTypes=row.itemTypes,requiredUnits=row.requiredUnits,
        knownExternalUnits=row.knownExternalUnits,sourceStatus=row.sourceStatus,
        outputStatus=row.outputStatus,hasSourceConflict=row.hasSourceConflict,
        publicVendorReference=publicVendor,publicVendorReferences=publicVendors,
        publicQuestReferences=publicQuestReferences,
        requiredSpellFocusID=row.requiredSpellFocusID,
        requiredSpellFocusName=row.requiredSpellFocusName,
        spellFocusRequirementStatus=row.spellFocusRequirementStatus,
        stockComplete=row.stockComplete,readOnly=true,nativeDispatchAllowed=false}
end
JLP:RegisterModule("MaterialsSources70450",Service)
