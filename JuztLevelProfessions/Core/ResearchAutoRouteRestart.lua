local _, JLP = ...

-- Alpha95 keeps restart candidates profession-scoped and binds them to the
-- profession-scoped lineage proof. A valid predecessor from one profession may
-- never authorize a fresh session for another profession; lineage retention/
-- compaction is authority-neutral and never creates restart permission.
-- Alpha94 binds every fresh restart candidate/authorization to an immediate-predecessor
-- session-lineage proof. Ancestors remain diagnostics only and can never authorize a
-- later generation, including after repeated boundaries or reload recovery.
--
-- Alpha93 extends the alpha92 fresh-click restart lifecycle with route-change basis
-- proof, stale-authority purge verification and post-purge revalidation. A resolved
-- interruption still becomes a brand-new runtime session only; the prior session,
-- ledger and delegation are never revived.
--
-- Alpha92 converts a resolved production Auto Route interruption into a fresh,
-- single-use restart authorization.  The old session/ledger/delegation is never
-- revived.  Readiness, consumer snapshot, Planner identity and current-build
-- provenance are rebuilt from live state, and a new explicit Profession Guide click
-- is required before a brand-new Auto Route session may exist.
local ResearchAutoRouteRestart = {
    contract = "production-auto-route-fresh-click-restart-planner-v1",
    candidateContract = "research-auto-route-restart-candidate-v1",
    authorizationContract = "research-auto-route-restart-authorization-v1",
    authority = "explicit-guide-click-fresh-session-restart-only",
    automaticResume = false,
    priorSessionReusable = false,
    freshSessionRequired = true,
    persisted = false,
    authorizationTTLSeconds = 3,
    candidateSerial = 0,
    authorizationSerial = 0,
    candidates = {},
    authorizations = {},
    consumedInterruptionByProfession = {},
    lastByProfession = {},
}

local function normalizeKey(value)
    local key=tostring(value or ""):upper(); return key~="" and key or nil
end
local function normalizeMode(value) return value=="aggressive" and "aggressive" or "normal" end
local function now()
    if type(GetTime)=="function" then local ok,v=pcall(GetTime); if ok and tonumber(v) then return tonumber(v) end end
    if type(time)=="function" then local ok,v=pcall(time); if ok and tonumber(v) then return tonumber(v) end end
    return 0
end
local function hash(parts)
    local value=table.concat(parts or {},"\31"); local h=5381
    for i=1,#value do h=(h*33+string.byte(value,i))%2147483647 end
    return string.format("%08x",h)
end
local function copy(row) local out={}; for k,v in pairs(row or {}) do out[k]=v end; return out end
local function stepIdentity(consumer)
    local step=consumer and consumer.plan and consumer.plan.step or nil
    if not step then return nil,nil,nil,nil end
    return step.recipe,tonumber(step.recipeID) or tonumber(step.rawStep and step.rawStep.recipeID) or tonumber(step.datasetStep and step.datasetStep.recipeID),tonumber(step.routeIndex),tonumber(step.skillTarget)
end

function ResearchAutoRouteRestart:_Sweep(nowValue)
    nowValue=tonumber(nowValue) or now()
    for token,row in pairs(self.authorizations) do
        if type(row)~="table" or row.consumed==true or (tonumber(row.expiresAt) and nowValue>tonumber(row.expiresAt)) then self.authorizations[token]=nil end
    end
end

function ResearchAutoRouteRestart:_InvalidateCandidate(professionKey,reason)
    professionKey=normalizeKey(professionKey); if not professionKey then return end
    local old=self.candidates[professionKey]
    if old then old.state=tostring(reason or "auto-route-restart-candidate-invalidated"); old.restartReady=false; old.invalidatedAt=now(); self.lastByProfession[professionKey]=copy(old) end
    self.candidates[professionKey]=nil
end

function ResearchAutoRouteRestart:_Base(professionKey,mode)
    return {contract=self.contract,candidateContract=self.candidateContract,authorizationContract=self.authorizationContract,authority=self.authority,
        professionKey=professionKey,mode=mode,state="auto-route-restart-evaluating",restartRequired=false,restartReady=false,
        explicitUserClickRequired=true,freshSessionRequired=true,automaticResume=false,priorSessionReusable=false,persisted=false}
end

function ResearchAutoRouteRestart:Evaluate(professionKey,mode,options)
    professionKey=normalizeKey(professionKey) or "ENGINEERING"; mode=normalizeMode(mode); options=type(options)=="table" and options or {}
    self:_Sweep(now())
    local model=self:_Base(professionKey,mode)
    local interruptions=JLP:GetModule("ResearchAutoRouteInterruption")
    local interruption=interruptions and interruptions.GetLast and interruptions:GetLast(professionKey) or nil
    if type(interruption)~="table" or interruption.restartable~=true then self:_InvalidateCandidate(professionKey,"auto-route-restart-not-applicable"); model.state="auto-route-restart-not-applicable"; return model end
    local token=tostring(interruption.interruptionToken or "")
    if token=="" then self:_InvalidateCandidate(professionKey,"auto-route-restart-interruption-identity-missing"); model.state="auto-route-restart-interruption-identity-missing"; return model end
    model.restartRequired=true; model.interruptionToken=token; model.interruptionCategory=interruption.category; model.interruptionState=interruption.state; model.interruptionDetail=interruption.detail
    model.priorSessionToken=interruption.priorSessionToken; model.priorLedgerID=interruption.ledgerID; model.priorRecipe=interruption.recipe; model.priorRecipeID=tonumber(interruption.recipeID)
    model.priorRouteIndex=tonumber(interruption.routeIndex); model.priorSkillTarget=tonumber(interruption.skillTarget); model.priorSkill=tonumber(interruption.currentSkill); model.priorBuild=tonumber(interruption.currentBuild)
    model.priorSnapshotToken=interruption.snapshotToken; model.priorStateFingerprint=interruption.stateFingerprint
    model.priorSourceAutoRouteAuthorityContract=interruption.sourceAutoRouteAuthorityContract; model.priorSourceAutoRoutePromotionContract=interruption.sourceAutoRoutePromotionContract
    if self.consumedInterruptionByProfession[professionKey]==token then self:_InvalidateCandidate(professionKey,"auto-route-restart-interruption-consumed"); model.state="auto-route-restart-interruption-consumed"; return model end

    local lineage=JLP:GetModule("ResearchAutoRouteSessionLineage")
    local lineageProof=lineage and lineage.AssessRestart and lineage:AssessRestart(interruption) or nil
    if not lineageProof or lineageProof.restartReady~=true then
        self:_InvalidateCandidate(professionKey,lineageProof and lineageProof.state or "auto-route-lineage-unavailable")
        model.state=lineageProof and lineageProof.state or "auto-route-lineage-unavailable"
        return model
    end
    model.lineageContract=lineageProof.contract; model.lineageChainToken=lineageProof.lineageChainToken; model.lineageRootSessionToken=lineageProof.lineageRootSessionToken
    model.lineageParentSessionToken=lineageProof.lineageParentSessionToken; model.lineageDepth=tonumber(lineageProof.lineageDepth); model.lineageGeneration=tonumber(lineageProof.lineageGeneration)
    model.lineagePredecessorProofToken=lineageProof.lineagePredecessorProofToken; model.lineageHistoryTruncated=lineageProof.lineageHistoryTruncated==true

    local orchestrator=JLP:GetModule("ResearchAutoRouteOrchestrator")
    local active=orchestrator and orchestrator.GetSession and orchestrator:GetSession(professionKey) or nil
    if active and active.active then self:_InvalidateCandidate(professionKey,"auto-route-restart-session-active"); model.state="auto-route-restart-session-active"; return model end
    if not orchestrator or not orchestrator.IsEffectiveEnabled or not orchestrator:IsEffectiveEnabled(professionKey) then self:_InvalidateCandidate(professionKey,"auto-route-restart-authority-not-ready"); model.state="auto-route-restart-authority-not-ready"; return model end

    local stop=JLP:GetModule("ResearchSequentialStopPolicy")
    local boundary,consumer
    if stop and stop.Evaluate then boundary,consumer=stop:Evaluate(professionKey,mode,options) end
    if boundary and boundary.terminal==true then
        model.currentBoundaryState=boundary.state; model.currentBoundaryCategory=boundary.category; model.blockedGate=boundary.blockedGate; model.blockedState=boundary.blockedState
        self:_InvalidateCandidate(professionKey,"auto-route-restart-still-blocked"); model.state="auto-route-restart-still-blocked"; return model
    end
    local readiness=JLP:GetModule("ResearchExecutionReadiness")
    local current=readiness and readiness.Evaluate and readiness:Evaluate(professionKey,mode,options) or nil
    model.readinessState=current and current.state or "execution-readiness-unavailable"; model.blockedGate=current and current.blockedGate or model.blockedGate; model.blockedState=current and current.blockedState or model.blockedState
    if not current or current.executionReadinessReady~=true then self:_InvalidateCandidate(professionKey,"auto-route-restart-readiness-not-ready"); model.state="auto-route-restart-readiness-not-ready"; return model end
    consumer=current.consumer or consumer
    if not consumer or consumer.state~="consumer-authority-active" or not consumer.plan or consumer.plan.actionKind~="craft" or not consumer.plan.step then self:_InvalidateCandidate(professionKey,"auto-route-restart-route-not-craft-ready"); model.state="auto-route-restart-route-not-craft-ready"; return model end

    local recipe,recipeID,routeIndex,skillTarget=stepIdentity(consumer)
    local currentSkill=tonumber(current.professionSkill)
    model.currentBuild=tonumber(current.currentBuild); model.currentSnapshotToken=current.snapshotToken; model.currentStateFingerprint=current.stateFingerprint; model.currentConsumerStateFingerprint=current.consumerStateFingerprint or (consumer and consumer.stateFingerprint)
    model.currentSourceAuthorityContract=consumer and consumer.snapshot and consumer.snapshot.sourceAuthorityContract or nil; model.currentSourceDatasetContract=consumer and consumer.snapshot and consumer.snapshot.sourceDatasetContract or nil
    model.currentSourceReadinessPolicyContract=current.sourceReadinessPolicyContract; model.currentSourceReadinessProofContract=current.sourceReadinessProofContract; model.currentSourceReadinessFingerprint=current.sourceReadinessFingerprint
    model.currentRecipe=recipe; model.currentRecipeID=recipeID; model.currentRouteIndex=routeIndex; model.currentSkillTarget=skillTarget; model.currentSkill=currentSkill
    model.craftabilityStatus=current.craftabilityStatus or "UNKNOWN"
    model.craftabilityReason=current.craftabilityReason
    model.currentNativeCraftable=model.craftabilityStatus=="KNOWN" and tonumber(current.nativeCraftable) or nil
    if not recipe or not recipeID or not routeIndex or not skillTarget or not model.currentSnapshotToken or not model.currentStateFingerprint or not model.currentConsumerStateFingerprint then self:_InvalidateCandidate(professionKey,"auto-route-restart-current-identity-incomplete"); model.state="auto-route-restart-current-identity-incomplete"; return model end
    if model.craftabilityStatus~="KNOWN" or type(model.currentNativeCraftable)~="number"
        or model.currentNativeCraftable~=model.currentNativeCraftable or model.currentNativeCraftable<0
        or model.currentNativeCraftable==math.huge or model.currentNativeCraftable==-math.huge
        or model.currentNativeCraftable%1~=0 then
        self:_InvalidateCandidate(professionKey,"auto-route-restart-craftability-unavailable")
        model.state="auto-route-restart-craftability-unavailable"
        return model
    end
    if model.currentNativeCraftable==0 then self:_InvalidateCandidate(professionKey,"auto-route-restart-native-craftability-zero"); model.state="auto-route-restart-native-craftability-zero"; return model end
    if currentSkill and skillTarget and currentSkill>=skillTarget then self:_InvalidateCandidate(professionKey,"auto-route-restart-target-already-reached"); model.state="auto-route-restart-target-already-reached"; return model end

    local routeHardening=JLP:GetModule("ResearchAutoRouteRouteChangeRestart")
    local transition=routeHardening and routeHardening.Assess and routeHardening:Assess({
        professionKey=professionKey,mode=mode,interruptionToken=model.interruptionToken,interruptionCategory=model.interruptionCategory,priorSessionToken=model.priorSessionToken,
        priorRecipe=model.priorRecipe,priorRecipeID=model.priorRecipeID,priorRouteIndex=model.priorRouteIndex,priorSkillTarget=model.priorSkillTarget,priorSkill=model.priorSkill,priorBuild=model.priorBuild,
        currentRecipe=recipe,currentRecipeID=recipeID,currentRouteIndex=routeIndex,currentSkillTarget=skillTarget,currentSkill=currentSkill,currentBuild=model.currentBuild,
        currentSnapshotToken=model.currentSnapshotToken,currentConsumerStateFingerprint=model.currentConsumerStateFingerprint,currentStateFingerprint=model.currentStateFingerprint,
        priorSourceAutoRouteAuthorityContract=model.priorSourceAutoRouteAuthorityContract,priorSourceAutoRoutePromotionContract=model.priorSourceAutoRoutePromotionContract,
        currentSourceAuthorityContract=model.currentSourceAuthorityContract,currentSourceDatasetContract=model.currentSourceDatasetContract,currentSourceReadinessPolicyContract=model.currentSourceReadinessPolicyContract,currentSourceReadinessProofContract=model.currentSourceReadinessProofContract,currentSourceReadinessFingerprint=model.currentSourceReadinessFingerprint,
    }) or nil
    if not transition or transition.ready~=true then self:_InvalidateCandidate(professionKey,"auto-route-restart-route-transition-not-ready"); model.state=transition and transition.state or "auto-route-restart-route-transition-not-ready"; model.routeChangeBasis=transition and transition.routeChangeBasis or nil; return model end
    model.routeTransitionKind=transition.transitionKind or "same-route"; model.routeChanged=transition.routeChanged==true; model.routeChangeBasis=transition.routeChangeBasis; model.routeChangeProofToken=transition.proofToken; model.routeChangePriorTargetReached=transition.priorTargetReached==true; model.routeChangeAuthoritativeReplan=transition.authoritativeReplanCategory==true

    if professionKey=="TAILORING" then
        local sourceHardening=JLP:GetModule("ProductionTailoringAutoRouteRestart")
        local sourceProof=sourceHardening and sourceHardening.Assess and sourceHardening:Assess(interruption,model) or nil
        if not sourceProof or sourceProof.ready~=true then
            self:_InvalidateCandidate(professionKey,sourceProof and sourceProof.state or "production-tailoring-auto-route-restart-source-proof-unavailable")
            model.state=sourceProof and sourceProof.state or "production-tailoring-auto-route-restart-source-proof-unavailable"
            return model
        end
        model.restartSourceProofContract=sourceProof.proofContract; model.restartSourceProofToken=sourceProof.proofToken
        model.restartSourceAutoRouteAuthorityContract=sourceProof.priorSourceAutoRouteAuthorityContract; model.restartSourceAutoRoutePromotionContract=sourceProof.priorSourceAutoRoutePromotionContract
    end

    local identity=table.concat({token,tostring(model.currentBuild or ""),tostring(model.currentSnapshotToken or ""),tostring(model.currentConsumerStateFingerprint or ""),tostring(model.currentStateFingerprint or ""),tostring(recipeID),tostring(routeIndex),tostring(skillTarget),tostring(currentSkill or ""),tostring(model.currentNativeCraftable),tostring(model.routeTransitionKind),tostring(model.routeChangeBasis or ""),tostring(model.routeChangeProofToken or ""),tostring(model.restartSourceProofContract or ""),tostring(model.restartSourceProofToken or ""),tostring(model.restartSourceAutoRouteAuthorityContract or ""),tostring(model.restartSourceAutoRoutePromotionContract or ""),tostring(model.currentSourceAuthorityContract or ""),tostring(model.currentSourceDatasetContract or ""),tostring(model.currentSourceReadinessPolicyContract or ""),tostring(model.currentSourceReadinessProofContract or ""),tostring(model.currentSourceReadinessFingerprint or ""),tostring(model.lineageChainToken or ""),tostring(model.lineageRootSessionToken or ""),tostring(model.lineageParentSessionToken or ""),tostring(model.lineageDepth or ""),tostring(model.lineagePredecessorProofToken or "")},"\31")
    local existing=self.candidates[professionKey]
    if type(existing)=="table" and existing.identity==identity and existing.restartReady==true then for k,v in pairs(existing) do model[k]=v end; self.lastByProfession[professionKey]=copy(model); return model end
    self.candidateSerial=(tonumber(self.candidateSerial) or 0)+1
    model.identity=identity; model.candidateToken="autoroute-restart-candidate-"..hash({identity,tostring(self.candidateSerial),tostring(now())}); model.state="auto-route-restart-ready"; model.restartReady=true; model.createdAt=now()
    self.candidates[professionKey]=copy(model); self.lastByProfession[professionKey]=copy(model); return model
end

function ResearchAutoRouteRestart:AuthorizeExplicitRestart(professionKey,mode,source,options)
    professionKey=normalizeKey(professionKey) or "ENGINEERING"; mode=normalizeMode(mode); source=tostring(source or "")
    local candidate=self:Evaluate(professionKey,mode,options)
    if candidate.restartRequired~=true then return false,"auto-route-restart-not-required",candidate end
    if candidate.restartReady~=true then return nil,candidate.state or "auto-route-restart-not-ready",candidate end
    if source~="profession-guide" then return nil,"auto-route-restart-explicit-guide-click-required",candidate end
    local routeHardening=JLP:GetModule("ResearchAutoRouteRouteChangeRestart")
    local hardeningReport
    if routeHardening and routeHardening.Harden then
        local hardeningInput={professionKey=professionKey,mode=mode,interruptionToken=candidate.interruptionToken,interruptionCategory=candidate.interruptionCategory,priorSessionToken=candidate.priorSessionToken,
            priorRecipe=candidate.priorRecipe,priorRecipeID=candidate.priorRecipeID,priorRouteIndex=candidate.priorRouteIndex,priorSkillTarget=candidate.priorSkillTarget,priorSkill=candidate.priorSkill,priorBuild=candidate.priorBuild,
            currentRecipe=candidate.currentRecipe,currentRecipeID=candidate.currentRecipeID,currentRouteIndex=candidate.currentRouteIndex,currentSkillTarget=candidate.currentSkillTarget,currentSkill=candidate.currentSkill,currentBuild=candidate.currentBuild,
            currentSnapshotToken=candidate.currentSnapshotToken,currentConsumerStateFingerprint=candidate.currentConsumerStateFingerprint,currentStateFingerprint=candidate.currentStateFingerprint,
            priorSourceAutoRouteAuthorityContract=candidate.priorSourceAutoRouteAuthorityContract,priorSourceAutoRoutePromotionContract=candidate.priorSourceAutoRoutePromotionContract,currentSourceAuthorityContract=candidate.currentSourceAuthorityContract,currentSourceDatasetContract=candidate.currentSourceDatasetContract,currentSourceReadinessPolicyContract=candidate.currentSourceReadinessPolicyContract,currentSourceReadinessProofContract=candidate.currentSourceReadinessProofContract,currentSourceReadinessFingerprint=candidate.currentSourceReadinessFingerprint}
        local ok,state,transition=routeHardening:Harden(hardeningInput)
        if not ok then return nil,state or "auto-route-restart-route-transition-hardening-failed",candidate end
        hardeningReport=transition
        candidate.routeTransitionKind=transition.transitionKind; candidate.routeChanged=transition.routeChanged==true; candidate.routeChangeBasis=transition.routeChangeBasis; candidate.routeChangeProofToken=transition.proofToken
        if candidate.routeChanged then
            local post=self:Evaluate(professionKey,mode,options)
            local verified,verifyState,verifiedProof=routeHardening:VerifyPostPurge(transition,{professionKey=professionKey,mode=mode,interruptionToken=post.interruptionToken,interruptionCategory=post.interruptionCategory,priorSessionToken=post.priorSessionToken,
                priorRecipe=post.priorRecipe,priorRecipeID=post.priorRecipeID,priorRouteIndex=post.priorRouteIndex,priorSkillTarget=post.priorSkillTarget,priorSkill=post.priorSkill,priorBuild=post.priorBuild,
                currentRecipe=post.currentRecipe,currentRecipeID=post.currentRecipeID,currentRouteIndex=post.currentRouteIndex,currentSkillTarget=post.currentSkillTarget,currentSkill=post.currentSkill,currentBuild=post.currentBuild,
                currentSnapshotToken=post.currentSnapshotToken,currentConsumerStateFingerprint=post.currentConsumerStateFingerprint,currentStateFingerprint=post.currentStateFingerprint,
                priorSourceAutoRouteAuthorityContract=post.priorSourceAutoRouteAuthorityContract,priorSourceAutoRoutePromotionContract=post.priorSourceAutoRoutePromotionContract,currentSourceAuthorityContract=post.currentSourceAuthorityContract,currentSourceDatasetContract=post.currentSourceDatasetContract,currentSourceReadinessPolicyContract=post.currentSourceReadinessPolicyContract,currentSourceReadinessProofContract=post.currentSourceReadinessProofContract,currentSourceReadinessFingerprint=post.currentSourceReadinessFingerprint},transition)
            if not verified then return nil,verifyState or "auto-route-route-change-post-purge-revalidation-failed",post end
            candidate=post; hardeningReport=verifiedProof
            candidate.routeChangeBasis=verifiedProof.routeChangeBasis; candidate.routeChangeProofToken=verifiedProof.proofToken; candidate.routeChangePurgeReceiptToken=verifiedProof.purgeReceiptToken; candidate.routeChangePurgeVerified=verifiedProof.purgeVerified==true; candidate.routeChangePostPurgeRevalidated=verifiedProof.postPurgeRevalidationReady==true
            candidate.routeChangePurgedIntentCount=tonumber(verifiedProof.purgedIntentCount) or 0; candidate.routeChangePurgedReservationCount=tonumber(verifiedProof.purgedReservationCount) or 0; candidate.routeChangePurgedClickOriginCount=tonumber(verifiedProof.purgedClickOriginCount) or 0
        end
    end
    self.authorizationSerial=(tonumber(self.authorizationSerial) or 0)+1; local created=now()
    local auth={contract=self.authorizationContract,token="autoroute-restart-auth-"..hash({candidate.candidateToken,tostring(candidate.currentBuild),tostring(candidate.currentSnapshotToken),tostring(self.authorizationSerial),tostring(created)}),
        candidateToken=candidate.candidateToken,interruptionToken=candidate.interruptionToken,interruptionCategory=candidate.interruptionCategory,interruptionState=candidate.interruptionState,
        professionKey=professionKey,mode=mode,priorSessionToken=candidate.priorSessionToken,priorLedgerID=candidate.priorLedgerID,priorRecipeID=candidate.priorRecipeID,priorRouteIndex=candidate.priorRouteIndex,priorSkillTarget=candidate.priorSkillTarget,
        lineageContract=candidate.lineageContract,lineageChainToken=candidate.lineageChainToken,lineageRootSessionToken=candidate.lineageRootSessionToken,lineageParentSessionToken=candidate.lineageParentSessionToken,lineageDepth=tonumber(candidate.lineageDepth),lineageGeneration=tonumber(candidate.lineageGeneration),lineagePredecessorProofToken=candidate.lineagePredecessorProofToken,lineageHistoryTruncated=candidate.lineageHistoryTruncated==true,
        currentBuild=candidate.currentBuild,currentSnapshotToken=candidate.currentSnapshotToken,currentConsumerStateFingerprint=candidate.currentConsumerStateFingerprint,currentStateFingerprint=candidate.currentStateFingerprint,currentRecipe=candidate.currentRecipe,currentRecipeID=candidate.currentRecipeID,currentRouteIndex=candidate.currentRouteIndex,currentSkillTarget=candidate.currentSkillTarget,
        priorSourceAutoRouteAuthorityContract=candidate.priorSourceAutoRouteAuthorityContract,priorSourceAutoRoutePromotionContract=candidate.priorSourceAutoRoutePromotionContract,currentSourceAuthorityContract=candidate.currentSourceAuthorityContract,currentSourceDatasetContract=candidate.currentSourceDatasetContract,currentSourceReadinessPolicyContract=candidate.currentSourceReadinessPolicyContract,currentSourceReadinessProofContract=candidate.currentSourceReadinessProofContract,currentSourceReadinessFingerprint=candidate.currentSourceReadinessFingerprint,
        restartSourceProofContract=candidate.restartSourceProofContract,restartSourceProofToken=candidate.restartSourceProofToken,restartSourceAutoRouteAuthorityContract=candidate.restartSourceAutoRouteAuthorityContract,restartSourceAutoRoutePromotionContract=candidate.restartSourceAutoRoutePromotionContract,
        routeTransitionKind=candidate.routeTransitionKind,routeChanged=candidate.routeChanged==true,routeChangeBasis=candidate.routeChangeBasis,routeChangeProofToken=candidate.routeChangeProofToken,routeChangePurgeReceiptToken=candidate.routeChangePurgeReceiptToken,routeChangePurgeVerified=candidate.routeChangePurgeVerified==true,routeChangePostPurgeRevalidated=candidate.routeChangePostPurgeRevalidated==true,
        routeChangePurgedIntentCount=tonumber(candidate.routeChangePurgedIntentCount) or 0,routeChangePurgedReservationCount=tonumber(candidate.routeChangePurgedReservationCount) or 0,routeChangePurgedClickOriginCount=tonumber(candidate.routeChangePurgedClickOriginCount) or 0,
        explicitUserClick=true,freshSessionRequired=true,automaticResume=false,priorSessionReusable=false,createdAt=created,expiresAt=created+self.authorizationTTLSeconds,singleUse=true,persisted=false}
    self.authorizations[auth.token]=copy(auth); return copy(auth),"auto-route-restart-explicitly-authorized",candidate
end

function ResearchAutoRouteRestart:ValidateAuthorization(submitted,professionKey,mode,options)
    if type(submitted)~="table" or submitted.contract~=self.authorizationContract then return false,"auto-route-restart-authorization-invalid",nil,nil end
    self:_Sweep(now()); local stored=self.authorizations[tostring(submitted.token or "")]
    if type(stored)~="table" then return false,"auto-route-restart-authorization-expired-or-unknown",nil,nil end
    professionKey=normalizeKey(professionKey); mode=normalizeMode(mode)
    local exact=normalizeKey(stored.professionKey)==professionKey and normalizeMode(stored.mode)==mode and tostring(submitted.candidateToken or "")==tostring(stored.candidateToken or "") and tostring(submitted.interruptionToken or "")==tostring(stored.interruptionToken or "") and tostring(submitted.priorSessionToken or "")==tostring(stored.priorSessionToken or "") and tostring(submitted.lineageContract or "")==tostring(stored.lineageContract or "") and tostring(submitted.lineageChainToken or "")==tostring(stored.lineageChainToken or "") and tostring(submitted.lineageRootSessionToken or "")==tostring(stored.lineageRootSessionToken or "") and tostring(submitted.lineageParentSessionToken or "")==tostring(stored.lineageParentSessionToken or "") and tonumber(submitted.lineageDepth)==tonumber(stored.lineageDepth) and tostring(submitted.lineagePredecessorProofToken or "")==tostring(stored.lineagePredecessorProofToken or "") and tonumber(submitted.currentBuild)==tonumber(stored.currentBuild) and tostring(submitted.currentSnapshotToken or "")==tostring(stored.currentSnapshotToken or "") and tostring(submitted.currentConsumerStateFingerprint or "")==tostring(stored.currentConsumerStateFingerprint or "") and tostring(submitted.currentStateFingerprint or "")==tostring(stored.currentStateFingerprint or "") and tonumber(submitted.currentRecipeID)==tonumber(stored.currentRecipeID) and tonumber(submitted.currentRouteIndex)==tonumber(stored.currentRouteIndex) and tonumber(submitted.currentSkillTarget)==tonumber(stored.currentSkillTarget) and tostring(submitted.routeTransitionKind or "")==tostring(stored.routeTransitionKind or "") and (submitted.routeChanged==true)==(stored.routeChanged==true) and tostring(submitted.routeChangeBasis or "")==tostring(stored.routeChangeBasis or "") and tostring(submitted.routeChangeProofToken or "")==tostring(stored.routeChangeProofToken or "") and tostring(submitted.routeChangePurgeReceiptToken or "")==tostring(stored.routeChangePurgeReceiptToken or "") and (submitted.routeChangePurgeVerified==true)==(stored.routeChangePurgeVerified==true) and (submitted.routeChangePostPurgeRevalidated==true)==(stored.routeChangePostPurgeRevalidated==true) and tostring(submitted.restartSourceProofContract or "")==tostring(stored.restartSourceProofContract or "") and tostring(submitted.restartSourceProofToken or "")==tostring(stored.restartSourceProofToken or "") and tostring(submitted.restartSourceAutoRouteAuthorityContract or "")==tostring(stored.restartSourceAutoRouteAuthorityContract or "") and tostring(submitted.restartSourceAutoRoutePromotionContract or "")==tostring(stored.restartSourceAutoRoutePromotionContract or "") and tostring(submitted.currentSourceAuthorityContract or "")==tostring(stored.currentSourceAuthorityContract or "") and tostring(submitted.currentSourceDatasetContract or "")==tostring(stored.currentSourceDatasetContract or "") and tostring(submitted.currentSourceReadinessPolicyContract or "")==tostring(stored.currentSourceReadinessPolicyContract or "") and tostring(submitted.currentSourceReadinessProofContract or "")==tostring(stored.currentSourceReadinessProofContract or "") and tostring(submitted.currentSourceReadinessFingerprint or "")==tostring(stored.currentSourceReadinessFingerprint or "") and submitted.explicitUserClick==true and submitted.freshSessionRequired==true and submitted.automaticResume==false and submitted.priorSessionReusable==false
    if not exact then return false,"auto-route-restart-authorization-tampered",nil,copy(stored) end
    local current=self:Evaluate(professionKey,mode,options)
    local currentExact=current and current.restartReady==true and tostring(current.candidateToken or "")==tostring(stored.candidateToken or "") and tostring(current.interruptionToken or "")==tostring(stored.interruptionToken or "") and tostring(current.lineageChainToken or "")==tostring(stored.lineageChainToken or "") and tostring(current.lineageRootSessionToken or "")==tostring(stored.lineageRootSessionToken or "") and tostring(current.lineageParentSessionToken or "")==tostring(stored.lineageParentSessionToken or "") and tonumber(current.lineageDepth)==tonumber(stored.lineageDepth) and tostring(current.lineagePredecessorProofToken or "")==tostring(stored.lineagePredecessorProofToken or "") and tonumber(current.currentBuild)==tonumber(stored.currentBuild) and tostring(current.currentSnapshotToken or "")==tostring(stored.currentSnapshotToken or "") and tostring(current.currentConsumerStateFingerprint or "")==tostring(stored.currentConsumerStateFingerprint or "") and tostring(current.currentStateFingerprint or "")==tostring(stored.currentStateFingerprint or "") and tonumber(current.currentRecipeID)==tonumber(stored.currentRecipeID) and tonumber(current.currentRouteIndex)==tonumber(stored.currentRouteIndex) and tonumber(current.currentSkillTarget)==tonumber(stored.currentSkillTarget) and tostring(current.routeTransitionKind or "")==tostring(stored.routeTransitionKind or "") and (current.routeChanged==true)==(stored.routeChanged==true) and tostring(current.routeChangeBasis or "")==tostring(stored.routeChangeBasis or "") and tostring(current.routeChangeProofToken or "")==tostring(stored.routeChangeProofToken or "") and tostring(current.restartSourceProofContract or "")==tostring(stored.restartSourceProofContract or "") and tostring(current.restartSourceProofToken or "")==tostring(stored.restartSourceProofToken or "") and tostring(current.restartSourceAutoRouteAuthorityContract or "")==tostring(stored.restartSourceAutoRouteAuthorityContract or "") and tostring(current.restartSourceAutoRoutePromotionContract or "")==tostring(stored.restartSourceAutoRoutePromotionContract or "") and tostring(current.currentSourceAuthorityContract or "")==tostring(stored.currentSourceAuthorityContract or "") and tostring(current.currentSourceDatasetContract or "")==tostring(stored.currentSourceDatasetContract or "") and tostring(current.currentSourceReadinessPolicyContract or "")==tostring(stored.currentSourceReadinessPolicyContract or "") and tostring(current.currentSourceReadinessProofContract or "")==tostring(stored.currentSourceReadinessProofContract or "") and tostring(current.currentSourceReadinessFingerprint or "")==tostring(stored.currentSourceReadinessFingerprint or "")
    if not currentExact then return false,"auto-route-restart-authorization-stale",current,copy(stored) end
    return true,"auto-route-restart-authorization-current",current,copy(stored)
end

function ResearchAutoRouteRestart:ConsumeAuthorization(authorizationOrToken,reason)
    local token=type(authorizationOrToken)=="table" and authorizationOrToken.token or authorizationOrToken; token=tostring(token or "")
    local stored=self.authorizations[token]; if not stored then return false,"auto-route-restart-authorization-expired-or-unknown" end
    self.authorizations[token]=nil; stored.consumed=true; stored.consumedAt=now(); stored.consumeReason=tostring(reason or "fresh-auto-route-session-created")
    local key=normalizeKey(stored.professionKey); if key then self.consumedInterruptionByProfession[key]=stored.interruptionToken; self.candidates[key]=nil; local last=copy(stored); last.state="auto-route-restart-authorization-consumed"; last.restartReady=false; self.lastByProfession[key]=last end
    return true,"auto-route-restart-authorization-consumed",copy(stored)
end

function ResearchAutoRouteRestart:GetLast(professionKey) local row=self.lastByProfession[normalizeKey(professionKey)]; return row and copy(row) or nil end
function ResearchAutoRouteRestart:GetSummary(professionKey,mode,options)
    local model=self:Evaluate(professionKey,mode,options)
    local lines={"AUTO ROUTE / FRESH-CLICK RESTART LIFECYCLE",tostring(model.professionKey).." / "..tostring(model.mode),"Contract: "..self.contract,"State: "..tostring(model.state),"Restart required: "..(model.restartRequired and "yes" or "no"),"Restart ready: "..(model.restartReady and "yes" or "no"),"Interruption: "..tostring(model.interruptionCategory or "none"),"Prior session: "..tostring(model.priorSessionToken or "none"),"Lineage parent: "..tostring(model.lineageParentSessionToken or "none"),"Lineage root: "..tostring(model.lineageRootSessionToken or "none"),"Lineage depth: "..tostring(model.lineageDepth or "none"),"Immediate predecessor proof: "..tostring(model.lineagePredecessorProofToken or "none"),"Current recipe: "..tostring(model.currentRecipe or "none").." / "..tostring(model.currentRecipeID or "unresolved"),"Route transition: "..tostring(model.routeTransitionKind or "unknown"),"Route-change basis: "..tostring(model.routeChangeBasis or "unknown"),"Route-change proof: "..tostring(model.routeChangeProofToken or "none"),"Production source proof: "..tostring(model.restartSourceProofToken or "none"),"Source Auto Route authority: "..tostring(model.restartSourceAutoRouteAuthorityContract or model.priorSourceAutoRouteAuthorityContract or "none"),"New explicit Guide click: required","Fresh session token: required","Fresh ledger per craft: required","Automatic resume: disabled","Prior session reuse: forbidden","Persistence: none"}
    return table.concat(lines,"\n")
end
function ResearchAutoRouteRestart:Validate()
    local errors,warnings={},{}
    if self.automaticResume~=false or self.priorSessionReusable~=false or self.freshSessionRequired~=true or self.persisted~=false then errors[#errors+1]="Auto Route restart safety boundary invalid" end
    for _,name in ipairs({"ResearchAutoRouteSessionLineage","ResearchAutoRouteInterruption","ResearchAutoRouteOrchestrator","ResearchSequentialStopPolicy","ResearchExecutionReadiness","ResearchRouteChangingRestart","ResearchAutoRouteRouteChangeRestart","ProductionTailoringAutoRouteRestart"}) do if not JLP:GetModule(name) then errors[#errors+1]="Auto Route restart dependency missing: "..name end end
    return #errors==0,errors,warnings
end

JLP:RegisterModule("ResearchAutoRouteRestart",ResearchAutoRouteRestart)
