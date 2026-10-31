local _, JLP = ...
local Page={name="Bank", selectedCharacterKey=nil, category="all", sortMode="type", searchText=""}

-- Transient UI-only item browsing. A material reference never authorizes
-- retrieval from another character or a bank scan/withdrawal.
local function validMaterialID(value)
    return type(value)=="number" and value==value and value>0 and
        value<2147483648 and value%1==0
end
function Page:FocusMaterialReference()
    local main=JLP.MainWindow
    local receipt=main and main.GetMaterialReference and main:GetMaterialReference("Bank")
    if not receipt or receipt.readOnly~=true or receipt.nativeDispatchAllowed~=false or
        not validMaterialID(receipt.materialID) then
        self.materialFocusID=nil; self.materialFocusReceipt=nil
        return false,"MATERIAL_REFERENCE_UNAVAILABLE"
    end
    if self.materialFocusID==receipt.materialID and self.materialFocusReceipt==receipt then
        self.materialFocusID=nil; self.materialFocusReceipt=nil
    else
        self.materialFocusID=receipt.materialID;self.materialFocusReceipt=receipt
    end
    self:Refresh()
    local grid=self.frame and self.frame.storage and self.frame.storage.grid
    local layout=JLP.UILayout
    if grid and layout and layout.ReturnToScrollOrigin then layout:ReturnToScrollOrigin(grid) end
    return true
end

local CATEGORY_DEFS={
    {key="all",label="All Items",icon="Interface\\Icons\\INV_Misc_Bag_10"},
    {key="crafting",label="Crafting Materials",icon="Interface\\Icons\\Trade_BlackSmithing"},
    {key="cloth",label="Cloth & Thread",icon="Interface\\Icons\\INV_Fabric_Linen_01"},
    {key="herbs",label="Herbs & Reagents",icon="Interface\\Icons\\INV_Misc_Herb_07"},
    {key="ores",label="Ores & Minerals",icon="Interface\\Icons\\INV_Ore_Copper_01"},
    {key="leather",label="Leather & Hides",icon="Interface\\Icons\\INV_Misc_LeatherScrap_03"},
    {key="food",label="Food & Consumables",icon="Interface\\Icons\\INV_Misc_Food_15"},
    {key="scrolls",label="Scrolls & Books",icon="Interface\\Icons\\INV_Scroll_03"},
    {key="misc",label="Miscellaneous",icon="Interface\\Icons\\INV_Misc_Bag_09"},
}
local SORTS={{key="type",label="Type"},{key="name",label="Name"},{key="quantity",label="Quantity"}}

-- Inventory can be absent or incompletely registered during bootstrap. Treat
-- every read as advisory and never infer a real zero from a missing service,
-- method, character identity, or malformed saved snapshot.
local function serviceCall(service, method, ...)
    if type(service)~="table" or type(service[method])~="function" then return nil,false end
    local ok,value=pcall(service[method],service,...)
    if not ok then return nil,false end
    return value,true
end

local function validKey(key)
    if type(key)=="string" and key~="" then return key end
    return nil
end

-- A saved bank snapshot is advisory and may be read for other characters,
-- but its declared owner must agree with the requested character. Legitimate
-- legacy-to-stable aliases are resolved ONLY through CharacterIdentity.
local function sameSnapshotOwner(requested, owner)
    if requested==owner then return true end
    if not validKey(requested) or not validKey(owner) then return false end
    local identity=JLP:GetModule("CharacterIdentity")
    if type(identity)~="table" or type(identity.ResolveAlias)~="function" then return false end
    local requestedCanonical,requestedOK=serviceCall(identity,"ResolveAlias",requested)
    local ownerCanonical,ownerOK=serviceCall(identity,"ResolveAlias",owner)
    return requestedOK and ownerOK and validKey(requestedCanonical)~=nil and
        requestedCanonical==ownerCanonical
end

local function qualifiedSnapshot(raw, requestedKey)
    if type(raw)~="table" then return {known=false,slots={},items={}} end
    -- Inventory:GetBankSnapshot stamps the requested key even for legacy
    -- realm:name records without an embedded owner. An ownerless *service*
    -- response has no safe provenance, so fail closed rather than displaying
    -- another character's slots, identity or freshness in the selected scope.
    -- Canonical/legacy aliases remain valid through CharacterIdentity only.
    if not validKey(raw.characterKey) or not sameSnapshotOwner(requestedKey,raw.characterKey) then
        return {known=false,slots={},items={},characterKey=requestedKey}
    end
    local snapshot={known=false,slots={},items={}}
    for _,field in ipairs({"characterKey","characterName","realm","updatedAt"}) do
        if type(raw[field])=="string" or (field=="updatedAt" and type(raw[field])=="number") then
            snapshot[field]=raw[field]
        end
    end
    if raw.known~=true or type(raw.slots)~="table" or type(raw.items)~="table" then return snapshot end
    local total,used=raw.totalSlots,raw.usedSlots
    if type(total)~="number" or type(used)~="number" or
        total~=total or used~=used or total==math.huge or used==math.huge or
        total<0 or used<0 or total%1~=0 or used%1~=0 or used>total then return snapshot end
    -- Snapshot rows are advisory but the summary must not interpret a missing
    -- occupied slot's quantity as a verified zero. Validate before marking
    -- the complete bank snapshot known; no SavedVariables data is modified.
    if total>10000 or #raw.slots>10000 then return snapshot end
    local occupiedEvidence=false
    -- A bank snapshot can be sparse (including legacy slot keys). Iterate
    -- actual entries, never infer occupied rows from a declared usedSlots.
    for _,slot in pairs(raw.slots) do
        if type(slot)~="table" then return snapshot end
        if slot.itemID~=nil then
            local id,count=tonumber(slot.itemID),slot.count
            if not id or id<=0 or id~=math.floor(id) or id>=2147483648 or
               type(count)~="number" or count~=count or count==math.huge or
               count==-math.huge or count<=0 or count~=math.floor(count) then
                return snapshot
            end
            occupiedEvidence=true
        end
    end
    for itemID,count in pairs(raw.items) do
        local id=tonumber(itemID)
        if not id or id<=0 or id~=math.floor(id) or id>=2147483648 or
           type(count)~="number" or count~=count or count==math.huge or
           count==-math.huge or count<0 or count~=math.floor(count) then
            return snapshot
        end
        if count>0 then occupiedEvidence=true end
    end
    -- A populated summary without even one qualified occupied record has
    -- contradictory source provenance. An actually empty bank (used=0) and
    -- old/sparse banks with positive items[] or slots[] remain supported.
    if used>0 and not occupiedEvidence then return snapshot end
    snapshot.known=true
    snapshot.totalSlots=total
    snapshot.usedSlots=used
    snapshot.freeSlots=raw.freeSlots
    snapshot.slots=raw.slots
    snapshot.items=raw.items
    return snapshot
end

local function lower(value) return string.lower(tostring(value or "")) end
local function contains(text,word) return text:find(word,1,true)~=nil end

local function itemMeta(itemID)
    local cache=JLP:GetModule("KnowledgeCache")
    local value,ok=serviceCall(cache,"GetItem",itemID)
    return ok and type(value)=="table" and value or nil
end

local function categoryFor(meta,name,itemID)
    local catalog=JLP:GetModule("MaterialCatalog")
    local category=serviceCall(catalog,"GetCategory",itemID or meta and meta.itemID,meta)
    if type(category)~="string" then category=nil end
    if category then return category end
    -- Locale-dependent words are only the final fallback for unindexed items.
    local text=lower((meta and meta.name or name or "").." "..(meta and meta.itemType or "").." "..(meta and meta.itemSubType or ""))
    if contains(text,"cloth") or contains(text,"thread") or contains(text,"linen") or contains(text,"wool") or contains(text,"silk") or contains(text,"mageweave") or contains(text,"runecloth") then return "cloth" end
    if contains(text,"herb") or contains(text,"flower") or contains(text,"bloom") or contains(text,"root") or contains(text,"leaf") then return "herbs" end
    if contains(text,"ore") or contains(text,"mineral") or contains(text,"stone") or contains(text,"bar") or contains(text,"gem") or contains(text,"crystal") then return "ores" end
    if contains(text,"leather") or contains(text,"hide") or contains(text,"scale") then return "leather" end
    if (meta and tonumber(meta.classID)==0) or contains(text,"food") or contains(text,"drink") or contains(text,"potion") or contains(text,"elixir") or contains(text,"consumable") then return "food" end
    if contains(text,"scroll") or contains(text,"book") or contains(text,"tome") or contains(text,"manual") or contains(text,"pattern") or contains(text,"formula") then return "scrolls" end
    if (meta and meta.isCraftingReagent) or (meta and tonumber(meta.classID)==7) or contains(text,"trade goods") or contains(text,"reagent") then return "crafting" end
    return "misc"
end

local function matchesCategory(meta,name,key)
    if key=="all" then return true end
    local primary=categoryFor(meta,name,meta and meta.itemID)
    if key=="crafting" then
        return primary=="crafting" or primary=="cloth" or primary=="herbs" or primary=="ores" or primary=="leather" or (meta and meta.isCraftingReagent) or (meta and tonumber(meta.classID)==7)
    end
    return primary==key
end

local function displaySlots(snapshot)
    local slots={}
    for _,row in ipairs(snapshot.slots or {}) do
        slots[#slots+1]={bagID=row.bagID,slot=row.slot,itemID=tonumber(row.itemID),count=tonumber(row.count) or 0}
    end
    if #slots==0 then
        for itemID,count in pairs(snapshot.items or {}) do
            if (tonumber(count) or 0)>0 then slots[#slots+1]={itemID=tonumber(itemID),count=tonumber(count) or 0} end
        end
        table.sort(slots,function(a,b) return (a.itemID or 0)<(b.itemID or 0) end)
    end
    return slots
end

local function categoryLabel(key)
    for _,row in ipairs(CATEGORY_DEFS) do if row.key==key then return row.label end end
    return "All Items"
end

local function sortLabel(key)
    for _,row in ipairs(SORTS) do if row.key==key then return row.label end end
    return "Type"
end

local function bankRow(parent,label,y)
    local W=JLP.UIWidgets
    local left=W:Label(parent,label,"GameFontHighlight")
    left:SetPoint("TOPLEFT",0,y); left:SetTextColor(JLP.UITheme:Color("muted"))
    local right=W:Label(parent,"0","GameFontHighlight")
    right:SetPoint("TOPRIGHT",0,y); right:SetJustifyH("RIGHT")
    return {label=left,value=right}
end

local function makeCategoryButton(parent,def,y,width)
    local W=JLP.UIWidgets
    local b=CreateFrame("Button",nil,parent); b:SetSize(width,32); b:SetPoint("TOPLEFT",0,y)
    local bg=b:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetTexture("Interface\\Buttons\\WHITE8X8"); bg:SetVertexColor(0.004,0.020,0.034,0.20); b.background=bg
    local icon=b:CreateTexture(nil,"ARTWORK"); icon:SetSize(22,22); icon:SetPoint("LEFT",8,0); icon:SetTexture(def.icon); b.icon=icon
    local label=W:Label(b,def.label,"GameFontHighlight"); label:SetPoint("LEFT",icon,"RIGHT",10,0); label:SetJustifyH("LEFT"); b.label=label
    local count=W:Label(b,"0","GameFontHighlight"); count:SetPoint("RIGHT",-8,0); count:SetJustifyH("RIGHT"); count:SetWidth(26); b.count=count
    label:SetPoint("RIGHT",count,"LEFT",-5,0)
    if label.SetWordWrap then label:SetWordWrap(false) end
    function b:SetActive(active)
        self.__active=active and true or false
        self.background:SetVertexColor(0.02,0.34,0.58,active and 0.72 or 0.20)
        self.label:SetTextColor(JLP.UITheme:Color(active and "text" or "muted"))
        self.count:SetTextColor(JLP.UITheme:Color(active and "text" or "muted"))
        if active then W:Border(self,"cyan",1) else W:Border(self,"sidebar",1) end
    end
    return b
end

local function measureTextWidth(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetText(text or "")
    local width = 0
    if fs.GetStringWidth then
        width = math.ceil(fs:GetStringWidth() or 0)
    else
        width = math.ceil(string.len(tostring(text or "")) * 8)
    end
    if fs.Hide then fs:Hide() end
    return width
end

local function longestLabel(rows)
    local best = ""
    for _, row in ipairs(rows or {}) do
        local label = tostring(row.label or "")
        if #label > #best then best = label end
    end
    return best
end

local function closeDropdown(other)
    if other and other.menu then other.menu:Hide() end
end

local function createDropdown(parent, entries, initialLabel, width)
    local W = JLP.UIWidgets
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 30)

    local bg=b:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(JLP.UITheme:Asset("buttons\\medium_blank.tga"))
    b.background=bg
    W:Border(b,"border",1)

    local label=W:Label(b, initialLabel or "", "GameFontHighlight")
    label:SetPoint("LEFT",12,0)
    label:SetPoint("RIGHT",-12,0)
    label:SetJustifyH("CENTER")
    b.label=label

    local menu=CreateFrame("Frame", nil, parent)
    -- Stay within the Bank page owner, rather than competing globally.
    if menu.SetFrameLevel and JLP.UILayout then
        menu:SetFrameLevel(JLP.UILayout:OverlayFrameLevel(parent,"popover"))
    end
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
    menu:SetWidth(width or 120)
    menu:SetHeight((#entries or 1) * 24 + 8)
    local menuBg=menu:CreateTexture(nil,"BACKGROUND")
    menuBg:SetAllPoints()
    menuBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    menuBg:SetVertexColor(0.004,0.020,0.034,0.96)
    W:Border(menu,"border",1)
    menu:Hide()
    b.menu=menu

    menu.buttons={}
    for i,row in ipairs(entries or {}) do
        local item=CreateFrame("Button", nil, menu)
        item:SetSize((width or 120)-8, 24)
        item:SetPoint("TOPLEFT",4,-4-((i-1)*24))
        local ibg=item:CreateTexture(nil,"BACKGROUND")
        ibg:SetAllPoints()
        ibg:SetTexture("Interface\\Buttons\\WHITE8X8")
        ibg:SetVertexColor(0.01,0.08,0.14,0.0)
        item.bg=ibg
        local ilabel=W:Label(item,row.label or "","GameFontHighlight")
        ilabel:SetPoint("LEFT",10,0)
        ilabel:SetPoint("RIGHT",-8,0)
        ilabel:SetJustifyH("LEFT")
        item.label=ilabel
        item.value=row.key
        item:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.04,0.32,0.50,0.26) end)
        item:SetScript("OnLeave", function(self) self.bg:SetVertexColor(0.01,0.08,0.14,0.0) end)
        menu.buttons[#menu.buttons+1]=item
    end

    function b:SetText(value)
        self.label:SetText(value or "")
    end

    b:SetScript("OnClick", function(self)
        if self.__dropdownPeer then closeDropdown(self.__dropdownPeer) end
        self.menu:SetShown(not self.menu:IsShown())
    end)
    b:SetScript("OnHide", function(self) if self.menu then self.menu:Hide() end end)
    b:SetScript("OnEnter", function(self)
        self.__hover = self.__hover or W:Fill(self, "cyan", "ARTWORK")
        self.__hover:SetVertexColor(JLP.UITheme:Color("cyan"))
        self.__hover:SetAlpha(0.14)
    end)
    b:SetScript("OnLeave", function(self) if self.__hover then self.__hover:SetAlpha(0) end end)
    return b
end

function Page:SetCharacterKey(key)
    -- Explicit character switching must not leave the previous owner's
    -- transient exact-ID inspection active, even with the same item ID.
    if self.selectedCharacterKey~=key then
        self.materialFocusID=nil;self.materialFocusReceipt=nil
        local main=JLP.MainWindow
        if main and type(main.InvalidateMaterialReference)=="function" then
            main:InvalidateMaterialReference("Bank","CHARACTER_CHANGED")
        end
        self.selectedCharacterKey=key
        if self.frame then self:Refresh() end
    end
end

function Page:GetCharacterKey()
    local selected=validKey(self.selectedCharacterKey)
    if selected then return selected end
    local key=serviceCall(JLP:GetModule("Inventory"),"GetCharacterKey")
    return validKey(key)
end

function Page:SetCategory(key)
    -- An explicit category choice exits the temporary exact material filter.
    self.materialFocusID=nil;self.materialFocusReceipt=nil
    self.category=key or "all"
    self:Refresh()
end

function Page:SetSortMode(key)
    self.sortMode=key or "type"
    self:Refresh()
end

function Page:Create(parent)
    if self.frame then return self.frame end
    local W,L,C=JLP.UIWidgets,JLP.UILayout,JLP.UIComponents
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    local viewport=CreateFrame("ScrollFrame",nil,f);viewport:SetAllPoints(f)
    local pageRoot=CreateFrame("Frame",nil,viewport)
    pageRoot:SetSize(1078,636)
    if viewport.SetScrollChild then viewport:SetScrollChild(pageRoot) end
    f.pageScroll=viewport;f.pageRoot=pageRoot
    local bounds=L:PageGeometry(parent,1078,636)
    pageRoot:SetSize(bounds.width,bounds.height)
    function f:ScrollPage(delta)
        local max=math.max(0,(self.pageRoot:GetHeight() or 636)-(self:GetHeight() or 636))
        local current=self.pageScroll.GetVerticalScroll and self.pageScroll:GetVerticalScroll() or 0
        local nextOffset=math.max(0,math.min(max,(tonumber(current) or 0)+(tonumber(delta) or 0)))
        self.pageScroll:SetVerticalScroll(nextOffset)
    end
    if viewport.EnableMouseWheel then viewport:EnableMouseWheel(true) end
    viewport:SetScript("OnMouseWheel",function(_,wheel) f:ScrollPage(-(tonumber(wheel) or 0)*120) end)
    local width,height=bounds.width,bounds.height;local gap=14
    local leftWidth=width>=1078 and width-278 or math.max(600,width-278)
    local rightWidth=width-leftWidth-gap
    f.pageGeometry=bounds

    local storage=W:Card(pageRoot,"Bank Storage","primary"); storage:SetPoint("TOPLEFT",0,0); storage:SetSize(leftWidth,height)
    local search=CreateFrame("EditBox",nil,storage); search:SetHeight(30); search:SetPoint("TOPLEFT",250,-10); search:SetAutoFocus(false); search:SetFontObject(GameFontHighlight); search:SetTextInsets(32,8,0,0)
    local sbg=search:CreateTexture(nil,"BACKGROUND"); sbg:SetAllPoints(); sbg:SetTexture("Interface\\Buttons\\WHITE8X8"); sbg:SetVertexColor(0.004,0.020,0.034,0.78); W:Border(search,"border",1)
    local sicon=search:CreateTexture(nil,"ARTWORK"); sicon:SetSize(18,18); sicon:SetPoint("LEFT",8,0); sicon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    search:SetText("")
    local hint=W:Label(search,"Search items...","GameFontHighlight"); hint:SetPoint("LEFT",32,0); hint:SetTextColor(JLP.UITheme:Color("muted")); search.hint=hint
    search:SetScript("OnTextChanged",function(self)
        Page.searchText=lower(self:GetText())
        -- A deliberate free-text edit leaves exact material inspection.
        Page.materialFocusID=nil; Page.materialFocusReceipt=nil
        if self.hint then self.hint:SetShown((self:GetText() or "")=="") end
        Page:Refresh()
    end)
    storage.search=search

    local filterWidth=math.max(118, measureTextWidth(storage, longestLabel(CATEGORY_DEFS), "GameFontHighlight") + 24)
    local sortWidth=math.max(86, measureTextWidth(storage, longestLabel(SORTS), "GameFontHighlight") + 24)
    local sort=createDropdown(storage, SORTS, sortLabel(Page.sortMode), sortWidth); sort:SetPoint("TOPRIGHT",-20,-10); storage.sort=sort
    local sortLabelText=W:Label(storage,"Sort By:","GameFontHighlight"); sortLabelText:SetPoint("RIGHT",sort,"LEFT",-8,0); sortLabelText:SetTextColor(JLP.UITheme:Color("muted"))
    local filter=createDropdown(storage, CATEGORY_DEFS, categoryLabel(Page.category), filterWidth); filter:SetPoint("RIGHT",sortLabelText,"LEFT",-14,0); storage.filter=filter
    search:SetPoint("TOPRIGHT",filter,"TOPLEFT",-8,0)
    storage.sortLabelText=sortLabelText
    filter.__dropdownPeer=sort; sort.__dropdownPeer=filter
    for i,row in ipairs(filter.menu.buttons or {}) do
        local def=CATEGORY_DEFS[i]
        row:SetScript("OnClick", function() filter.menu:Hide(); Page:SetCategory(def.key) end)
    end
    for i,row in ipairs(sort.menu.buttons or {}) do
        local def=SORTS[i]
        row:SetScript("OnClick", function() sort.menu:Hide(); Page:SetSortMode(def.key) end)
    end

    -- Redundant filter summary line removed: search/category/sort controls
    -- already expose these values. Keep the existing filtering authority.
    storage.grid=L:ScrollArea(storage,{width=leftWidth-40,height=height-108,contentWidth=leftWidth-54,scrollbarGutter=12,wheelStep=52})
    storage.grid:SetPoint("TOPLEFT",20,-101)
    storage.slots={}
    storage.emptyNotice=W:Body(storage.grid.content); storage.emptyNotice:SetPoint("TOPLEFT",8,-8); storage.emptyNotice:SetPoint("TOPRIGHT",-8,-8); storage.emptyNotice:SetHeight(54); storage.emptyNotice:SetTextColor(JLP.UITheme:Color("muted")); storage.emptyNotice:Hide()

    local summary=W:Card(pageRoot,"Storage Summary","primary"); summary:SetPoint("TOPLEFT",storage,"TOPRIGHT",gap,0); summary:SetSize(rightWidth,196)
    local sumContent=CreateFrame("Frame",nil,summary); sumContent:SetPoint("TOPLEFT",22,-68); sumContent:SetPoint("TOPRIGHT",-22,-68); sumContent:SetHeight(110)
    summary.rows={bankRow(sumContent,"Total Slots:",0),bankRow(sumContent,"Used Slots:",-28),bankRow(sumContent,"Free Slots:",-56)}
    summary.rows[2].value:SetTextColor(JLP.UITheme:Color("good"))
    summary.progress=W:Progress(sumContent); summary.progress:SetPoint("TOPLEFT",0,-88); summary.progress:SetPoint("TOPRIGHT",-72,-88); summary.progress:SetHeight(18)
    summary.percent=W:Label(sumContent,"0%","GameFontHighlight"); summary.percent:SetPoint("LEFT",summary.progress,"RIGHT",12,0); summary.percent:SetJustifyH("RIGHT"); summary.percent:SetTextColor(JLP.UITheme:Color("gold"))

    summary.freshness=W:StatusPill(summary,"UNKNOWN","muted",84)
    summary.freshness:SetPoint("TOPRIGHT",-22,-17)
    if summary.SetHeadingRightInset then summary:SetHeadingRightInset(118) end
    summary.lastUpdated=W:Label(summary,"Last updated: unknown","GameFontHighlightSmall")
    -- Two-line footer, bounded to the summary card; previously a single
    -- BOTTOMRIGHT label escaped into the surrounding UI.
    summary.lastUpdated:SetPoint("BOTTOMLEFT",summary,"BOTTOMLEFT",22,11)
    summary.lastUpdated:SetPoint("BOTTOMRIGHT",summary,"BOTTOMRIGHT",-22,11)
    summary.lastUpdated:SetHeight(34)
    if summary.lastUpdated.SetWordWrap then summary.lastUpdated:SetWordWrap(true) end
    summary.lastUpdated:SetJustifyH("LEFT")
    summary.lastUpdated:SetTextColor(JLP.UITheme:Color("muted"))

    local categories=W:Card(pageRoot,"Categories","primary"); categories:SetPoint("TOPLEFT",summary,"BOTTOMLEFT",0,-gap); categories:SetPoint("BOTTOMRIGHT",0,0)
    -- Categories must remain accessible at short *wide* viewport sizes.
    -- A dedicated ScrollFrame owns every category button in both layouts.
    categories.scroll=CreateFrame("ScrollFrame",nil,categories)
    categories.scroll:SetPoint("TOPLEFT",categories,"TOPLEFT",17,-57)
    categories.scroll:SetPoint("BOTTOMRIGHT",categories,"BOTTOMRIGHT",-12,12)
    local list=CreateFrame("Frame",nil,categories.scroll)
    categories.categoryContentHeight=math.max(1,(#CATEGORY_DEFS-1)*36+32)
    list:SetSize(math.max(1,rightWidth-29),categories.categoryContentHeight)
    categories.scroll:SetScrollChild(list)
    categories.content=list
    categories.scrollbar=JLP.UILayout:AttachNativeScrollbar(categories.scroll,
        {owner=categories,right=-2,top=-57,bottom=12,gutter=9})
    if categories.scroll.EnableMouseWheel then categories.scroll:EnableMouseWheel(true) end
    categories.scroll:SetScript("OnMouseWheel",function(self,delta)
        local limit=math.max(0,(list:GetHeight() or 0)-(self:GetHeight() or 1))
        local offset=self.GetVerticalScroll and self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math.max(0,math.min(limit,offset-(tonumber(delta) or 0)*44)))
    end)
    categories.buttons={}
    for i,def in ipairs(CATEGORY_DEFS) do
        local b=makeCategoryButton(list,def,-((i-1)*36),rightWidth-44)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT",list,"TOPLEFT",5,-((i-1)*36))
        b:SetScript("OnClick",function() Page:SetCategory(def.key) end)
        categories.buttons[i]={button=b,def=def}
    end

    -- Only a reference label; source-qualified quantities are read from the
    -- existing inventory snapshot during Refresh, not from the return receipt.
    f.materialReference=W:Label(storage,"", "GameFontHighlightSmall")
    f.materialReference:SetPoint("TOPLEFT",20,-66)
    f.materialReference:SetWidth(math.max(160,leftWidth-230))
    if f.materialReference.SetWordWrap then f.materialReference:SetWordWrap(true) end
    if f.materialReference.SetHeight then f.materialReference:SetHeight(35) end
    f.materialReference:Hide()
    -- Exact ID filter is deliberately user-triggered. It uses the SAME slot
    -- list, snapshot-owner gate and grid as normal Bank browsing.
    f.materialFind=W:Button(storage,"Find this material",174)
    f.materialFind:SetHeight(22); f.materialFind:SetPoint("TOPRIGHT",-20,-65)
    f.materialFind:SetScript("OnClick",function() Page:FocusMaterialReference() end)
    f.materialFind:Hide()
    -- This is a location choice only. It never initiates a bank withdrawal.
    f.ownerServiceNavigate=W:Button(storage,"Nearest bank · UNKNOWN",174)
    f.ownerServiceNavigate:SetHeight(24)
    f.ownerServiceNavigate:SetPoint("BOTTOMLEFT",storage,"BOTTOMLEFT",20,12)
    f.ownerServiceNavigate:SetScript("OnClick",function()
       local navActions=JLP:GetModule("IntegratedNavigationActions")
       local source=navActions and navActions.NearestOwnerService and
            navActions:NearestOwnerService("BANK") or nil
       if navActions then navActions:Request("BANK",source,{explicit=true,owner="BANK_USER_CLICK"}) end
    end)
    f.navigateTo=W:Button(storage,"Navigate To · UNKNOWN",174)
    f.navigateTo:SetHeight(24);f.navigateTo:SetPoint("BOTTOMRIGHT",storage,"BOTTOMRIGHT",-20,12)
    local actions=JLP:GetModule("IntegratedNavigationActions")
    if actions then actions:Bind(f.navigateTo,"MATERIAL_SOURCE",function()
       local main=JLP.MainWindow
       local ref=main and main.GetMaterialReference and main:GetMaterialReference("Bank")
       return ref and ref.navigationSource
    end,function() return {explicit=true,owner="BANK_USER_CLICK"} end) end
    f.advisoryBack=W:Button(categories,"Return to material guide",rightWidth-44)
    f.advisoryBack:SetHeight(24);f.advisoryBack:SetPoint("TOPLEFT",22,-26)
    f.advisoryBack:SetScript("OnClick",function()
        local main=JLP.MainWindow
        if main and main.ReturnFromMaterialReference then main:ReturnFromMaterialReference() end
    end)
    f.advisoryBack:Hide()
    f.storage=storage; f.summary=summary; f.categories=categories; self.frame=f
    if f.SetScript then f:SetScript("OnSizeChanged",function() Page:ApplyLayout() end) end
    self:ApplyLayout()
    return f
end

-- Storage, Summary and Categories form one measured page content hierarchy.
-- Full width preserves the authored alpha290 layout exactly.
function Page:ApplyLayout()
    local f=self.frame
    if not (f and f.storage and f.pageRoot) then return false end
    local w=tonumber(f.GetWidth and f:GetWidth()) or 0
    local h=tonumber(f.GetHeight and f:GetHeight()) or 0
    if w<=0 then w=1078 end
    if h<=0 then h=636 end
    local stacked=w<1000
    local gap=14
    local storage=f.storage;local summary=f.summary;local categories=f.categories
    local storageW=stacked and w or math.max(600,w-278)
    local storageH=stacked and math.max(490,h-66) or h
    local rightW=stacked and w or math.max(1,w-storageW-gap)
    local summaryH=232
    local catH=math.max(400,82+#categories.buttons*36)
    storage:ClearAllPoints();storage:SetPoint("TOPLEFT",f.pageRoot,"TOPLEFT",0,0)
    storage:SetSize(storageW,storageH)
    summary:ClearAllPoints();summary:SetSize(rightW,summaryH)
    categories:ClearAllPoints()
    if stacked then
        summary:SetPoint("TOPLEFT",storage,"BOTTOMLEFT",0,-gap)
        categories:SetPoint("TOPLEFT",summary,"BOTTOMLEFT",0,-gap)
        categories:SetSize(w,catH)
    else
        summary:SetPoint("TOPLEFT",storage,"TOPRIGHT",gap,0)
        categories:SetPoint("TOPLEFT",summary,"BOTTOMLEFT",0,-gap)
        categories:SetSize(rightW,math.max(1,h-summaryH-gap))
    end
    local contentH=stacked and storageH+summaryH+catH+2*gap or h
    f.pageRoot:SetSize(w,math.max(h,contentH))
    local search=storage.search
    search:ClearAllPoints()
    storage.filter:ClearAllPoints()
    storage.sort:ClearAllPoints()
    storage.sortLabelText:ClearAllPoints()
    f.materialReference:ClearAllPoints()
    f.materialFind:ClearAllPoints()
    if stacked then
        search:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-52)
        search:SetWidth(math.max(130,w-40))
        storage.filter:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-92)
        storage.sort:SetPoint("TOPRIGHT",storage,"TOPRIGHT",-20,-92)
        storage.sortLabelText:SetPoint("RIGHT",storage.sort,"LEFT",-8,0)
        f.materialReference:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-157)
        f.materialFind:SetPoint("TOPRIGHT",storage,"TOPRIGHT",-20,-157)
        storage.grid:ClearAllPoints()
        local evidenceVisible=f.materialReference:IsShown() or f.materialFind:IsShown()
        local top=evidenceVisible and 180 or 145
        storage.grid:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-top)
        storage.grid:Resize(math.max(1,w-40),math.max(1,storageH-top-46),math.max(1,w-54))
    else
        -- Header title and search/filter controls occupy separate rows.
        storage.sort:SetPoint("TOPRIGHT",storage,"TOPRIGHT",-20,-55)
        storage.sortLabelText:SetPoint("RIGHT",storage.sort,"LEFT",-8,0)
        storage.filter:SetPoint("RIGHT",storage.sortLabelText,"LEFT",-14,0)
        search:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-55)
        search:SetPoint("TOPRIGHT",storage.filter,"TOPLEFT",-8,0)
        f.materialReference:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-111)
        f.materialFind:SetPoint("TOPRIGHT",storage,"TOPRIGHT",-20,-110)
        storage.grid:ClearAllPoints()
        local evidenceVisible=f.materialReference:IsShown() or f.materialFind:IsShown()
        local top=evidenceVisible and 133 or 99
        storage.grid:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-top)
        storage.grid:Resize(math.max(1,storageW-40),math.max(1,storageH-top-46),math.max(1,storageW-54))
    end
    f.materialReference:SetWidth(math.max(130,storageW-230))
    f.advisoryBack:SetWidth(math.max(100,rightW-44))
    if categories.content and categories.scroll then
        categories.content:SetWidth(math.max(1,rightW-29))
        if categories.categoryContentHeight and categories.content.SetHeight then
            categories.content:SetHeight(categories.categoryContentHeight)
        end
        local maxCategories=math.max(0,(categories.categoryContentHeight or categories.content:GetHeight())-categories.scroll:GetHeight())
        if categories.scroll.GetVerticalScroll and categories.scroll.SetVerticalScroll then
            categories.scroll:SetVerticalScroll(math.max(0,math.min(maxCategories,categories.scroll:GetVerticalScroll() or 0)))
        end
        if categories.scrollbar then categories.scrollbar:Refresh() end
    end
    for _,entry in ipairs(categories.buttons) do
        entry.button:SetWidth(math.max(1,rightW-44))
    end
    -- Vertical page scrolling uses one proportional scrollbar when stacked.
    if not f.outerScrollbar then
        f.outerScrollbar=JLP.UILayout:AttachNativeScrollbar(f.pageScroll,
            {owner=f,right=-2,top=-2,bottom=2})
    end
    if f.outerScrollbar then f.outerScrollbar:Refresh() end
    f.__layoutStacked=stacked
    f.__bankGridTop=stacked and ((f.materialReference:IsShown() or f.materialFind:IsShown()) and 180 or 145) or
        ((f.materialReference:IsShown() or f.materialFind:IsShown()) and 133 or 99)
    return true
end

local function ensureSlots(card,count)
    while #card.slots<count do card.slots[#card.slots+1]=JLP.UIComponents:BankSlot(card.grid.content,52) end
    for i,slot in ipairs(card.slots) do slot:SetShown(i<=count) end
end

function Page:Refresh()
    if self.frame and self.frame.advisoryBack then
        local main=JLP.MainWindow
        self.frame.advisoryBack:SetShown(main and main.advisoryReturn~=nil and main.activePage=="Bank")
    end
    if not self.frame then return end
    self:ApplyLayout()
    if self.frame.ownerServiceNavigate then
       local actions=JLP:GetModule("IntegratedNavigationActions")
       local source=actions and actions.NearestOwnerService and actions:NearestOwnerService("BANK") or nil
       if actions then actions:Update(self.frame.ownerServiceNavigate,"BANK",source,{explicit=true}) end
       if source and self.frame.ownerServiceNavigate.SetText then
           self.frame.ownerServiceNavigate:SetText("Navigate · "..tostring(source.name or "Bank")) end
    end
    if self.frame.navigateTo then
       local actions=JLP:GetModule("IntegratedNavigationActions")
       local main=JLP.MainWindow
       local ref=main and main.GetMaterialReference and main:GetMaterialReference("Bank")
       if actions then actions:Update(self.frame.navigateTo,"MATERIAL_SOURCE",ref and ref.navigationSource,{explicit=true}) end
    end
    local inventory=JLP:GetModule("Inventory")
    local currentKey,currentCallable=serviceCall(inventory,"GetCharacterKey")
    currentKey=validKey(currentKey)
    local selectedKey=validKey(self.selectedCharacterKey)
    local key=selectedKey or currentKey
    local serviceAvailable=type(inventory)=="table" and currentCallable and currentKey~=nil and
        type(inventory.GetBankSnapshot)=="function" and
        type(inventory.RefreshBankCache)=="function" and
        type(inventory.IsBankOpen)=="function" and
        type(inventory.GetSnapshotFreshness)=="function" and
        type(inventory.GetCurrentCharacterIdentity)=="function"
    local isCurrent=key~=nil and currentKey~=nil and key==currentKey
    local bankOpen=false
    local refreshSucceeded=false
    if isCurrent and serviceAvailable then
        local open,ok=serviceCall(inventory,"IsBankOpen")
        bankOpen=ok and open==true
        if bankOpen then
            -- Refresh is permitted only for the verified current character,
            -- and is the pre-existing user-opened bank refresh, not a new scan.
            local refreshed,callOK=serviceCall(inventory,"RefreshBankCache",{allowContraction=false})
            -- Inventory returns true on a completed scan and false plus a
            -- settling/readability reason when a prior snapshot was retained.
            -- An exception or a false result must never confer LIVE freshness.
            refreshSucceeded=callOK and refreshed==true
        end
    end
    local raw,readOK=nil,false
    if serviceAvailable and key then raw,readOK=serviceCall(inventory,"GetBankSnapshot",key) end
    local snapshot=qualifiedSnapshot(readOK and raw or nil,key)
    if not snapshot.characterName and selectedKey then snapshot.characterName=selectedKey end
    local snapshotKnown=snapshot.known==true
    local isLive=isCurrent and bankOpen and refreshSucceeded and snapshotKnown
    local freshness="UNKNOWN"
    if serviceAvailable and snapshotKnown then
        local result,ok=serviceCall(inventory,"GetSnapshotFreshness",snapshot.updatedAt,isLive)
        if ok and ((isLive and result=="LIVE") or result=="RECENT" or result=="STALE") then
            freshness=result
        end
    end
    if self.frame.storage and self.frame.storage.heading then
        local selectedName=snapshot.characterName or (key and "Selected Character" or "Character Unknown")
        local identity,identityOK=serviceCall(inventory,"GetCurrentCharacterIdentity")
        if not identityOK or type(identity)~="table" then identity=nil end
        local selectedRealm=snapshot.realm
        local crossRealm=selectedRealm and identity and type(identity.realm)=="string" and selectedRealm~=identity.realm
        local suffix=crossRealm and (" - "..selectedRealm) or ""
        self.frame.storage.heading:SetText("Bank Storage - "..tostring(selectedName)..suffix)
    end
    if self.frame.summary and self.frame.summary.freshness then
        local tones={LIVE="good",RECENT="cyan",STALE="warn",UNKNOWN="muted"}
        self.frame.summary.freshness:SetStatus(freshness,tones[freshness] or "muted")
        local stamp=snapshotKnown and tonumber(snapshot.updatedAt) or nil
        local updated=nil
        if stamp and stamp==stamp and stamp~=math.huge and stamp~=-math.huge and type(date)=="function" then
            local ok,formatted=pcall(date,"%d-%m-%Y %H:%M",stamp)
            if ok and type(formatted)=="string" then updated=formatted end
        end
        local scope=not serviceAvailable and selectedKey and currentKey and selectedKey~=currentKey and
            "Other character; transfer required (Bank service incomplete)" or
            not serviceAvailable and "Bank service unavailable or incomplete" or
            not key and "Character identity unknown" or
            isLive and "LIVE current character" or
            isCurrent and bankOpen and not refreshSucceeded and "Current character cached (refresh unconfirmed)" or
            isCurrent and "Current character cached" or
            "Other character; transfer required"
        -- Separate timestamp and authority detail so both can wrap inside
        -- the bounded two-line footer at narrow widths.
        self.frame.summary.lastUpdated:SetText("Updated: "..tostring(updated or "unknown").."\n"..scope)
        local footer=self.frame.summary.lastUpdated
        -- Expand within the summary footer band when authority text wraps.
        if footer.GetStringHeight then
            local measured=tonumber(footer:GetStringHeight()) or 34
            footer:SetHeight(math.max(34,math.min(76,measured+4)))
        end
    end
    local all=displaySlots(snapshot)
    -- Reference is a transient UI affordance, NEVER saved bank state.
    -- Match the qualified snapshot's item ID, not a typed name/search term.
    local main=JLP.MainWindow
    local ref=main and main.GetMaterialReference and main:GetMaterialReference("Bank")
    if not ref or ref~=self.materialFocusReceipt or
        not validMaterialID(ref and ref.materialID) then
        self.materialFocusID=nil; self.materialFocusReceipt=nil
    end
    local focusedID=self.materialFocusID
    if self.frame.materialFind then
        local show=ref and ref.readOnly==true and ref.nativeDispatchAllowed==false and
            validMaterialID(ref.materialID)
        self.frame.materialFind:SetShown(show==true)
        if show then self.frame.materialFind:SetText(focusedID and "Show all bank items" or "Find this material") end
    end
    if self.frame.materialReference then
        if ref then
            local count=nil
            if snapshotKnown then
                -- qualifiedSnapshot verified every items[] count. Use this
                -- authoritative per-item aggregate instead of a second O(slots)
                -- traversal during every read-only Bank UI refresh.
                local W=JLP.UIWidgets
                count=W and W.QualifiedBankMaterialCount and
                    W:QualifiedBankMaterialCount(snapshot,ref.materialID) or nil
            end
            local widget=JLP.UIWidgets
            local label=widget and widget.MaterialInspectionSummary and
                widget:MaterialInspectionSummary(ref,"Bank",count,freshness)
            self.frame.materialReference:SetText(label or "Reference unavailable · manual review")
            self.frame.materialReference:Show()
        else
            local old=main and main.advisoryReturn
            if old and old.target=="Bank" and old.contextInvalidated==true then
                self.frame.materialReference:SetText(
                    "STALE REFERENCE · character selection changed. Exact item focus disabled; return and reselect the source.")
                self.frame.materialReference:Show()
            else self.frame.materialReference:Hide() end
        end
    end
    -- Reference controls change visibility after the primary layout pass;
    -- the grid must immediately reclaim their row in normal Bank browsing.
    local referenceVisible=self.frame.materialReference and self.frame.materialReference:IsShown()
    local findVisible=self.frame.materialFind and self.frame.materialFind:IsShown()
    local gridTop=self.frame.__layoutStacked and ((referenceVisible or findVisible) and 180 or 145) or
        ((referenceVisible or findVisible) and 133 or 99)
    if self.frame.__bankGridTop~=gridTop then
        self.frame.__bankGridTop=gridTop
        local storage=self.frame.storage
        storage.grid:ClearAllPoints()
        storage.grid:SetPoint("TOPLEFT",storage,"TOPLEFT",20,-gridTop)
        storage.grid:Resize(math.max(1,storage:GetWidth()-40),
            math.max(1,storage:GetHeight()-gridTop-18),
            math.max(1,storage:GetWidth()-54))
    end
    local search=lower(self.searchText)
    local counts={all=0,crafting=0,cloth=0,herbs=0,ores=0,leather=0,food=0,scrolls=0,misc=0}
    local occupied={}
    for _,row in ipairs(all) do
        if row.itemID then
            counts.all=counts.all+1
            -- Item ID is the authoritative exact-match key. Do not query the
            -- knowledge catalog or run category classification for thousands
            -- of unrelated bank slots while inspecting one qualified item.
            if not focusedID or row.itemID==focusedID then
                local meta=itemMeta(row.itemID) or {}
                row.name=meta.name or ("Item "..tostring(row.itemID));row.meta=meta
                if not focusedID then
                    local primary=categoryFor(meta,row.name,row.itemID)
                    counts[primary]=(counts[primary] or 0)+1
                    if primary~="crafting" and matchesCategory(meta,row.name,"crafting") then counts.crafting=counts.crafting+1 end
                end
                if focusedID then
                    occupied[#occupied+1]=row
                elseif matchesCategory(meta,row.name,self.category) and
                    (search=="" or lower(row.name):find(search,1,true)) then
                    occupied[#occupied+1]=row
                end
            end
        end
    end

    table.sort(occupied,function(a,b)
        if Page.sortMode=="quantity" then
            local aq,bq=tonumber(a.count) or 0,tonumber(b.count) or 0
            if aq~=bq then return aq>bq end
        elseif Page.sortMode=="name" then
            local an,bn=lower(a.name),lower(b.name); if an~=bn then return an<bn end
        else
            local ac,bc=categoryFor(a.meta,a.name,a.itemID),categoryFor(b.meta,b.name,b.itemID)
            if ac~=bc then return ac<bc end
            local an,bn=lower(a.name),lower(b.name); if an~=bn then return an<bn end
        end
        return (a.itemID or 0)<(b.itemID or 0)
    end)

    local display={}
    for _,row in ipairs(occupied) do display[#display+1]=row end
    if not focusedID and self.category=="all" and search=="" then
        local total=tonumber(snapshot.totalSlots) or #all
        if total<#display then total=#display end
        for i=#display+1,total do display[i]={} end
    end

    local card=self.frame.storage
    card.filter:SetText(focusedID and "Exact item ID" or categoryLabel(self.category))
    card.sort:SetText(sortLabel(self.sortMode))
    ensureSlots(card,#display)
    local slotSize,gap=52,8
    local available=math.max(1,tonumber(card.grid.__contentWidth) or 720)
    local columns=math.max(1,math.min(12,math.floor((available-8+gap)/(slotSize+gap))))
    for i,widget in ipairs(card.slots) do
        if display[i] then
            local idx=i-1; local col=idx%columns; local row=math.floor(idx/columns)
            widget:ClearAllPoints(); widget:SetPoint("TOPLEFT",8+(col*(slotSize+gap)),-8-(row*(slotSize+gap))); widget:SetSlot(display[i])
        end
    end
    local rowCount=math.max(1,math.ceil(math.max(1,#display)/columns)); card.grid:SetContentHeight(16+(rowCount*(slotSize+gap)),true)
    -- Search is a filter too. Without this condition, All Items with a
    -- nonmatching search writes the empty-state text but hides its notice.
    card.emptyNotice:SetShown(not snapshot.known or (#occupied==0 and
        (focusedID~=nil or self.category~="all" or search~="")))
    if not snapshot.known then
        local feedback=JLP.UIWidgets:FeedbackState("empty","Bank inventory unknown. Log into that character with JuztLevel enabled and open their Bank once. Other-character caches cannot count as current inventory. Offline banks cannot be read directly.")
        card.emptyNotice:SetText("No bank snapshot for "..tostring(snapshot.characterName or "this character")..". "..feedback.detail)
    elseif #occupied==0 and focusedID then
        local W=JLP.UIWidgets
        local known=W and W.QualifiedBankMaterialCount and
            W:QualifiedBankMaterialCount(snapshot,focusedID)
        if known==0 then
            card.emptyNotice:SetText("Item #"..tostring(focusedID)..
                " has no occupied slots in this qualified bank snapshot (0 cached). Review snapshot age and selected character.")
        else
            card.emptyNotice:SetText("Item #"..tostring(focusedID)..
                " cannot be matched to a qualified slot; bank quantity UNKNOWN. Verify manually.")
        end
    elseif #occupied==0 and (self.category~="all" or search~="") then card.emptyNotice:SetText("No bank items match the current filter.") end

    if not snapshotKnown then
        -- Unknown must not appear as a verified empty bank.
        for _,row in ipairs(self.frame.summary.rows) do row.value:SetText("—") end
        self.frame.summary.progress:SetSkill(0,1)
        if self.frame.summary.progress.SetAlpha then self.frame.summary.progress:SetAlpha(0.25) end
        self.frame.summary.percent:SetText("—")
    else
        local total=snapshot.totalSlots
        local used=snapshot.usedSlots
        local free=tonumber(snapshot.freeSlots)
        if free==nil or free<0 or (free+used)~=total then free=math.max(0,total-used) end
        local percent=total>0 and math.floor((used/total)*100+0.5) or 0
        self.frame.summary.rows[1].value:SetText(tostring(total))
        self.frame.summary.rows[2].value:SetText(tostring(used))
        self.frame.summary.rows[3].value:SetText(tostring(free))
        self.frame.summary.progress:SetSkill(used,math.max(1,total))
        if self.frame.summary.progress.SetAlpha then self.frame.summary.progress:SetAlpha(1) end
        self.frame.summary.percent:SetText(tostring(percent).."%")
    end
    for _,entry in ipairs(self.frame.categories.buttons) do
        entry.button.count:SetText(focusedID and "—" or (snapshotKnown and tostring(counts[entry.def.key] or 0) or "—"))
        entry.button:SetActive(entry.def.key==self.category)
    end
end

JLP.UIPages=JLP.UIPages or {}
JLP.UIPages[Page.name]=Page
