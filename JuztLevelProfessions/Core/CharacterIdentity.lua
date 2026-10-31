local _, JLP = ...

local CharacterIdentity = {
    contract = "stable-character-identity-v1",
    reconciliationContract = "lazy-character-key-reconciliation-v1",
    storeSchema = 1,
}

local cache

local function readNameRealm()
    local name, realm
    if type(UnitFullName) == "function" then
        local ok, n, r = pcall(UnitFullName, "player")
        if ok then name, realm = n, r end
    end
    if (not name or name == "") and type(UnitName) == "function" then
        local ok, n = pcall(UnitName, "player")
        if ok then name = n end
    end
    if (not realm or realm == "") and type(GetRealmName) == "function" then
        local ok, r = pcall(GetRealmName)
        if ok then realm = r end
    end
    return tostring(name or "UnknownCharacter"), tostring(realm or "UnknownRealm")
end

local function readGUID()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if not ok or type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

local function deepMergeMissing(dst, src, seen)
    if type(dst) ~= "table" or type(src) ~= "table" then return dst end
    seen = seen or {}
    if seen[src] then return dst end
    seen[src] = true
    for key, value in pairs(src) do
        if dst[key] == nil then
            dst[key] = value
        elseif type(dst[key]) == "table" and type(value) == "table" then
            deepMergeMissing(dst[key], value, seen)
        end
    end
    return dst
end

function CharacterIdentity:LegacyKey(name, realm)
    return tostring(realm or "UnknownRealm") .. ":" .. tostring(name or "UnknownCharacter")
end

function CharacterIdentity:StableKey(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    return "guid:" .. guid
end

function CharacterIdentity:GetCurrent(force)
    if cache and not force then return cache end
    local name, realm = readNameRealm()
    local guid = readGUID()
    local legacyKey = self:LegacyKey(name, realm)
    local stableKey = self:StableKey(guid)
    cache = {
        key = stableKey or legacyKey,
        stableKey = stableKey,
        legacyKey = legacyKey,
        guid = guid,
        name = name,
        realm = realm,
        source = stableKey and "unit-guid" or "legacy-realm-name",
    }
    return cache
end

function CharacterIdentity:GetKey(force)
    return self:GetCurrent(force).key
end

function CharacterIdentity:ClearCache()
    cache = nil
end

function CharacterIdentity:ReconcileCharactersMap(characters, identity, previousAlias)
    if type(characters) ~= "table" then return { moved=false, merged=false, reason="no-characters-map" } end
    identity = identity or self:GetCurrent()
    -- Rod competence is one atomic, evidenced capability, not missing scalars.
    -- Both account initialization and lazy resolver reads use this dispatch.
    local rods = JLP.DB and JLP.DB.account and JLP.DB.account.enchantingRodCompetence
    if rods and characters == rods.characters then
        local resolver = JLP:GetModule("EnchantingToolResolver")
        if resolver and resolver.ReconcileCompetence then
            return resolver:ReconcileCompetence(characters, identity, previousAlias)
        end
        return {moved=false,merged=false,reason="rod-resolver-unavailable-deferred"}
    end
    if not identity.stableKey or identity.stableKey == identity.legacyKey then
        return { moved=false, merged=false, reason="stable-guid-unavailable", key=identity.key }
    end
    local legacy = characters[identity.legacyKey]
    local stable = characters[identity.stableKey]
    if type(legacy) ~= "table" then
        return { moved=false, merged=false, reason="no-legacy-record", key=identity.stableKey }
    end
    if type(stable) ~= "table" then
        characters[identity.stableKey] = legacy
        characters[identity.legacyKey] = nil
        return { moved=true, merged=false, reason="moved", from=identity.legacyKey, to=identity.stableKey }
    end
    deepMergeMissing(stable, legacy)
    characters[identity.legacyKey] = nil
    return { moved=true, merged=true, reason="merged", from=identity.legacyKey, to=identity.stableKey }
end

-- Preserves independent observation receipts when the same character exists
-- under both the old realm/name key and the stable GUID key. Generic deep
-- merges of numeric arrays would otherwise discard overlapping row indices.
local function mergeObservationRows(stable, legacy, maximum)
    local a=type(stable)=="table" and stable.rows or nil
    local b=type(legacy)=="table" and legacy.rows or nil
    if type(a)~="table" or type(b)~="table" then return end
    local ids={}
    for _,row in ipairs(a) do if type(row)=="table" and row.id then ids[tostring(row.id)]=true end end
    for _,row in ipairs(b) do
        if type(row)=="table" and row.id and not ids[tostring(row.id)] then
            ids[tostring(row.id)]=true
            a[#a+1]=row
        end
    end
    table.sort(a,function(x,y)
        local xa,ya=tonumber(x.finishedAt) or 0,tonumber(y.finishedAt) or 0
        if xa~=ya then return xa<ya end
        return tostring(x.id or "")<tostring(y.id or "")
    end)
    while #a>maximum do table.remove(a,1) end
end

function CharacterIdentity:ReconcileAccount(db)
    if type(db) ~= "table" then return nil, "db-unavailable" end
    db.account = db.account or {}
    db.account.characterIdentity = db.account.characterIdentity or { schema=self.storeSchema, aliases={}, records={} }
    local root = db.account.characterIdentity
    root.schema = self.storeSchema
    root.aliases = root.aliases or {}
    root.records = root.records or {}

    local identity = self:GetCurrent(true)
    local previousAlias = root.aliases[identity.legacyKey] or false
    local receipt = {
        contract = self.reconciliationContract,
        key = identity.key,
        stableKey = identity.stableKey,
        legacyKey = identity.legacyKey,
        source = identity.source,
        stores = {},
        movedStores = 0,
        mergedStores = 0,
    }

    if identity.stableKey then
        root.aliases[identity.legacyKey] = identity.stableKey
        root.records[identity.stableKey] = root.records[identity.stableKey] or {}
        local record = root.records[identity.stableKey]
        record.guid = identity.guid
        record.name = identity.name
        record.realm = identity.realm
        record.legacyKey = identity.legacyKey
        record.lastSeenVersion = JLP.version
        if type(time) == "function" then
            local ok, stamp = pcall(time)
            if ok then record.lastSeenAt = stamp end
        end
    end

    for _, field in ipairs({
        "inventory", "knowledge", "routeProgress", "progressTracking", "executionProgress",
        "routeCheckpoint", "transactionRecovery", "transactionLedger", "recipeTelemetry", "recipeOutputEvidence",
        "craftObservation70374", "craftObservation70450", "enchantingRodCompetence",
    }) do
        local store = db.account[field]
        if type(store) == "table" and type(store.characters) == "table" then
            if field=="craftObservation70374" or field=="craftObservation70450" then
                mergeObservationRows(store.characters[identity.stableKey],
                    store.characters[identity.legacyKey],
                    field=="craftObservation70374" and 60 or 150)
            end
            local r
            if field=="enchantingRodCompetence" then
                local resolver=JLP:GetModule("EnchantingToolResolver")
                r=resolver and resolver.ReconcileCompetence and
                    resolver:ReconcileCompetence(store.characters,identity,previousAlias) or
                    {moved=false,merged=false,reason="rod-resolver-unavailable-deferred"}
            else
                r=self:ReconcileCharactersMap(store.characters,identity)
            end
            receipt.stores[field] = r
            if r.moved then receipt.movedStores = receipt.movedStores + 1 end
            if r.merged then receipt.mergedStores = receipt.mergedStores + 1 end
        end
    end

    root.lastReconciliation = receipt
    return receipt
end

function CharacterIdentity:GetSummary()
    local row = self:GetCurrent()
    return string.format(
        "Stable character identity: %s · source %s · legacy %s · GUID %s",
        tostring(row.key), tostring(row.source), tostring(row.legacyKey), tostring(row.guid or "unavailable")
    )
end

function CharacterIdentity:ResolveAlias(key)
    local db = JLP.DB
    local aliases = db and db.account and db.account.characterIdentity and db.account.characterIdentity.aliases
    return type(aliases) == "table" and aliases[key] or key
end

JLP:RegisterModule("CharacterIdentity", CharacterIdentity)
