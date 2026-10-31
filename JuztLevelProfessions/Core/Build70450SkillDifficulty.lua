local _, JLP = ...
-- The owner-supplied SkillLineAbility DB2 snapshot is the sole difficulty source.
-- Only Yellow=TrivialSkillLineRankLow and Grey=TrivialSkillLineRankHigh exist.
-- Orange/Green are UNKNOWN. Never infer an intermediate midpoint, probability,
-- orange learn rank, trainer requirement, or native craft eligibility.
local Service={contract="JLP-BUILD70450-DIFFICULTY-READONLY-1",sourceBuild=70450,
    readOnly=true,productionAuthority=false,nativeDispatchAllowed=false,executionEligible=false}
local BUILD=70450
-- The DB2 reference proves field values, not the complete four-color transition
-- model of the Forever server. Client observations are single-rank snapshots.
local LIVE_TYPES={optimal="ORANGE",medium="YELLOW",easy="GREEN",trivial="GREY"}
local function liveBuild()
    local m=JLP:GetModule("ClientBuildInfo")
    if not m or type(m.GetBuildNumber)~="function" then return nil end
    local ok,n=pcall(m.GetBuildNumber,m)
    return ok and type(n)=="number" and n>0 and n<math.huge and n==math.floor(n) and n or nil
end
local function split(s,sep)
    local out={};local start=1
    while true do
        local at=s:find(sep,start,true)
        if not at then out[#out+1]=s:sub(start);return out end
        out[#out+1]=s:sub(start,at-1);start=at+#sep
    end
end
local function sourceLine(packed,id)
    local needle=tostring(id).."^";local from=1
    while true do
        local at=packed:find(needle,from,true)
        if not at then return nil end
        if at==1 or packed:sub(at-1,at-1)=="\n" then
            local ending=packed:find("\n",at,true)
            return packed:sub(at,ending and ending-1 or #packed)
        end
        from=at+#needle
    end
end
local SOURCE_HASH="df6018b459f851bdee27edfc74d2f45678177cba50aeed4bf12bc9d5fa4973e4"
local function integer(n,zero)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and
        n==math.floor(n) and n>=(zero and 0 or 1) and n<=999999999
end
local function evidence()
    local d=JLP.data and JLP.data.build70450DifficultyEvidence
    local r=JLP.data and JLP.data.build70450Recipes
    if type(d)~="table" or d.contract~="JLP-BUILD70450-DIFFICULTY-EVIDENCE-1" or
        d.sourceBuild~=BUILD or d.skillLineAbilitySHA256~=SOURCE_HASH or
        d.uniqueProfessionSpell~=2664 or type(d.professionCounts)~="table" or
        type(r)~="table" or r.sourceBuild~=BUILD or
        type(r.inputSHA256)~="table" or r.inputSHA256.SkillLineAbility~=SOURCE_HASH or
        r.inputSHA256.SkillLine~=d.skillLineSHA256 or
        r.inputSHA256.SpellName~=d.spellNameSHA256 then
        return nil,"DIFFICULTY_SOURCE_IDENTITY_MISMATCH"
    end
    return d,nil
end
function Service:ForDecodedRecipe(row)
    local e,why=evidence(); if not e then return nil,why end
    if type(row)~="table" or row.sourceBuild~=BUILD or
        type(row.professionKey)~="string" or not integer(row.spellID) or
        not integer(row.skillLineID) or type(row.skillLineAbilityIDs)~="table" then
        return nil,"INVALID_RECIPE_REFERENCE"
    end
    local m=e.professionCounts[row.professionKey]
    local recipes=JLP.data.build70450Recipes
    local p=recipes.professions and recipes.professions[row.professionKey]
    if not m or not p or p.skillLineID~=row.skillLineID then
        return nil,"PROFESSION_IDENTITY_CONFLICT"
    end
    -- Reject caller-supplied or accidentally corrupted thresholds. An input row
    -- is only a reference after every difficulty-bearing field is tied back to
    -- the canonical, build-pinned packed SkillLineAbility record.
    local packed=sourceLine(p.packed or "",row.spellID)
    local f=packed and split(packed,"^")
    if not f or #f~=12 then return nil,"SOURCE_SPELL_IDENTITY_MISMATCH" end
    local abilityIDs=split(f[2],",")
    if #abilityIDs~=#row.skillLineAbilityIDs then
        return nil,"DIFFICULTY_ABILITY_IDENTITY_MISMATCH"
    end
    for i,id in ipairs(abilityIDs) do
        if tonumber(id)~=row.skillLineAbilityIDs[i] then
            return nil,"DIFFICULTY_ABILITY_IDENTITY_MISMATCH"
        end
    end
    if tonumber(f[3])~=row.rawMinSkillLineRank or
        tonumber(f[4])~=row.rawYellowThreshold or
        tonumber(f[5])~=row.rawGreyThreshold then
        return nil,"DIFFICULTY_CANONICAL_FIELD_MISMATCH"
    end
    local yellow,grey=tonumber(f[4]),tonumber(f[5])
    if not integer(yellow,true) or not integer(grey,true) then
        return nil,"INVALID_RAW_THRESHOLD_FIELDS"
    end
    local status
    if yellow==0 and grey==0 then status="MISSING_BOTH_ZERO"
    elseif yellow>0 and grey>0 and yellow<grey then status="SOURCE_ORDERED"
    elseif yellow>0 and grey>0 and yellow==grey then status="SOURCE_EQUAL_YELLOW_GREY"
    elseif yellow>grey then status="SOURCE_INVERTED_CONFLICT"
    else status="PARTIAL_BOUNDARY_UNQUALIFIED" end
    local usable=(status=="SOURCE_ORDERED" or status=="SOURCE_EQUAL_YELLOW_GREY")
    local current=liveBuild()
    local relation=current==BUILD and "MATCH" or (current and "MISMATCH" or "UNKNOWN")
    return {contract=self.contract,sourceBuild=BUILD,
        professionKey=row.professionKey,skillLineID=row.skillLineID,spellID=row.spellID,
        skillLineAbilityIDs=row.skillLineAbilityIDs,
        observedClientBuild=current,clientBuildRelation=relation,
        sourceTable="SkillLineAbility",sourceSHA256=e.skillLineAbilitySHA256,
        rawMinSkillLineRank=row.rawMinSkillLineRank,
        rawTrivialSkillLineRankLow=yellow,rawTrivialSkillLineRankHigh=grey,
        orange=nil, yellow=usable and yellow or nil,
        green=nil, grey=usable and grey or nil,
        orangeStatus="UNKNOWN_NOT_IN_CLIENT_EXPORT",
        greenStatus="UNKNOWN_NOT_IN_CLIENT_EXPORT",
        orangeThresholdEvidence="ABSENT_IN_SKILLLINEABILITY",
        greenThresholdEvidence="ABSENT_IN_SKILLLINEABILITY",
        yellowEvidence=usable and "EXACT_CLIENT_DB2_FIELD" or "SOURCE_PRESENT_UNQUALIFIED",
        greyEvidence=usable and "EXACT_CLIENT_DB2_FIELD" or "SOURCE_PRESENT_UNQUALIFIED",
        yellowGreyState=status,allFourVerified=false,
        thresholdEvidenceState=usable and "PARTIAL_DB2_FIELD_PAIR_ONLY" or "UNQUALIFIED_DB2_FIELDS",
        exactFourColorBoundariesAvailable=false,
        numericBoundaryCount=usable and 2 or 0,
        learnSkillRank=nil,learnSkillState="UNKNOWN_NOT_DERIVED_FROM_MIN_SKILL_LINE_RANK",
        skillUpProbability=nil,skillUpProbabilityState="NOT_IN_SOURCE",
        skillBandProductionEligible=false,readOnly=true,
        nativeDispatchAllowed=false,executionEligible=false,productionAuthority=false},nil
end
function Service:GetDifficulty(key,spellID,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    if not integer(spellID) then return nil,"INVALID_SPELL_ID" end
    local _,why=evidence();if why then return nil,why end
    local c=JLP:GetModule("Build70450RecipeCatalogue")
    if not c then return nil,"RECIPE_CATALOGUE_UNAVAILABLE" end
    local recipe,err=c:GetRecipe(key,spellID,build)
    if not recipe then return nil,err end
    if recipe.skillDifficulty and recipe.skillDifficulty.contract==self.contract then
        return recipe.skillDifficulty,nil
    end
    return self:ForDecodedRecipe(recipe)
end
function Service:GetAtSkill(key,spellID,skill,build)
    if not integer(skill,true) or skill>9999 then return nil,"INVALID_SKILL_RANK" end
    local ref,why=self:GetDifficulty(key,spellID,build)
    if not ref then return nil,why end
    local region
    if ref.yellowGreyState~="SOURCE_ORDERED" and
       ref.yellowGreyState~="SOURCE_EQUAL_YELLOW_GREY" then
        region="UNQUALIFIED_SOURCE_THRESHOLDS"
    elseif skill>=ref.grey then
        region="AT_OR_ABOVE_GREY_BOUNDARY"
    elseif skill<ref.yellow then
        region="BELOW_YELLOW_BOUNDARY_ORANGE_NOT_VERIFIED"
    else
        region="YELLOW_OR_GREEN_BOUNDARY_UNRESOLVED"
    end
    return {contract="JLP-DIFFICULTY-RANK-70450-1",sourceBuild=BUILD,
        professionKey=ref.professionKey,spellID=ref.spellID,skill=skill,
        skillRegion=region,verifiedColor=nil,
        sourceImpliedColor=region=="AT_OR_ABOVE_GREY_BOUNDARY" and "GREY" or nil,
        sourceColorQualification="SOURCE_CUTOFF_ONLY_NOT_LIVE_OBSERVED",
        yellow=ref.yellow,grey=ref.grey,orange=nil,green=nil,
        exactFourColorClassificationVerified=false,readOnly=true,
        productionAuthority=false,nativeDispatchAllowed=false},nil
end
-- Read-only, opt-in observation of ONE color at ONE currently displayed skill.
-- Does not identify ANY four-color numeric boundary: a single UI point is not
-- evidence of the rank where a transition starts or ends.
function Service:GetLiveTradeSkillColor(key,spellID,index,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local clientBuild=liveBuild()
    if not clientBuild then return nil,"CLIENT_BUILD_UNKNOWN" end
    if not integer(index) or index>10000 then return nil,"INVALID_TRADESKILL_INDEX" end
    local ref,why=self:GetDifficulty(key,spellID,build)
    if not ref then return nil,why end
    if spellID==461692 then return nil,"AMBIGUOUS_PROFESSION_UI_CONTEXT" end
    local registry=JLP:GetModule("ProfessionRegistry")
    local definition=registry and registry:Get(ref.professionKey)
    if not definition or not definition.label then return nil,"PROFESSION_IDENTITY_UNAVAILABLE" end
    if type(GetTradeSkillRecipeLink)~="function" or
        type(GetTradeSkillInfo)~="function" or
        type(GetTradeSkillLine)~="function" then
        return nil,"TRADESKILL_UI_API_UNAVAILABLE"
    end
    local okLink,link=pcall(GetTradeSkillRecipeLink,index)
    if not okLink or type(link)~="string" then return nil,"TRADESKILL_LINK_UNAVAILABLE" end
    local typ,linkedID=link:match("|H([%a]+):(%d+)")
    if not linkedID then typ,linkedID=link:match("^([%a]+):(%d+)") end
    if (typ~="enchant" and typ~="spell") or tonumber(linkedID)~=spellID then
        return nil,"TRADESKILL_RECIPE_LINK_MISMATCH"
    end
    local okProf,profession,rank,maxRank=pcall(GetTradeSkillLine)
    if not okProf or type(profession)~="string" or
        profession:lower()~=definition.label:lower() or
        not integer(rank,true) or rank>9999 or
        not integer(maxRank,true) or maxRank>9999 or rank>maxRank then
        return nil,"TRADESKILL_PROFESSION_OR_RANK_UNVERIFIED"
    end
    local okRow,name,skillType=pcall(GetTradeSkillInfo,index)
    if not okRow or type(name)~="string" or name=="" or
        type(skillType)~="string" or not LIVE_TYPES[skillType] then
        return nil,"TRADESKILL_COLOR_UNAVAILABLE"
    end
    if liveBuild()~=clientBuild then return nil,"CLIENT_BUILD_CHANGED_DURING_OBSERVATION" end
    return {contract="JLP-DIFFICULTY-UI-OBSERVATION-70450-1",sourceBuild=BUILD,
        observedClientBuild=clientBuild,
        clientBuildRelation=clientBuild==BUILD and "MATCH" or "MISMATCH",
        professionKey=ref.professionKey,
        spellID=spellID,tradeSkillIndex=index,skillRank=rank,maxSkillRank=maxRank,
        observedColor=LIVE_TYPES[skillType],rawColor=skillType,
        recipeLink=link,recipeName=name,uiProfession=profession,
        orange=nil,yellow=ref.yellow,green=nil,grey=ref.grey,
        fourNumericThresholdsVerified=false,observationScope="SINGLE_CURRENT_SKILL_RANK",
        observationEvidence="LIVE_UI_RECIPE_LINK_AND_PROFESSION_MATCH",
        persisted=false,readOnly=true,executionEligible=false,
        productionAuthority=false,nativeDispatchAllowed=false},nil
end
function Service:GetCoverage()
    local e,why=evidence(); if not e then return nil,why end
    local p={}
    for k,v in pairs(e.professionCounts) do
        p[k]={total=v.total,ordered=v.ordered,equal=v.equal,missing=v.missing,
            conflict=v.conflict,fullFourColorVerified=0}
    end
    return {contract=self.contract,sourceBuild=BUILD,sourceSHA256=e.skillLineAbilitySHA256,
        sourceRows=e.totalAbilityRows,uniqueProfessionSpell=e.uniqueProfessionSpell,
        ordered=e.ordered,equal=e.equal,missing=e.missing,conflict=e.conflict,
        qualifiedYellowGrey=e.ordered+e.equal,
        qualifiedOrange=0,qualifiedGreen=0,allFourVerified=0,
        liveObservationsPersisted=0,allNumericThresholdsComplete=false,
        byProfession=p,readOnly=true,nativeDispatchAllowed=false,
        productionAuthority=false},nil
end
JLP:RegisterModule("Build70450SkillDifficulty",Service)
