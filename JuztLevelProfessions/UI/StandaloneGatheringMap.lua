local _, JLP = ...
-- A second viewport over the *same* JLP GatheringSharedMapState/route service.
-- Never a source-addon map, duplicate node store or native gameplay controller.
local Window={contract="jlp-standalone-gathering-map-v1",nativeDispatchAllowed=false}
local W,MIN_W,MIN_H,MAX_W,MAX_H=nil,640,390,1300,1000
-- Start each new standalone map/zone view at 150%; Fit still returns to 100%.
local DEFAULT_MAP_ZOOM=1.5
-- Reserve enough reusable row widgets for the tallest supported viewport.
-- Actual visible capacity is determined by the space ABOVE the pager.
local RESOURCE_ROW_POOL_SIZE=22
local function clamp(value,minimum,maximum)
    return math.max(minimum,math.min(maximum,value))
end
local function viewState() return JLP:GetModule("GatheringSharedMapState") end
local function source() return JLP:GetModule("GatheringMapViewService") end
local function label(parent,text,size)
    local font=JLP.UIWidgets:Label(parent,text,size or "GameFontHighlightSmall")
    if font.SetJustifyH then font:SetJustifyH("LEFT") end
    return font
end
local function button(parent,text,width,anchor,x,y,handler)
    local b=JLP.UIWidgets:Button(parent,text,width)
    b:SetHeight(26);b:SetPoint(anchor or "TOPLEFT",x or 0,y or 0)
    b:SetScript("OnClick",handler)
    return b
end
local function settings()
    local s=viewState()
    return (s and s:GetStandaloneSettings()) or
        {x=0,y=0,width=760,height=550,backgroundOpacity=0.85,chromeOpacity=1,visible=false}
end
function Window:SetContentContext(scope)
    self:ExitContinentPreview()
    self:CloseZoneMenu()
    self.contentContext=scope=="FISHING" and "FISHING" or "GATHERING"
    self.includeGathering=false
    self.routeResult=nil;self.routeFeedback=nil
    if self.frame then self.frame.forceRedraw=true end
end
function Window:IsShown()
    return self.frame~=nil and self.frame:IsShown() or false
end
function Window:SavePosition()
    local f=self.frame
    if not f then return end
    local state=viewState()
    if not state then return end
    local patch={}
    -- Size is persisted ONLY when the user ends a drag/resize, not during an
    -- automatic fit caused by opening/reloading on a different resolution.
    local actualW=f.GetWidth and f:GetWidth() or f.width
    local actualH=f.GetHeight and f:GetHeight() or f.height
    if type(actualW)=="number" then patch.width=clamp(actualW,MIN_W,MAX_W) end
    if type(actualH)=="number" then patch.height=clamp(actualH,MIN_H,MAX_H) end
    if f.GetCenter and UIParent and UIParent.GetCenter then
        local cx,cy=f:GetCenter();local px,py=UIParent:GetCenter()
        local scale=(f.GetEffectiveScale and f:GetEffectiveScale()) or 1
        local rootScale=(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if type(cx)=="number" and type(cy)=="number" and
            type(px)=="number" and type(py)=="number" and
            type(scale)=="number" and scale>0 and type(rootScale)=="number" and rootScale>0 then
            patch.x=clamp((cx*scale-px*rootScale)/scale,-4096,4096)
            patch.y=clamp((cy*scale-py*rootScale)/scale,-4096,4096)
        end
    end
    state:SetStandaloneSettings(patch)
end

-- Refit on opening and on subsequent UIParent size/scale changes. Only the
-- explicit end of user drag/resize persists geometry; responsive fitting is
-- ephemeral and must never replace the user's intended window dimensions.
function Window:FitToViewport()
    self:CloseZoneMenu()
    local f=self.frame
    local layout=JLP:GetModule("GatheringViewportLayout")
    if not f or not layout then return false,"LAYOUT_UNAVAILABLE" end
    local screenW=UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1600
    local screenH=UIParent and UIParent.GetHeight and UIParent:GetHeight() or 900
    local parentScale=UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local result=layout:Fit(screenW,screenH,settings())
    local signature=layout:Signature(screenW,screenH,parentScale)
    self.lastFit=result
    if not result.frameFitsScreen or not result.interactiveControlsFit then
        return false,"VIEWPORT_TOO_SMALL"
    end
    if f.ClearAllPoints then f:ClearAllPoints() end
    f:SetSize(result.width,result.height)
    f:SetPoint("CENTER",UIParent,"CENTER",result.x,result.y)
    self.viewportSignature=signature
    self.lastFit=result
    self._lastContentSize=nil
    self._resizePending=false
    self:ApplyContentLayout(result)
    self:ApplyContinentCanvasLayout()
    f.forceRedraw=true
    return true,result
end

-- A local user resize never calls FitToViewport (which reads saved geometry).
-- Apply the live constraints once after the burst of size events settles.
function Window:ReflowContentLayout()
    local f=self.frame
    local contract=JLP:GetModule("GatheringViewportLayout")
    if not (f and contract and contract.ForFrameSize) then return false end
    local width=f.GetWidth and f:GetWidth() or 0
    local height=f.GetHeight and f:GetHeight() or 0
    local key=tostring(math.floor(width+0.5))..":"..tostring(math.floor(height+0.5))
    if key==self._lastContentSize then return false end
    self:CloseZoneMenu()
    self._lastContentSize=key
    local plan=contract:ForFrameSize(width,height)
    self.lastFit=plan
    self:ApplyContentLayout(plan)
    self:ApplyContinentCanvasLayout()
    f.forceRedraw=true
    return true
end

-- Keep the zoom caption to one line: the shortest breakpoint must not
-- allow guidance text to wrap into the map/sliders below the control bar.
function Window:UpdateZoomCaption()
    local f=self.frame
    if not (f and f.zoomText and f.canvas) then return end
    local width=tonumber(f.canvas.GetWidth and f.canvas:GetWidth()) or 0
    local view=f.canvas.gatheringView or {}
    local percentage=tostring(math.floor((view.zoom or 1)*100+0.5)).."%"
    local caption
    if width<455 then caption=percentage
    elseif width<545 then caption=percentage.." · zoom / pan"
    elseif self._continentPreview then caption=percentage.." · click zone to enter"
    elseif width>=740 then caption=percentage.." · drag: pan · right-click: continent"
    else caption=percentage.." · wheel: zoom · drag: pan" end
    if f.zoomText.SetWordWrap then f.zoomText:SetWordWrap(false) end
    if f.zoomText.SetWidth then f.zoomText:SetWidth(math.max(40,width-242)) end
    f.zoomText:SetText(caption)
end

-- Minimum-height resources cannot show a useful list alongside the fixed
-- search area and three-row footer. Offer the SAME scrollable editor instead
-- of a misleading 0/0 pager or inert selection controls.
function Window:UpdateCompactResourceAccess(empty)
    local f=self.frame
    if not f then return end
    self._compactResourcesEmpty=empty==true
    if f.options then
        f.options:SetText(empty and "Browse Resources" or "Route Planning / Display")
    end
end

-- Measure visible status AFTER text/width updates; the actual font height
-- owns the space before the first resource row, not a hardcoded 20 units.
function Window:MeasureResourceHeaderExtra(inDock)
    local info=self.frame and self.frame.resourceInfo
    if not (info and info.GetStringHeight) then return 0 end
    if info.SetWidth then info:SetWidth(inDock and 190 or 205) end
    local actual=tonumber(info:GetStringHeight()) or 0
    if actual~=actual or actual<0 then actual=0 end
    return math.max(0,math.min(300,math.ceil(actual)-18+4))
end

-- Content breakpoints are separate from the outer frame fit. In MINIMAL,
-- selection remains possible with visible Prev/Next buttons (no wheel-only trap).
-- UI-only boundary feedback. The rail never captures global keyboard events;
-- scrolling remains accessible through mousewheel and explicit buttons.
function Window:UpdateDockScrollControls()
    local f=self.frame
    local sc=f and f.optionsScroll
    if not sc or not sc.GetVerticalScroll or not sc.GetHeight then return false end
    local g=(JLP.UITheme and JLP.UITheme.gathering) or {dockContentHeight=438}
    local offset=tonumber((sc:GetVerticalScroll())) or 0
    local height=tonumber(sc:GetHeight()) or 1
    local contentHeight=f.optionsContent and f.optionsContent.GetHeight and
        f.optionsContent:GetHeight() or g.dockContentHeight
    local maxOffset=math.max(0,(tonumber(contentHeight) or 438)-math.max(1,height))
    if f.dockScrollbar then f.dockScrollbar:Refresh() end
    return true
end
-- Move the SINGLE resource editor between the original rail and the foldable
-- options scroll child. Buttons and callbacks are never duplicated; selection
-- remains owned by GatheringSharedMapState and layer qualification by the
-- LayerController. The fallback restores the original rail before hiding dock.
function Window:PlaceResourceEditor(inDock)
    local f=self.frame
    if not (f and f.sidebar and f.optionsContent and f.resourceRows) then return false end
    local g=JLP.UITheme and JLP.UITheme.gathering or {}
    local host=inDock and f.optionsContent or f.sidebar
    -- The full editor is attached as one unit. Only the section host changes
    -- parent on fold/unfold; every widget retains a stable common ancestor.
    if not f.resourcesSection then
        local section=CreateFrame("Frame",nil,f.sidebar)
        section:SetAllPoints(f.sidebar)
        f.resourcesSection=section
        -- Stable, named ownership layers inside the ONE movable editor.
        -- The view hosts change parent, not each control independently.
        local function host(name)
            local child=CreateFrame("Frame",nil,section)
            child:SetAllPoints(section)
            f[name]=child
            return child
        end
        local header=host("resourceHeaderContainer")
        local rows=host("resourceListContainer")
        local footer=host("resourceFooterContainer")
        for _,widget in ipairs({f.resourceSearch,f.resourceSearchClear,f.resourceTab,f.oreTab,f.resourceInfo}) do
            if widget and widget.SetParent then widget:SetParent(header) end
        end
        for _,widget in ipairs(f.resourceRows) do
            if widget and widget.SetParent then widget:SetParent(rows) end
        end
        for _,widget in ipairs({f.resourcePrev,f.resourceNext,f.resourcePages,f.selectAll,f.selectNone}) do
            if widget and widget.SetParent then widget:SetParent(footer) end
        end
    end
    local section=f.resourcesSection
    if section.GetParent and section:GetParent()~=host then section:SetParent(host) end
    section:ClearAllPoints()
    section:SetAllPoints(host)
    local function place(control,point,x,y)
        if not control then return end
        if control.ClearAllPoints then control:ClearAllPoints() end
        local parent=control.GetParent and control:GetParent() or section
        control:SetPoint(point,parent,point,x,y)
    end
    place(f.resourceSearch,"TOPLEFT",11,inDock and -(g.dockResourceSearchTop or 38) or -30)
    place(f.resourceSearchClear,"TOPLEFT",157,inDock and -(g.dockResourceSearchTop or 38) or -30)
    place(f.resourceTab,"TOPLEFT",11,inDock and -(g.dockResourceTabsTop or 72) or -59)
    place(f.oreTab,"TOPLEFT",114,inDock and -(g.dockResourceTabsTop or 72) or -59)
    place(f.resourceInfo,"TOPLEFT",11,inDock and -(g.dockResourceInfoTop or 101) or -91)
    local offset=self._resourceInfoExtra or 0
    local firstTop=inDock and (g.dockResourceRowsTop or 126) or
        ((self.lastFit and self.lastFit.breakpoint=="MINIMAL") and 91 or 111)
    for i,b in ipairs(f.resourceRows) do
        place(b,"TOPLEFT",11,-firstTop-(i-1)*29-offset)
    end
    place(f.resourcePrev,inDock and "TOPLEFT" or "BOTTOMLEFT",11,
        inDock and -(g.dockResourcePagerTop or 376)-offset or 80)
    place(f.resourceNext,inDock and "TOPLEFT" or "BOTTOMLEFT",178,
        inDock and -(g.dockResourcePagerTop or 376)-offset or 80)
    place(f.resourcePages,inDock and "TOPLEFT" or "BOTTOMLEFT",75,
        inDock and -(g.dockResourcePagerTop or 376)-8-offset or 88)
    place(f.selectAll,inDock and "TOPLEFT" or "BOTTOMLEFT",11,
        inDock and -(g.dockResourceSelectTop or 417)-offset or 44)
    place(f.selectNone,inDock and "TOPLEFT" or "BOTTOMLEFT",114,
        inDock and -(g.dockResourceSelectTop or 417)-offset or 44)
    if f.resourceInfo and f.resourceInfo.SetWidth then
        f.resourceInfo:SetWidth(inDock and 190 or 205)
    end
    self._resourceEditorInDock=inDock
    return true
end

-- The SAME Generate/Cancel buttons live in the toolbar when Map Options is
-- closed or Route Planning folded, and move into Route Planning when expanded.
-- Parent and anchors are restored on exit; never bind a second OnClick or
-- create a second route owner. Actions remain hardware-click only.
function Window:PlaceRouteActions(inDock,resourceHeight)
    local f=self.frame
    if not (f and f.generate and f.clear and f.optionsContent) then return false end
    -- Recompute geometry on every explicit layout pass. The previous two-key
    -- cache missed viewport changes while the dock state was unchanged.
    local routeHeight=resourceHeight or 0
    local routeHost=inDock and f.optionsContent or f
    if not f.routeActionsSection then
        f.routeActionsSection=CreateFrame("Frame",nil,f)
        f.generate:SetParent(f.routeActionsSection)
        f.clear:SetParent(f.routeActionsSection)
    end
    local section=f.routeActionsSection
    if section:GetParent()~=routeHost then section:SetParent(routeHost) end
    section:ClearAllPoints();section:SetAllPoints(routeHost)
    local g=JLP.UITheme and JLP.UITheme.gathering or {}
    local top=g.dockRouteActionTop or 156
    local w=g.dockRouteActionWidth or 92
    -- When the layer toggles sit above Resources, keep route actions together
    -- on the left, including at the 640-unit minimum frame width.
    for _,entry in ipairs({{f.generate,8,22,135},{f.clear,107,165,110}}) do
        local control=entry[1]
        if control.ClearAllPoints then control:ClearAllPoints() end
        if inDock then
            control:SetPoint("TOPLEFT",section,"TOPLEFT",entry[2],-resourceHeight-top)
            if control.SetWidth then control:SetWidth(w) end
            -- Caption is refreshed from the current route workflow below.
            -- Never overwrite GENERATING / unavailable state in a layout pass.
        else
            control:SetPoint("TOPLEFT",section,"TOPLEFT",entry[3],-91)
            if control.SetWidth then control:SetWidth(entry[4]) end
            -- Normal toolbar caption is also refreshed from routeUI.
        end
    end
    self._routeActionsInDock=inDock
    self._routeActionHeight=routeHeight
    return true
end
-- ROUTE PLANNING and MAP DISPLAY are the two independently foldable sections.
-- UI-only accordion inside the docked rail. Route information retains its
-- own paginated tab; both internal sections may fold independently. No changes
-- to SharedMapState, route authority, resource selection or persistence.
function Window:UpdateDockSections()
    local f=self.frame
    if not (f and f.optionsContent and f.dockRouteHeading and f.dockDisplayHeading) then return false end
    local g=JLP.UITheme and JLP.UITheme.gathering or {}
    local routeOpen=self.dockRouteExpanded~=false
    local displayOpen=self.dockDisplayExpanded~=false
    local resourcesOpen=self.dockResourcesExpanded==true
    local inDock=self.optionsShown==true and resourcesOpen
    -- Resource status can wrap into multiple lines; its measured extra height
    -- belongs to this accordion section and pushes the rows/pager downstream.
    local extra=0
    if resourcesOpen and f.resourceInfo then
        f.resourceInfo:SetWidth(190)
        local measured=f.resourceInfo.GetStringHeight and tonumber(f.resourceInfo:GetStringHeight()) or 0
        extra=math.max(0,math.min(100,(measured or 0)-26))
    end
    self._resourceInfoExtra=extra
    self:PlaceResourceEditor(inDock)
    -- Section extents are derived from the lowest *visible* child control.
    -- Keep a theme-defined minimum only for visual breathing room, never as a
    -- substitute for the actual pager / action / evidence bounds.
    local resourceExtent=math.max((g.dockResourcePagerTop or 376)+34,
        (g.dockResourceSelectTop or 417)+42,
        (g.dockResourceRowsTop or 126)+8*29+20)
    local resourceHeight=resourcesOpen and (math.max(g.dockResourcesExpandedHeight or 0,resourceExtent)+extra) or
        math.max(54,g.dockResourcesHeight or 64)
    self:PlaceRouteActions(self.optionsShown==true and routeOpen,resourceHeight)
    local routeExtent=math.max(187,(g.dockRouteActionTop or 156)+42,117+40)
    local routeHeight=routeOpen and math.max(routeExtent,g.dockRouteExpandedHeight or 0) or
        math.max(54,g.dockRouteCollapsedHeight or 30)
    local displayTop=-3-resourceHeight-routeHeight
    -- Map Display's Skinning acquisition subsection is an explicit fold.
    -- Without it the previous fixed 355-unit display reservation forced Route
    -- Information far below compact viewports even when users only wanted pins.
    local skinningOpen=self.dockSkinningExpanded==true
    -- Measure the current (possibly multiline) evidence before stacking the
    -- remaining display controls. One layout pass owns all downstream anchors.
    local evidenceHeight=36
    if displayOpen and f.skinningEvidence then
        f.skinningEvidence:SetWidth(190)
        f.skinningEvidence:SetHeight(108)
        local measured=f.skinningEvidence.GetStringHeight and f.skinningEvidence:GetStringHeight() or 36
        evidenceHeight=math.max(36,math.min(108,tonumber(measured) or 36))
        f.skinningEvidence:SetHeight(evidenceHeight)
    end
    local displayExtra=evidenceHeight-36
    local displayExtent=skinningOpen and math.max(410,345+44) or math.max(235,195+40)
    local displayHeight=displayOpen and (displayExtent+displayExtra) or
        math.max(54,g.dockDisplayCollapsedHeight or 30)
    local infoTop=displayTop-displayHeight
    local rationaleTop=displayTop-82-evidenceHeight-8
    local recommendTop=rationaleTop-34
    local skinningTop=recommendTop-35
    local function move(widget,y)
        if not widget then return end
        if widget.ClearAllPoints then widget:ClearAllPoints() end
        widget:SetPoint("TOPLEFT",f.optionsContent,"TOPLEFT",8,y)
    end
    f.dockRouteHeading:SetText((routeOpen and "[-] " or "[+] ").."Route Planning")
    f.dockDisplayHeading:SetText((displayOpen and "[-] " or "[+] ").."Map Display")
    if f.dockResourcesHeading then
        f.dockResourcesHeading:SetText((resourcesOpen and "[-] " or "[+] ").."Resources / Filters")
        f.dockResourcesSummary:SetShown(self.optionsShown==true and not resourcesOpen)
    end
    -- Editor content must be hidden when folded; RefreshResourceList also
    -- honours this after asynchronous layer/zone changes.
    if self.optionsShown and f.resourceRows then
        local widgets={f.resourceSearch,f.resourceSearchClear,f.resourceTab,f.oreTab,f.resourceInfo,
            f.resourcePrev,f.resourceNext,f.resourcePages,f.selectAll,f.selectNone}
        for _,control in ipairs(widgets) do control:SetShown(resourcesOpen) end
        for _,control in ipairs(f.resourceRows) do control:SetShown(resourcesOpen and control.resourceKey~=nil) end
    end
    move(f.dockRouteHeading,-3-resourceHeight)
    move(f.dockDisplayHeading,displayTop)
    -- Read-only collapsed summaries occupy a measured 54-unit section, not
    -- a hidden active hitbox or an overlay over the next heading.
    for _,entry in ipairs({{f.dockRouteSummary,-resourceHeight-30,not routeOpen},
        {f.dockDisplaySummary,displayTop-26,not displayOpen}}) do
        local widget=entry[1]
        if widget then move(widget,entry[2]);widget:SetShown(self.optionsShown==true and entry[3]) end
    end
    for _,entry in ipairs({{f.mode,8,-24},{f.focus,107,-24},{f.routeSources,8,-55},
        {f.routeShape,8,-86},{f.fishingAreas,8,-117},{f.fishingFilter,107,-117}}) do
        local widget=entry[1]
        if widget then
            if widget.ClearAllPoints then widget:ClearAllPoints() end
            widget:SetPoint("TOPLEFT",f.optionsContent,"TOPLEFT",entry[2],entry[3]-resourceHeight)
        end
    end
    local routeWidgets={f.mode,f.focus,f.routeSources,f.routeShape,f.fishingAreas,f.fishingFilter}
    for i=1,6 do
        local widget=routeWidgets[i]
        if widget then
        -- Keep the existing two-column anchors and guard against re-showing
        -- controls while Map Options is closed.
        widget:SetShown(routeOpen and self.optionsShown==true)
        end
    end
    for _,entry in ipairs({{f.fishingExtraLayer,displayTop-19},
        {f.pinDisplay,displayTop-49},{f.skinningEvidence,displayTop-82},
        {f.routeRationale,rationaleTop},{f.fishingRecommend,recommendTop}}) do
        move(entry[1],entry[2])
        entry[1]:SetShown(displayOpen and self.optionsShown==true and
            ((entry[1]~=f.fishingExtraLayer and entry[1]~=f.fishingRecommend) or self.contentContext=="FISHING"))
    end
    if f.skinningDetailToggle then
        move(f.skinningDetailToggle,skinningTop)
        f.skinningDetailToggle:SetText((skinningOpen and "[-] " or "[+] ").."Material supply / Skinning")
        f.skinningDetailToggle:SetShown(self.optionsShown==true and displayOpen)
    end
    for _,entry in ipairs({{f.skinningPrevItem,skinningTop-34},
        {f.skinningNextItem,skinningTop-34},{f.skinningMaterialDetails,skinningTop-73},
        {f.skinningBank,skinningTop-150},{f.skinningAH,skinningTop-150}}) do
        if entry[1] then
            if entry[1].ClearAllPoints then entry[1]:ClearAllPoints() end
            local x=(entry[1]==f.skinningNextItem or entry[1]==f.skinningAH) and 108 or 8
            entry[1]:SetPoint("TOPLEFT",f.optionsContent,"TOPLEFT",x,entry[2])
            entry[1]:SetShown(self.optionsShown==true and displayOpen and skinningOpen)
        end
    end
    if f.dockInfoHeading then
        move(f.dockInfoHeading,infoTop)
        f.dockInfoHeading:SetText((self.dockInformationExpanded==false and "[+] " or "[-] ").."Route Information")
    end
    local infoOpen=self.dockInformationExpanded~=false
    -- Route presentation is updated by RefreshRouteExplanation. Avoid the
    -- former undefined journey/routeView/status globals in layout code.
    if f.dockInfoSummary then
        move(f.dockInfoSummary,infoTop-26)
        f.dockInfoSummary:SetShown(self.optionsShown==true and not infoOpen)
    end
    -- Hidden children cannot intercept mouse input when the information fold
    -- is closed, including with stale map results or while scrolling.
    for _,entry in ipairs({{f.whyRoute,infoTop-27},
        {f.dockLegend,infoTop-92},{f.dockOutcome,infoTop-141}}) do
        local widget=entry[1]
        if widget then
            move(widget,entry[2])
            widget:SetShown(self.optionsShown==true and infoOpen)
        end
    end
    -- "Close Options" is an escape affordance, never hidden by a fold.
    if f.dockBack then
        move(f.dockBack,infoOpen and infoTop-195 or infoTop-82)
        f.dockBack:SetShown(self.optionsShown==true)
        if f.dockBack.EnableMouse then f.dockBack:EnableMouse(self.optionsShown==true) end
    end
    -- The route's committed status is read-only and uses the same dock viewport;
    -- no popup or new navigation surface is required on compact screens.
    -- One persistent footer keeps every accordion section reachable when the
    -- Resources fold alone exceeds the compact ScrollFrame viewport.
    -- All four controls are part of the reserved footer, outside the map canvas.
    for _,entry in ipairs({{f.dockJumpResources,"Resources"},{f.dockJumpRoute,"Route"},
        {f.dockJumpDisplay,"Display"},{f.dockJumpInfo,"Info"}}) do
        if entry[1] then entry[1]:SetShown(self.optionsShown==true) end
    end
    -- Source-derived offsets for direct heading navigation in compact docks.
    -- Pure UI state: no duplicate ResourceBrowser or route scheduler.
    self._dockSectionOffsets={resources=0,route=math.max(0,3+resourceHeight),
        display=math.max(0,-displayTop),information=math.max(0,-infoTop)}
    -- The collapsed height excludes invisible actions and labels; keep the
    -- section header reachable and do not reserve a phantom hitbox.
    local infoExtent=infoOpen and math.max(239,195+42) or math.max(119,82+40)
    local contentHeight=math.max(160,-infoTop+infoExtent)
    if JLP.UILayout and JLP.UILayout.BoundedContentHeight then
        contentHeight=JLP.UILayout:BoundedContentHeight(contentHeight,160,16000)
    end
    if f.optionsContent.SetHeight then f.optionsContent:SetHeight(contentHeight) end
    local sc=f.optionsScroll
    if sc and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local viewHeight=sc.GetHeight and sc:GetHeight() or 138
        local offset=sc:GetVerticalScroll() or 0
        local bound=JLP.UILayout and JLP.UILayout:BoundedScrollOffset(offset,viewHeight,contentHeight)
            or math.max(0,math.min(offset,contentHeight-viewHeight))
        sc:SetVerticalScroll(bound)
    end
    -- All detached controls use the same visible/interactive lifecycle.
    -- A hidden folded section cannot retain a mousewheel target over map art.
    local sync=JLP.UILayout and JLP.UILayout.SyncHiddenInput
    if sync then
        for _,entry in ipairs({{f.dockResourcesHeading,self.optionsShown},
            {f.dockRouteHeading,self.optionsShown},
            {f.dockDisplayHeading,self.optionsShown},{f.dockInfoHeading,self.optionsShown},
            {f.optionsScroll,self.optionsShown},
            {f.dockRouteSummary,self.optionsShown and not routeOpen},
            {f.dockDisplaySummary,self.optionsShown and not displayOpen},
            {f.dockInfoSummary,self.optionsShown and not infoOpen}}) do
            if entry[1] then sync(JLP.UILayout,entry[1],entry[2]) end
        end
    end
    self:UpdateDockScrollControls()
    return true
end
-- Navigates the existing scroll viewport to a section already in the dock.
-- A folded section remains reachable by its heading, and disabled native
-- ScrollFrame APIs fail closed without changing gathering state.
function Window:FocusDockSection(section)
    local f=self.frame
    local sc=f and f.optionsScroll
    local positions=self._dockSectionOffsets
    if not (self.optionsShown and sc and sc.SetVerticalScroll and
        type(positions)=="table" and positions[section]) then return false end
    local content=f.optionsContent and f.optionsContent.GetHeight and f.optionsContent:GetHeight() or 0
    local viewport=sc.GetHeight and sc:GetHeight() or 0
    local target=positions[section]
    local layout=JLP.UILayout
    local bounded=layout and layout.BoundedScrollOffset and
        layout:BoundedScrollOffset(target,viewport,content) or
        math.max(0,math.min(target,math.max(0,content-viewport)))
    sc:SetVerticalScroll(bounded)
    self:UpdateDockScrollControls()
    return true
end
-- One-click access to an actionable section, including in compact viewports.
-- Unlike heading-only focus, a shortcut opens the existing fold before
-- scrolling. No duplicate controls, scheduler, selections or route owner.
function Window:OpenDockSection(section)
    if not self.optionsShown or not self.frame then return false,"OPTIONS_HIDDEN" end
    if section=="resources" then self.dockResourcesExpanded=true
    elseif section=="route" then self.dockRouteExpanded=true
    elseif section=="display" then self.dockDisplayExpanded=true
    elseif section=="information" then self.dockInformationExpanded=true
    else return false,"SECTION_INVALID" end
    self:UpdateDockSections()
    if section=="resources" and self.lastView then
        self:RefreshResourceList(self.lastView.mapID)
    end
    return self:FocusDockSection(section)
end
-- Search is purely a browser filter. Resetting it never clears persisted
-- resource choices or old advisory source evidence.
function Window:ClearResourceSearch()
    local f=self.frame
    if not (f and f.resourceSearch and f.resourceSearch.SetText) then
        return false,"SEARCH_UNAVAILABLE" end
    self.resourceOffset=0
    f.resourceSearch:SetText("")
    self:RefreshResourceList(self.lastView and self.lastView.mapID)
    return true
end
function Window:ApplyContentLayout(layout)
    local f=self.frame
    if not f or not f.sidebar or not layout then return end
    local minimal=layout.breakpoint=="MINIMAL"
    if f.resourceInfo then f.resourceInfo:SetShown(not minimal) end
    -- Fishing-only controls must be inside the measured 193-unit minimum sidebar.
    if f.fishingFocusNotice then
        if f.fishingFocusNotice.ClearAllPoints then f.fishingFocusNotice:ClearAllPoints() end
        f.fishingFocusNotice:SetPoint("TOPLEFT",f.sidebar,"TOPLEFT",11,minimal and -87 or -104)
    end
    if f.fishingShowHerbs then
        if f.fishingShowHerbs.ClearAllPoints then f.fishingShowHerbs:ClearAllPoints() end
        f.fishingShowHerbs:SetPoint("TOPLEFT",f.sidebar,"TOPLEFT",11,minimal and -138 or -162)
    end
    if f.resourceRows and not self._resourceEditorInDock then
        for i,b in ipairs(f.resourceRows) do
            if b.ClearAllPoints then b:ClearAllPoints() end
            b:SetPoint("TOPLEFT",f.resourceListContainer or f.resourcesSection or f.sidebar,"TOPLEFT",
                11,-(minimal and 91 or 111)-(i-1)*29-(self._resourceInfoExtra or 0))
        end
        -- Hide unused buttons before a new layer/browser snapshot arrives.
        -- This prevents previously visible rows from covering footer controls.
        if not self.resourceMapID and not self.lastView then
            for _,b in ipairs(f.resourceRows) do b.resourceKey=nil;b:Hide() end
        end
    end
    -- Dock-owned pager must never acquire a cross-container sidebar anchor.
    if not self._resourceEditorInDock and f.resourcePrev and f.resourceNext and f.resourcePages then
        local host=f.resourceFooterContainer or f.resourcesSection or f.sidebar
        for _,b in ipairs({f.resourcePrev,f.resourceNext,f.resourcePages}) do
            if b.ClearAllPoints then b:ClearAllPoints() end
        end
        f.resourcePrev:SetPoint("BOTTOMLEFT",host,"BOTTOMLEFT",11,80)
        f.resourceNext:SetPoint("BOTTOMLEFT",host,"BOTTOMLEFT",178,80)
        f.resourcePages:SetPoint("BOTTOMLEFT",host,"BOTTOMLEFT",75,88)
    end
    -- Dock both advanced workspaces INSIDE the reserved right rail. Neither
    -- panel can intercept map pan/zoom; compact heights scroll instead of
    -- letting off-screen controls capture input across the canvas.
    if f.optionsPanel then
        local railHeight=math.max(1,layout.sidebarHeight or (layout.height-197))
        for _,panel in ipairs({f.optionsPanel,f.detailsPanel}) do
            if panel then
                if panel.ClearAllPoints then panel:ClearAllPoints() end
                panel:SetPoint("TOPLEFT",f.sidebar,"TOPLEFT",0,0)
                panel:SetSize(f.sidebar.GetWidth and f.sidebar:GetWidth() or 228,railHeight)
            end
        end
        if f.detailsText then
            f.detailsText:SetWidth(190)
            if f.detailsText.SetHeight then f.detailsText:SetHeight(math.max(24,railHeight-112)) end
        end
        if f.detailsPage and f.detailsPage.ClearAllPoints then
            f.detailsPage:ClearAllPoints()
            f.detailsPage:SetPoint("BOTTOMLEFT",f.detailsPanel,"BOTTOMLEFT",99,20)
        end
        if f.optionsScroll and f.optionsScroll.SetSize then
            local g=(JLP.UITheme and JLP.UITheme.gathering) or {dockContentHeight=438,dockScrollFooter=55,dockMinViewport=40,dockScrollStep=35}
            local oldHeight=f.optionsScroll.GetHeight and f.optionsScroll:GetHeight() or 138
            local offset=f.optionsScroll.GetVerticalScroll and f.optionsScroll:GetVerticalScroll() or 0
            local newHeight=JLP.UILayout and JLP.UILayout.DockViewportHeight and
                JLP.UILayout:DockViewportHeight(railHeight,g.dockScrollTop or 38,
                    math.max(90,g.dockScrollFooter or 55),g.dockMinViewport or 40) or
                math.max(g.dockMinViewport or 40,railHeight-(g.dockScrollTop or 38)-math.max(90,g.dockScrollFooter or 55))
            f.optionsScroll:SetSize(210,newHeight)
            local layout=JLP.UILayout
            local contentHeight=f.optionsContent and f.optionsContent.GetHeight and
                f.optionsContent:GetHeight() or g.dockContentHeight
            local nextOffset=layout and layout:PreserveScrollRatio(offset,oldHeight,newHeight,contentHeight) or 0
            if f.optionsScroll.SetVerticalScroll then f.optionsScroll:SetVerticalScroll(nextOffset) end
            self:UpdateDockScrollControls()
        end
    end
    if f.dockRouteHeading and self.UpdateDockSections then self:UpdateDockSections() end
    self:UpdateZoomCaption()
    -- At the smallest width the second chrome-opacity slider would extend
    -- beneath the fixed bottom-right Pins control (both have real hitboxes).
    local showSecondOpacity=(tonumber(layout.width) or 0)>=760
    if f.chromeText then f.chromeText:SetShown(showSecondOpacity) end
    if f.chromeSlider then f.chromeSlider:SetShown(showSecondOpacity) end
    if f.resourceRows and self.lastView then self:RefreshResourceList(self.lastView.mapID) end
end
function Window:SetBackgroundOpacity(value)
    value=clamp(tonumber(value) or 0.85,0.2,1)
    local f=self.frame
    if f then
        -- Map-art opacity is independent from the surrounding UI chrome.
        if f.mapBackground and f.mapBackground.SetAlpha then f.mapBackground:SetAlpha(value) end
        for _,tex in ipairs(f.canvas and f.canvas.fishingTiles or {}) do
            if tex.SetAlpha then tex:SetAlpha(value) end
        end
        for _,tex in ipairs(f.canvas and f.canvas.jlpRevealTextures or {}) do
            if tex.SetAlpha then tex:SetAlpha(value) end
        end
        if f.opacityText then f.opacityText:SetText("Map background: "..math.floor(value*100+0.5).."%") end
    end
    local state=viewState()
    if state then
        local prior=state:GetStandaloneSettings()
        if prior and math.abs(prior.backgroundOpacity-value)>0.0001 then
            state:SetStandaloneSettings({backgroundOpacity=value})
        end
    end
end
function Window:SetChromeOpacity(value)
    value=clamp(tonumber(value) or 1,0.35,1)
    local f=self.frame
    if f then
        for _,texture in pairs(f.__jlpSkin or {}) do
            if texture.SetAlpha then texture:SetAlpha(value) end
        end
        for _,region in ipairs(f.chromeTargets or {}) do
            if region and region.SetAlpha then region:SetAlpha(value) end
        end
        if f.chromeText then f.chromeText:SetText("UI chrome: "..math.floor(value*100+0.5).."%") end
    end
    local state=viewState()
    if state then
        local prior=state:GetStandaloneSettings()
        if prior and math.abs(prior.chromeOpacity-value)>0.0001 then
            state:SetStandaloneSettings({chromeOpacity=value})
        end
    end
end
-- One transaction for changes which invalidate route authority. The shared
-- route service remains the sole scheduler/generation owner; the view only
-- retires its transient receipt and refuses stale callbacks or overlays.
function Window:InvalidateRouteContext(reason)
    self._routeRequestSerial=(self._routeRequestSerial or 0)+1
    self._routeProgressToken=nil
    self._mapPresentation=nil
    self._lastOverlay=nil
    self.routeResult=nil
    self.routeFeedback=nil
    local route=JLP:GetModule("GatheringRouteService")
    if route and type(route.Cancel)=="function" then
        local status=self.lastView and type(route.GetStatusForMap)=="function" and
            route:GetStatusForMap(self.lastView.mapID)
        -- Even when a changed shared context makes GetStatusForMap return
        -- NO_ACTIVE_ROUTE, the service may still own a running old job.
        if status=="GENERATING" or status=="READY" or
            route._schedulerActive==true or route._presentationContext~=nil then
            local ok,accepted,why=pcall(route.Cancel,route,reason or "VIEW_CONTEXT_CHANGED")
            if not ok or accepted~=true then
                if type(route.QuarantineUnconfirmedCancellation)=="function" then
                    pcall(route.QuarantineUnconfirmedCancellation,route,why or "CANCEL_UNCONFIRMED")
                end
                local overlay=JLP:GetModule("GatheringMapOverlay")
                if overlay and overlay.Clear and self.frame and self.frame.canvas then
                    pcall(overlay.Clear,overlay,self.frame.canvas)
                end
                self.routeFeedback="Route cancellation not confirmed · "..tostring(why or "RETRY_STOP")
                return false,why or "CANCEL_NOT_CONFIRMED"
            end
        end
    end
    if self.frame then self.frame.forceRedraw=true end
    return true
end
function Window:OnContentChange(preserveRouteReceipt)
    -- A new explicit user choice invalidates pending zone recommendations.
    -- Route service's successful Start is followed by OnContentChange(true),
    -- which must NOT abort the job it just accepted.
    if preserveRouteReceipt~=true then
        self._smartGenerateSerial=(self._smartGenerateSerial or 0)+1
    end
    self:CloseZoneMenu()
    if preserveRouteReceipt~=true then self:InvalidateRouteContext("USER_SELECTION_CHANGED") end
    self._refreshBudget=nil
    local page=JLP.UIPages and JLP.UIPages.Secondaries
    if page and page.frame and page:GetMode()=="FISHING" then page:Refresh() end
    self:Refresh()
end
function Window:SelectZone(direction)
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local browser=JLP:GetModule("ForeverFishingZoneBrowser")
    local current=map and map:GetCurrentZone()
    local ok=current and browser and browser:Step(current,direction)
    if ok then self:OnContentChange() end
    return ok or false
end
-- One transient dropdown surface for both continent buttons. This remains
-- inside the standalone window and owns no SavedVariables or gathering data.
function Window:CloseZoneMenu()
    local f=self.frame
    if f and f.zoneMenu then
        if JLP.UIInteraction and JLP.UIInteraction.HideTooltipTree then
            JLP.UIInteraction:HideTooltipTree(f.zoneMenu)
        end
        f.zoneMenu:Hide()
    end
    self._openZoneContinent=nil
end
-- Temporary continent browsing is VISUAL ONLY: the shared selected zone,
-- routes, Smart assessment, resource selections and SavedVariables are unchanged.
-- This is intentionally not represented as a synthetic zone in ViewService.
function Window:ApplyContinentCanvasLayout()
    local f=self.frame
    if not (f and f.canvas and f.sidebar) then return end
    local continent=self._continentPreview~=nil
    local resources=not continent and self.resourcesVisible~=false
    f.sidebar:SetShown(resources)
    if f.rightRailHeader then f.rightRailHeader:SetShown(resources) end
    f.canvas:ClearAllPoints()
    f.canvas:SetPoint("TOPLEFT",f,"TOPLEFT",22,-126)
    if resources then f.canvas:SetPoint("BOTTOMRIGHT",f.sidebar,"BOTTOMLEFT",-10,44)
    else f.canvas:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-22,116) end
    if f.edit and f.edit.SetEnabled then f.edit:SetEnabled(not continent) end
    -- Hide zone-specific footer actions; restore their exact prior visibility.
    if continent and not self._continentFooterVisibility then
        self._continentFooterVisibility={}
        for _,name in ipairs({"sources","routeWhy","pinDisplay"}) do
            local widget=f[name]
            if widget then
                self._continentFooterVisibility[name]=widget.IsShown and widget:IsShown() or false
            end
        end
    end
    for _,name in ipairs({"sources","routeWhy","pinDisplay"}) do
        local widget=f[name]
        if widget and widget.SetShown then
            if continent then widget:SetShown(false)
            elseif self._continentFooterVisibility then
                widget:SetShown(self._continentFooterVisibility[name]==true)
            end
        end
    end
    if not continent then self._continentFooterVisibility=nil end
end
function Window:ExitContinentPreview()
    if not self._continentPreview then return false end
    self._continentPreview=nil
    self.lastArt=nil
    self._lastViewport=nil
    self._lastPresentedToken=nil
    if self.frame then
        self.frame.forceRedraw=true
        self:ApplyContinentCanvasLayout()
        local canvas=self.frame.canvas
        if canvas then
            canvas.continentRightDown=nil
            canvas.zonePointerStart=nil
            canvas.panCursor=nil
            local map=JLP:GetModule("ForeverFishingMapCanvas")
            if map then map:SetViewport(canvas,DEFAULT_MAP_ZOOM,0.5,0.5) end
        end
    end
    return true
end
function Window:OpenContinentAtCursor(screenX,screenY)
    local f=self.frame
    if not (f and f.canvas and self.lastView and self.lastArt) then
        return false,"ZONE_ART_UNAVAILABLE" end
    if self._continentPreview then return false,"ALREADY_CONTINENT" end
    local nav=JLP:GetModule("GatheringMapZoneClick")
    local position,reason
    if nav then position,reason=nav:CursorToMap(f.canvas,self.lastArt,screenX,screenY) end
    if not position then return false,reason or "CLICK_OUTSIDE_MAP" end
    local browser=JLP:GetModule("ForeverFishingZoneBrowser")
    local zoneID=self.lastView.mapID
    local continentKey=browser and browser:IsContinentZone(zoneID,"KALIMDOR") and "KALIMDOR" or
        browser and browser:IsContinentZone(zoneID,"EASTERN_KINGDOMS") and "EASTERN_KINGDOMS" or nil
    if not continentKey then return false,"ZONE_CONTINENT_UNAVAILABLE" end
    local continentID=browser:GetContinentMapID(continentKey)
    local svc=source()
    local art,artReason
    if svc then art,artReason=svc:GetArt(continentID) end
    if not (art and art.mapID==continentID) then
        return false,artReason or "CONTINENT_ART_UNAVAILABLE" end
    self:CloseZoneMenu()
    -- Clear existing POINTs, overlays, route strokes, player marker and reveal.
    -- Clearing this CANVAS does not cancel or mutate the service route session.
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    if map then map:Clear(f.canvas) end
    self._continentPreview={mapID=continentID,key=continentKey,art=art,
        sourceZoneID=zoneID}
    self.lastArt=art
    self._lastViewport=nil
    self._lastPresentedToken=nil
    self._mapPresentation=nil
    self._lastOverlay=nil
    self._lastRoutes=nil
    self._lastSpatial=nil
    self._lastStats=nil
    self._lastRouteOverlaySubmitted=false
    self._lastRouteStrokesSubmitted=0
    self._panDirty=nil
    f.canvas.panCursor=nil
    f.canvas.zonePointerStart=nil
    self:ApplyContinentCanvasLayout()
    if map then map:SetViewport(f.canvas,1,0.5,0.5) end
    f.forceRedraw=true
    local ready,why=self:Refresh()
    if not ready then
        -- Never trap the user in an unusable blank continent viewer.
        self:ExitContinentPreview()
        self:Refresh()
        return false,why or "CONTINENT_RENDER_FAILED"
    end
    return true,"CONTINENT_OPENED"
end
function Window:RefreshContinentView(reloadID)
    local preview=self._continentPreview
    local f=self.frame
    local svc=source()
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    if not (preview and f and f.canvas and svc and map) then
        return false,"CONTINENT_VIEW_UNAVAILABLE" end
    self:ApplyContinentCanvasLayout()
    local art,reason=svc:GetArt(preview.mapID,reloadID==preview.mapID)
    if not art then
        f.fallback:SetText("Continent artwork unavailable: "..tostring(reason))
        f.fallback:Show()
        return false,reason or "CONTINENT_ART_UNAVAILABLE" end
    preview.art=art
    local painted,renderReason=svc:RenderArt(f.canvas,art,f.forceRedraw==true)
    if not painted then
        f.fallback:SetText("Continent artwork unavailable: "..tostring(renderReason))
        f.fallback:Show()
        return false,renderReason or "CONTINENT_RENDER_FAILED" end
    self.lastArt=art
    f.forceRedraw=nil
    local name=preview.key=="KALIMDOR" and "Kalimdor" or "Eastern Kingdoms"
    f.title:SetText("Gathering Map · "..name)
    f.status:SetText("Continent overview · click a zone to open its map")
    f.routeDetail:SetText("Right-clicked from zone · no gathering routes or pins on continent overview")
    if f.fallback then f.fallback:Hide() end
    if f.generate then f.generate:SetEnabled(false);f.generate:SetAlpha(0.45) end
    if f.clear then f.clear:SetEnabled(false);f.clear:SetAlpha(0.45) end
    if f.zoomRoute then f.zoomRoute:SetEnabled(false);f.zoomRoute:SetAlpha(0.45) end
    self:UpdateZoomCaption()
    return true,"CONTINENT_VIEW"
end
function Window:SelectContinentZone(mapID,continentKey)
    local browser=JLP:GetModule("ForeverFishingZoneBrowser")
    local canvasMap=JLP:GetModule("ForeverFishingMapCanvas")
    local state=viewState()
    if not (browser and browser:IsContinentZone(mapID,continentKey) and
        canvasMap and canvasMap:GetZoneByID(mapID) and state) then
        return false,"CLIENT_ZONE_UNAVAILABLE"
    end
    -- Do not strand the viewport on a zone whose Blizzard native art is
    -- unavailable. Probe the existing LRU service before changing state.
    local artService=JLP:GetModule("GatheringMapViewService")
    if artService and type(artService.GetArt)=="function" then
        local art,reason=artService:GetArt(mapID)
        if not art then
            if type(JLP.Print)=="function" then
                JLP:Print("Cannot open selected zone map: "..tostring(reason or "NATIVE_ART_UNAVAILABLE"))
            end
            return false,reason or "NATIVE_ART_UNAVAILABLE"
        end
    end
    -- First retire the old route/view receipt, then store the exact selected
    -- mapID through the same source of truth as the previous zone buttons.
    local ok,why=state:SelectMap(mapID,"CONTINENT")
    if ok then
        self:ExitContinentPreview()
        self:CloseZoneMenu()
        self:OnContentChange()
    end
    return ok,why
end
function Window:ToggleContinentZones(continentKey)
    local f=self.frame
    if not (f and f.zoneMenu and f.zoneMenuScroll) then return false,"MENU_UNAVAILABLE" end
    if self._openZoneContinent==continentKey and f.zoneMenu:IsShown() then
        self:CloseZoneMenu();return true
    end
    local browser=JLP:GetModule("ForeverFishingZoneBrowser")
    local zones,reason=browser and browser:DiscoverContinent(continentKey)
    if type(zones)~="table" then zones={};reason=reason or "BROWSER_UNAVAILABLE" end
    local sourceButton=continentKey=="KALIMDOR" and f.kalimdor or f.easternKingdoms
    if not sourceButton then return false,"CONTINENT_INVALID" end
    local menu=f.zoneMenu
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT",sourceButton,"BOTTOMLEFT",0,-4)
    -- Stay inside the owner at MIN_H and offer scrolling for long native lists.
    local height=math.max(145,math.min(390,(f:GetHeight() or MIN_H)-108,
        math.max(1,#zones)*25+12))
    menu:SetSize(240,height)
    local scroll=f.zoneMenuScroll
    scroll:Resize(232,height-10,216)
    scroll:SetContentHeight(math.max(height-10,#zones*25+8))
    scroll:ScrollTo(0)
    local rows=f.zoneMenuRows
    local count=math.max(1,#zones)
    for i=1,count do
        local b=rows[i]
        if not b then
            b=JLP.UIWidgets:Button(scroll.content,"",211)
            b:SetHeight(24)
            b:SetPoint("TOPLEFT",scroll.content,"TOPLEFT",3,-4-(i-1)*25)
            if b.EnableMouseWheel then b:EnableMouseWheel(true) end
            b:SetScript("OnMouseWheel",function(_,delta) scroll:ScrollWheel(delta) end)
            rows[i]=b
        end
        local entry=zones[i]
        b.zoneID=entry and entry.mapID or nil
        b.zoneContinent=continentKey
        if entry then
            b:SetText(entry.name)
            b:SetEnabled(true)
            b:SetScript("OnClick",function(self)
                Window:SelectContinentZone(self.zoneID,self.zoneContinent)
            end)
            b:SetScript("OnEnter",function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:SetText(entry.name)
                GameTooltip:AddLine("WoW client zone · uiMapID "..entry.mapID,0.65,0.79,0.91)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave",function(self)
                if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self) end
            end)
        else
            b:SetText("No available zones ("..tostring(reason)..")")
            b:SetEnabled(false)
            b:SetScript("OnClick",nil)
        end
        b:Show()
    end
    for i=count+1,#rows do rows[i]:Hide() end
    if menu.SetFrameLevel and f.GetFrameLevel then
        menu:SetFrameLevel(f:GetFrameLevel()+75)
    end
    self._openZoneContinent=continentKey
    menu:Show()
    return #zones>0,reason
end
-- A click on an adjacent native zone area opens that zone through the SAME
-- validated continent browser as the explicit Kalimdor/Eastern Kingdoms menus.
-- Never treat a drag, a pin click, empty map margin or a zone label alone as
-- an authoritative map transition. Route generation remains user-triggered.
function Window:OpenZoneAtCursor(screenX,screenY)
    local f=self.frame
    local view=self.lastView
    local art=self.lastArt
    local displayedMapID=self._continentPreview and self._continentPreview.mapID or
        (view and view.mapID)
    if not (f and f.canvas and displayedMapID and art and displayedMapID==art.mapID) then
        self._lastZoneClick={status="CURRENT_ART_UNAVAILABLE"}
        return false,"CURRENT_ART_UNAVAILABLE" end
    local click=JLP:GetModule("GatheringMapZoneClick")
    local candidate,reason
    if click then candidate,reason=click:Resolve(f.canvas,art,displayedMapID,screenX,screenY) end
    if candidate and self._continentPreview and candidate.continent~=self._continentPreview.key then
        candidate=nil;reason="ZONE_OUTSIDE_DISPLAYED_CONTINENT"
    end
    if not candidate then
        self._lastZoneClick={status=reason or "ZONE_CLICK_UNAVAILABLE",source=displayedMapID}
        return false,reason or "ZONE_CLICK_UNAVAILABLE" end
    local ok,why=self:SelectContinentZone(candidate.mapID,candidate.continent)
    self._lastZoneClick={status=ok and "ZONE_OPENED" or (why or "ZONE_REJECTED"),
        source=displayedMapID,target=candidate.mapID,name=candidate.name,
        x=candidate.x,y=candidate.y}
    return ok,why
end
function Window:BeginMapPointer(canNavigate)
    local canvas=self.frame and self.frame.canvas
    if not (canvas and type(GetCursorPosition)=="function") then return false end
    local x,y=GetCursorPosition()
    if type(x)~="number" or type(y)~="number" then return false end
    canvas.panCursor={x=x,y=y}
    -- The origin is never updated by frame-rate-based pan previews.
    canvas.zonePointerStart={x=x,y=y,moved=false,navigate=canNavigate==true,
        mapID=self._continentPreview and self._continentPreview.mapID or
            (self.lastView and self.lastView.mapID) or nil}
    return true
end
function Window:UpdateMapPointerMovement(x,y)
    local c=self.frame and self.frame.canvas
    local start=c and c.zonePointerStart
    if not start or start.moved or type(x)~="number" or type(y)~="number" then return end
    local scale=c.GetEffectiveScale and c:GetEffectiveScale() or 1
    local distance=7*(type(scale)=="number" and scale>0 and scale or 1)
    if math.abs(x-start.x)>distance or math.abs(y-start.y)>distance then
        start.moved=true
    end
end
function Window:EndMapPointer(canNavigate)
    local canvas=self.frame and self.frame.canvas
    if not canvas then return false,"CANVAS_UNAVAILABLE" end
    local press=canvas.zonePointerStart
    local x,y
    if type(GetCursorPosition)=="function" then x,y=GetCursorPosition() end
    if press then self:UpdateMapPointerMovement(x,y) end
    canvas.zonePointerStart=nil
    -- Do not pan for tiny sub-threshold click jitter. A real drag still
    -- commits its final delta even if released between 23ms preview frames.
    local wasPanDirty=self._panDirty==true
    if press and not press.moved and not wasPanDirty then
        canvas.panCursor=nil
        self.panElapsed=0
    else
        self:FinishPan()
    end
    if press and press.navigate and canNavigate==true and not press.moved and
        not wasPanDirty and press.mapID==
        (self._continentPreview and self._continentPreview.mapID or
            (self.lastView and self.lastView.mapID)) and
        type(x)=="number" and type(y)=="number" then
        return self:OpenZoneAtCursor(x,y)
    end
    return false,"PAN_OR_NON_NAVIGATION_CLICK"
end
function Window:UseCurrentZone()
    self:ExitContinentPreview()
    self:CloseZoneMenu()
    local state=viewState()
    if state and state:SelectMap(nil) then self:OnContentChange();return true end
    return false
end
function Window:ToggleLayer(key)
    local state=viewState()
    local options=state and state:GetSnapshot()
    if options and options.mode=="SMART_PROFESSION" then
        return false,"SMART_LAYER_AUTOMATIC"
    end
    local ctrl=JLP:GetModule("GatheringMapLayerController")
    if ctrl and self.lastView and ctrl:ToggleLayer(self.lastView.mapID,key) then
        self:OnContentChange();return true
    end
    return false
end
function Window:SetRouteFeedback(ok,reason,status)
    local module=JLP:GetModule("GatheringRouteResult")
    local result=module and module:FromAttempt(ok,reason,status)
    local route=JLP:GetModule("GatheringRouteService")
    if result and module and type(module.Bind)=="function" then
        module:Bind(result,self.lastView and self.lastView.mapID,route)
    end
    self.routeResult=result
    local labelText=JLP.UIWidgets and type(JLP.UIWidgets.GatheringFeedback)=="function" and
        JLP.UIWidgets:GatheringFeedback(nil,result)
    self.routeFeedback=labelText or (result and result.message) or (ok and "Generating route..." or
        "Route unavailable: "..tostring(reason or "ROUTE_UNAVAILABLE"))
    if ok and route and type(route.MarkFeedbackStaged)=="function" and
        self.lastView and self.lastView.mapID then
        route:MarkFeedbackStaged(self.lastView.mapID)
    end
    if result and result.identityPolicy=="transient-unverified" and
        type(JLP.Print)=="function" then JLP:Print(self.routeFeedback) end
    return result
end
-- One explicit Generate owns both zone recommendation and route generation.
-- Zone choice is evidence-qualified, never performed by a Focus toggle.
-- A small editor on the existing shared map. Draft choices never alter an
-- active task; Start is the only operation which freezes a new selection.
function Window:RefreshManualTargetUI()
    local state=viewState();local task=state and state:GetManualTargetTask()
    local f=self.frame
    if f and f.manualTargetButton then
        f.manualTargetButton:SetText(task and not task.dismissed and
            ("Task "..task.collected.."/"..task.total) or "Material task")
    end
    local p=self.manualTargetEditor
    if not p or not p:IsShown() then return end
    p.progress:SetText(task and (task.professionKey.." · "..task.status.."\n"..
        task.collected.." / "..task.total.." collected · "..task.remaining.." remaining\n"..
        tostring(task.proofStatus)) or "No manual collection task · existing bags never count")
    local draft=self._manualTaskDraft
    for i,row in ipairs(p.rows) do
        local choice=draft and draft.choices[(draft.offset or 0)+i]
        row.choice=choice
        if choice then
            local key=(choice.resourceKey or "")..":"..choice.itemID
            row:SetText((draft.selected[key] and "[x] " or "[ ] ")..choice.name)
            row:Show()
        else row:Hide() end
    end
end
function Window:SetManualTargetDraftProfession(key)
    local state=viewState()
    local mapID=self.lastView and self.lastView.mapID
    self._manualTaskDraft={professionKey=key,choices=state and state:GetManualTargetChoices(key,mapID) or {},selected={},offset=0,mapID=mapID}
    self:RefreshManualTargetUI()
end
function Window:StartManualTargetFromEditor()
    local p=self.manualTargetEditor;local draft=self._manualTaskDraft;local state=viewState()
    if not p or not draft or not state then return false,"EDITOR_UNAVAILABLE" end
    local items,resources,first={},{},nil
    for _,row in ipairs(draft.choices) do
        if draft.selected[(row.resourceKey or "")..":"..row.itemID] then
            items[row.itemID]=true;first=first or row.itemID
            if row.resourceKey then resources[row.resourceKey]=true end
        end
    end
    local ok,why=state:SelectSupplyGoal({status="MANUAL_TARGET",professionKey=draft.professionKey,itemID=first,
        required=tonumber(p.total:GetText()),selectedItemIDs=items,selectedResourceKeys=resources,mapID=draft.mapID})
    p.feedback:SetText(ok and "Started: only new qualified collection receipts count." or tostring(why or "Select materials and one total."))
    self:RefreshManualTargetUI();self:Refresh()
    return ok,why
end
function Window:ToggleManualTargetEditor()
    if self.manualTargetEditor then
        self.manualTargetEditor:SetShown(not self.manualTargetEditor:IsShown())
        self:RefreshManualTargetUI();return
    end
    if not self.frame then return end
    local p=CreateFrame("Frame",nil,self.frame)
    self.manualTargetEditor=p;p:SetSize(400,440);p:SetPoint("CENTER",self.frame,"CENTER",0,0)
    if p.SetFrameStrata then p:SetFrameStrata("DIALOG") end
    if p.SetFrameLevel and self.frame.GetFrameLevel then p:SetFrameLevel(self.frame:GetFrameLevel()+30) end
    local bg=p:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetTexture("Interface\\Buttons\\WHITE8X8");bg:SetVertexColor(.03,.07,.11,.98)
    local title=label(p,"Manual material task — one combined total","GameFontHighlight")
    title:SetPoint("TOPLEFT",12,-12)
    button(p,"X",25,"TOPRIGHT",-5,-5,function()p:Hide()end)
    for index,key in ipairs({"MINING","HERBALISM","FISHING","SKINNING"}) do
        button(p,key,92,"TOPLEFT",10+(index-1)*96,-38,function()Window:SetManualTargetDraftProfession(key)end)
    end
    p.rows={}
    for i=1,6 do
        local row=button(p,"",376,"TOPLEFT",12,-70-(i-1)*28,function(self)
            local draft=Window._manualTaskDraft;local choice=self.choice
            if draft and choice then
                local key=(choice.resourceKey or "")..":"..choice.itemID
                draft.selected[key]=not draft.selected[key];Window:RefreshManualTargetUI()
            end
        end)
        p.rows[i]=row
    end
    button(p,"<",35,"TOPLEFT",12,-240,function()
        local draft=Window._manualTaskDraft;if draft then draft.offset=math.max(0,draft.offset-6);Window:RefreshManualTargetUI() end
    end)
    button(p,">",35,"TOPLEFT",53,-240,function()
        local draft=Window._manualTaskDraft;if draft then draft.offset=math.min(math.max(0,#draft.choices-6),draft.offset+6);Window:RefreshManualTargetUI() end
    end)
    local caption=label(p,"Total units:");caption:SetPoint("TOPLEFT",100,-248)
    p.total=CreateFrame("EditBox",nil,p,"InputBoxTemplate");p.total:SetSize(70,24);p.total:SetPoint("TOPLEFT",185,-241)
    if p.total.SetAutoFocus then p.total:SetAutoFocus(false) end
    if p.total.SetNumeric then p.total:SetNumeric(true) end
    p.total:SetText("")
    button(p,"Start new",112,"TOPLEFT",270,-240,function()Window:StartManualTargetFromEditor()end)
    for i,entry in ipairs({{"Pause","PauseManualTarget"},{"Resume","ResumeManualTarget"},{"Stop","StopManualTarget"}}) do
        button(p,entry[1],120,"TOPLEFT",12+(i-1)*128,-273,function()
            local state=viewState();local ok,why=state and state[entry[2]] and state[entry[2]](state)
            p.feedback:SetText(ok and entry[1] or tostring(why or "No task"));Window:RefreshManualTargetUI();Window:Refresh()
        end)
    end
    p.progress=label(p,"");p.progress:SetPoint("TOPLEFT",12,-307);p.progress:SetWidth(376);p.progress:SetHeight(66)
    p.feedback=label(p,"Choose exact materials. Start again to change a frozen selection.")
    p.feedback:SetPoint("TOPLEFT",12,-381);p.feedback:SetWidth(376);p.feedback:SetHeight(48)
    self:SetManualTargetDraftProfession(self.contentContext=="FISHING" and "FISHING" or self.resourceProfession or "MINING")
    self:RefreshManualTargetUI()
end

function Window:GenerateFishingSectorReview()
    local manual=viewState();local task=manual and manual:GetManualTargetTask()
    if task and not task.dismissed and task.status~="ACTIVE" then return false,"MANUAL_TARGET_"..task.status end
    local view=self.lastView
    local state=viewState()
    local options=state and state:GetSnapshot()
    local planner=JLP:GetModule("FishingSectorItinerary70450")
    -- Do not wrap a multi-return Build in `and`: Lua reduces it to one
    -- value and drops the source-qualified failure reason needed by the UI.
    local plan,reason
    if planner and view then
        plan,reason=planner:Build(view.mapID,
            options and options.routeShape or "LOOP",view.playerPosition)
    else
        reason=not view and "MAP_UNAVAILABLE" or "FISHING_SECTOR_PLANNER_UNAVAILABLE"
    end
    self.fishingAreaPlan=plan
    self.fishingAdvice=plan and planner:Describe(plan) or
        "Fishing sector review unavailable: "..tostring(reason or "DATA_UNAVAILABLE")
    self:Refresh()
    return plan~=nil,plan and "HISTORICAL_SECTOR_REVIEW_ONLY" or reason
end
function Window:GenerateRoute()
    local manual=viewState();local task=manual and manual:GetManualTargetTask()
    if task and not task.dismissed and task.status~="ACTIVE" then return false,"MANUAL_TARGET_"..task.status end
    if self._continentPreview then return false,"CONTINENT_NAVIGATION_ONLY" end
    local shared=viewState()
    local snapshot=shared and shared:GetSnapshot()
    if snapshot and snapshot.mode=="SMART_PROFESSION" then
        if self.contentContext=="FISHING" and not self.includeGathering then
            return self:GenerateFishingSectorReview()
        end
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        local current=map and map:GetCurrentZone()
        local engine=JLP:GetModule("GatheringZoneSuitability")
        if not current or not engine or not self.lastView then
            self:SetRouteFeedback(false,"ZONE_RECOMMENDATION_UNAVAILABLE")
            self:Refresh();return false,"ZONE_RECOMMENDATION_UNAVAILABLE"
        end
        self._smartGenerateSerial=(self._smartGenerateSerial or 0)+1
        local serial=self._smartGenerateSerial
        local focus=snapshot.focus
        local originalMap=self.lastView.mapID
        local requestSelected=snapshot.selectedMapID
        local started,why=engine:StartRecommendation(current,focus,function(best,reason)
            if self._smartGenerateSerial~=serial or not (self.frame and self.frame.IsShown and self.frame:IsShown()) then return end
            local active=shared and shared:GetSnapshot()
            if not active or active.mode~="SMART_PROFESSION" or active.focus~=focus or
                active.selectedMapID~=requestSelected or
                not self.lastView or self.lastView.mapID~=originalMap then return end
            if not best or not best.mapID then
                self:SetRouteFeedback(false,reason or "NO_SUITABLE_REFERENCE_ZONE")
                self:Refresh();return
            end
            -- FROM_PLAYER geometry is not meaningful in a different zone.
            if best.mapID~=originalMap and active.routeShape=="FROM_PLAYER" then
                self:SetRouteFeedback(false,"SELECT_LOOP_FOR_REMOTE_ZONE")
                self:Refresh();return
            end
            if best.mapID~=originalMap then
                local canvas=JLP:GetModule("ForeverFishingMapCanvas")
                local artService=JLP:GetModule("GatheringMapViewService")
                if not (canvas and canvas:GetZoneByID(best.mapID)) or
                    (artService and type(artService.GetArt)=="function" and not artService:GetArt(best.mapID)) then
                    self:SetRouteFeedback(false,"RECOMMENDED_NATIVE_MAP_UNAVAILABLE")
                    self:Refresh();return
                end
                local ok,err=shared:SelectMap(best.mapID)
                if not ok then self:SetRouteFeedback(false,err);self:Refresh();return end
                self:Refresh()
                if not self.lastView or self.lastView.mapID~=best.mapID then
                    self:SetRouteFeedback(false,"RECOMMENDED_MAP_UNAVAILABLE");self:Refresh();return
                end
            end
            self._smartLastRecommendation={mapID=best.mapID,name=best.name,
                focus=focus,score=best.score,confidence=best.confidence,
                eligibleCells=best.eligibleCells,provenance="HISTORICAL_REFERENCE_ONLY"}
            local routeOK,routeWhy=self:GenerateCurrentZoneRoute()
            if not routeOK then
                self:SetRouteFeedback(false,routeWhy or "ROUTE_UNAVAILABLE")
                self:Refresh()
            end
            if type(JLP.Print)=="function" then
                JLP:Print("Smart "..focus.." · "..tostring(best.name or best.mapID)..
                    " · historical score "..tostring(best.score).." ("..tostring(best.confidence)..
                    " confidence; no live yield or spawn guarantee)")
            end
        end)
        if not started then
            self:SetRouteFeedback(false,why or "ZONE_RECOMMENDATION_FAILED")
            self:Refresh();return false,why
        end
        -- A new Generate invalidates any previously committed route before
        -- the new recommendation. No stale route is presented as the new one.
        local routes=JLP:GetModule("GatheringRouteService")
        if routes then routes:Cancel("NEW_SMART_GENERATE") end
        self._mapPresentation=nil;self._lastOverlay=nil
        if self.frame then self.frame.forceRedraw=true end
        self.routeFeedback="Evaluating qualified zones on both continents…"
        if self.frame and self.frame.status then
            self.frame.status:SetText("SMART · assessing zones, then generating route…")
        end
        return true,"ZONE_RECOMMENDATION_GENERATING"
    end
    return self:GenerateCurrentZoneRoute()
end
function Window:GenerateCurrentZoneRoute()
    local manual=viewState();local task=manual and manual:GetManualTargetTask()
    if task and not task.dismissed and task.status~="ACTIVE" then return false,"MANUAL_TARGET_"..task.status end
    if self._continentPreview then return false,"CONTINENT_NAVIGATION_ONLY" end
    if self.contentContext=="FISHING" and not self.includeGathering then
        return self:GenerateFishingSectorReview()
    end
    local view=self.lastView
    local state=viewState()
    local route=JLP:GetModule("GatheringRouteService")
    local err=not view and "MAP_UNAVAILABLE" or not state and "STATE_UNAVAILABLE" or
        not route and "ROUTE_SERVICE_UNAVAILABLE" or nil
    if err then
        self:SetRouteFeedback(false,err);self:Refresh()
        return false,err
    end
    local snapshotOK,snapshot=false,nil
    if type(state.GetSnapshot)=="function" then
        snapshotOK,snapshot=pcall(state.GetSnapshot,state)
    end
    if not snapshotOK or type(snapshot)~="table" or
        (snapshot.routeShape~="LOOP" and snapshot.routeShape~="FROM_PLAYER") then
        self:SetRouteFeedback(false,"STATE_UNAVAILABLE");self:Refresh()
        return false,"STATE_UNAVAILABLE"
    end
    local callbackMapID=view.mapID
    -- Start may reject an unchanged/invalid request without mutating the
    -- previous committed route. Keep its visible overlay until a NEW route
    -- has actually been accepted; the route service owns revocation.
    self._routeRequestSerial=(self._routeRequestSerial or 0)+1
    local requestSerial=self._routeRequestSerial
    local callbackToken=nil -- assigned only after a successful owner Start
    local callbackDuringStart=false
    local invocationOK,ok,reason=pcall(route.Start,route,view.mapID,snapshot.routeShape,view.playerPosition,function()
        if callbackToken==nil then callbackDuringStart=true;return end
        if type(route.GetContextToken)~="function" then return end
        local valid,token=pcall(route.GetContextToken,route,callbackMapID)
        if valid and self._routeRequestSerial==requestSerial and self.lastView and
            self.lastView.mapID==callbackMapID and
            (type(callbackToken)=="string" and callbackToken~="" and token==callbackToken) then self:Refresh() end
    end)
    if not invocationOK then
        ok=false;reason="ROUTE_START_EXCEPTION"
        -- A thrown scheduler may have partially started. Never show an old route.
        if type(route.QuarantineUnconfirmedCancellation)=="function" then
            pcall(route.QuarantineUnconfirmedCancellation,route,reason)
        end
    end
    if ok and type(route.GetContextToken)=="function" then
        local tokenOK,token=pcall(route.GetContextToken,route,callbackMapID)
        if tokenOK and type(token)=="string" and token~="" then callbackToken=token end
    end
    if ok and not callbackToken then
        ok=false;reason="ROUTE_GENERATION_UNCONFIRMED"
        if type(route.QuarantineUnconfirmedCancellation)=="function" then
            pcall(route.QuarantineUnconfirmedCancellation,route,reason)
        end
    end
    if ok then
        -- The owner has committed a distinct generation. Now retire the old
        -- visual receipt; an ordinary Start rejection must leave it intact.
        self._mapPresentation=nil
        self._lastOverlay=nil
        if self.frame then self.frame.forceRedraw=true end
    elseif not invocationOK or reason=="ROUTE_GENERATION_UNCONFIRMED" then
        -- The prior generation may no longer be trustworthy after an exception
        -- or unbound token. Quarantine above and suppress stale local artwork.
        self._mapPresentation=nil
        self._lastOverlay=nil
        if self.frame then self.frame.forceRedraw=true end
    end
    if ok and callbackDuringStart then
        -- A synchronous callback was observed before the identity was
        -- available. Refresh below, after binding the valid generation token.
        if self.frame then self.frame.forceRedraw=true end
    end
    -- First truthful feedback is independent of eventual overlay submission.
    -- Do not wait for the scheduler's next Tick or for native art fetch.
    if self.frame and self.frame.status and self.frame.status.SetText then
        self.frame.status:SetText(ok and "GENERATING · preparing advisory route…" or
            ("Route unavailable · "..tostring(reason or "UNKNOWN")))
    end
    -- Route progression is owned by the single service frame scheduler.
    local status=ok and route.GetStatusForMap and route:GetStatusForMap(view.mapID) or nil
    self:SetRouteFeedback(ok,reason,status)
    self:OnContentChange(true)
    return ok,reason
end
function Window:ClearRoute()
    if self._continentPreview then return false,"CONTINENT_NAVIGATION_ONLY" end
    self._smartGenerateSerial=(self._smartGenerateSerial or 0)+1
    local suitability=JLP:GetModule("GatheringZoneSuitability")
    if suitability then suitability:CancelRecommendation("CLEARED_BY_USER") end
    -- Fishing catch areas are NOT herb/ore routes. A hidden route cannot be
    -- cleared accidentally from a Fishing-only viewport.
    if self.contentContext=="FISHING" and not self.includeGathering then
        self:SetRouteFeedback(false,"FISHING_ONLY_CONTEXT");self:Refresh()
        return false,"FISHING_ONLY_CONTEXT"
    end
    local route=JLP:GetModule("GatheringRouteService")
    if not route or type(route.Cancel)~="function" then
        self:SetRouteFeedback(false,"ROUTE_SERVICE_UNAVAILABLE");self:Refresh()
        return false,"ROUTE_SERVICE_UNAVAILABLE"
    end
    self._routeRequestSerial=(self._routeRequestSerial or 0)+1
    self._routeProgressToken=nil
    local invocationOK,cancelled,reason=pcall(route.Cancel,route,"CLEARED_BY_USER")
    if not invocationOK then cancelled=false;reason="ROUTE_CANCEL_EXCEPTION" end
    if cancelled==true then
        local overlay=JLP:GetModule("GatheringMapOverlay")
        if overlay and type(overlay.Clear)=="function" and self.frame and self.frame.canvas then
            pcall(overlay.Clear,overlay,self.frame.canvas)
        end
        self._mapPresentation=nil
        self._lastOverlay=nil
        if self.frame then self.frame.forceRedraw=true end
    end
    local confirmed=cancelled==true
    if not confirmed and type(route.QuarantineUnconfirmedCancellation)=="function" then
        pcall(route.QuarantineUnconfirmedCancellation,route,reason or "STOP_UNCONFIRMED")
        local overlay=JLP:GetModule("GatheringMapOverlay")
        if overlay and overlay.Clear and self.frame and self.frame.canvas then
            pcall(overlay.Clear,overlay,self.frame.canvas)
        end
        self._mapPresentation=nil;self._lastOverlay=nil
        if self.frame then self.frame.forceRedraw=true end
    end
    self:SetRouteFeedback(confirmed,reason,confirmed and "CLEARED_BY_USER" or nil)
    -- A partial/rejected cancellation must not be advertised as a cleared map.
    -- Preserve route/context until every callable engine confirms Cancel.
    if confirmed then self:OnContentChange(true)
    else self:Refresh() end
    return confirmed,reason
end
-- Choice controls are model-independent.  They must remain truthful when
-- Blizzard cannot provide a usable mapID; map/render/route work is separate.
-- This is an idempotent presentation-only operation (no persisted writes).
-- Transient Skinning source browser. The 13 Forever item pages qualify
-- item identity only, NOT a verified mob output or farm geometry. Selection
-- never becomes a route POINT or an exact purchased/source-qualified receipt.
function Window:CycleSkinningMaterial(direction)
    local data=JLP.data and JLP.data.skinningMaterialResearch
    local entries=data and data.materials
    if type(entries)~="table" or #entries==0 then return false,"SOURCE_UNAVAILABLE" end
    local index=math.floor(tonumber(self._skinningMaterialIndex) or 1)
    self._skinningMaterialIndex=((index-1+(direction or 1))%#entries)+1
    self:RefreshSkinningMaterialAdvice()
    return true,self._skinningMaterialIndex
end
function Window:RefreshSkinningMaterialAdvice()
    local f=self.frame
    if not (f and f.skinningMaterialDetails) then return false,"VIEW_UNAVAILABLE" end
    local shared=JLP:GetModule("GatheringSharedMapState")
    local snapshot=shared and shared:GetSnapshot()
    local goal=snapshot and snapshot.supplyGoal
    if goal then
        local names={LEATHERWORKING="Leatherworking",BLACKSMITHING="Blacksmithing",ENGINEERING="Engineering",ALCHEMY="Alchemy"}
        local label=goal.origin=="AUTOMATIC_PLAN" and ((names[goal.ownerProfession]or "Profession").." supply")or
            goal.origin=="MANUAL_SELECTION" and (goal.professionKey=="FISHING"and "Manual Fishing material target"or goal.professionKey=="MINING"and "Manual Mining material target"or goal.professionKey=="HERBALISM"and "Manual Herbalism material target"or "Manual Skinning material target") or "Previous material reference (owner unverified)"
        f.skinningMaterialDetails:SetText(label.." · item "..goal.itemID..
            (goal.quantity and (" · remaining "..goal.quantity) or " · quantity UNKNOWN")..
            "\n"..tostring(goal.status).." · "..tostring(goal.scope or "inventory verification")..
            "\n"..tostring(goal.sourceName or "Current Step verifies the next action")..
            (goal.professionKey=="FISHING"and (goal.status=="FISHING_AREA"and "\nArea/zone approach only; find safe eligible water manually. Arrival is not a species, pool or catch receipt."or "\nFollow Current Step's inventory/acquisition action; arrival is not delivery or a catch receipt.")or "\nVerify source/loot on arrival; no live spawn promise."))
        return true,"SELECTED_LEATHERWORKING_SUPPLY"
    end
    local api=JLP:GetModule("ProfessionAPI")
    local owned=api and api:Get("SKINNING")
    local intel=JLP:GetModule("SkinningMaterialIntelligence")
    local bridge=JLP:GetModule("GatheringMaterialBridge")
    local advice=owned and owned.cached~=true and intel and
        intel:GetProgressionSource(owned.skill,bridge and bridge.unavailable)
    if advice and owned.skill<300 then
        f.skinningMaterialDetails:SetText("Static Forever Skinning reference · "..advice.name..
            " · "..advice.zone.." (UIMap "..advice.mapID..")\nPublic mob location; current corpse/difficulty/loot UNKNOWN.\n"..
            "Skinning Current Step owns navigation; no guaranteed skill-up or yield.")
        return true,"STATIC_FOREVER_SOURCE_ADVICE"
    end
    local data=JLP.data and JLP.data.skinningMaterialResearch
    local entries=data and data.materials or {}
    if #entries==0 then
        f.skinningMaterialDetails:SetText("Skinning item evidence SOURCE_UNAVAILABLE")
        return false,"SOURCE_UNAVAILABLE"
    end
    self._skinningMaterialIndex=math.max(1,math.min(#entries,
        math.floor(tonumber(self._skinningMaterialIndex) or 1)))
    local row=entries[self._skinningMaterialIndex]
    local source=JLP:GetModule("SkinningMaterialIntelligence")
    local mapID=self.lastView and self.lastView.mapID
    local api=JLP:GetModule("ProfessionAPI")
    local owned=api and api:Get("SKINNING")
    local advice=source and source.BuildManualAcquisition and mapID and owned and
        owned.cached~=true and source:BuildManualAcquisition(mapID,owned.skill,row.itemID)
    local kind=row.tabRequested=="SKINNED_FROM" and "Skinning tab requested" or
        "Drop tab ONLY (not Skinning evidence)"
    local zone=advice and advice.status=="AREA_ADVICE_ITEM_OUTPUT_UNVERIFIED" and
        "Zone AREA advice" or "Zone SOURCE_UNAVAILABLE"
    f.skinningMaterialDetails:SetText(tostring(self._skinningMaterialIndex).."/"..#entries..
        " · "..tostring(row.name).." (#"..tostring(row.itemID)..")\n"..
        kind.." · "..zone.." · MOB_OUTPUT_UNVERIFIED\n"..
        (self._skinningReturnMessage and ("Return: "..tostring(self._skinningReturnMessage).."\n") or "")..
        "Manual Bank item check / AH search only · no mob output or quote")
    return true,advice and advice.status or "SOURCE_UNAVAILABLE"
end
-- Manual item-identity-only acquisition. Source URL proves the catalogue item,
-- not a mob output, farming polygon, or price. Nothing is written to SavedVariables.
function Window:SkinningMaterialOwner()
    local inventory=JLP:GetModule("Inventory")
    if not inventory or type(inventory.GetCharacterKey)~="function" then return "OWNER_UNKNOWN" end
    local ok,key=pcall(inventory.GetCharacterKey,inventory)
    return ok and type(key)=="string" and key~="" and key or "OWNER_UNKNOWN"
end
function Window:CaptureSkinningMaterial()
    local entries=JLP.data and JLP.data.skinningMaterialResearch and
        JLP.data.skinningMaterialResearch.materials or {}
    local row=entries[self._skinningMaterialIndex or 1]
    local owned=JLP:GetModule("ProfessionAPI")
    local info=owned and owned.Get and owned:Get("SKINNING")
    local map=self.lastView and self.lastView.mapID
    local owner=self:SkinningMaterialOwner()
    local intel=JLP:GetModule("SkinningMaterialIntelligence")
    local material=intel and row and intel:GetMaterial(row.itemID)
    if not row or not material or not map or not info or info.cached==true or
        type(info.skill)~="number" or owner=="OWNER_UNKNOWN" then
        return nil,"SOURCE_OR_OWNER_UNAVAILABLE" end
    return {mapID=map,skill=info.skill,itemID=row.itemID,
        materialIndex=self._skinningMaterialIndex,sourceURL=material.sourceURL,
        ownerSignature=owner,readOnly=true,nativeDispatchAllowed=false,
        evidence="ITEM_IDENTITY_ONLY_MOB_OUTPUT_UNVERIFIED"}
end
function Window:ValidateSkinningMaterialCapture(capture)
    if type(capture)~="table" or capture.nativeDispatchAllowed~=false or
        capture.ownerSignature~=self:SkinningMaterialOwner() or
        capture.ownerSignature=="OWNER_UNKNOWN" then return false,"OWNER_CHANGED" end
    local state=viewState()
    local map=self.lastView and self.lastView.mapID
    if not map or map~=capture.mapID or not state then return false,"MAP_CHANGED" end
    local prev=self._skinningMaterialIndex
    if prev~=capture.materialIndex then return false,"MATERIAL_POSITION_CHANGED" end
    local now,err=self:CaptureSkinningMaterial()
    if not now then return false,err end
    if now.itemID~=capture.itemID or now.skill~=capture.skill or
        now.sourceURL~=capture.sourceURL then return false,"SOURCE_CHANGED" end
    return true
end
function Window:InspectSkinningMaterial(target)
    if target~="Bank" and target~="Auction House" then return false,"TARGET_UNAVAILABLE" end
    local cap,reason=self:CaptureSkinningMaterial()
    if not cap then self._skinningReturnMessage=reason;self:Refresh();return false,reason end
    local main=JLP.MainWindow
    if not main or not main.BeginSkinningMaterialReference then return false,"NAVIGATION_UNAVAILABLE" end
    local ok,why=main:BeginSkinningMaterialReference(target,cap)
    if not ok then self._skinningReturnMessage=why;self:Refresh() end
    return ok,why
end
function Window:RefreshChoiceLabels(choices)
    local f=self.frame
    if not f then return false,"VIEW_UNAVAILABLE" end
    if type(choices)~="table" then choices=nil end
    if f.mode then f.mode:SetText(choices and choices.mode=="SMART_PROFESSION" and "Smart mode" or "Custom mode") end
    if f.routeShape then
        f.routeShape:SetText(choices and choices.routeShape=="FROM_PLAYER" and
            "Shape: From player" or "Shape: Loop")
    end
    if f.focus then
        local focus=choices and choices.focus or "BALANCED"
        f.focus:SetText(focus=="MATERIALS" and "Materials" or
            focus=="SKILL" and "Skill focus" or "Balanced")
        local smart=choices and choices.mode=="SMART_PROFESSION"
        f.focus:SetAlpha(smart and 1 or 0.5)
        if f.focus.SetEnabled then f.focus:SetEnabled(smart==true) end
    end
    if f.sources then
        f.sources:SetText(choices and choices.sourceFilter=="OBSERVED_ONLY" and
            "Pins: My observations" or "Pins: All sources")
    end
    if f.routeSources then
        f.routeSources:SetText("Route nodes: "..(choices and choices.routeSource=="OBSERVED_ONLY" and "Observed" or
            choices and choices.routeSource=="PREFER_OBSERVED" and "Prefer observed" or "All"))
    end
    return choices~=nil
end
-- Read-only map-bound dock receipt. A nil model always invalidates old READY,
-- even if the previous map or a stale observer still exists. No route mutation.
function Window:RefreshDockOutcome(mapID,status,router)
    local f=self.frame
    if not (f and f.dockOutcome and f.dockOutcome.SetText) then return false end
    local lifecycle
    if not mapID then
        lifecycle={text="No verified map · choose a supported zone before generating"}
    else
        local widgets=JLP.UIWidgets
        lifecycle=widgets and widgets.GatheringLifecycleReceipt and
            widgets:GatheringLifecycleReceipt(router or JLP:GetModule("GatheringRouteService"),mapID,status)
    end
    local text=lifecycle and lifecycle.text or "No committed advisory route"
    local journey=JLP:GetModule("GatheringRouteJourney")
    local routeView=journey and mapID and journey:Inspect(mapID,{
        visible=f.canvas and f.canvas.IsVisible and f.canvas:IsVisible()==true,
        routeSubmitted=self._lastRouteOverlaySubmitted==true,
        strokes=self._lastRouteStrokesSubmitted,
        receipt=self._mapPresentation})
    self._routeJourney=routeView
    -- A computed READY route is not necessarily presented. This ephemeral
    -- receipt belongs to this canvas/map/generation, never the route owner.
    local presentation=self._mapPresentation
    local token=router and router.GetContextToken and mapID and router:GetContextToken(mapID)
    if status=="READY" and mapID then
        if self._lastRouteOverlaySubmitted==true and (self._lastRouteStrokesSubmitted or 0)==0 then
            text=text.." · no route lines submitted; try Show Route"
        elseif type(token)=="string" and token~="" and presentation and presentation.mapID==mapID and presentation.token==token then
            text=text.." · overlay submitted (native paint UNKNOWN)"
        else
            text=text.." · map overlay pending/UNKNOWN"
        end
    end
    local widgets=JLP.UIWidgets
    if f.dockInfoSummary then
        if widgets and widgets.SetAdvisoryStatusText then
            widgets:SetAdvisoryStatusText(f.dockInfoSummary,text,190,48)
        else f.dockInfoSummary:SetText(text) end
    end
    if widgets and widgets.SetAdvisoryStatusText then
        widgets:SetAdvisoryStatusText(f.dockOutcome,text,190,44)
    else
        -- Preserve direct no-widget rendering for limited WoW/UI shims.
        f.dockOutcome:SetText(text)
    end
    return true
end
function Window:Refresh()
    self:RefreshManualTargetUI()
    -- Consume manual reload intent at the start of the attempt. An unavailable
    -- zone, a hidden frame or an early exception must not carry a forced fetch
    -- into the next, potentially different, map. The requested map is bound
    -- to the last confirmed view, not a mutable global map selection.
    local reloadMapID=self._forceArtMapID
    self._forceArtFetch=nil
    self._forceArtMapID=nil
    local f=self.frame
    if not f or not f:IsShown() then return false,"VIEW_HIDDEN" end
    if self._continentPreview then return self:RefreshContinentView(reloadMapID) end
    local state=viewState()
    local choices=state and type(state.GetSnapshot)=="function" and state:GetSnapshot()
    self:RefreshChoiceLabels(choices)
    if f.dockRouteSummary then
        local mode=choices and choices.mode=="CUSTOM_LOOP" and "Custom" or "Smart"
        local focus=choices and choices.focus or "BALANCED"
        local shape=choices and choices.routeShape=="FROM_PLAYER" and "From player" or "Loop"
        local routeSource=choices and choices.routeSource or "ALL"
        f.dockRouteSummary:SetText(mode.." · "..tostring(focus).." · "..shape.."\n"..tostring(routeSource))
    end
    local svc=source()
    local workspace=JLP:GetModule("SecondaryWorkspace")
    local fishing=workspace and workspace:GetSnapshot("FISHING")
    local fishingCtx=JLP:GetModule("FishingSkillContext")
    local observedSkill=fishingCtx and fishingCtx:FromSnapshot(fishing)
    local model,reason=svc and svc:Resolve(fishing and fishing.skill,observedSkill and observedSkill.observedBonus)
    if self.lastView and model and self.lastView.mapID~=model.mapID and f.canvas then
        -- A new map invalidates the previous viewer's pins, fishing AREA and
        -- route geometry BEFORE fetching potentially unavailable native art.
        -- The shared route service remains authoritative and untouched.
        local overlay=JLP:GetModule("GatheringMapOverlay")
        if overlay and overlay.Clear then overlay:Clear(f.canvas) end
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        if map then map:SetViewport(f.canvas,DEFAULT_MAP_ZOOM,0.5,0.5) end
        self.routeResult=nil;self.routeFeedback=nil
        self._routeProgressToken=nil
        self._mapPresentation=nil
        self._routeRequestSerial=(self._routeRequestSerial or 0)+1
        self.lastArt=nil;self._lastOverlay=nil;self._lastRoutes=nil
        self._lastSpatial=nil;self._lastStats=nil;self._lastViewport=nil
        f.forceRedraw=true
    end
    self.lastView=model
    if self.fishingAreaPlan then
        local state=viewState()
        local selected=state and state:GetSnapshot()
        local sector=self.fishingAreaPlan
        local current=model and model.spatial
        if not model or sector.mapID~=model.mapID or
            sector.filter~=(current and current.fishingAreaFilter) or
            sector.selectedItemID~=(current and current.fishingSelectedItemID) or
            sector.shape~=(selected and selected.routeShape) or
            sector.rawFishingSkill~=(observedSkill and observedSkill.rawSkill) then
            self.fishingAreaPlan=nil;self.fishingAdvice=nil
        end
    end
    if f.reloadMap and f.reloadMap.SetEnabled then
        f.reloadMap:SetEnabled(model~=nil)
        if f.reloadMap.SetAlpha then f.reloadMap:SetAlpha(model and 1 or 0.45) end
    end
    if not model then
        -- This early return used to preserve the old zone's committed READY
        -- in the dock although all map-owned data had been discarded.
        self._routeProgressToken=nil
        self._mapPresentation=nil
        self:RefreshDockOutcome(nil,"NO_MAP")
        if f.dockResourcesSummary then f.dockResourcesSummary:SetText("No zone · resources unavailable") end
        if f.dockDisplaySummary then f.dockDisplaySummary:SetText("No art · no map presentation") end
        if f.reloadMap and f.reloadMap.SetText then f.reloadMap:SetText("Choose Zone") end
        local canvas=f.canvas
        if self._lastResolvedMapID~=nil then
            self:InvalidateRouteContext("MAP_ART_UNAVAILABLE")
        end
        self._lastResolvedMapID=nil
        self.routeResult=nil;self.routeFeedback=nil
        local overlay=JLP:GetModule("GatheringMapOverlay")
        if overlay and overlay.Clear then overlay:Clear(canvas) end
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        if map then map:Clear(canvas) end
        self.lastArt=nil;self._lastOverlay=nil;self._lastRoutes=nil;self._lastSpatial=nil;self._lastStats=nil
        f.title:SetText("Gathering Map · No zone")
        f.status:SetText("Blizzard map unavailable")
        if f.routeDetail then f.routeDetail:SetText("Select a supported zone and reopen the map") end
        -- A missing map is not route-eligible; never retain actionable controls
        -- or previous zone resource rows after the no-map transition.
        for _,control in ipairs({f.generate,f.clear,f.herb,f.ore}) do
            if control then
                if control.SetEnabled then control:SetEnabled(false) end
                if control.SetAlpha then control:SetAlpha(0.45) end
            end
        end
        self.resourceMapID=nil
        if self.RefreshResourceList then self:RefreshResourceList(nil) end
        self.fullRouteRationale="No verified map is available. Select a supported zone before generating an advisory route."
        if self.detailsShown then self:RefreshRouteExplanation() end
        return false,reason
    end
    if self._lastResolvedMapID and self._lastResolvedMapID~=model.mapID then
        self:InvalidateRouteContext("MAP_CHANGED")
        self.resourceOffset=0
        self.resourceMapID=nil
    end
    self._lastResolvedMapID=model.mapID
    local policy=JLP:GetModule("GatheringViewLayerPolicy")
    model=policy and policy:FilterStandalone(model,self.contentContext,self.includeGathering) or model
    f.title:SetText((self.contentContext=="FISHING" and "Fishing Areas · " or "Gathering Map · ")..model.name)
    if f.dockLegend and JLP.UIWidgets and JLP.UIWidgets.GatheringPointSummary then
        local summary=JLP.UIWidgets:GatheringPointSummary(model.overlay)
        f.dockLegend:SetText(summary.label)
    end
    if f.skinningEvidence then
        self:RefreshSkinningMaterialAdvice()
        local intel=JLP:GetModule("SkinningMaterialIntelligence")
        local coverage=intel and intel:GetCoverage()
        local skinningMobIdentityCount=model.spatial and model.spatial.skinningMobIdentityCount or 0
        local catalog=JLP:GetModule("SkinningResearchCatalog")
        local api=JLP:GetModule("ProfessionAPI")
        local owned=api and api:Get("SKINNING")
        local area=catalog and catalog.GetQualifiedZoneAreaAdvice and
            owned and owned.cached~=true and catalog:GetQualifiedZoneAreaAdvice(model.mapID,owned.skill)
        local suggestion=area and area.suggestions and area.suggestions[1]
        local shared=JLP:GetModule("GatheringSharedMapState")
        local supply=shared and shared:GetSnapshot();supply=supply and supply.supplyGoal
        if supply and (supply.professionKey=="MINING"or supply.professionKey=="HERBALISM")then
            f.skinningEvidence:SetText((supply.professionKey=="MINING"and "Mining"or "Herbalism").." supply · "..tostring(supply.resourceKey or supply.status).." · Current Step owns the next action")
        elseif suggestion then
            f.skinningEvidence:SetText("Skinning AREA · "..suggestion.zone..
                " · skill "..suggestion.fromSkill.."–"..(suggestion.toSkill-1)..
                " (Forever guide). Zone only; no polygons or live spawn proof")
        else
            f.skinningEvidence:SetText("Skinning: "..tostring(coverage and coverage.materialCount or 0)..
                " research items · "..tostring(skinningMobIdentityCount)..
                " mob leads · no verified area for this skill/zone")
        end
    end
    self:UpdateZoomCaption()
    local ctrl=JLP:GetModule("GatheringMapLayerController")
    local layers=ctrl and ctrl:GetLayerState(model.mapID)
    if f.dockResourcesSummary or f.dockDisplaySummary then
        local counts={};local total=0;local active=0
        for _,key in ipairs({"HERBALISM","MINING"}) do
            local layer=layers and layers.layers and layers.layers[key]
            local selected=0
            for resource,enabled in pairs(layer and type(layer.resourceSelection)=="table" and layer.resourceSelection or {}) do
                if type(resource)=="string" and enabled==true then selected=selected+1 end
            end
            total=total+selected
            if layer and layer.learned and layer.enabled then active=active+1 end
            counts[#counts+1]=(key=="MINING" and "Ore " or "Herb ")..selected
        end
        if f.dockResourcesSummary then
            f.dockResourcesSummary:SetText(table.concat(counts," · ").."\n"..
                (choices and choices.mode=="SMART_PROFESSION" and
                "Smart filters POINTs by focus and learned skill; no route until Generate" or
                "Custom displays only explicitly selected POINTs"))
        end
        if f.dockDisplaySummary then
            f.dockDisplaySummary:SetText("Layers "..active.."/2 · "..tostring(f.canvas.gatheringDisplayMode or "SELECTED")..
                " pins\nZoom/pan on map canvas")
        end
    end
    for _,key in ipairs({"HERBALISM","MINING"}) do
        local layer=layers and layers.layers[key]
        local b=key=="HERBALISM" and f.herb or f.ore
        local name=key=="HERBALISM" and "Herbalism" or "Mining"
        local auto=choices and choices.mode=="SMART_PROFESSION"
        b:SetText(name..": "..(not layer or not layer.learned and "Not learned" or
            auto and "Smart" or layer.enabled and "On" or "Off"))
        if b.SetEnabled then b:SetEnabled(layer and layer.learned==true and not auto or false) end
        b:SetAlpha(layer and layer.learned and (auto and 0.75 or 1) or 0.45)
    end
    if f.fishingAreas then
        f.fishingAreas:SetText("Fishing: "..((not model.spatial or not model.spatial.fishingLearned) and "Not learned" or
            (model.spatial.fishingEnabled and "On" or "Off")))
        if f.fishingAreas.SetEnabled then f.fishingAreas:SetEnabled(model.spatial and model.spatial.fishingLearned or false) end
    end
    if f.fishingFilter then
        local spatial=model.spatial
        local mode=spatial and spatial.fishingAreaFilter or "ALL"
        local name=mode=="COOKING_NEEDS" and "Cooking needs" or
            mode=="SINGLE_FISH" and ("Fish "..tostring(spatial.fishingSelectedItemID)) or "All"
        if mode=="SINGLE_FISH" then
            for _,fish in ipairs(JLP.data and JLP.data.fishingCatchAreaReference and
                JLP.data.fishingCatchAreaReference.maps[model.mapID] or {}) do
                if fish.itemID==spatial.fishingSelectedItemID then name=fish.name;break end
            end
        end
        f.fishingFilter:SetText("Fish: "..(#name>9 and name:sub(1,8).."…" or name).." ▾")
        if f.fishingFilter.SetEnabled then f.fishingFilter:SetEnabled(spatial and spatial.fishingLearned or false) end
    end
    -- Read-only route presentation controls the primary CTA, never the planner.
    local presenter=JLP:GetModule("GatheringRoutePresentation")
    local routeUI=presenter and presenter:Build(model.mapID)
    local progressRouter=JLP:GetModule("GatheringRouteService")
    if progressRouter and type(progressRouter.SetProgressObserver)=="function" and
        (self._observedRouter~=progressRouter or self._observedMapID~=model.mapID) then
        self._observedRouter=progressRouter
        self._observedMapID=model.mapID
        progressRouter:SetProgressObserver("STANDALONE",function(receipt)
            if not self.frame or not self.lastView or self.lastView.mapID~=receipt.mapID or
                not self:IsShown() then return end
            local current=progressRouter:GetContextToken(receipt.mapID)
            if type(current)~="string" or current=="" or current~=self._routeProgressToken then return end
            if receipt.status=="GENERATING" then
                -- No expensive map/overlay redraw; the two short receipts
                -- come from the SAME generation and map context.
                self:RefreshDockOutcome(receipt.mapID,receipt.status,progressRouter)
                -- Direct FontString update; no expensive map/overlay redraw.
                local status=JLP.UIWidgets and JLP.UIWidgets.GatheringProgressLabel and
                    JLP.UIWidgets:GatheringProgressLabel(receipt) or "Planning route…"
                if self.frame.status then self.frame.status:SetText(status) end
            elseif receipt.committed and self.frame.status then
                -- The scheduler is the route owner. A READY publication does
                -- not paint the viewer by itself; refresh this visible canvas
                -- exactly once per committed generation, without driving Tick.
                local generationToken=current
                if self._lastReadyRenderToken~=generationToken and not self._refreshingReadyRoute then
                    self._lastReadyRenderToken=generationToken
                    self._refreshingReadyRoute=true
                    local refreshed=pcall(self.Refresh,self)
                    self._refreshingReadyRoute=false
                    if not refreshed then
                        self._mapPresentation=nil
                        self.frame.status:SetText("Route ready · map presentation failed; use Reload Map")
                    end
                else
                    self:RefreshDockOutcome(receipt.mapID,"READY",progressRouter)
                end
            else
                -- Error, EMPTY, Cancel and Clear are just status updates: do
                -- not repaint a map or resurrect a stale READY presentation.
                self:RefreshDockOutcome(receipt.mapID,receipt.status,progressRouter)
                local W=JLP.UIWidgets
                local label=W and W.GatheringLifecycleReceipt and
                    W:GatheringLifecycleReceipt(progressRouter,receipt.mapID,receipt.status)
                if self.frame.status then
                    self.frame.status:SetText(label and label.text or "Route result unavailable")
                end
            end
        end)
    end
    -- Token changes on Start/Cancel without changing the observer function.
    self._routeProgressToken=progressRouter and progressRouter.GetContextToken and
        progressRouter:GetContextToken(model.mapID) or nil
    if f.generate then
        local eligible=(self.contentContext~="FISHING" or self.includeGathering) and
            routeUI and routeUI.canGenerate~=false
        local primary=routeUI and routeUI.primaryLabel or "Generate Route"
        if self._routeActionsInDock then
            if primary=="Regenerate Route" then primary="Regen"
            elseif primary=="Generate Route" then primary="Generate"
            elseif primary=="Cancel Route" then primary="Cancel" end
        end
        f.generate:SetText(primary)
        if f.generate.SetEnabled then f.generate:SetEnabled(eligible==true) end
        f.generate:SetAlpha(eligible and 1 or 0.45)
        if f.generate.SetActiveState and f.generate.__jlpActiveState~=eligible then
            f.generate:SetActiveState(eligible==true)
        end
    end
    self:RefreshDockOutcome(model.mapID,model.routeStatus,progressRouter)
    if f.zoomRoute then
        local canFocus=model.routeStatus=="READY" and model.routeSnapshot~=nil
        if f.zoomRoute.SetEnabled then f.zoomRoute:SetEnabled(canFocus) end
        f.zoomRoute:SetAlpha(canFocus and 1 or 0.45)
    end
    if f.clear then
        local canClear=(self.contentContext~="FISHING" or self.includeGathering) and
            routeUI and routeUI.canClear
        local clearCaption=routeUI and routeUI.workflow=="GENERATING" and "Cancel Route" or "Clear Route"
        if self._routeActionsInDock then
            clearCaption=clearCaption=="Cancel Route" and "Cancel" or "Clear"
        end
        f.clear:SetText(clearCaption)
        if f.clear.SetEnabled then f.clear:SetEnabled(canClear==true) end
        f.clear:SetAlpha(canClear and 1 or 0.45)
    end
    if f.fishingExtraLayer then
        f.fishingExtraLayer:SetShown(self.contentContext=="FISHING" and self.optionsShown==true and self.dockDisplayExpanded~=false)
        f.fishingExtraLayer:SetText(self.includeGathering and "Herb/Ore: Visible" or "Herb/Ore: Hidden")
    end
    self:RefreshResourceList(model.mapID)
    local routeIdentity=model.routeSnapshot and model.routeSnapshot.routes
    local progressRouter=JLP:GetModule("GatheringRouteService")
    local currentRouteToken=progressRouter and progressRouter.GetContextToken and
        progressRouter:GetContextToken(model.mapID) or nil
    local viewportIdentity=f.canvas.gatheringView and
        (tostring(f.canvas.gatheringView.zoom)..":"..tostring(f.canvas.gatheringView.centerX)..":"..tostring(f.canvas.gatheringView.centerY)) or "fit"
    local sameContent=self._lastViewport==viewportIdentity and self.lastArt and f.canvas.fishingMapID==model.mapID and
        self._lastOverlay==model.overlay and self._lastRoutes==routeIdentity and
        self._lastSpatial==model.spatial and
        self._lastPresentedToken==currentRouteToken and
        svc and svc.IsTilePresentationCurrent and
        svc:IsTilePresentationCurrent(f.canvas,model.mapID) and
        not f.forceRedraw
    -- A manual Reload Map intentionally bypasses the four-map art LRU ONCE.
    -- Unlike a normal viewport redraw it requests fresh native C_Map metadata.
    local forceArtFetch=reloadMapID~=nil and reloadMapID==model.mapID
    if forceArtFetch then sameContent=false end
    local report
    local paintStart=type(debugprofilestop)=="function" and debugprofilestop() or nil
    local presentedToken=currentRouteToken
    if sameContent then
        -- Map reveal is visual-only and may have changed independently of the
        -- route snapshot/viewport; keep its optional Leatrix gate up to date.
        local reveal=JLP:GetModule("MapRevealRenderer")
        if reveal and self.lastArt then
            local ok=pcall(reveal.Render,reveal,f.canvas,self.lastArt)
            if not ok then pcall(reveal.Clear,reveal,f.canvas) end
        end
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        if model.playerPosition then map:PlacePlayerMarker(f.canvas,self.lastArt,model.playerPosition)
        else map:HidePlayerMarker(f.canvas) end
        report={ready=true,art=self.lastArt,stats=self._lastStats,status="READY",
            routeOverlaySubmitted=self._lastRouteOverlaySubmitted==true,
            routeStrokesSubmitted=self._lastRouteStrokesSubmitted or 0,nativeDispatchAllowed=false}
    else
        report=svc:Render(f.canvas,model,f.forceRedraw,forceArtFetch,true)
    end
    f.forceRedraw=nil
    if not (report and report.ready) then
        self._lastPresentedToken=nil
        self._mapPresentation=nil
    end
    local acceptedOverlayReceipt=false
    if report and report.ready and report.routeOverlaySubmitted==true and
        model.routeStatus=="READY" and type(presentedToken)=="string" and presentedToken~="" and progressRouter and
        type(progressRouter.MarkOverlayPresented)=="function" and (report.routeStrokesSubmitted or 0)>0 then
        local now=type(debugprofilestop)=="function" and debugprofilestop() or nil
        local paintCpu=paintStart and now and now>=paintStart and now-paintStart or nil
        local accepted,receipt=pcall(progressRouter.MarkOverlayPresented,progressRouter,
            model.mapID,presentedToken,paintCpu,not sameContent)
        acceptedOverlayReceipt=accepted and receipt==true
    end
    -- Keep the retry affordance visible after a failed fetch/render. This
    -- control only refreshes map art; it never invokes gathering actions.
    if f.reloadMap and f.reloadMap.SetText then
        local action=JLP.UIWidgets and JLP.UIWidgets.GatheringMapRetryAction and
            JLP.UIWidgets:GatheringMapRetryAction(true,report.ready)
        local text=action and action.label or (report.ready and "Reload Map" or "Retry Map")
        f.reloadMap:SetText(text=="Reload Map" and "Reload" or text=="Choose Zone" and "Choose" or text)
    end
    if report.ready then
        self.lastArt=report.art
        self._lastPresentedToken=currentRouteToken
        self._mapPresentation=model.routeStatus=="READY" and
            acceptedOverlayReceipt and report.routeOverlaySubmitted==true and
            (report.routeStrokesSubmitted or 0)>0 and
            type(currentRouteToken)=="string" and currentRouteToken~="" and
            type(report.stats)=="table" and report.stats.status~="MAP_MISMATCH" and
            {mapID=model.mapID,token=currentRouteToken,overlay=report.stats.status,
                nativePaint="UNKNOWN"} or nil
        self._lastOverlay=model.overlay
        self._lastRoutes=routeIdentity
        self._lastSpatial=model.spatial
        self._lastStats=report.stats
        self._lastRouteOverlaySubmitted=report.routeOverlaySubmitted==true
        self._lastRouteStrokesSubmitted=report.routeStrokesSubmitted or 0
        self._lastViewport=viewportIdentity
        -- Commit the dock text AFTER the current canvas receipt/stroke fields.
        -- A hidden/folded dock can then reveal the same current generation.
        self:RefreshDockOutcome(model.mapID,model.routeStatus,progressRouter)
        f.fallback:Hide()
        self:SetBackgroundOpacity(settings().backgroundOpacity)
        self:SetChromeOpacity(settings().chromeOpacity)
        local stats=report.stats
        local explanation=JLP:GetModule("GatheringOutputExplanation")
        local routeService=JLP:GetModule("GatheringRouteService")
        local chosenRoutes,chosenStatus=routeService and routeService:GetRoutes(model.mapID)
        local outputHeadline=choices and choices.mode=="SMART_PROFESSION" and
            chosenStatus=="READY" and explanation and explanation:RouteHeadline(chosenRoutes) or nil
        local hasRoute=model.routeStatus=="READY"
        local lifecycle=JLP.UIWidgets and JLP.UIWidgets.GatheringLifecycleReceipt and
            JLP.UIWidgets:GatheringLifecycleReceipt(JLP:GetModule("GatheringRouteService"),model.mapID,model.routeStatus)
        local routeText=hasRoute and "Route ready" or model.routeStatus=="GENERATING" and "Planning route…" or
            (lifecycle and lifecycle.text or "No route")
        local routeDetails={}
        for _,key in ipairs({"HERBALISM","MINING"}) do
            local item=chosenRoutes and chosenRoutes[key]
            if item and item.points then
                routeDetails[#routeDetails+1]=(key=="HERBALISM" and "Herbs " or "Ores ")..
                    #item.points.." stops"..(type(item.normalizedLength)=="number" and
                    (" · geometric map length "..string.format("%.2f",item.normalizedLength)) or "")
            end
        end
        if f.routeRationale then
            local reason=routeUI and routeUI.action or "No route data"
            if outputHeadline then reason=reason.."\n"..outputHeadline end
            local evidence=JLP.UIWidgets and JLP.UIWidgets.GatheringRouteEvidence and
                JLP.UIWidgets:GatheringRouteEvidence(model.overlay,routeUI and routeUI.workflow,choices,model.mapID)
            if evidence then reason=reason.."\n"..evidence.title.." · "..evidence.detail.."\n"..evidence.context end
            self.fullRouteRationale=reason
            -- A fixed short instruction is safe even with Unicode source text;
            -- the full unmodified reason belongs to the detail panel.
            f.routeRationale:SetText("See Why this route? for full details")
            if self.detailsShown then self:RefreshRouteExplanation() end
        end
        local resultModule=JLP:GetModule("GatheringRouteResult")
        local routeService=JLP:GetModule("GatheringRouteService")
        if self.routeResult and resultModule and type(resultModule.IsCurrent)=="function" and
           not resultModule:IsCurrent(self.routeResult,model.mapID,routeService) then
            self.routeResult=nil;self.routeFeedback=nil
        end
        if routeUI and self.routeResult and
            (self.routeResult.phase=="GENERATING" or self.routeResult.phase=="READY") and
            (routeUI.workflow=="READY" or routeUI.workflow=="GENERATING") then
            local latest=resultModule and resultModule:FromStatus(routeUI.status)
            if latest then
                if resultModule.Bind then resultModule:Bind(latest,model.mapID,routeService) end
                self.routeResult=latest;self.routeFeedback=latest.message
            end
        end
        if self.contentContext=="FISHING" and not self.includeGathering then
            f.status:SetText(self.fishingAdvice or "Fishing: historical catch areas · no verified pool route")
            f.routeDetail:SetText("Catch areas are not verified pool positions. Enable Herb/Ore layers for gathering routes.")
        else
            local phase=routeUI and routeUI.workflow=="GENERATING" and
                JLP.UIWidgets and JLP.UIWidgets.GatheringPhaseLabel and
                JLP.UIWidgets:GatheringPhaseLabel(routeService,model.mapID) or nil
            local lifecycleText=lifecycle and lifecycle.text or nil
            f.status:SetText(model.routeStatus=="GENERATING" and
                (lifecycleText or "Generating advisory route") or
                (self.routeFeedback or lifecycleText or (routeUI and routeUI.header or "No active route")))
            f.routeDetail:SetText(phase and phase.text or (self.routeResult and self.routeResult.detail or
                (routeUI and routeUI.detail or "Select resources to create a route")))
        end
        if f.routeWhy then
            local showWhy=self.contentContext~="FISHING" or self.includeGathering
            f.routeWhy:SetShown(showWhy)
        end
        if f.status.SetWidth then
            local panelWidth=f.GetWidth and f:GetWidth() or 760
            local geom=JLP:GetModule("GatheringViewportLayout")
            local fit=geom and geom:RouteFeedbackBudget(panelWidth,f.GetHeight and f:GetHeight() or 550)
            f.status:SetWidth(fit and fit.statusWidth or math.max(1,panelWidth-44))
            f.routeDetail:SetWidth(fit and fit.detailWidth or math.max(1,panelWidth-175))
        end
        if f.status.SetJustifyH then f.status:SetJustifyH("LEFT") end
    else
        self.lastArt=nil;self._lastOverlay=nil;self._lastRoutes=nil;self._lastSpatial=nil;self._lastStats=nil
        self._mapPresentation=nil
        self:RefreshDockOutcome(model.mapID,model.routeStatus,progressRouter)
        local failure=JLP.UIWidgets and JLP.UIWidgets.GatheringMapFailure and
            JLP.UIWidgets:GatheringMapFailure(report.status)
        f.fallback:SetText("Blizzard map art unavailable: "..tostring(report.status))
        f.fallback:Show()
        f.status:SetText(failure and failure.title or "Map artwork unavailable")
        f.routeDetail:SetText(failure and failure.detail or "Choose another client-supported zone")
    end
    return report.ready,report.status
end
-- Explicit refresh is advisory map-art retrieval, never a gathering action.
-- Reuses the existing right-independent top control row and one Render pass.
function Window:ReloadMapArt()
    if not (self.frame and self.lastView and self.lastView.mapID) then
        return false,"MAP_UNAVAILABLE"
    end
    if self.frame.IsShown and not self.frame:IsShown() then
        return false,"VIEW_HIDDEN"
    end
    self._forceArtFetch=true -- legacy test/UI hint; always consumed by Refresh
    self._forceArtMapID=self._continentPreview and self._continentPreview.mapID or self.lastView.mapID
    self.frame.forceRedraw=true
    return self:Refresh()
end
function Window:RecommendFishingZone()
    local api=JLP:GetModule("ProfessionAPI")
    local p=api and api:Get("FISHING")
    if not p or p.key~="FISHING" or p.cached or type(p.skill)~="number" then
        return false,"FISHING_NOT_LEARNED"
    end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local current=map and map:GetCurrentZone()
    local browser=JLP:GetModule("ForeverFishingZoneBrowser")
    local zones=browser and current and browser:Discover(current) or {}
    local available={}
    for _,z in ipairs(zones) do available[z.mapID]=true end
    local state=viewState();local snapshot=state and state:GetSnapshot()
    local intel=JLP:GetModule("FishingAreaIntelligence")
    if not snapshot or not intel then return false,"FISHING_INTELLIGENCE_UNAVAILABLE" end
    local top,reason=intel:RecommendZones(snapshot.fishingAreaFilter or "ALL",
        snapshot.fishingSelectedItemID,nil,function(id) return available[id] end)
    local best=top and top[1]
    if not best then return false,reason or "NO_CLIENT_BROWSABLE_FISHING_AREA" end
    local ok,why=state:SelectMap(best.mapID)
    if not ok then return false,why end
    self.fishingAdvice="Historical coverage: "..best.uniqueSectors.." sectors · no catch-rate claim"
    self:OnContentChange()
    return true,best.mapID
end
function Window:RefreshRouteExplanation()
    local f=self.frame
    if not f or not f.detailsPanel then return end
    local explanation=JLP:GetModule("GatheringRouteExplanation")
    local content=self.fullRouteRationale or
        "Choose a route to see evidence and selection rationale."
    local W=JLP.UIWidgets
    local router=JLP:GetModule("GatheringRouteService")
    local mapID=self.lastView and self.lastView.mapID
    local timing=W and W.GatheringTimingSummary and mapID and
        W:GatheringTimingSummary(router,mapID) or nil
    if timing then content=content.."\n\n"..timing end
    local journey=JLP:GetModule("GatheringRouteJourney")
    if journey and mapID then
        local receipt=journey:Inspect(mapID,{visible=f.canvas and f.canvas:IsVisible()==true,
            routeSubmitted=self._lastRouteOverlaySubmitted==true,
            strokes=self._lastRouteStrokesSubmitted,receipt=self._mapPresentation})
        content=journey:Summary(receipt).."\n\n"..content
    end
    local pages=explanation and explanation:Pages(content,42,5) or {"No route information available"}
    self.explanationPage=clamp(self.explanationPage or 1,1,#pages)
    f.detailsText:SetText(pages[self.explanationPage])
    f.detailsPage:SetText(self.explanationPage.." / "..#pages)
    if f.detailsPrevious.SetEnabled then f.detailsPrevious:SetEnabled(self.explanationPage>1) end
    if f.detailsNext.SetEnabled then f.detailsNext:SetEnabled(self.explanationPage<#pages) end
end
-- The right rail may present one modal workspace at a time.
-- Transition order is explicit: visibility, scroll/wheel, then section hosts.
function Window:SetRailWorkspace(mode)
    local f=self.frame
    if not f then return false end
    if mode~="NORMAL" and mode~="OPTIONS" and mode~="DETAILS" then return false end
    local previous=self.railWorkspace or "NORMAL"
    self.railWorkspace=mode
    self.optionsShown=mode=="OPTIONS"
    self.detailsShown=mode=="DETAILS"
    if f.optionsPanel then f.optionsPanel:SetShown(self.optionsShown) end
    if f.detailsPanel then f.detailsPanel:SetShown(self.detailsShown) end
    if f.sidebar and f.sidebar.EnableMouseWheel then
        f.sidebar:EnableMouseWheel(mode=="NORMAL")
    end
    if f.optionsContent and f.dockRouteHeading then self:UpdateDockSections() end
    if previous=="OPTIONS" and mode~="OPTIONS" and self.lastFit then
        self:ApplyContentLayout(self.lastFit)
    end
    if self.lastView then self:RefreshResourceList(self.lastView.mapID) end
    return true
end
function Window:ToggleRouteExplanation(show)
    local f=self.frame
    if not (f and f.detailsPanel) then return false end
    local want=show==nil and not self.detailsShown or show==true
    if want then
        self.explanationPage=1
        self:RefreshRouteExplanation()
    end
    return self:SetRailWorkspace(want and "DETAILS" or "NORMAL")
end
-- Display choice is UI-only; it neither mutates resource selection nor changes
-- historical reference provenance or the route itself.
function Window:CyclePinDisplay()
    local order={"COMPACT","SELECTED","DETAILED"}
    local nextMode="COMPACT"
    for i,mode in ipairs(order) do
        if mode==(self.pinDisplayMode or "SELECTED") then
            nextMode=order[i%#order+1];break
        end
    end
    self.pinDisplayMode=nextMode
    if self.frame and self.frame.canvas then self.frame.canvas.gatheringDisplayMode=nextMode end
    if self.frame and self.frame.pinDisplay then
        self.frame.pinDisplay:SetText("Pins: "..(nextMode=="COMPACT" and "Compact clusters" or
            nextMode=="SELECTED" and "Selected resources" or "Detailed"))
    end
    self._lastOverlay=nil
    if self.frame then self.frame.forceRedraw=true end
    self:Refresh()
    return nextMode
end
function Window:ToggleOptions()
    local f=self.frame
    if not (f and f.optionsPanel) then return false end
    local nextMode=self.optionsShown and "NORMAL" or "OPTIONS"
    local ok=self:SetRailWorkspace(nextMode)
    if ok and self.lastView then
        local router=JLP:GetModule("GatheringRouteService")
        local status=router and router.GetStatusForMap and router:GetStatusForMap(self.lastView.mapID)
        self:RefreshDockOutcome(self.lastView.mapID,status,router)
    end
    return ok
end
function Window:RefreshResourceList(mapID)
    local f=self.frame
    if not f or not f.resourceRows then return end
    local fishingOnly=self.contentContext=="FISHING" and not self.includeGathering
    if f.fishingFocusNotice then f.fishingFocusNotice:SetShown(fishingOnly) end
    if f.fishingShowHerbs then f.fishingShowHerbs:SetShown(fishingOnly) end
    for _,control in ipairs({f.resourceSearch,f.resourceSearchClear,f.resourceTab,f.oreTab,f.resourceInfo,
        f.resourcePrev,f.resourceNext,f.resourcePages,f.selectAll,f.selectNone}) do
        control:SetShown(not fishingOnly)
    end
    if fishingOnly then
        self:UpdateCompactResourceAccess(false)
        for _,row in ipairs(f.resourceRows) do row:Hide() end
        if f.resourceTitle then f.resourceTitle:SetText("FISHING · HISTORICAL AREAS") end
        return
    end
    local routeSettings=viewState() and viewState():GetSnapshot()
    local editingMaterials=routeSettings and routeSettings.mode=="SMART_PROFESSION" and routeSettings.focus=="MATERIALS"
    if f.resourceTitle then
        f.resourceTitle:SetText(editingMaterials and "MATERIAL TARGETS · ALL ZONES" or "RESOURCES · CURRENT ZONE")
    end
    local id=mapID or self.resourceMapID or (self.lastView and self.lastView.mapID)
    if id then self.resourceMapID=id end
    local ctrl=JLP:GetModule("GatheringMapLayerController")
    local layers=nil
    if id and ctrl and type(ctrl.GetLayerState)=="function" then
        local ok,result=pcall(ctrl.GetLayerState,ctrl,id)
        if ok then layers=result end
    end
    local browser=JLP:GetModule("GatheringResourceBrowser")
    local rowRenderer=JLP:GetModule("GatheringResourceRow")
    local function unavailable(reason)
        self.resourceOffset=0
        for _,b in ipairs(f.resourceRows) do
            b.resourceKey=nil
            if b.SetEnabled then b:SetEnabled(false) end
            b:Hide()
        end
        f.resourcePages:SetText("0 / 0")
        for _,b in ipairs({f.resourcePrev,f.resourceNext,f.selectAll,f.selectNone}) do
            if b.SetEnabled then b:SetEnabled(false) end
        end
        if f.resourceInfo then
            f.resourceInfo:SetText(reason or "Resources unavailable. Select a map or retry this resource layer.")
            local minimal=self.lastFit and self.lastFit.breakpoint=="MINIMAL"
            f.resourceInfo:SetShown((not minimal or self._resourceEditorInDock) and
                not (self.optionsShown and self.dockResourcesExpanded~=true))
        end
    end
    if not id then unavailable("Select a map to browse historical gathering resources.");return end
    if type(layers)~="table" or type(layers.layers)~="table" then
        unavailable("No gathering layer data for this map. Switch map or reopen it.");return
    end
    if type(browser)~="table" or type(browser.Build)~="function" or
        type(rowRenderer)~="table" or type(rowRenderer.Apply)~="function" then
        unavailable("Resource browser unavailable. Reopen the map to retry.");return
    end
    local profession=self.resourceProfession or "HERBALISM"
    local current=layers.layers[profession]
    if type(current)~="table" then unavailable("No gathering resources for this layer.");return end
    if not current.learned then
        local alt=profession=="HERBALISM" and "MINING" or "HERBALISM"
        if type(layers.layers[alt])=="table" and layers.layers[alt].learned then profession=alt end
    end
    self.resourceProfession=profession
    local layer=layers.layers[profession]
    if type(layer)~="table" then unavailable("Gathering layer unavailable. Select another profession.");return end
    if editingMaterials then
        local state=viewState()
        local targets=routeSettings.smartMaterialTargets and routeSettings.smartMaterialTargets[profession] or {}
        layer={learned=layer.learned,enabled=layer.enabled,skill=layer.skill,
            resourceSelection=targets,resources=state:GetSmartMaterialChoices(profession)}
    end
    -- Sidebar anchors use -125 from the top and +72 from the bottom.
    -- Some offline shims return nil/zero for dual-anchored frame height.
    -- Recover from the actual parent height rather than showing a false empty
    -- resource list; if neither dimension is valid, retain the safe empty state.
    local viewport=JLP:GetModule("GatheringViewportLayout")
    local parentHeight=f.GetHeight and f:GetHeight() or
        (self.lastFit and self.lastFit.height)
    local measuredHeight=f.sidebar.GetHeight and f.sidebar:GetHeight() or nil
    local minimal=self.lastFit and self.lastFit.breakpoint=="MINIMAL"
    local inDock=self.optionsShown==true and self.dockResourcesExpanded==true and
        self._resourceEditorInDock==true
    local g=JLP.UITheme and JLP.UITheme.gathering or {}
    local budget
    if inDock and viewport and viewport.DockResourceListBudget then
        local scrollHeight=f.optionsScroll and f.optionsScroll.GetHeight and f.optionsScroll:GetHeight() or nil
        budget=viewport:DockResourceListBudget(parentHeight,scrollHeight,
            g.dockResourcesExpandedHeight,g.dockResourceRowsTop,g.dockResourcePagerTop)
    elseif viewport and viewport.ResourceListBudget then
        budget=viewport:ResourceListBudget(parentHeight,measuredHeight,minimal,
            (minimal and 91 or 111)+(self._resourceInfoExtra or 0))
    end
    -- Defensive fallback for a missing service during offline/UI partial load.
    local availableHeight=budget and budget.sidebarHeight or 0
    local perPage=math.min(#f.resourceRows,budget and budget.visibleRows or 0)
    self.resourcePageCapacity=perPage
    self:UpdateCompactResourceAccess(perPage==0 and minimal and not inDock)
    if perPage==0 then
        unavailable("Not enough viewport height; expand Resources and scroll to browse.")
        if minimal and not inDock then
            if f.resourceTitle then f.resourceTitle:SetText("RESOURCES · COMPACT VIEW") end
            if f.resourceInfo then
                f.resourceInfo:SetText("Too little room for resource choices.\nSelect Browse Resources below.")
                if f.resourceInfo.SetWordWrap then f.resourceInfo:SetWordWrap(true) end
                f.resourceInfo:Show()
            end
            -- No first/next resource page exists in the physical viewport.
            -- Keep the scrollable resource editor reachable through Options.
            for _,control in ipairs({f.resourcePrev,f.resourceNext,f.resourcePages,
                f.selectAll,f.selectNone}) do control:Hide() end
        end
        return
    end
    -- Page-aligned offsets avoid overlapping pages when the final page is
    -- shorter than the measured row capacity. Other browser clients retain
    -- their original row-by-row scrolling contract.
    local ok,listing=pcall(browser.Build,browser,layer,
        f.resourceSearch and f.resourceSearch:GetText() or "",self.resourceOffset,perPage,"PAGES")
    if not ok or type(listing)~="table" or type(listing.rows)~="table" then
        unavailable();return
    end
    self.resourceOffset=listing.offset
    local pageState=viewport and viewport.ResourcePageState and
        viewport:ResourcePageState(listing,perPage,layer)
    local opts=viewState() and viewState():GetSnapshot()
    local smart=opts and opts.mode=="SMART_PROFESSION"
    -- Saved resource flags are not automatically active planner filters.
    -- In Smart mode the planner chooses candidates independently; in Custom
    -- mode an unlearned/disabled layer must never count as eligible POINTs.
    -- LayerController is the qualification owner: saved flags are not eligible
    -- when the profession is not learned, even if layerEnabled persisted true.
    local feedback=JLP.UIWidgets and JLP.UIWidgets.GatheringResourceSelectionFeedback and
        JLP.UIWidgets:GatheringResourceSelectionFeedback(layer,listing.selectedCount,
            opts and opts.mode,listing.matchingCount,listing.totalCount)
    if editingMaterials then
        f.resourceInfo:SetText(tostring(listing.selectedCount).." material targets · all qualified zones; Generate to rank")
    elseif feedback then
        f.resourceInfo:SetText(feedback.text)
    else
        -- Partial Widgets loading: retain truthful fallback information rather
        -- than a blank status. This path does not own any selection state.
        local prefix=not layer.learned and "Not learned · " or
            not layer.enabled and "Layer off · " or ""
        local count=smart and 0 or (layer.learned and layer.enabled and listing.selectedCount or 0)
        f.resourceInfo:SetText(prefix..(smart and "Smart candidates" or
            (tostring(count).." effective · "..tostring(listing.selectedCount).." saved")))
    end
    if f.resourceInfo then f.resourceInfo:SetShown((not minimal or self._resourceEditorInDock) and
        (not self.optionsShown or self.dockResourcesExpanded==true)) end
    local nextExtra=(minimal and not inDock) and 0 or self:MeasureResourceHeaderExtra(inDock)
    if nextExtra~=(self._resourceInfoExtra or 0) then
        self._resourceInfoExtra=nextExtra
        self:PlaceResourceEditor(inDock)
        self._resourceStatusLayoutPending=true
    end
    if minimal and f.resourceTitle then f.resourceTitle:SetText(listing.selectedCount.." SELECTED · SCROLL TO BROWSE") end
    f.resourceTab:SetAlpha(profession=="HERBALISM" and 1 or 0.7)
    f.oreTab:SetAlpha(profession=="MINING" and 1 or 0.7)
    -- Partial/malformed layer snapshots must not fault the whole map UI.
    local herbs=layers.layers.HERBALISM
    local ores=layers.layers.MINING
    if f.resourceTab.SetEnabled then f.resourceTab:SetEnabled(type(herbs)=="table" and herbs.learned==true) end
    if f.oreTab.SetEnabled then f.oreTab:SetEnabled(type(ores)=="table" and ores.learned==true) end
    f.resourcePages:SetText(pageState and
        (pageState.page.." / "..pageState.pageCount) or
        (listing.first.."-"..listing.last.." / "..listing.matchingCount))
    if pageState and pageState.status~="READY" and f.resourceInfo then
        f.resourceInfo:SetText(pageState.text or "Resources unavailable")
        f.resourceInfo:SetShown(not (self.optionsShown and self.dockResourcesExpanded~=true))
    end
    -- At minimum frame height, explicit Prev/Next remain reachable even when
    -- the list only has a few rows. Never require mouse wheel as the only input.
    for _,b in ipairs({f.resourcePrev,f.resourceNext,f.resourcePages}) do b:Show() end
    for _,b in ipairs({f.selectAll,f.selectNone}) do
        b:SetShown(self._resourceEditorInDock or (not minimal and availableHeight>=270))
    end
    if f.resourcePrev.SetEnabled then f.resourcePrev:SetEnabled(pageState and pageState.canPrevious or listing.canPrevious) end
    if f.resourceNext.SetEnabled then f.resourceNext:SetEnabled(pageState and pageState.canNext or listing.canNext) end
    for i,b in ipairs(f.resourceRows) do
        local item=(not pageState or pageState.status=="READY") and
            i<=perPage and listing.rows[i] or nil
        b.__resourceFullName=item and item.name or nil
        rowRenderer:Apply(b,item,profession,layer.learned,smart and not editingMaterials,16)
    end
    if self.optionsShown and self.dockResourcesExpanded==true and self.UpdateDockSections then
        self:UpdateDockSections()
    end
    local canSelect=(not pageState or pageState.canSelect) and (not smart or editingMaterials)
    if f.selectAll.SetText then
        local text=f.resourceSearch and f.resourceSearch.GetText and f.resourceSearch:GetText() or ""
        f.selectAll:SetText(type(text)=="string" and text:match("%S") and "All matching" or "All")
    end
    if f.selectAll.SetEnabled then f.selectAll:SetEnabled(canSelect) end
    if f.selectNone.SetEnabled then f.selectNone:SetEnabled(canSelect) end
    -- A layer refresh must never resurrect hidden controls above the dock.
    if self.optionsShown and self.dockResourcesExpanded~=true then
        for _,control in ipairs({f.resourceSearch,f.resourceSearchClear,f.resourceTab,f.oreTab,f.resourceInfo,
            f.resourcePrev,f.resourceNext,f.resourcePages,f.selectAll,f.selectNone}) do control:Hide() end
        for _,control in ipairs(f.resourceRows) do control:Hide() end
    end
end
function Window:ScrollResources(delta)
    local before=self.resourceOffset or 0
    -- Prev/Next and mouse wheel move one FULL visible page. The final page
    -- may contain fewer rows, but it must never repeat the previous page.
    local capacity=math.max(1,tonumber(self.resourcePageCapacity) or 8)
    self.resourceOffset=math.max(0,before+((delta or 0)*capacity))
    self:RefreshResourceList()
    return before~=self.resourceOffset
end
function Window:SetAllResources(enabled)
    local state=viewState()
    local opts=state and state:GetSnapshot()
    if opts and opts.mode=="SMART_PROFESSION" and opts.focus=="MATERIALS" then
        local ok,reason=state:SetAllSmartMaterials(self.resourceProfession or "HERBALISM",enabled)
        if ok then self:OnContentChange() end
        return ok,reason
    end
    if opts and opts.mode~="CUSTOM_LOOP" then return false,"SMART_SELECTION_READ_ONLY" end
    if state and self.lastView then
        local ok,reason
        if enabled and type(state.ActivateZoneResources)=="function" then
            ok,reason=state:ActivateZoneResources(self.lastView.mapID,
                self.resourceProfession or "HERBALISM",
                self.frame and self.frame.resourceSearch and self.frame.resourceSearch:GetText() or "")
        else
            ok,reason=state:SetResourceSelectionAll(self.lastView.mapID,
                self.resourceProfession or "HERBALISM",enabled)
        end
        if ok then
            self:OnContentChange()
            return true,reason
        end
        if self.frame and self.frame.resourceInfo then
            self.frame.resourceInfo:SetText("Unable to select zone nodes · "..tostring(reason or "UNKNOWN"))
        end
        return false,reason
    end
    return false,"MAP_UNAVAILABLE"
end
function Window:ToggleResources()
    local f=self.frame
    if not f or self._continentPreview then return false,"CONTINENT_NAVIGATION_ONLY" end
    self.resourcesVisible=not (self.resourcesVisible~=false)
    self:ApplyContinentCanvasLayout()
    f.forceRedraw=true;self:Refresh()
end
function Window:Zoom(delta)
    local f=self.frame; if not f or not self.lastArt then return false end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local state=f.canvas.gatheringView or {}
    local zoom=math.max(1,math.min(3.5,(state.zoom or 1)+(delta>0 and 0.5 or -0.5)))
    map:SetViewport(f.canvas,zoom)
    f.forceRedraw=true;self:Refresh();return true
end
-- Mouse drag uses lightweight viewport-only painting. A full model/cluster
-- reconciliation happens ONCE when dragging ends, never on each cursor tick.
function Window:Pan(dx,dy,preview)
    local f=self.frame;if not f or not self.lastArt then return false end
    if type(dx)~="number" or type(dy)~="number" or dx~=dx or dy~=dy or
        (dx==0 and dy==0) then return false end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local t=map:ViewTransform(f.canvas,self.lastArt)
    local state=f.canvas.gatheringView or {}
    -- WoW screen cursor uses bottom-origin; normalized map Y increases down.
    local scale=f.GetEffectiveScale and f:GetEffectiveScale() or 1
    scale=type(scale)=="number" and scale>0 and scale or 1
    local oldX,oldY=state.centerX or 0.5,state.centerY or 0.5
    map:SetViewport(f.canvas,state.zoom,oldX-dx/(scale*self.lastArt.width*t.scale),
        oldY+dy/(scale*self.lastArt.height*t.scale))
    map:ViewTransform(f.canvas,self.lastArt) -- clamp new viewport to native art bounds
    if oldX==f.canvas.gatheringView.centerX and oldY==f.canvas.gatheringView.centerY then
        return false,"PAN_AT_EDGE"
    end
    if preview then
        local svc=source()
        if self._continentPreview then
            local ok,why=svc and svc:RenderArt(f.canvas,self.lastArt,false)
            if not ok then return false,why or "CONTINENT_PAN_PAINT_FAILED" end
            self._panDirty=true
            return true,"CONTINENT_PAN_PREVIEW"
        end
        local start=type(debugprofilestop)=="function" and debugprofilestop() or nil
        local ok,reason=svc and svc:RenderPan(f.canvas,self.lastArt,self.lastView)
        local finished=start and debugprofilestop() or nil
        self._panPreviewFrames=(self._panPreviewFrames or 0)+1
        if finished and finished>=start then
            local ms=finished-start
            self._panPreviewTotalMs=(self._panPreviewTotalMs or 0)+ms
            self._panPreviewMaxMs=math.max(self._panPreviewMaxMs or 0,ms)
            self._panPreviewLastMs=ms
        end
        self._panDirty=true
        if ok then return true,"PAN_PREVIEW" end
        -- No expensive full-refresh in the drag handler on cache failure:
        -- defer the complete reconciliation until mouse release.
        self._panPreviewFailures=(self._panPreviewFailures or 0)+1
        return false,reason or "PAN_PREVIEW_DEFERRED"
    end
    f.forceRedraw=true;self:Refresh();return true
end
function Window:FinishPan()
    local f=self.frame
    local canvas=f and f.canvas
    if not canvas or not canvas.panCursor then return false end
    local prev=canvas.panCursor
    canvas.panCursor=nil
    self.panElapsed=0
    if type(GetCursorPosition)=="function" then
        local x,y=GetCursorPosition()
        if type(x)=="number" and type(y)=="number" then
            self:Pan(x-prev.x,y-prev.y,true)
        end
    end
    if self._panDirty then
        self._panDirty=nil
        self._panCommits=(self._panCommits or 0)+1
        -- Rebuild source-bound clusters, clipping and map receipts once.
        f.forceRedraw=true
        return self:Refresh()
    end
    return true
end
-- Re-find the committed route after pan, zoom or reopening options. This is
-- navigation only; it cannot start work or promote an advisory route.
function Window:FocusCurrentRoute()
    local f=self.frame
    local view=self.lastView
    local router=JLP:GetModule("GatheringRouteService")
    local focus=JLP:GetModule("GatheringRouteViewport")
    if not (f and f.canvas and view and self.lastArt and router and focus) then
        return false,"ROUTE_VIEW_UNAVAILABLE" end
    local routes,status=router:GetRoutes(view.mapID)
    if status~="READY" or type(routes)~="table" then return false,"ROUTE_NOT_READY" end
    local ok,reason=focus:Apply(f.canvas,self.lastArt,
        {mapID=view.mapID,routes=routes},view.mapID)
    if not ok then
        if f.routeDetail then f.routeDetail:SetText("Cannot show route · "..tostring(reason)) end
        return false,reason
    end
    f.forceRedraw=true
    self:Refresh()
    return true,reason
end
function Window:ResetZoom()
    if not self.frame then return false end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    map:SetViewport(self.frame.canvas,1,0.5,0.5)
    self.frame.forceRedraw=true;self:Refresh();return true
end
function Window:Create()
    if self.frame then return self.frame end
    local preferences=settings()
    local f=CreateFrame("Frame","JuztLevelProfessionsStandaloneMap",UIParent)
    self.frame=f
    if JLP.UIWindowRegistry then
        JLP.UIWindowRegistry:Register("StandaloneMap",f)
        JLP.UIWindowRegistry:RegisterSpecial("JuztLevelProfessionsStandaloneMap")
    end
    if f.SetMovable then f:SetMovable(true) end
    if f.EnableMouse then f:EnableMouse(true) end
    -- Match Show() so reopening does not silently change the layer contract.
    if f.SetFrameStrata then f:SetFrameStrata("FULLSCREEN_DIALOG") end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W,MIN_H,MAX_W,MAX_H)
    else
        if f.SetMinResize then f:SetMinResize(MIN_W,MIN_H) end
        if f.SetMaxResize then f:SetMaxResize(MAX_W,MAX_H) end
    end
    -- Fit to the *current* viewport without overwriting manually saved geometry.
    -- At small effective UIParent sizes, even the nominal resize minimum may
    -- be too large, so an initial safe fit is allowed below the drag minimum.
    self:FitToViewport()
    JLP.UIWidgets:SkinPanel(f,"primary")
    local head=CreateFrame("Frame",nil,f)
    f.head=head
    head:SetPoint("TOPLEFT",f,"TOPLEFT",10,-6)
    head:SetPoint("TOPRIGHT",f,"TOPRIGHT",-46,-6)
    head:SetHeight(38)
    head:EnableMouse(true);head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart",function() if f.StartMoving then f:StartMoving() end end)
    head:SetScript("OnDragStop",function()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        Window:SavePosition()
    end)
    f.title=label(head,"Gathering Map","GameFontNormalLarge")
    f.title:SetPoint("LEFT",12,0)
    local close=CreateFrame("Button",nil,f)
    close:SetSize(28,28);close:SetPoint("TOPRIGHT",-14,-12)
    close:SetNormalTexture(JLP.UITheme:Asset("window\\close.tga"))
    close:SetScript("OnClick",function() Window:Hide() end)
    f.close=close
    f.kalimdor=button(f,"Kalimdor",98,"TOPLEFT",22,-56,function()
        Window:ToggleContinentZones("KALIMDOR")
    end)
    f.easternKingdoms=button(f,"Eastern Kingdoms",140,"TOPLEFT",128,-56,function()
        Window:ToggleContinentZones("EASTERN_KINGDOMS")
    end)
    f.current=button(f,"Current Zone",106,"TOPLEFT",276,-56,function() Window:UseCurrentZone() end)
    -- One reusable native-zone dropdown, never a second map editor or a
    -- second route owner. Use the shared scroll contract for long continents.
    f.zoneMenu=CreateFrame("Frame",nil,f)
    f.zoneMenu:SetSize(240,190)
    f.zoneMenu:EnableMouse(true)
    local zoneMenuBG=f.zoneMenu:CreateTexture(nil,"BACKGROUND")
    zoneMenuBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    zoneMenuBG:SetAllPoints()
    zoneMenuBG:SetVertexColor(0.004,0.020,0.034,0.98)
    JLP.UIWidgets:Border(f.zoneMenu,"border",1)
    f.zoneMenuScroll=JLP.UILayout:ScrollArea(f.zoneMenu,
        {width=232,height=180,contentWidth=216,scrollbarGutter=12,wheelStep=48})
    f.zoneMenuScroll:SetPoint("TOPLEFT",f.zoneMenu,"TOPLEFT",5,-5)
    f.zoneMenuRows={}
    f.zoneMenu:Hide()
    f.edit=button(f,"Resources",124,"TOPRIGHT",-22,-56,function()
        Window:CloseZoneMenu()
        Window:ToggleResources()
    end)
    -- Available even when the right dock is collapsed. No map-canvas overlay.
    -- At minimum W640, x=390..476 stays before Resources (x>=494).
    f.reloadMap=button(f,"Reload",86,"TOPLEFT",390,-56,function()
        Window:CloseZoneMenu()
        Window:ReloadMapArt()
    end)
    f.generate=button(f,"Generate Route",135,"TOPLEFT",22,-91,function() Window:GenerateRoute() end)
    f.clear=button(f,"Clear Route",110,"TOPLEFT",165,-91,function() Window:ClearRoute() end)
    -- Alpha170: spacious map with an independent resource sidebar. Controls
    -- that are not needed constantly live inside the sidebar, not above art.
    f.sidebar=CreateFrame("Frame",nil,f)
    f.sidebar:SetPoint("TOPRIGHT",f,"TOPRIGHT",-20,-125)
    f.sidebar:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-20,72)
    f.sidebar:SetWidth(228)
    local sideBG=f.sidebar:CreateTexture(nil,"BACKGROUND")
    sideBG:SetTexture("Interface\\Buttons\\WHITE8X8");sideBG:SetAllPoints()
    sideBG:SetVertexColor(0.015,0.05,0.075,0.92)
    JLP.UIWidgets:Border(f.sidebar,"border",1)
    -- The layer toggles have their own sibling slot ABOVE the resource body.
    -- Do not parent clickable controls beyond the sidebar's frame bounds.
    f.rightRailHeader=CreateFrame("Frame",nil,f)
    f.rightRailHeader:SetPoint("BOTTOMLEFT",f.sidebar,"TOPLEFT",0,0)
    f.rightRailHeader:SetSize(228,37)
    self.resourcesVisible=true
    f.herb=button(f.rightRailHeader,"Herbalism: Off",108,"TOPLEFT",4,-3,function()
        Window:ToggleLayer("HERBALISM")
    end)
    f.ore=button(f.rightRailHeader,"Mining: Off",108,"TOPLEFT",116,-3,function()
        Window:ToggleLayer("MINING")
    end)
    for _,layerButton in ipairs({f.herb,f.ore}) do
        layerButton:ClearAllPoints()
    end
    f.herb:SetPoint("TOPLEFT",f.rightRailHeader,"TOPLEFT",4,-3)
    f.ore:SetPoint("TOPLEFT",f.rightRailHeader,"TOPLEFT",116,-3)
    f.resourceTitle=label(f.sidebar,"RESOURCES · CURRENT ZONE","GameFontHighlightSmall")
    f.resourceTitle:SetPoint("TOPLEFT",10,-10)
    f.resourceSearch=CreateFrame("EditBox",nil,f.sidebar,"InputBoxTemplate")
    f.resourceSearch:SetSize(137,24);f.resourceSearch:SetPoint("TOPLEFT",11,-30)
    f.resourceSearchClear=button(f.sidebar,"Clear",48,"TOPLEFT",157,-30,function()
        Window:ClearResourceSearch()
    end)
    f.resourceSearchClear:SetHeight(24)
    if f.resourceSearch.SetAutoFocus then f.resourceSearch:SetAutoFocus(false) end
    if f.resourceSearch.SetFontObject then f.resourceSearch:SetFontObject("GameFontHighlightSmall") end
    f.resourceSearch:SetText("")
    f.resourceSearch:SetScript("OnTextChanged",function() Window.resourceOffset=0;Window:RefreshResourceList() end)
    f.resourceSearch:SetScript("OnEscapePressed",function(self) if self.ClearFocus then self:ClearFocus() end end)
    f.resourceTab=button(f.sidebar,"Herbs",96,"TOPLEFT",11,-59,function()
        Window.resourceProfession="HERBALISM";Window.resourceOffset=0;Window:RefreshResourceList()
    end)
    f.oreTab=button(f.sidebar,"Ores",96,"TOPLEFT",114,-59,function()
        Window.resourceProfession="MINING";Window.resourceOffset=0;Window:RefreshResourceList()
    end)
    if f.sidebar.EnableMouseWheel then f.sidebar:EnableMouseWheel(true) end
    f.sidebar:SetScript("OnMouseWheel",function(_,delta)
        Window:ScrollResources(delta<0 and 1 or -1)
    end)
    f.fishingFocusNotice=label(f.sidebar,"Historical fish catch areas only.\nNo verified pool points for a route.","GameFontHighlightSmall")
    f.fishingFocusNotice:SetPoint("TOPLEFT",11,-137)
    f.fishingFocusNotice:SetWidth(205);f.fishingFocusNotice:Hide()
    f.fishingShowHerbs=button(f.sidebar,"Show Herb/Ore layers",205,"TOPLEFT",11,-197,function()
        Window.includeGathering=true
        Window.fishingAdvice=nil
        Window.frame.forceRedraw=true
        Window:Refresh()
    end)
    f.fishingShowHerbs:Hide()
    f.resourceInfo=label(f.sidebar,"Choose nodes for Custom Loop","GameFontHighlightSmall")
    f.resourceInfo:SetPoint("TOPLEFT",11,-91)
    f.resourceRows={}
    for i=1,RESOURCE_ROW_POOL_SIZE do
        local b=button(f.sidebar,"",205,"TOPLEFT",11,-111-(i-1)*29,function(self)
            if Window.lastView and self.resourceKey and Window.resourceProfession then
                local state=viewState();local opts=state and state:GetSnapshot()
                local selected=state and state:GetResourceSelection(Window.lastView.mapID,Window.resourceProfession)
                if state and opts and opts.mode=="SMART_PROFESSION" and opts.focus=="MATERIALS" then
                    local targets=opts.smartMaterialTargets and opts.smartMaterialTargets[Window.resourceProfession] or {}
                    local ok,reason=state:SetSmartMaterialTarget(Window.resourceProfession,self.resourceKey,
                        targets[self.resourceKey]~=true)
                    if ok then Window:OnContentChange()
                    elseif f.resourceInfo then f.resourceInfo:SetText("Target unavailable · "..tostring(reason)) end
                elseif state and opts and opts.mode=="CUSTOM_LOOP" and type(state.SelectQualifiedZoneResource)=="function" then
                    local ok,reason=state:SelectQualifiedZoneResource(Window.lastView.mapID,
                        Window.resourceProfession,self.resourceKey,not (selected and selected[self.resourceKey]))
                    if ok then Window:OnContentChange()
                    elseif f.resourceInfo then
                        f.resourceInfo:SetText("Node unavailable · "..tostring(reason or "UNKNOWN"))
                    end
                end
            end
        end)
        b.resourceIcon=b:CreateTexture(nil,"OVERLAY")
        b.resourceIcon:SetSize(17,17)
        b.resourceIcon:SetPoint("LEFT",b,"LEFT",5,0)
        b:SetScript("OnEnter",function(self)
            if not self.resourceKey or not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_CURSOR")
            GameTooltip:SetText(self.__resourceFullName or self.resourceKey)
            if GameTooltip.AddLine then GameTooltip:AddLine("Historical resource · manual selection",0.65,0.79,0.91) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function(self)
            if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self) end
        end)
        f.resourceRows[i]=b
    end
    f.resourcePrev=button(f.sidebar,"<",35,"BOTTOMLEFT",11,80,function()
        Window:ScrollResources(-1)
    end)
    f.resourceNext=button(f.sidebar,">",35,"BOTTOMLEFT",178,80,function()
        Window:ScrollResources(1)
    end)
    f.resourcePages=label(f.sidebar,"1 / 1","GameFontHighlightSmall")
    f.resourcePages:SetPoint("BOTTOMLEFT",75,88)
    f.selectAll=button(f.sidebar,"All",95,"BOTTOMLEFT",11,44,function()
        Window:SetAllResources(true)
    end)
    f.selectNone=button(f.sidebar,"None",95,"BOTTOMLEFT",114,44,function()
        Window:SetAllResources(false)
    end)
    f.mode=button(f.sidebar,"Mode: Custom",98,"BOTTOMLEFT",11,94,function()
        local state=viewState();local current=state and state:GetSnapshot()
        if current then state:SetMode(current.mode=="CUSTOM_LOOP" and "SMART_PROFESSION" or "CUSTOM_LOOP");Window:OnContentChange() end
    end)
    f.focus=button(f.sidebar,"Focus: Balanced",98,"BOTTOMLEFT",114,94,function()
        local state=viewState();local current=state and state:GetSnapshot()
        if current and current.mode=="SMART_PROFESSION" then
            state:SetMode("SMART_PROFESSION",current.focus=="MATERIALS" and "SKILL" or
                current.focus=="SKILL" and "BALANCED" or "MATERIALS")
            Window:OnContentChange()
        end
    end)
    f.routeSources=button(f.sidebar,"Route nodes: All",205,"BOTTOMLEFT",11,63,function()
        local state=viewState()
        if state and state:CycleRouteSource() then Window:OnContentChange() end
    end)
    f.routeShape=button(f.sidebar,"Shape: Loop",190,"BOTTOMLEFT",11,32,function()
        local state=viewState();local opts=state and state:GetSnapshot()
        if opts and state:SetRouteShape(opts.routeShape=="LOOP" and "FROM_PLAYER" or "LOOP") then
            Window:OnContentChange()
        end
    end)
    f.fishingAreas=button(f.sidebar,"Fishing: On",98,"BOTTOMLEFT",11,32,function()
        local state=viewState();local current=state and state:GetSnapshot()
        if current and state:SetFishingAreas(not current.showFishingAreas) then Window:OnContentChange() end
    end)
    f.fishingFilter=button(f.sidebar,"Choose Fish",98,"BOTTOMLEFT",114,32,function()
        if f.fishResourcePicker then f.fishResourcePicker.Toggle() end
    end)
    local fishPicker=JLP:GetModule("FishingResourcePicker70450")
    f.fishResourcePicker=fishPicker and fishPicker:Attach(f.fishingFilter,
        function() return Window.lastView and Window.lastView.mapID end,
        function()
            Window:OnContentChange()
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end)
    -- Advanced fishing recommendation belongs to existing Fishing guide; there
    -- is no room to obscure the map with its own extra button.
    f.fishingRecommend=button(f.sidebar,"Suggest Fish",95,"BOTTOMLEFT",11,2,function()
        local ok,reason=Window:RecommendFishingZone()
        if not ok then Window.fishingAdvice="Fishing suggestion: "..tostring(reason);Window:Refresh() end
    end)
    -- Four logical workspaces share one reserved rail, never the map canvas:
    -- Gathering & Resources (default), Route Planning, Map Display, Route
    -- Information. Existing buttons keep their original handlers.
    f.options=button(f.sidebar,"Route Planning / Display",205,"BOTTOMLEFT",11,8,function()
        if Window._compactResourcesEmpty and not Window.optionsShown then
            Window.dockResourcesExpanded=true
            Window:SetRailWorkspace("OPTIONS")
            Window:OpenDockSection("resources")
        else
            Window:ToggleOptions()
        end
    end)
    f.resourceTitle:SetText("GATHERING & RESOURCES")
    -- 228-unit dock does not accommodate the prior long heading.
    f.optionsPanel=JLP.UIWidgets:Card(f.sidebar,"Map Options","secondary")
    f.optionsPanel:SetSize(228,193)
    f.optionsPanel:SetPoint("TOPLEFT",f.sidebar,"TOPLEFT",0,0)
    if f.optionsPanel.SetFrameLevel and f.sidebar.GetFrameLevel then
        local policy=JLP.UILayout
        f.optionsPanel:SetFrameLevel(policy and policy:OverlayFrameLevel(f.sidebar,"popover") or f.sidebar:GetFrameLevel()+15)
    end
    f.optionsScroll=CreateFrame("ScrollFrame",nil,f.optionsPanel)
    f.optionsScroll:SetPoint("TOPLEFT",f.optionsPanel,"TOPLEFT",8,-38)
    f.optionsScroll:SetSize(210,100)
    f.optionsContent=CreateFrame("Frame",nil,f.optionsScroll)
    f.optionsContent:SetSize(206,(JLP.UITheme and JLP.UITheme.gathering and JLP.UITheme.gathering.dockContentHeight) or 438)
    if type(f.optionsScroll.SetScrollChild)=="function" then
        f.optionsScroll:SetScrollChild(f.optionsContent)
    elseif f.optionsContent.SetParent then
        -- Offline Frame shims may not model ScrollFrame API. No secure/native fallback.
        f.optionsContent:SetParent(f.optionsPanel)
    end
    if f.optionsScroll.EnableMouseWheel then f.optionsScroll:EnableMouseWheel(true) end
    local function dockScrollBy(delta)
        local sc=f.optionsScroll
        if not (sc.GetVerticalScroll and sc.SetVerticalScroll) then return false end
        local g=(JLP.UITheme and JLP.UITheme.gathering) or {dockContentHeight=438,dockScrollFooter=55,dockMinViewport=40,dockScrollStep=35}
        local viewHeight=sc.GetHeight and sc:GetHeight() or 138
        local current=sc:GetVerticalScroll() or 0
        local layout=JLP.UILayout
        local contentHeight=f.optionsContent and f.optionsContent.GetHeight and
            f.optionsContent:GetHeight() or g.dockContentHeight
        local nextOffset=layout and layout:BoundedScrollOffset(current+delta,viewHeight,contentHeight) or
            math.max(0,math.min(contentHeight-viewHeight,current+delta))
        sc:SetVerticalScroll(nextOffset)
        Window:UpdateDockScrollControls()
        return true
    end
    local function onDockWheel(_,delta)
        dockScrollBy(-(delta or 0)*((JLP.UITheme and JLP.UITheme.gathering and JLP.UITheme.gathering.dockScrollStep) or 35))
    end
    f.optionsScroll:SetScript("OnMouseWheel",onDockWheel)
    -- Blank space inside the scroll child may be the wheel target on WoW;
    -- forward it without a second scroll owner or a keyboard focus hook.
    if f.optionsContent.EnableMouseWheel then f.optionsContent:EnableMouseWheel(true) end
    f.optionsContent:SetScript("OnMouseWheel",onDockWheel)
    -- Accordion overflow is indicated by a proportional scrollbar instead
    -- of duplicated Top/Bottom buttons. The four section shortcuts remain.
    f.dockScrollbar=JLP.UILayout:AttachNativeScrollbar(f.optionsScroll,
        {owner=f.optionsPanel,right=-2,top=-38,bottom=91,gutter=9})
    Window:UpdateDockScrollControls()
    -- Persistent section shortcuts: a closed Resources fold and a long resource
    -- search never trap Mode/Focus/Map Display below the scroll fold.
    for _,entry in ipairs({{"Resources","resources"},{"Route","route"},
        {"Display","display"},{"Info","information"}}) do
        local i=#(f.dockSectionJumps or {})+1
        f.dockSectionJumps=f.dockSectionJumps or {}
        local col=(i-1)%2
        local row=math.floor((i-1)/2)
        local jump=button(f.optionsPanel,entry[1],95,"BOTTOMLEFT",10+col*105,57-row*26,function()
            Window:OpenDockSection(entry[2])
        end)
        jump:SetHeight(22)
        f.dockSectionJumps[#f.dockSectionJumps+1]=jump
    end
    f.dockJumpResources=f.dockSectionJumps[1]
    f.dockJumpRoute=f.dockSectionJumps[2]
    f.dockJumpDisplay=f.dockSectionJumps[3]
    f.dockJumpInfo=f.dockSectionJumps[4]
    local function section(text,y)
        local title=label(f.optionsContent,text,"GameFontNormalSmall")
        title:SetPoint("TOPLEFT",8,y);title:SetWidth(190)
        return title
    end
    f.dockResourcesHeading=button(f.optionsContent,"[+] Resources / Filters",190,"TOPLEFT",8,-3,function()
        Window.dockResourcesExpanded=not (Window.dockResourcesExpanded==true)
        Window:UpdateDockSections()
        if Window.lastView then Window:RefreshResourceList(Window.lastView.mapID) end
        Window:FocusDockSection("resources")
    end)
    f.dockResourcesHeading:SetHeight(20)
    f.dockResourcesSummary=label(f.optionsContent,"Resource selection in Resources tab","GameFontHighlightSmall")
    f.dockResourcesSummary:SetPoint("TOPLEFT",8,-28)
    f.dockResourcesSummary:SetWidth(190)
    if f.dockResourcesSummary.SetWordWrap then f.dockResourcesSummary:SetWordWrap(true) end
    f.dockRouteHeading=button(f.optionsContent,"[-] Route Planning",190,"TOPLEFT",8,-67,function()
        Window.dockRouteExpanded=not (Window.dockRouteExpanded~=false)
        Window:UpdateDockSections()
        Window:FocusDockSection("route")
    end)
    f.dockRouteHeading:SetHeight(20)
    f.dockRouteSummary=label(f.optionsContent,"Mode / focus / source / shape", "GameFontHighlightSmall")
    f.dockRouteSummary:SetWidth(190);f.dockRouteSummary:SetHeight(28)
    if f.dockRouteSummary.SetWordWrap then f.dockRouteSummary:SetWordWrap(true) end
    f.mode:SetWidth(92); f.focus:SetWidth(92)
    for _,entry in ipairs({{f.mode,8,-24},{f.focus,107,-24},
        {f.routeSources,8,-55},{f.routeShape,8,-86},{f.fishingAreas,8,-117},
        {f.fishingFilter,107,-117},{f.fishingRecommend,8,-148}}) do
        local b=entry[1]
        if b.ClearAllPoints then b:ClearAllPoints() end
        if b.SetParent then b:SetParent(f.optionsContent) end
        b:SetPoint("TOPLEFT",f.optionsContent,"TOPLEFT",entry[2],entry[3])
        b:SetWidth((b==f.mode or b==f.focus) and 92 or
            (b==f.fishingAreas or b==f.fishingFilter) and 92 or 190)
        b:Hide()
    end
    f.dockDisplayHeading=button(f.optionsContent,"[-] Map Display",190,"TOPLEFT",8,-157,function()
        Window.dockDisplayExpanded=not (Window.dockDisplayExpanded~=false)
        Window:UpdateDockSections()
        Window:FocusDockSection("display")
    end)
    f.dockDisplayHeading:SetHeight(20)
    f.dockDisplaySummary=label(f.optionsContent,"Selected pins / layers", "GameFontHighlightSmall")
    f.dockDisplaySummary:SetWidth(190);f.dockDisplaySummary:SetHeight(28)
    if f.dockDisplaySummary.SetWordWrap then f.dockDisplaySummary:SetWordWrap(true) end
    f.fishingExtraLayer=button(f.optionsContent,"Herb/Ore: Hidden",190,"TOPLEFT",8,-176,function()
        Window.includeGathering=not Window.includeGathering
        Window.fishingAdvice=nil
        Window.frame.forceRedraw=true
        Window:Refresh()
    end)
    f.pinDisplay=button(f.optionsContent,"Pins: Selected resources",190,"TOPLEFT",8,-206,function()
        Window:CyclePinDisplay()
    end)
    f.skinningEvidence=label(f.optionsContent,"Skinning: no verified areas","GameFontHighlightSmall")
    f.skinningEvidence:SetPoint("TOPLEFT",8,-239);f.skinningEvidence:SetWidth(190)
    f.skinningEvidence:SetHeight(36) -- bounded before rationale/action region
    if f.skinningEvidence.SetWordWrap then f.skinningEvidence:SetWordWrap(true) end
    -- Item identities are browsed separately from AREA advice; no mob-output
    -- join is silently inferred. Both controls live INSIDE the same dock fold.
    f.skinningDetailToggle=button(f.optionsContent,"[+] Skinning materials",190,"TOPLEFT",8,-390,function()
        Window.dockSkinningExpanded=not (Window.dockSkinningExpanded==true)
        Window:UpdateDockSections()
        Window:FocusDockSection("display")
    end)
    f.skinningDetailToggle:SetHeight(22)
    f.skinningPrevItem=button(f.optionsContent,"Previous item",92,"TOPLEFT",8,-420,function()
        Window:CycleSkinningMaterial(-1)
    end)
    f.skinningNextItem=button(f.optionsContent,"Next item",92,"TOPLEFT",108,-390,function()
        Window:CycleSkinningMaterial(1)
    end)
    f.skinningMaterialDetails=label(f.optionsContent,"Skinning material research","GameFontHighlightSmall")
    f.skinningMaterialDetails:SetPoint("TOPLEFT",8,-425)
    f.skinningBank=button(f.optionsContent,"Inspect Bank",93,"TOPLEFT",8,-502,function()
        Window:InspectSkinningMaterial("Bank")
    end)
    f.skinningAH=button(f.optionsContent,"Manual AH",93,"TOPLEFT",108,-502,function()
        Window:InspectSkinningMaterial("Auction House")
    end)
    f.skinningMaterialDetails:SetWidth(192)
    f.skinningMaterialDetails:SetHeight(70) -- bounded before Bank/AH targets
    if f.skinningMaterialDetails.SetWordWrap then f.skinningMaterialDetails:SetWordWrap(true) end
    f.routeRationale=label(f.optionsContent,"Route rationale appears after selection","GameFontHighlightSmall")
    f.routeRationale:SetPoint("TOPLEFT",8,-273)
    f.routeRationale:SetWidth(190);f.routeRationale:SetHeight(26)
    if f.routeRationale.SetWordWrap then f.routeRationale:SetWordWrap(true) end
    f.dockInfoHeading=button(f.optionsContent,"[-] Route Information",190,"TOPLEFT",8,-303,function()
        Window.dockInformationExpanded=not (Window.dockInformationExpanded~=false)
        Window:UpdateDockSections()
        Window:FocusDockSection("information")
    end)
    f.dockInfoHeading:SetHeight(20)
    -- A folded information section must still expose GENERATING/READY/EMPTY
    -- from the existing route receipt, without a second route-state owner.
    f.dockInfoSummary=label(f.optionsContent,"No committed route · choose resources","GameFontHighlightSmall")
    f.dockInfoSummary:SetWidth(190);f.dockInfoSummary:SetHeight(48)
    if f.dockInfoSummary.SetWordWrap then f.dockInfoSummary:SetWordWrap(true) end
    f.whyRoute=button(f.optionsContent,"Why this route (details)",190,"TOPLEFT",8,-330,function()
        Window:FocusDockSection("information")
        Window:ToggleRouteExplanation(true)
    end)
    f.dockBack=button(f.optionsContent,"Close Map Options",190,"TOPLEFT",8,-336,function()
        Window:ToggleOptions()
    end)
    f.dockLegend=label(f.optionsContent,(JLP.UIWidgets.GatheringLegend and JLP.UIWidgets:GatheringLegend().full) or
        "Historical nodes and personal observations are past references, not live spawns","GameFontHighlightSmall")
    f.dockLegend:SetPoint("TOPLEFT",8,-370)
    f.dockLegend:SetWidth(190)
    if f.dockLegend.SetWordWrap then f.dockLegend:SetWordWrap(true) end
    f.dockOutcome=label(f.optionsContent,"No committed route · choose resources", "GameFontHighlightSmall")
    f.dockOutcome:SetWidth(190)
    if f.dockOutcome.SetWordWrap then f.dockOutcome:SetWordWrap(true) end
    Window:UpdateDockSections()
    f.optionsPanel:Hide()
    -- Route information uses a separate tab in the SAME right rail.
    f.detailsPanel=JLP.UIWidgets:Card(f.sidebar,"Route Information","secondary")
    f.detailsPanel:SetSize(228,193)
    f.detailsPanel:SetPoint("TOPLEFT",f.sidebar,"TOPLEFT",0,0)
    if f.detailsPanel.SetFrameLevel and f.sidebar.GetFrameLevel then
        local policy=JLP.UILayout
        f.detailsPanel:SetFrameLevel(policy and policy:OverlayFrameLevel(f.sidebar,"modal") or f.sidebar:GetFrameLevel()+16)
    end
    f.detailsText=label(f.detailsPanel,"No additional route information available.","GameFontHighlightSmall")
    f.detailsText:SetPoint("TOPLEFT",12,-43)
    f.detailsText:SetWidth(190);f.detailsText:SetHeight(82)
    if f.detailsText.SetWordWrap then f.detailsText:SetWordWrap(true) end
    f.detailsPage=label(f.detailsPanel,"1 / 1","GameFontHighlightSmall")
    f.detailsPage:SetPoint("BOTTOMLEFT",99,20)
    f.detailsPrevious=button(f.detailsPanel,"Prev",63,"BOTTOMLEFT",8,12,function()
        Window.explanationPage=(Window.explanationPage or 1)-1
        Window:RefreshRouteExplanation()
    end)
    f.detailsNext=button(f.detailsPanel,"Next",63,"BOTTOMRIGHT",-8,12,function()
        Window.explanationPage=(Window.explanationPage or 1)+1
        Window:RefreshRouteExplanation()
    end)
    f.detailsClose=button(f.detailsPanel,"Close",65,"TOPRIGHT",-9,-8,function()
        Window:ToggleRouteExplanation(false)
    end)
    f.detailsPanel:Hide()
    f.canvas=CreateFrame("Frame",nil,f)
    f.canvas.playerMarkerLayer=CreateFrame("Frame",nil,f.canvas)
    f.canvas.playerMarkerLayer:SetAllPoints(f.canvas)
    if f.canvas.playerMarkerLayer.EnableMouse then f.canvas.playerMarkerLayer:EnableMouse(false) end
    f.canvas:SetPoint("TOPLEFT",f,"TOPLEFT",22,-126)
    f.canvas:SetPoint("BOTTOMRIGHT",f.sidebar,"BOTTOMLEFT",-10,44)
    f.canvas.gatheringView={zoom=DEFAULT_MAP_ZOOM,centerX=0.5,centerY=0.5}
    if f.canvas.EnableMouse then f.canvas:EnableMouse(true) end
    if f.canvas.EnableMouseWheel then f.canvas:EnableMouseWheel(true) end
    f.canvas:SetScript("OnMouseWheel",function(_,delta) Window:Zoom(delta) end)
    -- Pin widgets can own mouse hover without blocking left-drag map panning.
    f.canvas.__gatheringPanStart=function()
        -- A resource pin may initiate pan, but clicking it must never change zone.
        Window:BeginMapPointer(false)
    end
    f.canvas.__gatheringPanStop=function()
        Window:EndMapPointer(false)
    end
    f.canvas:SetScript("OnMouseDown",function(_,key)
        if key=="LeftButton" then
            Window:BeginMapPointer(true)
        elseif key=="RightButton" and type(GetCursorPosition)=="function" then
            local x,y=GetCursorPosition()
            f.canvas.continentRightDown={x=x,y=y,
                source=Window.lastView and Window.lastView.mapID}
        end
    end)
    f.canvas:SetScript("OnMouseUp",function(_,key)
        if key=="LeftButton" then Window:EndMapPointer(true)
        elseif key=="RightButton" then
            local press=f.canvas.continentRightDown
            f.canvas.continentRightDown=nil
            if press and type(GetCursorPosition)=="function" then
                local x,y=GetCursorPosition()
                local scale=f.canvas.GetEffectiveScale and f.canvas:GetEffectiveScale() or 1
                local threshold=7*(type(scale)=="number" and scale>0 and scale or 1)
                if type(x)=="number" and type(y)=="number" and
                    math.abs(x-press.x)<=threshold and math.abs(y-press.y)<=threshold and
                    Window.lastView and Window.lastView.mapID==press.source then
                    Window:OpenContinentAtCursor(x,y)
                end
            end
        end
    end)
    f.mapControlBar=CreateFrame("Frame",nil,f)
    f.mapControlBar:SetPoint("TOPLEFT",f.canvas,"BOTTOMLEFT",0,-4)
    f.mapControlBar:SetPoint("TOPRIGHT",f.canvas,"BOTTOMRIGHT",0,-4)
    f.mapControlBar:SetHeight(36)
    f.zoomOut=button(f.mapControlBar,"−",34,"TOPLEFT",0,-4,function() Window:Zoom(-1) end)
    f.zoomIn=button(f.mapControlBar,"+",34,"TOPLEFT",40,-4,function() Window:Zoom(1) end)
    f.zoomReset=button(f.mapControlBar,"Fit",48,"TOPLEFT",80,-4,function() Window:ResetZoom() end)
    f.zoomRoute=button(f.mapControlBar,"Show Route",88,"TOPLEFT",134,-4,function()
        Window:FocusCurrentRoute()
    end)
    f.manualTargetButton=button(f.mapControlBar,"Material task",112,"TOPRIGHT",0,-4,function()Window:ToggleManualTargetEditor()end)
    f.zoomText=label(f.mapControlBar,"150%","GameFontHighlightSmall")
    f.zoomText:SetPoint("LEFT",235,0)
    if f.zoomText.SetWordWrap then f.zoomText:SetWordWrap(false) end
    local bg=f.canvas:CreateTexture(nil,"BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8");bg:SetAllPoints()
    bg:SetVertexColor(0.01,0.035,0.055,0.92)
    f.mapBackground=bg
    JLP.UIWidgets:Border(f.canvas,"border",1)
    f.fallback=label(f.canvas,"Awaiting verified Blizzard map tiles","GameFontHighlight")
    f.fallback:SetPoint("CENTER",0,0)
    f.status=label(f,"No active route","GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT",22,30)
    f.status:SetWidth(660)
    f.routeDetail=label(f,"Choose resources, then Generate Route","GameFontHighlightSmall")
    f.routeDetail:SetPoint("BOTTOMLEFT",22,12)
    f.routeDetail:SetWidth(510)
    f.routeWhy=button(f,"Why this route?",119,"BOTTOMRIGHT",-22,7,function()
        Window:ToggleRouteExplanation(true)
    end)
    if f.status.SetWordWrap then f.status:SetWordWrap(false) end
    if f.routeDetail.SetWordWrap then f.routeDetail:SetWordWrap(false) end
    f.sources=button(f,"Pins: All sources",165,"BOTTOMRIGHT",-22,43,function()
        local state=viewState()
        local current=state and state:GetSnapshot()
        if state and current then
            state:SetSourceFilter(current.sourceFilter=="ALL" and "OBSERVED_ONLY" or "ALL")
            Window:Refresh()
        end
    end)
    f.opacityText=label(f,"Map background: 85%","GameFontHighlightSmall")
    f.opacityText:SetPoint("BOTTOMLEFT",22,49)
    local slider=CreateFrame("Slider",nil,f)
    slider:SetSize(132,14)
    slider:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",169,51)
    slider:SetOrientation("HORIZONTAL");slider:SetMinMaxValues(0.2,1)
    if slider.SetValueStep then slider:SetValueStep(0.05) end
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local track=slider:CreateTexture(nil,"BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetPoint("LEFT",0,0);track:SetPoint("RIGHT",0,0);track:SetHeight(4)
    track:SetVertexColor(0.24,0.42,0.57,0.95)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetScript("OnValueChanged",function(_,value) Window:SetBackgroundOpacity(value) end)
    f.opacitySlider=slider
    f.chromeText=label(f,"UI chrome: 100%","GameFontHighlightSmall")
    f.chromeText:SetPoint("BOTTOMLEFT",319,49)
    local chromeSlider=CreateFrame("Slider",nil,f)
    chromeSlider:SetSize(98,14)
    chromeSlider:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",439,51)
    chromeSlider:SetOrientation("HORIZONTAL");chromeSlider:SetMinMaxValues(0.35,1)
    if chromeSlider.SetValueStep then chromeSlider:SetValueStep(0.05) end
    if chromeSlider.SetObeyStepOnDrag then chromeSlider:SetObeyStepOnDrag(true) end
    local chromeTrack=chromeSlider:CreateTexture(nil,"BACKGROUND")
    chromeTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
    chromeTrack:SetPoint("LEFT",0,0);chromeTrack:SetPoint("RIGHT",0,0);chromeTrack:SetHeight(4)
    chromeTrack:SetVertexColor(0.24,0.42,0.57,0.95)
    chromeSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    chromeSlider:SetScript("OnValueChanged",function(_,value) Window:SetChromeOpacity(value) end)
    f.chromeSlider=chromeSlider
    local handle=CreateFrame("Button",nil,f)
    handle:SetSize(26,26);handle:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-2,2)
    handle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    handle:SetScript("OnMouseDown",function(_,key)
        if key=="LeftButton" and f.StartSizing then f:StartSizing("BOTTOMRIGHT") end
    end)
    handle:SetScript("OnMouseUp",function()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        Window:SavePosition()
    end)
    f.resizeHandle=handle
    f.canvas:SetScript("OnSizeChanged",function()
        if Window.lastView and f:IsShown() then
            -- Batch resize redraws: do not reconstruct 520 markers for every
            -- mouse pixel when a player drags the window grip.
            f.forceRedraw=true
            Window.elapsed=math.max(Window.elapsed or 0,0.75)
        end
    end)
    f:SetScript("OnMouseDown",function() Window:CloseZoneMenu() end)
    f:SetScript("OnSizeChanged",function(_,width,height)
        -- Redraw after viewport resize; persistence is handled on user release
        -- by SavePosition(), never from programmatic SetSize or :Show().
        if Window._created and width and height then
            f.forceRedraw=true
            Window._resizePending=true
            Window._resizeElapsed=0
        end
    end)
    f:SetScript("OnShow",function()
        local state=viewState();if state then state:SetStandaloneSettings({visible=true}) end
        Window:Refresh()
    end)
    f:SetScript("OnHide",function()
        Window:CloseZoneMenu()
        -- UISpecialFrames/Escape invokes frame:Hide directly. Use the same
        -- viewport retirement path as the Close button, not merely map:Clear.
        if not Window._closingWindow then Window:Hide() end
        local state=viewState();if state then state:SetStandaloneSettings({visible=false}) end
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        if map then map:Clear(f.canvas) end
        local coordinator=JLP:GetModule("GatheringWindowCoordinator")
        if coordinator then coordinator:OnStandaloneHidden() end
    end)
    f:SetScript("OnUpdate",function(_,elapsed)
        local dt=type(elapsed)=="number" and elapsed or 0.05
        Window.panElapsed=(Window.panElapsed or 0)+dt
        Window._smartAssessElapsed=(Window._smartAssessElapsed or 0)+dt
        if Window._smartAssessElapsed>=0.05 then
            Window._smartAssessElapsed=0
            local recommendation=JLP:GetModule("GatheringZoneSuitability")
            if recommendation and recommendation:GetRecommendationStatus()=="GENERATING" then
                recommendation:TickRecommendation()
            end
        end
        -- Target ~43 Hz (23 ms), with a larger interval if the last paint exceeded
        -- the CPU budget (e.g. a dense, dashed route). Prevent a long drag
        -- from monopolizing the client's render thread.
        local cost=Window._panPreviewLastMs or 0
        local cadence=cost>40 and 0.085 or cost>20 and 0.055 or 0.023
        -- Track any meaningful movement every frame, even when redraw is
        -- throttled. Moving out and back must not become a zone click.
        if f.canvas.zonePointerStart and GetCursorPosition then
            local pointerX,pointerY=GetCursorPosition()
            Window:UpdateMapPointerMovement(pointerX,pointerY)
        end
        if f.canvas.panCursor and (not f.canvas.zonePointerStart or
            f.canvas.zonePointerStart.moved) and GetCursorPosition and
            Window.panElapsed>=cadence then
            Window.panElapsed=0
            local x,y=GetCursorPosition()
            local last=f.canvas.panCursor
            if math.abs(x-last.x)+math.abs(y-last.y)>=2 then
                Window:Pan(x-last.x,y-last.y,true)
                f.canvas.panCursor={x=x,y=y}
            end
        end
        if Window._resizePending then
            Window._resizeElapsed=(Window._resizeElapsed or 0)+dt
            if Window._resizeElapsed>=0.18 then
                Window._resizePending=false
                Window:ReflowContentLayout()
            end
        end
        if Window._resourceStatusLayoutPending then
            Window._resourceStatusLayoutPending=false
            if Window.lastView then Window:RefreshResourceList(Window.lastView.mapID) end
        end
        Window.elapsed=(Window.elapsed or 0)+dt
        if Window.elapsed<0.9 then return end
        Window.elapsed=0
        -- A heartbeat/moving-player full Refresh would otherwise re-run the
        -- entire clustering pipeline mid-drag and cause a periodic hitch.
        if f.canvas.panCursor then return end
        -- WoW may change its logical UIParent dimensions without rebuilding
        -- addon frames. Compare only once per refresh cycle, not per frame.
        local layout=JLP:GetModule("GatheringViewportLayout")
        local viewportChanged=false
        if layout then
            local w=UIParent and UIParent.GetWidth and UIParent:GetWidth()
            local h=UIParent and UIParent.GetHeight and UIParent:GetHeight()
            local scale=UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
            if layout:Signature(w,h,scale)~=Window.viewportSignature then
                viewportChanged=select(1,Window:FitToViewport())==true
            end
        end
        -- Redraw cadence is independent of the single service-owned route driver.
        local page=JLP.UIPages and JLP.UIPages.Secondaries
        local embedded=page and page.frame and page.frame.views and page.frame.views.FISHING
        local route=JLP:GetModule("GatheringRouteService")
        local active=embedded and embedded.mapArt and embedded.mapArt.IsVisible and embedded.mapArt:IsVisible()
        local routeBusy=route and route:GetStatus()=="GENERATING"
        local suitability=JLP:GetModule("GatheringZoneSuitability")
        local suitabilityBusy=suitability and suitability:GetRecommendationStatus()=="GENERATING"
        -- Recommendation work is driven above on a bounded, responsive 50ms
        -- cadence, not once every 900ms. No duplicate heartbeat Tick here.
        -- Skip expensive full-map render while the player is stationary and
        -- no job/viewport/input is changing. A bounded heartbeat still picks
        -- up inventory, map and external changes without relying on one event.
        local speedFn=type(GetUnitSpeed)=="function" and GetUnitSpeed or nil
        local speed=speedFn and tonumber(speedFn("player")) or nil
        local movementUnknown=speed==nil
        local budget=JLP:GetModule("GatheringRefreshBudget")
        if not Window._refreshBudget and budget then Window._refreshBudget=budget:New() end
        local doRefresh=not budget or budget:ShouldRefresh(Window._refreshBudget,0.9,{
            viewportChanged=viewportChanged,force=f.forceRedraw or not Window.lastView,
            generating=routeBusy or suitabilityBusy,
            moving=movementUnknown or speed>0,
        })
        if doRefresh then Window:Refresh() end
    end)
    f.sidebarBg=sideBG
    -- No nil holes: ipairs on a sparse literal truncated the opacity pass.
    -- Avoid nested parent/child alpha multiplication by targeting leaf controls;
    -- sidebar skin textures remain individually adjustable, map art is excluded.
    -- Hover hints give full action identity even at the minimum dock width.
    local function hint(control,describe)
        if not control then return end
        control:SetScript("OnEnter",function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_CURSOR")
            GameTooltip:SetText(describe())
            GameTooltip:Show()
        end)
        control:SetScript("OnLeave",function(self)
            if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self) end
        end)
    end
    hint(f.mode,function()
        local state=viewState();local current=state and state:GetSnapshot()
        return "Route mode: "..(current and current.mode=="SMART_PROFESSION" and "Smart Profession" or "Custom Loop")
    end)
    hint(f.focus,function()
        local state=viewState();local current=state and state:GetSnapshot()
        return current and current.mode=="SMART_PROFESSION" and
            ("Smart Route Focus: "..tostring(current.focus)..
             ". Filters historical reference pins; Generate Route is required to plan a route.") or
            "Route Focus is available only in Smart mode."
    end)
    hint(f.herb,function()
        local text=f.herb.label and f.herb.label.GetText and f.herb.label:GetText() or "Herbalism"
        return tostring(text)
    end)
    hint(f.ore,function()
        local text=f.ore.label and f.ore.label.GetText and f.ore.label:GetText() or "Mining"
        return tostring(text)
    end)
    hint(f.reloadMap,function()return "Reload the current zone map artwork (no route generation)" end)
    -- Phase 1 UI contract: make similarly named controls distinguishable without
    -- changing gameplay, map filtering, persistent resource choices or anchors.
    -- One control has one owner and one OnClick; these are hover explanations.
    hint(f.edit,function()
        return "Show or hide the Resources panel. This does not change selected resources or the map layers."
    end)
    hint(f.resourceTab,function()
        return "Browse herb reference types in this zone. This does not turn the Herbalism map layer on or off."
    end)
    hint(f.oreTab,function()
        return "Browse ore reference types in this zone. This does not turn the Mining map layer on or off."
    end)
    hint(f.resourceSearchClear,function()
        return "Clear only the resource search text. Your saved resource selections are unchanged."
    end)
    hint(f.selectAll,function()
        return "Select all eligible matching reference types for Custom Loop. Disabled in Smart Profession mode."
    end)
    hint(f.selectNone,function()
        return "Clear manual resource selections for this zone and profession. Disabled in Smart Profession mode."
    end)
    hint(f.sources,function()
        return "Filter visible pin sources: all historical references or your own observed references. Does not change resource choices."
    end)
    hint(f.pinDisplay,function()
        return "Change pin appearance between compact clusters, selected-resource view and detailed view. Does not change saved selections."
    end)
    hint(f.options,function()
        return Window._compactResourcesEmpty and
            "Open the scrollable resource browser in Map Options, keeping current selections." or
            "Open Map Options for route mode, focus, map display and read-only route information."
    end)
    hint(f.generate,function()
        return "Generate an advisory gathering route from the current mode and eligible historical references."
    end)
    hint(f.clear,function()
        return "Clear or cancel the current gathering route without clearing the manually selected resources."
    end)
    hint(f.zoomReset,function()
        return "Fit the zone map at 100% zoom. Newly opened zones use 150% by default."
    end)
    hint(f.current,function()
        return "Switch back to the player’s current zone."
    end)
    hint(f.routeWhy,function()
        return "Read the explanation and status of the current route; this does not start or change a route."
    end)
    f.chromeTargets={}
    local seen={}
    local function chrome(target)
        if target and target.SetAlpha and not seen[target] then
            seen[target]=true
            f.chromeTargets[#f.chromeTargets+1]=target
        end
    end
    chrome(f.sidebarBg)
    for _,target in pairs({f.title,f.close,f.sidebarTitle,f.resourceInfo,
        f.resourcePrev,f.resourceNext,f.selectAll,f.selectNone,f.options,
        f.previous,f.next,f.current,f.herb,f.ore,f.generate,f.clear,
        f.opacityText,f.routeRationale,f.skinningEvidence,f.skinningBank,f.skinningAH,
        f.whyRoute,f.routeDetail,f.sources,f.fishingAreas,f.fishingFilter,
        f.fishingRecommend,f.mode,f.focus,f.routeSources,f.fishingExtraLayer,
        f.chromeText,f.zoomOut,f.zoomIn,f.zoomReset,f.zoomRoute,f.zoomText,
        f.resourceSearch,f.resourceSearchClear,f.resourceTab,f.oreTab,
        f.resourcePages,f.reloadMap,f.edit,f.pinDisplay}) do chrome(target) end
    for _,target in pairs(f.resourceRows or {}) do chrome(target) end
    for _,target in pairs(f.dockSectionJumps or {}) do chrome(target) end
    -- Set the sliders last, after frame hooks, to keep the real readout in sync.
    slider:SetValue(preferences.backgroundOpacity)
    chromeSlider:SetValue(preferences.chromeOpacity or 1)
    self._created=true
    f:Hide()
    return f
end
function Window:Show()
    if not self.contentContext then self:SetContentContext("GATHERING") end
    local f=self:Create()
    -- Reopening must also fit a window originally created at a different
    -- resolution; :Create() is intentionally only invoked once per session.
    local fitted,reason=self:FitToViewport()
    if not fitted then
        if JLP.Print then JLP:Print("Gathering Map needs more screen space. Lower UI scale or increase resolution ("..tostring(reason)..").") end
        return false,reason
    end
    if f.SetFrameStrata then f:SetFrameStrata("FULLSCREEN_DIALOG") end
    if f.Raise then f:Raise() end
    local wasShown=f:IsShown()
    self._refreshBudget=nil
    self._panDirty=nil;self.panElapsed=0
    f:Show()
    local state=viewState()
    if state then state:SetStandaloneSettings({visible=true}) end
    if wasShown then self:Refresh() end
    return true
end
function Window:GetRefreshDiagnostics()
    local j=self._refreshBudget or {}
    local previews=self._panPreviewFrames or 0
    return {contract="jlp-gathering-refresh-diagnostics-v2",
        checked=j.checked or 0,refreshed=j.refreshed or 0,skipped=j.skipped or 0,
        lastReason=j.lastReason or "NOT_STARTED",clientMeasured=false,
        panPreviewFrames=previews,panPreviewFailures=self._panPreviewFailures or 0,
        panCommits=self._panCommits or 0,
        panPreviewAverageMs=previews>0 and (self._panPreviewTotalMs or 0)/previews or nil,
        panPreviewMaxMs=self._panPreviewMaxMs or nil}
end
function Window:Hide()
    if self._closingWindow then return true end
    self:ExitContinentPreview()
    self._smartGenerateSerial=(self._smartGenerateSerial or 0)+1
    local assessor=JLP:GetModule("GatheringZoneSuitability")
    if assessor then assessor:CancelRecommendation("WINDOW_CLOSED") end
    self._closingWindow=true
    -- This is only a viewport close, NOT Map Stop: the embedded Secondaries
    -- viewer uses the same service-owned generation and must continue receiving
    -- a READY result. Retire only this viewport's callbacks and overlay receipt.
    self._routeRequestSerial=(self._routeRequestSerial or 0)+1
    self._routeProgressToken=nil
    self._mapPresentation=nil;self._lastOverlay=nil
    self.routeResult=nil;self.routeFeedback=nil
    self._refreshBudget=nil
    self._panDirty=nil;self.panElapsed=0
    if self.frame and self.frame.canvas then
        self.frame.canvas.panCursor=nil
        self.frame.canvas.zonePointerStart=nil
    end
    self:CloseZoneMenu()
    if self.frame then
        local overlay=JLP:GetModule("GatheringMapOverlay")
        if overlay and type(overlay.Clear)=="function" and self.frame.canvas then
            pcall(overlay.Clear,overlay,self.frame.canvas)
        end
        self.frame.forceRedraw=true
        if self.detailsShown then self:ToggleRouteExplanation(false) end
        if JLP.UIWindowRegistry then JLP.UIWindowRegistry:CloseOwner("StandaloneMap") end
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltipTree(self.frame) end
        self.frame:Hide()
    end
    local state=viewState()
    if state then state:SetStandaloneSettings({visible=false}) end
    self._closingWindow=false
    return true
end
-- A read-only acceptance diagnostic for native adjacent-zone clicks.
-- Logs no positions except normalized zone-hit coordinates from the last
-- completed click; does not query/map/modify gameplay state.
_G.SLASH_JLP_MAP_ZONE_CLICK1="/jlmapclick"
SlashCmdList["JLP_MAP_ZONE_CLICK"]=function()
    local d=Window._lastZoneClick
    if JLP.Print then
        if not d then
            JLP:Print("Map zone click: no eligible artwork click attempted yet.")
        else
            local coords=d.x and d.y and
                string.format(" (%.3f, %.3f)",d.x,d.y) or ""
            JLP:Print("Map zone click: "..tostring(d.status)..
                " | source="..tostring(d.source or "n/a")..
                " | target="..tostring(d.target or "n/a")..
                " | zone="..tostring(d.name or "n/a")..coords)
        end
    end
end
-- Optional read-only local performance readout. Does not profile gameplay,
-- mutate settings or claim a controlled native benchmark.
_G.SLASH_JLP_MAP_PAN_PERF1="/jlpanperf"
SlashCmdList["JLP_MAP_PAN_PERF"]=function()
    local d=Window:GetRefreshDiagnostics()
    local avg=d.panPreviewAverageMs and string.format("%.2f",d.panPreviewAverageMs) or "unavailable"
    local peak=d.panPreviewMaxMs and string.format("%.2f",d.panPreviewMaxMs) or "unavailable"
    if JLP.Print then
        JLP:Print("Gathering Map pan preview: "..tostring(d.panPreviewFrames)..
            " frames | failures "..tostring(d.panPreviewFailures)..
            " | commits "..tostring(d.panCommits)..
            " | Lua CPU average/max "..avg.."/"..peak.." ms (if profiled). "..
            "Client FPS and texture upload cost are not measured.")
    end
end
-- Read-only diagnostic: exact reference availability versus representative
-- pins and performance ceiling. It does not mutate resource selections.
_G.SLASH_JLP_MAP_PIN_COVERAGE1="/jlpincoverage"
SlashCmdList["JLP_MAP_PIN_COVERAGE"]=function()
    local c=Window.frame and Window.frame.canvas
    local overlay=JLP:GetModule("GatheringMapOverlay")
    local d=overlay and overlay:GetSelectionDiagnostics() or {}
    local stats=Window._lastStats or {}
    local total=tonumber(stats.total) or 0
    local visible=tonumber(stats.visible) or 0
    local candidates=tonumber(stats.visibleCandidates) or tonumber(d.visibleCandidates) or visible
    local status=d.budgetLimited and "YES" or "NO"
    if JLP.Print then
        JLP:Print("Gathering pin coverage: map="..tostring(c and c.gatheringOverlayMapID or "none")..
            " | references="..total.." | visible candidate clusters="..candidates..
            " | displayed pins="..visible.." | cap="..tostring(stats.budget or d.budget or 0)..
            " | budget-limited="..status..
            " | kinds="..tostring(stats.representedResourceKinds or d.representedKindCount or 0)..".")
    end
end
-- Persistence is per-character. Visibility is restored only when explicitly
-- left enabled; no auto-open from temporary preview frames.
local loader=CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent",function()
    local state=viewState()
    local v=state and state:GetStandaloneSettings()
    if v and v.visible then Window:Show() end
end)
JLP.StandaloneGatheringMap=Window
