local _, JLP = ...

-- Alpha95 keeps alpha94's immediate-terminal-predecessor authority while adding
-- strict profession isolation and bounded long-run retention. Full lineage nodes
-- are keyed by profession + session token, so one profession can never collide
-- with or authorize another profession. Older consumed ancestors are compacted
-- into a bounded fail-closed replay filter; head/root/depth/immediate-predecessor
-- authority remains exact and active Auto Route sessions are never persisted.
local ResearchAutoRouteSessionLineage = {
    contract = "production-auto-route-multi-session-lineage-v1",
    nodeContract = "research-auto-route-session-lineage-node-v1",
    predecessorProofContract = "research-auto-route-immediate-predecessor-proof-v1",
    isolationContract = "production-auto-route-multi-profession-isolation-v1",
    retentionContract = "production-auto-route-bounded-lineage-retention-v1",
    compactedReplayContract = "research-auto-route-compacted-token-replay-filter-v1",
    authority = "runtime-only-immediate-terminal-predecessor-lineage-v1",
    automaticResume = false,
    ancestorReuseAllowed = false,
    crossProfessionReuseAllowed = false,
    nativeDispatchAllowed = false,
    persisted = false,
    retainedNodeLimit = 16,
    compactedReplayFilterSlots = 8191,
    compactedReplayFilterHashes = 3,
    serial = 0,
    nodesByToken = {},
    headByProfession = {},
    lastByProfession = {},
    retainedOrderByProfession = {},
    compactedReplayFilterByProfession = {},
    compactionStatsByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function now()
    if type(GetTime) == "function" then local ok,v=pcall(GetTime); if ok and tonumber(v) then return tonumber(v) end end
    if type(time) == "function" then local ok,v=pcall(time); if ok and tonumber(v) then return tonumber(v) end end
    return 0
end

local function hash(parts)
    local value = table.concat(parts or {}, "\31")
    local h = 5381
    for i=1,#value do h=(h*33+string.byte(value,i))%2147483647 end
    return string.format("%08x",h)
end

local function copy(row)
    local out={}
    for k,v in pairs(row or {}) do
        if type(v)=="table" then local nested={}; for nk,nv in pairs(v) do nested[nk]=nv end; out[k]=nested else out[k]=v end
    end
    return out
end

local function sessionTokenOf(session)
    return session and (session.token or session.sessionToken) or nil
end

local function storageKey(professionKey,sessionToken)
    professionKey=normalizeKey(professionKey)
    sessionToken=tostring(sessionToken or "")
    if not professionKey or sessionToken=="" then return nil end
    return professionKey.."\31"..sessionToken
end

function ResearchAutoRouteSessionLineage:_GetRaw(professionKey,sessionToken)
    local key=storageKey(professionKey,sessionToken)
    return key and self.nodesByToken[key] or nil
end

function ResearchAutoRouteSessionLineage:_SetRaw(node)
    if type(node)~="table" then return nil end
    local key=storageKey(node.professionKey,node.sessionToken)
    if not key then return nil end
    self.nodesByToken[key]=node
    return node
end

function ResearchAutoRouteSessionLineage:_DeleteRaw(professionKey,sessionToken)
    local key=storageKey(professionKey,sessionToken)
    if key then self.nodesByToken[key]=nil end
end

function ResearchAutoRouteSessionLineage:_ReplaySlots(professionKey,sessionToken)
    local slots={}
    local slotCount=math.max(257,tonumber(self.compactedReplayFilterSlots) or 8191)
    local hashes=math.max(2,tonumber(self.compactedReplayFilterHashes) or 3)
    for index=1,hashes do
        local digest=tonumber(hash({professionKey,tostring(sessionToken or ""),"compacted",tostring(index)}),16) or 0
        slots[#slots+1]=(digest%slotCount)+1
    end
    return slots
end

function ResearchAutoRouteSessionLineage:_MarkCompactedToken(professionKey,sessionToken)
    professionKey=normalizeKey(professionKey)
    if not professionKey or tostring(sessionToken or "")=="" then return end
    local filter=self.compactedReplayFilterByProfession[professionKey]
    if type(filter)~="table" then filter={}; self.compactedReplayFilterByProfession[professionKey]=filter end
    for _,slot in ipairs(self:_ReplaySlots(professionKey,sessionToken)) do filter[slot]=true end
end

function ResearchAutoRouteSessionLineage:_CompactedTokenSeen(professionKey,sessionToken)
    professionKey=normalizeKey(professionKey)
    local filter=professionKey and self.compactedReplayFilterByProfession[professionKey] or nil
    if type(filter)~="table" then return false end
    for _,slot in ipairs(self:_ReplaySlots(professionKey,sessionToken)) do if filter[slot]~=true then return false end end
    return true
end

function ResearchAutoRouteSessionLineage:_RetentionStats(professionKey)
    professionKey=normalizeKey(professionKey)
    if not professionKey then return nil end
    local stats=self.compactionStatsByProfession[professionKey]
    if type(stats)~="table" then
        stats={professionKey=professionKey,retainedNodeLimit=tonumber(self.retainedNodeLimit) or 16,compactedCount=0,lastCompactedDepth=nil,historyCompacted=false}
        self.compactionStatsByProfession[professionKey]=stats
    end
    return stats
end

function ResearchAutoRouteSessionLineage:_TrackRetained(node)
    if type(node)~="table" then return end
    local professionKey=normalizeKey(node.professionKey)
    local token=tostring(node.sessionToken or "")
    if not professionKey or token=="" then return end
    local order=self.retainedOrderByProfession[professionKey]
    if type(order)~="table" then order={}; self.retainedOrderByProfession[professionKey]=order end
    for _,existing in ipairs(order) do if tostring(existing)==token then return end end
    order[#order+1]=token
end

function ResearchAutoRouteSessionLineage:_CompactProfession(professionKey)
    professionKey=normalizeKey(professionKey)
    if not professionKey then return nil end
    local order=self.retainedOrderByProfession[professionKey]
    if type(order)~="table" then order={}; self.retainedOrderByProfession[professionKey]=order end
    local limit=math.max(4,tonumber(self.retainedNodeLimit) or 16)
    local stats=self:_RetentionStats(professionKey)
    local headToken=tostring(self.headByProfession[professionKey] or "")
    local guard=0
    while #order>limit and guard<(#order+limit+8) do
        guard=guard+1
        local token=table.remove(order,1)
        local node=self:_GetRaw(professionKey,token)
        if node and (tostring(token)==headToken or node.active==true or node.terminal~=true or node.restartConsumed~=true) then
            order[#order+1]=token
        elseif node then
            self:_MarkCompactedToken(professionKey,token)
            self:_DeleteRaw(professionKey,token)
            stats.compactedCount=(tonumber(stats.compactedCount) or 0)+1
            stats.lastCompactedSessionToken=token
            stats.lastCompactedDepth=tonumber(node.depth)
            stats.historyCompacted=true
        end
    end
    stats.retainedCount=#order
    stats.retainedNodeLimit=limit
    stats.currentHeadSessionToken=self.headByProfession[professionKey]
    local oldestToken=order[1]
    local oldest=oldestToken and self:_GetRaw(professionKey,oldestToken) or nil
    stats.oldestRetainedDepth=oldest and tonumber(oldest.depth) or nil
    return stats
end

function ResearchAutoRouteSessionLineage:_Emit(row)
    if JLP.EventBus and JLP.EventBus.Emit and type(row)=="table" then
        JLP.EventBus:Emit("RESEARCH_AUTO_ROUTE_LINEAGE_UPDATED",copy(row))
    end
end

function ResearchAutoRouteSessionLineage:_Record(row)
    if type(row)~="table" then return nil end
    local key=normalizeKey(row.professionKey)
    if key then self.lastByProfession[key]=copy(row) end
    self:_Emit(row)
    return row
end

function ResearchAutoRouteSessionLineage:GetNode(sessionToken,professionKey)
    sessionToken=tostring(sessionToken or "")
    if sessionToken=="" then return nil end
    professionKey=normalizeKey(professionKey)
    if professionKey then
        local row=self:_GetRaw(professionKey,sessionToken)
        return row and copy(row) or nil
    end
    local found=nil
    for _,row in pairs(self.nodesByToken or {}) do
        if type(row)=="table" and tostring(row.sessionToken or "")==sessionToken then
            if found then return nil end -- ambiguous across professions: fail closed
            found=row
        end
    end
    return found and copy(found) or nil
end

function ResearchAutoRouteSessionLineage:GetHead(professionKey)
    professionKey=normalizeKey(professionKey)
    local token=professionKey and self.headByProfession[professionKey] or nil
    local row=token and self:_GetRaw(professionKey,token) or nil
    return row and copy(row) or nil
end

function ResearchAutoRouteSessionLineage:GetRetentionStats(professionKey)
    professionKey=normalizeKey(professionKey)
    if not professionKey then return nil end
    self:_CompactProfession(professionKey)
    local stats=copy(self:_RetentionStats(professionKey) or {})
    stats.replayFilterSlots=tonumber(self.compactedReplayFilterSlots) or 8191
    stats.replayFilterHashes=tonumber(self.compactedReplayFilterHashes) or 3
    return stats
end

function ResearchAutoRouteSessionLineage:_CreateObservedTerminal(session,interruption,recovered)
    local token=tostring(sessionTokenOf(session) or interruption and interruption.priorSessionToken or "")
    local professionKey=normalizeKey(session and session.professionKey or interruption and interruption.professionKey)
    if token=="" or not professionKey then return nil,"auto-route-lineage-terminal-identity-missing" end
    local existing=self:_GetRaw(professionKey,token)
    if existing then return existing,"auto-route-lineage-terminal-node-existing" end
    if self:_CompactedTokenSeen(professionKey,token) then return nil,"auto-route-lineage-compacted-token-reused" end

    self.serial=(tonumber(self.serial) or 0)+1
    local parent=session and session.lineageParentSessionToken or nil
    local root=session and session.lineageRootSessionToken or nil
    local depth=tonumber(session and session.lineageDepth) or 1
    local chain=session and session.lineageChainToken or nil
    if not root or tostring(root)=="" then root=token end
    if not chain or tostring(chain)=="" then chain="autoroute-lineage-"..hash({professionKey,tostring(root),tostring(self.serial)}) end
    local node={
        contract=self.contract,nodeContract=self.nodeContract,isolationContract=self.isolationContract,retentionContract=self.retentionContract,authority=self.authority,
        professionKey=professionKey,sessionToken=token,chainToken=chain,rootSessionToken=root,
        parentSessionToken=parent,depth=depth,generation=depth,createdAt=tonumber(session and session.createdAt) or now(),
        active=false,terminal=true,recovered=recovered==true,observedTerminal=true,
        sessionProofToken=session and session.lineageSessionProofToken or nil,
        predecessorProofToken=session and session.lineagePredecessorProofToken or nil,
        predecessorInterruptionToken=session and session.lineageInterruptionToken or nil,
        automaticResume=false,ancestorReuseAllowed=false,crossProfessionReuseAllowed=false,persisted=false,
    }
    if not node.sessionProofToken or tostring(node.sessionProofToken)=="" then
        node.sessionProofToken="autoroute-lineage-session-"..hash({professionKey,chain,tostring(root),tostring(parent or ""),token,tostring(depth),recovered and "recovered" or "observed"})
    end
    self:_SetRaw(node); self:_TrackRetained(node); self.headByProfession[professionKey]=token
    local stats=self:_CompactProfession(professionKey); node.historyCompacted=stats and stats.historyCompacted==true or false
    return node,"auto-route-lineage-terminal-node-observed"
end

function ResearchAutoRouteSessionLineage:RecordTerminal(session,interruption)
    if type(interruption)~="table" then return nil,"auto-route-lineage-interruption-missing" end
    local token=tostring(sessionTokenOf(session) or interruption.priorSessionToken or "")
    local professionKey=normalizeKey(session and session.professionKey or interruption.professionKey)
    if token=="" or not professionKey then return nil,"auto-route-lineage-terminal-identity-missing" end
    local node=self:_GetRaw(professionKey,token)
    if not node then node=self:_CreateObservedTerminal(session,interruption,false) end
    if type(node)~="table" then return nil,"auto-route-lineage-terminal-node-unavailable" end
    if normalizeKey(node.professionKey)~=professionKey then return nil,"auto-route-lineage-cross-profession-node-rejected" end
    local headToken=self.headByProfession[professionKey]
    if headToken and tostring(headToken)~=token and node.active~=true then
        return nil,"auto-route-lineage-terminal-not-current-head"
    end
    node.active=false; node.terminal=true; node.terminatedAt=now()
    node.terminalState=tostring(interruption.state or session and session.state or "unknown")
    node.interruptionToken=interruption.interruptionToken; node.interruptionCategory=interruption.category; node.interruptionRestartable=interruption.restartable==true
    node.lastLedgerID=interruption.ledgerID; node.lastOrdinal=tonumber(interruption.currentOrdinal); node.lastSettledCount=tonumber(interruption.settledCount) or 0
    node.recovered=false
    self.headByProfession[professionKey]=token; self:_SetRaw(node)
    local stats=self:_CompactProfession(professionKey); node.historyCompacted=stats and stats.historyCompacted==true or node.historyCompacted==true
    local report=copy(node); report.state="auto-route-lineage-terminal-recorded"
    self:_Record(report)
    return copy(node),report.state
end

function ResearchAutoRouteSessionLineage:RecordRecoveredTerminal(status,interruption,provenance)
    provenance=type(provenance)=="table" and provenance or {}
    interruption=type(interruption)=="table" and interruption or {}
    local token=tostring(interruption.priorSessionToken or provenance.autoRouteSessionToken or "")
    local professionKey=normalizeKey(interruption.professionKey or status and status.key or provenance.professionKey)
    if token=="" or not professionKey then return nil,"auto-route-lineage-recovery-identity-missing" end
    if provenance.professionKey and normalizeKey(provenance.professionKey)~=professionKey then return nil,"auto-route-lineage-recovery-cross-profession-mismatch" end
    local node=self:_GetRaw(professionKey,token)
    if not node then
        local synthetic={
            token=token,professionKey=professionKey,createdAt=tonumber(status and status.startedAt),
            lineageChainToken=provenance.autoRouteLineageChainToken,
            lineageRootSessionToken=provenance.autoRouteLineageRootSessionToken,
            lineageParentSessionToken=provenance.autoRouteLineageParentSessionToken,
            lineageDepth=tonumber(provenance.autoRouteLineageDepth),
            lineagePredecessorProofToken=provenance.autoRouteLineagePredecessorProofToken,
            lineageSessionProofToken=provenance.autoRouteLineageSessionProofToken,
            lineageInterruptionToken=provenance.autoRouteLineageInterruptionToken,
        }
        node=self:_CreateObservedTerminal(synthetic,interruption,true)
    end
    if type(node)~="table" then return nil,"auto-route-lineage-recovery-node-unavailable" end
    node.active=false; node.terminal=true; node.recovered=true; node.observedTerminal=true; node.terminatedAt=now()
    node.terminalState="reload-no-resume"; node.interruptionToken=interruption.interruptionToken; node.interruptionCategory="RELOAD_NO_RESUME"; node.interruptionRestartable=true
    node.lastLedgerID=status and status.ledgerID or interruption.ledgerID; node.lastOrdinal=tonumber(provenance.autoRouteOrdinal); node.lastSettledCount=tonumber(status and status.confirmedCount) or 0
    node.historyTruncated=true
    self:_SetRaw(node); self.headByProfession[professionKey]=token
    local stats=self:_CompactProfession(professionKey); node.historyCompacted=stats and stats.historyCompacted==true or false
    local report=copy(node); report.state="auto-route-lineage-recovered-terminal-recorded"
    self:_Record(report)
    return copy(node),report.state
end

function ResearchAutoRouteSessionLineage:AssessRestart(interruption)
    interruption=type(interruption)=="table" and interruption or {}
    local professionKey=normalizeKey(interruption.professionKey)
    local priorToken=tostring(interruption.priorSessionToken or "")
    local report={
        contract=self.contract,predecessorProofContract=self.predecessorProofContract,isolationContract=self.isolationContract,retentionContract=self.retentionContract,authority=self.authority,
        professionKey=professionKey,priorSessionToken=priorToken,interruptionToken=interruption.interruptionToken,
        restartReady=false,automaticResume=false,ancestorReuseAllowed=false,crossProfessionReuseAllowed=false,persisted=false,
        state="auto-route-lineage-restart-evaluating",
    }
    if not professionKey or priorToken=="" or not interruption.interruptionToken then report.state="auto-route-lineage-restart-identity-missing"; return report end
    local headToken=self.headByProfession[professionKey]
    if headToken and tostring(headToken)~=priorToken then report.state="auto-route-lineage-not-immediate-predecessor"; report.currentHeadSessionToken=headToken; return report end
    local node=self:_GetRaw(professionKey,priorToken)
    if not node and not headToken then
        if self:_CompactedTokenSeen(professionKey,priorToken) then report.state="auto-route-lineage-compacted-token-reused"; return report end
        local synthetic={token=priorToken,professionKey=professionKey,currentRecipe=interruption.recipe,currentRecipeID=interruption.recipeID,currentRouteIndex=interruption.routeIndex,currentSkillTarget=interruption.skillTarget,currentSkill=interruption.currentSkill,currentBuild=interruption.currentBuild,currentSnapshotToken=interruption.snapshotToken,currentStateFingerprint=interruption.stateFingerprint}
        node=self:_CreateObservedTerminal(synthetic,interruption,false)
        if type(node)=="table" then node.interruptionToken=interruption.interruptionToken; node.interruptionCategory=interruption.category; node.interruptionRestartable=interruption.restartable==true; self:_SetRaw(node) end
    end
    if not node then report.state="auto-route-lineage-predecessor-missing"; return report end
    if normalizeKey(node.professionKey)~=professionKey then report.state="auto-route-lineage-cross-profession-node-rejected"; return report end
    headToken=self.headByProfession[professionKey]
    if tostring(headToken or "")~=priorToken then report.state="auto-route-lineage-not-immediate-predecessor"; report.currentHeadSessionToken=headToken; return report end
    if node.terminal~=true or node.active==true then report.state="auto-route-lineage-predecessor-not-terminal"; return report end
    if node.restartConsumed==true then report.state="auto-route-lineage-predecessor-already-consumed"; report.childSessionToken=node.childSessionToken; return report end
    if node.interruptionToken and tostring(node.interruptionToken)~=tostring(interruption.interruptionToken) then report.state="auto-route-lineage-interruption-token-mismatch"; return report end
    node.interruptionToken=interruption.interruptionToken; node.interruptionCategory=interruption.category; node.interruptionRestartable=interruption.restartable==true
    local depth=tonumber(node.depth) or 1
    local stats=self:GetRetentionStats(professionKey) or {}
    report.lineageChainToken=node.chainToken
    report.lineageRootSessionToken=node.rootSessionToken or node.sessionToken
    report.lineageParentSessionToken=node.sessionToken
    report.lineageDepth=depth+1; report.lineageGeneration=depth+1
    report.lineageHistoryTruncated=node.historyTruncated==true
    report.lineageHistoryCompacted=stats.historyCompacted==true or node.historyCompacted==true
    report.lineageRetainedNodeCount=tonumber(stats.retainedCount) or 0
    report.lineageRetainedNodeLimit=tonumber(stats.retainedNodeLimit) or tonumber(self.retainedNodeLimit) or 16
    report.lineagePredecessorProofToken="autoroute-lineage-predecessor-"..hash({
        professionKey,tostring(node.chainToken or ""),tostring(node.rootSessionToken or node.sessionToken or ""),tostring(node.sessionToken or ""),
        tostring(depth),tostring(node.sessionProofToken or ""),tostring(interruption.interruptionToken or ""),tostring(interruption.category or ""),tostring(node.terminalState or ""),
    })
    report.restartReady=true; report.state="auto-route-lineage-immediate-predecessor-proof-ready"
    return report
end

function ResearchAutoRouteSessionLineage:RegisterSession(session,restartAuthorization)
    if type(session)~="table" then return nil,"auto-route-lineage-session-invalid" end
    local professionKey=normalizeKey(session.professionKey)
    local token=tostring(sessionTokenOf(session) or "")
    if not professionKey or token=="" then return nil,"auto-route-lineage-session-identity-missing" end
    if self:_GetRaw(professionKey,token) or self:_CompactedTokenSeen(professionKey,token) then return nil,"auto-route-lineage-session-token-reused" end

    local parentToken,chainToken,rootToken,depth,predecessorProof,interruptionToken
    local restarted=type(restartAuthorization)=="table" and tostring(restartAuthorization.priorSessionToken or "")~=""
    if restarted then
        if restartAuthorization.professionKey and normalizeKey(restartAuthorization.professionKey)~=professionKey then return nil,"auto-route-lineage-cross-profession-authorization-rejected" end
        local assessment=self:AssessRestart({professionKey=professionKey,priorSessionToken=restartAuthorization.priorSessionToken,interruptionToken=restartAuthorization.interruptionToken,category=restartAuthorization.interruptionCategory,restartable=true})
        if assessment.restartReady~=true then return nil,assessment.state,assessment end
        local exact=tostring(restartAuthorization.lineageChainToken or "")==tostring(assessment.lineageChainToken or "")
            and tostring(restartAuthorization.lineageRootSessionToken or "")==tostring(assessment.lineageRootSessionToken or "")
            and tostring(restartAuthorization.lineageParentSessionToken or "")==tostring(assessment.lineageParentSessionToken or "")
            and tonumber(restartAuthorization.lineageDepth)==tonumber(assessment.lineageDepth)
            and tostring(restartAuthorization.lineagePredecessorProofToken or "")==tostring(assessment.lineagePredecessorProofToken or "")
        if not exact then return nil,"auto-route-lineage-restart-binding-mismatch",assessment end
        parentToken=assessment.lineageParentSessionToken; chainToken=assessment.lineageChainToken; rootToken=assessment.lineageRootSessionToken; depth=assessment.lineageDepth
        predecessorProof=assessment.lineagePredecessorProofToken; interruptionToken=restartAuthorization.interruptionToken
        if token==tostring(parentToken or "") or token==tostring(rootToken or "") then return nil,"auto-route-lineage-ancestor-session-token-reused" end
    else
        self.serial=(tonumber(self.serial) or 0)+1
        parentToken=nil; rootToken=token; depth=1
        chainToken="autoroute-lineage-"..hash({professionKey,token,tostring(self.serial),tostring(now())})
    end

    local node={
        contract=self.contract,nodeContract=self.nodeContract,isolationContract=self.isolationContract,retentionContract=self.retentionContract,authority=self.authority,
        professionKey=professionKey,sessionToken=token,chainToken=chainToken,rootSessionToken=rootToken,parentSessionToken=parentToken,
        depth=depth,generation=depth,predecessorProofToken=predecessorProof,predecessorInterruptionToken=interruptionToken,
        createdAt=tonumber(session.createdAt) or now(),active=true,terminal=false,recovered=false,automaticResume=false,ancestorReuseAllowed=false,crossProfessionReuseAllowed=false,persisted=false,
    }
    node.sessionProofToken="autoroute-lineage-session-"..hash({professionKey,chainToken,tostring(rootToken),tostring(parentToken or ""),token,tostring(depth),tostring(predecessorProof or ""),tostring(interruptionToken or "")})
    if parentToken then
        local parent=self:_GetRaw(professionKey,parentToken)
        if not parent or parent.terminal~=true then return nil,"auto-route-lineage-parent-not-terminal" end
        if normalizeKey(parent.professionKey)~=professionKey then return nil,"auto-route-lineage-cross-profession-parent-rejected" end
        parent.restartConsumed=true; parent.childSessionToken=token; parent.childCreatedAt=node.createdAt; self:_SetRaw(parent)
    end
    self:_SetRaw(node); self:_TrackRetained(node); self.headByProfession[professionKey]=token
    local stats=self:_CompactProfession(professionKey)
    node.historyCompacted=stats and stats.historyCompacted==true or false
    node.retainedNodeCount=stats and tonumber(stats.retainedCount) or nil
    node.retainedNodeLimit=stats and tonumber(stats.retainedNodeLimit) or tonumber(self.retainedNodeLimit)
    local report=copy(node); report.state=restarted and "auto-route-lineage-child-session-registered" or "auto-route-lineage-root-session-registered"
    self:_Record(report)
    return copy(node),report.state
end

function ResearchAutoRouteSessionLineage:ValidateActiveSession(session)
    if type(session)~="table" then return false,"auto-route-lineage-session-invalid" end
    local professionKey=normalizeKey(session.professionKey); local token=tostring(sessionTokenOf(session) or "")
    local node=self:_GetRaw(professionKey,token)
    if not professionKey or token=="" or not node then
        if professionKey and token~="" and self:_CompactedTokenSeen(professionKey,token) then return false,"auto-route-lineage-session-compacted" end
        return false,"auto-route-lineage-session-unknown"
    end
    if normalizeKey(node.professionKey)~=professionKey then return false,"auto-route-lineage-cross-profession-node-rejected" end
    if tostring(self.headByProfession[professionKey] or "")~=token then return false,"auto-route-lineage-session-not-head" end
    if node.active~=true or node.terminal==true then return false,"auto-route-lineage-session-not-active" end
    local exact=tostring(session.lineageChainToken or "")==tostring(node.chainToken or "")
        and tostring(session.lineageRootSessionToken or "")==tostring(node.rootSessionToken or "")
        and tostring(session.lineageParentSessionToken or "")==tostring(node.parentSessionToken or "")
        and tonumber(session.lineageDepth)==tonumber(node.depth)
        and tostring(session.lineagePredecessorProofToken or "")==tostring(node.predecessorProofToken or "")
        and tostring(session.lineageSessionProofToken or "")==tostring(node.sessionProofToken or "")
        and tostring(session.lineageInterruptionToken or "")==tostring(node.predecessorInterruptionToken or "")
    if not exact then return false,"auto-route-lineage-session-proof-mismatch" end
    return true,"auto-route-lineage-session-current",copy(node)
end

function ResearchAutoRouteSessionLineage:GetSummary(professionKey)
    professionKey=normalizeKey(professionKey) or "ENGINEERING"
    local head=self:GetHead(professionKey); local stats=self:GetRetentionStats(professionKey) or {}
    local lines={
        "AUTO ROUTE / MULTI-SESSION LINEAGE",professionKey,"Contract: "..self.contract,
        "Isolation: strict profession-scoped lineage","Isolation contract: "..self.isolationContract,
        "Retention contract: "..self.retentionContract,"Authority: immediate terminal predecessor only","Ancestor restart reuse: forbidden","Cross-profession reuse: forbidden","Automatic resume: disabled","Native dispatch: forbidden","Persistence: none",
        "Current head: "..tostring(head and head.sessionToken or "none"),
        "Retained full nodes: "..tostring(stats.retainedCount or 0).." / "..tostring(stats.retainedNodeLimit or self.retainedNodeLimit),
        "Compacted ancestors: "..tostring(stats.compactedCount or 0),
        "Compacted replay filter: bounded fail-closed ("..tostring(self.compactedReplayFilterSlots).." slots / "..tostring(self.compactedReplayFilterHashes).." hashes)",
    }
    if head then
        lines[#lines+1]="Chain: "..tostring(head.chainToken or "none")
        lines[#lines+1]="Root: "..tostring(head.rootSessionToken or "none")
        lines[#lines+1]="Parent: "..tostring(head.parentSessionToken or "none")
        lines[#lines+1]="Depth: "..tostring(head.depth or 1)
        lines[#lines+1]="State: "..(head.terminal and "terminal" or (head.active and "active" or "inactive"))
        lines[#lines+1]="Interruption: "..tostring(head.interruptionCategory or "none")
        lines[#lines+1]="Recovered predecessor: "..(head.recovered and "yes" or "no")
        lines[#lines+1]="History truncated by reload: "..(head.historyTruncated and "yes" or "no")
        lines[#lines+1]="History compacted in runtime: "..((stats.historyCompacted or head.historyCompacted) and "yes" or "no")
    end
    return table.concat(lines,"\n")
end

function ResearchAutoRouteSessionLineage:Validate()
    local errors,warnings={},{}
    if self.automaticResume~=false or self.ancestorReuseAllowed~=false or self.crossProfessionReuseAllowed~=false or self.nativeDispatchAllowed~=false or self.persisted~=false then errors[#errors+1]="Auto Route multi-session lineage safety boundary invalid" end
    if (tonumber(self.retainedNodeLimit) or 0)<4 then errors[#errors+1]="Auto Route lineage retained-node limit is unsafe" end
    if (tonumber(self.compactedReplayFilterSlots) or 0)<257 or (tonumber(self.compactedReplayFilterHashes) or 0)<2 then errors[#errors+1]="Auto Route lineage compacted replay filter is unsafe" end
    return #errors==0,errors,warnings
end

JLP:RegisterModule("ResearchAutoRouteSessionLineage",ResearchAutoRouteSessionLineage)
