local _, JLP = ...
-- Build 70450 profession recipe qualification. Entirely reference-only.
-- DB2 spell/category records are not server trainer/vendor/loot/spec/faction grants.
local QA={contract="JLP-BUILD70450-RECIPE-QUALIFICATION-1",sourceBuild=70450,
    readOnly=true,productionAuthority=false,nativeDispatchAllowed=false,executionEligible=false}
local BUILD=70450
local ROOTS={TAILORING=197,ENCHANTING=333,ALCHEMY=171,BLACKSMITHING=164,
    ENGINEERING=202,LEATHERWORKING=165,HERBALISM=182,MINING=186,
    SKINNING=393,COOKING=185,FIRST_AID=129,FISHING=356}
local SPEC_HINTS={
    ENGINEERING={{"gnomish","GNOMISH_ENGINEERING"},{"goblin","GOBLIN_ENGINEERING"}},
    LEATHERWORKING={{"tribal","TRIBAL_LEATHERWORKING"},
        {"dragonscale","DRAGONSCALE_LEATHERWORKING"},
        {"elemental","ELEMENTAL_LEATHERWORKING"}},
    BLACKSMITHING={{"armorsmith","ARMORSMITH"},{"weaponsmith","WEAPONSMITH"}},
}
local function evidence()
    local q=JLP.data and JLP.data.build70450RecipeQA
    local d=JLP.data and JLP.data.build70450Recipes
    if type(q)~="table" or q.contract~="JLP-BUILD70450-RECIPE-QA-1" or
        q.sourceBuild~=BUILD or q.readOnly~=true or q.productionAuthority~=false or
        type(q.inputSHA256)~="table" or type(q.professionCounts)~="table" or
        type(q.exceptionRows)~="table" or type(d)~="table" or d.sourceBuild~=BUILD or
        type(d.inputSHA256)~="table" or type(d.metadata)~="table" then
        return nil,"RECIPE_QA_SOURCE_UNAVAILABLE"
    end
    for name,sha in pairs(q.inputSHA256) do
        if d.inputSHA256[name]~=sha then return nil,"RECIPE_QA_SHA_MISMATCH_"..name end
    end
    local m,e=d.metadata,q.expected
    if type(e)~="table" or m.originalRows~=e.sourceRows or
        m.uniqueProfSpell~=e.uniqueSpells or m.recipeCandidates~=e.recipeCandidates or
        m.abilityOnly~=e.abilityOnly then return nil,"RECIPE_QA_COUNTS_MISMATCH" end
    for key,skill in pairs(ROOTS) do
        local a,b=d.professions and d.professions[key],q.professionCounts[key]
        if not a or not b or a.skillLineID~=skill or a.abilityRows~=b.sourceRows or
            a.uniqueRows~=b.uniqueSpells or a.recipeCandidates~=b.recipeCandidates or
            a.abilityOnly~=b.abilityOnly then return nil,"RECIPE_QA_PROFESSION_MISMATCH_"..key end
    end
    return q,nil
end
local function castFocusEvidence()
    local q=JLP.data and JLP.data.build70450RecipeQA
    local f=q and q.castFocus70450
    -- Absence of an OPTIONAL workstation supplement cannot erase independent
    -- client-qualified recipe/reagent identity. A PRESENT but malformed or
    -- checksum-conflicting supplement remains a hard source-integrity error.
    if f==nil then return nil,"CAST_FOCUS_EVIDENCE_MISSING" end
    if type(f)~="table" or f.contract~="JLP-70450-CAST-FOCUS-REFERENCE-1"
        or f.sourceBuild~=BUILD or f.readOnly~=true or f.productionAuthority~=false
        or type(f.sourceSHA256)~="table"
        or f.sourceSHA256.SpellCastingRequirements~="c366a0de88b70dcf25b395a4377479bf772080810361e570490da959c24cfab5"
        or f.sourceSHA256.SpellFocusObject~="e0585e2650c2e7747eba4e62c2c92df7cdbe63122a333157854be2d088cabbe4"
        or type(f.spellToFocus)~="table" or type(f.focusNames)~="table"
        or f.matchedProfSpells~=1105 or f.matchedNamedFocus~=1105 then
        return nil,"CAST_FOCUS_SOURCE_UNAVAILABLE"
    end
    return f,nil
end
local function specializationHint(key,name)
    local list=SPEC_HINTS[key]
    if not list or type(name)~="string" then return nil end
    name=name:lower()
    for _,entry in ipairs(list) do
        if name:find(entry[1],1,true) then return entry[2] end
    end
    return nil
end
function QA:Decorate(row)
    local q,why=evidence();if not q then return nil,why end
    if type(row)~="table" or row.sourceBuild~=BUILD or
        row.skillLineID~=ROOTS[row.professionKey] or type(row.spellID)~="number" or
        type(row.categoryPath)~="table" or row.readOnly~=true or
        row.nativeDispatchAllowed~=false or row.executionEligible~=false then
        return nil,"INVALID_70450_RECIPE_REFERENCE"
    end
    local status="VALID_CLIENT_HIERARCHY"
    local path=row.categoryPath
    if not row.tradeSkillCategoryID or #path==0 then
        status="NO_CATEGORY_IN_SOURCE"
    elseif not path[1] or path[1].categoryID~=row.tradeSkillCategoryID or
        not path[#path] or path[#path].categorySkillLineID~=row.skillLineID then
        return nil,"CATEGORY_ROOT_PROFESSION_CONFLICT"
    end
    local flags={}
    if row.recordKind=="RECIPE_CANDIDATE" then
        if status~="VALID_CLIENT_HIERARCHY" then flags[#flags+1]=status end
        if row.reagentState=="NO_REAGENT_RECORD" then flags[#flags+1]="MISSING_REAGENT_ROW" end
    end
    if not row.name then flags[#flags+1]="MISSING_SPELL_NAME" end
    if row.duplicateSourceRows then flags[#flags+1]="DUPLICATE_ABILITY_IDENTITY" end
    if row.rawRaceMasks then flags[#flags+1]="OPAQUE_RACE_MASK_UNRESOLVED" end
    local hint=specializationHint(row.professionKey,row.name)
    if hint then flags[#flags+1]="SPECIALIZATION_NAME_HINT_NOT_GATE" end
    if row.seasonOfDiscoveryCategory then flags[#flags+1]="SOD_PHASE_NOT_VERIFIED" end
    -- This evidence is independent of reagent/yield/acquisition and server rights.
    -- Missing requirement row means UNKNOWN, never "no station needed".
    local station,stationReason=castFocusEvidence()
    if not station and stationReason~="CAST_FOCUS_EVIDENCE_MISSING" then
        return nil,stationReason
    end
    local focusID=station and station.spellToFocus[row.spellID] or nil
    if focusID~=nil then
        if type(focusID)~="number" or focusID<=0 or
            focusID~=math.floor(focusID) or
            type(station.focusNames[focusID])~="string" or
            station.focusNames[focusID]=="" then
            return nil,"CAST_FOCUS_IDENTITY_CONFLICT"
        end
        row.requiredSpellFocusID=focusID
        row.requiredSpellFocusName=station.focusNames[focusID]
        row.spellFocusRequirementStatus="DOCUMENTED_70450_CAST_FOCUS"
    else
        row.requiredSpellFocusID=nil
        row.requiredSpellFocusName=nil
        row.spellFocusRequirementStatus=station and
            "NO_CAST_REQUIREMENT_RECORD_IN_SOURCE" or "CAST_FOCUS_EVIDENCE_UNAVAILABLE"
    end
    row.spellFocusEvidenceBuild=station and BUILD or nil
    row.spellFocusRuntimeAvailable="UNKNOWN"
    row.specializationNameHint=hint -- limited to the 3 specializable profession families
    row.specializationGate="UNKNOWN"
    row.factionAccess="UNKNOWN"
    row.actualAvailability="UNKNOWN"
    row.categoryStatus=status
    row.categoryEvidence=status=="VALID_CLIENT_HIERARCHY" and
        "70450_TRADESKILL_CATEGORY_PARENT_CHAIN" or "UNRESOLVED_70450_CATEGORY"
    row.classificationEvidence="70450_SKILLLINEABILITY_CANDIDATE_HEURISTIC"
    row.recipeAvailabilityStatus="NOT_VERIFIED_ON_FOREVER_SERVER"
    row.specializationRequirementStatus="NOT_VERIFIED_ON_FOREVER_SERVER"
    row.specializationEvidence=hint and "NAME_HINT_ONLY_NOT_REQUIREMENT" or "NO_SPECIALIZATION_PROOF"
    row.factionRequirementStatus="NOT_VERIFIED_ON_FOREVER_SERVER"
    row.factionEvidence=row.rawRaceMasks and "OPAQUE_64_BIT_RACE_MASK" or "NO_RECIPE_FACTION_PROOF"
    row.acquisitionRequirementStatus="NOT_VERIFIED_ON_FOREVER_SERVER"
    row.phaseRequirementStatus="NOT_VERIFIED_ON_FOREVER_SERVER"
    row.catalogueVerification="CLIENT_SOURCE_INTEGRITY_ONLY"
    row.reviewCodes=flags
    row.qaContract=self.contract
    row.productionAuthority=false
    row.nativeDispatchAllowed=false
    row.executionEligible=false
    row.readOnly=true
    return row,nil
end
function QA:GetCoverage()
    local q,why=evidence();if not q then return nil,why end
    local p={}
    for key,c in pairs(q.professionCounts) do
        p[key]={sourceRows=c.sourceRows,uniqueSpells=c.uniqueSpells,
            recipeCandidates=c.recipeCandidates,abilityOnly=c.abilityOnly}
    end
    return {contract=self.contract,sourceBuild=BUILD,sourceRows=q.expected.sourceRows,
        uniqueSpells=q.expected.uniqueSpells,recipeCandidates=q.expected.recipeCandidates,
        abilityOnly=q.expected.abilityOnly,professionCount=12,byProfession=p,
        issueRows=#q.exceptionRows,sourceChecksums=q.inputSHA256,
        availabilityVerifiedLive=0,specializationRequirementsVerifiedLive=0,
        factionRequirementsVerifiedLive=0,productionAuthority=false,
        nativeDispatchAllowed=false,readOnly=true},nil
end
function QA:GetExceptions(key,offset,limit,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local q,why=evidence();if not q then return nil,why end
    if key~=nil then
        local r=JLP:GetModule("ProfessionRegistry")
        key=r and r:NormalizeKey(key)
        if not key then return nil,"UNKNOWN_PROFESSION" end
    end
    offset=offset or 0;limit=limit or 20
    if type(offset)~="number" or offset<0 or offset>100000 or offset~=math.floor(offset) or
        type(limit)~="number" or limit<1 or limit>30 or limit~=math.floor(limit) then
        return nil,"INVALID_PAGE_BOUNDS"
    end
    local result={};local count=0
    for _,e in ipairs(q.exceptionRows) do
        if not key or e[1]==key then
            if count>=offset and #result<limit then
                result[#result+1]={professionKey=e[1],spellID=e[2],code=e[3],
                    sourceBuild=BUILD,serverAvailability="UNKNOWN",productionAuthority=false}
            end
            count=count+1
        end
    end
    return {contract=self.contract,sourceBuild=BUILD,professionKey=key,
        offset=offset,limit=limit,totalMatches=count,rows=result,readOnly=true,
        nativeDispatchAllowed=false,productionAuthority=false},nil
end
JLP:RegisterModule("Build70450RecipeQualification",QA)
