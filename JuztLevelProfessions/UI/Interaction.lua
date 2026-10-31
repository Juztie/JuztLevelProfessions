local _, JLP = ...

local Interaction = {}

local function shown(frame)
    if not frame then return false end
    if frame.IsShown then
        local ok, value = pcall(frame.IsShown, frame)
        if ok then return value and true or false end
    end
    return true
end

local function objectName(obj)
    if not obj or not obj.GetName then return "" end
    local ok, value = pcall(obj.GetName, obj)
    return ok and string.lower(tostring(value or "")) or ""
end

local function isEditBox(obj)
    if not obj then return false end
    if obj.GetObjectType then
        local ok, value = pcall(obj.GetObjectType, obj)
        if ok and value == "EditBox" then return true end
    end
    return type(obj.SetText) == "function" and type(obj.GetText) == "function"
end

local function findNamedEditBox(root, depth, visited)
    if not root or depth < 0 then return nil end
    visited = visited or {}
    if visited[root] then return nil end
    visited[root] = true
    if isEditBox(root) then
        local name = objectName(root)
        if name:find("search",1,true) or name:find("browse",1,true) or name:find("name",1,true) then return root end
    end
    if not root.GetChildren then return nil end
    local ok, children = pcall(function() return {root:GetChildren()} end)
    if not ok then return nil end
    for _, child in ipairs(children or {}) do
        local found = findNamedEditBox(child, depth - 1, visited)
        if found then return found end
    end
    return nil
end

local function auctionRoot()
    local roots = { _G.AuctionHouseFrame, _G.AuctionFrame, _G.AuctionFrameBrowse }
    for _, root in pairs(roots) do if shown(root) then return root end end
    return nil
end

local function auctionSearchBox()
    local ah = _G.AuctionHouseFrame
    local candidates = {
        ah and ah.SearchBar and ah.SearchBar.SearchBox,
        ah and ah.BrowseResultsFrame and ah.BrowseResultsFrame.SearchBar and ah.BrowseResultsFrame.SearchBar.SearchBox,
        _G.AuctionFrameBrowse and _G.AuctionFrameBrowse.SearchBox,
        _G.AuctionFrameBrowse and _G.AuctionFrameBrowse.Name,
        _G.BrowseName,
        _G.AuctionFrameBrowse_SearchBox,
    }
    for _, box in pairs(candidates) do if isEditBox(box) then return box end end
    local root = auctionRoot()
    return root and findNamedEditBox(root, 6, {}) or nil
end

-- A client link must identify the item represented by the UI row. Cached
-- names are not a substitute for item identity; never synthesize links for
-- metadata gaps or trust a different item's hyperlink from a name search.
local function validItemLink(link, expectedID)
    if type(link)~="string" then return false end
    local id=link:match("|Hitem:(%d+)") or link:match("^item:(%d+)")
    if not id then return false end
    expectedID=tonumber(expectedID)
    return expectedID~=nil and expectedID>0 and expectedID==math.floor(expectedID)
        and tonumber(id)==expectedID
end

local function itemInfo(query, fallbackName)
    local cache = JLP.GetModule and JLP:GetModule("KnowledgeCache") or nil
    local cached = cache and cache.ResolveItem and cache:ResolveItem(tonumber(query), fallbackName or (type(query)=="string" and query or nil)) or nil
    if cached and (cached.name or cached.link) then return cached.name, cached.link end
    if query == nil or type(GetItemInfo) ~= "function" then return fallbackName, nil end
    local ok, name, link = pcall(GetItemInfo, query)
    if not ok then return fallbackName, nil end
    return name or fallbackName, link
end

function Interaction:ShowItem(owner, itemID, name)
    if not owner or not GameTooltip then return false end
    if GameTooltip.SetOwner then GameTooltip:SetOwner(owner, JLP.UILayout and JLP.UILayout:TooltipAnchorFor(owner,UIParent,320) or "ANCHOR_CURSOR") end
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end

    local resolvedName, link = itemInfo(tonumber(itemID) or name, name)
    if link and not validItemLink(link,itemID) then
        -- The returned cache record may have been populated by a different
        -- item-name lookup. Neither its link nor its name is identity proof.
        resolvedName=name or (tonumber(itemID) and ("Item "..tostring(itemID))) or "Item"
        link=nil
    end
    local shown = false
    if validItemLink(link,itemID) and GameTooltip.SetHyperlink then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    end

    if not shown and GameTooltip.SetText then
        GameTooltip:SetText(resolvedName or name or (itemID and ("Item " .. tostring(itemID))) or "Item")
        if itemID and GameTooltip.AddLine then
            GameTooltip:AddLine("Item ID: " .. tostring(itemID), 0.55, 0.72, 0.82)
        end
        shown = true
    end

    if shown and self:IsAuctionHouseOpen() and GameTooltip.AddLine then
        GameTooltip:AddLine("Shift-click: add to Auction House search", 0.00, 0.80, 1.00)
    end
    if shown and GameTooltip.Show then GameTooltip:Show() end
    return shown
end


local function appendAuctionHint(self)
    if self:IsAuctionHouseOpen() and GameTooltip and GameTooltip.AddLine then
        GameTooltip:AddLine("Shift-click: add to Auction House search", 0.00, 0.80, 1.00)
    end
end

function Interaction:ShowItemLocation(owner, row)
    if not owner or not row or not GameTooltip then return false end
    if GameTooltip.SetOwner then GameTooltip:SetOwner(owner, JLP.UILayout and JLP.UILayout:TooltipAnchorFor(owner,UIParent,320) or "ANCHOR_CURSOR") end
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end

    local shown = false
    local location = row.location
    local expectedID=tonumber(row.itemID)
    local function sameBagItem(bag,slot)
        if not expectedID or expectedID<=0 or expectedID~=math.floor(expectedID) then return false end
        local getter=C_Container and C_Container.GetContainerItemID or _G.GetContainerItemID
        if type(getter)~="function" then return false end
        local ok,actual=pcall(getter,bag,slot)
        return ok and tonumber(actual)==expectedID
    end
    local function sameEquipmentItem(slot)
        if not expectedID or expectedID<=0 or expectedID~=math.floor(expectedID) or
            type(GetInventoryItemID)~="function" then return false end
        local ok,actual=pcall(GetInventoryItemID,"player",slot)
        return ok and tonumber(actual)==expectedID
    end
    if location then
        if location.IsBagAndSlot and location.GetBagAndSlot and GameTooltip.SetBagItem then
            local okKind, isBag = pcall(location.IsBagAndSlot, location)
            if okKind and isBag then
                local okPos, bag, slot = pcall(location.GetBagAndSlot, location)
                if okPos and bag ~= nil and slot ~= nil and sameBagItem(bag,slot) then
                    shown = pcall(GameTooltip.SetBagItem, GameTooltip, bag, slot)
                end
            end
        end
        if not shown and location.IsEquipmentSlot and location.GetEquipmentSlot and GameTooltip.SetInventoryItem then
            local okKind, isEquipment = pcall(location.IsEquipmentSlot, location)
            if okKind and isEquipment then
                local okPos, slot = pcall(location.GetEquipmentSlot, location)
                if okPos and slot ~= nil and sameEquipmentItem(slot) then
                    shown = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", slot)
                end
            end
        end
    end

    -- Preserve the exact random suffix/enchant/item instance whenever the client supplied a link.
    if not shown and validItemLink(row.link,row.itemID) and GameTooltip.SetHyperlink then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, row.link)
    end

    if not shown then
        return self:ShowItem(owner, row.itemID, row.name)
    end

    appendAuctionHint(self)
    if GameTooltip.Show then GameTooltip:Show() end
    return true
end

function Interaction:ShowProfession(owner, key, profession)
    if not owner or not GameTooltip then return false end
    local api = JLP.GetModule and JLP:GetModule("ProfessionAPI") or nil
    local reg = JLP.GetModule and JLP:GetModule("ProfessionRegistry") or nil
    local normalized=reg and reg:NormalizeKey(key)
    local ownership=normalized and api and api.GetOwnership and api:GetOwnership(normalized)
    local current=ownership and ownership.owned==true and profession and profession.key==normalized and profession or nil
    local label = current and current.name or (reg and reg:GetDisplayNameOrKey(key)) or "Profession"
    if GameTooltip.SetOwner then GameTooltip:SetOwner(owner, JLP.UILayout and JLP.UILayout:TooltipAnchorFor(owner,UIParent,320) or "ANCHOR_CURSOR") end
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    if GameTooltip.SetText then GameTooltip:SetText(label) end
    if GameTooltip.AddLine then
        local historical=current and (current.cached==true or current.presentationState=="historical") or
            ownership and ownership.state=="OWNED_CURRENT_UNKNOWN"
        if historical then GameTooltip:AddLine("Historical observation; current skill and slot are not confirmed.",1,.75,.2) end
        if current and current.presentationConflict then GameTooltip:AddLine("Conflicting profession evidence; verify current identity.",1,.75,.2)
        elseif ownership and ownership.owned==true then GameTooltip:AddLine("Click to open JuztLevel Guide / Secondary", 0.00, 0.80, 1.00)
        else GameTooltip:AddLine("Profession ownership not confirmed.",1,.75,.2) end
    end
    if GameTooltip.Show then GameTooltip:Show() end
    return true
end

-- The active owner can be tested without overwriting Blizzard's tooltip.
-- HideTooltip(nil) preserves legacy explicit-close behaviour, while supplying
-- a frame only hides the tooltip currently owned by that frame.
function Interaction:HideTooltip(owner)
    if not GameTooltip or not GameTooltip.Hide then return false end
    if owner and GameTooltip.GetOwner and GameTooltip:GetOwner()~=owner then return false end
    GameTooltip:Hide()
    return true
end
function Interaction:HideTooltipTree(root)
    if not root or not GameTooltip or not GameTooltip.GetOwner then return false end
    local owner=GameTooltip:GetOwner()
    local depth=0
    while owner and depth<48 do
        if owner==root then return self:HideTooltip(GameTooltip:GetOwner()) end
        owner=owner.GetParent and owner:GetParent() or nil
        depth=depth+1
    end
    return false
end

function Interaction:OpenProfession(key, profession)
    local reg=JLP.GetModule and JLP:GetModule("ProfessionRegistry")
    if not reg then return false,"Profession registry is unavailable." end
    local normalized=reg:NormalizeKey(key);local def=normalized and reg:Get(normalized)
    if not def or (def.category~="PRIMARY" and def.category~="SECONDARY") then return false,"Unknown profession key." end
    local api = JLP.GetModule and JLP:GetModule("ProfessionAPI") or nil
    local ownership=api and api.GetOwnership and api:GetOwnership(normalized)
    if not (ownership and ownership.owned==true) then return false,ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN" end
    local window=JLP.MainWindow
    if not window or type(window.Create)~="function" or
        type(window.ShowGuideMode)~="function" or type(window.ShowSecondaryMode)~="function" then
        return false,"JuztLevel MainWindow is unavailable."
    end
    if def.category=="PRIMARY" then
        local workspace=JLP:GetModule("ProfessionWorkspace")
        local resolved=workspace and workspace:ResolveGuideMode(normalized)
        if resolved~=normalized then return false,"PROFESSION_PRESENTATION_UNCONFIRMED" end
        window:ShowGuideMode(normalized)
    else window:ShowSecondaryMode(normalized) end
    -- Both existing views create their frame once. Do not create a second UI
    -- or fall back to a native profession panel when an internal view is absent.
    if window.frame and window.frame.Show then window.frame:Show() end
    return true,"JuztLevel: "..reg:GetDisplayNameOrKey(normalized)
end

function Interaction:IsAuctionHouseOpen()
    return auctionRoot() ~= nil
end

function Interaction:SearchAuctionHouse(itemID, name)
    if not self:IsAuctionHouseOpen() then return false, "Open the Auction House first." end
    local resolvedName = itemInfo(tonumber(itemID) or name, name)
    resolvedName = type(resolvedName) == "string" and resolvedName or name
    if not resolvedName or resolvedName == "" then return false, "Item name is unavailable." end
    local box = auctionSearchBox()
    if not box or type(box.SetText) ~= "function" then return false, "Auction House search field was not found." end
    local ok = pcall(box.SetText, box, resolvedName)
    if not ok then return false, "Auction House search field could not be updated." end
    if box.SetFocus then pcall(box.SetFocus, box) end
    if box.SetCursorPosition then pcall(box.SetCursorPosition, box, string.len(resolvedName)) end
    return true, "Auction House search: " .. tostring(resolvedName)
end

function Interaction:HandleItemClick(itemID, name, button)
    if button ~= "LeftButton" then return false end
    local shifted = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() or false
    if not shifted then return false end
    return self:SearchAuctionHouse(itemID, name)
end

JLP.UIInteraction = Interaction
