local _, JLP = ...
local Inventory = { bankOpen = false, bankOpenedAt = nil }
local identityCache
local itemCountCallShape = setmetatable({}, { __mode = "k" })
-- Evidence is scoped to the exact callable: replacing an API implementation
-- never inherits a previous function's observed includeBank semantics.
local itemCountBankSemantics = setmetatable({}, { __mode = "k" })

-- An item-count result must be a valid nonnegative observation, not an API
-- sentinel/invalid result (or a SavedVariables-derived estimate).
local function validCount(value)
    local n = tonumber(value)
    return n and n == n and n >= 0 and n < math.huge and n == math.floor(n) and n or nil
end

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return value end
    end
    return nil
end

local function characterIdentity()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetCurrent then
        local row = identity:GetCurrent()
        return row.key, row.name, row.realm, row.guid, row.legacyKey, row.source
    end
    return "UnknownRealm:UnknownCharacter", "UnknownCharacter", "UnknownRealm", nil, nil, "fallback"
end

local function characterKey()
    local key = characterIdentity()
    return key
end

local function getCharacterStore()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.inventory = JLP.DB.account.inventory or { characters = {} }
    JLP.DB.account.inventory.characters = JLP.DB.account.inventory.characters or {}
    local key, name, realm, guid, legacyKey, identitySource = characterIdentity()
    local character = JLP.DB.account.inventory.characters[key]
    if type(character) ~= "table" then
        character = {}
        JLP.DB.account.inventory.characters[key] = character
    end
    character.meta = character.meta or {}
    character.meta.key = key
    character.meta.name = name
    character.meta.realm = realm
    character.meta.guid = guid
    character.meta.legacyKey = legacyKey
    character.meta.identitySource = identitySource
    -- Persist faction only when the local client independently reports it.
    -- Alt-character bank/bag snapshots must never inherit the active faction.
    if type(UnitFactionGroup)=="function" then
        local ok, faction = pcall(UnitFactionGroup,"player")
        if ok and (faction=="Horde" or faction=="Alliance") then
            character.meta.faction=faction
        end
    end
    local stamp = now()
    if stamp and (not character.meta.lastSeenAt or stamp - character.meta.lastSeenAt >= 60) then character.meta.lastSeenAt = stamp end
    character.bags = character.bags or { known = false, items = {}, updatedAt = nil }
    character.bank = character.bank or { known = false, items = {}, slots = {}, totalSlots = 0, usedSlots = 0, updatedAt = nil }
    character.bags.items = character.bags.items or {}
    character.bank.items = character.bank.items or {}
    character.bank.slots = character.bank.slots or {}
    return character
end

-- A successful call with extra arguments proves only that Lua accepted them:
-- functions declared as function(itemID) silently ignore includeBank. The
-- documented native Blizzard GetItemCount/C_Item.GetItemCount implementation
-- supports includeBank; for Lua wrappers/mocks, require observable response to
-- toggling the flag on the SAME item and call shape. An unchanged zero-bank
-- total is ambiguous until such evidence exists for that exact callable.
local function nativeItemCountContract(fn)
    if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then return false end
    local ok, info = pcall(debug.getinfo, fn, "S")
    return ok and type(info) == "table" and info.what == "C"
end

local function definitelyBagOnlyLua(fn)
    if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then return false end
    local ok, info = pcall(debug.getinfo, fn, "uS")
    -- Only the strict fixed-arity case is rejected: a vararg implementation
    -- may legitimately consume includeBank despite a single named parameter.
    return ok and type(info) == "table" and info.what == "Lua" and
        type(info.nparams) == "number" and info.nparams < 2 and not info.isvararg
end

local function callCount(fn, itemID, includeBank)
    if type(fn) ~= "function" then return nil, false end
    local bank = includeBank and true or false
    local function invoke(shape, withBank)
        if shape == 4 then return pcall(fn, itemID, withBank, false, false) end
        if shape == 3 then return pcall(fn, itemID, withBank, false) end
        if shape == 2 then return pcall(fn, itemID, withBank) end
        return pcall(fn, itemID)
    end
    local preferred = itemCountCallShape[fn]
    if not includeBank then
        local shapes = preferred and {preferred, 4, 3, 2, 1} or {4, 3, 2, 1}
        for _, shape in ipairs(shapes) do
            local ok, value = invoke(shape, false)
            local count = ok and validCount(value)
            if count then
                itemCountCallShape[fn] = shape
                return count, true
            end
        end
        itemCountCallShape[fn] = nil
        return nil, false
    end

    -- A literal one-parameter, non-vararg Lua implementation cannot consume
    -- extra arguments. Keep its valid bag observation, not fake bank evidence.
    if definitelyBagOnlyLua(fn) then return nil, false end
    local native = nativeItemCountContract(fn)
    local shapes = (preferred and preferred ~= 1) and
        {preferred, 4, 3, 2} or {4, 3, 2}
    for _, shape in ipairs(shapes) do
        local ok, value = invoke(shape, true)
        local total = ok and validCount(value)
        if total then
            -- A previous differential observation or the documented native
            -- API contract qualifies an equal (zero-bank) observation too.
            if native or itemCountBankSemantics[fn] then
                itemCountCallShape[fn] = shape
                return total, true
            end
            local bagOK, bagValue = invoke(shape, false)
            local bags = bagOK and validCount(bagValue)
            if bags and bags ~= total then
                -- A smaller includeBank result is contradictory, not positive
                -- evidence of bank semantics. Still return the observation so
                -- GetBankCount can report BANK_COUNT_CONFLICT, but do not
                -- authorize a later equal result for this callable.
                if total > bags then itemCountBankSemantics[fn] = true end
                itemCountCallShape[fn] = shape
                return total, true
            end
            -- Same result is not evidence of includeBank capability for an
            -- unqualified wrapper, even if it accepts extra arguments.
        end
    end
    return nil, false
end

local function apiCount(itemID, includeBank)
    itemID = tonumber(itemID)
    if not itemID then return nil, false end
    if type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        local value, ok = callCount(C_Item.GetItemCount, itemID, includeBank)
        if ok then return value, true end
    end
    return callCount(GetItemCount, itemID, includeBank)
end

local function numSlots(bagID)
    if type(C_Container) == "table" and type(C_Container.GetContainerNumSlots) == "function" then
        local ok, value = pcall(C_Container.GetContainerNumSlots, bagID)
        if ok and validCount(value) then return validCount(value), true end
    end
    if type(GetContainerNumSlots) == "function" then
        local ok, value = pcall(GetContainerNumSlots, bagID)
        if ok and validCount(value) then return validCount(value), true end
    end
    return 0, false
end

local function characterBankTabIDs()
    -- The client's API surface may change during bank-frame initialization;
    -- resolve each scan from live Enum/slot observations, never a stale cache.
    local out = {}
    local seen = {}
    local bagIndex = type(Enum) == "table" and type(Enum.BagIndex) == "table" and Enum.BagIndex or nil
    if bagIndex then
        -- Forever 1.60.1 exposes the ordinary character bank as numbered
        -- CharacterBankTab_N containers. CharacterBankTab_1 is the 48-slot base
        -- bank; CharacterBankTab_2..9 correspond to the eight purchasable bank
        -- bag positions. Do not use Enum.BagIndex.Keyring/BANK_CONTAINER (-1)
        -- as the base bank on Forever: that is a different storage domain.
        local indexed = {}
        for key, value in pairs(bagIndex) do
            local normalized = string.lower(tostring(key)):gsub("[^a-z0-9]", "")
            local index = tonumber(normalized:match("^characterbanktab(%d+)$"))
            local numeric = tonumber(value)
            if index and numeric and not seen[numeric] then indexed[#indexed + 1] = { index=index, id=numeric } end
        end
        table.sort(indexed, function(a,b) return a.index < b.index end)
        for _, row in ipairs(indexed) do
            seen[row.id] = true
            out[#out + 1] = row.id
        end
    end

    -- Legacy numbered bank tabs have previously been observed at 6..14.
    -- Never infer their existence from the addon's TARGET_INTERFACE constant:
    -- a different client may expose unrelated containers at those IDs.
    -- Admit the legacy layout only when its base container is observable now.
    if #out == 0 then
        local slots, known = numSlots(6)
        local declared = tonumber(NUM_BANKGENERIC_SLOTS)
        local verifiedBase = known and slots > 0 and
            (slots >= 48 or (declared and declared > 0 and slots == declared))
        -- A legacy layout is only provisionally identified while a bank is
        -- actually open, with live slot counts (never a pinned interface ID).
        if Inventory.bankOpen == true and verifiedBase then
            for id = 6, 14 do out[#out + 1] = id end
        end
    end
    -- Missing/incomplete runtime evidence is retried every observation, even
    -- when a client adds additional CharacterBankTab IDs after opening.
    return out
end

local function purchasedBankBagCount(tabs)
    if type(GetNumBankSlots) == "function" then
        local ok, value = pcall(GetNumBankSlots)
        if ok and tonumber(value) then
            return math.max(0, math.min(8, math.floor(tonumber(value) or 0))), true, "GetNumBankSlots"
        end
    end

    -- Retail-derived Forever clients also expose C_Bank. When the legacy count
    -- is unavailable, derive the number of extra unlocked bank positions from
    -- purchased Character-bank tab IDs. The base tab itself is not a bag slot.
    if type(C_Bank) == "table" and type(C_Bank.FetchPurchasedBankTabIDs) == "function" then
        local bankType = type(Enum) == "table" and type(Enum.BankType) == "table" and Enum.BankType.Character or 0
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
        if ok and type(ids) == "table" then
            tabs = tabs or characterBankTabIDs()
            local ordinary = {}
            for _, id in ipairs(tabs) do ordinary[tonumber(id) or id] = true end
            local purchased = 0
            for _, id in ipairs(ids) do
                local identity = tonumber(id) or id
                if ordinary[identity] and identity ~= (tonumber(tabs[1]) or tabs[1]) then purchased = purchased + 1 end
            end
            return math.max(0, math.min(8, purchased)), true, "C_Bank.FetchPurchasedBankTabIDs"
        end
    end
    return nil, false, "unavailable"
end

local function bankBaseID(tabs)
    tabs = tabs or characterBankTabIDs()
    if tabs[1] ~= nil then return tabs[1], "character-bank-tab" end
    if BANK_CONTAINER ~= nil then return tonumber(BANK_CONTAINER) or BANK_CONTAINER, "legacy-bank-container" end
    if type(Enum) == "table" and type(Enum.BagIndex) == "table" and Enum.BagIndex.Bank ~= nil then
        return tonumber(Enum.BagIndex.Bank) or Enum.BagIndex.Bank, "legacy-bank-enum"
    end
    return -1, "legacy-fallback"
end

local function bankBagID(index, tabs)
    index = math.max(1, math.floor(tonumber(index) or 1))
    tabs = tabs or characterBankTabIDs()
    if tabs[index + 1] ~= nil then return tabs[index + 1], "character-bank-tab" end

    if type(Enum) == "table" and type(Enum.BagIndex) == "table" then
        local direct = Enum.BagIndex["BankBag_" .. tostring(index)]
        if direct ~= nil then return tonumber(direct) or direct, "legacy-bank-bag-enum" end
        for key, value in pairs(Enum.BagIndex) do
            local normalized = string.lower(tostring(key)):gsub("[^a-z0-9]", "")
            if normalized == ("bankbag" .. tostring(index)) then
                return tonumber(value) or value, "legacy-bank-bag-enum"
            end
        end
    end
    local bagSlots = tonumber(NUM_BAG_SLOTS) or 4
    return bagSlots + index, "legacy-offset"
end

local function slotInfo(bagID, slot)
    local primaryUnreadable = false
    if type(C_Container) == "table" and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bagID, slot)
        if ok and info == nil then return nil, 0, true end
        if ok and type(info) == "table" then
            local itemID = tonumber(info.itemID)
            local count = validCount(info.stackCount or info.count)
            if itemID then return itemID, count or 1, count ~= nil and count > 0 end
        end
        -- A failed or malformed primary observation is not evidence of an
        -- empty slot. An alternate nil item-ID cannot repair that failure.
        primaryUnreadable = true
    end

    local itemID, count, idKnown = nil, nil, false
    if type(C_Container) == "table" and type(C_Container.GetContainerItemID) == "function" then
        local ok, value = pcall(C_Container.GetContainerItemID, bagID, slot)
        if ok then
            itemID = validCount(value)
            if itemID == 0 then itemID = nil end
            idKnown = itemID ~= nil or (value == nil and not primaryUnreadable)
        end
    elseif type(GetContainerItemID) == "function" then
        local ok, value = pcall(GetContainerItemID, bagID, slot)
        if ok then
            itemID = validCount(value)
            if itemID == 0 then itemID = nil end
            idKnown = itemID ~= nil or (value == nil and not primaryUnreadable)
        end
    end
    if not itemID then return nil, 0, idKnown end

    if type(GetContainerItemInfo) == "function" then
        local ok, _, stackCount = pcall(GetContainerItemInfo, bagID, slot)
        if ok then count = validCount(stackCount) end
    end
    return itemID, count or 1, count ~= nil and count > 0
end

local function addUnique(out, seen, value)
    value = tonumber(value)
    if value == nil or seen[value] then return end
    seen[value] = true
    out[#out + 1] = value
end

local function bagIDs()
    -- Recompute from live Enum.BagIndex: an early login scan must not freeze
    -- the available bag/reagent-bag IDs for the remainder of the session.
    local out, seen = {}, {}
    local bagSlots = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, bagSlots do addUnique(out, seen, bag) end
    if type(Enum) == "table" and type(Enum.BagIndex) == "table" then
        for key, value in pairs(Enum.BagIndex) do
            local lower = string.lower(tostring(key))
            if lower == "backpack" or lower:match("^bag_") or lower == "reagentbag" then
                addUnique(out, seen, value)
            end
        end
    end
    return out
end

local FOREVER_BASE_BANK_SLOTS = 48

local function visibleBaseBankSlots(baseID, model, rawCount)
    baseID = baseID ~= nil and baseID or select(1, bankBaseID())
    local raw = rawCount ~= nil and math.max(0, math.floor(tonumber(rawCount) or 0)) or numSlots(baseID)
    if raw <= 0 then return 0, "unreadable" end

    -- Numbered CharacterBankTab_1 is the real Forever bank surface, so its live
    -- capacity is authoritative. This intentionally permits a future Forever
    -- build to change the base-bank size without JuztLevel being frozen at 48.
    if model == "character-bank-tab" then return raw, "character-bank-tab-size" end

    -- Legacy fallback only: cap oversized/shared BANK_CONTAINER surfaces to the
    -- currently audited Forever base-bank size. This path is never preferred on
    -- 1.60.1 when CharacterBankTab_N enums are available.
    if raw >= FOREVER_BASE_BANK_SLOTS then
        return FOREVER_BASE_BANK_SLOTS, raw == FOREVER_BASE_BANK_SLOTS and "container-size" or "forever-visible-cap"
    end
    local declared = math.max(0, math.floor(tonumber(NUM_BANKGENERIC_SLOTS) or 0))
    if declared > 0 then return math.min(raw, declared), "legacy-visible-fallback" end
    return raw, "container-size"
end

local function bankContainers()
    local out, seen = {}, {}
    local tabs = characterBankTabIDs()
    local baseID, bankModel = bankBaseID(tabs)
    local baseRaw, baseSizeKnown = numSlots(baseID)
    local baseLimit, baseSource = visibleBaseBankSlots(baseID, bankModel, baseRaw)
    out[#out + 1] = { bagID=baseID, rawSlots=baseRaw, slotsKnown=baseSizeKnown, slotLimit=baseLimit, kind="base", capacitySource=baseSource, containerModel=bankModel }
    seen[tonumber(baseID) or baseID] = true

    local purchased, purchasedKnown, purchasedSource = purchasedBankBagCount(tabs)
    local count = purchasedKnown and purchased or 0
    if not purchasedKnown then
        local maximum = tonumber(NUM_BANKBAGSLOTS) or 8
        for index = 1, maximum do
            local id, idModel = bankBagID(index, tabs)
            local slots, slotsKnown = numSlots(id)
            local identity = tonumber(id) or id
            if slots > 0 then
                if not seen[identity] then
                    seen[identity] = true
                    out[#out + 1] = { bagID=id, rawSlots=slots, slotsKnown=slotsKnown, slotLimit=slots, kind="bank-bag", bankBagIndex=index, capacitySource="inserted-bag", containerModel=idModel }
                end
            else
                break
            end
        end
    else
        for index = 1, count do
            local id, idModel = bankBagID(index, tabs)
            local identity = tonumber(id) or id
            if id ~= nil and not seen[identity] then
                seen[identity] = true
                local slots, slotsKnown = numSlots(id)
                out[#out + 1] = { bagID=id, rawSlots=slots, slotsKnown=slotsKnown, slotLimit=slots, kind="bank-bag", bankBagIndex=index, capacitySource="inserted-bag", containerModel=idModel }
            end
        end
    end
    return out, count, purchasedKnown, {
        model = bankModel,
        baseContainerID = baseID,
        purchasedSource = purchasedSource,
    }
end

local function observeItem(itemID)
    local cache = JLP:GetModule("KnowledgeCache")
    if cache and cache.ResolveItem then cache:ResolveItem(itemID) end
end

local function scanContainers(ids)
    local items = {}
    local readable, complete = false, true
    for _, bagID in ipairs(ids or {}) do
        local slots, slotsKnown = numSlots(bagID)
        -- An empty equipped bag position (zero slots) is a valid observation;
        -- a failed/unavailable slot-count API is not.
        if not slotsKnown then complete = false end
        if slots > 0 then readable = true end
        for slot = 1, slots do
            local itemID, count, slotKnown = slotInfo(bagID, slot)
            if not slotKnown then complete = false end
            if itemID and count and count > 0 then
                items[itemID] = (items[itemID] or 0) + count
            end
        end
    end
    -- Never publish a partial container scan as current BAG evidence.
    -- A failed scan may leave old persisted counts intact for advisory display.
    if not (readable and complete) then return {}, false end
    for itemID in pairs(items) do observeItem(itemID) end
    return items, true
end

local function scanContainersDetailed(containers)
    local items, slots = {}, {}
    local readable, complete, totalSlots, usedSlots, freeSlots = false, true, 0, 0, 0
    local baseSlots, bankBagSlots, baseReadable = 0, 0, false
    local containerDetails = {}
    for _, spec in ipairs(containers or {}) do
        local bagID = type(spec) == "table" and spec.bagID or spec
        local rawCount = type(spec) == "table" and tonumber(spec.rawSlots) or nil
        local sizeKnown = type(spec) == "table" and spec.slotsKnown
        if rawCount == nil then rawCount, sizeKnown = numSlots(bagID) end
        if sizeKnown ~= true then complete = false end
        rawCount = math.max(0, math.floor(tonumber(rawCount) or 0))
        local requestedLimit = type(spec) == "table" and tonumber(spec.slotLimit) or nil
        local count = rawCount
        if requestedLimit ~= nil then count = math.min(rawCount, math.max(0, math.floor(requestedLimit))) end
        if count > 0 then readable = true end
        if type(spec) == "table" and spec.kind == "base" and count > 0 then baseReadable = true end
        local occupiedFromRows = 0
        for slot = 1, count do
            totalSlots = totalSlots + 1
            local itemID, quantity, slotKnown = slotInfo(bagID, slot)
            -- A bank slot API failure is not an observed empty slot. Never
            -- replace a complete persisted bank snapshot with a partial read.
            if slotKnown ~= true then complete = false end
            local row = {
                bagID = bagID,
                slot = slot,
                itemID = itemID,
                count = tonumber(quantity) or 0,
                storageKind = type(spec) == "table" and spec.kind or nil,
                bankBagIndex = type(spec) == "table" and spec.bankBagIndex or nil,
            }
            slots[#slots + 1] = row
            if itemID and row.count > 0 then
                occupiedFromRows = occupiedFromRows + 1
                items[itemID] = (items[itemID] or 0) + row.count
            end
        end
        if type(spec) == "table" and spec.kind == "base" then baseSlots = baseSlots + count
        elseif type(spec) == "table" and spec.kind == "bank-bag" then bankBagSlots = bankBagSlots + count end
        containerDetails[#containerDetails + 1] = {
            bagID = bagID,
            kind = type(spec) == "table" and spec.kind or nil,
            bankBagIndex = type(spec) == "table" and spec.bankBagIndex or nil,
            rawSlots = rawCount,
            visibleSlots = count,
            usedSlots = occupiedFromRows,
            freeSlots = math.max(0, count - occupiedFromRows),
            capacitySource = type(spec) == "table" and spec.capacitySource or nil,
            containerModel = type(spec) == "table" and spec.containerModel or nil,
        }
        -- Capacity/usage must describe exactly the same visible slots that the
        -- Bank grid renders. Derive used/free from explicit per-slot occupancy
        -- instead of allowing a broader free-slot API to count another storage
        -- domain on custom/Forever clients.
        usedSlots = usedSlots + occupiedFromRows
        freeSlots = freeSlots + math.max(0, count - occupiedFromRows)
    end
    -- Do not publish knowledge/cache side effects from a failed bank scan.
    if complete then for itemID in pairs(items) do observeItem(itemID) end end
    return items, slots, readable, totalSlots, usedSlots, freeSlots, baseSlots, bankBagSlots, baseReadable, containerDetails, complete
end

local function countMapItems(map)
    local count = 0
    for _, quantity in pairs(map or {}) do if (tonumber(quantity) or 0) > 0 then count = count + 1 end end
    return count
end

function Inventory:GetCharacterKey()
    return characterKey()
end

function Inventory:SetBankOpen(open)
    local nextOpen=open and true or false
    if nextOpen and not self.bankOpen then
        self.bankOpenedAt=now()
        -- Each scan rediscovers the bank API/enum capabilities.
    end
    if not nextOpen then
        self.bankOpenedAt=nil
    end
    self.bankOpen=nextOpen
end

function Inventory:IsBankOpen()
    return self.bankOpen and true or false
end

function Inventory:RefreshBagCache()
    local character = getCharacterStore()
    if not character then return false, "database-not-ready" end
    local items, readable = scanContainers(bagIDs())
    if readable then
        character.bags.items = items
        character.bags.known = true
        character.bags.updatedAt = now()
        return true, items
    end
    return false, "bag-containers-not-readable"
end

function Inventory:RefreshBankCache(options)
    local character = getCharacterStore()
    if not character then return false, "database-not-ready" end
    options = type(options) == "table" and options or {}
    local containers, purchasedBankBags, purchasedKnown, bankMeta = bankContainers()
    local items, slots, readable, totalSlots, usedSlots, freeSlots, baseSlots, bankBagSlots, baseReadable, containerDetails, complete = scanContainersDetailed(containers)
    -- BANKFRAME_OPENED can fire before Forever materializes CharacterBankTab_1
    -- and/or the purchased bag containers. Never replace a good persisted
    -- snapshot with a partial scan. The immediate UI/open refresh therefore
    -- preserves a larger last-known-good capacity; settled/container-update
    -- callers opt into contraction once the client state is authoritative.
    if readable and complete and baseReadable and baseSlots > 0 then
        local previousTotal = character.bank and character.bank.known and tonumber(character.bank.totalSlots) or nil
        local allowContraction = options.allowContraction and true or false
        if previousTotal and totalSlots < previousTotal and not allowContraction then
            return false, "bank-capacity-settling"
        end
        character.bank.items = items
        character.bank.slots = slots
        character.bank.totalSlots = totalSlots
        character.bank.usedSlots = usedSlots
        character.bank.freeSlots = freeSlots
        character.bank.baseSlots = baseSlots
        character.bank.bankBagSlots = bankBagSlots
        character.bank.purchasedBankBags = purchasedBankBags
        character.bank.purchasedBankBagsKnown = purchasedKnown and true or false
        character.bank.purchasedBankBagsSource = bankMeta and bankMeta.purchasedSource or nil
        character.bank.containerModel = bankMeta and bankMeta.model or nil
        character.bank.baseContainerID = bankMeta and bankMeta.baseContainerID or nil
        character.bank.containerDetails = containerDetails
        character.bank.known = true
        character.bank.updatedAt = now()
        return true, items
    end
    return false, baseReadable and "bank-containers-not-readable" or "bank-base-container-not-ready"
end

function Inventory:GetCurrentCharacterIdentity()
    local key, name, realm, guid, legacyKey, identitySource = characterIdentity()
    return { key=key, name=name, realm=realm, guid=guid, legacyKey=legacyKey, identitySource=identitySource }
end

function Inventory:GetCharacterStore(key)
    if not JLP.DB or not JLP.DB.account or not JLP.DB.account.inventory then return nil end
    local identity = JLP:GetModule("CharacterIdentity")
    local canonical = identity and identity.ResolveAlias and identity:ResolveAlias(key) or key
    local characters = JLP.DB.account.inventory.characters or {}
    local resolved, legacy = characters[canonical], characters[key]
    -- Older characters can retain a last-known bank under the realm:name key
    -- even after the identity alias map was written. Prefer a complete saved
    -- snapshot over an empty canonical stub without rewriting offline data.
    if type(legacy)=="table" and legacy.bank and legacy.bank.known and
       (type(resolved)~="table" or not (resolved.bank and resolved.bank.known)) then
        return legacy
    end
    return resolved or legacy
end

function Inventory:GetBankSnapshot(key)
    key = key or characterKey()
    local character = self:GetCharacterStore(key)
    if not character then
        local identity = JLP:GetModule("CharacterIdentity")
        local resolved = identity and identity.ResolveAlias and identity:ResolveAlias(key) or key
        local records = JLP.DB and JLP.DB.account and JLP.DB.account.characterIdentity and JLP.DB.account.characterIdentity.records or {}
        local record = records[resolved] or {}
        return { known=false, items={}, slots={}, totalSlots=0, usedSlots=0,
            characterKey=key, characterName=record.name, realm=record.realm }
    end
    local bank = character.bank or {}
    local name = character.meta and character.meta.name or tostring(key):match(":([^:]+)$") or tostring(key)
    local realm = character.meta and character.meta.realm or tostring(key):match("^(.-):") or "UnknownRealm"
    return {
        known = bank.known and true or false,
        items = bank.items or {},
        slots = bank.slots or {},
        totalSlots = tonumber(bank.totalSlots) or #(bank.slots or {}),
        usedSlots = tonumber(bank.usedSlots) or countMapItems(bank.items),
        freeSlots = tonumber(bank.freeSlots),
        baseSlots = tonumber(bank.baseSlots),
        bankBagSlots = tonumber(bank.bankBagSlots),
        purchasedBankBags = tonumber(bank.purchasedBankBags),
        purchasedBankBagsKnown = bank.purchasedBankBagsKnown and true or false,
        purchasedBankBagsSource = bank.purchasedBankBagsSource,
        containerModel = bank.containerModel,
        baseContainerID = bank.baseContainerID,
        containerDetails = bank.containerDetails or {},
        updatedAt = bank.updatedAt,
        characterKey = key,
        characterName = name,
        realm = realm,
    }
end

-- Account-scoped Bank navigation. This is NOT live/offline bank access: an
-- offline bank has values only after that character opened its bank once.
-- Include known characters without bank snapshots so the missing capture is
-- discoverable rather than silently omitting their submenu.
function Inventory:GetBankNavigationCharacters()
    local current = self:GetCurrentCharacterIdentity()
    local account = JLP.DB and JLP.DB.account or {}
    local inventory = account.inventory or {}
    local characters = inventory.characters or {}
    local identities = account.characterIdentity or {}
    local aliases, records = identities.aliases or {}, identities.records or {}
    local entries = {}
    local function canonical(key)
        return tostring(aliases[key] or key)
    end
    local currentKeys = {
        [tostring(current.key)]=true,
        [tostring(current.legacyKey)]=true,
    }
    local function consider(key, meta, bank)
        if type(key)~="string" or key=="" then return end
        local identity = canonical(key)
        if currentKeys[key] or currentKeys[identity] or identity==current.key then return end
        meta = type(meta)=="table" and meta or {}
        local record = type(records[identity])=="table" and records[identity] or {}
        local realm = meta.realm or record.realm or key:match("^(.-):")
        local name = meta.name or record.name or key:match("^[^:]+:([^:]+)$")
        if not name or not realm or name=="" or realm=="" or
           name=="UnknownCharacter" or realm=="UnknownRealm" then return end
        local known = type(bank)=="table" and bank.known and true or false
        local previous = entries[identity]
        if not previous or (known and not previous.bankKnown) then
            entries[identity] = {
                key=key, identityKey=identity, name=name, realm=realm,
                bankKnown=known,
                updatedAt=type(bank)=="table" and bank.updatedAt or nil,
            }
        end
    end
    for key, character in pairs(characters) do
        if type(character)=="table" then
            consider(key, character.meta, character.bank)
        end
    end
    -- A previously logged-in character may have an identity record even when
    -- its inventory store was not populated on a particular client version.
    for key, record in pairs(records) do consider(key, record, nil) end
    local out = {}
    for _, entry in pairs(entries) do
        entry.sameRealm = string.lower(tostring(entry.realm)):gsub("[%s%-']", "") ==
            string.lower(tostring(current.realm)):gsub("[%s%-']", "")
        entry.label = entry.name .. (entry.sameRealm and "" or (" - " .. entry.realm))
        entry.freshness = self:GetSnapshotFreshness(entry.updatedAt, false)
        out[#out+1] = entry
    end
    table.sort(out, function(a,b)
        if a.sameRealm ~= b.sameRealm then return a.sameRealm end
        local left,right = string.lower(a.label),string.lower(b.label)
        if left~=right then return left<right end
        return a.identityKey<b.identityKey
    end)
    return out
end

-- Legacy helper remains same-realm for acquisition consumers; the Bank sidebar
-- intentionally uses the account-wide method above.
function Inventory:GetKnownBankCharactersSameRealm()
    local out={}
    for _, row in ipairs(self:GetBankNavigationCharacters()) do
        if row.sameRealm then out[#out+1]=row end
    end
    return out
end

function Inventory:GetBagCount(itemID)
    itemID = tonumber(itemID)
    if not itemID then return 0 end
    local count, ok = apiCount(itemID, false)
    if ok then
        observeItem(itemID)
        return math.max(0, count or 0), true, "CLIENT_ITEM_COUNT_API"
    end

    -- A previous-session bags snapshot is advisory, never evidence of items
    -- currently carried. Prefer a fresh container observation over SavedVariables
    -- when the direct client count API is temporarily unavailable. A failed
    -- scan leaves the old observation intact, but grants no immediate stock.
    local character = getCharacterStore()
    local items, readable = scanContainers(bagIDs())
    if readable and character then
        character.bags.items = items
        character.bags.known = true
        character.bags.updatedAt = now()
    end
    if not readable then return 0, false, "BAGS_UNKNOWN" end
    return math.max(0, tonumber(items[itemID]) or 0), true, "CONTAINER_SCAN"
end

function Inventory:GetBankCount(itemID, knownBagCount, knownBagObservation)
    itemID = tonumber(itemID)
    if not itemID then return 0, false end

    local character = getCharacterStore()
    local bank = character and character.bank
    local cached = bank and bank.known and tonumber(bank.items and bank.items[itemID]) or nil
    if bank and bank.known then
        -- A captured ordinary-bank snapshot is complete: a missing sparse-map
        -- row means zero. This avoids a generic include-bank API call for every
        -- absent material and prevents reagent/special storage from leaking into
        -- the visible character-bank count while the Bank is closed.
        local value = math.max(0, cached or 0)
        if value > 0 then observeItem(itemID) end
        return value, true, "SAVED_ORDINARY_BANK_SNAPSHOT"
    end

    -- Generic include-bank counts are only a bootstrap fallback before this
    -- character has ever produced an authoritative ordinary-bank snapshot.
    -- Reuse the caller's already-resolved bag count so GetOwned() never performs
    -- the bag API twice.
    local bagCount, bagObserved
    if knownBagObservation == true then
        -- Only a valid, observed bag count may be subtracted from a generic
        -- inclusive item count; an invalid caller count grants no authority.
        bagCount, bagObserved = validCount(knownBagCount), validCount(knownBagCount) ~= nil
    elseif knownBagObservation == false then
        bagCount, bagObserved = 0, false
    else
        bagCount, bagObserved = self:GetBagCount(itemID)
    end
    if not bagObserved then return 0, false, "BANK_UNKNOWN_BAGS_UNOBSERVED" end
    local total, totalKnown = apiCount(itemID, true)
    -- An inclusive total smaller than the observed bags is contradictory,
    -- not proof of a known-empty bank. Do not persist either observation.
    if totalKnown and total < bagCount then
        return 0, false, "BANK_COUNT_CONFLICT"
    end
    local bankCount = totalKnown and math.max(0, total - bagCount) or 0
    if bankCount > 0 then observeItem(itemID) end
    return bankCount, totalKnown or (bank and bank.known) or false,
        totalKnown and "GENERIC_INCLUDE_BANK_API" or "BANK_UNKNOWN"
end

function Inventory:GetSnapshotFreshness(updatedAt, isLive)
    if isLive then return "LIVE" end
    local stamp = tonumber(updatedAt)
    local current = tonumber(now())
    if not stamp or not current then return "UNKNOWN" end
    local age = math.max(0, current - stamp)
    if age <= 86400 then return "RECENT" end
    return "STALE"
end

function Inventory:GetAltBankAvailability(itemID, options)
    itemID = tonumber(itemID)
    if not itemID then return {} end
    options = type(options)=="table" and options or {}
    local current = self:GetCurrentCharacterIdentity()
    local characters = JLP.DB and JLP.DB.account and JLP.DB.account.inventory and JLP.DB.account.inventory.characters or {}
    local out = {}
    for key, character in pairs(characters) do
        if key ~= current.key and type(character)=="table" then
            local meta = character.meta or {}
            local realm = meta.realm or tostring(key):match("^(.-):")
            if options.sameRealm ~= true or realm == current.realm then
                local bank = character.bank or {}
                local count = bank.known and math.max(0, tonumber(bank.items and bank.items[itemID]) or 0) or 0
                if count > 0 or options.includeZero == true then
                    out[#out+1] = {
                        characterKey = key,
                        name = meta.name or tostring(key):match(":([^:]+)$") or key,
                        realm = realm,
                        itemID = itemID,
                        count = count,
                        bankKnown = bank.known and true or false,
                        updatedAt = bank.updatedAt,
                        freshness = self:GetSnapshotFreshness(bank.updatedAt, false),
                        currentAccessible = false,
                        requiresTransfer = count > 0,
                    }
                end
            end
        end
    end
    table.sort(out,function(a,b)
        if (tonumber(a.count) or 0) ~= (tonumber(b.count) or 0) then return (tonumber(a.count) or 0) > (tonumber(b.count) or 0) end
        return string.lower(tostring(a.name or "")) < string.lower(tostring(b.name or ""))
    end)
    return out
end

function Inventory:GetAccountAvailability(itemID)
    local current = self:GetOwned(itemID)
    local alts = self:GetAltBankAvailability(itemID,{sameRealm=true})
    local altTotal = 0
    for _, row in ipairs(alts) do altTotal = altTotal + (tonumber(row.count) or 0) end
    return {
        itemID = tonumber(itemID),
        currentBags = tonumber(current.bags) or 0,
        currentBank = tonumber(current.bank) or 0,
        currentAccessibleTotal = tonumber(current.total) or 0,
        altBankTotal = altTotal,
        accountKnownTotal = (tonumber(current.total) or 0) + altTotal,
        alts = alts,
        immediateCraftAccessible = tonumber(current.bags) or 0,
        altBankCountsForReadiness = false,
    }
end

function Inventory:GetOwned(itemID)
    local bags, bagKnown, bagEvidence = self:GetBagCount(itemID)
    local bank, bankKnown, bankEvidence = self:GetBankCount(itemID, bags, bagKnown)
    local character = getCharacterStore() or {}
    return {
        itemID = tonumber(itemID),
        bags = bags,
        bank = bank,
        total = bags + bank,
        bagKnown = bagKnown==true,
        bagEvidence = bagEvidence,
        -- Historical observation for reference only, not immediate readiness.
        savedBagsAdvisory = not bagKnown and character.bags and
            character.bags.known and math.max(0, tonumber(character.bags.items and
            character.bags.items[tonumber(itemID)]) or 0) or nil,
        bankKnown = bankKnown and true or false,
        bankEvidence = bankEvidence,
        bankOpenedAt = self.bankOpen and self.bankOpenedAt or nil,
        bagCacheUpdatedAt = character.bags and character.bags.updatedAt or nil,
        bankCacheUpdatedAt = character.bank and character.bank.updatedAt or nil,
    }
end

function Inventory:GetItemCount(itemID)
    return self:GetOwned(itemID).total
end

function Inventory:GetCacheSummary()
    local character = getCharacterStore() or {}
    local bags = character.bags or {}
    local bank = character.bank or {}
    return string.format(
        "Persistent inventory: bags %s (%d item types) - bank %s (%d item types)",
        bags.known and "known" or "unknown",
        countMapItems(bags.items),
        bank.known and "known" or "unknown",
        countMapItems(bank.items)
    )
end

JLP:RegisterModule("Inventory", Inventory)
