local _, JLP = ...
local T = JLP._integratedTravel
local C=T.Contract
local Network={}
Network.__index=Network
local MODES={WALK=true,BOAT=true,ZEPPELIN=true,FLIGHT=true,PORTAL=true,TRAM=true,ZONE_GATE=true,OTHER=true}
function Network.New()
    return setmetatable({nodes={},edges={},edgeIds={},generation=0,limits={nodes=600,edges=1600}},Network)
end
function Network:RegisterNode(item)
    if type(item)~='table' or not C.validId(item.id) then return false,'INVALID_NODE_ID' end
    if self.nodes[item.id] then return false,'DUPLICATE_NODE' end
    local count=0;for _ in pairs(self.nodes) do count=count+1 end
    if count>=self.limits.nodes then return false,'NODE_LIMIT' end
    local p,reason=C.point(item)
    if not p then return false,reason end
    p.id=item.id
    p.kind=tostring(item.kind or 'WAYPOINT')
    p.label=(item.label and tostring(item.label)) or item.id
    p.placeName=type(item.placeName)=="string" and item.placeName:sub(1,130) or nil
    p.provenance=item.provenance and tostring(item.provenance) or 'UNVERIFIED'
    p.confirmed=item.confirmed==true
    p.clientVerified=item.clientVerified==true
    p.ownerAuthorized=item.ownerAuthorized==true
    self.nodes[p.id]=p
    self.generation=self.generation+1
    return true
end
function Network:RegisterEdge(item)
    if type(item)~='table' or not C.validId(item.id) then return false,'INVALID_EDGE_ID' end
    if self.edgeIds[item.id] then return false,'DUPLICATE_EDGE' end
    if #self.edges>=self.limits.edges then return false,'EDGE_LIMIT' end
    if not self.nodes[item.from] or not self.nodes[item.to] then return false,'UNKNOWN_ENDPOINT' end
    if not MODES[item.mode] then return false,'INVALID_MODE' end
    if not C.finite(item.costUnits) or item.costUnits<=0 or item.costUnits>100000 then return false,'INVALID_COST' end
    local from,to=self.nodes[item.from],self.nodes[item.to]
    if item.mode=='WALK' and from.mapID~=to.mapID then return false,'CROSS_MAP_WALK_FORBIDDEN' end
    if item.mode~='WALK' and (type(item.provenance)~='string' or #item.provenance<5) then
        return false,'MISSING_PROVENANCE'
    end
    local r={id=item.id,from=item.from,to=item.to,mode=item.mode,costUnits=item.costUnits,
        status=item.status=='verified' and 'verified' or 'draft',
        faction=item.faction or 'NEUTRAL',requiresUnlock=(item.mode=='FLIGHT' or item.requiresUnlock==true),
        minLevel=item.minLevel,requiresClass=item.requiresClass,provenance=item.provenance or 'UNVERIFIED',
        note=tostring(item.note or ''),mustConfirm=item.mustConfirm~=false,clientVerified=item.clientVerified==true,
        ownerAuthorized=item.ownerAuthorized==true}
    if r.faction~='HORDE' and r.faction~='ALLIANCE' and r.faction~='NEUTRAL' then return false,'INVALID_FACTION' end
    if r.minLevel~=nil and (not C.finite(r.minLevel) or r.minLevel<1) then return false,'INVALID_LEVEL' end
    if r.requiresClass~=nil and r.requiresClass~='DRUID' then return false,'INVALID_CLASS_REQUIREMENT' end
    if from.mapID~=to.mapID and item.mode=='WALK' then return false,'INVALID_TRANSITION' end
    self.edgeIds[r.id]=true
    self.edges[#self.edges+1]=r
    self.generation=self.generation+1
    return true
end
function Network:RegisterDataset(dataset)
    if type(dataset)~='table' or dataset.contract~='juzt-travel-dataset-v1' then return false,'DATASET_CONTRACT_MISMATCH' end
    -- Atomic staging: failure cannot leave partially written topology.
    local staged=Network.New()
    for id,node in pairs(self.nodes) do staged.nodes[id]=C.shallowCopy(node) end
    for i,e in ipairs(self.edges) do staged.edges[i]=C.shallowCopy(e);staged.edgeIds[e.id]=true end
    staged.generation=self.generation
    for _,node in ipairs(dataset.nodes or {}) do
        local ok,why=staged:RegisterNode(node);if not ok then return false,why end
    end
    for _,edge in ipairs(dataset.edges or {}) do
        local ok,why=staged:RegisterEdge(edge);if not ok then return false,why end
    end
    self.nodes,self.edges,self.edgeIds,self.generation=staged.nodes,staged.edges,staged.edgeIds,staged.generation
    return true
end
function Network:CanTraverse(e,context)
    context=context or {}
    -- User-selected routing policy: all registered transport edges can be considered.
    -- Evidence/status is diagnostic, never an eligibility gate.
    if e.faction~='NEUTRAL' and context.faction~=e.faction then return false,'FACTION_RESTRICTED' end
    if e.minLevel and (not C.finite(context.level) or context.level<e.minLevel) then return false,'LEVEL_REQUIREMENT' end
    if e.requiresClass and context.classToken~=e.requiresClass then return false,'CLASS_RESTRICTED' end
    -- A missing taxi survey is UNKNOWN, not proof that a connection is locked.
    -- Keep it in advisory route planning; actual flight selection stays manual.
    -- An explicit client-observed lock is still a real access restriction.
    if e.requiresUnlock and type(context.unlocked)=='table' and context.unlocked[e.id]==false then
        return false,'FLIGHT_CONFIRMED_LOCKED'
    end
    if context.blocked and context.blocked[e.id] then return false,'EDGE_BLOCKED' end
    return true
end
T.Network = Network
