local _,JLP=...
-- Internal JuztTom-derived navigation renderer. It is updated solely by JLP's
-- existing Core event owner; it does not register addon events or SavedVariables.
local Tom=JLP._integratedTom
local HUD={contract="jlp-internal-tom-hud-v1",arrivalRadiusYards=5,enabled=true,
 motionPreset="balanced",style="clean",scale=1,showDistance=true,
  showStatus=true,locked=false,elapsed=0,nativeDispatchAllowed=false}
local pi,sqrt=math.pi,math.sqrt
local function finite(x) return type(x)=="number" and x==x and x~=math.huge and x~=-math.huge end
local function angle(y,x)
 if type(math.atan2)=="function" then return math.atan2(y,x) end
 if x>0 then return math.atan(y/x) end
 if x<0 then return math.atan(y/x)+(y>=0 and pi or -pi) end
 return y>0 and pi/2 or y<0 and -pi/2 or 0
end
local function xy(p)
 if type(p)~="table" then return nil end
 if type(p.GetXY)=="function" then return p:GetXY() end
 return p.x,p.y
end
local function world(id,x,y)
 if type(C_Map)~="table" or type(C_Map.GetWorldPosFromMapPos)~="function" or
   type(CreateVector2D)~="function" then return nil end
 local ok,instance,p=pcall(C_Map.GetWorldPosFromMapPos,id,CreateVector2D(x,y))
 if not ok or not instance or not p then return nil end
 local ok2,wx,wy=pcall(xy,p)
 if ok2 and finite(wx) and finite(wy) then return instance,wx,wy end
 return nil
end
-- Always obtain the player coordinate from the actual client map, never
-- reinterpret normalized coordinates from a microzone as destination-map XY.
-- C_Map world-space projections can bridge two UI maps ONLY when the game
-- reports the same world instance for both points.
function HUD:GetGeometry(point)
 if type(point)~="table" or type(point.mapID)~="number" or
    point.mapID<1 or point.mapID~=math.floor(point.mapID) or
    not finite(point.x) or not finite(point.y) or
    point.x<0 or point.x>1 or point.y<0 or point.y>1 then
     return nil,"INVALID_TARGET" end
 if type(C_Map)~="table" or type(C_Map.GetBestMapForUnit)~="function" or
   type(C_Map.GetPlayerMapPosition)~="function" then return nil,"POSITION_UNAVAILABLE" end
 local ok,map=pcall(C_Map.GetBestMapForUnit,"player")
 if not ok or type(map)~="number" or map<1 or map~=math.floor(map) then
   return nil,"POSITION_UNAVAILABLE" end
 local ok2,p=pcall(C_Map.GetPlayerMapPosition,map,"player")
 if not ok2 or not p then return nil,"POSITION_UNAVAILABLE" end
 local ok3,x,y=pcall(xy,p)
 if not ok3 or not finite(x) or not finite(y) or x<0 or x>1 or y<0 or y>1 then
  return nil,"POSITION_UNAVAILABLE" end
 local a,ax,ay=world(map,x,y)
 local b,bx,by=world(point.mapID,point.x,point.y)
 if a==nil or b==nil or a~=b then
   return {direction=nil,distanceYards=nil,instanceVerified=false,
      mapID=map,pointMapID=point.mapID,positionAvailable=false},
      "WORLD_INSTANCE_UNVERIFIED"
 end
 local dx,dy=bx-ax,by-ay
 local heading=angle(-dx,-dy)
 if heading<0 then heading=heading+2*pi end
 return {direction=heading,distanceYards=sqrt(dx*dx+dy*dy),instanceVerified=true,
  mapID=map,pointMapID=point.mapID,crossMap=(map~=point.mapID),
  positionAvailable=true,terrainVerified=false,etaVerified=false}
end
function HUD:SetArrowStyle(style)
 if style~="classic" and style~="updated" and style~="clean" then return false,"UNKNOWN_STYLE" end
 self.style=style
 if self.arrowTexture then
  self.arrowTexture:SetTexture("Interface\\AddOns\\JuztLevelProfessions\\Assets\\Navigation\\arrow_"..style..".tga")
 end
 return true
end
function HUD:SetArrivalRadius(yards)
 if not finite(yards) or yards<3 or yards>35 then return false,"INVALID_RADIUS" end
 self.arrivalRadiusYards=yards;return true
end
function HUD:SetScale(value)
 if not finite(value) or value<0.75 or value>1.35 then return false,"INVALID_SCALE" end
 self.scale=value
 self:FitToViewport()
 return true
end
-- Responsive HUD scale is a presentation limit, not a saved preference.
-- Refit without moving a HUD which the player deliberately dragged.
function HUD:FitToViewport()
 local f=self.frame
 if not f or not UIParent then return false,"HUD_NOT_INITIALIZED" end
 local w=UIParent.GetWidth and UIParent:GetWidth() or nil
 local h=UIParent.GetHeight and UIParent:GetHeight() or nil
 if not finite(w) or not finite(h) or w<1 or h<1 then
    return false,"VIEWPORT_UNKNOWN" end
 local usableW=math.max(1,w-24)
 local usableH=math.max(1,h-24)
 local limited=math.min(self.scale,usableW/198,usableH/204)
 if limited<0.40 then return false,"VIEWPORT_TOO_SMALL" end
 self.renderedScale=limited
 if f.SetScale then f:SetScale(limited) end
 if f.SetClampedToScreen then f:SetClampedToScreen(true) end
 if not self.manuallyPositioned and f.ClearAllPoints and f.SetPoint then
    f:ClearAllPoints()
    f:SetPoint("CENTER",UIParent,"CENTER",0,math.min(175,math.max(0,(h-204*limited)/2-10)))
 end
 return true,limited
end
function HUD:ResetPosition()
 self.manuallyPositioned=false
 return self:FitToViewport()
end
function HUD:SetMotionPreset(value)
 if value~="balanced" and value~="smooth" and value~="instant" then return false,"INVALID_MOTION" end
 self.motionPreset=value;return true
end
function HUD:SetLocked(value)
 if type(value)~="boolean" then return false,"INVALID_LOCK" end
 self.locked=value
 if self.frame then self.frame:SetMovable(not value) end
 return true
end
function HUD:SetVisible(value)
 if type(value)~="boolean" then return false,"INVALID_VISIBILITY" end
 self.enabled=value
 if value==false and self.frame then self.frame:Hide() end
 return true
end
function HUD:SetDistanceVisible(value)
 if type(value)~="boolean" then return false,"INVALID_DISTANCE_VISIBILITY" end
 self.showDistance=value;return true
end
function HUD:SetStatusVisible(value)
 if type(value)~="boolean" then return false,"INVALID_STATUS_VISIBILITY" end
 self.showStatus=value;return true
end
-- Settings are deliberately session-local; no second SavedVariables contract.
function HUD:GetSettings()
 return {style=self.style,scale=self.scale,locked=self.locked,
   arrivalRadiusYards=self.arrivalRadiusYards,motionPreset=self.motionPreset,
   showDistance=self.showDistance,showStatus=self.showStatus,enabled=self.enabled,
   persistence="JLP_SAVED_VARIABLES",nativeDispatchAllowed=false}
end
function HUD:CycleStyle()
 local nextStyle=self.style=="clean" and "classic" or self.style=="classic" and "updated" or "clean"
 return self:SetArrowStyle(nextStyle)
end
function HUD:SelectGathering(profession)
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not origin or not owner then return false,"PLAYER_MAP_UNAVAILABLE" end
 return owner:SelectGatheringStop(origin.mapID,profession,1)
end
function HUD:Initialize()
 if self.initialized then return true end
 if type(CreateFrame)~="function" or not UIParent then return false,"UI_UNAVAILABLE" end
 local w=UIParent.GetWidth and UIParent:GetWidth() or nil
 local h=UIParent.GetHeight and UIParent:GetHeight() or nil
 if not finite(w) or not finite(h) or w<24+198*.40 or h<24+204*.40 then
   return false,"VIEWPORT_TOO_SMALL" end
 local f=CreateFrame("Frame",nil,UIParent)
 f:SetSize(198,204);f:SetPoint("CENTER",UIParent,"CENTER",0,175)
 f:SetFrameStrata("MEDIUM");f:EnableMouse(true)
 f:SetMovable(not self.locked);f:RegisterForDrag("LeftButton")
 if f.SetClampedToScreen then f:SetClampedToScreen(true) end
 f:SetScript("OnDragStart",function(frame) if not HUD.locked then frame:StartMoving() end end)
 f:SetScript("OnDragStop",function(frame)
    frame:StopMovingOrSizing()
    HUD.manuallyPositioned=true
 end)
 local bg=f:CreateTexture(nil,"BACKGROUND")
 bg:SetAllPoints();bg:SetColorTexture(.009,.030,.052,.84)
 if type(Tom.SkinThemePanel)=="function" then Tom:SkinThemePanel(f,"secondary") end
 local arrow=f:CreateTexture(nil,"ARTWORK")
 arrow:SetSize(104,104);arrow:SetPoint("TOP",f,"TOP",0,-8)
 self.arrowTexture=arrow;self:SetArrowStyle(self.style)
 local label=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 label:SetPoint("BOTTOM",f,"BOTTOM",0,50);label:SetWidth(192)
 self.label=label
 local status=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 status:SetPoint("BOTTOM",f,"BOTTOM",0,32);status:SetWidth(192)
 self.statusText=status
 local stop=CreateFrame("Button",nil,f)
 stop:SetSize(48,16);stop:SetPoint("TOPLEFT",f,"TOPLEFT",2,-2)
 local stopLabel=stop:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 stopLabel:SetAllPoints();stopLabel:SetText("Stop")
 stop:SetScript("OnClick",function() local o=JLP:GetModule("IntegratedDestinationOwner");if o then o:Stop("HUD_STOP") end end)
 local function action(caption,x,width,fn)
    local button=CreateFrame("Button",nil,f)
    button:SetSize(width or 58,21);button:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",x,6)
    local label=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    label:SetAllPoints();label:SetText(caption)
    local bg=button:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints()
    bg:SetColorTexture(.03,.19,.27,.93)
    button:SetScript("OnClick",fn)
    return button
 end
 action("Pause",4,55,function()
     local o=JLP:GetModule("IntegratedDestinationOwner")
     if o then o:Pause() end
 end)
 action("Resume",60,58,function()
     local o=JLP:GetModule("IntegratedDestinationOwner")
     if o then o:Resume() end
 end)
 action("Style",120,72,function() HUD:CycleStyle() end)
 f:SetScript("OnMouseUp",function(_,button)
     if button=="RightButton" then HUD:CycleStyle() end
 end)
 self.frame=f;self.initialized=true
 local fitted=self:FitToViewport()
 if not fitted then self.initialized=false;f:Hide();return false,"VIEWPORT_TOO_SMALL" end
 f:Hide();return true
end
-- One HUD for all navigation owners. A qualified target may have a safe
-- direct bearing even without a *routable* transport graph. That compass is
-- advisory, never an assertion of terrain/path or native transport access.
function HUD:Refresh(elapsed)
 -- P0-A correction: the actual, character-bound C_Map observation is
 -- authoritative for advisory presentation. Source build is provenance,
 -- not a blanket client-version permission (native permissions remain separate).
 local capabilities=JLP:GetModule("NavigationCapabilityEvidence")
 local qualified,reason,proof=false,"NAVIGATION_CAPABILITY_UNAVAILABLE",nil
 if capabilities and type(capabilities.Check)=="function" then
   local ok,allowed,why,observed=pcall(capabilities.Check,capabilities,"POSITION")
   if ok then qualified=allowed==true;reason=why or "NAVIGATION_CAPABILITY_UNKNOWN";proof=observed
   else reason="NAVIGATION_CAPABILITY_ERROR" end
 end
 if not qualified then
   if self.frame then self.frame:Hide() end
   self.lastGeometry=nil;self.lastArrowReason=reason
   return false,reason
 end
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 local state=owner and owner:GetSnapshot() or nil
 -- An owner intent cannot be rendered for another character/faction/class
 -- merely because the new character also has a valid C_Map position.
 if type(state)=="table" and state.point and
    ((state.characterKey~=nil and (type(proof)~="table" or proof.characterKey~=state.characterKey)) or
     (state.faction~=nil and (type(proof)~="table" or proof.faction~=state.faction)) or
     (state.classToken~=nil and (type(proof)~="table" or proof.classToken~=state.classToken))) then
   if self.frame then self.frame:Hide() end
   self.lastGeometry=nil;self.lastArrowReason="STALE_CHARACTER_CONTEXT"
   return false,"STALE_CHARACTER_CONTEXT"
 end
 if not state or not state.point or not self.enabled then
  if self.frame then self.frame:Hide() end
  self.lastGeometry=nil;self.lastArrowReason="NO_VISIBLE_DESTINATION"
  return false,"NO_VISIBLE_DESTINATION"
 end
 if not self.initialized then
  local ok,why=self:Initialize()
  if not ok then self.lastArrowReason=why;return false,why end
 end
 local fitted,fitReason=self:FitToViewport()
 if not fitted then
  if self.frame then self.frame:Hide() end
  self.lastArrowReason=fitReason;return false,fitReason
 end
 local gatheringReference=state.category=="GATHERING" and state.status=="DESTINATION_ONLY" and
   state.sourceStatus=="PARTIAL" and type(state.contextToken)=="string"
 local travel=JLP:GetModule("IntegratedTravelEngine")
 local guidance=(travel and travel.GetGuidance and state.route and travel:GetGuidance()) or nil
 local phase=guidance and guidance.phase
 local waiting=phase=="WAIT_FOR_TRANSPORT" or phase=="TRANSFER_ARRIVAL"
 local inTransit=phase=="IN_TRANSIT"
 local finished=phase=="ARRIVED"
 local permitted=state.status=="AVAILABLE" or
   (state.status=="DESTINATION_ONLY" and (gatheringReference or state.sourceStatus=="DESTINATION_ONLY"))
 local ready=permitted and not inTransit and not finished
 local compassOnly=state.route==nil and not gatheringReference
 local legWaypoint=state.point
 if ready and phase=="WALK_TO_WAYPOINT" and guidance.waypoint then
   legWaypoint=guidance.waypoint
 elseif ready and waiting then
   -- Guide toward the known *departure* platform, NOT the arrival map.
   legWaypoint=guidance.from or state.point
 end
 local geo,why=nil,nil
 if ready then geo,why=self:GetGeometry(legWaypoint) end
 -- Arrival is evaluated only by the engine and only for a qualified WALK leg.
 -- A direct bearing or a boarding platform can never complete a journey.
 if ready and phase=="WALK_TO_WAYPOINT" and geo and geo.instanceVerified and
    geo.distanceYards and geo.distanceYards<=self.arrivalRadiusYards and travel and
    travel.ObserveVerifiedPosition then
     travel:ObserveVerifiedPosition(nil,nil,self.arrivalRadiusYards)
     guidance=travel:GetGuidance()
     phase=guidance and guidance.phase
     finished=phase=="ARRIVED"
     if finished then ready=false end
 end
 self.frame:Show()
 self.label:SetText((legWaypoint and legWaypoint.label and legWaypoint.label~="" and legWaypoint.label) or
   state.point.label or "Destination")
 if not ready then
   self.arrowTexture:Hide()
   self.lastArrowReason=state.status=="STALE" and "STALE_CONTEXT" or
      state.status=="PAUSED" and "PAUSED" or inTransit and "IN_TRANSIT" or
      finished and "ARRIVED" or "NO_ACTIVE_GUIDANCE"
   self.statusText:SetText(state.status=="STALE" and "STALE · revalidation required" or
       state.status=="PAUSED" and "PAUSED" or
       inTransit and "IN TRANSIT · arrival not verified" or
       finished and "ARRIVED · guidance only" or "Guidance awaiting verification")
 elseif not geo or geo.instanceVerified~=true or type(geo.direction)~="number" then
   self.arrowTexture:Hide();self.lastArrowReason=why or "WORLD_GEOMETRY_UNKNOWN"
   self.statusText:SetText(self.lastArrowReason)
 else
   local playerFacing
   if type(GetPlayerFacing)=="function" then
     local ok,facing=pcall(GetPlayerFacing)
     if ok and finite(facing) then playerFacing=facing end
   end
   if playerFacing then
     self._heading=Tom:MotionStep(self._heading,geo.direction-playerFacing,elapsed or .1,
       self.motionPreset,true)
     local ok=type(self.arrowTexture.SetRotation)=="function" and
       pcall(self.arrowTexture.SetRotation,self.arrowTexture,self._heading or 0)
     if ok then
       self.arrowTexture:Show();self.lastArrowReason="WORLD_VERIFIED_BEARING"
     else
       self.arrowTexture:Hide();self.lastArrowReason="ARROW_ROTATION_UNAVAILABLE"
     end
   else
     self.arrowTexture:Hide();self.lastArrowReason="PLAYER_FACING_UNAVAILABLE"
   end
   local distance=geo.distanceYards and string.format("%.0f yd",geo.distanceYards) or "distance UNKNOWN"
   if gatheringReference then
     self.statusText:SetText("Gathering reference · "..distance.." · terrain UNKNOWN")
   elseif waiting then
     self.statusText:SetText("Transport departure · "..distance.." · board manually")
   elseif compassOnly then
     self.statusText:SetText("DIRECT BEARING · route UNKNOWN · "..distance)
   elseif not self.showDistance then
     self.statusText:SetText("Navigation guidance · terrain UNKNOWN")
   else
     self.statusText:SetText(distance.." · terrain UNKNOWN")
   end
 end
 if self.statusText and self.statusText.SetShown then self.statusText:SetShown(self.showStatus==true) end
 self.lastGeometry=geo;self.lastOwnerStatus=state.status
 return true,self.lastArrowReason
end
function HUD:GetSnapshot()
 local geo=self.lastGeometry
 return {contract=self.contract,style=self.style,arrivalRadiusYards=self.arrivalRadiusYards,
   scale=self.scale,renderedScale=self.renderedScale,motionPreset=self.motionPreset,
   locked=self.locked,enabled=self.enabled,
   showDistance=self.showDistance,showStatus=self.showStatus,settingsPersistence="JLP_SAVED_VARIABLES",
   distanceYards=geo and geo.distanceYards or nil,
   distanceVerified=geo and geo.instanceVerified==true or false,
   status=self.lastOwnerStatus or "UNKNOWN",arrowReason=self.lastArrowReason or "NOT_REFRESHED",
   bearingAvailable=geo and geo.instanceVerified==true and finite(geo.direction) or false,
   crossMapBearing=geo and geo.crossMap==true or false,
   terrainVerified=false,nativeDispatchAllowed=false}
end
JLP:RegisterModule("IntegratedNavigationHUD",HUD)
