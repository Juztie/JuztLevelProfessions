local _, JLP = ...
-- Alpha174: pure, read-only logical UI viewport geometry. Never SavedVariables
-- policy, source-map coordinates, route projections or native game actions.
local Layout={contract="jlp-gathering-viewport-layout-v1",nativeDispatchAllowed=false,
    margin=16,minWidth=640,minHeight=390,maxWidth=1300,maxHeight=1000,
    maxResourceRows=22}
local function finite(value,fallback)
    return type(value)=="number" and value==value and value>0 and value<100000 and value or fallback
end
local function clamp(value,a,b)
    return math.max(a,math.min(b,value))
end
function Layout:Fit(screenW,screenH,preferences)
    -- Frame and UIParent both use UI units. Callers must NEVER mix raw pixel
    -- GetCursorPosition values or framebuffer resolutions with these values.
    screenW=finite(screenW,1600);screenH=finite(screenH,900)
    preferences=type(preferences)=="table" and preferences or {}
    local availableW=math.max(1,screenW-self.margin*2)
    local availableH=math.max(1,screenH-self.margin*2)
    local requestedW=clamp(finite(preferences.width,760),self.minWidth,self.maxWidth)
    local requestedH=clamp(finite(preferences.height,550),self.minHeight,self.maxHeight)
    local width=math.min(requestedW,availableW)
    local height=math.min(requestedH,availableH)
    local halfX=math.max(0,(screenW-width)/2-self.margin)
    local halfY=math.max(0,(screenH-height)/2-self.margin)
    local x=clamp(tonumber(preferences.x) or 0,-halfX,halfX)
    local y=clamp(tonumber(preferences.y) or 0,-halfY,halfY)
    local sidebarHeight=height-197  -- top 125 + bottom 72
    local breakpoint=width>=860 and height>=560 and "FULL" or
        width>=690 and height>=460 and "COMPACT" or "MINIMAL"
    local frameFits=width>=self.minWidth and height>=self.minHeight
    local interactive=frameFits and sidebarHeight>=190
    return {width=width,height=height,x=x,y=y,
        screenWidth=screenW,screenHeight=screenH,
        breakpoint=breakpoint,sidebarHeight=sidebarHeight,
        frameFitsScreen=frameFits,interactiveControlsFit=interactive,
        minimumControlsFit=interactive,
        wasConstrained=width<requestedW or height<requestedH or
            x~=(tonumber(preferences.x) or 0) or y~=(tonumber(preferences.y) or 0),
        persisted=false}
end
-- Reflow does not re-fit or persist the user's window position. It derives
-- the exact same breakpoint from live frame dimensions after manual resize.
function Layout:ForFrameSize(width,height)
    width=finite(width,self.minWidth);height=finite(height,self.minHeight)
    local sidebarHeight=math.max(0,height-197)
    local breakpoint=width>=860 and height>=560 and "FULL" or
        width>=690 and height>=460 and "COMPACT" or "MINIMAL"
    return {width=width,height=height,sidebarHeight=sidebarHeight,
        breakpoint=breakpoint,frameFitsScreen=true,interactiveControlsFit=sidebarHeight>=190,
        persisted=false,source="LIVE_FRAME_SIZE"}
end
-- Sidebar is anchored 125 UI units below the parent top and 72 above its
-- bottom. Parent geometry wins over contradictory positive shim GetHeight;
-- never allow a stale measured sidebar to expose rows over its footer.
function Layout:ResourceListBudget(parentHeight,sidebarMeasured,minimal,rowsStartTop)
    local h=finite(parentHeight,nil)
    local computed=h and (h-197) or nil
    local measured=finite(sidebarMeasured,nil)
    local sidebarHeight=computed and math.max(0,computed) or measured or 0
    local firstTop=math.max(minimal and 91 or 111,tonumber(rowsStartTop) or 0)
    -- Footer has three non-overlapping rows in every breakpoint: pager at
    -- bottom+80, selection at +44 and Options at +8.
    local footerTop=sidebarHeight-106
    -- Do not stop after eight choices when the rail has physical room for
    -- more. The pager is a fixed bottom region; leave a small clearance above
    -- it, with resource button height/stride preserved (26 / 29 UI units).
    local count=math.max(0,math.min(self.maxResourceRows or 22,
        math.floor((footerTop-firstTop-32)/29)+1))
    return {sidebarHeight=sidebarHeight,visibleRows=count,firstRowTop=firstTop,
        footerTop=footerTop,reason=count>0 and nil or "RESOURCE_VIEWPORT_TOO_SHORT",
        source=computed and "PARENT_ANCHORS" or measured and "MEASURED" or "UNAVAILABLE"}
end
-- A docked editor has an independent scroll CHILD, not the rail's measured
-- height. Every row between its top anchor and pager is reachable through
-- existing dock scroll controls even when no row fits the physical rail at
-- once. The legacy sidebar ResourceListBudget remains unchanged.
function Layout:DockResourceListBudget(parentHeight,scrollHeight,sectionHeight,rowsTop,pagerTop)
    local tokens=JLP.UITheme and JLP.UITheme.gathering or {}
    local section=finite(sectionHeight,tokens.dockResourcesExpandedHeight or 460)
    local top=finite(rowsTop,tokens.dockResourceRowsTop or 126)
    local pager=finite(pagerTop,tokens.dockResourcePagerTop or 376)
    local stride=finite(tokens.resourceRowHeight,29)
    local rowHeight=math.min(stride,32)
    local rows=math.max(0,math.min(8,math.floor((math.min(pager,section)-top-rowHeight)/stride)+1))
    local viewport=finite(scrollHeight,nil)
    local parent=finite(parentHeight,nil)
    if not viewport and parent then viewport=math.max(1,parent-197-95) end
    viewport=viewport or 1
    local scrollContent=math.max(section,top+rows*stride,pager+48)
    return {visibleRows=rows,firstRowTop=top,footerTop=pager,
        sidebarHeight=section,scrollViewport=viewport,scrollContent=scrollContent,
        scrollingRequired=scrollContent>viewport,source="DOCK_SCROLL_CHILD",
        reason=rows>0 and nil or "RESOURCE_DOCK_TOO_SHORT",nativeDispatchAllowed=false}
end
-- Logical parent-bound text geometry; the 119-unit Why button at the
-- bottom-right owns its hitbox. Bottom status and detail never enter it.
-- Layout units, not framebuffer/browser pixels; no persist or native actions.
function Layout:RouteFeedbackBudget(width,height,options)
    width=finite(width,760);height=finite(height,550)
    options=type(options)=="table" and options or {}
    local tokens=JLP.UITheme and JLP.UITheme.gathering or {}
    local left=options.left or tokens.statusLeft or 22
    local right=options.right or tokens.statusRight or 22
    local reserved=options.buttonWidth or tokens.feedbackButton or 119
    local gap=options.gap or tokens.feedbackGap or 12
    local maxWidth=math.max(1,width-left-right)
    local detailWidth=math.max(1,maxWidth-reserved-gap)
    return {statusWidth=maxWidth,detailWidth=detailWidth,
        fits=height>=self.minHeight and width>=self.minWidth,
        state=height<self.minHeight and "VIEWPORT_TOO_SHORT" or "READY",
        left=left,buttonReserved=reserved+gap,persisted=false}
end
-- A shared logical parent-bound contract for popup/options geometry. Embedded
-- and standalone entrypoints consume the SAME measurement; no browser fonts,
-- pixel assumptions, or SavedVariables. At small heights, panels shrink to
-- the available vertical budget rather than crossing the map footer.
function Layout:OverlayBudget(parentWidth,parentHeight,kind)
    local width=finite(parentWidth,760)
    local height=finite(parentHeight,550)
    local embedded=kind=="EMBEDDED_PICKER"
    local tokens=JLP.UITheme and JLP.UITheme.gathering or {}
    local inset=embedded and (tokens.pickerInset or 14) or (tokens.overlayInset or 22)
    local top=embedded and (tokens.pickerTop or 179) or (tokens.overlayTop or 80)
    local preferredWidth=embedded and (tokens.pickerPreferredWidth or 365) or kind=="DETAIL" and 420 or 292
    local preferredHeight=embedded and (tokens.pickerPreferredHeight or 350) or kind=="DETAIL" and 292 or 314
    local availableWidth=math.max(1,width-2*inset)
    local availableHeight=math.max(1,height-(embedded and top+(tokens.pickerFooterAllowance or 12) or 100))
    local panelWidth=math.min(preferredWidth,availableWidth)
    local panelHeight=math.min(preferredHeight,availableHeight)
    local left=embedded and math.max(inset,math.min(tokens.pickerPreferredLeft or 358,width-panelWidth-inset)) or inset
    -- The same row/pager dimensions are used by Secondaries when placing actual controls.
    local pickerRows=nil
    if embedded then
        local lastRowBottom=panelHeight-(tokens.pickerPagerBottom or 14)-
            (tokens.pickerPagerHeight or 24)-(tokens.pickerPagerGap or 8)
        pickerRows=math.max(0,math.min(tokens.pickerMaxRows or 6,
            math.floor((lastRowBottom-(tokens.pickerRowTop or 128)-
                (tokens.pickerRowHeight or 25))/(tokens.pickerRowStride or 27))+1))
    end
    local contentFits=not embedded or
        (panelWidth>=(tokens.pickerMinContentWidth or 340) and pickerRows>=1)
    local contentReason=embedded and not contentFits and
        (panelWidth<(tokens.pickerMinContentWidth or 340) and "PICKER_VIEWPORT_TOO_NARROW" or
            "VIEWPORT_TOO_SHORT") or nil
    return {left=left,top=top,width=panelWidth,height=panelHeight,
        pickerRows=pickerRows,contentFits=contentFits,contentReason=contentReason,
        fitsControls=panelWidth>=(embedded and (tokens.pickerMinContentWidth or 340) or 232) and
            panelHeight>=(embedded and 330 or 250),
        state=availableHeight<preferredHeight and "COMPACT" or "STANDARD",
        parentWidth=width,parentHeight=height,nativeDispatchAllowed=false,persisted=false}
end
function Layout:ResourcePageState(listing,capacity,layer)
    local count=type(listing)=="table" and tonumber(listing.matchingCount) or 0
    local slots=math.max(0,math.floor(tonumber(capacity) or 0))
    local available=type(listing)=="table" and type(listing.rows)=="table"
    local code=not available and "BROWSER_FAILURE" or slots==0 and "VIEWPORT_TOO_SHORT" or
        (type(layer)=="table" and not layer.learned) and "NOT_LEARNED" or
        count==0 and "EMPTY_MATCH" or #listing.rows==0 and "ROWS_PENDING" or "READY"
    local texts={BROWSER_FAILURE="Resource browser unavailable; retry map selection.",
        VIEWPORT_TOO_SHORT="Not enough height for resource rows; enlarge the map.",
        NOT_LEARNED="Learn Herbalism or Mining to select these resources.",
        EMPTY_MATCH="No matching resources; clear search or switch resource layer.",
        ROWS_PENDING="Resource rows unavailable; retry map or filter selection."}
    return {contract="jlp-resource-page-state-v1",status=code,text=texts[code],
        page=(code=="READY") and (math.floor((tonumber(listing.offset) or 0)/slots)+1) or 0,
        pageCount=(code=="READY") and math.ceil(count/slots) or 0,
        visibleRows=(code=="READY") and math.min(slots,#listing.rows) or 0,
        canPrevious=code=="READY" and listing.canPrevious==true,
        canNext=code=="READY" and listing.canNext==true,
        canSelect=code=="READY" and type(layer)=="table" and layer.learned==true,
        nativeDispatchAllowed=false}
end
function Layout:Signature(screenW,screenH,effectiveScale)
    return tostring(finite(screenW,1600))..":"..tostring(finite(screenH,900))..
        ":"..tostring(finite(effectiveScale,1))
end
JLP:RegisterModule("GatheringViewportLayout",Layout)
