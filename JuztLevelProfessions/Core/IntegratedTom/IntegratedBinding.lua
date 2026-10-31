local _,JLP=...
local JT=JLP._integratedTom
local function module(id) return JLP:GetModule(id) end
local function copyTarget(point,category)
 if type(point)~="table" then return nil end
 local t=JT:CleanPoint(point.mapID,point.x,point.y,point.label or category or "Destination",category or "JLP_OWNER")
 if t then t.zone=point.zone end
 return t
end
local function validOwner()
 local owner=module("IntegratedDestinationOwner")
 local s=owner and owner.GetSnapshot and owner:GetSnapshot()
 if type(s)~="table" then return nil end
 if s.status=="PAUSED" or s.status=="STALE" or s.status=="STOPPED" then return s,false end
 local permitted=s.status=="AVAILABLE" or s.status=="DESTINATION_ONLY"
 if not permitted then return s,false end
 if s.category=="GATHERING" and (s.sourceStatus~="PARTIAL" or s.needsRevalidation) then
  return s,false
 end
 return s,s.point~=nil and s.needsRevalidation~=true
end
-- A Gathering selection is a deliberate source switch, not just a visual
-- mode toggle. Validate the READY Gathering Map receipt before replacing a
-- previously explicit Current Step/manual destination. The route itself stays
-- in GatheringRouteService; JuztTom never imports it into a manual route list.
function JT:ActivateGatheringNavigation()
 -- Do not persist a new display mode until the single destination owner
 -- has admitted the gathering stop. A denied selection must leave an
 -- existing explicit manual / Current Step arrow visible and actionable.
 local gathering,why=self:SyncGathering()
 local route=gathering and gathering.routes and gathering.routes[gathering.activeKey]
 local stop=route and route.points and route.points[route.index or 1]
 if not stop then
   self.gatheringActionFeedback=why or "GENERATE_ROUTE_IN_GATHERING_MAP"
   self:Refresh(true)
   return false,self.gatheringActionFeedback
 end
 local owner=module("IntegratedDestinationOwner")
 if not owner or type(owner.GetGatheringGuidance)~="function" or
    type(owner.SelectGatheringStop)~="function" then
   self.gatheringActionFeedback="GATHERING_OWNER_UNAVAILABLE"
   self:Refresh(true);return false,self.gatheringActionFeedback
 end
 local receipt,reason=owner:GetGatheringGuidance(stop.mapID)
 if not receipt or receipt.status~="READY" or receipt.routeNavigationReady~=true then
   self.gatheringActionFeedback=reason or (receipt and receipt.overlayStatus) or "GATHERING_ROUTE_NOT_READY"
   self:Refresh(true);return false,self.gatheringActionFeedback
 end
 -- Atomic explicit source switch. Do not discard the old destination if a
 -- READY gathering route fails admission; the owner commits it or leaves
 -- the previous source and its visible arrow untouched.
 local ok,reason=owner:SelectGatheringStop(stop.mapID,gathering.activeKey,route.index or 1,{explicit=true})
 if ok then
   self.manual=nil;self.external=nil
   self.lastArrived=nil;self.gatheringActionFeedback=nil
   self:SetMode("GATHERING") -- Persist ONLY after authoritative acceptance.
 else
   self.gatheringActionFeedback=reason or "GATHERING_SELECTION_FAILED"
   self:Refresh(true)
 end
 return ok,reason
end
-- A manually selected next gathering stop is submitted to the single owner;
-- gathering route lists remain under Gathering Map, never JuztTom Routes.
function JT:AdvanceSelectedGathering()
 if self.mode~="GATHERING" then return false,"WRONG_MODE" end
 local gathering,why=self:SyncGathering()
 local route=gathering and gathering.routes and gathering.routes[gathering.activeKey]
 if not route or not route.points or #route.points==0 then return false,why or "NO_GATHERING_ROUTE" end
 local nextIndex=(route.index or 1)+1
 if nextIndex>#route.points then
    if route.closed then nextIndex=1 else return false,"ROUTE_COMPLETE" end
 end
 local owner=module("IntegratedDestinationOwner")
 local ok,reason=owner and owner:SelectGatheringStop(route.points[nextIndex].mapID,gathering.activeKey,nextIndex)
 if not ok then return false,reason or "GATHERING_SELECTION_FAILED" end
 route.index=nextIndex;route.done=false;self.lastArrived=nil
 self:Refresh(true)
 return true
end

-- Current Step targets cannot bypass JLP's canonical source qualification.
function JT:ActiveCurrentStep()
 return nil,"SELECT_CURRENT_STEP_IN_JUZTLEVEL"
end
-- JLP already synchronizes the step to its single destination owner.
function JT:SyncCurrentStepTravel()
 self._autoTravelStatus="JLP_DESTINATION_OWNER"
 return false
end
function JT:ReadTravelGuidance()
 local s,allowed=validOwner()
 if not allowed then return nil end
 local engine=module("IntegratedTravelEngine")
 -- No JuztTom-specific routing for any navigation mode. The exact same
 -- JuztTravel guidance contract drives manual, Current Step and Gathering.
 local g=engine and engine.GetNavigationGuidance and
     engine:GetNavigationGuidance(s.point,s.route~=nil) or nil
 if type(g)~="table" or g.phase=="IDLE" or g.phase=="ARRIVED" then return nil end
 local p=g.waypoint
 if g.phase=="WALK_TO_WAYPOINT" and type(p)~="table" then return nil end
 local owner=module("IntegratedDestinationOwner")
 local source=owner and owner.resumeSource
 local zone=s.category=="CURRENT_STEP"and source and source.fishingApproach==true and source.zoneApproach==true
 return {phase=g.phase,instruction=tostring(g.instruction or ""):sub(1,400),
    waypoint=copyTarget(p,"JUZTTRAVEL"),index=g.index,total=g.total,
    stage=g.stage,transport=g.transport,active=true,
    transportEdgeID=g.transportEdgeID,
    displayTitle=zone and ("Zone approach: "..tostring(source.zone))or type(g.displayTitle)=='string' and g.displayTitle or nil,
    displayDetail=zone and "Not a species/pool/cast point. Find safe water in the documented area manually; arrival is not a catch or quest receipt."or type(g.displayDetail)=='string' and g.displayDetail or nil,
    nextFlightDestination=type(g.nextFlightDestination)=='string' and g.nextFlightDestination or nil,
    routeVerified=g.routeVerified~=false and s.route~=nil,
    confidence=g.confidence,autoAdvance=g.autoAdvance~=false}
end
function JT:TravelStatusTitle(travel)
 local names={DIRECT_BEARING="Direct bearing (not a dungeon route)",WALK_TO_WAYPOINT="Follow travel marker",WAIT_FOR_TRANSPORT="Wait for transport",
    IN_TRANSIT="Transport in progress",TRANSFER_ARRIVAL="Transport arrival",
    ENTER_DESTINATION_CITY="Enter destination",EXIT_SOURCE_CITY="Leave the city"}
 return travel and (names[travel.phase] or "Travel guidance") or "Travel guidance"
end
-- The travel engine and arrival gates retain the strict world-instance
-- verifier in IntegratedNavigationHUD. A JuztTom *visual-only* compass may use
-- same-map normalized coordinates when world positions are unavailable.
-- Map-relative values are never in yards and never certify arrival/transport.
local function finite(v)
 return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function currentPlayerMap()
 if type(C_Map)~="table" or type(C_Map.GetBestMapForUnit)~="function" then return nil end
 local ok,id=pcall(C_Map.GetBestMapForUnit,"player")
 if ok and finite(id) and id>0 and id==math.floor(id) then return id end
 return nil
end
local function sameMapFallback(point)
 local map=currentPlayerMap()
 if not point or map~=point.mapID or
    type(C_Map.GetPlayerMapPosition)~="function" then return nil end
 local ok,p=pcall(C_Map.GetPlayerMapPosition,map,"player")
 if not ok or not p then return nil end
 local good,x,y=pcall(function()
  if type(p.GetXY)=="function" then return p:GetXY() end
  return p.x,p.y
 end)
 if not good or not finite(x) or not finite(y) or x<0 or x>1 or y<0 or y>1 then return nil end
 local dx,dy=point.x-x,point.y-y
 local width,height=1,1
 if type(C_Map.GetMapWorldSize)=="function" then
   local got,w,h=pcall(C_Map.GetMapWorldSize,map)
   if got and finite(w) and finite(h) and w>0 and h>0 then width,height=w,h end
 end
 dx,dy=dx*width,dy*height
 local a=math.atan2
 local angle
 if type(a)=="function" then angle=a(-dx,-dy)
 elseif -dy>0 then angle=math.atan(-dx/-dy)
 elseif -dy<0 then angle=math.atan(-dx/-dy)+((-dx)>=0 and math.pi or -math.pi)
 else angle=(-dx)>0 and math.pi/2 or (-dx)<0 and -math.pi/2 or 0 end
 return {positionAvailable=true,direction=angle%(2*math.pi),
    distanceMap=math.sqrt((point.x-x)^2+(point.y-y)^2),
    distanceYards=nil,mapID=map,crossMap=false,instanceVerified=false,
    status="SAME_MAP_BEARING_ONLY",approximate=true}
end
function JT:GetGeometry(point)
 local hud=module("IntegratedNavigationHUD")
 local g=hud and hud.GetGeometry and hud:GetGeometry(point)
 if g and g.instanceVerified==true and finite(g.direction) then
  return {positionAvailable=true,direction=g.direction,
   distanceYards=g.distanceYards,mapID=g.mapID,crossMap=g.crossMap,
   instanceVerified=true,status="WORLD_VERIFIED"}
 end
 local fallback=sameMapFallback(point)
 if fallback then return fallback end
 return {positionAvailable=false,mapID=currentPlayerMap(),
   pointMapID=point and point.mapID or nil,
   status=g and "WORLD_INSTANCE_UNVERIFIED" or "PLAYER_POSITION_UNAVAILABLE"}
end
-- Shared JLP owner takes priority over an autonomous (unqualified) step. The
-- standalone UI and external/manual route controls remain available, but an
-- explicit JLP-selected destination is not silently replaced by a UI refresh.
local standaloneUpdate=JT.UpdateNavigation
function JT:UpdateNavigation(force)
 standaloneUpdate(self,force)
 -- The shared P0-A evidence service validates live character/map/XY;
 -- no standalone or historical source-build grant of presentation authority.
 local capabilities=module("NavigationCapabilityEvidence")
 local qualified,reason,proof=false,"NAVIGATION_CAPABILITY_UNAVAILABLE",nil
 if capabilities and type(capabilities.Check)=="function" then
    local ok,allowed,why,observed=pcall(capabilities.Check,capabilities,"POSITION")
    if ok then qualified=allowed==true;reason=why or "NAVIGATION_CAPABILITY_UNKNOWN";proof=observed
    else reason="NAVIGATION_CAPABILITY_ERROR" end
 end
 if not qualified then
    self.current=nil;self.geometry=nil;self.distanceYards=nil
    self.travelOverlay=nil;self.status=reason
    return
 end
 local state,permitted=validOwner()
 if type(state)=="table" and state.point and
    ((state.characterKey~=nil and (type(proof)~="table" or proof.characterKey~=state.characterKey)) or
     (state.faction~=nil and (type(proof)~="table" or proof.faction~=state.faction)) or
     (state.classToken~=nil and (type(proof)~="table" or proof.classToken~=state.classToken))) then
    self.current=nil;self.geometry=nil;self.distanceYards=nil
    self.travelOverlay=nil;self.status="STALE_CHARACTER_CONTEXT"
    return
 end
 -- The mode is an explicit SOURCE choice. Never keep displaying the old
 -- Current Step arrow while Gathering is selected (or vice versa).
 if self.mode=="GATHERING" and (not state or state.category~="GATHERING") and
    not self._demoRestore then
    self.current=nil;self.geometry=nil;self.distanceYards=nil
    self.travelOverlay=nil;self.underlyingTarget=nil
    self.routeIndex=nil;self.routeCount=nil
    self.status=self.gatheringActionFeedback or "NO_GATHERING_ROUTE"
    return
 end
 if self.mode=="CURRENT_STEP" and state and state.category=="GATHERING" and
    not self._demoRestore then
    self.current=nil;self.geometry=nil;self.distanceYards=nil
    self.travelOverlay=nil;self.underlyingTarget=nil
    self.routeIndex=nil;self.routeCount=nil
    self.status="SELECT_CURRENT_STEP_IN_JUZTLEVEL"
    return
 end
 -- Keep the one authoritative owner aligned when a generated gathering route
 -- advances to its next point. Do not modify owner while paused or stale.
 if self.mode=="GATHERING" and state and state.category=="GATHERING" and
    permitted and not self._demoRestore and self.gatheringState then
   local gathering=self.gatheringState
   local route=gathering.routes and gathering.routes[gathering.activeKey]
   local waypoint=route and route.points and route.points[route.index or 1]
   if waypoint and (not state.point or state.point.mapID~=waypoint.mapID or
      state.point.x~=waypoint.x or state.point.y~=waypoint.y) then
      local owner=module("IntegratedDestinationOwner")
      if owner and owner.SelectGatheringStop then
         local ok=owner:SelectGatheringStop(waypoint.mapID,gathering.activeKey,route.index or 1)
         if ok then state,permitted=validOwner() end
      end
   end
 end
 if not state or not permitted or self._demoRestore then
    if state and (state.status=="STALE" or state.status=="PAUSED" or state.status=="STOPPED") then
       self.current=nil;self.geometry=nil;self.distanceYards=nil
       self.travelOverlay=nil;self.status="JLP_"..state.status
    end
    return
 end
 local target=copyTarget(state.point,state.category)
 if not target then
    -- A previously drawn arrow must not survive an invalid owner waypoint.
    self.current=nil;self.geometry=nil;self.distanceYards=nil
    self.travelOverlay=nil;self.status="INVALID_TARGET"
    return
 end
 local overlay=self:ReadTravelGuidance()
 self.underlyingTarget=target
 self.travelOverlay=overlay
 local point=target
 if overlay then
     -- All advisory stages own their visual arrow state. A text-only city
     -- transition MUST NOT fall back to the final trainer's remote map.
     point=overlay.waypoint
 end
 self.current=point
 self.geometry=point and self:GetGeometry(point) or nil
 self.distanceYards=self.geometry and self.geometry.distanceYards or nil
 self.routeIndex=overlay and overlay.index or nil
 self.routeCount=overlay and overlay.total or nil
 if not overlay and state.category=="GATHERING" and self.gatheringState then
    local gathering=self.gatheringState
    local route=gathering.routes and gathering.routes[gathering.activeKey]
    if route then self.routeIndex,self.routeCount=route.index,#route.points end
 end
 if not overlay and self.userRoute and state.category=="MANUAL" and
    self.userRoute.points[self.userRoute.index] and
    self.userRoute.points[self.userRoute.index].mapID==target.mapID and
    self.userRoute.points[self.userRoute.index].x==target.x and
    self.userRoute.points[self.userRoute.index].y==target.y then
    self.routeIndex=self.userRoute.index
    self.routeCount=#self.userRoute.points
 end
 self.activeTargetKey=point and (tostring(state.generation).."|"..tostring(point.mapID).."|"..tostring(point.x).."|"..tostring(point.y)) or nil
 if overlay and not point then self.status="TRAVEL_"..tostring(overlay.phase)
 elseif not point then self.status="NO_WAYPOINT"
 elseif not self.geometry or not self.geometry.positionAvailable then self.status="TRAVEL_TO_DESTINATION_MAP"
 elseif overlay and overlay.phase=="ENTER_DESTINATION_CITY" and overlay.routeVerified==false then
     -- Reaching an approximate entrance marker does not equal entering the city.
     self.status="CITY_INGRESS_REFERENCE_ONLY"
 elseif self.distanceYards and self.profile and self.distanceYards<=self.profile.arrival then self.status="AT_WAYPOINT"
 elseif self.geometry and self.geometry.approximate then self.status="MAP_RELATIVE_DIRECTION"
 else self.status="NAVIGATING" end
end
-- A user manually entering coordinates through JuztTom must use the same
-- owner admission boundary as every other JLP navigation consumer.
local originalWaypoint=JT.SetWaypoint
function JT:SetWaypoint(mapID,x,y,title)
 local point=self:CleanPoint(mapID,x,y,title,"MANUAL")
 if not point then return false,"INVALID_COORDINATES" end
 local owner=module("IntegratedDestinationOwner")
 if not owner then return false,"OWNER_UNAVAILABLE" end
 local ok,why=owner:NavigateTo("MANUAL",{
    nav={mapID=point.mapID,x=point.x,y=point.y,mapDomain="UI_MAP_ID",evidence="EXPLICIT_USER_ENTERED_COORDINATES"},
    name=point.title},{explicit=true,owner="JuztTom"})
 if not ok then return false,why end
 return originalWaypoint(self,mapID,x,y,title)
end
local originalClear=JT.ClearWaypoint
function JT:ClearWaypoint()
 local owner=module("IntegratedDestinationOwner")
 local state=owner and owner:GetSnapshot()
 if state and state.category=="MANUAL" and state.owner=="JuztTom" then owner:Stop("JUZTTOM_MANUAL_CLEAR") end
 return originalClear(self)
end
function JT:GetIntegrationStatus()
 local state=module("IntegratedDestinationOwner")
 local current=state and state:GetSnapshot() or nil
 local travel=module("IntegratedTravelEngine")
 local graph=travel and travel.GetGraphStatus and travel:GetGraphStatus() or nil
 return {provider="JuztLevel Internal",travel="Integrated",ownerStatus=current and current.status,
   ownerCategory=current and current.category,transportGraph=graph and graph.status,
   currentMap=current and current.point and current.point.mapID}
end

-- Explicit profession changes must not leave a different profession's
-- TRAINER/Current Step arrow (or its saved reload checkpoint) active when the
-- newly selected profession has no navigable step. Do not touch manual,
-- gathering, bank or auction-house destinations in this path.
function JT:ClearObsoleteProfessionDestination(previousProfession,newProfession)
 if previousProfession==nil or previousProfession==newProfession then return false end
 local owner=module("IntegratedDestinationOwner")
 local state=owner and owner.GetSnapshot and owner:GetSnapshot()
 if not state or not state.point or not (
      state.category=="TRAINER" or state.category=="CURRENT_STEP" or
      state.category=="RECIPE_SOURCE" or state.category=="VENDOR" or
      state.category=="CRAFT_STATION") then return false end
 -- User explicitly changed the active profession; this is not a background
 -- planner refresh. Preserve independent manual and gathering workspaces.
 -- Changing focus without a navigable Current Step is not a user Stop.
 -- Release only the obsolete profession source; retain manual/gathering.
 owner:Invalidate("PROFESSION_FOCUS_NO_DESTINATION")
 self.manual=nil;self.external=nil;self.travelOverlay=nil
 self.current=nil;self.geometry=nil;self.distanceYards=nil
 self.currentStepActionFeedback="NO_NAVIGABLE_STEP_FOR_"..tostring(newProfession)
 return true
end

-- A user-initiated profession selection is an actual navigation request,
-- including the FIRST click while Gathering is active. Admission precedes
-- the mode change so unsuccessful selection preserves an existing Gathering
-- session; a successful Current Step request replaces its active owner through
-- the SAME JuztTravel engine used by every other navigation producer.
-- Never fabricate a route from the on-screen action description alone.
function JT:ActivateCurrentStepTarget(professionKey,previousProfession)
 local planner=module("Planner")
 local actions=module("IntegratedNavigationActions")
 if not planner or not actions then return false,"CURRENT_STEP_SERVICES_UNAVAILABLE" end
 local targets=self:GetCurrentTargets(true)
 local chosen
 for _,t in ipairs(targets) do
  if t.key==professionKey then chosen=t;break end
 end
 if not chosen then return false,"SELECT_A_LEARNED_PROFESSION" end
 local plan=planner.GetProfessionPlan and planner:GetProfessionPlan(chosen.key)
 if type(plan)~="table" then
   self:ClearObsoleteProfessionDestination(previousProfession,chosen.key)
   self.currentStepActionFeedback="CURRENT_STEP_PLAN_UNAVAILABLE"
   self:Refresh(true)
   return false,"CURRENT_STEP_PLAN_UNAVAILABLE"
 end
 local source,reason=actions:GuideSource(chosen.key,plan,plan.sourceInfo or
     (type(plan.step)=="table" and plan.step.sourceInfo or nil))
 if not source then
   self:ClearObsoleteProfessionDestination(previousProfession,chosen.key)
   self.currentStepActionFeedback=reason or "CURRENT_STEP_SOURCE_UNAVAILABLE"
   self:Refresh(true)
   return false,self.currentStepActionFeedback
 end
 local category=plan.actionKind=="train" and "TRAINER" or actions:CategoryForSource(source,"CURRENT_STEP")
 local ok,why=actions:Request(category,source,{explicit=true,owner="JuztTom",professionKey=chosen.key})
 if ok then
   self.focusPrimary=chosen.key
   if self.profile then self.profile.focusPrimary=chosen.key end
   self.manual=nil -- Explicit JuztTom selection replaces a manual override.
   self.mode="CURRENT_STEP"
   if self.profile then self.profile.mode="CURRENT_STEP" end
 end
 if not ok then self:ClearObsoleteProfessionDestination(previousProfession,chosen.key) end
 self.currentStepActionFeedback=ok and nil or tostring(why or "NAVIGATION_NOT_AVAILABLE")
 self:Refresh(true)
 return ok,why
end
