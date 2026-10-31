local _, JLP = ...
-- Alpha173: one bounded, source-honest UI read model across embedded/standalone.
-- Every field is derived at refresh time; never persists choices or drives native actions.
local Present={contract="jlp-gathering-route-presentation-v2",nativeDispatchAllowed=false}
local KEYS={"HERBALISM","MINING"}
local NAMES={HERBALISM="Herbalism",MINING="Mining"}
local FOCUS={
    MATERIALS={name="Materials",why="Prioritizes required documented outputs; if no shortages, historical generic-material coverage"},
    SKILL={name="Skill",why="Prioritizes skill-eligible historical node types"},
    BALANCED={name="Balanced",why="Balances missing materials and possible skill progress"},
}
local EMPTY={
    NO_MATERIAL_DEMAND={"No missing materials reported", "Select Smart Skill or Balanced, or use Custom resources", "NO_ELIGIBLE"},
    NO_ELIGIBLE_ROUTE={"No eligible route in this zone", "Try another zone, enable a learned profession or change route focus", "NO_ELIGIBLE"},
    NO_ELIGIBLE_NODES={"No eligible historical nodes", "Try other resources, a suitable zone or a different route source", "NO_ELIGIBLE"},
    NO_SELECTED_ROUTE_POINTS={"No selected route points available", "Choose at least one resource with two eligible reference points, or change zone", "NO_ELIGIBLE"},
    GATHERING_DATA_UNAVAILABLE={"Gathering reference data unavailable", "Choose a supported zone and check learned gathering professions", "ERROR"},
    PLAYER_POSITION_UNAVAILABLE={"Player position unavailable", "Choose Loop shape or return to your current zone", "NO_ELIGIBLE"},
    MAP_UNAVAILABLE={"Map data unavailable", "Select a client-supported zone and try again", "NO_ELIGIBLE"},
    ROUTE_ERROR={"Route could not be optimized", "Choose a different zone or resources and try again", "ERROR"},
    SHAPE_INVALID={"Route shape unavailable", "Choose Loop shape and try again", "ERROR"},
    MAP_ID_INVALID={"Selected zone unavailable", "Choose a client-supported zone", "ERROR"},
    STATE_UNAVAILABLE={"Gathering choices unavailable", "Reopen the gathering guide", "ERROR"},
}
local function formatKey(key)
    return type(key)=="string" and key:gsub("_"," "):lower():gsub("(%a)([%w']*)",
        function(a,b) return a:upper()..b end) or "Unknown"
end
local function summaryOfResources(routes)
    local kinds,routeNames,stopCount,professionCount={}, {}, 0,0
    for _,key in ipairs(KEYS) do
        local route=routes and routes[key]
        if type(route)=="table" and type(route.points)=="table" and #route.points>0 then
            professionCount=professionCount+1
            stopCount=stopCount+#route.points
            routeNames[#routeNames+1]=NAMES[key].." "..#route.points
            for _,point in ipairs(route.points) do
                if type(point.resourceKey)=="string" then kinds[point.resourceKey]=true end
            end
        end
    end
    local names={}
    for key in pairs(kinds) do names[#names+1]=formatKey(key) end
    table.sort(names)
    return stopCount,professionCount,names,routeNames
end
local function selectedResources(mapID,mode)
    local ctrl=JLP:GetModule("GatheringMapLayerController")
    local layers=ctrl and ctrl:GetLayerState(mapID)
    local total,active=0,0
    for _,key in ipairs(KEYS) do
        local layer=layers and layers.layers and layers.layers[key]
        if layer and layer.learned and layer.enabled then
            active=active+1
            if type(layer.resourceSelection)=="table" then
                for _,r in ipairs(layer.resources or {}) do
                    if layer.resourceSelection[r.resourceKey] then total=total+1 end
                end
            -- Old single-type marker filters do not supply Custom route
            -- selections; routing requires the explicit per-map checkbox set.
            end
        end
    end
    if active==0 then return 0,"Enable a learned gathering profession",false end
    if mode=="SMART_PROFESSION" then return 0,"Smart chooses its own resources",true end
    if total==0 then return 0,"Choose resources for Custom routing",false end
    return total,tostring(total).." resource type"..(total==1 and "" or "s").." selected",true
end
local function compactNames(names,maximum)
    local limited={}
    for i=1,math.min(#names,maximum) do limited[#limited+1]=names[i] end
    return table.concat(limited,", ")..(#names>maximum and (" +"..(#names-maximum).." more") or "")
end
function Present:Build(mapID)
    local router=JLP:GetModule("GatheringRouteService")
    local shared=JLP:GetModule("GatheringSharedMapState")
    local choices=shared and shared:GetSnapshot()
    -- Preserve BOTH returns: Lua `and` expressions collapse multi-return status.
    local routes,status=nil,"NO_ACTIVE_ROUTE"
    if router then routes,status=router:GetRoutes(mapID) end
    -- Status is bound to the active map and mode, not a global coroutine state.
    -- Errors from a failed Start remain readable only in the originating zone.
    if (status==nil or status=="NO_ACTIVE_ROUTE") and router and router.GetStatusForMap then
        status=router:GetStatusForMap(mapID)
    end
    status=status or "IDLE"
    local smart=choices and choices.mode=="SMART_PROFESSION"
    local mode=smart and "Smart" or "Custom"
    local focus=FOCUS[choices and choices.focus or "BALANCED"] or FOCUS.BALANCED
    local shape=choices and choices.routeShape=="FROM_PLAYER" and "From player" or "Loop"
    local stops,routeCount,names,routeNames=summaryOfResources(routes)
    local selectedCount,selectionText,hasSelection=selectedResources(mapID,choices and choices.mode)
    local result={status=status,workflow="IDLE",header="No active route",action="",
        detail="",mode=mode,focus=smart and focus.name or nil,shape=shape,
        stopCount=stops,routeCount=routeCount,resourceCount=#names,
        resources=names,resourceSummary=selectionText,selectedCount=selectedCount,
        canGenerate=hasSelection,canClear=false,
        primaryLabel="Generate Route",referenceOnly=true,nativeDispatchAllowed=false}
    if smart then
        result.goal="Smart "..focus.name
        result.selectionExplanation=focus.why.."; Custom selections are unchanged"
    else
        result.goal="Custom resources"
        result.selectionExplanation="Uses your enabled layers and explicit resource selection"
    end
    local summary=smart and router and router:GetSummary(mapID)
    -- Status without matching waypoints is not proof of a READY route for this map.
    -- This guard covers rapid mode/zone transitions and asynchronous refreshes.
    if status=="READY" and stops==0 then status="NO_ACTIVE_ROUTE";result.status=status end
    if status=="READY" and stops>0 then
        result.workflow="READY";result.canClear=true;result.primaryLabel="Regenerate Route"
        result.header=table.concat(routeNames," + ").." stops · "..shape.." · Ready"
        result.detail=tostring(#names).." resource type"..(#names==1 and "" or "s")..": "..compactNames(names,3)
        if smart then
            result.action="Smart "..focus.name.." · "..focus.why.."; historical positions, not live spawns"
            if summary and summary.committed==true and (summary.candidateCells or 0)>0 then
                result.action=result.action.." · "..summary.candidateCells.." candidate cells"
            end
        else
            result.action="Custom selection · historical reference positions; no terrain-safe travel claim"
        end
    elseif status=="GENERATING" then
        result.workflow="GENERATING";result.canGenerate=false;result.canClear=true
        result.primaryLabel="Generating..."
        result.header="Generating "..mode.." route..."
        result.detail=smart and ("Smart "..focus.name.." · "..focus.why) or selectionText
        result.action="Scanning historical positions and optimizing a route · Clear to cancel"
        local progress=router and type(router.GetProgressForMap)=="function" and
            router:GetProgressForMap(mapID)
        if type(progress)=="table" and type(progress.workChecks)=="number" and
            progress.workChecks>=0 and progress.workChecks==progress.workChecks then
            local labels={REFERENCE_LOAD="Loading references",ZONE_SUITABILITY="Assessing zone",
                CANDIDATE_SELECTION="Selecting historical nodes",CANDIDATE_SORT="Ordering candidates",
                CANDIDATE_DIVERSIFY="Balancing map coverage",CANDIDATE_SCORING="Choosing route stops",ROUTE_GEOMETRY="Optimizing geometry"}
            result.progress={stage=progress.stage,workChecks=progress.workChecks,
                workUnit=progress.workUnit,nativeDispatchAllowed=false}
            local phase=(labels[progress.stage] or "Planning route")
            result.detail=phase.." · "..math.floor(progress.workChecks).." checks ("..
                tostring(progress.workUnit or "?").."/Tick budget)"
            result.action=phase.." · "..math.floor(progress.workChecks).." budgeted checks · Clear to cancel"
        end
    elseif status=="CANCELLED" or status=="CLEARED_BY_USER" or
        status=="OTHER_ROUTE_MODE_ACTIVE" or status=="CURRENT_ZONE_CHANGED" or status=="RESTARTED" then
        result.workflow="IDLE";result.header="No active route · selections preserved"
        result.detail=smart and ("Smart "..focus.name.." · "..focus.why) or selectionText
        result.action="Generate again when ready; Clear never changes resource selections"
    elseif EMPTY[status] then
        local issue=EMPTY[status]
        result.workflow=issue[3];result.header=issue[1];result.detail=issue[2]
        result.action=smart and ("Smart "..focus.name.." · "..focus.why) or selectionText
    else
        result.workflow=hasSelection and "SELECTING" or "IDLE"
        result.header="No active "..mode.." route · "..shape
        result.detail=smart and ("Smart "..focus.name.." · "..focus.why) or selectionText
        result.action=smart and "Smart computes its own candidate types; choose focus then Generate" or
            (hasSelection and "Generate a route from selected historical resources" or
                "Enable a learned layer and select route resources")
    end
    -- These are intentionally absent: physical distance, ETA, live node and loot assurances.
    return result
end
-- Both map entrypoints consume the same transient receipt precedence.
-- Errors and unconfirmed cancellation remain visible until context changes;
-- no status field confers engine or native execution authority.
function Present:Feedback(view,receipt)
    if type(receipt)=="table" and type(receipt.message)=="string" then
        return receipt.message,receipt.detail,receipt.phase
    end
    if type(view)=="table" then
        return view.header,view.detail,view.workflow
    end
    return "No active route","Choose resources or a Smart goal.","IDLE"
end
JLP:RegisterModule("GatheringRoutePresentation",Present)
