local _, JLP = ...

-- Alpha94 attaches every terminal Auto Route interruption to the runtime-only session lineage.
-- The lineage records only terminal predecessor identity and never revives sessions.
--
-- Alpha92 owns deterministic interruption classification for production Auto Route.
-- It never dispatches native work and never persists an Auto Route session.  When an
-- irreversible craft is already in flight, the orchestrator lets that exact ledger
-- settle first; only then is the runtime session terminally closed.  /reload recovery
-- may recover the craft transaction, but it can only create a no-resume interruption
-- record -- never a reconstructed Auto Route session.
local ResearchAutoRouteInterruption = {
    contract = "production-auto-route-interruption-lifecycle-v1",
    interruptionContract = "research-auto-route-interruption-v1",
    authority = "terminal-session-classification-and-reload-no-resume-only",
    automaticResume = false,
    priorSessionReusable = false,
    nativeDispatchAllowed = false,
    persisted = false,
    serial = 0,
    lastByProfession = {},
    recoverySeen = {},
    initialized = false,
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

local function copy(row)
    local out={}
    for k,v in pairs(row or {}) do
        if type(v)=="table" then
            local nested={}; for nk,nv in pairs(v) do nested[nk]=nv end; out[k]=nested
        else out[k]=v end
    end
    return out
end

local RESTARTABLE = {
    ACQUIRE=true, RETRIEVE=true, PREPARE=true, MATERIALS=true,
    TRAIN=true, LEARN_RECIPE=true, LEARN_PROFESSION=true, VERIFY_RECIPE=true,
    OPEN_PROFESSION_WINDOW=true, WINDOW_LOST=true, RECIPE_ACCESS=true,
    NATIVE_CRAFTABILITY=true, WAIT_TRANSACTION=true, AUTHORITY_REVALIDATION=true,
    AUTHORITY_REVOKED=true, AUTHORITY_DISABLED=true, PLANNER_PARITY=true,
    BUILD_CHANGED=true, API_FAILURE=true, RELOAD_NO_RESUME=true,
    REPLAN_PENDING=true, ROUTE_BLOCKED=true, SAFETY_CAP=true, CANCELLED=true,
}

local function reasonContains(reason, needle)
    return tostring(reason or ""):lower():find(tostring(needle or ""):lower(),1,true) ~= nil
end

local function classify(state, reason, boundary)
    state=tostring(state or "")
    reason=tostring(reason or "")
    if state=="reload-no-resume" then return "RELOAD_NO_RESUME","Reload recovered only the in-flight craft transaction; the prior Auto Route session is permanently dead" end
    if type(boundary)=="table" and boundary.category then
        local category=tostring(boundary.category):upper()
        if category=="COMPLETE" then return "COMPLETE",boundary.nextActionText or "Profession route complete" end
        if category=="AUTHORITY_REVALIDATION" then
            local authorityText=table.concat({tostring(boundary.sourceAuthorityState or ""),tostring(boundary.blockedGate or ""),tostring(boundary.blockedState or ""),tostring(boundary.detail or ""),reason}," ")
            if reasonContains(authorityText,"parity") then return "PLANNER_PARITY",boundary.nextActionText or "Planner/shadow parity must be revalidated" end
            if reasonContains(authorityText,"build") or reasonContains(authorityText,"provenance") then return "BUILD_CHANGED",boundary.nextActionText or "Current-build provenance must be revalidated" end
            if reasonContains(authorityText,"revoked") or reasonContains(authorityText,"disabled") then return "AUTHORITY_REVOKED",boundary.nextActionText or "Execution authority was revoked" end
        end
        return category,boundary.nextActionText or boundary.detail or reason
    end
    if state=="auto-route-stopped-target-replan-pending" then return "REPLAN_PENDING","The skill target is complete but Planner has not published the next verified route step" end
    if state=="auto-route-stopped-safety-cap" then return "SAFETY_CAP","Runtime safety craft cap reached; only a fresh explicit session may continue" end
    if state=="auto-route-cancelled" or state=="auto-route-cancelled-after-settlement" then
        if reasonContains(reason,"authority") or reasonContains(reason,"feature-gate") then return "AUTHORITY_REVOKED",reason end
        return "CANCELLED",reason ~= "" and reason or "Auto Route cancelled"
    end
    if state=="auto-route-stopped-authority-disabled" or reasonContains(reason,"authority-disabled") or reasonContains(reason,"authority revoked") then return "AUTHORITY_REVOKED",reason end
    if state=="auto-route-stopped-dispatch-rejected" or reasonContains(reason,"native") or reasonContains(reason,"api") then
        if reasonContains(reason,"window") then return "WINDOW_LOST",reason end
        if reasonContains(reason,"build") then return "BUILD_CHANGED",reason end
        if reasonContains(reason,"authority") then return "AUTHORITY_REVOKED",reason end
        return "API_FAILURE",reason ~= "" and reason or state
    end
    if state=="auto-route-stopped-settlement-failure" then return "API_FAILURE",reason ~= "" and reason or "Native craft settlement failed" end
    if state=="auto-route-stopped-revalidation" then
        if reasonContains(reason,"parity") then return "PLANNER_PARITY",reason end
        if reasonContains(reason,"build") then return "BUILD_CHANGED",reason end
        if reasonContains(reason,"authority") or reasonContains(reason,"consumer") then return "AUTHORITY_REVALIDATION",reason end
        return "ROUTE_BLOCKED",reason ~= "" and reason or state
    end
    if state=="auto-route-stopped-premature-route-change" or state=="auto-route-stopped-route-handoff-not-ready" or state=="auto-route-stopped-ordinal-mismatch" then
        return "SAFETY_INCONSISTENCY",reason ~= "" and reason or state
    end
    return "OTHER",reason ~= "" and reason or (state ~= "" and state or "Unknown Auto Route interruption")
end

function ResearchAutoRouteInterruption:IsRestartableCategory(category)
    return RESTARTABLE[tostring(category or ""):upper()] == true
end

function ResearchAutoRouteInterruption:Classify(state, reason, boundary)
    return classify(state,reason,boundary)
end

function ResearchAutoRouteInterruption:RecordSession(session, state, reason, source)
    if type(session)~="table" then return nil,"auto-route-interruption-session-invalid" end
    local professionKey=normalizeKey(session.professionKey) or "UNKNOWN"
    local boundary=type(session.stopBoundary)=="table" and session.stopBoundary or nil
    local category,detail=classify(state or session.state,reason or session.stopReason,boundary)
    self.serial=(tonumber(self.serial) or 0)+1
    local row={
        contract=self.contract,interruptionContract=self.interruptionContract,authority=self.authority,
        interruptionToken="autoroute-interruption-"..tostring(self.serial),
        professionKey=professionKey,mode=session.mode,state=tostring(state or session.state or "unknown"),category=category,
        detail=detail,source=tostring(source or "auto-route-orchestrator"),recordedAt=now(),
        priorSessionToken=session.token or session.sessionToken,ledgerID=session.lastSettledLedgerID or session.currentLedgerID,
        currentOrdinal=tonumber(session.currentOrdinal),dispatchedCount=tonumber(session.dispatchedCount) or 0,settledCount=tonumber(session.settledCount) or 0,
        recipe=session.currentRecipe,recipeID=tonumber(session.currentRecipeID),routeIndex=tonumber(session.currentRouteIndex),skillTarget=tonumber(session.currentSkillTarget),
        currentSkill=tonumber(session.currentSkill or session.lastEndingSkill),currentBuild=tonumber(session.currentBuild),snapshotToken=session.currentSnapshotToken,
        stateFingerprint=session.currentStateFingerprint,
        sourceAutoRouteAuthorityContract=session.sourceAutoRouteAuthorityContract,sourceAutoRoutePromotionContract=session.sourceAutoRoutePromotionContract,
        stopBoundary=boundary and copy(boundary) or nil,stopBoundaryState=boundary and boundary.state or nil,stopBoundaryCategory=boundary and boundary.category or nil,
        restartable=self:IsRestartableCategory(category),automaticResume=false,priorSessionReusable=false,nativeDispatchAllowed=false,persisted=false,
    }
    local lineage=JLP:GetModule("ResearchAutoRouteSessionLineage")
    if lineage and lineage.RecordTerminal then
        local lineageNode,lineageState=lineage:RecordTerminal(session,row)
        row.lineageState=lineageState
        if lineageNode then
            row.lineageChainToken=lineageNode.chainToken; row.lineageRootSessionToken=lineageNode.rootSessionToken
            row.lineageParentSessionToken=lineageNode.parentSessionToken; row.lineageDepth=tonumber(lineageNode.depth)
            row.lineageSessionProofToken=lineageNode.sessionProofToken; row.lineagePredecessorProofToken=lineageNode.predecessorProofToken
        end
    end
    self.lastByProfession[professionKey]=row
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("RESEARCH_AUTO_ROUTE_INTERRUPTION_UPDATED",copy(row)) end
    return copy(row),"auto-route-interruption-recorded"
end

function ResearchAutoRouteInterruption:RecordReloadRecovery(status)
    local provenance=type(status)=="table" and status.authorityProvenance or nil
    if type(provenance)~="table" or not provenance.autoRouteSessionToken then return nil,"not-auto-route-recovery" end
    local professionKey=normalizeKey(status.key or provenance.professionKey)
    if not professionKey then return nil,"auto-route-recovery-profession-missing" end
    local recoveryKey=table.concat({tostring(provenance.autoRouteSessionToken),tostring(status.ledgerID or ""),tostring(status.snapshotID or "")},"|")
    if self.recoverySeen[recoveryKey] then return self:GetLast(professionKey),"auto-route-recovery-already-recorded" end
    self.recoverySeen[recoveryKey]=true
    self.serial=(tonumber(self.serial) or 0)+1
    local row={
        contract=self.contract,interruptionContract=self.interruptionContract,authority=self.authority,
        interruptionToken="autoroute-interruption-"..tostring(self.serial),professionKey=professionKey,mode=provenance.mode or "normal",
        state="reload-no-resume",category="RELOAD_NO_RESUME",detail="Reload recovered only the in-flight craft transaction; the prior Auto Route session is permanently dead",
        source="transaction-recovery",recordedAt=now(),priorSessionToken=provenance.autoRouteSessionToken,ledgerID=status.ledgerID,
        currentOrdinal=tonumber(provenance.autoRouteOrdinal),dispatchedCount=tonumber(provenance.autoRouteOrdinal) or 0,
        settledCount=tonumber(status.confirmedCount) or 0,recipe=provenance.recipe,recipeID=tonumber(provenance.autoRouteRecipeID or provenance.recipeID),
        routeIndex=tonumber(provenance.autoRouteRouteIndex or provenance.routeIndex),skillTarget=tonumber(provenance.autoRouteSkillTarget or provenance.skillTarget),
        currentSkill=tonumber(status.endingSkill or provenance.startedSkill),currentBuild=tonumber(provenance.currentBuild),snapshotToken=provenance.autoRouteSnapshotToken or provenance.snapshotToken,stateFingerprint=provenance.stateFingerprint,
        sourceAutoRouteAuthorityContract=provenance.autoRouteSourceAuthorityContract,sourceAutoRoutePromotionContract=provenance.autoRouteSourcePromotionContract,
        recoveryState=status.state,recoveryTerminal=status.terminal==true,restartable=true,automaticResume=false,priorSessionReusable=false,nativeDispatchAllowed=false,persisted=false,
    }
    local lineage=JLP:GetModule("ResearchAutoRouteSessionLineage")
    if lineage and lineage.RecordRecoveredTerminal then
        local lineageNode,lineageState=lineage:RecordRecoveredTerminal(status,row,provenance)
        row.lineageState=lineageState
        if lineageNode then
            row.lineageChainToken=lineageNode.chainToken; row.lineageRootSessionToken=lineageNode.rootSessionToken
            row.lineageParentSessionToken=lineageNode.parentSessionToken; row.lineageDepth=tonumber(lineageNode.depth)
            row.lineageSessionProofToken=lineageNode.sessionProofToken; row.lineagePredecessorProofToken=lineageNode.predecessorProofToken
            row.lineageHistoryTruncated=lineageNode.historyTruncated==true
        end
    end
    self.lastByProfession[professionKey]=row
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("RESEARCH_AUTO_ROUTE_INTERRUPTION_UPDATED",copy(row)) end
    return copy(row),"auto-route-reload-interruption-recorded"
end

function ResearchAutoRouteInterruption:GetLast(professionKey)
    local row=self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ResearchAutoRouteInterruption:GetSummary(professionKey)
    professionKey=normalizeKey(professionKey) or "ENGINEERING"
    local last=self:GetLast(professionKey)
    local lines={
        "AUTO ROUTE / INTERRUPTION LIFECYCLE",professionKey,"Contract: "..self.contract,
        "Authority: classification / no dispatch","In-flight craft: settle before terminal session close","Reload auto-resume: disabled",
        "Prior session reuse: forbidden","Persistence: none","Last interruption: "..tostring(last and last.category or "none"),
    }
    if last then
        lines[#lines+1]="State: "..tostring(last.state)
        lines[#lines+1]="Detail: "..tostring(last.detail)
        lines[#lines+1]="Prior session: "..tostring(last.priorSessionToken or "none")
        lines[#lines+1]="Progress: "..tostring(last.settledCount or 0).." settled / "..tostring(last.dispatchedCount or 0).." dispatched"
        lines[#lines+1]="Restartable: "..(last.restartable and "yes" or "no")
        lines[#lines+1]="Source Auto Route authority: "..tostring(last.sourceAutoRouteAuthorityContract or "none")
        lines[#lines+1]="Source promotion: "..tostring(last.sourceAutoRoutePromotionContract or "none")
    end
    return table.concat(lines,"\n")
end

function ResearchAutoRouteInterruption:Initialize()
    if self.initialized then return true end
    self.initialized=true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("TRANSACTION_RECOVERY_UPDATED",function(status)
            local provenance=status and status.authorityProvenance
            if type(provenance)=="table" and provenance.autoRouteSessionToken and tostring(status.state or "")~="IDLE" then self:RecordReloadRecovery(status) end
        end)
    end
    return true
end

function ResearchAutoRouteInterruption:Validate()
    local errors,warnings={},{}
    if self.automaticResume~=false or self.priorSessionReusable~=false or self.nativeDispatchAllowed~=false or self.persisted~=false then errors[#errors+1]="Auto Route interruption lifecycle safety boundary invalid" end
    return #errors==0,errors,warnings
end

JLP:RegisterModule("ResearchAutoRouteInterruption",ResearchAutoRouteInterruption)
