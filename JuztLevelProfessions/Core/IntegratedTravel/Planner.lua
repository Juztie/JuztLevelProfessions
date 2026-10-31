local _, JLP = ...
local T = JLP._integratedTravel
local C=T.Contract
local Planner={}
local START,GOAL='__JT_START','__JT_GOAL'
-- A recorded flight connection is not proof that the current character has
-- unlocked it. Prefer any usable ground/boat/zeppelin alternative. Retain
-- unknown flights in the graph as explicitly conditional fallbacks only.
local UNKNOWN_FLIGHT_PENALTY=20000
local function flightUnconfirmed(edge,context)
    return edge.mode=='FLIGHT' and
        (type(context.unlocked)~='table' or context.unlocked[edge.id]~=true)
end
local function walkCost(a,b,opts)
    -- Abstract ranking metric only. Not yards, path length or ETA; terrain unknown.
    return C.distance(a,b)*(opts.walkWeight or 1000)
end
local function leg(u,v,mode,cost,e)
    return {mode=mode,from=C.copyPoint(u),to=C.copyPoint(v),costUnits=cost,
        id=e and e.id or 'local-walk',provenance=e and e.provenance or 'DIRECT_MAP_VECTOR_ONLY',
        note=e and e.note or 'Straight-line map bearing; obstacles are not modeled',
        requiresConfirmation=e and e.mustConfirm~=false or false,
        distanceVerified=false,etaVerified=false,clientVerified=e and e.clientVerified==true or false,
        toPlaceName=type(v.placeName)=="string" and v.placeName or nil}
end
local function cleanOptions(options)
    options=options or {}
    local walkWeight=tonumber(options.walkWeight) or 1000
    if not C.finite(walkWeight) or walkWeight<=0 or walkWeight>100000 then return nil,'INVALID_WALK_WEIGHT' end
    return {walkWeight=walkWeight,maxVisited=600,profile=options.profile or 'FASTEST_ESTIMATE'}
end
function Planner:Plan(graph,origin,destination,context,options)
    if type(graph)~='table' or type(graph.nodes)~='table' or type(graph.edges)~='table' then return nil,'INVALID_GRAPH' end
    local from,e=C.point(origin);if not from then return nil,e end
    local to,e2=C.point(destination);if not to then return nil,e2 end
    local opts,oe=cleanOptions(options);if not opts then return nil,oe end
    if from.mapID==to.mapID and C.distance(from,to)==0 then
        return {contract=T.contract,engineVersion=T.engineVersion,generation=graph.generation,
            origin=from,destination=to,legs={},totalCostUnits=0,status='ALREADY_AT_POINT',
            confidence='MAP_VECTOR_ONLY',etaSeconds=nil,profile=opts.profile},nil
    end
    local vertices={[START]=from,[GOAL]=to}
    for id,node in pairs(graph.nodes) do vertices[id]=node end
    local adj={}
    local function add(a,b,kind,cost,record)
        adj[a]=adj[a] or {}
        adj[a][#adj[a]+1]={to=b,mode=kind,cost=cost,edge=record}
    end
    if from.mapID==to.mapID then add(START,GOAL,'WALK',walkCost(from,to,opts)) end
    for id,node in pairs(graph.nodes) do
        if node.mapID==from.mapID then add(START,id,'WALK',walkCost(from,node,opts)) end
        if node.mapID==to.mapID then add(id,GOAL,'WALK',walkCost(node,to,opts)) end
    end
    -- Multimodal transfer inside the same client-verified UI map only.
    -- Such legs are map vectors, NOT proven walkable terrain or travel-time estimates.
    -- External callers cannot introduce new nodes into this graph.
    local stationIds={}
    for id,node in pairs(graph.nodes) do
        stationIds[#stationIds+1]=id
    end
    table.sort(stationIds)
    for i=1,#stationIds do
        local a=graph.nodes[stationIds[i]]
        for j=i+1,#stationIds do
            local b=graph.nodes[stationIds[j]]
            if a.mapID==b.mapID then
                local estimated=walkCost(a,b,opts)
                local advisory={id='transfer-'..stationIds[i]..'-'..stationIds[j],
                    provenance='SAME_UI_MAP_LOCAL_VECTOR_ONLY',
                    note='Advisory local transfer; terrain and walkability unverified',
                    mustConfirm=true,clientVerified=false}
                add(stationIds[i],stationIds[j],'WALK',estimated,advisory)
                add(stationIds[j],stationIds[i],'WALK',estimated,advisory)
            end
        end
    end
    local known=0;local excluded={};context=context or {}
    for _,edge in ipairs(graph.edges) do
        local allowed,reason=graph:CanTraverse(edge,context)
        if allowed then
            local conditional=flightUnconfirmed(edge,context)
            add(edge.from,edge.to,edge.mode,
                edge.costUnits+(conditional and UNKNOWN_FLIGHT_PENALTY or 0),edge)
            known=known+1
        else excluded[reason or 'RUNTIME_ACCESS_RESTRICTED']=(excluded[reason or 'RUNTIME_ACCESS_RESTRICTED'] or 0)+1 end
    end
    -- Dijkstra: deterministic tie resolution, bounded work.
    local best={[START]=0};local parent={};local seen={};local visited=0
    while visited<opts.maxVisited do
        local key,score
        for id,cost in pairs(best) do
            if not seen[id] and (not score or cost<score or (cost==score and id<key)) then key,score=id,cost end
        end
        if not key then break end
        if key==GOAL then break end
        seen[key]=true;visited=visited+1
        for _,edge in ipairs(adj[key] or {}) do
            local alt=score+edge.cost
            if not best[edge.to] or alt<best[edge.to] then
                best[edge.to]=alt
                parent[edge.to]={from=key,edge=edge}
            end
        end
    end
    if not best[GOAL] then
        return nil,'NO_REGISTERED_ACCESSIBLE_ROUTE', {excluded=excluded,eligibleEdges=known,graphGeneration=graph.generation}
    end
    local legs={};local cursor=GOAL;local unconfirmedFlights={}
    while cursor~=START do
        local step=parent[cursor];if not step then return nil,'BROKEN_PATH' end
        local nextLeg=leg(vertices[step.from],vertices[cursor],step.edge.mode,step.edge.cost,step.edge.edge)
        if step.edge.edge and flightUnconfirmed(step.edge.edge,context) then
            nextLeg.flightUnlock='NOT_CONFIRMED_FOR_CHARACTER'
            table.insert(unconfirmedFlights,1,step.edge.edge.id)
        end
        table.insert(legs,1,nextLeg)
        cursor=step.from
        if #legs>1000 then return nil,'PATH_TOO_LONG' end
    end
    return {contract=T.contract,engineVersion=T.engineVersion,generation=graph.generation,
        origin=from,destination=to,legs=legs,totalCostUnits=best[GOAL],status='ESTIMATED_ROUTE',
        confidence=#unconfirmedFlights>0 and 'CONDITIONAL_FLIGHT_ACCESS_NOT_CONFIRMED' or
            'REGISTERED_TRANSPORT_EDGES_LOCAL_PATH_ADVISORY',
        requiresFlightUnlockConfirmation=#unconfirmedFlights>0,
        unconfirmedFlightEdges=unconfirmedFlights,etaSeconds=nil,profile=opts.profile},nil
end
T.Planner=Planner
