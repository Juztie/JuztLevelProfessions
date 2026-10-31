local _, JLP = ...

-- Alpha94 binds every Production Auto Route runtime session and delegated Craft One
-- ordinal to the runtime-only multi-session lineage. A restarted session can descend
-- only from its immediate terminal predecessor; ancestor sessions/proofs cannot be
-- reused by later generations.
--
-- Alpha93 carries route-change restart proof/purge provenance through every delegated
-- Craft One ordinal. A route-changing restart is valid only after alpha93 basis proof,
-- stale-authority purge verification and post-purge revalidation.
--
-- Alpha92 hardens the alpha91 production Auto Route lifecycle. One explicit Guide
-- click owns one runtime-only session; every native craft remains a single Craft One
-- ledger. An interruption can never discard an irreversible in-flight craft: that
-- ordinal settles first and the session then closes terminally. Restart never revives
-- the old session and requires fresh route/snapshot/readiness validation plus a new
-- explicit Profession Guide click.
local AutoRoute = {
    contract = "auto-route-target-aware-production-orchestrator-v1",
    sessionContract = "research-auto-route-session-v1",
    delegationContract = "research-auto-route-dispatch-delegation-v1",
    authority = "feature-gated-explicit-click-target-aware-auto-route-v1",
    persisted = false,
    automaticResume = false,
    nativeDispatchPerOrdinal = 1,
    automaticNonCraftActions = false,
    crossRecipeRequiresTarget = true,
    safetyCraftCap = 250,
    serial = 0,
    sessions = {},
    lastByProfession = {},
    initialized = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(value)
    return value == "aggressive" and "aggressive" or "normal"
end

local function now()
    if type(GetTime) == "function" then local ok,v=pcall(GetTime); if ok and tonumber(v) then return tonumber(v) end end
    if type(time) == "function" then local ok,v=pcall(time); if ok and tonumber(v) then return tonumber(v) end end
    return 0
end

local function hash(parts)
    local value=table.concat(parts or {},"\31"); local h=5381
    for i=1,#value do h=(h*33+string.byte(value,i))%2147483647 end
    return string.format("%08x",h)
end

local function copy(row)
    local out={}; for k,v in pairs(row or {}) do out[k]=v end; return out
end

local function terminal(status)
    status=tostring(status or "")
    return status=="success" or status=="failed" or status=="timeout" or status=="aborted_unknown"
end

local function profile()
    local p=JLP.DB and JLP.DB.profile
    return p and p.researchAutoRouteAuthority or nil
end

local function productionTailoringAuthority()
    return JLP:GetModule("ProductionTailoringAutoRouteAuthority")
end

local function nativeAuthorityFor(professionKey)
    professionKey=normalizeKey(professionKey)
    if professionKey=="TAILORING" then return JLP:GetModule("ProductionTailoringNativeExecutionAuthority") end
    return JLP:GetModule("ResearchNativeExecutionAuthority")
end

local function stepIdentity(consumer)
    local step=consumer and consumer.plan and consumer.plan.step or nil
    if not step then return nil,nil,nil,nil end
    local recipeID=tonumber(step.recipeID) or tonumber(step.rawStep and step.rawStep.recipeID) or tonumber(step.datasetStep and step.datasetStep.recipeID)
    return step.recipe,recipeID,tonumber(step.routeIndex),tonumber(step.skillTarget)
end

function AutoRoute:IsFeatureEnabled(professionKey)
    professionKey=normalizeKey(professionKey)
    if professionKey=="TAILORING" then
        local source=productionTailoringAuthority()
        return source and source.IsFeatureEnabled and source:IsFeatureEnabled() or false
    end
    local p=profile(); return p and p.enabled==true or false
end

function AutoRoute:GetSafetyCraftCap(professionKey)
    professionKey=normalizeKey(professionKey)
    if professionKey=="TAILORING" then
        local source=productionTailoringAuthority()
        if source and source.GetSafetyCraftCap then return source:GetSafetyCraftCap() end
    end
    local p=profile(); local cap=math.floor(tonumber(p and p.safetyCraftCap) or self.safetyCraftCap)
    if cap<1 then cap=1 end; if cap>self.safetyCraftCap then cap=self.safetyCraftCap end
    return cap
end

function AutoRoute:GetNativeAuthority(professionKey)
    return nativeAuthorityFor(professionKey)
end

function AutoRoute:IsSupported(professionKey)
    professionKey=normalizeKey(professionKey)
    local native=nativeAuthorityFor(professionKey)
    if professionKey=="TAILORING" then
        local source=productionTailoringAuthority()
        return source and source.IsSupported and source:IsSupported(professionKey) and native and native.IsSupported and native:IsSupported(professionKey) or false
    end
    return native and native.IsSupported and native:IsSupported(professionKey) or false
end

function AutoRoute:IsEffectiveEnabled(professionKey)
    professionKey=normalizeKey(professionKey)
    if professionKey=="TAILORING" then
        local source=productionTailoringAuthority()
        return source and source.IsEffectiveEnabled and source:IsEffectiveEnabled() or false
    end
    if not self:IsFeatureEnabled(professionKey) then return false end
    local e=JLP:GetModule("ResearchExecutionAuthorityGate")
    local n=JLP:GetModule("ResearchNativeExecutionAuthority")
    return e and e.IsFeatureEnabled and e:IsFeatureEnabled() and n and n.IsEffectiveEnabled and n:IsEffectiveEnabled() or false
end

function AutoRoute:_Emit(report)
    if JLP.EventBus and JLP.EventBus.Emit and type(report)=="table" then JLP.EventBus:Emit("RESEARCH_AUTO_ROUTE_UPDATED",copy(report)) end
end

function AutoRoute:_Snapshot(s,override)
    local r={
        contract=self.contract,sessionContract=self.sessionContract,delegationContract=self.delegationContract,authority=self.authority,
        professionKey=s and s.professionKey or nil,mode=s and s.mode or nil,sessionToken=s and s.token or nil,
        state=s and s.state or "auto-route-unavailable",active=s and s.active==true or false,
        sourceAutoRouteAuthorityContract=s and s.sourceAutoRouteAuthorityContract or nil,sourceAutoRoutePromotionContract=s and s.sourceAutoRoutePromotionContract or nil,
        dispatchedCount=s and tonumber(s.dispatchedCount) or 0,settledCount=s and tonumber(s.settledCount) or 0,
        currentOrdinal=s and tonumber(s.currentOrdinal) or nil,currentLedgerID=s and s.currentLedgerID or nil,
        currentRecipe=s and s.currentRecipe or nil,currentRecipeID=s and tonumber(s.currentRecipeID) or nil,
        currentRouteIndex=s and tonumber(s.currentRouteIndex) or nil,currentSkillTarget=s and tonumber(s.currentSkillTarget) or nil,
        currentSnapshotToken=s and s.currentSnapshotToken or nil,currentStateFingerprint=s and s.currentStateFingerprint or nil,currentBuild=s and tonumber(s.currentBuild) or nil,currentSkill=s and tonumber(s.currentSkill) or nil,
        initialRecipe=s and s.initialRecipe or nil,initialRecipeID=s and tonumber(s.initialRecipeID) or nil,
        initialRouteIndex=s and tonumber(s.initialRouteIndex) or nil,initialSkillTarget=s and tonumber(s.initialSkillTarget) or nil,
        routeTransitions=s and tonumber(s.routeTransitions) or 0,targetTransitions=s and tonumber(s.targetTransitions) or 0,
        stopReason=s and s.stopReason or nil,stopBoundary=s and s.stopBoundary or nil,
        stopCategory=s and s.stopBoundary and s.stopBoundary.category or nil,nextActionText=s and s.stopBoundary and s.stopBoundary.nextActionText or nil,
        safetyCraftCap=self:GetSafetyCraftCap(s and s.professionKey),nativeDispatchPerOrdinal=1,perCraftRevalidation=true,crossRecipeRequiresTarget=true,
        automaticNonCraftActions=false,automaticResume=false,persisted=false,
        restartCandidateToken=s and s.restartCandidateToken or nil,restartAuthorizationToken=s and s.restartAuthorizationToken or nil,
        restartedFromSessionToken=s and s.restartedFromSessionToken or nil,restartedFromBoundaryState=s and s.restartedFromBoundaryState or nil,
        restartedFromBoundaryCategory=s and s.restartedFromBoundaryCategory or nil,restartRouteTransitionKind=s and s.restartRouteTransitionKind or nil,
        restartRouteChanged=s and s.restartRouteChanged==true or false,restartPriorRecipeID=s and tonumber(s.restartPriorRecipeID) or nil,
        restartPriorRouteIndex=s and tonumber(s.restartPriorRouteIndex) or nil,restartCurrentRecipeID=s and tonumber(s.restartCurrentRecipeID) or nil,
        restartCurrentRouteIndex=s and tonumber(s.restartCurrentRouteIndex) or nil,restartExplicitUserClick=s and s.restartExplicitUserClick==true or false,
        restartSourceProofContract=s and s.restartSourceProofContract or nil,restartSourceProofToken=s and s.restartSourceProofToken or nil,
        restartSourceAutoRouteAuthorityContract=s and s.restartSourceAutoRouteAuthorityContract or nil,restartSourceAutoRoutePromotionContract=s and s.restartSourceAutoRoutePromotionContract or nil,
        routeChangeBasis=s and s.routeChangeBasis or nil,routeChangeProofToken=s and s.routeChangeProofToken or nil,routeChangePurgeReceiptToken=s and s.routeChangePurgeReceiptToken or nil,
        routeChangePurgeVerified=s and s.routeChangePurgeVerified==true or false,routeChangePostPurgeRevalidated=s and s.routeChangePostPurgeRevalidated==true or false,
        routeChangePurgedIntentCount=s and tonumber(s.routeChangePurgedIntentCount) or 0,routeChangePurgedReservationCount=s and tonumber(s.routeChangePurgedReservationCount) or 0,routeChangePurgedClickOriginCount=s and tonumber(s.routeChangePurgedClickOriginCount) or 0,
        lineageContract=s and s.lineageContract or nil,lineageChainToken=s and s.lineageChainToken or nil,lineageRootSessionToken=s and s.lineageRootSessionToken or nil,
        lineageParentSessionToken=s and s.lineageParentSessionToken or nil,lineageDepth=s and tonumber(s.lineageDepth) or nil,lineageGeneration=s and tonumber(s.lineageGeneration) or nil,
        lineagePredecessorProofToken=s and s.lineagePredecessorProofToken or nil,lineageSessionProofToken=s and s.lineageSessionProofToken or nil,lineageInterruptionToken=s and s.lineageInterruptionToken or nil,
    }
    for k,v in pairs(override or {}) do r[k]=v end
    return r
end

function AutoRoute:_Record(s,override)
    local r=self:_Snapshot(s,override); local key=normalizeKey(r.professionKey)
    if key then self.lastByProfession[key]=copy(r) end; self:_Emit(r); return r
end

function AutoRoute:SetFeatureEnabled(enabled)
    local p=profile(); if not p then return false,"profile-unavailable" end
    if enabled==true then
        local e=JLP:GetModule("ResearchExecutionAuthorityGate"); local n=JLP:GetModule("ResearchNativeExecutionAuthority")
        if not (e and e.IsFeatureEnabled and e:IsFeatureEnabled()) then return false,"execution-authority-eligibility-gate-disabled" end
        if not (n and n.IsEffectiveEnabled and n:IsEffectiveEnabled()) then return false,"native-execution-authority-gate-disabled" end
    end
    p.enabled=enabled==true
    if not p.enabled then
        -- The legacy/research Auto Route gate no longer owns production Tailoring
        -- sessions.  Disable only sessions sourced from the research authority;
        -- the dedicated ProductionTailoringAutoRouteAuthority gate owns Tailoring.
        local keys={}
        for key in pairs(self.sessions or {}) do
            if normalizeKey(key)~="TAILORING" then keys[#keys+1]=key end
        end
        for _,key in ipairs(keys) do self:Cancel(key,"auto-route-feature-gate-disabled") end
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_AUTO_ROUTE_AUTHORITY_UPDATED",{enabled=p.enabled})
        JLP.EventBus:Emit("SETTINGS_CHANGED","researchAutoRouteAuthority",p.enabled)
    end
    return true,p.enabled and "enabled" or "disabled"
end

function AutoRoute:GetSession(key)
    local s=self.sessions[normalizeKey(key)]; return s and self:_Snapshot(s) or nil
end
function AutoRoute:GetLast(key)
    local r=self.lastByProfession[normalizeKey(key)]; return r and copy(r) or nil
end

function AutoRoute:_Close(s,state,reason)
    if not s then return nil end
    s.state=state or "auto-route-stopped"; s.stopReason=reason; s.active=false; s.finishedAt=now()
    local key=normalizeKey(s.professionKey); if key and self.sessions[key]==s then self.sessions[key]=nil end
    local report=self:_Record(s)
    local interruption=JLP:GetModule("ResearchAutoRouteInterruption")
    if interruption and interruption.RecordSession then interruption:RecordSession(s,s.state,s.stopReason,"auto-route-orchestrator") end
    return report
end

function AutoRoute:Cancel(key,reason)
    key=normalizeKey(key); local s=key and self.sessions[key] or nil
    if not s then return false,"auto-route-not-active" end
    s.cancelRequested=true; s.cancelReason=reason or "user-cancelled"
    local inFlight=s.currentLedgerID~=nil or s.dispatchInProgress==true or (tonumber(s.dispatchedCount) or 0)>(tonumber(s.settledCount) or 0)
    if inFlight then s.state="auto-route-stopping-after-current"; self:_Record(s,{interruptionPending=true}); return true,s.state end
    self:_Close(s,"auto-route-cancelled",s.cancelReason); return true,"auto-route-cancelled"
end
function AutoRoute:CancelAll(reason)
    local keys={}; for k in pairs(self.sessions) do keys[#keys+1]=k end
    for _,k in ipairs(keys) do self:Cancel(k,reason or "cancel-all") end; return true
end

function AutoRoute:ValidateDelegation(d,professionKey,mode)
    if type(d)~="table" or d.contract~=self.delegationContract then return false,"auto-route-delegation-invalid" end
    professionKey=normalizeKey(professionKey or d.professionKey); mode=normalizeMode(mode or d.mode)
    local s=professionKey and self.sessions[professionKey] or nil
    if not s or s.active~=true then return false,"auto-route-session-expired-or-unknown" end
    if tostring(d.sessionToken or "")~=tostring(s.token or "") then return false,"auto-route-session-token-mismatch" end
    if mode~=normalizeMode(s.mode) then return false,"auto-route-mode-mismatch" end
    local ordinal=tonumber(d.ordinal); local expected=(tonumber(s.settledCount) or 0)+1
    if ordinal~=expected or ordinal<1 then return false,"auto-route-ordinal-mismatch" end
    if (d.directGuideClick==true)~=(ordinal==1) then return false,"auto-route-origin-kind-mismatch" end
    if tonumber(d.recipeID)~=tonumber(s.currentRecipeID) or tonumber(d.routeIndex)~=tonumber(s.currentRouteIndex) or tonumber(d.skillTarget)~=tonumber(s.currentSkillTarget) then
        return false,"auto-route-step-identity-mismatch"
    end
    if tostring(d.sourceAutoRouteAuthorityContract or "")~=tostring(s.sourceAutoRouteAuthorityContract or "") or tostring(d.sourceAutoRoutePromotionContract or "")~=tostring(s.sourceAutoRoutePromotionContract or "") then
        return false,"auto-route-source-authority-mismatch"
    end
    if tostring(d.snapshotToken or "")~=tostring(s.currentSnapshotToken or "") then return false,"auto-route-snapshot-mismatch" end
    local restartExact=tostring(d.restartCandidateToken or "")==tostring(s.restartCandidateToken or "") and tostring(d.restartAuthorizationToken or "")==tostring(s.restartAuthorizationToken or "") and tostring(d.restartedFromSessionToken or "")==tostring(s.restartedFromSessionToken or "") and tostring(d.restartRouteTransitionKind or "")==tostring(s.restartRouteTransitionKind or "") and (d.restartRouteChanged==true)==(s.restartRouteChanged==true) and tostring(d.restartSourceProofContract or "")==tostring(s.restartSourceProofContract or "") and tostring(d.restartSourceProofToken or "")==tostring(s.restartSourceProofToken or "") and tostring(d.restartSourceAutoRouteAuthorityContract or "")==tostring(s.restartSourceAutoRouteAuthorityContract or "") and tostring(d.restartSourceAutoRoutePromotionContract or "")==tostring(s.restartSourceAutoRoutePromotionContract or "") and tostring(d.routeChangeBasis or "")==tostring(s.routeChangeBasis or "") and tostring(d.routeChangeProofToken or "")==tostring(s.routeChangeProofToken or "") and tostring(d.routeChangePurgeReceiptToken or "")==tostring(s.routeChangePurgeReceiptToken or "") and (d.routeChangePurgeVerified==true)==(s.routeChangePurgeVerified==true) and (d.routeChangePostPurgeRevalidated==true)==(s.routeChangePostPurgeRevalidated==true)
    if not restartExact then return false,"auto-route-restart-provenance-mismatch" end
    local lineageExact=tostring(d.lineageContract or "")==tostring(s.lineageContract or "") and tostring(d.lineageChainToken or "")==tostring(s.lineageChainToken or "") and tostring(d.lineageRootSessionToken or "")==tostring(s.lineageRootSessionToken or "") and tostring(d.lineageParentSessionToken or "")==tostring(s.lineageParentSessionToken or "") and tonumber(d.lineageDepth)==tonumber(s.lineageDepth) and tostring(d.lineagePredecessorProofToken or "")==tostring(s.lineagePredecessorProofToken or "") and tostring(d.lineageSessionProofToken or "")==tostring(s.lineageSessionProofToken or "") and tostring(d.lineageInterruptionToken or "")==tostring(s.lineageInterruptionToken or "")
    if not lineageExact then return false,"auto-route-lineage-delegation-mismatch" end
    local lineage=JLP:GetModule("ResearchAutoRouteSessionLineage")
    local lineageOK,lineageState=lineage and lineage.ValidateActiveSession and lineage:ValidateActiveSession(s) or false,"auto-route-lineage-unavailable"
    if not lineageOK then return false,lineageState or "auto-route-lineage-session-invalid" end
    if s.restartRouteChanged==true and (not s.routeChangeProofToken or not s.routeChangePurgeReceiptToken or s.routeChangePurgeVerified~=true or s.routeChangePostPurgeRevalidated~=true) then return false,"auto-route-route-change-proof-incomplete" end
    if professionKey=="TAILORING" then
        local source=productionTailoringAuthority()
        if not source or tostring(s.sourceAutoRouteAuthorityContract or "")~=tostring(source.contract or "") or tostring(s.sourceAutoRoutePromotionContract or "")~=tostring(source.promotionContract or "") then return false,"auto-route-production-source-authority-mismatch" end
        if s.restartedFromSessionToken and (not s.restartSourceProofToken or tostring(s.restartSourceAutoRouteAuthorityContract or "")~=tostring(source.contract or "") or tostring(s.restartSourceAutoRoutePromotionContract or "")~=tostring(source.promotionContract or "")) then return false,"auto-route-production-restart-source-proof-incomplete" end
    end
    if s.cancelRequested then return false,"auto-route-cancel-requested" end
    if not self:IsEffectiveEnabled(professionKey) then return false,"auto-route-authority-disabled" end
    return true,"auto-route-delegation-current",s
end

function AutoRoute:_Delegation(s,ordinal,direct)
    return {
        contract=self.delegationContract,sessionToken=s.token,professionKey=s.professionKey,mode=s.mode,ordinal=ordinal,directGuideClick=direct==true,
        sourceAutoRouteAuthorityContract=s.sourceAutoRouteAuthorityContract,sourceAutoRoutePromotionContract=s.sourceAutoRoutePromotionContract,
        source=direct and "profession-guide" or "auto-route-orchestrator",recipe=s.currentRecipe,recipeID=s.currentRecipeID,routeIndex=s.currentRouteIndex,
        skillTarget=s.currentSkillTarget,snapshotToken=s.currentSnapshotToken,
        restartCandidateToken=s.restartCandidateToken,restartAuthorizationToken=s.restartAuthorizationToken,restartedFromSessionToken=s.restartedFromSessionToken,
        restartedFromBoundaryState=s.restartedFromBoundaryState,restartedFromBoundaryCategory=s.restartedFromBoundaryCategory,
        restartRouteTransitionKind=s.restartRouteTransitionKind,restartRouteChanged=s.restartRouteChanged==true,
        restartPriorRecipeID=s.restartPriorRecipeID,restartPriorRouteIndex=s.restartPriorRouteIndex,restartCurrentRecipeID=s.restartCurrentRecipeID,
        restartCurrentRouteIndex=s.restartCurrentRouteIndex,restartExplicitUserClick=s.restartExplicitUserClick==true,
        restartSourceProofContract=s.restartSourceProofContract,restartSourceProofToken=s.restartSourceProofToken,restartSourceAutoRouteAuthorityContract=s.restartSourceAutoRouteAuthorityContract,restartSourceAutoRoutePromotionContract=s.restartSourceAutoRoutePromotionContract,
        routeChangeBasis=s.routeChangeBasis,routeChangeProofToken=s.routeChangeProofToken,routeChangePurgeReceiptToken=s.routeChangePurgeReceiptToken,routeChangePurgeVerified=s.routeChangePurgeVerified==true,routeChangePostPurgeRevalidated=s.routeChangePostPurgeRevalidated==true,
        routeChangePurgedIntentCount=s.routeChangePurgedIntentCount,routeChangePurgedReservationCount=s.routeChangePurgedReservationCount,routeChangePurgedClickOriginCount=s.routeChangePurgedClickOriginCount,
        lineageContract=s.lineageContract,lineageChainToken=s.lineageChainToken,lineageRootSessionToken=s.lineageRootSessionToken,lineageParentSessionToken=s.lineageParentSessionToken,lineageDepth=s.lineageDepth,lineageGeneration=s.lineageGeneration,
        lineagePredecessorProofToken=s.lineagePredecessorProofToken,lineageSessionProofToken=s.lineageSessionProofToken,lineageInterruptionToken=s.lineageInterruptionToken,persisted=false,
    }
end

function AutoRoute:_DispatchNext(s,direct)
    if not s or s.active~=true then return false,"auto-route-not-active" end
    if s.cancelRequested then self:_Close(s,"auto-route-cancelled",s.cancelReason or "cancel-requested"); return false,"auto-route-cancelled" end
    if not self:IsEffectiveEnabled(s.professionKey) then self:_Close(s,"auto-route-stopped-authority-disabled","auto-route-or-native-authority-disabled"); return false,"auto-route-stopped-authority-disabled" end
    local ordinal=(tonumber(s.settledCount) or 0)+1
    if ordinal>self:GetSafetyCraftCap(s.professionKey) then self:_Close(s,"auto-route-stopped-safety-cap","safety-craft-cap-reached"); return false,"auto-route-stopped-safety-cap" end
    local gate=JLP:GetModule("ResearchExecutionAuthorityGate"); local native=nativeAuthorityFor(s.professionKey)
    if not gate or not gate.BeginAutoRouteClickOrigin or not native or not native.Request then self:_Close(s,"auto-route-stopped-dependency-unavailable","execution-boundary-unavailable"); return false,"auto-route-stopped-dependency-unavailable" end
    local d=self:_Delegation(s,ordinal,direct); local origin,originState=gate:BeginAutoRouteClickOrigin(s.professionKey,s.mode,d)
    if not origin then self:_Close(s,"auto-route-stopped-origin-rejected",originState); return false,originState end
    s.currentOrdinal=ordinal; s.state="auto-route-authorizing-craft"; s.dispatchInProgress=true; s.dispatchedCount=ordinal; s.currentOriginToken=origin.token
    self:_Record(s,{originState=originState})
    local ok,state,report=native:Request(s.professionKey,s.mode,origin,s.options)
    s.dispatchInProgress=false; s.currentLedgerID=report and (report.ledgerID or report.transactionID) or s.currentLedgerID
    if not ok then if s.active then self:_Close(s,"auto-route-stopped-dispatch-rejected",state) end; return false,state,report end
    if s.active and (tonumber(s.settledCount) or 0)<ordinal then s.state="auto-route-awaiting-settlement"; self:_Record(s,{dispatchState=state}) end
    if s.active and s.continuePending then s.continuePending=false; return self:_Continue(s) end
    return true,state,report
end

function AutoRoute:_StopForBoundary(s,b)
    s.stopBoundary={contract=b.boundaryContract,state=b.state,category=b.category,label=b.label,nextActionText=b.nextActionText,detail=b.detail,actionKind=b.actionKind,blockedGate=b.blockedGate,blockedState=b.blockedState,consumerState=b.consumerState,sourceAuthorityState=b.sourceAuthorityState,snapshotToken=b.snapshotToken,stateFingerprint=b.stateFingerprint,recipe=b.recipe,recipeID=b.recipeID,routeIndex=b.routeIndex,skillTarget=b.skillTarget,persisted=false}
    self:_Close(s,"auto-route-stopped-boundary",b.state or b.category or "non-craft-boundary")
end

function AutoRoute:_Continue(s)
    if not s or s.active~=true then return false,"auto-route-not-active" end
    if s.cancelRequested then self:_Close(s,"auto-route-cancelled-after-settlement",s.cancelReason or "cancel-requested"); return false,"auto-route-cancelled-after-settlement" end
    if (tonumber(s.settledCount) or 0)>=self:GetSafetyCraftCap(s.professionKey) then self:_Close(s,"auto-route-stopped-safety-cap","safety-craft-cap-reached"); return false,"auto-route-stopped-safety-cap" end
    if not self:IsEffectiveEnabled(s.professionKey) then self:_Close(s,"auto-route-stopped-authority-disabled","authority-disabled-after-settlement"); return false,"auto-route-stopped-authority-disabled" end

    s.state="auto-route-revalidating"
    local stop=JLP:GetModule("ResearchSequentialStopPolicy"); local boundary,consumer
    if stop and stop.Evaluate then boundary,consumer=stop:Evaluate(s.professionKey,s.mode,s.options); if boundary and boundary.terminal==true then self:_StopForBoundary(s,boundary); return false,"auto-route-stopped-boundary",boundary end end
    if not consumer or consumer.state~="consumer-authority-active" or not consumer.plan or consumer.plan.actionKind~="craft" or not consumer.plan.step then
        self:_Close(s,"auto-route-stopped-revalidation",consumer and consumer.state or "consumer-authority-unavailable"); return false,"auto-route-stopped-revalidation"
    end

    local recipe,recipeID,routeIndex,skillTarget=stepIdentity(consumer)
    local api=JLP:GetModule("ProfessionAPI"); local live=api and api.Get and api:Get(s.professionKey) or nil
    local currentSkill=tonumber(live and live.skill) or tonumber(s.currentSkill) or tonumber(s.lastEndingSkill) or 0
    local oldRecipeID,oldRoute,oldTarget=tonumber(s.currentRecipeID),tonumber(s.currentRouteIndex),tonumber(s.currentSkillTarget)
    local routeChanged=oldRoute and routeIndex and oldRoute~=routeIndex or false
    local recipeChanged=oldRecipeID and recipeID and oldRecipeID~=recipeID or false

    if routeChanged or recipeChanged then
        if oldTarget and currentSkill<oldTarget then self:_Close(s,"auto-route-stopped-premature-route-change","previous-target-not-reached"); return false,"auto-route-stopped-premature-route-change" end
        local transition=JLP:GetModule("ResearchNativeStepTransition"); local last=transition and transition.GetLast and transition:GetLast(s.professionKey) or nil
        local ready=last and last.transitionReady==true and tostring(last.ledgerID or "")==tostring(s.lastSettledLedgerID or "") and tonumber(last.toRouteIndex)==tonumber(routeIndex) and tonumber(last.toRecipeID)==tonumber(recipeID)
        if not ready then self:_Close(s,"auto-route-stopped-route-handoff-not-ready",last and last.state or "route-step-handoff-unavailable"); return false,"auto-route-stopped-route-handoff-not-ready" end
        s.routeTransitions=(tonumber(s.routeTransitions) or 0)+1; s.targetTransitions=(tonumber(s.targetTransitions) or 0)+1
    elseif skillTarget and currentSkill>=skillTarget then
        -- Target is already complete but Planner has not moved. Never dispatch an
        -- extra ordinal on the completed step; wait for a fresh route handoff.
        self:_Close(s,"auto-route-stopped-target-replan-pending","current-target-reached-without-route-advance"); return false,"auto-route-stopped-target-replan-pending"
    end

    s.currentRecipe=recipe; s.currentRecipeID=recipeID; s.currentRouteIndex=routeIndex; s.currentSkillTarget=skillTarget; s.currentSnapshotToken=consumer.snapshotToken; s.currentStateFingerprint=consumer.stateFingerprint; s.currentBuild=tonumber(consumer.currentBuild); s.currentSkill=currentSkill
    s.state="auto-route-revalidated"
    self:_Record(s,{routeChanged=routeChanged,recipeChanged=recipeChanged,revalidatedSnapshotToken=consumer.snapshotToken,currentSkill=currentSkill})
    return self:_DispatchNext(s,false)
end

function AutoRoute:_ScheduleContinue(s)
    if not s or s.active~=true then return end
    if s.dispatchInProgress then s.continuePending=true; return end
    if type(C_Timer)=="table" and type(C_Timer.After)=="function" then local token=s.token; C_Timer.After(0,function() local c=AutoRoute.sessions[s.professionKey]; if c and c.active and c.token==token then AutoRoute:_Continue(c) end end) else self:_Continue(s) end
end

function AutoRoute:ObserveCraftAction(action)
    local p=type(action)=="table" and action.authorityProvenance or nil; local token=p and p.autoRouteSessionToken or nil
    if not token or not terminal(action and action.status) then return false,"not-auto-route-terminal" end
    local key=normalizeKey(action.key or p.professionKey); local s=key and self.sessions[key] or nil
    if not s or s.active~=true or tostring(s.token or "")~=tostring(token or "") then return false,"auto-route-session-expired-or-unknown" end
    local ledgerKey=tostring(action.ledgerID or action.transactionID or action.token or ""); s.settledLedgers=s.settledLedgers or {}
    if ledgerKey~="" and s.settledLedgers[ledgerKey] then return false,"auto-route-terminal-duplicate" end
    if ledgerKey~="" then s.settledLedgers[ledgerKey]=true end
    local ordinal=tonumber(p.autoRouteOrdinal); local expected=(tonumber(s.settledCount) or 0)+1
    if ordinal~=expected then self:_Close(s,"auto-route-stopped-ordinal-mismatch","terminal-ordinal-mismatch"); return false,"auto-route-stopped-ordinal-mismatch" end
    s.lastSettledLedgerID=action.ledgerID or action.transactionID; s.lastSettledRecipe=action.recipeName or p.recipe; s.lastSettledRecipeID=tonumber(action.recipeID or p.recipeID); s.lastSettledRouteIndex=tonumber(p.routeIndex); s.lastSettlementStatus=tostring(action.status or "unknown"); s.lastEndingSkill=tonumber(action.endingSkill)
    if tostring(action.status or "")~="success" then self:_Close(s,"auto-route-stopped-settlement-failure",tostring(action.status or "failed")); return true,"auto-route-stopped-settlement-failure" end
    s.settledCount=expected; s.currentRecipe=s.lastSettledRecipe; s.currentRecipeID=s.lastSettledRecipeID; s.currentRouteIndex=s.lastSettledRouteIndex; s.currentSkill=tonumber(action.endingSkill) or s.currentSkill; s.state="auto-route-craft-settled"
    self:_Record(s,{settledLedgerID=s.lastSettledLedgerID,settledOrdinal=ordinal,settlementStatus="success",endingSkill=s.currentSkill})
    if s.cancelRequested then self:_Close(s,"auto-route-cancelled-after-settlement",s.cancelReason or "cancel-requested"); return true,"auto-route-cancelled-after-settlement" end
    self:_ScheduleContinue(s); return true,"auto-route-continuing"
end

function AutoRoute:Request(professionKey,mode,source,options)
    professionKey=normalizeKey(professionKey) or "ENGINEERING"; mode=normalizeMode(mode); source=tostring(source or "profession-guide"); options=type(options)=="table" and options or nil
    if not self:IsFeatureEnabled(professionKey) then return false,"auto-route-feature-gate-disabled" end
    if not self:IsEffectiveEnabled(professionKey) then return false,"auto-route-authority-disabled" end
    if source~="profession-guide" then return false,"auto-route-user-origin-required" end
    if self.sessions[professionKey] and self.sessions[professionKey].active then return false,"auto-route-already-active" end
    local native=nativeAuthorityFor(professionKey); if not native or not native.IsSupported or not native:IsSupported(professionKey) then return false,"auto-route-profession-unsupported" end
    local stop=JLP:GetModule("ResearchSequentialStopPolicy"); local boundary,consumer
    if stop and stop.Evaluate then boundary,consumer=stop:Evaluate(professionKey,mode,options) end
    if boundary and boundary.terminal==true then return false,"auto-route-start-boundary",boundary end
    if not consumer or consumer.state~="consumer-authority-active" or not consumer.plan or not consumer.plan.step then return false,consumer and consumer.state or "consumer-authority-unavailable" end

    local restartAuthorization; local restart=JLP:GetModule("ResearchAutoRouteRestart")
    if restart and restart.AuthorizeExplicitRestart then
        local a,st,m=restart:AuthorizeExplicitRestart(professionKey,mode,source,options)
        if a==nil then return false,st or "auto-route-restart-not-ready",m elseif a~=false then restartAuthorization=a end
    end
    local recipe,recipeID,routeIndex,skillTarget=stepIdentity(consumer)
    if restartAuthorization then
        local valid,validationState,current=restart:ValidateAuthorization(restartAuthorization,professionKey,mode,options)
        if not valid then return false,validationState or "auto-route-restart-authorization-stale",current or restartAuthorization end
        local exact=tostring(restartAuthorization.currentSnapshotToken or "")==tostring(consumer.snapshotToken or "") and tostring(restartAuthorization.currentConsumerStateFingerprint or "")==tostring(consumer.stateFingerprint or "") and tonumber(restartAuthorization.currentRecipeID)==tonumber(recipeID) and tonumber(restartAuthorization.currentRouteIndex)==tonumber(routeIndex) and tonumber(restartAuthorization.currentBuild)==tonumber(consumer.currentBuild)
        if professionKey=="TAILORING" then
            local source=productionTailoringAuthority()
            exact=exact and source and tostring(restartAuthorization.restartSourceAutoRouteAuthorityContract or "")==tostring(source.contract or "") and tostring(restartAuthorization.restartSourceAutoRoutePromotionContract or "")==tostring(source.promotionContract or "") and tostring(restartAuthorization.restartSourceProofToken or "")~=""
        end
        if restartAuthorization.routeChanged==true then exact=exact and restartAuthorization.routeChangePurgeVerified==true and restartAuthorization.routeChangePostPurgeRevalidated==true and tostring(restartAuthorization.routeChangeProofToken or "")~="" and tostring(restartAuthorization.routeChangePurgeReceiptToken or "")~="" end
        if not exact then return false,"auto-route-restart-authorization-stale",restartAuthorization end
    end
    self.serial=(tonumber(self.serial) or 0)+1; local t=now(); local token="auto-route-"..hash({professionKey,mode,tostring(consumer.snapshotToken or ""),tostring(recipeID or ""),tostring(self.serial),tostring(t)})
    local api=JLP:GetModule("ProfessionAPI"); local live=api and api.Get and api:Get(professionKey) or nil
    local sourceAutoRoute=professionKey=="TAILORING" and productionTailoringAuthority() or nil
    local s={contract=self.sessionContract,token=token,professionKey=professionKey,mode=mode,state="auto-route-prepared",source=source,createdAt=t,active=true,persisted=false,options=options,settledLedgers={},dispatchedCount=0,settledCount=0,routeTransitions=0,targetTransitions=0,
        sourceAutoRouteAuthorityContract=sourceAutoRoute and sourceAutoRoute.contract or self.contract,sourceAutoRoutePromotionContract=sourceAutoRoute and sourceAutoRoute.promotionContract or nil,
        initialRecipe=recipe,initialRecipeID=recipeID,initialRouteIndex=routeIndex,initialSkillTarget=skillTarget,initialSnapshotToken=consumer.snapshotToken,
        currentRecipe=recipe,currentRecipeID=recipeID,currentRouteIndex=routeIndex,currentSkillTarget=skillTarget,currentSnapshotToken=consumer.snapshotToken,currentStateFingerprint=consumer.stateFingerprint,currentBuild=tonumber(consumer.currentBuild),currentSkill=tonumber(live and live.skill),
        restartCandidateToken=restartAuthorization and restartAuthorization.candidateToken or nil,restartAuthorizationToken=restartAuthorization and restartAuthorization.token or nil,restartedFromSessionToken=restartAuthorization and restartAuthorization.priorSessionToken or nil,restartedFromBoundaryState=restartAuthorization and restartAuthorization.interruptionState or nil,restartedFromBoundaryCategory=restartAuthorization and restartAuthorization.interruptionCategory or nil,restartRouteTransitionKind=restartAuthorization and restartAuthorization.routeTransitionKind or nil,restartRouteChanged=restartAuthorization and restartAuthorization.routeChanged==true or false,restartPriorRecipeID=restartAuthorization and restartAuthorization.priorRecipeID or nil,restartPriorRouteIndex=restartAuthorization and restartAuthorization.priorRouteIndex or nil,restartCurrentRecipeID=restartAuthorization and restartAuthorization.currentRecipeID or nil,restartCurrentRouteIndex=restartAuthorization and restartAuthorization.currentRouteIndex or nil,restartExplicitUserClick=restartAuthorization and restartAuthorization.explicitUserClick==true or false,
        restartSourceProofContract=restartAuthorization and restartAuthorization.restartSourceProofContract or nil,restartSourceProofToken=restartAuthorization and restartAuthorization.restartSourceProofToken or nil,restartSourceAutoRouteAuthorityContract=restartAuthorization and restartAuthorization.restartSourceAutoRouteAuthorityContract or nil,restartSourceAutoRoutePromotionContract=restartAuthorization and restartAuthorization.restartSourceAutoRoutePromotionContract or nil,
        routeChangeBasis=restartAuthorization and restartAuthorization.routeChangeBasis or nil,routeChangeProofToken=restartAuthorization and restartAuthorization.routeChangeProofToken or nil,routeChangePurgeReceiptToken=restartAuthorization and restartAuthorization.routeChangePurgeReceiptToken or nil,routeChangePurgeVerified=restartAuthorization and restartAuthorization.routeChangePurgeVerified==true or false,routeChangePostPurgeRevalidated=restartAuthorization and restartAuthorization.routeChangePostPurgeRevalidated==true or false,
        routeChangePurgedIntentCount=restartAuthorization and restartAuthorization.routeChangePurgedIntentCount or 0,routeChangePurgedReservationCount=restartAuthorization and restartAuthorization.routeChangePurgedReservationCount or 0,routeChangePurgedClickOriginCount=restartAuthorization and restartAuthorization.routeChangePurgedClickOriginCount or 0,
        lineageContract=restartAuthorization and restartAuthorization.lineageContract or nil,lineageChainToken=restartAuthorization and restartAuthorization.lineageChainToken or nil,lineageRootSessionToken=restartAuthorization and restartAuthorization.lineageRootSessionToken or nil,lineageParentSessionToken=restartAuthorization and restartAuthorization.lineageParentSessionToken or nil,lineageDepth=restartAuthorization and restartAuthorization.lineageDepth or nil,lineageGeneration=restartAuthorization and restartAuthorization.lineageGeneration or nil,
        lineagePredecessorProofToken=restartAuthorization and restartAuthorization.lineagePredecessorProofToken or nil,lineageInterruptionToken=restartAuthorization and restartAuthorization.interruptionToken or nil}
    local lineage=JLP:GetModule("ResearchAutoRouteSessionLineage")
    if not lineage or not lineage.RegisterSession then return false,"auto-route-lineage-unavailable" end
    local lineageNode,lineageState,lineageReport=lineage:RegisterSession(s,restartAuthorization)
    if not lineageNode then return false,lineageState or "auto-route-lineage-session-registration-failed",lineageReport end
    s.lineageContract=lineageNode.contract; s.lineageChainToken=lineageNode.chainToken; s.lineageRootSessionToken=lineageNode.rootSessionToken; s.lineageParentSessionToken=lineageNode.parentSessionToken
    s.lineageDepth=tonumber(lineageNode.depth); s.lineageGeneration=tonumber(lineageNode.generation); s.lineagePredecessorProofToken=lineageNode.predecessorProofToken; s.lineageSessionProofToken=lineageNode.sessionProofToken; s.lineageInterruptionToken=lineageNode.predecessorInterruptionToken
    self.sessions[professionKey]=s
    if restartAuthorization and restart and restart.ConsumeAuthorization then restart:ConsumeAuthorization(restartAuthorization,"fresh-auto-route-session-created") end
    self:_Record(s); local ok,state,report=self:_DispatchNext(s,true); return ok,state,report or self:GetSession(professionKey)
end

function AutoRoute:GetSummary(professionKey)
    professionKey=normalizeKey(professionKey) or "ENGINEERING"; local last=self:GetSession(professionKey) or self:GetLast(professionKey)
    local lines={"AUTO ROUTE / TARGET-AWARE PRODUCTION ORCHESTRATION",professionKey,"Contract: "..self.contract,"Authority: explicit Guide click · Craft One ordinals only","Feature gate: "..(self:IsFeatureEnabled(professionKey) and "enabled" or "disabled"),"Effective authority: "..(self:IsEffectiveEnabled(professionKey) and "enabled" or "disabled"),"Native dispatch per ordinal: 1","Same recipe: continue only while target is open","Cross-recipe handoff: previous target + alpha79 handoff required","Non-craft actions: stop and hand off to Guide","Safety craft cap: "..tostring(self:GetSafetyCraftCap(professionKey)),"Reload auto-resume: disabled","Restart: fresh Guide click + fresh session only","Route-changing restart: basis proof + stale-authority purge + post-purge revalidation","Multi-session lineage: immediate terminal predecessor only","Lineage isolation: strict per profession · bounded full history","Prior session reuse: forbidden","Persistence: none","Last state: "..tostring(last and last.state or "none")}
    if last then lines[#lines+1]="Progress: "..tostring(last.settledCount or 0).." settled · "..tostring(last.routeTransitions or 0).." route transitions"; lines[#lines+1]="Current recipe: "..tostring(last.currentRecipe or "unknown").." / "..tostring(last.currentRecipeID or "unresolved"); lines[#lines+1]="Current target: "..tostring(last.currentSkillTarget or "unknown"); if last.stopReason then lines[#lines+1]="Stop reason: "..tostring(last.stopReason) end end
    return table.concat(lines,"\n")
end

function AutoRoute:Initialize()
    if self.initialized then return true end; self.initialized=true
    if JLP.EventBus and JLP.EventBus.On then
        local function cancelResearchSessions(reason)
            local keys={}
            for key in pairs(self.sessions or {}) do if normalizeKey(key)~="TAILORING" then keys[#keys+1]=key end end
            for _,key in ipairs(keys) do self:Cancel(key,reason) end
        end
        local function demoteTailoring(reason)
            local p=JLP.DB and JLP.DB.profile and JLP.DB.profile.productionTailoringAutoRouteAuthority or nil
            if p and p.enabled==true then p.enabled=false end
            self:Cancel("TAILORING",reason)
            self:_Emit({contract=self.contract,professionKey="TAILORING",state="auto-route-auto-demoted",reason=reason,persisted=false})
        end
        JLP.EventBus:On("CRAFT_ACTION_UPDATED",function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("RESEARCH_NATIVE_EXECUTION_AUTHORITY_UPDATED",function(payload)
            if type(payload)=="table" and payload.enabled==false and self:IsFeatureEnabled() then
                local p=profile(); if p then p.enabled=false end
                cancelResearchSessions("native-execution-authority-disabled")
                self:_Emit({contract=self.contract,state="auto-route-auto-demoted",reason="native-execution-authority-disabled",persisted=false})
            end
        end)
        JLP.EventBus:On("PRODUCTION_TAILORING_NATIVE_EXECUTION_AUTHORITY_UPDATED",function(payload)
            if type(payload)=="table" and payload.enabled==false and self:IsFeatureEnabled("TAILORING") then demoteTailoring("production-tailoring-native-execution-authority-disabled") end
        end)
        JLP.EventBus:On("PRODUCTION_TAILORING_AUTHORITY_UPDATED",function(payload)
            if type(payload)=="table" and payload.enabled==false and self:IsFeatureEnabled("TAILORING") then demoteTailoring("production-tailoring-authority-disabled") end
        end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED",function(payload)
            if type(payload)=="table" and payload.enabled==false then
                if self:IsFeatureEnabled() then local p=profile(); if p then p.enabled=false end end
                local tp=JLP.DB and JLP.DB.profile and JLP.DB.profile.productionTailoringAutoRouteAuthority or nil
                if tp and tp.enabled==true then tp.enabled=false end
                self:CancelAll("execution-authority-eligibility-disabled")
                self:_Emit({contract=self.contract,state="auto-route-auto-demoted",reason="execution-authority-eligibility-disabled",persisted=false})
            end
        end)
    end
    return true
end

function AutoRoute:Validate()
    local errors,warnings={},{}
    if self.persisted~=false then errors[#errors+1]="Auto Route sessions must not persist" end
    if self.automaticResume~=false then errors[#errors+1]="Auto Route must not auto-resume after reload" end
    if self.nativeDispatchPerOrdinal~=1 then errors[#errors+1]="Auto Route native dispatch must remain one craft per ordinal" end
    if self.crossRecipeRequiresTarget~=true then errors[#errors+1]="Auto Route cross-recipe handoff must require previous target completion" end
    if self.automaticNonCraftActions~=false then errors[#errors+1]="Auto Route must stop at non-craft actions" end
    for _,name in ipairs({"ResearchExecutionAuthorityGate","ResearchNativeExecutionAuthority","ProductionTailoringNativeExecutionAuthority","ProductionTailoringAutoRouteAuthority","ResearchPlannerConsumerBridge","ResearchNativeStepTransition","ResearchSequentialStopPolicy","ResearchAutoRouteInterruption","ResearchAutoRouteRestart","ResearchAutoRouteRouteChangeRestart","ProductionTailoringAutoRouteRestart","Crafting"}) do if not JLP:GetModule(name) then errors[#errors+1]="Auto Route dependency missing: "..name end end
    return #errors==0,errors,warnings
end

JLP:RegisterModule("ResearchAutoRouteOrchestrator",AutoRoute)
