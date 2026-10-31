local _, JLP = ...
-- M12: Non-mutating diagnostics, not navigation/crafting authorization.
-- Observes currently published service/viewport receipts; never calls Start,
-- SetViewport, Refresh, GetArt, SetUserWaypoint or owner NavigateTo.
local Audit={contract="jlp-navigation-map-route-audit-v1",nativeDispatchAllowed=false}
local function finite(x)
    return type(x)=="number" and x==x and x~=math.huge and x~=-math.huge
end
local function integer(x) return finite(x) and x>=1 and x==math.floor(x) end
local function call(module,method,...)
    if type(module)~="table" or type(module[method])~="function" then return nil,"SERVICE_UNAVAILABLE" end
    local ok,value,extra=pcall(module[method],module,...)
    if not ok then return nil,"SERVICE_ERROR" end
    return value,extra
end
function Audit:Inspect()
    local state=JLP:GetModule("GatheringSharedMapState")
    local snapshot=call(state,"GetSnapshot")
    local window=JLP.StandaloneGatheringMap or JLP:GetModule("StandaloneGatheringMap")
    local frame=window and window.frame
    local canvas=frame and frame.canvas
    local continent=window and window._continentPreview
    local mapID=continent and continent.mapID or
        window and window.lastView and window.lastView.mapID or
        snapshot and snapshot.selectedMapID
    local service=JLP:GetModule("GatheringMapViewService")
    local route=JLP:GetModule("GatheringRouteService")
    local nav=JLP:GetModule("Navigation")
    local owner=JLP:GetModule("IntegratedDestinationOwner")
    local engine=JLP:GetModule("IntegratedTravelEngine")
    local common=JLP:GetModule("UnifiedDestinationNavigation")
    local response={contract=self.contract,nativeDispatchAllowed=false,
        nativeVisualVerification="NOT_PERFORMED",routeExecutionAuthorized=false,
        mapID=integer(mapID) and mapID or nil,
        mode=snapshot and snapshot.mode or "UNAVAILABLE",
        zoom=canvas and canvas.gatheringView and canvas.gatheringView.zoom or nil,
        continentPreview=continent~=nil,
        viewerVisible=frame and type(frame.IsShown)=="function" and frame:IsShown()==true or false,
        selectedMapID=snapshot and snapshot.selectedMapID,
        tileStatus="VIEW_NOT_PRESENT",routeStatus="NO_ROUTE_CONTEXT",
        routePresentation="NOT_VERIFIED",destinationStatus="NONE",
        travelStatus="NOT_READ"}
    local capabilities=call(nav,"GetCapabilities")
    response.waypointAvailable=type(capabilities)=="table" and capabilities.canWaypoint==true
    response.mapOpenAvailable=type(capabilities)=="table" and capabilities.canOpenMap==true
    if canvas then
        local art=window.lastArt
        local tiles=tonumber(canvas.fishingTilesVisible) or 0
        response.tileStatus=art and integer(art.mapID) and
            art.mapID==canvas.fishingMapID and tiles==art.count and
            canvas.__jlpTileArtKey~=nil and "ART_SUBMITTED" or "ART_UNVERIFIED"
        response.artMapID=art and art.mapID
        response.artTiles=art and art.count or nil
        response.submittedTiles=tiles
        response.strokes=tonumber(canvas.gatheringRouteStrokesVisible) or 0
    end
    local diagnostics=call(service,"GetArtDiagnostics")
    if type(diagnostics)=="table" then
        response.cachedArtMaps=diagnostics.cacheCount
        response.artFetchFailures=diagnostics.fetchFailures
        response.overlayFailures=diagnostics.overlayRenderFailures
    end
    if response.mapID and not response.continentPreview then
        local current=call(route,"ContextIsCurrent",response.mapID)
        local status=call(route,"GetStatusForMap",response.mapID)
        response.routeStatus=type(status)=="string" and status or "STATUS_UNAVAILABLE"
        response.routeContextCurrent=current==true
        local journey=JLP:GetModule("GatheringRouteJourney")
        local token=call(route,"GetContextToken",response.mapID)
        local receipt=window and window._mapPresentation
        local inspection=call(journey,"Inspect",response.mapID,{
            visible=response.viewerVisible,
            strokes=tonumber(window and window._lastRouteStrokesSubmitted) or 0,
            routeSubmitted=window and window._lastRouteOverlaySubmitted==true,
            receipt=receipt})
        if type(inspection)=="table" then
            response.routePresentation=inspection.state or "NOT_VERIFIED"
            response.routePoints=inspection.points
            response.routeReceiptValid=inspection.receiptValid==true
            response.routeTokenValid=inspection.tokenValid==true
        end
        response.tokenAvailable=type(token)=="string" and token~=""
        local pathing=JLP:GetModule("GatheringPathingDiagnostics")
        local pathSnapshot=call(pathing,"InspectActive",response.mapID)
        if type(pathSnapshot)=="table" then
            response.pathingStatus=pathSnapshot.status
            response.pathingGeometry={}
            for _,key in ipairs({"HERBALISM","MINING"}) do
                local record=pathSnapshot.routes and pathSnapshot.routes[key]
                if record then
                    response.pathingGeometry[key]={valid=record.valid,
                        reason=record.reason,stopCount=record.stopCount,
                        normalizedLength=record.normalizedLength}
                end
            end
            response.pathingTerrainVerified=false
        end
    elseif response.continentPreview then
        response.routeStatus="CONTINENT_VIEW_ONLY"
        response.routePresentation="NO_ROUTE_OVERLAY_ON_CONTINENT"
    end
    -- Only inspect already-published state. Do NOT initialize the travel graph
    -- during a map audit: that would be a state mutation.
    if type(owner)=="table" then
        local a=owner.active
        response.destinationStatus=type(a)=="table" and
            (a.needsRevalidation and "NEEDS_REVALIDATION" or a.sourceStatus or "SELECTED") or "NONE"
        response.destinationMapID=type(a)=="table" and a.point and a.point.mapID or nil
    end
    local commonState=call(common,"Inspect")
    response.destinationConsistency=type(commonState)=="table" and
        commonState.waypointConsistency or "UNAVAILABLE"
    response.destinationGeneration=type(commonState)=="table" and
        commonState.generation or nil
    if type(engine)=="table" then
        response.travelStatus=engine.initialized==true and
            (engine.ownerDatasetStatus or engine.datasetStatus or "INITIALIZED") or "NOT_INITIALIZED"
    end
    return response
end
function Audit:Print(scope)
    scope=scope or "all"
    if scope~="all" and scope~="map" and scope~="route" and scope~="travel" then
        return false,"USE_NAVQA_ALL_MAP_ROUTE_TRAVEL" end
    local row=self:Inspect()
    local printLine=type(JLP.Print)=="function" and function(message) JLP:Print(message) end or function() end
    printLine("M12 read-only navigation QA · no live visual certification")
    if scope=="all" or scope=="map" then
        printLine("Map: "..tostring(row.mapID or "none").." / "..tostring(row.tileStatus)..
            " / preview="..tostring(row.continentPreview).." / zoom="..tostring(row.zoom or "n/a"))
        printLine("Map API: open="..tostring(row.mapOpenAvailable)..
            " / waypoint="..tostring(row.waypointAvailable)..
            " / cached art="..tostring(row.cachedArtMaps or "n/a"))
    end
    if scope=="all" or scope=="route" then
        printLine("Gathering route: "..tostring(row.routeStatus)..
            " / context="..tostring(row.routeContextCurrent)..
            " / overlay="..tostring(row.routePresentation))
        printLine("Route geometry: strokes="..tostring(row.strokes or 0)..
            " / points="..tostring(row.routePoints or "n/a")..
            " / receipt="..tostring(row.routeReceiptValid==true))
        local geometry=row.pathingGeometry or {}
        for _,key in ipairs({"HERBALISM","MINING"}) do
            local checked=geometry[key]
            if checked then printLine("Pathing "..key..": "..tostring(checked.reason)..
                " / stops="..tostring(checked.stopCount or "invalid").." / terrain=false") end
        end
    end
    if scope=="all" or scope=="travel" then
        printLine("Destination: "..tostring(row.destinationStatus)..
            " / map="..tostring(row.destinationMapID or "none")..
            " / waypoint="..tostring(row.destinationConsistency)..
            " / travel="..tostring(row.travelStatus))
    end
    return true,row
end
JLP:RegisterModule("NavigationMapRouteAudit",Audit)
