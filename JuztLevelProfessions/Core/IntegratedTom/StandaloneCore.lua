local _, JLP = ...
local JT = JLP._integratedTom
-- Embedded namespace: never create a global standalone JuztTom addon.
JT.version = "0.1.0-alpha9-integrated-jlp"
JT.DEFAULT_ARRIVAL_YARDS = 5
JT.contract = "juzttom-navigation-api-v1"
JT.colors = {bg={0.009,0.030,0.052,0.96},alt={0.018,0.053,0.080,0.98},border={0.25,0.43,0.56,1},blue={0.00,0.57,0.92,1},gold={1,0.67,0.10,1},silver={0.91,0.95,0.98,1},muted={0.61,0.73,0.82,1}}
JT.asset = "Interface\\AddOns\\JuztLevelProfessions\\Assets\\JuztTom\\"
JT.elapsed = 0
JT.refreshInterval = 0.30
JT.motionInterval = 0.075
JT.settings = nil
JT.profile = nil
JT.mode = "GATHERING"
JT.auto = true

local function characterKey()
    local realm = type(GetRealmName)=="function" and GetRealmName() or "realm"
    local name = type(UnitName)=="function" and UnitName("player") or "character"
    return tostring(realm)..":"..tostring(name)
end
function JT:Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffdfe9f5JuztTom|r: "..tostring(message))
    end
end
function JT:Initialize()
    -- This is a module of JuztLevel, never a separate SavedVariables owner.
    local parent = JLP.DB
    if type(parent)~="table" then return false,"JLP_DB_NOT_READY" end
    parent.account=type(parent.account)=="table" and parent.account or {}
    parent.account.juztTom=type(parent.account.juztTom)=="table" and parent.account.juztTom or {}
    local db=parent.account.juztTom
    db.schema = 1
    db.characters=type(db.characters)=="table" and db.characters or {}
    local k=characterKey()
    db.characters[k]=type(db.characters[k])=="table" and db.characters[k] or {}
    self.profile=db.characters[k]
    local p=self.profile
    p.mode=p.mode=="CURRENT_STEP" and "CURRENT_STEP" or "GATHERING"
    p.selected=type(p.selected)=="table" and p.selected or {}
    self.focusPrimary=type(p.focusPrimary)=="string" and p.focusPrimary or nil
    -- A bounded, per-character list is a user-authored route, not source evidence.
    -- Keep all stops across /reload; the destination owner still arbitrates the
    -- one ACTIVE waypoint and must verify every explicit step selection.
    local old=type(p.manualRoute)=="table" and p.manualRoute or {}
    local points={}
    for i=1,math.min(#(type(old.points)=="table" and old.points or {}),100) do
        local item=old.points[i]
        if type(item)=="table" and self:ValidPoint(item.mapID,item.x,item.y) then
            points[#points+1]=self:CleanPoint(item.mapID,item.x,item.y,"Manual stop "..(#points+1),"MANUAL")
        end
    end
    if #points>0 then
        local index=math.floor(tonumber(old.index) or 1)
        p.manualRoute={points=points,index=math.max(1,math.min(#points,index))}
        self.userRoute=p.manualRoute
    else p.manualRoute=nil;self.userRoute=nil end
    -- Per-character arrival radius (in actual world-distance yards only).
    -- The alpha8-test1 default was 12 yd; alpha8-test2 defaults to 5 yd.
    -- One-time migration changes only the recognizable OLD DEFAULT (12).
    -- Other stored preferences (3..35) remain unchanged. An old user-selected
    -- value of exactly 12 cannot be distinguished from the old default.
    local arrival=tonumber(p.arrival)
    if not arrival or arrival~=arrival or arrival==math.huge or arrival==-math.huge then
        arrival=self.DEFAULT_ARRIVAL_YARDS
    end
    if p.arrivalDefaultRevision~=2 then
        if arrival==12 then arrival=self.DEFAULT_ARRIVAL_YARDS end
        p.arrivalDefaultRevision=2
    end
    p.arrival=math.max(3,math.min(35,arrival))
    -- Persist HUD typography and pointer dimensions per character.
    local a=tonumber(p.arrowSize)
    if not a or a~=a or a==math.huge or a==-math.huge then a=112 end
    p.arrowSize=math.floor(math.max(64,math.min(224,a))/8+0.5)*8
    local f=tonumber(p.textSize)
    if not f or f~=f or f==math.huge or f==-math.huge then f=13 end
    p.textSize=math.floor(math.max(10,math.min(26,f))+0.5)
    -- Alpha3 test: mutually exclusive art selections, smooth-motion presets.
    if p.arrowStyle~="classic" and p.arrowStyle~="updated" and p.arrowStyle~="clean" then p.arrowStyle="clean" end
    if p.motionPreset~="fast" and p.motionPreset~="balanced" and p.motionPreset~="gentle" then p.motionPreset="balanced" end
    if p.textStyle~="OUTLINE" and p.textStyle~="THICKOUTLINE" and p.textStyle~="NONE" then p.textStyle="OUTLINE" end
    p.smoothMotion=p.smoothMotion~=false
    p.showDistanceText=p.showDistanceText~=false
    p.showArrivalIndicator=p.showArrivalIndicator~=false
    p.arrowShown=p.arrowShown~=false
    p.locked=p.locked==true
    p.autoAdvance=p.autoAdvance~=false
    -- Current Step interzone travel is opt-out and controlled per character.
    p.autoTravelCurrentStep=p.autoTravelCurrentStep~=false
    p.arrowX=math.max(-1500,math.min(1500,tonumber(p.arrowX) or 0))
    p.arrowY=math.max(-1500,math.min(1500,tonumber(p.arrowY) or 175))
    p.panelX=tonumber(p.panelX) or 0
    p.panelY=tonumber(p.panelY) or 0
    self.mode=p.mode
    self.auto=p.autoAdvance
    self._motionAngle=nil
    self._motionHeading=nil
    self._motionTargetKey=nil
end
function JT:SetMode(mode)
    if mode~="GATHERING" and mode~="CURRENT_STEP" then return false,"INVALID_MODE" end
    self.mode=mode
    if self.profile then self.profile.mode=mode end
    self:Refresh(true)
    return true
end
function JT:ValidPoint(mapID,x,y)
    mapID,x,y=tonumber(mapID),tonumber(x),tonumber(y)
    if not mapID or mapID<1 or mapID==math.huge or mapID==-math.huge or
       mapID~=math.floor(mapID) or not x or not y or
       x==math.huge or x==-math.huge or y==math.huge or y==-math.huge then return false end
    return x==x and y==y and x>=0 and x<=1 and y>=0 and y<=1
end
function JT:CleanPoint(mapID,x,y,title,source)
    if not self:ValidPoint(mapID,x,y) then return nil end
    return {mapID=tonumber(mapID),x=tonumber(x),y=tonumber(y),title=tostring(title or "Waypoint"):sub(1,130),source=source}
end
function JT:SetWaypoint(mapID,x,y,title)
    local point=self:CleanPoint(mapID,x,y,title,"MANUAL")
    if not point then return false,"INVALID_COORDINATES" end
    self.manual=point
    self.external=nil
    self.lastExternalArrival=nil
    self:Refresh(true)
    return true
end
function JT:ClearWaypoint()
    self.manual=nil
    self.external=nil
    self.lastExternalArrival=nil
    self:Refresh(true)
end
-- Future integration surface: external producers submit a validated COPY of
-- a list of stops. The producer retains full ownership of its route state.
function JT:SetRoute(providerID,mapID,points,options)
    if type(providerID)~="string" or providerID=="" or #providerID>64 or
       type(points)~="table" or #points==0 or #points>1000 then return false,"INVALID_ROUTE" end
    local copy={}
    for i=1,#points do
        local p=points[i]
        if type(p)~="table" then return false,"INVALID_STOP" end
        local point=self:CleanPoint(mapID,p.x,p.y,p.title or ("Stop "..i),"EXTERNAL")
        if not point then return false,"INVALID_STOP" end
        copy[i]=point
    end
    options=type(options)=="table" and options or {}
    self.external={id=providerID,mapID=tonumber(mapID),points=copy,closed=options.closed==true,index=1}
    self.manual=nil
    self.lastExternalArrival=nil -- new provider run, even with a reused provider ID
    self:Refresh(true)
    return true
end
function JT:ClearRoute(providerID)
    if not self.external or (providerID and self.external.id~=providerID) then return false end
    self.external=nil
    self.lastExternalArrival=nil
    self:Refresh(true)
    return true
end
function JT:GetState()
    local t=self.current
    local base=self.underlyingTarget
    return {contract=self.contract,mode=self.mode,provider=t and t.source or "NONE",
        target=t and {mapID=t.mapID,x=t.x,y=t.y,title=t.title} or nil,
        baseTarget=base and {mapID=base.mapID,x=base.x,y=base.y,title=base.title} or nil,
        travel=self.travelOverlay and {phase=self.travelOverlay.phase,instruction=self.travelOverlay.instruction} or nil,
        routePosition=self.routeIndex,routeCount=self.routeCount,status=self.status,
        distanceYards=self.distanceYards,arrival=self.profile and self.profile.arrival}
end
function JT:Refresh(force)
    if self.UpdateNavigation then self:UpdateNavigation(force) end
    if self.RefreshUI then self:RefreshUI() end
end
function JT:CyclePrimary()
    local candidates=self:GetCurrentTargets()
    if #candidates==0 then return false end
    local nextIndex=1
    for i,c in ipairs(candidates) do
        if self.focusPrimary==c.key then nextIndex=i%#candidates+1;break end
    end
    self.focusPrimary=candidates[nextIndex].key
    self:Refresh(true)
    return true
end
function JT:Advance()
    -- A user-facing Next action must not advance a hidden underlying route
    -- while JuztTravel owns the temporary navigation overlay.
    if self.ReadTravelGuidance and self:ReadTravelGuidance() then return false,"TRAVEL_GUIDANCE_ACTIVE" end
    if self.manual then self.manual=nil
    elseif self.external then
        if self.external.index<#self.external.points then self.external.index=self.external.index+1
        elseif self.external.closed then self.external.index=1
        else self.external=nil end
    elseif self.mode=="GATHERING" then self:AdvanceGathering(true)
    else return self:CyclePrimary() end
    self:Refresh(true)
end
-- Safe standalone UI verification without an installed JuztLevel.
-- Deliberately synthetic coordinates, clearly labeled and never presented as nodes.
function JT:StartDemo()
    if self._demoRestore then
        if self.external and self.external.id=="juzttom-demo" then return true end
        self._demoRestore=nil -- demo was replaced by an independent source
    end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return false,"PLAYER_MAP_UNAVAILABLE" end
    local ok,map=pcall(C_Map.GetBestMapForUnit,"player")
    if not ok or not map then return false,"PLAYER_MAP_UNAVAILABLE" end
    local ready,pos=pcall(C_Map.GetPlayerMapPosition,map,"player")
    if not ready or not pos then return false,"PLAYER_POSITION_UNAVAILABLE" end
    local px,py
    local valid=pcall(function() px,py=pos:GetXY() end)
    if not valid or not self:ValidPoint(map,px,py) then return false,"PLAYER_POSITION_UNAVAILABLE" end
    local function clamp(v)return math.min(.96,math.max(.04,v)) end
    local stops={
        {x=clamp(px+.032),y=clamp(py-.018),title="DEMO ONLY - point A"},
        {x=clamp(px-.029),y=clamp(py-.034),title="DEMO ONLY - point B"},
        {x=clamp(px+.006),y=clamp(py+.045),title="DEMO ONLY - point C"},
    }
    self._demoRestore={manual=self.manual,external=self.external}
    local result,reason=self:SetRoute("juzttom-demo",map,stops,{closed=true})
    if not result then self._demoRestore=nil;return false,reason end
    return true
end
function JT:StopDemo()
    local previous=self._demoRestore
    if not previous then return false end
    self._demoRestore=nil
    if not (self.external and self.external.id=="juzttom-demo") then
        return false,"DEMO_REPLACED_BY_USER"
    end
    self.manual=previous.manual
    self.external=previous.external
    self.lastExternalArrival=nil
    self:Refresh(true)
    return true
end

-- User-facing JuztTom commands are registered by JuztLevel after its own
-- event owner initializes. The embedded module never registers ADDON_LOADED.
function JT:OpenSettings()
    if not self.profile then
        local ok,reason=self:Initialize()
        if ok==false then return false,reason end
    end
    if not self.panel then self:CreateUI() end
    if not self.designPanel then self:CreateDesignUI() end
    self.designPanel:Show()
    self:ShowDesignPage("Behaviour")
    return true
end
function JT:OpenPage(page)
    if not self.profile then
        local ok,reason=self:Initialize()
        if ok==false then return false,reason end
    end
    if not self.panel then self:CreateUI() end
    if not self.designPanel then self:CreateDesignUI() end
    self.designPanel:Show()
    self:ShowDesignPage(page or "Navigation")
    return true
end
JLP:RegisterModule("IntegratedJuztTom",JT)
