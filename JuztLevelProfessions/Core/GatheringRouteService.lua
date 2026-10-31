local _, JLP = ...
-- Advisory router. A rejected Start must not cancel an independent route or
-- replace the last successful presentation context.
local Router={contract="jlp-gathering-route-service-v2",nativeDispatchAllowed=false}
local progressStatuses={GENERATING=true,READY=true,EMPTY=true,NO_ACTIVE_ROUTE=true,
    ERROR=true,NO_ELIGIBLE_ROUTE=true,ROUTE_ERROR=true,CANCELLED=true}
local function validMap(id)
    return type(id)=="number" and id>0 and id==math.floor(id)
end
-- Native UI timing is optional. No wall-clock estimate is fabricated offline.
local function clockMs()
    if type(debugprofilestop)~="function" then return nil end
    local ok,value=pcall(debugprofilestop)
    return ok and type(value)=="number" and value==value and value>=0 and
        value<1e12 and value or nil
end
local function elapsedMs(start)
    local tick=clockMs()
    return tick and start and tick>=start and math.floor(tick-start) or nil
end
local function snapshot()
    local state=JLP:GetModule("GatheringSharedMapState")
    if type(state)~="table" or type(state.GetSnapshot)~="function" then return nil,"STATE_UNAVAILABLE" end
    local ok,current=pcall(state.GetSnapshot,state)
    if not ok or type(current)~="table" or
        (current.mode~="SMART_PROFESSION" and current.mode~="CUSTOM_LOOP") then
        return nil,"STATE_UNAVAILABLE" end
    return current
end
local function service(mode)
    return JLP:GetModule(mode=="SMART_PROFESSION" and "GatheringSmartRoute" or "GatheringCustomRoute")
end
local function callable(module,method)
    return type(module)=="table" and type(module[method])=="function"
end
function Router:GetContextToken(mapID)
    if not validMap(mapID) then return nil,"MAP_ID_INVALID" end
    local current,err=snapshot()
    if not current then return nil,err end
    local state=JLP:GetModule("GatheringSharedMapState")
    local key
    if callable(state,"GetRouteContextKey") then
        local ok,result=pcall(state.GetRouteContextKey,state,mapID)
        if ok and type(result)=="string" then key=result end
    end
    if not key then
        key=tostring(mapID)..":"..current.mode..":"..tostring(current.focus)..":"..
            tostring(current.routeShape)..":"..tostring(current.routeSource)
    end
    -- A map/filter match is not sufficient: imported reference points,
    -- personally confirmed observations and learned skill levels can change
    -- while an asynchronous route is building or after it reaches READY.
    -- All three identifiers are constant-time/low-cardinality reads. No
    -- expensive planner recalculation or packed-reference decode per frame.
    local registry=JLP:GetModule("GatheringDataRegistry")
    local observations=JLP:GetModule("GatheringObservationStore")
    local professionAPI=JLP:GetModule("ProfessionAPI")
    local fields={key,"referenceEpoch="..tostring(registry and registry._mutationEpoch or "UNAVAILABLE")}
    local observedRevision=nil
    if callable(observations,"GetRevision") then
        local ok,rev=pcall(observations.GetRevision,observations)
        if ok and type(rev)=="number" and rev==rev then observedRevision=rev end
    end
    fields[#fields+1]="observationRevision="..tostring(observedRevision or "UNAVAILABLE")
    for _,profession in ipairs({"HERBALISM","MINING"}) do
        local skill,known="UNAVAILABLE",false
        if callable(professionAPI,"Get") then
            local ok,p=pcall(professionAPI.Get,professionAPI,profession)
            if ok and type(p)=="table" and p.key==profession and p.cached~=true and
                type(p.skill)=="number" and p.skill==p.skill and
                p.skill>=0 and p.skill<math.huge then
                skill=p.skill;known=true
            end
        end
        fields[#fields+1]=profession.."="..(known and tostring(skill) or "UNLEARNED_OR_UNKNOWN")
    end
    fields[#fields+1]="generation="..tostring(self._generation or 0)
    return table.concat(fields,"|")
end
-- A confirmed cancellation requires an explicit `true` from EVERY callable
-- route module. nil is unconfirmed (not success); false is rejection; a thrown
-- exception is an engine fault. Partial cancellation cannot be rolled back:
-- leave router generation/presentation unchanged and report a retriable error.
-- Missing/non-callable modules are ignored when at least one callable exists.
-- A user-initiated invalidation must fail CLOSED even when one engine refuses
-- cancellation. Quarantine the old advisory generation at the shared route
-- owner, so BOTH embedded and standalone viewers suppress stale READY routes.
-- This does not mutate a source record or grant any native authority.
function Router:QuarantineUnconfirmedCancellation(reason)
    self._quarantinedGeneration=self._generation or 0
    self._quarantineReason=type(reason)=="string" and reason or "CANCEL_UNCONFIRMED"
    return true,"PRESENTATION_QUARANTINED"
end
function Router:Cancel(reason)
    local attempted,confirmed,firstError=0,0,nil
    for _,key in ipairs({"GatheringSmartRoute","GatheringCustomRoute"}) do
        local module=JLP:GetModule(key)
        if callable(module,"Cancel") then
            attempted=attempted+1
            local ok,accepted,code=pcall(module.Cancel,module,reason)
            if ok and accepted==true then
                confirmed=confirmed+1
            elseif not firstError then
                firstError=not ok and "ROUTE_ERROR" or accepted==false and
                    (type(code)=="string" and code or "ROUTE_CANCEL_REJECTED") or
                    "ROUTE_CANCEL_UNCONFIRMED"
            end
        end
    end
    if attempted==0 then return false,"ROUTE_SERVICE_UNAVAILABLE" end
    if confirmed~=attempted then
        if confirmed>0 then return false,"ROUTE_CANCEL_PARTIAL" end
        return false,firstError or "ROUTE_CANCEL_UNCONFIRMED"
    end
    local follow=JLP:GetModule("GatheringWaypointProgress70450")
    if follow and type(follow.Stop)=="function" then pcall(follow.Stop,follow,"ROUTE_CANCELLED") end
    self._presentationContext=nil
    self._quarantinedGeneration=nil;self._quarantineReason=nil
    -- Fail closed for cached engine receipts after a confirmed global Stop.
    self._everOwnedGeneration=self._everOwnedGeneration or (self._generation or 0)>0
    self._generation=(self._generation or 0)+1
    self._schedulerActive=false
    -- Engine cancellation is already committed. An optional Frame.Hide failure
    -- must not turn a confirmed cancellation into a thrown/ambiguous receipt.
    if self._driver and type(self._driver.Hide)=="function" then
        pcall(self._driver.Hide,self._driver)
    end
    return true
end
function Router:Start(mapID,shape,player,onComplete)
    -- Preflight before ANY side effects to other jobs or UI context.
    if not validMap(mapID) then return false,"MAP_ID_INVALID" end
    if shape~="LOOP" and shape~="FROM_PLAYER" then return false,"SHAPE_INVALID" end
    local current,err=snapshot()
    if not current then return false,err end
    local active=service(current.mode)
    if not callable(active,"Start") then return false,"ROUTE_SERVICE_UNAVAILABLE" end
    -- Negative proof: an unavailable/rejected Frame previously allowed an
    -- engine to enter GENERATING without any OnUpdate driver. Prepare FIRST;
    -- no engine state or presentation generation is mutated on rejection.
    -- Real WoW exposes CreateFrame. Older headless engine fixtures intentionally
    -- omit it and drive Router:Tick explicitly; do not turn those manual tests
    -- into a client scheduler claim. A callable but rejected CreateFrame FAILS.
    local manualOnly=type(CreateFrame)~="function"
    if not manualOnly then
        -- Activate before engine mutation. A previously accepted Frame may reject
        -- Show on a later Start; no second unprotected Show may follow Start.
        local schedulerReady,schedulerReason=self:EnsureScheduler(false)
        if not schedulerReady then return false,schedulerReason or "SCHEDULER_UNAVAILABLE" end
    end
    local ok,started,reason=pcall(active.Start,active,mapID,shape,player,onComplete)
    if not ok then
        -- A throwing engine may have mutated its active job before raising.
        -- Preserve the prior context for diagnostics but revoke its authority
        -- to publish stale READY or continue scheduling until explicit Stop.
        if self._presentationContext then
            self:QuarantineUnconfirmedCancellation("ROUTE_START_EXCEPTION")
            self._schedulerActive=false
        end
        return false,"ROUTE_ERROR"
    end
    if not started then return false,reason or "ROUTE_ERROR" end
    -- Replacing a committed generation revokes any previous waypoint follow.
    local follow=JLP:GetModule("GatheringWaypointProgress70450")
    if follow and type(follow.Stop)=="function" then pcall(follow.Stop,follow,"ROUTE_REPLACED") end
    -- Start succeeded: only now may the inactive job be cancelled.
    local inactive=service(current.mode=="SMART_PROFESSION" and "CUSTOM_LOOP" or "SMART_PROFESSION")
    if callable(inactive,"Cancel") then pcall(inactive.Cancel,inactive,"OTHER_ROUTE_MODE_ACTIVE") end
    self._generation=(self._generation or 0)+1
    self._everOwnedGeneration=true
    self._quarantinedGeneration=nil;self._quarantineReason=nil
    local contextKey=self:GetContextToken(mapID)
    -- Bind the entire resource/zone/source/layer configuration to the accepted
    -- generation. A DB mutation while cancellation is unconfirmed MUST NOT
    -- expose the old engine's route in either Gathering Map view.
    self._presentationContext={mapID=mapID,mode=current.mode,generation=self._generation,
        contextKey=contextKey}
    -- A single service-owned OnUpdate driver advances this generation even if
    -- both (or neither) Gathering viewports are visible. Never create one per UI.
    self._schedulerActive=not manualOnly
    self._schedulerManualOnly=manualOnly
    self._schedulerElapsed=0
    self._schedulerTickCount=0
    self._schedulerGeneration=self._generation
    self._schedulerStartedMs=clockMs()
    self._schedulerFirstTickMs=nil
    self._schedulerFirstFeedbackStagedMs=nil
    self._schedulerCommittedMs=nil
    self._mapRenderCpuSampleMs=nil
    self._overlayAfterCommitMs=nil
    self._overlayWasRepainted=nil
    self._schedulerPhase="REFERENCE_LOAD"
    self._schedulerNotifyStage=nil
    self._schedulerNotifyCount=0
    self._schedulerPublishCount=0
    self._schedulerWorkChecks=0
    self._schedulerFirstStageMs={REFERENCE_LOAD=0}
    self._schedulerStageWorkChecks={REFERENCE_LOAD=0}
    self._schedulerCpuTickMs=0
    self._schedulerCpuTickMaxMs=0
    self._schedulerCpuMeasuredTicks=0
    self._schedulerStartHeapKB=(type(collectgarbage)=="function" and collectgarbage("count")) or nil
    -- Acceptance is a distinct observable service phase before expensive
    -- reference decoding begins on the first cooperative engine Tick. It uses
    -- existing subscribers, never a second OnUpdate/Tick driver. Stage time
    -- denotes receipt broadcast, not native FontString paint or FPS.
    self._schedulerClickAcceptedMs=elapsedMs(self._schedulerStartedMs)
    -- The accepted click is synchronous. Both view click handlers already stage
    -- immediate GENERATING text; the first worker-stage fanout remains Tick-
    -- owned to preserve older observer/cancel/restart reentrancy semantics.
    return started,reason
end
function Router:ContextIsCurrent(mapID)
    local origin=self._presentationContext
    -- Before this owner has ever started a route, old read-only fixtures may
    -- still inspect engine data. Once a generation was owned, however, a
    -- confirmed Stop MUST revoke presentation even if an engine returns a
    -- cached READY result after Cancel. No implicit resurrection on refresh.
    if not origin then
        if self._everOwnedGeneration then return false,"NO_ACTIVE_ROUTE" end
        return true
    end
    if origin.mapID~=mapID or
        (origin.generation~=nil and origin.generation~=(self._generation or 0)) then
        return false,"NO_ACTIVE_ROUTE"
    end
    local current=snapshot()
    if not current or current.mode~=origin.mode then return false,"NO_ACTIVE_ROUTE" end
    -- Legacy read-only presentation fixtures predate the bound contextKey;
    -- production Start always binds a non-empty key to the generation.
    if origin.contextKey~=nil then
        local currentKey=self:GetContextToken(mapID)
        if type(origin.contextKey)~="string" or origin.contextKey=="" or
            currentKey~=origin.contextKey then return false,"ROUTE_CONTEXT_CHANGED" end
    end
    if self._quarantinedGeneration~=nil and
        self._quarantinedGeneration==(self._generation or 0) then
        return false,"CANCEL_UNCONFIRMED_PRESENTATION_QUARANTINED" end
    return true
end
function Router:GetRoutes(mapID)
    if not validMap(mapID) then return nil,"MAP_ID_INVALID" end
    local contextOK,contextReason=self:ContextIsCurrent(mapID)
    if not contextOK then return nil,contextReason end
    if self._quarantinedGeneration~=nil and
        self._quarantinedGeneration==(self._generation or 0) then
        return nil,"CANCEL_UNCONFIRMED_PRESENTATION_QUARANTINED" end
    local current,err=snapshot()
    if not current then return nil,err end
    local active=service(current.mode)
    if not callable(active,"GetRoutes") then return nil,"ROUTE_SERVICE_UNAVAILABLE" end
    local ok,routes,status=pcall(active.GetRoutes,active,mapID)
    if not ok then return nil,"ROUTE_ERROR" end
    return routes,status or (routes and "READY" or "NO_ACTIVE_ROUTE")
end
function Router:GetStatusForMap(mapID)
    local routes,status=self:GetRoutes(mapID)
    if status~="NO_ACTIVE_ROUTE" then return status end
    local current=snapshot()
    local origin=self._presentationContext
    if not current or not origin or origin.mapID~=mapID or origin.mode~=current.mode or
       (origin.generation~=nil and origin.generation~=(self._generation or 0)) then return "NO_ACTIVE_ROUTE" end
    local active=service(current.mode)
    if not callable(active,"GetStatus") then return "ROUTE_SERVICE_UNAVAILABLE" end
    local ok,result=pcall(active.GetStatus,active)
    return ok and type(result)=="string" and result or "ROUTE_ERROR"
end
function Router:GetStatus()
    local origin=self._presentationContext
    if origin then
        local contextOK,contextReason=self:ContextIsCurrent(origin.mapID)
        if not contextOK then return contextReason end
    end
    local current,err=snapshot()
    if not current then return err end
    local active=service(current.mode)
    if not callable(active,"GetStatus") then return "ROUTE_SERVICE_UNAVAILABLE" end
    local ok,result=pcall(active.GetStatus,active)
    return ok and type(result)=="string" and result or "ROUTE_ERROR"
end
-- Scheduler ownership is scoped to a successful Start generation. OnUpdate is
-- independent of redraw; the service never renders, dispatches or persists.
-- One coroutine Tick is intentionally finite-cooperative; 0.02 is cadence,
-- NOT a frame-time guarantee. Manual Tick remains available for offline QA.
function Router:PumpScheduler(elapsed)
    if not self._schedulerActive then return false,"INACTIVE" end
    local context=self._presentationContext
    if not context or context.generation~=self._schedulerGeneration or
       context.generation~=(self._generation or 0) then
        self._schedulerActive=false
        return false,"STALE_GENERATION"
    end
    local contextOK,reason=self:ContextIsCurrent(context.mapID)
    if not contextOK then
        self._schedulerActive=false
        return false,reason
    end
    local dt=type(elapsed)=="number" and elapsed==elapsed and elapsed>=0 and
        elapsed<=1 and elapsed or 0.02
    self._schedulerElapsed=math.min(0.02,(self._schedulerElapsed or 0)+dt)
    if self._schedulerElapsed<0.02 then return false,"WAITING" end
    self._schedulerElapsed=0
    if self:GetStatusForMap(context.mapID)~="GENERATING" then
        self._schedulerActive=false
        return false,"NOT_GENERATING"
    end
    self._schedulerTickCount=(self._schedulerTickCount or 0)+1
    if self._schedulerFirstTickMs==nil then
        self._schedulerFirstTickMs=elapsedMs(self._schedulerStartedMs)
    end
    local cpuStart=clockMs()
    local result=self:Tick()
    -- A route engine can synchronously invoke an OnComplete callback that
    -- cancels/restarts the router. Do not attribute the old Tick's CPU/phase,
    -- commit or observer receipt to that newer generation.
    if self._generation~=context.generation or
        self._schedulerGeneration~=context.generation or
        self._presentationContext~=context then
        return false,"STALE_GENERATION_AFTER_TICK"
    end
    local cpuEnd=clockMs()
    if cpuStart and cpuEnd and cpuEnd>=cpuStart then
        local tickCpuMs=cpuEnd-cpuStart
        self._schedulerCpuTickMs=(self._schedulerCpuTickMs or 0)+tickCpuMs
        self._schedulerCpuTickMaxMs=math.max(self._schedulerCpuTickMaxMs or 0,tickCpuMs)
        self._schedulerCpuMeasuredTicks=(self._schedulerCpuMeasuredTicks or 0)+1
    end
    local progress=self:GetProgressForMap(context.mapID)
    if progress and type(progress.stage)=="string" then
        self._schedulerPhase=progress.stage
        self._schedulerWorkChecks=tonumber(progress.workChecks) or self._schedulerWorkChecks
        -- Sampled at Tick boundaries: phases completed inside one coroutine
        -- resume cannot be assigned exact start timestamps by this observer.
        self._schedulerFirstStageMs=self._schedulerFirstStageMs or {}
        self._schedulerStageWorkChecks=self._schedulerStageWorkChecks or {}
        if self._schedulerFirstStageMs[progress.stage]==nil then
            self._schedulerFirstStageMs[progress.stage]=elapsedMs(self._schedulerStartedMs)
            self._schedulerStageWorkChecks[progress.stage]=self._schedulerWorkChecks
        end
    end
    local status=self:GetStatusForMap(context.mapID)
    if status~="GENERATING" then
        self._schedulerActive=false
        self._schedulerPhase=status=="READY" and "PUBLISH" or status or "COMPLETE"
        self._schedulerCommittedMs=elapsedMs(self._schedulerStartedMs)
        self._schedulerFirstStageMs=self._schedulerFirstStageMs or {}
        self._schedulerFirstStageMs[self._schedulerPhase]=self._schedulerCommittedMs
        self._schedulerStageWorkChecks=self._schedulerStageWorkChecks or {}
        self._schedulerStageWorkChecks[self._schedulerPhase]=self._schedulerWorkChecks
    end
    -- Notify only at phase transitions, completion and bounded tick intervals.
    -- The service owns the sole Tick driver; subscribers are presentation-only.
    self:PublishProgress(status)
    return true,result
end
-- Only known viewers can subscribe; no listener may drive route execution.
-- Notifications contain primitives (no mutable engine/provenance references).
function Router:SetProgressObserver(viewer,callback)
    if viewer~="STANDALONE" and viewer~="EMBEDDED" then return false,"VIEWER_INVALID" end
    if callback~=nil and type(callback)~="function" then return false,"CALLBACK_INVALID" end
    self._progressObservers=self._progressObservers or {}
    self._observerRevision=self._observerRevision or {}
    -- A replacement/unsubscribe is not eligible for an already in-flight
    -- publication, even when it registers the same Lua function again.
    self._observerRevision[viewer]=(self._observerRevision[viewer] or 0)+1
    self._progressObservers[viewer]=callback
    return true
end
function Router:PublishProgress(status)
    local ctx=self._presentationContext
    if not ctx or ctx.generation~=(self._generation or 0) or
        ctx.generation~=self._schedulerGeneration then return false,"STALE_GENERATION" end
    if not progressStatuses[status] then return false,"STATUS_UNAVAILABLE" end
    local stage=self._schedulerPhase or "REFERENCE_LOAD"
    local count=self._schedulerTickCount or 0
    if status=="GENERATING" and stage==self._schedulerNotifyStage and
        count-(self._schedulerNotifyCount or 0)<12 then return false,"THROTTLED" end
    self._schedulerNotifyStage=stage
    self._schedulerNotifyCount=count
    local receipt={mapID=ctx.mapID,generation=ctx.generation,mode=ctx.mode,
        status=status,stage=stage,ticks=count,workChecks=self._schedulerWorkChecks or 0,
        committed=status=="READY",nativeDispatchAllowed=false}
    -- A subscriber can synchronously Cancel/Start, unsubscribe or throw.
    -- Validate at EACH boundary: a successful Start is a new generation,
    -- and the previous subscriber must not publish to the next viewer.
    local contextKey=self:GetContextToken(ctx.mapID)
    local function stillCurrent()
        -- A subscriber can change mode/focus/route source in SharedMapState
        -- without explicitly cancelling the engine. Revalidate the complete
        -- advisory context, not merely the internal generation counter.
        local currentKey=self:GetContextToken(ctx.mapID)
        return contextKey~=nil and currentKey==contextKey and
            self:ContextIsCurrent(ctx.mapID)==true and
            self._presentationContext==ctx and self._generation==ctx.generation and
            self._schedulerGeneration==ctx.generation and
            self._schedulerTickCount==count and self._schedulerPhase==stage
    end
    -- Snapshot subscriber revisions once, before invoking ANY untrusted UI
    -- callback. New subscriptions never receive stale in-flight previews.
    local observerRevisions={}
    for _,viewer in ipairs({"STANDALONE","EMBEDDED"}) do
        observerRevisions[viewer]=self._observerRevision and self._observerRevision[viewer] or 0
    end
    for _,viewer in ipairs({"STANDALONE","EMBEDDED"}) do
        if not stillCurrent() then return false,"STALE_GENERATION_DURING_PUBLISH" end
        local subscribed=(self._observerRevision and self._observerRevision[viewer] or 0)==observerRevisions[viewer]
        local callback=subscribed and self._progressObservers and self._progressObservers[viewer]
        if type(callback)=="function" then
            local isolated={}
            for key,value in pairs(receipt) do isolated[key]=value end
            local ok=pcall(callback,isolated)
            -- Subscriber faults belong only to the generation which emitted.
            if not stillCurrent() then return false,"STALE_GENERATION_DURING_PUBLISH" end
            if not ok then self._progressObserverFaults=(self._progressObserverFaults or 0)+1 end
        end
    end
    if not stillCurrent() then return false,"STALE_GENERATION_DURING_PUBLISH" end
    self._schedulerPublishCount=(self._schedulerPublishCount or 0)+1
    return true
end
function Router:EnsureScheduler(prepareOnly)
    if self._driver then
        -- Native WoW Frames expose Show/Hide. Historic headless fixtures use
        -- bare script-only stubs; preserve that manual-Tick test contract.
        if not prepareOnly and type(self._driver.Show)=="function" then
            local ok,accepted=pcall(self._driver.Show,self._driver)
            if not ok or accepted==false then return false,"SCHEDULER_FRAME_REJECTED" end
        end
        return true
    end
    if type(CreateFrame)~="function" then return false,"FRAME_API_UNAVAILABLE" end
    local ok,frame=pcall(CreateFrame,"Frame")
    if not ok or (type(frame)~="table" and type(frame)~="userdata") or
        type(frame.SetScript)~="function" then
        return false,"FRAME_API_UNAVAILABLE"
    end
    local registered,accepted=pcall(frame.SetScript,frame,"OnUpdate",function(_,elapsed)
        -- A rejected preflight frame can remain visible if its Hide method
        -- rejects the request. Its callback is inert unless the service has
        -- explicitly adopted this exact frame as the sole current driver.
        -- This also rejects stale OnUpdate callbacks after a rearm attempt.
        if Router._driver~=frame then return end
        Router:PumpScheduler(elapsed)
        if not Router._schedulerActive and type(frame.Hide)=="function" then
            pcall(frame.Hide,frame)
        end
    end)
    if not registered or accepted==false then return false,"SCHEDULER_SCRIPT_REJECTED" end
    -- Validate the ordinary frame visibility methods before accepting any job.
    -- A mock that rejects Show must not strand the engine after Start.
    if type(frame.Show)=="function" then
        local shown,showResult=pcall(frame.Show,frame)
        if not shown or showResult==false then return false,"SCHEDULER_FRAME_REJECTED" end
    end
    if type(frame.Hide)=="function" then
        local hidden,hideResult=pcall(frame.Hide,frame)
        if not hidden or hideResult==false then return false,"SCHEDULER_FRAME_REJECTED" end
    end
    if not prepareOnly and type(frame.Show)=="function" then
        local armed,armedResult=pcall(frame.Show,frame)
        if not armed or armedResult==false then return false,"SCHEDULER_FRAME_REJECTED" end
    end
    self._driver=frame
    return true
end
-- Called only when a viewport has staged feedback text. This is NOT native
-- font painting time, guaranteed first frame, or an ETA.
function Router:MarkFeedbackStaged(mapID)
    local context=self._presentationContext
    if not context or context.mapID~=mapID or
        context.generation~=self._schedulerGeneration then return false end
    if self._schedulerFirstFeedbackStagedMs==nil then
        self._schedulerFirstFeedbackStagedMs=elapsedMs(self._schedulerStartedMs)
    end
    return true
end
-- Called by an existing renderer AFTER its normal paint. This samples display
-- work independently of route construction, without driving another Tick.
-- Old map/generation receipts are rejected; client frame-time is unverified.
function Router:MarkOverlayPresented(mapID,token,paintElapsedMs,repainted)
    local ctx=self._presentationContext
    if not ctx or ctx.mapID~=mapID or ctx.generation~=(self._generation or 0) or
       ctx.generation~=self._schedulerGeneration or token~=self:GetContextToken(mapID) or
       self:GetStatusForMap(mapID)~="READY" then return false,"STALE_PRESENTATION" end
    if type(paintElapsedMs)=="number" and paintElapsedMs==paintElapsedMs and
       paintElapsedMs>=0 and paintElapsedMs<=10000 then
        self._mapRenderCpuSampleMs=paintElapsedMs
    else self._mapRenderCpuSampleMs=nil end
    self._overlayAfterCommitMs=elapsedMs(self._schedulerStartedMs)
    self._overlayWasRepainted=repainted==true
    return true
end
function Router:GetSchedulerDiagnostics()
    local firstStage,stageWork={},{}
    for k,v in pairs(self._schedulerFirstStageMs or {}) do firstStage[k]=v end
    for k,v in pairs(self._schedulerStageWorkChecks or {}) do stageWork[k]=v end
    local currentHeap=type(collectgarbage)=="function" and collectgarbage("count") or nil
    return {active=self._schedulerActive==true,
        mapID=self._presentationContext and self._presentationContext.mapID,
        generation=self._schedulerGeneration,
        ticks=self._schedulerTickCount or 0,
        phase=self._schedulerPhase or "IDLE",
        workChecks=self._schedulerWorkChecks or 0,
        firstTickElapsedMs=self._schedulerFirstTickMs,
        firstFeedbackStagedMs=self._schedulerFirstFeedbackStagedMs,
        clickAcceptedElapsedMs=self._schedulerClickAcceptedMs,
        commitElapsedMs=self._schedulerCommittedMs,
        overlayPresentedElapsedMs=self._overlayAfterCommitMs,
        mapRenderCpuSampleMs=self._mapRenderCpuSampleMs,
        renderSamplingScope="MAP_RENDER_INCLUDES_ART_AND_OVERLAY",
        overlayWasRepainted=self._overlayWasRepainted,
        cadenceSeconds=0.02,
        driverCount=self._driver and 1 or 0,
        progressObserverFaults=self._progressObserverFaults or 0,
        progressNotifications=self._schedulerPublishCount or 0,
        manualOnlyOutsideClient=self._schedulerManualOnly==true,
        phaseFirstObservedMs=firstStage,phaseFirstObservedWorkChecks=stageWork,
        tickCpuSampleMs=self._schedulerCpuTickMs or 0,
        maxObservedTickCpuMs=self._schedulerCpuTickMaxMs or 0,
        tickCpuSampleCount=self._schedulerCpuMeasuredTicks or 0,
        heapDeltaKB=currentHeap and self._schedulerStartHeapKB and
            currentHeap-self._schedulerStartHeapKB or nil,
        phaseSampling="AFTER_SERVICE_TICK",clientFrameTimeVerified=false,
        nativeDispatchAllowed=false}
end
function Router:Tick()
    local ctx=self._presentationContext
    if ctx then
        local currentContext,reason=self:ContextIsCurrent(ctx.mapID)
        if not currentContext then return reason end
    end
    local current,err=snapshot()
    if not current then return err end
    local active=service(current.mode)
    if not callable(active,"Tick") then return "ROUTE_SERVICE_UNAVAILABLE" end
    local ok,result=pcall(active.Tick,active)
    return ok and type(result)=="string" and result or "ROUTE_ERROR"
end
-- Read-only generation-scoped budget observations, not a route permission.
function Router:GetProgressForMap(mapID)
 if not validMap(mapID) then return nil end
 local context=self._presentationContext
 local state=snapshot()
 if not context or not state or context.mapID~=mapID or context.mode~=state.mode or
    context.generation~=(self._generation or 0) or
    self:ContextIsCurrent(mapID)~=true then return nil end
 local active=service(state.mode)
 if not callable(active,"GetProgress") then return nil end
 local ok,result=pcall(active.GetProgress,active,mapID)
 return ok and type(result)=="table" and result or nil
end
function Router:GetSummary(mapID)
    local origin=self._presentationContext
    if mapID~=nil and (not origin or origin.mapID~=mapID or
        origin.generation~=(self._generation or 0)) then return nil,"NO_ACTIVE_ROUTE" end
    local current,err=snapshot()
    if not current then return nil,err end
    if origin and self:ContextIsCurrent(origin.mapID)~=true then
        return nil,"ROUTE_CONTEXT_CHANGED" end
    if current.mode~="SMART_PROFESSION" then return nil,"NOT_SMART_MODE" end
    local smart=JLP:GetModule("GatheringSmartRoute")
    if not callable(smart,"GetSummary") then return nil,"ROUTE_SERVICE_UNAVAILABLE" end
    local ok,result=pcall(smart.GetSummary,smart,mapID)
    if not ok then return nil,"ROUTE_ERROR" end
    return result
end
JLP:RegisterModule("GatheringRouteService",Router)
