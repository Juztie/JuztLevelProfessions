local _,JLP=...
-- M13: one admission and display boundary for navigation consumers. The
-- IntegratedDestinationOwner alone owns the active destination. No SavedVariables,
-- private API, protected craft, automatic waypoint replacement or route completion.
local Service={contract="jlp-common-navigation-v1",nativeDispatchAllowed=false}
local function sourceCategory(source)
 local actions=JLP:GetModule("IntegratedNavigationActions")
 return actions and actions.CategoryForSource and
    actions:CategoryForSource(source,"RECIPE_SOURCE") or "RECIPE_SOURCE"
end
local function clone(context)
 local out={}
 if type(context)=="table" then for k,v in pairs(context) do out[k]=v end end
 return out
end
local function snapshot()
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 return owner and owner.GetSnapshot and owner:GetSnapshot() or nil
end
function Service:GetSnapshot()
 return snapshot()
end
function Service:Inspect()
 local current=snapshot()
 local nav=JLP:GetModule("Navigation")
 local marker=nav and nav.GetActiveWaypoint and nav:GetActiveWaypoint() or nil
 local ownerPoint=current and current.point
 local markerMatch=ownerPoint and marker and nav and nav.TargetMatches and
     nav:TargetMatches(ownerPoint,marker)==true
 local status=(not current or not ownerPoint) and "NO_DESTINATION" or
     (current.status=="STALE" and "STALE_DESTINATION" or
       markerMatch and "MATCHED_NATIVE_WAYPOINT" or
       marker and "OTHER_USER_WAYPOINT" or "NO_NATIVE_WAYPOINT_OBSERVED")
 return {contract=self.contract,status=current and current.status or "UNAVAILABLE",
    waypointConsistency=status,
    activeCategory=current and current.category,point=current and current.point,
    generation=current and current.generation,navigationOnly=true,
    nativeDispatchAllowed=false,persisted=false}
end
function Service:CanNavigate(category,source,context)
 -- Read-only preflight used by automatic Current Step refresh. A direct
 -- Request() still requires an explicit user interaction.
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not owner or type(owner.CanNavigate)~="function" then
   return false,"DESTINATION_OWNER_UNAVAILABLE" end
 if type(context)~="table" then return false,"INVALID_CONTEXT" end
 return owner:CanNavigate(category,source,context)
end
function Service:CanRequest(category,source,context)
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not owner or type(owner.CanNavigate)~="function" then
   return false,"DESTINATION_OWNER_UNAVAILABLE" end
 if type(context)~="table" then return false,"INVALID_CONTEXT" end
 if context.explicit~=true and category~="CURRENT_STEP" then
   return false,"EXPLICIT_USER_CLICK_REQUIRED" end
 -- Automatic Current Step must use SyncCurrentStep instead, not a public
 -- request that can replace a deliberate stop.
 if category=="CURRENT_STEP" and context.explicit~=true then
   return false,"USE_CURRENT_STEP_SYNC" end
 return owner:CanNavigate(category,source,context)
end
function Service:Request(category,source,context)
 local ok,reason=self:CanRequest(category,source,context)
 if not ok then return false,reason end
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 local current=owner:GetSnapshot()
 local nav=source and (source.nav or source)
 if current and current.point and type(nav)=="table" and
    current.status~="STALE" and current.status~="STOPPED" and
    current.category==category and current.point.mapID==nav.mapID and
    current.point.x==nav.x and current.point.y==nav.y and
    current.planRevision==context.planRevision and
    current.contextToken==context.contextToken and
    current.characterKey==context.characterKey then
     return true,"DESTINATION_UNCHANGED" end
 return owner:NavigateTo(category,source,context)
end
function Service:ObservePlanContext(context)
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if owner and owner.RevalidateAnnoraApproach then owner:RevalidateAnnoraApproach() end
 if owner and owner.RevalidateRecipeAcquisition then owner:RevalidateRecipeAcquisition() end
 if not owner or type(owner.ObservePlanContext)~="function" then
   return false,"DESTINATION_OWNER_UNAVAILABLE" end
 return owner:ObservePlanContext(context)
end
function Service:SyncCurrentStep(source,context)
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not owner or type(owner.SyncCurrentStep)~="function" then
   return false,"DESTINATION_OWNER_UNAVAILABLE" end
 return owner:SyncCurrentStep(source,context)
end
function Service:SelectGatheringStop(mapID,profession,index)
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not owner or type(owner.SelectGatheringStop)~="function" then
   return false,"DESTINATION_OWNER_UNAVAILABLE" end
 return owner:SelectGatheringStop(mapID,profession,index)
end
function Service:Stop(reason)
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 return owner and owner:Stop(reason or "USER_STOP") or false
end
function Service:Pause()
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not owner then return false,"DESTINATION_OWNER_UNAVAILABLE" end
 return owner:Pause()
end
function Service:Resume(context)
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not owner then return false,"DESTINATION_OWNER_UNAVAILABLE" end
 return owner:Resume(context)
end
-- The only side-effecting map/waypoint entrypoint. First validate the typed,
-- source-bound identity, THEN perform any map mutation. Display receipts are
-- distinct from owner guidance, transport route and native visual verification.
function Service:ShowSource(source,options)
 options=options or {}
 if type(options)~="table" then return false,"INVALID_OPTIONS" end
 local category=options.sourceCategory or sourceCategory(source)
 local context=clone(options.context)
 context.explicit=true
 context.owner=context.owner or "JLP_SHOW_SOURCE"
 local accepted,reason=self:CanRequest(category,source,context)
 if not accepted then return false,reason end
 local nav=JLP:GetModule("Navigation")
 if not nav or type(nav.GetTarget)~="function" or
   type(nav.GetActiveWaypoint)~="function" or
   type(nav._OpenMap)~="function" then return false,"MAP_ADAPTER_UNAVAILABLE" end
 local target=nav:GetTarget(source)
 if not target then return false,"INVALID_MAP_COORDINATES" end
 local current=snapshot()
 if current and current.category=="CURRENT_STEP" and category=="CURRENT_STEP" and
    current.status=="STALE" then return false,"STALE_DESTINATION_CONTEXT" end
 local capabilities=nav.GetCapabilities and nav:GetCapabilities() or {}
 if capabilities.canWaypoint==true and capabilities.canReadWaypoint~=true and
    options.replaceExisting~=true then
    local opened=nav:_OpenMap(target)
    if not opened then return false,"WAYPOINT_UNOBSERVABLE_MAP_UNAVAILABLE",target end
    return true,"MAP_ONLY_WAYPOINT_UNOBSERVABLE",target
 end
 local previous=nav:GetActiveWaypoint()
 local matching=previous and nav:TargetMatches(previous,target)==true or false
 local different=previous~=nil and not matching
 if different and options.replaceExisting~=true then
   -- Preserve BOTH the native user's waypoint and the selected owner target.
   -- Display-only map navigation must not silently supersede either.
   local opened=nav:_OpenMap(target)
   if not opened then return false,"USER_WAYPOINT_PRESERVED_MAP_UNAVAILABLE",target end
   return true,"MAP_ONLY_USER_WAYPOINT_PRESERVED",target
 end
 -- Owner selection can still fail after preview if a producer/plan changed.
 -- No waypoint has been modified at this point.
 local selected,why=self:Request(category,source,context)
 if not selected then return false,why end
 local set=false
 if not matching and type(nav.SetWaypointPoint)=="function" then
    set=nav:SetWaypointPoint(target)==true end
 local opened=nav:_OpenMap(target)==true
 nav.lastTarget=target
 nav.lastWaypointSet=set or matching
 nav.lastMapOpened=opened
 local receipt={routeBound=options.routeBound==true,
   waypointSet=set,mapOpened=opened,activeMatching=matching==true,
   preservedUserWaypoint=false,replacedExisting=different and set or false,
   previousWaypoint=different and previous or nil,travelStatus=options.travelStatus,
   destinationGeneration=snapshot() and snapshot().generation or nil,
   qualification="SOURCE_BOUND",nativeVisualVerified=false}
 local marker=JLP:GetModule("RouteMarkerLifecycle")
 if marker and type(marker.RecordNavigation)=="function" then
   marker:RecordNavigation(source,target,receipt) end
 if JLP.EventBus and type(JLP.EventBus.Emit)=="function" and
    type(nav.GetMarkerStatus)=="function" then
   JLP.EventBus:Emit("NAVIGATION_MARKER_UPDATED",nav:GetMarkerStatus(source),receipt)
 end
 if matching then return true,"MATCHING_WAYPOINT_ACTIVE",target end
 if set then return true,"WAYPOINT_SUBMITTED",target end
 if opened then return true,"DESTINATION_SELECTED_MAP_OPENED",target end
 -- A destination-only HUD target is a valid internal outcome, but no claim
 -- is made that Blizzard accepted the waypoint or rendered the map.
 return true,"DESTINATION_SELECTED_MAP_UNAVAILABLE",target
end
-- Read-only JSON/Lua-table-shaped future handoff to independent JuztTravel /
-- JuztTom. No code is called across addon boundaries; callers must revalidate.
function Service:ExportHandoff()
 local s=snapshot()
 if not s or not s.point or (s.status~="AVAILABLE" and s.status~="DESTINATION_ONLY") or
    s.sourceStatus=="PARTIAL" then return nil,"NO_CURRENT_QUALIFIED_DESTINATION" end
 local p=s.point
 return {contract="jlp-navigation-handoff-v1",mapDomain="UI_MAP_ID",
   mapID=p.mapID,x=p.x,y=p.y,category=s.category,
   generation=s.generation,characterKey=s.characterKey,
   contextToken=s.contextToken,planRevision=s.planRevision,
   status=s.status,readOnly=true,persisted=false,navigationOnly=true,
   nativeDispatchAllowed=false,routeVerified=false,
   requiresIndependentAcceptance=true},"READ_ONLY_HANDOFF"
end
JLP:RegisterModule("UnifiedDestinationNavigation",Service)
