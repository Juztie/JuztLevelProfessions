local _, JLP = ...
-- Alpha151: original resource icons + adaptive screen-density controlled pins.
-- Historical reference geometry only. Routes remain advisory and non-automating.
local Overlay={contract="gathering-map-overlay-v2",nativeDispatchAllowed=false,
    minimumBudget=160,maximumBudget=520,maxRouteStrokes=1800}
-- Presentation contract: cap the number of UI buttons, NOT the underlying
-- historical POINTs. Multiple resource identities in one cell are distinct.
local PIN_OFFSETS={{0,0},{16,0},{-16,0},{0,16},{0,-16},
    {16,16},{-16,-16},{16,-16},{-16,16},{32,0},{-32,0},
    {0,32},{0,-32}}
local function pinPosition(selected,x,y,w,h)
    -- Only a small visual disambiguation for different resource kinds in one
    -- density cell. Does not change the stored reference location or routes.
    local ox=selected.offsetX or 0
    local oy=selected.offsetY or 0
    local inset=math.min(14,math.max(0,math.min(w,h)/4))
    return math.max(inset,math.min(w-inset,x+ox)),
        math.max(-h+inset,math.min(-inset,y+oy))
end
local WHITE="Interface\\Buttons\\WHITE8X8"
local COLORS={CLOTH={0.85,0.85,0.95},HERBALISM={0.30,0.87,0.44},MINING={0.98,0.72,0.27}}
local function valid(point)
    return type(point)=="table" and type(point.x)=="number" and type(point.y)=="number" and
        point.x==point.x and point.y==point.y and point.x>=0 and point.x<=1 and point.y>=0 and point.y<=1 and
        COLORS[point.professionKey] and type(point.resourceKey)=="string"
end
local function hide(collection)
    for _,widget in ipairs(collection or {}) do widget:Hide() end
end
function Overlay:Clear(canvas)
    if not canvas then return end
    -- Hidden pin owners must not leave a stale GameTooltip over another map.
    if JLP.UIInteraction and JLP.UIInteraction.HideTooltipTree then
        JLP.UIInteraction:HideTooltipTree(canvas)
    end
    hide(canvas.gatheringPins)
    hide(canvas.gatheringRouteStrokes)
    for _,stroke in ipairs(canvas.gatheringRouteStrokes or {}) do
        stroke.__jlpRouteCanvas=nil
    end
    hide(canvas.gatheringFishingSectors)
    hide(canvas.gatheringFishingAreaIcons)
    canvas.gatheringFishingSectorsVisible=0
    canvas.gatheringFishingAreaIconsVisible=0
    canvas.gatheringPinsVisible=0
    canvas.gatheringPinIconLookups=0
    canvas.gatheringPinTextureRebinds=0
    canvas.gatheringRouteStrokesVisible=0
    canvas.gatheringOverlayMapID=nil
    -- Clear/Stop/map mismatch ends this canvas-local selection receipt.
    canvas.__jlpSelectedPoints=nil
end
local function dimensions(canvas,art)
    local w=canvas.GetWidth and canvas:GetWidth() or 740
    local h=canvas.GetHeight and canvas:GetHeight() or 350
    if type(w)~="number" or w<1 then w=740 end
    if type(h)~="number" or h<1 then h=350 end
    if art and type(art.width)=="number" and type(art.height)=="number" and art.width>0 and art.height>0 then
        local scale=math.min(w/art.width,h/art.height)
        return art.width*scale,art.height*scale
    end
    return w,h
end
function Overlay:DisplayContract(canvas,kindCount)
    local mode=canvas and canvas.gatheringDisplayMode or "SELECTED"
    if mode~="COMPACT" and mode~="SELECTED" and mode~="DETAILED" then mode="SELECTED" end
    local zoom=tonumber(canvas and canvas.gatheringView and canvas.gatheringView.zoom) or 1
    zoom=math.max(1,math.min(3.5,zoom))
    -- Declutter broad map views while revealing detail as players zoom in.
    -- Only the presentation is adjusted; historical POINTs are never mutated.
    local base={COMPACT=24,SELECTED=15,DETAILED=9}
    local factor=math.max(0.72,1.5/zoom)
    local size=math.floor(base[mode]*factor+0.5)
    -- The old fixed 240-slot limit at 150% caused different selected types
    -- to displace one another. Use more of the EXISTING maximumBudget as
    -- resource diversity grows, without allowing unbounded UI-frame creation.
    local variety=math.max(1,math.floor(tonumber(kindCount) or 1))
    local caps={COMPACT=160,
        SELECTED=math.min(self.maximumBudget,(zoom<=1.5 and 240 or zoom<=2.5 and 350 or 420)
            +math.max(0,variety-1)*34),
        DETAILED=self.maximumBudget}
    return {mode=mode,cellSize=size,markerCap=caps[mode],zoom=zoom,
        provenance="PERSONAL_AND_HISTORICAL",nativeDispatchAllowed=false}
end
function Overlay:ComputeBudget(snapshot,canvas,art)
    local w,h=dimensions(canvas,art)
    local display=self:DisplayContract(canvas)
    local types={};local count=0
    for _,p in ipairs(snapshot and snapshot.points or {}) do
        if valid(p) then
            local key=p.professionKey..":"..p.resourceKey
            if not types[key] then count=count+1;types[key]=true end
        end
    end
    if count==0 then return 0,0 end
    -- More chosen node types receive more budget; viewport area and one marker
    -- per ~210 square pixels prevent an unreadable solid carpet of icons.
    local typeBudget=math.min(self.maximumBudget,self.minimumBudget+math.max(0,count-1)*70)
    local spatialBudget=math.max(36,math.floor(w*h/210))
    display=self:DisplayContract(canvas,count)
    return math.min(typeBudget,spatialBudget,self.maximumBudget,display.markerCap),count
end
function Overlay:SelectPoints(snapshot,canvas,art)
    local result={}
    if not snapshot or type(snapshot.points)~="table" then return result,0 end
    -- One validation pass instead of the old ComputeBudget + SelectPoints
    -- double scan. Include off-screen resource kinds in the original budget
    -- semantics; never mutate points or cache provenance across map/filter.
    local w,h=dimensions(canvas,art)
    local viewportW=canvas.GetWidth and canvas:GetWidth() or w
    local viewportH=canvas.GetHeight and canvas:GetHeight() or h
    local display=self:DisplayContract(canvas)
    -- Cell boundaries are tied to normalized ZONE coordinates, never the
    -- moving viewport. Pan must not reassign a POINT to another cluster.
    local zoom=tonumber(canvas.gatheringView and canvas.gatheringView.zoom) or 1
    local cols=math.max(1,math.floor(w*zoom/display.cellSize))
    local rows=math.max(1,math.floor(h*zoom/display.cellSize))
    local mapAdapter=JLP:GetModule("ForeverFishingMapCanvas")
    -- Only a compatible adapter can supply a prepared projector. Legacy
    -- mocked adapters retain the original ProjectNormalizedToCanvas path.
    local project,bounds
    if #snapshot.points>0 and mapAdapter and
        type(mapAdapter.PrepareNormalizedProjection)=="function" then
        project,bounds=mapAdapter:PrepareNormalizedProjection(canvas,art)
    end
    -- Bounding checks are valid ONLY for the native prepared projector which
    -- supplied this envelope. Other adapters continue projecting every POINT.
    -- An envelope is meaningful only for the projector that produced it.
    -- Malformed/NaN/infinite or inverted bounds must never cull valid POINTs.
    local function finiteEnvelopeNumber(v)
        return type(v)=="number" and v==v and v>-math.huge and v<math.huge
    end
    if type(project)~="function" or type(bounds)~="table" or
        bounds.contract~="NORMALIZED_MAP_VISIBILITY_ENVELOPE_V1" or
        not finiteEnvelopeNumber(bounds.minX) or
        not finiteEnvelopeNumber(bounds.maxX) or
        not finiteEnvelopeNumber(bounds.minY) or
        not finiteEnvelopeNumber(bounds.maxY) or
        bounds.minX>bounds.maxX or bounds.minY>bounds.maxY then bounds=nil end
    local groups,types={},{}
    local allKinds,kindCount={},0
    -- Only resource identities are cached, never selected POINTs or provenance.
    -- Local to one selection; map/mode/focus filters rebuild it each call.
    local typeKeys,typeKeyBuilds={},0
    local cellInfo={}
    -- Per-selection compact cell indexes avoid building cx:cy strings for
    -- every historical record. The exact lexical key is built only once per
    -- occupied viewport cell; the original winner and lexical sort remain.
    local cellKeys={}
    local cellKeyBuilds=0
    local checks,projected,culled=0,0,0
    for _,point in ipairs(snapshot.points) do
        checks=checks+1
        if valid(point) then
            local byProfession=typeKeys[point.professionKey]
            if not byProfession then byProfession={};typeKeys[point.professionKey]=byProfession end
            local typeKey=byProfession[point.resourceKey]
            if not typeKey then
                typeKey=point.professionKey..":"..point.resourceKey
                byProfession[point.resourceKey]=typeKey;typeKeyBuilds=typeKeyBuilds+1
            end
            if not allKinds[typeKey] then allKinds[typeKey]=true;kindCount=kindCount+1 end
            -- Group ALL valid historical positions in stationary world cells.
            -- Never choose a different winner merely because the viewport
            -- crossed a cell boundary; visibility is tested after grouping.
            local cx=math.min(cols-1,math.floor(point.x*cols))
            local cy=math.min(rows-1,math.floor(point.y*rows))
            local cellID=cx*rows+cy
            if not groups[typeKey] then groups[typeKey]={};types[#types+1]=typeKey end
            local winner=groups[typeKey][cellID]
            if not winner or (point.personallyObserved and not winner.personallyObserved) then
                groups[typeKey][cellID]=point
            end
            local composition=cellInfo[cellID]
            if not composition then
                composition={count=0,resources={}};cellInfo[cellID]=composition
                cellKeys[cellID]=cx..":"..cy
                cellKeyBuilds=cellKeyBuilds+1
            end
            composition.count=composition.count+1
            composition.resources[typeKey]=(composition.resources[typeKey] or 0)+1
        end
    end
    if kindCount==0 then
        self._lastSelectionMetrics={validityChecks=checks,inputPoints=#snapshot.points,
            resourceKinds=0,selectedRepresentatives=0,budget=0,nativeDispatchAllowed=false}
        return result,0,0
    end
    local typeBudget=math.min(self.maximumBudget,self.minimumBudget+math.max(0,kindCount-1)*70)
    local spatialBudget=math.max(36,math.floor(w*h/210))
    display=self:DisplayContract(canvas,kindCount)
    local budget=math.min(typeBudget,spatialBudget,self.maximumBudget,display.markerCap)
    table.sort(types)
    local ordered,indices={},{}
    -- Divide the viewport into coarse macro-cells so each resource's limited
    -- representatives cover the WHOLE visible zone, rather than selecting
    -- just the first lexical cells near the left/top edge.
    local macroColumns,macroRows=8,6
    local macroCount=macroColumns*macroRows
    for _,kind in ipairs(types) do
        local buckets={}
        for cellID,point in pairs(groups[kind]) do
            local px,py
            if bounds and (point.x<bounds.minX or point.x>bounds.maxX or
                point.y<bounds.minY or point.y>bounds.maxY) then
                culled=culled+1
            elseif mapAdapter then
                projected=projected+1
                if project then px,py=project(point.x,point.y)
                else px,py=mapAdapter:ProjectNormalizedToCanvas(canvas,art,point.x,point.y) end
            end
            local inset=math.min(14,math.max(0,math.min(viewportW,viewportH)/4))
            local inside=type(px)=="number" and type(py)=="number" and
                px>=inset and px<=viewportW-inset and
                py<=-inset and py>=-viewportH+inset
            if inside then
            local cx=math.floor(cellID/rows)
            local cy=cellID%rows
            local bx=math.min(macroColumns-1,math.floor(cx/cols*macroColumns))
            local by=math.min(macroRows-1,math.floor(cy/rows*macroRows))
            local bucket=bx*macroRows+by+1
            if not buckets[bucket] then buckets[bucket]={} end
            buckets[bucket][#buckets[bucket]+1]=cellID
            end
        end
        local maxDepth=0
        for _,keys in pairs(buckets) do
            table.sort(keys,function(a,b)
                local aa=groups[kind][a].personallyObserved==true
                local bb=groups[kind][b].personallyObserved==true
                if aa~=bb then return aa end
                return cellKeys[a]<cellKeys[b]
            end)
            maxDepth=math.max(maxDepth,#keys)
        end
        ordered[kind]={}
        for depth=1,maxDepth do
            for bucket=1,macroCount do
                local keys=buckets[bucket]
                local cellID=keys and keys[depth]
                if cellID then
                    local chosen=groups[kind][cellID]
                    ordered[kind][#ordered[kind]+1]={point=chosen,cell=cellID,
                        count=cellInfo[cellID].resources[kind] or 1}
                end
            end
        end
        indices[kind]=1
    end
    self._lastSelectionMetrics={validityChecks=checks,projectionCalls=projected,
        inputPoints=#snapshot.points,resourceKinds=kindCount,resourceKeyBuilds=typeKeyBuilds,
        cellKeyBuilds=cellKeyBuilds,visibilityPruned=culled,
        preparedProjection=project~=nil,viewportTransformBuilds=project and 1 or projected,
        nativeDispatchAllowed=false}
    -- Distinct resource identities must NOT exclude each other merely because
    -- they share a density cell. The legacy global occupied[cell] discarded
    -- the second kind, making checked resource rows apparently disappear.
    -- Still apply an explicit shared button ceiling for WoW UI performance.
    -- Slot offsets depend on the immutable world-cell resource composition,
    -- not on which neighbouring types happened to fit the current viewport.
    local cellSlots={}
    for cellID,composition in pairs(cellInfo) do
        local keys={}
        for key in pairs(composition.resources) do keys[#keys+1]=key end
        table.sort(keys)
        local slots={}
        for index,key in ipairs(keys) do slots[key]=index end
        cellSlots[cellID]=slots
    end
    local represented={}
    local function emit(kind,item)
        if represented[item.point] or #result>=budget then return false end
        represented[item.point]=true
        local slot=cellSlots[item.cell] and cellSlots[item.cell][kind] or 1
        local offset=PIN_OFFSETS[(slot-1)%#PIN_OFFSETS+1]
        local cell=cellInfo[item.cell]
        result[#result+1]={point=item.point,cellCount=item.count,
            clusterCount=cell and cell.count or 1,
            clusterResources=cell and cell.resources or {},
            colocatedTypes=cell and cell.resources or {},
            offsetX=offset[1],offsetY=offset[2]}
        return true
    end
    -- Preserve the canonical, STILL-VISIBLE representatives across a drag.
    -- A pan must not evict an existing pin just because newly visible cells
    -- changed the 520-slot ordering. This cache is strictly viewport-local
    -- and source-snapshot-bound; never reuse it after filter/map/zoom changes.
    local previous=canvas.__jlpSelectedPoints
    if previous and previous.snapshot==snapshot and previous.art==art and
       previous.zoom==zoom and previous.width==viewportW and
       previous.height==viewportH and previous.display==canvas.gatheringDisplayMode then
        local available={}
        for _,kind in ipairs(types) do
            for _,item in ipairs(ordered[kind]) do
                available[item.point]={kind=kind,item=item}
            end
        end
        for _,old in ipairs(previous.points or {}) do
            local candidate=old and available[old.point]
            if candidate then emit(candidate.kind,candidate.item) end
            if #result>=budget then break end
        end
    end
    while #result<budget do
        local advanced=false
        for _,kind in ipairs(types) do
            local idx=indices[kind]
            local item=ordered[kind][idx]
            if item then
                indices[kind]=idx+1
                advanced=true
                emit(kind,item)
                if #result>=budget then break end
            end
        end
        if not advanced then break end
    end
    -- Snapshot-local diagnostic: selected count is a representative-cluster
    -- count, not a count of exact spawns. No hidden state is persisted.
    local inViewKinds={}
    for _,selected in ipairs(result) do
        local p=selected.point
        local key=p.professionKey..":"..p.resourceKey
        inViewKinds[key]=(inViewKinds[key] or 0)+1
    end
    local candidateCount=0
    for _,kind in ipairs(types) do candidateCount=candidateCount+#ordered[kind] end
    self._lastSelectionMetrics.visibleCandidates=candidateCount
    self._lastSelectionMetrics.representedKinds=inViewKinds
    self._lastSelectionMetrics.representedKindCount=#types
    self._lastSelectionMetrics.selectedRepresentatives=#result
    self._lastSelectionMetrics.budget=budget
    self._lastSelectionMetrics.budgetLimited=candidateCount>#result
    -- Third return is ephemeral presentation budget for the same selection.
    -- Render must not revalidate the full point set through ComputeBudget().
    -- ComputeBudget remains public for legacy callers and retains semantics.
    return result,kindCount,budget,project
end
function Overlay:GetSelectionDiagnostics()
    local copy={}
    for key,value in pairs(self._lastSelectionMetrics or {}) do copy[key]=value end
    copy.nativeDispatchAllowed=false
    return copy
end
local function tooltip(button,point)
    if not GameTooltip or not GameTooltip.SetOwner or not point then return end
    GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
    local name=point.resourceKey:gsub("_"," "):lower():gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end)
    GameTooltip:SetText(name)
    if point.personallyObserved then
        GameTooltip:AddLine("PERSONALLY OBSERVED · successful gather + loot",0.30,1,0.46)
        GameTooltip:AddLine("Recorded interactions: "..tostring(point.count or 1),0.8,0.9,1)
        if type(point.observedAt)=="number" and date then
            GameTooltip:AddLine("Last recorded: "..date("%Y-%m-%d %H:%M",point.observedAt),0.75,0.84,1)
        end
        if point.personalOnly then GameTooltip:AddLine("Approximate player location; not an exact node coordinate",1,0.78,0.34,true) end
    else
        GameTooltip:AddLine(point.professionKey.." · historical reference",0.75,0.86,1)
    end
    if type(point.requiredSkill)=="number" then
        local low=type(point.skill)=="number" and point.skill<point.requiredSkill
        GameTooltip:AddLine("Required skill: "..point.requiredSkill..(low and " · NOT GATHERABLE YET" or ""),
            low and 1 or 0.8,low and 0.25 or 0.86,0.25)
    end
    if button.clusterCount and button.clusterCount>1 then
        GameTooltip:AddLine("Nearby historical references: "..button.clusterCount.." (zoom in to separate)",0.65,0.86,1)
        local entries={}
        for kind,count in pairs(button.clusterResources or {}) do
            entries[#entries+1]={kind=kind,count=count}
        end
        table.sort(entries,function(a,b) return a.kind<b.kind end)
        for i=1,math.min(5,#entries) do
            local part=entries[i]
            GameTooltip:AddLine(part.kind:gsub("_"," ").." · "..part.count,0.65,0.86,1)
        end
        if #entries>5 then GameTooltip:AddLine("+"..(#entries-5).." other resource types",0.65,0.86,1) end
    end
    if button.iconStatus=="PROFESSION_FALLBACK" then
        GameTooltip:AddLine("No exact historical icon available; profession icon fallback",0.85,0.65,0.36)
    end
    GameTooltip:AddLine("Sources: "..table.concat(point.sources or {},", "),0.65,0.75,0.8)
    local explanation=JLP:GetModule("GatheringOutputExplanation")
    if point.clothLoot then
        GameTooltip:AddLine("Manual combat/kill-loot reference. No gathering profession, cast, yield, rate or current spawn is implied.",0.78,0.84,0.90,true)
    elseif explanation then
        local lines=explanation:TooltipLines(point.professionKey,point.resourceKey)
        for _,line in ipairs(lines) do
            GameTooltip:AddLine(line,0.78,0.84,0.90,true)
        end
    end
    GameTooltip:AddLine("Observation history only · NOT a detected active spawn",0.75,0.75,0.75,true)
    GameTooltip:Show()
end
local function drawRoutes(self,canvas,art,mapAdapter,routeSnapshot)
    canvas.gatheringRouteStrokes=canvas.gatheringRouteStrokes or {}
    local used=0
    local routes=routeSnapshot and routeSnapshot.mapID==art.mapID and routeSnapshot.routes or nil
    -- Dimensions are immutable during this synchronous overlay paint. Reading
    -- them once and using scalar Liang-Barsky edges avoids four temporary
    -- edge tables (plus their container) for EVERY dashed mining stroke.
    local clipWidth=canvas.GetWidth and canvas:GetWidth() or 740
    local clipHeight=canvas.GetHeight and canvas:GetHeight() or 350
    -- Transform once for this synchronous route paint, not once per waypoint.
    -- The adapter's projector is deliberately not retained across frames.
    local project=type(mapAdapter.PrepareNormalizedProjection)=="function" and
        mapAdapter:PrepareNormalizedProjection(canvas,art) or nil
    if type(project)~="function" then
        project=function(x,y) return mapAdapter:ProjectNormalizedToCanvas(canvas,art,x,y) end
    end
    local clipAttempts=0
    local offscreenSegments=0
    local geometryRebinds=0
    -- Exact AABB rejection against the Liang-Barsky viewport. All dashed
    -- subsegments of a rejected Mining edge are outside as well. No shared
    -- art/view cache: calculated anew for every synchronous overlay paint.
    -- Reject malformed or overflowed screen projections before clipping.
    -- This is paint-local validation: it never alters canonical route points
    -- and cannot cache values across zoom, pan, map or route generations.
    local projectionLimit=math.max(clipWidth,clipHeight,1)*1000000
    local function finiteProjection(x,y)
        -- Bounded comparisons reject NaN, +/-Inf and extreme magnitudes
        -- without redundant abs/infinity tests per projected endpoint.
        return type(x)=="number" and type(y)=="number" and
            x>=-projectionLimit and x<=projectionLimit and
            y>=-projectionLimit and y<=projectionLimit
    end
    local function outsideViewport(x1,y1,x2,y2)
        return (x1<0 and x2<0) or (x1>clipWidth and x2>clipWidth) or
            (y1>0 and y2>0) or (y1 < -clipHeight and y2 < -clipHeight)
    end
    local function clipEdge(p,q,t0,t1)
        if p==0 then return q>=0,t0,t1 end
        local ratio=q/p
        if p<0 then t0=math.max(t0,ratio) else t1=math.min(t1,ratio) end
        return true,t0,t1
    end
    local function stroke(x1,y1,x2,y2,color)
        if used>=self.maxRouteStrokes then return end
        clipAttempts=clipAttempts+1
        local dx,dy=x2-x1,y2-y1
        local length=math.sqrt(dx*dx+dy*dy)
        if length<1 then return end
        local t0,t1=0,1
        -- Equivalent to the original four-edge clip, in exactly the same
        -- order. No persistent cache and no change to advisory route geometry.
        local ok
        ok,t0,t1=clipEdge(-dx,x1,t0,t1)
        if not ok then return end
        ok,t0,t1=clipEdge(dx,clipWidth-x1,t0,t1)
        if not ok then return end
        ok,t0,t1=clipEdge(-dy,clipHeight+y1,t0,t1)
        if not ok then return end
        ok,t0,t1=clipEdge(dy,-y1,t0,t1)
        if not ok or t0>=t1 then return end
        local sx1,sy1=x1+dx*t0,y1+dy*t0
        local sx2,sy2=x1+dx*t1,y1+dy*t1
        x1,y1,x2,y2=sx1,sy1,sx2,sy2
        dx,dy=x2-x1,y2-y1
        length=math.sqrt(dx*dx+dy*dy)
        used=used+1
        local t=canvas.gatheringRouteStrokes[used]
        if not t then
            t=canvas:CreateTexture(nil,"ARTWORK",nil,5)
            t:SetTexture(WHITE)
            canvas.gatheringRouteStrokes[used]=t
        end
        local centerX,centerY=(x1+x2)/2,(y1+y2)/2
        local angle
        if type(math.atan2)=="function" then angle=math.atan2(dy,dx)
        elseif dx>0 then angle=math.atan(dy/dx)
        elseif dx<0 then angle=math.atan(dy/dx)+(dy>=0 and math.pi or -math.pi)
        else angle=dy>=0 and math.pi/2 or -math.pi/2 end
        local signatureChanged=t.__jlpRouteCanvas~=canvas or
            t.__jlpRouteX~=centerX or t.__jlpRouteY~=centerY or
            t.__jlpRouteLength~=length or t.__jlpRouteAngle~=angle or
            t.__jlpRouteColor~=color
        if signatureChanged then
            if t.ClearAllPoints then t:ClearAllPoints() end
            t:SetPoint("CENTER",canvas,"TOPLEFT",centerX,centerY)
            t:SetSize(length,2.5)
            if t.SetRotation then t:SetRotation(angle) end
            t:SetVertexColor(color[1],color[2],color[3],0.88)
            t.__jlpRouteCanvas=canvas;t.__jlpRouteX=centerX;t.__jlpRouteY=centerY
            t.__jlpRouteLength=length;t.__jlpRouteAngle=angle;t.__jlpRouteColor=color
            geometryRebinds=geometryRebinds+1
        end
        t:Show()
    end
    for _,key in ipairs({"HERBALISM","MINING"}) do
        -- The visible cap is already exhausted. Avoid projecting remaining
        -- segments in this and later professions: they cannot create strokes.
        -- No cached coordinates or route state survive this synchronous paint.
        if used>=self.maxRouteStrokes then break end
        local route=routes and routes[key]
        if route and type(route.points)=="table" and #route.points>1 then
            local last=#route.points
            local count=route.closed and last or last-1
            -- Consecutive segments share endpoints. Keep projected coordinates
            -- only for THIS synchronous draw; no stale cache across viewport,
            -- zone, profession or map/provenance changes. Closing a loop uses
            -- the same first projection instead of projecting the start again.
            local initial=route.points[1]
            local firstX,firstY
            if type(initial)=="table" then
                firstX,firstY=project(initial.x,initial.y)
            end
            if not finiteProjection(firstX,firstY) then firstX,firstY=nil,nil end
            -- FROM_PLAYER has an explicit, validated origin. Render the
            -- previously missing initial leg without inventing a path between
            -- zones or relying on a live player position during repaint.
            local origin=route.startPosition
            if route.shape=="FROM_PLAYER" and type(origin)=="table" and
                type(origin.x)=="number" and type(origin.y)=="number" and
                origin.x>=0 and origin.x<=1 and origin.y>=0 and origin.y<=1 and
                firstX then
                local ox,oy=project(origin.x,origin.y)
                if finiteProjection(ox,oy) and not outsideViewport(ox,oy,firstX,firstY) then
                    if key=="MINING" then
                        local dx,dy=firstX-ox,firstY-oy
                        local dist=math.sqrt(dx*dx+dy*dy)
                        if dist>0 then
                            local distance=0
                            while distance<dist and used<self.maxRouteStrokes do
                                local finish=math.min(dist,distance+6)
                                stroke(ox+dx*distance/dist,oy+dy*distance/dist,
                                    ox+dx*finish/dist,oy+dy*finish/dist,COLORS[key])
                                distance=distance+11
                            end
                        end
                    else
                        stroke(ox,oy,firstX,firstY,COLORS[key])
                    end
                end
            end
            local x1,y1=firstX,firstY
            for i=1,count do
                if used>=self.maxRouteStrokes then break end
                local b=route.points[i==last and 1 or i+1]
                local x2,y2
                if i==last then x2,y2=firstX,firstY
                elseif type(b)=="table" then
                    x2,y2=project(b.x,b.y)
                end
                if not finiteProjection(x2,y2) then x2,y2=nil,nil end
                -- Previous endpoint was already validated when it was read.
                if x1 and x2 then
                    if outsideViewport(x1,y1,x2,y2) then
                        offscreenSegments=offscreenSegments+1
                    elseif key=="MINING" then
                        local dx,dy=x2-x1,y2-y1
                        local length=math.sqrt(dx*dx+dy*dy)
                        local d=0
                        while d<length and used<self.maxRouteStrokes do
                            local e=math.min(length,d+6)
                            stroke(x1+dx*d/length,y1+dy*d/length,x1+dx*e/length,y1+dy*e/length,COLORS[key])
                            d=d+11
                        end
                    else
                        stroke(x1,y1,x2,y2,COLORS[key])
                    end
                end
                x1,y1=x2,y2
            end
        end
    end
    for i=used+1,#canvas.gatheringRouteStrokes do
        local texture=canvas.gatheringRouteStrokes[i]
        texture:Hide();texture.__jlpRouteCanvas=nil
    end
    canvas.gatheringRouteStrokesVisible=used
    canvas.gatheringRouteGeometryRebinds=geometryRebinds
    -- Read-only scalar counters for offline diagnosis; no route authority.
    canvas.gatheringRouteClipAttempts=clipAttempts
    canvas.gatheringRouteOffscreenSegments=offscreenSegments
end
local function drawFishingAreas(canvas,art,mapAdapter,spatial)
    canvas.gatheringFishingSectors=canvas.gatheringFishingSectors or {}
    canvas.gatheringFishingAreaIcons=canvas.gatheringFishingAreaIcons or {}
    local used=0
    local iconsShown=0
    local icons=JLP:GetModule("FishingResourceCatalogue70450")
    local iconPaths={}
    local project=type(mapAdapter.PrepareNormalizedProjection)=="function" and
        mapAdapter:PrepareNormalizedProjection(canvas,art) or nil
    if type(project)~="function" then
        project=function(x,y) return mapAdapter:ProjectNormalizedToCanvas(canvas,art,x,y) end
    end
    if spatial and spatial.mapID==art.mapID and spatial.fishingEnabled then
        for _,sector in ipairs(spatial.areas or {}) do
            local x,y=project(sector.x,sector.y)
            local x2,y2=project(sector.x+sector.width,sector.y+sector.height)
            if x and x2 and used<48 then
                local w=canvas.GetWidth and canvas:GetWidth() or 740
                local h=canvas.GetHeight and canvas:GetHeight() or 350
                local left,right=math.max(0,x),math.min(w,x2)
                local top,bottom=math.min(0,y),math.max(-h,y2)
                if right>left and top>bottom then
                used=used+1
                local texture=canvas.gatheringFishingSectors[used]
                if not texture then
                    texture=canvas:CreateTexture(nil,"ARTWORK",nil,1)
                    texture:SetTexture(WHITE)
                    canvas.gatheringFishingSectors[used]=texture
                end
                if texture.ClearAllPoints then texture:ClearAllPoints() end
                texture:SetPoint("TOPLEFT",canvas,"TOPLEFT",left,top)
                texture:SetSize(right-left,top-bottom)
                -- Transparent blue footprint, never a point marker or route line.
                texture:SetVertexColor(0.22,0.59,0.96,0.27)
                texture:Show()
                -- Artwork is an annotation INSIDE a coarse historical sector,
                -- not a point location, pool pin or waypoint. A specific fish
                -- icon is used only after a native item-icon identity match.
                local artIcon=canvas.gatheringFishingAreaIcons[used]
                if not artIcon then
                    artIcon=canvas:CreateTexture(nil,"ARTWORK",nil,2)
                    canvas.gatheringFishingAreaIcons[used]=artIcon
                end
                local species=sector.itemIDs and #sector.itemIDs==1 and sector.itemIDs[1] or nil
                local memoKey=species or "GENERIC"
                local path=iconPaths[memoKey]
                if not path then
                    path=icons and icons:ResolveIcon(art.mapID,species)
                    if path then iconPaths[memoKey]=path end
                end
                if path and right-left>=10 and top-bottom>=10 then
                    artIcon:SetTexture(path)
                    if artIcon.SetVertexColor then artIcon:SetVertexColor(1,1,1,0.82) end
                    if artIcon.ClearAllPoints then artIcon:ClearAllPoints() end
                    artIcon:SetPoint("CENTER",canvas,"TOPLEFT",(left+right)/2,(top+bottom)/2)
                    local artSize=math.min(17,right-left-2,top-bottom-2)
                    artIcon:SetSize(artSize,artSize)
                    artIcon:Show();iconsShown=iconsShown+1
                else artIcon:Hide() end
                end
            end
        end
    end
    for i=used+1,#canvas.gatheringFishingSectors do canvas.gatheringFishingSectors[i]:Hide() end
    for i=used+1,#canvas.gatheringFishingAreaIcons do canvas.gatheringFishingAreaIcons[i]:Hide() end
    canvas.gatheringFishingSectorsVisible=used
    canvas.gatheringFishingAreaIconsVisible=iconsShown
end
-- Drag-only geometry pass. The last full render has already verified the
-- historical snapshot and selected representative clusters. Reproject those
-- SAME buttons during a drag; do not revisit thousands of source POINTs,
-- allocate pin widgets, resolve icons, or rebuild cluster composition until
-- mouse release. Existing cluster counts remain provisional during motion.
-- Return false on stale cache so the normal, authoritative render can recover.
function Overlay:RenderPan(canvas,art,mapAdapter,routeSnapshot,spatialSnapshot)
    local cache=canvas and canvas.__jlpSelectedPoints
    local view=canvas and canvas.gatheringView or nil
    if not (canvas and art and mapAdapter and cache and view and
        cache.mapID==art.mapID and cache.art==art and
        cache.zoom==view.zoom and cache.width==canvas:GetWidth() and
        cache.height==canvas:GetHeight() and
        cache.display==canvas.gatheringDisplayMode and
        type(cache.points)=="table" and type(canvas.gatheringPins)=="table" and
        type(mapAdapter.PrepareNormalizedProjection)=="function") then
        return false,"PAN_SELECTION_UNAVAILABLE"
    end
    local project=mapAdapter:PrepareNormalizedProjection(canvas,art)
    if type(project)~="function" then return false,"PAN_PROJECTOR_UNAVAILABLE" end
    -- Validate identity BEFORE mutating any widgets. The indices are exactly
    -- those of the previous full draw, with no sorting or recreation here.
    for i,selected in ipairs(cache.points) do
        local pin=canvas.gatheringPins[i]
        if not (pin and selected and selected.point and
            pin.referenceRecord==selected.point) then
            return false,"PAN_PIN_IDENTITY_STALE"
        end
    end
    drawFishingAreas(canvas,art,mapAdapter,spatialSnapshot)
    drawRoutes(self,canvas,art,mapAdapter,routeSnapshot)
    local w,h=canvas:GetWidth(),canvas:GetHeight()
    local inset=math.min(14,math.max(0,math.min(w,h)/4))
    local visible,moved=0,0
    for i,selected in ipairs(cache.points) do
        local pin=canvas.gatheringPins[i]
        local point=selected.point
        local px,py=project(point.x,point.y)
        -- Do NOT clamp an off-screen pin to the border while dragging:
        -- that would create phantom markers along the viewport edge.
        local originallyVisible=px and py and px>=inset and px<=w-inset and
            py<=-inset and py>=-h+inset
        if originallyVisible then px,py=pinPosition(selected,px,py,w,h) end
        if originallyVisible and px and py and px>=inset and px<=w-inset and
            py<=-inset and py>=-h+inset then
            if pin.__jlpAnchorX~=px or pin.__jlpAnchorY~=py or
                pin.__jlpAnchorCanvas~=canvas then
                if pin.ClearAllPoints then pin:ClearAllPoints() end
                pin:SetPoint("CENTER",canvas,"TOPLEFT",px,py)
                pin.__jlpAnchorX=px;pin.__jlpAnchorY=py
                pin.__jlpAnchorCanvas=canvas
                moved=moved+1
            end
            pin:Show();visible=visible+1
        else
            pin:Hide()
        end
    end
    for i=#cache.points+1,#canvas.gatheringPins do
        canvas.gatheringPins[i]:Hide()
    end
    canvas.gatheringPinsVisible=visible
    canvas.__jlpPanPreviewMoves=moved
    -- The full pin selection, spatial grid and cluster labels are refreshed on
    -- mouse release. No source/route/SavedVariables state is modified here.
    return true,{visible=visible,moved=moved,selected=#cache.points}
end

function Overlay:Render(canvas,art,snapshot,mapAdapter,routeSnapshot,spatialSnapshot)
    if not canvas or not art or not snapshot or snapshot.mapID~=art.mapID or
       not mapAdapter or type(mapAdapter.ProjectNormalizedToCanvas)~="function" then
        self:Clear(canvas);return {visible=0,total=0,status="MAP_MISMATCH"}
    end
    drawFishingAreas(canvas,art,mapAdapter,spatialSnapshot)
    drawRoutes(self,canvas,art,mapAdapter,routeSnapshot)
    -- A route-only redraw cannot change the immutable layer-controller snapshot.
    -- Keep just ONE selection per canvas, not a global list of historical nodes.
    -- The source cache returns a new snapshot identity on every filter, map,
    -- profession, source or import epoch. Never reuse across viewport/art changes.
    local view=canvas.gatheringView or {}
    local width=canvas.GetWidth and canvas:GetWidth() or 0
    local height=canvas.GetHeight and canvas:GetHeight() or 0
    local cache=canvas.__jlpSelectedPoints
    local snapshotKey=type(snapshot.__jlpLayerSnapshotKey)=="string" and
        snapshot.__jlpLayerSnapshotKey or nil
    local same=snapshotKey and cache and cache.snapshot==snapshot and
        cache.snapshotKey==snapshotKey and cache.art==art and
        cache.mapID==art.mapID and cache.width==width and cache.height==height and
        cache.zoom==view.zoom and cache.centerX==view.centerX and
        cache.centerY==view.centerY and cache.display==canvas.gatheringDisplayMode
    local points,types,selectionBudget,selectedProjection
    if same then
        points,types,selectionBudget=cache.points,cache.types,cache.budget
        -- Never cache a prepared projector/visibility envelope across a render.
        -- It is rebuilt for the current native canvas and only projected pins
        -- (not the full input) need the adapter on this route-only redraw.
        local prepare=mapAdapter.PrepareNormalizedProjection
        if type(prepare)=="function" then
            selectedProjection=prepare(mapAdapter,canvas,art)
            if type(selectedProjection)~="function" then selectedProjection=nil end
        end
        -- Keep coverage diagnostics for cached redraws. Erasing the counts
        -- here previously made a cache hit appear to have zero resource kinds.
        self._lastSelectionMetrics={}
        for k,v in pairs(cache.selectionMetrics or {}) do
            self._lastSelectionMetrics[k]=v
        end
        self._lastSelectionMetrics.validityChecks=0
        self._lastSelectionMetrics.projectionCalls=0
        self._lastSelectionMetrics.selectionCacheHit=true
        self._lastSelectionMetrics.nativeDispatchAllowed=false
    else
        points,types,selectionBudget,selectedProjection=self:SelectPoints(snapshot,canvas,art)
        canvas.__jlpSelectedPoints=snapshotKey and
            {snapshot=snapshot,snapshotKey=snapshotKey,art=art,mapID=art.mapID,
            width=width,height=height,zoom=view.zoom,centerX=view.centerX,
            centerY=view.centerY,display=canvas.gatheringDisplayMode,
            points=points,types=types,budget=selectionBudget,
            selectionMetrics=self:GetSelectionDiagnostics()}
    end
    canvas.gatheringPins=canvas.gatheringPins or {}
    local icons=JLP:GetModule("GatheringResourceIcons")
    local used=0
    -- Reuse the prepared viewport projector from THIS synchronous selection.
    -- Never retain across canvas resize, zoom, map, frame or generation.
    local project=selectedProjection
    -- Resolve one artwork identity per type per paint; these are immutable
    -- original assets, but the memo expires with THIS render, never a source cache.
    local iconPaths,iconLookups={},0
    local textureRebinds=0
    local anchorRebinds=0
    for _,selected in ipairs(points) do
        local point=selected.point
        local px,py
        if project then px,py=project(point.x,point.y)
        else px,py=mapAdapter:ProjectNormalizedToCanvas(canvas,art,point.x,point.y) end
        if px and py then px,py=pinPosition(selected,px,py,width,height) end
        if px then
            used=used+1
            local button=canvas.gatheringPins[used]
            if not button then
                button=CreateFrame("Button",nil,canvas)
                button:SetSize(14,14)
                -- Explicit canvas-local pin plane: above tile/route textures,
                -- below sibling dock/overlay frames at their own strata.
                if button.SetFrameLevel and canvas.GetFrameLevel then
                    button:SetFrameLevel(canvas:GetFrameLevel()+2)
                end
                -- Never fill an opaque profession-color square behind the original
                -- resource artwork. Historical icons retain their actual pixels.
                button.border=button:CreateTexture(nil,"OVERLAY",nil,1)
                button.border:SetPoint("CENTER");button.border:SetSize(14,14)
                button.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
                button.dot=button:CreateTexture(nil,"OVERLAY",nil,2)
                button.dot:SetPoint("CENTER");button.dot:SetSize(13,13)
                button.ownMark=button:CreateTexture(nil,"OVERLAY",nil,3)
                button.ownMark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                button.ownMark:SetSize(10,10);button.ownMark:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",4,-3)
                button.ownMark:Hide()
                button.clusterLabel=button:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                button.clusterLabel:SetPoint("TOPRIGHT",button,"TOPRIGHT",5,6)
                if button.clusterLabel.SetTextColor then button.clusterLabel:SetTextColor(0.95,0.97,1,1) end
                button.clusterLabel:Hide()
                button:SetScript("OnMouseDown",function(_,key)
                    if key=="LeftButton" and canvas.__gatheringPanStart then
                        canvas.__gatheringPanStart()
                    end
                end)
                button:SetScript("OnMouseUp",function(_,key)
                    if key=="LeftButton" and canvas.__gatheringPanStop then
                        canvas.__gatheringPanStop()
                    end
                end)
                button:SetScript("OnEnter",function(self) tooltip(self,self.referenceRecord) end)
                button:SetScript("OnLeave",function(self)
                    if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self)
                    elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
                end)
                canvas.gatheringPins[used]=button
            end
            if button.SetFrameLevel and canvas.GetFrameLevel then
                local level=canvas:GetFrameLevel()+2
                if not button.GetFrameLevel or button:GetFrameLevel()~=level then
                    button:SetFrameLevel(level)
                end
            end
            button.referenceRecord=point
            button.cellCount=selected.cellCount
            button.clusterCount=selected.clusterCount
            button.clusterResources=selected.clusterResources
            if button.clusterLabel then
                local n=selected.clusterCount or 1
                button.clusterLabel:SetText(n>9 and "9+" or tostring(n))
                button.clusterLabel:SetShown(n>1)
            end
            local byProfession=iconPaths[point.professionKey]
            if not byProfession then byProfession={};iconPaths[point.professionKey]=byProfession end
            local artwork=byProfession[point.resourceKey]
            if not artwork then
                local path,status
                if icons then path,status=icons:Resolve(point.professionKey,point.resourceKey) end
                artwork={path=path or "Interface\\Icons\\INV_Misc_QuestionMark",status=status}
                byProfession[point.resourceKey]=artwork
                iconLookups=iconLookups+1
            end
            button.iconStatus=artwork.status
            if button.__jlpGatheringIconPath~=artwork.path then
                button.dot:SetTexture(artwork.path)
                button.__jlpGatheringIconPath=artwork.path
                textureRebinds=textureRebinds+1
            end
            button.dot:SetVertexColor(1,1,1,point.personallyObserved and 1 or 0.9)
            button.ownMark:SetShown(point.personallyObserved==true)
            button.border:SetSize(point.personallyObserved and 17 or 14,point.personallyObserved and 17 or 14)
            local color=COLORS[point.professionKey]
            button.border:SetVertexColor(color[1],color[2],color[3],point.personallyObserved and 0.75 or 0.18)
            -- Frame anchors are expensive WoW UI mutations. A generation
            -- may force a redraw even when the selected POINT maps to the
            -- exact same pixel. Never reanchor an unchanged visible pin.
            -- The memo is owned by this pin, not a global POINT/source cache.
            if button.__jlpAnchorX~=px or button.__jlpAnchorY~=py or
                button.__jlpAnchorCanvas~=canvas then
                if button.ClearAllPoints then button:ClearAllPoints() end
                button:SetPoint("CENTER",canvas,"TOPLEFT",px,py)
                button.__jlpAnchorX=px;button.__jlpAnchorY=py
                button.__jlpAnchorCanvas=canvas
                anchorRebinds=anchorRebinds+1
            end
            button:Show()
        end
    end
    local hovered=GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() or nil
    for i=used+1,#canvas.gatheringPins do
        local pin=canvas.gatheringPins[i]
        if pin==hovered and JLP.UIInteraction then JLP.UIInteraction:HideTooltip(pin) end
        pin:Hide()
    end
    canvas.gatheringPinsVisible=used
    canvas.gatheringPinIconLookups=iconLookups
    canvas.gatheringPinTextureRebinds=textureRebinds
    canvas.gatheringPinAnchorRebinds=anchorRebinds
    canvas.gatheringOverlayMapID=art.mapID
    local diagnostics=self._lastSelectionMetrics or {}
    return {visible=used,total=snapshot.total or 0,selectedTypes=types,
        visibleCandidates=diagnostics.visibleCandidates or used,
        budgetLimited=diagnostics.budgetLimited==true,
        representedResourceKinds=diagnostics.representedKindCount or 0,
        displayMode=self:DisplayContract(canvas).mode,
        legend="Historical references; green check = personal observation; not active spawns",
        budget=selectionBudget or 0,
        routeStrokes=canvas.gatheringRouteStrokesVisible or 0,
        iconLookups=iconLookups,textureRebinds=textureRebinds,
        anchorRebinds=anchorRebinds,nativePaintStatus="UNKNOWN",
        routeClipAttempts=canvas.gatheringRouteClipAttempts or 0,
        routeGeometryRebinds=canvas.gatheringRouteGeometryRebinds or 0,
        fishingSectors=canvas.gatheringFishingSectorsVisible or 0,
        fishingAreaIcons=canvas.gatheringFishingAreaIconsVisible or 0,
        status=used>0 and (snapshot.observationCount and snapshot.observationCount>0 and
            "PERSONAL_AND_REFERENCE" or "REFERENCE_ONLY") or
            (canvas.gatheringFishingSectorsVisible or 0)>0 and "HISTORICAL_FISHING_AREAS_ONLY" or
            "NO_VISIBLE_REFERENCES",
        personallyObserved=snapshot.observationCount or 0,unresolved=snapshot.unresolvedCount or 0,
        truncated=used<(snapshot.total or 0)}
end
JLP:RegisterModule("GatheringMapOverlay",Overlay)
