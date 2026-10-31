
local _, JLP = ...
local JT = JLP._integratedTom
JT.themeAsset = "Interface\\AddOns\\JuztLevelProfessions\\Assets\\"

function JT:ThemeAssetPath(rel)
    return self.themeAsset .. tostring(rel or "")
end

function JT:SkinThemePanel(frame, variant)
    if not frame then return end
    variant = variant == "secondary" and "card_secondary" or "card_primary"
    frame.__jtThemePanels = frame.__jtThemePanels or {}
    if frame.__jtThemePanels[variant] then
        for key,tex in pairs(frame.__jtThemePanels) do
            if type(tex)=="table" then
                for _,t in pairs(tex) do if t and t.SetShown then t:SetShown(key==variant) end end
            end
        end
        frame.__jtThemeVariant = variant
        return frame.__jtThemePanels[variant]
    end
    local root = self:ThemeAssetPath(variant .. "\\")
    local corner = 28
    local layer = "BACKGROUND"
    local set = {}
    local function tex(key, file)
        local t = frame:CreateTexture(nil, layer)
        t:SetTexture(root .. file)
        set[key]=t
        return t
    end
    local tl=tex("tl","top_left.tga"); tl:SetPoint("TOPLEFT",0,0); tl:SetSize(corner,corner)
    local tr=tex("tr","top_right.tga"); tr:SetPoint("TOPRIGHT",0,0); tr:SetSize(corner,corner)
    local bl=tex("bl","bottom_left.tga"); bl:SetPoint("BOTTOMLEFT",0,0); bl:SetSize(corner,corner)
    local br=tex("br","bottom_right.tga"); br:SetPoint("BOTTOMRIGHT",0,0); br:SetSize(corner,corner)
    local top=tex("top","top_edge.tga"); top:SetPoint("TOPLEFT",tl,"TOPRIGHT",0,0); top:SetPoint("TOPRIGHT",tr,"TOPLEFT",0,0); top:SetHeight(corner)
    local bottom=tex("bottom","bottom_edge.tga"); bottom:SetPoint("BOTTOMLEFT",bl,"BOTTOMRIGHT",0,0); bottom:SetPoint("BOTTOMRIGHT",br,"BOTTOMLEFT",0,0); bottom:SetHeight(corner)
    local left=tex("left","left_edge.tga"); left:SetPoint("TOPLEFT",tl,"BOTTOMLEFT",0,0); left:SetPoint("BOTTOMLEFT",bl,"TOPLEFT",0,0); left:SetWidth(corner)
    local right=tex("right","right_edge.tga"); right:SetPoint("TOPRIGHT",tr,"BOTTOMRIGHT",0,0); right:SetPoint("BOTTOMRIGHT",br,"TOPRIGHT",0,0); right:SetWidth(corner)
    local center=tex("center","center_fill.tga"); center:SetPoint("TOPLEFT",tl,"BOTTOMRIGHT",0,0); center:SetPoint("BOTTOMRIGHT",br,"TOPLEFT",0,0)
    frame.__jtThemePanels[variant]=set
    for key,texset in pairs(frame.__jtThemePanels) do
        if key ~= variant and type(texset)=="table" then
            for _,t in pairs(texset) do if t and t.SetShown then t:SetShown(false) end end
        end
    end
    frame.__jtThemeVariant = variant
    return set
end

function JT:AccentLine(parent, anchorA, anchorB, yoff)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.31,0.48,0.61,0.55)
    line:SetPoint("TOPLEFT", parent, anchorA or "TOPLEFT", 22, yoff or -45)
    line:SetPoint("TOPRIGHT", parent, anchorB or "TOPRIGHT", -22, yoff or -45)
    line:SetHeight(1)
    return line
end

function JT:StyleThemeButton(button, caption, opts)
    if not button then return end
    opts = type(opts)=="table" and opts or {}
    button.__jtThemeButton = true
    local bg = button.background or button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(button)
    bg:SetTexture(self:ThemeAssetPath("buttons\\medium_blank.tga"))
    button.background = bg

    local hover = button.hover or button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(button)
    hover:SetTexture(self:ThemeAssetPath("buttons\\medium_blank_active_green.tga"))
    hover:SetAlpha(0)
    button.hover = hover

    local active = button.activeBackdrop or button:CreateTexture(nil, "ARTWORK")
    active:SetAllPoints(button)
    active:SetTexture(self:ThemeAssetPath("buttons\\medium_blank_active_green.tga"))
    active:SetAlpha(0)
    button.activeBackdrop = active

    local captionTemplate=opts.font or "GameFontHighlightSmall"
    local captionFS = button.caption or button:CreateFontString(nil,"OVERLAY",captionTemplate)
    if captionTemplate=="GameFontHighlightSmall" or captionTemplate=="GameFontNormalSmall" then
        local face,size,flags=captionFS:GetFont()
        if face and (not size or size<14) then captionFS:SetFont(face,14,flags or "") end
    end
    captionFS:SetPoint("LEFT", button, "LEFT", opts.leftPad or 14, 0)
    captionFS:SetPoint("RIGHT", button, "RIGHT", opts.rightPad or -14, 0)
    captionFS:SetJustifyH(opts.justify or "CENTER")
    captionFS:SetTextColor(0.91,0.95,0.98,1)
    captionFS:SetText(caption or "")
    button.caption = captionFS

    button.__jtThemeActive = button.__jtThemeActive or false
    function button:SetThemeActiveState(value)
        self.__jtThemeActive = value and true or false
        self.activeBackdrop:SetAlpha(self.__jtThemeActive and 1 or 0)
        self.background:SetTexture(JT:ThemeAssetPath(self.__jtThemeActive and "buttons\\medium_blank_active_green.tga" or "buttons\\medium_blank.tga"))
        self.caption:SetTextColor(self.__jtThemeActive and 1 or 0.91, self.__jtThemeActive and 0.83 or 0.95, self.__jtThemeActive and 0.58 or 0.98, 1)
    end
    button:SetScript("OnEnter", function(self)
        if not self.__jtThemeActive then self.hover:SetAlpha(0.18) end
    end)
    button:SetScript("OnLeave", function(self)
        if not self.__jtThemeActive then self.hover:SetAlpha(0) end
    end)
    button:SetThemeActiveState(button.__jtThemeActive)
    if opts.onClick then button:SetScript("OnClick", opts.onClick) end
    return button
end

function JT:CreateThemeButton(parent, caption, width, height, onClick, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 150, height or 32)
    self:StyleThemeButton(b, caption, opts or {onClick=onClick})
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end


-- Source reference: JuztLevelProfessions/UI/MainWindow.lua and UI/Widgets.lua,
-- delivery 0.31.0-alpha290. These assets are bundled locally; no runtime
-- dependency on JuztLevel, and no calls into JuztLevel UI state.
function JT:SkinThemeImage(parent, path, layer)
    local t=parent:CreateTexture(nil,layer or "BACKGROUND")
    t:SetAllPoints(parent)
    t:SetTexture(self:ThemeAssetPath(path))
    return t
end

function JT:SkinNavigationTab(button,iconPath)
    local base=button:CreateTexture(nil,"BACKGROUND")
    base:SetAllPoints(button)
    base:SetTexture("Interface\\Buttons\\WHITE8X8")
    base:SetVertexColor(0.004,0.020,0.034,0.50)
    local focus=button:CreateTexture(nil,"BORDER")
    focus:SetAllPoints(button)
    focus:SetTexture("Interface\\Buttons\\WHITE8X8")
    focus:SetVertexColor(0.04,0.36,0.56,0)
    local icon=button:CreateTexture(nil,"ARTWORK")
    icon:SetTexture(self:ThemeAssetPath(iconPath))
    icon:SetSize(34,34)
    icon:SetPoint("LEFT",button,"LEFT",15,0)
    local caption=button:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    caption:SetPoint("LEFT",icon,"RIGHT",12,0)
    caption:SetPoint("RIGHT",button,"RIGHT",-9,0)
    caption:SetJustifyH("LEFT")
    caption:SetTextColor(0.96,0.97,1,1)
    button.caption=caption
    button.icon=icon
    button.navFocus=focus
    button.__jtThemeActive=false
    function button:SetThemeActiveState(active)
        self.__jtThemeActive=active and true or false
        self.navFocus:SetVertexColor(0.04,0.36,0.56,self.__jtThemeActive and 0.68 or 0)
        self.caption:SetTextColor(self.__jtThemeActive and 1 or 0.96,
            self.__jtThemeActive and 0.67 or 0.97,
            self.__jtThemeActive and 0.10 or 1,1)
        if self.icon.SetDesaturated then self.icon:SetDesaturated(not self.__jtThemeActive) end
    end
    button:SetScript("OnEnter",function(self)
        if not self.__jtThemeActive then self.navFocus:SetVertexColor(0.04,0.32,0.50,0.30) end
    end)
    button:SetScript("OnLeave",function(self)
        if not self.__jtThemeActive then self.navFocus:SetVertexColor(0.04,0.36,0.56,0) end
    end)
    return button
end

function JT:SkinThemeCloseButton(button)
    local art=button:CreateTexture(nil,"ARTWORK")
    art:SetAllPoints(button)
    art:SetTexture(self:ThemeAssetPath("window\\close.tga"))
    local hi=button:CreateTexture(nil,"HIGHLIGHT")
    hi:SetAllPoints(button)
    hi:SetTexture(self:ThemeAssetPath("window\\close.tga"))
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.32)
    return art
end
