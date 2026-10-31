local _, JLP = ...
local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end
local MainWindow={}

local function playerIdentity()
    local name=type(UnitName)=="function" and UnitName("player") or "Player"
    local level=type(UnitLevel)=="function" and UnitLevel("player") or 0
    return string.format("%s  -  Level %s",tostring(name or "Player"),tostring(level or 0))
end


local function clamp(value, low, high)
    value=tonumber(value) or low
    if value<low then return low end
    if value>high then return high end
    return value
end

local function transparencyPercent(alpha)
    return math.floor(((1-clamp(alpha,0.20,1.0))*100)+0.5)
end

function MainWindow:ApplyOpacity(alpha)
    if not self.frame then return end
    alpha=clamp(alpha,0.20,1.0)
    if self.frame.SetAlpha then self.frame:SetAlpha(alpha) end
    if self.frame.opacityValue then
        self.frame.opacityValue:SetText(string.format("Transparency: %d%%",transparencyPercent(alpha)))
    end
    if self.frame.opacitySlider and self.frame.opacitySlider.GetValue then
        local current=self.frame.opacitySlider:GetValue()
        if math.abs((tonumber(current) or 0)-alpha)>0.001 and self.frame.opacitySlider.SetValue then
            self.frame.opacitySlider.__syncing=true
            self.frame.opacitySlider:SetValue(alpha)
            self.frame.opacitySlider.__syncing=false
        end
    end
end

local function mouseState(frame,exempt)
    if not frame.EnableMouse then return end
    if exempt then frame:EnableMouse(true)
    elseif frame.__jlpForceMouseDisabled then frame:EnableMouse(false)
    else
        if frame.__jlpMouseIntent==nil and frame.IsMouseEnabled then
            frame.__jlpMouseIntent=frame:IsMouseEnabled() and true or false
        end
        if not frame.IsMouseEnabled or frame:IsMouseEnabled() then frame:EnableMouse(false) end
    end
end
local function rememberMouse(pass,frame)
    if not frame or pass.seen[frame] then return end
    pass.seen[frame]=true
    pass.rows[#pass.rows+1]={frame=frame}
    mouseState(frame,pass.exemptions[frame])
end
local function readMouseChildren(pass,row)
    local frame=row.frame
    if not frame.GetChildren then return end
    local children={frame:GetChildren()}
    row.childCount=#children
    for _,child in ipairs(children) do rememberMouse(pass,child) end
end

-- WoW has no generic child-added event. Reconcile a bounded frontier only while
-- click-through is active. Counts alone cannot detect a same-count reparent.
-- Page refreshes can create/reparent children; this discovers them incrementally,
-- without a full-tree pass on every Apply call or every 0.2-second viewport tick.
function MainWindow:ReconcileClickThrough(budget)
    local pass=self._mousePass
    if not self._clickThroughActive or not pass then return 0 end
    local limit=math.min(32,math.max(1,math.floor(tonumber(budget) or 32)))
    local processed=0
    while processed<limit and #pass.rows>0 do
        if pass.cursor>#pass.rows then pass.cursor=1 end
        local row=pass.rows[pass.cursor];pass.cursor=pass.cursor+1
        local frame=row.frame
        mouseState(frame,pass.exemptions[frame])
        readMouseChildren(pass,row)
        processed=processed+1
    end
    return processed
end

function MainWindow:DeactivateActivePage(nextPage)
    if self.activePage=="Guide" and nextPage~="Guide" then
        local guide=JLP.UIPages and JLP.UIPages.Guide
        if guide and guide.Deactivate then guide:Deactivate() end
    end
    if self.activePage=="Secondaries" and nextPage~="Secondaries" then
        local secondaries=JLP.UIPages and JLP.UIPages.Secondaries
        if secondaries and secondaries.Deactivate then secondaries:Deactivate() end
        if JLP.UIWindowRegistry then JLP.UIWindowRegistry:CloseOwner("Secondaries") end
    end
end

function MainWindow:ApplyClickThrough(enabled)
    if not self.frame then return end
    enabled=enabled and true or false
    local frame=self.frame
    if self._clickThroughFrame==frame and self._clickThroughActive==enabled then return end
    -- UIParent-bound Guide popups are logically owned by this window. The
    -- mouse pass cannot descend into them, so close them before click-through.
    if enabled then
        local guide=JLP.UIPages and JLP.UIPages.Guide
        if guide and guide.Deactivate then guide:Deactivate() end
        local secondaries=JLP.UIPages and JLP.UIPages.Secondaries
        if secondaries and secondaries.Deactivate then secondaries:Deactivate() end
        if JLP.UIWindowRegistry then JLP.UIWindowRegistry:CloseOwner("Secondaries") end
    end
    local exemptions={}
    if frame.clickThroughButton then exemptions[frame.clickThroughButton]=true end
    if frame.opacitySlider then exemptions[frame.opacitySlider]=true end
    if enabled then
        local pass={rows={},seen={},exemptions=exemptions,cursor=1}
        rememberMouse(pass,frame)
        local i=1
        -- Iterative, visited-guarded traversal: a malformed/cyclic fixture cannot
        -- recurse forever. Only the false->true transition scans the whole tree.
        while i<=#pass.rows do readMouseChildren(pass,pass.rows[i]);i=i+1 end
        self._mousePass=pass
    else
        for _,row in ipairs(self._mousePass and self._mousePass.rows or {}) do
            local child=row.frame
            if child.EnableMouse then
                if child.__jlpForceMouseDisabled then child:EnableMouse(false)
                elseif child.__jlpMouseIntent~=nil then child:EnableMouse(child.__jlpMouseIntent) end
            end
            child.__jlpMouseIntent=nil
        end
        self._mousePass=nil
    end
    self._clickThroughFrame=frame;self._clickThroughActive=enabled
    if frame.clickThroughButton and frame.clickThroughButton.EnableMouse then frame.clickThroughButton:EnableMouse(true) end
    if frame.opacitySlider and frame.opacitySlider.EnableMouse then frame.opacitySlider:EnableMouse(true) end
    if frame.clickThroughButton then
        frame.clickThroughButton:SetText(enabled and "Click-through: ON" or "Click-through: OFF")
    end
end

function MainWindow:SetClickThrough(enabled)
    enabled=enabled and true or false
    if JLP.DB and JLP.DB.profile then JLP.DB.profile.clickThrough=enabled end
    self:ApplyClickThrough(enabled)
end

function MainWindow:ToggleClickThrough()
    local current=JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough
    self:SetClickThrough(not current)
end

local function workspace() return JLP:GetModule("ProfessionWorkspace") end

function MainWindow:FitToViewport()
 local f=self.frame
 local layout=JLP:GetModule("MainViewportLayout")
 if not f or not layout then return false,"LAYOUT_UNAVAILABLE" end
 local L=JLP.UITheme.layout
 local profile=JLP.DB and JLP.DB.profile
 local preferred=profile and profile.scale or 1
 local width=UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1600
 local height=UIParent and UIParent.GetHeight and UIParent:GetHeight() or 900
 local parentScale=UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
 local result=layout:Fit(width,height,preferred,L.width,L.height,L.minScale,L.maxScale)
 self.viewportSignature=layout:Signature(width,height,parentScale)
 self.lastViewportFit=result
 if not result.fits then return false,"VIEWPORT_TOO_SMALL" end
 if f.SetScale then f:SetScale(result.scale) end
 -- Automatic viewport refits must also update the scale label; the old label
 -- was only refreshed by the manual resize handle.
 if f.scaleLabel and f.scaleLabel.SetText then
     f.scaleLabel:SetText(string.format("%d%%",math.floor(result.scale*100+0.5)))
 end
 -- Preserve manually moved position across viewport signatures. The owner can
 -- still clamp to the resized display, and ResetUILayout explicitly recentres.
 if not self.__manuallyPositioned then
     if f.ClearAllPoints then f:ClearAllPoints() end
     if f.SetPoint then f:SetPoint("CENTER",UIParent,"CENTER",0,0) end
 end
 if f.SetClampedToScreen then f:SetClampedToScreen(true) end
 return true,result
end

function MainWindow:ResetUILayout()
 self.__manuallyPositioned=false
 local profile=JLP.DB and JLP.DB.profile
 if profile then profile.scale=1 end
 return self:FitToViewport()
end

function MainWindow:UpdateGuideSubmenuLabels()
    if not self.frame or not self.frame.guideSubButtons then return end
    local ws=workspace()
    local defs=ws and ws:GetGuideModes() or {{mode="onboarding",label="Learn a primary profession",kind="onboarding"}}
    local signatureParts={}
    for _,def in ipairs(defs) do
        signatureParts[#signatureParts+1]=tostring(def.mode).."="..tostring(def.label).."="..tostring(def.kind)
    end
    local signature=table.concat(signatureParts,"|")
    local changed=signature~=self.frame.guideSubSignature
    self.frame.guideSubSignature=signature
    self.frame.guideSubDefs=defs
    for i,b in ipairs(self.frame.guideSubButtons) do
        local def=defs[i]
        if def then
            b.mode=def.mode
            b.kind=def.kind
            b:SetText(def.label)
        else
            b.mode=nil
            b.kind=nil
            b:Hide()
        end
    end
    if self.frame.header and self.frame.header.subtitle then
        self.frame.header.subtitle:SetText(ws and ws:GetHeaderSubtitle() or "No primary professions learned")
    end
    return changed
end


function MainWindow:UpdateSecondarySubmenuLabels()
    if not self.frame then return end
    local service=JLP:GetModule("SecondaryWorkspace")
    local defs=service and service:GetMenuDefinitions() or {}
    self.frame.secondarySubDefs=defs
    for i,button in ipairs(self.frame.secondarySubButtons or {}) do
        local def=defs[i]
        button.secondaryMode=def and def.key or nil
        if def then button:SetText(def.label) else button:Hide() end
    end
end

function MainWindow:UpdateSecondarySubmenuState(mode)
    if not self.frame then return end
    for _,button in ipairs(self.frame.secondarySubButtons or {}) do
        button:SetActive(button.secondaryMode~=nil and button.secondaryMode==mode)
    end
    if self.frame.secondariesButton then
        self.frame.secondariesButton:SetActive(self.activePage=="Secondaries")
    end
end

function MainWindow:UpdateBankSubmenuLabels()
    if not self.frame then return false end
    local inventory=JLP:GetModule("Inventory")
    local characters=inventory and inventory:GetBankNavigationCharacters() or {}
    local signatureParts={}
    for _,row in ipairs(characters) do signatureParts[#signatureParts+1]=tostring(row.key or "").."="..tostring(row.label or "").."="..tostring(row.bankKnown) end
    local signature=table.concat(signatureParts,"|")
    local changed=signature~=self.frame.bankSubSignature
    self.frame.bankSubSignature=signature
    self.frame.bankSubButtons=self.frame.bankSubButtons or {}
    while #self.frame.bankSubButtons < #characters do
        local sub=JLP.UIWidgets:SubNavButton(self.frame.navContainer or self.frame.sidebar,"")
        sub:SetScript("OnClick",function(self) MainWindow:ShowBankCharacter(self.characterKey) end)
        self.frame.bankSubButtons[#self.frame.bankSubButtons+1]=sub
    end
    for i,b in ipairs(self.frame.bankSubButtons) do
        local row=characters[i]
        if row then
            b.characterKey=row.key
            b.bankKnown=row.bankKnown
            b:SetText(row.label or row.name or row.key)
        else
            b.characterKey=nil
            b:Hide()
        end
    end
    self.frame.bankSubDefs=characters
    if self.frame.bankEmptyHint then
        self.frame.bankEmptyHint:SetText("No other characters saved yet.\nLog into each alt and open its Bank once.")
    end
    return changed
end

function MainWindow:UpdateBankSubmenuState(characterKey)
    if not self.frame then return end
    for _,b in ipairs(self.frame.bankSubButtons or {}) do b:SetActive(b.characterKey~=nil and b.characterKey==characterKey) end
end

function MainWindow:LayoutSidebar(expandedGuide, expandedBank, expandedSecondaries)
    local frame=self.frame
    if not frame then return end
    local y=24
    local gap=10
    local mainHeight=62
    local subHeight=36
    local subGap=5

    for _,def in ipairs(JLP.UITheme.nav) do
        local b=frame.buttons[def.key]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT",12,-y)
        b:SetPoint("TOPRIGHT",-12,-y)
        b:SetHeight(mainHeight)
        y=y+mainHeight+gap

        if def.key=="Guide" then
            for _,sub in ipairs(frame.guideSubButtons or {}) do
                sub:ClearAllPoints()
                if expandedGuide and sub.mode then
                    sub:SetPoint("TOPLEFT",34,-y)
                    sub:SetPoint("TOPRIGHT",-14,-y)
                    sub:SetHeight(subHeight)
                    sub:Show()
                    y=y+subHeight+subGap
                else
                    sub:Hide()
                end
            end
            -- Full-width group row, same 36px height as a regular submenu.
            -- It belongs to the Guide hierarchy, below all primary submenus.
            local secondaries=frame.secondariesButton
            if secondaries then
                secondaries:ClearAllPoints()
                if expandedGuide then
                    secondaries:SetPoint("TOPLEFT",12,-y)
                    secondaries:SetPoint("TOPRIGHT",-12,-y)
                    secondaries:SetHeight(subHeight)
                    secondaries:Show()
                    y=y+subHeight+subGap
                else secondaries:Hide() end
            end
            for _,sub in ipairs(frame.secondarySubButtons or {}) do
                sub:ClearAllPoints()
                if expandedGuide and expandedSecondaries and sub.secondaryMode then
                    sub:SetPoint("TOPLEFT",34,-y)
                    sub:SetPoint("TOPRIGHT",-14,-y)
                    sub:SetHeight(subHeight)
                    sub:Show()
                    y=y+subHeight+subGap
                else sub:Hide() end
            end
            if expandedGuide then y=y+4 end
        elseif def.key=="Bank" then
            for _,sub in ipairs(frame.bankSubButtons or {}) do
                sub:ClearAllPoints()
                if expandedBank and sub.characterKey then
                    sub:SetPoint("TOPLEFT",34,-y)
                    sub:SetPoint("TOPRIGHT",-14,-y)
                    sub:SetHeight(subHeight)
                    sub:Show()
                    y=y+subHeight+subGap
                else
                    sub:Hide()
                end
            end
            if frame.bankEmptyHint then
                frame.bankEmptyHint:ClearAllPoints()
                if expandedBank and #(frame.bankSubDefs or {})==0 then
                    frame.bankEmptyHint:SetPoint("TOPLEFT",30,-y)
                    frame.bankEmptyHint:SetWidth(218)
                    frame.bankEmptyHint:SetHeight(58)
                    frame.bankEmptyHint:Show()
                    y=y+58
                else frame.bankEmptyHint:Hide() end
            end
            if expandedBank and #(frame.bankSubDefs or {})>0 then y=y+4 end
        end
    end
    if frame.navScroll and frame.navScroll.SetContentHeight then
        frame.navScroll:SetContentHeight(math.max(frame.navScroll.__layoutHeight or 1,y+8),true)
    end
end

function MainWindow:UpdateGuideSubmenuState(mode)
    if not self.frame then return end
    for _,b in ipairs(self.frame.guideSubButtons or {}) do
        b:SetActive(b.mode==mode)
    end
end

function MainWindow:Create()
    if self.frame then return self.frame end
    local W=JLP.UIWidgets
    local L=JLP.UITheme.layout

    local frame=CreateFrame("Frame","JuztLevelProfessionsMainWindow",UIParent)
    frame:SetSize(L.width,L.height)
    -- Escape registration and logical ownership use the common UI registry.
    if JLP.UIWindowRegistry then
        JLP.UIWindowRegistry:Register("MainWindow",frame)
        JLP.UIWindowRegistry:RegisterSpecial("JuztLevelProfessionsMainWindow")
    end
    frame:SetScript("OnShow",function()
        if JLP.DB and JLP.DB.profile then JLP.DB.profile.showWindow=true end
        MainWindow:FitToViewport()
    end)
    frame:SetScript("OnUpdate",function(_,elapsed)
        if not frame:IsShown() then return end
        MainWindow.viewportElapsed=(MainWindow.viewportElapsed or 0)+(tonumber(elapsed) or 0)
        if MainWindow.viewportElapsed<0.2 then return end
        MainWindow.viewportElapsed=0
        -- Reconcile widgets created or re-enabled after the first recursive
        -- pass. Normal mode is not polled; only the transient disabled state.
        if JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough then
            MainWindow:ApplyClickThrough(true)
            MainWindow:ReconcileClickThrough(32)
        end
        local layout=JLP:GetModule("MainViewportLayout")
        if not layout then return end
        local w=UIParent and UIParent.GetWidth and UIParent:GetWidth()
        local h=UIParent and UIParent.GetHeight and UIParent:GetHeight()
        local ui=UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
        if layout:Signature(w,h,ui)~=MainWindow.viewportSignature then MainWindow:FitToViewport() end
    end)
    frame:SetScript("OnHide",function()
        if JLP.UIWindowRegistry then
            JLP.UIWindowRegistry:CloseOwner("Guide")
            JLP.UIWindowRegistry:CloseOwner("Secondaries")
        end
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltipTree(frame) end
        MainWindow:DeactivateActivePage(nil)
        if frame.__jlpGatheringHandoff then return end
        -- A closed owner window cannot retain a hidden material Return action.
        MainWindow.advisoryReturn=nil
        MainWindow._materialReferenceEntering=nil
        if JLP.DB and JLP.DB.profile then JLP.DB.profile.showWindow=false end
    end)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        MainWindow.__manuallyPositioned=true
    end)

    local profile = JLP.DB and JLP.DB.profile
    local initialScale = profile and tonumber(profile.scale) or 1.0
    initialScale = math.max(L.minScale or 0.65, math.min(L.maxScale or 1.30, initialScale))
    if frame.SetScale then frame:SetScale(initialScale) end
    self.frame=frame
    self:FitToViewport()
    local initialOpacity=clamp(profile and profile.opacity or 1.0,0.20,1.0)
    if profile then profile.opacity=initialOpacity end
    if frame.SetAlpha then frame:SetAlpha(initialOpacity) end

    local shellBG = frame:CreateTexture(nil,"BACKGROUND")
    shellBG:SetAllPoints()
    shellBG:SetTexture(JLP.UITheme:Asset("layout\\main_background.tga"))
    frame.shellBackground = shellBG

    local header=CreateFrame("Frame",nil,frame)
    header:SetPoint("TOPLEFT",0,0)
    header:SetPoint("TOPRIGHT",0,0)
    header:SetHeight(L.headerHeight)
    local headerBG=header:CreateTexture(nil,"BACKGROUND")
    headerBG:SetAllPoints()
    headerBG:SetTexture(JLP.UITheme:Asset("layout\\header_background.tga"))
    header.background=headerBG
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart",function()
        local clickThrough=JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough
        if clickThrough then return end
        if frame.StartMoving then frame:StartMoving() end
    end)
    header:SetScript("OnDragStop",function()
        if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
        MainWindow.__manuallyPositioned=true
    end)

    local title=W:Label(header,"JuztLevel","GameFontNormalHuge")
    title:SetPoint("LEFT",34,12)
    if title.SetScale then title:SetScale(1.18) end
    local dash=W:Label(header,"-","GameFontNormalHuge")
    dash:SetPoint("LEFT",title,"RIGHT",14,0)
    if dash.SetScale then dash:SetScale(1.18) end
    dash:SetTextColor(JLP.UITheme:Color("gold"))
    local suffix=W:Label(header,"Professions","GameFontNormalHuge")
    suffix:SetPoint("LEFT",dash,"RIGHT",14,0)
    if suffix.SetScale then suffix:SetScale(1.18) end
    suffix:SetTextColor(JLP.UITheme:Color("gold"))
    local subtitle=W:Label(header,"No primary professions learned","GameFontHighlight")
    subtitle:SetPoint("TOPLEFT",title,"BOTTOMLEFT",2,-6)
    if subtitle.SetScale then subtitle:SetScale(1.12) end
    subtitle:SetTextColor(JLP.UITheme:Color("muted"))
    header.subtitle=subtitle

    local ident=W:Label(header,playerIdentity(),"GameFontHighlightLarge")
    ident:SetPoint("RIGHT",-92,0)
    ident:SetJustifyH("RIGHT")
    header.identity=ident

    local close=CreateFrame("Button",nil,header)
    close:SetSize(36,36)
    close:SetPoint("RIGHT",-24,2)
    local closeTex=close:CreateTexture(nil,"ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture(JLP.UITheme:Asset("window\\close.tga"))
    close:SetScript("OnClick",function()
        frame:Hide()
        if JLP.DB and JLP.DB.profile then JLP.DB.profile.showWindow = false end
    end)

    local scaleLabel=W:Label(header,"100%","GameFontHighlightSmall")
    -- Position the value in the gap between the close-button bottom and header bottom.
    scaleLabel:SetPoint("TOP",close,"BOTTOM",0,-8)
    scaleLabel:SetTextColor(JLP.UITheme:Color("muted"))
    local function updateScaleLabel(scale)
        local percent=math.floor(((tonumber(scale) or 1.0)*100)+0.5)
        scaleLabel:SetText(string.format("%d%%",percent))
    end
    updateScaleLabel(initialScale)
    header.scaleLabel=scaleLabel
    frame.scaleLabel=scaleLabel

    local sidebar=CreateFrame("Frame",nil,frame)
    sidebar:SetPoint("TOPLEFT",0,-L.headerHeight)
    sidebar:SetPoint("BOTTOMLEFT",0,0)
    sidebar:SetWidth(L.sidebarWidth)
    local sidebarBG=sidebar:CreateTexture(nil,"BACKGROUND")
    sidebarBG:SetAllPoints()
    sidebarBG:SetTexture(JLP.UITheme:Asset("layout\\sidebar_background.tga"))
    sidebar.background=sidebarBG

    -- A dedicated fixed FooterContainer owns bottom controls. The navigation
    -- viewport measures the remaining sidebar height instead of a magic -148.
    local footer=CreateFrame("Frame",nil,sidebar)
    footer:SetPoint("BOTTOMLEFT",sidebar,"BOTTOMLEFT",0,0)
    footer:SetPoint("BOTTOMRIGHT",sidebar,"BOTTOMRIGHT",0,0)
    footer:SetHeight(148)
    sidebar.footer=footer
    local measuredSidebarHeight=sidebar.GetHeight and tonumber(sidebar:GetHeight()) or 0
    if measuredSidebarHeight<=0 then measuredSidebarHeight=L.height-L.headerHeight end
    local availableNavHeight=math.max(1,measuredSidebarHeight-footer:GetHeight())
    local navScroll=JLP.UILayout:ScrollArea(sidebar,{width=L.sidebarWidth,height=availableNavHeight,contentWidth=L.sidebarWidth-10,scrollbarGutter=8,wheelStep=44})
    navScroll:SetPoint("TOPLEFT",0,0)
    local navContainer=navScroll.content

    local content=CreateFrame("Frame",nil,frame)
    content:SetPoint("TOPLEFT",sidebar,"TOPRIGHT",L.contentInset,-L.contentInset)
    content:SetPoint("BOTTOMRIGHT",-L.contentInset,L.contentInset)

    frame.header=header
    frame.sidebar=sidebar
    frame.navScroll=navScroll
    -- A true sidebar resize invalidates nav scroll metrics, but does not move
    -- fixed FooterContainer controls or reset navigation position.
    if sidebar.SetScript then
        sidebar:SetScript("OnSizeChanged",function(self)
            local actual=tonumber(self:GetHeight()) or 0
            local height=math.max(1,(actual>0 and actual or (L.height-L.headerHeight))-footer:GetHeight())
            navScroll:Resize(L.sidebarWidth,height,L.sidebarWidth-10)
        end)
    end
    frame.navContainer=navContainer
    frame.content=content
    frame.buttons={}
    frame.pages={}
    frame.guideSubButtons={}
    frame.bankSubButtons={}
    frame.bankEmptyHint=W:Label(navContainer,"", "GameFontHighlightSmall")
    frame.bankEmptyHint:SetTextColor(JLP.UITheme:Color("muted"))
    frame.bankEmptyHint:SetJustifyH("LEFT")
    frame.bankEmptyHint:Hide()
    frame.secondarySubButtons={}

    for _,def in ipairs(JLP.UITheme.nav) do
        local b=W:NavButton(navContainer,def)
        if def.key=="Guide" then
            b:SetScript("OnClick",function() MainWindow:ShowGuideMode(nil) end)
        elseif def.key=="Bank" then
            b:SetScript("OnClick",function() MainWindow:ShowBankCharacter(nil) end)
        else
            b:SetScript("OnClick",function() MainWindow:ShowPage(def.key) end)
        end
        frame.buttons[def.key]=b
    end

    for i=1,3 do
        local sub=W:SubNavButton(navContainer,"")
        sub:SetScript("OnClick",function(self) if self.mode then MainWindow:ShowGuideMode(self.mode) end end)
        frame.guideSubButtons[i]=sub
    end
    local secondaries=W:SubNavButton(navContainer,"Secondaries")
    secondaries:SetScript("OnClick",function() MainWindow:ShowSecondaryMode("overview") end)
    frame.secondariesButton=secondaries
    for i=1,3 do
        local button=W:SubNavButton(navContainer,"")
        button:SetScript("OnClick",function(self)
            if self.secondaryMode then MainWindow:ShowSecondaryMode(self.secondaryMode) end
        end)
        frame.secondarySubButtons[i]=button
    end
    self.frame=frame
    self:UpdateGuideSubmenuLabels()
    self:UpdateSecondarySubmenuLabels()
    self:UpdateBankSubmenuLabels()
    self:LayoutSidebar(false,false)

    local version=W:Label(footer,"v"..JLP.version,"GameFontHighlightSmall")
    version:SetPoint("BOTTOMLEFT",24,116)
    version:SetTextColor(JLP.UITheme:Color("muted"))
    frame.versionLabel=version

    local clickThrough=W:Button(footer,"Click-through: OFF",202)
    clickThrough:SetHeight(30)
    clickThrough:SetPoint("BOTTOMLEFT",24,72)
    clickThrough:SetScript("OnClick",function() MainWindow:ToggleClickThrough() end)
    frame.clickThroughButton=clickThrough

    local opacityValue=W:Label(footer,"Transparency: 0%","GameFontHighlightSmall")
    opacityValue:SetPoint("BOTTOMLEFT",24,52)
    opacityValue:SetTextColor(JLP.UITheme:Color("muted"))
    frame.opacityValue=opacityValue

    local opacitySlider=CreateFrame("Slider",nil,footer)
    opacitySlider:SetPoint("BOTTOMLEFT",24,28)
    opacitySlider:SetSize(202,18)
    if opacitySlider.SetOrientation then opacitySlider:SetOrientation("HORIZONTAL") end
    opacitySlider:SetMinMaxValues(0.20,1.00)
    if opacitySlider.SetValueStep then opacitySlider:SetValueStep(0.01) end
    if opacitySlider.SetObeyStepOnDrag then opacitySlider:SetObeyStepOnDrag(true) end

    -- The visual track uses the same movement span as the thumb. By anchoring
    -- the fill directly to the thumb center, the bright fill can never drift
    -- away from the handle while dragging.
    local trackInset=7
    local sliderBG=opacitySlider:CreateTexture(nil,"BACKGROUND")
    sliderBG:SetPoint("LEFT",opacitySlider,"LEFT",trackInset,0)
    sliderBG:SetPoint("RIGHT",opacitySlider,"RIGHT",-trackInset,0)
    sliderBG:SetHeight(6)
    sliderBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    sliderBG:SetVertexColor(0.02,0.14,0.22,0.95)

    if opacitySlider.SetThumbTexture then
        opacitySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    end
    local thumb=(opacitySlider.GetThumbTexture and opacitySlider:GetThumbTexture()) or nil
    -- Keep Blizzard's native thumb dimensions. This restores the larger handle
    -- used before v0.5.1 while retaining the corrected fill-to-thumb anchoring.
    opacitySlider.nativeThumbSize=true

    local sliderFill=opacitySlider:CreateTexture(nil,"ARTWORK")
    sliderFill:SetPoint("LEFT",opacitySlider,"LEFT",trackInset,0)
    sliderFill:SetHeight(6)
    sliderFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    sliderFill:SetVertexColor(JLP.UITheme:Color("cyan"))
    if thumb then
        sliderFill:SetPoint("RIGHT",thumb,"CENTER",0,0)
    end
    opacitySlider.fill=sliderFill
    opacitySlider.thumb=thumb

    opacitySlider:SetScript("OnValueChanged",function(self,value)
        value=clamp(value,0.20,1.0)
        -- Fallback for clients where GetThumbTexture is unavailable. The
        -- normal Forever path is anchored directly to the thumb above.
        if not self.thumb and self.fill and self.fill.SetWidth then
            local usable=202-(trackInset*2)
            self.fill:SetWidth(math.max(1,usable*((value-0.20)/0.80)))
        end
        MainWindow:ApplyOpacity(value)
        if not self.__syncing and JLP.DB and JLP.DB.profile then JLP.DB.profile.opacity=value end
    end)
    opacitySlider:SetValue(initialOpacity)
    frame.opacitySlider=opacitySlider
    MainWindow:ApplyOpacity(initialOpacity)

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(26,26)
    resize:SetPoint("BOTTOMRIGHT",-4,4)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or type(GetCursorPosition) ~= "function" then return end
        local x, y = GetCursorPosition()
        local effective = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        self.__dragging = true
        self.__startX = x / effective
        self.__startY = y / effective
        self.__startScale = (frame.GetScale and frame:GetScale()) or 1
        self:SetScript("OnUpdate", function(handle)
            if not handle.__dragging then return end
            local cx, cy = GetCursorPosition()
            local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            cx, cy = cx / uiScale, cy / uiScale
            local dx = cx - handle.__startX
            local dy = handle.__startY - cy
            local delta = ((dx / L.width) + (dy / L.height)) * 0.5
            local newScale = handle.__startScale + delta
            newScale = math.max(L.minScale or 0.65, math.min(L.maxScale or 1.30, newScale))
            if frame.SetScale then frame:SetScale(newScale) end
            -- A manual resize cannot move critical controls outside UIParent.
            local layout=JLP:GetModule("MainViewportLayout")
            if layout then
                local bound=layout:Fit(UIParent:GetWidth(),UIParent:GetHeight(),newScale,L.width,L.height,L.minScale,L.maxScale)
                newScale=bound.scale
                if frame.SetScale then frame:SetScale(newScale) end
            end
            updateScaleLabel(newScale)
            handle.__currentScale = newScale
        end)
    end)
    resize:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        self.__dragging = false
        self:SetScript("OnUpdate", nil)
        local scale = self.__currentScale or ((frame.GetScale and frame:GetScale()) or 1)
        updateScaleLabel(scale)
        if JLP.DB and JLP.DB.profile then JLP.DB.profile.scale = scale end
        MainWindow:FitToViewport()
    end)
    frame.resizeHandle = resize

    self:ShowPage("Overview")
    self:ApplyClickThrough(profile and profile.clickThrough or false)
    return frame
end

function MainWindow:ShowGuideMode(mode)
    -- An unrelated manual navigation must not leave a stale return target.
    self.advisoryReturn=nil
    local frame=self:Create()
    -- Changing Guide mode also closes transient Guide overlays.
    local guide=JLP.UIPages and JLP.UIPages.Guide
    if guide and guide.Deactivate then guide:Deactivate() end
    self:UpdateGuideSubmenuLabels()
    self:LayoutSidebar(true,false,false)
    self:UpdateSecondarySubmenuState(nil)

    for key,pageFrame in pairs(frame.pages) do pageFrame:SetShown(key=="Guide") end
    for key,b in pairs(frame.buttons) do b:SetActive(key=="Guide") end

    local page=JLP.UIPages and JLP.UIPages.Guide
    if page then
        if not frame.pages.Guide then frame.pages.Guide=page:Create(frame.content) end
        page:SetMode(mode)
        frame.pages.Guide:Show()
        page:Refresh()
    end
    self:UpdateGuideSubmenuState(page and page:GetMode() or mode or "onboarding")
    self.activePage="Guide"
    self:UpdateSecondarySubmenuState(nil)
    self:ApplyClickThrough(JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough)
end

function MainWindow:ShowSecondaryMode(mode)
    self.advisoryReturn=nil
    local frame=self:Create()
    self:DeactivateActivePage("Secondaries")
    self:UpdateGuideSubmenuLabels()
    self:UpdateSecondarySubmenuLabels()
    self:LayoutSidebar(true,false,true)
    for key,pageFrame in pairs(frame.pages) do pageFrame:SetShown(key=="Secondaries") end
    for key,button in pairs(frame.buttons) do button:SetActive(key=="Guide") end
    for _,button in ipairs(frame.guideSubButtons or {}) do button:SetActive(false) end
    for _,button in ipairs(frame.bankSubButtons or {}) do button:SetActive(false) end
    local page=JLP.UIPages and JLP.UIPages.Secondaries
    if page then
        if not frame.pages.Secondaries then frame.pages.Secondaries=page:Create(frame.content) end
        page:SetMode(mode)
        frame.pages.Secondaries:Show()
        page:Refresh()
    end
    self.activePage="Secondaries"
    self:UpdateSecondarySubmenuState(page and page:GetMode() or "overview")
    self:ApplyClickThrough(JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough)
end

function MainWindow:ShowBankCharacter(characterKey)
    -- A manual character switch inside Bank is not a material-source return.
    if self.activePage=="Bank" and characterKey~=nil then self.advisoryReturn=nil end
    local frame=self:Create()
    self:DeactivateActivePage("Bank")
    local inventory=JLP:GetModule("Inventory")
    local current=inventory and inventory:GetCharacterKey() or nil
    characterKey=characterKey or current
    self:UpdateBankSubmenuLabels()
    self:LayoutSidebar(false,true)
    for _,b in ipairs(frame.guideSubButtons or {}) do b:SetActive(false) end
    for _,b in ipairs(frame.bankSubButtons or {}) do b:SetActive(false) end
    for key,pageFrame in pairs(frame.pages) do pageFrame:SetShown(key=="Bank") end
    for key,b in pairs(frame.buttons) do b:SetActive(key=="Bank") end
    local page=JLP.UIPages and JLP.UIPages.Bank
    if page then
        if not frame.pages.Bank then frame.pages.Bank=page:Create(frame.content) end
        page:SetCharacterKey(characterKey)
        frame.pages.Bank:Show()
        page:Refresh()
    end
    self:UpdateBankSubmenuState(characterKey~=current and characterKey or nil)
    self.activePage="Bank"
    self:UpdateSecondarySubmenuState(nil)
    self:ApplyClickThrough(JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough)
end

-- A user-clicked source-qualified material can open existing read-only Bank/
-- AH pages and return to the prior Guide/Secondary context. No inventory or
-- price claim is cached: the destination page fetches its own current evidence.
-- A zone AREA is NOT an item drop. This is manual item-identity lookup only.
-- The standalone map remains the sole source/position owner for Return.
function MainWindow:BeginSkinningMaterialReference(target,capture)
    if target~="Bank" and target~="Auction House" then return false,"TARGET_UNAVAILABLE" end
    local map=JLP.StandaloneGatheringMap
    if not map or type(map.ValidateSkinningMaterialCapture)~="function" then
        return false,"MAP_UNAVAILABLE" end
    local ok,reason=map:ValidateSkinningMaterialCapture(capture)
    if not ok then return false,reason end
    self.advisoryReturn={page="Gathering Map",target=target,mode="SKINNING",
        materialID=capture.itemID,materialName="Skinning item (identity only)",
        capture=capture,sourceQualified=true,readOnly=true,nativeDispatchAllowed=false}
    self._materialReferenceEntering=target
    local opened=pcall(self.ShowPage,self,target)
    self._materialReferenceEntering=nil
    if not opened then self.advisoryReturn=nil;return false,"DESTINATION_UNAVAILABLE" end
    local page=JLP.UIPages and JLP.UIPages[target]
    local back=page and page.frame and (target=="Bank" and page.frame.advisoryBack or
        page.frame.status and page.frame.status.advisoryBack)
    if back and back.SetShown then back:SetShown(true) end
    return true
end
function MainWindow:BeginMaterialReference(target,origin,qualified,originView)
    if target~="Bank" and target~="Auction House" then return false,"TARGET_UNAVAILABLE" end
    if origin~="Guide" and origin~="Secondaries" then return false,"ORIGIN_UNAVAILABLE" end
    if type(qualified)~="table" or qualified.readOnly~=true or
        qualified.nativeDispatchAllowed~=false or not qualified.itemID then
        return false,"UNQUALIFIED_MATERIAL"
    end
    local page=JLP.UIPages and JLP.UIPages[origin]
    if self.activePage~=origin or not page then return false,"ORIGIN_NOT_ACTIVE" end
    local capture,reason
    if type(page.CaptureMaterialReference)=="function" then
        local ok,value,err=pcall(page.CaptureMaterialReference,page,qualified,originView)
        if ok then capture,reason=value,err else reason="ORIGIN_CAPTURE_ERROR" end
        if capture==false then capture=nil end
        if not capture then return false,reason or "ORIGIN_NOT_QUALIFIED" end
    end
    -- Missing owner identity cannot authorize exact item focus. Keep the
    -- qualified Guide return path available even when inventory is unavailable.
    if (origin=="Guide" or origin=="Secondaries") and page.MaterialOwnerSignature and
        type(page.MaterialOwnerSignature)=="function" then
        local okOwner,owner=pcall(page.MaterialOwnerSignature,page)
        if not okOwner or owner=="OWNER_UNKNOWN" or type(owner)~="string" or owner=="" then
            return false,"OWNER_UNKNOWN"
        end
    end
    -- The primary page owns a transient, source-qualified capture. An older
    -- integration without an adapter may navigate, but must not re-open a
    -- purportedly current SourceSheet on return.
    if capture and (capture.materialID~=qualified.itemID or capture.readOnly~=true or
        capture.nativeDispatchAllowed~=false) then return false,"SOURCE_IDENTITY_INVALID" end
    self.advisoryReturn={page=origin,target=target,mode=page.GetMode and page:GetMode(),
        materialID=qualified.itemID,materialName=qualified.name,
        capture=capture,sourceQualified=capture~=nil,
        readOnly=true,nativeDispatchAllowed=false}
    page.materialReferenceWarning=nil
    -- Bank/AH Refresh runs before ShowPage assigns activePage; this temporary
    -- token lets those read-only pages show the relevant item on FIRST render,
    -- without scanning/refreshing inventory twice or another scheduler.
    self._materialReferenceEntering=target
    local navOK=pcall(self.ShowPage,self,target)
    self._materialReferenceEntering=nil
    if not navOK then self.advisoryReturn=nil;return false,"DESTINATION_UNAVAILABLE" end
    -- ShowPage performs its first Refresh before activePage is assigned.
    -- Update this transient return affordance after navigation completes.
    local destination=JLP.UIPages and JLP.UIPages[target]
    if destination and destination.frame then
        local back=target=="Bank" and destination.frame.advisoryBack or
            destination.frame.status and destination.frame.status.advisoryBack
        if back and back.SetShown then back:SetShown(true) end
    end
    return true
end
-- A manual owner/context change invalidates a destination's exact item receipt
-- without destroying the user's safe Return affordance. No bank/AH action.
function MainWindow:InvalidateMaterialReference(target,reason)
    local receipt=self.advisoryReturn
    if type(receipt)~="table" or receipt.target~=target then return false end
    receipt.contextInvalidated=true
    receipt.contextInvalidationReason=type(reason)=="string" and reason or "SOURCE_CHANGED"
    return true
end
function MainWindow:GetMaterialReference(target)
    local receipt=self.advisoryReturn
    -- A source receipt created for a prior character cannot remain a live
    -- Bank/AH reference just because the target page has not refreshed.
    if receipt and receipt.page=="Gathering Map" then
        local map=JLP.StandaloneGatheringMap
        local ok,reason=map and map.ValidateSkinningMaterialCapture and
            map:ValidateSkinningMaterialCapture(receipt.capture)
        if not ok then self:InvalidateMaterialReference(target,reason or "SOURCE_CHANGED") end
    end
    if receipt and receipt.capture and receipt.capture.ownerSignature and
        (receipt.page=="Guide" or receipt.page=="Secondaries") then
        local origin=JLP.UIPages and JLP.UIPages[receipt.page]
        if origin and type(origin.MaterialOwnerSignature)=="function" then
            local ok,owner=pcall(origin.MaterialOwnerSignature,origin)
            if not ok or owner=="OWNER_UNKNOWN" or owner~=receipt.capture.ownerSignature then
                self:InvalidateMaterialReference(target,"CHARACTER_CHANGED")
            end
        else
            self:InvalidateMaterialReference(target,"ORIGIN_UNAVAILABLE")
        end
    end
    if not receipt or receipt.contextInvalidated==true or receipt.target~=target or receipt.readOnly~=true or
        receipt.nativeDispatchAllowed~=false or
        (self.activePage~=target and self._materialReferenceEntering~=target) then return nil end
    return receipt
end
function MainWindow:ReturnFromMaterialReference()
    local receipt=self.advisoryReturn
    if not receipt or (self.activePage~="Bank" and self.activePage~="Auction House") or
        (receipt.target~=nil and receipt.target~=self.activePage) then
        return false,"RETURN_UNAVAILABLE"
    end
    self.advisoryReturn=nil
    if receipt.page=="Gathering Map" and receipt.readOnly==true and
        receipt.nativeDispatchAllowed==false then
        local map=JLP.StandaloneGatheringMap
        local ok,reason=receipt.contextInvalidated~=true and map and
            map.ValidateSkinningMaterialCapture and
            map:ValidateSkinningMaterialCapture(receipt.capture)
        if map and type(map.Show)=="function" then map:Show() end
        if map then
            map._skinningReturnMessage=ok and "ITEM_REFERENCE_RESTORED" or
                (receipt.contextInvalidationReason or reason or "SOURCE_CHANGED")
            if map.Refresh then map:Refresh() end
        end
        return true,ok and "REFERENCE_RESTORED" or "RETURN_TO_SAFE_MAP"
    end
    if receipt.readOnly~=true or receipt.nativeDispatchAllowed~=false or
        (receipt.page~="Guide" and receipt.page~="Secondaries") then
        return false,"RETURN_UNQUALIFIED"
    end
    -- A legacy/manual pre-adapter receipt cannot re-open an unqualified sheet.
    -- Its previously visible plain scroll position is harmless to retain;
    -- source/material context is restored ONLY from a qualified capture.
    local legacyScroll=nil
    if not receipt.capture and receipt.page=="Guide" then
        local prior=JLP.UIPages and JLP.UIPages.Guide
        local frame=prior and prior.frame
        legacyScroll=frame and tonumber(frame.scrollOffset) or nil
    end
    -- Page switching is the existing navigation route and may reset scrolling.
    -- Restore only after both SetMode and the page's last Refresh have run.
    if receipt.page=="Guide" then self:ShowGuideMode(receipt.mode)
    else self:ShowSecondaryMode(receipt.mode) end
    local page=JLP.UIPages and JLP.UIPages[receipt.page]
    local restoreReason=nil
    if receipt.contextInvalidated~=true and receipt.capture and page and
        type(page.RestoreMaterialReference)=="function" then
        local ok,valid,reason=pcall(page.RestoreMaterialReference,page,receipt.capture)
        if ok and valid==true then return true,"REFERENCE_RESTORED" end
        restoreReason=ok and reason or "ORIGIN_RESTORE_ERROR"
    end
    -- Mismatched profession/recipe/evidence fails CLOSED. The normal page
    -- remains available, with old SourceSheet and material receipt discarded.
    if page and type(page.ClearMaterialReference)=="function" then
        pcall(page.ClearMaterialReference,page)
    end
    if legacyScroll and legacyScroll>=0 and legacyScroll==legacyScroll and
        legacyScroll<100000 and page and page.frame then
        local layout=JLP.UILayout
        if layout and type(layout.RestoreScrollPosition)=="function" then
            layout:RestoreScrollPosition(page.frame,legacyScroll)
        elseif page.frame.ScrollPage then page.frame:ScrollPage(legacyScroll) end
    end
    self.materialReferenceFeedback=receipt.contextInvalidated and
        ("Material reference invalidated ("..tostring(receipt.contextInvalidationReason or "context changed")..
        "); review the selected character and reopen the source manually.") or
        ("Material source unavailable ("..tostring(restoreReason or "SOURCE_CHANGED")..
        "); review the current material step and reopen manually.")
    if page then page.materialReferenceWarning=self.materialReferenceFeedback end
    if page and type(page.Refresh)=="function" and receipt.capture then
        pcall(page.Refresh,page)
        if page.frame then
            local layout=JLP.UILayout
            if layout and layout.ReturnToScrollOrigin then
                if receipt.page=="Guide" then layout:ReturnToScrollOrigin(page.frame) end
            end
        end
    end
    return true,"RETURN_TO_SAFE_OVERVIEW"
end
function MainWindow:ShowPage(name)
    -- Removed/unknown pages must never leave a blank active content surface.
    -- In particular, old navigation references cannot resurrect a retired
    -- catalogue browser after an upgrade. No SavedVariables reset required.
    if type(name)~="string" or not (JLP.UIPages and JLP.UIPages[name]) then
        name="Overview"
    end
    if self.advisoryReturn and name~="Bank" and name~="Auction House" then self.advisoryReturn=nil end
    if self.advisoryReturn and (name=="Bank" or name=="Auction House") and
        self.activePage~=self.advisoryReturn.page and
        self.advisoryReturn.page~="Gathering Map" then self.advisoryReturn=nil end
    if name=="Guide" then
        local mode=(JLP.DB and JLP.DB.profile and JLP.DB.profile.guideMode) or nil
        return self:ShowGuideMode(mode)
    elseif name=="Bank" then
        return self:ShowBankCharacter(nil)
    elseif name=="Secondaries" then
        return self:ShowSecondaryMode("overview")
    end

    local frame=self:Create()
    self:DeactivateActivePage(name)
    self:LayoutSidebar(false,false)
    for _,b in ipairs(frame.guideSubButtons or {}) do b:SetActive(false) end
    for _,b in ipairs(frame.bankSubButtons or {}) do b:SetActive(false) end
    for key,pageFrame in pairs(frame.pages) do pageFrame:SetShown(key==name) end
    for key,b in pairs(frame.buttons) do b:SetActive(key==name) end
    local page=JLP.UIPages and JLP.UIPages[name]
    if page then
        if not frame.pages[name] then frame.pages[name]=page:Create(frame.content) end
        frame.pages[name]:Show()
        if page.Refresh then page:Refresh() end
    end
    self.activePage=name
    self:UpdateSecondarySubmenuState(nil)
    self:ApplyClickThrough(JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough)
end

function MainWindow:RefreshActiveData()
    if not self.frame or not self.frame:IsShown() or not self.activePage then return end
    if self.frame.header and self.frame.header.identity then
        self.frame.header.identity:SetText(playerIdentity())
    end
    local pageName=self.activePage
    local page=JLP.UIPages and JLP.UIPages[pageName]
    if page and page.Refresh then page:Refresh() end
    if JLP.DB and JLP.DB.profile and JLP.DB.profile.clickThrough then
        self:ApplyClickThrough(true)
    end
end

function MainWindow:Refresh()
    -- Hidden windows receive a full refresh on Toggle/Show. Avoid repeatedly
    -- rebuilding submenu labels for background events while no UI is visible.
    if not self.frame or not self.frame.IsShown or not self.frame:IsShown() then return end
    local guideNavigationChanged=self:UpdateGuideSubmenuLabels()
    self:UpdateSecondarySubmenuLabels()
    local bankNavigationChanged=self:UpdateBankSubmenuLabels()
    if not self.frame:IsShown() or not self.activePage then return end

    if self.activePage=="Guide" then
        local page=JLP.UIPages and JLP.UIPages.Guide
        self:UpdateGuideSubmenuState(page and page:GetMode() or "onboarding")
        if guideNavigationChanged then self:LayoutSidebar(true,false,false) end
    elseif self.activePage=="Secondaries" then
        local page=JLP.UIPages and JLP.UIPages.Secondaries
        self:UpdateSecondarySubmenuState(page and page:GetMode() or "overview")
        self:LayoutSidebar(true,false,true)
    elseif self.activePage=="Bank" then
        local page=JLP.UIPages and JLP.UIPages.Bank
        local inventory=JLP:GetModule("Inventory")
        local current=inventory and inventory:GetCharacterKey() or nil
        local selected=page and page:GetCharacterKey() or nil
        self:UpdateBankSubmenuState(selected~=current and selected or nil)
        if bankNavigationChanged then self:LayoutSidebar(false,true) end
    end
    self:RefreshActiveData()
end

function MainWindow:Toggle()
    local frame=self:Create()
    if frame:IsShown() then
        frame:Hide()
        if JLP.DB and JLP.DB.profile then JLP.DB.profile.showWindow = false end
    else
        frame:Show()
        if JLP.DB and JLP.DB.profile then JLP.DB.profile.showWindow = true end
        self:Refresh()
    end
end

do
 local build=MainWindow.Create
 function MainWindow:Create(...)
  local args={n=select("#",...),...}
  return withObservationPass("UI.Create",function() return build(self,(unpack or table.unpack)(args,1,args.n)) end)
 end
end
do
 local build=MainWindow.ShowPage
 function MainWindow:ShowPage(...)
  local args={n=select("#",...),...}
  return withObservationPass("UI.ShowPage",function() return build(self,(unpack or table.unpack)(args,1,args.n)) end)
 end
end
do
 local build=MainWindow.ShowGuideMode
 function MainWindow:ShowGuideMode(...)
  local args={n=select("#",...),...}
  return withObservationPass("UI.ShowGuideMode",function() return build(self,(unpack or table.unpack)(args,1,args.n)) end)
 end
end
do
 local build=MainWindow.ShowSecondaryMode
 function MainWindow:ShowSecondaryMode(...)
  local args={n=select("#",...),...}
  return withObservationPass("UI.ShowSecondaryMode",function() return build(self,(unpack or table.unpack)(args,1,args.n)) end)
 end
end
do
 local build=MainWindow.ShowBankCharacter
 function MainWindow:ShowBankCharacter(...)
  local args={n=select("#",...),...}
  return withObservationPass("UI.ShowBankCharacter",function() return build(self,(unpack or table.unpack)(args,1,args.n)) end)
 end
end
do
 local build=MainWindow.Refresh
 function MainWindow:Refresh(...)
  local args={n=select("#",...),...}
  return withObservationPass("UI.Refresh",function() return build(self,(unpack or table.unpack)(args,1,args.n)) end)
 end
end
do
 local build=MainWindow.RefreshActiveData
 function MainWindow:RefreshActiveData(...)
  local args={n=select("#",...),...}
  return withObservationPass("UI.RefreshActiveData",function() return build(self,(unpack or table.unpack)(args,1,args.n)) end)
 end
end

JLP.MainWindow=MainWindow
