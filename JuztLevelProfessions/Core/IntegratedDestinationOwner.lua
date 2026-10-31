local _,JLP=...
-- Single transient destination owner: no DB writes, no automatic migration,
-- no task completion, no inventory or native authority.
local Owner={contract="jlp-unified-destination-v1",revision=0,active=nil,paused=false,stopped=false}
local CATEGORIES={CURRENT_STEP=true,BANK=true,AUCTION_HOUSE=true,VENDOR=true,
 TRAINER=true,RECIPE_SOURCE=true,MATERIAL_SOURCE=true,CRAFT_STATION=true,
 GATHERING=true,MANUAL=true}
local function integer(v) return type(v)=="number" and v>=1 and v<2147483648 and v==math.floor(v) end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function point(nav)
 if type(nav)~="table" or not integer(nav.mapID) or not finite(nav.x) or not finite(nav.y)
  or nav.x<0 or nav.x>1 or nav.y<0 or nav.y>1 then return nil end
 if nav.mapDomain~=nil and nav.mapDomain~="UI_MAP_ID" then return nil end
 return {mapID=nav.mapID,x=nav.x,y=nav.y,mapDomain="UI_MAP_ID"}
end
-- Explicit manual coordinates are a user action, never service evidence.
-- Qualified service records must come from the existing verified source contract;
-- a nonempty evidence string alone cannot grant navigation admission.
local DENIED={CANDIDATE=true,UNKNOWN=true,CONFLICT=true,RESEARCH_ONLY=true,
 PARTIAL=true,PARTIAL_RESEARCH_ONLY=true,NOT_APPROVED=true,STALE=true,
 BLOCKED=true,UNQUALIFIED=true}
local VERIFIED={SOURCE_QUALIFIED=true,VERIFIED=true,QUALIFIED=true}
local function resolveSource(category,source,context)
 if type(source)~="table" then return nil,"SOURCE_NOT_TABLE" end
 local nav=source.nav or source
 local p=point(nav)
 if not p then return nil,"NO_QUALIFIED_WAYPOINT" end
 if category=="MANUAL" then
    if context.explicit~=true or nav.evidence~="EXPLICIT_USER_ENTERED_COORDINATES"
       or source.sourceQualified==false or nav.sourceQualified==false or
       source.productionAuthorized==true or nav.productionAuthorized==true or
       source.state~=nil or source.status~=nil or nav.state~=nil or nav.status~=nil then
       return nil,"MANUAL_INPUT_NOT_VERIFIED" end
    p.evidence="EXPLICIT_USER_ENTERED_COORDINATES"
 else
    if source.sourceQualified~=true or (nav.sourceQualified~=nil and nav.sourceQualified~=true)
      or not VERIFIED[source.state or source.status] or
      (source.state~=nil and source.status~=nil and source.state~=source.status) or
      (nav.state~=nil and not VERIFIED[nav.state]) or
      (nav.status~=nil and not VERIFIED[nav.status]) or
      (nav.state~=nil and nav.status~=nil and nav.state~=nav.status) or
      source.hordeAccess==false or nav.hordeAccess==false or
      source.hordeAccess=="UNKNOWN" or nav.hordeAccess=="UNKNOWN" or
      source.hordeAccess=="CONFLICT" or nav.hordeAccess=="CONFLICT" or
      source.productionAuthorized==true or nav.productionAuthorized==true or
      nav.mapDomain~="UI_MAP_ID" then
      return nil,"NO_QUALIFIED_WAYPOINT" end
    local evidence=nav.evidence or source.evidence
    if type(evidence)~="string" or #evidence<8 or DENIED[evidence] or
       evidence=="EXPLICIT_USER_ENTERED_COORDINATES" or
       (source.evidence and nav.evidence and source.evidence~=nav.evidence) then
       return nil,"NO_QUALIFIED_WAYPOINT" end
    local resolver=JLP:GetModule("SourceResolver")
    if not resolver or type(resolver.VerifyNavigationWaypoint)~="function" then
        return nil,"CANONICAL_NAVIGATION_PROOF_MISSING" end
    local ok,bound=resolver:VerifyNavigationWaypoint(category,source)
    if ok~=true then return nil,bound or "CANONICAL_NAVIGATION_PROOF_MISSING" end
    p.evidence=evidence
    -- Typed presentation survives only fresh canonical admission, not manual flags.
    if source.serviceID=="ULDAMAN_ANNORA" and source.directBearing==true then
      p.directBearing=true;p.metricGeometry=source.metricGeometry
    end
 end
 p.label=tostring(source.name or nav.label or "Navigation waypoint"):sub(1,130)
 return p
end
local function getGeneration()
 return JLP:GetModule("GatheringRouteService")
end
-- A route READY token is not a displayed stroke. Bind the CURRENT generation
-- to the service-owned overlay-presented receipt at every consumer boundary.
-- This is a source/QA presentation contract, not native pixel verification.
local function gatheringReceipt(service,mapID,token)
 if type(service)~="table" or not integer(mapID) or type(token)~="string" then
   return false,"GATHERING_OVERLAY_RECEIPT_MISSING" end
 local generation=tonumber(token:match(":generation=(%d+)$"))
 if not integer(generation) or
    type(service.GetSchedulerDiagnostics)~="function" or
    type(service.ContextIsCurrent)~="function" or
    type(service.GetContextToken)~="function" or
    type(service.GetStatusForMap)~="function" then
   return false,"GATHERING_OVERLAY_RECEIPT_MISSING" end
 local okContext,current=pcall(service.ContextIsCurrent,service,mapID)
 local okToken,actual=pcall(service.GetContextToken,service,mapID)
 local okStatus,status=pcall(service.GetStatusForMap,service,mapID)
 if not okContext or current~=true or not okToken or actual~=token or
    not okStatus or status~="READY" then
   return false,"STALE_GATHERING_CONTEXT" end
 local ok,receipt=pcall(service.GetSchedulerDiagnostics,service)
 if not ok or type(receipt)~="table" or receipt.mapID~=mapID or
    receipt.generation~=generation or receipt.overlayWasRepainted~=true or
    not finite(receipt.overlayPresentedElapsedMs) or
    receipt.overlayPresentedElapsedMs<0 or
    (receipt.commitElapsedMs~=nil and
     (not finite(receipt.commitElapsedMs) or receipt.commitElapsedMs<0 or
      receipt.overlayPresentedElapsedMs<receipt.commitElapsedMs)) then
   return false,"GATHERING_OVERLAY_RECEIPT_MISSING" end
 return true,"RECEIPT_OBSERVED"
end
local function copy(t)
 if type(t)~="table" then return nil end
 local n={};for k,v in pairs(t) do if type(v)~="table" then n[k]=v end end;return n
end
-- This is only a serializable source *claim*. Restoring it requires a fresh
-- SourceResolver canonical comparison after /reload, never blind admission.
local function copySourceForCheckpoint(source)
 if type(source)~="table" or type(source.nav)~="table" then return nil end
 local result={}
 for k,v in pairs(source) do
   if type(k)=="string" and #k<65 and
     (type(v)=="boolean" or type(v)=="number" or
      (type(v)=="string" and #v<=512)) then result[k]=v end
 end
 result.nav={}
 for k,v in pairs(source.nav) do
   if type(k)=="string" and #k<65 and
     (type(v)=="boolean" or type(v)=="number" or
      (type(v)=="string" and #v<=512)) then result.nav[k]=v end
 end
 return result
end
function Owner:ValidateCategory(category) return CATEGORIES[category]==true end
local function workflowOwnershipReason(category,source,context)
 if category~="CURRENT_STEP" then return nil end
 local key=type(source)=="table" and (source.workflowProfessionKey or source.professionKey or source.profession)
 key=key or context and context.professionKey
 local api=JLP:GetModule("ProfessionAPI")
 local ownership=api and api.GetOwnership and api:GetOwnership(key)
 if not (ownership and ownership.owned==true) then return ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN" end
end
function Owner:ObserveProfessionOwnership()
 if not self.active then return end
 local prerequisite=workflowOwnershipReason(self.active.category,self.resumeSource)
 if prerequisite then
  self.active.ownershipBlocked=prerequisite
  local engine=JLP:GetModule("IntegratedTravelEngine")
  if engine and engine.StopGuidance then engine:StopGuidance()end
 elseif self.active.ownershipBlocked then
  self.active.ownershipBlocked=nil;self.active.needsRevalidation=true;self.active.route=nil
  self.active.routeReason="OWNERSHIP_CHANGED_SOURCE_REVALIDATION_REQUIRED"
 end -- preserve intent, Pause/Stop and every manual destination
end
function Owner:CanNavigate(category,source,context)
 if not self:ValidateCategory(category) or category=="GATHERING" then return false,"INVALID_DESTINATION_CATEGORY" end
 if context~=nil and type(context)~="table" then return false,"INVALID_CONTEXT" end
 context=context or {}
 local prerequisite=workflowOwnershipReason(category,source,context)
 if prerequisite then return false,prerequisite end
 if context.stale==true or context.status=="STALE" then return false,"STALE_CONTEXT" end
 -- Background navigation cannot silently replace a user-selected target,
 -- including a manually selected Gathering reference. A new deliberate UI
 -- action (context.explicit=true) may replace it.
 if self.active and self.active.priority>1 and context.explicit~=true then
   return false,"EXPLICIT_DESTINATION_HAS_PRIORITY" end
 if type(source)=="table" then
   -- Identities held by a visible UI card cannot be silently rebound to a
   -- different plan, character or context between Refresh and a user click.
   for _,field in ipairs({"planRevision","contextToken","characterKey"}) do
     if source[field]~=nil and source[field]~=context[field] then
       return false,"STALE_SOURCE_CONTEXT" end
   end
 end
 local p,why=resolveSource(category,source,context)
 return p~=nil,why or "WAYPOINT_QUALIFIED"
end

function Owner:NavigateTo(category,source,context)
 context=context or {}
 if not self:ValidateCategory(category) then return false,"INVALID_DESTINATION_CATEGORY" end
 if category=="GATHERING" then return false,"USE_GATHERING_SNAPSHOT" end
 if context.stale==true or context.status=="STALE" then return false,"STALE_CONTEXT" end
 local e=JLP:GetModule("NavigationCapabilityEvidence")
 local supported,why,identityProof
 if e and e.Check then supported,why,identityProof=e:Check("CHARACTER") end
 if supported~=true then return false,why or "CHARACTER_CAPABILITY_UNKNOWN" end
 if context.characterKey~=nil and context.characterKey~=identityProof.characterKey then
   return false,"CHARACTER_CHANGED" end
 context.characterKey=identityProof.characterKey
 local eligible,denial=self:CanNavigate(category,source,context)
 if not eligible then return false,denial end
 local target,reason=resolveSource(category,source,context)
 if not target then return false,reason end
 if context.contextToken~=nil and (type(context.contextToken)~="string" or context.contextToken=="") then return false,"INVALID_CONTEXT_TOKEN" end
 if self.active and self.active.priority>1 and context.explicit~=true then
   return false,"EXPLICIT_DESTINATION_HAS_PRIORITY" end
 self.revision=self.revision+1
 self.active={category=category,point=target,priority=category=="MANUAL" and 3 or
   (context.explicit==true and 2 or 1),owner=tostring(context.owner or "JLP"),
   planRevision=context.planRevision,contextToken=context.contextToken,
   characterKey=context.characterKey,
   generation=self.revision,sourceStatus="AVAILABLE",navigationOnly=true,
   route=nil,routeReason="ORIGIN_UNVERIFIED",needsRevalidation=false}
 self.paused=false;self.stopped=false
 self.resumeSource=category~='MANUAL' and copySourceForCheckpoint(source) or nil
 local engine=JLP:GetModule("IntegratedTravelEngine")
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if origin and integer(origin.mapID) and finite(origin.x) and finite(origin.y) and engine then
   local guidance,plan,why=engine:BeginGuidance(origin,target,context.characterContext)
   self.active.route=plan;self.active.routeReason=why or (plan and "ROUTE_AVAILABLE")
   if not plan and engine.StopGuidance then engine:StopGuidance() end
 else
   if engine and engine.StopGuidance then engine:StopGuidance() end
 end
 local continuity=JLP:GetModule("TravelContinuity70450")
 if continuity and continuity.OnOwnerSelected then continuity:OnOwnerSelected(self) end
 -- Write a fresh intent immediately; PLAYER_LOGOUT also refreshes this checkpoint.
 if continuity and continuity.Save then continuity:Save(self) end
 if not self.active.route then
   self.active.sourceStatus="DESTINATION_ONLY"
   return true,"DESTINATION_ONLY_NO_ROUTE"
 end
 return true,"NAVIGATION_GUIDANCE_READY"
end
function Owner:NavigateSource(category,source,context)
 return self:NavigateTo(category,source,context)
end
-- Only Current Step auto-sync may replace a previously selected automatic step.
-- It may NEVER override manual or other explicit destinations. No polling loop.
function Owner:ObservePlanContext(context)
 if type(context)~="table" then return false,"PLAN_CONTEXT_MISSING" end
 local a=self.active
 if not a or a.category~="CURRENT_STEP" or a.priority>1 then return true,"NO_AUTOMATIC_STEP" end
 if (a.contextToken~=nil and a.contextToken~=context.contextToken) or
    (a.planRevision~=nil and a.planRevision~=context.planRevision) or
    (a.characterKey~=nil and a.characterKey~=context.characterKey) then
    a.needsRevalidation=true;a.route=nil;a.routeReason="PLAN_CONTEXT_CHANGED"
    a.nativeReturnRecovery=nil
    local engine=JLP:GetModule("IntegratedTravelEngine")
    if engine and engine.StopGuidance then engine:StopGuidance() end
    return false,"PLAN_CONTEXT_CHANGED"
 end
 return true,"PLAN_CONTEXT_CURRENT"
end
function Owner:SyncCurrentStep(source,context)
 context=context or {}
 if self.stopped then return false,"STOPPED_BY_USER" end
 if self.paused then return false,"PAUSED_BY_USER" end
 if self.active and self.active.needsRevalidation then
   -- A fresh, positively re-verified plan revision can replace an OLD automatic
   -- step, but a stale zone/reload context cannot silently revive it.
   if self.active.category~="CURRENT_STEP" or self.active.routeReason~="PLAN_CONTEXT_CHANGED" or
      self.active.contextToken==context.contextToken then return false,"STALE_CONTEXT" end
 end
 local eligible,denial=self:CanNavigate("CURRENT_STEP",source,context)
 if not eligible then return false,denial end
 local target,why=resolveSource("CURRENT_STEP",source,context)
 if not target then return false,why end
 if self.active and not self.active.needsRevalidation and self.active.category=="CURRENT_STEP" and
      self.active.point and self.active.point.mapID==target.mapID and
      self.active.point.x==target.x and self.active.point.y==target.y and
      self.active.contextToken==context.contextToken and
      self.active.planRevision==context.planRevision then
      return true,"CURRENT_STEP_UNCHANGED"
 end
 local safe={};for k,v in pairs(context) do safe[k]=v end
 safe.explicit=false
 return self:NavigateTo("CURRENT_STEP",source,safe)
end
function Owner:Stop(reason)
 local gathering=JLP:GetModule("GatheringSharedMapState")
 if gathering and gathering.ClearAutomaticSupplyGoal then
  local snapshot=gathering.GetSnapshot and gathering:GetSnapshot()
  local automatic=snapshot and snapshot.automaticSupplyGoal
  if automatic then gathering:ClearAutomaticSupplyGoal(automatic.ownerProfession,"USER_STOPPED")end
 end
 local continuity=JLP:GetModule("TravelContinuity70450")
 if continuity and continuity.Clear then continuity:Clear("STOPPED_BY_USER") end
 self.revision=self.revision+1;self.active=nil;self.resumeSource=nil;self.paused=false;self.stopped=true
 local engine=JLP:GetModule("IntegratedTravelEngine")
 if engine and engine.StopGuidance then engine:StopGuidance() end
 return true,reason or "STOPPED"
end
-- Restore a saved *paused intent*, never a saved executable route.
-- The continuity service has already verified character, build, age,
-- current position and stored-point equality; source admission is repeated.
function Owner:RestorePaused(category,source,context)
 context=context or {}
 if context.owner~="AUTO_RESTORED_PAUSED_DESTINATION" or
    context.explicit~=true or self.active or self.stopped or self.paused then
    return false,"PAUSED_RESTORE_NOT_ELIGIBLE" end
 local e=JLP:GetModule("NavigationCapabilityEvidence")
 local supported,why,identityProof
 if e and e.Check then supported,why,identityProof=e:Check("POSITION") end
 if supported~=true then return false,why or "POSITION_CAPABILITY_UNKNOWN" end
 if context.characterKey~=nil and context.characterKey~=identityProof.characterKey then
    return false,"CHARACTER_CHANGED" end
 context.characterKey=identityProof.characterKey
 local valid,why=self:CanNavigate(category,source,context)
 if not valid then return false,why end
 local target,reason=resolveSource(category,source,context)
 if not target then return false,reason end
 self.revision=self.revision+1
 self.active={category=category,point=target,
   priority=category=="MANUAL" and 3 or category=="CURRENT_STEP" and context.restoreAutomatic==true and 1 or 2,
   owner="AUTO_RESTORED_PAUSED_DESTINATION",
   planRevision=context.planRevision,contextToken=context.contextToken,
   characterKey=context.characterKey,generation=self.revision,
   sourceStatus="DESTINATION_ONLY",navigationOnly=true,
   route=nil,routeReason="PAUSED_AWAITING_RESUME",needsRevalidation=false,
   restoredPaused=true}
 self.resumeSource=category~="MANUAL" and copySourceForCheckpoint(source) or nil
 self.paused=true;self.stopped=false
 local engine=JLP:GetModule("IntegratedTravelEngine")
 if engine and engine.StopGuidance then engine:StopGuidance() end
 return true,"PAUSED_INTENT_RESTORED"
end
function Owner:Pause()
 if not self.active then return false,"NO_ACTIVE_TARGET" end
 if self.active.needsRevalidation then return false,"STALE_CONTEXT" end
 if self.paused then return true,"ALREADY_PAUSED" end
 -- Pausing applies equally to local routes and map-transition advisories.
 -- Neither advances transport stages nor grants access to an unverified link.
 self.paused=true
 -- Route legs may be retained while paused only until a native zone event.
 -- Any later zone transition requires a new live-origin route on user Resume.
 self.active.pausedZoneChanged=false
 local continuity=JLP:GetModule('TravelContinuity70450')
 if continuity and continuity.SavePaused then continuity:SavePaused(self) end
 return true,"PAUSED"
end
function Owner:Resume(context)
 if not self.active then return false,"NO_ACTIVE_TARGET" end
 if type(context)=="table" and (context.stale or
   (context.contextToken and context.contextToken~=self.active.contextToken) or
   (context.planRevision and context.planRevision~=self.active.planRevision)) then
  self:Stop("STALE_CONTEXT");return false,"STALE_CONTEXT" end
 if self.active.needsRevalidation then return false,"STALE_CONTEXT" end
 if not self.paused then return false,"NOT_PAUSED" end
 -- Advisory stages deliberately have no end-to-end route object. They may
 -- resume their existing qualified intent; fresh live map data chooses the
 -- visible stage, not the stale waypoint captured before Pause.
 if not self.active.route and self.active.sourceStatus~="DESTINATION_ONLY" and
    self.active.category~="GATHERING" then return false,"GUIDANCE_NOT_RESUMABLE" end
 if self.active.restoredPaused or self.active.pausedZoneChanged then
    -- Both a reloaded PAUSED intent and a same-session zone transition must
    -- re-admit live origin/source when the player explicitly clicks Resume.
    -- A Gathering receipt belongs to its original zone/generation: the user
    -- must select a freshly qualified Gathering stop rather than revive it.
    if self.active.category=="GATHERING" then
       return false,"GATHERING_ROUTE_REVALIDATION_REQUIRED" end
    local source=self.resumeSource
    local ctx={explicit=true,characterKey=self.active.characterKey,
       contextToken=self.active.contextToken,planRevision=self.active.planRevision}
    if self.active.category~="MANUAL" then
       local valid,why=self:CanNavigate(self.active.category,source,ctx)
       if not valid then return false,why end
       local point,reason=resolveSource(self.active.category,source,ctx)
       if not point or point.mapID~=self.active.point.mapID or
           point.x~=self.active.point.x or point.y~=self.active.point.y then
           return false,reason or "RESTORED_SOURCE_CHANGED" end
    end
    local router=JLP:GetModule("TravelRouter")
    local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
    if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
       not integer(origin.mapID) or not finite(origin.x) or not finite(origin.y) then
       return false,"PLAYER_POSITION_UNAVAILABLE" end
    local engine=JLP:GetModule("IntegratedTravelEngine")
    if not engine or not engine.BeginGuidance then return false,"TRAVEL_ENGINE_MISSING" end
    local _,plan,why=engine:BeginGuidance(origin,self.active.point)
    self.active.route=plan
    self.active.routeReason=why or (plan and "ROUTE_AVAILABLE" or "NO_ROUTE")
    self.active.sourceStatus=plan and "AVAILABLE" or "DESTINATION_ONLY"
    if not plan and engine.StopGuidance then engine:StopGuidance() end
    self.active.restoredPaused=nil
    self.active.pausedZoneChanged=nil
 end
 self.paused=false
 local continuity=JLP:GetModule('TravelContinuity70450')
 if continuity and continuity.Save then continuity:Save(self) end
 return true,self.active.route and "ACTIVE" or "RESUMED_DESTINATION_ONLY"
end
-- A material receipt may invalidate only its own automatic destination.
-- Explicit/manual targets and the user's Pause/Stop authority are unchanged.
function Owner:InvalidateSupplySource(sourceID,reason,ownerToken)
 local a=self.active
 if not a or a.category~="CURRENT_STEP" or a.priority~=1 or
    not self.resumeSource or not (sourceID and self.resumeSource.serviceID==sourceID or
    ownerToken and self.resumeSource.supplyOwnerToken==ownerToken) then return false,"NOT_THIS_AUTOMATIC_SUPPLY" end
 local paused,stopped=self.paused,self.stopped
 self:Invalidate(reason)
 self.paused,self.stopped=paused,stopped
 return true,reason
end
-- Retire only the matching automatic entrance goal when current learning,
-- instance context or exact offering no longer supports this outdoor leg.
-- The enclosing profession task and explicit/manual targets are untouched.

function Owner:RevalidateRecipeAcquisition()
 if not self.active or self.active.category~="CURRENT_STEP"or self.active.priority~=1 or
  not self.resumeSource or (self.resumeSource.accessNPCID~=11278 and self.resumeSource.firstAidAccess~=true and self.resumeSource.secondaryAccess~=true and self.resumeSource.fishingApproach~=true and self.resumeSource.cookingKitBank~=true) then return false,"NOT_AUTOMATIC_MAGNUS_ACCESS"end
 local resolver=JLP:GetModule("SourceResolver")
 if resolver and resolver:VerifyNavigationWaypoint("CURRENT_STEP",self.resumeSource)then return true end
 return self:InvalidateSupplySource(self.resumeSource.serviceID,self.resumeSource.cookingKitBank and "COOKING_KIT_BANK_CONSUMER_OR_DELIVERY_CHANGED" or "MAGNUS_ACCESS_OR_LEARNING_OBSERVED_REPLAN")
end

function Owner:RevalidateAnnoraApproach()
 if not self.active or self.active.category~="CURRENT_STEP" or self.active.priority~=1 or
  not self.resumeSource or (self.resumeSource.serviceID~="ULDAMAN_REAR" and self.resumeSource.serviceID~="ULDAMAN_ANNORA") then return false,"NOT_AUTOMATIC_ANNORA_APPROACH" end
 local resolver=JLP:GetModule("SourceResolver")
 local ok=resolver and resolver.VerifyNavigationWaypoint and resolver:VerifyNavigationWaypoint("CURRENT_STEP",self.resumeSource)
 if ok then return true,"ANNORA_APPROACH_STILL_NEEDED" end
 return self:InvalidateSupplySource(self.resumeSource.serviceID,"ANNORA_APPROACH_REPLAN_FROM_OBSERVATION")
end
function Owner:Invalidate(reason)
 local continuity=JLP:GetModule('TravelContinuity70450')
 if continuity and continuity.Clear then continuity:Clear('INVALIDATED') end
 self.revision=self.revision+1;self.active=nil;self.resumeSource=nil;self.paused=false
 local engine=JLP:GetModule("IntegratedTravelEngine")
 if engine and engine.StopGuidance then engine:StopGuidance() end
 return true,reason or "INVALIDATED"
end
-- Revalidation requires a new actual player-origin observation matching the
-- caller's map and the retained plan/character/token identity. Empty refreshes
-- never clear STALE. This is session-local evidence, NOT reload persistence.
function Owner:Revalidate(context)
 if not self.active then return false,"NO_ACTIVE_TARGET" end
 -- Manual destinations have no source token, so only a NEW explicit user
 -- action can revalidate them. Qualified service targets still require their
 -- exact original context/plan/character receipt.
 local manual=self.active.category=="MANUAL" and context and context.explicit==true
 if type(context)~="table" or context.currentMapID==nil or
    (not manual and (type(context.contextToken)~="string" or
       context.contextToken=="" or context.contextToken~=self.active.contextToken)) or
    (self.active.planRevision~=nil and context.planRevision~=self.active.planRevision) or
    (self.active.characterKey~=nil and context.characterKey~=self.active.characterKey) then
   self.active.needsRevalidation=true
   return false,"REVALIDATION_EVIDENCE_REQUIRED"
 end
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
    not integer(origin.mapID) or context.currentMapID~=origin.mapID or
    not finite(origin.x) or not finite(origin.y) then
   self.active.needsRevalidation=true
   return false,"ORIGIN_NOT_VERIFIED"
 end
 if self.active.category=="GATHERING" then
   local service=getGeneration()
   local current=service and service.ContextIsCurrent and service:ContextIsCurrent(origin.mapID)
   local token=service and service.GetContextToken and service:GetContextToken(origin.mapID)
   if current~=true or token~=self.active.contextToken then
      self.active.needsRevalidation=true;return false,"STALE_GATHERING_CONTEXT" end
   local valid,receiptReason=gatheringReceipt(service,self.active.routeMapID,token)
   if not valid then
      self.active.needsRevalidation=true
      self.active.route=nil;self.active.routeReason=receiptReason
      return false,receiptReason
   end
 else
   local engine=JLP:GetModule("IntegratedTravelEngine")
   local guidance,route,why
   if engine and type(engine.BeginGuidance)=="function" then
     guidance,route,why=engine:BeginGuidance(origin,self.active.point,context.characterContext)
   else why="INTEGRATED_TRAVEL_UNAVAILABLE" end
   self.active.route=route;self.active.routeReason=why or (route and "ROUTE_AVAILABLE")
   if not route and engine and engine.StopGuidance then engine:StopGuidance() end
 end
 self.active.needsRevalidation=false
 self.active.nativeReturnRecovery=nil
 self.paused=false
 if not self.active.route and self.active.category~="GATHERING" then
   self.active.sourceStatus="DESTINATION_ONLY"
   return true,"DESTINATION_ONLY_NO_ROUTE"
 end
 self.active.sourceStatus="AVAILABLE"
 return true,"CURRENT"
end
-- Map transitions may become readable one or more frames after a zone event.
-- A rate-limited owner tick may therefore retry the exact same pre-qualified
-- destination once actual C_Map evidence identifies its UI map.
function Owner:AttemptLocalRouteAfterMapChange()
 if not self.active or self.paused or self.active.needsRevalidation or
    self.active.route or not self.active.point or
    (self.active.sourceStatus~="DESTINATION_ONLY" and
     not (self.active.category=="GATHERING" and self.active.sourceStatus=="PARTIAL")) then
    return false,"LOCAL_REPLAN_NOT_ELIGIBLE" end
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
    origin.mapID~=self.active.point.mapID or
    not finite(origin.x) or not finite(origin.y) then
    return false,"DESTINATION_ONLY_AWAITING_TARGET_MAP" end
 local engine=JLP:GetModule("IntegratedTravelEngine")
 if not engine or type(engine.BeginGuidance)~="function" then
    return false,"INTEGRATED_TRAVEL_UNAVAILABLE" end
 local _,plan,why=engine:BeginGuidance(origin,self.active.point)
 if not plan then
    self.active.routeReason=why or "LOCAL_ROUTE_UNAVAILABLE"
    return false,self.active.routeReason
 end
 self.active.route=plan
 self.active.routeReason="ROUTE_REPLANNED_ON_NATIVE_TARGET_MAP"
 -- Gathering's READY source remains its own qualification contract; a
 -- JuztTravel route never promotes gathering data to NPC/source authority.
 self.active.sourceStatus=self.active.category=="GATHERING" and "PARTIAL" or "AVAILABLE"
 return true,"ROUTE_REPLANNED_ON_NATIVE_TARGET_MAP"
end
-- Recover a qualified, already-active target when the player deliberately
-- walks BACK through a documented city/exterior transition. This only changes
-- the navigation *presentation*: it cannot certify reaching the trainer,
-- boarding a vehicle or progressing a profession. All other unexpected maps
-- remain STALE and require the existing full revalidation.
local function navigationCapability()
 local e=JLP:GetModule("NavigationCapabilityEvidence")
 if not e or type(e.Check)~="function" then return false,"CAPABILITY_CONTRACT_UNAVAILABLE" end
 return e:Check("POSITION")
end
function Owner:RecoverAttestedCityExit()
 local a=self.active
 if not a or a.needsRevalidation or self.paused or self.stopped or
    a.category=="GATHERING" or a.sourceStatus~="AVAILABLE" or
    not a.route or not a.point or not integer(a.point.mapID) or
    not finite(a.point.x) or not finite(a.point.y) then
   return false,"CITY_EXIT_RECOVERY_INELIGIBLE" end
 local supported,reason=navigationCapability()
 if not supported then return false,reason end
 local identity=JLP:GetModule("CharacterIdentity")
 if a.characterKey~=nil then
   local current=identity and identity.GetCurrent and identity:GetCurrent(true) or nil
   if not current or current.stableKey~=a.characterKey then
     return false,"CHARACTER_CHANGED" end
 end
 local legs=a.route.legs
 local final=type(legs)=="table" and legs[#legs] or nil
 if not final or final.mode~="WALK" or not final.to or
    final.to.mapID~=a.point.mapID then
   return false,"NOT_LOCAL_DESTINATION_WALK" end
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
    not integer(origin.mapID) or not finite(origin.x) or not finite(origin.y) or
    origin.x<0 or origin.x>1 or origin.y<0 or origin.y>1 then
   return false,"NATIVE_POSITION_UNAVAILABLE" end
 local topology=JLP._integratedTravel and JLP._integratedTravel.MapTransitions
 if not topology or type(topology.IsAttestedCityExit)~="function" or
    not topology:IsAttestedCityExit(a.point.mapID,origin.mapID) then
   return false,"CITY_EXIT_NOT_ATTESTED" end
 local engine=JLP:GetModule("IntegratedTravelEngine")
 if not engine or type(engine.GetStagedGuidance)~="function" or
    type(engine.StopGuidance)~="function" then
   return false,"STAGED_ROUTE_UNAVAILABLE" end
 -- The CURRENT transport graph must still permit re-entry into the exact
 -- destination city. Merely being on an attested exterior map is not enough.
 local guide=engine:GetStagedGuidance(a.point)
 if not guide or guide.phase~="ENTER_DESTINATION_CITY" or
    guide.nextMapID~=a.point.mapID then
   return false,"CURRENT_CITY_REENTRY_NOT_QUALIFIED" end
 engine:StopGuidance()
 self.revision=self.revision+1
 a.route=nil
 a.routeReason="ATTESTED_CITY_EXIT_AWAITING_REENTRY"
 a.sourceStatus="DESTINATION_ONLY"
 a.generation=self.revision
 a.needsRevalidation=false
 return true,"ATTESTED_CITY_EXIT_REPLANNED"
end
-- Universal *native-return* recovery for a previously qualified local WALK
-- destination. A newly observed but unattested exterior map is NEVER treated
-- as a valid route. While outside, the owner remains STALE; only a confirmed
-- return to the exact original UIMapID with unchanged character/source intent
-- may create another local navigation leg. Applies to every target map; no
-- city names or coordinate assumptions are embedded in this recovery path.
function Owner:ArmNativeReturnRecovery()
 local a=self.active
 if not a or a.needsRevalidation or self.paused or self.stopped or
    a.category=="GATHERING" or a.sourceStatus~="AVAILABLE" or
    not a.point or not a.route or not integer(a.point.mapID) or
    not finite(a.point.x) or not finite(a.point.y) then
   return false,"RETURN_RECOVERY_INELIGIBLE" end
 local legs=a.route.legs
 local last=type(legs)=="table" and legs[#legs] or nil
 if not last or last.mode~="WALK" or not last.to or
    last.to.mapID~=a.point.mapID then
   return false,"RETURN_RECOVERY_NOT_LOCAL_WALK" end
 local supported,reason=navigationCapability()
 if not supported then return false,reason end
 local character=JLP:GetModule("CharacterIdentity")
 local who=character and character.GetCurrent and character:GetCurrent(true) or nil
 if not who or type(who.stableKey)~="string" or who.stableKey=="" or
    (a.characterKey~=nil and a.characterKey~=who.stableKey) then
   return false,"CHARACTER_NOT_VERIFIED" end
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
    not integer(origin.mapID) or origin.mapID==a.point.mapID or
    not finite(origin.x) or origin.x<0 or origin.x>1 or
    not finite(origin.y) or origin.y<0 or origin.y>1 then
   return false,"NATIVE_OFF_MAP_EVIDENCE_REQUIRED" end
 a.nativeReturnRecovery={characterKey=who.stableKey,mapID=a.point.mapID,
    x=a.point.x,y=a.point.y,generation=a.generation,
    planRevision=a.planRevision,contextToken=a.contextToken}
 return true,"RETURN_RECOVERY_ARMED"
end
function Owner:RecoverNativeReturn()
 local a=self.active
 local pending=a and a.nativeReturnRecovery
 if not a or not pending or not a.needsRevalidation or
    a.routeReason~="UNEXPECTED_ZONE_REVALIDATION_REQUIRED" or
    self.paused or self.stopped or a.category=="GATHERING" or a.route or
    not a.point or a.generation~=pending.generation or
    a.point.mapID~=pending.mapID or a.point.x~=pending.x or a.point.y~=pending.y or
    a.planRevision~=pending.planRevision or a.contextToken~=pending.contextToken or
    (a.characterKey~=nil and a.characterKey~=pending.characterKey) then
   return false,"RETURN_RECOVERY_NOT_ELIGIBLE" end
 local supported,reason=navigationCapability()
 if not supported then return false,reason end
 local character=JLP:GetModule("CharacterIdentity")
 local who=character and character.GetCurrent and character:GetCurrent(true) or nil
 if not who or who.stableKey~=pending.characterKey then
   return false,"CHARACTER_CHANGED" end
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
    origin.mapID~=pending.mapID or not finite(origin.x) or
    origin.x<0 or origin.x>1 or not finite(origin.y) or
    origin.y<0 or origin.y>1 then
   return false,"RETURN_TO_NATIVE_TARGET_MAP_REQUIRED" end
 local engine=JLP:GetModule("IntegratedTravelEngine")
 if not engine or type(engine.BeginGuidance)~="function" then
   return false,"TRAVEL_ENGINE_MISSING" end
 -- Attempt real local routing first; leave stale evidence unchanged on failure.
 local _,plan,reason=engine:BeginGuidance(origin,a.point)
 if not plan or type(plan.legs)~="table" or #plan.legs==0 or
    plan.legs[#plan.legs].mode~="WALK" or
    not plan.legs[#plan.legs].to or
    plan.legs[#plan.legs].to.mapID~=a.point.mapID then
   if engine.StopGuidance then engine:StopGuidance() end
   return false,reason or "RETURN_LOCAL_ROUTE_NOT_VERIFIED" end
 self.revision=self.revision+1
 a.route=plan;a.routeReason="RECOVERED_ON_NATIVE_TARGET_MAP"
 a.generation=self.revision;a.needsRevalidation=false
 a.sourceStatus="AVAILABLE";a.nativeReturnRecovery=nil
 return true,"RECOVERED_ON_NATIVE_TARGET_MAP"
end
function Owner:ObserveEvent(event)
 self:RevalidateRecipeAcquisition()
 self:RevalidateAnnoraApproach()
 if self.active and self.active.characterKey then
   local e=JLP:GetModule("NavigationCapabilityEvidence")
   local supported,_,proof
   if e and e.Check then supported,_,proof=e:Check("CHARACTER") end
   if supported~=true or proof.characterKey~=self.active.characterKey then
     self:Invalidate("CHARACTER_CHANGED")
     return false,"CHARACTER_CHANGED"
   end
 end
 if event=="PLAYER_LOGOUT" then
    local continuity=JLP:GetModule("TravelContinuity70450")
    if self.paused then
       if continuity and continuity.SavePaused then continuity:SavePaused(self) end
    else
       if continuity and continuity.Save then continuity:Save(self) end
    end
    return true,"INTENT_CHECKPOINT_ONLY"
 end
 if event=="PLAYER_ENTERING_WORLD" or event=="ZONE_CHANGED_NEW_AREA" or
    event=="ZONE_CHANGED" or event=="ZONE_CHANGED_INDOORS" then
    if not self.active then
       return true,"NO_TRAVEL_GUIDANCE_TO_ADVANCE" end
    local engine=JLP:GetModule("IntegratedTravelEngine")
    if self.paused then
       -- Skip automatic route progress while paused, but remember that the
       -- pre-pause legs are no longer safe to reactivate on Resume.
       self.active.pausedZoneChanged=true
       return false,"GUIDANCE_NOT_ACTIVE"
    end
    if self.active.needsRevalidation then
       if self.active.routeReason=="UNEXPECTED_ZONE_REVALIDATION_REQUIRED" then
          return self:RecoverNativeReturn()
       end
       return false,"GUIDANCE_NOT_ACTIVE" end
    if not self.active.route then
       return self:AttemptLocalRouteAfterMapChange()
    end
    if not self.active.route then return false,"GUIDANCE_NOT_ACTIVE" end
    local state,reason
    if engine and engine.ObserveLive then state,reason=engine:ObserveLive(event) end
    if reason=="UNEXPECTED_MAP_DURING_TRANSFER" or
       reason=="WALK_MAP_MISMATCH" then
       -- A native-observed reverse city boundary is a navigation re-plan,
       -- not stale source evidence. Recover only this documented topology.
       if reason=="WALK_MAP_MISMATCH" then
         local recovered,recoveryReason=self:RecoverAttestedCityExit()
         if recovered then return true,recoveryReason end
       end
       -- An unknown off-map WALK must remain stale, but a future native
       -- return to the same previously qualified target can safely replan.
       -- An unexpected transport-map mismatch is never eligible.
       if reason=="WALK_MAP_MISMATCH" then self:ArmNativeReturnRecovery() end
       self.revision=self.revision+1
       self.active.needsRevalidation=true
       self.active.routeReason="UNEXPECTED_ZONE_REVALIDATION_REQUIRED"
       self.active.route=nil
       if engine and engine.StopGuidance then engine:StopGuidance() end
       return false,"UNEXPECTED_ZONE_REVALIDATION_REQUIRED"
    end
    return state~=nil,reason or "NO_NEW_POSITION_EVIDENCE"
 end
 return true
end
function Owner:GetGatheringGuidance(mapID)
 local service=getGeneration()
 if not service or not integer(mapID) then return nil,"NO_ACTIVE_ROUTE" end
 local valid,why=service:ContextIsCurrent(mapID)
 if valid~=true then return nil,why or "STALE_GATHERING_CONTEXT" end
 local token=service:GetContextToken(mapID)
 local status=service:GetStatusForMap(mapID)
 local routes,why2=service:GetRoutes(mapID)
 if status~="READY" or type(routes)~="table" then return nil,why2 or status end
 local state=JLP:GetModule("GatheringSharedMapState")
 local snapshot=state and state.GetSnapshot and state:GetSnapshot() or nil
 local count=0;for _,route in pairs(routes) do
    if type(route)=="table" and type(route.points)=="table" then count=count+1 end
 end
 if count==0 then return nil,"NO_ELIGIBLE_ROUTE" end
 local overlayMatches=gatheringReceipt(service,mapID,token)
 return {category="GATHERING",mode=snapshot and snapshot.mode,contextToken=token,
  status=status,routeCount=count,navigationOnly=true,source="GATHERING_ROUTE_SERVICE",
  overlayStatus=overlayMatches and "RECEIPT_OBSERVED" or "OVERLAY_NOT_VERIFIED",
  routePresentationReady=overlayMatches, routeNavigationReady=true,
  nativeDispatchAllowed=false}
end
-- Manual handoff from an existing positive GatheringRouteService READY receipt.
-- This is a transient reference marker, not a new gathering route or spawn claim.
function Owner:SelectGatheringStop(mapID,profession,index,context)
 if not integer(mapID) or (profession~="HERBALISM" and profession~="MINING") or
    not integer(index) then return false,"INVALID_GATHERING_SELECTION" end
 local service=getGeneration()
 if not service then return false,"GATHERING_ROUTE_UNAVAILABLE" end
 local current,reason=service:ContextIsCurrent(mapID)
 if current~=true then return false,reason or "STALE_GATHERING_CONTEXT" end
 local token=service:GetContextToken(mapID)
 local status=service:GetStatusForMap(mapID)
 if type(token)~="string" or token=="" or status~="READY" then
   return false,"NO_READY_ROUTE_RECEIPT" end
 local routes=service:GetRoutes(mapID)
 local route=routes and routes[profession]
 local stop=route and type(route.points)=="table" and route.points[index] or nil
 if not stop then return false,"STOP_UNAVAILABLE" end
 local p=point({mapID=mapID,x=stop.x,y=stop.y,mapDomain="UI_MAP_ID"})
 if not p then return false,"UNVERIFIED_ROUTE_COORDINATES" end
 local manual=self.active and self.active.priority>=2 and self.active.category~="GATHERING"
 if manual and not (type(context)=="table" and context.explicit==true) then
    return false,"EXPLICIT_DESTINATION_HAS_PRIORITY" end
 -- READY route + live context token + current generation qualify this
 -- selected waypoint. Map overlay painting is an independent UI/QA signal,
 -- never a reason to discard an otherwise usable generated route.
 local presentationObserved,receiptReason=gatheringReceipt(service,mapID,token)
 -- Every navigable target, including Gathering, is handed to the same
 -- JuztTravel engine. A complete plan is used when available; otherwise
 -- JuztTravel itself supplies the next map/transport advisory stage.
 local engine=JLP:GetModule("IntegratedTravelEngine")
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 local plan,routeReason
 if engine and engine.BeginGuidance and origin and integer(origin.mapID) and
    finite(origin.x) and finite(origin.y) and
    origin.positionEvidence=="C_Map.GetPlayerMapPosition" then
    local _,candidate,why=engine:BeginGuidance(origin,p)
    plan=candidate;routeReason=why or (candidate and "ROUTE_AVAILABLE")
 end
 if not plan and engine and engine.StopGuidance then engine:StopGuidance() end
 self.revision=self.revision+1
 p.label=(profession=="HERBALISM" and "Herbalism" or "Mining").." - stop "..tostring(index)
 p.evidence="READY_GATHERING_ROUTE_REFERENCE_ONLY"
 -- SelectGatheringStop is called after a deliberate user selection.
 -- It must outrank background Current Step updates, but a subsequent
 -- explicit destination selection remains allowed.
 self.active={category="GATHERING",priority=2,point=p,generation=self.revision,
    owner="GatheringRouteService",contextToken=token,routeMapID=mapID,
    sourceStatus="PARTIAL",navigationOnly=true,route=plan,
    routeReason=routeReason or "AWAITING_JUZTTRAVEL_MAP_STAGE",
    presentationStatus=presentationObserved and "RECEIPT_OBSERVED" or receiptReason}
 self.paused=false;self.stopped=false;self.resumeSource=nil
 local continuity=JLP:GetModule('TravelContinuity70450')
 if continuity and continuity.Clear then continuity:Clear('GATHERING_SELECTION_SUPERSEDES_TRAVEL') end
 return true,plan and "JUZTTRAVEL_ROUTE_AVAILABLE" or "JUZTTRAVEL_STAGED_GUIDANCE"
end
function Owner:GetSnapshot()
 local prerequisite=self.active and workflowOwnershipReason(self.active.category,self.resumeSource)
 if prerequisite then return {contract=self.contract,status=prerequisite,
  category=self.active.category,generation=self.active.generation,navigationOnly=true,
  ownershipBlocked=true,nativeDispatchAllowed=false,paused=self.paused}end
 self:RevalidateRecipeAcquisition()
 -- Refresh Annora's typed bearing at presentation time too: a floor/art change
 -- must not leave an arrow visible until the next Core update. Manual goals
 -- and other explicit destinations are outside this scoped contract.
 if self.active and self.resumeSource and
  (self.resumeSource.serviceID=="ULDAMAN_REAR" or self.resumeSource.serviceID=="ULDAMAN_ANNORA") then
  if self.active.priority==1 then self:RevalidateAnnoraApproach()
  else
   local resolver=JLP:GetModule("SourceResolver")
   if not resolver or not resolver:VerifyNavigationWaypoint("CURRENT_STEP",self.resumeSource) then
    self.active.needsRevalidation=true;self.active.route=nil;self.active.routeReason="ANNORA_SOURCE_REVALIDATION_REQUIRED"
   end
  end
 end
 if self.active and self.active.category=="GATHERING" then
    local service=getGeneration()
    local current=service and service.ContextIsCurrent and
        service:ContextIsCurrent(self.active.routeMapID)
    local token=service and service.GetContextToken and
        service:GetContextToken(self.active.routeMapID)
    local status=service and service.GetStatusForMap and
        service:GetStatusForMap(self.active.routeMapID)
    if current~=true or token~=self.active.contextToken or status~="READY" then
        self.active.needsRevalidation=true
        self.active.route=nil
        self.active.routeReason="STALE_GATHERING_CONTEXT"
    else
        -- Only the route context may invalidate this live waypoint.
        -- Rendering may be delayed/hidden while navigation remains usable.
        local observed,why=gatheringReceipt(service,self.active.routeMapID,token)
        self.active.presentationStatus=observed and "RECEIPT_OBSERVED" or why
    end
 end
 if not self.active then return {contract=self.contract,status=self.stopped and "STOPPED" or "UNKNOWN",
   navigationOnly=true,nativeDispatchAllowed=false,generation=self.revision} end
 local out=copy(self.active)
 out.point=copy(self.active.point)
 out.contract=self.contract;out.status=(self.active.needsRevalidation and "STALE") or
   (self.paused and "PAUSED") or
   (self.active.route and "AVAILABLE") or "DESTINATION_ONLY"
 out.nativeDispatchAllowed=false;out.navigationOnly=true
 if self.active.route and not self.paused and not self.active.needsRevalidation then
  out.route={status=self.active.route.status,legs=#(self.active.route.legs or {}),
    generation=self.active.route.generation,etaSeconds=nil}
 end
 return out
end
JLP:RegisterModule("IntegratedDestinationOwner",Owner)
