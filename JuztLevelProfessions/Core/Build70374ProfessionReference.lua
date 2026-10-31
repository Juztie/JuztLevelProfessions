local _, JLP = ...
-- Build-pinned, read-only reference extracted exclusively from the owner's seven
-- 1.60.1.70374 CSV inputs. This does not replace native profession execution.
local Service = {
    contract="JLP-BUILD70374-PROFESSION-REFERENCE-1",
    readOnly=true, nativeDispatchAllowed=false, executionEligible=false,
    pageLimit=30,
}
local BUILD=70374
local function integer(v)
    return type(v)=="number" and v==math.floor(v) and v>0 and v<math.huge
end
local function data()
    local d=JLP.data and JLP.data.build70374Professions
    if type(d)~="table" or d.contract~="JLP-OWNER-BUILD70374-CSV-1" or d.sourceBuild~=BUILD then
        return nil
    end
    return d
end
local function profession(key)
    local registry=JLP:GetModule("ProfessionRegistry")
    local normalized=registry and registry:NormalizeKey(key)
    local d=data()
    local source=normalized and d and d.professions[normalized]
    if type(source)~="table" or type(source.packed)~="string" then return nil,nil end
    local def=registry:Get(normalized)
    if not def or def.skillLineID~=source.skillLineID then return nil,nil end
    return source,normalized
end
local function buildAllowed(clientBuild)
    -- An explicit input is required, because simply packaging the 70374 source
    -- does not establish which build the running WoW client actually uses.
    return integer(clientBuild) and clientBuild==BUILD
end
local function splitFields(line)
    local fields={}
    for value in (line.."^"):gmatch("(.-)%^") do fields[#fields+1]=value end
    if #fields~=9 then return nil end
    return fields
end
local function materialRows(raw)
    if raw=="?" then return nil,"SPELL_REAGENTS_RECORD_MISSING" end
    if raw=="-" then return {},"EMPTY_DB2_REAGENT_SLOTS" end
    local result,seen={},{}
    for part in raw:gmatch("[^,]+") do
        local id,quantity=part:match("^(%d+):(%d+)$")
        id=tonumber(id); quantity=tonumber(quantity)
        if not integer(id) or not integer(quantity) or seen[id] then
            return nil,"INVALID_DB2_REAGENT_ENTRY"
        end
        seen[id]=true
        result[#result+1]={itemID=id,quantity=quantity}
    end
    if #result==0 or #result>8 then return nil,"INVALID_DB2_REAGENT_COUNT" end
    return result,"RAW_CSV_REAGENT_COUNTS"
end
local function outputRows(raw)
    local result={}
    if raw=="-" then return result end
    for part in raw:gmatch("[^,]+") do
        local id,base,effect=part:match("^(%d+):([%-]?%d+):(%d+)$")
        id=tonumber(id);base=tonumber(base);effect=tonumber(effect)
        if not integer(id) or type(base)~="number" or
            (effect~=24 and effect~=157) then return nil end
        result[#result+1]={itemID=id,effectBasePoints=base,effectType=effect,
            quantityState="EFFECT_BASE_POINTS_NOT_VERIFIED_AS_CRAFT_YIELD"}
    end
    return result
end
local function fromLine(key,source,line)
    local f=splitFields(line)
    if not f then return nil,"MALFORMED_PACKED_ROW" end
    local id,ability,minRank,low,high,method=tonumber(f[1]),tonumber(f[2]),
        tonumber(f[3]),tonumber(f[4]),tonumber(f[5]),tonumber(f[6])
    if not integer(id) or not integer(ability) or not minRank or not low or
        not high or not method then return nil,"INVALID_SOURCE_NUMBERS" end
    local reagents,reagentStatus=materialRows(f[7])
    local outputs=outputRows(f[8])
    if outputs==nil then return nil,"INVALID_OUTPUT_EFFECT" end
    local isRecipe=reagents~=nil or #outputs>0
    local result={
        professionKey=key,skillLineID=source.skillLineID,
        recipeID=id,spellID=id,skillLineAbilityID=ability,name=f[9],
        recordKind=isRecipe and "RECIPE_REFERENCE" or "PROFESSION_ABILITY",
        reagents=reagents,reagentStatus=reagentStatus,outputs=outputs,
        -- These are literal DB2 fields, NOT validated recipe-learn gates or
        -- complete four-color difficulty boundaries.
        minSkillLineRankRaw=minRank,trivialRankLowRaw=low,trivialRankHighRaw=high,
        acquisitionMethodRaw=method,acquisitionActorState="UNKNOWN",
        acquisition={hordeQualified=nil,trainer=nil,vendor=nil,scroll=nil,drop=nil},
        sourceBuild=BUILD,evidenceState="RAW_OWNER_CSV",state="CANDIDATE",
        identityType="SPELL",readOnly=true,sourceQualified=false,
        verifiedFieldSet=false,productionAuthority=false,
        nativeDispatchAllowed=false,executionEligible=false,
        requiredSkillState="NOT_INDEPENDENTLY_VERIFIED",
        difficulty4State="NOT_AVAILABLE_FROM_CSV",
        outputYieldState="NOT_INDEPENDENTLY_VERIFIED",
        learnedState="UNKNOWN",clientSkillKnown=false,
        fieldProvenance={},qualifiedFields={},
        requirements={skill=nil},
        output={kind=#outputs>0 and "RAW_ITEM_EFFECT" or "UNKNOWN",
            itemID=#outputs==1 and outputs[1].itemID or nil,
            quantityMin=nil,quantityMax=nil},
    }
    return result,nil
end
local function findLine(packed,spellID)
    local needle=tostring(spellID).."^"
    local start=1
    while true do
        local pos=packed:find(needle,start,true)
        if not pos then return nil end
        if pos==1 or packed:sub(pos-1,pos-1)=="\n" then
            local stop=packed:find("\n",pos,true)
            return packed:sub(pos,stop and stop-1 or #packed)
        end
        start=pos+#needle
    end
end
function Service:GetRecipe(key,spellID,clientBuild)
    local src,normalized=profession(key)
    if not src then return nil,"UNKNOWN_PROFESSION" end
    if not buildAllowed(clientBuild) then return nil,"EXPLICIT_BUILD_70374_REQUIRED" end
    if not integer(spellID) then return nil,"INVALID_SPELL_ID" end
    local line=findLine(src.packed,spellID)
    if not line then return nil,"SPELL_NOT_IN_SOURCE_SKILL_LINE" end
    local row,why=fromLine(normalized,src,line)
    if not row then return nil,why end
    return row,nil
end
function Service:GetPage(key,offset,pageSize,clientBuild,recordKind)
    local src,normalized=profession(key)
    if not src then return nil,"UNKNOWN_PROFESSION" end
    if not buildAllowed(clientBuild) then return nil,"EXPLICIT_BUILD_70374_REQUIRED" end
    offset=offset or 0;pageSize=pageSize or 12
    if type(offset)~="number" or offset~=math.floor(offset) or offset<0 or
        type(pageSize)~="number" or pageSize~=math.floor(pageSize) or
        pageSize<1 or pageSize>self.pageLimit then return nil,"INVALID_PAGE" end
    if recordKind~=nil and recordKind~="RECIPE_REFERENCE" and
        recordKind~="PROFESSION_ABILITY" then return nil,"INVALID_RECORD_KIND" end
    local rows,total={},0
    for line in src.packed:gmatch("[^\n]+") do
        -- Only materialize the bounded window (plus optional record-kind filter).
        local matchesKind=true
        if recordKind then
            local f=splitFields(line)
            matchesKind=f and ((f[7]~="?" or f[8]~="-") and
                "RECIPE_REFERENCE" or "PROFESSION_ABILITY")==recordKind or false
        end
        if matchesKind then
            if total>=offset and #rows<pageSize then
                local row,why=fromLine(normalized,src,line)
                if not row then return nil,why end
                rows[#rows+1]=row
            end
            total=total+1
        end
    end
    return {contract="JLP-BUILD70374-RECIPE-PAGE-1",professionKey=normalized,
        sourceBuild=BUILD,rows=rows,total=total,offset=offset,pageSize=pageSize,
        recordKind=recordKind or "ALL_SKILL_LINE_ABILITIES",
        readOnly=true,nativeDispatchAllowed=false,sourceQualified=false},nil
end
-- Single-pass, bounded candidate lookup. No full profession index is cached,
-- so opening the economics/progression reference adds no persistent heap.
function Service:GetSkillCandidates(key,skill,offset,limit,clientBuild)
    local src,normalized=profession(key)
    if not src then return nil,"UNKNOWN_PROFESSION" end
    if not buildAllowed(clientBuild) then return nil,"EXPLICIT_BUILD_70374_REQUIRED" end
    if type(skill)~="number" or skill~=math.floor(skill) or skill<0 or skill>999 or
       type(offset)~="number" or offset~=math.floor(offset) or offset<0 or offset>10000 or
       type(limit)~="number" or limit~=math.floor(limit) or limit<1 or limit>self.pageLimit then
        return nil,"INVALID_CANDIDATE_QUERY"
    end
    local result,total={},0
    for line in src.packed:gmatch("[^\n]+") do
        local f=splitFields(line)
        if not f then return nil,"MALFORMED_PACKED_ROW" end
        local lo,hi=tonumber(f[4]),tonumber(f[5])
        if lo and hi and hi>0 and lo<=skill and hi>=skill and
           f[7]~="?" and f[7]~="-" then
            total=total+1
            if total>offset and #result<limit then
                local recipe,err=fromLine(normalized,src,line)
                if not recipe then return nil,err end
                if recipe.reagents and #recipe.reagents>0 then
                    result[#result+1]=recipe
                end
            end
        end
    end
    return {professionKey=normalized,skill=skill,total=total,offset=offset,
        limit=limit,rows=result,sourceBuild=BUILD,readOnly=true,
        nativeDispatchAllowed=false},nil
end
local function nameFromBucket(packed,id)
    if type(packed)~="string" then return nil end
    local needle=tostring(id).."\t"; local pos=packed:find(needle,1,true)
    while pos do
        if pos==1 or packed:sub(pos-1,pos-1)=="\n" then
            local stop=packed:find("\n",pos,true)
            return packed:sub(pos+#needle,stop and stop-1 or #packed)
        end
        pos=packed:find(needle,pos+#needle,true)
    end
    return nil
end
function Service:GetItem(itemID,clientBuild)
    if not buildAllowed(clientBuild) then return nil,"EXPLICIT_BUILD_70374_REQUIRED" end
    if not integer(itemID) then return nil,"INVALID_ITEM_ID" end
    local d=data();if not d then return nil,"SOURCE_UNAVAILABLE" end
    local name=nameFromBucket(d.itemBuckets[math.floor(itemID/1000)],itemID)
    if not name then return nil,"ITEM_NOT_IN_PROFESSION_REFERENCES" end
    return {itemID=itemID,name=name,sourceBuild=BUILD,
        provenance="OWNER_ITEMSSPARSE_CSV",readOnly=true},nil
end
-- Exact normalized item-name matches only; an item name is not evidence
-- that this item learns the named spell, nor that a vendor sells it.
function Service:GetRecipeAccessItemCandidates(key,spellID,clientBuild)
    local row,reason=self:GetRecipe(key,spellID,clientBuild)
    if not row then return nil,reason end
    local d=data()
    local line=findLine(d.recipeAccessItems or "",spellID)
    if not line then return {professionKey=row.professionKey,spellID=spellID,
        itemIDs={},state="RECIPE_ITEM_SOURCE_UNKNOWN",readOnly=true},nil end
    local ids={}
    local field=line:match("^%d+%^(.*)$") or ""
    for raw in field:gmatch("%d+") do
        local id=tonumber(raw)
        if integer(id) then ids[#ids+1]=id end
    end
    return {professionKey=row.professionKey,spellID=spellID,
        itemIDs=ids,state=#ids==1 and "NAME_MATCH_CANDIDATE" or
            "AMBIGUOUS_NAME_MATCH_CANDIDATES",sourceBuild=BUILD,
        acquisitionActorState="UNKNOWN",learnsSpellVerified=false,
        nativeDispatchAllowed=false,readOnly=true},nil
end
function Service:GetMaterialRequirements(key,spellID,crafts,clientBuild)
    if not integer(crafts) or crafts>9999 then return nil,"INVALID_CRAFT_COUNT" end
    local row,reason=self:GetRecipe(key,spellID,clientBuild)
    if not row then return nil,reason end
    if not row.reagents then return nil,row.reagentStatus end
    local requirements={}
    for _,v in ipairs(row.reagents) do
        local item=self:GetItem(v.itemID,clientBuild)
        requirements[#requirements+1]={itemID=v.itemID,name=item and item.name or nil,
            perCraft=v.quantity,rawTotal=v.quantity*crafts}
    end
    return {professionKey=row.professionKey,spellID=spellID,crafts=crafts,
        requirements=requirements,sourceBuild=BUILD,evidenceState="RAW_OWNER_CSV",
        totalsAreAdvisory=true,completeAsProductionEvidence=false,
        readOnly=true,nativeDispatchAllowed=false},nil
end
function Service:GetCoverage()
    local d=data();if not d then return nil,"SOURCE_UNAVAILABLE" end
    local byProfession={};local totalAbilities,totalReagentRows,totalOutputRows=0,0,0
    for key,s in pairs(d.professions) do
        byProfession[key]={skillLineID=s.skillLineID,skillLineAbilityRows=s.abilityRows,
            reagentRecordRows=s.reagentRecordRows,outputEffectRows=s.outputRows,
            perRecipeActorCompleteness="UNKNOWN",productionQualifiedRecipes=0}
        totalAbilities=totalAbilities+s.abilityRows
        totalReagentRows=totalReagentRows+s.reagentRecordRows
        totalOutputRows=totalOutputRows+s.outputRows
    end
    return {contract="JLP-BUILD70374-COVERAGE-1",sourceBuild=BUILD,
        professionCount=12,skillLineAbilityRows=totalAbilities,
        rowsWithReagents=totalReagentRows,rowsWithItemOutputs=totalOutputRows,
        byProfession=byProfession,namedProfessionItems=d.namedItemCount,
        recipeItemNameCandidateSpells=d.recipeItemCandidateSpellCount,
        ambiguousRecipeItemNameMatches=d.ambiguousRecipeItemSpellCount,
        allRecipeSourcesComplete=false,
        fullProductionCatalogueComplete=false,
        qualification="OWNER_CSV_REFERENCE_ONLY",nativeDispatchAllowed=false},nil
end
-- Existing trainer locations and recipe-source research remain separate;
-- caller receives a qualified location list only when the existing producer
-- independently qualifies it. Never infer an NPC actor from AcquireMethod=0.
function Service:GetKnownTrainers(key)
    local src=profession(key);if not src then return nil,"UNKNOWN_PROFESSION" end
    local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
    if not catalogue or type(catalogue.GetOwnerHordeTrainers)~="function" then
        return nil,"TRAINER_SERVICE_UNAVAILABLE"
    end
    return catalogue:GetOwnerHordeTrainers(key)
end
-- Owner-authored Horde/Neutral vendor lists are research only. A generic
-- profession material price or buy-price must never imply an NPC stock entry.
function Service:GetMaterialVendorResearch(key,itemID,clientBuild)
    local source,normalized=profession(key)
    if not source then return nil,"UNKNOWN_PROFESSION" end
    if not buildAllowed(clientBuild) then return nil,"EXPLICIT_BUILD_70374_REQUIRED" end
    local item,why=self:GetItem(itemID,clientBuild)
    if not item then return nil,why end
    local catalogue=JLP.data and JLP.data.professionSources
    local material=catalogue and catalogue.vendors and
        catalogue.vendors[normalized] and catalogue.vendors[normalized][item.name]
    if type(material)~="table" then return nil,"VENDOR_SOURCE_UNVERIFIED" end
    local actors={}
    for _,faction in ipairs({"Horde","Neutral"}) do
        for _,actor in ipairs(material.options and material.options[faction] or {}) do
            actors[#actors+1]={name=actor.name,zone=actor.zone,area=actor.area,
                faction=faction,locationSource=actor.evidence,
                currentBuildRecipeSourceVerified=false}
        end
    end
    if #actors==0 then return nil,"NO_HORDE_OR_NEUTRAL_VENDOR_REFERENCE" end
    return {professionKey=normalized,itemID=itemID,itemName=item.name,
        candidates=actors,sourceBuild=BUILD,quality="HISTORICAL_JLP_RESEARCH",
        vendorStockVerifiedAgainstBuild70374=false,
        nativeDispatchAllowed=false,readOnly=true},"HISTORICAL_VENDOR_RESEARCH_ADVISORY"
end
function Service:GetRecipeSourceResearch(key,spellID,clientBuild)
    local recipe,reason=self:GetRecipe(key,spellID,clientBuild)
    if not recipe then return nil,reason end
    local catalogue=JLP.data and JLP.data.professionSources
    local source=catalogue and catalogue.recipes and
        catalogue.recipes[key] and catalogue.recipes[key][recipe.name]
    if type(source)~="table" then return nil,"RECIPE_SOURCE_ACTOR_UNVERIFIED" end
    local actors={}
    for _,faction in ipairs({"Horde","Neutral"}) do
        for _,actor in ipairs(source.options and source.options[faction] or {}) do
            actors[#actors+1]={name=actor.name,zone=actor.zone,area=actor.area,
                faction=faction,locationSource=actor.evidence,
                currentBuildRecipeSourceVerified=false}
        end
    end
    return {contract="JLP-BUILD70374-RECIPE-SOURCE-RESEARCH-1",
        professionKey=key,spellID=spellID,name=recipe.name,
        sourceKind=source.kind,actors=actors,sourceBuild=BUILD,
        researchSourceBuild=source.capturedBuild,
        provenance=source.evidence,notes=source.note,
        recipeActorSourceQualified=false,
        nativeDispatchAllowed=false,readOnly=true},"HISTORICAL_RECIPE_SOURCE_ADVISORY"
end
JLP:RegisterModule("Build70374ProfessionReference",Service)
