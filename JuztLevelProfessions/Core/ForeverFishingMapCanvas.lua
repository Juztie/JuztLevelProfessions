local _, JLP = ...
-- Advisory 1.60.1+ map-art adapter. All uiMapIDs, tile IDs and player positions
-- originate from the running Blizzard client. NO synthetic pins or coordinates.
local Map={contract="forever-fishing-client-map-art-v1",nativeDispatchAllowed=false,
    mapTilesFromBlizzard=true,requiresLiveQA=false,hasFishingPins=false}
local function posint(v)
    if type(v)~="number" or v~=v or v==math.huge or v<1 or v~=math.floor(v) then return nil end
    return v
end
local function n(v)
    if type(v)~="number" or v~=v or v==math.huge or v<=0 then return nil end
    return v
end
-- Reject non-finite pan/zoom inputs at the presentation boundary.
local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function saneZoom(v)
    return finite(v) and math.max(1,math.min(3.5,v)) or 1
end
local function saneCenter(v)
    return finite(v) and math.max(0,math.min(1,v)) or 0.5
end
local function safe(fn,...)
    if type(fn)~="function" then return nil end
    local ok,result=pcall(fn,...)
    if ok then return result end
    return nil
end
function Map:GetZoneByID(mapID,rawSkill,bonus)
    local api=C_Map
    if type(api)~="table" or type(api.GetMapInfo)~="function" then return nil,"MAP_API_UNAVAILABLE" end
    if not posint(mapID) then return nil,"MAP_ID_INVALID" end
    local info=safe(api.GetMapInfo,mapID)
    if type(info)~="table" or info.mapType~=3 or
       type(info.name)~="string" or info.name=="" then return nil,"ZONE_MAP_UNAVAILABLE" end
    local result={contract=self.contract,mapID=mapID,name=info.name,source="C_Map.GetMapInfo",
        isClientMap=true,mapPinsAvailable=false,requiresLiveQA=false,nativeDispatchAllowed=false,
        fishingRequirement=nil,fishingRequirementStatus="MAP_ID_UNVERIFIED"}
    -- Fishing-area exceptions are deliberately not resolved from base-zone names.
    local skill=tonumber(rawSkill)
    if skill and skill>=0 then
        local guide=JLP:GetModule("ForeverFishingZoneModel")
        local model=guide and guide:LookupMap(mapID,skill,bonus) 
        if model and model.selected then
            result.fishingRequirement=model.selected
            result.fishingRequirementStatus="WOWHEAD_FOREVER_ZONE_MATCH"
            result.requirementSourceURL=model.sourceURL
            result.requirementIdentitySource=model.identitySource
        end
    end
    return result
end
function Map:GetCurrentZone(rawSkill,bonus)
    local api=C_Map
    if type(api)~="table" or type(api.GetBestMapForUnit)~="function" or
       type(api.GetMapInfo)~="function" then return nil,"MAP_API_UNAVAILABLE" end
    local id=posint(safe(api.GetBestMapForUnit,"player"))
    if not id then return nil,"PLAYER_MAP_UNAVAILABLE" end
    local info=safe(api.GetMapInfo,id)
    -- Resolve micro/dungeon maps to the current zone with bounded traversal.
    local visits={}
    for _=1,6 do
        if type(info)~="table" or visits[id] then return nil,"ZONE_MAP_UNAVAILABLE" end
        visits[id]=true
        if info.mapType==3 or (info.mapType==nil and type(info.name)=="string") then break end
        if type(info.mapType)=="number" and info.mapType<3 then return nil,"ZONE_MAP_UNAVAILABLE" end
        id=posint(info.parentMapID)
        if not id then return nil,"ZONE_MAP_UNAVAILABLE" end
        info=safe(api.GetMapInfo,id)
    end
    if type(info)~="table" or (info.mapType~=nil and info.mapType~=3) or
       type(info.name)~="string" or info.name=="" then return nil,"ZONE_MAP_UNAVAILABLE" end
    local result
    if info.mapType==nil then
        -- Preserve alpha147's conservative nil-mapType client fallback.
        result={contract=self.contract,mapID=id,name=info.name,source="C_Map.GetMapInfo",
            isClientMap=true,mapPinsAvailable=false,requiresLiveQA=false,nativeDispatchAllowed=false,
            fishingRequirement=nil,fishingRequirementStatus="MAP_ID_UNVERIFIED"}
    else
        result=self:GetZoneByID(id,rawSkill,bonus)
    end
    if not result then return nil,"ZONE_MAP_UNAVAILABLE" end
    if type(api.GetPlayerMapPosition)=="function" then
        local point=safe(api.GetPlayerMapPosition,id,"player")
        if (type(point)=="table" or type(point)=="userdata") and type(point.GetXY)=="function" then
            local ok,x,y=pcall(point.GetXY,point)
            if ok and type(x)=="number" and type(y)=="number" and
               x==x and y==y and x>=0 and x<=1 and y>=0 and y<=1 then
                result.playerPosition={mapID=id,x=x,y=y,source="C_Map.GetPlayerMapPosition"}
            end
        end
    end
    if info.mapType==nil then
        local skill=tonumber(rawSkill)
        if skill and skill>=0 then
            local guide=JLP:GetModule("ForeverFishingZoneModel")
            local model=guide and guide:LookupMap(id,skill,bonus) 
            if model and model.selected then
                result.fishingRequirement=model.selected
                result.fishingRequirementStatus="WOWHEAD_FOREVER_ZONE_MATCH"
                result.requirementSourceURL=model.sourceURL
                result.requirementIdentitySource=model.identitySource
            end
        end
    end
    return result
end
function Map:GetMapTiles(mapID)
    local api=C_Map
    if type(api)~="table" or type(api.GetMapArtLayers)~="function" or
       type(api.GetMapArtLayerTextures)~="function" then return nil,"MAP_ART_API_UNAVAILABLE" end
    if not posint(mapID) then return nil,"MAP_ID_INVALID" end
    local layers=safe(api.GetMapArtLayers,mapID)
    local layer=type(layers)=="table" and layers[1]
    if type(layer)~="table" then return nil,"MAP_ART_NOT_LOADED" end
    local width,height,tileW,tileH=n(layer.layerWidth),n(layer.layerHeight),n(layer.tileWidth),n(layer.tileHeight)
    if not width or not height or not tileW or not tileH then return nil,"MAP_ART_GEOMETRY_INVALID" end
    local cols,rows=math.ceil(width/tileW),math.ceil(height/tileH)
    local count=cols*rows
    if count<1 or count>64 then return nil,"MAP_ART_TILE_LIMIT" end
    local files=safe(api.GetMapArtLayerTextures,mapID,1)
    if type(files)~="table" or #files~=count then return nil,"MAP_ART_TILES_INCOMPLETE" end
    for i=1,count do
        if not posint(files[i]) then return nil,"MAP_ART_TEXTURE_INVALID" end
    end
    return {mapID=mapID,width=width,height=height,tileWidth=tileW,tileHeight=tileH,
        columns=cols,rows=rows,fileIDs=files,count=count,source="C_Map.GetMapArtLayerTextures",
        pinsAvailable=false,coordinatesInvented=false}
end
-- Per-viewport visual transform. It does not change source map coordinates,
-- gathering routes, mapID or SavedVariables. The crop keeps all tiles inside
-- the frame even when WoW's SetClipsChildren API is unavailable.
function Map:ViewTransform(canvas,art)
    local aw=canvas and canvas.GetWidth and canvas:GetWidth() or 740
    local ah=canvas and canvas.GetHeight and canvas:GetHeight() or 350
    aw=n(aw) or 740;ah=n(ah) or 350
    local state=canvas and canvas.gatheringView or nil
    local zoom=saneZoom(state and state.zoom)
    local cx=saneCenter(state and state.centerX)
    local cy=saneCenter(state and state.centerY)
    local scale=math.min(aw/art.width,ah/art.height)*zoom
    local fullW,fullH=art.width*scale,art.height*scale
    -- The centre may travel only until the corresponding edge is visible.
    local maxX=math.max(0,(fullW-aw)/(2*fullW))
    local maxY=math.max(0,(fullH-ah)/(2*fullH))
    cx=math.max(0.5-maxX,math.min(0.5+maxX,cx))
    cy=math.max(0.5-maxY,math.min(0.5+maxY,cy))
    if state then state.centerX=cx;state.centerY=cy;state.zoom=zoom end
    return {width=aw,height=ah,scale=scale,
        left=aw/2-cx*fullW,top=ah/2-cy*fullH,zoom=zoom}
end
function Map:SetViewport(canvas,zoom,cx,cy)
    if not canvas then return false end
    local current=canvas.gatheringView or {}
    local wantedZoom=tonumber(zoom) or tonumber(current.zoom)
    local wantedX=tonumber(cx) or tonumber(current.centerX)
    local wantedY=tonumber(cy) or tonumber(current.centerY)
    canvas.gatheringView={zoom=saneZoom(wantedZoom),
        centerX=saneCenter(wantedX),centerY=saneCenter(wantedY)}
    return true
end
function Map:Render(canvas,art)
    if not canvas or type(canvas.CreateTexture)~="function" then return false,"CANVAS_UNAVAILABLE" end
    if not art or not art.fileIDs then return false,"MAP_ART_UNAVAILABLE" end
    -- Reuse the existing texture widgets; changing maps never leaks old art.
    canvas.fishingTiles=canvas.fishingTiles or {}
    local visible=canvas.fishingTiles
    local transform=self:ViewTransform(canvas,art)
    local scale,left,top=transform.scale,transform.left,transform.top
    local index=0
    for row=0,art.rows-1 do
        for col=0,art.columns-1 do
            index=index+1
            local texture=visible[index]
            if not texture then texture=canvas:CreateTexture(nil,"ARTWORK",nil,-2);visible[index]=texture end
            local dx,dy=col*art.tileWidth,row*art.tileHeight
            local srcW=math.min(art.tileWidth,art.width-dx)
            local srcH=math.min(art.tileHeight,art.height-dy)
            local x0,y0=left+dx*scale,top+dy*scale
            local x1,y1=x0+srcW*scale,y0+srcH*scale
            local vx0,vx1=math.max(0,x0),math.min(transform.width,x1)
            local vy0,vy1=math.max(0,y0),math.min(transform.height,y1)
            if vx1>vx0 and vy1>vy0 then
                if texture.ClearAllPoints then texture:ClearAllPoints() end
                local fileID=art.fileIDs[index]
                if texture.__jlpBaseFileID~=fileID then
                    texture:SetTexture(fileID)
                    texture.__jlpBaseFileID=fileID
                end
                texture:SetPoint("TOPLEFT",canvas,"TOPLEFT",vx0,-vy0)
                texture:SetSize(vx1-vx0,vy1-vy0)
                if texture.SetTexCoord then
                    texture:SetTexCoord((vx0-x0)/(art.tileWidth*scale),(vx1-x0)/(art.tileWidth*scale),
                        (vy0-y0)/(art.tileHeight*scale),(vy1-y0)/(art.tileHeight*scale))
                end
                texture:Show()
            else texture:Hide() end
        end
    end
    for i=index+1,#visible do visible[i]:Hide() end
    canvas.fishingMapID=art.mapID
    canvas.fishingTilesVisible=index
    return true
end
function Map:ProjectNormalizedToCanvas(canvas,art,x,y)
    if not canvas or not art or not n(art.width) or not n(art.height) or
       type(x)~="number" or type(y)~="number" or x~=x or y~=y or
       x<0 or x>1 or y<0 or y>1 then return nil end
    local t=self:ViewTransform(canvas,art)
    return t.left+x*art.width*t.scale,-t.top-y*art.height*t.scale
end
-- Alpha259: bounded, render-local POINT projector. ViewTransform clamps the
-- viewport ONCE, rather than once for every historical reference point.
-- Never persisted, shared across maps, or used to invent AREA coordinates.
function Map:PrepareNormalizedProjection(canvas,art)
    if not canvas or not art or not n(art.width) or not n(art.height) then return nil end
    local transform=self:ViewTransform(canvas,art)
    local left,top=transform.left,transform.top
    local scale=transform.scale
    local projector=function(x,y)
        if type(x)~="number" or type(y)~="number" or x~=x or y~=y or
            x<0 or x>1 or y<0 or y>1 then return nil end
        -- Preserve the public projector's operand order for boundary parity.
        return left+x*art.width*scale,-top-y*art.height*scale
    end
    -- Second optional return is a conservative, render-local POINT visibility
    -- envelope derived from the SAME transform. An epsilon avoids rejecting
    -- floating-point boundary winners. No persisted or shared source cache.
    local dx,dy=art.width*scale,art.height*scale
    if type(dx)=="number" and type(dy)=="number" and dx>0 and dy>0 and
        dx<math.huge and dy<math.huge and left==left and top==top and
        type(transform.width)=="number" and type(transform.height)=="number" then
        local eps=1e-7
        return projector,{contract="NORMALIZED_MAP_VISIBILITY_ENVELOPE_V1",
            minX=-left/dx-eps,maxX=(transform.width-left)/dx+eps,
            minY=-top/dy-eps,maxY=(transform.height-top)/dy+eps}
    end
    return projector
end
function Map:PlacePlayerMarker(canvas,art,position)
    if not canvas or not art or not position then return false end
    local px,py=self:ProjectNormalizedToCanvas(canvas,art,position.x,position.y)
    local w=canvas.GetWidth and canvas:GetWidth() or 740
    local h=canvas.GetHeight and canvas:GetHeight() or 350
    if not px or px<0 or px>w or py>0 or py< -h then
        self:HidePlayerMarker(canvas);return false end
    -- A dedicated, mouse-transparent frame ABOVE pin buttons owns the arrow.
    local markerHost=canvas.playerMarkerLayer or canvas
    if markerHost~=canvas and markerHost.SetFrameLevel and canvas.GetFrameLevel then
        markerHost:SetFrameLevel(canvas:GetFrameLevel()+5)
    end
    -- Display a prominent Blizzard-derived player arrow with a glowing halo.
    -- Coordinates remain the observed in-client player position.
    if not canvas.fishingPlayerMarkerRing then
        local ring=markerHost:CreateTexture(nil,"OVERLAY")
        ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        ring:SetSize(44,44)
        if ring.SetBlendMode then ring:SetBlendMode("ADD") end
        if ring.SetVertexColor then ring:SetVertexColor(1,0.8,0.16,0.95) end
        canvas.fishingPlayerMarkerRing=ring
    end
    if not canvas.fishingPlayerMarker then
        canvas.fishingPlayerMarker=markerHost:CreateTexture(nil,"OVERLAY")
        canvas.fishingPlayerMarker:SetTexture("Interface\\Minimap\\MinimapArrow")
        canvas.fishingPlayerMarker:SetSize(30,30)
    end
    local ring=canvas.fishingPlayerMarkerRing
    local marker=canvas.fishingPlayerMarker
    if ring then
        if ring.ClearAllPoints then ring:ClearAllPoints() end
        ring:SetPoint("CENTER",canvas,"TOPLEFT",px,py)
        ring:Show()
    end
    if marker.ClearAllPoints then marker:ClearAllPoints() end
    marker:SetPoint("CENTER",canvas,"TOPLEFT",px,py)
    marker:Show()
    return true
end
function Map:HidePlayerMarker(canvas)
    if canvas and canvas.fishingPlayerMarker then canvas.fishingPlayerMarker:Hide() end
    if canvas and canvas.fishingPlayerMarkerRing then canvas.fishingPlayerMarkerRing:Hide() end
end
function Map:Clear(canvas)
    if not canvas then return end
    for _,tex in ipairs(canvas.fishingTiles or {}) do tex:Hide() end
    local reveal=JLP:GetModule("MapRevealRenderer")
    if reveal then reveal:Clear(canvas) end
    canvas.fishingMapID=nil; canvas.fishingTilesVisible=0
    self:HidePlayerMarker(canvas)
    local overlay=JLP:GetModule("GatheringMapOverlay")
    if overlay then overlay:Clear(canvas) end
end
JLP:RegisterModule("ForeverFishingMapCanvas",Map)
