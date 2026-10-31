local _, JLP = ...
-- Advisory map-coordinate geometry only: NOT terrain-safe pathfinding, movement,
-- gathering, cast automation, skill gain prediction or Smart Profession logic.
local Route={contract="jlp-custom-gathering-loop-v1",nativeDispatchAllowed=false,
    maxStopsPerProfession=250,workUnit=1400,maxTwoOptPasses=2}
local PROFESSIONS={"HERBALISM","MINING"}
local function dist2(a,b)
    local dx=a.x-b.x;local dy=a.y-b.y
    return dx*dx+dy*dy
end
local function length(a,b) return math.sqrt(dist2(a,b)) end
local function routeLength(points,shape,start)
    local total=0
    for i=2,#points do total=total+length(points[i-1],points[i]) end
    if shape=="LOOP" and #points>1 then total=total+length(points[#points],points[1]) end
    if shape=="FROM_PLAYER" and type(start)=="table" and type(start.x)=="number" and type(start.y)=="number" and #points>0 then
        total=total+length(start,points[1])
    end
    return total
end
local function validPosition(point)
    return type(point)=="table" and type(point.x)=="number" and type(point.y)=="number" and
        point.x==point.x and point.y==point.y and point.x>=0 and point.x<=1 and point.y>=0 and point.y<=1
end
-- One candidate union for Custom and Smart. A personal point proves a past
-- interaction at its own coordinates; historical resource identity supplies
-- only the known skill requirement, never a claimed reference spawn there.
function Route:MergeObservationCandidates(references,observed,profession,mapID,currentSkill,checkpoint)
    local check=type(checkpoint)=="function" and checkpoint or function() end
    local identity=JLP:GetModule("GatheringReferenceIdentity")
    local points,index,seen,bands=references or {},{},{},{}
    local copied=false
    local pending={}
    for _,ob in ipairs(observed and observed.verified or {}) do
        if ob.professionKey==profession and validPosition(ob) and
            (ob.mapID==nil or ob.mapID==mapID) then pending[#pending+1]=ob end
        check()
    end
    if #pending==0 then return points,index end
    local function learn(resource,required)
        if type(resource)~="string" or not resource:match("^[A-Z0-9_]+$") or
            type(required)~="number" or required<0 or required>=math.huge or required~=math.floor(required) then return end
        if bands[resource]==nil then bands[resource]=required
        elseif bands[resource]~=required then bands[resource]=false end
    end
    for _,point in ipairs(references or {}) do
        if point.professionKey==profession and point.geometryType=="POINT" and validPosition(point) then
            learn(point.resourceKey,point.requiredSkill)
            local id=identity and identity:FromReference(point,mapID)
            if id then seen[id]=true end
        end
        check()
    end
    -- Packed rows are a resource catalogue even where the selected zone has
    -- no historical positions. Qualify source permission/build/license before
    -- borrowing a threshold; conflicting thresholds remain unknown.
    local pack=JLP.data and JLP.data.gatheringReferencePacked
    local manifest=JLP.data and JLP.data.gatheringSourceManifest
    for _,rows in pairs(type(pack)=="table" and pack.maps or {}) do
        for _,row in ipairs(type(rows)=="table" and rows or {}) do
            local source=manifest and manifest.sources and manifest.sources[row[1]]
            if row[2]==profession and source and source.redistributionApproved==true and
                source.licenseVerified==true and source.buildVerified==true then learn(row[3],row[5]) end
            check()
        end
    end
    for _,ob in ipairs(pending) do
        local id=identity and identity:FromFields(profession,ob.resourceKey,mapID,ob.x,ob.y)
        if id then
            if ob.matchedReferenceID then index[ob.matchedReferenceID]=ob end
            index[id]=ob
            local required=bands[ob.resourceKey]
            if not seen[id] and not (ob.matchedReferenceID and seen[ob.matchedReferenceID]) and
                type(required)=="number" and type(currentSkill)=="number" and currentSkill==currentSkill and
                currentSkill<math.huge and currentSkill==math.floor(currentSkill) and currentSkill>=required then
                if not copied then
                    points={}
                    for _,point in ipairs(references or {}) do points[#points+1]=point;check() end
                    copied=true
                end
                points[#points+1]={professionKey=profession,resourceKey=ob.resourceKey,
                    mapID=mapID,geometryType="POINT",x=ob.x,y=ob.y,requiredSkill=required,
                    referenceID=id,personallyObserved=true,personalOnly=true,
                    source="PERSONAL_OBSERVATION",observerCharacter=ob.observerCharacter,
                    observerRealm=ob.observerRealm,clientBuild=ob.clientBuild}
                seen[id]=true
            end
        end
        check()
    end
    return points,index
end
-- The legacy keys are "cx:cy" strings. Sorting *each axis* separately
-- does not reproduce combined lexical order ("10:" sorts before "1:").
-- One fixed 2,400-cell ordering is computed at module load and reused ONLY
-- for coordinate iteration; this never stores point/map/provenance state.
local lexicalCells={}
for cx=0,59 do
    for cy=0,39 do
        lexicalCells[#lexicalCells+1]={x=cx,y=cy,key=cx..":"..cy}
    end
end
table.sort(lexicalCells,function(a,b) return a.key<b.key end)
-- Immutable lexical rank map; x/y numeric indexing never allocates per-point
-- string keys and reproduces the original combined "cx:cy" lexical sort.
local lexicalRank={}
for rank,coord in ipairs(lexicalCells) do
    if not lexicalRank[coord.x] then lexicalRank[coord.x]={} end
    lexicalRank[coord.x][coord.y]=rank
end
local SPARSE_SORT_LIMIT=256 -- bounded table.sort: no non-yieldable 2,400-cell sort
local function spatialSubset(points,selection,maximum,check)
    check=check or function() end
    local types,cells,occupied={},{},{}
    for _,point in ipairs(points) do
        check()
        if selection[point.resourceKey] and
            (point.geometryType==nil or point.geometryType=="POINT") and validPosition(point) then
            local typeKey=point.resourceKey
            local bucket=cells[typeKey]
            if not bucket then
                bucket={};cells[typeKey]=bucket;occupied[typeKey]={}
                types[#types+1]=typeKey
            end
            local cx=math.min(59,math.floor(point.x*60))
            local cy=math.min(39,math.floor(point.y*40))
            local column=bucket[cx]
            if not column then column={};bucket[cx]=column end
            if not column[cy] then
                column[cy]=point -- first-seen cell winner, never overwritten
                -- Only retain the bounded sparse index. Once the type crosses
                -- the threshold, the dense branch reads the bucket grid.
                local entries=occupied[typeKey]
                if #entries<=SPARSE_SORT_LIMIT then
                    entries[#entries+1]={rank=lexicalRank[cx][cy],point=point}
                end
            end
        end
    end
    table.sort(types)
    local arrays={}
    for _,kind in ipairs(types) do
        local arr={}
        local bucket=cells[kind]
        -- Sparse resources visit only occupied cells. Keep table.sort bounded
        -- to 256 entries; dense resources retain the fixed, cooperative grid.
        -- Both branches produce the EXACT former lexical "cx:cy" order.
        local entries=occupied[kind]
        if #entries<=SPARSE_SORT_LIMIT then
            table.sort(entries,function(a,b) return a.rank<b.rank end)
            for _,entry in ipairs(entries) do arr[#arr+1]=entry.point;check() end
        else
            for _,coordinate in ipairs(lexicalCells) do
                local column=bucket[coordinate.x]
                local point=column and column[coordinate.y]
                if point then arr[#arr+1]=point end
                check()
            end
        end
        arrays[kind]=arr
    end
    local result,indices={},{}
    for _,kind in ipairs(types) do indices[kind]=1 end
    while #result<maximum do
        local progressed=false
        for _,kind in ipairs(types) do
            check()
            local list=arrays[kind]
            if indices[kind]<=#list and #result<maximum then
                result[#result+1]=list[indices[kind]]
                indices[kind]=indices[kind]+1
                progressed=true
            end
        end
        if not progressed then break end
    end
    return result
end
-- Exposed for bounded selection tests; this is not a Smart-route evaluator.
function Route:SelectCandidates(points,selectedKeys,maxStops,routeSource,observed,mapID,checkpoint)
    local check=type(checkpoint)=="function" and checkpoint or function() end
    if type(points)~="table" or type(selectedKeys)~="table" then return {} end
    local eligible=points
    if routeSource=="OBSERVED_ONLY" or routeSource=="PREFER_OBSERVED" then
        local identity=JLP:GetModule("GatheringReferenceIdentity")
        local index={}
        for _,ob in ipairs(observed and observed.verified or {}) do
            check()
            if ob.matchedReferenceID then index[ob.matchedReferenceID]=ob end
            local id=identity and identity:FromFields(ob.professionKey,ob.resourceKey,mapID,ob.x,ob.y)
            if id then index[id]=ob end
        end
        eligible={}
        -- Prefer observed with stable order, but never discard other source
        -- positions unless the user chose OBSERVED_ONLY explicitly.
        local preferred,remaining={},{}
        for _,point in ipairs(points) do
            check()
            local id=identity and identity:FromReference(point,mapID)
            local own=point.personalOnly and point.personallyObserved or (id and index[id])
            if own then preferred[#preferred+1]=point
            elseif routeSource~="OBSERVED_ONLY" then remaining[#remaining+1]=point end
        end
        for _,point in ipairs(preferred) do eligible[#eligible+1]=point;check() end
        for _,point in ipairs(remaining) do eligible[#eligible+1]=point;check() end
    end
    return spatialSubset(eligible,selectedKeys,math.min(self.maxStopsPerProfession,math.max(0,math.floor(maxStops or self.maxStopsPerProfession))),check)
end
local function makeRoute(points,key,shape,start,check)
    if #points<2 then return nil,"INSUFFICIENT_REFERENCE_POINTS" end
    -- Bounded nearest-neighbour traversal of ONLY unvisited candidates.
    -- Linked numerical indices retain the exact original `ipairs(points)`
    -- tie ordering. Removal is O(1), with no array shifts and no aliasing
    -- or mutation of the qualified POINT source records.
    local ordered,nextIndex,prevIndex={}, {}, {}
    for i=1,#points do
        nextIndex[i]=i<#points and i+1 or nil
        prevIndex[i]=i>1 and i-1 or nil
    end
    local head=#points>0 and 1 or nil
    local anchor=(shape=="FROM_PLAYER" and validPosition(start)) and start or points[1]
    for _=1,#points do
        local bestIndex,bestCost=nil,math.huge
        local index=head
        while index do
            local candidate=points[index]
            local cost=dist2(anchor,candidate)
            if cost<bestCost then bestCost=cost;bestIndex=index end
            index=nextIndex[index]
            check() -- every candidate comparison remains cooperative
        end
        if not bestIndex then break end
        local previous,nextOne=prevIndex[bestIndex],nextIndex[bestIndex]
        if previous then nextIndex[previous]=nextOne else head=nextOne end
        if nextOne then prevIndex[nextOne]=previous end
        ordered[#ordered+1]=points[bestIndex]
        anchor=points[bestIndex]
    end
    local initialLength=routeLength(ordered,shape,start)
    -- Optimize actual Euclidean edge length, not squared distance (which can
    -- prefer a longer route). Include the closing edge for LOOP geometry.
    -- Keep the first waypoint fixed, preserving FROM_PLAYER anchoring.
    local completedPasses=0
    for _=1,Route.maxTwoOptPasses do
        local improved=false
        completedPasses=completedPasses+1
        for i=2,#ordered-1 do
            local endIndex=shape=="LOOP" and #ordered or #ordered-1
            -- The preceding waypoint never moves inside this i loop. Cache
            -- its edge length until a successful reversal changes ordered[i].
            -- This removes one sqrt per unsuccessful 2-opt comparison, with
            -- identical arithmetic and exact legacy reversal/tie ordering.
            local a=ordered[i-1]
            local b=ordered[i]
            local ab=length(a,b)
            for j=i+1,endIndex do
                local c=ordered[j]
                local d=ordered[j+1] or ordered[1]
                if length(a,c)+length(b,d)+0.00000001<ab+length(c,d) then
                    local left,right=i,j
                    while left<right do
                        ordered[left],ordered[right]=ordered[right],ordered[left]
                        left=left+1;right=right-1
                    end
                    b=ordered[i]
                    ab=length(a,b) -- invalidate ONLY when the current edge changed
                    improved=true
                end
                check()
            end
        end
        if not improved then break end
    end
    local optimizedLength=routeLength(ordered,shape,start)
    return {professionKey=key,shape=shape,points=ordered,stopCount=#ordered,
        closed=shape=="LOOP",source="HISTORICAL_REFERENCE_GEOMETRY",
        -- Distance in normalized map coordinates, never meters or travel time.
        initialNormalizedLength=initialLength,normalizedLength=optimizedLength,
        -- Preserve the verified request's FROM_PLAYER anchor as immutable
        -- normalized coordinates. The renderer may draw player -> first stop;
        -- it is not a travel guarantee and does not alter stopCount.
        startPosition=shape=="FROM_PLAYER" and validPosition(start) and
            {x=start.x,y=start.y} or nil,
        improvementNormalized=math.max(0,initialLength-optimizedLength),twoOptPasses=completedPasses,
        terrainValidated=false,nativeDispatchAllowed=false,styleID=key=="MINING" and "AMBER_DASHED" or "GREEN_SOLID"}
end
function Route:BuildGeometry(points,key,shape,start,check)
    return makeRoute(points,key,shape,start,check or function() end)
end
function Route:Cancel(reason)
    self._generation=(self._generation or 0)+1
    self._job=nil
    self._routes=nil
    self._mapID=nil
    self._status=reason or "CANCELLED"
    return true
end
function Route:GetRoutes(mapID)
    if self._mapID==mapID then return self._routes,self._status end
    return nil,"NO_ACTIVE_ROUTE"
end
function Route:GetStatus()
    return self._status or "IDLE"
end
function Route:Start(mapID,shape,position,onComplete)
    if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then return false,"MAP_ID_INVALID" end
    if shape~="LOOP" and shape~="FROM_PLAYER" then return false,"SHAPE_INVALID" end
    if shape=="FROM_PLAYER" and not validPosition(position) then return false,"PLAYER_POSITION_UNAVAILABLE" end
    local ctrl=JLP:GetModule("GatheringMapLayerController")
    local state=JLP:GetModule("GatheringSharedMapState")
    local layers=ctrl and ctrl:GetLayerState(mapID)
    local shared=state and state:GetSnapshot()
    local registry=JLP:GetModule("GatheringDataRegistry")
    if not layers or not shared or not registry then return false,"GATHERING_DATA_UNAVAILABLE" end
    local task=shared.manualTargetTask
    if task and not task.dismissed then
        if task.status~="ACTIVE" or task.remaining<=0 then return false,"MANUAL_TARGET_"..task.status end
        if task.professionKey~="MINING" and task.professionKey~="HERBALISM" then return false,"MANUAL_TARGET_AREA_GUIDANCE_ONLY" end
    end
    if shared.mode~="CUSTOM_LOOP" then return false,"NOT_CUSTOM_MODE" end
    local observations=JLP:GetModule("GatheringObservationStore")
    local own=observations and observations:GetZoneSnapshot(mapID) or nil
    -- Cheap observed-only impossibility guard preserves existing immediate
    -- validation without scanning 12k historical reference points in Start().
    if shared.routeSource=="OBSERVED_ONLY" and
        #(own and own.verified or {})<2 then
        self:Cancel("NO_SELECTED_ROUTE_POINTS")
        return false,"NO_SELECTED_ROUTE_POINTS"
    end
    local batches={};local any=false
    if type(layers.layers)~="table" then return false,"GATHERING_DATA_UNAVAILABLE" end
    for _,key in ipairs(PROFESSIONS) do
        local layer=layers.layers[key]
        local selected=layer and layer.resourceSelection
        if task and not task.dismissed then
            selected=key==task.professionKey and task.selectedResourceKeys or {}
        end
        if layer and layer.enabled and layer.learned and type(selected)=="table" then
            local hasSelection=false
            for resource,enabled in pairs(selected) do
                if type(resource)=="string" and enabled==true then hasSelection=true;break end
            end
            if hasSelection then
                -- Do not lazily materialize full map references in the click
                -- handler; defer registry snapshot lookup to the job.
                batches[#batches+1]={key=key,selected=selected,skill=layer.skill}
                any=true
            end
        end
    end
    if not any then self:Cancel("NO_SELECTED_ROUTE_POINTS");return false,"NO_SELECTED_ROUTE_POINTS" end
    self:Cancel("RESTARTED")
    local generation=self._generation
    self._mapID=mapID;self._status="GENERATING"
    self._routes={}
    local job={mapID=mapID,generation=generation,onComplete=onComplete,workUnits=0,stage="REFERENCE_LOAD"}
    self._job=job
    job.co=coroutine.create(function()
        local ops=0
        local function check()
            job.workUnits=job.workUnits+1
            ops=ops+1
            if ops>=math.max(1,Route.workUnit) then
                ops=0
                coroutine.yield("YIELD_WORK_BUDGET")
            end
        end
        local outputs={}
        local keys={}
        for _,batch in ipairs(batches) do keys[#keys+1]=batch.key end
        local projected,projectionError=registry:GetZoneBatchSnapshots(mapID,keys,check)
        if not projected then error(projectionError or "REFERENCE_PROJECTION_UNAVAILABLE") end
        for _,batch in ipairs(batches) do
            -- Registry zone materialization itself remains a separate bounded-
            -- decode improvement; do not confuse coroutine placement with
            -- time-sliced registry decoding.
            -- Budget both lazy packed decode and the snapshot projection; a
            -- cancelled job cannot commit a partially decoded shared map.
            local snapshot=projected[batch.key]
            local referencePoints=type(snapshot)=="table" and type(snapshot.references)=="table"
                and snapshot.references or {}
            local points=self:MergeObservationCandidates(referencePoints,own,batch.key,mapID,batch.skill,check)
            -- SelectCandidates also yields while scanning, deduplicating and
            -- applying per-resource spatial fairness; never in Start().
            job.stage="CANDIDATE_SELECTION"
            local refs=self:SelectCandidates(points,batch.selected,self.maxStopsPerProfession,
                shared.routeSource,own,mapID,check)
            if #refs>=2 then
                job.stage="ROUTE_GEOMETRY"
                local route=makeRoute(refs,batch.key,shape,position,check)
                if route then route.routeSource=shared.routeSource or "ALL";outputs[batch.key]=route end
            end
        end
        return outputs
    end)
    return true,"GENERATING"
end
function Route:Tick()
    local job=self._job
    if not job then return self._status or "IDLE" end
    if job.generation~=self._generation then return self._status or "CANCELLED" end
    if coroutine.status(job.co)=="dead" then return self._status end
    local ok,result=coroutine.resume(job.co)
    if not ok then
        self:Cancel("ROUTE_ERROR")
        return "ROUTE_ERROR" -- no protected gameplay action and no unsafe exception propagation
    end
    if coroutine.status(job.co)=="dead" then
        self._routes=type(result)=="table" and result or {}
        self._status=next(self._routes) and "READY" or "NO_ELIGIBLE_ROUTE"
        self._job=nil
        if type(job.onComplete)=="function" then pcall(job.onComplete,self._status) end
    end
    return self._status
end
function Route:GetProgress(mapID)
 local job=self._job
 if not job or self._mapID~=mapID or job.generation~=self._generation then return nil end
 return {stage=job.stage,workChecks=job.workUnits,workUnit=self.workUnit,
  nativeDispatchAllowed=false}
end
JLP:RegisterModule("GatheringCustomRoute",Route)
