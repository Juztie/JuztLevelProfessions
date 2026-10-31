local _, JLP = ...

local IconResolver = {}

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local PROFESSION_FALLBACK = {
    TAILORING = "Interface\\Icons\\Trade_Tailoring",
    ENCHANTING = "Interface\\Icons\\INV_Enchant_Disenchant",
    ALCHEMY = "Interface\\Icons\\Trade_Alchemy",
    BLACKSMITHING = "Interface\\Icons\\Trade_BlackSmithing",
    ENGINEERING = "Interface\\Icons\\Trade_Engineering",
    LEATHERWORKING = "Interface\\Icons\\Trade_LeatherWorking",
    HERBALISM = "Interface\\Icons\\Trade_Herbalism",
    MINING = "Interface\\Icons\\Trade_Mining",
    SKINNING = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    COOKING = "Interface\\Icons\\INV_Misc_Food_15",
    FIRST_AID = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    FISHING = "Interface\\Icons\\Trade_Fishing",
}

local SEMANTIC = {
    skill = "Interface\\Icons\\Ability_Marksmanship",
    target = "Interface\\Icons\\Ability_Hunter_SniperShot",
    estimate = "Interface\\Icons\\INV_Hammer_04",
    recipe = "Interface\\Icons\\INV_Misc_Book_09",
    bag = "Interface\\Icons\\INV_Misc_Bag_10",
    bank = JLP.UITheme:Asset("icons\\bank.tga"),
    live = "Interface\\Icons\\Ability_Rogue_Sprint",
    workspace = "Interface\\Icons\\INV_Misc_Key_03",
    switches = "Interface\\Icons\\Ability_Rogue_FleetFooted",
    info = "Interface\\Icons\\INV_Misc_Note_01",
    trainer = "Interface\\Icons\\INV_Misc_GroupLooking",
    area = "Interface\\Icons\\INV_Misc_Map_01",
    zone = "Interface\\Icons\\INV_Misc_Map02",
    coordinates = "Interface\\Icons\\INV_Misc_Map03",
    process = "Interface\\Icons\\Achievement_General",
    waiting = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    state = "Interface\\Icons\\INV_Misc_Star_01",
    storage = "Interface\\Icons\\INV_Box_01",
    prepare = "Interface\\Icons\\Trade_BlackSmithing",
    total = "Interface\\Icons\\INV_Misc_PocketWatch_02",
    raw = "Interface\\Icons\\INV_Misc_Bag_09",
    auction = "Interface\\Icons\\INV_Hammer_15",
    itemtypes = "Interface\\Icons\\INV_Misc_Note_05",
    cooldown = "Interface\\Icons\\INV_Misc_PocketWatch_02",
    plan = "Interface\\Icons\\INV_Misc_Note_05",
    acquisition = "Interface\\Icons\\INV_Misc_Bag_10",
    route = "Interface\\Icons\\INV_Misc_Map_01",
    scan = "Interface\\Icons\\INV_Hammer_15",
    success = "Interface\\Icons\\Ability_DualWield",

    -- READINESS & WORKSPACE semantics. These are intentionally explicit rather
    -- than falling back to INV_Misc_QuestionMark: every operational row should
    -- communicate its purpose visually even when its live value is unavailable.
    execution = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    next = "Interface\\Icons\\Ability_Hunter_SniperShot",
    batch = "Interface\\Icons\\INV_Misc_Note_05",
    travel = "Interface\\Icons\\INV_Misc_Map_01",
    journey = "Interface\\Icons\\Ability_Mount_RidingHorse",
    confidence = "Interface\\Icons\\Spell_Holy_MindVision",
    navigation = "Interface\\Icons\\INV_Misc_Map02",
    marker = "Interface\\Icons\\Ability_Hunter_SniperShot",
    handoff = "Interface\\Icons\\Ability_Rogue_FleetFooted",
    recovery = "Interface\\Icons\\Spell_Holy_Renew",
    txrecovery = "Interface\\Icons\\Spell_Holy_Resurrection",
    efficiency = "Interface\\Icons\\INV_Hammer_04",
}

local function validItemIcon(value)
    if value == nil or value == false or value == 0 or value == "" then return nil end
    return value
end

local function itemIDFromLink(link)
    return type(link)=="string" and tonumber(link:match("item:(%d+)")) or nil
end

local function tryItemInfo(query)
    if query == nil then return nil end
    -- Forever is a modern-API client. Prefer C_Item.GetItemInfo; the old global
    -- GetItemInfo can be absent even when the namespaced API is available.
    if type(C_Item)=="table" and type(C_Item.GetItemInfo)=="function" then
        local ok, _, _, _, _, _, _, _, _, _, texture = pcall(C_Item.GetItemInfo, query)
        texture=ok and validItemIcon(texture) or nil
        if texture then return texture end
    end
    if type(GetItemInfo)=="function" then
        local ok, _, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, query)
        texture=ok and validItemIcon(texture) or nil
        if texture then return texture end
    end
    return nil
end

local function tryItemIcon(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        local ok, texture = pcall(C_Item.GetItemIconByID, itemID)
        texture=ok and validItemIcon(texture) or nil
        if texture then return texture end
    end
    if type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, texture = pcall(C_Item.GetItemInfoInstant, itemID)
        texture=ok and validItemIcon(texture) or nil
        if texture then return texture end
    end
    if type(GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, texture = pcall(GetItemInfoInstant, itemID)
        texture=ok and validItemIcon(texture) or nil
        if texture then return texture end
    end
    if type(GetItemIcon) == "function" then
        local ok, texture = pcall(GetItemIcon, itemID)
        texture=ok and validItemIcon(texture) or nil
        if texture then return texture end
    end
    return tryItemInfo(itemID)
end

local function itemObjectForGUID(guid)
    if not guid or type(Item)~="table" or type(Item.CreateFromItemGUID)~="function" then return nil end
    local candidates={}
    local ok,value=pcall(function() return Item:CreateFromItemGUID(guid) end)
    if ok and value then candidates[#candidates+1]=value end
    local okDot,valueDot=pcall(Item.CreateFromItemGUID,guid)
    if okDot and valueDot and valueDot~=value then candidates[#candidates+1]=valueDot end
    for _,candidate in ipairs(candidates) do
        if type(candidate)=="table" then
            local id
            if type(candidate.GetItemID)=="function" then
                local okID,valueID=pcall(candidate.GetItemID,candidate)
                if okID then id=tonumber(valueID) end
            end
            if id then return candidate,id end
        end
    end
    return candidates[1],nil
end

local function requestItemData(itemID)
    itemID=tonumber(itemID)
    if not itemID or type(C_Item)~="table" or type(C_Item.RequestLoadItemDataByID)~="function" then return false end
    return pcall(C_Item.RequestLoadItemDataByID,itemID) and true or false
end

-- Resolve an exact enchant-target row. GetEnchantItems() gives JuztLevel a GUID;
-- different Forever builds expose the associated texture through different item
-- surfaces. This resolver deliberately derives identity first, then tries every
-- modern item path before falling back to the persistent knowledge cache.
function IconResolver:GetEnchantTarget(target, requestLoad)
    target=target or {}
    local icon=validItemIcon(target.icon)
    if icon then return icon end

    local guid=target.guid
    local location=target.location
    local link=target.link
    local itemID=tonumber(target.itemID) or itemIDFromLink(link)
    local itemObject, objectID=itemObjectForGUID(guid)
    itemID=itemID or objectID

    if not location and itemObject and type(itemObject.GetItemLocation)=="function" then
        local ok,value=pcall(itemObject.GetItemLocation,itemObject)
        if ok then location=value end
    end
    if not location and guid and type(C_Item)=="table" and type(C_Item.GetItemLocation)=="function" then
        local ok,value=pcall(C_Item.GetItemLocation,guid)
        if ok then location=value end
    end
    if not itemID and location and type(C_Item)=="table" and type(C_Item.GetItemID)=="function" then
        local ok,value=pcall(C_Item.GetItemID,location)
        if ok then itemID=tonumber(value) end
    end
    if not itemID and guid and type(C_Item)=="table" and type(C_Item.GetItemIDByGUID)=="function" then
        local ok,value=pcall(C_Item.GetItemIDByGUID,guid)
        if ok then itemID=tonumber(value) end
    end
    if not itemID and link and type(C_Item)=="table" and type(C_Item.GetItemIDForItemInfo)=="function" then
        local ok,value=pcall(C_Item.GetItemIDForItemInfo,link)
        if ok then itemID=tonumber(value) end
    end

    if location and type(C_Item)=="table" and type(C_Item.GetItemIcon)=="function" then
        local ok,value=pcall(C_Item.GetItemIcon,location)
        icon=ok and validItemIcon(value) or nil
        if icon then return icon end
    end
    if guid and type(C_Item)=="table" and type(C_Item.GetItemIconByGUID)=="function" then
        local ok,value=pcall(C_Item.GetItemIconByGUID,guid)
        icon=ok and validItemIcon(value) or nil
        if icon then return icon end
    end
    if itemObject and type(itemObject.GetItemIcon)=="function" then
        local ok,value=pcall(itemObject.GetItemIcon,itemObject)
        icon=ok and validItemIcon(value) or nil
        if icon then return icon end
    end
    icon=tryItemIcon(itemID)
    if icon then return icon end

    local instantQuery=itemID or link or guid
    if instantQuery and type(C_Item)=="table" and type(C_Item.GetItemInfoInstant)=="function" then
        local ok,instantID,_,_,_,instantIcon=pcall(C_Item.GetItemInfoInstant,instantQuery)
        if ok then
            itemID=itemID or tonumber(instantID)
            icon=validItemIcon(instantIcon)
            if icon then return icon end
        end
    end
    if link then
        icon=tryItemInfo(link)
        if icon then return icon end
    end
    if itemID then
        icon=tryItemInfo(itemID)
        if icon then return icon end
    end

    local cache = JLP.GetModule and JLP:GetModule("KnowledgeCache") or nil
    local cached = cache and cache.ResolveItem and cache:ResolveItem(itemID, target.name) or nil
    icon=validItemIcon(cached and cached.icon)
    if icon then return icon end

    if requestLoad~=false and itemID then requestItemData(itemID) end
    return QUESTION
end

local function recipeCandidateID(recipe)
    local data = JLP.data and JLP.data.tailoringDisenchant
    for _, row in ipairs((data and data.candidates) or {}) do
        if row.recipe == recipe then return row.itemID end
    end
    return nil
end

function IconResolver:GetItem(itemID, name)
    local cache = JLP.GetModule and JLP:GetModule("KnowledgeCache") or nil
    local cached = cache and cache.ResolveItem and cache:ResolveItem(itemID, name) or nil
    local icon=validItemIcon(cached and cached.icon) or tryItemIcon(itemID) or tryItemInfo(name)
    if not icon and tonumber(itemID) then requestItemData(itemID) end
    return icon or QUESTION
end

function IconResolver:GetProfession(key, profession)
    if profession and profession.icon then return profession.icon end
    local api = JLP.GetModule and JLP:GetModule("ProfessionAPI") or nil
    local current = api and api:Get(key) or nil
    return (current and current.icon) or PROFESSION_FALLBACK[key] or QUESTION
end

function IconResolver:GetRecipe(recipe, key)
    local candidate = recipeCandidateID(recipe)
    local cache = JLP.GetModule and JLP:GetModule("KnowledgeCache") or nil
    local cached = cache and cache.ResolveItem and cache:ResolveItem(candidate, recipe) or nil
    return validItemIcon(cached and cached.icon) or tryItemIcon(candidate) or tryItemInfo(recipe) or self:GetProfession(key)
end

function IconResolver:GetSemantic(key)
    -- Semantic/status rows must never render as the black/red question-mark
    -- placeholder used for unresolved item identities. Unknown semantic keys
    -- degrade to the neutral information icon instead.
    return SEMANTIC[key] or SEMANTIC.info
end

function IconResolver:GetFallback()
    return QUESTION
end

JLP.UIIconResolver = IconResolver
