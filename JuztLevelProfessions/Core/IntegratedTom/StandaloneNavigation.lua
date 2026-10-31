local _, JLP = ...
local JT = JLP._integratedTom
local abs,sqrt,atan,pi=math.abs,math.sqrt,math.atan,math.pi
local function angle2(y,x)
    if type(math.atan2)=="function" then return math.atan2(y,x) end
    if x>0 then return atan(y/x) end
    if x<0 then return atan(y/x)+(y>=0 and pi or -pi) end
    return y>0 and pi/2 or y<0 and -pi/2 or 0
end
local function safePosition(mapID)
    if type(C_Map)~="table" or type(C_Map.GetPlayerMapPosition)~="function" then return nil end
    local ok,p=pcall(C_Map.GetPlayerMapPosition,mapID,"player")
    if not ok or not p then return nil end
    local good,x,y=pcall(function()
        if type(p.GetXY)=="function" then return p:GetXY() end
        return p.x,p.y
    end)
    if not good then return nil end
    local tested,valid=pcall(JT.ValidPoint,JT,mapID,x,y)
    if not tested or not valid then return nil end
    local converted,px,py=pcall(function()return tonumber(x),tonumber(y) end)
    if not converted then return nil end
    return px,py
end
local function playerMap()
    if type(C_Map)~="table" or type(C_Map.GetBestMapForUnit)~="function" then return nil end
    local ok,id=pcall(C_Map.GetBestMapForUnit,"player")
    return ok and tonumber(id) or nil
end
local function world(mapID,x,y)
    if type(C_Map)~="table" or type(C_Map.GetWorldPosFromMapPos)~="function" or
        type(CreateVector2D)~="function" then return nil end
    local ok,instance,vector=pcall(function()
        return C_Map.GetWorldPosFromMapPos(mapID,CreateVector2D(x,y))
    end)
    if not ok or not instance or not vector then return nil end
    local good,wx,wy=pcall(function()
        if type(vector.GetXY)=="function" then return vector:GetXY() end
        return vector.x,vector.y
    end)
    if not good or type(wx)~="number" or type(wy)~="number" then return nil end
    return instance,wx,wy
end
function JT:GetGeometry(point)
    if not point or not self:ValidPoint(point.mapID,point.x,point.y) then return nil end
    local x,y=safePosition(point.mapID)
    if not x or not y then return {positionAvailable=false,mapID=playerMap(),status="DESTINATION_MAP_NOT_AVAILABLE"} end
    local ok,vector=pcall(function()
        local dx,dy=point.x-x,point.y-y
        local normalized=sqrt(dx*dx+dy*dy)
        -- WoW GetPlayerFacing increases COUNTERCLOCKWISE: N=0, W=pi/2,
        -- S=pi, E=3*pi/2. Map Y increases toward south, so negate dx and dy.
        -- Keep this convention identical to Texture:SetRotation (positive CCW).
        local direction=angle2(-dx,-dy)
        if direction<0 then direction=direction+2*pi end
        return {distanceMap=normalized,direction=direction,positionAvailable=true,mapID=point.mapID}
    end)
    if not ok or not vector then return {positionAvailable=false,status="COORDINATES_PROTECTED"} end
    local a,ax,ay=world(point.mapID,x,y)
    local b,bx,by=world(point.mapID,point.x,point.y)
    if a and b and a==b then
        local success,d=pcall(function()return sqrt((bx-ax)^2+(by-ay)^2) end)
        if success and type(d)=="number" and d==d then vector.distanceYards=d end
    end
    -- The same-map fallback is dimensionless: never label it as yards.
    return vector
end
function JT:NearestIndex(points,mapID,closed)
    if not closed then return 1 end
    local x,y=safePosition(mapID)
    if not x then return 1 end
    local bestIndex,best=1,math.huge
    for i,p in ipairs(points) do
        local delta=(p.x-x)*(p.x-x)+(p.y-y)*(p.y-y)
        if delta<best then best=delta;bestIndex=i end
    end
    return bestIndex
end
function JT:AdvanceGathering(manual)
    local state=self.gatheringState
    if not state or not state.activeKey then return false end
    local selected=state.routes[state.activeKey]
    if not selected then return false end
    local total=#selected.points
    if selected.index<total then selected.index=selected.index+1
    elseif selected.closed then selected.index=1
    else selected.done=true end
    if manual then selected.lastManualAdvance=true end
    return true
end
function JT:CycleGathering()
    local state=self.gatheringState
    if not state then return false end
    local keys={}
    for _,k in ipairs({"HERBALISM","MINING"}) do if state.routes[k] then keys[#keys+1]=k end end
    if #keys<2 then return false end
    state.activeKey=(state.activeKey==keys[1]) and keys[2] or keys[1]
    self:Refresh(true)
    return true
end
function JT:SyncGathering()
    local receipt,why=self:ReadGathering()
    if not receipt then self.gatheringState=nil;return nil,why end
    local signature=receipt.mapID.."|"..receipt.token.."|"..tostring(receipt.generation)
    -- Identity remains qualified by token AND owner generation. Route mutations
    -- do not survive a new job, changed filter or zone selection.
    local state=self.gatheringState
    if not state or state.signature~=signature then
        state={signature=signature,routes={},activeKey=nil}
        for _,key in ipairs({"HERBALISM","MINING"}) do
            local r=receipt.routes[key]
            if r then
                r.index=self:NearestIndex(r.points,receipt.mapID,r.closed)
                state.routes[key]=r
                if not state.activeKey then state.activeKey=key end
            end
        end
        if state.routes.HERBALISM and state.routes.MINING then
            local best,bestDist
            for _,key in ipairs({"HERBALISM","MINING"}) do
                local r=state.routes[key]
                local geometry=self:GetGeometry(r.points[r.index])
                local dist=geometry and geometry.distanceMap or nil
                if dist and (not bestDist or dist<bestDist) then best,bestDist=key,dist end
            end
            state.activeKey=best or state.activeKey
        end
        self.gatheringState=state
    end
    return state
end
local function targetSame(a,b)
    return a and b and a.mapID==b.mapID and a.x==b.x and a.y==b.y and a.source==b.source
end
function JT:UpdateNavigation(force)
    local point,why,active
    local routeIndex,routeCount=nil,nil
    if self.manual then point=self.manual
    elseif self.external then
        point=self.external.points[self.external.index]
        routeIndex,routeCount=self.external.index,#self.external.points
    elseif self.mode=="GATHERING" then
        local state
        state,why=self:SyncGathering()
        if state then
            active=state.routes[state.activeKey]
            if active and not active.done then
                point=active.points[active.index]
                routeIndex,routeCount=active.index,#active.points
                if point then point.group=state.activeKey end
            else why="ROUTE_COMPLETE" end
        end
    else
        point,why,active=self:ActiveCurrentStep(force)
    end
    -- Do not mutate the existing manual, external, Gathering or Current Step
    -- provider. All remain available after the travel overlay disappears.
    self.underlyingTarget=point
    -- Current Step is the sole authoritative auto-travel goal. Synchronize
    -- before reading the travel overlay, without calling GetState() recursively.
    -- Manual waypoints and explicit external routes never trigger auto-planning.
    if self.SyncCurrentStepTravel then self:SyncCurrentStepTravel(point,active) end
    local travel=self.ReadTravelGuidance and self:ReadTravelGuidance() or nil
    self.travelOverlay=travel
    if travel then
        point=travel.waypoint
        routeIndex,routeCount=travel.index,travel.total
        active=nil  -- never auto-advance gathering while travel is authoritative
    end
    local geometry=self:GetGeometry(point)
    local reached=false
    if geometry and geometry.positionAvailable then
        if geometry.distanceYards then reached=geometry.distanceYards<=self.profile.arrival
        elseif geometry.distanceMap and geometry.approximate~=true then reached=geometry.distanceMap<=0.002 end
    end
    if reached and not travel and self.profile.autoAdvance and self.mode=="GATHERING" and
       not self.manual and not self.external and active then
        -- One advancement per first arrival, hysteresis prevents churn at a
        -- loop seam and repeated triggers while standing on the same point.
        local fingerprint=self.gatheringState.signature.."|"..self.gatheringState.activeKey.."|"..active.index
        if self.lastArrived~=fingerprint then
            self.lastArrived=fingerprint
            self:AdvanceGathering(false)
            if not active.done then
                point=active.points[active.index]
                routeIndex=active.index
                geometry=self:GetGeometry(point)
                reached=geometry and geometry.distanceYards and geometry.distanceYards<=self.profile.arrival or false
            else point=nil;why="ROUTE_COMPLETE" end
        end
    elseif not reached then self.lastArrived=nil end
    if reached and not travel and self.external and self.profile.autoAdvance then
        local route=self.external
        local stamp=route.id..":"..route.index
        if self.lastExternalArrival~=stamp then
            self.lastExternalArrival=stamp
            if route.index<#route.points then route.index=route.index+1
            elseif route.closed then route.index=1
            else self.external=nil end
            -- Atomically recompute target and geometry in this same update.
            -- Never show a distance for stop N alongside stop N+1 in the UI.
            if self.external then
                point=route.points[route.index]
                routeIndex,routeCount=route.index,#route.points
                geometry=self:GetGeometry(point)
                reached=geometry and geometry.positionAvailable and (
                    (geometry.distanceYards and geometry.distanceYards<=self.profile.arrival) or
                    (not geometry.distanceYards and geometry.distanceMap and geometry.approximate~=true and geometry.distanceMap<=0.002)) or false
            else
                point=nil;geometry=nil;routeIndex=nil;routeCount=nil
                reached=false;why="ROUTE_COMPLETE"
            end
        end
    elseif not reached then self.lastExternalArrival=nil end
    if not targetSame(point,self.current) or force then self.current=point end
    self.geometry=geometry
    self.distanceYards=geometry and geometry.distanceYards or nil
    self.routeIndex,self.routeCount=routeIndex,routeCount
    self.activeTargetKey=point and (tostring(point.source).."|"..tostring(point.mapID).."|"..
        tostring(point.x).."|"..tostring(point.y).."|"..tostring(routeIndex or "")) or nil
    if travel and not point then
        self.status="TRAVEL_"..tostring(travel.phase)
    elseif not point then self.status=why or "NO_WAYPOINT"
    elseif not geometry or not geometry.positionAvailable then self.status="TRAVEL_TO_DESTINATION_MAP"
    elseif reached then self.status=travel and "TRAVEL_AT_WAYPOINT" or "AT_WAYPOINT"
    elseif geometry.distanceYards then self.status="NAVIGATING"
    else self.status="MAP_RELATIVE_DIRECTION" end
end
