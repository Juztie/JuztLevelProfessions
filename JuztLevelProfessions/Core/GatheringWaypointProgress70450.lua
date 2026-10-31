local _,JLP=...
-- Explicitly started waypoint following for ADVISORY map geometry, not
-- movement, node availability, terrain safety or a verified footpath.
-- No saved-state resurrection: every session requires a fresh user action.
local Follow={contract="jlp-gathering-waypoint-progress-70450-v1",nativeDispatchAllowed=false,
    walkabilityVerified=false,arrivalRadius=0.007,sampleInterval=0.4}
local function finite(x)
    return type(x)=="number" and x==x and x>-math.huge and x<math.huge
end
local function validPoint(p)
    return type(p)=="table" and finite(p.x) and finite(p.y) and p.x>=0 and p.x<=1 and
        p.y>=0 and p.y<=1
end
local function copyPoint(p) return {x=p.x,y=p.y} end
local function near(a,b,r)
    return (a.x-b.x)^2+(a.y-b.y)^2<=r*r
end
local function currentBuild()
    local b=JLP:GetModule("ClientBuildInfo")
    if not b or type(b.GetBuildNumber)~="function" then return nil end
    local ok,v=pcall(b.GetBuildNumber,b)
    return ok and v or nil
end
local function playerPosition()
    if type(C_Map)~="table" or type(C_Map.GetBestMapForUnit)~="function" or
       type(C_Map.GetPlayerMapPosition)~="function" then return nil,"POSITION_API_UNAVAILABLE" end
    local ok,mapID=pcall(C_Map.GetBestMapForUnit,"player")
    if not ok or type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then
        return nil,"PLAYER_MAP_UNKNOWN" end
    local got,p=pcall(C_Map.GetPlayerMapPosition,mapID,"player")
    if not got or not p then return nil,"PLAYER_POSITION_UNAVAILABLE" end
    local xy,x,y=pcall(function()
        if type(p.GetXY)=="function" then return p:GetXY() end
        return p.x,p.y
    end)
    local result={x=x,y=y,mapID=mapID}
    if not xy or not validPoint(result) then return nil,"PLAYER_POSITION_INVALID" end
    return result
end
local function routeFor(mapID,profession)
    local owner=JLP:GetModule("GatheringRouteService")
    if not owner or type(owner.GetRoutes)~="function" or
       type(owner.GetContextToken)~="function" or
       type(owner.ContextIsCurrent)~="function" then return nil,"ROUTE_OWNER_UNAVAILABLE" end
    local ok,current=pcall(owner.ContextIsCurrent,owner,mapID)
    -- Require an actually OWNED generation, not legacy fixture fallback.
    if not ok or current~=true or type(owner._presentationContext)~="table" or
       owner._presentationContext.mapID~=mapID then return nil,"ROUTE_CONTEXT_UNQUALIFIED" end
    local received,routes,status=pcall(owner.GetRoutes,owner,mapID)
    if not received or status~="READY" or type(routes)~="table" then
        return nil,"ROUTE_NOT_READY" end
    local route=routes[profession]
    local inspector=JLP:GetModule("GatheringPathingDiagnostics")
    if not inspector or type(inspector.InspectRoute)~="function" then
        return nil,"GEOMETRY_INSPECTOR_UNAVAILABLE" end
    local accepted,report=pcall(inspector.InspectRoute,inspector,route)
    if not accepted or type(report)~="table" or report.valid~=true or
       report.walkabilityVerified~=false or route.terrainValidated~=false or
       route.nativeDispatchAllowed~=false then return nil,"ROUTE_GEOMETRY_UNQUALIFIED" end
    local tokenOK,token=pcall(owner.GetContextToken,owner,mapID)
    if not tokenOK or type(token)~="string" or token=="" then return nil,"ROUTE_TOKEN_MISSING" end
    return route,token
end
local function sameRoute(active,route)
    if route.shape~=active.shape or #route.points~=#active.points then return false end
    if route.shape=="FROM_PLAYER" and
       (not validPoint(route.startPosition) or not near(route.startPosition,active.anchor,0.0000001)) then
        return false end
    for i,p in ipairs(active.points) do
        local q=route.points[i]
        if not validPoint(q) or p.x~=q.x or p.y~=q.y then return false end
    end
    return true
end
function Follow:GetStatus()
    local s=self._active
    if not s then return {status=self._lastStatus or "IDLE",nativeDispatchAllowed=false,
        walkabilityVerified=false,arrivalEvidence="MAP_PROXIMITY_ONLY"} end
    return {status=s.status,mapID=s.mapID,professionKey=s.profession,index=s.index,
        stopCount=#s.points,shape=s.shape,waypointConsent=s.consent,
        waypointOwned=s.waypointOwned==true,reason=s.reason,
        arrivalEvidence="TWO_CLIENT_MAP_POSITION_SAMPLES",walkabilityVerified=false,
        liveNodeVerified=false,normalizedRadius=self.arrivalRadius,nativeDispatchAllowed=false}
end
local function ownedWaypoint(nav,mapID,target)
    if not nav or type(nav.GetActiveWaypoint)~="function" then return false end
    local ok,actual=pcall(nav.GetActiveWaypoint,nav)
    return ok and type(actual)=="table" and actual.mapID==mapID and
        near(actual,target,0.0001)
end
function Follow:_SetWaypoint(s,target)
    if not s.consent then return true,"ADVISORY_ONLY" end
    local nav=JLP:GetModule("Navigation")
    if not nav or type(nav.GetActiveWaypoint)~="function" or
       type(nav.SetWaypointPoint)~="function" or type(nav.GetCapabilities)~="function" then
        return false,"WAYPOINT_API_UNAVAILABLE" end
    local capOK,cap=pcall(nav.GetCapabilities,nav)
    if not capOK or type(cap)~="table" or cap.canReadWaypoint~=true or
       cap.canWaypoint~=true then return false,"WAYPOINT_READ_WRITE_UNVERIFIED" end
    if s.waypointOwned and not ownedWaypoint(nav,s.mapID,s.waypointOwned) then
        return false,"USER_WAYPOINT_CHANGED" end
    if not s.waypointOwned then
        -- Never replace a user waypoint, including another addon's waypoint.
        local ok,active=pcall(nav.GetActiveWaypoint,nav)
        if not ok then return false,"WAYPOINT_READ_FAILED" end
        if active then return false,"EXISTING_USER_WAYPOINT" end
    end
    local targetMap={mapID=s.mapID,x=target.x,y=target.y}
    local ok,set=pcall(nav.SetWaypointPoint,nav,targetMap,{superTrack=false})
    if not ok or set~=true then return false,"WAYPOINT_SET_FAILED" end
    if not ownedWaypoint(nav,s.mapID,target) then
        -- A write without client readback is not evidence of waypoint ownership.
        return false,"WAYPOINT_READBACK_FAILED" end
    s.waypointOwned=copyPoint(target)
    return true,"WAYPOINT_CONFIRMED"
end
function Follow:_ClearOwned(s)
    if not s or not s.waypointOwned then return end
    local nav=JLP:GetModule("Navigation")
    if nav and type(nav.ClearWaypointIfMatches)=="function" and
       ownedWaypoint(nav,s.mapID,s.waypointOwned) then
        pcall(nav.ClearWaypointIfMatches,nav,{mapID=s.mapID,x=s.waypointOwned.x,y=s.waypointOwned.y})
    end
end
function Follow:Stop(reason)
    local previous=self._active
    self._active=nil
    self._lastStatus=reason or "STOPPED_BY_USER"
    if self._frame and type(self._frame.Hide)=="function" then pcall(self._frame.Hide,self._frame) end
    self:_ClearOwned(previous)
    return true,self._lastStatus
end
function Follow:_Driver()
    if self._frame then
        if type(self._frame.Show)=="function" then
            local ok,ret=pcall(self._frame.Show,self._frame)
            if not ok or ret==false then return false end
        end
        return true
    end
    if type(CreateFrame)~="function" then return true end -- explicit manual offline Tick only
    local ok,frame=pcall(CreateFrame,"Frame")
    if not ok or not frame or type(frame.SetScript)~="function" then return false end
    local attached,ret=pcall(frame.SetScript,frame,"OnUpdate",function(_,elapsed)
        if Follow._frame~=frame or not Follow._active then return end
        local dt=finite(elapsed) and elapsed>=0 and elapsed<=1 and elapsed or 0
        Follow._elapsed=math.min(Follow.sampleInterval,(Follow._elapsed or 0)+dt)
        if Follow._elapsed>=Follow.sampleInterval then
            Follow._elapsed=0
            Follow:Tick()
        end
    end)
    if not attached or ret==false then return false end
    if type(frame.Show)=="function" then
        local shown,result=pcall(frame.Show,frame)
        if not shown or result==false then return false end
    end
    self._frame=frame
    return true
end
function Follow:Begin(mapID,profession,consent)
    if self._active then return false,"SESSION_ALREADY_ACTIVE" end
    local observedBuild=currentBuild()
    if type(observedBuild)~="number" or observedBuild~=math.floor(observedBuild) or observedBuild<1 then
        return false,"CLIENT_BUILD_UNKNOWN" end
    if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then
        return false,"MAP_ID_INVALID" end
    if profession~="HERBALISM" and profession~="MINING" then return false,"PROFESSION_INVALID" end
    if type(consent)~="boolean" then return false,"CONSENT_INVALID" end
    local route,token=routeFor(mapID,profession)
    if not route then return false,token end
    local position,err=playerPosition()
    if not position then return false,err end
    if position.mapID~=mapID then return false,"PLAYER_MAP_MISMATCH" end
    if route.shape=="FROM_PLAYER" and not near(position,route.startPosition,0.03) then
        return false,"FROM_PLAYER_ORIGIN_STALE" end
    local points={}
    for _,p in ipairs(route.points) do points[#points+1]=copyPoint(p) end
    if type(UnitOnTaxi)=="function" then
        local taxiOK,taxi=pcall(UnitOnTaxi,"player")
        if not taxiOK or taxi==true then return false,"TRANSPORT_OR_TAXI_UNVERIFIED" end
    end
    local s={mapID=mapID,profession=profession,token=token,shape=route.shape,
        anchor=route.startPosition and copyPoint(route.startPosition),
        points=points,index=1,clientBuild=observedBuild,consent=consent,status="FOLLOWING_ADVISORY_GEOMETRY",nearSamples=0}
    -- Native marker is only set after an explicit user follow request and
    -- verified absent other waypoint. Never request movement/transport.
    local canSet,reason=self:_SetWaypoint(s,points[1])
    if not canSet then return false,reason end
    if not self:_Driver() then
        self:_ClearOwned(s)
        return false,"PROGRESSION_DRIVER_UNAVAILABLE" end
    self._active=s;self._elapsed=0;self._lastStatus=s.status
    return true,"FOLLOWING_ADVISORY_GEOMETRY"
end
function Follow:Tick()
    local s=self._active
    if not s then return false,"NO_ACTIVE_SESSION" end
    if currentBuild()~=s.clientBuild then self:Stop("BUILD_CHANGED");return false,"BUILD_CHANGED" end
    local route,token=routeFor(s.mapID,s.profession)
    if not route or token~=s.token or not sameRoute(s,route) then
        self:Stop("RESOURCE_OR_ROUTE_CHANGED")
        return false,"RESOURCE_OR_ROUTE_CHANGED"
    end
    local pos,err=playerPosition()
    if not pos then s.nearSamples=0;s.status=err;return false,err end
    if pos.mapID~=s.mapID then self:Stop("PLAYER_MAP_CHANGED");return false,"PLAYER_MAP_CHANGED" end
    if type(UnitOnTaxi)=="function" then
        local ok,taxi=pcall(UnitOnTaxi,"player")
        if not ok or taxi==true then s.nearSamples=0;s.status="TRANSPORT_OR_TAXI_UNVERIFIED"
            return false,s.status end
    end
    if s.consent and s.waypointOwned and not ownedWaypoint(JLP:GetModule("Navigation"),s.mapID,s.waypointOwned) then
        self:Stop("USER_WAYPOINT_CHANGED")
        return false,"USER_WAYPOINT_CHANGED"
    end
    local target=s.points[s.index]
    if not target then self:Stop("COMPLETE");return true,"COMPLETE" end
    if near(pos,target,self.arrivalRadius) then s.nearSamples=s.nearSamples+1
    else s.nearSamples=0;s.status="FOLLOWING_ADVISORY_GEOMETRY"
        return true,"NOT_NEAR_WAYPOINT" end
    if s.nearSamples<2 then return true,"ARRIVAL_SAMPLE_PENDING" end
    s.nearSamples=0
    if s.index>=#s.points then self:Stop("COMPLETE_MAP_PROXIMITY_ONLY")
        return true,"COMPLETE_MAP_PROXIMITY_ONLY" end
    local nextTarget=s.points[s.index+1]
    local ok,reason=self:_SetWaypoint(s,nextTarget)
    if not ok then
        self:Stop("WAYPOINT_ADVANCE_BLOCKED_"..reason)
        return false,reason
    end
    s.index=s.index+1;s.status="FOLLOWING_ADVISORY_GEOMETRY"
    return true,"ADVANCED_MAP_PROXIMITY_ONLY"
end
JLP:RegisterModule("GatheringWaypointProgress70450",Follow)
