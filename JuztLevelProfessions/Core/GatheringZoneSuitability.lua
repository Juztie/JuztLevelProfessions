local _, JLP = ...
-- Alpha155. Read-only, source-qualified historical zone suitability assessment.
-- Fast, bounded scanning of packed source strings; DOES NOT decode all source
-- entries into the live Registry, create map pins or imply current spawns.
local Engine={contract="jlp-gathering-zone-suitability-v1",nativeDispatchAllowed=false,
 maxZonesPerRanking=256,maxEncodedPositionsPerZone=12000,cellResolution=20, recommendationWorkUnit=700}
local PROFESSIONS={"HERBALISM","MINING"}
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function int(v) return finite(v) and v>=1 and v==math.floor(v) end
local function safeFloor(v) return math.floor(v+0.5) end
local function clamp(v) return math.max(0,math.min(1,v)) end
local function logScore(v) return math.log(1+math.max(0,v)) end
function Engine:Evaluate(mapID,focus,needs,layers,observations,checkpoint,targets)
 if not int(mapID) then return nil,"MAP_ID_INVALID" end
 if focus~="MATERIALS" and focus~="SKILL" and focus~="BALANCED" then return nil,"FOCUS_INVALID" end
 local result={mapID=mapID,status="NO_REFERENCE_COVERAGE",score=0,confidence="LOW",
  referenceCount=0,eligibleCount=0,eligibleCells=0,uniqueCells=0,
  materialCells=0,skillCells=0,materialWeightedCells=0,skillWeightedCells=0,
  materialReferenceCount=0,skillReferenceCount=0,resourceTypes=0,sourceCount=0,
  reasons={},estimatedTravel=false,liveSpawnVerified=false,nativeDispatchAllowed=false}
 local pack=JLP.data and JLP.data.gatheringReferencePacked
 local bucket=pack and pack.maps and pack.maps[mapID]
 if type(bucket)~="table" then return result end
 local manifest=JLP.data and JLP.data.gatheringSourceManifest
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local noDemand=true
 for _,v in pairs(type(needs)=="table" and needs or {}) do
  if type(v)=="number" and v>0 then noDemand=false;break end
 end
 local cellSeen,coordSeen,resourceSeen,sources={},{},{},{}
 local materialTypes,skillTypes,eligibleTypes={},{},{}
 local scan=0;local truncated=false
 -- Allow only actually learned and explicitly enabled professions. Caller
 -- cannot promote an unlearned layer by passing an arbitrary skill number.
 for _,row in ipairs(bucket) do
  if scan>=self.maxEncodedPositionsPerZone then truncated=true;break end
  local source,profession,resource,_,required,encoded=row[1],row[2],row[3],row[4],row[5],row[6]
  local sourceMeta=manifest and manifest.sources and manifest.sources[source]
  local layer=type(layers)=="table" and layers[profession]
  if layer and layer.learned==true and layer.enabled==true and finite(layer.skill) and layer.skill>=0 and
    sourceMeta and sourceMeta.redistributionApproved==true and sourceMeta.buildVerified==true and
    sourceMeta.licenseVerified==true and type(encoded)=="string" and #encoded%6==0 and
    type(resource)=="string" and (profession=="HERBALISM" or profession=="MINING") then
   sources[source]=true
   local candidate=bridge and bridge:MatchMaterialNeeds(profession,resource,needs)
   local shortage=candidate and candidate.weightedDemand or 0
   if (focus=="MATERIALS" or focus=="BALANCED") and noDemand and bridge and
     bridge.HasQualifiedGenericOutput and
     bridge:HasQualifiedGenericOutput(profession,resource) then shortage=0.20 end
   local gatherable=finite(required) and required>=0 and layer.skill>=required
   local requested=type(targets)=="table" and type(targets[profession])=="table" and
       targets[profession][resource]==true
   if focus=="MATERIALS" and targets~=nil then
       shortage=requested and 1 or 0
   end
   local mayProgress=gatherable and layer.skill<required+100
   for pos=1,#encoded,6 do
    if scan>=self.maxEncodedPositionsPerZone then truncated=true;break end
    scan=scan+1
    if checkpoint then checkpoint(1) end
    local x=tonumber(encoded:sub(pos,pos+2))
    local y=tonumber(encoded:sub(pos+3,pos+5))
    if x and y and x<=1000 and y<=1000 then
     local id=profession..":"..resource..":"..x..":"..y
     if not coordSeen[id] then
      coordSeen[id]=true;result.referenceCount=result.referenceCount+1
      resourceSeen[profession..":"..resource]=true
      local gridX=math.min(self.cellResolution-1,math.floor(x*self.cellResolution/1000))
      local gridY=math.min(self.cellResolution-1,math.floor(y*self.cellResolution/1000))
      local cell=profession..":"..resource..":"..gridX..":"..gridY
      if not cellSeen[cell] then
       cellSeen[cell]=true;result.uniqueCells=result.uniqueCells+1
       if gatherable then
        result.eligibleCells=result.eligibleCells+1
        if shortage>0 then
            result.materialCells=result.materialCells+1
            result.materialWeightedCells=result.materialWeightedCells+math.min(1,shortage)
        end
        if mayProgress then
            result.skillCells=result.skillCells+1
            result.skillWeightedCells=result.skillWeightedCells+
                (layer.skill<required+25 and 1 or layer.skill<required+50 and 0.72 or 0.35)
        end
       end
      end
      if gatherable then
       result.eligibleCount=result.eligibleCount+1
       eligibleTypes[profession..":"..resource]=true
       if shortage>0 then
        materialTypes[profession..":"..resource]=true
        result.materialReferenceCount=result.materialReferenceCount+1
       end
       if mayProgress then
        skillTypes[profession..":"..resource]=true
        result.skillReferenceCount=result.skillReferenceCount+1
       end
      end
     end
    end
   end
  end
 end
 for _ in pairs(resourceSeen) do result.resourceTypes=result.resourceTypes+1 end
 for _ in pairs(sources) do result.sourceCount=result.sourceCount+1 end
 if result.referenceCount==0 then
  result.status="NO_ELIGIBLE_LAYERS_OR_REFERENCES"
  return result
 end
 result.status="HISTORICAL_ZONE_ESTIMATE"
 result.sampleTruncated=truncated
 -- Density is computed over FOCUS-RELEVANT cells; unrelated gatherable
 -- resources must never inflate a Materials-only zone score.
 local relevant=focus=="MATERIALS" and result.materialCells or
  focus=="SKILL" and result.skillCells or math.max(result.skillCells,result.materialCells)
 local kinds={}
 local sourceTypes=focus=="MATERIALS" and materialTypes or
  focus=="SKILL" and skillTypes or eligibleTypes
 for _ in pairs(sourceTypes) do kinds[#kinds+1]=true end
 local relevantTypes=#kinds
 local support=math.min(1,relevant/20)
 local coverage=math.min(1,logScore(relevant)/logScore(100))
 local diversity=math.min(1,relevantTypes/4)
 local matched=math.min(1,logScore(result.materialWeightedCells)/logScore(35))
 local progression=math.min(1,logScore(result.skillWeightedCells)/logScore(35))
 local relevance=focus=="MATERIALS" and matched or
  focus=="SKILL" and progression or (0.55*matched+0.45*progression)
 -- Balance the purposes that remain available. Finishing skill progression
 -- does not erase known material demand, and no demand does not erase skill.
 if focus=="BALANCED" then
  if result.skillCells==0 then relevance=matched
  elseif result.materialCells==0 then relevance=progression end
 end
 if relevance==0 then result.status="NO_RELEVANT_NODES" end
 result.score=safeFloor(100*clamp(relevance*(0.65*coverage+0.20*diversity+0.15*support)))
 result.confidence=truncated and "LOW" or relevant>=30 and relevantTypes>=2 and "MODERATE" or "LOW"
 if relevant<8 then result.score=math.min(result.score,39) end
 if result.confidence=="LOW" then result.score=math.min(result.score,69) end
 result.reasons[1]=result.eligibleCells.." eligible historical cells across "..result.resourceTypes.." resources"
 result.reasons[2]=result.materialCells.." material-relevant and "..result.skillCells.." progression-reference cells ("..relevant.." focus-relevant)"
 result.reasons[3]=truncated and "Sample capped; low confidence" or "No live spawn, terrain or yield validation"
 return result
end
function Engine:Rank(mapIDs,focus,needs,layers,limit)
 if type(mapIDs)~="table" then return {},"MAP_LIST_INVALID" end
 local unique,results={},{}
 for _,id in ipairs(mapIDs) do
  if #results>=self.maxZonesPerRanking then break end
  if int(id) and not unique[id] then
   unique[id]=true
   local result=self:Evaluate(id,focus,needs,layers)
   if result and result.referenceCount>0 then results[#results+1]=result end
  end
 end
 table.sort(results,function(a,b)
  if a.score~=b.score then return a.score>b.score end
  if a.eligibleCells~=b.eligibleCells then return a.eligibleCells>b.eligibleCells end
  return a.mapID<b.mapID
 end)
 while #results>math.max(1,math.min(12,math.floor(tonumber(limit) or 5))) do table.remove(results) end
 return results,"HISTORICAL_COMPARISON_ONLY"
end
function Engine:RecommendFromBrowser(currentZone,focus)
 local browser=JLP:GetModule("ForeverFishingZoneBrowser")
 local ctrl=JLP:GetModule("GatheringMapLayerController")
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 if not browser or not ctrl then return nil,"ZONE_SERVICE_UNAVAILABLE" end
 local candidates,reason=browser:Discover(currentZone)
 if #candidates==0 then return nil,reason end
 local layer=ctrl:GetLayerState(currentZone.mapID)
 if not layer then return nil,"LAYERS_UNAVAILABLE" end
 local needs,total=bridge and bridge:ReadPlannerNeeds()
 local ids={}
 for _,z in ipairs(candidates) do ids[#ids+1]=z.mapID end
 local ranked=self:Rank(ids,focus,needs,layer.layers,5)
 local best=ranked[1]
 if not best or best.score==0 then
  return nil,"NO_SUITABLE_REFERENCE_ZONE" end
 local name
 for _,z in ipairs(candidates) do if z.mapID==best.mapID then name=z.name;break end end
 best.name=name
 return best,"ADVISORY_ONLY"
end

-- Alpha158: expensive reference-zone scans never execute inside the UI click.
-- Every checkpoint yields after a finite number of packed coordinate operations.
function Engine:CancelRecommendation(reason)
 self._recommendGeneration=(self._recommendGeneration or 0)+1
 self._recommendJob=nil
 self._recommendStatus=reason or "CANCELLED"
 return true
end
function Engine:GetRecommendationStatus()
 return self._recommendJob and "GENERATING" or self._recommendStatus or "IDLE"
end
function Engine:GetRecommendationProgress()
 local job=self._recommendJob
 return job and {scanned=job.scanned or 0,zonesProcessed=job.zonesProcessed or 0,
  zonesTotal=job.zonesTotal or 0,estimated=true} or nil
end
function Engine:StartRecommendation(currentZone,focus,onComplete)
 self:CancelRecommendation("REPLACED")
 if type(currentZone)~="table" or not int(currentZone.mapID) then return false,"MAP_INVALID" end
 if focus~="MATERIALS" and focus~="SKILL" and focus~="BALANCED" then return false,"FOCUS_INVALID" end
 local shared=JLP:GetModule("GatheringSharedMapState")
 local snapshot=shared and shared:GetSnapshot()
 if not snapshot or snapshot.mode~="SMART_PROFESSION" or snapshot.focus~=focus then return false,"SMART_MODE_REQUIRED" end
 local generation=self._recommendGeneration
 local job={generation=generation,originalMap=snapshot.selectedMapID,focus=focus,
  scanned=0,zonesProcessed=0,zonesTotal=0,onComplete=onComplete,
  materialToken=focus=="MATERIALS" and shared:GetRouteContextKey(snapshot.selectedMapID or currentZone.mapID) or nil,
  originalCurrentMap=currentZone.mapID}
 self._recommendJob=job
 self._recommendStatus="GENERATING"
 job.co=coroutine.create(function()
  local browser=JLP:GetModule("ForeverFishingZoneBrowser")
  local ctrl=JLP:GetModule("GatheringMapLayerController")
  local bridge=JLP:GetModule("GatheringMaterialBridge")
  if not browser or not ctrl then return nil,"ZONE_SERVICE_UNAVAILABLE" end
  local zones,seen={},{}
  -- Evaluate both continents, never just the player's current continent.
  -- Native C_Map validates zone IDs; packed evidence gates candidate scope.
  local packed=JLP.data and JLP.data.gatheringReferencePacked
  for _,continent in ipairs({"KALIMDOR","EASTERN_KINGDOMS"}) do
   local entries=browser:DiscoverContinent(continent)
   for _,entry in ipairs(type(entries)=="table" and entries or {}) do
    if not seen[entry.mapID] and type(packed)=="table" and type(packed.maps)=="table" and
       type(packed.maps[entry.mapID])=="table" then
      seen[entry.mapID]=true;zones[#zones+1]=entry
    end
   end
  end
  -- Include any further Forever zones with packaged qualified references.
  -- Discover all candidate IDs from our data, but accept the display name
  -- and zone mapType ONLY from the running client's native C_Map registry.
  local client=type(C_Map)=="table" and C_Map or nil
  if client and type(client.GetMapInfo)=="function" and type(packed)=="table" then
   for mapID,rows in pairs(type(packed.maps)=="table" and packed.maps or {}) do
    if int(mapID) and type(rows)=="table" and not seen[mapID] then
     local valid,info=pcall(client.GetMapInfo,mapID)
     if valid and type(info)=="table" and info.mapType==3 and
         type(info.name)=="string" and info.name~="" then
      seen[mapID]=true;zones[#zones+1]={mapID=mapID,name=info.name}
     end
    end
   end
  end
  table.sort(zones,function(a,b) return a.mapID<b.mapID end)
  if #zones==0 then return nil,"NO_QUALIFIED_CLIENT_ZONES" end
  local layer=ctrl:GetLayerState(currentZone.mapID)
  if not layer then return nil,"LAYERS_UNAVAILABLE" end
  local needs,total=bridge and bridge:ReadPlannerNeeds()
  needs=type(needs)=="table" and needs or {}
  local targets=focus=="MATERIALS" and snapshot.smartMaterialTargets or nil
  if focus=="MATERIALS" then
    local found=false
    for _,profession in ipairs(PROFESSIONS) do
      for _,chosen in pairs(type(targets)=="table" and targets[profession] or {}) do
        if chosen then found=true;break end
      end
    end
    if not found then return nil,"MATERIAL_TARGETS_REQUIRED" end
  end
  local seen,results={},{}
  local unit=0
  local function checkpoint(n)
   job.scanned=job.scanned+(n or 1)
   unit=unit+(n or 1)
   if unit>=self.recommendationWorkUnit then
    unit=0
    coroutine.yield("YIELD_WORK_BUDGET")
   end
  end
  job.zonesTotal=math.min(#zones,self.maxZonesPerRanking)
  for _,z in ipairs(zones) do
   if job.zonesProcessed>=self.maxZonesPerRanking then break end
   if int(z.mapID) and not seen[z.mapID] then
    seen[z.mapID]=true
    local score=self:Evaluate(z.mapID,focus,needs,layer.layers,nil,checkpoint,targets)
    if score and score.score>0 and score.eligibleCells>0 and
        (focus=="MATERIALS" and score.materialReferenceCount>=2 or
         focus=="SKILL" and score.skillReferenceCount>=2 or
         focus=="BALANCED" and math.max(score.skillReferenceCount,score.materialReferenceCount)>=2) then
      score.name=z.name;results[#results+1]=score
    end
    job.zonesProcessed=job.zonesProcessed+1
    checkpoint(1)
   end
  end
  table.sort(results,function(a,b)
   if a.score~=b.score then return a.score>b.score end
   if a.eligibleCells~=b.eligibleCells then return a.eligibleCells>b.eligibleCells end
   return a.mapID<b.mapID
  end)
  local best=results[1]
  if not best or best.score==0 then
   return nil,"NO_SUITABLE_REFERENCE_ZONE"
  end
  return best,"ADVISORY_ONLY"
 end)
 return true,"GENERATING"
end
function Engine:TickRecommendation()
 local job=self._recommendJob
 if not job then return self:GetRecommendationStatus() end
 local shared=JLP:GetModule("GatheringSharedMapState")
 local snapshot=shared and shared:GetSnapshot()
  if not snapshot or snapshot.selectedMapID~=job.originalMap or
   snapshot.mode~="SMART_PROFESSION" or snapshot.focus~=job.focus or
   (job.materialToken and job.materialToken~=(shared:GetRouteContextKey(job.originalMap or job.originalCurrentMap) or "")) then
  self:CancelRecommendation("STATE_CHANGED")
  return "CANCELLED"
 end
 local ok,result,reason=coroutine.resume(job.co)
 if not ok then
  self:CancelRecommendation("RECOMMENDATION_ERROR")
  if type(job.onComplete)=="function" then pcall(job.onComplete,nil,"RECOMMENDATION_ERROR") end
  return "RECOMMENDATION_ERROR"
 end
 if coroutine.status(job.co)=="dead" then
  self._recommendJob=nil
  self._recommendStatus=result and "READY" or (reason or "NO_SUITABLE_REFERENCE_ZONE")
  if type(job.onComplete)=="function" then
   job.onComplete(result,reason or self._recommendStatus)
  end
 end
 return self:GetRecommendationStatus()
end

JLP:RegisterModule("GatheringZoneSuitability",Engine)
