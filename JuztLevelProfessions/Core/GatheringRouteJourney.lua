local _,JLP=...
-- One read-only view receipt contract shared by standalone, embedded and QA.
-- READY is a ROUTE status. A stroke submission is a CANVAS observation.
-- Even a matching MarkOverlayPresented receipt cannot prove native pixels.
local Journey={contract="gathering-route-journey-view-receipt-v1",nativeDispatchAllowed=false}
local function validToken(v) return type(v)=="string" and v~="" end
local function validMap(v) return type(v)=="number" and v>0 and v==math.floor(v) end
local function countPoints(routes)
    local total=0
    for _,route in pairs(type(routes)=="table" and routes or {}) do
        if type(route)=="table" and type(route.points)=="table" then total=total+#route.points end
    end
    return total
end
function Journey:Inspect(mapID,viewer)
    local result={mapID=mapID,state="NO_MAP",ready=false,points=0,strokes=0,
        receiptValid=false,viewerVisible=false,submitted=false,nativeFirstPaint="UNKNOWN",
        nativeDispatchAllowed=false}
    if not validMap(mapID) then return result end
    local router=JLP:GetModule("GatheringRouteService")
    if not router then result.state="ROUTE_SERVICE_UNAVAILABLE";return result end
    local okay,rows,status=pcall(router.GetRoutes,router,mapID)
    if not okay then result.state="ROUTE_SERVICE_ERROR";return result end
    if status==nil or status=="NO_ACTIVE_ROUTE" then
        if type(router.GetStatusForMap)=="function" then
            local ok,st=pcall(router.GetStatusForMap,router,mapID)
            if ok then status=st end
        end
    end
    result.routeStatus=status or "NO_ACTIVE_ROUTE"
    local tokenOK,token=pcall(router.GetContextToken,router,mapID)
    local contextOK,current=false,false
    -- Separate return capture: pcall() first return is invocation success.
    if type(router.ContextIsCurrent)=="function" then
        local ok,valid=pcall(router.ContextIsCurrent,router,mapID)
        contextOK=ok;current=valid==true
    end
    local owner=router._presentationContext
    local diag=type(router.GetSchedulerDiagnostics)=="function" and
        router:GetSchedulerDiagnostics() or nil
    result.generation=owner and owner.mapID==mapID and owner.generation or nil
    result.tokenValid=tokenOK and validToken(token) and contextOK and current==true and
        owner and owner.mapID==mapID and owner.generation==router._schedulerGeneration or false
    result.points=countPoints(rows)
    result.ready=status=="READY" and result.tokenValid==true and result.points>0
    result.schedulerTicks=diag and diag.ticks
    result.commitElapsedMs=diag and diag.commitElapsedMs
    local visible=type(viewer)=="table" and viewer.visible==true
    result.viewerVisible=visible
    local strokes=viewer and viewer.strokes
    result.strokes=type(strokes)=="number" and strokes>0 and math.floor(strokes) or 0
    result.submitted=result.ready and viewer and viewer.routeSubmitted==true and result.strokes>0 or false
    local receipt=viewer and viewer.receipt
    result.receiptValid=result.submitted==true and visible and type(receipt)=="table" and
        receipt.mapID==mapID and receipt.token==token and
        (receipt.strokes or result.strokes)>0 or false
    if status=="GENERATING" then result.state="GENERATING"
    elseif status=="CANCELLED" or status=="CLEARED_BY_USER" then result.state="CANCELLED"
    elseif status=="ERROR" or status=="ROUTE_ERROR" then result.state="ERROR"
    elseif result.ready then
        if not visible then result.state="READY_VIEW_HIDDEN"
        elseif result.strokes==0 then result.state="READY_NO_STROKES"
        elseif not result.submitted then result.state="READY_STROKES_UNCONFIRMED"
        elseif not result.receiptValid then result.state="READY_RECEIPT_PENDING"
        else result.state="READY_OVERLAY_SUBMITTED" end
    elseif status=="READY" then result.state="READY_CONTEXT_UNQUALIFIED"
    else result.state=status or "NO_ACTIVE_ROUTE" end
    return result
end
function Journey:Summary(result)
    result=type(result)=="table" and result or {state="NO_MAP"}
    if result.state=="READY_OVERLAY_SUBMITTED" then
        return "Route "..tostring(result.points).." stops · "..tostring(result.strokes)..
            " strokes submitted · receipt matches · native pixels UNKNOWN"
    elseif result.state=="READY_RECEIPT_PENDING" then
        return "Route "..tostring(result.points).." stops · "..tostring(result.strokes)..
            " strokes · presentation receipt pending; refresh map"
    elseif result.state=="READY_NO_STROKES" or result.state=="READY_STROKES_UNCONFIRMED" then
        return "Route ready · no confirmed visible lines · use Show Route"
    elseif result.state=="READY_VIEW_HIDDEN" then
        return "Route ready · view hidden; open map to inspect presentation"
    elseif result.state=="GENERATING" then return "Generating advisory route…"
    elseif result.state=="CANCELLED" then return "Route stopped · selections preserved"
    elseif result.state=="READY_CONTEXT_UNQUALIFIED" then
        return "Route context changed · rerun Generate"
    elseif result.state=="NO_MAP" then return "Choose a supported map"
    else return "Route "..tostring(result.state or "UNKNOWN").." · no visible route confirmed" end
end
JLP:RegisterModule("GatheringRouteJourney",Journey)
