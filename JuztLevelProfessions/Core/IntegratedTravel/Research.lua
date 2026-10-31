-- M17 read-only canonical research facade. The owner Excel provider is the
-- only source. This never authorizes crafting, taxi booking or automatic travel.
local _,JLP=...
local T=JLP._integratedTravel
local C=T.Contract
local R={}
local function owner() return JLP:GetModule('OwnerAuthorizedNavigation') end
local function safeEntries()
 local m=owner()
 return m and m.GetTransportPlaces and m:GetTransportPlaces() or {}
end
local function matchMap(e)
 if not (e and C.finite(e.mapID) and e.mapID>0 and type(e.zone)=='string') then return nil end
 if type(C_Map)~='table' or type(C_Map.GetMapInfo)~='function' then return nil end
 local ok,info=pcall(C_Map.GetMapInfo,e.mapID)
 if not ok or type(info)~='table' or type(info.name)~='string' then return nil end
 local function norm(x) return x:lower():gsub('^the ',''):gsub('%s+',' ') end
 if norm(info.name)~=norm(e.zone) then return nil end
 return e.mapID
end
function R:BuildGraph(preview)
 local m=owner()
 if not m or type(m.GetTransportDataset)~='function' then return nil,'OWNER_EXCEL_UNAVAILABLE' end
 local ds=m:GetTransportDataset()
 if not m:MatchesCanonicalTransport(ds) then return nil,'TRANSPORT_DATA_CONFLICT' end
 local graph=T.Network.New()
 local read={contract='juzt-travel-dataset-v1',nodes={},edges={}}
 for _,n in ipairs(ds.nodes or {}) do read.nodes[#read.nodes+1]=n end
 for _,e in ipairs(ds.edges or {}) do
  local copy=C.shallowCopy(e)
  copy.status=preview and 'verified' or 'draft'
  if preview then copy.requiresUnlock=false end -- preview only, never admission
  read.edges[#read.edges+1]=copy
 end
 local ok,reason=graph:RegisterDataset(read)
 if not ok then return nil,reason end
 return graph
end
function R:Summary()
 local entries=safeEntries()
 local out={total=#entries,knownMapIDs=0,unmapped=0,
  flightMasters=0,boatDepartures=0,zeppelinDepartures=0,
  linkHypotheses=0,sourceDirectRoutes=162,source='CANONICAL_EXCEL'}
 for _,e in ipairs(entries) do
  if matchMap(e) then out.knownMapIDs=out.knownMapIDs+1
   else out.unmapped=out.unmapped+1 end
  if e.category=='Flight Path' then out.flightMasters=out.flightMasters+1
  elseif e.category=='Boat' then out.boatDepartures=out.boatDepartures+1
  elseif e.category=='Zeppelin' then out.zeppelinDepartures=out.zeppelinDepartures+1 end
 end
 return out
end
function R:Nearby(mapID,x,y,maxItems)
 local loc=C.point({mapID=mapID,x=x,y=y})
 if not loc then return {},'INVALID_ORIGIN' end
 local out={}
 for _,e in ipairs(safeEntries()) do
  if matchMap(e)==loc.mapID then
   local d=C.distance(loc,{mapID=e.mapID,x=e.x,y=e.y})
   if d then out[#out+1]={id=e.id,name=e.name,kind=e.category,zone=e.zone,
    mapID=e.mapID,x=e.x,y=e.y,mapFraction=d,clientVerified=false,
    evidence='USER_EXCEL_MAP_NAME_OBSERVED'} end
  end
 end
 table.sort(out,function(a,b) if a.mapFraction==b.mapFraction then return a.id<b.id end
  return a.mapFraction<b.mapFraction end)
 local limit=tonumber(maxItems) or 5
 if limit<1 then limit=1 elseif limit>25 then limit=25 end
 while #out>limit do table.remove(out) end
 return out
end
function R:Preview(origin,goal,context)
 local graph,reason=self:BuildGraph(true)
 if not graph then return nil,reason end
 local plan,why,detail=T.Planner:Plan(graph,origin,goal,context or {faction='HORDE'},nil)
 if not plan then return nil,why,detail end
 return {contract='juzt-travel-excel-preview-v1',status='RESEARCH_ONLY_NOT_NAVIGABLE',
  graphGeneration=graph.generation,legs=plan.legs,etaSeconds=nil,
  routeAuthoritative=false,hypotheticalHops={},
  warning='Verified workbook connections are not live boarding evidence. Map name lookup and taxi unlocks must be observed in game.'}
end
T.Research=R
