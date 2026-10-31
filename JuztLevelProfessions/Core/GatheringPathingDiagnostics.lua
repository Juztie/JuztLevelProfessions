local _, JLP = ...
-- One read-only diagnostic contract over both gathering route engines.
-- Normalized map geometry is advisory; NEVER claim obstacle avoidance,
-- transport continuity, or confirmed spawn probability.
local Guard={contract="jlp-gathering-pathing-diagnostics-v1",nativeDispatchAllowed=false}
local function finite(v)
 return type(v)=="number" and v==v and v<math.huge and v>-math.huge
end
local function point(p)
 return type(p)=="table" and finite(p.x) and finite(p.y) and
  p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1
end
function Guard:InspectRoute(route)
 if type(route)~="table" or type(route.points)~="table" then
  return {valid=false,reason="ROUTE_MISSING",nativeDispatchAllowed=false}
 end
 if route.shape~="LOOP" and route.shape~="FROM_PLAYER" then
  return {valid=false,reason="SHAPE_INVALID",nativeDispatchAllowed=false}
 end
 local count=#route.points
 if count<2 or count>250 then
  return {valid=false,reason="STOP_COUNT_INVALID",nativeDispatchAllowed=false}
 end
 if route.shape=="FROM_PLAYER" and not point(route.startPosition) then
  return {valid=false,reason="START_POSITION_INVALID",nativeDispatchAllowed=false}
 end
 for i=1,count do
  if not point(route.points[i]) then
   return {valid=false,reason="ROUTE_POINT_INVALID",index=i,nativeDispatchAllowed=false}
  end
 end
 if route.nativeDispatchAllowed~=false or route.terrainValidated==true then
  return {valid=false,reason="PATH_AUTHORITY_INVALID",nativeDispatchAllowed=false}
 end
 if route.closed~=(route.shape=="LOOP") then
  return {valid=false,reason="CLOSURE_INVALID",nativeDispatchAllowed=false}
 end
 local normalized=0
 for i=2,count do
  local a,b=route.points[i-1],route.points[i]
  normalized=normalized+math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
 end
 if route.shape=="LOOP" then
  local a,b=route.points[count],route.points[1]
  normalized=normalized+math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
 else
  local a,b=route.startPosition,route.points[1]
  normalized=normalized+math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
 end
 return {valid=true,reason="ADVISORY_GEOMETRY_ONLY",stopCount=count,
  normalizedLength=normalized,terrainValidated=false,liveNodesVerified=false,
  walkabilityVerified=false,notTravelDistance=true,nativeDispatchAllowed=false}
end
function Guard:InspectActive(mapID)
 local router=JLP:GetModule("GatheringRouteService")
 if not router or type(router.GetRoutes)~="function" then
  return {status="ROUTE_SERVICE_UNAVAILABLE",nativeDispatchAllowed=false}
 end
 local routes,status=router:GetRoutes(mapID)
 local out={mapID=mapID,status=status or "UNAVAILABLE",routes={},
  terrainValidated=false,nativeDispatchAllowed=false}
 if status=="READY" and type(routes)=="table" then
  for _,key in ipairs({"HERBALISM","MINING"}) do
   if routes[key] then out.routes[key]=self:InspectRoute(routes[key]) end
  end
 end
 return out
end
JLP:RegisterModule("GatheringPathingDiagnostics",Guard)
