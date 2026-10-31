local _, JLP = ...
-- JLP-owned per-character observation history. Reference data remain immutable.
-- The records represent successful player interactions near nodes, not live spawns.
local Store={contract="jlp-gathering-observations-v1",schema=1,nativeDispatchAllowed=false,
    maxVerified=1800,maxUnresolved=120,matchRadius=0.012,ambiguityMargin=0.002}
local function coords(x,y)
    return type(x)=="number" and type(y)=="number" and x==x and y==y and x>=0 and x<=1 and y>=0 and y<=1
end
local function validKey(s) return type(s)=="string" and #s<=80 and s:match("^[A-Z0-9_]+$")~=nil end
local function identity(prof,resource,mapID,x,y)
    local reference=JLP:GetModule("GatheringReferenceIdentity")
    return reference and reference:FromFields(prof,resource,mapID,x,y)
end
function Store:GetBucket()
    local shared=JLP:GetModule("GatheringSharedMapState")
    if not shared or type(shared.GetCharacterState)~="function" then return nil,"GATHERING_STATE_NOT_READY" end
    local g,reason=shared:GetCharacterState()
    if type(g)~="table" then return nil,reason or "GATHERING_STATE_NOT_READY" end
    if type(g.schema)=="number" and g.schema>1 then return nil,"FUTURE_GATHERING_SCHEMA" end
    if type(g.observations)=="table" and type(g.observations.schema)=="number" and g.observations.schema>1 then
        return nil,"FUTURE_OBSERVATION_SCHEMA"
    end
    if type(g.observations)~="table" or g.observations.schema~=1 then
        g.observations={schema=1,revision=0,verified={},unresolved={}}
    end
    local b=g.observations
    b.verified=type(b.verified)=="table" and b.verified or {}
    b.unresolved=type(b.unresolved)=="table" and b.unresolved or {}
    return b
end
function Store:GetRevision()
    local b=self:GetBucket()
    return b and (tonumber(b.revision) or 0) or 0
end
function Store:FindReference(prof,resource,mapID,x,y)
    local registry=JLP:GetModule("GatheringDataRegistry")
    local snapshot=registry and registry:GetZoneSnapshot(mapID,prof)
    local near={}
    for _,r in ipairs(snapshot and snapshot.references or {}) do
        if r.resourceKey==resource and r.geometryType=="POINT" then
            local d=math.sqrt((r.x-x)^2+(r.y-y)^2)
            if d<=self.matchRadius then near[#near+1]={r=r,d=d} end
        end
    end
    table.sort(near,function(a,b) return a.d<b.d end)
    if #near==0 then return nil,"NO_NEAR_REFERENCE" end
    if #near>1 and near[2].d-near[1].d<self.ambiguityMargin then
        return nil,"AMBIGUOUS_NEAR_REFERENCES"
    end
    local r=near[1].r
    return identity(prof,resource,mapID,r.x,r.y),"MATCHED_REFERENCE"
end
function Store:Record(record)
    if type(record)~="table" or record.evidenceKind~="CAST_SUCCESS_AND_LOOT_OPENED" or
       record.castSucceeded~=true or record.lootOpened~=true then return false,"EVIDENCE_INSUFFICIENT" end
    if record.professionKey~="HERBALISM" and record.professionKey~="MINING" then return false,"PROFESSION_INVALID" end
    if not validKey(record.resourceKey) or type(record.mapID)~="number" or record.mapID<1 or
        record.mapID~=math.floor(record.mapID) or not coords(record.x,record.y) then return false,"DATA_INVALID" end
    local b,err=self:GetBucket();if not b then return false,err end
    local matched,matchStatus=self:FindReference(record.professionKey,record.resourceKey,record.mapID,record.x,record.y)
    if matchStatus=="AMBIGUOUS_NEAR_REFERENCES" then
        self:RecordUnresolved({professionKey=record.professionKey,resourceKey=record.resourceKey,mapID=record.mapID,
            x=record.x,y=record.y,reason=matchStatus,observedAt=record.observedAt})
        return false,matchStatus
    end
    local id=matched or identity(record.professionKey,record.resourceKey,record.mapID,record.x,record.y)
    if not id then return false,"RESOURCE_IDENTITY_UNAVAILABLE" end
    local found
    for _,r in ipairs(b.verified) do if r.id==id then found=r;break end end
    if not found then
        found={id=id,professionKey=record.professionKey,resourceKey=record.resourceKey,
            mapID=record.mapID,x=record.x,y=record.y,matchedReferenceID=matched,
            outcome="PERSONALLY_OBSERVED",count=0}
        b.verified[#b.verified+1]=found
        if #b.verified>self.maxVerified then table.remove(b.verified,1) end
    end
    found.count=math.min(999999,(tonumber(found.count) or 0)+1)
    found.observedAt=tonumber(record.observedAt) or (type(time)=="function" and time() or 0)
    if type(UnitGUID)=="function" then
        local ok,guid=pcall(UnitGUID,"player")
        if ok and type(guid)=="string" then found.observerCharacter=guid end
    end
    if type(GetRealmName)=="function" then
        local ok,realm=pcall(GetRealmName)
        if ok and type(realm)=="string" then found.observerRealm=realm end
    end
    local buildInfo=JLP:GetModule("ClientBuildInfo")
    found.clientBuild=buildInfo and buildInfo:GetBuildNumber() or nil
    found.evidenceKind="CAST_SUCCESS_AND_LOOT_OPENED"
    found.matchStatus=matchStatus
    b.revision=(tonumber(b.revision) or 0)+1
    if JLP.EventBus then JLP.EventBus:Emit("GATHERING_OBSERVATION_UPDATED",record.mapID) end
    return true,matchStatus
end
-- A stop is a historical place where THIS character skinned a creature and
-- observed this item. It is not a spawn pin, drop table, guaranteed yield or
-- inventory transaction. Build provenance is retained, never a build lock.
function Store:RecordSkinningLoot(r)
    if type(r)~="table" or r.castSucceeded~=true or r.lootSourceMatched~=true or
       type(r.castGUID)~="string" or #r.castGUID>160 or
       type(r.targetGUID)~="string" or not r.targetGUID:match("^Creature%-") or
       type(r.itemID)~="number" or r.itemID<1 or r.itemID~=math.floor(r.itemID) or
       type(r.quantity)~="number" or r.quantity<=0 or r.quantity~=math.floor(r.quantity) or
       type(r.mapID)~="number" or r.mapID<1 or r.mapID~=math.floor(r.mapID) or
       not coords(r.x,r.y) then return false,"SKINNING_EVIDENCE_INSUFFICIENT" end
    local b,why=self:GetBucket();if not b then return false,why end
    b.skinning=type(b.skinning)=="table" and b.skinning or {}
    b.skinningReceipts=type(b.skinningReceipts)=="table" and b.skinningReceipts or {}
    local receipt=r.castGUID..":"..r.itemID
    for _,value in ipairs(b.skinningReceipts) do if value==receipt then return false,"DUPLICATE_RECEIPT" end end
    local shared=JLP:GetModule("GatheringSharedMapState")
    local _,guid=shared:GetCharacterKey()
    if not guid then return false,"CHARACTER_UNKNOWN" end
    local mobID=tonumber(r.targetGUID:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not mobID or type(r.mobLevel)~="number" or r.mobLevel<1 or r.mobLevel>100 then return false,"MOB_ID_OR_LEVEL_UNKNOWN" end
    local id=string.format("SKIN:%d:%d:%d:%d:%d",r.itemID,mobID,r.mapID,math.floor(r.x*10000),math.floor(r.y*10000))
    local found
    for _,row in ipairs(b.skinning) do if row.id==id then found=row;break end end
    if not found then found={id=id,count=0};b.skinning[#b.skinning+1]=found end
    found.itemID=r.itemID;found.mobID=mobID;found.mobLevel=r.mobLevel
    found.mapID=r.mapID;found.x=r.x;found.y=r.y;found.observerCharacter=guid
    found.observedAt=r.observedAt;found.lastObservedQuantity=r.quantity
    found.count=math.min(999999,found.count+1)
    found.evidenceKind="SKINNING_CAST_AND_EXACT_LOOT_SOURCE"
    local build=JLP:GetModule("ClientBuildInfo")
    found.clientBuild=build and build:GetBuildNumber() or nil
    b.skinningReceipts[#b.skinningReceipts+1]=receipt
    if #b.skinningReceipts>self.maxVerified then table.remove(b.skinningReceipts,1) end
    if #b.skinning>self.maxVerified then table.remove(b.skinning,1) end
    b.revision=(tonumber(b.revision) or 0)+1
    if JLP.EventBus then JLP.EventBus:Emit("GATHERING_OBSERVATION_UPDATED",r.mapID) end
    return true,"PERSONAL_HISTORICAL_STOP_NOT_SPAWN_OR_INVENTORY"
end
function Store:GetSkinningSupplies(itemID)
    local b=self:GetBucket();local out={}
    if not b then return out end
    local shared=JLP:GetModule("GatheringSharedMapState")
    local _,guid=shared:GetCharacterKey()
    for _,r in ipairs(b.skinning or {}) do
        if r.observerCharacter==guid and r.itemID==itemID and coords(r.x,r.y) and
           r.evidenceKind=="SKINNING_CAST_AND_EXACT_LOOT_SOURCE" then
            local copy={};for k,v in pairs(r) do if type(v)~="table" then copy[k]=v end end
            copy.scope="PERSONAL_HISTORICAL_SKINNING_STOP";copy.guaranteed=false
            out[#out+1]=copy
        end
    end
    table.sort(out,function(a,b)return a.id<b.id end)
    return out
end
-- Node-object receipts differ from creature/corpse receipts. Temporal/spatial
-- correlation plus the actual GameObject loot source is retained explicitly;
-- this does not claim a target GUID was available at UNIT_SPELLCAST_SENT.
function Store:RecordNodeLoot(prof,r)
 if prof~="MINING"and prof~="HERBALISM"then return false,"PROFESSION_INVALID"end
 if type(r)~="table"or r.castSucceeded~=true or r.lootSourceMatched~=true or
  type(r.castGUID)~="string"or #r.castGUID>160 or type(r.objectGUID)~="string"or
  not r.objectGUID:match("^GameObject%-")or type(r.itemID)~="number"or r.itemID<1 or r.itemID>=math.huge or r.itemID~=math.floor(r.itemID)or
  type(r.quantity)~="number"or r.quantity<1 or r.quantity>=math.huge or r.quantity~=math.floor(r.quantity)or
  not coords(r.x,r.y)or type(r.mapID)~="number"or r.mapID<1 or r.mapID~=math.floor(r.mapID)then return false,"MINING_EVIDENCE_INSUFFICIENT"end
 local objectID=tonumber(r.objectGUID:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
 local guide=JLP:GetModule(prof=="MINING"and "ForeverMiningNodeProgression210"or "ForeverHerbalismProgression209")
 local node=guide and guide:GetObjectContract(objectID)
 if not node or node.resourceKey~=r.resourceKey then return false,"OBJECT_IDENTITY_UNQUALIFIED"end
 local matched=false;for _,id in ipairs(node.itemIDs or {})do if id==r.itemID then matched=true;break end end
 if not matched then return false,"ITEM_OBJECT_RELATION_UNQUALIFIED"end
 local b,why=self:GetBucket();if not b then return false,why end
 local historyKey=prof=="MINING"and "mining"or "herbalism"
 local receiptKey=historyKey.."Receipts";b[historyKey]=b[historyKey]or {};b[receiptKey]=b[receiptKey]or {}
 local history,receipts=b[historyKey],b[receiptKey]
 local receipt=r.castGUID..":"..r.objectGUID..":"..r.itemID
 for _,id in ipairs(receipts)do if id==receipt then return false,"DUPLICATE_RECEIPT"end end
 local shared=JLP:GetModule("GatheringSharedMapState");local _,guid=shared:GetCharacterKey()
 if not guid then return false,"CHARACTER_UNKNOWN"end
 local id=string.format((prof=="MINING"and "MINED:%d:%d:%d:%d:%d"or "HERBED:%d:%d:%d:%d:%d"),r.itemID,objectID,r.mapID,math.floor(r.x*10000),math.floor(r.y*10000))
 local row
 for _,value in ipairs(history)do if value.id==id then row=value;break end end
 if not row then row={id=id,count=0};history[#history+1]=row end
 row.itemID=r.itemID;row.objectID=objectID;row.resourceKey=node.resourceKey;row.objectGUID=r.objectGUID
 row.mapID=r.mapID;row.x=r.x;row.y=r.y;row.observerCharacter=guid
 row.observedAt=r.observedAt;row.lastObservedQuantity=r.quantity;row.count=math.min(999999,row.count+1)
 row.evidenceKind=prof.."_CAST_AND_OBJECT_LOOT_SOURCE_TEMPORAL_SPATIAL";row.targetGUIDCapturedAtCast=false
 local build=JLP:GetModule("ClientBuildInfo");row.clientBuild=build and build:GetBuildNumber()or nil
 receipts[#receipts+1]=receipt
 if #receipts>self.maxVerified then table.remove(receipts,1)end
 if #history>self.maxVerified then table.remove(history,1)end
 b.revision=(tonumber(b.revision)or 0)+1
 return true,"PERSONAL_MINING_HISTORY_NOT_SPAWN_OR_INVENTORY"
end
function Store:GetNodeSupplies(prof,itemID)
 if prof~="MINING"and prof~="HERBALISM"then return {}end
 local b=self:GetBucket();local out={};if not b then return out end
 local shared=JLP:GetModule("GatheringSharedMapState");local _,guid=shared:GetCharacterKey()
 for _,r in ipairs(b[prof=="MINING"and "mining"or "herbalism"]or {})do
  if r.observerCharacter==guid and r.itemID==itemID and r.evidenceKind==prof.."_CAST_AND_OBJECT_LOOT_SOURCE_TEMPORAL_SPATIAL"then
   local value={};for k,v in pairs(r)do if type(v)~="table"then value[k]=v end end
   value.scope="PERSONAL_"..prof.."_OBJECT_LOOT_HISTORY";value.notLiveSpawn=true;out[#out+1]=value
  end
 end
 table.sort(out,function(a,b)return a.id<b.id end);return out
end
function Store:RecordMiningLoot(r)return self:RecordNodeLoot("MINING",r)end
function Store:GetMiningSupplies(itemID)return self:GetNodeSupplies("MINING",itemID)end
function Store:RecordHerbalismLoot(r)return self:RecordNodeLoot("HERBALISM",r)end
function Store:RecordUnresolved(record)
    if type(record)~="table" then return false,"INVALID_RECORD" end
    local b,err=self:GetBucket();if not b then return false,err end
    local x=coords(record.x,record.y) and record.x or nil
    local y=coords(record.x,record.y) and record.y or nil
    local row={professionKey=record.professionKey=="SKINNING" and "SKINNING" or record.professionKey=="MINING" and "MINING" or "HERBALISM",
        resourceKey=validKey(record.resourceKey) and record.resourceKey or "UNKNOWN",
        mapID=type(record.mapID)=="number" and record.mapID or nil,
        x=x,y=y,observedAt=tonumber(record.observedAt) or (type(time)=="function" and time() or 0),
        outcome="UNRESOLVED_OBSERVATION",reason=tostring(record.reason or "INSUFFICIENT_EVIDENCE"):sub(1,80)}
    local shared=JLP:GetModule("GatheringSharedMapState")
    local _,guid=shared:GetCharacterKey()
    row.observerCharacter=guid
    if type(GetRealmName)=="function" then
        local ok,realm=pcall(GetRealmName)
        if ok and type(realm)=="string" then row.observerRealm=realm end
    end
    local build=JLP:GetModule("ClientBuildInfo")
    row.clientBuild=build and build:GetBuildNumber() or nil
    b.unresolved[#b.unresolved+1]=row
    if #b.unresolved>self.maxUnresolved then table.remove(b.unresolved,1) end
    b.revision=(tonumber(b.revision) or 0)+1
    return true
end
function Store:GetZoneSnapshot(mapID,prof)
    local b=self:GetBucket()
    local snapshot={mapID=mapID,verified={},unresolvedCount=0,revision=self:GetRevision(),nativeDispatchAllowed=false}
    if not b then return snapshot end
    local shared=JLP:GetModule("GatheringSharedMapState")
    local _,guid=shared:GetCharacterKey()
    for _,r in ipairs(b.verified) do
        if r.observerCharacter==guid and r.mapID==mapID and (not prof or r.professionKey==prof) and coords(r.x,r.y) and validKey(r.resourceKey) then
            snapshot.verified[#snapshot.verified+1]={id=r.id,professionKey=r.professionKey,resourceKey=r.resourceKey,
                mapID=r.mapID,x=r.x,y=r.y,matchedReferenceID=r.matchedReferenceID,observedAt=r.observedAt,
                observerCharacter=r.observerCharacter,observerRealm=r.observerRealm,clientBuild=r.clientBuild,
                count=r.count,evidenceKind=r.evidenceKind,matchStatus=r.matchStatus}
        end
    end
    for _,r in ipairs(b.unresolved) do if r.observerCharacter==guid and r.mapID==mapID and (not prof or r.professionKey==prof) then
        snapshot.unresolvedCount=snapshot.unresolvedCount+1 end end
    return snapshot
end
JLP:RegisterModule("GatheringObservationStore",Store)
