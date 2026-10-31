local _, JLP = ...
-- Client-owned zone hit testing for standalone Gathering Map. This module
-- interprets a real click in the displayed map artwork, never guesses zone
-- shapes from name labels and never mutates routes, position or exploration.
local Navigation={contract="jlp-gathering-map-click-navigation-v1",nativeDispatchAllowed=false}
local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function posint(v)
    return finite(v) and v>=1 and v==math.floor(v)
end
local function safely(fn,...)
    if type(fn)~="function" then return nil end
    local ok,result=pcall(fn,...)
    if ok then return result end
end
function Navigation:CursorToMap(canvas,art,screenX,screenY)
    if not (canvas and type(art)=="table" and finite(art.width) and art.width>0 and
        finite(art.height) and art.height>0 and finite(screenX) and finite(screenY)) then
        return nil,"CURSOR_OR_ART_UNAVAILABLE"
    end
    local scale=canvas.GetEffectiveScale and canvas:GetEffectiveScale()
    local left=canvas.GetLeft and canvas:GetLeft()
    local top=canvas.GetTop and canvas:GetTop()
    local width=canvas.GetWidth and canvas:GetWidth()
    local height=canvas.GetHeight and canvas:GetHeight()
    if not (finite(scale) and scale>0 and finite(left) and finite(top) and
        finite(width) and width>0 and finite(height) and height>0) then
        return nil,"CANVAS_BOUNDS_UNAVAILABLE"
    end
    -- GetCursorPosition uses screen pixels and a bottom-left origin, whereas
    -- the map viewport has a TOPLEFT origin and operates in UI units.
    local x=screenX/scale-left
    local y=top-screenY/scale
    if x<0 or y<0 or x>width or y>height then return nil,"OUTSIDE_CANVAS" end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    if not (map and type(map.ViewTransform)=="function") then return nil,"VIEW_TRANSFORM_UNAVAILABLE" end
    local t=map:ViewTransform(canvas,art)
    if type(t)~="table" or not (finite(t.scale) and t.scale>0 and
        finite(t.left) and finite(t.top)) then return nil,"VIEW_TRANSFORM_INVALID" end
    -- Inverse of native base-art / reveal projection, including zoom and pan.
    local nx=(x-t.left)/(art.width*t.scale)
    local ny=(y-t.top)/(art.height*t.scale)
    if nx<0 or nx>1 or ny<0 or ny>1 then return nil,"OUTSIDE_NATIVE_MAP_ART" end
    return {x=nx,y=ny,localX=x,localY=y},"NATIVE_ART_COORDINATES"
end
function Navigation:Resolve(canvas,art,sourceMapID,screenX,screenY)
    if not posint(sourceMapID) or not art or art.mapID~=sourceMapID then
        return nil,"STALE_MAP_ART"
    end
    local pos,reason=self:CursorToMap(canvas,art,screenX,screenY)
    if not pos then return nil,reason end
    local api=C_Map
    if type(api)~="table" or type(api.GetMapInfoAtPosition)~="function" or
        type(api.GetMapInfo)~="function" then return nil,"ZONE_HIT_API_UNAVAILABLE" end
    -- Includes adjacent map regions shown as part of a zone texture on native
    -- clients that publish zone-map hit geometry. Nothing is guessed if absent.
    local info=safely(api.GetMapInfoAtPosition,sourceMapID,pos.x,pos.y)
    local id=type(info)=="table" and info.mapID or nil
    local seen={}
    for _=1,6 do
        if not posint(id) or seen[id] then break end
        seen[id]=true
        local canonical=safely(api.GetMapInfo,id)
        if type(canonical)~="table" then break end
        if canonical.mapType==3 then
            if id==sourceMapID then return nil,"SAME_ZONE" end
            local browser=JLP:GetModule("ForeverFishingZoneBrowser")
            if not browser then return nil,"ZONE_BROWSER_UNAVAILABLE" end
            local continent=browser:IsContinentZone(id,"KALIMDOR") and "KALIMDOR" or
                browser:IsContinentZone(id,"EASTERN_KINGDOMS") and "EASTERN_KINGDOMS" or nil
            if not continent then return nil,"UNSUPPORTED_CONTINENT" end
            if type(canonical.name)~="string" or canonical.name=="" then
                return nil,"ZONE_NAME_UNAVAILABLE" end
            return {mapID=id,name=canonical.name,continent=continent,x=pos.x,y=pos.y},"CLIENT_ZONE_HIT"
        end
        -- Micro and dungeon maps may resolve to a real parent zone; continent
        -- maps may not. Limit traversal and refuse any ambiguous/cyclic chain.
        if type(canonical.mapType)~="number" or canonical.mapType<=3 then break end
        id=canonical.parentMapID
    end
    return nil,"NO_ADJACENT_ZONE_AT_POSITION"
end
JLP:RegisterModule("GatheringMapZoneClick",Navigation)
