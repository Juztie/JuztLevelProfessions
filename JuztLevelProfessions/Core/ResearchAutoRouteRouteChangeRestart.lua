local _, JLP = ...

-- Alpha93 hardens route-changing production Auto Route restarts. Alpha92 already
-- guarantees that a stopped session is terminal and that restart needs a fresh
-- explicit click. This layer proves that abandoning the prior route identity is
-- legitimate, purges every profession-scoped pre-dispatch artifact from the old
-- route, and requires a post-purge revalidation before restart authorization can
-- become execution provenance.
local ResearchAutoRouteRouteChangeRestart = {
    contract = "production-auto-route-route-changing-restart-hardening-v1",
    proofContract = "research-auto-route-route-change-restart-proof-v1",
    purgeReceiptContract = "research-auto-route-stale-authority-purge-receipt-v1",
    authority = "route-change-basis-proof-stale-authority-purge-post-purge-revalidation-only",
    nativeDispatchAllowed = false,
    automaticResume = false,
    persisted = false,
    serial = 0,
    lastByProfession = {},
}

local AUTHORITATIVE_REPLAN = {
    TRAIN=true,
    LEARN_RECIPE=true,
    LEARN_PROFESSION=true,
    VERIFY_RECIPE=true,
    RECIPE_ACCESS=true,
    AUTHORITY_REVALIDATION=true,
    PLANNER_PARITY=true,
    BUILD_CHANGED=true,
    REPLAN_PENDING=true,
    ROUTE_BLOCKED=true,
}

local function normalizeKey(value)
    local key=tostring(value or ""):upper()
    return key~="" and key or nil
end

local function normalizeCategory(value)
    local category=tostring(value or ""):upper()
    return category~="" and category or "OTHER"
end

local function now()
    if type(GetTime)=="function" then local ok,v=pcall(GetTime); if ok and tonumber(v) then return tonumber(v) end end
    if type(time)=="function" then local ok,v=pcall(time); if ok and tonumber(v) then return tonumber(v) end end
    return 0
end

local function hash(parts)
    local value=table.concat(parts or {},"\31")
    local h=5381
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

local function changed(a,b)
    if a==nil or b==nil then return false end
    return tostring(a)~=tostring(b)
end

function ResearchAutoRouteRouteChangeRestart:IsAuthoritativeReplanCategory(category)
    return AUTHORITATIVE_REPLAN[normalizeCategory(category)]==true
end

function ResearchAutoRouteRouteChangeRestart:Assess(model)
    model=type(model)=="table" and model or {}
    local report={
        contract=self.contract,
        proofContract=self.proofContract,
        purgeReceiptContract=self.purgeReceiptContract,
        authority=self.authority,
        professionKey=normalizeKey(model.professionKey),
        mode=model.mode,
        interruptionToken=model.interruptionToken,
        interruptionCategory=normalizeCategory(model.interruptionCategory),
        priorSessionToken=model.priorSessionToken,
        priorRecipe=model.priorRecipe,
        priorRecipeID=tonumber(model.priorRecipeID),
        priorRouteIndex=tonumber(model.priorRouteIndex),
        priorSkillTarget=tonumber(model.priorSkillTarget),
        priorSkill=tonumber(model.priorSkill),
        priorBuild=tonumber(model.priorBuild),
        currentRecipe=model.currentRecipe,
        currentRecipeID=tonumber(model.currentRecipeID),
        currentRouteIndex=tonumber(model.currentRouteIndex),
        currentSkillTarget=tonumber(model.currentSkillTarget),
        currentSkill=tonumber(model.currentSkill),
        currentBuild=tonumber(model.currentBuild),
        currentSnapshotToken=model.currentSnapshotToken,
        currentConsumerStateFingerprint=model.currentConsumerStateFingerprint,
        currentStateFingerprint=model.currentStateFingerprint,
        priorSourceAutoRouteAuthorityContract=model.priorSourceAutoRouteAuthorityContract,
        priorSourceAutoRoutePromotionContract=model.priorSourceAutoRoutePromotionContract,
        currentSourceAuthorityContract=model.currentSourceAuthorityContract,
        currentSourceDatasetContract=model.currentSourceDatasetContract,
        currentSourceReadinessPolicyContract=model.currentSourceReadinessPolicyContract,
        currentSourceReadinessProofContract=model.currentSourceReadinessProofContract,
        currentSourceReadinessFingerprint=model.currentSourceReadinessFingerprint,
        nativeDispatchAllowed=false,
        automaticResume=false,
        persisted=false,
        ready=false,
        state="auto-route-route-change-proof-evaluating",
    }

    report.recipeChanged=changed(report.priorRecipeID or report.priorRecipe,report.currentRecipeID or report.currentRecipe)
    report.routeIndexChanged=changed(report.priorRouteIndex,report.currentRouteIndex)
    report.skillTargetChanged=changed(report.priorSkillTarget,report.currentSkillTarget)
    report.routeChanged=report.recipeChanged or report.routeIndexChanged
    report.transitionKind=report.routeChanged and "route-changing" or "same-route"
    report.priorTargetReached=report.priorSkill~=nil and report.priorSkillTarget~=nil and report.priorSkill>=report.priorSkillTarget or false
    report.authoritativeReplanCategory=self:IsAuthoritativeReplanCategory(report.interruptionCategory)

    if not report.routeChanged then
        report.routeChangeBasis="SAME_ROUTE"
        report.state="auto-route-same-route-restart-proof-ready"
        report.ready=true
    else
        if not report.priorRecipeID or not report.priorRouteIndex or not report.priorSkillTarget then
            report.state="auto-route-route-change-prior-identity-incomplete"
            return report
        end
        if not report.currentRecipe or not report.currentRecipeID or not report.currentRouteIndex or not report.currentSkillTarget then
            report.state="auto-route-route-change-current-identity-incomplete"
            return report
        end
        if not report.currentBuild or not report.currentSnapshotToken or not report.currentConsumerStateFingerprint or not report.currentStateFingerprint then
            report.state="auto-route-route-change-current-authority-incomplete"
            return report
        end

        if report.priorTargetReached then
            report.routeChangeBasis="PRIOR_TARGET_REACHED"
            if report.currentRouteIndex<=report.priorRouteIndex and not report.authoritativeReplanCategory then
                report.state="auto-route-route-change-nonforward-without-authoritative-replan"
                return report
            end
        elseif report.authoritativeReplanCategory then
            report.routeChangeBasis="AUTHORITATIVE_REPLAN_"..report.interruptionCategory
        else
            report.routeChangeBasis="UNPROVEN"
            report.state="auto-route-route-change-basis-unproven"
            return report
        end
        report.state="auto-route-route-change-proof-ready"
        report.ready=true
    end

    self.serial=(tonumber(self.serial) or 0)+1
    report.proofToken="autoroute-route-change-proof-"..hash({
        tostring(report.interruptionToken or ""),tostring(report.priorSessionToken or ""),
        tostring(report.interruptionCategory),tostring(report.routeChangeBasis or ""),
        tostring(report.priorRecipeID or ""),tostring(report.priorRouteIndex or ""),tostring(report.priorSkillTarget or ""),tostring(report.priorSkill or ""),
        tostring(report.currentRecipeID or ""),tostring(report.currentRouteIndex or ""),tostring(report.currentSkillTarget or ""),tostring(report.currentSkill or ""),
        tostring(report.currentBuild or ""),tostring(report.currentSnapshotToken or ""),tostring(report.currentConsumerStateFingerprint or ""),tostring(report.currentStateFingerprint or ""),
        tostring(report.priorSourceAutoRouteAuthorityContract or ""),tostring(report.priorSourceAutoRoutePromotionContract or ""),
        tostring(report.currentSourceAuthorityContract or ""),tostring(report.currentSourceDatasetContract or ""),
        tostring(report.currentSourceReadinessPolicyContract or ""),tostring(report.currentSourceReadinessProofContract or ""),tostring(report.currentSourceReadinessFingerprint or ""),
    })
    return report
end

local function countReadinessIntents(readiness,professionKey)
    if readiness and readiness.CountIntentsForProfession then return tonumber(readiness:CountIntentsForProfession(professionKey)) or 0 end
    local count=0
    for _,intent in pairs(readiness and readiness.intents or {}) do if normalizeKey(intent and intent.professionKey)==professionKey then count=count+1 end end
    return count
end

local function countGateArtifacts(gate,professionKey)
    if gate and gate.CountArtifactsForProfession then
        local row=gate:CountArtifactsForProfession(professionKey)
        return tonumber(row and row.reservations) or 0,tonumber(row and row.clickOrigins) or 0
    end
    local reservations,origins=0,0
    for _,row in pairs(gate and gate.reservations or {}) do if normalizeKey(row and row.professionKey)==professionKey then reservations=reservations+1 end end
    for _,row in pairs(gate and gate.clickOrigins or {}) do if normalizeKey(row and row.professionKey)==professionKey then origins=origins+1 end end
    return reservations,origins
end

function ResearchAutoRouteRouteChangeRestart:Harden(model)
    local report=self:Assess(model)
    if report.ready~=true then return false,report.state,report end
    if report.routeChanged~=true then
        report.purgeVerified=true
        report.purgeReceiptToken=nil
        report.postPurgeRevalidationRequired=false
        if report.professionKey then self.lastByProfession[report.professionKey]=copy(report) end
        return true,report.state,report
    end

    local readiness=JLP:GetModule("ResearchExecutionReadiness")
    local gate=JLP:GetModule("ResearchExecutionAuthorityGate")
    local legacy=JLP:GetModule("ResearchRouteChangingRestart")
    if not readiness or not gate or not legacy or not legacy.Harden then
        report.state="auto-route-route-change-purge-dependency-unavailable"
        return false,report.state,report
    end

    local beforeIntents=countReadinessIntents(readiness,report.professionKey)
    local beforeReservations,beforeOrigins=countGateArtifacts(gate,report.professionKey)
    local ok,state,legacyReport=legacy:Harden(model)
    if not ok then
        report.state=state or "auto-route-route-change-legacy-hardening-failed"
        report.legacyTransitionState=legacyReport and legacyReport.state or nil
        return false,report.state,report
    end
    local afterIntents=countReadinessIntents(readiness,report.professionKey)
    local afterReservations,afterOrigins=countGateArtifacts(gate,report.professionKey)
    report.purgeBefore={intents=beforeIntents,reservations=beforeReservations,clickOrigins=beforeOrigins}
    report.purgeAfter={intents=afterIntents,reservations=afterReservations,clickOrigins=afterOrigins}
    report.purgedIntentCount=math.max(0,beforeIntents-afterIntents)
    report.purgedReservationCount=math.max(0,beforeReservations-afterReservations)
    report.purgedClickOriginCount=math.max(0,beforeOrigins-afterOrigins)
    report.purgeVerified=afterIntents==0 and afterReservations==0 and afterOrigins==0
    report.oldExecutionArtifactsPurged=report.purgeVerified
    report.postPurgeRevalidationRequired=true
    if not report.purgeVerified then
        report.state="auto-route-route-change-stale-authority-purge-incomplete"
        if report.professionKey then self.lastByProfession[report.professionKey]=copy(report) end
        return false,report.state,report
    end
    report.purgeReceiptToken="autoroute-route-change-purge-"..hash({
        tostring(report.proofToken or ""),tostring(beforeIntents),tostring(beforeReservations),tostring(beforeOrigins),
        tostring(afterIntents),tostring(afterReservations),tostring(afterOrigins),tostring(now()),
    })
    report.state="auto-route-route-change-purge-verified"
    if report.professionKey then self.lastByProfession[report.professionKey]=copy(report) end
    return true,report.state,copy(report)
end

function ResearchAutoRouteRouteChangeRestart:VerifyPostPurge(beforeProof,currentModel,purgeReport)
    if type(beforeProof)~="table" or beforeProof.ready~=true then return false,"auto-route-route-change-post-purge-proof-missing",nil end
    if beforeProof.routeChanged~=true then return true,"auto-route-same-route-post-purge-not-required",beforeProof end
    if type(purgeReport)~="table" or purgeReport.purgeVerified~=true or not purgeReport.purgeReceiptToken then return false,"auto-route-route-change-purge-receipt-missing",nil end
    local after=self:Assess(currentModel)
    local exact=after.ready==true and after.routeChanged==true
        and tostring(after.routeChangeBasis or "")==tostring(beforeProof.routeChangeBasis or "")
        and tostring(after.interruptionToken or "")==tostring(beforeProof.interruptionToken or "")
        and tostring(after.priorSessionToken or "")==tostring(beforeProof.priorSessionToken or "")
        and tonumber(after.priorRecipeID)==tonumber(beforeProof.priorRecipeID)
        and tonumber(after.priorRouteIndex)==tonumber(beforeProof.priorRouteIndex)
        and tonumber(after.priorSkillTarget)==tonumber(beforeProof.priorSkillTarget)
        and tonumber(after.currentRecipeID)==tonumber(beforeProof.currentRecipeID)
        and tonumber(after.currentRouteIndex)==tonumber(beforeProof.currentRouteIndex)
        and tonumber(after.currentSkillTarget)==tonumber(beforeProof.currentSkillTarget)
        and tonumber(after.currentBuild)==tonumber(beforeProof.currentBuild)
        and tostring(after.currentSnapshotToken or "")==tostring(beforeProof.currentSnapshotToken or "")
        and tostring(after.currentConsumerStateFingerprint or "")==tostring(beforeProof.currentConsumerStateFingerprint or "")
        and tostring(after.currentStateFingerprint or "")==tostring(beforeProof.currentStateFingerprint or "")
        and tostring(after.priorSourceAutoRouteAuthorityContract or "")==tostring(beforeProof.priorSourceAutoRouteAuthorityContract or "")
        and tostring(after.priorSourceAutoRoutePromotionContract or "")==tostring(beforeProof.priorSourceAutoRoutePromotionContract or "")
        and tostring(after.currentSourceAuthorityContract or "")==tostring(beforeProof.currentSourceAuthorityContract or "")
        and tostring(after.currentSourceDatasetContract or "")==tostring(beforeProof.currentSourceDatasetContract or "")
        and tostring(after.currentSourceReadinessPolicyContract or "")==tostring(beforeProof.currentSourceReadinessPolicyContract or "")
        and tostring(after.currentSourceReadinessProofContract or "")==tostring(beforeProof.currentSourceReadinessProofContract or "")
        and tostring(after.currentSourceReadinessFingerprint or "")==tostring(beforeProof.currentSourceReadinessFingerprint or "")
    if not exact then
        after.state="auto-route-route-change-post-purge-revalidation-drifted"
        after.postPurgeRevalidationReady=false
        return false,after.state,after
    end
    after.proofToken=beforeProof.proofToken
    after.purgeReceiptToken=purgeReport.purgeReceiptToken
    after.purgeVerified=true
    after.purgedIntentCount=purgeReport.purgedIntentCount
    after.purgedReservationCount=purgeReport.purgedReservationCount
    after.purgedClickOriginCount=purgeReport.purgedClickOriginCount
    after.postPurgeRevalidationReady=true
    after.state="auto-route-route-change-post-purge-revalidated"
    if after.professionKey then self.lastByProfession[after.professionKey]=copy(after) end
    return true,after.state,copy(after)
end

function ResearchAutoRouteRouteChangeRestart:GetLast(professionKey)
    local row=self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ResearchAutoRouteRouteChangeRestart:GetSummary(professionKey)
    local row=self:GetLast(professionKey)
    local lines={
        "AUTO ROUTE / ROUTE-CHANGING RESTART HARDENING",
        tostring(normalizeKey(professionKey) or "UNKNOWN"),
        "Contract: "..self.contract,
        "Authority: proof + stale-authority purge + post-purge revalidation only",
        "Native dispatch: forbidden",
        "Automatic resume: disabled",
        "Persistence: none",
        "Last state: "..tostring(row and row.state or "none"),
    }
    if row then
        lines[#lines+1]="Transition: "..tostring(row.transitionKind or "unknown")
        lines[#lines+1]="Basis: "..tostring(row.routeChangeBasis or "unknown")
        lines[#lines+1]="Interruption: "..tostring(row.interruptionCategory or "unknown")
        lines[#lines+1]="Old route: "..tostring(row.priorRouteIndex or "?").." / "..tostring(row.priorRecipe or row.priorRecipeID or "unknown")
        lines[#lines+1]="New route: "..tostring(row.currentRouteIndex or "?").." / "..tostring(row.currentRecipe or row.currentRecipeID or "unknown")
        lines[#lines+1]="Purge verified: "..(row.purgeVerified and "yes" or "no")
        lines[#lines+1]="Post-purge revalidation: "..(row.postPurgeRevalidationReady and "ready" or (row.postPurgeRevalidationRequired and "required" or "not required"))
    end
    return table.concat(lines,"\n")
end

function ResearchAutoRouteRouteChangeRestart:Validate()
    local errors,warnings={},{}
    if self.nativeDispatchAllowed~=false or self.automaticResume~=false or self.persisted~=false then errors[#errors+1]="Auto Route route-change restart hardening authority boundary invalid" end
    for _,name in ipairs({"ResearchRouteChangingRestart","ResearchExecutionReadiness","ResearchExecutionAuthorityGate"}) do if not JLP:GetModule(name) then errors[#errors+1]="Auto Route route-change hardening dependency missing: "..name end end
    return #errors==0,errors,warnings
end

JLP:RegisterModule("ResearchAutoRouteRouteChangeRestart",ResearchAutoRouteRouteChangeRestart)
