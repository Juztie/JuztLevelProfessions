local _, JLP = ...

-- Persistent observation cache. This module intentionally stores only facts the
-- addon has actually observed from the client (item metadata, profession state
-- and recipe scans). Positive recipe knowledge survives reloads indefinitely;
-- negative knowledge is trusted only for the same observed Forever build.
local KnowledgeCache = {}

-- Session-only affirmative learned facts. Never persist these tables to
-- SavedVariables: reloading the UI MUST require a new client confirmation.
-- Indexed by character, profession and recipe; build/ID are checked on read.
local sessionLearned = {}
-- Transient scan-identity conflicts must not rewrite a saved positive recipe.
-- They do revoke live advisory authority until an unambiguous fresh read.
local sessionConflicts = {}
-- ID-primary transient observations, independent of name projections.
local sessionByID = {}
-- Only an explicit learned=false on the same enumerated SpellID can veto
-- historical same-build advisory. This is transient: a reload requires a new
-- client observation, and SavedVariables positive provenance remains intact.
local sessionUnlearned = {}
local lastObservedSessionIdentity = nil
local function sessionFor(character, profession)
    local characterRows = sessionLearned[character]
    if not characterRows then characterRows = {}; sessionLearned[character] = characterRows end
    local rows = characterRows[profession]
    if not rows then rows = {}; characterRows[profession] = rows end
    return rows
end

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return tonumber(value) end
    end
    return nil
end

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("%s+", " ")
    return value
end

local function currentBuild()
    local provider = JLP:GetModule("ClientBuildInfo")
    local build, token, sessionVerified=false
    if type(provider)=="table" and type(provider.Read)=="function" then
        local ok, receipt=pcall(provider.Read,provider)
        if ok and type(receipt)=="table" and receipt.known==true then
            local n=receipt.buildNumber
            local interface=receipt.interfaceVersion
            if type(n)=="number" and n==n and n>0 and n<=9007199254740991 and
                n==math.floor(n) and (interface==nil or (type(interface)=="number" and
                interface==interface and interface>0 and interface<=9007199254740991 and
                interface==math.floor(interface))) then
                local expected=string.format("forever:%s|interface:%s",tostring(n),tostring(interface or "unknown"))
                if receipt.token==expected then
                    build=n;token=expected
                    sessionVerified=interface~=nil
                end
            end
        end
    elseif type(provider)=="table" and type(provider.GetBuildNumber)=="function" then
        -- Compatibility with older clients/providers that have no Read() API.
        local ok,n=pcall(provider.GetBuildNumber,provider)
        if ok and type(n)=="number" and n==n and n>0 and
            n<=9007199254740991 and n==math.floor(n) then
            build=n
            token=string.format("forever:%s|interface:unknown",tostring(n))
        end
    end
    -- A client/interface identity transition invalidates all transient learned
    -- claims, even when the numerical build stays the same. Unknown is a
    -- distinct state, never a reusable verified session identity.
    local identity=token or "UNKNOWN_CLIENT_SESSION"
    if lastObservedSessionIdentity~=nil and identity~=lastObservedSessionIdentity then
        sessionLearned={};sessionConflicts={};sessionUnlearned={};sessionByID={}
    end
    lastObservedSessionIdentity=identity
    return build,sessionVerified and "live-client" or
        (build and "live-build-only" or "unknown")
end

local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function accountStore()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.knowledge = JLP.DB.account.knowledge or { items = {}, itemNames = {}, characters = {} }
    local store = JLP.DB.account.knowledge
    store.items = store.items or {}
    store.itemNames = store.itemNames or {}
    store.characters = store.characters or {}
    return store
end

local function characterStore()
    local account = accountStore()
    if not account then return nil end
    local key = characterKey()
    local store = account.characters[key]
    if type(store) ~= "table" then
        store = { professions = {}, recipes = {}, updatedAt = nil }
        account.characters[key] = store
    end
    store.professions = store.professions or {}
    store.recipes = store.recipes or {}
    return store
end

local function validItemIcon(value)
    if value == nil or value == false or value == 0 or value == "" then return nil end
    return value
end

local function parseItemID(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function KnowledgeCache:GetCharacterKey()
    return characterKey()
end

-- Durable positive ownership, separate from menus, offers and live recipe facts.
-- Only ProfessionAPI's identified native observation writes this bounded map.
function KnowledgeCache:GetProfessionOwnership()
    local store=characterStore()
    if not store then return nil end
    local out={}
    for key,row in pairs(store.ownership or {}) do
        if type(row)=="table" then
            local copy={}
            for field,value in pairs(row) do
                local t=type(value)
                if t=="string" or t=="number" or t=="boolean" then copy[field]=value end
            end
            out[key]=copy
        end
    end
    return out -- Detached ownership facts, never a DB alias.
end
function KnowledgeCache:RememberProfessionOwnership(info,active)
    local reg=JLP:GetModule("ProfessionRegistry")
    local key=type(info)=="table" and reg and reg:NormalizeKey(info.key)
    local owner=characterKey()
    if not key or info.characterKey~=owner or owner:find("UnknownRealm",1,true) or
        owner:find("UnknownCharacter",1,true) then return end
    if info.skillLine~=reg:GetSkillLineID(key) then return end
    local store=characterStore();if not store then return end
    local prior=store.ownership and store.ownership[key]
    if active==false then
        -- ProfessionAPI qualified a positive primary-slot replacement. Keep
        -- the old observation as history; an empty tuple is not this receipt.
        if info.detectionSource~="POSITIVE_PRIMARY_REPLACEMENT" or not prior or prior.observed~=true then return end
        prior.active=false;prior.retiredSource=info.detectionSource
        return true
    end
    local historical=info.detectionSource=="MIGRATED_QUALIFIED_PRIMARY_SLOT_HISTORY"
    local evidence
    if historical then
        local row=store.professions[key]
        evidence=row and row.lastObservedPrimarySlotEvidence
        if prior or reg:Get(key).category~="PRIMARY" or not row or
            (info.primarySlot~=1 and info.primarySlot~=2) or row.lastObservedPrimarySlot~=info.primarySlot or
            type(evidence)~="table" or evidence.source~="get-professions-primary" or
            evidence.characterKey~=owner or evidence.professionKey~=key or evidence.skillLineID~=info.skillLine or
            type(evidence.clientBuild)~="number" or evidence.clientBuild<=0 or
            evidence.clientBuild~=math.floor(evidence.clientBuild) then return end
    elseif info.cached==true or not (tonumber(info.skill) and info.skill>0 or
        tonumber(info.maxSkill) and info.maxSkill>0) then return end
    store.ownership=store.ownership or {}
    store.ownership[key]={key=key,observed=true,active=true,source=info.detectionSource,
        skillLineID=info.skillLine,primarySlot=info.primarySlot,
        clientBuild=historical and evidence.clientBuild or info.observedClientBuild,
        observedAt=now()}
    return true
end

function KnowledgeCache:RememberItem(itemID, name, link, icon, quality)
    local account = accountStore()
    if not account then return nil end
    itemID = tonumber(itemID) or parseItemID(link)
    if not itemID then return nil end

    local row = account.items[itemID]
    if type(row) ~= "table" then row = { itemID = itemID }; account.items[itemID] = row end
    if name and name ~= "" then
        local newName=tostring(name)
        if row.name and row.name~=newName then
            local previousKey=normalizeText(row.name)
            if account.itemNames[previousKey]==itemID then account.itemNames[previousKey]=nil end
        end
        row.name=newName
    end
    -- Never persist a hyperlink whose embedded identity differs from the
    -- requested item. This cache is shared by multiple UI consumers.
    if link and link ~= "" and parseItemID(link)==itemID then row.link=tostring(link) end
    icon = validItemIcon(icon)
    if icon then row.icon = icon end
    if quality ~= nil then row.quality = tonumber(quality) or quality end
    row.updatedAt = now()

    if row.name and row.name ~= "" then
        account.itemNames[normalizeText(row.name)] = itemID
    end
    return row
end

function KnowledgeCache:CaptureItem(itemID, fallbackName, fallbackIcon, quality)
    local resolvedID = tonumber(itemID)
    local name, link, icon = fallbackName, nil, fallbackIcon
    local query = resolvedID or fallbackName

    local itemType, itemSubType, classID, subClassID, isCraftingReagent
    if query ~= nil and type(GetItemInfo) == "function" then
        local ok, liveName, liveLink, liveQuality, _, _, liveType, liveSubType, _, _, liveIcon, _, liveClassID, liveSubClassID, _, _, _, liveCrafting = pcall(GetItemInfo, query)
        if ok then
            name = liveName or name
            link = liveLink or link
            quality = liveQuality ~= nil and liveQuality or quality
            icon = liveIcon or icon
            itemType = liveType
            itemSubType = liveSubType
            classID = tonumber(liveClassID)
            subClassID = tonumber(liveSubClassID)
            isCraftingReagent = liveCrafting and true or false
            resolvedID = resolvedID or parseItemID(liveLink)
        end
    end

    if resolvedID and not icon and type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        local ok, liveIcon = pcall(C_Item.GetItemIconByID, resolvedID)
        if ok then icon = validItemIcon(liveIcon) or icon end
    end
    if resolvedID and not icon and type(GetItemIcon) == "function" then
        local ok, liveIcon = pcall(GetItemIcon, resolvedID)
        if ok then icon = validItemIcon(liveIcon) or icon end
    end

    if resolvedID then
        local row = self:RememberItem(resolvedID, name, link, icon, quality)
        if row then
            if itemType and itemType ~= "" then row.itemType = tostring(itemType) end
            if itemSubType and itemSubType ~= "" then row.itemSubType = tostring(itemSubType) end
            if classID ~= nil then row.classID = classID end
            if subClassID ~= nil then row.subClassID = subClassID end
            if isCraftingReagent ~= nil then row.isCraftingReagent = isCraftingReagent end
        end
        return row
    end
    return nil
end

function KnowledgeCache:GetItem(itemID, name)
    local account = accountStore()
    if not account then return nil end
    local id = tonumber(itemID)
    if not id and name then id = tonumber(account.itemNames[normalizeText(name)]) end
    return id and account.items[id] or nil
end

function KnowledgeCache:ResolveItem(itemID, name, icon, quality)
    return self:CaptureItem(itemID, name, icon, quality) or self:GetItem(itemID, name)
end

function KnowledgeCache:InvalidateRecipeScan(professionKey, keepPositive)
    local store = characterStore()
    if not store or not professionKey then return false end
    local current = store.recipes[professionKey]
    if not current then return false end
    if sessionLearned[characterKey()] then
        sessionLearned[characterKey()][professionKey] = nil
    end
    if sessionConflicts[characterKey()] then
        sessionConflicts[characterKey()][professionKey] = nil
    end
    if sessionUnlearned[characterKey()] then
        sessionUnlearned[characterKey()][professionKey] = nil
    end
    if sessionByID[characterKey()] then sessionByID[characterKey()][professionKey]=nil end
    if keepPositive then
        current.complete = false
        current.completenessVerified = false
        current.build = nil
        current.invalidatedAt = now()
    else
        store.recipes[professionKey] = nil
    end
    store.updatedAt = now()
    return true
end

-- Rank shape qualification is fieldwise; numeric strings, NaN, infinities,
-- negatives and fractional values are not observed profession ranks.
local function professionRank(value)
    if type(value)=="number" and value==value and value>=0 and
       value<math.huge and value==math.floor(value) then return value end
    return nil
end

function KnowledgeCache:RememberProfession(info)
    if type(info) ~= "table" or not info.key then return nil end
    local store = characterStore()
    if not store then return nil end
    local previous = store.professions[info.key]

    local incomingSkill = professionRank(info.skill)
    local incomingMax = professionRank(info.maxSkill)
    -- A partial lower skill must not erase the last rollback comparison before
    -- a later complete observation (including after reload). One optional
    -- scalar in the existing row retains that history; it is never live rank.
    local rollbackSkill=previous and professionRank(previous.skillBeforePartialRank)
    local previousSkill=previous and professionRank(previous.skill)
    if previousSkill~=nil and (rollbackSkill==nil or previousSkill>rollbackSkill) then
        rollbackSkill=previousSkill
    end

    -- Forever can transiently expose 0/0 profession ranks during login/reload
    -- before the skill lines are fully hydrated. Treating that as a real skill
    -- rollback destroys perfectly valid persisted recipe knowledge and causes a
    -- false VERIFY state until the profession window is opened again.
    --
    -- Only invalidate on a *credible* rollback: both the previous observation
    -- and the new live observation must have a real profession cap, and the new
    -- skill must itself be a positive rank. A 0/0 (or otherwise incomplete)
    -- startup observation is provisional and must never erase knowledge.
    local credibleRollback = previous
        and (tonumber(previous.maxSkill) or 0) > 0
        and (tonumber(previous.skill) or 0) > 0
        and (incomingMax or 0) > 0
        and (incomingSkill or 0) > 0
        and incomingSkill <= incomingMax
        and incomingSkill < (rollbackSkill or 0)
    if credibleRollback then
        self:InvalidateRecipeScan(info.key, false)
    end

    local row = previous or {}
    local completeRank=incomingSkill~=nil and incomingMax~=nil and
        incomingMax>0 and incomingSkill<=incomingMax
    if completeRank then
        row.skillBeforePartialRank=nil
    elseif rollbackSkill~=nil and (tonumber(row.maxSkill) or 0)>0 then
        row.skillBeforePartialRank=rollbackSkill
    end
    row.key = info.key
    row.name = info.name or row.name
    row.icon = info.icon or row.icon
    -- Persistent values are independent historical facts, not a simultaneous
    -- current pair. A positive field can update without its sibling. Zero skill
    -- needs a hydrated positive cap; provisional 0/0 never replaces knowledge.
    if incomingSkill~=nil and (incomingSkill>0 or (incomingMax or 0)>0) then
        row.skill = incomingSkill
    end
    if (incomingMax or 0)>0 then row.maxSkill = incomingMax end
    row.skillLine = tonumber(info.skillLine) or row.skillLine
    -- Only a stable, current GetProfessions position may update the saved
    -- *historical* slot. Do not fabricate this from names, old cache rows,
    -- partial APIs or a stale/foreign character/build observation.
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and reg:Get(info.key)
    local slot=info.primarySlot
    local liveBuild=currentBuild()
    local observedBuild=info.observedClientBuild
    local owner=characterKey()
    local slotVerified=(slot==1 or slot==2) and def and def.category=="PRIMARY" and
        info.cached==false and info.detectionSource=="get-professions-primary" and
        type(info.characterKey)=="string" and info.characterKey==owner and
        not owner:find("UnknownRealm",1,true) and not owner:find("UnknownCharacter",1,true) and
        type(observedBuild)=="number" and observedBuild>0 and
        observedBuild==math.floor(observedBuild) and observedBuild==liveBuild and
        tonumber(info.skillLine)==tonumber(def.skillLineID) and
        (info.professionEnum==nil or tonumber(info.professionEnum)==tonumber(def.professionEnum))
    if slotVerified then
        -- A newly observed occupant displaces stale slot claims, but we
        -- retain their historical profession and skill information.
        for otherKey,other in pairs(store.professions) do
            if otherKey~=info.key and type(other)=="table" and other.lastObservedPrimarySlot==slot then
                other.lastObservedPrimarySlot=nil
                other.lastObservedPrimarySlotEvidence=nil
            end
        end
        row.lastObservedPrimarySlot=slot
        row.lastObservedPrimarySlotEvidence={
            source="get-professions-primary",professionKey=info.key,
            characterKey=owner,clientBuild=observedBuild,
            skillLineID=tonumber(info.skillLine),
        }
    end
    row.updatedAt = now()
    store.professions[info.key] = row
    store.updatedAt = now()
    return row
end

function KnowledgeCache:SyncProfessions(professions)
    local store = characterStore()
    if not store then return false end
    -- Native profession APIs can temporarily return an empty or partial list
    -- during login/reload. Merge positive observations into the persistent
    -- store, but never interpret a missing row here as an explicit unlearn.
    -- Explicit invalidation is handled only from credible contradictory data.
    for _, info in ipairs(professions or {}) do
        if info and info.key then self:RememberProfession(info) end
    end
    store.updatedAt = now()
    return true
end

-- Ownership migration also reads qualified historical profession/slot facts.
-- Detach their nested evidence so a read cannot become an implicit DB writer.
local function detachedProfessionFact(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {};if seen[value] then return seen[value] end
    local copy={};seen[value]=copy
    for key,field in pairs(value) do copy[key]=detachedProfessionFact(field,seen) end
    return copy
end
function KnowledgeCache:GetProfession(key)
    local store = characterStore()
    return detachedProfessionFact(store and store.professions and store.professions[key] or nil)
end

function KnowledgeCache:GetProfessions()
    local store = characterStore()
    return detachedProfessionFact(store and store.professions or {})
end

-- Only affirmative learned=true from an identified current-client recipe entry
-- may qualify session authority. A nonempty GetAllRecipeIDs enumeration proves
-- availability, NOT completeness or negative learned-state.
function KnowledgeCache:RememberRecipeScan(professionKey, known, recipeIDs, scanEvidence)
    if not professionKey then return false end
    local store = characterStore()
    if not store then return false end
    local normalized, ids = {}, {}
    for recipeName, value in pairs(known or {}) do
        if value == true then
            local key = normalizeText(recipeName)
            if key ~= "" then normalized[key] = true end
        end
    end
    for recipeName, recipeID in pairs(recipeIDs or {}) do
        local key = normalizeText(recipeName)
        local id = tonumber(recipeID)
        if key ~= "" and id and id>0 and id==math.floor(id) then ids[key] = id end
    end
    local previous = store.recipes[professionKey]
    if type(previous) ~= "table" then previous = {} end
    -- Preserve positive saved facts. Unverified scan absence never deletes a
    -- previous learned recipe or changes it to not-known.
    local merged = {}
    for key, value in pairs(previous.known or {}) do
        if value == true then merged[key] = true end
    end
    local allIDs = {}
    for key, id in pairs(previous.recipeIDs or {}) do
        if tonumber(id) then allIDs[key] = tonumber(id) end
    end
    local recipeBuilds = {}
    for key, build in pairs(previous.recipeBuilds or {}) do
        recipeBuilds[key] = build
    end
    local build, buildSource = currentBuild()
    local session = sessionFor(characterKey(), professionKey)
    local characterNegatives = sessionUnlearned[characterKey()]
    if not characterNegatives then characterNegatives = {};sessionUnlearned[characterKey()] = characterNegatives end
    local negative = characterNegatives[professionKey]
    if not negative then negative = {};characterNegatives[professionKey] = negative end
    local conflicts = sessionConflicts[characterKey()]
    if not conflicts then conflicts = {}; sessionConflicts[characterKey()] = conflicts end
    local professionConflicts = conflicts[professionKey]
    if not professionConflicts then professionConflicts = {}; conflicts[professionKey] = professionConflicts end
    local fresh = type(scanEvidence)=="table" and scanEvidence.sessionConfirmed==true
        and build~=nil and buildSource=="live-client"
    -- Build an ID-primary transient index only from a stable verified panel.
    -- Same-name different-ID learned=false never removes another positive ID.
    if fresh and type(scanEvidence.observedByID)=="table" then
        local char=characterKey()
        sessionByID[char]=sessionByID[char] or {}
        local byID={}
        for rawID,record in pairs(scanEvidence.observedByID) do
            local id=tonumber(rawID)
            if id and type(record)=="table" and record.verifiedMembership==true and
                (record.learned==true or record.learned==false) then
                byID[id]={learned=record.learned,build=build,
                    name=normalizeText(record.name),panelToken=scanEvidence.panelToken,
                    recipeSkillLineID=record.recipeSkillLineID,
                    parentSkillLineID=record.parentSkillLineID,
                    identityState=record.identityState}
            end
        end
        sessionByID[char][professionKey]=byID
    end
    -- An explicit learned=false for this exact entry revokes a previously
    -- granted session advisory, without rewriting persistent saved positives.
    -- Absence from a partial/filtered enumeration is NEVER such evidence.
    if fresh and type(scanEvidence.explicitUnlearned)=="table" then
        for name, observedIDs in pairs(scanEvidence.explicitUnlearned) do
            local key = normalizeText(name)
            local savedID = tonumber(allIDs[key])
            -- Accept the prior scalar contract for existing direct callers,
            -- while RouteProgress now sends an ID-keyed set. The last false
            -- row of another SpellID must never erase the saved ID's false.
            if type(observedIDs)~="table" then
                observedIDs={[observedIDs]=true}
            end
            for observedID, explicitlyFalse in pairs(observedIDs) do
                observedID=tonumber(observedID)
                -- A name-only negative or unrelated SpellID cannot disprove
                -- the saved identity. Missing entries are not negatives.
                if key ~= "" and explicitlyFalse==true and observedID and
                    savedID==observedID then
                    session[key] = nil
                    negative[key] = {build=build, recipeID=observedID}
                end
            end
        end
    end
    -- A fresh, stable panel exposing two learned SpellIDs for one normalized
    -- name is explicit identity contradiction, not mere absence from a partial
    -- enumeration. Revoke only that recipe's transient authority. SavedVariables
    -- keep their original positive ID and source build for audit/rollback.
    if fresh and type(scanEvidence.conflictingNames)=="table" then
        for name, conflict in pairs(scanEvidence.conflictingNames) do
            if conflict == true then
                local key = normalizeText(name)
                if key ~= "" then
                    session[key] = nil
                    professionConflicts[key] = true
                end
            end
        end
    end
    for key in pairs(normalized) do
        -- Never restore a conflicted name in the same inconsistent scan.
        if not professionConflicts[key] or
           not (type(scanEvidence.conflictingNames)=="table" and
                scanEvidence.conflictingNames[key]==true) then
            merged[key] = true
            if ids[key] then
                if not (merged[key]==true and allIDs[key] and allIDs[key]~=ids[key]) then
                    allIDs[key] = ids[key]
                end
                recipeBuilds[key] = build
                if fresh then
                    if tonumber(allIDs[key])==tonumber(ids[key]) then
                        session[key] = {build=build, recipeID=ids[key],
                            panelToken=scanEvidence.panelToken,
                            panelRevision=scanEvidence.panelRevision}
                    end
                    negative[key] = nil -- newer unique learned=true restores advice
                    professionConflicts[key] = nil
                end
            end
        end
    end
    -- In particular, preexisting complete=true snapshots from older addon
    -- versions are not evidence that a filtered/partial list was complete.
    store.recipes[professionKey] = {
        known=merged, recipeIDs=allIDs, recipeBuilds=recipeBuilds,
        available=true, complete=false, completenessVerified=false,
        build=build, buildSource=buildSource, scannedAt=now(),
        scanCompletenessReason="RECIPE_ENUMERATION_NOT_PROVEN_COMPLETE",
    }
    store.updatedAt = now()
    return true
end

function KnowledgeCache:RememberRecipeID(professionKey, recipeName, recipeID)
    local key = normalizeText(recipeName)
    local id = tonumber(recipeID)
    if key == "" or not professionKey or not id then return false end
    local store = characterStore()
    if not store then return false end
    local state = store.recipes[professionKey]
    if type(state) ~= "table" then
        local build, buildSource = currentBuild()
        -- A metadata lookup is NOT a scan and must not manufacture scannedAt.
        state = { known = {}, recipeIDs = {}, complete = false, build = build, buildSource = buildSource }
        store.recipes[professionKey] = state
    end
    state.known = state.known or {}
    state.recipeIDs = state.recipeIDs or {}
    state.recipeBuilds = state.recipeBuilds or {}
    local build, buildSource = currentBuild()
    -- ID resolution is not evidence that the character LEARNED the recipe.
    -- Do not overwrite a prior confirmed positive with a contradictory ID.
    local previousID = tonumber(state.recipeIDs[key])
    if state.known[key] == true and previousID and previousID ~= id then
        return false
    end
    state.recipeIDs[key] = id
    -- Preserve any previously confirmed recipeBuilds/known positive, without
    -- assigning a new learned build or a session proof from an ID lookup.
    state.lastObservedBuild = build
    state.lastObservedBuildSource = buildSource
    -- Keep any genuine older scan timestamp unchanged. Never synthesize one
    -- from ID lookup or upgrade legacy complete=true into verified completeness.
    store.updatedAt = now()
    return true
end

function KnowledgeCache:GetRecipeID(recipeName, professionKey)
    local key = normalizeText(recipeName)
    if key == "" or not professionKey then return nil end
    local store = characterStore()
    local state = store and store.recipes and store.recipes[professionKey]
    return state and state.recipeIDs and tonumber(state.recipeIDs[key]) or nil
end

function KnowledgeCache:GetRecipeKnowledge(recipeName, professionKey)
    local key = normalizeText(recipeName)
    if key == "" or not professionKey then return "unknown" end
    local store = characterStore()
    local state = store and store.recipes and store.recipes[professionKey]
    if type(state) ~= "table" then return "unknown" end
    if state.known and state.known[key] then return "known" end
    -- Build equality and SavedVariables `complete` / `completenessVerified`
    -- flags do not prove a complete *current-session* recipe enumeration.
    -- This API may report positive persisted knowledge as advisory, but no
    -- negative recipe authority from a legacy build-only saved scan.
    return "unknown"
end

function KnowledgeCache:GetRecipeKnowledgeState(recipeName, professionKey)
    local key = normalizeText(recipeName)
    local activeBuild, buildSource = currentBuild()
    if key == "" or not professionKey then
        return { knowledge="unknown", currentBuild=activeBuild, currentBuildSource=buildSource,
            currentBuildObserved=false, sessionLearnedObserved=false, scanAvailable=false, scanComplete=false }
    end
    local store = characterStore()
    local state = store and store.recipes and store.recipes[professionKey]
    if type(state) ~= "table" then
        return { knowledge="unknown", currentBuild=activeBuild, currentBuildSource=buildSource,
            currentBuildObserved=false, sessionLearnedObserved=false, scanAvailable=false, scanComplete=false }
    end
    local knowledge = self:GetRecipeKnowledge(recipeName, professionKey)
    local observedBuild = state.recipeBuilds and tonumber(state.recipeBuilds[key]) or nil
    local scanBuild = tonumber(state.build)
    -- No current scan produces an exhaustive enumeration receipt. Legacy
    -- `complete` flags remain archival metadata, never live negative proof.
    local scanComplete = false
    local currentObserved = buildSource=="live-client" and activeBuild ~= nil and (
        (observedBuild ~= nil and observedBuild == activeBuild)
        or (knowledge == "not-known" and scanComplete and scanBuild ~= nil and scanBuild == activeBuild)
    )
    local session = sessionLearned[characterKey()]
    session = session and session[professionKey]
    local evidence = session and session[key]
    local negativeRows = sessionUnlearned[characterKey()]
    negativeRows = negativeRows and negativeRows[professionKey]
    local explicitNegative = negativeRows and negativeRows[key]
    local negativeActive = buildSource=="live-client" and
        type(explicitNegative)=="table" and activeBuild~=nil and
        tonumber(explicitNegative.build)==tonumber(activeBuild) and
        tonumber(explicitNegative.recipeID)==tonumber(state.recipeIDs and state.recipeIDs[key])
    local conflicts = sessionConflicts[characterKey()]
    local conflict = conflicts and conflicts[professionKey] and conflicts[professionKey][key] == true
    -- A new panel cannot inherit a previous panel's per-name confirmation.
    local livePanel=nil
    if evidence and evidence.panelToken then
        local api=JLP:GetModule("ProfessionAPI")
        livePanel=api and api.GetOpenProfessionContext and api:GetOpenProfessionContext()
    end
    local panelCurrent=not (evidence and evidence.panelToken) or
        (livePanel and livePanel.verified==true and
         livePanel.panelToken==evidence.panelToken and
         livePanel.panelRevision==evidence.panelRevision and
         livePanel.professionKey==professionKey)
    local sessionObserved = buildSource=="live-client" and panelCurrent and not conflict and
        knowledge == "known" and activeBuild ~= nil and
        type(evidence) == "table" and tonumber(evidence.build) == tonumber(activeBuild) and
        tonumber(evidence.recipeID) ~= nil and
        tonumber(evidence.recipeID) == tonumber(state.recipeIDs and state.recipeIDs[key])
    -- Matching a persisted build number only proves historical provenance.
    -- A current-client claim needs a surviving same-session learned/negative
    -- observation, including the interface identity checked above.
    currentObserved = currentObserved and
        (sessionObserved or (knowledge=="not-known" and negativeActive and scanComplete))
    return {
        knowledge = knowledge,
        recipeID = state.recipeIDs and tonumber(state.recipeIDs[key]) or nil,
        -- Older snapshots may carry scannedAt from RememberRecipeID; without
        -- an explicit available flag that timestamp cannot establish a scan.
        scanAvailable = state.available == true,
        sessionIdentityConflict = conflict and true or false,
        sessionExplicitUnlearned = negativeActive and true or false,
        scanComplete = scanComplete,
        scanCompletenessReason = scanComplete and "INDEPENDENTLY_VERIFIED" or "RECIPE_ENUMERATION_NOT_PROVEN_COMPLETE",
        sessionLearnedObserved = sessionObserved and true or false,
        scanBuild = scanBuild,
        observedBuild = observedBuild,
        currentBuild = activeBuild,
        currentBuildSource = buildSource,
        currentBuildObserved = currentObserved and true or false,
    }
end

-- P1-177: exact-ID volatile recipe observation. Does not write Learned, scan
-- state, SavedVariables or the session-authoritative tables. A saved recipe ID
-- can be used as a LOOKUP KEY only; learned state is read from the open panel.
function KnowledgeCache:GetReadOnlyRecipeKnowledgeState(recipeName,professionKey,recipeID)
    local out={contract="recipe-volatile-advisory-v1",readOnly=true,
        nativeDispatchAllowed=false,plannerHandoffEligible=false,
        persistentReceiptEligible=false,currentBuildObserved=false,
        sessionLearnedObserved=false,readOnlyObserved=false,
        knowledge="unknown",reason="UNVERIFIED"}
    local name=normalizeText(recipeName)
    if name=="" or type(professionKey)~="string" or professionKey=="" then
        out.reason="RECIPE_OR_PROFESSION_MISSING";return out
    end
    -- Inspect existing SavedVariables without calling characterStore(): the
    -- read-only accessor must not create or update persistent cache entries.
    local root=JLP.DB and JLP.DB.account and JLP.DB.account.knowledge
    local characters=root and root.characters
    local owner=characters and characters[characterKey()]
    local state=owner and owner.recipes and owner.recipes[professionKey]
    out.historicalKnowledge=state and state.known and state.known[name]==true
        and "known" or "unknown"
    local id=tonumber(recipeID) or tonumber(state and state.recipeIDs and state.recipeIDs[name])
    if not id or id<1 or id~=math.floor(id) or id==math.huge then
        out.reason="EXACT_RECIPE_ID_UNAVAILABLE";return out
    end
    out.recipeID=id
    local api=JLP:GetModule("ProfessionAPI")
    if not api or type(api.GetReadOnlyRecipeObservation)~="function" then
        out.reason="READ_ONLY_RECIPE_API_UNAVAILABLE";return out
    end
    local live=api:GetReadOnlyRecipeObservation(id,professionKey)
    if type(live)~="table" or live.readOnlyObserved~=true then
        out.reason=live and live.reason or "RECIPE_UNVERIFIED";return out
    end
    if normalizeText(live.name)~=name or live.professionKey~=professionKey or
        tonumber(live.recipeID)~=id or type(live.learned)~="boolean" then
        out.reason="RECIPE_ID_OR_NAME_CONFLICT";return out
    end
    out.readOnlyObserved=true
    out.learned=live.learned
    out.knowledge=live.learned and "known" or "not-known"
    out.observationQuality=live.observationQuality
    out.reason="LIVE_RECIPE_READ_ONLY"
    return out
end

function KnowledgeCache:InvalidateSessionObservations()
    -- A changed / closed panel cannot lend its previously verified learning
    -- to a new panel session. Persistent audit history stays intact.
    sessionLearned={};sessionUnlearned={};sessionConflicts={};sessionByID={}
end

function KnowledgeCache:GetRecipeIDObservation(professionKey, recipeID)
    local build=select(1,currentBuild())
    local character=sessionByID[characterKey()]
    local rows=character and character[professionKey]
    local observed=rows and rows[tonumber(recipeID)]
    local api=JLP:GetModule("ProfessionAPI")
    local panel=api and api.GetOpenProfessionContext and api:GetOpenProfessionContext()
    if not observed or not build or tonumber(observed.build)~=tonumber(build) or
        not panel or panel.verified~=true or panel.professionKey~=professionKey or
        panel.panelToken~=observed.panelToken then
        return {observed=false,learned=nil,sessionLearnedObserved=false}
    end
    return {observed=true,learned=observed.learned,
        sessionLearnedObserved=observed.learned==true,
        sessionExplicitUnlearned=observed.learned==false,
        recipeID=tonumber(recipeID),build=build,name=observed.name,
        identityState=observed.identityState,
        recipeSkillLineID=observed.recipeSkillLineID,
        parentSkillLineID=observed.parentSkillLineID}
end

function KnowledgeCache:GetRecipeSnapshot()
    local store = characterStore()
    local union, states = {}, {}
    for professionKey, state in pairs((store and store.recipes) or {}) do
        states[professionKey] = state
        for recipeName, known in pairs((state and state.known) or {}) do
            if known then union[recipeName] = true end
        end
    end
    return union, states
end

function KnowledgeCache:GetSummary()
    local account = accountStore()
    local character = characterStore()
    local itemCount, recipeCount, professionScans = 0, 0, 0
    for _ in pairs((account and account.items) or {}) do itemCount = itemCount + 1 end
    for _, state in pairs((character and character.recipes) or {}) do
        professionScans = professionScans + 1
        for _, known in pairs((state and state.known) or {}) do if known then recipeCount = recipeCount + 1 end end
    end
    return string.format("Persistent knowledge: %d item records - %d known recipes across %d profession scan(s)", itemCount, recipeCount, professionScans)
end

JLP:RegisterModule("KnowledgeCache", KnowledgeCache)
