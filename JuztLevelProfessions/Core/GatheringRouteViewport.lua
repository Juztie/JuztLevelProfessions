local _, JLP = ...
-- Shared, advisory-only visual navigation. Geometry belongs to each canvas;
-- generation, resources and map selection remain owned by their existing services.
local Focus={contract="gathering-route-viewport-v1",nativeDispatchAllowed=false}
local function finite(v)
    return type(v)=="number" and v==v and v>-math.huge and v<math.huge
end
function Focus:Calculate(snapshot,mapID,canvas,art)
    if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then
        return nil,"MAP_ID_INVALID" end
    if type(snapshot)~="table" or snapshot.mapID~=mapID or
        type(snapshot.routes)~="table" then return nil,"ROUTE_UNAVAILABLE" end
    if not canvas or not art or not finite(art.width) or not finite(art.height) or
        art.width<=0 or art.height<=0 then return nil,"MAP_ART_UNAVAILABLE" end
    local cw=canvas.GetWidth and canvas:GetWidth() or nil
    local ch=canvas.GetHeight and canvas:GetHeight() or nil
    if not finite(cw) or not finite(ch) or cw<=0 or ch<=0 then
        return nil,"VIEWPORT_UNAVAILABLE" end
    local minX,maxX,minY,maxY=1,0,1,0
    local count=0
    for _,key in ipairs({"HERBALISM","MINING"}) do
        local route=snapshot.routes[key]
        if type(route)=="table" and type(route.points)=="table" then
            for _,point in ipairs(route.points) do
                count=count+1
                if count>4096 then return nil,"ROUTE_TOO_LARGE" end
                if type(point)~="table" or not finite(point.x) or not finite(point.y) or
                    point.x<0 or point.x>1 or point.y<0 or point.y>1 then
                    return nil,"ROUTE_POINT_INVALID" end
                minX=math.min(minX,point.x);maxX=math.max(maxX,point.x)
                minY=math.min(minY,point.y);maxY=math.max(maxY,point.y)
            end
        end
    end
    if count==0 then return nil,"ROUTE_EMPTY" end
    local scale=math.min(cw/art.width,ch/art.height)
    local fullW,fullH=art.width*scale,art.height*scale
    local spanX=math.max(0.02,maxX-minX)
    local spanY=math.max(0.02,maxY-minY)
    local zoom=math.min(3.5,0.82*cw/(spanX*fullW),0.82*ch/(spanY*fullH))
    if count==1 then zoom=math.min(zoom,2.5) end
    return {mapID=mapID,centerX=(minX+maxX)/2,centerY=(minY+maxY)/2,
        zoom=math.max(1,zoom),pointCount=count,nativeDispatchAllowed=false}
end
function Focus:Apply(canvas,art,snapshot,mapID)
    local target,reason=self:Calculate(snapshot,mapID,canvas,art)
    if not target then return false,reason end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    if not map or type(map.SetViewport)~="function" then return false,"MAP_SERVICE_UNAVAILABLE" end
    local ok,applied=pcall(map.SetViewport,map,canvas,target.zoom,target.centerX,target.centerY)
    if not ok or applied~=true then return false,"VIEWPORT_UPDATE_FAILED" end
    return true,target
end
JLP:RegisterModule("GatheringRouteViewport",Focus)
