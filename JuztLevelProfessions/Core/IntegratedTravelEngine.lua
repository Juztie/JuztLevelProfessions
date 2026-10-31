local _, JLP = ...
-- The original Travel portable engine is rebound to JLP._integratedTravel.
-- This adapter is the only production access to its graph; research edges
-- never graduate merely because the standalone source marked them verified.
local T=JLP._integratedTravel
local Engine={contract="jlp-integrated-travel-v1",nativeDispatchAllowed=false}
local privateNetwork
local function clone(node)
    local out={};for k,v in pairs(node) do out[k]=v end;return out
end
local function safeGraph(base)
    local graph=T.Network.New()
    if not base then return graph end
    local nodes,edges={},{}
    for id,node in pairs(base.nodes or {}) do nodes[id]=clone(node) end
    for _,edge in ipairs(base.edges or {}) do
        -- Keep every structurally registered edge in the canonical/research graph.
        -- Runtime class, faction, level and unlock checks remain in Network:CanTraverse.
        edges[#edges+1]=clone(edge)
    end
    graph.nodes=nodes;graph.edges=edges;graph.generation=base.generation
    for _,edge in ipairs(edges) do graph.edgeIds[edge.id]=true end
    return graph
end
function Engine:Initialize()
    if self.initialized then return true end
    privateNetwork=T.Network.New()
    local ok,why=privateNetwork:RegisterDataset(T.HordeCorridor)
    self.datasetStatus=ok and "USER_REFERENCE_RESEARCH_ONLY" or "INVALID_DATASET"
    self.datasetError=why
    if not ok then privateNetwork=T.Network.New() end
    local provider=JLP:GetModule("OwnerAuthorizedNavigation")
    if provider and provider.GetTransportDataset then
       local accepted,reason=self:RegisterVerifiedDataset(provider:GetTransportDataset())
       self.ownerDatasetStatus=accepted and "OWNER_AUTHORIZED_REGISTERED" or reason
       self.ownerDatasetAccepted=accepted==true
    else
       self.ownerDatasetStatus="OWNER_DATASET_MODULE_MISSING"
       self.ownerDatasetAccepted=false
    end
    self.initialized=true
    return ok,why
end
function Engine:GetGraphStatus()
    self:Initialize()
    local eligible=0;for _,e in ipairs(privateNetwork.edges) do
        -- Eligible here means registered; actual traversal remains character-dependent.
        eligible=eligible+1
    end
    return {contract=self.contract,generation=privateNetwork.generation,
      eligibleTransportEdges=eligible,rawEdges=#privateNetwork.edges,
      status=self.ownerDatasetStatus or self.datasetStatus,source="OWNER_ATTESTED_2026_10_17_PLUS_RESEARCH",
      ownerDataAuthorized=self.ownerDatasetAccepted==true,productionAuthorized=false,
      registeredOwnerEdges=self.ownerDatasetAccepted and eligible or 0,
      nativeClientAcceptance="NOT_RUN",
      flightUnlockObservation=(JLP:GetModule("FlightUnlockObservation") and
         JLP:GetModule("FlightUnlockObservation"):GetStatus().status) or "UNKNOWN",
      flightObservedEdges=(JLP:GetModule("FlightUnlockObservation") and
         JLP:GetModule("FlightUnlockObservation"):GetStatus().verifiedFlightEdges) or 0}
end
function Engine:RegisterVerifiedDataset(dataset)
    -- The admission scope is exactly the bundled, immutable owner CSV dataset;
    -- owner-status strings or SHA claims supplied by callers confer no authority.
    local provider=JLP:GetModule("OwnerAuthorizedNavigation")
    if not provider or not provider.MatchesCanonicalTransport or
       provider:MatchesCanonicalTransport(dataset)~=true then
       return false,"NON_CANONICAL_OWNER_TRANSPORT_DATASET" end
    if not privateNetwork then return false,"NETWORK_NOT_INITIALIZED" end
    if self.ownerDatasetAccepted then return true,"OWNER_DATASET_ALREADY_REGISTERED" end
    local ok,why=privateNetwork:RegisterDataset(dataset)
    if ok then self.ownerDatasetAccepted=true end
    return ok,why
end
local function navigationCapability()
 local e=JLP:GetModule("NavigationCapabilityEvidence")
 if not e or type(e.Check)~="function" then return false,"CAPABILITY_CONTRACT_UNAVAILABLE" end
 return e:Check("POSITION")
end
function Engine:Calculate(origin,destination,context,opts)
    local allowed,reason,proof=navigationCapability()
    if not allowed then return nil,reason end
    if type(origin)~="table" or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
       origin.mapID~=proof.mapID then return nil,"NATIVE_ORIGIN_REQUIRED" end
    self:Initialize()
    local a,why=T.Contract.point(origin);if not a then return nil,why end
    -- Never let a caller choose its own start coordinate; the map and
    -- position are taken from the freshly observed native C_Map result.
    a={mapID=proof.mapID,x=proof.x,y=proof.y,mapDomain="UI_MAP_ID"}
    local b,why2=T.Contract.point(destination);if not b then return nil,why2 end
    if a.mapID~=b.mapID and self:GetGraphStatus().eligibleTransportEdges==0 then
        return nil,"NO_QUALIFIED_TRANSPORT_EDGES"
    end
    -- Never trust arbitrary UI-supplied taxi unlock claims.
    -- Taxi unlocks are a route-planning hint. Unknown does not hide registered
    -- connections; confirmed locked flights remain unavailable in game.
    local restricted={}
    -- Never accept caller-provided faction/level/unlocks as eligibility evidence.
    -- Optional blocked edges may only remove choices from the current graph.
    if type(context)=="table" and type(context.blocked)=="table" then
        restricted.blocked={}
        for k,v in pairs(context.blocked) do
            if type(k)=="string" and v==true then restricted.blocked[k]=true end
        end
    end
    local observer=JLP:GetModule("FlightUnlockObservation")
    local verified=observer and observer.GetVerifiedUnlocks and
       observer:GetVerifiedUnlocks() or nil
    restricted.unlocked=verified -- never a caller-provided field
    if type(UnitFactionGroup)=="function" then
      local ok,faction=pcall(UnitFactionGroup,"player")
      if ok and (faction=="Horde" or faction=="Alliance") then
        restricted.faction=faction:upper()
      else restricted.faction=nil end
    else restricted.faction=nil end
    if type(UnitLevel)=="function" then
      local ok,level=pcall(UnitLevel,"player")
      restricted.level=ok and type(level)=="number" and level or nil
    else restricted.level=nil end
    -- The caller cannot self-attest a class; use the client's class token only.
    if type(UnitClass)=="function" then
      local ok,_,token=pcall(UnitClass,"player")
      if ok and type(token)=="string" then restricted.classToken=token end
    end
    local plan,reason,detail=T.Planner:Plan(safeGraph(privateNetwork),a,b,restricted,opts)
    if not plan then return nil,reason,detail end
    plan.navigationOnly=true;plan.nativeDispatchAllowed=false
    return plan
end
function Engine:PreviewResearchRoute(origin,destination,context)
    self:Initialize()
    local plan,reason=T.Planner:Plan(privateNetwork,origin,destination,context or {})
    if not plan then return nil,reason end
    plan.previewOnly=true;plan.productionAuthorized=false
    plan.status="RESEARCH_PREVIEW_NOT_NAVIGABLE"
    return plan
end
-- Journey is a portable read-only state machine; no automatic boarding or
-- craft/arrival task completion. Started only after the destination owner has
-- admitted the target and Calculate has excluded unverified transport edges.
local activeJourney
local taxiLegReceipt
function Engine:BeginGuidance(origin,destination,context)
 if destination and destination.directBearing==true then
  self:StopGuidance()
  return nil,nil,"DIRECT_BEARING_NOT_PHYSICAL_ROUTE"
 end
 local plan,why=self:Calculate(origin,destination,context)
 if not plan then return nil,nil,why end
 local nextJourney=T.Journey.New()
 local ok,reason=nextJourney:Start(plan)
 if not ok then return nil,nil,reason end
 activeJourney=nextJourney;taxiLegReceipt=nil
 return nextJourney:Guidance(),plan
end
function Engine:StopGuidance()
 if activeJourney then activeJourney:Stop() end
 activeJourney=nil;taxiLegReceipt=nil
 return true
end
-- A caller-provided map point must never advance a production journey.
-- Only ObserveLive may consume native player/instance evidence.
function Engine:ObservePosition(position)
 return nil,"NATIVE_CLIENT_OBSERVATION_REQUIRED"
end
function Engine:ObserveVerifiedPosition(position,worldDistanceYards,arrivalRadiusYards)
 -- Compatibility surface, now independent of caller-provided distance.
 -- Live observation performs all native origin, instance and radius checks.
 return self:ObserveLive("VERIFIED_POSITION_REQUEST")
end
local function nativeOrigin()
 local router=JLP:GetModule("TravelRouter")
 local p=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 local C=T.Contract
 if not p or p.positionEvidence~="C_Map.GetPlayerMapPosition" then
    return nil,"NATIVE_POSITION_UNAVAILABLE" end
 local point=C.point(p)
 if not point then return nil,"NATIVE_POSITION_INVALID" end
 return point
end
local function onTaxi()
 if type(UnitOnTaxi)=="function" then
  local ok,result=pcall(UnitOnTaxi,"player")
  if ok and (result==true or result==1) then return true end
 end
 return false
end
function Engine:ObserveLive(event)
 if not activeJourney then return nil,"NO_ACTIVE_JOURNEY" end
 local supported,why=navigationCapability()
 if not supported then return nil,why end
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 local ownerState=owner and owner.GetSnapshot and owner:GetSnapshot() or nil
 if not ownerState or ownerState.status~="AVAILABLE" or not ownerState.route or
    not ownerState.point or activeJourney.plan==nil then
   return nil,"ACTIVE_QUALIFIED_ROUTE_REQUIRED" end
 if not T.Contract.point(ownerState.point) or
    activeJourney.plan.destination.mapID~=ownerState.point.mapID or
    math.abs(activeJourney.plan.destination.x-ownerState.point.x)>0.0000001 or
    math.abs(activeJourney.plan.destination.y-ownerState.point.y)>0.0000001 then
    return nil,"DESTINATION_CHANGED" end
 local position,why=nativeOrigin()
 if not position then return nil,why end
 local leg=activeJourney:CurrentLeg()
 activeJourney.lastLocation=position
 if not leg then return activeJourney:Guidance(),"ALREADY_ARRIVED" end
 if leg.mode=="WALK" then
    if position.mapID~=leg.to.mapID then
       activeJourney.lastError="PLAYER_OFF_EXPECTED_MAP"
       return activeJourney:Guidance(),"WALK_MAP_MISMATCH" end
    local hud=JLP:GetModule("IntegratedNavigationHUD")
    local geo=hud and hud.GetGeometry and hud:GetGeometry(leg.to) or nil
    local jt=JLP:GetModule("IntegratedJuztTom")
    local radius=jt and jt.profile and tonumber(jt.profile.arrival) or 5
    if radius<3 or radius>35 or radius~=radius then radius=5 end
    if type(geo)=="table" and geo.instanceVerified==true and
       type(geo.distanceYards)=="number" and geo.distanceYards==geo.distanceYards and
       geo.distanceYards>=0 and geo.distanceYards<=radius then
       activeJourney:Advance();activeJourney.lastError=nil
       return activeJourney:Guidance(),"WORLD_VERIFIED_WALK_ARRIVAL"
    end
    return activeJourney:Guidance(),"WALK_ARRIVAL_NOT_WORLD_VERIFIED"
 end
 if leg.from.mapID~=leg.to.mapID then
    if position.mapID==leg.to.mapID then
       -- Crossing over a zone while still on a flight path is not landing.
       if leg.mode=="FLIGHT" and onTaxi() then
          activeJourney.lastError=nil
          return activeJourney:Guidance(),"FLIGHT_IN_PROGRESS"
       end
       activeJourney:Advance();activeJourney.lastError=nil
       return activeJourney:Guidance(),"NATIVE_DESTINATION_ZONE_OBSERVED"
    elseif position.mapID~=leg.from.mapID then
       activeJourney.lastError="UNEXPECTED_MAP_DURING_TRANSFER"
       return activeJourney:Guidance(),"UNEXPECTED_MAP_DURING_TRANSFER"
    end
 else
    -- Flights can traverse a single UI map. Observe the taxi state on this
    -- exact journey leg, followed by an independent native world-distance
    -- arrival receipt. Never equate a simple normalized coordinate with it.
    if leg.mode=="FLIGHT" and onTaxi() then
       taxiLegReceipt={journey=activeJourney,index=activeJourney.index}
       activeJourney.lastError=nil
       return activeJourney:Guidance(),"FLIGHT_IN_PROGRESS"
    end
    if leg.mode=="FLIGHT" and taxiLegReceipt and
       taxiLegReceipt.journey==activeJourney and
       taxiLegReceipt.index==activeJourney.index then
       local hud=JLP:GetModule("IntegratedNavigationHUD")
       local geo=hud and hud.GetGeometry and hud:GetGeometry(leg.to) or nil
       local jt=JLP:GetModule("IntegratedJuztTom")
    local radius=jt and jt.profile and tonumber(jt.profile.arrival) or 5
    if radius<3 or radius>35 or radius~=radius then radius=5 end
       if type(geo)=="table" and geo.instanceVerified==true and
          type(geo.distanceYards)=="number" and geo.distanceYards>=0 and
          geo.distanceYards<=radius then
          activeJourney:Advance();taxiLegReceipt=nil
          return activeJourney:Guidance(),"OBSERVED_SAME_MAP_TAXI_ARRIVAL"
       end
    end
    activeJourney.lastError="SAME_MAP_TRANSPORT_REQUIRES_LIVE_CONFIRMATION"
    return activeJourney:Guidance(),"SAME_MAP_TRANSFER_NOT_CONFIRMED"
 end
 activeJourney.lastError=nil
 return activeJourney:Guidance(),onTaxi() and "FLIGHT_IN_PROGRESS" or "TRANSPORT_NOT_YET_ARRIVED"
end
-- Explicit user confirmation is permitted only after the player is physically
-- at the landing point in native world-space; confirms *guidance progression*,
-- never that a vendor, taxi, vehicle, or production action occurred.
function Engine:ConfirmSameMapArrival()
 if not activeJourney then return false,"NO_ACTIVE_JOURNEY" end
 local leg=activeJourney:CurrentLeg()
 if not leg or leg.mode=="WALK" or leg.from.mapID~=leg.to.mapID then
    return false,"NO_SAME_MAP_TRANSFER" end
 local supported,why=navigationCapability()
 if not supported then return false,why end
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 local s=owner and owner.GetSnapshot and owner:GetSnapshot()
 if not s or s.status~="AVAILABLE" or not s.route then
    return false,"ACTIVE_QUALIFIED_ROUTE_REQUIRED" end
 local current=nativeOrigin()
 if not current or current.mapID~=leg.to.mapID then return false,"MAP_NOT_VERIFIED" end
 local hud=JLP:GetModule("IntegratedNavigationHUD")
 local geo=hud and hud.GetGeometry and hud:GetGeometry(leg.to)
 local jt=JLP:GetModule("IntegratedJuztTom")
    local radius=jt and jt.profile and tonumber(jt.profile.arrival) or 5
    if radius<3 or radius>35 or radius~=radius then radius=5 end
 if not geo or geo.instanceVerified~=true or
    type(geo.distanceYards)~="number" or geo.distanceYards~=geo.distanceYards or
    geo.distanceYards<0 or geo.distanceYards>radius then
    return false,"LANDING_NOT_WORLD_VERIFIED" end
 activeJourney:Advance();taxiLegReceipt=nil
 return true,"USER_CONFIRMED_WORLD_VERIFIED_TRANSFER"
end
function Engine:GetGuidance()
 if not activeJourney then return {phase="IDLE",waypoint=nil,navigationOnly=true} end
 local state=activeJourney:Guidance()
 state.navigationOnly=true;state.nativeDispatchAllowed=false
 if state.phase=="WAIT_FOR_TRANSPORT" or state.phase=="TRANSFER_ARRIVAL" then
    state.waypoint=nil
    if state.transport=="FLIGHT" and onTaxi() then
       state.phase="IN_TRANSIT";state.instruction="Flight observed; awaiting destination map."
    end
 end
 return state
end
-- General, map-level advisory guidance from the same owner-qualified transport
-- graph used by Calculate. Unlike Calculate, a city entrance need not have
-- invented coordinates: the client-observed map change is the stage receipt.
-- No stage is admitted to the production journey or permits auto-completion.
function Engine:GetStagedGuidance(target)
 local supported,why=navigationCapability()
 if not supported then return nil,why end
 local destination,why=T.Contract.point(target)
 if not destination then return nil,why end
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" or
    not T.Contract.point(origin) then return nil,"NATIVE_PLAYER_POSITION_MISSING" end
 if origin.mapID==destination.mapID then return nil,"SAME_CLIENT_MAP" end
 self:Initialize()
 if not self.ownerDatasetAccepted then return nil,"OWNER_TRANSPORT_DATA_NOT_ADMITTED" end
 local graph=safeGraph(privateNetwork)
 local context={}
 if type(UnitFactionGroup)=="function" then
    local ok,v=pcall(UnitFactionGroup,"player")
    if ok and (v=="Horde" or v=="Alliance") then context.faction=v:upper() end
 end
 if type(UnitLevel)=="function" then
    local ok,v=pcall(UnitLevel,"player")
    if ok and type(v)=="number" then context.level=v end
 end
 if type(UnitClass)=="function" then
    local ok,_,token=pcall(UnitClass,"player")
    if ok and type(token)=="string" then context.classToken=token end
 end
 local observer=JLP:GetModule("FlightUnlockObservation")
 context.unlocked=observer and observer.GetVerifiedUnlocks and
    observer:GetVerifiedUnlocks() or nil
 local planner=T.MapTransitions
 if not planner or type(planner.FindPath)~="function" then
    return nil,"MAP_TRANSITION_ENGINE_UNAVAILABLE" end
 local route,reason,detail=planner:FindPath(graph,origin.mapID,destination.mapID,context)
 if not route then return nil,reason,detail end
 if #route==0 then return nil,"SAME_CLIENT_MAP" end
 local guidance,why2=planner:Guidance(route[1],destination,#route)
 if not guidance then return nil,why2 end
 guidance.originMapID=origin.mapID
 guidance.targetMapID=destination.mapID
 guidance.graphGeneration=graph.generation
 -- The raw point of a transport platform is only a location cue. Arriving
 -- there does not establish vehicle boarding, journey completion or unlock.
 if guidance.phase=="WALK_TO_WAYPOINT" and guidance.waypoint then
    local hud=JLP:GetModule("IntegratedNavigationHUD")
    local geo=hud and hud.GetGeometry and hud:GetGeometry(guidance.waypoint) or nil
    local tom=JLP:GetModule("IntegratedJuztTom")
    local radius=tom and tom.profile and tonumber(tom.profile.arrival) or 5
    if radius<3 or radius>35 or radius~=radius then radius=5 end
    if geo and geo.instanceVerified==true and
       type(geo.distanceYards)=="number" and geo.distanceYards>=0 and
       geo.distanceYards<=radius then
       guidance.phase="WAIT_FOR_TRANSPORT"
       guidance.waypoint=nil
       guidance.instruction="At the departure platform. Board the correct "..
         tostring(guidance.transport or "transport"):lower()..
         " manually; wait for the game client to confirm the next map."
       guidance.stage=tostring(guidance.stage).."_BOARDING_PENDING"
    end
 end
 return guidance,"ADVISORY_MAP_TRANSITION_GUIDANCE"
end
-- Single presentation entry point for every admitted destination category.
-- The destination owner decides source identity; JuztTravel alone decides
-- how to travel. Incomplete network topology yields staged guidance, never
-- an independently constructed Gathering/Current Step/Manual route.
function Engine:GetNavigationGuidance(target,hasActiveRoute)
 if target and target.directBearing==true then
  return {phase="DIRECT_BEARING",waypoint=target,routeVerified=false,autoAdvance=false,
   instruction="Direct bearing to Annora; not a corridor/door/floor route. Observe learning separately.",
   displayTitle="Annora: direct bearing only",displayDetail="Terrain/passages unverified; no automatic completion.",
   terrainVerified=false,etaVerified=false},"DIRECT_BEARING_NOT_PHYSICAL_ROUTE"
 end
 if hasActiveRoute then
    local g=self:GetGuidance()
    if g and g.phase~="IDLE" and g.phase~="ARRIVED" then
       return g,"JUZTTRAVEL_ACTIVE_ROUTE"
    end
 end
 return self:GetStagedGuidance(target)
end
function Engine:GetIngressReference(target)
 local supported,why=navigationCapability()
 if not supported then return nil,why end
 self:Initialize()
 local router=JLP:GetModule("TravelRouter")
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" then
   return nil,"NATIVE_PLAYER_POSITION_MISSING" end
 local corridor=T.Corridor
 if not corridor or type(corridor.GetIngressReference)~="function" then
   return nil,"INGRESS_CONTRACT_MISSING" end
 return corridor:GetIngressReference(origin,target)
end
function Engine:GetCorridorCoverage()
    self:Initialize()
    return {"ORGRIMMAR_UNDERCITY_USER_OBSERVED_STANDALONE",
      "OWNER_AUTHORIZED_DATA_WITH_NATIVE_TEST_NOT_RUN",
      "FLIGHT_UNLOCK_AND_STAGE_CONFIRMATION_REQUIRED"}
end
JLP:RegisterModule("IntegratedTravelEngine",Engine)
