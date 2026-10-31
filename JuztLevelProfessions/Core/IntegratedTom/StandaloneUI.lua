local _, JLP = ...
local JT = JLP._integratedTom
local C=JT.colors
local function backdrop(frame,r,g,b,a)
    local t=frame:CreateTexture(nil,"BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(r,g,b,a)
    local edges={}
    for i=1,4 do
        local edge=frame:CreateTexture(nil,"BORDER")
        edge:SetColorTexture(unpack(C.border))
        if i==1 then edge:SetPoint("TOPLEFT");edge:SetPoint("TOPRIGHT");edge:SetHeight(1)
        elseif i==2 then edge:SetPoint("BOTTOMLEFT");edge:SetPoint("BOTTOMRIGHT");edge:SetHeight(1)
        elseif i==3 then edge:SetPoint("TOPLEFT");edge:SetPoint("BOTTOMLEFT");edge:SetWidth(1)
        else edge:SetPoint("TOPRIGHT");edge:SetPoint("BOTTOMRIGHT");edge:SetWidth(1) end
        edges[i]=edge
    end
    return t
end
local function text(parent,size,color)
    local template=size or "GameFontNormalSmall"
    local f=parent:CreateFontString(nil,"OVERLAY",template)
    if template=="GameFontHighlightSmall" or template=="GameFontNormalSmall" then
        local face,pt,flags=f:GetFont()
        if face and (not pt or pt<14) then f:SetFont(face,14,flags or "") end
    end
    f:SetJustifyH("LEFT")
    f:SetTextColor(unpack(C[color or "silver"]))
    return f
end
local function button(parent,label,w,h,click)
    local b=CreateFrame("Button",nil,parent)
    b:SetSize(w or 110,h or 27)
    backdrop(b,0.025,0.090,0.139,0.94)
    local line=b:CreateTexture(nil,"ARTWORK")
    line:SetColorTexture(unpack(C.blue))
    line:SetPoint("BOTTOMLEFT",b,"BOTTOMLEFT",2,2)
    line:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-2,2)
    line:SetHeight(2)
    local t=text(b,"GameFontHighlightSmall","silver")
    t:SetAllPoints()
    t:SetJustifyH("CENTER")
    t:SetText(label)
    b.caption=t
    b:SetScript("OnClick",click)
    b:SetScript("OnEnter",function(self) self.hover:SetAlpha(1) end)
    b:SetScript("OnLeave",function(self) self.hover:SetAlpha(0) end)
    local hover=b:CreateTexture(nil,"HIGHLIGHT")
    hover:SetAllPoints();hover:SetColorTexture(0.13,0.30,0.45,0.22)
    b.hover=hover;hover:SetAlpha(0)
    return b
end
local function movable(frame,keyX,keyY)
    frame:SetMovable(true);frame:EnableMouse(true);frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self)
        if self==JT.arrowFrame and JT.profile.locked then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local x,y=self:GetCenter()
        local sx,sy=UIParent:GetCenter()
        if x and y and sx and sy then
            local scale=self:GetEffectiveScale()/UIParent:GetEffectiveScale()
            JT.profile[keyX]=(x-sx)*scale
            JT.profile[keyY]=(y-sy)*scale
        end
        self:ClearAllPoints()
        self:SetPoint("CENTER",UIParent,"CENTER",JT.profile[keyX],JT.profile[keyY])
    end)
end
function JT:CreateUI()
    if self.panel then return end
    -- Transparent draggable HUD: NO panel, borders, underlay, backdrop or plate.
    local arrow=CreateFrame("Frame","JuztLevelIntegratedTomArrow",UIParent)
    arrow:SetFrameStrata("HIGH")
    arrow:SetPoint("CENTER",UIParent,"CENTER",self.profile.arrowX,self.profile.arrowY)
    movable(arrow,"arrowX","arrowY")
    -- Logical arrow slot is separate from the enlarged, padded texture.
    -- Rotation through +/-45 degrees must not cut off the wing tips.
    local arrowSlot=CreateFrame("Frame",nil,arrow)
    arrowSlot:SetPoint("TOP",arrow,"TOP",0,0)
    self.arrowSlot=arrowSlot
    local arrowImage=arrowSlot:CreateTexture(nil,"ARTWORK")
    arrowImage:SetTexture(self.asset.."arrow_clean.tga")
    arrowImage:SetPoint("CENTER",arrowSlot,"CENTER",0,0)
    self.arrowTexture=arrowImage
    -- The updated/Blue Trim variant needs an unmistakable border distinct
    -- from Clean Blue. This glow belongs to the same arrow slot and rotates
    -- with the arrow, without a second independent navigation pointer.
    local glow=arrowSlot:CreateTexture(nil,"BORDER")
    glow:SetTexture(self.asset.."arrow_updated.tga")
    glow:SetPoint("CENTER",arrowSlot,"CENTER",0,0)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(.18,.57,1,1)
    glow:SetAlpha(.36)
    glow:Hide()
    self.arrowBlueTrimGlow=glow
    local label=text(arrow,"GameFontNormalSmall","silver")
    label:SetPoint("TOP",arrowSlot,"BOTTOM",0,-5)
    label:SetJustifyH("CENTER")
    self.arrowLabel=label
    -- Optional standalone descriptor line. Distance is *always* the final,
    -- separate line: title / optional descriptor / yards.
    local context=text(arrow,"GameFontHighlightSmall","muted")
    context:SetPoint("TOP",label,"BOTTOM",0,-3)
    context:SetJustifyH("CENTER")
    context:Hide()
    self.arrowContext=context
    local detail=text(arrow,"GameFontHighlightSmall","muted")
    detail:SetPoint("TOP",label,"BOTTOM",0,-3)
    detail:SetJustifyH("CENTER")
    self.arrowDetail=detail
    self.arrowFrame=arrow
    arrow:SetScript("OnMouseUp",function(_,mouse)
        if mouse=="RightButton" then
            if JT.ToggleDesignPanel then JT:ToggleDesignPanel() else JT:TogglePanel() end
        end
    end)
    self:ApplyArrowSizing()

    local panel=CreateFrame("Frame","JuztLevelIntegratedTomPanel",UIParent)
    panel:SetSize(430,644)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("CENTER",UIParent,"CENTER",self.profile.panelX,self.profile.panelY)
    backdrop(panel,unpack(C.bg))
    movable(panel,"panelX","panelY")
    self.panel=panel
    local header=panel:CreateTexture(nil,"ARTWORK")
    header:SetColorTexture(0.027,0.083,0.13,1)
    header:SetPoint("TOPLEFT",panel,"TOPLEFT",2,-2)
    header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-2,-2)
    header:SetHeight(64)
    local icon=panel:CreateTexture(nil,"OVERLAY")
    icon:SetTexture(self.asset.."juzttom_icon.tga")
    icon:SetSize(47,47)
    icon:SetPoint("TOPLEFT",panel,"TOPLEFT",13,-8)
    local title=text(panel,"GameFontNormalLarge","silver")
    title:SetPoint("TOPLEFT",panel,"TOPLEFT",69,-15)
    title:SetText("JuztTom")
    local subtitle=text(panel,"GameFontHighlightSmall","muted")
    subtitle:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-3)
    subtitle:SetText("Navigation companion  |  Integrated JuztTravel")
    local close=button(panel,"X",28,27,function()panel:Hide()end)
    close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-10,-13)
    local tabs={}
    tabs.GATHERING=button(panel,"Gathering",186,35,function()JT:SetMode("GATHERING")end)
    tabs.GATHERING:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-77)
    tabs.CURRENT_STEP=button(panel,"Current Step",186,35,function()JT:SetMode("CURRENT_STEP")end)
    tabs.CURRENT_STEP:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-77)
    self.modeTabs=tabs
    local info=CreateFrame("Frame",nil,panel)
    info:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-125)
    info:SetSize(390,199)
    backdrop(info,unpack(C.alt))
    local heading=text(info,"GameFontNormal","silver")
    heading:SetPoint("TOPLEFT",info,"TOPLEFT",12,-13)
    self.infoHeading=heading
    local status=text(info,"GameFontHighlightSmall","muted")
    status:SetPoint("TOPLEFT",info,"TOPLEFT",12,-38)
    status:SetSize(367,35)
    status:SetWordWrap(true)
    self.infoStatus=status
    local target=text(info,"GameFontHighlight","silver")
    target:SetPoint("TOPLEFT",info,"TOPLEFT",12,-78)
    target:SetSize(364,22)
    self.infoTarget=target
    local coordinates=text(info,"GameFontHighlightSmall","muted")
    coordinates:SetPoint("TOPLEFT",info,"TOPLEFT",12,-104)
    coordinates:SetSize(364,23)
    self.infoCoordinates=coordinates
    local infoMore=text(info,"GameFontHighlightSmall","muted")
    infoMore:SetPoint("TOPLEFT",info,"TOPLEFT",12,-135)
    infoMore:SetSize(365,50)
    infoMore:SetWordWrap(true)
    self.infoMore=infoMore
    local current=CreateFrame("Frame",nil,panel)
    current:SetPoint("TOPLEFT",panel,"TOPLEFT",0,-333)
    current:SetSize(430,74)
    self.primaryControls=current
    local slots={}
    for i=1,2 do
        local index=i
        local b=button(current,"[ ] Primary profession",190,28,function()
            local snapshot=JT:GetPrimarySlots()
            if snapshot[index] then JT:TogglePrimary(snapshot[index].key) end
        end)
        if i==1 then b:SetPoint("TOPLEFT",current,"TOPLEFT",20,0)
        else b:SetPoint("TOPRIGHT",current,"TOPRIGHT",-20,0) end
        slots[i]=b
    end
    self.primaryButtons=slots
    local btns=CreateFrame("Frame",nil,panel)
    btns:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-341)
    btns:SetSize(390,64)
    self.routeControls=btns
    local switch=button(btns,"Switch Route",186,28,function()JT:CycleGathering()end)
    switch:SetPoint("TOPLEFT",btns,"TOPLEFT",0,0)
    self.switchRouteButton=switch
    local nextStop=button(btns,"Next Stop",186,28,function()JT:Advance()end)
    nextStop:SetPoint("TOPRIGHT",btns,"TOPRIGHT",0,0)
    local focus=button(current,"Switch Profession",185,27,function()JT:CyclePrimary()end)
    focus:SetPoint("TOPLEFT",current,"TOPLEFT",20,-38)
    self.switchPrimaryButton=focus
    local clearOverride=button(current,"Clear override",185,27,function()
        JT:ClearWaypoint()
    end)
    clearOverride:SetPoint("TOPRIGHT",current,"TOPRIGHT",-20,-38)
    local settings=CreateFrame("Frame",nil,panel)
    settings:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-412)
    settings:SetSize(390,46)
    self.settingsControls=settings
    local show=button(settings,"Arrow: On",122,28,function()
        JT.profile.arrowShown=not JT.profile.arrowShown;JT:Refresh(true)
    end)
    show:SetPoint("TOPLEFT",settings,"TOPLEFT",0,0)
    self.showButton=show
    local lock=button(settings,"Unlocked",122,28,function()
        JT.profile.locked=not JT.profile.locked;JT:Refresh(true)
    end)
    lock:SetPoint("TOPLEFT",show,"TOPRIGHT",9,0)
    self.lockButton=lock
    local auto=button(settings,"Auto: On",122,28,function()
        JT.profile.autoAdvance=not JT.profile.autoAdvance;JT:Refresh(true)
    end)
    auto:SetPoint("TOPRIGHT",settings,"TOPRIGHT",0,0)
    self.autoButton=auto
    local footer=text(panel,"GameFontHighlightSmall","muted")
    footer:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",20,15)
    footer:SetSize(390,20)
    self.footer=footer
    local arrivalL=button(panel,"-",28,25,function()
        JT.profile.arrival=math.max(3,JT.profile.arrival-2);JT:Refresh(true)
    end)
    arrivalL:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-456)
    local arrival=text(panel,"GameFontHighlightSmall","muted")
    arrival:SetPoint("LEFT",arrivalL,"RIGHT",11,0)
    arrival:SetSize(164,20)
    self.arrivalLabel=arrival
    local arrivalR=button(panel,"+",28,25,function()
        JT.profile.arrival=math.min(35,JT.profile.arrival+2);JT:Refresh(true)
    end)
    arrivalR:SetPoint("LEFT",arrival,"RIGHT",6,0)
    local reset=button(panel,"Reset position",119,25,function()
        JT.profile.arrowX=0;JT.profile.arrowY=175
        JT.arrowFrame:ClearAllPoints()
        JT.arrowFrame:SetPoint("CENTER",UIParent,"CENTER",0,175)
        JT:Refresh(true)
    end)
    reset:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-456)
    -- Independent controls persisted in JuztTomDB; no Blizzard slider templates.
    local arrowMinus=button(panel,"-",32,28,function()
        JT.profile.arrowSize=math.max(64,JT.profile.arrowSize-8);JT:Refresh(true)
    end)
    arrowMinus:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-507)
    local arrowSizeLabel=text(panel,"GameFontHighlightSmall","silver")
    arrowSizeLabel:SetPoint("LEFT",arrowMinus,"RIGHT",11,0)
    arrowSizeLabel:SetSize(222,22)
    self.arrowSizeLabel=arrowSizeLabel
    local arrowPlus=button(panel,"+",32,28,function()
        JT.profile.arrowSize=math.min(224,JT.profile.arrowSize+8);JT:Refresh(true)
    end)
    arrowPlus:SetPoint("LEFT",arrowSizeLabel,"RIGHT",3,0)
    local fontMinus=button(panel,"-",32,28,function()
        JT.profile.textSize=math.max(10,JT.profile.textSize-1);JT:Refresh(true)
    end)
    fontMinus:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-548)
    local textSizeLabel=text(panel,"GameFontHighlightSmall","silver")
    textSizeLabel:SetPoint("LEFT",fontMinus,"RIGHT",11,0)
    textSizeLabel:SetSize(222,22)
    self.textSizeLabel=textSizeLabel
    local fontPlus=button(panel,"+",32,28,function()
        JT.profile.textSize=math.min(26,JT.profile.textSize+1);JT:Refresh(true)
    end)
    fontPlus:SetPoint("LEFT",textSizeLabel,"RIGHT",3,0)
    local design=button(panel,"Open Main JuztTom UI",390,29,function()
        if JT.ToggleDesignPanel then JT:ToggleDesignPanel() end
    end)
    design:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-591)
    self.openDesignButton=design
    if type(_G.UISpecialFrames)=="table" then table.insert(_G.UISpecialFrames,"JuztLevelIntegratedTomPanel") end
    panel:Hide()
end
function JT:ApplyArrowSizing()
    if not self.arrowFrame or not self.profile then return end
    local s=self.profile.arrowSize or 112
    local f=self.profile.textSize or 13
    local style=self.profile.textStyle or "OUTLINE"
    if self._appliedArrowSize==s and self._appliedTextSize==f and self._appliedTextStyle==style then return end
    self._appliedArrowSize,self._appliedTextSize,self._appliedTextStyle=s,f,style
    local width=math.max(200,s+30,math.floor(f*20))
    self.arrowFrame:SetSize(width,s+3*f+32)
    self.arrowSlot:SetSize(s,s)
    -- Source TGA = 384px square with original 256px glyph centered.
    -- 1.5x UV rectangle preserves the requested physical glyph size.
    self.arrowTexture:SetSize(s*1.5,s*1.5)
    if self.arrowBlueTrimGlow then self.arrowBlueTrimGlow:SetSize(s*1.68,s*1.68) end
    self.arrowLabel:SetSize(width, f+5)
    self.arrowContext:SetSize(width, f+5)
    self.arrowDetail:SetSize(width, f+5)
    local font=STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local flags=style=="NONE" and "" or style
    self.arrowLabel:SetFont(font,f,flags)
    self.arrowContext:SetFont(font,f,flags)
    self.arrowDetail:SetFont(font,f,flags)
end
function JT:RelativeRotation(absoluteHeading,playerHeading)
    if type(absoluteHeading)~="number" or type(playerHeading)~="number" then return nil end
    if absoluteHeading~=absoluteHeading or playerHeading~=playerHeading or
       math.abs(absoluteHeading)==math.huge or math.abs(playerHeading)==math.huge then return nil end
    -- Both GetPlayerFacing and SetRotation use positive COUNTERCLOCKWISE.
    local delta=(absoluteHeading-playerHeading+math.pi)%(2*math.pi)-math.pi
    return delta
end
function JT:TogglePanel()
    if not self.panel then return end
    if self.panel:IsShown() then self.panel:Hide()
    else self.panel:Show();self:Refresh(true) end
end
local function clip(s,n)
    s=tostring(s or "")
    if #s<=n then return s end
    return s:sub(1,n-3).."..."
end
function JT:RefreshUI()
    if not self.panel then return end
    local p=self.profile
    self:ApplyArrowSizing()
    self.arrowFrame:SetShown(p.arrowShown)
    local style=p.arrowStyle or "clean"
    local arrived=(self.status=="AT_WAYPOINT") and p.showArrivalIndicator
    local textureName="arrow_"..style..(arrived and "_arrived.tga" or ".tga")
    local texturePath=self.asset..textureName
    if self._arrowTexturePath~=texturePath then
        self.arrowTexture:SetTexture(texturePath)
        self._arrowTexturePath=texturePath
    end
    if self.arrowBlueTrimGlow then
        self.arrowBlueTrimGlow:SetShown(style=="updated" and p.arrowShown~=false and
            self.current~=nil and self.geometry~=nil and self.geometry.positionAvailable==true)
    end
    local point=self.current
    local travel=self.travelOverlay
    local stopped=self.status=="JLP_STOPPED"
    local paused=self.status=="JLP_PAUSED"
    local entrance=not stopped and not paused and travel and
        travel.phase=="ENTER_DESTINATION_CITY" and travel.routeVerified==false
    local name=travel and travel.displayTitle or point and point.title or
        (travel and self:TravelStatusTitle(travel)) or "No waypoint"
    local descriptor=travel and travel.displayDetail or nil
    if entrance then
        -- Keep metadata's full location name; normalize HUD presentation only.
        -- This does not mutate the qualified waypoint or destination owner.
        name=name:gsub("%s+[Ee]ntrance%s*$","")
        descriptor="Entrance"
    elseif point and type(point.hudDescription)=="string" and point.hudDescription~="" then
        descriptor=point.hudDescription
    end
    self.arrowLabel:SetText(stopped and "Navigation stopped" or
        paused and "Navigation paused" or clip(name,38))
    self.arrowContext:SetText(descriptor or "")
    self.arrowContext:SetShown(descriptor~=nil)
    -- Hidden frames are not automatically removed from the anchor chain.
    -- Re-anchor the distance under the description only when it exists.
    local hasDescriptor=descriptor~=nil
    if self._detailHasDescriptor~=hasDescriptor then
        self.arrowDetail:ClearAllPoints()
        self.arrowDetail:SetPoint("TOP",hasDescriptor and self.arrowContext or self.arrowLabel,"BOTTOM",0,-3)
        self._detailHasDescriptor=hasDescriptor
    end
    local distance=self.distanceYards
    -- Rotation belongs exclusively to Motion.lua's per-frame animator.
    -- Never SetRotation from this slower 0.30s UI/status refresh.
    if stopped or paused or not point or not self.geometry or not self.geometry.positionAvailable then
        -- A stopped or paused session shows status, never a misleading arrow.
        self.arrowTexture:SetAlpha((stopped or paused or travel) and 0 or 0.28)
    end
    local dLabel=distance and string.format("%.0f yd",distance) or
        (self.status=="MAP_RELATIVE_DIRECTION" and "Map direction (no yard metric)" or
         self.status=="AT_WAYPOINT" and "Waypoint reached" or
         self.status=="TRAVEL_TO_DESTINATION_MAP" and "Check map / player location" or "Awaiting waypoint")
    if stopped then dLabel="Select a destination to restart"
    elseif paused then dLabel="Use Resume navigation to continue"
    elseif travel and not point then dLabel=clip(travel.instruction or self:TravelStatusTitle(travel),32) end
    if travel and travel.phase=="ENTER_DESTINATION_CITY" and travel.routeVerified==false then
        dLabel=distance and string.format("%.0f yd",distance) or
            "Distance unavailable"
    end
    self.arrowDetail:SetText(dLabel)
    self.arrowDetail:SetShown(p.showDistanceText~=false)
    if self.designPanel and self.RefreshDesignUI then self:RefreshDesignUI() end
    if not self.panel:IsShown() then return end
    for key,b in pairs(self.modeTabs) do
        b.caption:SetText((self.mode==key and "[ " or "")..(key=="GATHERING" and "Gathering" or "Current Step")..(self.mode==key and " ]" or ""))
    end
    local gathering=self.mode=="GATHERING"
    self.routeControls:SetShown(gathering)
    self.primaryControls:SetShown(not gathering)
    self.infoHeading:SetText(travel and "JUZTTRAVEL GUIDANCE" or self.manual and "MANUAL WAYPOINT" or self.external and "EXTERNAL ROUTE" or
        gathering and "GATHERING ROUTE" or "CURRENT STEP / PRIMARY PROFESSIONS")
    self.infoStatus:SetText(clip(travel and self:TravelStatusTitle(travel) or self.status or "NO_WAYPOINT",70))
    self.infoTarget:SetText(clip(point and point.title or "No qualified destination",49))
    self.infoCoordinates:SetText(point and string.format("Map %d  |  %.2f, %.2f",point.mapID,point.x*100,point.y*100) or "No verified map coordinates")
    local desc=""
    if gathering then
        local route=self.gatheringState and self.gatheringState.routes[self.gatheringState.activeKey]
        desc=point and ((self.gatheringState.activeKey or "Route").."  |  Stop "..tostring(self.routeIndex or 0).."/"..tostring(self.routeCount or 0).."\nSaved gathering locations; not live-detected resource nodes.") or "Generate a route in JuztLevel Gathering Map.\nOnly READY routes with valid context are followed."
        self.switchRouteButton.caption:SetText("Route: "..tostring(self.gatheringState and self.gatheringState.activeKey or "None"))
    else
        local targets=self:GetCurrentTargets()
        local primary
        for _,s in ipairs(targets) do if s.key==self.focusPrimary then primary=s;break end end
        primary=primary or targets[1]
        desc=primary and ((primary.name or "")..": "..clip(primary.action,104)) or "Select 1-2 learned primary professions below."
        local slots=self:GetPrimarySlots()
        for i,b in ipairs(self.primaryButtons) do
            local slot=slots[i]
            b:SetShown(slot~=nil)
            if slot then b.caption:SetText((self:IsPrimarySelected(slot.key) and "[x] " or "[ ] ")..clip(slot.name,22)) end
        end
    end
    if self.manual then desc="Manual destination override. /jt clear to resume JuztLevel."
    elseif self.external then desc="External provider: "..clip(self.external.id,42).."  |  Stop "..tostring(self.external.index).."/"..tostring(#self.external.points).."." end
    if travel then desc=travel.instruction or "Travel in progress" end
    self.infoMore:SetText(desc)
    self.showButton.caption:SetText(p.arrowShown and "Arrow: On" or "Arrow: Off")
    self.lockButton.caption:SetText(p.locked and "Locked" or "Unlocked")
    self.autoButton.caption:SetText(p.autoAdvance and "Auto: On" or "Auto: Off")
    self.arrivalLabel:SetText("Arrival: "..tostring(p.arrival).." yards")
    self.arrowSizeLabel:SetText("Pil: "..tostring(p.arrowSize).." px")
    self.textSizeLabel:SetText("Tekst under pil: "..tostring(p.textSize).." pt")
    self.footer:SetText("JuztLevel: "..clip(self:GetBridgeState(),41).."  |  /jt")
end
