-- Portable corridor controller: converts a city destination into zone zeppelin
-- legs, then waits for the correct destination city map before final navigation.
-- Uses only injected graph/planner/journey/point observations (no WoW globals).
local _, JLP = ...
local T = JLP._integratedTravel
local C=T.Contract
local M={}
M.__index=M
local PLACES={
  ORGRIMMAR={city=1454,zone=1411,arrivalNode='horde_og_uc_durotar',
    cityLabel='Orgrimmar',zoneLabel='Durotar',exitText='Leave Orgrimmar by its main gate into Durotar. Then follow the zeppelin marker.',
    enterText='Head to the Orgrimmar main gate and enter the city. Navigation continues on the city map.',
    entryLandmark={mapID=1411,x=.455,y=.121,label='Orgrimmar main gate',zone='Durotar'}},
  UNDERCITY={city=1458,zone=1420,arrivalNode='horde_uc_og_tirisfal',
    cityLabel='Undercity',zoneLabel='Tirisfal Glades',exitText='Leave Undercity through the Ruins of Lordaeron into Tirisfal Glades.',
    enterText='Head toward the Ruins of Lordaeron entrance, then enter Undercity. Navigation continues on the city map.',
    entryLandmark={mapID=1420,x=.619,y=.651,label='Ruins of Lordaeron entrance',zone='Tirisfal Glades'}},
}
function M.New(graph)
  return setmetatable({graph=graph,journey=T.Journey.New(),phase='IDLE',plan=nil,goal=nil,fromKey=nil,toKey=nil,context=nil,options=nil,reason=nil,sequence=0,reentry=false},M)
end
local function srcFor(mapID)
  for k,v in pairs(PLACES) do if mapID==v.city or mapID==v.zone then return k,v end end
end
local function targetFor(mapID)
  for k,v in pairs(PLACES) do if mapID==v.city or mapID==v.zone then return k,v end end
end
local function gp(place,graph)
  local p=graph.nodes[place.arrivalNode]
  return p and C.copyPoint(p)
end
function M:Stop()
  self.journey:Stop();self.phase='IDLE';self.plan=nil;self.goal=nil
  self.fromKey=nil;self.toKey=nil;self.context=nil;self.reason=nil;self.reentry=false
  self.sequence=self.sequence+1
end
function M:BeginLegs(origin)
  local source, dest=PLACES[self.fromKey],PLACES[self.toKey]
  local endpoint=gp(dest,self.graph)
  if not endpoint then self.phase='BLOCKED';self.reason='CORRIDOR_DATA_MISSING';return false,self.reason end
  local route,reason=self.planner:Plan(self.graph,origin,endpoint,self.context,self.options)
  if not route then self.phase='BLOCKED';self.reason=reason;return false,reason end
  local ok,why=self.journey:Start(route)
  if not ok then self.phase='BLOCKED';self.reason=why;return false,why end
  self.plan=route;self.phase='TO_TRANSPORT';self.reason=nil
  return true
end
function M:Start(origin,destination,context,options)
  local src,srcPlace=srcFor(origin and origin.mapID)
  local dst,dstPlace=targetFor(destination and destination.mapID)
  if not src or not dst then return false,'CORRIDOR_ENDPOINT_OUT_OF_SCOPE' end
  if options~=nil and type(options)~='table' then return false,'INVALID_OPTIONS' end
  options=options or {}
  local final,why
  if options.cityOnly==true then
    if type(destination)=='table' and destination.mapID==dstPlace.city then
      final={mapID=dstPlace.city,label=dstPlace.cityLabel,zone=dstPlace.zoneLabel}
    else return false,'CITY_ONLY_REQUIRES_CITY_MAP' end
  else
    final,why=C.point(destination)
    if not final then return false,why end
  end
  if not src or not dst then return false,'CORRIDOR_ENDPOINT_OUT_OF_SCOPE' end
  if src==dst then
    -- Local POINT intent is still a journey: retain it across city exits.
    -- A city-only request in the current city remains a no-op.
    if options.cityOnly or not final or final.mapID~=dstPlace.city then
      return false,'SAME_CITY_USE_LOCAL_NAVIGATION'
    end
    if type(context)~='table' or context.faction~='HORDE' then return false,'HORDE_ONLY_CORRIDOR' end
    self:Stop()
    self.goal=final;self.fromKey=src;self.toKey=dst;self.reentry=false
    self.context=C.shallowCopy(context);self.options=C.shallowCopy(options)
    self.planner=T.Planner;self.graphGeneration=self.graph.generation
    if origin.mapID==dstPlace.zone then
      self.phase='ENTER_DESTINATION_CITY';self.reentry=true
      return true,nil,self:Guidance()
    end
    local plan,reason=self.planner:Plan(self.graph,origin,final,context,options)
    if not plan then self:Stop();return false,reason end
    self.journey:Start(plan);self.plan=plan;self.phase='FINAL_LOCAL'
    return true,nil,plan
  end
  if type(context)~='table' or context.faction~='HORDE' then return false,'HORDE_ONLY_CORRIDOR' end
  if not self.graph.nodes[srcPlace.arrivalNode] or not self.graph.nodes[dstPlace.arrivalNode] then return false,'CORRIDOR_DATA_MISSING' end
  -- Never mutate the previous journey if a new request is invalid.
  self:Stop()
  self.goal=final;self.fromKey=src;self.toKey=dst;self.reentry=false
  self.context=C.shallowCopy(context);self.options=C.shallowCopy(options or {})
  self.planner=T.Planner
  self.graphGeneration=self.graph.generation
  if origin.mapID~=srcPlace.zone then
    self.phase='EXIT_SOURCE_CITY'
    return true,nil,{phase=self.phase}
  end
  local ok,reason=self:BeginLegs(origin)
  if not ok then self:Stop();return false,reason end
  return true,nil,self.plan
end
function M:Guidance()
  if self.phase=='IDLE' then return {contract=T.contract,phase='IDLE'} end
  if self.graph.generation~=self.graphGeneration then return {contract=T.contract,phase='STALE_PLAN',reason='NETWORK_GENERATION_CHANGED'} end
  if self.phase=='BLOCKED' then return {contract=T.contract,phase='BLOCKED',reason=self.reason} end
  local src,dst=PLACES[self.fromKey],PLACES[self.toKey]
  local info={contract=T.contract,corridor='HORDE_OG_UC',destination=self.goal,
    goalKind=self.options and self.options.cityOnly and 'CITY' or 'POINT',
    confidence='USER_REFERENCE_NOT_INGAME',etaSeconds=nil,
    fromCity=src.cityLabel,toCity=dst.cityLabel}
  if self.phase=='EXIT_SOURCE_CITY' then
    info.phase='EXIT_SOURCE_CITY';info.instruction=src.exitText
    info.waypoint=nil;return info
  end
  if self.phase=='ARRIVED_CITY' then
    info.phase='ARRIVED';info.instruction='Reached the '..dst.cityLabel..' city map.'
    info.waypoint=nil;return info
  end
  if self.phase=='OUTSIDE_SUPPORTED_CORRIDOR' then
    info.phase='OUTSIDE_SUPPORTED_CORRIDOR'
    info.instruction='Outside the currently supported city corridor. Return to '..dst.zoneLabel..' or '..dst.cityLabel..' for verified map guidance.'
    info.waypoint=nil;return info
  end
  if self.phase=='ENTER_DESTINATION_CITY' then
    info.phase='ENTER_DESTINATION_CITY';info.stage=self.reentry and 'RETURN_TO_CITY' or 'CITY_INGRESS'
    info.instruction=self.reentry and ('Return to '..dst.cityLabel..'. '..dst.enterText) or dst.enterText
    -- Map landmark only: it is NOT a measured doorway, elevator or walkable path.
    -- Never auto-finish this phase by proximity, only on observing the city UIMapID.
    info.waypoint=C.copyPoint(dst.entryLandmark)
    info.waypointQuality='APPROXIMATE_CITY_LANDMARK_NOT_VERIFIED_INGAME'
    return info
  end
  local g=self.journey:Guidance()
  for k,v in pairs(g) do info[k]=v end
  if self.phase=='FINAL_LOCAL' then
    info.stage='FINAL_LOCAL'
    info.waypointQuality='MAP_COORDINATE_NOT_NPC_INTERACTION'
    if g.phase=='ARRIVED' then info.phase='ARRIVED' end
    return info
  end
  info.stage='CORRIDOR'
  if g.phase=='WAIT_FOR_TRANSPORT' then
    local current=self.journey:CurrentLeg()
    info.instruction='Wait for the '..dst.cityLabel..' zeppelin. '..(current and current.note or '')
  elseif g.phase=='WALK_TO_WAYPOINT' then
    info.instruction='Follow the marker toward '..tostring(g.waypoint and g.waypoint.label or 'the zeppelin tower')..'.'
  end
  return info
end
function M:Observe(point)
  if self.phase=='IDLE' then return nil,'NO_ACTIVE_CORRIDOR' end
  if self.graph.generation~=self.graphGeneration then return nil,'NETWORK_GENERATION_CHANGED' end
  local loc,why=C.point(point);if not loc then return nil,why end
  local src,dst=PLACES[self.fromKey],PLACES[self.toKey]
  if self.phase=='EXIT_SOURCE_CITY' then
    if loc.mapID==src.zone then
      local ok,reason=self:BeginLegs(loc)
      if not ok then return nil,reason end
    end
    return self:Guidance()
  end
  if self.phase=='ENTER_DESTINATION_CITY' then
    if loc.mapID==dst.city then
      if self.options.cityOnly==true then
        self.phase='ARRIVED_CITY';return self:Guidance()
      end
      local plan,reason=self.planner:Plan(self.graph,loc,self.goal,self.context,self.options)
      if not plan then self.phase='BLOCKED';self.reason=reason;return nil,reason end
      self.journey:Start(plan);self.plan=plan;self.phase='FINAL_LOCAL';self.reentry=false
    end
    return self:Guidance()
  end
  if self.phase=='TO_TRANSPORT' then
    -- Arrival may fall a short distance from the center of a large zeppelin platform.
    -- This is normalized-map proximity, NOT yards. Only used on the expected zone.
    local before=self.journey:CurrentLeg()
    -- Conservative pre-boarding radius. Alpha3 used 0.008 of the entire map,
    -- which live testing showed was too generous. Still a map-fraction, NOT yards.
    -- 0.0015 requires much closer approach; exact tuning needs Forever client evidence.
    local beforeRadius=(before and before.mode=='WALK') and 0.0015 or 0.002
    local _,err=self.journey:Observe(loc,beforeRadius)
    if err then return nil,err end
    -- After a verified destination-map observation, consume the landing WALK
    -- leg in the same tick only if we are genuinely at its mapped point.
    -- This does not infer a boarding event or guess a cross-map transfer.
    local after=self.journey:CurrentLeg()
    if before and before.mode~='WALK' and after and after.mode=='WALK' and
       loc.mapID==after.to.mapID and C.distance(loc,after.to)<=0.002 then
      self.journey:Observe(loc,0.002)
    end
    if self.journey.state=='ARRIVED' then
      if self.goal.mapID==dst.city then
        self.phase='ENTER_DESTINATION_CITY'
      else
        -- A destination in the arrival zone needs its own local leg after
        -- completing the zeppelin arrival legs. Never treat arrival platform
        -- as arrival at an unrelated target in the same zone.
        local localPlan,localReason=self.planner:Plan(self.graph,loc,self.goal,self.context,self.options)
        if not localPlan then self.phase='BLOCKED';self.reason=localReason;return nil,localReason end
        self.journey:Start(localPlan);self.plan=localPlan;self.phase='FINAL_LOCAL'
      end
    end
    return self:Guidance()
  end
  if self.phase=='FINAL_LOCAL' then
    -- A POINT journey owns the final NPC target until qualified arrival.
    -- Crossing from the city map back into its exterior does not complete it.
    if self.options.cityOnly~=true and self.goal.mapID==dst.city and
        loc.mapID==dst.zone and self.journey.state~='ARRIVED' then
      self.phase='ENTER_DESTINATION_CITY';self.reentry=true
      return self:Guidance()
    end
    -- On unrelated maps, keep the intent but never create a cross-map bearing.
    if loc.mapID~=self.goal.mapID and self.journey.state~='ARRIVED' then
      self.phase='OUTSIDE_SUPPORTED_CORRIDOR'
      return self:Guidance()
    end
    local _,err=self.journey:Observe(loc,0.001)
    if err then return nil,err end
    return self:Guidance()
  end
  if self.phase=='OUTSIDE_SUPPORTED_CORRIDOR' then
    if self.goal.mapID==dst.city and loc.mapID==dst.zone then
      self.phase='ENTER_DESTINATION_CITY';self.reentry=true
    elseif loc.mapID==self.goal.mapID then
      local plan,reason=self.planner:Plan(self.graph,loc,self.goal,self.context,self.options)
      if not plan then self.phase='BLOCKED';self.reason=reason;return nil,reason end
      self.journey:Start(plan);self.plan=plan;self.phase='FINAL_LOCAL';self.reentry=false
    end
    return self:Guidance()
  end
  return self:Guidance()
end
-- Explicit optional fallback if source coordinates do not align with the
-- physical waiting location. Only puts the journey in WAIT; it cannot claim
-- boarding or arrival without the expected destination map observation.
function M:ConfirmPlatform(point)
  if self.phase~='TO_TRANSPORT' then return false,'NOT_APPROACHING_PLATFORM' end
  local leg=self.journey:CurrentLeg()
  local nextLeg=self.journey.plan and self.journey.plan.legs[self.journey.index+1]
  if not leg or leg.mode~='WALK' or not nextLeg or nextLeg.mode=='WALK' then
    return false,'NOT_APPROACHING_PLATFORM'
  end
  local loc,reason=C.point(point)
  if not loc then return false,reason end
  if loc.mapID~=leg.to.mapID or C.distance(loc,leg.to)>0.012 then
    return false,'PLATFORM_LOCATION_NOT_QUALIFIED'
  end
  self.journey.lastLocation=loc
  self.journey:Advance()
  self.manualPlatformConfirmation=true
  return true,nil,self:Guidance()
end
function M:GetPlaces()
  return {ORGRIMMAR={city=1454,zone=1411},UNDERCITY={city=1458,zone=1420}}
end
-- Scope-limited, source-labelled city approach hint, not a production route.
-- The city entrance points were already bundled as approximate reference
-- landmarks; no new terrain connection or transport entitlement is asserted.
function M:GetIngressReference(origin,target)
  local _,place=targetFor(target and target.mapID)
  if not place or target.mapID~=place.city or
     type(origin)~="table" or origin.mapID~=place.zone then
    return nil,"INGRESS_REFERENCE_NOT_APPLICABLE" end
  local p=C.point(place.entryLandmark)
  if not p then return nil,"INGRESS_LANDMARK_INVALID" end
  p.label=place.cityLabel.." entrance"
  return {phase="ENTER_DESTINATION_CITY",waypoint=p,
    destination=C.copyPoint(target),destinationMapID=place.city,
    instruction=place.enterText,
    confidence="APPROXIMATE_CITY_LANDMARK_NOT_VERIFIED_INGAME",
    routeVerified=false,arrivalVerified=false,autoAdvance=false,
    navigationOnly=true,nativeDispatchAllowed=false},"REFERENCE_CITY_INGRESS_ONLY"
end
T.Corridor=M
