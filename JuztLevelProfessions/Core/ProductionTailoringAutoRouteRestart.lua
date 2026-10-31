local _, JLP = ...

-- Alpha104 binds every fresh production Tailoring Auto Route restart to the
-- production source that created the terminal predecessor.  The generic alpha92-
-- alpha95 restart/route/lineage machinery remains the lifecycle owner; this module
-- adds a fail-closed source proof so research-source interruptions, stale dataset
-- identities or non-production readiness proofs cannot authorize Tailoring.
local ProductionTailoringAutoRouteRestart = {
    contract = "production-tailoring-auto-route-fresh-restart-hardening-v1",
    proofContract = "production-tailoring-auto-route-restart-source-proof-v1",
    interruptionContract = "production-tailoring-auto-route-source-bound-interruption-v1",
    authority = "source-bound-fresh-click-production-tailoring-auto-route-restart-only",
    professionKey = "TAILORING",
    nativeDispatchAllowed = false,
    automaticResume = false,
    priorSessionReusable = false,
    persisted = false,
    serial = 0,
    last = nil,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function hash(parts)
    local value = table.concat(parts or {}, "\31")
    local h = 5381
    for i = 1, #value do h = (h * 33 + string.byte(value, i)) % 2147483647 end
    return string.format("%08x", h)
end

local function copy(row)
    local out = {}
    for k, v in pairs(row or {}) do out[k] = v end
    return out
end

function ProductionTailoringAutoRouteRestart:Assess(interruption, current)
    interruption = type(interruption) == "table" and interruption or {}
    current = type(current) == "table" and current or {}
    local report = {
        contract = self.contract,
        proofContract = self.proofContract,
        interruptionContract = self.interruptionContract,
        authority = self.authority,
        professionKey = normalizeKey(current.professionKey or interruption.professionKey),
        interruptionToken = interruption.interruptionToken,
        priorSessionToken = interruption.priorSessionToken,
        priorSourceAutoRouteAuthorityContract = interruption.sourceAutoRouteAuthorityContract,
        priorSourceAutoRoutePromotionContract = interruption.sourceAutoRoutePromotionContract,
        currentSourceAuthorityContract = current.currentSourceAuthorityContract,
        currentSourceDatasetContract = current.currentSourceDatasetContract,
        currentSourceReadinessPolicyContract = current.currentSourceReadinessPolicyContract,
        currentSourceReadinessProofContract = current.currentSourceReadinessProofContract,
        currentSourceReadinessFingerprint = current.currentSourceReadinessFingerprint,
        currentSnapshotToken = current.currentSnapshotToken,
        currentConsumerStateFingerprint = current.currentConsumerStateFingerprint,
        currentStateFingerprint = current.currentStateFingerprint,
        currentRecipeID = tonumber(current.currentRecipeID),
        currentRouteIndex = tonumber(current.currentRouteIndex),
        currentSkillTarget = tonumber(current.currentSkillTarget),
        currentBuild = tonumber(current.currentBuild),
        routeChangeProofToken = current.routeChangeProofToken,
        ready = false,
        nativeDispatchAllowed = false,
        automaticResume = false,
        priorSessionReusable = false,
        persisted = false,
        state = "production-tailoring-auto-route-restart-source-proof-evaluating",
    }

    if report.professionKey ~= self.professionKey then
        report.state = "production-tailoring-auto-route-restart-profession-mismatch"
        return report
    end

    local promotion = JLP:GetModule("ProductionTailoringAutoRouteAuthority")
    local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
    local readiness = JLP:GetModule("ProductionTailoringExecutionReadiness")
    if not promotion or not adapter or not readiness then
        report.state = "production-tailoring-auto-route-restart-source-dependency-unavailable"
        return report
    end

    report.expectedSourceAutoRouteAuthorityContract = promotion.contract
    report.expectedSourceAutoRoutePromotionContract = promotion.promotionContract
    report.expectedSourceAuthorityContract = adapter.contract
    report.expectedSourceDatasetContract = adapter.datasetContract
    report.expectedSourceReadinessPolicyContract = readiness.contract
    report.expectedSourceReadinessProofContract = readiness.proofContract

    if tostring(report.priorSourceAutoRouteAuthorityContract or "") ~= tostring(promotion.contract or "") then
        report.state = "production-tailoring-auto-route-restart-source-authority-mismatch"
        return report
    end
    if tostring(report.priorSourceAutoRoutePromotionContract or "") ~= tostring(promotion.promotionContract or "") then
        report.state = "production-tailoring-auto-route-restart-source-promotion-mismatch"
        return report
    end
    if tostring(report.currentSourceAuthorityContract or "") ~= tostring(adapter.contract or "") then
        report.state = "production-tailoring-auto-route-restart-consumer-source-mismatch"
        return report
    end
    if tostring(report.currentSourceDatasetContract or "") ~= tostring(adapter.datasetContract or "") then
        report.state = "production-tailoring-auto-route-restart-dataset-source-mismatch"
        return report
    end
    if tostring(report.currentSourceReadinessPolicyContract or "") ~= tostring(readiness.contract or "") then
        report.state = "production-tailoring-auto-route-restart-readiness-policy-mismatch"
        return report
    end
    if tostring(report.currentSourceReadinessProofContract or "") ~= tostring(readiness.proofContract or "") then
        report.state = "production-tailoring-auto-route-restart-readiness-proof-mismatch"
        return report
    end
    if not report.interruptionToken or not report.priorSessionToken or not report.currentSnapshotToken
        or not report.currentConsumerStateFingerprint or not report.currentStateFingerprint
        or not report.currentSourceReadinessFingerprint or not report.currentRecipeID
        or not report.currentRouteIndex or not report.currentSkillTarget or not report.currentBuild then
        report.state = "production-tailoring-auto-route-restart-source-proof-incomplete"
        return report
    end

    report.proofToken = "tailoring-autoroute-restart-source-" .. hash({
        tostring(report.interruptionToken), tostring(report.priorSessionToken),
        tostring(report.priorSourceAutoRouteAuthorityContract), tostring(report.priorSourceAutoRoutePromotionContract),
        tostring(report.currentSourceAuthorityContract), tostring(report.currentSourceDatasetContract),
        tostring(report.currentSourceReadinessPolicyContract), tostring(report.currentSourceReadinessProofContract), tostring(report.currentSourceReadinessFingerprint),
        tostring(report.currentSnapshotToken), tostring(report.currentConsumerStateFingerprint), tostring(report.currentStateFingerprint),
        tostring(report.currentRecipeID), tostring(report.currentRouteIndex), tostring(report.currentSkillTarget), tostring(report.currentBuild),
        tostring(report.routeChangeProofToken or ""),
    })
    report.ready = true
    report.state = "production-tailoring-auto-route-restart-source-proof-ready"
    self.last = copy(report)
    return report
end

function ProductionTailoringAutoRouteRestart:GetLast()
    return self.last and copy(self.last) or nil
end

function ProductionTailoringAutoRouteRestart:GetSummary()
    local row = self:GetLast()
    local lines = {
        "PRODUCTION TAILORING / AUTO ROUTE FRESH-RESTART SOURCE HARDENING",
        "Contract: " .. self.contract,
        "Proof contract: " .. self.proofContract,
        "Authority: source-bound fresh explicit click only",
        "Prior production source required: yes",
        "Current production consumer/readiness source required: yes",
        "Automatic resume: disabled",
        "Prior session reuse: forbidden",
        "Native dispatch: forbidden",
        "Persistence: none",
        "Last state: " .. tostring(row and row.state or "none"),
        "Last proof: " .. tostring(row and row.proofToken or "none"),
    }
    return table.concat(lines, "\n")
end

function ProductionTailoringAutoRouteRestart:Validate()
    local errors, warnings = {}, {}
    if self.nativeDispatchAllowed ~= false then errors[#errors+1] = "production Tailoring Auto Route restart hardening must not dispatch native work" end
    if self.automaticResume ~= false then errors[#errors+1] = "production Tailoring Auto Route restart hardening must not auto-resume" end
    if self.priorSessionReusable ~= false then errors[#errors+1] = "production Tailoring Auto Route prior sessions must remain terminal" end
    if self.persisted ~= false then errors[#errors+1] = "production Tailoring Auto Route restart proof must not persist" end
    for _, name in ipairs({"ProductionTailoringAutoRouteAuthority", "ProductionTailoringAuthorityAdapter", "ProductionTailoringExecutionReadiness", "ResearchAutoRouteRestart", "ResearchAutoRouteInterruption"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "production Tailoring Auto Route restart dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringAutoRouteRestart", ProductionTailoringAutoRouteRestart)
