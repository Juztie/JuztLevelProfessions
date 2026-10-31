-- JuztTom alpha6: information architecture overhaul; the navigation engine is unchanged.
-- Six semantic pages, JuztLevel source texture family, bounded content, no silent invented distances.
local _, JLP = ...
local JT = JLP._integratedTom
local min,max,floor = math.min,math.max,math.floor
local C=JT.colors
-- Local accessibility rule: the small WoW font templates were unreadable in
-- Diagnostics and across the six-tab JuztTom menu. Never modify Blizzard's
-- shared font objects; resize only FontStrings owned by this integrated UI.
-- The in-world arrow remains controlled by its separate Text Size slider.
local READABLE_SMALL_FONT=14
local function readableSmallFont(fontString,template)
    if fontString and (template=="GameFontHighlightSmall" or template=="GameFontNormalSmall") and
       type(fontString.GetFont)=="function" and type(fontString.SetFont)=="function" then
        local face,current,flags=fontString:GetFont()
        if face and (not current or current<READABLE_SMALL_FONT) then
            fontString:SetFont(face,READABLE_SMALL_FONT,flags or "")
        end
    end
    return fontString
end
local function label(parent,text,template,x,y,w,h,color)
    template=template or "GameFontHighlightSmall"
    local fs=readableSmallFont(parent:CreateFontString(nil,"OVERLAY",template),template)
    fs:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    if w then fs:SetSize(w,h or 22) end
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(C[color or "silver"]))
    fs:SetText(text or "")
    return fs
end
local function line(parent,y)
    local t=parent:CreateTexture(nil,"ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(.31,.48,.61,.50)
    t:SetPoint("TOPLEFT",parent,"TOPLEFT",20,y)
    t:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-20,y)
    t:SetHeight(1)
    return t
end
local function section(parent,heading,y)
    label(parent,heading,"GameFontNormal",22,y,526,23)
    line(parent,y-30)
end
local function panel(parent,x,y,w,h,variant)
    local f=CreateFrame("Frame",nil,parent)
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    f:SetSize(w,h)
    JT:SkinThemePanel(f,variant or "secondary")
    return f
end
local function captionButton(parent,caption,x,y,w,h,onClick)
    local b=JT:CreateThemeButton(parent,caption,w,h,onClick)
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    b._jtEnabled=true
    b._jtAction=onClick
    b:SetScript("OnClick",function()
        if b._jtEnabled and b._jtAction then b._jtAction() end
    end)
    return b
end
local function enabled(b,value)
    if not b then return end
    b._jtEnabled=value and true or false
    b:SetAlpha(b._jtEnabled and 1 or .38)
    if b.EnableMouse then b:EnableMouse(b._jtEnabled) end
end
local function selected(b,isSelected)
    if not b then return end
    if not b._jtSelection then
        local t=b:CreateTexture(nil,"BORDER")
        t:SetPoint("TOPLEFT",b,"TOPLEFT",4,-4)
        t:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-4,4)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(.04,.42,.72,.46)
        b._jtSelection=t
    end
    b._jtSelection:SetShown(isSelected and true or false)
    b.caption:SetTextColor(isSelected and 1 or .91,isSelected and .72 or .95,isSelected and .17 or .98,1)
end
local function boxCheck(parent,textValue,x,y,w,onClick)
    local b=CreateFrame("Button",nil,parent)
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    b:SetSize(w,30)
    local plate=b:CreateTexture(nil,"BACKGROUND")
    plate:SetAllPoints(b);plate:SetColorTexture(.015,.06,.10,.76)
    local check=b:CreateTexture(nil,"ARTWORK")
    check:SetPoint("LEFT",b,"LEFT",7,0);check:SetSize(17,17)
    check:SetTexture("Interface\\Buttons\\WHITE8X8")
    check:SetVertexColor(.07,.42,.65,1)
    local mark=readableSmallFont(b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"),"GameFontHighlightSmall")
    mark:SetPoint("CENTER",check,"CENTER",0,0)
    mark:SetText("X")
    local text=readableSmallFont(b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"),"GameFontHighlightSmall")
    text:SetPoint("LEFT",check,"RIGHT",12,0)
    text:SetPoint("RIGHT",b,"RIGHT",-5,0)
    text:SetJustifyH("LEFT");text:SetText(textValue)
    b.checkMark=mark;b.caption=text
    b:SetScript("OnClick",function()if onClick then onClick() end end)
    function b:SetCheckedVisual(isChecked)
        mark:SetShown(isChecked and true or false)
        check:SetVertexColor(isChecked and .06 or .15,isChecked and .55 or .23,isChecked and .85 or .30,1)
    end
    return b
end
local function slider(parent,name,y,lo,hi,step,get,set)
    label(parent,name,"GameFontHighlight",23,y,127,20)
    local bar=CreateFrame("Slider",nil,parent)
    bar:SetPoint("TOPLEFT",parent,"TOPLEFT",168,y-1)
    bar:SetSize(257,19)
    local track=bar:CreateTexture(nil,"BACKGROUND")
    track:SetPoint("LEFT",bar,"LEFT",0,0);track:SetPoint("RIGHT",bar,"RIGHT",0,0)
    track:SetHeight(7);track:SetColorTexture(.055,.19,.30,1)
    local v=label(parent,"","GameFontHighlight",445,y-1,114,24)
    v:SetJustifyH("RIGHT")
    local range=label(parent,tostring(lo).." - "..tostring(hi),"GameFontHighlightSmall",168,y-23,260,18,"muted")
    bar:SetMinMaxValues(lo,hi);bar:SetValueStep(step)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    if bar.SetOrientation then bar:SetOrientation("HORIZONTAL") end
    if bar.SetThumbTexture then
        bar:SetThumbTexture(JT:ThemeAssetPath("controls\\slider_thumb.tga"))
        if bar.GetThumbTexture then
            local thumb=bar:GetThumbTexture()
            if thumb and thumb.SetSize then thumb:SetSize(20,25) end
        end
    end
    bar:SetScript("OnValueChanged",function(_,value)
        if JT._sliderSync or not JT.profile then return end
        local snapped=lo+floor((min(hi,max(lo,tonumber(value) or lo))-lo)/step+.5)*step
        if get()~=snapped then set(snapped);JT:Refresh(true) end
    end)
    return {slider=bar,value=v,get=get,range=range}
end
local function pageTitle(page,name,desc)
    label(page,name,"GameFontNormalLarge",22,-18,540,29)
    label(page,desc,"GameFontHighlightSmall",22,-53,543,28,"muted")
    line(page,-80)
end
local function stateText(status,mode,hasTarget)
    if status=="JLP_PAUSED" then
        return "Navigation paused","Your destination is saved. Choose Resume navigation to continue."
    end
    if hasTarget then
        if status=="AT_WAYPOINT" then return "Waypoint reached","Arrival registered at the active destination."
        elseif status=="CITY_INGRESS_REFERENCE_ONLY" then return "Enter destination city","Follow the entrance marker and enter the city. Navigation continues after the game detects the zone change."
        elseif status=="TRAVEL_TO_DESTINATION_MAP" then return "Position or map mismatch","Your current location cannot be projected onto this destination. Check the selected Map ID and zone."
        elseif status=="MAP_RELATIVE_DIRECTION" then return "Map direction available","Arrow follows same-map coordinates. Distance in yards and arrival are not verified."
        else return "Navigation active","The arrow follows one destination at a time." end
    end
    if status=="ROUTE_COMPLETE" then return "Route complete","Choose another route or generate a new one."
    elseif mode=="CURRENT_STEP" then
        if type(status)=="string" and status:find("NO_AUDITED_COORDINATE",1,true) then
            return "Current step has no verified location","The plan is available, but its destination lacks approved coordinates."
        end
        return "No navigable current step","Select up to two learned professions. Navigation uses known destination coordinates."
    end
    if status=="ROUTE_CONTEXT_CHANGED" or status=="UNQUALIFIED_GENERATION" or status=="MISSING_CONTEXT_TOKEN" then
        return "Route needs regeneration","The previous route is no longer valid for the current JuztLevel context."
    end
    if JT:GetBridgeState()=="not installed" then
        return "JuztLevel not detected","Install JuztLevel for generated gathering routes, or set a manual waypoint."
    end
    return "No active gathering route","Generate a route in the JuztLevel Gathering Map, then return here."
end
local function readableDiagnosticStatus(value)
    local text=tostring(value or "")
    -- Do not change internal identifiers: these are display labels only.
    if text=="CITY_INGRESS_REFERENCE_ONLY" then return "ENTERING_DESTINATION_CITY" end
    return text:gsub("REFERENCE","WAYPOINT"):gsub("APPROXIMATE","MAP_DIRECTION")
end
local function destinationName(point)
    if not point then return "No waypoint selected" end
    local s=tostring(point.title or "Waypoint")
    return #s>58 and s:sub(1,55).."..." or s
end
local function mapText(point)
    if not point then return "No destination map" end
    local z=point.zone and (tostring(point.zone).."  /  ") or ""
    return string.format("%sMap %d   %.2f, %.2f",z,point.mapID,point.x*100,point.y*100)
end
local function routeData()
    if JT.userRoute and type(JT.userRoute.points)=="table" and #JT.userRoute.points>0 then
        local r=JT.userRoute
        return {title="My manual route",mapID=r.points[r.index] and r.points[r.index].mapID,
            points=r.points,index=r.index,kind="USER",closed=false}
    end
    -- This tab is the USER'S manual-route workspace only. A generated
    -- Gathering Map route is owned and displayed by JuztLevel Gathering Map;
    -- it must never be copied into or represented as a manual route here.
    if JT.external and JT.external.id=="juzttom-demo" then
        local r=JT.external
        return {title="Demo route",mapID=r.mapID,points=r.points,index=r.index,kind="EXTERNAL",closed=r.closed}
    end
    return nil
end
function JT:SelectRouteStop(index)
    local r=routeData()
    if not r or not r.points[index] then return false end
    if r.kind=="USER" then return self:SelectUserRouteStop(index) end
    if self.external then self.external.index=index;self.lastExternalArrival=nil
    elseif self.gatheringState and self.gatheringState.activeKey then
        local active=self.gatheringState.routes[self.gatheringState.activeKey]
        if not active then return false end
        active.index=index;active.done=false;self.lastArrived=nil
    else return false end
    self:Refresh(true)
    return true
end
function JT:SetManualWaypointPercent(mapInput,xInput,yInput)
    local map=tonumber(mapInput);local x=tonumber(xInput);local y=tonumber(yInput)
    if not map or not x or not y or map~=floor(map) or x<0 or x>100 or y<0 or y>100 then
        return false,"Enter an integer Map ID and X/Y values between 0 and 100."
    end
    local ok,why=self:SetWaypoint(map,x/100,y/100,"Manual waypoint")
    return ok,ok and "Manual waypoint activated." or tostring(why)
end
-- User-built manual routes are distinct from the single Set waypoint action.
-- Each selected stop is explicitly admitted by the common destination owner.
function JT:SelectUserRouteStop(index)
    local r=self.userRoute
    index=tonumber(index)
    if not r or not index or index~=math.floor(index) or not r.points[index] then
        return false,"MANUAL_ROUTE_STOP_MISSING"
    end
    local p=r.points[index]
    local ok,why=self:SetWaypoint(p.mapID,p.x,p.y,"Manual stop "..index)
    if ok then
        r.index=index
        if self.profile then self.profile.manualRoute=r end
        self:Refresh(true)
    end
    return ok,why
end
function JT:AddManualRouteStop(mapInput,xInput,yInput)
    local map,x,y=tonumber(mapInput),tonumber(xInput),tonumber(yInput)
    if not map or not x or not y or map~=math.floor(map) or
        not self:ValidPoint(map,x/100,y/100) or x<0 or x>100 or y<0 or y>100 then
        return false,"Enter a valid Map ID and X/Y values from 0 to 100."
    end
    local r=self.userRoute
    if r and #r.points>=100 then return false,"Maximum 100 manual stops." end
    local index=r and (#r.points+1) or 1
    local p=self:CleanPoint(map,x/100,y/100,"Manual stop "..index,"MANUAL")
    -- Admit the FIRST route stop before persisting a new route.
    if not r then
        local ok,why=self:SetWaypoint(p.mapID,p.x,p.y,p.title)
        if not ok then return false,why end
        r={points={},index=1}
        self.userRoute=r
    end
    r.points[#r.points+1]=p
    if self.profile then self.profile.manualRoute=r end
    self:Refresh(true)
    return true,"Waypoint added to route ("..#r.points.."/100)."
end
function JT:ClearUserRoute()
    self.userRoute=nil
    if self.profile then self.profile.manualRoute=nil end
    self:ClearWaypoint() -- clears the shared owner only for manual navigation
    self:Refresh(true)
end
-- Auto-select the actual player UI map when entering Routes. Explicitly
-- typed Map IDs are never overwritten on refresh or after a zone change.
function JT:SyncManualMapField()
    local field=self.manualMap
    if not field or not field.GetText or not field.SetText or not C_Map or
       type(C_Map.GetBestMapForUnit)~="function" then return false end
    local ok,map=pcall(C_Map.GetBestMapForUnit,"player")
    if not ok or type(map)~="number" or map<1 or map~=math.floor(map) then return false end
    local current=tostring(field:GetText() or "")
    if self.manualMapUserEdited and current~="" then return false end
    if current=="" or current==tostring(self.manualMapAutoValue or "") then
        local value=tostring(map)
        if current~=value then field:SetText(value) end
        self.manualMapAutoValue=value
        self.manualMapUserEdited=false
        return true
    end
    return false
end
function JT:ShowDesignPage(key)
    local aliases={Mode="Navigation",Route="Routes",Behaviour="Settings",Advanced="Settings"}
    if key=="Advanced" then self.settingsSection="Advanced" end
    if key=="Behaviour" then self.settingsSection="Behaviour" end
    key=aliases[key] or key
    if not self.designPages or not self.designPages[key] then return false end
    self.designPage=key
    if key=="Routes" then self:SyncManualMapField() end
    for id,page in pairs(self.designPages) do page:SetShown(id==key) end
    for id,b in pairs(self.designTabs) do if b.SetThemeActiveState then b:SetThemeActiveState(id==key) end end
    if key=="Settings" and not self.settingsSection then self.settingsSection="Behaviour" end
    self:RefreshDesignUI()
    return true
end
function JT:CreateDesignUI()
    if self.designPanel then return end
    local frame=CreateFrame("Frame","JuztLevelIntegratedTomDesignPanel",UIParent)
    local L={width=875,height=746,header=92,sidebar=244,inset=16,pageWidth=594,pageHeight=596}
    frame:SetSize(L.width,L.height)
    frame:SetFrameStrata("DIALOG");frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    frame:SetClampedToScreen(true);frame:EnableMouse(true);frame:SetMovable(true)
    local function fit()
        local w=UIParent and UIParent.GetWidth and UIParent:GetWidth()
        local h=UIParent and UIParent.GetHeight and UIParent:GetHeight()
        if type(w)=="number" and w>0 and type(h)=="number" and h>0 then
            frame:SetScale(max(.50,min(1,(w-32)/L.width,(h-32)/L.height)))
        end
    end
    fit();frame:SetScript("OnShow",fit)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(f)f:StartMoving()end)
    frame:SetScript("OnDragStop",function(f)f:StopMovingOrSizing()end)
    self.designShellBackground=self:SkinThemeImage(frame,"layout\\main_background.tga")
    local top=CreateFrame("Frame",nil,frame)
    top:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0);top:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0)
    top:SetHeight(L.header)
    self.designHeaderBackground=self:SkinThemeImage(top,"layout\\header_background.tga")
    local logo=top:CreateTexture(nil,"ARTWORK");logo:SetPoint("LEFT",top,"LEFT",24,0)
    logo:SetSize(48,48);logo:SetTexture(self.asset.."juzttom_icon.tga")
    self.designHeaderIcon=logo
    self.designHeaderTitle=label(top,"Juzt","GameFontNormalHuge",86,-15,104,35)
    self.designHeaderSuffix=label(top,"Tom","GameFontNormalHuge",175,-15,110,35,"gold")
    self.designHeaderSubtitle=label(top,"Profession & gathering navigation","GameFontHighlightSmall",88,-51,490,23,"muted")
    self.designVersion=label(top,"v"..self.version,"GameFontHighlightSmall",596,-36,214,22,"muted")
    self.designVersion:SetJustifyH("RIGHT")
    local close=CreateFrame("Button",nil,top)
    close:SetSize(36,36);close:SetPoint("RIGHT",top,"RIGHT",-21,0)
    self:SkinThemeCloseButton(close);close:SetScript("OnClick",function()frame:Hide()end)
    self.designCloseButton=close
    local sidebar=CreateFrame("Frame",nil,frame)
    sidebar:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-L.header)
    sidebar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0);sidebar:SetWidth(L.sidebar)
    self.designSidebarBackground=self:SkinThemeImage(sidebar,"layout\\sidebar_background.tga")
    self.designSidebar=sidebar;self.designTabs={};self.designPages={}
    local tabs={
        {"Navigation","juzttom_icon.tga",true},{"Professions","icons\\professions.tga"},
        {"Routes","icons\\routes.tga"},{"Display","icons\\display.tga"},
        {"Settings","icons\\settings.tga"},{"About","icons\\about.tga"},
    }
    for i,def in ipairs(tabs) do
        local name=def[1]
        local b=CreateFrame("Button",nil,sidebar)
        b:SetSize(218,62);b:SetPoint("TOPLEFT",sidebar,"TOPLEFT",12,-30-(i-1)*84)
        self:SkinNavigationTab(b,def[2])
        if def[3] then b.icon:SetTexture(self.asset..def[2]) end
        b.caption:SetText(name)
        b:SetScript("OnClick",function()self:ShowDesignPage(name)end)
        self.designTabs[name]=b
        local pg=CreateFrame("Frame",nil,frame)
        pg:SetPoint("TOPLEFT",frame,"TOPLEFT",L.sidebar+L.inset,-L.header-L.inset)
        pg:SetSize(L.pageWidth,L.pageHeight)
        self:SkinThemePanel(pg,"primary");pg:Hide();self.designPages[name]=pg
    end
    -- NAVIGATION (mode + dashboard, no test controls)
    local nav=self.designPages.Navigation
    pageTitle(nav,"Navigation","One active destination, whether you are gathering or following a profession step.")
    section(nav,"Navigation Mode",-96)
    self.modeButtons={}
    self.modeButtons.GATHERING=captionButton(nav,"Gathering",20,-138,265,38,function()
        local ok,why=self:ActivateGatheringNavigation()
        if not ok then self:Print("Gathering: "..tostring(why or "NO_ACTIVE_ROUTE")) end
        self:RefreshDesignUI()
    end)
    self.modeButtons.CURRENT_STEP=captionButton(nav,"Current Step",309,-138,265,38,function()
        -- Only the admitted owner may commit Current Step mode (05C).
        -- A refused action must not hide an existing Gathering/Manual arrow.
        local slots=self:GetCurrentTargets(true)
        local focus=self.focusPrimary
        local chosen
        for _,s in ipairs(slots) do if s.key==focus then chosen=s;break end end
        chosen=chosen or slots[1]
        local ok,why=self:ActivateCurrentStepTarget(chosen and chosen.key)
        if not ok then self:Print("Current Step: "..tostring(why));self:RefreshDesignUI() end
    end)
    self.designModeHint=label(nav,"","GameFontHighlightSmall",23,-186,545,34,"muted")
    local info=panel(nav,19,-236,556,232)
    label(info,"ACTIVE DESTINATION","GameFontNormal",18,-15,430,24,"gold")
    line(info,-46)
    self.designNavStatus=label(info,"","GameFontHighlight",18,-60,517,24)
    self.designNavDetail=label(info,"","GameFontHighlightSmall",18,-87,517,34,"muted")
    self.designNavTarget=label(info,"","GameFontHighlight",18,-129,513,25)
    self.designNavMap=label(info,"","GameFontHighlightSmall",18,-164,520,24,"muted")
    self.designNavDistance=label(info,"","GameFontNormal",18,-191,515,26,"gold")
    self.navNext=captionButton(nav,"Next waypoint",20,-486,266,38,function()
        local r=routeData()
        if r and r.kind=="USER" then self:SelectUserRouteStop(math.min(#r.points,(r.index or 1)+1))
        elseif self.mode=="GATHERING" then self:AdvanceSelectedGathering()
        else self:Advance() end
    end)
    self.navArrow=captionButton(nav,"Hide navigation arrow",309,-486,265,38,function()
        self.profile.arrowShown=not self.profile.arrowShown;self:Refresh(true)
    end)
    -- Explicit owner controls. Hide arrow is a display preference, not Stop.
    -- A stopped journey clears the reload checkpoint and cannot reappear on its own.
    self.navPause=captionButton(nav,"Pause navigation",20,-532,266,31,function()
        local owner=JLP:GetModule("IntegratedDestinationOwner")
        local state=owner and owner.GetSnapshot and owner:GetSnapshot() or nil
        self:ControlIntegratedNavigation(state and state.status=="PAUSED" and "RESUME" or "PAUSE")
    end)
    self.navStop=captionButton(nav,"Stop navigation",309,-532,265,31,function()
        self:ControlIntegratedNavigation("STOP")
    end)
    self.navFooter=label(nav,"","GameFontHighlightSmall",22,-573,545,21,"muted")

    -- PROFESSIONS: selected != focus; no spurious switch action
    local pro=self.designPages.Professions
    pageTitle(pro,"Primary Professions","Select up to two learned professions, then choose the active navigation target.")
    section(pro,"Learned Professions",-99)
    self.designPrimaryButtons={};self.designPrimaryFocusButtons={};self.designPrimaryLabels={}
    for i=1,2 do
        local index=i
        local y=-148-(i-1)*81
        local f=panel(pro,20,y,554,69)
        local toggle=boxCheck(f,"",11,-18,323,function()
            local slots=self:GetPrimarySlots();local s=slots[index]
            if s then self:TogglePrimary(s.key) end
        end)
        self.designPrimaryButtons[i]=toggle
        local badge=label(f,"","GameFontHighlightSmall",348,-10,190,19,"muted")
        self.designPrimaryLabels[i]=badge
        local focus=captionButton(f,"Set active",355,-32,180,29,function()
            local slots=self:GetPrimarySlots();local s=slots[index]
            if s and self:IsPrimarySelected(s.key) then
                local oldFocus=self.focusPrimary
                -- Do not write focus or SavedVariables before owner admission.
                -- ActivateCurrentStepTarget commits both on success (05C).
                -- Set active is an explicit navigation action, not a focus-only
                -- preview. Resolve/admit the selected profession before changing
                -- visual mode: a successful request transfers ownership from
                -- Gathering to the shared JuztTravel Current Step session in
                -- ONE click. If qualification fails, retain an existing
                -- Gathering journey; do not lose or overwrite its route.
                local ok,why=self:ActivateCurrentStepTarget(s.key,oldFocus)
                if not ok then self:Print("Current Step: "..tostring(why)) end
            end
        end)
        self.designPrimaryFocusButtons[i]=focus
    end
    section(pro,"Current Step",-326)
    local step=panel(pro,20,-370,554,171)
    self.designPrimaryStatus=label(step,"","GameFontHighlight",17,-16,520,24)
    self.designPrimaryAction=label(step,"","GameFontHighlightSmall",17,-53,514,56,"muted")
    self.designPrimaryPoint=label(step,"","GameFontHighlightSmall",17,-112,514,44,"muted")

    -- ROUTES: route page with bounded scrolling and manual form
    local route=self.designPages.Routes
    pageTitle(route,"Manual Routes & Waypoints","Manage your own waypoints. Gathering routes remain in JuztLevel Gathering Map.")
    self.routeSummary=label(route,"","GameFontHighlight",22,-98,548,26)
    self.routeDetails=label(route,"","GameFontHighlightSmall",22,-126,545,27,"muted")
    self.routePrevious=captionButton(route,"Previous stop",20,-165,170,32,function()
        local r=routeData();if r then self:SelectRouteStop((r.index or 1)-1) end
    end)
    self.routeNext=captionButton(route,"Next stop",211,-165,170,32,function()
        local r=routeData();if r then self:SelectRouteStop((r.index or 1)%#r.points+1) end
    end)
    self.routeCycle=captionButton(route,"Switch route",402,-165,172,32,function()self:CycleGathering()end)
    self.routeCycle:Hide() -- Generated Gathering Map routes are not managed here.
    section(route,"Waypoints",-213)
    self.routeList={}
    for i=1,4 do
        local row=captionButton(route,"",24,-247-(i-1)*33,546,29,function()
            local entry=self.routeList[i]
            if entry and entry._index then self:SelectRouteStop(entry._index) end
        end)
        self.routeList[i]=row
        if row.EnableMouseWheel then row:EnableMouseWheel(true) end
        row:SetScript("OnMouseWheel",function(_,delta)
            local r=routeData();local total=r and #r.points or 0
            if total<=4 then return end
            local direction=tonumber(delta) or 0
            self.routeListOffset=min(max(0,(self.routeListOffset or 0)-(direction>0 and 1 or -1)),max(0,total-4))
            self:RefreshDesignUI()
        end)
    end
    self.routeScrollUp=captionButton(route,"Previous 4",24,-389,147,28,function()
        self.routeListOffset=max(0,(self.routeListOffset or 0)-4);self:RefreshDesignUI()
    end)
    self.routeScrollLabel=label(route,"","GameFontHighlightSmall",207,-394,179,22,"muted")
    self.routeScrollLabel:SetJustifyH("CENTER")
    self.routeScrollDown=captionButton(route,"Next 4",423,-389,147,28,function()
        self.routeListOffset=(self.routeListOffset or 0)+4;self:RefreshDesignUI()
    end)
    section(route,"Manual Waypoint",-432)
    local fieldY=-470
    local function field(name,x,w)
        label(route,name,"GameFontHighlightSmall",x,fieldY,w,18,"muted")
        local box=CreateFrame("EditBox",nil,route)
        box:SetSize(w-12,25);box:SetPoint("TOPLEFT",route,"TOPLEFT",x+6,fieldY-19)
        if box.SetFont then box:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",14,"") end
        local backdrop=box:CreateTexture(nil,"BACKGROUND")
        backdrop:SetAllPoints(box);backdrop:SetColorTexture(.04,.12,.20,.96)
        local border=box:CreateTexture(nil,"BORDER")
        border:SetPoint("BOTTOMLEFT",box,"BOTTOMLEFT",0,0)
        border:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",0,0)
        border:SetHeight(1);border:SetColorTexture(.30,.49,.66,.85)
        if box.SetAutoFocus then box:SetAutoFocus(false) end
        if box.SetMaxLetters then box:SetMaxLetters(16) end
        if box.SetNumeric then box:SetNumeric(false) end
        box:SetText("")
        box:SetScript("OnEnterPressed",function(self)self:ClearFocus()end)
        box:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
        return box
    end
    self.manualMap=field("Map ID",27,120)
    self.manualMap:SetScript("OnTextChanged",function(box,userInput)
        if userInput then
            self.manualMapUserEdited=tostring(box:GetText() or "")~=""
        end
    end)
    self:SyncManualMapField()
    self.manualX=field("X %",165,114)
    self.manualY=field("Y %",295,114)
    self.manualSet=captionButton(route,"Set waypoint",423,-485,146,32,function()
        self:SyncManualMapField()
        local ok,msg=self:SetManualWaypointPercent(self.manualMap:GetText(),self.manualX:GetText(),self.manualY:GetText())
        if ok then self.userRoute=nil;if self.profile then self.profile.manualRoute=nil end end
        self.manualFeedback:SetText(msg)
        self:RefreshDesignUI()
    end)
    self.manualAdd=captionButton(route,"Add to route",397,-528,172,29,function()
        self:SyncManualMapField()
        local ok,msg=self:AddManualRouteStop(self.manualMap:GetText(),self.manualX:GetText(),self.manualY:GetText())
        self.manualFeedback:SetText(msg)
        self:RefreshDesignUI()
    end)
    self.manualClear=captionButton(route,"Clear manual",22,-528,168,29,function()
        if self.userRoute or self.manual then
            self:ClearUserRoute()
            self.manualFeedback:SetText("Manual route and navigation cleared.")
        end
    end)
    self.manualCurrent=captionButton(route,"Use my position",205,-528,181,29,function()
        local ok,map=pcall(function()return C_Map.GetBestMapForUnit("player") end)
        if not ok or type(map)~="number" then
            self.manualFeedback:SetText("Player map is not available.")
            return
        end
        local got,pos=pcall(function()return C_Map.GetPlayerMapPosition(map,"player") end)
        local x,y
        if got and pos then pcall(function()x,y=pos:GetXY()end) end
        if not self:ValidPoint(map,x,y) then
            self.manualFeedback:SetText("Current location cannot be verified.")
            return
        end
        local result=self:SetWaypoint(map,x,y,"Current position")
        self.manualFeedback:SetText(result and "Current position selected." or "Could not use current position.")
        self:RefreshDesignUI()
    end)
    self.manualFeedback=label(route,"Map ID uses your current zone automatically. X/Y: 0–100.","GameFontHighlightSmall",22,-565,547,22,"muted")
    
    -- DISPLAY: keep live arrow styles, typography and visibility, not motion settings
    local display=self.designPages.Display
    pageTitle(display,"Display","Choose the arrow appearance and adjust its live in-game HUD.")
    self.styleButtons={};self.styleMarker={}
    local styles={{"classic","Classic Silver","Silver / halo"},{"updated","Blue Trim","Blue / halo"},{"clean","Clean Blue","Blue / no halo"}}
    for i,e in ipairs(styles) do
        local style,name,desc=unpack(e)
        local card=CreateFrame("Button",nil,display)
        card:SetPoint("TOPLEFT",display,"TOPLEFT",20+(i-1)*187,-99)
        card:SetSize(180,169)
        self:SkinThemePanel(card,"secondary")
        local bg=card:CreateTexture(nil,"BACKGROUND")
        bg:SetPoint("TOPLEFT",card,"TOPLEFT",10,-9);bg:SetPoint("TOPRIGHT",card,"TOPRIGHT",-10,-9)
        bg:SetHeight(108);bg:SetColorTexture(.08,.15,.24,.62)
        local preview=card:CreateTexture(nil,"ARTWORK")
        preview:SetTexture(self.asset.."arrow_"..style..".tga")
        preview:SetSize(123,123);preview:SetPoint("TOP",card,"TOP",0,-2)
        local nameText=label(card,name,"GameFontHighlight",15,-117,150,23)
        nameText:SetJustifyH("CENTER")
        local short=label(card,desc,"GameFontHighlightSmall",8,-142,163,19,"muted")
        short:SetJustifyH("CENTER")
        local marker=card:CreateTexture(nil,"OVERLAY")
        marker:SetPoint("BOTTOMLEFT",card,"BOTTOMLEFT",8,6)
        marker:SetPoint("BOTTOMRIGHT",card,"BOTTOMRIGHT",-8,6)
        marker:SetHeight(3);marker:SetColorTexture(0,.63,.97,1)
        card:SetScript("OnClick",function()
            self:SetArrowStyle(style)
            self._arrowTexturePath=nil -- Force renderer to reapply the selected art.
            self:Refresh(true)
        end)
        self.styleButtons[style]=card;self.styleMarker[style]=marker
    end
    section(display,"Size & Typography",-286)
    self.designSliders={}
    self.designSliders.arrow=slider(display,"Arrow size",-328,64,224,8,
        function()return self.profile.arrowSize end,function(v)self.profile.arrowSize=v end)
    self.designSliders.text=slider(display,"Text size",-379,10,26,1,
        function()return self.profile.textSize end,function(v)self.profile.textSize=v end)
    self.designArrowSizeLabel=self.designSliders.arrow.value
    self.designTextSizeLabel=self.designSliders.text.value
    label(display,"Text style","GameFontHighlight",22,-432,137,20)
    self.textStyleButtons={}
    for i,e in ipairs({{"OUTLINE","Outline"},{"THICKOUTLINE","Thick"},{"NONE","Plain"}}) do
        local key,text=unpack(e)
        self.textStyleButtons[key]=captionButton(display,text,166+(i-1)*135,-429,126,27,function()
            self.profile.textStyle=key;self._appliedTextStyle=nil;self:Refresh(true)
        end)
    end
    section(display,"HUD Visibility",-473)
    self.distanceTextButton=boxCheck(display,"Distance text",22,-509,166,function()
        self.profile.showDistanceText=not self.profile.showDistanceText;self:Refresh(true)
    end)
    self.arrivalIndicatorButton=boxCheck(display,"Arrival accent",204,-509,174,function()
        self.profile.showArrivalIndicator=not self.profile.showArrivalIndicator;self:Refresh(true)
    end)
    self.showArrowButton=boxCheck(display,"Show arrow",399,-509,168,function()
        self.profile.arrowShown=not self.profile.arrowShown;self:Refresh(true)
    end)
    self.designResetButton=captionButton(display,"Restore appearance defaults",22,-552,257,29,function()
        local p=self.profile
        p.arrowStyle="clean";p.arrowSize=112;p.textSize=13;p.textStyle="OUTLINE"
        p.showDistanceText=true;p.showArrivalIndicator=true;p.arrowShown=true
        self._appliedTextStyle=nil;self:Refresh(true)
    end)

    -- SETTINGS: behaviour + advanced as compact subviews, not duplicate menu pages
    local settings=self.designPages.Settings
    pageTitle(settings,"Settings","Navigation behaviour, HUD configuration, integration and diagnostics.")
    self.settingsTabs={}
    self.settingsTabs.Behaviour=captionButton(settings,"Behaviour",22,-101,262,35,function()self.settingsSection="Behaviour";self:RefreshDesignUI()end)
    self.settingsTabs.Advanced=captionButton(settings,"Advanced",307,-101,261,35,function()self.settingsSection="Advanced";self:RefreshDesignUI()end)
    self.settingsViews={}
    for _,key in ipairs({"Behaviour","Advanced"}) do
        local p=CreateFrame("Frame",nil,settings)
        p:SetPoint("TOPLEFT",settings,"TOPLEFT",0,-146);p:SetSize(594,437)
        self.settingsViews[key]=p
    end
    local bh=self.settingsViews.Behaviour
    section(bh,"Automation",-10)
    self.behaviourSmooth=boxCheck(bh,"Smooth rotation",24,-54,265,function()
        self.profile.smoothMotion=not self.profile.smoothMotion;self:Refresh(true)
    end)
    self.behaviourAuto=boxCheck(bh,"Auto-advance waypoints",296,-54,270,function()
        self.profile.autoAdvance=not self.profile.autoAdvance;self:Refresh(true)
    end)
    section(bh,"Rotation Response",-108)
    self.behaviourPresets={};self.motionButtons={}
    for i,entry in ipairs({{"fast","Fast"},{"balanced","Balanced"},{"gentle","Gentle"}}) do
        local key,name=unpack(entry)
        local b=captionButton(bh,name,23+(i-1)*185,-150,174,37,function()
            self.profile.motionPreset=key;self:Refresh(true)
        end)
        self.behaviourPresets[key]=b;self.motionButtons[key]=b
    end
    self.behaviourMotionHint=label(bh,"","GameFontHighlightSmall",24,-198,540,54,"muted")
    section(bh,"Waypoint Arrival Radius",-255)
    self.arrivalMinus=captionButton(bh,"-",24,-299,81,33,function()
        self.profile.arrival=max(3,self.profile.arrival-2);self:Refresh(true)
    end)
    self.behaviourArrival=label(bh,"","GameFontHighlight",139,-300,271,33)
    self.behaviourArrival:SetJustifyH("CENTER")
    self.arrivalPlus=captionButton(bh,"+",458,-299,105,33,function()
        self.profile.arrival=min(35,self.profile.arrival+2);self:Refresh(true)
    end)
    label(bh,"Yard radius applies when world distance is available. Map-only arrival uses a separate normalized tolerance.",
        "GameFontHighlightSmall",24,-352,540,48,"muted")
    self.arrivalReset=captionButton(bh,"Reset to 5 yd",24,-402,176,29,function()
        self.profile.arrival=self.DEFAULT_ARRIVAL_YARDS
        self:Refresh(true)
    end)
    local adv=self.settingsViews.Advanced
    section(adv,"HUD",-10)
    self.advancedLocked=boxCheck(adv,"Lock arrow position",24,-56,263,function()
        self.profile.locked=not self.profile.locked;self:Refresh(true)
    end)
    self.resetHud=captionButton(adv,"Reset arrow position",305,-55,260,32,function()
        self.profile.arrowX=0;self.profile.arrowY=175
        if self.arrowFrame then
            self.arrowFrame:ClearAllPoints();self.arrowFrame:SetPoint("CENTER",UIParent,"CENTER",0,175)
        end
        self:Refresh(true)
    end)
    section(adv,"JuztLevel Integration",-114)
    self.advancedIntegration=label(adv,"","GameFontHighlightSmall",24,-160,542,69,"muted")
    section(adv,"Diagnostics",-241)
    -- Six compact, legible diagnostic rows fit above the existing button row.
    -- The previous 119px field overlapped buttons at y=-393 even at the old font size.
    self.advancedDiagnostics=label(adv,"","GameFontHighlightSmall",24,-282,538,103,"muted")
    self.advancedDiagnosticDetails=captionButton(adv,"Print details in chat",305,-393,261,31,function()
        self:PrintFullDiagnostics()
    end)
    self.startDemo=captionButton(adv,"Start demo route",24,-393,127,31,function()
        local ok,reason=self:StartDemo();self:Print(ok and "Demo started" or tostring(reason));self:Refresh(true)
    end)
    self.stopDemo=captionButton(adv,"Stop demo",165,-393,128,31,function()self:StopDemo();self:Refresh(true)end)

    -- ABOUT: no unescaped WoW pipes or overly long single FontString
    local about=self.designPages.About
    pageTitle(about,"About JuztTom","Integrated JuztTom navigation for JuztLevel – Professions.")
    label(about,"JuztTom — Juztie","GameFontNormalLarge",24,-106,430,30,"gold")
    self.aboutVersion=label(about,"Version "..self.version,"GameFontHighlightSmall",25,-143,520,25,"muted")
    label(about,"WoW Forever 1.60.1  /  Integrated module  /  JuztLevel owner", "GameFontHighlightSmall",25,-166,544,21,"muted")
    section(about,"Features",-203)
    label(about,"Gathering route navigation and manual waypoints\nCurrent Step navigation for up to two professions\nThree arrow styles with frame-driven smooth rotation\nConfigurable HUD, inside JuztLevel",
        "GameFontHighlightSmall",26,-250,532,112)
    section(about,"Slash Commands",-366)
    label(about,"/jt                     Open or close the main menu\n/jt nav                Show navigation mode and current target\n/jt goto 142 43.6 71.2       Set a waypoint (map, X%, Y%)\n/jt next               Advance route\n/jt demo               Run synthetic test route\n/jt demo off           Restore the previous route\n/jt status             Print navigation status",
        "GameFontHighlightSmall",26,-409,534,170)
    self.designPanel=frame
    if type(_G.UISpecialFrames)=="table" then table.insert(_G.UISpecialFrames,"JuztLevelIntegratedTomDesignPanel") end
    self:ShowDesignPage("Navigation")
    frame:Hide()
end
-- Unified user actions. Never treat Hide arrow or a manual waypoint as a Stop.
-- The destination owner remains the single authority for persisted navigation.
function JT:ControlIntegratedNavigation(action)
    local unified=JLP:GetModule("UnifiedDestinationNavigation")
    if not unified then return false,"NAVIGATION_UNAVAILABLE" end
    local ok,reason
    if action=="STOP" and type(unified.Stop)=="function" then
        ok,reason=unified:Stop("USER_STOP")
        if ok then
            self.manual=nil;self.external=nil;self._demoRestore=nil
            self.lastExternalArrival=nil;self.lastArrived=nil
        end
    elseif action=="PAUSE" and type(unified.Pause)=="function" then
        ok,reason=unified:Pause()
    elseif action=="RESUME" and type(unified.Resume)=="function" then
        ok,reason=unified:Resume()
    else return false,"UNSUPPORTED_NAVIGATION_ACTION" end
    self:Refresh(true)
    return ok,reason
end
-- Visible comprehensive diagnostic export; never print private SavedVariables.
function JT:PrintFullDiagnostics()
    local state=self:GetState()
    local owner=JLP:GetModule("IntegratedDestinationOwner")
    local snapshot=owner and owner.GetSnapshot and owner:GetSnapshot() or nil
    local p=self.profile or {}
    local clientMap
    if C_Map and type(C_Map.GetBestMapForUnit)=="function" then
        local ok,result=pcall(C_Map.GetBestMapForUnit,"player")
        if ok then clientMap=result end
    end
    local target=state.target
    local point=snapshot and snapshot.point
    local geometry=self.geometry
    local function v(n) return tostring(n==nil and "-" or n) end
    local function pos(a)
        if not a then return "none" end
        return string.format("Map %s  %.2f, %.2f",v(a.mapID),(a.x or 0)*100,(a.y or 0)*100)
    end
    self:Print("--- Navigation diagnostics ---")
    self:Print("JuztLevel: "..v(self:GetBridgeState()).." | Settings: JuztLevelProfessionsDB")
    self:Print("Mode: "..v(state.mode).." | Status: "..v(state.status).." | Owner: "..v(snapshot and snapshot.status))
    self:Print("Provider: "..v(state.provider).." | Category: "..v(snapshot and snapshot.category).." | Player map: "..v(clientMap))
    self:Print("Active waypoint: "..pos(target).." | "..v(target and target.title))
    self:Print("Final destination: "..pos(point).." | "..v(point and point.label))
    self:Print("Route: "..v(state.routePosition).."/"..v(state.routeCount).." | "..v(snapshot and snapshot.routeReason))
    self:Print("Travel: "..v(state.travel and state.travel.phase).." | "..v(state.travel and state.travel.instruction):sub(1,110))
    self:Print("Geometry: "..v(geometry and geometry.status).." | Distance: "..v(state.distanceYards).." yd")
    self:Print("Arrow: "..v(p.arrowStyle).." | Size: "..v(p.arrowSize).." | Text: "..v(p.textSize).." | Smooth: "..v(p.smoothMotion))
    self:Print("Manual route: "..v(self.userRoute and #self.userRoute.points or 0).." stops | Current step: "..v(self.focusPrimary))
    local taxi=JLP:GetModule("FlightUnlockObservation")
    local fs=taxi and taxi.GetStatus and taxi:GetStatus() or nil
    if fs then
        self:Print("Flight access: "..v(fs.verifiedFlightEdges).." confirmed connections | "..
            v(fs.knownFlightMasters).." observed Flight Masters | Surveys: "..
            v(fs.observations).." | Stored: "..v(fs.persisted))
    end
end
function JT:ToggleDesignPanel()
    if not self.designPanel then self:CreateDesignUI() end
    if self.designPanel:IsShown() then self.designPanel:Hide()
    else self.designPanel:Show();self:RefreshDesignUI() end
end
function JT:RefreshDesignUI()
    if not self.designPanel or not self.profile or not self.designPanel:IsShown() then return end
    if self.designPage=="Routes" then self:SyncManualMapField() end
    local p=self.profile;local pt=self.current
    local travel=self.travelOverlay
    local owner=JLP:GetModule("IntegratedDestinationOwner")
    local ownerState=owner and owner.GetSnapshot and owner:GetSnapshot() or nil
    local ownerStatus=ownerState and ownerState.status or "UNKNOWN"
    local pausedPoint=ownerStatus=="PAUSED" and ownerState.point or nil
    -- A mode button must not advertise or control an unrelated owner target.
    local ownerMatchesMode=ownerState and (self.mode~="GATHERING" or ownerState.category=="GATHERING")
    if not ownerMatchesMode then pausedPoint=nil end
    local heading,hint=stateText(self.status,self.mode,pt~=nil)
    if self.mode=="GATHERING" and not pt then
        heading="No active gathering waypoint"
        hint="Generate a gathering route in JuztLevel Gathering Map, then choose Gathering."
    end
    if travel then
        heading=self:TravelStatusTitle(travel)
        hint=travel.instruction~="" and travel.instruction or "Follow the active JuztTravel stage."
    end
    self.designNavStatus:SetText(heading)
    self.designNavDetail:SetText(hint)
    local number=self.routeIndex and self.routeCount and ("Stop "..self.routeIndex.."/"..self.routeCount.."  -  ") or ""
    self.designNavTarget:SetText(pausedPoint and ("Paused destination: "..tostring(pausedPoint.label or "Selected waypoint")) or
        (travel and not pt and "Destination: awaiting next travel stage" or
         ("Destination: "..number..(travel and travel.displayTitle or destinationName(pt)))))
    if pausedPoint then
        self.designNavMap:SetText(string.format("Map %d   %.2f, %.2f",pausedPoint.mapID,pausedPoint.x*100,pausedPoint.y*100))
    else
        self.designNavMap:SetText(mapText(pt))
    end
    if self.userRoute and self.manual and not travel then
        number="Stop "..tostring(self.userRoute.index).."/"..tostring(#self.userRoute.points).."  -  "
    end
    local d=self.distanceYards
    self.designNavDistance:SetText(pausedPoint and "Distance: —" or
        (d and string.format("Distance: %.0f yd",d) or (pt and "Distance: map direction only" or "Distance: —")))
    local isGather=self.mode=="GATHERING"
    self.designModeHint:SetText(isGather and
        ((self.gatheringState and self.gatheringState.activeKey and ownerMatchesMode) and
            "Following "..self.gatheringState.activeKey.." from Gathering Map." or
            "Select a generated route in JuztLevel Gathering Map.") or
        "Following the active learned profession's current step.")
    for mode,b in pairs(self.modeButtons) do selected(b,self.mode==mode) end
    local r=routeData()
    local gatherRoute=self.mode=="GATHERING" and ownerMatchesMode and self.gatheringState and
        self.gatheringState.routes and self.gatheringState.routes[self.gatheringState.activeKey] or nil
    enabled(self.navNext,(r and r.points and #r.points>1 and
        (r.closed or (r.index or 0)<#r.points) and (not travel or r.kind=="USER")) or
        (gatherRoute and #gatherRoute.points>1 and
            (gatherRoute.closed or (gatherRoute.index or 0)<#gatherRoute.points)))
    self.navArrow.caption:SetText(p.arrowShown and "Hide navigation arrow" or "Show navigation arrow")
    local hasTarget=ownerMatchesMode and ownerState.point~=nil
    -- An advisory zone transition is an active journey, even though it has
    -- no end-to-end route object. Pause/Resume must work there as well.
    enabled(self.navPause,hasTarget and ownerState.needsRevalidation~=true and
        (ownerStatus=="PAUSED" or ownerStatus=="AVAILABLE" or
         ownerStatus=="DESTINATION_ONLY"))
    self.navPause.caption:SetText(ownerStatus=="PAUSED" and "Resume navigation" or "Pause navigation")
    enabled(self.navStop,hasTarget and ownerStatus~="STALE" and ownerStatus~="STOPPED")
    self.navFooter:SetText(ownerStatus=="STOPPED" and "Navigation stopped. Select a destination to restart." or
        ownerStatus=="PAUSED" and "Navigation paused. Choose Resume to continue." or
        travel and "Follow the next travel stage to reach your destination." or
        pt and "Current destination is controlled by the selected route or step." or
        (isGather and "Open Gathering Map and select Generate Route." or "Choose a primary profession in the Professions tab."))
    local slots=self:GetPrimarySlots()
    local targets=self:GetCurrentTargets()
    local focus=self.focusPrimary
    for i=1,2 do
        local s=slots[i]
        local b=self.designPrimaryButtons[i];local fb=self.designPrimaryFocusButtons[i]
        local badge=self.designPrimaryLabels[i]
            b:SetShown(s~=nil);fb:SetShown(s~=nil);badge:SetShown(s~=nil)
        if s then
            local checked=self:IsPrimarySelected(s.key)
            b.caption:SetText(s.name or s.key);b:SetCheckedVisual(checked)
            local active=checked and focus==s.key
            badge:SetText(active and "ACTIVE" or checked and "SELECTED" or "NOT SELECTED")
            fb.caption:SetText(active and "Navigate To" or "Set active")
            enabled(fb,checked)
        end
    end
    local chosen=nil
    for _,s in ipairs(targets) do if s.key==focus then chosen=s;break end end
    chosen=chosen or targets[1]
    self.designPrimaryStatus:SetText(chosen and ((self.mode=="CURRENT_STEP" and "Current Step focus: " or "Next Current Step focus: ")..chosen.name) or "No profession selected")
    self.designPrimaryAction:SetText(chosen and ("Current step: "..tostring(chosen.action or "Not available")) or "Select at least one learned primary profession.")
    self.designPrimaryPoint:SetText(chosen and chosen.point and ("Destination: "..destinationName(chosen.point).."\n"..mapText(chosen.point)) or
        (chosen and "No destination coordinates for this step." or "Awaiting profession selection."))
    if self.currentStepActionFeedback then
        local explanation={CURRENT_STEP_SOURCE_UNAVAILABLE="No navigable Current Step for this profession. Existing Gathering navigation remains available.",
            CURRENT_STEP_PLAN_UNAVAILABLE="No Current Step plan is available for this profession. Existing Gathering navigation remains available."}
        self.designPrimaryPoint:SetText(explanation[self.currentStepActionFeedback] or
            "Navigation: "..self.currentStepActionFeedback)
    end
    self.routeSummary:SetText(r and ("Route: "..tostring(r.title)) or (self.manual and "Single manual waypoint active" or "No manual route"))
    self.routeDetails:SetText(r and ("Map "..tostring(r.mapID).."   /   Stop "..tostring(r.index or 1).." / "..tostring(#r.points).."   /   "..tostring(r.kind)) or
        "Add your own points below. Generated routes stay in Gathering Map.")
    enabled(self.routePrevious,(not travel or (r and r.kind=="USER")) and r and (r.index or 1)>1)
    enabled(self.routeNext,(not travel or (r and r.kind=="USER")) and r and #r.points>1 and (r.closed or (r.index or 0)<#r.points))
    enabled(self.routeCycle,false) -- Gathering-route switching belongs to Gathering Map.
    enabled(self.manualClear,self.manual~=nil or self.userRoute~=nil)
    self.manualClear.caption:SetText(self.userRoute and "Clear route" or "Clear manual")
    local n=r and #r.points or 0
    self.routeListOffset=min(max(0,self.routeListOffset or 0),max(0,n-4))
    for i,b in ipairs(self.routeList) do
        local index=self.routeListOffset+i
        local point=r and r.points[index]
        b._index=point and index or nil
        b:SetShown(point~=nil)
        if point then
            b.caption:SetText(string.format("%s  %d/%d     %s", index==r.index and ">" or "  ",index,n,destinationName(point)))
            selected(b,index==r.index)
        end
    end
    self.routeScrollLabel:SetText(n>0 and (tostring(self.routeListOffset+1).."–"..tostring(min(n,self.routeListOffset+4)).." / "..tostring(n)) or "0 / 0")
    self.routeScrollUp:SetShown(n>4)
    self.routeScrollDown:SetShown(n>4)
    self.routeScrollLabel:SetShown(n>4)
    enabled(self.routeScrollUp,self.routeListOffset>0)
    enabled(self.routeScrollDown,self.routeListOffset+4<n)
    for style,marker in pairs(self.styleMarker) do marker:SetShown(style==p.arrowStyle) end
    self._sliderSync=true
    for _,v in pairs(self.designSliders) do v.slider:SetValue(v.get()) end
    self._sliderSync=false
    self.designArrowSizeLabel:SetText(tostring(p.arrowSize).." px")
    self.designTextSizeLabel:SetText(tostring(p.textSize).." pt")
    for style,b in pairs(self.textStyleButtons) do selected(b,style==p.textStyle) end
    self.distanceTextButton:SetCheckedVisual(p.showDistanceText)
    self.arrivalIndicatorButton:SetCheckedVisual(p.showArrivalIndicator)
    self.showArrowButton:SetCheckedVisual(p.arrowShown)
    local view=self.settingsSection or "Behaviour"
    for name,f in pairs(self.settingsViews) do f:SetShown(name==view) end
    for name,b in pairs(self.settingsTabs) do selected(b,name==view) end
    self.behaviourSmooth:SetCheckedVisual(p.smoothMotion)
    self.behaviourAuto:SetCheckedVisual(p.autoAdvance)
    for name,b in pairs(self.behaviourPresets) do selected(b,name==p.motionPreset) end
    local descriptions={fast="Fast: rapid adjustment for sharp turns.",balanced="Balanced: responsive, with smooth transitions.",gentle="Gentle: slower easing for gradual movement."}
    self.behaviourMotionHint:SetText(descriptions[p.motionPreset] or descriptions.balanced)
    self.behaviourArrival:SetText(tostring(p.arrival).." yards")
    enabled(self.arrivalMinus,p.arrival>3);enabled(self.arrivalPlus,p.arrival<35)
    self.advancedLocked:SetCheckedVisual(p.locked)
    local bridge=self:GetBridgeState()
    self.advancedIntegration:SetText("JuztLevel: "..tostring(bridge).."\nProvider: "..tostring(pt and pt.source or "none").."     Navigation mode: "..self.mode..(travel and "\nTravel: "..tostring(travel.phase) or ""))
    local clientMap=nil
    if C_Map and type(C_Map.GetBestMapForUnit)=="function" then
        local ok,result=pcall(C_Map.GetBestMapForUnit,"player")
        if ok then clientMap=result end
    end
    local owner=JLP:GetModule("IntegratedDestinationOwner")
    local ownerState=owner and type(owner.GetSnapshot)=="function" and owner:GetSnapshot() or nil
    local routeReason=ownerState and ownerState.routeReason or "NO_DESTINATION"
    -- Staged navigation is advisory: don't describe it as a verified route.
    if travel and travel.routeVerified==false and travel.stage then
        routeReason="STAGED_ADVISORY / "..tostring(travel.stage)
    end
    self.advancedDiagnostics:SetText("Navigation: "..readableDiagnosticStatus(self.status or "NO_WAYPOINT")..
        "  /  "..readableDiagnosticStatus(ownerState and ownerState.status or "NO_OWNER")..
        "\nPlayer Map: "..tostring(clientMap or "—").."    Target Map: "..tostring(pt and pt.mapID or "—")..
        "\nTravel route: "..tostring(routeReason):sub(1,62)..
        "\nGeometry: "..tostring(self.geometry and self.geometry.status or "NO_POSITION")..
        "    Stops: "..tostring(self.routeIndex or "—").." / "..tostring(self.routeCount or "—")..
        "\nMotion: "..tostring(p.motionPreset).." / Smooth: "..tostring(p.smoothMotion)..
        "\nSettings: JuztLevelProfessionsDB")
    enabled(self.stopDemo,self.external and self.external.id=="juzttom-demo" and self._demoRestore~=nil)
end
