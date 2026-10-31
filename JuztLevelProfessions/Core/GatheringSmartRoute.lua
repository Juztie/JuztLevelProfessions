local _, JLP = ...
-- Smart MATERIALS, SKILL, BALANCED advisory policies over the SAME gathering
-- registry and CustomRoute geometry implementation. No live spawn assertions.
local Smart={contract="jlp-smart-profession-route-v1",nativeDispatchAllowed=false,
 maxStopsPerProfession=140,workUnit=1200}
local PROFESSIONS={"HERBALISM","MINING"}
local function position(p)
 return type(p)=="table" and type(p.x)=="number" and type(p.y)=="number" and
 p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1 and p.x==p.x and p.y==p.y
end
local function score(record,skill,focus,needs,bridge,observed,itemCache,skillCache,routeSource,mapID,evaluator,identityModule,selectionNow,keyCache,materialFallback,materialTargets)
 if not record or record.geometryType~="POINT" then return nil end
 -- These identities are identical for every POINT of one resource/skill
 -- band. Avoid repeating concatenation through the cooperative scan. The
 -- cache exists for this SelectCandidates job only; no map or DB persistence.
 local professionKeys=keyCache[record.professionKey]
 if not professionKeys then professionKeys={};keyCache[record.professionKey]=professionKeys end
 local keys=professionKeys[record.resourceKey]
 if not keys then
  keys={identity=record.professionKey..":"..record.resourceKey,bands={}}
  professionKeys[record.resourceKey]=keys
  keyCache._builds=keyCache._builds+1
 end
 local identity=keys.identity
 local bandIndex=record.requiredSkill~=nil and record.requiredSkill or false
 local bandKey=keys.bands[bandIndex]
 if not bandKey then
  bandKey=identity..":"..tostring(record.requiredSkill)..":"..tostring(skill)
  keys.bands[bandIndex]=bandKey
  keyCache._builds=keyCache._builds+1
 end
 local e=skillCache[bandKey]
 if not e then
  e=evaluator and evaluator:Evaluate(record,skill,"SMART_PROFESSION") or {smartEligible=false}
  skillCache[bandKey]=e
 end
 if not e.smartEligible then return nil end
 local matched=itemCache[identity]
 if matched==nil then
  matched=bridge and bridge:MatchMaterialNeeds(record.professionKey,record.resourceKey,needs) or
   {missing=0,weightedDemand=0}
  itemCache[identity]=matched
 end
 local missing=matched.missing or 0
 local material=matched.weightedDemand or 0
 local progression=(e.progressionEligibility=="POSSIBLE") and
  (e.colorBand=="ORANGE" and 1 or e.colorBand=="YELLOW" and 0.72 or 0.40) or 0
 if materialFallback and (focus=="MATERIALS" or focus=="BALANCED") and
    bridge and type(bridge.HasQualifiedGenericOutput)=="function" then
  -- One generic-output lookup per node identity per route generation;
  -- this is a historical-density proxy, not verified spawn/yield chance.
  if matched._jlpGeneric==nil then
   matched._jlpGeneric=bridge:HasQualifiedGenericOutput(record.professionKey,record.resourceKey)==true
  end
  if matched._jlpGeneric then material=math.max(material,0.20) end
 end
 if focus=="MATERIALS" and materialTargets~=nil then
  if not (type(materialTargets[record.professionKey])=="table" and
    materialTargets[record.professionKey][record.resourceKey]==true) then return nil end
  material=1
 end
 if focus=="MATERIALS" and missing<=0 and material==0 then return nil end
 if focus=="SKILL" and progression==0 then return nil end
 if focus=="BALANCED" and material==0 and progression==0 then return nil end
 local personalID=record.referenceID or (identityModule and identityModule:FromReference(record,mapID))
 -- Legacy direct-selector fixtures lack referenceID. Runtime Start() always
 -- supplies the canonical ID, and only that ID can identify matched records.
 local directTestKey=(not personalID) and (record.resourceKey..":"..math.floor(record.x*10000+0.5)..":"..math.floor(record.y*10000+0.5)) or nil
 local personal=observed and ((personalID and observed[personalID]) or (directTestKey and observed[directTestKey]))
 if routeSource=="OBSERVED_ONLY" and not personal then return nil end
 local personalCount=type(personal)=="table" and math.max(1,tonumber(personal.count) or 1) or (personal and 1 or 0)
 local observedAt=type(personal)=="table" and tonumber(personal.observedAt) or nil
 local now=selectionNow
 local ageDays=(now and observedAt and now>=observedAt) and math.floor((now-observedAt)/86400) or nil
 local freshPersonal=personalCount>0 and (not ageDays or ageDays<=180)
 local corroborated=type(record.sources)=="table" and #record.sources>=2
 local value=(focus=="MATERIALS" and material or
  focus=="SKILL" and progression or 0.55*material+0.45*progression)
 -- Evidence is a bounded tie-breaker, NOT a live spawn or loot probability.
 local evidenceBoost=(corroborated and 0.025 or 0)+(freshPersonal and
  ((routeSource=="PREFER_OBSERVED" and 0.115 or 0.055)+math.min(0.02,0.005*personalCount)) or 0)
 -- The full immutable advisory reason is needed only by the winning POINT
 -- in each spatial cell. Return scalar evidence so losing nodes create no
 -- short-lived per-record reason table in the cooperative hot path.
 return value*(0.90+evidenceBoost),material,progression,missing,matched.itemID,
  matched.outputKind,personalCount>0,corroborated,personalCount,ageDays
end
function Smart:SelectCandidates(points,skill,focus,needs,bridge,observed,maxStops,checkpoint,routeSource,mapID,materialFallback,materialTargets)
 local cells={};local all={}
 local itemCache,skillCache={},{}
 local keyCache={_builds=0}
 -- Capture stateless module references once per cooperative selection. Previously
 -- GetModule was traversed for every eligible POINT during cold decode; neither
 -- evaluator nor identity registry changes in the same job. No cross-job cache.
 local evaluator=JLP:GetModule("NodeSkillEvaluator")
 local identityModule=mapID and JLP:GetModule("GatheringReferenceIdentity") or nil
 local check=type(checkpoint)=="function" and checkpoint or function() end
 -- Personal observation ages share one job-local clock snapshot. Calling time()
 -- for every eligible POINT was redundant and could cross a day boundary while
 -- scoring one candidate set. Never persist this value across map/jobs.
 local selectionNow=type(time)=="function" and time() or nil
 local scanned=0
 self._reasonTablesBuilt=0 -- read-only benchmark diagnostic, scoped to this job
 for _,p in ipairs(points or {}) do
  scanned=scanned+1
  local value,material,progression,missing,materialID,outputKind,personal,
   corroborated,personalCount,ageDays=score(p,skill,focus,needs or {},bridge,observed,
   itemCache,skillCache,routeSource,mapID,evaluator,identityModule,selectionNow,keyCache,materialFallback,materialTargets)
  if value then
   -- Cold selection: retain the exact resource/x/y cell identity without
   -- allocating a composite resource:x:y string for every eligible POINT.
   -- The three-level index is job-local; winner/tie and sort semantics are
   -- unchanged. No map-wide cache or source-record mutation is introduced.
   local byResource=cells[p.resourceKey]
   if not byResource then byResource={};cells[p.resourceKey]=byResource end
   local cx,cy=math.floor(p.x*40),math.floor(p.y*40)
   local column=byResource[cx]
   if not column then column={};byResource[cx]=column end
   local previous=column[cy]
   if not previous or value>previous.score then
    local why={material=material,progression=progression,demand=missing,
     materialItemID=materialID,materialOutputKind=outputKind,outputNotGuaranteed=true,
     confidence=personal and "PERSONAL_HISTORY" or "HISTORICAL_REFERENCE",
     historicalCorroboration=corroborated,observationCount=personalCount,
     observationAgeDays=ageDays}
    column[cy]={point=p,score=value,why=why}
    self._reasonTablesBuilt=(self._reasonTablesBuilt or 0)+1
   end
  end
  check()
 end
 -- Read-only diagnostics for a job; no candidate/scoring ownership.
 self._resourceKeyBuilds=keyCache._builds
 for _,resourceCells in pairs(cells) do
  for _,column in pairs(resourceCells) do
   for _,entry in pairs(column) do all[#all+1]=entry;check() end
  end
 end
 -- Bottom-up stable mergesort: all comparisons and writes checkpointed.
 -- table.sort() is a non-yieldable C call in WoW Lua 5.1; its worst-case
 -- candidate-cell work previously happened inside a single Tick().
 -- The same score/resource/x/y order is preserved, with source insertion
 -- order as the deterministic final tie-breaker (no score/provenance change).
 local function before(a,b)
  if a.score~=b.score then return a.score>b.score end
  if a.point.resourceKey~=b.point.resourceKey then return a.point.resourceKey<b.point.resourceKey end
  if a.point.x~=b.point.x then return a.point.x<b.point.x end
  return a.point.y<=b.point.y
 end
 local n=#all
 if self._job then self._job.stage="CANDIDATE_SORT" end
 if n>1 then
  -- Cooperative stable mergesort with alternating job-local buffers. The
  -- old implementation copied all n entries BACK into `all` after each
  -- merge width, checkpointing the same array an extra log2(n) times.
  -- The final buffer owns the identical stable order, with checkpoints on
  -- every comparison/output write. No non-yieldable table.sort or persistence.
  local input,output=all,{}
  local width=1
  while width<n do
   local left=1
   while left<=n do
    local middle=math.min(n,left+width-1)
    local right=math.min(n,left+2*width-1)
    local i,j=left,middle+1
    for k=left,right do
     if i>middle then output[k]=input[j];j=j+1
     elseif j>right then output[k]=input[i];i=i+1
     elseif before(input[i],input[j]) then output[k]=input[i];i=i+1
     else output[k]=input[j];j=j+1 end
     check()
    end
    left=right+1
   end
   input,output=output,input
   width=width*2
  end
  all=input
 end
 if self._job then self._job.stage="CANDIDATE_DIVERSIFY" end
 -- A score-only prefix can collapse into a single end of the map. Build a
 -- bounded, spatially representative shortlist BEFORE the greedy selection.
 local shortlist={};local coarse={}
 for _,entry in ipairs(all) do
  local p=entry.point
  -- Preserve the exact two-dimensional bucket identity without allocating
  -- a composite string for every candidate after the bounded stable sort.
  -- The row table is job-local; negative coordinates retain distinct cells.
  local cx=math.min(11,math.floor(p.x*12))
  local cy=math.min(11,math.floor(p.y*12))
  local column=coarse[cx]
  if not column then column={};coarse[cx]=column end
  local count=column[cy] or 0
  if count<8 then
   column[cy]=count+1
   shortlist[#shortlist+1]=entry
  end
  check()
 end
 if self._job then self._job.stage="CANDIDATE_SCORING" end
 local chosen={};local used={};local nearest={};local nearestSpread={}
 local previousPoint=nil
 -- Cache only the sqrt of the monotonic nearest distance for this selection.
 -- Re-evaluate it when a new waypoint improves nearest[i]; no cache survives
 -- cancellation, map changes or the next SelectCandidates invocation.
 self._spreadComputations=0
 local cap=math.max(0,math.min(self.maxStopsPerProfession,math.floor(maxStops or self.maxStopsPerProfession)))
 for _=1,math.min(cap,#shortlist) do
  local bestIndex,bestRank=nil,-1
  for i,r in ipairs(shortlist) do
   if not used[i] then
    -- Fold the previous selection's nearest-distance update into the NEXT
    -- scoring scan. Identical ranks/tie order, but one bounded traversal per
    -- selected stop rather than scoring + separate nearest update.
    if previousPoint then
     local dx=r.point.x-previousPoint.x;local dy=r.point.y-previousPoint.y
     local dist=dx*dx+dy*dy
     if not nearest[i] or dist<nearest[i] then
      nearest[i]=dist
      nearestSpread[i]=math.min(1,math.sqrt(dist))
      self._spreadComputations=self._spreadComputations+1
     end
    end
    local spread=nearestSpread[i] or 1
    local rank=0.82*r.score+0.18*spread
    if rank>bestRank then bestRank=rank;bestIndex=i end
   end
   check()
  end
  if not bestIndex then break end
  used[bestIndex]=true
  local entry=shortlist[bestIndex]
  local point={}
  for k,v in pairs(entry.point) do point[k]=v end
  point.smartReasons=entry.why
  chosen[#chosen+1]=point
  previousPoint=point
 end
 return chosen,#all,scanned
end
function Smart:Cancel(reason)
 self._generation=(self._generation or 0)+1
 self._job=nil;self._mapID=nil;self._routes=nil
 self._status=reason or "CANCELLED"
 self._summary=nil -- cancelled jobs must not expose uncommitted candidate counts
 self._preview=nil
 return true
end
function Smart:GetRoutes(mapID)
 if self._mapID==mapID then return self._routes,self._status end
 return nil,"NO_ACTIVE_ROUTE"
end
function Smart:GetStatus() return self._status or "IDLE" end
function Smart:Start(mapID,shape,player,onComplete)
 if type(mapID)~="number" or mapID<1 or mapID~=math.floor(mapID) then return false,"MAP_ID_INVALID" end
 if shape~="LOOP" and shape~="FROM_PLAYER" then return false,"SHAPE_INVALID" end
 if shape=="FROM_PLAYER" and not position(player) then return false,"PLAYER_POSITION_UNAVAILABLE" end
 local shared=JLP:GetModule("GatheringSharedMapState")
 local options=shared and shared:GetSnapshot()
 if not options or options.mode~="SMART_PROFESSION" then return false,"NOT_SMART_MODE" end
 local layerController=JLP:GetModule("GatheringMapLayerController")
 local layers=layerController and layerController:GetLayerState(mapID)
 local registry=JLP:GetModule("GatheringDataRegistry")
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local custom=JLP:GetModule("GatheringCustomRoute")
 if not layers or not registry or not bridge or not custom then return false,"SMART_DATA_UNAVAILABLE" end
 local needs,total,source=bridge:ReadPlannerNeeds()
 local targets=options.focus=="MATERIALS" and options.smartMaterialTargets or nil
 if options.focus=="MATERIALS" then
  local any=false
  for _,profession in ipairs(PROFESSIONS) do
   for _,chosen in pairs(type(targets)=="table" and targets[profession] or {}) do
    if chosen then any=true;break end
   end
  end
  if not any then return false,"MATERIAL_TARGETS_REQUIRED" end
 end
 -- Start is O(enabled layers), never a cold-zone decode or reference copy.
 -- Both historical references and personal observations are read in the
 -- cooperative coroutine. No partial route/cache publication from Start.
 local batches={}
 for _,key in ipairs(PROFESSIONS) do
  local layer=layers.layers and layers.layers[key]
  if layer and layer.learned and layer.enabled then
   batches[#batches+1]={key=key,skill=layer.skill}
  end
 end
 -- No planner shortage: score documented generic gathering outputs using
 -- historical coverage only; do not invent live yields or resource demand.
 if #batches==0 then
  self:Cancel("NO_ELIGIBLE_ROUTE");return false,"NO_ELIGIBLE_ROUTE" end
 self:Cancel("RESTARTED")
 local generation=self._generation
 self._mapID=mapID;self._status="GENERATING";self._routes={}
 self._preview={mode="SMART_PROFESSION",focus=options.focus,plannerSource=source,
  materialShortageCount=total,candidateCells=0,excludedLayers=0,scannedRecords=0,
  sourceEvidence="HISTORICAL_REFERENCE_ONLY",terrainValidated=false,nativeDispatchAllowed=false}
 -- Final summary is private until routes atomically commit at job completion.
 self._summary=nil
 local job={generation=generation,onComplete=onComplete,workUnits=0,stage="REFERENCE_LOAD"}
 self._job=job
 job.co=coroutine.create(function()
  local operations=0
  local function checkpoint()
   job.workUnits=job.workUnits+1
   operations=operations+1
   if operations>=Smart.workUnit then operations=0;coroutine.yield("YIELD_WORK_BUDGET") end
  end
  local observations=JLP:GetModule("GatheringObservationStore")
  local own=observations and observations:GetZoneSnapshot(mapID)
  checkpoint()
  job.stage="ZONE_SUITABILITY"
  local suitability=JLP:GetModule("GatheringZoneSuitability")
  local zone=suitability and suitability:Evaluate(mapID,options.focus,needs,layers.layers,nil,checkpoint)
  local pendingSummary={mode="SMART_PROFESSION",focus=options.focus,plannerSource=source,
   materialShortageCount=total,candidateCells=0,excludedLayers=0,scannedRecords=0,
   sourceEvidence="HISTORICAL_REFERENCE_ONLY",terrainValidated=false,nativeDispatchAllowed=false}
  pendingSummary.zoneSuitability=zone and {score=zone.score,confidence=zone.confidence,
   eligibleCells=zone.eligibleCells,reasons=zone.reasons} or nil
  local routes={}
  local considered,skipped,scanned=0,0,0
  -- Both engines use the same historical/personal candidate union. The job
  -- owns each profession's observation index; no shared mutable route cache.
  job.stage="REFERENCE_LOAD"
  local keys={}
  for _,batch in ipairs(batches) do keys[#keys+1]=batch.key end
  local projected,projectionError=registry:GetZoneBatchSnapshots(mapID,keys,checkpoint)
  if not projected then error(projectionError or "REFERENCE_PROJECTION_UNAVAILABLE") end
  for _,batch in ipairs(batches) do
   -- Budgeted registry decode/copy is executed ONLY from Tick's coroutine.
   -- An import invalidating a staged decode aborts the job fail-closed.
   job.stage="REFERENCE_LOAD"
   local snapshot=projected[batch.key]
   local points,verified=custom:MergeObservationCandidates(snapshot and snapshot.references or {},
    own,batch.key,mapID,batch.skill,checkpoint)
   job.stage="CANDIDATE_SELECTION"
   local chosen,count,n=self:SelectCandidates(points,batch.skill,options.focus,
    needs,bridge,verified,self.maxStopsPerProfession,checkpoint,options.routeSource,mapID,total==0 and options.focus~="MATERIALS",targets)
   considered=considered+count;scanned=scanned+n
   if #chosen>=2 then
    job.stage="ROUTE_GEOMETRY"
    local route=custom:BuildGeometry(chosen,batch.key,shape,player,checkpoint)
    if route then
     route.mode="SMART_PROFESSION";route.focus=options.focus
     route.reason="Sourced requirements and historical locations; no live spawn or terrain guarantee"
     route.candidateCells=count;route.scannedRecords=n
     route.routeSource=options.routeSource or "ALL"
     routes[batch.key]=route
    end
   else skipped=skipped+1 end
  end
  pendingSummary.candidateCells=considered
  pendingSummary.scannedRecords=scanned
  pendingSummary.excludedLayers=skipped
  pendingSummary.sourceEvidence=own and #(own.verified or {})>0 and "HISTORICAL_AND_PERSONAL_HISTORY" or "HISTORICAL_REFERENCE_ONLY"
  return {routes=routes,summary=pendingSummary}
 end)
 return true,"GENERATING"
end
function Smart:Tick()
 local job=self._job
 if not job then return self:GetStatus() end
 if job.generation~=self._generation then return "CANCELLED" end
 local ok,result=coroutine.resume(job.co)
 if not ok then self:Cancel("ROUTE_ERROR");return "ROUTE_ERROR" end
 if coroutine.status(job.co)=="dead" then
  -- One generation owns both completed routes and final read-only summary.
  self._routes=type(result)=="table" and type(result.routes)=="table" and result.routes or {}
  self._status=next(self._routes) and "READY" or "NO_ELIGIBLE_ROUTE"
  self._summary=type(result)=="table" and result.summary or nil
  self._preview=nil
  self._job=nil
  if type(job.onComplete)=="function" then pcall(job.onComplete,self._status) end
 end
 return self:GetStatus()
end
-- Check counts are operation budgets, never a progress percentage or ETA.
function Smart:GetProgress(mapID)
 local job=self._job
 if not job or self._mapID~=mapID or job.generation~=self._generation then return nil end
 return {stage=job.stage,workChecks=job.workUnits,workUnit=self.workUnit,
  nativeDispatchAllowed=false}
end
-- Never expose mutable internal summaries or mid-job suitability/candidate data.
-- GENERATING is a preview of Start inputs only, not a committed route receipt.
local function safeSummary(source,depth)
 if type(source)~="table" then return source end
 depth=depth or 0
 if depth>=6 then return nil end -- fail closed on unexpected recursive data
 local out={}
 for k,v in pairs(source) do
  if type(v)=="table" then out[k]=safeSummary(v,depth+1)
  elseif type(v)~="function" and type(v)~="userdata" then out[k]=v end
 end
 return out
end
function Smart:GetSummary(mapID)
 if mapID~=nil and mapID~=self._mapID then return nil,"NO_ACTIVE_ROUTE" end
 local generating=self._job~=nil and self._status=="GENERATING"
 local summary=safeSummary(generating and self._preview or self._summary)
 if not summary then return nil,self:GetStatus() end
 summary.generation=self._generation
 summary.mapID=self._mapID
 summary.status=self:GetStatus()
 summary.committed=not generating
 summary.preview=generating
 summary.nativeDispatchAllowed=false
 return summary
end
JLP:RegisterModule("GatheringSmartRoute",Smart)
