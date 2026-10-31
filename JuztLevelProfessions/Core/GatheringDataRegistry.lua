local _, JLP = ...
-- Shared read-only gathering reference authority with zone-scoped lazy decode.
-- Historical reference locations are never asserted to be active/live spawns.
local Registry={contract="gathering-data-registry-v1",nativeDispatchAllowed=false,
    sourceCoverage="NO_REFERENCE_COVERAGE",maxRecordsPerImport=50000}
local allowed={HERBALISM=true,MINING=true,FISHING=true,SKINNING=true}
local geometries={POINT=true,CIRCLE=true,POLYGON=true,AREA=true}
-- Canonical source order and shared snapshot projection; neither grants route authority.
-- The two built-in sources account for the large majority of reference rows.
local SOURCE_GATHERLITE="GATHERLITE_8_1_12"
local SOURCE_GATHERSKILL="GATHERSKILLMAP_1_3_0"
local REFERENCE_SOURCES={SOURCE_GATHERLITE,SOURCE_GATHERSKILL}
local function copySortedSources(sources)
    local hasGatherlite,hasGatherskill=false,false
    local others
    for source in pairs(sources or {}) do
        if source==SOURCE_GATHERLITE then hasGatherlite=true
        elseif source==SOURCE_GATHERSKILL then hasGatherskill=true
        else
            others=others or {}
            others[#others+1]=source
        end
    end
    if not others then
        if hasGatherlite and hasGatherskill then return {SOURCE_GATHERLITE,SOURCE_GATHERSKILL} end
        if hasGatherlite then return {SOURCE_GATHERLITE} end
        if hasGatherskill then return {SOURCE_GATHERSKILL} end
        return {}
    end
    if hasGatherlite then others[#others+1]=SOURCE_GATHERLITE end
    if hasGatherskill then others[#others+1]=SOURCE_GATHERSKILL end
    table.sort(others)
    return others
end
local function copySnapshotReference(r)
    return {professionKey=r.professionKey,resourceKey=r.resourceKey,
        objectID=r.objectID,uiMapID=r.uiMapID,instanceID=r.instanceID,
        x=r.x,y=r.y,geometryType=r.geometryType,requiredSkill=r.requiredSkill,
        sourceConfidence=r.sourceConfidence,sources=copySortedSources(r.sources),
        personallyObserved=false}
end
local function integer(v)
    return type(v)=="number" and v==v and v~=math.huge and v>=1 and v==math.floor(v)
end
local function coordinate(v)
    return type(v)=="number" and v==v and v~=math.huge and v>=0 and v<=1
end
local function keyFor(r)
    -- Quantize spatial equality to 1/10000th of a normalized map; identity
    -- ALWAYS includes profession, resource, map and instance, not display text.
    return table.concat({r.professionKey,r.resourceKey,r.uiMapID,r.instanceID or 0,
        math.floor(r.x*10000+0.5),math.floor(r.y*10000+0.5)},":")
end
function Registry:ValidateRecord(r)
    if type(r)~="table" then return nil,"RECORD_INVALID" end
    if not allowed[r.professionKey] then return nil,"PROFESSION_INVALID" end
    if type(r.resourceKey)~="string" or not r.resourceKey:match("^[A-Z0-9_]+$") or #r.resourceKey>80 then
        return nil,"RESOURCE_KEY_INVALID" end
    if not integer(r.uiMapID) then return nil,"MAP_ID_INVALID" end
    if r.instanceID~=nil and (type(r.instanceID)~="number" or r.instanceID<0 or r.instanceID~=math.floor(r.instanceID)) then
        return nil,"INSTANCE_ID_INVALID" end
    if not geometries[r.geometryType] then return nil,"GEOMETRY_INVALID" end
    -- No false pool/node precision: non-POINT geometry needs a separate area geometry contract.
    if r.geometryType~="POINT" then return nil,"AREA_GEOMETRY_NOT_IMPLEMENTED" end
    if r.professionKey=="SKINNING" then return nil,"SKINNING_AREA_REQUIRED" end
    -- Fishing catch geography is an AREA until an actual named pool object
    -- has been independently verified. Source permission alone is insufficient.
    if r.professionKey=="FISHING" and (r.verifiedPool~=true or not integer(r.objectID)) then
        return nil,"VERIFIED_POOL_IDENTITY_REQUIRED" end
    if not coordinate(r.x) or not coordinate(r.y) then return nil,"COORDINATES_INVALID" end
    if r.objectID~=nil and not integer(r.objectID) then return nil,"OBJECT_ID_INVALID" end
    if r.requiredSkill~=nil and (type(r.requiredSkill)~="number" or r.requiredSkill<0 or
        r.requiredSkill~=math.floor(r.requiredSkill)) then return nil,"SKILL_REQUIREMENT_INVALID" end
    return keyFor(r)
end
function Registry:Import(source,records)
    -- Fixture/build imports require explicit approved source manifest; deny by
    -- default, and never elevate a historical coordinate into a live-spawn claim.
    local result={accepted=0,duplicate=0,rejected=0,reasons={},status="SOURCE_NOT_APPROVED"}
    local manifest=JLP.data and JLP.data.gatheringSourceManifest
    local authority=manifest and manifest.sources and source and manifest.sources[source]
    if type(records)~="table" then result.rejected=1;result.reasons.RECORDS_INVALID=1;return result end
    if not authority or authority.redistributionApproved~=true or authority.buildVerified~=true or
        authority.licenseVerified~=true then
        result.rejected=#records; result.reasons.SOURCE_NOT_APPROVED=#records
        return result
    end
    if #records>self.maxRecordsPerImport then
        result.rejected=#records;result.reasons.IMPORT_LIMIT=#records;result.status="IMPORT_LIMIT";return result
    end
    self._records=self._records or {}; self._spatial=self._spatial or {}
    result.status="IMPORTED_READ_ONLY"
    for _,r in ipairs(records) do
        local k,reason=self:ValidateRecord(r)
        if not k then
            result.rejected=result.rejected+1;result.reasons[reason]=(result.reasons[reason] or 0)+1
        else
            local existing=self._spatial[k]
            if existing then
                result.duplicate=result.duplicate+1
                existing.sources[source]=true
            else
                -- Deliberate field projection: never store references to mutable input rows.
                local rec={professionKey=r.professionKey,resourceKey=r.resourceKey,uiMapID=r.uiMapID,
                    instanceID=r.instanceID,x=r.x,y=r.y,geometryType=r.geometryType,
                    objectID=r.objectID,requiredSkill=r.requiredSkill,sourceConfidence=r.sourceConfidence or "HISTORICAL",
                    sourceBuild=authority.build, sources={[source]=true},personallyObserved=false}
                self._spatial[k]=rec
                local zone=self._records[r.uiMapID] or {}
                self._records[r.uiMapID]=zone
                zone[#zone+1]=rec
                result.accepted=result.accepted+1
            end
        end
    end
    self._mutationEpoch=(self._mutationEpoch or 0)+1
    return result
end
-- Offline built source blobs remain encoded; only the selected map gets decoded.
-- Loaded records are memory-only and excluded from SavedVariables.
function Registry:EnsureReferenceMap(mapID)
    if not integer(mapID) then return nil,"MAP_ID_INVALID" end
    if self._referenceAutoEnabled==false then return nil,"DISABLED_FOR_FIXTURE" end
    self._loadedMaps=self._loadedMaps or {}
    if self._loadedMaps[mapID] then return self._loadedMaps[mapID] end
    local pack=JLP.data and JLP.data.gatheringReferencePacked
    local bucket=pack and pack.maps and pack.maps[mapID]
    if type(bucket)~="table" then
        local absent={status="NO_REFERENCE_COVERAGE",accepted=0,rejected=0,duplicate=0}
        self._loadedMaps[mapID]=absent
        return absent
    end
    local batches={}
    local malformed=0
    for _,entry in ipairs(bucket) do
        local source,prof,key,objectID,skill,encoded=entry[1],entry[2],entry[3],entry[4],entry[5],entry[6]
        if type(encoded)=="string" and #encoded%6==0 and #encoded<=60000 and
            type(source)=="string" and type(key)=="string" then
            local batch=batches[source] or {}
            batches[source]=batch
            for i=1,#encoded,6 do
                local x=tonumber(encoded:sub(i,i+2))
                local y=tonumber(encoded:sub(i+3,i+5))
                if x and y and x<=1000 and y<=1000 then
                    batch[#batch+1]={professionKey=prof,resourceKey=key,objectID=objectID,
                        uiMapID=mapID,x=x/1000,y=y/1000,geometryType="POINT",requiredSkill=skill,
                        sourceConfidence="HISTORICAL_REFERENCE"}
                else
                    malformed=malformed+1
                end
            end
        else
            malformed=malformed+1
        end
    end
    local output={status="REFERENCE_ONLY",accepted=0,rejected=malformed,duplicate=0,sources={}}
    -- Stable iteration order makes cross-source provenance aggregation deterministic.
    for _,source in ipairs(REFERENCE_SOURCES) do
        if batches[source] then
            local result=self:Import(source,batches[source])
            output.accepted=output.accepted+result.accepted
            output.rejected=output.rejected+result.rejected
            output.duplicate=output.duplicate+result.duplicate
            output.sources[source]={accepted=result.accepted,rejected=result.rejected,duplicate=result.duplicate}
        end
    end
    if output.accepted==0 and output.duplicate==0 then output.status="NO_REFERENCE_COVERAGE" end
    self._loadedMaps[mapID]=output
    return output
end
-- The optional route checkpoint yields in the caller's coroutine. A staged,
-- map-scoped decode is published atomically: cancellation never leaves partly
-- decoded references in the shared cache, and source metadata is preserved.
function Registry:EnsureReferenceMapBudgeted(mapID,checkpoint)
    if type(checkpoint)~="function" then return self:EnsureReferenceMap(mapID) end
    if not integer(mapID) then return nil,"MAP_ID_INVALID" end
    if self._referenceAutoEnabled==false then return nil,"DISABLED_FOR_FIXTURE" end
    if self._loadedMaps and self._loadedMaps[mapID] then return self._loadedMaps[mapID] end
    local pack=JLP.data and JLP.data.gatheringReferencePacked
    local bucket=pack and pack.maps and pack.maps[mapID]
    if type(bucket)~="table" then return self:EnsureReferenceMap(mapID) end
    local oldEpoch=self._mutationEpoch or 0
    local records,spatial={},{}
    for _,r in ipairs(self._records and self._records[mapID] or {}) do
        local clone={}
        for k,v in pairs(r) do clone[k]=v end
        clone.sources={}
        for source,exists in pairs(r.sources or {}) do clone.sources[source]=exists end
        records[#records+1]=clone;spatial[keyFor(clone)]=clone;checkpoint()
    end
    local result={status="REFERENCE_ONLY",accepted=0,rejected=0,duplicate=0,sources={}}
    local manifest=JLP.data and JLP.data.gatheringSourceManifest
    for _,source in ipairs(REFERENCE_SOURCES) do
        local stats={accepted=0,rejected=0,duplicate=0}
        local authority=manifest and manifest.sources and manifest.sources[source]
        local approved=authority and authority.redistributionApproved==true and
            authority.buildVerified==true and authority.licenseVerified==true
        local count=0
        for _,entry in ipairs(bucket) do
            local encoded=entry[6]
            if entry[1]==source then
                if type(encoded)~="string" or #encoded%6~=0 or #encoded>60000 or
                    type(entry[3])~="string" then
                    stats.rejected=stats.rejected+1
                else
                    for i=1,#encoded,6 do
                        count=count+1;checkpoint()
                        local x=tonumber(encoded:sub(i,i+2));local y=tonumber(encoded:sub(i+3,i+5))
                        if not approved or count>self.maxRecordsPerImport or not x or not y or x>1000 or y>1000 then
                            stats.rejected=stats.rejected+1
                        else
                            local row={professionKey=entry[2],resourceKey=entry[3],objectID=entry[4],
                                uiMapID=mapID,x=x/1000,y=y/1000,geometryType="POINT",requiredSkill=entry[5]}
                            local key=self:ValidateRecord(row)
                            if not key then stats.rejected=stats.rejected+1
                            elseif spatial[key] then
                                stats.duplicate=stats.duplicate+1;spatial[key].sources[source]=true
                            else
                                local record={professionKey=row.professionKey,resourceKey=row.resourceKey,
                                    uiMapID=mapID,x=row.x,y=row.y,geometryType="POINT",
                                    objectID=row.objectID,requiredSkill=row.requiredSkill,
                                    sourceConfidence="HISTORICAL_REFERENCE",sourceBuild=authority.build,
                                    sources={[source]=true},personallyObserved=false}
                                records[#records+1]=record;spatial[key]=record;stats.accepted=stats.accepted+1
                            end
                        end
                    end
                end
            end
            checkpoint()
        end
        result.accepted=result.accepted+stats.accepted
        result.rejected=result.rejected+stats.rejected
        result.duplicate=result.duplicate+stats.duplicate
        if stats.accepted>0 or stats.rejected>0 or stats.duplicate>0 then result.sources[source]=stats end
    end
    if result.accepted==0 and result.duplicate==0 then result.status="NO_REFERENCE_COVERAGE" end
    -- Never publish a spatial index copied before another coroutine committed.
    -- All O(N) copying remains checkpointed off-cache; publication is a short,
    -- non-yielding pointer swap. Import uses _mutationEpoch; staged publishes
    -- use a separate _cacheCommitEpoch, so an Import still aborts the decode
    -- while competing map decodes retry their index copy against the latest
    -- live revision. No readers can observe an incomplete spatial merge.
    while true do
        if (self._mutationEpoch or 0)~=oldEpoch then return nil,"IMPORT_CHANGED_DURING_DECODE" end
        if self._loadedMaps and self._loadedMaps[mapID] then return self._loadedMaps[mapID] end
        local liveRevision=self._cacheCommitEpoch or 0
        local newIndex={}
        for key,value in pairs(self._spatial or {}) do
            newIndex[key]=value
            checkpoint()
        end
        for key,value in pairs(spatial) do
            newIndex[key]=value
            checkpoint()
        end
        -- No checkpoints between this guard and the commit: a cooperative
        -- Lua coroutine cannot interleave another commit in this section.
        if (self._mutationEpoch or 0)~=oldEpoch then return nil,"IMPORT_CHANGED_DURING_DECODE" end
        if self._loadedMaps and self._loadedMaps[mapID] then return self._loadedMaps[mapID] end
        if (self._cacheCommitEpoch or 0)==liveRevision then
            self._records=self._records or {}
            self._loadedMaps=self._loadedMaps or {}
            self._records[mapID]=records
            self._spatial=newIndex
            self._loadedMaps[mapID]=result
            self._cacheCommitEpoch=liveRevision+1
            return result
        end
        -- A different map committed while this worker was yielded. Discard
        -- only the temporary index, not the validated map-scoped stage.
    end
end
-- Bounded, identity-aware cache of immutable historical packed-map summaries.
-- Returned rows are always fresh copies, never aliases into the shared cache;
-- no cache result grants route, spawn, or native execution authority.
local function copyReferenceSummary(src)
    local out={mapID=src.mapID,status=src.status,referenceOnly=true,
        resources={},sourceCounts={},nativeDispatchAllowed=false}
    for _,r in ipairs(src.resources) do
        out.resources[#out.resources+1]={professionKey=r.professionKey,
            resourceKey=r.resourceKey,requiredSkill=r.requiredSkill,
            referenceCount=r.referenceCount}
    end
    for k,v in pairs(src.sourceCounts) do out.sourceCounts[k]=v end
    return out
end
function Registry:InvalidateReferenceSummaryCache()
    self._summaryCache=nil
    self._summaryOrder=nil
end
function Registry:GetZoneResourceSummary(mapID,professionKey)
    if not integer(mapID) then return nil,"MAP_ID_INVALID" end
    if professionKey and not allowed[professionKey] then return nil,"PROFESSION_INVALID" end
    local pack=JLP.data and JLP.data.gatheringReferencePacked
    local bucket=pack and pack.maps and pack.maps[mapID]
    local cache=self._summaryCache
    local cacheKey=tostring(mapID)..":"..tostring(professionKey or "ALL")
    local existing=cache and cache[cacheKey]
    if existing and existing.bucket==bucket and existing.size==(bucket and #bucket or 0) then
        return copyReferenceSummary(existing.summary)
    end
    local out={mapID=mapID,status="NO_REFERENCE_COVERAGE",referenceOnly=true,
        resources={},sourceCounts={},nativeDispatchAllowed=false}
    if type(bucket)~="table" then return out end
    local resourceIndex={}
    for _,entry in ipairs(bucket) do
        local source,prof,key,_,required,encoded=entry[1],entry[2],entry[3],entry[4],entry[5],entry[6]
        if (not professionKey or prof==professionKey) and type(encoded)=="string" then
            local count=math.floor(#encoded/6)
            local id=prof..":"..key
            local rec=resourceIndex[id]
            if not rec then
                rec={professionKey=prof,resourceKey=key,requiredSkill=required,referenceCount=0}
                resourceIndex[id]=rec;out.resources[#out.resources+1]=rec
            end
            rec.referenceCount=rec.referenceCount+count
            out.sourceCounts[source]=(out.sourceCounts[source] or 0)+count
        end
    end
    if #out.resources>0 then out.status="HISTORICAL_REFERENCES" end
    table.sort(out.resources,function(a,b)
        if a.professionKey==b.professionKey then return a.resourceKey<b.resourceKey end
        return a.professionKey<b.professionKey end)
    -- Up to 24 map/profession combinations are retained; the source blob
    -- remains packed and independently versioned. A replaced map table or
    -- changed table length invalidates its entry; explicit source replacement
    -- should also call InvalidateReferenceSummaryCache().
    cache=cache or {}
    self._summaryCache=cache
    local order=self._summaryOrder or {}
    self._summaryOrder=order
    if existing then
        for i=#order,1,-1 do
            if order[i]==cacheKey then table.remove(order,i);break end
        end
    end
    while #order>=24 do cache[table.remove(order,1)]=nil end
    order[#order+1]=cacheKey
    cache[cacheKey]={bucket=bucket,size=#bucket,summary=out}
    return copyReferenceSummary(out)
end
-- Job-local multi-profession projection. The caller owns these independent
-- read-only-by-contract record COPIES; the registry retains no snapshot alias.
-- Smart/Custom used to scan the entire zone once for EACH eligible profession.
-- A single checkpointed pass preserves the per-profession insertion order,
-- identical sorted sources and one import epoch for the entire job projection.
function Registry:GetZoneBatchSnapshots(mapID,professionKeys,checkpoint)
    if not integer(mapID) then return nil,"MAP_ID_INVALID" end
    if type(professionKeys)~="table" then return nil,"PROFESSIONS_INVALID" end
    local targets,output={},{}
    for _,key in ipairs(professionKeys) do
        if not allowed[key] then return nil,"PROFESSION_INVALID" end
        if not targets[key] then
            targets[key]=true
            output[key]={mapID=mapID,status="NO_REFERENCE_COVERAGE",
                references={},nativeDispatchAllowed=false}
        end
    end
    local loaded,reason
    if type(checkpoint)=="function" then
        loaded,reason=self:EnsureReferenceMapBudgeted(mapID,checkpoint)
    else loaded,reason=self:EnsureReferenceMap(mapID) end
    -- Match GetZoneSnapshot: fixture-disabled map decoding still permits
    -- already imported, read-only rows. Only an epoch-changing decode must
    -- abort and must never publish partially mixed source provenance.
    if not loaded and reason=="IMPORT_CHANGED_DURING_DECODE" then return nil,reason end
    local epoch=self._mutationEpoch or 0
    local zone=self._records and self._records[mapID] or {}
    for _,r in ipairs(zone) do
        if type(checkpoint)=="function" then checkpoint() end
        local snapshot=output[r.professionKey]
        if snapshot then
            snapshot.references[#snapshot.references+1]=copySnapshotReference(r)
            snapshot.status="REFERENCE_ONLY"
        end
    end
    -- Import may occur at ANY yield, including the final checkpoint. Never
    -- return partly old/new provenance after an import/cancelled generation.
    if (self._mutationEpoch or 0)~=epoch then return nil,"IMPORT_CHANGED_DURING_PROJECTION" end
    return output
end
function Registry:GetZoneSnapshot(mapID,professionKey,checkpoint)
    if not integer(mapID) then return nil,"MAP_ID_INVALID" end
    if professionKey~=nil and not allowed[professionKey] then return nil,"PROFESSION_INVALID" end
    if type(checkpoint)=="function" then
        local status,reason=self:EnsureReferenceMapBudgeted(mapID,checkpoint)
        if not status and reason=="IMPORT_CHANGED_DURING_DECODE" then return nil,reason end
    else self:EnsureReferenceMap(mapID) end
    local epoch=self._mutationEpoch or 0
    local zone=self._records and self._records[mapID] or {}
    local snapshot={mapID=mapID,status=#zone>0 and "REFERENCE_ONLY" or "NO_REFERENCE_COVERAGE",
        references={},nativeDispatchAllowed=false}
    for _,r in ipairs(zone) do
        if type(checkpoint)=="function" then checkpoint() end
        if not professionKey or r.professionKey==professionKey then
            snapshot.references[#snapshot.references+1]=copySnapshotReference(r)
        end
    end
    if (self._mutationEpoch or 0)~=epoch then return nil,"IMPORT_CHANGED_DURING_PROJECTION" end
    if #snapshot.references==0 then snapshot.status="NO_REFERENCE_COVERAGE" end
    return snapshot
end
JLP:RegisterModule("GatheringDataRegistry",Registry)
