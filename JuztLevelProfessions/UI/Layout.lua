local _, JLP = ...

-- Deterministic layout helpers. WoW Frames are used as bounded containers in
-- the same spirit as HTML block elements: explicit size, padding and overflow.
local Layout = {}

local function finiteNumber(value, fallback)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then
        return fallback
    end
    return value
end
local function clamp(value, minimum, maximum)
    value=finiteNumber(value,0)
    minimum=finiteNumber(minimum,0)
    maximum=finiteNumber(maximum,minimum)
    if maximum<minimum then maximum=minimum end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

-- Shared source-level bounds for docked and embedded scrollports.
-- Rendering/focus remain with each owning WoW ScrollFrame; no keyboard capture.
function Layout:BoundedScrollOffset(offset,viewportHeight,contentHeight)
    local visible=math.max(1,finiteNumber(viewportHeight,1))
    local total=math.max(visible,finiteNumber(contentHeight,visible))
    return clamp(offset,0,total-visible),total-visible
end
function Layout:PreserveScrollRatio(offset,previousHeight,nextHeight,contentHeight)
    local old,oldMax=self:BoundedScrollOffset(offset,previousHeight,contentHeight)
    local _,newMax=self:BoundedScrollOffset(0,nextHeight,contentHeight)
    return newMax*(oldMax>0 and old/oldMax or 0)
end

-- The dock has a non-scrolling header AND two non-scrolling footer rows.
-- A viewport that subtracts only the footer overlaps navigation shortcuts;
-- allocate all three bands before children are positioned or made clickable.
function Layout:DockViewportHeight(railHeight,headerHeight,footerHeight,minHeight)
    local rail=tonumber(railHeight) or 0
    local head=tonumber(headerHeight) or 0
    local foot=tonumber(footerHeight) or 0
    local minimum=math.max(1,tonumber(minHeight) or 1)
    if rail~=rail or rail<0 or head~=head or head<0 or foot~=foot or foot<0 then
        return minimum
    end
    return math.max(minimum,math.floor(math.max(0,rail-head-foot)))
end
function Layout:SyncHiddenInput(frame,shown)
    if not frame then return false end
    shown=shown==true
    if frame.SetShown then frame:SetShown(shown) end
    if frame.EnableMouse then frame:EnableMouse(shown) end
    if frame.EnableMouseWheel then frame:EnableMouseWheel(shown) end
    return true
end

-- Safe source-sheet sizing for Guide and Secondaries; no font-pixel or
-- native-client assumptions. A positive measured FontString height may only
-- expand the estimate, never shrink available scrollable text.
-- Pure source-derived content contract. A changing notice may increase
-- content height, but NaN/negative/absurd measurements cannot strand scroll
-- controls outside a bounded viewport. This has no protected API side effects.
function Layout:BoundedContentHeight(content,viewport,maximum)
    local v=tonumber(viewport) or 1
    if v~=v or v<1 or v==math.huge then v=1 end
    local c=tonumber(content) or v
    if c~=c or c<0 or c==math.huge then c=v end
    local cap=tonumber(maximum) or 8000
    if cap~=cap or cap<v then cap=math.max(v,8000) end
    return math.max(v,math.min(cap,c))
end
-- Scroll after dynamic content has been rebuilt: SetContentHeight(...,true)
-- otherwise deliberately retains the prior deep offset. Used by Guide Back
-- and the shared SourceSheet; optional for lightweight/offline mocks.
function Layout:ReturnToScrollOrigin(viewport)
    if type(viewport)~="table" then return false end
    if type(viewport.ScrollTo)=="function" then viewport:ScrollTo(0); return true end
    if type(viewport.ScrollPage)=="function" then viewport:ScrollPage(0); return true end
    if type(viewport.SetVerticalScroll)=="function" then viewport:SetVerticalScroll(0); return true end
    return false
end
-- Transient, never SavedVariables: capture and restore an existing view's
-- scroll only after its owning page has rebuilt/validated its content.
function Layout:CaptureScrollPosition(viewport)
    if type(viewport)~="table" then return 0 end
    local value=viewport.__scrollOffset or viewport.scrollOffset
    if value==nil and type(viewport.GetVerticalScroll)=="function" then
        local ok,v=pcall(viewport.GetVerticalScroll,viewport)
        if ok then value=v end
    end
    value=tonumber(value) or 0
    if value~=value or value<0 or value==math.huge then return 0 end
    return math.min(value,100000)
end
function Layout:RestoreScrollPosition(viewport,offset)
    if type(viewport)~="table" then return false end
    local value=tonumber(offset)
    if not value or value~=value or value<0 or value==math.huge then return false end
    value=math.min(value,100000)
    if type(viewport.ScrollTo)=="function" then viewport:ScrollTo(value);return true end
    if type(viewport.ScrollPage)=="function" then viewport:ScrollPage(value);return true end
    if type(viewport.SetVerticalScroll)=="function" then
        local visible=viewport.GetHeight and viewport:GetHeight() or 1
        local child=viewport.GetScrollChild and viewport:GetScrollChild()
        local total=child and child.GetHeight and child:GetHeight() or nil
        if total then value=self:BoundedScrollOffset(value,visible,total) end
        viewport:SetVerticalScroll(value);return true
    end
    return false
end
function Layout:AdvisoryTextContentHeight(text,viewportHeight,measuredHeight)
    local height=tonumber(viewportHeight) or 280
    if height~=height or height<=0 then height=280 end
    local chars=type(text)=="string" and #text or 0
    local estimated=math.max(height,math.min(8000,math.ceil(chars/45)*20+120))
    local measured=tonumber(measuredHeight)
    if measured and measured==measured and measured>0 and measured<100000 then
        estimated=math.max(estimated,measured+24)
    end
    return self:BoundedContentHeight(estimated,height,8000)
end
-- Alpha290-uiarch6: reusable scrollbar for existing native ScrollFrames and
-- virtualised lists. This is a visual/input primitive only. Existing content,
-- pagination data and qualified read-only authority remain unchanged.
function Layout:AttachOffsetScrollbar(owner, options)
    options=options or {}
    if not owner or type(options.getState)~="function" or
        type(options.setOffset)~="function" then return nil end
    local gutter=math.max(8,tonumber(options.gutter) or 11)
    local track=CreateFrame("Button",nil,owner)
    track:SetWidth(gutter)
    track:SetPoint("TOPRIGHT",owner,"TOPRIGHT",tonumber(options.right) or -1,
        tonumber(options.top) or -1)
    track:SetPoint("BOTTOMRIGHT",owner,"BOTTOMRIGHT",tonumber(options.right) or -1,
        tonumber(options.bottom) or 1)
    local fill=track:CreateTexture(nil,"BACKGROUND")
    fill:SetAllPoints();fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetVertexColor(0.04,0.14,0.20,0.9)
    local thumb=CreateFrame("Button",nil,track)
    thumb:SetWidth(math.max(6,gutter-2))
    local ink=thumb:CreateTexture(nil,"ARTWORK")
    ink:SetAllPoints();ink:SetTexture("Interface\\Buttons\\WHITE8X8")
    ink:SetVertexColor(JLP.UITheme:Color("cyan"))
    local bar={track=track,thumb=thumb,owner=owner,maximum=0,travel=0,extent=1}
    function bar:Refresh()
        local offset,maximum,visible,total=options.getState()
        maximum=finiteNumber(maximum,0)
        visible=finiteNumber(visible,1)
        total=finiteNumber(total,visible)
        if maximum<0 then maximum=0 end
        local trackHeight=math.max(1,track.GetHeight and track:GetHeight() or 1)
        self.maximum=maximum
        local overflow=maximum>0.5 and visible>0
        track:SetShown(overflow)
        if not overflow then self.travel=0;return end
        local size=math.min(trackHeight,math.max(24,math.floor(trackHeight*visible/math.max(total,visible)+0.5)))
        self.travel=math.max(0,trackHeight-size)
        self.extent=size
        thumb:SetHeight(size)
        local scroll=clamp(offset,0,maximum)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP",track,"TOP",0,-(self.travel*scroll/maximum))
    end
    function bar:ScrollTo(offset)
        local value=finiteNumber(offset,0)
        options.setOffset(clamp(value,0,self.maximum))
        self:Refresh()
    end
    local function fromCursor()
        if bar.maximum<=0 or not GetCursorPosition or not track.GetTop then return end
        local _,y=GetCursorPosition()
        local scale=track.GetEffectiveScale and track:GetEffectiveScale() or 1
        local top=track:GetTop()
        if not y or not top then return end
        if not scale or scale<=0 then scale=1 end
        local v=math.max(0,math.min(bar.travel,top-y/scale-bar.extent/2))
        bar:ScrollTo(bar.travel>0 and v/bar.travel*bar.maximum or 0)
    end
    track:SetScript("OnMouseDown",function(_,button)
        if not button or button=="LeftButton" then fromCursor() end
    end)
    thumb:SetScript("OnMouseDown",function(self,button)
        if button and button~="LeftButton" then return end
        self.__dragging=true
        fromCursor()
        self:SetScript("OnUpdate",function(widget)
            if widget.__dragging then fromCursor() end
        end)
    end)
    local function stop(widget)
        widget.__dragging=false
        widget:SetScript("OnUpdate",nil)
    end
    thumb:SetScript("OnMouseUp",stop)
    thumb:SetScript("OnHide",stop)
    bar:Refresh()
    return bar
end

function Layout:AttachNativeScrollbar(scroll,options)
    if not scroll then return nil end
    options=options or {}
    local area=self:AttachOffsetScrollbar(options.owner or scroll,{
        gutter=options.gutter,right=options.right,top=options.top,bottom=options.bottom,
        getState=function()
            local child=scroll.GetScrollChild and scroll:GetScrollChild()
            local total=child and child.GetHeight and child:GetHeight() or 0
            local visible=scroll.GetHeight and scroll:GetHeight() or 1
            return scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0,
                math.max(0,(tonumber(total) or 0)-math.max(1,tonumber(visible) or 1)),
                visible,total
        end,
        setOffset=function(offset)
            if scroll.SetVerticalScroll then scroll:SetVerticalScroll(offset) end
        end,
    })
    if area and scroll.HookScript then
        scroll:HookScript("OnVerticalScroll",function() area:Refresh() end)
        scroll:HookScript("OnSizeChanged",function() area:Refresh() end)
    end
    if area then
        -- A changing scroll child does not resize its owning ScrollFrame.
        -- Listen to the actual child so virtualised lists invalidate the track.
        local observedChild=nil
        function area:SyncContentHeight(newHeight)
            local child=scroll.GetScrollChild and scroll:GetScrollChild()
            if not child then return false end
            if newHeight and child.SetHeight then child:SetHeight(math.max(1,tonumber(newHeight) or 1)) end
            local visible=scroll.GetHeight and scroll:GetHeight() or 1
            local total=child.GetHeight and child:GetHeight() or visible
            local offset=scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
            local bounded=JLP.UILayout:BoundedScrollOffset(offset,visible,total)
            if scroll.SetVerticalScroll and bounded~=offset then scroll:SetVerticalScroll(bounded) end
            self:Refresh()
            return true
        end
        if scroll.GetScrollChild then
            observedChild=scroll:GetScrollChild()
            if observedChild and observedChild.HookScript then
                observedChild:HookScript("OnSizeChanged",function() area:SyncContentHeight() end)
            end
        end
        area.__observedChild=observedChild
    end
    return area
end

-- Shared vertical scrolling primitive used by every bounded content region.
-- The thumb follows conventional scrollbar semantics:
--   * scroll offset 0 => thumb at the top
--   * scrolling down => thumb moves down
--   * thumb length = viewport / total content
-- This avoids relying on the client-specific min/max direction of a Slider.
function Layout:ScrollArea(parent, options)
    options = options or {}
    local width = tonumber(options.width) or 300
    local height = tonumber(options.height) or 160
    local gutter = tonumber(options.scrollbarGutter) or 12
    local contentWidth = tonumber(options.contentWidth) or math.max(1, width - gutter)
    local wheelStep = tonumber(options.wheelStep) or 34
    local minThumbHeight = tonumber(options.minThumbHeight) or 28
    local trackInset = 2
    local trackHeight = math.max(1, height - (trackInset * 2))

    local root = CreateFrame("Frame", nil, parent)
    root:SetSize(width, height)
    root.__layoutWidth = width
    root.__layoutHeight = height
    root.__contentWidth = contentWidth
    root.__scrollbarGutter = gutter
    root.__scrollOffset = 0
    root.__contentHeight = height
    root.__maxScroll = 0
    root.__thumbHeight = trackHeight
    root.__thumbTravel = 0

    local viewport = CreateFrame("ScrollFrame", nil, root)
    viewport:SetPoint("TOPLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", -gutter, 0)

    local child = CreateFrame("Frame", nil, viewport)
    child:SetSize(contentWidth, height)
    if viewport.SetScrollChild then viewport:SetScrollChild(child) end
    root.viewport = viewport
    root.content = child
    -- The default reserved track gutter is configurable by the owning page.
    -- Do not make page modules mutate a shared ScrollFrame's anchors directly.
    function root:SetViewportGutter(reserved)
        local inset=tonumber(reserved) or gutter
        if inset~=inset then return false end
        inset=math.max(0,math.min(gutter,inset))
        self.__viewportGutter=inset
        viewport:ClearAllPoints()
        viewport:SetPoint("TOPLEFT",self,"TOPLEFT",0,0)
        viewport:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",-inset,0)
        return true
    end
    -- Child widgets with their own mouse hit rectangles can forward wheel
    -- events to the same scroll contract instead of trapping the gesture.
    child.__jlpScrollArea = root
    if child.EnableMouseWheel then child:EnableMouseWheel(true) end
    child:SetScript("OnMouseWheel",function(_,delta) root:ScrollWheel(delta) end)

    -- Custom track + thumb. A normal Frame is used instead of the native
    -- Slider thumb so the visual direction and proportional size are identical
    -- on every supported Forever client build.
    local track = CreateFrame("Frame", nil, root)
    track:SetPoint("TOPRIGHT", -1, -trackInset)
    track:SetSize(7, trackHeight)
    local trackTexture = track:CreateTexture(nil, "BACKGROUND")
    trackTexture:SetAllPoints()
    trackTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    trackTexture:SetVertexColor(0.03, 0.12, 0.18, 0.72)
    track.texture = trackTexture

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetSize(7, trackHeight)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbTexture:SetVertexColor(JLP.UITheme:Color("cyan"))
    thumb.texture = thumbTexture
    track.thumb = thumb
    root.scrollbar = track
    root.scrollThumb = thumb

    local function positionThumb()
        local maxScroll = root.__maxScroll or 0
        local travel = root.__thumbTravel or 0
        local ratio = maxScroll > 0 and clamp((root.__scrollOffset or 0) / maxScroll, 0, 1) or 0
        local topOffset = math.floor((travel * ratio) + 0.5)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -topOffset)
    end

    local function applyScroll(offset)
        offset = clamp(offset, 0, root.__maxScroll)
        root.__scrollOffset = offset
        if viewport.SetVerticalScroll then viewport:SetVerticalScroll(offset) end
        positionThumb()
    end

    function root:ScrollTo(offset)
        applyScroll(offset)
    end

    function root:ScrollBy(delta)
        self:ScrollTo((self.__scrollOffset or 0) + (tonumber(delta) or 0))
    end

    -- Alpha186: one scroll contract for nested Guide card viewports.
    -- A positive pixel delta travels down. The inner viewport consumes what
    -- fits; only the remaining pixels are offered to its owning outer page.
    -- This is transient UI state, not a SavedVariables preference.
    function root:SetWheelHandoff(callback)
        self.__wheelHandoff=type(callback)=="function" and callback or nil
    end
    function root:ScrollWheel(wheelDelta)
        local amount=-(tonumber(wheelDelta) or 0)*wheelStep
        if amount==0 then return 0 end
        local before=self.__scrollOffset or 0
        self:ScrollTo(before+amount)
        local consumed=(self.__scrollOffset or 0)-before
        local remainder=amount-consumed
        if math.abs(remainder)>0.001 and self.__wheelHandoff and not self.__wheelRouting then
            self.__wheelRouting=true
            local ok=pcall(self.__wheelHandoff,remainder,self)
            self.__wheelRouting=false
            if not ok then self.__wheelHandoffError=true end
        end
        return consumed
    end

    function root:SetContentHeight(contentHeight, preserveOffset)
        -- Every ScrollArea consumer (Gathering, Guide, Bank, AH, Secondaries)
        -- must fail closed on malformed dynamic measurements. NaN/Inf cannot
        -- become a scroll maximum or strand hidden controls outside viewport.
        local requested=tonumber(contentHeight)
        if not requested or requested~=requested or requested==math.huge or
            requested==-math.huge or requested<1 then requested=height end
        contentHeight=math.max(1,math.min(100000,requested))
        self.__contentHeight = contentHeight
        self.__maxScroll = math.max(0, contentHeight - height)
        child:SetHeight(math.max(height, contentHeight))
        child:SetWidth(contentWidth)

        local overflow = self.__maxScroll > 0
        track:SetShown(overflow)

        if overflow then
            -- Conventional proportional thumb: a nearly fitting document gets
            -- a long thumb, while a much taller document gets a short thumb.
            local visibleRatio = clamp(height / contentHeight, 0, 1)
            local thumbHeight = clamp(math.floor((trackHeight * visibleRatio) + 0.5), minThumbHeight, trackHeight)
            self.__thumbHeight = thumbHeight
            self.__thumbTravel = math.max(0, trackHeight - thumbHeight)
            thumb:SetHeight(thumbHeight)
        else
            self.__thumbHeight = trackHeight
            self.__thumbTravel = 0
            thumb:SetHeight(trackHeight)
        end

        local target = preserveOffset and self.__scrollOffset or 0
        applyScroll(target)
    end

    -- A ScrollArea is a viewport container, not a create-time fixed rectangle.
    -- Resize recomputes the proportional thumb and preserves a bounded offset.
    function root:Resize(newWidth,newHeight,newContentWidth)
        local w=finiteNumber(newWidth,width)
        local h=finiteNumber(newHeight,height)
        if w<1 or h<1 then return false end
        width=math.max(1,math.min(100000,w))
        height=math.max(1,math.min(100000,h))
        contentWidth=math.max(1,math.min(width,finiteNumber(newContentWidth,width-gutter)))
        trackHeight=math.max(1,height-trackInset*2)
        self.__layoutWidth=width;self.__layoutHeight=height
        self.__contentWidth=contentWidth
        self:SetSize(width,height)
        track:SetHeight(trackHeight)
        self:SetContentHeight(self.__contentHeight,true)
        return true
    end

    function root:HasOverflow()
        return (self.__maxScroll or 0) > 0
    end

    local function scrollFromCursor()
        if not root:HasOverflow() or not GetCursorPosition or not track.GetTop then return end
        local _, cursorY = GetCursorPosition()
        if not cursorY then return end
        local scale = root.GetEffectiveScale and root:GetEffectiveScale() or 1
        if not scale or scale == 0 then scale = 1 end
        local trackTop = track:GetTop()
        if not trackTop then return end
        local cursorYUi = cursorY / scale
        local travel = root.__thumbTravel or 0
        if travel <= 0 then root:ScrollTo(0); return end
        local thumbHeight = root.__thumbHeight or minThumbHeight
        local thumbTop = clamp(trackTop - cursorYUi - (thumbHeight / 2), 0, travel)
        root:ScrollTo((thumbTop / travel) * (root.__maxScroll or 0))
    end

    if thumb.EnableMouse then thumb:EnableMouse(true) end
    thumb:SetScript("OnMouseDown", function(self, button)
        if button and button ~= "LeftButton" then return end
        root.__draggingThumb = true
        scrollFromCursor()
        self:SetScript("OnUpdate", function()
            if root.__draggingThumb then scrollFromCursor() end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        root.__draggingThumb = false
        self:SetScript("OnUpdate", nil)
    end)
    thumb:SetScript("OnHide", function(self)
        root.__draggingThumb = false
        self:SetScript("OnUpdate", nil)
    end)

    if track.EnableMouse then track:EnableMouse(true) end
    track:SetScript("OnMouseDown", function(_, button)
        if button and button ~= "LeftButton" then return end
        scrollFromCursor()
    end)

    if root.EnableMouseWheel then root:EnableMouseWheel(true) end
    local function handleWheel(_,delta) root:ScrollWheel(delta) end
    root:SetScript("OnMouseWheel",handleWheel)
    -- The ScrollFrame itself can be the target on some WoW client builds.
    if viewport.EnableMouseWheel then viewport:EnableMouseWheel(true) end
    viewport:SetScript("OnMouseWheel",handleWheel)

    root:SetContentHeight(height)
    return root
end

-- Measured logical page coordinates. MainWindow normally scales its 1078x636
-- content surface; measuring avoids stale hardcoded metrics when parent changes.
function Layout:PageGeometry(parent, fallbackWidth, fallbackHeight)
    local width=parent and parent.GetWidth and tonumber(parent:GetWidth()) or nil
    local height=parent and parent.GetHeight and tonumber(parent:GetHeight()) or nil
    width=(width and width>0) and width or (tonumber(fallbackWidth) or 1078)
    height=(height and height>0) and height or (tonumber(fallbackHeight) or 636)
    local bp=width>=950 and "FULL" or width>=740 and "COMPACT" or "UNSUPPORTED_NARROW"
    return {width=width,height=height,breakpoint=bp,interactiveControlsFit=width>=740 and height>=500}
end
-- The Fishing canvas uses one shared normalized projection and native map
-- tiles. Reflowing its child offsets independently would desynchronise pins;
-- uniformly fit the existing designed surface, or present a truthful fallback.
-- This is a measured *fit*, not a claim of one-column responsive redesign.
function Layout:SecondaryViewportFit(width,height)
    local designW,designH=1078,636
    width=tonumber(width) or designW
    height=tonumber(height) or designH
    if width<=0 then width=designW end
    if height<=0 then height=designH end
    local scale=math.min(1,width/designW,height/designH)
    local supported=scale>=0.72
    return {
        contract="jlp-secondary-viewport-fit-v1",
        state=not supported and "UNSUPPORTED" or scale<0.999 and "COMPACT" or "FULL",
        viewportWidth=width,viewportHeight=height,
        designWidth=designW,designHeight=designH,
        scale=scale,scaledWidth=designW*scale,scaledHeight=designH*scale,
        interactiveControlsFit=supported,frameFitsScreen=supported,
        -- The child map/buttons stay in a single scaled coordinate space.
        projectionSafe=true,persisted=false,
    }
end

-- Alpha183: independent content reflow. The older viewport-fit contract is retained
-- for compatibility, but compact Secondaries no longer relies on scaling the
-- whole three-column page. Single-column views scroll vertically. The Fishing
-- map's tile art and overlays keep one common visual scale.
function Layout:SecondaryResponsivePlan(width,height,mode)
    width=tonumber(width) or 1078
    height=tonumber(height) or 636
    if width<=0 then width=1078 end
    if height<=0 then height=636 end
    local supported=width>=700 and height>=430
    local stacked=supported and width<1040
    local contentWidth=math.max(1,width-(stacked and 26 or 0))
    local mapScale=stacked and math.min(1,contentWidth/800) or 1
    local count=mode=="overview" and 3 or 2
    local contentHeight=stacked and (count*636*mapScale+((count-1)*14)) or 636
    -- Non-map cards are not scaled in the stacked presentation.
    if stacked and mode~="FISHING" then contentHeight=count*636+(count-1)*14 end
    return {contract="jlp-secondary-responsive-v1",
        state=not supported and "UNSUPPORTED" or stacked and "SINGLE_COLUMN" or "FULL",
        mode=mode or "overview",interactiveControlsFit=supported,
        stacked=stacked,contentWidth=contentWidth,contentHeight=contentHeight,
        viewportWidth=width,viewportHeight=height,
        mapScale=mapScale,projectionSafe=true,persisted=false}
end

-- Alpha184: Guide card geometry is a presentation-only read model.  Content
-- width is measured in the page viewport and inner card controls are retained.
-- No SavedVariables, route, recipe, or native-dispatch authority is changed.
function Layout:GuideResponsivePlan(width,height,mode)
    width=tonumber(width) or 1078
    height=tonumber(height) or 636
    if width<=0 then width=1078 end
    if height<=0 then height=636 end
    local supported=width>=740 and height>=430
    local compact=supported and width<1040
    local innerWidth=math.max(1,width-(compact and 22 or 0))
    local gap=14
    local cardWidth=compact and innerWidth or math.max(1,(innerWidth-gap)/2)
    local planHeight=compact and 490 or math.max(1,height-204)
    local materialsHeight=compact and 470 or math.max(1,height-204)
    local dualHeight=compact and 636 or height
    local totalHeight=compact and (mode=="dual" and dualHeight*2+gap or 190+gap+planHeight+gap+materialsHeight) or height
    return {
        contract="jlp-guide-responsive-v1",
        state=not supported and "UNSUPPORTED" or compact and "SINGLE_COLUMN" or "FULL",
        stacked=compact,interactiveControlsFit=supported,persisted=false,
        viewportWidth=width,viewportHeight=height,contentWidth=innerWidth,
        contentHeight=totalHeight,cardWidth=cardWidth,dualCardHeight=dualHeight,
        progressHeight=190,planHeight=planHeight,materialsHeight=materialsHeight,gap=gap,
    }
end

-- Alpha185: typed sizing estimate for material titles and dependency rows.
-- The WoW FontString measurement remains authoritative if available; these
-- estimates provide deterministic headless/mobile-font fallback without
-- chopping UTF-8 byte sequences or modifying persisted material names.
local function visualCharacters(value)
    local text=tostring(value or "")
    -- UTF-8 continuation bytes are not standalone characters.
    local _, continuation=text:gsub("[\128-\191]", "")
    return math.max(0,#text-continuation)
end
function Layout:GuideMaterialRowMetrics(width,name,dependency,detailed,measuredTitle,measuredDependency)
    width=math.max(230,tonumber(width) or 430)
    local titleBudget=math.max(14,math.floor((width-190)/7.4))
    local function textHeight(text,measured)
        local count=visualCharacters(text)
        local lines=math.max(1,math.ceil(count/titleBudget))
        -- Client measurement may be larger due to locale fonts and word wrapping.
        -- Limit extreme user-provided strings, but retain full text in the
        -- row's tooltip. Ordinary localized multiline names remain uncut.
        return math.max(18,tonumber(measured) or 0,math.min(lines,16)*18)
    end
    local titleHeight=textHeight(name,measuredTitle)
    local depHeight=dependency and textHeight(dependency,measuredDependency) or 18
    local base=detailed and 132 or (dependency and 108 or 76)
    local extra=math.max(0,titleHeight-18)+(dependency and math.max(0,depHeight-18) or 0)
    return {contract="jlp-guide-material-readability-v1",titleHeight=titleHeight,
        dependencyHeight=depHeight,height=base+extra,hasDependency=dependency~=nil,
        titleBudget=titleBudget,estimated=true,persisted=false}
end

-- Side-aware tooltip location.  Positions must be in the same logical units;
-- unknown frame coordinates fail back to the client's cursor anchor.
function Layout:TooltipAnchorFor(owner,viewport,estimatedWidth)
    local left=owner and owner.GetLeft and owner:GetLeft() or nil
    local right=owner and owner.GetRight and owner:GetRight() or nil
    local viewportLeft=viewport and viewport.GetLeft and viewport:GetLeft() or nil
    local viewportRight=viewport and viewport.GetRight and viewport:GetRight() or nil
    estimatedWidth=math.max(120,finiteNumber(estimatedWidth,300))
    if not (finiteNumber(left,nil) and finiteNumber(right,nil) and
        finiteNumber(viewportLeft,nil) and finiteNumber(viewportRight,nil)) then
        return "ANCHOR_CURSOR"
    end
    local availableRight=viewportRight-right
    local availableLeft=left-viewportLeft
    if availableRight>=estimatedWidth or availableRight>=availableLeft and availableRight>=120 then return "ANCHOR_RIGHT" end
    if availableLeft>=120 then return "ANCHOR_LEFT" end
    return "ANCHOR_CURSOR"
end

-- Deterministic, owner-relative layer bands. Do not place a frame on a
-- guessed global level (for example 200), as sibling add-ons may differ.
function Layout:OverlayFrameLevel(owner,role)
    local base=owner and owner.GetFrameLevel and tonumber(owner:GetFrameLevel()) or 0
    local offsets={content=1,control=5,popover=15,modal=30}
    return math.max(1,math.min(10000,base+(offsets[role] or 5)))
end
function Layout:EqualColumns(width,count,gap)
    count=math.max(1,math.floor(tonumber(count) or 1))
    gap=math.max(0,tonumber(gap) or 0)
    return math.max(1,(math.max(1,tonumber(width) or 1)-gap*(count-1))/count)
end

function Layout:CardScrollArea(card, options)
    options = options or {}
    local cardWidth = tonumber(options.cardWidth) or (card and card.GetWidth and card:GetWidth()) or 300
    local cardHeight = tonumber(options.cardHeight) or (card and card.GetHeight and card:GetHeight()) or 200
    local left = tonumber(options.left) or 22
    local right = tonumber(options.right) or 12
    local top = tonumber(options.top) or 58
    local bottom = tonumber(options.bottom) or 12
    local gutter = tonumber(options.scrollbarGutter) or 12
    local width = math.max(1, cardWidth - left - right)
    local height = math.max(1, cardHeight - top - bottom)
    local area = self:ScrollArea(card, {
        width = width,
        height = height,
        contentWidth = math.max(1, width - gutter),
        scrollbarGutter = gutter,
        wheelStep = options.wheelStep,
        minThumbHeight = options.minThumbHeight,
    })
    area:SetPoint("TOPLEFT", left, -top)
    area.__cardContentTop = top
    area.__cardContentBottom = bottom
    area.__cardContentLeft = left
    area.__cardContentRight = right
    -- Call whenever the owning card is reflowed. Anchoring and scroll metrics
    -- are one transaction, rather than the original create-time snapshot.
    function area:ApplyCardBounds(w,h)
        w=tonumber(w) or (card and card.GetWidth and card:GetWidth()) or cardWidth
        h=tonumber(h) or (card and card.GetHeight and card:GetHeight()) or cardHeight
        if w<=0 or h<=0 then return false end
        return self:Resize(math.max(1,w-left-right),math.max(1,h-top-bottom))
    end
    -- Cards with an actual fixed footer require a larger bottom exclusion
    -- zone. Ordinary crafting cards must not inherit that unused space.
    -- Keep the ScrollFrame anchor and content height in the same transaction.
    function area:SetCardBottomInset(inset)
        inset=tonumber(inset)
        if not inset or inset~=inset or inset<0 or inset>256 then return false end
        if math.abs(bottom-inset)<0.001 then return true end
        bottom=inset
        self.__cardContentBottom=inset
        return self:ApplyCardBounds()
    end
    return area
end

JLP.UILayout = Layout
