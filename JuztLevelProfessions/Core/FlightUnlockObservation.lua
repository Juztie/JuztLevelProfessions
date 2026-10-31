local _,JLP=...
-- Read-only native taxi-map observation with character-scoped, build-scoped
-- SavedVariables for positively witnessed access. Never clicks flight controls,
-- never infers undiscovered paths from a map marker, never asserts all flights.
-- Unmatched locale, unobserved connections and ambiguous identities remain UNKNOWN.
local Observation={contract="jlp-flight-unlock-observation-v3",nativeDispatchAllowed=false}
local last=nil
local taxiOpened=false
local openedContext=nil
local function now()
 if type(GetTime)~="function" then return nil end
 local ok,t=pcall(GetTime)
 if ok and type(t)=="number" and t==t and t>=0 then return t end
 return nil
end
local function guid()
 if type(UnitGUID)~="function" then return nil end
 local ok,g=pcall(UnitGUID,"player")
 if ok and type(g)=="string" and #g>3 then return g end
 return nil
end
local function currentMap()
 if type(C_Map)~="table" or type(C_Map.GetBestMapForUnit)~="function" then return nil end
 local ok,m=pcall(C_Map.GetBestMapForUnit,"player")
 if ok and type(m)=="number" then return m end
 return nil
end
local function nativeFaction()
 if type(UnitFactionGroup)~="function" then return nil end
 local ok,value=pcall(UnitFactionGroup,"player")
 if ok and (value=="Horde" or value=="Alliance") then return value:upper() end
 return nil
end
local function exactName(name)
 -- Exact owner-recorded enUS taxi label. No NPC fallback or fuzzy aliases.
 if type(name)~="string" or name=="" or #name>150 then return nil end
 return name
end
local function locale()
 if type(GetLocale)~="function" then return nil end
 local ok,value=pcall(GetLocale)
 return ok and type(value)=="string" and value or nil
end
local function visibleTaxi()
 if TaxiFrame==nil or type(TaxiFrame.IsShown)~="function" then return false end
 local ok,v=pcall(TaxiFrame.IsShown,TaxiFrame)
 return ok and v==true
end
local function capability(scope)
 local e=JLP:GetModule("NavigationCapabilityEvidence")
 if not e or type(e.Check)~="function" then return false,"CAPABILITY_CONTRACT_UNAVAILABLE" end
 return e:Check(scope or "POSITION")
end
local STORE_SCHEMA=2
local STORE_LIMIT=320
local function accountStore(create)
 local db=JLP.DB
 if type(db)~="table" or type(db.account)~="table" then return nil end
 local root=db.account.flightUnlockObservations70450
 if root==nil and create then
    root={schema=STORE_SCHEMA,characters={}}
    db.account.flightUnlockObservations70450=root
 end
 -- v1 observations were build-70450-specific. Archive rather than promote
 -- their flight edges as current unlocks, even on the same client build.
 if type(root)=="table" and root.schema==1 and type(root.characters)=="table" and create then
    root.legacy70450=root.characters
    root.characters={}
    root.schema=STORE_SCHEMA
 end
 if type(root)~="table" or root.schema~=STORE_SCHEMA or
    type(root.characters)~="table" then return nil end
 return root.characters
end
local function canonicalEdgeIDs()
 local provider=JLP:GetModule("OwnerAuthorizedNavigation")
 if not provider or type(provider.GetTransportDataset)~="function" or
    type(provider.MatchesCanonicalTransport)~="function" then return nil end
 local ds=provider:GetTransportDataset()
 if type(ds)~="table" or not provider:MatchesCanonicalTransport(ds) then return nil end
 local edges={}
 for _,e in ipairs(ds.edges or {}) do
    if type(e)=="table" and e.mode=="FLIGHT" and e.requiresUnlock==true and
        type(e.id)=="string" then edges[e.id]=true end
 end
 return edges
end
local function getCharacterRecord(create)
 local supported,reason,proof=capability("POSITION")
 if not supported then return nil,reason end
 local g,f,lang=guid(),nativeFaction(),locale()
 local classToken=proof.classToken
 local rows=accountStore(create)
 if not g or not f or not lang or not rows then
    return nil,"CHARACTER_OR_SAVEDVARIABLES_UNAVAILABLE" end
 local key="guid:"..g
 local rec=rows[key]
 if rec and (type(rec)~="table" or rec.schema~=STORE_SCHEMA or
     rec.clientBuild~=proof.observedClientBuild or
     rec.interface~=proof.interface or rec.guid~=g or rec.faction~=f or
     rec.classToken~=classToken or rec.locale~=lang or
     type(rec.unlockedEdges)~="table") then
     -- A changed build, faction or locale cannot borrow another survey.
     if create then rows[key]=nil end
     rec=nil
 end
 if not rec and create then
   rec={schema=STORE_SCHEMA,sourceBuild=70450,
       clientBuild=proof.observedClientBuild,interface=proof.interface,
       guid=g,faction=f,classToken=classToken,locale=lang,
       unlockedEdges={},knownStations={},observations=0}
   rows[key]=rec
 end
 return rec,rec and "CHARACTER_FLIGHT_RECORD_FOUND" or "NO_FLIGHT_RECORD"
end
local function persistPositiveSurvey(nodeTypes,aliases,nodes,observedEdges)
 local record,why=getCharacterRecord(true)
 if not record then return false,why end
 local whitelist=canonicalEdgeIDs()
 if not whitelist then return false,"CANONICAL_TAXI_EDGES_UNAVAILABLE" end
 local recorded=0
 for id,value in pairs(observedEdges) do
   if value==true and whitelist[id] and not record.unlockedEdges[id] then
      record.unlockedEdges[id]=true;recorded=recorded+1
   end
 end
 record.knownStations=type(record.knownStations)=="table" and record.knownStations or {}
 -- CURRENT confirms the player's present Flight Master; REACHABLE confirms
 -- visibility and ability to select from this taxi map. Distant is inconclusive.
 for ownerID,label in pairs(aliases) do
    local kind=nodeTypes[label]
    if nodes[ownerID] and (kind=="CURRENT" or kind=="REACHABLE") then
       record.knownStations[ownerID]=true
    end
 end
 -- Prevent unexpected SavedVariables growth if the underlying source expands.
 local count=0;for _ in pairs(record.unlockedEdges) do count=count+1 end
 if count>STORE_LIMIT then return false,"FLIGHT_RECORD_LIMIT" end
 record.observations=math.min(100000,(tonumber(record.observations) or 0)+1)
 record.lastObservedAt=type(time)=="function" and time() or nil
 record.lastTaxiMapID=currentMap()
 return true,recorded
end
local function capture()
 last=nil
 local supported,reason,proof=capability("TAXI")
 if not supported then return false,reason end
 local g,clock,map,faction=guid(),now(),currentMap(),nativeFaction()
 -- TAXIMAP_OPENED can precede readiness of the current C_Map position.
 -- Retry only for the same taxi-opening character, build, faction and class.
 if not openedContext or proof.characterKey~=openedContext.characterKey or
    proof.observedClientBuild~=openedContext.observedClientBuild or
    proof.faction~=openedContext.faction or proof.classToken~=openedContext.classToken or
    (openedContext.mapID and map~=openedContext.mapID) then
    return false,"TAXI_CONTEXT_CHANGED" end
 openedContext.mapID=map
 local lang=locale()
 -- English EU clients commonly report enGB; only exact native labels
 -- matching the pinned English inventory are accepted in either locale.
 if lang~="enUS" and lang~="enGB" then return false,"TAXI_LOCALE_UNVERIFIED" end
 if not g or not clock or not map or not faction or not visibleTaxi() or
   type(NumTaxiNodes)~="function" or type(TaxiNodeGetType)~="function" or
   type(TaxiNodeName)~="function" then return false,"TAXI_API_OR_CONTEXT_UNKNOWN" end
 local ok,n=pcall(NumTaxiNodes)
 if not ok or type(n)~="number" or n<1 or n>512 or n~=math.floor(n) then
    return false,"TAXI_NODE_LIST_UNAVAILABLE" end
 local nodeTypes={}
 for i=1,n do
   local okName,name=pcall(TaxiNodeName,i)
   local okType,kind=pcall(TaxiNodeGetType,i)
   if not okName or not okType or not exactName(name) or
      (kind~="CURRENT" and kind~="REACHABLE" and kind~="DISTANT") then
      return false,"TAXI_NODE_OBSERVATION_INCOMPLETE" end
   -- Even equal duplicates are ambiguous: two taxi nodes cannot share one identity.
   if nodeTypes[name] then return false,"TAXI_NODE_NAME_AMBIGUOUS" end
   nodeTypes[name]=kind
 end
 local provider=JLP:GetModule("OwnerAuthorizedNavigation")
 if not provider or type(provider.GetTransportDataset)~="function" then
   return false,"OWNER_ROUTE_SOURCE_MISSING" end
 local ds=provider:GetTransportDataset()
 local identities=provider.GetTaxiNodeIdentities and provider:GetTaxiNodeIdentities() or nil
 if type(ds)~="table" or type(ds.edges)~="table" or
    type(identities)~="table" or
    not provider.MatchesCanonicalTransport or
    not provider.MatchesCanonicalTaxiIdentities or
    provider:MatchesCanonicalTransport(ds)~=true or
    provider:MatchesCanonicalTaxiIdentities(identities)~=true then
    return false,"OWNER_TAXI_SOURCE_INVALID" end
 local nodes={}
 for _,node in ipairs(ds.nodes or {}) do nodes[node.id]=node end
 -- The typed source-join is generated from pinned owner files. UI callers
 -- cannot supply mappings; missing/duplicate identities fail closed.
 local aliases,labels={},{}
 for _,entry in ipairs(identities) do
   if type(entry)~="table" or entry.locale~="enUS" or entry.faction~=faction or
      type(entry.ownerNodeID)~="string" or not exactName(entry.taxiNodeName) or
      type(entry.mapID)~="number" or not nodes[entry.ownerNodeID] or
      nodes[entry.ownerNodeID].mapID~=entry.mapID or
      aliases[entry.ownerNodeID] or labels[entry.taxiNodeName] then
       return false,"OWNER_TAXI_IDENTITY_CONFLICT" end
   aliases[entry.ownerNodeID]=entry.taxiNodeName
   labels[entry.taxiNodeName]=true
 end
 local unlocked={}
 for _,edge in ipairs(ds.edges) do
   if edge.mode=="FLIGHT" and edge.requiresUnlock==true and
      (edge.faction=="NEUTRAL" or edge.faction==faction) then
     local a,b=nodes[edge.from],nodes[edge.to]
     local aName,bName=aliases[edge.from],aliases[edge.to]
     -- Do not compare native taxi names to NPC labels, ever.
     -- A city Flight Master may belong to an exterior taxi map while the
     -- player's current C_Map UI map is the city interior. Native CURRENT
     -- taxi identity is authoritative for the source, not mapID equality.
     if a and b and aName and bName and
        nodeTypes[aName]=="CURRENT" and nodeTypes[bName]=="REACHABLE" then
        unlocked[edge.id]=true
     end
   end
 end
 local stored,why=persistPositiveSurvey(nodeTypes,aliases,nodes,unlocked)
 local _,_,proof=capability("POSITION")
 last={guid=g,mapID=map,faction=faction,locale=lang,at=clock,
    clientBuild=proof and proof.observedClientBuild,unlocked=unlocked,
    persistStatus=stored and "PERSISTED" or tostring(why)}
 return true,stored and "TAXI_MAP_OBSERVED_AND_PERSISTED" or
    "TAXI_MAP_OBSERVED_NOT_PERSISTED"
end
function Observation:GetVerifiedUnlocks()
 local supported,reason=capability("POSITION")
 if not supported then
   -- An absent position immediately after TAXIMAP_OPENED is transient.
   -- Preserve the bounded, character-bound retry; publish no unlocks.
   last=nil;return nil,reason
 end
 if taxiOpened and openedContext then
   local _,_,live=capability("POSITION")
   if not live or live.characterKey~=openedContext.characterKey or
      live.observedClientBuild~=openedContext.observedClientBuild or
      live.mapID~=openedContext.mapID or live.faction~=openedContext.faction or
      live.classToken~=openedContext.classToken then
      last=nil;taxiOpened=false;openedContext=nil
   end
 end
 if not last and taxiOpened and visibleTaxi() then capture() end
 local verified={};local evidence=false
 -- Persisted observations are hints for routing, NOT native permission to fly.
 -- Validate all edge IDs against the current owner-qualified graph on read.
 local stored,reason=getCharacterRecord(false)
 local whitelist=canonicalEdgeIDs()
 if stored and whitelist then
    for id,v in pairs(stored.unlockedEdges or {}) do
       if v==true and whitelist[id] then verified[id]=true;evidence=true end
    end
 end
 local g,m,t,f=guid(),currentMap(),now(),nativeFaction()
 local _,_,proof=capability("POSITION")
 if last and g and m and t and f and proof and
    proof.observedClientBuild==last.clientBuild and locale()==last.locale and
    f==last.faction and g==last.guid and m==last.mapID and
    t>=last.at and t-last.at<=120 then
    for id,v in pairs(last.unlocked) do
       if v==true and whitelist and whitelist[id] then verified[id]=true;evidence=true end
    end
 else last=nil end
 if evidence then return verified,"CHARACTER_PERSISTED_OR_LIVE_TAXI_ACCESS" end
 -- An empty result is not proof that any undiscovered edge is locked.
 return nil,reason or "FLIGHT_ACCESS_UNKNOWN"
end
function Observation:GetStatus()
 local v,why=self:GetVerifiedUnlocks()
 local count=0;for _ in pairs(v or {}) do count=count+1 end
 local r=getCharacterRecord(false)
 local stationCount=0
 for _,known in pairs(r and r.knownStations or {}) do if known==true then stationCount=stationCount+1 end end
 return {status=v and "OBSERVED" or "UNKNOWN",verifiedFlightEdges=count,
         knownFlightMasters=stationCount,observations=r and r.observations or 0,
         lastObservedAt=r and r.lastObservedAt or nil,reason=why,
         nativeAcceptance="NOT_RUN",persisted=r~=nil,
         store="JuztLevelProfessionsDB.account.flightUnlockObservations70450"}
end
-- Native taxi UI can become visible a frame after TAXIMAP_OPENED. Retry for
-- a bounded 10 seconds while it is open; no background scans or taxi actions.
if type(CreateFrame)=="function" then
 local ok,f=pcall(CreateFrame,"Frame")
 if ok and f and type(f.RegisterEvent)=="function" and type(f.SetScript)=="function" then
   for _,event in ipairs({"TAXIMAP_OPENED","TAXIMAP_CLOSED","PLAYER_ENTERING_WORLD","PLAYER_LOGOUT",
       "ZONE_CHANGED","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED_INDOORS"}) do
     pcall(f.RegisterEvent,f,event)
   end
   local function stopRetry() f:SetScript("OnUpdate",nil) end
   f:SetScript("OnEvent",function(_,event)
     if event=="TAXIMAP_OPENED" then
       -- Character must be known at opening time. Map/XY can settle later.
       local valid,_,ctx=capability("CHARACTER")
       taxiOpened=valid==true
       openedContext=taxiOpened and ctx or nil
       local accepted=taxiOpened and capture()
       if accepted then stopRetry();return end
       local elapsed,attempts=0,0
       f:SetScript("OnUpdate",function(_,dt)
          if not taxiOpened then stopRetry();return end
          elapsed=elapsed+(type(dt)=="number" and dt or 0)
          if elapsed<0.25 then return end
          elapsed=0;attempts=attempts+1
          if capture() or attempts>=40 then stopRetry() end
       end)
     else taxiOpened=false;openedContext=nil;last=nil;stopRetry() end
   end)
 end
end
JLP:RegisterModule("FlightUnlockObservation",Observation)
