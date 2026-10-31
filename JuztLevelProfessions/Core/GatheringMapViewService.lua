local _, JLP = ...
-- Shared, read-only map projection. Both viewers consume the same DB-backed
-- SharedMapState and route service. A per-zone art cache avoids duplicate C_Map
-- art calls; render textures and view geometry remain viewer-local.
local Service={contract="jlp-gathering-view-service-v1",nativeDispatchAllowed=false,maxCachedArtMaps=4}
local function artIdentity(art)
    local parts={tostring(art.mapID),tostring(art.count),tostring(art.width),
        tostring(art.height),tostring(art.tileWidth),tostring(art.tileHeight)}
    for i=1,art.count or 0 do
        parts[#parts+1]=tostring(art.fileIDs and art.fileIDs[i] or "UNKNOWN")
    end
    return table.concat(parts,":")
end
-- A new native fetch receives a new presentation receipt even when returned
-- file IDs are identical. This is per service, ephemeral, never persisted.
local function presentationIdentity(self,art)
    local receipt=self._artReceipts and self._artReceipts[art] or 0
    return artIdentity(art)..":fetch="..tostring(receipt)
end
local function viewportIdentity(canvas)
    local view=canvas.gatheringView or {}
    local width=canvas.GetWidth and canvas:GetWidth() or 0
    local height=canvas.GetHeight and canvas:GetHeight() or 0
    return table.concat({tostring(width),tostring(height),tostring(view.zoom or 1),
        tostring(view.centerX or 0.5),tostring(view.centerY or 0.5)},":")
end
function Service:Resolve(rawFishingSkill,bonus)
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local browser=JLP:GetModule("ForeverFishingZoneBrowser")
    local ctrl=JLP:GetModule("GatheringMapLayerController")
    local route=JLP:GetModule("GatheringRouteService")
    if not map or not browser or not ctrl then return nil,"MAP_SERVICE_UNAVAILABLE" end
    local current,why=map:GetCurrentZone(rawFishingSkill,bonus)
    if not current then return nil,why end
    local choice=browser:ResolveSelection(current,rawFishingSkill,bonus)
    local context=choice and choice.context or current
    if not context then return nil,"ZONE_UNAVAILABLE" end
    local routes,routeStatus=route and route:GetRoutes(context.mapID)
    return {mapID=context.mapID,name=context.name,context=context,current=current,
        selected=choice and choice.browsing or false,zoneCount=choice and #choice.zones or 0,
        playerPosition=current.mapID==context.mapID and current.playerPosition or nil,
        overlay=ctrl:BuildOverlay(context.mapID),
        spatial=JLP:GetModule("GatheringSpatialAreaCatalog") and
            JLP:GetModule("GatheringSpatialAreaCatalog"):GetMapSnapshot(context.mapID),
        routeSnapshot=routes and {mapID=context.mapID,routes=routes} or nil,
        routeStatus=routeStatus or "NO_ACTIVE_ROUTE",nativeDispatchAllowed=false}
end
-- Small LRU cache: keeps frequently revisited map art without decoding or
-- querying C_Map again. Cache contains native client art metadata, never copies
-- of Blizzard textures or recorded map tiles in SavedVariables.
function Service:GetArt(mapID,force)
    if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then
        return nil,"MAP_ID_INVALID" end
    self._artCache=self._artCache or {}
    self._artOrder=self._artOrder or {}
    local cache=self._artCache
    local order=self._artOrder
    local cached=not force and cache[mapID]
    if cached then
        self._artCacheHits=(self._artCacheHits or 0)+1
        for i=#order,1,-1 do if order[i]==mapID then table.remove(order,i);break end end
        order[#order+1]=mapID
        self._artID=mapID;self._art=cached
        return cached
    end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    -- Preserve the native service's failure reason. Lua `and` collapses
    -- multi-return values, previously losing the second return entirely.
    local art,reason
    self._artFetchAttempts=(self._artFetchAttempts or 0)+1
    if map and type(map.GetMapTiles)=="function" then
        -- A provider error must be indistinguishable from a failed fetch for
        -- cache-invalidation purposes, including forced refreshes. Do not
        -- propagate an exception across the UI repaint boundary.
        local ok,value,detail=pcall(map.GetMapTiles,map,mapID)
        if ok then art,reason=value,detail
        else reason="MAP_ART_FETCH_ERROR" end
    else
        reason="MAP_SERVICE_UNAVAILABLE"
    end
    if not art then self._artFetchFailures=(self._artFetchFailures or 0)+1 end
    if force and not art then
        -- A failed *forced* native reload must not leave the old receipt
        -- falsely valid for either viewer. Evict only this map, not the LRU.
        cache[mapID]=nil
        for i=#order,1,-1 do if order[i]==mapID then table.remove(order,i) end end
        if self._artID==mapID then self._artID=nil;self._art=nil end
    end
    if art then
        self._artFetchEpoch=(self._artFetchEpoch or 0)+1
        self._artReceipts=self._artReceipts or setmetatable({}, {__mode="k"})
        self._artReceipts[art]=self._artFetchEpoch
        cache[mapID]=art
        for i=#order,1,-1 do if order[i]==mapID then table.remove(order,i);break end end
        order[#order+1]=mapID
        local limit=math.max(1,math.min(4,math.floor(self.maxCachedArtMaps or 4)))
        while #order>limit do
            local oldest=table.remove(order,1)
            cache[oldest]=nil
        end
        self._artID=mapID;self._art=art
    end
    -- Failed API calls are never cached: the client may supply tiles later.
    return art,reason
end
-- Shared viewer-independent receipt: counts alone never prove tile identity.
function Service:IsTilePresentationCurrent(canvas,mapID)
    local art=self._artCache and self._artCache[mapID]
    return canvas~=nil and art~=nil and canvas.fishingMapID==mapID and
        canvas.fishingTilesVisible==art.count and
        canvas.__jlpTileArtKey==presentationIdentity(self,art) and
        canvas.__jlpTileViewportKey==viewportIdentity(canvas)
end
function Service:RenderArt(canvas,art,force)
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    if not canvas or not art or not map then return false,"ART_UNAVAILABLE" end
    local artKey=presentationIdentity(self,art)
    local viewKey=viewportIdentity(canvas)
    local needsTiles=canvas.fishingMapID~=art.mapID or force or
        canvas.fishingTilesVisible~=art.count or
        canvas.__jlpTileArtKey~=artKey or canvas.__jlpTileViewportKey~=viewKey
    if needsTiles then
        local ok,painted=pcall(map.Render,map,canvas,art)
        if not ok or painted~=true then
            self._artRenderFailures=(self._artRenderFailures or 0)+1
            -- Native texture mutations may be partially completed before a
            -- failure. Invalidate receipts FIRST, then attempt best-effort
            -- canvas cleanup; never claim the old image is current.
            canvas.__jlpTileArtKey=nil;canvas.__jlpTileViewportKey=nil
            if type(map.Clear)=="function" then pcall(map.Clear,map,canvas) end
            return false,"ART_RENDER_FAILED"
        end
        -- A provider can report true after drawing only part of the requested
        -- tile set. Never certify that partial native image as READY.
        if canvas.fishingTilesVisible~=art.count or canvas.fishingMapID~=art.mapID then
            self._artRenderFailures=(self._artRenderFailures or 0)+1
            canvas.__jlpTileArtKey=nil;canvas.__jlpTileViewportKey=nil
            if type(map.Clear)=="function" then pcall(map.Clear,map,canvas) end
            return false,"ART_RENDER_INCOMPLETE"
        end
        canvas.__jlpTileArtKey=artKey
        canvas.__jlpTileViewportKey=viewportIdentity(canvas)
    end
    return true,needsTiles
end
function Service:Render(canvas,view,force,forceArtFetch,standaloneReveal)
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local overlay=JLP:GetModule("GatheringMapOverlay")
    if not canvas or not map or not view then
        if map and canvas and type(map.Clear)=="function" then pcall(map.Clear,map,canvas) end
        return {ready=false,status="MAP_UNAVAILABLE",nativeDispatchAllowed=false}
    end
    -- A viewport redraw (resize/layer focus) must not invalidate immutable C_Map art metadata.
    local art,reason=self:GetArt(view.mapID,forceArtFetch==true)
    if not art then
        canvas.__jlpTileArtKey=nil;canvas.__jlpTileViewportKey=nil
        if type(map.Clear)=="function" then pcall(map.Clear,map,canvas) end
        return {ready=false,status=reason or "ART_UNAVAILABLE",nativeDispatchAllowed=false}
    end
    local rendered,needsTiles=self:RenderArt(canvas,art,force)
    if not rendered then return {ready=false,status=needsTiles or "ART_RENDER_FAILED",nativeDispatchAllowed=false} end
    -- Optional visual enhancement only. Failures must not affect gathering or
    -- route authority. The standalone window opts in; embedded viewers do not.
    local reveal=JLP:GetModule("MapRevealRenderer")
    if reveal then
        if standaloneReveal==true then
            local ok=pcall(reveal.Render,reveal,canvas,art)
            if not ok then pcall(reveal.Clear,reveal,canvas) end
        else pcall(reveal.Clear,reveal,canvas) end
    end
    -- READY is a route-service state, not proof that a route was submitted to
    -- the canvas. A successful tile/pin render without a source-bound route
    -- snapshot must not become an overlay receipt.
    local routeSubmitted=false
    if view.routeStatus=="READY" and type(view.routeSnapshot)=="table" and
        view.routeSnapshot.mapID==view.mapID and type(view.routeSnapshot.routes)=="table" then
        for _,routeData in pairs(view.routeSnapshot.routes) do
            if type(routeData)=="table" and type(routeData.points)=="table" and
                #routeData.points>0 then routeSubmitted=true;break end
        end
    end
    -- A failed overlay/player marker can leave a partial image. Never expose
    -- a READY report or retain a valid presentation receipt in that state.
    local ok,stats=pcall(function()
        local result=overlay and overlay:Render(canvas,art,view.overlay,map,view.routeSnapshot,view.spatial)
        if view.playerPosition then map:PlacePlayerMarker(canvas,art,view.playerPosition)
        else map:HidePlayerMarker(canvas) end
        return result
    end)
    -- A successful Lua call is not proof that the overlay accepted the map.
    -- A mismatched snapshot can return MAP_MISMATCH without throwing; it must
    -- never certify partially rendered tiles as a READY gathering canvas.
    if not ok or type(stats)~="table" or stats.status=="MAP_MISMATCH" then
        self._overlayRenderFailures=(self._overlayRenderFailures or 0)+1
        canvas.__jlpTileArtKey=nil;canvas.__jlpTileViewportKey=nil
        if type(map.Clear)=="function" then pcall(map.Clear,map,canvas) end
        if overlay and type(overlay.Clear)=="function" then pcall(overlay.Clear,overlay,canvas) end
        return {ready=false,status="ART_OVERLAY_FAILED",nativeDispatchAllowed=false}
    end
    local strokes=type(stats.routeStrokes)=="number" and stats.routeStrokes or 0
    return {ready=true,art=art,stats=stats,status="READY",
        routeOverlaySubmitted=routeSubmitted,routeStrokesSubmitted=strokes,
        routeGeometryStatus=not routeSubmitted and "NO_ROUTE_SNAPSHOT" or
            strokes>0 and "STROKES_SUBMITTED" or "NO_VISIBLE_ROUTE_STROKES",
        expectedTiles=art.count,visibleTiles=canvas.fishingTilesVisible or 0,
        tilesComplete=canvas.fishingTilesVisible==art.count,
        tileRenderTriggered=needsTiles,nativeDispatchAllowed=false}
end
-- Bounded visual-only pan path. The current verified read-model and native
-- artwork are captured at the previous full Refresh(). This routine never
-- resolves gathering source snapshots or touches route generation/receipts.
function Service:RenderPan(canvas,art,view)
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local overlay=JLP:GetModule("GatheringMapOverlay")
    if not (canvas and art and view and view.mapID==art.mapID and
        canvas.fishingMapID==art.mapID and map and overlay and
        type(overlay.RenderPan)=="function") then
        return false,"PAN_VIEW_UNAVAILABLE"
    end
    -- Validate the cached selection before any art mutation, so a stale map
    -- or source snapshot never leaves a half-updated drag presentation.
    local cache=canvas.__jlpSelectedPoints
    if not (cache and cache.art==art and cache.snapshot==view.overlay and
        cache.mapID==art.mapID) then return false,"PAN_CACHE_STALE" end
    local ok,painted=pcall(map.Render,map,canvas,art)
    if not ok or painted~=true then return false,"PAN_MAP_ART_FAILED" end
    local reveal=JLP:GetModule("MapRevealRenderer")
    if reveal then
        local valid=pcall(reveal.Render,reveal,canvas,art)
        if not valid then pcall(reveal.Clear,reveal,canvas) end
    end
    local ready,result=pcall(overlay.RenderPan,overlay,canvas,art,map,
        view.routeSnapshot,view.spatial)
    if not ready or result~=true then
        return false,"PAN_OVERLAY_FAILED"
    end
    if view.playerPosition then
        pcall(map.PlacePlayerMarker,map,canvas,art,view.playerPosition)
    else pcall(map.HidePlayerMarker,map,canvas) end
    self._panPreviewFrames=(self._panPreviewFrames or 0)+1
    -- Intentionally do NOT certify TilePresentationCurrent or route READY:
    -- final mouse-up must execute the complete snapshot-consistent refresh.
    return true,"PAN_PREVIEW"
end

-- Read-only bounded diagnostics: no C_Map calls, no persisted data.
function Service:GetArtDiagnostics()
    local maps={}
    for i,id in ipairs(self._artOrder or {}) do maps[i]=id end
    return {cachedMaps=maps,cacheCount=#maps,cacheLimit=4,
        cacheHits=self._artCacheHits or 0,fetchAttempts=self._artFetchAttempts or 0,
        fetchFailures=self._artFetchFailures or 0,
        artRenderFailures=self._artRenderFailures or 0,
        overlayRenderFailures=self._overlayRenderFailures or 0,
        fetchEpoch=self._artFetchEpoch or 0,nativeDispatchAllowed=false}
end
function Service:ClearCache()
    self._artID=nil;self._art=nil
    self._artCache=nil;self._artOrder=nil
end
JLP:RegisterModule("GatheringMapViewService",Service)
