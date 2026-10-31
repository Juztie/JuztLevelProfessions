local _, JLP = ...

local Components = {}

local function W() return JLP.UIWidgets end

local function validItemIcon(value)
    if value == nil or value == false or value == 0 or value == "" then return nil end
    return value
end
local function C(name) return JLP.UITheme:Color(name) end
local function safe(v) return JLP.SafeText and JLP:SafeText(v) or tostring(v or "") end

local function toneText(value, tone)
    local r,g,b = C(tone or "text")
    return string.format("|cff%02x%02x%02x%s|r", math.floor((r or 1)*255+0.5), math.floor((g or 1)*255+0.5), math.floor((b or 1)*255+0.5), safe(value))
end

function Components:Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    size = size or 40
    f:SetSize(size, size)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.005, 0.018, 0.030, 0.96)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    tex:SetTexture(JLP.UIIconResolver:GetFallback())
    f.texture = tex
    W():Border(f, "border", 1)
    if f.EnableMouse then f:EnableMouse(true) end

    function f:ClearInteraction()
        self.__interactionKind = nil
        self.__itemID = nil
        self.__itemName = nil
        self.__professionKey = nil
        self.__profession = nil
    end
    function f:SetResolved(texture)
        self.texture:SetTexture(texture or JLP.UIIconResolver:GetFallback())
    end
    function f:SetItemContext(itemID, name)
        self.__interactionKind = "item"
        self.__itemID = tonumber(itemID) or itemID
        self.__itemName = name
        self.__professionKey = nil
        self.__profession = nil
    end
    function f:SetItem(itemID, name)
        self:SetResolved(JLP.UIIconResolver:GetItem(itemID, name))
        self:SetItemContext(itemID, name)
    end
    function f:SetProfession(key, profession)
        self:SetResolved(JLP.UIIconResolver:GetProfession(key, profession))
        self.__interactionKind = "profession"
        self.__professionKey = key
        self.__profession = profession
        self.__itemID = nil
        self.__itemName = nil
    end

    f:SetScript("OnEnter", function(self)
        local interaction = JLP.UIInteraction
        if not interaction then return end
        if self.__interactionKind == "item" then
            interaction:ShowItem(self, self.__itemID, self.__itemName)
        elseif self.__interactionKind == "profession" then
            interaction:ShowProfession(self, self.__professionKey, self.__profession)
        end
    end)
    f:SetScript("OnLeave", function(self)
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self) end
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if not JLP.UIInteraction then return end
        if self.__interactionKind == "item" then
            local ok, message = JLP.UIInteraction:HandleItemClick(self.__itemID, self.__itemName, button)
            if not ok and message and JLP.UIInteraction:IsAuctionHouseOpen() and JLP.Print then JLP:Print(message) end
            return
        end
        if button ~= "LeftButton" or self.__interactionKind ~= "profession" then return end
        local ok, message = JLP.UIInteraction:OpenProfession(self.__professionKey, self.__profession)
        if not ok and JLP.Print then JLP:Print(message) end
    end)
    return f
end

function Components:EnchantTargetSlot(parent, size)
    -- Compact Optional Target selector.  This intentionally does NOT instantiate
    -- Blizzard's detached profession enchant-slot template.  Detached Blizzard profession
    -- templates contain internal input/state surfaces whose hit-testing changes in
    -- Forever after the first selection.  One JuztLevel Button now owns both the
    -- visible slot and every mouse event, so selected artwork can never replace or
    -- cover the interaction surface.
    size = size or 30
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.__nativeEnchantSlot=false
    b.__jlpSingleSurface=true
    b.hit=b

    local function arm(self)
        self.__jlpMouseIntent=true
        local through=JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough
        if self.EnableMouse then self:EnableMouse(not through) end
        if self.RegisterForClicks then self:RegisterForClicks("LeftButtonDown", "LeftButtonUp") end
        if self.SetMouseClickEnabled then pcall(self.SetMouseClickEnabled,self,true) end
        if self.SetMouseMotionEnabled then pcall(self.SetMouseMotionEnabled,self,true) end
        if self.SetHitRectInsets then self:SetHitRectInsets(0,0,0,0) end
        if self.SetFrameLevel and parent and parent.GetFrameLevel then
            local ok,level=pcall(parent.GetFrameLevel,parent)
            if ok and tonumber(level) then
                local policy=JLP.UILayout
                self:SetFrameLevel(policy and policy.OverlayFrameLevel and
                    policy:OverlayFrameLevel(parent,"control") or tonumber(level)+5)
            end
        end
    end
    arm(b)

    local bg=b:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.018,0.018,0.016,0.98)
    b.background=bg

    local inner=b:CreateTexture(nil,"BORDER")
    inner:SetPoint("TOPLEFT",3,-3)
    inner:SetPoint("BOTTOMRIGHT",-3,3)
    inner:SetTexture("Interface\\Buttons\\WHITE8X8")
    inner:SetVertexColor(0.035,0.045,0.040,0.94)
    b.inner=inner

    local tex=b:CreateTexture(nil,"ARTWORK")
    tex:SetPoint("TOPLEFT",3,-3)
    tex:SetPoint("BOTTOMRIGHT",-3,3)
    tex:Hide()
    b.texture=tex

    -- Native-like circular green plus.  Both regions are textures/fontstrings on
    -- the Button itself; neither can receive mouse input independently.
    local ring=b:CreateTexture(nil,"OVERLAY")
    ring:SetSize(math.max(18,size-8),math.max(18,size-8))
    ring:SetPoint("CENTER")
    ring:SetTexture("Interface\\Buttons\\WHITE8X8")
    ring:SetVertexColor(0.24,0.32,0.46,0.90)
    b.plusRing=ring
    local plus=W():Label(b,"+","GameFontNormalLarge")
    plus:SetPoint("CENTER",0,0)
    plus:SetJustifyH("CENTER")
    plus:SetTextColor(0.10,1.00,0.18,1.0)
    b.plus=plus
    W():Border(b,"border",1)

    local function resolveIcon(row)
        if not row then return nil end
        if JLP.UIIconResolver and JLP.UIIconResolver.GetEnchantTarget then
            return JLP.UIIconResolver:GetEnchantTarget(row,true)
        end
        local explicit=validItemIcon(row.icon)
        if explicit then return explicit end
        if row.itemID and JLP.UIIconResolver then return JLP.UIIconResolver:GetItem(row.itemID,row.name) end
        return nil
    end

    local function targetIdentity(row)
        if not row then return "none" end
        return tostring(row.guid or row.link or row.itemID or row.name or "unknown")
    end

    function b:SetTarget(row)
        local previousIdentity=targetIdentity(self.__target)
        local nextIdentity=targetIdentity(row)
        -- Always retain the freshest ItemLocation/link for exact-instance tooltips,
        -- but do not repaint/re-arm the same visual target on every data refresh.
        self.__target=row
        self.__jlpSetTargetCount=(self.__jlpSetTargetCount or 0)+1
        local nextIcon=row and (resolveIcon(row) or "Interface\\Icons\\INV_Misc_QuestionMark") or nil
        -- Item data can settle after the target was selected. Keep the stable
        -- single Button/hit surface, but allow that same GUID to repaint exactly
        -- once when its real texture replaces the temporary placeholder.
        if previousIdentity==nextIdentity and self.__jlpResolvedIcon==nextIcon then return end
        self.__jlpResolvedIcon=nextIcon
        if row then
            self.texture:SetTexture(nextIcon)
            self.texture:Show()
            self.plus:Hide()
            self.plusRing:Hide()
        else
            self.texture:SetTexture(nil)
            self.texture:Hide()
            self.plusRing:Show()
            self.plus:Show()
        end
        self.__jlpManualVisualCount=(self.__jlpManualVisualCount or 0)+1
        -- Reassert only this same Button; no new frames are created or shown.
        arm(self)
    end

    function b:GetTarget() return self.__target end
    function b:SetPickerHandler(handler) self.__pickerHandler=handler end
    function b:OpenPicker()
        self.__jlpOpenCount=(self.__jlpOpenCount or 0)+1
        if self.__pickerHandler then return self.__pickerHandler(self) end
    end

    b:SetScript("OnMouseDown",function(self,button)
        if button~="LeftButton" then return end
        self.__jlpMouseDownCount=(self.__jlpMouseDownCount or 0)+1
        self.__jlpOwnedHitDownCount=(self.__jlpOwnedHitDownCount or 0)+1
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltip() end
        self:OpenPicker()
    end)
    b:SetScript("OnShow",function(self)
        self.__jlpShowCount=(self.__jlpShowCount or 0)+1
        arm(self)
    end)
    b:SetScript("OnHide",function(self)
        self.__jlpHideCount=(self.__jlpHideCount or 0)+1
    end)
    b:SetScript("OnEnter",function(self)
        self.__jlpEnterCount=(self.__jlpEnterCount or 0)+1
        local row=self.__target
        if row and JLP.UIInteraction then
            if JLP.UIInteraction.ShowItemLocation then JLP.UIInteraction:ShowItemLocation(self,row)
            else JLP.UIInteraction:ShowItem(self,row.itemID,row.name) end
            if type(GameTooltip)=="table" and GameTooltip.AddLine then
                GameTooltip:AddLine("Click to replace this enchant target.",0.2,1.0,0.2,true)
                if GameTooltip.Show then GameTooltip:Show() end
            end
        elseif type(GameTooltip)=="table" and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            if GameTooltip.ClearLines then GameTooltip:ClearLines() end
            if GameTooltip.SetText then GameTooltip:SetText("Optional Target") end
            if GameTooltip.AddLine then GameTooltip:AddLine("Click to choose an enchant target.",0.2,1.0,0.2,true) end
            if GameTooltip.Show then GameTooltip:Show() end
        end
    end)
    b:SetScript("OnLeave",function(self)
        self.__jlpLeaveCount=(self.__jlpLeaveCount or 0)+1
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self)
        elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
    end)

    b:SetTarget(nil)
    return b
end

function Components:SectionTitle(parent, text)
    local label = W():SectionLabel(parent, text or "", "gold")
    return label
end

function Components:KeyValueRow(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 360, 22)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18,18)
    f.icon:SetPoint("LEFT",0,0)
    f.icon:SetTexture(JLP.UIIconResolver:GetSemantic("info"))
    f.label = W():Label(f, "", "GameFontHighlight")
    f.label:SetPoint("LEFT", f.icon, "RIGHT", 9, 0)
    f.label:SetWidth(126)
    f.label:SetJustifyH("LEFT")
    f.label:SetTextColor(C("muted"))
    f.value = W():Label(f, "", "GameFontHighlight")
    f.value:SetPoint("LEFT", f.label, "RIGHT", 5, 0)
    f.value:SetPoint("RIGHT", -2, 0)
    f.value:SetJustifyH("LEFT")
    function f:SetRow(iconKey, label, value, tone)
        self.icon:SetTexture(JLP.UIIconResolver:GetSemantic(iconKey or "info"))
        self.label:SetText(label or "")
        self.value:SetText(value or "")
        self.value:SetTextColor(C(tone or "text"))
    end
    return f
end

function Components:InlineRow(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 300, 22)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18,18)
    f.icon:SetPoint("LEFT",0,0)
    f.icon:SetTexture(JLP.UIIconResolver:GetSemantic("info"))
    f.text = W():Label(f,"","GameFontHighlightSmall")
    f.text:SetPoint("LEFT",f.icon,"RIGHT",9,0)
    f.text:SetPoint("RIGHT",-2,0)
    f.text:SetJustifyH("LEFT")
    function f:SetRow(iconKey, label, value, tone)
        self.icon:SetTexture(JLP.UIIconResolver:GetSemantic(iconKey or "info"))
        self.text:SetText(safe(label or "") .. (label and label ~= "" and ": " or "") .. toneText(value or "", tone or "text"))
    end
    return f
end

-- The ActionBlock owns the vertical space occupied by its wrapped title and
-- instruction. Consumers anchor following sections below its measured bounds.
function Components:ActionBlock(parent, width, compact)
    local f = CreateFrame("Frame", nil, parent)
    local minimum=compact and 54 or 64
    local iconSize=compact and 42 or 48
    f:SetSize(width or 420, minimum)
    f.icon = self:Icon(f, iconSize)
    f.icon:SetPoint("TOPLEFT",0,0)
    f.title = W():Label(f,"","GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -1)
    f.title:SetPoint("TOPRIGHT", -2, -1)
    f.title:SetJustifyH("LEFT")
    f.title:SetTextColor(C("cyan"))
    f.meta = W():Label(f,"","GameFontHighlight")
    f.meta:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -7)
    -- TOPRIGHT with a fixed negative y constrains a multiline meta label to
    -- its first row. Anchor only the right edge; its height remains intrinsic.
    f.meta:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -7)
    f.meta:SetJustifyH("LEFT")
    f.meta:SetTextColor(C("muted"))
    local function measured(region, fallback)
        if region and region.GetStringHeight then
            local ok, h=pcall(region.GetStringHeight,region)
            if ok and type(h)=="number" and h==h and h>0 and h<math.huge then
                return math.ceil(h)
            end
        end
        return fallback
    end
    function f:Relayout()
        -- ActionBlock belongs to the scroll content, not the original card
        -- geometry. Reconcile its width before measuring wrapped text when
        -- an existing Guide instance is resized (including 540 -> 280 -> 540).
        local parentWidth=parent and parent.GetWidth and tonumber(parent:GetWidth())
        if parentWidth and parentWidth==parentWidth and parentWidth>=80 and parentWidth<math.huge then
            local current=self.GetWidth and tonumber(self:GetWidth())
            if not current or math.abs(current-parentWidth)>0.01 then
                self:SetWidth(parentWidth)
            end
        end
        local titleH=measured(self.title, 18)
        local metaH=measured(self.meta, 16)
        local value=math.max(minimum, 1+titleH+7+metaH+6, iconSize+6)
        -- Hard cap prevents corrupt text metrics from producing unbounded
        -- scroll content; normal paragraphs can still expand to many lines.
        value=math.min(16000,math.ceil(value))
        self:SetHeight(value)
        self.__layoutHeight=value
        return value
    end
    function f:SetAction(iconTexture, title, meta, titleTone, itemID, itemName)
        self.icon:SetResolved(iconTexture)
        if itemID or itemName then self.icon:SetItemContext(itemID, itemName) else self.icon:ClearInteraction() end
        self.title:SetText(title or "")
        self.title:SetTextColor(C(titleTone or "cyan"))
        self.meta:SetText(meta or "")
        self:Relayout()
    end
    f:Relayout()
    return f
end

local SOURCE_LABELS = {
    crafted="Craft", craft="Craft", vendor="Vendor", auction="Auction House",
    ["disenchant-or-auction"]="Disenchant / AH", bank="Bank",
}

function Components:MaterialRow(parent, width, detailed, guideReadable)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 430, detailed and 118 or 108)
    f.__layoutHeight=detailed and 118 or 108
    f.itemIcon = self:Icon(f, detailed and 48 or 42)
    f.itemIcon:SetPoint("TOPLEFT",0,0)
    f.name = W():Label(f,"","GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT",f.itemIcon,"TOPRIGHT",12,-1)
    f.name:SetJustifyH("LEFT")
    f.name:SetTextColor(C("cyan"))
    f.source = W():Label(f,"","GameFontHighlight")
    f.source:SetPoint("TOPRIGHT",-2,-1)
    f.source:SetWidth(118)
    f.source:SetJustifyH("RIGHT")
    f.source:SetTextColor(C("text"))
    f.name:SetPoint("RIGHT",f.source,"LEFT",-10,0)
    f.summary = W():Label(f,"","GameFontHighlight")
    f.summary:SetPoint("TOPLEFT",f.name,"BOTTOMLEFT",0,-8)
    f.summary:SetPoint("TOPRIGHT",-2,-29)
    f.summary:SetJustifyH("LEFT")
    f.summary:SetTextColor(C("text"))
    f.dependencyName = W():Label(f,"","GameFontHighlight")
    f.dependencyName:SetPoint("TOPLEFT",f.summary,"BOTTOMLEFT",0,-5)
    f.dependencyName:SetPoint("TOPRIGHT",-2,-49)
    f.dependencyName:SetJustifyH("LEFT")
    f.dependencyName:SetTextColor(C("cyan"))
    f.dependencyName:Hide()
    f.dependencyCounts = W():Label(f,"","GameFontHighlightSmall")
    f.dependencyCounts:SetPoint("TOPLEFT",f.dependencyName,"BOTTOMLEFT",0,-3)
    f.dependencyCounts:SetPoint("TOPRIGHT",-2,-65)
    f.dependencyCounts:SetJustifyH("LEFT")
    f.dependencyCounts:SetTextColor(C("text"))
    f.dependencyCounts:Hide()
    f.dependency = f.dependencyCounts
    f.__guideReadable=guideReadable and true or false
    if f.__guideReadable then
        if f.EnableMouse then f:EnableMouse(true) end
        -- MaterialRow receives its own pointer hits for read-only tooltips.
        -- Explicitly route its wheel input to the parent Guide card scroller.
        if f.EnableMouseWheel then f:EnableMouseWheel(true) end
        f:SetScript("OnMouseWheel",function(_,delta)
            local area=parent and parent.__jlpScrollArea
            if area and area.ScrollWheel then area:ScrollWheel(delta) end
        end)
        f:SetScript("OnEnter",function(self)
            if not self.__material or not GameTooltip then return end
            local row=self.__material
            local anchor=JLP.UILayout and JLP.UILayout:TooltipAnchorFor(self,UIParent,340) or "ANCHOR_CURSOR"
            if GameTooltip.SetOwner then GameTooltip:SetOwner(self,anchor) end
            if GameTooltip.ClearLines then GameTooltip:ClearLines() end
            if GameTooltip.SetText then GameTooltip:SetText(safe(row.name or "Material")) end
            local source=SOURCE_LABELS[row.source] or safe(row.source or "Source unavailable")
            if GameTooltip.AddLine then
                GameTooltip:AddLine("Source: "..source,0.65,0.82,0.98,true)
                if row.availability then
                    local a=row.availability
                    GameTooltip:AddLine("Required "..tostring(a.required).." | Bags "..tostring(a.bags or "unknown")..
                        " | Bank "..tostring(a.bank or "unknown").." | External "..tostring(a.needed or "unverified"),1,1,1,true)
                    GameTooltip:AddLine("Source "..tostring(a.sourceStatus or "UNVERIFIED")..
                        " | Freshness "..tostring(a.sourceFreshness or "UNKNOWN")..
                        " | Confidence "..tostring(a.sourceConfidence or "UNVERIFIED"),0.65,0.82,0.98,true)
                    GameTooltip:AddLine("Next (manual): "..tostring(a.nextManualAction or "Review materials"),1,0.85,0.55,true)
                else
                    GameTooltip:AddLine(string.format("Need %d  |  Owned %d  |  Missing %d",tonumber(row.required) or 0,tonumber(row.owned) or tonumber(row.storage and row.storage.total) or 0,tonumber(row.missing) or 0),1,1,1,true)
                end
                if row.craftedFrom then GameTooltip:AddLine("Crafted from: "..safe(row.craftedFrom.name or "Unknown"),0.4,0.9,1,true) end
            end
            if GameTooltip.Show then GameTooltip:Show() end
        end)
        f:SetScript("OnLeave",function(self)
            if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self)
            elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
        end)
    end
    f.extra1 = W():Label(f,"","GameFontHighlightSmall")
    f.extra1:SetPoint("TOPLEFT",f.itemIcon,"BOTTOMLEFT",0,-10)
    f.extra1:SetPoint("TOPRIGHT",-2,-62)
    f.extra1:SetJustifyH("LEFT")
    f.extra1:SetTextColor(C("muted"))
    f.extra2 = W():Label(f,"","GameFontHighlight")
    f.extra2:SetPoint("TOPLEFT",f.extra1,"BOTTOMLEFT",0,-6)
    f.extra2:SetPoint("TOPRIGHT",-2,-88)
    f.extra2:SetJustifyH("LEFT")
    f.extra2:SetTextColor(C("cyan"))
    f.extra3 = W():Label(f,"","GameFontHighlightSmall")
    f.extra3:SetPoint("TOPLEFT",f.extra2,"BOTTOMLEFT",0,-4)
    f.extra3:SetPoint("TOPRIGHT",-2,-110)
    f.extra3:SetJustifyH("LEFT")
    f.extra3:SetTextColor(C("text"))
    if not detailed then f.extra1:Hide(); f.extra2:Hide(); f.extra3:Hide() end
    function f:SetMaterial(row)
        row = row or {}
        self.__material=self.__guideReadable and row or nil
        local storage = row.storage or {}
        self.itemIcon:SetItem(row.itemID, row.name)
        self.name:SetText(row.name or "Material")
        self.source:SetText("["..(SOURCE_LABELS[row.source] or safe(row.source or "Source")).."]")
        local required = tonumber(row.required) or 0
        local owned = tonumber(row.owned) or tonumber(storage.total) or 0
        local missing = tonumber(row.missing) or math.max(0, required-owned)
        local availability=row.availability
        if availability then
            local bags=availability.unknownBags and "unknown" or tostring(availability.bags)
            local bank=availability.unknownBank and "unknown" or tostring(availability.bank)
            local external=availability.needed==nil and "unverified" or tostring(availability.needed)
            self.summary:SetText("Required "..required.." | Bags "..bags.." | Bank "..bank.." | External "..external)
            self.summary:SetTextColor(C((availability.unknownBags or availability.unknownBank) and "warn" or "text"))
        else
            self.summary:SetText(string.format("Need: %d    Owned: %d    Missing: %d", required, owned, missing))
            self.summary:SetTextColor(C("text"))
        end
        if detailed then
            self.dependencyName:Hide(); self.dependencyCounts:Hide()
            self.extra1:Show(); self.extra2:Show(); self.extra3:Show()
            self.extra1:SetHeight(availability and 36 or 18)
            self.extra1:SetText(availability and ("Source: "..tostring(availability.sourceStatus or "UNVERIFIED")..
                " | Freshness: "..tostring(availability.sourceFreshness or "UNKNOWN")..
                "\nNext (manual): "..tostring(availability.nextManualAction or "Review materials")) or
                string.format("Storage    Bags: %d    Bank: %d", tonumber(storage.bags) or 0, tonumber(storage.bank) or 0))
            if row.craftedFrom then
                local raw = row.craftedFrom
                local rawStorage = raw.storage or {}
                self.extra2:SetText(safe(raw.name or ("Item "..tostring(raw.itemID or "?"))))
                self.extra2:SetTextColor(C("cyan"))
                self.extra3:SetText(string.format("Need: %d    Owned: %d    Missing: %d    |    Bags: %d    Bank: %d", tonumber(raw.required) or 0, tonumber(raw.owned) or 0, tonumber(raw.missing) or 0, tonumber(rawStorage.bags) or 0, tonumber(rawStorage.bank) or 0))
                self.extra3:SetTextColor(C("text"))
            else
                self.extra2:SetText("")
                self.extra3:SetText("")
            end
        else
            self.extra1:Hide(); self.extra2:Hide(); self.extra3:Hide()
            if row.craftedFrom then
                local raw = row.craftedFrom
                self.dependencyName:Show(); self.dependencyCounts:Show()
                self.dependencyName:SetText(safe(raw.name or ("Item "..tostring(raw.itemID or "?"))))
                self.dependencyCounts:SetText(string.format("Need: %d    Owned: %d    Missing: %d", tonumber(raw.required) or 0, tonumber(raw.owned) or 0, tonumber(raw.missing) or 0))
                self.dependencyCounts:SetTextColor(C("text"))
                self:SetHeight(108); self.__layoutHeight=108
            else
                self.dependencyName:Hide(); self.dependencyCounts:Hide(); self.dependencyName:SetText(""); self.dependencyCounts:SetText("")
                self:SetHeight(76); self.__layoutHeight=76
            end
        end
        if self.__guideReadable and JLP.UILayout and JLP.UILayout.GuideMaterialRowMetrics then
            local raw=row.craftedFrom
            local metrics=JLP.UILayout:GuideMaterialRowMetrics(self.GetWidth and self:GetWidth() or width or 430,row.name,raw and raw.name,detailed,
                self.name.GetStringHeight and self.name:GetStringHeight() or nil,
                raw and self.dependencyName.GetStringHeight and self.dependencyName:GetStringHeight() or nil)
            self.name:SetHeight(metrics.titleHeight)
            -- Re-anchor labels to the previous measured line, never to the old
            -- fixed card TOPRIGHT y-offset. This prevents contradictory top
            -- anchors when a locale creates two or more title lines.
            local function flow(label,above,gap,leftOffset)
                label:ClearAllPoints()
                label:SetPoint("TOPLEFT",above,"BOTTOMLEFT",leftOffset or 0,-gap)
                label:SetPoint("RIGHT",self,"RIGHT",-2,0)
            end
            flow(self.summary,self.name,8,0)
            flow(self.dependencyName,self.summary,5,0)
            flow(self.dependencyCounts,self.dependencyName,3,0)
            if raw and not detailed then self.dependencyName:SetHeight(metrics.dependencyHeight) end
            if detailed then
                self.extra1:ClearAllPoints()
                self.extra1:SetPoint("TOPLEFT",self.summary,"BOTTOMLEFT",-54,-8)
                self.extra1:SetPoint("RIGHT",self,"RIGHT",-2,0)
                -- Crafted-from appears in extra2 on the detailed card. Its
                -- wrapped label must push extra3 down, not overlap the counts.
                self.extra2:ClearAllPoints()
                self.extra2:SetPoint("TOPLEFT",self.extra1,"BOTTOMLEFT",0,-6)
                self.extra2:SetPoint("RIGHT",self,"RIGHT",-2,0)
                self.extra2:SetHeight(raw and metrics.dependencyHeight or 18)
                self.extra3:ClearAllPoints()
                self.extra3:SetPoint("TOPLEFT",self.extra2,"BOTTOMLEFT",0,-4)
                self.extra3:SetPoint("RIGHT",self,"RIGHT",-2,0)
            end
            -- A second advisory line needs real scroll height; it must not
            -- overlap the following item row at narrow Guide viewports.
            local advisoryHeight=(detailed and availability) and 18 or 0
            self:SetHeight(metrics.height+advisoryHeight)
            self.__layoutHeight=metrics.height+advisoryHeight
            self.__readabilityMetrics=metrics
        end
    end
    return f
end

function Components:RequirementRow(parent, width)
    local f=CreateFrame("Frame",nil,parent)
    f:SetSize(width or 420,132)
    f.__layoutHeight=132
    f.itemIcon=self:Icon(f,42); f.itemIcon:SetPoint("TOPLEFT",0,0)
    f.title=W():Label(f,"","GameFontNormalLarge"); f.title:SetPoint("TOPLEFT",f.itemIcon,"TOPRIGHT",10,-1); f.title:SetJustifyH("LEFT"); f.title:SetTextColor(C("cyan"))
    f.tag=W():Label(f,"","GameFontHighlight"); f.tag:SetPoint("TOPRIGHT",-2,-1); f.tag:SetWidth(118); f.tag:SetJustifyH("RIGHT"); f.tag:SetTextColor(C("text"))
    f.title:SetPoint("RIGHT",f.tag,"LEFT",-10,0)
    f.counts=W():Label(f,"","GameFontHighlight"); f.counts:SetPoint("TOPLEFT",f.title,"BOTTOMLEFT",0,-8); f.counts:SetPoint("TOPRIGHT",-2,-29); f.counts:SetJustifyH("LEFT"); f.counts:SetTextColor(C("text"))
    f.options=W():Label(f,"","GameFontHighlightSmall"); f.options:SetPoint("TOPLEFT",f.counts,"BOTTOMLEFT",0,-4); f.options:SetPoint("TOPRIGHT",-2,-47); f.options:SetJustifyH("LEFT"); f.options:SetTextColor(C("muted"))
    f.rawName=W():Label(f,"","GameFontHighlight"); f.rawName:SetPoint("TOPLEFT",f.options,"BOTTOMLEFT",0,-7); f.rawName:SetPoint("TOPRIGHT",-2,-71); f.rawName:SetJustifyH("LEFT"); f.rawName:SetTextColor(C("cyan")); f.rawName:Hide()
    f.raw=W():Label(f,"","GameFontHighlightSmall"); f.raw:SetPoint("TOPLEFT",f.rawName,"BOTTOMLEFT",0,-3); f.raw:SetPoint("TOPRIGHT",-2,-89); f.raw:SetJustifyH("LEFT"); f.raw:SetTextColor(C("text")); f.raw:Hide()
    f.rawOptions=W():Label(f,"","GameFontHighlightSmall"); f.rawOptions:SetPoint("TOPLEFT",f.raw,"BOTTOMLEFT",0,-4); f.rawOptions:SetPoint("TOPRIGHT",-2,-107); f.rawOptions:SetJustifyH("LEFT"); f.rawOptions:SetTextColor(C("muted")); f.rawOptions:Hide()
    function f:SetRequirement(row)
        row=row or {}
        self.itemIcon:SetItem(row.itemID,row.name)
        self.title:SetText(tostring(row.name or "Material"))
        self.title:SetTextColor(C((tonumber(row.missing) or 0)>0 and "cyan" or "good"))
        self.tag:SetText("["..(SOURCE_LABELS[row.source] or safe(row.source or "Source")).."]")
        local required=tonumber(row.required) or 0
        local owned=tonumber(row.owned) or 0
        local missing=tonumber(row.missing) or 0
        self.counts:SetText(string.format("Need: %d    Owned: %d    Missing: %d",required,owned,missing))
        self.counts:SetTextColor(C("text"))
        self.options:SetText("Get: "..tostring(row.optionsText ~= "" and row.optionsText or "Source unavailable"))
        if row.raw then
            self.rawName:Show(); self.raw:Show(); self.rawOptions:Show()
            self.rawName:SetText(tostring(row.raw.name or "Raw material"))
            self.raw:SetText(string.format("Need: %d    Owned: %d    Missing: %d",tonumber(row.raw.required) or 0,tonumber(row.raw.owned) or 0,tonumber(row.raw.missing) or 0))
            self.raw:SetTextColor(C("text"))
            self.rawOptions:SetText("Get: "..tostring(row.raw.optionsText ~= "" and row.raw.optionsText or "Source unavailable"))
            self:SetHeight(132); self.__layoutHeight=132
        else
            self.rawName:Hide(); self.raw:Hide(); self.rawOptions:Hide(); self.rawName:SetText(""); self.raw:SetText(""); self.rawOptions:SetText("")
            self:SetHeight(76); self.__layoutHeight=76
        end
    end
    return f
end

function Components:MetricTile(parent, width, height)
    local f = CreateFrame("Frame",nil,parent)
    f:SetSize(width or 220,height or 105)
    f.icon=f:CreateTexture(nil,"ARTWORK")
    f.icon:SetSize(30,30)
    f.icon:SetPoint("TOP",0,-10)
    f.label=W():Label(f,"","GameFontHighlight")
    f.label:SetPoint("TOP",f.icon,"BOTTOM",0,-8)
    f.label:SetPoint("LEFT",4,0); f.label:SetPoint("RIGHT",-4,0)
    f.label:SetJustifyH("CENTER")
    f.label:SetTextColor(C("muted"))
    f.value=W():Label(f,"","GameFontNormalLarge")
    f.value:SetPoint("TOP",f.label,"BOTTOM",0,-8)
    f.value:SetPoint("LEFT",4,0); f.value:SetPoint("RIGHT",-4,0)
    f.value:SetJustifyH("CENTER")
    function f:SetMetric(iconKey,label,value,tone)
        self.icon:SetTexture(JLP.UIIconResolver:GetSemantic(iconKey or "info"))
        self.label:SetText(label or "")
        self.value:SetText(value or "")
        self.value:SetTextColor(C(tone or "text"))
    end
    return f
end

function Components:TextBlock(parent, width, height)
    local f=CreateFrame("Frame",nil,parent)
    f:SetSize(width or 420,height or 82)
    f.icon=f:CreateTexture(nil,"ARTWORK")
    f.icon:SetSize(32,32)
    f.icon:SetPoint("TOPLEFT",0,-2)
    f.title=W():Label(f,"","GameFontNormal")
    f.title:SetPoint("TOPLEFT",f.icon,"TOPRIGHT",12,0)
    f.title:SetPoint("TOPRIGHT",-2,0)
    f.title:SetTextColor(C("gold"))
    f.body=W():Body(f)
    f.body:SetPoint("TOPLEFT",f.title,"BOTTOMLEFT",0,-6)
    f.body:SetPoint("BOTTOMRIGHT",-2,0)
    function f:SetBlock(iconKey,title,body,titleTone)
        self.icon:SetTexture(JLP.UIIconResolver:GetSemantic(iconKey or "info"))
        self.title:SetText(title or "")
        self.title:SetTextColor(C(titleTone or "gold"))
        self.body:SetText(body or "")
    end
    return f
end

function Components:NoticeRow(parent, width, height)
    local f=CreateFrame("Frame",nil,parent)
    f:SetSize(width or 300,height or 54)
    f.icon=f:CreateTexture(nil,"ARTWORK")
    f.icon:SetSize(28,28)
    f.icon:SetPoint("TOPLEFT",0,-2)
    f.body=W():Body(f)
    f.body:SetPoint("TOPLEFT",f.icon,"TOPRIGHT",12,0)
    f.body:SetPoint("BOTTOMRIGHT",-2,0)
    function f:SetNotice(iconKey, body, tone)
        self.icon:SetTexture(JLP.UIIconResolver:GetSemantic(iconKey or "info"))
        self.body:SetText(body or "")
        self.body:SetTextColor(C(tone or "text"))
    end
    return f
end

function Components:ShoppingRow(parent, width)
    local f=CreateFrame("Frame",nil,parent)
    f:SetSize(width or 500,38)
    f.index=W():Label(f,"","GameFontHighlightSmall"); f.index:SetPoint("LEFT",0,0); f.index:SetWidth(20)
    f.icon=self:Icon(f,24); f.icon:SetPoint("LEFT",24,0)
    f.item=W():Label(f,"","GameFontHighlight"); f.item:SetPoint("LEFT",54,0); f.item:SetWidth(110); f.item:SetTextColor(C("cyan"))
    f.unit=W():Label(f,"","GameFontHighlightSmall"); f.unit:SetPoint("LEFT",170,0); f.unit:SetWidth(76); f.unit:SetJustifyH("LEFT")
    f.total=W():Label(f,"","GameFontHighlightSmall"); f.total:SetPoint("LEFT",250,0); f.total:SetWidth(80); f.total:SetJustifyH("LEFT")
    f.owned=W():Label(f,"","GameFontHighlightSmall"); f.owned:SetPoint("LEFT",334,0); f.owned:SetWidth(42); f.owned:SetJustifyH("CENTER")
    f.bags=W():Label(f,"","GameFontHighlightSmall"); f.bags:SetPoint("LEFT",378,0); f.bags:SetWidth(42); f.bags:SetJustifyH("CENTER")
    f.bank=W():Label(f,"","GameFontHighlightSmall"); f.bank:SetPoint("LEFT",422,0); f.bank:SetWidth(42); f.bank:SetJustifyH("CENTER")
    function f:SetCompactLayout(compact,width)
        self.__compact=compact==true
        local function position(region,x,y,w)
            region:ClearAllPoints()
            region:SetPoint(self.__compact and "TOPLEFT" or "LEFT",self,
                self.__compact and "TOPLEFT" or "LEFT",x,y)
            region:SetWidth(w)
        end
        if self.__compact then
            self:SetHeight(82)
            position(self.index,0,-11,18)
            self.icon:ClearAllPoints();self.icon:SetPoint("TOPLEFT",self,"TOPLEFT",22,-5)
            position(self.item,54,-5,math.max(60,(width or 330)-60))
            position(self.unit,54,-32,100)
            position(self.total,168,-32,math.max(80,(width or 330)-172))
            position(self.owned,54,-57,80)
            position(self.bags,138,-57,75)
            position(self.bank,218,-57,math.max(55,(width or 330)-220))
            for _,label in ipairs({self.owned,self.bags,self.bank}) do label:SetJustifyH("LEFT") end
        else
            self:SetHeight(38)
            position(self.index,0,0,20)
            self.icon:ClearAllPoints();self.icon:SetPoint("LEFT",self,"LEFT",24,0)
            position(self.item,54,0,110)
            position(self.unit,170,0,76)
            position(self.total,250,0,80)
            position(self.owned,334,0,42)
            position(self.bags,378,0,42)
            position(self.bank,422,0,42)
            for _,label in ipairs({self.owned,self.bags,self.bank}) do label:SetJustifyH("CENTER") end
        end
        if self.__lastShopping then
            self:SetShopping(self.__lastIndex,self.__lastShopping,self.__lastMoney)
        end
    end
    function f:SetShopping(index,row,moneyFn)
        row=row or {}; local storage=row.storage or {}
        self.__lastIndex=index;self.__lastShopping=row;self.__lastMoney=moneyFn
        self.index:SetText(tostring(index or ""))
        self.icon:SetItem(row.itemID,row.name)
        self.item:SetText(row.name or "Item")
        local missing=math.max(1,tonumber(row.missing) or 1)
        local unit=row.unitPrice or (row.quote and row.quote.cost and ((tonumber(row.quote.cost) or 0)/missing)) or 0
        self.unit:SetText(moneyFn and moneyFn(unit) or tostring(unit))
        self.total:SetText(row.complete and (moneyFn and moneyFn(row.cost or 0) or tostring(row.cost or 0)) or (row.note or "Unpriced"))
        local compact=self.__compact==true
        self.owned:SetText((compact and "Own " or "")..tostring(row.owned or storage.total or 0))
        self.bags:SetText((compact and "Bags " or "")..tostring(storage.bags or 0))
        self.bank:SetText((compact and "Bank " or "")..tostring(storage.bank or 0))
        self.total:SetTextColor(C(row.complete and "good" or "warn"))
    end
    return f
end

function Components:BankSlot(parent, size)
    local f=CreateFrame("Button",nil,parent)
    size=size or 50
    f:SetSize(size,size)
    local bg=f:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.004,0.016,0.026,0.96)
    f.background=bg
    local icon=f:CreateTexture(nil,"ARTWORK")
    icon:SetPoint("TOPLEFT",3,-3); icon:SetPoint("BOTTOMRIGHT",-3,3)
    icon:SetTexture(JLP.UIIconResolver:GetSemantic("bag")); icon:SetAlpha(0.16)
    f.icon=icon
    local count=W():Label(f,"","GameFontHighlight")
    count:SetPoint("BOTTOMRIGHT",-3,3); count:SetJustifyH("RIGHT")
    f.count=count
    W():Border(f,"border",1)
    local function applyBorder(self,quality)
        local r,g,b,a=C("border")
        if ITEM_QUALITY_COLORS and quality ~= nil and ITEM_QUALITY_COLORS[tonumber(quality)] then
            local q=ITEM_QUALITY_COLORS[tonumber(quality)]
            r,g,b,a=q.r or r,q.g or g,q.b or b,1
        end
        for _,edge in pairs(self.__jlpBorder or {}) do edge:SetVertexColor(r,g,b,a or 1) end
    end
    function f:SetSlot(row)
        row=row or {}
        self.itemID=tonumber(row.itemID)
        self.itemName=row.name
        self.quantity=tonumber(row.count) or 0
        if self.itemID then
            local cache=JLP.GetModule and JLP:GetModule("KnowledgeCache") or nil
            local meta=cache and cache.ResolveItem and cache:ResolveItem(self.itemID,row.name) or nil
            self.itemName=(meta and meta.name) or row.name
            self.icon:SetTexture(validItemIcon(meta and meta.icon) or JLP.UIIconResolver:GetItem(self.itemID,self.itemName))
            self.icon:SetAlpha(1)
            self.count:SetText(self.quantity>1 and tostring(self.quantity) or "")
            applyBorder(self,meta and meta.quality)
            self.__jlpMouseIntent=true
            local through=JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough
            self:EnableMouse(not through)
        else
            self.icon:SetTexture(JLP.UIIconResolver:GetSemantic("bag")); self.icon:SetAlpha(0.12)
            self.count:SetText("")
            applyBorder(self,nil)
            self.__jlpMouseIntent=false
            self:EnableMouse(false)
        end
    end
    f:SetScript("OnEnter",function(self)
        if self.itemID and JLP.UIInteraction then JLP.UIInteraction:ShowItem(self,self.itemID,self.itemName) end
    end)
    f:SetScript("OnLeave",function(self) if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self) end end)
    f:SetScript("OnMouseUp",function(self,button)
        if not self.itemID or not JLP.UIInteraction then return end
        local ok,message=JLP.UIInteraction:HandleItemClick(self.itemID,self.itemName,button)
        if not ok and message and JLP.UIInteraction:IsAuctionHouseOpen() and JLP.Print then JLP:Print(message) end
    end)
    return f
end

JLP.UIComponents=Components
