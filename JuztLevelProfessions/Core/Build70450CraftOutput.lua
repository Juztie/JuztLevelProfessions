local _, JLP = ...
-- Build 70450 only. SpellEffect quantities are source measurements, NOT server receipts.
-- No native dispatch, protected UI mutation, or authority promotion occurs here.
local Engine={contract="JLP-BUILD70450-CRAFT-OUTPUT-2",sourceBuild=70450,
    readOnly=true,nativeDispatchAllowed=false,executionEligible=false,productionAuthority=false}
local BUILD=70450
local MAX_CRAFTS=9999
local MAX_OUTPUT=999999999
-- Source effect bases and old Forever web reference rows are NOT craft receipts.
-- A skill-window reading can be obtained separately with verified recipe links.
local function oldExternalReference(spellID)
    local d=JLP.data and JLP.data.recipeOutputYields
    if type(d)~="table" or d.contract~="forever-recipe-output-yield-reference-v1" or
        type(d.recipes)~="table" or type(d.sourceMetadata)~="table" or
        d.sourceMetadata.buildPinned~=false or d.sourceMetadata.plannerEligible~=false then return nil end
    for _,row in pairs(d.recipes) do
        if type(row)=="table" and row.spellID==spellID and
            row.externalVerified==true and row.liveVerified==false and
            row.plannerEligible==false and row.fixed==true and
            type(row.outputQuantity)=="number" and
            row.outputQuantity>0 and row.outputQuantity==math.floor(row.outputQuantity) then
            return {perCraftCandidate=row.outputQuantity,source=row.source,
                referenceCapturedAt=d.sourceMetadata.capturedAt,
                capturedAgainstBuild=d.sourceMetadata.capturedAgainstBuild,
                buildPinned=false,liveVerified=false,productionAuthority=false}
        end
    end
    return nil
end
local function uint(n,allowZero)
    return type(n)=="number" and n==n and n<math.huge and n==math.floor(n) and
        n>=(allowZero and 0 or 1) and n<=MAX_OUTPUT
end
local function data()
    local d=JLP.data and JLP.data.build70450CraftOutputs
    if type(d)~="table" or d.contract~="JLP-BUILD70450-OUTPUT-SOURCE-1" or
        d.sourceBuild~=BUILD or type(d.professions)~="table" then return nil end
    return d
end
local function findLine(packed,id,delimiter)
    if type(packed)~="string" then return nil end
    local needle=tostring(id)..delimiter
    local start=1
    while true do
        local p=packed:find(needle,start,true)
        if not p then return nil end
        if p==1 or packed:sub(p-1,p-1)=="\n" then
            local stop=packed:find("\n",p,true)
            return packed:sub(p+#needle,stop and stop-1 or #packed)
        end
        start=p+#needle
    end
end
local function unpackParts(str,sep)
    local out={};local start=1
    while true do
        local p=str:find(sep,start,true)
        if not p then out[#out+1]=str:sub(start);return out end
        out[#out+1]=str:sub(start,p-1);start=p+#sep
    end
end
local function itemEntry(d,itemID)
    local line=findLine(d.itemsPacked,itemID,"\t")
    if not line then return nil,"NOT_IN_OUTPUT_SOURCE" end
    local presence,name=line:match("^([^\t]*)\t(.*)$")
    if not presence then return nil,"INVALID_ITEM_LOOKUP" end
    return {itemID=itemID,name=name~="" and name or nil,
        inItemTable=presence=="B" or presence=="I",
        inItemSparse=presence=="B" or presence=="S",
        itemEvidenceState=presence=="B" and "ITEM_AND_ITEMSPARSE_70450" or
            (presence=="I" and "ITEM_ONLY_70450" or
             (presence=="S" and "ITEMSPARSE_ONLY_70450" or "NO_ITEM_ROW"))}
end
local function observedBuild()
    local provider=JLP.GetModule and JLP:GetModule("ClientBuildInfo")
    local n=provider and provider.GetBuildNumber and provider:GetBuildNumber()
    -- Output-quantity MAX_OUTPUT is not a client build-number ceiling.
    return type(n)=="number" and n==n and n>0 and
        n==math.floor(n) and n<=9007199254740991 and n or nil
end
local function normalize(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    if not reg or type(reg.NormalizeKey)~="function" or type(reg.Get)~="function" then
        return nil,"REGISTRY_UNAVAILABLE" end
    local k=reg:NormalizeKey(key)
    if not k then return nil,"UNKNOWN_PROFESSION" end
    local d=data()
    if not d then return nil,"OUTPUT_SOURCE_UNAVAILABLE" end
    local r=reg:Get(k)
    local src=d.professions[k]
    if not src or not r or src.skillLineID~=r.skillLineID then
        return nil,"PROFESSION_SKILLLINE_MISMATCH" end
    return k,d,src
end
local function parseEffect(d,parts,crafts)
    if #parts~=6 then return nil,"INVALID_EFFECT_FIELDS" end
    local idx,typ,itemID,base,variance,enchantID=tonumber(parts[1]),tonumber(parts[2]),
        tonumber(parts[3]),tonumber(parts[4]),tonumber(parts[5]),tonumber(parts[6])
    if not uint(idx,true) or not uint(typ) or not uint(itemID,true) or
       not uint(enchantID,true) or not base or base~=base or not variance or
       variance~=variance or math.abs(base)>MAX_OUTPUT or math.abs(variance)>MAX_OUTPUT then
        return nil,"INVALID_SPELL_EFFECT" end
    local row={effectIndex=idx,spellEffect=typ,rawEffectBasePointsF=base,
        rawVariance=variance,sourceBuild=BUILD,readOnly=true,
        gameYieldVerified=false,productionAuthority=false}
    if typ==24 then
        if itemID==0 then return nil,"MISSING_CREATED_ITEM_ID" end
        local item,err=itemEntry(d,itemID)
        if not item then return nil,err end
        for k,v in pairs(item) do row[k]=v end
        row.kind="CREATED_ITEM"
        local items=JLP:GetModule("Build70450ItemMetadata")
        if items then
            local m=items:GetItem(itemID,BUILD)
            if m then
                row.itemMetadataContract=m.contract
                row.itemMetadataNameEvidence=m.nameEvidence
                row.itemName=m.name or row.name
                row.itemClassID=m.fields.ClassID
                row.itemSubclassID=m.fields.SubclassID
                row.itemQualityRaw=m.fields.OverallQualityID
                row.acquisitionVerified=false
            end
        end
        if variance~=0 then
            row.yieldState="VARIABLE_VARIANCE_UNRESOLVED"
            row.perCraftQuantity=nil;row.totalQuantity=nil
            row.minimumQuantity=nil;row.maximumQuantity=nil
        elseif uint(base) then
            row.yieldState="SOURCE_FIXED_REFERENCE"
            row.perCraftQuantity=base
            row.totalQuantity=base*crafts
            if row.totalQuantity>MAX_OUTPUT then return nil,"OUTPUT_QUANTITY_OVERFLOW" end
            row.minimumQuantity=nil;row.maximumQuantity=nil
        else
            -- Base=0 is not a guarantee that zero items are created.
            row.yieldState="BASE_ZERO_OR_NONINTEGER_UNRESOLVED"
            row.perCraftQuantity=nil;row.totalQuantity=nil
            row.minimumQuantity=nil;row.maximumQuantity=nil
        end
    elseif typ==53 then
        if itemID~=0 or enchantID==0 then return nil,"MALFORMED_ENCHANT_EFFECT" end
        row.kind="TARGET_ITEM_ENCHANTMENT"
        row.enchantmentID=enchantID
        row.enchantmentName=findLine(d.enchantmentsPacked,enchantID,"\t")
        if not row.enchantmentName then return nil,"ENCHANTMENT_NOT_IN_SOURCE" end
        row.yieldState="NO_NEW_ITEM_TARGET_ENCHANTMENT"
        row.perCraftQuantity=nil;row.totalQuantity=nil
        row.standardNewItemsProduced=0
        row.targetExistingItem=true
        row.itemCreationSemantics="MODIFIES_EXISTING_TARGET_NOT_A_NEW_ITEM"
    elseif typ==99 then
        row.kind="DISENCHANT_RANDOM_LOOT"
        row.yieldState="RANDOM_LOOT_UNRESOLVED"
        row.perCraftQuantity=nil;row.totalQuantity=nil
    else
        return nil,"UNSUPPORTED_EFFECT_TYPE"
    end
    return row
end
function Engine:ForKnownRecipe(professionKey,spellID,crafts,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    if not uint(spellID) then return nil,"INVALID_SPELL_ID" end
    if not uint(crafts) or crafts>MAX_CRAFTS then return nil,"INVALID_CRAFT_COUNT" end
    local k,d,src=normalize(professionKey)
    if not k then return nil,d end
    local packed=findLine(src.effectPacked,spellID,"^")
    local effects={};local itemCount=0;local enchantCount=0;local unresolvedCount=0;local byItem={}
    if packed then
        for _,chunk in ipairs(unpackParts(packed,",")) do
            local row,err=parseEffect(d,unpackParts(chunk,":"),crafts)
            if not row then return nil,err end
            effects[#effects+1]=row
            if row.kind=="CREATED_ITEM" then
                itemCount=itemCount+1
                if row.yieldState~="SOURCE_FIXED_REFERENCE" then unresolvedCount=unresolvedCount+1
                else byItem[row.itemID]=(byItem[row.itemID] or 0)+row.totalQuantity end
            elseif row.kind=="TARGET_ITEM_ENCHANTMENT" then enchantCount=enchantCount+1
            else unresolvedCount=unresolvedCount+1 end
        end
    end
    local outcome
    if #effects==0 then outcome="NO_DIRECT_OUTPUT_EFFECT_IN_EXPORT"
    elseif itemCount>0 and (enchantCount>0 or #effects>itemCount) then outcome="MIXED_OUTPUT_EFFECTS"
    elseif itemCount>0 then outcome=unresolvedCount>0 and "ITEM_OUTPUT_UNCERTAIN" or "ITEM_OUTPUT_STATIC_REFERENCE"
    elseif enchantCount>0 then outcome="TARGET_ENCHANTMENT_NO_CREATED_ITEM"
    else outcome="RANDOM_LOOT_UNRESOLVED" end
    -- An unpinned Forever web reference may disagree with the DB2 effect base.
    -- Preserve BOTH values, never silently replace the raw 70450 number.
    local external= itemCount==1 and oldExternalReference(spellID) or nil
    local referenceConflict=false
    if external then
        for _,effect in ipairs(effects) do
            if effect.kind=="CREATED_ITEM" then
                effect.unpinnedExternalReference=external
                referenceConflict=effect.yieldState~="SOURCE_FIXED_REFERENCE" or
                    effect.perCraftQuantity~=external.perCraftCandidate
                effect.referenceComparison=referenceConflict and
                    "DIFFERENT_UNPINNED_SOURCES" or "SAME_NUMBER_NOT_SERVER_VERIFIED"
                break
            end
        end
    end
    if referenceConflict and outcome=="ITEM_OUTPUT_STATIC_REFERENCE" then
        outcome="ITEM_OUTPUT_REFERENCE_CONFLICT"
    end
    local itemTotals={}
    for id,total in pairs(byItem) do itemTotals[#itemTotals+1]={itemID=id,sourceReferenceTotal=total} end
    table.sort(itemTotals,function(a,b) return a.itemID<b.itemID end)
    local actual=observedBuild()
    return {contract=self.contract,sourceBuild=BUILD,professionKey=k,spellID=spellID,
        crafts=crafts,observedClientBuild=actual,
        clientBuildRelation=actual==BUILD and "MATCH" or (actual and "MISMATCH" or "UNKNOWN"),
        outcome=outcome,effects=effects,effectCount=#effects,
        createdItemEffectCount=itemCount,enchantmentEffectCount=enchantCount,
        unresolvedEffectCount=unresolvedCount,sourceItemTotals=unresolvedCount==0 and itemTotals or nil,
        externalReferencePresent=external~=nil,sourceReferenceConflict=referenceConflict,
        outputRangeState= (itemCount==0 and enchantCount>0 and unresolvedCount==0) and
            "NO_SEPARATE_CREATED_ITEM" or "NOT_VERIFIED_BY_CLIENT_UI",
        countGuarantee="NOT_LIVE_VERIFIED",itemYieldsVerifiedInClient=false,
        nativeDispatchAllowed=false,productionAuthority=false,readOnly=true},nil
end
function Engine:GetRecipeOutput(key,spellID,crafts,build)
    -- Recipe identity must be validated against M6; a random spell in the DB2
    -- effect table is not a professions recipe merely because it has an effect.
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then return nil,"RECIPE_CATALOGUE_UNAVAILABLE" end
    local recipe,why=ref:GetRecipe(key,spellID,build)
    if not recipe then return nil,why end
    return self:ForKnownRecipe(recipe.professionKey,spellID,crafts,build)
end
-- Explicit opt-in, READ-ONLY client UI evidence. Indexes are not identities.
-- Never accept a GetTradeSkillNumMade value without verifying its enchant/spell
-- hyperlink carries the exact requested spell ID and the live build is 70450.
function Engine:GetClientTradeSkillYield(key,spellID,index,crafts,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local clientBuild=observedBuild()
    if not clientBuild then return nil,"CLIENT_BUILD_UNKNOWN" end
    if not uint(index) or index>10000 then return nil,"INVALID_TRADESKILL_INDEX" end
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then return nil,"RECIPE_CATALOGUE_UNAVAILABLE" end
    local recipe,reason=ref:GetRecipe(key,spellID,build)
    if not recipe then return nil,reason end
    if recipe.recordKind~="RECIPE_CANDIDATE" then return nil,"NOT_RECIPE_CANDIDATE" end
    -- Spell 461692 is registered in both Leatherworking and Tailoring in
    -- the same 70450 SkillLineAbility export. A link verifies the spell, but
    -- not which profession window is actually open; refuse attribution.
    if spellID==461692 then return nil,"AMBIGUOUS_PROFESSION_UI_CONTEXT" end
    local output,why=self:ForKnownRecipe(recipe.professionKey,spellID,crafts,build)
    if not output then return nil,why end
    if type(GetTradeSkillRecipeLink)~="function" or type(GetTradeSkillNumMade)~="function" or
        type(GetTradeSkillInfo)~="function" then return nil,"TRADESKILL_UI_API_UNAVAILABLE" end
    local ok,link=pcall(GetTradeSkillRecipeLink,index)
    if not ok or type(link)~="string" then return nil,"TRADESKILL_RECIPE_LINK_UNAVAILABLE" end
    local kind,id=link:match("|H([%a]+):(%d+)")
    if not id then kind,id=link:match("^([%a]+):(%d+)") end
    if (kind~="enchant" and kind~="spell") or tonumber(id)~=spellID then
        return nil,"TRADESKILL_RECIPE_LINK_MISMATCH" end
    local rowOK,rowName,rowType=pcall(GetTradeSkillInfo,index)
    if not rowOK or type(rowName)~="string" or rowName=="" or
        rowType=="header" or rowType=="subheader" then
        return nil,"TRADESKILL_ROW_UNAVAILABLE" end
    local madeOK,minMade,maxMade=pcall(GetTradeSkillNumMade,index)
    if not madeOK or not uint(minMade) or not uint(maxMade) or maxMade<minMade or
        maxMade>MAX_OUTPUT then return nil,"TRADESKILL_YIELD_INVALID_OR_UNKNOWN" end
    if maxMade*crafts>MAX_OUTPUT then return nil,"OUTPUT_QUANTITY_OVERFLOW" end
    local itemID,sourcePerCraft=nil,nil
    if output.createdItemEffectCount==1 then
        for _,e in ipairs(output.effects) do
            if e.kind=="CREATED_ITEM" then itemID=e.itemID;sourcePerCraft=e.perCraftQuantity;break end
        end
    end
    local assignable=output.createdItemEffectCount==1 and
        output.enchantmentEffectCount==0 and output.unresolvedEffectCount<=1
    if observedBuild()~=clientBuild then return nil,"CLIENT_BUILD_CHANGED_DURING_OBSERVATION" end
    return {contract="JLP-BUILD70450-CLIENT-YIELD-SNAPSHOT-1",sourceBuild=BUILD,
        observedClientBuild=clientBuild,
        clientBuildRelation=clientBuild==BUILD and "MATCH" or "MISMATCH",professionKey=recipe.professionKey,
        spellID=spellID,tradeSkillIndex=index,uiRecipeLink=link,uiName=rowName,
        crafts=crafts,uiMinMade=minMade,uiMaxMade=maxMade,
        uiRangeIsFixed=minMade==maxMade,
        uiQuantityEvidence="LIVE_CLIENT_TRADESKILL_WINDOW_NOT_CRAFT_RECEIPT",
        -- UI amount is not the count of newly created items for target enchants.
        createdItemID=assignable and itemID or nil,
        createdItemMinPerCraft=assignable and minMade or nil,
        createdItemMaxPerCraft=assignable and maxMade or nil,
        createdItemMinTotal=assignable and minMade*crafts or nil,
        createdItemMaxTotal=assignable and maxMade*crafts or nil,
        quantityAssignmentState=assignable and "SINGLE_CREATED_ITEM_MATCH" or
            "UI_QUANTITY_NOT_ASSIGNABLE_TO_NEW_ITEM",
        rawSourceBase=sourcePerCraft,
        rawSourceComparison=sourcePerCraft and
            (sourcePerCraft>=minMade and sourcePerCraft<=maxMade and
            "BASE_WITHIN_UI_RANGE" or "BASE_CONFLICTS_WITH_UI_RANGE") or "BASE_UNRESOLVED",
        noSeparateItemOutput=output.createdItemEffectCount==0 and
            output.enchantmentEffectCount>0 and output.unresolvedEffectCount==0,
        sourceReferenceConflict=output.sourceReferenceConflict,
        countGuarantee="UI_OBSERVATION_NOT_SERVER_CRAFT_RECEIPT",
        productionAuthority=false,executionEligible=false,nativeDispatchAllowed=false,
        readOnly=true},nil
end
function Engine:GetOutputWithMaterials(key,spellID,crafts,build)
    local output,why=self:GetRecipeOutput(key,spellID,crafts,build)
    if not output then return nil,why end
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    local materials,reason=ref:GetMaterialNeeds(key,spellID,crafts,build)
    return {contract="JLP-OUTPUT-MATERIAL-70450-1",sourceBuild=BUILD,
        professionKey=output.professionKey,spellID=spellID,crafts=crafts,output=output,
        materials=materials,materialsError=reason,combinedEconomyPriceState="NOT_CALCULATED",
        referenceOnly=true,readOnly=true,nativeDispatchAllowed=false}
end
function Engine:GetCoverage()
    local d=data();if not d then return nil,"OUTPUT_SOURCE_UNAVAILABLE" end
    local counts={}
    for k,v in pairs(d.meta or {}) do counts[k]=v end
    local actual=observedBuild()
    return {contract=self.contract,sourceBuild=BUILD,counts=counts,
        sourceSHA256=d.inputSHA256,observedClientBuild=actual,
        clientBuildRelation=actual==BUILD and "MATCH" or (actual and "MISMATCH" or "UNKNOWN"),
        referenceOnly=true,nativeDispatchAllowed=false,readOnly=true}
end
JLP:RegisterModule("Build70450CraftOutput",Engine)
