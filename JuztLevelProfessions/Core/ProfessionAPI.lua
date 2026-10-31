local _, JLP = ...
local ProfessionAPI = {
    contract = "stable-id-profession-detection-v1",
    identityContract = "profession-stable-identity-v1",
    secondaryDetectionContract = "secondary-profession-detection-v1",
}

-- Name matching remains a last-resort compatibility fallback only. All known
-- Forever professions resolve through stable skill-line / Enum.Profession IDs.
local LEGACY_NAME_KEYS = {
    ["tailoring"] = "TAILORING",
    ["enchanting"] = "ENCHANTING",
    ["blacksmithing"] = "BLACKSMITHING",
    ["engineering"] = "ENGINEERING",
    ["alchemy"] = "ALCHEMY",
    ["leatherworking"] = "LEATHERWORKING",
    ["herbalism"] = "HERBALISM",
    ["mining"] = "MINING",
    ["skinning"] = "SKINNING",
    ["cooking"] = "COOKING",
    ["first aid"] = "FIRST_AID",
    ["firstaid"] = "FIRST_AID",
    ["fishing"] = "FISHING",
}

local function registry() return JLP:GetModule("ProfessionRegistry") end

local function professionLabel(key)
    local reg = registry()
    return reg and reg:GetDisplayName(key) or tostring(key or "Profession")
end

local function stableIdentity(name, skillLineID, professionEnum)
    local reg = registry()
    if reg then
        local key, reason = reg:ResolveStableIdentity(skillLineID, professionEnum)
        if key then
            return key, skillLineID and "skill-line-id" or "profession-enum"
        end
        -- A contradictory numeric identity must never silently become an
        -- English-name match. That would attach the wrong profession's data.
        if reason == "stable-identity-conflict" then
            return nil, "stable-identity-conflict"
        end
        if (tonumber(skillLineID) or 0)>0 or (tonumber(professionEnum) or -1)>=0 then
            return nil, "unrecognized-numeric-identity"
        end
    end
    local lower = string.lower(tostring(name or ""))
    local key = LEGACY_NAME_KEYS[lower]
    return key, key and "legacy-name-fallback" or nil
end

local function professionEnumForSkillLine(skillLineID)
    if not skillLineID or not C_TradeSkillUI or type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) ~= "function" then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
    if ok and type(info) == "table" then return tonumber(info.profession), info end
    return nil, nil
end

-- Transient provenance for a CURRENT character/API observation. This is not
-- reconstructed by KnowledgeCache and must never make saved skill live again.
local function currentObservationIdentity()
    local owner=JLP:GetModule("CharacterIdentity")
    local build=JLP:GetModule("ClientBuildInfo")
    local pass=JLP.GetObservationPass and JLP:GetObservationPass()
    local key=pass and pass.characterKey or (owner and type(owner.GetKey)=="function" and owner:GetKey(true) or nil)
    local number=build and type(build.GetBuildNumber)=="function" and build:GetBuildNumber() or nil
    if type(key)~="string" or key=="" or key:find("UnknownCharacter",1,true) or
       key:find("UnknownRealm",1,true) then key=nil end
    if type(number)~="number" or number<=0 or number~=math.floor(number) then number=nil end
    return key,number
end

local function remember(info)
    local cache = JLP:GetModule("KnowledgeCache")
    if cache and cache.RememberProfession then cache:RememberProfession(info) end
    return info
end

-- Direct rank fields are independent observations. Absence/invalidity must
-- reach the canonical cache as nil, never as an invented zero.
local function directRank(value)
    if type(value)=="number" and value==value and value>=0 and
       value<math.huge and value==math.floor(value) then return value,"OBSERVED" end
    return nil,value==nil and "MISSING" or "INVALID"
end

local function readProfession(index, source, primarySlot, deferRemember)
    if not index or type(GetProfessionInfo) ~= "function" then return nil end
    local infoOK, name, icon, skill, maxSkill, numAbilities, spellOffset, skillLine, skillModifier = pcall(GetProfessionInfo, index)
    if not infoOK or not name then return nil end
    local professionEnum = professionEnumForSkillLine(skillLine)
    local key, identitySource = stableIdentity(name, skillLine, professionEnum)
    if not key then return nil end
    local characterKey,observedClientBuild=currentObservationIdentity()
    local observedSkill,skillStatus=directRank(skill)
    local observedMax,maxStatus=directRank(maxSkill)
    local row={
        key = key,
        characterKey=characterKey,observedClientBuild=observedClientBuild,
        index = index,
        -- Position is part of the same live observation, before persistence.
        primarySlot = source == "get-professions-primary" and primarySlot or nil,
        name = name,
        icon = icon,
        skill = observedSkill,
        skillObservationStatus=skillStatus,
        maxSkillObservationStatus=maxStatus,
        skillModifier = (type(skillModifier)=="number" and skillModifier==skillModifier and skillModifier~=math.huge and skillModifier>=0) and skillModifier or nil,
        maxSkill = observedMax,
        skillLine = tonumber(skillLine),
        professionEnum = tonumber(professionEnum),
        identitySource = identitySource,
        detectionSource = source or "get-profession-info",
        cached = false,
    }
    return deferRemember and row or remember(row)
end

-- KnowledgeCache records an observed slot as history, not as an API
-- observation. A legacy/foreign/contradictory cache row has no slot proof.
local function historicalPrimarySlot(row,key,reg)
    local evidence=row.lastObservedPrimarySlotEvidence
    local n=row.lastObservedPrimarySlot
    local identity=JLP:GetModule("CharacterIdentity")
    local owner=identity and type(identity.GetKey)=="function" and identity:GetKey() or nil
    local def=reg and reg:Get(key)
    if (n==1 or n==2) and type(evidence)=="table" and def and
       def.category=="PRIMARY" and evidence.source=="get-professions-primary" and
       evidence.characterKey==owner and evidence.professionKey==key and
       type(evidence.clientBuild)=="number" and evidence.clientBuild>0 and
       evidence.clientBuild==math.floor(evidence.clientBuild) and
       evidence.skillLineID==tonumber(def.skillLineID) then return n end
    return nil
end

local function cachedDetected(category)
    local cache = JLP:GetModule("KnowledgeCache")
    local stored = cache and cache.GetProfessions and cache:GetProfessions() or {}
    local reg = registry()
    local out = {}
    for _, key in ipairs(reg and reg:GetKeys({category=category}) or {}) do
        local row = stored and stored[key]
        if type(row) == "table" then
            out[#out+1] = {
                key=key,
                index=nil,
                name=row.name or professionLabel(key) or key,
                icon=row.icon,
                skill=directRank(row.skill),
                maxSkill=directRank(row.maxSkill),
                skillLine=tonumber(row.skillLine) or (reg and reg:GetSkillLineID(key)),
                professionEnum=reg and reg:GetProfessionEnum(key) or nil,
                identitySource="registry-stable-id-cache",
                detectionSource="knowledge-cache",
                cached=true,
                -- Historic layout evidence only. SavedVariables must never
                -- be mistaken for a current GetProfessions observation.
                primarySlot=historicalPrimarySlot(row,key,reg),
                primarySlotHistorical=true,
                slotObservationSource="knowledge-cache",
            }
        end
    end
    return out
end

local function supplementalStableProfession(key)
    local reg = registry()
    if not reg or not C_TradeSkillUI or type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) ~= "function" then return nil end
    local skillLineID = reg:GetSkillLineID(key)
    if not skillLineID then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
    if not ok or type(info) ~= "table" then return nil end
    local resolved = reg:ResolveStableIdentity(skillLineID, info.profession)
    if resolved ~= key then return nil end
    local skill = tonumber(info.skillLevel) or 0
    local maxSkill = tonumber(info.maxSkillLevel) or 0
    -- Supplemental detection is used mainly for secondary professions not
    -- returned by GetProfessions (notably First Aid on Forever). Never infer a
    -- learned profession from a display name or a catalogue maximum alone.
    -- Without a GetProfessions index, an observed positive player skill is
    -- required; cap-only metadata cannot activate a secondary workflow.
    if skill <= 0 then return nil end
    local characterKey,observedClientBuild=currentObservationIdentity()
    return remember({
        key=key,
        characterKey=characterKey,observedClientBuild=observedClientBuild,
        index=nil,
        name=info.professionName or professionLabel(key),
        icon=nil,
        skill=skill,
        maxSkill=maxSkill,
        skillLine=tonumber(skillLineID),
        professionEnum=tonumber(info.profession),
        identitySource="skill-line-id",
        detectionSource="stable-id-query",
        cached=false,
    })
end

function ProfessionAPI:KeyForSkillLine(name, skillLineID)
    local professionEnum = professionEnumForSkillLine(skillLineID)
    return stableIdentity(name, skillLineID, professionEnum)
end

function ProfessionAPI:KeyForProfessionEnum(professionEnum)
    local reg = registry()
    local def = reg and reg:GetByProfessionEnum(professionEnum)
    return def and def.key or nil
end

function ProfessionAPI:GetStableSkillLineID(key)
    local reg = registry()
    return reg and reg:GetSkillLineID(key) or nil
end

-- Direct, validated base-panel observations establish live identity regardless of build.
-- GetTradeSkillLine is only a capability-gated numeric legacy fallback.
-- IsDataSourceChanging is optional; absent does not mean "stable" or "changing".
-- Neither a historical dataset nor an English name authorizes native execution.
local panelRevision = 0
local explicitPanelClosed = false
-- Source identity is volatile. Reuse the existing panel revision as its epoch;
-- KnowledgeCache remains the sole persistent facts owner. Missing source APIs
-- are UNKNOWN, never proof that the panel belongs to the player.
local ownSource
local sourceChanging = false
local function retireSource(reason,force)
    local prior=ownSource
    if not prior and not force then return end
    panelRevision=panelRevision+1
    ownSource=nil
    local cache=JLP:GetModule("KnowledgeCache")
    if cache and cache.InvalidateSessionObservations then cache:InvalidateSessionObservations() end
    local pass=JLP.GetObservationPass and JLP:GetObservationPass()
    if pass then pass.memo={};pass.memoCount=0 end
    if prior and JLP.MarkObservationsDirty then JLP:MarkObservationsDirty(reason,prior.professionKey) end
end
local function sourceWitness()
    if sourceChanging then return nil,"DATA_SOURCE_TRANSITION_PENDING" end
    local api=C_TradeSkillUI
    if type(api)~="table" then return nil,"TRADE_SKILL_API_UNAVAILABLE" end
    local owner=JLP:GetModule("CharacterIdentity")
    local key=owner and type(owner.GetKey)=="function" and owner:GetKey(true) or nil
    if type(key)~="string" or key=="" or key:find("UnknownCharacter",1,true) or
        key:find("UnknownRealm",1,true) then return nil,"CHARACTER_UNVERIFIED" end
    local witness={api=api,characterKey=key,baseProvider=api.GetBaseProfessionInfo,
        legacyProvider=api.GetTradeSkillLine,changingProvider=api.IsDataSourceChanging}
    for _,name in ipairs({"IsTradeSkillLinked","IsTradeSkillGuild","IsNPCCrafting","IsTradeSkillGuildMember"}) do
        local fn=api[name]
        if type(fn)~="function" then return nil,"OWN_SOURCE_CAPABILITY_UNAVAILABLE:"..name end
        witness[name]=fn
        local ok,value=pcall(fn)
        if not ok or type(value)~="boolean" or
            (type(issecretvalue)=="function" and issecretvalue(value)) then
            return nil,"OWN_SOURCE_RETURN_UNQUALIFIED:"..name
        end
        if value then return nil,"FOREIGN_PROFESSION_SOURCE:"..name end
    end
    return witness
end
local function sameWitness(a,b)
    if not a or not b then return false end
    for _,k in ipairs({"api","characterKey","baseProvider","legacyProvider","changingProvider",
        "IsTradeSkillLinked","IsTradeSkillGuild","IsNPCCrafting","IsTradeSkillGuildMember"}) do if a[k]~=b[k] then return false end end
    return true
end
local function counterValid(value)
    if type(issecretvalue)=="function" and issecretvalue(value) then return false end
    return value==nil or type(value)=="number" and value==value and value>=0 and
        value<math.huge and value==math.floor(value)
end
local function bindOwnSource(witness,key,line,enum,counter,buildToken)
    if not counterValid(counter) then retireSource("SOURCE_COUNTER_INVALID");return nil end
    local changed=not sameWitness(ownSource,witness) or not ownSource or
        ownSource.professionKey~=key or ownSource.line~=line or ownSource.enum~=enum or
        ownSource.counter~=counter or ownSource.buildToken~=buildToken
    if changed then
        retireSource("PROFESSION_SOURCE_CHANGED",true)
        witness.professionKey=key;witness.line=line;witness.enum=enum
        witness.counter=counter;witness.buildToken=buildToken;ownSource=witness
    end
    return panelRevision
end

local function readOpenBase()
    local api=C_TradeSkillUI
    if type(api)~="table" then return nil,"TRADE_SKILL_API_UNAVAILABLE" end
    if type(api.GetBaseProfessionInfo)~="function" then
        -- Capability-based support for older clients *only if* the legacy
        -- symbol really exists. A numeric, registry-known skillLineID and
        -- full live receipt are mandatory; historic names never authorize.
        if type(api.GetTradeSkillLine)~="function" then
            return nil,"BASE_PROFESSION_API_UNAVAILABLE"
        end
        local runtime=JLP:GetModule("RuntimeCompatibility")
        local receipt=runtime and type(runtime.GetSessionReceipt)=="function"
            and runtime:GetSessionReceipt() or nil
        if not receipt then return nil,"CLIENT_SESSION_UNVERIFIED" end
        local ok,observedLine,display=pcall(api.GetTradeSkillLine)
        local line=tonumber(observedLine)
        if not ok or not line or line<=0 or line~=math.floor(line) then
            return nil,"LEGACY_PROFESSION_ID_UNVERIFIED"
        end
        local reg=registry()
        local def=reg and reg:GetBySkillLineID(line)
        if not def then return nil,"LEGACY_PROFESSION_ID_UNKNOWN" end
        local sourceState=nil
        if type(api.IsDataSourceChanging)=="function" then
            local stateOK,changing=pcall(api.IsDataSourceChanging)
            if not stateOK or type(changing)~="boolean" or changing then
                return nil,"DATA_SOURCE_CHANGING_OR_UNKNOWN"
            end
            sourceState=false
        else
            -- No data-source indicator: re-read the live numeric line and
            -- reject a change before accepting this legacy-panel identity.
            local repeatOK,repeatLine=pcall(api.GetTradeSkillLine)
            if not repeatOK or tonumber(repeatLine)~=line then
                return nil,"LEGACY_PROFESSION_CHANGED_DURING_READ"
            end
        end
        local identity=JLP:GetModule("CharacterIdentity")
        local owner=identity and type(identity.GetKey)=="function" and identity:GetKey(true) or nil
        local build=JLP:GetModule("ClientBuildInfo")
        local liveBuild=build and type(build.GetBuildNumber)=="function" and build:GetBuildNumber() or nil
        if type(owner)~="string" or owner=="" or owner:find("UnknownCharacter",1,true) then
            return nil,"CHARACTER_UNVERIFIED"
        end
        if type(liveBuild)~="number" or liveBuild<=0 or liveBuild~=math.floor(liveBuild) then
            return nil,"CLIENT_BUILD_UNVERIFIED"
        end
        if runtime:GetSessionReceipt()~=receipt then return nil,"CLIENT_SESSION_CHANGED" end
        return {professionKey=def.key,baseSkillLineID=line,
            professionEnum=def.professionEnum,registryProfessionEnum=def.professionEnum,
            observedProfessionEnum=nil,displayName=display,
            identitySource="legacy-numeric-skill-line",build=liveBuild,
            clientBuildToken=receipt,characterKey=owner,verified=true,
            legacyNumericIdentity=true,dataSourceChanging=sourceState,
            dataSourceState=sourceState==false and "OBSERVED_STABLE" or "API_UNAVAILABLE"},nil
    end
    -- A panel's current identity is established by observed build+interface,
    -- never by a hardcoded build or an interface fallback constant.
    local runtime=JLP:GetModule("RuntimeCompatibility")
    local startReceipt=runtime and type(runtime.GetSessionReceipt)=="function"
        and runtime:GetSessionReceipt() or nil
    if not startReceipt then return nil,"CLIENT_SESSION_UNVERIFIED" end
    local ok,info=pcall(api.GetBaseProfessionInfo)
    if not ok or type(info)~="table" then return nil,"BASE_PROFESSION_API_ERROR" end
    if not counterValid(info.sourceCounter) then return nil,"SOURCE_COUNTER_INVALID" end
    local base=tonumber(info.professionID)
    local reg=registry()
    local def=reg and reg:GetBySkillLineID(base)
    if not def then return nil,"UNKNOWN_BASE_PROFESSION_ID" end
    -- The observed numeric enum is a *separate* panel identity signal, not
    -- a value which may be silently replaced by the registry's expected enum.
    -- In particular, zero is First Aid's valid Enum.Profession value.
    local observedEnum=info.profession
    if observedEnum==nil then return nil,"BASE_PROFESSION_ENUM_MISSING" end
    if type(observedEnum)~="number" then return nil,"BASE_PROFESSION_ENUM_NON_NUMERIC" end
    if observedEnum~=observedEnum or observedEnum<0 or observedEnum==math.huge or
        observedEnum~=math.floor(observedEnum) then
        return nil,"BASE_PROFESSION_ENUM_INVALID"
    end
    local expectedEnum=tonumber(def.professionEnum)
    if expectedEnum==nil then return nil,"REGISTRY_PROFESSION_ENUM_MISSING" end
    if observedEnum~=expectedEnum then return nil,"BASE_PROFESSION_ENUM_CONFLICT" end
    local sourceState=nil
    if type(api.IsDataSourceChanging)=="function" then
        local stateOK,changing=pcall(api.IsDataSourceChanging)
        -- An installed but malfunctioning indicator is not "unavailable":
        -- avoid promoting ambiguous/active transition into live authority.
        if not stateOK or type(changing)~="boolean" or changing then
            return nil,"DATA_SOURCE_CHANGING_OR_UNKNOWN"
        end
        sourceState=false
    else
        -- Optional API is absent. Corroborate the stable numeric panel identity
        -- from two client reads under the SAME session receipt instead.
        local secondOK,second=pcall(api.GetBaseProfessionInfo)
        if not secondOK or type(second)~="table" or
            tonumber(second.professionID)~=base or
            second.profession~=observedEnum then
            return nil,"BASE_PROFESSION_CHANGED_DURING_READ"
        end
    end
    local build=JLP:GetModule("ClientBuildInfo")
    local liveBuild=build and build.GetBuildNumber and build:GetBuildNumber()
    local ident=JLP:GetModule("CharacterIdentity")
    local character=ident and ident.GetKey and ident:GetKey(true)
    if type(liveBuild)~="number" or liveBuild~=math.floor(liveBuild) or liveBuild<=0 then
        return nil,"CLIENT_BUILD_UNVERIFIED"
    end
    if type(character)~="string" or character=="" or
        tostring(character):find("UnknownCharacter",1,true) then
        return nil,"CHARACTER_UNVERIFIED"
    end
    local endReceipt=runtime:GetSessionReceipt()
    if not endReceipt or endReceipt~=startReceipt then
        return nil,"CLIENT_SESSION_CHANGED"
    end
    local skill=tonumber(info.skillLevel)
    local maxSkill=tonumber(info.maxSkillLevel)
    -- Both identity signals must be observed and agree with the registry.
    return {professionKey=def.key,baseSkillLineID=base,
        professionEnum=observedEnum,observedProfessionEnum=observedEnum,
        registryProfessionEnum=expectedEnum,skill=skill,maxSkill=maxSkill,
        displayName=info.professionName,identitySource="base-profession-info",
        build=liveBuild,clientBuildToken=startReceipt,
        characterKey=character,sourceCounter=info.sourceCounter,dataSourceChanging=sourceState,
        dataSourceState=sourceState==false and "OBSERVED_STABLE" or "API_UNAVAILABLE",
        verified=true},nil
end

function ProfessionAPI:GetOpenProfessionContext()
    if explicitPanelClosed then
        return {verified=false,reason="TRADE_SKILL_PANEL_CLOSED",identitySource="unknown"}
    end
    local before,why=sourceWitness()
    if not before then retireSource(why);return {verified=false,reason=why,identitySource="unknown"} end
    local ctx,reason=readOpenBase()
    local again=ctx and readOpenBase() or nil
    local after,sourceWhy=sourceWitness()
    if not ctx or not again or not sameWitness(before,after) or
        ctx.characterKey~=before.characterKey or again.characterKey~=before.characterKey or
        ctx.professionKey~=again.professionKey or ctx.baseSkillLineID~=again.baseSkillLineID or
        ctx.professionEnum~=again.professionEnum or ctx.clientBuildToken~=again.clientBuildToken or
        ctx.sourceCounter~=again.sourceCounter or not counterValid(ctx.sourceCounter) then
        -- Native-session evidence and read-only source evidence are independent.
        -- An unavailable client receipt cannot change a stable source epoch.
        -- A read-only consumer must still re-read identity/counter before use.
        if reason~="CLIENT_SESSION_UNVERIFIED" or not sameWitness(before,after) then
            retireSource(reason or sourceWhy or "PROFESSION_SOURCE_CHANGED_DURING_READ")
        end
        return {verified=false,reason=reason or sourceWhy or "PROFESSION_SOURCE_CHANGED_DURING_READ",identitySource="unknown"}
    end
    local epoch=bindOwnSource(after,ctx.professionKey,ctx.baseSkillLineID,ctx.professionEnum,
        ctx.sourceCounter,ctx.clientBuildToken)
    if not epoch then return {verified=false,reason="SOURCE_COUNTER_INVALID",identitySource="unknown"} end
    ctx.panelToken=table.concat({ctx.characterKey,ctx.clientBuildToken,ctx.professionKey,
        ctx.baseSkillLineID,tostring(epoch)},"|")
    ctx.panelRevision=epoch;ctx.sourceEpoch=epoch;ctx.sourceOwnership="OWN_SOURCE_OBSERVED"
    ctx.sourceCounterStatus=ctx.sourceCounter~=nil and "OBSERVED" or "UNAVAILABLE"
    return ctx
end

function ProfessionAPI:InvalidateOpenProfessionContext(reason)
    if reason=="TRADE_SKILL_CLOSE" then explicitPanelClosed=true
    elseif reason=="TRADE_SKILL_SHOW" then explicitPanelClosed=false end
    if reason=="TRADE_SKILL_DATA_SOURCE_CHANGING" then sourceChanging=true
    elseif reason=="TRADE_SKILL_DATA_SOURCE_CHANGED" then sourceChanging=false end
    -- Explicit lifecycle observations retire all pending/current source proofs.
    retireSource(reason or "PROFESSION_PANEL_INVALIDATED",true)
end

-- Unified, transient Forever profession/recipe contract. No historical dataset,
-- SavedVariables recipe-name cache or fixed client build can establish native
-- recipe authority. A recipe is checked against the *same* open panel and
-- client receipt both before and after API access.
local function validRecipeID(value)
    return type(value)=="number" and value>0 and value==math.floor(value) and value<2147483648
end

local function validArrayIDs(rows)
    if type(rows)~="table" then return nil,"RECIPE_LIST_INVALID" end
    local n,max,seen,counts=0,0,{},{ }
    for key,id in pairs(rows) do
        if not validRecipeID(key) or key>100000 or not validRecipeID(id) then
            return nil,"RECIPE_LIST_INVALID"
        end
        n=n+1;max=math.max(max,key)
        -- Forever GetAllRecipeIDs has been observed to include repeated IDs.
        -- Presence is a set; multiplicity remains part of the stability proof.
        seen[id]=true;counts[id]=(counts[id] or 0)+1
    end
    if n~=max then return nil,"RECIPE_LIST_SPARSE" end
    return seen,nil,counts
end

function ProfessionAPI:GetRecipeContext(recipeID, expectedKey)
    local result={contract="profession-recipe-context-v2",verified=false,
        recipeID=tonumber(recipeID),expectedProfessionKey=expectedKey,
        visible=false,learned=nil,recipeInfo=nil,reason="UNVERIFIED"}
    if not validRecipeID(result.recipeID) then
        result.reason="RECIPE_ID_INVALID";return result
    end
    local panel=self:GetOpenProfessionContext()
    result.panel=panel
    if not panel or panel.verified~=true then
        result.reason=panel and panel.reason or "PROFESSION_PANEL_UNVERIFIED";return result
    end
    result.professionKey=panel.professionKey
    result.skillLineID=panel.baseSkillLineID
    result.clientSessionToken=panel.clientBuildToken
    result.panelToken=panel.panelToken
    result.panelRevision=panel.panelRevision
    if expectedKey~=nil and expectedKey~=panel.professionKey then
        result.reason="PROFESSION_MISMATCH";return result
    end
    local client=C_TradeSkillUI
    if type(client)~="table" or type(client.GetAllRecipeIDs)~="function"
        or type(client.GetRecipeInfo)~="function" then
        result.reason="RECIPE_API_UNAVAILABLE";return result
    end
    local ok,rows=pcall(client.GetAllRecipeIDs)
    if not ok then result.reason="RECIPE_LIST_API_ERROR";return result end
    local seen,why,firstCounts=validArrayIDs(rows)
    if not seen then result.reason=why;return result end
    if not seen[result.recipeID] then
        result.reason="RECIPE_NOT_IN_OPEN_PANEL";return result
    end
    result.visible=true
    if type(client.GetTradeSkillLineForRecipe)=="function" then
        -- Documented positional returns: skillLineID, localizedName,
        -- parentSkillLineID. pcall inserts a leading success boolean.
        local lineOK,child,localizedLineName,parent=pcall(client.GetTradeSkillLineForRecipe,result.recipeID)
        if not lineOK or not validRecipeID(tonumber(child)) then
            result.reason="RECIPE_LINE_UNVERIFIED";return result
        end
        local reg=registry()
        -- A malformed parent is not "missing parent": it must not fall
        -- through into the historical CSV mapping and manufacture authority.
        if parent~=nil and type(parent)~="number" then
            result.reason="RECIPE_PARENT_INVALID";return result
        end
        result.recipeSkillLineID=tonumber(child)
        result.recipeSkillLineName=type(localizedLineName)=="string" and localizedLineName or nil
        result.recipeParentSkillLineID=tonumber(parent)
        local lineage=reg and reg.ResolveRecipeLineage and
            reg:ResolveRecipeLineage(panel.professionKey,result.recipeSkillLineID,
                result.recipeParentSkillLineID,result.recipeID,"LIVE_PANEL_RECIPE_API") or "UNKNOWN_IDENTITY"
        result.lineage=lineage
        if lineage~="EXACT_BASE_MATCH" and lineage~="VERIFIED_DESCENDANT_MATCH" then
            result.reason="RECIPE_LINE_"..tostring(lineage);return result
        end
    else
        result.lineage="API_UNAVAILABLE"
        -- Absence of this optional API does not remove verified list/name
        -- observations; it also never creates a lineage assertion.
    end
    local infoOK,info=pcall(client.GetRecipeInfo,result.recipeID)
    if not infoOK or type(info)~="table" or type(info.name)~="string" or info.name=="" then
        result.reason="RECIPE_INFO_UNAVAILABLE";return result
    end
    if info.recipeID~=nil and tonumber(info.recipeID)~=result.recipeID then
        result.reason="RECIPE_INFO_ID_CONFLICT";return result
    end
    -- Copy only stable primitive fields; never expose an API-owned mutable
    -- object as a persisted or transferable execution proof.
    local snapshot={name=info.name}
    if type(info.learned)=="boolean" then snapshot.learned=info.learned end
    if info.recipeID~=nil then snapshot.recipeID=tonumber(info.recipeID) end
    result.recipeInfo=snapshot
    result.name=info.name
    if type(info.learned)=="boolean" then result.learned=info.learned end
    -- Callbacks can switch the panel, data-source or client identity. Repeat
    -- panel validation and the recipe list check before promoting the result.
    local after=self:GetOpenProfessionContext()
    if not after or after.verified~=true or
       after.panelToken~=panel.panelToken or
       after.panelRevision~=panel.panelRevision then
        result.reason="PROFESSION_CONTEXT_CHANGED";return result
    end
    local againOK,againRows=pcall(client.GetAllRecipeIDs)
    if not againOK then result.reason="RECIPE_LIST_CHANGED";return result end
    local again,againWhy,laterCounts=validArrayIDs(againRows)
    if not again then result.reason=againWhy;return result end
    -- A provider must not change membership OR duplicate multiplicity during
    -- an observation. Merely comparing unique IDs would miss that mutation.
    for id,count in pairs(firstCounts) do
        if laterCounts[id]~=count then
            result.reason="RECIPE_LIST_CHANGED";return result
        end
    end
    for id,count in pairs(laterCounts) do
        if firstCounts[id]~=count then
            result.reason="RECIPE_LIST_CHANGED";return result
        end
    end
    local final=self:GetOpenProfessionContext()
    if not final or final.verified~=true or final.panelToken~=panel.panelToken
       or final.panelRevision~=panel.panelRevision then
        result.reason="PROFESSION_CONTEXT_CHANGED";return result
    end
    result.verified=true
    result.reason="OK"
    return result
end

-- P1-176: volatile, explicitly READ-ONLY profession evidence. This path is
-- independent of a complete build+interface receipt, but cannot satisfy
-- GetOpenProfessionContext / GetRecipeContext / GetExecutionRecipeContext or
-- any native dispatch / persisted learned / auto-completion contract.
function ProfessionAPI:GetReadOnlyProfessionObservation()
    local result={contract="volatile-live-profession-observation-v1",readOnly=true,
        nativeDispatchAllowed=false,executionEligible=false,sessionVerified=false,
        observed=false,verified=false,reason="UNVERIFIED"}
    if explicitPanelClosed then result.reason="TRADE_SKILL_PANEL_CLOSED";return result end
    local witness,sourceWhy=sourceWitness()
    if not witness then retireSource(sourceWhy);result.reason=sourceWhy;return result end
    local api=C_TradeSkillUI
    if type(api)~="table" or type(api.GetBaseProfessionInfo)~="function" then
        result.reason="BASE_PROFESSION_API_UNAVAILABLE";return result
    end
    local provider=api.GetBaseProfessionInfo
    local stateProvider=api.IsDataSourceChanging
    local identity=JLP:GetModule("CharacterIdentity")
    if not identity or type(identity.GetKey)~="function" then
        result.reason="CHARACTER_IDENTITY_UNAVAILABLE";return result
    end
    local function read()
        if C_TradeSkillUI~=api or api.GetBaseProfessionInfo~=provider or
            api.IsDataSourceChanging~=stateProvider then return nil,"API_PROVIDER_CHANGED" end
        if type(stateProvider)=="function" then
            local ok,changing=pcall(stateProvider)
            if not ok or changing~=false then return nil,"DATA_SOURCE_CHANGING_OR_UNKNOWN" end
        end
        local ok,info=pcall(provider)
        if not ok or type(info)~="table" then return nil,"BASE_PROFESSION_API_ERROR" end
        local line=info.professionID
        local enum=info.profession
        -- The enum is nullable; the observed skill-line binds these read-only fields.
        -- Keep native identity strict and never fill an absent enum from the registry.
        if type(line)~="number" or line<=0 or line~=math.floor(line) or
            (enum~=nil and (type(enum)~="number" or enum<0 or enum~=math.floor(enum) or
            enum==math.huge)) then return nil,"BASE_PROFESSION_IDENTITY_INVALID" end
        local def=registry() and registry():GetBySkillLineID(line)
        if not def or (enum~=nil and tonumber(def.professionEnum)~=enum) then
            return nil,"BASE_PROFESSION_IDENTITY_CONFLICT" end
        local skill,maxSkill=info.skillLevel,info.maxSkillLevel
        if type(skill)~="number" or type(maxSkill)~="number" or
            skill~=skill or maxSkill~=maxSkill or skill<0 or maxSkill<=0 or
            skill>maxSkill or maxSkill==math.huge or
            skill~=math.floor(skill) or maxSkill~=math.floor(maxSkill) then
            return nil,"PROFESSION_SKILL_INVALID"
        end
        local owner=identity:GetKey(true)
        if type(owner)~="string" or owner=="" or
            owner:find("UnknownCharacter",1,true) or
            owner:find("UnknownRealm",1,true) then return nil,"CHARACTER_UNVERIFIED" end
        local buildModule=JLP:GetModule("RuntimeCompatibility")
        local buildInfo=buildModule and type(buildModule.Read)=="function" and buildModule:Read() or nil
        if not counterValid(info.sourceCounter) then return nil,"SOURCE_COUNTER_INVALID" end
        return {key=def.key,line=line,enum=enum,skill=skill,maxSkill=maxSkill,counter=info.sourceCounter,
            owner=owner,build=buildInfo and buildInfo.clientBuild or nil,
            buildToken=buildInfo and buildInfo.clientBuildToken or nil,
            sessionVerified=buildInfo and buildInfo.clientSessionVerified==true or false},nil
    end
    local initial,why=read()
    if not initial then retireSource(why);result.reason=why;return result end
    local again,why2=read()
    if not again then retireSource(why2);result.reason=why2;return result end
    local after,afterWhy=sourceWitness()
    if not sameWitness(witness,after) or initial.owner~=witness.characterKey or
        initial.counter~=again.counter or initial.key~=again.key or initial.line~=again.line or initial.enum~=again.enum or
        initial.skill~=again.skill or initial.maxSkill~=again.maxSkill or
        initial.owner~=again.owner or initial.build~=again.build or
        initial.buildToken~=again.buildToken or initial.sessionVerified~=again.sessionVerified or
        explicitPanelClosed or api.GetBaseProfessionInfo~=provider then
        retireSource(afterWhy or "LIVE_PANEL_CHANGED_DURING_READ")
        result.reason=afterWhy or "LIVE_PANEL_CHANGED_DURING_READ";return result
    end
    local epoch=bindOwnSource(after,initial.key,initial.line,initial.enum,initial.counter,initial.buildToken)
    if not epoch then result.reason="SOURCE_COUNTER_INVALID";return result end
    result.sourceEpoch=epoch;result.sourceCounter=initial.counter
    result.sourceCounterStatus=initial.counter~=nil and "OBSERVED" or "UNAVAILABLE"
    result.sourceOwnership="OWN_SOURCE_OBSERVED"
    result.observed=true
    result.professionKey=initial.key
    result.baseSkillLineID=initial.line
    result.professionEnum=initial.enum
    result.skill=initial.skill
    result.maxSkill=initial.maxSkill
    result.characterKey=initial.owner
    result.clientBuild=initial.build
    result.observationQuality=initial.sessionVerified and "FULL_SESSION_READ_ONLY" or
        (initial.build and "BUILD_ONLY_VOLATILE" or "UNVERSIONED_VOLATILE")
    -- A volatile marker has no cross-reload authority and must never be saved
    -- in an execution receipt. Panel revision changes on observed open/close.
    result.observationToken=table.concat({initial.owner,initial.key,
        tostring(initial.line),tostring(initial.enum),tostring(epoch)},"|")
    result.panelRevision=panelRevision
    result.reason="LIVE_PANEL_OBSERVED_READ_ONLY"
    return result
end

-- Exact-ID read-only recipe inspection for an *instruction to the player*.
-- Two list reads, two recipe reads and stable panel observation are required.
-- UNKNOWN build/interface never becomes a native session receipt here.
function ProfessionAPI:GetReadOnlyRecipeObservation(recipeID,expectedKey)
    local out={contract="volatile-live-recipe-observation-v1",readOnly=true,
        nativeDispatchAllowed=false,executionEligible=false,verified=false,
        readOnlyObserved=false,recipeID=recipeID,reason="UNVERIFIED"}
    if not validRecipeID(recipeID) then out.reason="RECIPE_ID_INVALID";return out end
    local before=self:GetReadOnlyProfessionObservation()
    if not before.observed then out.reason=before.reason;return out end
    if expectedKey~=nil and expectedKey~=before.professionKey then
        out.reason="PROFESSION_MISMATCH";return out end
    local api=C_TradeSkillUI
    if type(api)~="table" or type(api.GetAllRecipeIDs)~="function" or
        type(api.GetRecipeInfo)~="function" then out.reason="RECIPE_API_UNAVAILABLE";return out end
    local listFn,infoFn=api.GetAllRecipeIDs,api.GetRecipeInfo
    local function inspect()
        if C_TradeSkillUI~=api or api.GetAllRecipeIDs~=listFn or
            api.GetRecipeInfo~=infoFn then return nil,"RECIPE_PROVIDER_CHANGED" end
        local ok,ids=pcall(listFn)
        if not ok then return nil,"RECIPE_LIST_API_ERROR" end
        local membership,err,counts=validArrayIDs(ids)
        if not membership then return nil,err end
        if not membership[recipeID] then return nil,"RECIPE_NOT_IN_OPEN_PANEL" end
        local infoOK,info=pcall(infoFn,recipeID)
        if not infoOK or type(info)~="table" then return nil,"RECIPE_INFO_UNAVAILABLE" end
        if info.recipeID~=nil and info.recipeID~=recipeID then
            return nil,"RECIPE_INFO_ID_MISMATCH" end
        if type(info.name)~="string" or info.name=="" or
            type(info.learned)~="boolean" then return nil,"RECIPE_IDENTITY_UNVERIFIED" end
        return {name=info.name,learned=info.learned,counts=counts},nil
    end
    local first,why=inspect()
    if not first then out.reason=why;return out end
    local last,why2=inspect()
    if not last then out.reason=why2;return out end
    if first.name~=last.name or first.learned~=last.learned then
        out.reason="RECIPE_INFO_CHANGED";return out end
    for id,n in pairs(first.counts) do
        if last.counts[id]~=n then out.reason="RECIPE_LIST_CHANGED";return out end
    end
    for id,n in pairs(last.counts) do
        if first.counts[id]~=n then out.reason="RECIPE_LIST_CHANGED";return out end
    end
    local after=self:GetReadOnlyProfessionObservation()
    if not after.observed or before.observationToken~=after.observationToken or
        before.skill~=after.skill or before.maxSkill~=after.maxSkill or
        before.clientBuild~=after.clientBuild or
        before.observationQuality~=after.observationQuality or
        api.GetAllRecipeIDs~=listFn or api.GetRecipeInfo~=infoFn then
        out.reason="LIVE_PANEL_CHANGED_DURING_READ";return out
    end
    out.readOnlyObserved=true
    out.visible=true
    out.learned=first.learned
    out.name=first.name
    out.professionKey=before.professionKey
    out.panelToken=before.observationToken
    out.panelRevision=before.panelRevision
    out.observationQuality=before.observationQuality
    out.observationToken=before.observationToken
    out.reason="LIVE_RECIPE_OBSERVED_READ_ONLY"
    return out
end

function ProfessionAPI:GetExecutionRecipeContext(recipeID, expectedKey, kind)
    local context=self:GetRecipeContext(recipeID,expectedKey)
    context.executionKind=kind=="enchant" and "enchant" or "craft"
    context.nativeCapability=false
    context.executionReady=false
    if context.verified~=true then return context end
    local api=C_TradeSkillUI
    if context.executionKind=="enchant" then
        context.nativeCapability=type(api)=="table" and
            type(api.CraftEnchant)=="function" and
            type(api.GetEnchantItems)=="function"
    else
        context.nativeCapability=type(api)=="table" and
            type(api.CraftRecipe)=="function" and
            type(api.GetCraftableCount)=="function"
    end
    context.executionReady=context.nativeCapability and context.learned==true
    -- This flag is API readiness only. It does not grant a native intent:
    -- material, source, policy, transaction and protected-click gates remain.
    if not context.nativeCapability then context.reason="NATIVE_API_UNAVAILABLE"
    elseif context.learned~=true then context.reason="RECIPE_NOT_CONFIRMED_LEARNED" end
    return context
end

-- Native-only, transient reagent observation. This is NOT a material budget,
-- output-yield claim, or permission to dispatch. A schematic is optional on
-- some Forever clients; absent capability is not a client/build ban.
-- A canonical required-slot snapshot can be compared around the last native
-- craftability read. Alternative/optional reagents remain non-canonical.
function ProfessionAPI:GetNativeReagentSnapshot(recipeID)
    local out={contract="native-live-reagent-snapshot-v1",status="UNAVAILABLE",
        recipeID=tonumber(recipeID),nativeDispatchAllowed=false}
    if not validRecipeID(out.recipeID) then
        out.status="INVALID";out.reason="RECIPE_ID_INVALID";return out
    end
    local client=C_TradeSkillUI
    if type(client)~="table" or type(client.GetRecipeSchematic)~="function" then
        out.reason="SCHEMATIC_API_UNAVAILABLE";return out
    end
    local ok,schematic=pcall(client.GetRecipeSchematic,out.recipeID,false)
    if not ok then out.status="ERROR";out.reason="SCHEMATIC_API_EXCEPTION";return out end
    if type(schematic)~="table" or type(schematic.reagentSlotSchematics)~="table" then
        out.status="UNKNOWN";out.reason="SCHEMATIC_NOT_OBSERVED";return out
    end
    local slots=schematic.reagentSlotSchematics
    local slotCount,maxIndex=0,0
    for index in pairs(slots) do
        if not validRecipeID(index) or index>256 then
            out.status="INVALID";out.reason="SCHEMATIC_SLOT_KEY_INVALID";return out
        end
        slotCount=slotCount+1;maxIndex=math.max(maxIndex,index)
    end
    if slotCount==0 then
        out.status="UNKNOWN";out.reason="SCHEMATIC_EMPTY";return out
    end
    if slotCount~=maxIndex then
        out.status="INVALID";out.reason="SCHEMATIC_SLOTS_SPARSE";return out
    end
    local parts,totals={},{}
    local canonical=true
    for i=1,slotCount do
        local slot=slots[i]
        if type(slot)~="table" or type(slot.reagents)~="table" then
            -- API shape may differ on older/newer clients. An unsupported
            -- representation is UNKNOWN, not proof of invalid ingredients.
            out.status="UNKNOWN";out.reason="SCHEMATIC_SHAPE_UNSUPPORTED";return out
        end
        local alternatives=slot.reagents
        local n,last=0,0
        for j in pairs(alternatives) do
            if not validRecipeID(j) or j>64 then
                out.status="INVALID";out.reason="SCHEMATIC_ALTERNATIVE_KEY_INVALID";return out
            end
            n=n+1;last=math.max(last,j)
        end
        if n==0 or n~=last then
            out.status="INVALID";out.reason="SCHEMATIC_ALTERNATIVES_INVALID";return out
        end
        local ids={}
        for j=1,n do
            local reagent=alternatives[j]
            if type(reagent)~="table" or not validRecipeID(reagent.itemID) then
                out.status="INVALID";out.reason="SCHEMATIC_ITEM_ID_INVALID";return out
            end
            ids[#ids+1]=tostring(reagent.itemID)
        end
        -- Do not assert quantity or possession for optional or ambiguous slots.
        local required=slot.required
        local quantity=slot.quantityRequired
        if type(required)~="boolean" or n~=1 then canonical=false end
        if required==true then
            if type(quantity)~="number" or quantity<=0 or quantity~=math.floor(quantity) or quantity>1000000000 then
                out.status="INVALID";out.reason="SCHEMATIC_QUANTITY_INVALID";return out
            end
            if n==1 then
                local id=alternatives[1].itemID
                totals[id]=(totals[id] or 0)+quantity
                if totals[id]>1000000000 then
                    out.status="INVALID";out.reason="SCHEMATIC_QUANTITY_OVERFLOW";return out
                end
            end
        end
        parts[#parts+1]=table.concat({tostring(i),tostring(required),tostring(quantity),table.concat(ids,",")},":")
    end
    out.status=canonical and "OBSERVED" or "NON_CANONICAL"
    out.reason=canonical and "REAGENTS_OBSERVED" or "ALTERNATIVE_OPTIONAL_OR_UNKNOWN_REQUIRED"
    -- Length-prefixed slot signature is ephemeral. It is compared, never
    -- persisted, and must not be used as an authority token on its own.
    out.fingerprint=table.concat(parts,"|")
    out.materials={}
    if canonical then
        for id,quantity in pairs(totals) do
            out.materials[#out.materials+1]={itemID=id,quantity=quantity}
        end
        table.sort(out.materials,function(x,y)return x.itemID<y.itemID end)
    end
    return out
end

function ProfessionAPI:GetOpenProfessionKey()
    local ctx=self:GetOpenProfessionContext()
    if ctx.verified then
        -- 'skill-line-id' is the existing stable-source consumer contract;
        -- the context carries the stricter direct API provenance separately.
        return ctx.professionKey,ctx.baseSkillLineID,ctx.displayName,"skill-line-id",ctx
    end
    return nil,nil,nil,ctx.reason,ctx
end

-- Capture positional returns once for both primary and secondary interpretation.
-- Detached copies keep callers from modifying the pass's observation inputs.
local function detached(rows)
    local out={}
    for k,row in pairs(rows or {}) do local copy={};for f,v in pairs(row) do copy[f]=v end;out[k]=copy end
    return out
end
local function captureDetected()
    -- Direct callers also select the current character before any historical
    -- fallback. Within a pass the owner was already captured at its boundary.
    if not (JLP.GetObservationPass and JLP:GetObservationPass()) then
        local identity=JLP:GetModule("CharacterIdentity")
        if identity and identity.GetKey then identity:GetKey(true) end
    end
    local primary,secondary,detected,seen,indices={},{},{},{},{}
    local available=type(GetProfessions)=="function" and type(GetProfessionInfo)=="function"
    local ok,a,b,arch,f,c,fa
    if available then ok,a,b,arch,f,c,fa=pcall(GetProfessions) end
    local complete=ok==true
    local function read(index,source,slot)
        if index==nil then return nil end
        if indices[index]==nil then indices[index]=readProfession(index,source,slot,source=="get-professions-primary") or false end
        if indices[index]==false then complete=false end
        return indices[index] or nil
    end
    if ok then
        local slots={[1]=a,[2]=b}
        for slot=1,2 do local info=read(slots[slot],"get-professions-primary",slot)
            if info then primary[#primary+1]=info;detected[info.key]=info end
        end
        local cache=JLP:GetModule("KnowledgeCache")
        if cache and cache.SyncProfessions then cache:SyncProfessions(primary)
        else for _,info in ipairs(primary) do remember(info) end end
    else
        primary=cachedDetected("PRIMARY")
        for _,info in ipairs(primary) do detected[info.key]=info end
    end
    local reg=registry()
    if ok then
        local slots={[1]=f,[2]=c,[3]=fa}
        for slot=1,3 do local info=read(slots[slot],"get-professions-secondary")
            local def=info and reg and reg:Get(info.key)
            if def and def.category=="SECONDARY" and not seen[info.key] then
                seen[info.key]=true;secondary[#secondary+1]=info
            end
        end
    end
    for _,key in ipairs(reg and reg:GetKeys({category="SECONDARY"}) or {}) do
        if not seen[key] then local info=supplementalStableProfession(key)
            if info then seen[key]=true;secondary[#secondary+1]=info end
        end
    end
    table.sort(secondary,function(x,y)return reg:GetOrder(x.key)<reg:GetOrder(y.key) end)
    if #secondary==0 and not available then secondary=cachedDetected("SECONDARY") end
    for _,info in ipairs(secondary) do detected[info.key]=info end
    return {primary=primary,secondary=secondary,detected=detected,available=complete}
end
-- Ownership is character knowledge. The session snapshot has no plan, menu,
-- schematic, inventory, price or action authority. Missing reads retain positive
-- knowledge as historical/UNKNOWN; they are never a new negative observation.
local ownershipSession
-- The pending object is the only settled-generation identity. It stores no
-- plan, menu, readiness or cross-event evaluation model.
local ownershipObservation
local ownershipRevision=0
local function ownerKey()
    local identity=JLP:GetModule("CharacterIdentity")
    return identity and identity:GetKey(true) or nil
end
local function ownershipSnapshot()
    local owner=ownerKey()
    if not owner or owner:find("UnknownCharacter",1,true) or owner:find("UnknownRealm",1,true) then
        -- Do not replace the last character's positives or create ownership
        -- for an unidentified player during login/identity transitions.
        return {characterKey=owner,detected={},states={},freshPasses={}}
    end
    if ownershipSession and ownershipSession.characterKey==owner then return ownershipSession end
    local identity=JLP:GetModule("CharacterIdentity")
    if identity and identity.ReconcileAccount and JLP.DB then identity:ReconcileAccount(JLP.DB) end
    local raw=captureDetected()
    local cache=JLP:GetModule("KnowledgeCache")
    local known=cache and cache.GetProfessionOwnership and cache:GetProfessionOwnership() or {}
    -- Migrate strictly scoped native primary-slot history, never bare saved
    -- numbers/names or secondary catalogues without ownership provenance.
    for _,info in ipairs(cachedDetected("PRIMARY")) do
        if known and not known[info.key] and info.primarySlot and cache and cache.RememberProfessionOwnership then
            cache:RememberProfessionOwnership({key=info.key,characterKey=owner,
                skillLine=info.skillLine,primarySlot=info.primarySlot,cached=true,
                detectionSource="MIGRATED_QUALIFIED_PRIMARY_SLOT_HISTORY"},true)
        end
    end
    local rows,states={},{ }
    local reg=registry()
    local primaryCount=0
    for _,info in pairs(raw.detected) do
        if info.cached~=true and ((tonumber(info.skill) or 0)>0 or (tonumber(info.maxSkill) or 0)>0) then
            rows[info.key]=info
            if reg:Get(info.key).category=="PRIMARY" then primaryCount=primaryCount+1 end
            if cache and cache.RememberProfessionOwnership then cache:RememberProfessionOwnership(info,true) end
        end
    end
    known=cache and cache.GetProfessionOwnership and cache:GetProfessionOwnership() or known
    for _,key in ipairs(reg and reg:GetKeys() or {}) do
        local prior=known and known[key]
        if rows[key] then states[key]="OWNED"
        elseif prior and prior.observed==true and prior.active~=false and prior.skillLineID==reg:GetSkillLineID(key) then
            local replaced=reg:Get(key).category=="PRIMARY" and primaryCount>=2
            if reg:Get(key).category=="PRIMARY" and prior.primarySlot then
                for other,info in pairs(rows) do
                    if other~=key and info.primarySlot==prior.primarySlot and info.cached~=true then replaced=true end
                end
            end
            if replaced then
                -- Two positively identified different slots are concrete replacement
                -- evidence. Keep the old fact, but do not activate a third primary.
                if cache and cache.RememberProfessionOwnership then
                    cache:RememberProfessionOwnership({key=key,characterKey=owner,
                        skillLine=reg:GetSkillLineID(key),detectionSource="POSITIVE_PRIMARY_REPLACEMENT"},false)
                end
                states[key]="PROFESSION_NOT_LEARNED"
            else
                local historical=cache and cache:GetProfession(key)
                rows[key]=historical and detached({historical})[1] or {key=key,name=reg:GetDisplayNameOrKey(key)}
                rows[key].key=key;rows[key].cached=true;rows[key].ownershipCurrent="UNKNOWN"
                rows[key].characterKey=owner
                rows[key].primarySlot=prior.primarySlot
                rows[key].primarySlotHistorical=prior.primarySlot~=nil
                rows[key].slotObservationSource="knowledge-cache"
                states[key]="OWNED_CURRENT_UNKNOWN"
            end
        else states[key]=raw.available and not (ownershipObservation and ownershipObservation.characterKey==owner)
            and "PROFESSION_NOT_LEARNED" or "PROFESSION_OWNERSHIP_UNKNOWN" end
    end
    local primaryOwned=0
    for key in pairs(rows) do if reg:Get(key).category=="PRIMARY" then primaryOwned=primaryOwned+1 end end
    if primaryOwned>2 then
        -- Conflicting history cannot activate a third primary slot.
        for key,info in pairs(rows) do
            if reg:Get(key).category=="PRIMARY" and info.cached==true then rows[key]=nil;states[key]="PROFESSION_OWNERSHIP_UNKNOWN" end
        end
    end
    local freshPasses={};local pass=JLP.GetObservationPass and JLP:GetObservationPass() or nil
    for key,info in pairs(rows) do if info.cached~=true then freshPasses[key]=pass and pass.token end end
    ownershipSession={characterKey=owner,detected=rows,states=states,freshPasses=freshPasses}
    return ownershipSession
end
function ProfessionAPI:InvalidateOwnership(reason)
    ownershipSession=nil
    local pass=JLP.GetObservationPass and JLP:GetObservationPass()
    if pass then pass.memo["profession-api"]=nil;pass.affectedProfessions={} end
    self.ownershipReason=reason
end
function ProfessionAPI:GetOwnership(key)
    local reg=registry();key=reg and reg:NormalizeKey(key) or key
    local snapshot=ownershipSnapshot()
    local state=key and snapshot.states[key] or "PROFESSION_OWNERSHIP_UNKNOWN"
    return {key=key,characterKey=snapshot.characterKey,state=state,
        owned=state=="OWNED" or state=="OWNED_CURRENT_UNKNOWN",readOnly=true}
end
function ProfessionAPI:RefreshOwnedProfession(key)
    local snapshot=ownershipSnapshot();local prior=snapshot.detected[key]
    if not prior then return false end
    local info=prior.index and readProfession(prior.index,prior.detectionSource,prior.primarySlot) or supplementalStableProfession(key)
    if not info or info.key~=key then return false end
    snapshot.detected[key]=info;snapshot.states[key]="OWNED"
    local pass=JLP.GetObservationPass and JLP:GetObservationPass() or nil
    snapshot.freshPasses[key]=pass and pass.token
    if pass then pass.memo["profession-api"]=nil;pass.affectedProfessions=pass.affectedProfessions or {};pass.affectedProfessions[key]=true end
    return true
end
function ProfessionAPI:RefreshOwnership(reason)
    local previous=ownershipSession
    self:InvalidateOwnership(reason)
    local snapshot=ownershipSnapshot()
    local pass=JLP.GetObservationPass and JLP:GetObservationPass()
    if pass and previous and previous.characterKey==snapshot.characterKey and reason~="PLAYER_LOGIN" then
        for key,info in pairs(snapshot.detected) do
            local old=previous.detected[key]
            if not old or old.skill~=info.skill or old.maxSkill~=info.maxSkill or previous.states[key]~=snapshot.states[key] then
                pass.affectedProfessions[key]=true
                if JLP.MarkObservationsDirty then JLP:MarkObservationsDirty(reason,key) end
            end
        end
    end
    return self:GetDetected()
end

function ProfessionAPI:ObservePositiveOwnershipFromPanel()
    -- Read the current panel directly, never caller-supplied data. A numeric
    -- identity plus positive skill/cap under one verified character/session is
    -- ownership evidence only; recipe/menu/readiness checks remain separate.
    local ctx=self:GetOpenProfessionContext()
    local owner,build=currentObservationIdentity()
    local reg=registry();local key=ctx and ctx.professionKey
    if not ctx or ctx.verified~=true or not key or ctx.characterKey~=owner or ctx.build~=build
        or ctx.baseSkillLineID~=reg:GetSkillLineID(key)
        or type(ctx.skill)~="number" or ctx.skill<=0 or ctx.skill~=math.floor(ctx.skill)
        or type(ctx.maxSkill)~="number" or ctx.maxSkill<ctx.skill or ctx.maxSkill==math.huge
        or ctx.maxSkill~=math.floor(ctx.maxSkill) then
        return false,"POSITIVE_PANEL_OWNERSHIP_UNVERIFIED"
    end
    local snapshot=ownershipSnapshot()
    if snapshot.characterKey~=owner then return false,"CHARACTER_UNVERIFIED" end
    local after=self:GetOpenProfessionContext()
    if not after.verified or after.panelToken~=ctx.panelToken or after.clientBuildToken~=ctx.clientBuildToken
        or after.characterKey~=owner then return false,"PANEL_CHANGED_DURING_OWNERSHIP_READ" end
    if snapshot.detected[key] and snapshot.states[key]=="OWNED" then return true,key end
    if not snapshot.detected[key] and reg:Get(key).category=="PRIMARY" then
        local count=0
        for other in pairs(snapshot.detected) do if reg:Get(other).category=="PRIMARY" then count=count+1 end end
        -- A panel has no native slot-replacement proof. It cannot activate a
        -- third primary by silently discarding another character fact.
        if count>=2 then return false,"PRIMARY_SLOT_REQUALIFICATION_REQUIRED" end
    end
    local prior=snapshot.detected[key]
    local info={key=key,name=ctx.displayName or reg:GetDisplayNameOrKey(key),skill=ctx.skill,maxSkill=ctx.maxSkill,
        skillLine=ctx.baseSkillLineID,professionEnum=ctx.professionEnum,characterKey=owner,
        observedClientBuild=build,cached=false,detectionSource="verified-positive-profession-panel",
        identitySource=ctx.identitySource,primarySlot=prior and prior.primarySlot,index=prior and prior.index}
    snapshot.detected[key]=info;snapshot.states[key]="OWNED"
    local pass=JLP.GetObservationPass and JLP:GetObservationPass()
    snapshot.freshPasses[key]=pass and pass.token
    local cache=JLP:GetModule("KnowledgeCache")
    if cache then
        if cache.RememberProfession then cache:RememberProfession(info) end
        if cache.RememberProfessionOwnership then cache:RememberProfessionOwnership(info,true) end
    end
    if pass then
        pass.memo["profession-api"]=nil;pass.affectedProfessions=pass.affectedProfessions or {};pass.affectedProfessions[key]=true
    end
    if JLP.MarkObservationsDirty then JLP:MarkObservationsDirty("POSITIVE_PANEL_OWNERSHIP",key) end
    return true,key
end

local ownershipEvents={PLAYER_LOGIN=true,PLAYER_ENTERING_WORLD=true,SKILL_LINES_CHANGED=true,
    LEARNED_SPELL_IN_TAB=true,NEW_RECIPE_LEARNED=true}
local panelEvents={TRADE_SKILL_SHOW=true,TRADE_SKILL_LIST_UPDATE=true,TRADE_SKILL_UPDATE=true}
local function ownershipResult(previous,reason,scope)
    local current=ownershipSnapshot();local changed,retired={},{}
    if not previous or previous.characterKey~=current.characterKey then previous={detected={},states={}} end
    for key,state in pairs(current.states) do
        local info,old=current.detected[key],previous.detected[key]
        if (previous.states[key] or "PROFESSION_OWNERSHIP_UNKNOWN")~=state or
            (info and (not old or old.skill~=info.skill or old.maxSkill~=info.maxSkill)) then
            changed[key]=true
        end
        if old and not info then retired[key]=true end
    end
    ownershipRevision=ownershipRevision+1
    return {changedKeys=changed,retiredKeys=retired,characterKey=current.characterKey,
        pending=ownershipObservation~=nil and ownershipObservation.characterKey==current.characterKey,
        reason=reason,scope=scope,revision=ownershipRevision,readOnly=true}
end
local function promotedDuring(pending)
    for key,info in pairs(ownershipSession and ownershipSession.detected or {}) do
        if not pending.keys[key] and info.cached~=true then return true end
    end
    return false
end
local function scheduleOwnershipRead(pending,delay)
    if type(C_Timer)~="table" or type(C_Timer.After)~="function" then ownershipObservation=nil;return end
    pending.scheduled=true
    local ok,err=pcall(C_Timer.After,delay,function()
        if ownershipObservation~=pending then return end
        pending.scheduled=false
        if ownerKey()~=pending.characterKey then ownershipObservation=nil;return end
        local function settle()
            local previous=ownershipSession
            pending.attempt=pending.attempt+1
            local final=pending.attempt>=2
            if final then ownershipObservation=nil end
            ProfessionAPI:RefreshOwnership("OWNERSHIP_SETTLED")
            if final or promotedDuring(pending) then ownershipObservation=nil end
            local result=ownershipResult(previous,"OWNERSHIP_SETTLED","OWNERSHIP")
            -- Core distributes the detached result. Observation never invokes
            -- Planner, execution, workspace, source, navigation or UI itself.
            if pending.onSettled then pending.onSettled(result) end
        end
        if JLP.WithObservationPass then JLP:WithObservationPass("OWNERSHIP_SETTLED",settle,true)
        else settle() end
        if ownershipObservation==pending then scheduleOwnershipRead(pending,0.6) end
    end)
    if not ok then
        ownershipObservation=nil
        if JLP.RecordRuntimeError then JLP:RecordRuntimeError("OWNERSHIP_SETTLED_TIMER",err) end
    end
end
function ProfessionAPI:ObserveOwnershipEvent(event,onSettled)
    if not ownershipEvents[event] and not panelEvents[event] then return nil end
    local previous=ownershipSession
    if panelEvents[event] then
        if previous then
            local states={};for key,state in pairs(previous.states) do states[key]=state end
            previous={characterKey=previous.characterKey,states=states,detected=detached(previous.detected)}
        end
        if event=="TRADE_SKILL_SHOW" then self:InvalidateOpenProfessionContext(event) end
        self:ObservePositiveOwnershipFromPanel()
        local key=self:GetOpenProfessionKey()
        if key and self:GetOwnership(key).owned then self:RefreshOwnedProfession(key) end
        return ownershipResult(previous,event,"PANEL")
    end
    local owner=ownerKey();local pending=ownershipObservation
    if not pending or pending.characterKey~=owner then
        local keys={}
        if previous and previous.characterKey==owner then for key in pairs(previous.detected) do keys[key]=true end end
        pending={characterKey=owner,keys=keys,attempt=0,onSettled=onSettled}
        ownershipObservation=pending
    end
    self:RefreshOwnership(event)
    if promotedDuring(pending) then ownershipObservation=nil
    elseif not pending.scheduled then scheduleOwnershipRead(pending,0.2) end
    return ownershipResult(previous,event,"OWNERSHIP")
end
local function detectionSnapshot()
    local function project()
        local snapshot=ownershipSnapshot();local primary,secondary,detected={},{},{}
        local reg=registry();local pass=JLP.GetObservationPass and JLP:GetObservationPass()
        for _,key in ipairs(reg and reg:GetKeys() or {}) do local row=snapshot.detected[key]
            if row then
                local info=detached({row})[1]
                if row.skillObservationStatus~=nil then
                    -- Keep the raw independent fields in the session snapshot.
                    -- A partial/provisional pair may use persistent knowledge for
                    -- advice, but must not qualify as one current rank/cap read.
                    local skill,cap=directRank(row.skill),directRank(row.maxSkill)
                    local pair=skill~=nil and cap~=nil and cap>0 and skill<=cap
                    if not pair then
                        local cache=JLP:GetModule("KnowledgeCache")
                        local historical=cache and cache:GetProfession(key)
                        info.skill=historical and historical.skill or nil
                        info.maxSkill=historical and historical.maxSkill or nil
                        info.cached=true
                    end
                end
                if not (pass and pass.token) or snapshot.freshPasses[key]~=pass.token then info.cached=true end
                detected[key]=info
                local list=reg:Get(key).category=="PRIMARY" and primary or secondary
                list[#list+1]=info
            end
        end
        table.sort(primary,function(a,b)return (a.primarySlot or 99)<(b.primarySlot or 99) end)
        return {primary=primary,secondary=secondary,detected=detected}
    end
    if JLP.MemoObservation then return JLP:MemoObservation("profession-api","detected",project) end
    return project()
end
function ProfessionAPI:GetPrimaryPair() return detached(detectionSnapshot().primary) end
function ProfessionAPI:GetSecondaryProfessions() return detached(detectionSnapshot().secondary) end
function ProfessionAPI:GetDetected() return detached(detectionSnapshot().detected) end
function ProfessionAPI:Get(key)
    local reg=registry()
    local normalized=reg and reg:NormalizeKey(key) or key
    local info=normalized and self:GetDetected()[normalized] or nil
    if info and info.cached==true then
        local function refreshCurrent()
            -- A demanded owned key can refresh its numeric skill/cap from its
            -- identified native index. Menus/schematics remain panel-scoped.
            -- This is not a new all-profession ownership scan.
            self:RefreshOwnedProfession(normalized)
        end
        if JLP.MemoObservation then JLP:MemoObservation("profession-current",normalized,refreshCurrent)
        else refreshCurrent() end
        info=self:GetDetected()[normalized]
    end
    return info
end

function ProfessionAPI:Open(key, profession)
    local reg = registry()
    local normalized = reg and reg:NormalizeKey(key) or key
    local ownership=self:GetOwnership(normalized)
    if not ownership.owned then return false,ownership.state end
    local info = profession
    if not info or not info.skillLine then info = self:Get(normalized) end
    if not info then return false, "Profession is not currently detected." end

    local skillLine = tonumber(info.skillLine)
    if skillLine and C_TradeSkillUI and type(C_TradeSkillUI.OpenTradeSkill) == "function" then
        local ok, result = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
        if ok and result ~= false then return true, tostring(info.name or normalized or "Profession") .. " opened." end
    end

    return false, "This client does not expose a supported native profession-open API for " .. tostring(info.name or normalized or "this profession") .. "."
end

function ProfessionAPI:GetIdentitySummary()
    local reg = registry()
    if not reg then return "Profession identity registry unavailable" end
    local stable, learned = 0, 0
    for _, key in ipairs(reg:GetKeys()) do if reg:GetSkillLineID(key) and reg:GetProfessionEnum(key) ~= nil then stable=stable+1 end end
    for _ in pairs(self:GetDetected()) do learned=learned+1 end
    return string.format("Stable profession identity: %d / %d registered · %d detected",stable,#reg:GetKeys(),learned)
end

function ProfessionAPI:GetSummary()
    local reg = registry()
    local detected = self:GetDetected()
    local parts = {}
    for _, key in ipairs(reg and reg:GetKeys() or {}) do
        local p=detected[key]
        if p then parts[#parts + 1] = string.format("%s %s/%s%s", p.name, tostring(p.skill or "UNKNOWN"), tostring(p.maxSkill or "UNKNOWN"), p.cached and " (cached)" or "") end
    end
    if #parts == 0 then return "Supported professions not detected" end
    return table.concat(parts, "  -  ")
end

JLP:RegisterModule("ProfessionAPI", ProfessionAPI)
