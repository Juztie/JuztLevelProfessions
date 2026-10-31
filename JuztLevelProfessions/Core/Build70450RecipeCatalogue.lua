local _, JLP = ...
-- Build 70450 source snapshot. All output is advisory and non-executable.
-- This module NEVER alters M3/M4/M5's build-70374 execution/price gates.
local Catalogue = {contract="JLP-BUILD70450-RECIPE-READONLY-1",sourceBuild=70450,
    readOnly=true,nativeDispatchAllowed=false,executionEligible=false,pageLimit=30}
local BUILD=70450
local SPECIALIZATION_WORDS={
    {"gnomish","GNOMISH_ENGINEERING"},{"goblin","GOBLIN_ENGINEERING"},
    {"tribal","TRIBAL_LEATHERWORKING"},{"dragonscale","DRAGONSCALE_LEATHERWORKING"},
    {"elemental","ELEMENTAL_LEATHERWORKING"},{"armorsmith","ARMORSMITH"},
    {"weaponsmith","WEAPONSMITH"},
}
local function positive(x)
    return type(x)=="number" and x==x and x>0 and x<2147483647 and x==math.floor(x)
end
local function source()
    local d=JLP.data and JLP.data.build70450Recipes
    if type(d)~="table" or d.contract~="JLP-OWNER-BUILD70450-RECIPES-1" or
        d.sourceBuild~=BUILD or type(d.professions)~="table" then return nil end
    return d
end
local function definition(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    if not reg or not reg.NormalizeKey then return nil,"REGISTRY_UNAVAILABLE" end
    local k=reg:NormalizeKey(key)
    if not k then return nil,"UNKNOWN_PROFESSION" end
    local d=source();if not d then return nil,"SOURCE_UNAVAILABLE" end
    local definition=reg:Get(k)
    local entry=d.professions[k]
    if not definition or not entry or definition.skillLineID~=entry.skillLineID or
        type(entry.packed)~="string" then return nil,"REGISTRY_SKILLLINE_CONFLICT" end
    return entry,k
end
local function allowedBuild(build)
    return build==BUILD
end
local function currentBuild()
    local m=JLP:GetModule("ClientBuildInfo")
    if not m or type(m.GetBuildNumber)~="function" then return nil end
    local ok,n=pcall(m.GetBuildNumber,m)
    return ok and positive(n) and n or nil
end
local function split(s,sep)
    local out={};local start=1
    while true do
        local pos=s:find(sep,start,true)
        if not pos then out[#out+1]=s:sub(start);return out end
        out[#out+1]=s:sub(start,pos-1);start=pos+#sep
    end
end
local function materialList(raw)
    if raw=="?" then return nil,"NO_REAGENT_RECORD" end
    if raw=="-" then return {},"EMPTY_REAGENT_SLOTS" end
    local out={}
    for _,part in ipairs(split(raw,",")) do
        local id,quantity=part:match("^(%d+):(%d+)$")
        id,quantity=tonumber(id),tonumber(quantity)
        if not positive(id) or not positive(quantity) then return nil,"BAD_REAGENT_SLOT" end
        out[#out+1]={itemID=id,quantity=quantity,itemNameState="NOT_IN_70450_EXPORT"}
    end
    if #out>8 then return nil,"REAGENT_SLOT_OVERFLOW" end
    return out,"RAW_REAGENT_SLOTS"
end
local function outputList(raw)
    if raw=="-" then return {} end
    local out={}
    for _,part in ipairs(split(raw,",")) do
        local id,points,index=part:match("^(%d+):([%-%d%.]+):(%d+)$")
        id,index=tonumber(id),tonumber(index)
        if not positive(id) or index==nil or index<0 then return nil,"BAD_OUTPUT_EFFECT" end
        out[#out+1]={itemID=id,effectIndex=index,effectType=24,
            rawEffectBasePointsF=tonumber(points),outputQuantityState="UNVERIFIED"}
    end
    return out
end
local function path(categoryID)
    local d=source();local paths={};local visited={}
    local i=categoryID
    for _=1,12 do
        if not positive(i) then break end
        if visited[i] then return nil,"CATEGORY_CYCLE" end
        visited[i]=true
        local c=d.categories[i]
        if not c then return nil,"UNKNOWN_CATEGORY_ID" end
        paths[#paths+1]={categoryID=i,name=c[1],hordeName=c[2]~="" and c[2] or nil,
            parentID=c[3],categorySkillLineID=c[4],flags=c[5]}
        i=c[3]
    end
    return paths
end
local function decode(key,src,line)
    local f=split(line,"^")
    if #f~=12 then return nil,"PACKED_FIELD_COUNT_CONFLICT" end
    local id=tonumber(f[1]);local ids={}
    for _,val in ipairs(split(f[2],",")) do
        local n=tonumber(val)
        if not positive(n) then return nil,"INVALID_ABILITY_ID" end
        ids[#ids+1]=n
    end
    if not positive(id) or #ids<1 then return nil,"INVALID_SOURCE_IDENTITY" end
    local min,low,high,method,cat=tonumber(f[3]),tonumber(f[4]),tonumber(f[5]),tonumber(f[6]),tonumber(f[7])
    if not min or min<0 or not low or low<0 or not high or high<0 or not method or not cat then
        return nil,"INVALID_SOURCE_THRESHOLDS"
    end
    local reagents,reagentState=materialList(f[10])
    if not reagents and reagentState=="BAD_REAGENT_SLOT" then return nil,reagentState end
    local outputs,outputErr=outputList(f[11]);if not outputs then return nil,outputErr end
    local categories,categoryErr=path(cat);if not categories then return nil,categoryErr end
    local sod=false
    for _,c in ipairs(categories) do
        if c.name=="SEASON OF DISCOVERY" then sod=true end
    end
    local maskPresent=f[8]~="0" or f[9]~="0"
    local kind=(cat>0 or f[10]~="?" or #outputs>0) and "RECIPE_CANDIDATE" or "ABILITY_ONLY"
    local spec=nil;local lower=f[12]:lower()
    for _,pair in ipairs(SPECIALIZATION_WORDS) do
        if lower:find(pair[1],1,true) then spec=pair[2];break end
    end
    local actual=currentBuild()
    return {contract=Catalogue.contract,sourceBuild=BUILD,
        observedClientBuild=actual,clientBuildRelation=actual==BUILD and "MATCH" or
            (actual and "MISMATCH" or "UNKNOWN"),
        professionKey=key,skillLineID=src.skillLineID,spellID=id,recipeID=id,
        skillLineAbilityIDs=ids,duplicateSourceRows=#ids>1,
        name=f[12]~="" and f[12] or nil,
        nameEvidence=f[12]~="" and "SPELLNAME_70450" or "MISSING_IN_SOURCE_SPELLNAME",
        recordKind=kind,tradeSkillCategoryID=cat>0 and cat or nil,categoryPath=categories,
        seasonOfDiscoveryCategory=sod,phase="UNKNOWN",phaseAccessVerified=false,
        specializationNameHint=spec,specializationGate="UNKNOWN",
        factionAccess="UNKNOWN",factionGateVerified=false,
        rawRaceMasks=maskPresent and {f[8],f[9]} or nil,
        rawRaceMaskState=maskPresent and "PRESENT_NOT_DECODED" or "NOT_SPECIFIED_IN_ABILITY_ROW",
        rawAcquireMethod=method,sourceActor="UNKNOWN",sourceActorVerified=false,
        rawMinSkillLineRank=min,rawYellowThreshold=low,rawGreyThreshold=high,
        learnSkillRequirement="UNKNOWN",actualAvailability="UNKNOWN",
        learnedOnCharacter="UNKNOWN",reagents=reagents,reagentState=reagentState,
        outputs=outputs,outputQuantityVerified=false,
        referenceEvidence="OWNER_70450_CLIENT_TABLES",nativeDispatchAllowed=false,
        executionEligible=false,productionAuthority=false,readOnly=true},nil
end
local function findLine(packed,id)
    local needle=tostring(id).."^";local start=1
    while true do
        local pos=packed:find(needle,start,true)
        if not pos then return nil end
        if pos==1 or packed:sub(pos-1,pos-1)=="\n" then
            local finish=packed:find("\n",pos,true)
            return packed:sub(pos,finish and finish-1 or #packed)
        end
        start=pos+#needle
    end
end
-- One read-only qualification path for both direct and paginated references.
-- Paged progression must not silently omit source-backed output or item metadata.
local function qualify(row,preQualified)
    if not preQualified then
        local qa=JLP:GetModule("Build70450RecipeQualification")
        if not qa then return nil,"RECIPE_QUALIFICATION_UNAVAILABLE" end
        local why
        row,why=qa:Decorate(row)
        if not row then return nil,why end
    end
    local output=JLP:GetModule("Build70450CraftOutput")
    if output and output.ForKnownRecipe then
        local y,err=output:ForKnownRecipe(row.professionKey,row.spellID,1,BUILD)
        if not y then return nil,"OUTPUT_REFERENCE_"..tostring(err) end
        row.craftOutput=y
        row.craftOutputContract=y.contract
        row.craftOutputReferenceOnly=true
    end
    local difficulty=JLP:GetModule("Build70450SkillDifficulty")
    if difficulty then
        local result,err=difficulty:ForDecodedRecipe(row)
        if not result then return nil,"DIFFICULTY_REFERENCE_"..tostring(err) end
        row.skillDifficulty=result
    end
    local items=JLP:GetModule("Build70450ItemMetadata")
    if items then
        for _,r in ipairs(row.reagents or {}) do
            local m=items:GetItem(r.itemID,BUILD)
            if m then
                r.itemName=m.name;r.itemNameState=m.nameEvidence
                r.metadataSourceBuild=BUILD
            end
        end
    end
    return row,nil
end
function Catalogue:GetRecipe(key,spellID,build)
    if not allowedBuild(build) then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    if not positive(spellID) then return nil,"INVALID_SPELL_ID" end
    local src,k=definition(key);if not src then return nil,k end
    local line=findLine(src.packed,spellID)
    if not line then return nil,"SPELL_NOT_IN_70450_SKILL_LINE" end
    local row,why=decode(k,src,line)
    if not row then return nil,why end
    return qualify(row)
end
function Catalogue:GetPage(key,offset,limit,build,options)
    if not allowedBuild(build) then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local src,k=definition(key);if not src then return nil,k end
    offset=offset or 0;limit=limit or 20
    if type(offset)~="number" or offset<0 or offset~=math.floor(offset) or offset>100000 or
        type(limit)~="number" or limit<1 or limit>50 or limit~=math.floor(limit) then
        return nil,"INVALID_PAGE_BOUNDS"
    end
    options=type(options)=="table" and options or {}
    local rows={};local matching=0
    for line in src.packed:gmatch("[^\n]+") do
        local row,why=decode(k,src,line)
        if not row then return nil,why end
        local qa=JLP:GetModule("Build70450RecipeQualification")
        if not qa then return nil,"RECIPE_QUALIFICATION_UNAVAILABLE" end
        row,why=qa:Decorate(row)
        if not row then return nil,why end
        local include=(not options.recordKind or options.recordKind==row.recordKind) and
            (not options.categoryID or options.categoryID==row.tradeSkillCategoryID) and
            (options.sodOnly~=true or row.seasonOfDiscoveryCategory==true) and
            (options.unresolvedFaction~=true or row.rawRaceMasks~=nil) and
            (options.specializationHintsOnly~=true or row.specializationNameHint~=nil) and
            (options.issuesOnly~=true or #row.reviewCodes>0)
        if include and type(options.search)=="string" and options.search~="" then
            local find=options.search:lower()
            include=(row.name and row.name:lower():find(find,1,true)~=nil) or
                tostring(row.spellID)==find
        end
        if include then
            if matching>=offset and #rows<limit then
                row,why=qualify(row,true)
                if not row then return nil,why end
                rows[#rows+1]=row
            end
            matching=matching+1
        end
    end
    return {contract=Catalogue.contract,sourceBuild=BUILD,professionKey=k,
        offset=offset,pageSize=limit,totalMatches=matching,rows=rows,
        readOnly=true,nativeDispatchAllowed=false},nil
end
function Catalogue:GetMaterialNeeds(key,spellID,crafts,build)
    if not positive(crafts) or crafts>9999 then return nil,"INVALID_CRAFT_COUNT" end
    local row,why=self:GetRecipe(key,spellID,build);if not row then return nil,why end
    if row.recordKind~="RECIPE_CANDIDATE" then return nil,"NOT_A_CRAFTING_RECIPE" end
    if not row.reagents then return nil,row.reagentState end
    local totals={};local requirements={}
    for _,reagent in ipairs(row.reagents) do
        local total=reagent.quantity*crafts
        if total>999999999 then return nil,"MATERIAL_COUNT_TOO_LARGE" end
        totals[reagent.itemID]=(totals[reagent.itemID] or 0)+total
        if totals[reagent.itemID]>999999999 then return nil,"MATERIAL_COUNT_TOO_LARGE" end
    end
    for itemID,total in pairs(totals) do
        requirements[#requirements+1]={itemID=itemID,rawTotal=total,perCraft=total/crafts}
    end
    table.sort(requirements,function(a,b) return a.itemID<b.itemID end)
    local items=JLP:GetModule("Build70450ItemMetadata")
    if items then for _,r in ipairs(requirements) do
        local m=items:GetItem(r.itemID,BUILD)
        if m then r.itemName=m.name;r.itemNameState=m.nameEvidence end
    end end
    return {professionKey=row.professionKey,spellID=spellID,crafts=crafts,
        requirements=requirements,sourceBuild=BUILD,referenceOnly=true,
        sourceReagentState=row.reagentState,perCraftMaterialIDsVerifiedInSource=row.reagentState=="RAW_REAGENT_SLOTS",
        emptyReagentSlotsOnlySourceEvidence=row.reagentState=="EMPTY_REAGENT_SLOTS",
        productionReady=false,readOnly=true,nativeDispatchAllowed=false}
end
function Catalogue:GetCategory(categoryID)
    local d=source();if not d then return nil,"SOURCE_UNAVAILABLE" end
    if not positive(categoryID) then return nil,"INVALID_CATEGORY_ID" end
    local p,why=path(categoryID)
    if not p then return nil,why end
    return {categoryID=categoryID,path=p,sourceBuild=BUILD,readOnly=true}
end
function Catalogue:GetCoverage()
    local d=source();if not d then return nil,"SOURCE_UNAVAILABLE" end
    local qa=JLP:GetModule("Build70450RecipeQualification")
    if not qa then return nil,"RECIPE_QUALIFICATION_UNAVAILABLE" end
    local verified,why=qa:GetCoverage()
    if not verified then return nil,why end
    local per={}
    for key,src in pairs(d.professions) do
        per[key]={skillLineID=src.skillLineID,abilityRows=src.abilityRows,
            uniqueSpells=src.uniqueRows,recipeCandidates=src.recipeCandidates,
            abilityOnly=src.abilityOnly,reagentRecords=src.reagentRecords,
            missingSpellNames=src.missingSpellNames,
            seasonOfDiscoveryCategory=src.seasonOfDiscoveryTagRows}
    end
    local actual=currentBuild()
    return {contract=Catalogue.contract,sourceBuild=BUILD,observedClientBuild=actual,
        clientBuildRelation=actual==BUILD and "MATCH" or (actual and "MISMATCH" or "UNKNOWN"),
        professionCount=12,sourceRows=d.metadata.originalRows,
        uniqueProfessionSpellRecords=d.metadata.uniqueProfSpell,
        recipeCandidates=d.metadata.recipeCandidates,
        abilityOnly=d.metadata.abilityOnly,duplicateSourceRows=d.metadata.duplicateRows,
        missingFrom70374=d.metadata.missingFrom70374,
        sourceSHA256=d.inputSHA256,byProfession=per,
        taxonomySourceQualified=true,clientCSVIntegrityQualified=true,
        qualityAssurance=verified,
        factionRestrictionsFullyQualified=false,
        specializationRestrictionsFullyQualified=false,
        phaseAvailabilityFullyQualified=false,
        acquisitionSourcesFullyQualified=false,
        gameClientAvailabilityFullyQualified=false,
        referenceOnly=true,readOnly=true,nativeDispatchAllowed=false},nil
end
function Catalogue:GetMissingFrom70374()
    local d=source();if not d then return nil,"SOURCE_UNAVAILABLE" end
    local rows={}
    for key,ids in pairs(d.absentSince70374 or {}) do
        for _,id in ipairs(ids) do
            rows[#rows+1]={professionKey=key,spellID=id,
                priorSourceBuild=70374,currentSourceBuild=BUILD,
                status="NOT_IN_70450_PROFESSION_SKILL_LINE",
                removedFromGame="NOT_ESTABLISHED"}
        end
    end
    table.sort(rows,function(a,b) return a.spellID<b.spellID end)
    return {sourceBuild=BUILD,rows=rows,referenceOnly=true,readOnly=true}
end
function Catalogue:GetSkillRaceClassSource(key)
    local src,k=definition(key);if not src then return nil,k end
    local d=source();local packed=d.skillRaceClassInfo[k] or "";local rows={}
    for entry in packed:gmatch("[^;]+") do
        local f=split(entry,":")
        if #f==8 then rows[#rows+1]={rowID=tonumber(f[1]),classMaskRaw=f[2],
            flagsRaw=f[3],availabilityRaw=f[4],minLevelRaw=f[5],
            skillTierIDRaw=f[6],raceMasksRaw={f[7],f[8]}} end
    end
    return {professionKey=k,skillLineID=src.skillLineID,
        scope="SKILL_LINE_NOT_RECIPE",rows=rows,
        factionClaim="UNKNOWN",sourceBuild=BUILD,readOnly=true}
end
-- Raw ChrRaces/ChrClasses values are not a permit to decode opaque 64-bit
-- SkillLineAbility race masks or prove Alliance/Horde vendor availability.
function Catalogue:GetRaceReference(raceID)
    local d=source();if not d then return nil,"SOURCE_UNAVAILABLE" end
    if not positive(raceID) then return nil,"INVALID_RACE_ID" end
    local v=d.races and d.races[raceID]
    if not v then return nil,"RACE_NOT_IN_SNAPSHOT" end
    return {raceID=raceID,name=v[1],rawAllianceFlag=v[2],
        playableRaceBitRaw=v[3],factionIDRaw=v[4],sourceBuild=BUILD,
        factionTableState="RAW_CLIENT_TABLE",recipeAccessImplication="NONE",readOnly=true}
end
function Catalogue:GetClassReference(classID)
    local d=source();if not d then return nil,"SOURCE_UNAVAILABLE" end
    if not positive(classID) then return nil,"INVALID_CLASS_ID" end
    local name=d.classes and d.classes[classID]
    if not name then return nil,"CLASS_NOT_IN_SNAPSHOT" end
    return {classID=classID,name=name,sourceBuild=BUILD,
        recipeAccessImplication="NONE",readOnly=true}
end
JLP:RegisterModule("Build70450RecipeCatalogue",Catalogue)
