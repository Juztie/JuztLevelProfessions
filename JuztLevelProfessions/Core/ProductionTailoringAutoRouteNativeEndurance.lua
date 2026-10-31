local _, JLP = ...

-- Alpha106 is an observational runtime endurance monitor for the real production
-- Tailoring Auto Route execution path.  It never dispatches crafting itself; it
-- records terminal production Auto Route Craft One actions and audits the shared
-- reservation / ledger / lineage state after longer native-style segments.
local NativeEndurance = {
    contract = "production-tailoring-auto-route-native-segmented-endurance-v1",
    observationContract = "production-tailoring-auto-route-native-endurance-observation-v1",
    hygieneContract = "production-tailoring-auto-route-post-segment-hygiene-v1",
    authority = "observational-production-tailoring-native-endurance-only",
    professionKey = "TAILORING",
    nativeDispatchAllowed = false,
    automaticExecutionAllowed = false,
    persisted = false,
    initialized = false,
    run = nil,
    lastAudit = nil,
}

local function copy(row)
    local out = {}
    for k,v in pairs(row or {}) do out[k] = v end
    return out
end

local function terminal(status)
    status = tostring(status or "")
    return status == "success" or status == "failed" or status == "timeout" or status == "aborted_unknown"
end

local function productionSourceContract()
    local source = JLP:GetModule("ProductionTailoringAutoRouteAuthority")
    return source and source.contract or "production-tailoring-auto-route-authority-v1"
end

local function productionNativeProvenance()
    local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    return native and native.provenanceContract or "production-tailoring-native-dispatch-provenance-v1"
end

function NativeEndurance:Reset(label)
    self.run = {
        contract = self.contract,
        observationContract = self.observationContract,
        hygieneContract = self.hygieneContract,
        authority = self.authority,
        label = tostring(label or "runtime"),
        professionKey = self.professionKey,
        terminalActions = 0,
        successfulSettlements = 0,
        failedSettlements = 0,
        skillGainSettlements = 0,
        noSkillGainSettlements = 0,
        duplicateTerminalEvents = 0,
        uniqueLedgers = 0,
        uniqueSessions = 0,
        routeTransitionsObserved = 0,
        recipeTransitionsObserved = 0,
        terminalLedgers = {},
        sessions = {},
        recipes = {},
        lastRouteIndex = nil,
        lastRecipeID = nil,
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
    }
    self.lastAudit = nil
    return self.run
end

function NativeEndurance:_EnsureRun()
    return self.run or self:Reset("runtime")
end

function NativeEndurance:ObserveCraftAction(action)
    if type(action) ~= "table" or tostring(action.key or ""):upper() ~= self.professionKey then return false end
    local provenance = type(action.authorityProvenance) == "table" and action.authorityProvenance or nil
    if not provenance
        or tostring(provenance.contract or "") ~= tostring(productionNativeProvenance())
        or tostring(provenance.autoRouteSourceAuthorityContract or "") ~= tostring(productionSourceContract())
        or not provenance.autoRouteSessionToken then
        return false
    end
    if not terminal(action.status) then return false end

    local run = self:_EnsureRun()
    local ledgerID = tostring(action.ledgerID or action.transactionID or "")
    if ledgerID == "" then return false end
    if run.terminalLedgers[ledgerID] then
        run.duplicateTerminalEvents = run.duplicateTerminalEvents + 1
        return false
    end

    run.terminalLedgers[ledgerID] = {
        ledgerID = ledgerID,
        status = tostring(action.status or "unknown"),
        recipeID = tonumber(action.recipeID),
        routeIndex = tonumber(provenance.autoRouteRouteIndex or provenance.routeIndex),
        ordinal = tonumber(provenance.autoRouteOrdinal),
        sessionToken = provenance.autoRouteSessionToken,
        startedSkill = tonumber(action.startedSkill),
        endingSkill = tonumber(action.endingSkill),
        confirmedCount = tonumber(action.completedCount) or 0,
    }
    run.uniqueLedgers = run.uniqueLedgers + 1
    run.terminalActions = run.terminalActions + 1

    if tostring(action.status or "") == "success" then
        run.successfulSettlements = run.successfulSettlements + 1
        local before,after = tonumber(action.startedSkill),tonumber(action.endingSkill)
        if before and after and after > before then run.skillGainSettlements = run.skillGainSettlements + 1
        else run.noSkillGainSettlements = run.noSkillGainSettlements + 1 end
    else
        run.failedSettlements = run.failedSettlements + 1
    end

    local sessionToken = tostring(provenance.autoRouteSessionToken or "")
    if sessionToken ~= "" and not run.sessions[sessionToken] then
        run.sessions[sessionToken] = true
        run.uniqueSessions = run.uniqueSessions + 1
    end

    local rid = tonumber(action.recipeID)
    local routeIndex = tonumber(provenance.autoRouteRouteIndex or provenance.routeIndex)
    if rid then run.recipes[rid] = (run.recipes[rid] or 0) + 1 end
    if run.lastRouteIndex and routeIndex and routeIndex ~= run.lastRouteIndex then run.routeTransitionsObserved = run.routeTransitionsObserved + 1 end
    if run.lastRecipeID and rid and rid ~= run.lastRecipeID then run.recipeTransitionsObserved = run.recipeTransitionsObserved + 1 end
    run.lastRouteIndex = routeIndex or run.lastRouteIndex
    run.lastRecipeID = rid or run.lastRecipeID
    return true
end

function NativeEndurance:Audit()
    local run = self:_EnsureRun()
    local ledger = JLP:GetModule("TransactionLedger")
    local gate = JLP:GetModule("ResearchExecutionAuthorityGate")
    local crafting = JLP:GetModule("Crafting")
    local autoRoute = JLP:GetModule("ResearchAutoRouteOrchestrator")
    local lineage = JLP:GetModule("ResearchAutoRouteSessionLineage")

    local orphanLedgers,ledgerConfirmedMismatch,ledgerStatusMismatch = 0,0,0
    for id,observed in pairs(run.terminalLedgers or {}) do
        local status = ledger and ledger.GetStatus and ledger:GetStatus(id) or nil
        if not status then
            orphanLedgers = orphanLedgers + 1
        else
            if tostring(status.status or "") ~= tostring(observed.status or "") then ledgerStatusMismatch = ledgerStatusMismatch + 1 end
            if tostring(observed.status or "") == "success" and tonumber(status.confirmedCount) ~= 1 then ledgerConfirmedMismatch = ledgerConfirmedMismatch + 1 end
        end
    end

    local artifacts = gate and gate.CountArtifactsForProfession and gate:CountArtifactsForProfession(self.professionKey) or {reservations=-1,clickOrigins=-1,activeReservation=true}
    local pending = crafting and crafting.pendingCraft or nil
    local pendingProvenance = pending and pending.authorityProvenance or nil
    local pendingProductionAutoRoute = pending ~= nil
        and tostring(pending.key or ""):upper() == self.professionKey
        and type(pendingProvenance) == "table"
        and tostring(pendingProvenance.autoRouteSourceAuthorityContract or "") == tostring(productionSourceContract())
    local activeSession = autoRoute and autoRoute.GetSession and autoRoute:GetSession(self.professionKey) or nil
    local head = lineage and lineage.GetHead and lineage:GetHead(self.professionKey) or nil

    local audit = {
        contract = self.contract,
        observationContract = self.observationContract,
        hygieneContract = self.hygieneContract,
        authority = self.authority,
        professionKey = self.professionKey,
        label = run.label,
        terminalActions = run.terminalActions,
        successfulSettlements = run.successfulSettlements,
        failedSettlements = run.failedSettlements,
        skillGainSettlements = run.skillGainSettlements,
        noSkillGainSettlements = run.noSkillGainSettlements,
        duplicateTerminalEvents = run.duplicateTerminalEvents,
        uniqueLedgers = run.uniqueLedgers,
        uniqueSessions = run.uniqueSessions,
        routeTransitionsObserved = run.routeTransitionsObserved,
        recipeTransitionsObserved = run.recipeTransitionsObserved,
        orphanLedgers = orphanLedgers,
        ledgerConfirmedMismatch = ledgerConfirmedMismatch,
        ledgerStatusMismatch = ledgerStatusMismatch,
        staleReservations = tonumber(artifacts.reservations) or 0,
        staleClickOrigins = tonumber(artifacts.clickOrigins) or 0,
        activeReservation = artifacts.activeReservation == true,
        pendingProductionAutoRoute = pendingProductionAutoRoute == true,
        activeAutoRouteSession = activeSession ~= nil and activeSession.active == true,
        lineageHeadSessionToken = head and head.sessionToken or nil,
        lineageHeadTerminal = head and head.terminal == true or false,
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        persisted = false,
    }
    audit.hygieneClean = audit.orphanLedgers == 0
        and audit.ledgerConfirmedMismatch == 0
        and audit.ledgerStatusMismatch == 0
        and audit.staleReservations == 0
        and audit.staleClickOrigins == 0
        and audit.activeReservation == false
        and audit.pendingProductionAutoRoute == false
        and audit.activeAutoRouteSession == false
    audit.state = audit.hygieneClean and "production-tailoring-auto-route-native-endurance-clean" or "production-tailoring-auto-route-native-endurance-dirty"
    self.lastAudit = audit
    return copy(audit)
end

function NativeEndurance:GetLast()
    return self.lastAudit and copy(self.lastAudit) or nil
end

function NativeEndurance:GetSummary()
    local r = self:Audit()
    local lines = {
        "PRODUCTION TAILORING / NATIVE AUTO ROUTE SEGMENTED ENDURANCE",
        "Contract: "..self.contract,
        "Observation: "..self.observationContract,
        "Hygiene: "..self.hygieneContract,
        "State: "..tostring(r.state),
        "Terminal native Craft One settlements: "..tostring(r.terminalActions),
        "Successful settlements: "..tostring(r.successfulSettlements),
        "Skill gain / no skill gain: "..tostring(r.skillGainSettlements).." / "..tostring(r.noSkillGainSettlements),
        "Unique ledgers: "..tostring(r.uniqueLedgers).." · orphan ledgers: "..tostring(r.orphanLedgers),
        "Unique Auto Route sessions: "..tostring(r.uniqueSessions),
        "Observed recipe/route transitions: "..tostring(r.recipeTransitionsObserved).." / "..tostring(r.routeTransitionsObserved),
        "Duplicate terminal observations: "..tostring(r.duplicateTerminalEvents),
        "Stale reservations / click origins: "..tostring(r.staleReservations).." / "..tostring(r.staleClickOrigins),
        "Pending production Auto Route craft: "..(r.pendingProductionAutoRoute and "yes" or "no"),
        "Active production Auto Route session: "..(r.activeAutoRouteSession and "yes" or "no"),
        "Native dispatch from endurance monitor: forbidden",
        "Automatic execution from endurance monitor: forbidden",
        "Persistence: none",
    }
    return table.concat(lines,"\n")
end

function NativeEndurance:Validate()
    local errors,warnings = {},{}
    if self.nativeDispatchAllowed ~= false or self.automaticExecutionAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "production Tailoring native endurance monitor safety boundary invalid"
    end
    for _,name in ipairs({"ProductionTailoringAutoRouteAuthority","ProductionTailoringNativeExecutionAuthority","ResearchAutoRouteOrchestrator","ResearchExecutionAuthorityGate","TransactionLedger","ResearchAutoRouteSessionLineage"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "production Tailoring native endurance dependency missing: "..name end
    end
    return #errors == 0,errors,warnings
end

function NativeEndurance:Initialize()
    if self.initialized then return true end
    self.initialized = true
    self:Reset("runtime")
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED",function(action) self:ObserveCraftAction(action) end)
    end
    return true
end

JLP:RegisterModule("ProductionTailoringAutoRouteNativeEndurance", NativeEndurance)
