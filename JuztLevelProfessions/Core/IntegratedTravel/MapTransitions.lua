local _, JLP = ...
-- Map topology, not terrain navigation. UiMap/AreaTable identify maps, but
-- shared continent/parent does NOT establish a walkable cross-map passage.
-- Only explicitly attested city/exterior transitions may join transport maps.
local T=JLP._integratedTravel
local M={contract='jlp-map-transition-advisory-v1'}
-- The transport dataset is fully available for planning, but an unobserved
-- flight unlock is NOT an available service on the current character.
-- A conditional flight must lose to any path using known usable edges.
local UNKNOWN_FLIGHT_PENALTY=20000
local transitionPairs={
 {id='ORGRIMMAR_DUROTAR',city=1454,zone=1411,cityName='Orgrimmar',zoneName='Durotar',
  exitText='Leave Orgrimmar into Durotar. The next waypoint will be selected after the client confirms the Durotar map.',
  enterText='Enter Orgrimmar from Durotar. Resume local navigation when the city map is confirmed.',
  -- Historical user-supplied corridor landmark, NOT an exact city-gate point.
  zoneLandmark={mapID=1411,x=.455,y=.121,label='Orgrimmar main gate'},
  authority='EXPLICIT_CORRIDOR_REFERENCE_NOT_CLIENT_WALKABILITY'},
 {id='UNDERCITY_TIRISFAL',city=1458,zone=1420,cityName='Undercity',zoneName='Tirisfal Glades',
  exitText='Leave Undercity into Tirisfal Glades. Continue after the client confirms the exterior map.',
  enterText='Head toward the Ruins of Lordaeron entrance, then enter Undercity. Navigation continues when the game detects the Undercity map.',
  zoneLandmark={mapID=1420,x=.619,y=.651,label='Ruins of Lordaeron entrance'},
  authority='EXPLICIT_CORRIDOR_REFERENCE_NOT_CLIENT_WALKABILITY'}
}
local function finiteMap(n)
 return type(n)=='number' and n>0 and n==math.floor(n)
end
local function outgoing(graph,context)
 local adj={};local admitted=0;local denied={}
 local function push(a,b,step)
  if not finiteMap(a) or not finiteMap(b) or a==b then return end
  adj[a]=adj[a] or {};adj[a][#adj[a]+1]=step
 end
 for _,pair in ipairs(transitionPairs) do
  push(pair.city,pair.zone,{from=pair.city,to=pair.zone,kind='EXIT_CITY',cost=2,transition=pair})
  push(pair.zone,pair.city,{from=pair.zone,to=pair.city,kind='ENTER_CITY',cost=2,transition=pair})
 end
 for _,edge in ipairs(graph.edges or {}) do
  local from=graph.nodes and graph.nodes[edge.from]
  local to=graph.nodes and graph.nodes[edge.to]
  -- Registered endpoints and links are routable regardless of evidence label.
  -- Only actual gameplay restrictions can make a link unavailable.
  if from and to and edge.from~=edge.to and from.mapID~=to.mapID then
   local ok,why=graph:CanTraverse(edge,context)
   if ok then
    -- Map-level cost is an ordering heuristic, NOT a distance or ETA.
    -- Node-level routing still requires live, verified coordinates.
    local unconfirmedFlight=edge.mode=='FLIGHT' and
        (type(context.unlocked)~='table' or context.unlocked[edge.id]~=true)
    push(from.mapID,to.mapID,{from=from.mapID,to=to.mapID,
      kind='TRANSPORT',cost=10+(unconfirmedFlight and UNKNOWN_FLIGHT_PENALTY or 0),
      unlockStatus=unconfirmedFlight and 'NOT_CONFIRMED_FOR_CHARACTER' or 'NOT_REQUIRED_OR_CONFIRMED',
      edge=edge,platform=from,arrival=to})
    admitted=admitted+1
   else denied[why or 'NOT_ELIGIBLE']=(denied[why or 'NOT_ELIGIBLE'] or 0)+1 end
  end
 end
 for _,steps in pairs(adj) do
  table.sort(steps,function(a,b)
   if a.to~=b.to then return a.to<b.to end
   return tostring(a.edge and a.edge.id or a.transition and a.transition.id or '')<
       tostring(b.edge and b.edge.id or b.transition and b.transition.id or '')
  end)
 end
 return adj,admitted,denied
end
function M:FindPath(graph,originMap,destinationMap,context)
 if not graph or type(graph.nodes)~='table' or type(graph.edges)~='table' then
  return nil,'MAP_GRAPH_UNAVAILABLE' end
 if not finiteMap(originMap) or not finiteMap(destinationMap) then
  return nil,'INVALID_MAP_ID' end
 if originMap==destinationMap then return {},'SAME_CLIENT_MAP' end
 local adj,admitted,denied=outgoing(graph,context or {})
 local best={[originMap]=0};local parent={};local seen={};local visited=0
 -- Bounded Dijkstra over map-level transitions. Never link maps merely
 -- because they share a continent or UiMap.ParentUiMapID.
 while visited<120 do
  local nextMap,nextCost
  for map,cost in pairs(best) do
   if not seen[map] and (not nextCost or cost<nextCost or (cost==nextCost and map<nextMap)) then
    nextMap,nextCost=map,cost
   end
  end
  if not nextMap or nextMap==destinationMap then break end
  seen[nextMap]=true;visited=visited+1
  for _,step in ipairs(adj[nextMap] or {}) do
   local cost=nextCost+step.cost
   if not best[step.to] or cost<best[step.to] then
    best[step.to]=cost;parent[step.to]={map=nextMap,step=step}
   end
  end
 end
 if not best[destinationMap] then
  return nil,'NO_ATTESTED_MAP_TRANSITION_PATH',
    {eligibleTransportEdges=admitted,excluded=denied,visited=visited}
 end
 local path={};local at=destinationMap
 while at~=originMap do
  local p=parent[at];if not p then return nil,'BROKEN_MAP_PATH' end
  table.insert(path,1,p.step);at=p.map
  if #path>120 then return nil,'MAP_PATH_LIMIT' end
 end
 return path,'ADVISORY_MAP_PATH',
  {eligibleTransportEdges=admitted,transitionCount=#path,visited=visited}
end
function M:Guidance(step,destination,routeLength)
 if not step then return nil,'NO_NEXT_MAP_TRANSITION' end
 local common={destination=T.Contract.copyPoint(destination),routeVerified=false,
  arrivalVerified=false,autoAdvance=false,navigationOnly=true,
  nativeDispatchAllowed=false,confidence='ATTESTED_MAP_TOPOLOGY_GUIDANCE_ONLY',
  mapTransitionCount=routeLength}
 local function with(fields)
  for k,v in pairs(fields) do common[k]=v end
  return common
 end
 if step.kind=='EXIT_CITY' then
  return with({phase='EXIT_SOURCE_CITY',stage=(step.transition.id=='ORGRIMMAR_DUROTAR' and 'ORGRIMMAR_TO_DUROTAR' or step.transition.id..'_EXIT'),
   instruction=step.transition.exitText,waypoint=nil,nextMapID=step.to,
   mapTransitionAuthority=step.transition.authority})
 elseif step.kind=='ENTER_CITY' then
  local landmark=step.transition.zoneLandmark
  return with({phase='ENTER_DESTINATION_CITY',stage=step.transition.id..'_ENTER',
   instruction=step.transition.enterText,waypoint=landmark and T.Contract.copyPoint(landmark) or nil,
   nextMapID=step.to,waypointQuality='APPROXIMATE_REFERENCE_NOT_CLIENT_VERIFIED',
   mapTransitionAuthority=step.transition.authority})
 elseif step.kind=='TRANSPORT' then
  local pt=T.Contract.copyPoint(step.platform)
  pt.label=step.platform.label
  local flightDestination=step.edge.mode=='FLIGHT' and step.arrival and
      type(step.arrival.placeName)=='string' and step.arrival.placeName~='' and
      step.arrival.placeName or nil
  local desc=step.edge.mode=='FLIGHT' and
      (step.unlockStatus=='NOT_CONFIRMED_FOR_CHARACTER' and
       'Flight Path availability is not confirmed for this character. Speak with the Flight Master before using this conditional leg.' or
       'Speak with the Flight Master and select the available flight.') or
      ('Use the '..step.edge.mode:lower()..' from the indicated platform. Board manually.')
  return with({phase='WALK_TO_WAYPOINT',stage=(step.edge.id=='R002' and step.from==1411 and 'DUROTAR_ZEPPELIN_R002' or 'TRANSPORT_'..step.edge.id),
   waypoint=pt,nextMapID=step.to,transport=step.edge.mode,
   flightUnlock=step.edge.mode=='FLIGHT' and step.unlockStatus or nil,
   transportEdgeAuthorized=true,transportEdgeID=step.edge.id,
   displayTitle=flightDestination and ('Fly to '..flightDestination) or nil,
   displayDetail=flightDestination and ('Flight Master: '..tostring(pt.label or 'Flight Master')) or nil,
   nextFlightDestination=flightDestination,
   instruction='Travel to '..tostring(pt.label or 'the transport platform')..'. '..
       (flightDestination and ('Select '..flightDestination..' on the Flight Master map. ') or '')..
       desc..' The next map change must be observed by the game client.',
   waypointQuality='OWNER_ATTESTED_STATION_POSITION_NOT_TERRAIN_PATH',
   mapTransitionAuthority='OWNER_AUTHORIZED_ELIGIBLE_TRANSPORT_EDGE'})
 end
 return nil,'UNKNOWN_MAP_TRANSITION'
end
-- A return through an explicitly documented city/exterior boundary is not a
-- new transport edge. The observed native map still has to match the pair.
-- Unknown adjacent maps and shared parent maps are never inferred here.
function M:IsAttestedCityExit(cityMap,exteriorMap)
 if not finiteMap(cityMap) or not finiteMap(exteriorMap) then return false end
 for _,entry in ipairs(transitionPairs) do
  if entry.city==cityMap and entry.zone==exteriorMap then
   return true,entry.id
  end
 end
 return false
end
T.MapTransitions=M
