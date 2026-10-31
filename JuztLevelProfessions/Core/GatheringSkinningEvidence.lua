local _, JLP = ...
-- Alpha161: a source-gated schema for future Skinning farming AREAS.
-- No source-qualified mob/geometry records are currently bundled.
local M={contract="jlp-skinning-area-evidence-v1",nativeDispatchAllowed=false,geometryType="GRID_AREA"}
local function positive(n) return type(n)=="number" and n>0 and n==math.floor(n) end
function M:Validate(record)
    if type(record)~="table" then return false,"RECORD_REQUIRED" end
    if not positive(record.mapID) or not positive(record.mobID) or
        not positive(record.outputItemID) then return false,"IDENTITY_UNVERIFIED" end
    if record.geometryType~="GRID_AREA" then return false,"AREA_GEOMETRY_REQUIRED" end
    if type(record.x)~="number" or type(record.y)~="number" or
        type(record.width)~="number" or type(record.height)~="number" or
        record.x<0 or record.y<0 or record.width<=0 or record.height<=0 or
        record.x+record.width>1.000001 or record.y+record.height>1.000001 then
        return false,"AREA_BOUNDS_INVALID" end
    if type(record.sourceRef)~="string" or #record.sourceRef<8 or
        type(record.buildQualifier)~="string" or #record.buildQualifier<3 or
        record.sourceVerified~=true then return false,"SOURCE_EVIDENCE_REQUIRED" end
    if record.notLiveSpawn~=true then return false,"HISTORICAL_ONLY_REQUIRED" end
    return true,"SOURCE_QUALIFIED_AREA"
end
function M:GetEvidenceSummary()
    local data=JLP.data and JLP.data.skinningSourceEvidence
    local sourceCount=0
    for _,entry in ipairs(data and data.facts or {}) do
        if type(entry.sourceURL)=="string" and entry.sourceURL:match("^https://www%.wowhead%.com/forever/") then
            sourceCount=sourceCount+1
        end
    end
    return {status="NONSPATIAL_SOURCES_ONLY",sourceCount=sourceCount,
        confirmedAreaCount=0,verifiedMobOutputPairs=0,
        mobOutputAssociation="UNRESOLVED",geometryStatus="NO_SOURCE_QUALIFIED_GEOMETRY",
        buildQualifier=data and data.buildQualifier or "UNKNOWN",notLiveSpawn=true,
        nativeDispatchAllowed=false}
end
function M:GetMapSnapshot(mapID)
    if not positive(mapID) then return nil,"MAP_ID_INVALID" end
    local source=JLP.data and JLP.data.skinningFarmingAreaEvidence
    local rows=source and source.maps and source.maps[mapID] or nil
    local result={mapID=mapID,status="NO_REFERENCE_COVERAGE",areas={},rejected=0,
        geometryType="GRID_AREA",notLiveSpawn=true,nativeDispatchAllowed=false,
        sourceEvidence=self:GetEvidenceSummary()}
    if type(rows)~="table" then return result end
    for _,r in ipairs(rows) do
        local ok=self:Validate(r)
        if ok and r.mapID==mapID then result.areas[#result.areas+1]=r else result.rejected=result.rejected+1 end
    end
    if #result.areas>0 then result.status="HISTORICAL_SOURCE_QUALIFIED_AREAS" end
    return result
end
JLP:RegisterModule("GatheringSkinningEvidence",M)
