local _, JLP = ...

-- Alpha85 owns the post-dispatch lifecycle of guarded research Craft All.  The
-- client repeat is stopped immediately when a terminal boundary is observed,
-- but the ledger remains open for a short settlement grace so an already
-- in-flight final ordinal cannot be lost or double-counted.  Recovery remains
-- recipe-local and never authorizes a new repeat after /reload.
local ResearchNativeCraftAllSettlement = {
    contract = "native-current-recipe-craft-all-settlement-orchestrator-v1",
    settlementContract = "research-native-craft-all-settlement-v1",
    provenanceContract = "research-native-craft-all-provenance-v1",
    productionTailoringProvenanceContract = "production-tailoring-native-craft-all-provenance-v1",
    authority = "post-dispatch-current-recipe-reconciliation-only",
    stopGraceSeconds = 1.5,
    persistedAuthorization = false,
    automaticResume = false,
    automaticRouteAdvance = false,
    terminalByLedger = {},
    lastByProfession = {},
    initialized = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function copy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function provenance(action)
    return type(action) == "table" and type(action.authorityProvenance) == "table" and action.authorityProvenance or nil
end

local function isResearchCraftAll(action)
    local row = provenance(action)
    local contract = type(row) == "table" and tostring(row.contract or "") or ""
    local supported = contract == ResearchNativeCraftAllSettlement.provenanceContract
        or contract == ResearchNativeCraftAllSettlement.productionTailoringProvenanceContract
    return supported and (action.researchNativeCraftAll == true or action.productionTailoringCraftAll == true or action.mode == "all") or false
end

local function stateFor(action)
    local status = tostring(action and action.status or "unknown")
    if status == "success" then return "craft-all-settlement-confirmed", true end
    if status == "failed" then return "craft-all-settlement-failed", true end
    if status == "timeout" then return "craft-all-settlement-timeout", true end
    if status == "aborted_unknown" or status == "ABORTED_UNKNOWN" then return "craft-all-settlement-aborted-unknown", true end
    if status == "RECOVERED_SUCCESS" then return "craft-all-settlement-recovered-success", true end
    if status == "RECOVERED_PARTIAL" then return "craft-all-settlement-aborted-unknown", true end
    if status == "RECOVERED_FAILED" then return "craft-all-settlement-recovered-failed", true end
    if status == "UNRESOLVED" then return "craft-all-settlement-recovering", false end
    if action and action.repeatStopRequested then return "craft-all-settlement-stop-grace", false end
    return "craft-all-settlement-in-flight", false
end

function ResearchNativeCraftAllSettlement:IsResearchCraftAll(action)
    return isResearchCraftAll(action)
end

function ResearchNativeCraftAllSettlement:_Emit(report)
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_SETTLEMENT_UPDATED", copy(report))
    end
end

function ResearchNativeCraftAllSettlement:_Record(report)
    if type(report) ~= "table" then return nil end
    local key = normalizeKey(report.professionKey)
    local ledgerID = report.ledgerID and tostring(report.ledgerID) or nil
    if ledgerID and report.terminal == true then
        local prior = self.terminalByLedger[ledgerID]
        if prior then
            prior.duplicateTerminalSignals = (tonumber(prior.duplicateTerminalSignals) or 0) + 1
            prior.lastDuplicateSource = report.source
            return prior, "terminal-already-settled"
        end
        self.terminalByLedger[ledgerID] = report
    end
    if key then self.lastByProfession[key] = report end
    self:_Emit(report)
    return report, report.terminal and "terminal-settled" or "observed"
end

function ResearchNativeCraftAllSettlement:ObserveCraftAction(action)
    if not isResearchCraftAll(action) then return false, "not-research-craft-all" end
    local row = provenance(action)
    local state, terminal = stateFor(action)
    local report = {
        contract = self.contract,
        settlementContract = self.settlementContract,
        authority = self.authority,
        professionKey = normalizeKey(action.key or row.professionKey),
        state = state,
        terminal = terminal,
        transactionStatus = tostring(action.status or "unknown"),
        recipe = action.recipeName or row.recipe,
        recipeID = tonumber(action.recipeID or row.recipeID),
        requestedCount = tonumber(action.requestedCount) or tonumber(row.requestedCount) or 1,
        completedCount = tonumber(action.completedCount) or 0,
        targetSkill = tonumber(action.targetSkill or row.skillTarget),
        targetReached = action.targetReached == true,
        ledgerID = action.ledgerID or action.transactionID,
        stopReason = action.repeatStopReason,
        stopSource = action.repeatStopSource,
        stopRequested = action.repeatStopRequested == true,
        killSwitchObserved = action.killSwitchObserved == true,
        postStopOrdinalObserved = action.postStopOrdinalObserved == true,
        postStopOrdinalCount = tonumber(action.postStopOrdinalCount) or 0,
        strictTargetSafeCraftAll = action.strictTargetSafeCraftAll == true or row.strictTargetSafeCraftAll == true,
        nativeDispatchPerOrdinal = tonumber(action.nativeDispatchPerOrdinal or row.nativeDispatchPerOrdinal),
        strictOrdinalDispatchCount = tonumber(action.strictOrdinalDispatchCount) or 0,
        strictLastSettledOrdinal = tonumber(action.strictLastSettledOrdinal) or 0,
        recipeLocked = row.recipeLocked == true,
        automaticRouteAdvance = false,
        recovered = action.recovered == true,
        source = action.source or "craft-action",
        persistedAuthorization = false,
        automaticResume = false,
    }
    self:_Record(report)
    return true, state, report
end

function ResearchNativeCraftAllSettlement:ObserveRecovery(status)
    if type(status) ~= "table" then return false, "invalid-recovery-status" end
    local row = type(status.authorityProvenance) == "table" and status.authorityProvenance or nil
    if not row or (row.contract ~= self.provenanceContract and row.contract ~= self.productionTailoringProvenanceContract) then return false, "not-guarded-craft-all" end
    local pseudo = {
        status = status.state,
        mode = "all",
        key = status.key or row.professionKey,
        recipeID = status.recipeID or row.recipeID,
        recipeName = status.recipeName or row.recipe,
        requestedCount = status.requestedCount or row.requestedCount,
        completedCount = status.confirmedCount or 0,
        targetSkill = row.skillTarget,
        targetReached = false,
        ledgerID = status.ledgerID,
        authorityProvenance = row,
        recovered = true,
        source = "transaction-recovery",
        killSwitchObserved = status.killSwitchObserved == true,
        repeatStopRequested = status.repeatStopRequested == true,
        repeatStopReason = status.repeatStopReason,
        repeatStopSource = status.repeatStopSource,
        researchNativeCraftAll = row.contract == self.provenanceContract,
        productionTailoringCraftAll = row.contract == self.productionTailoringProvenanceContract,
    }
    local state, terminal = stateFor(pseudo)
    local report = {
        contract=self.contract,settlementContract=self.settlementContract,authority=self.authority,
        professionKey=normalizeKey(pseudo.key),state=state,terminal=terminal,transactionStatus=tostring(status.state or "unknown"),
        recipe=pseudo.recipeName,recipeID=tonumber(pseudo.recipeID),requestedCount=tonumber(pseudo.requestedCount) or 1,
        completedCount=tonumber(pseudo.completedCount) or 0,targetSkill=tonumber(row.skillTarget),ledgerID=status.ledgerID,
        stopReason=pseudo.repeatStopReason,stopSource=pseudo.repeatStopSource,stopRequested=pseudo.repeatStopRequested,
        killSwitchObserved=pseudo.killSwitchObserved,recipeLocked=row.recipeLocked==true,automaticRouteAdvance=false,
        recovered=true,source="transaction-recovery",persistedAuthorization=false,automaticResume=false,
    }
    self:_Record(report)
    return true, state, report
end

function ResearchNativeCraftAllSettlement:RequestStop(reason, source)
    local crafting = JLP:GetModule("Crafting")
    if not crafting or not crafting.RequestResearchCraftAllStop then return false, "craft-all-stop-boundary-unavailable" end
    return crafting:RequestResearchCraftAllStop(reason or "research Craft All stop requested", source or "settlement")
end


function ResearchNativeCraftAllSettlement:HandleProvisionalFailure(event, pending, detail)
    if not isResearchCraftAll(pending) then return false, "not-research-craft-all" end
    pending.provisionalFailure = {event=tostring(event or "UNIT_SPELLCAST_FAILED"),detail=tostring(detail or "client rejected or failed the repeat cast")}
    pending.settlementState = "craft-all-failure-stop-grace"
    return self:RequestStop(pending.provisionalFailure.detail, "spellcast-failure")
end

function ResearchNativeCraftAllSettlement:HandleTimeout(pending)
    if not isResearchCraftAll(pending) then return false, "not-research-craft-all" end
    pending.settlementState = "craft-all-timeout-reconciliation"
    return self:RequestStop("Craft All completion timeout", "timeout")
end

function ResearchNativeCraftAllSettlement:OnKillSwitch(reason)
    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and crafting.pendingCraft or nil
    if not isResearchCraftAll(pending) then return false, "no-research-craft-all-in-flight" end
    pending.killSwitchObserved = true
    pending.killSwitchReason = tostring(reason or "research-craft-all-kill-switch")
    return self:RequestStop(pending.killSwitchReason, "kill-switch")
end

function ResearchNativeCraftAllSettlement:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ResearchNativeCraftAllSettlement:GetSummary(professionKey)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local last = self:GetLast(professionKey)
    local lines = {
        "RESEARCH CRAFT ALL SETTLEMENT / RECIPE-LOCKED RECOVERY",
        professionKey,
        "Contract: " .. self.contract,
        "Settlement contract: " .. self.settlementContract,
        "Stop policy: strict mode never pre-authorizes the next ordinal; kill-switch/failure reconciles only the one already in flight",
        "Target policy: target skill is checked before every subsequent native dispatch",
        "Native dispatch policy: CraftRecipe(recipeID, 1) only for strict research Craft All",
        "Recipe policy: exact recipe only; route advancement forbidden",
        "Reload policy: recover partial ledger only; repeat never auto-resumes",
        "Kill switch policy: stop future ordinals; settle already irreversible evidence",
        "Persistence: checkpoint/provenance only; authorization none",
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines+1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines+1] = "Progress: " .. tostring(last.completedCount or 0) .. " / " .. tostring(last.requestedCount or 1)
        lines[#lines+1] = "Stop reason: " .. tostring(last.stopReason or "none")
        lines[#lines+1] = "Kill switch observed: " .. (last.killSwitchObserved and "yes" or "no")
        lines[#lines+1] = "Post-stop ordinal observed: " .. (last.postStopOrdinalObserved and ("yes (" .. tostring(last.postStopOrdinalCount or 0) .. ")") or "no")
        lines[#lines+1] = "Strict target-safe: " .. (last.strictTargetSafeCraftAll and "yes" or "no")
        lines[#lines+1] = "Native dispatch per ordinal: " .. tostring(last.nativeDispatchPerOrdinal or "n/a")
        lines[#lines+1] = "Ordinal dispatches observed: " .. tostring(last.strictOrdinalDispatchCount or 0)
        lines[#lines+1] = "Recovered: " .. (last.recovered and "yes" or "no")
    end
    return table.concat(lines, "\n")
end

function ResearchNativeCraftAllSettlement:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("TRANSACTION_RECOVERY_UPDATED", function(status) self:ObserveRecovery(status) end)
        JLP.EventBus:On("RESEARCH_CRAFT_ALL_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch(payload.state or "craft-all-authority-disabled") end
        end)
        JLP.EventBus:On("PRODUCTION_TAILORING_CRAFT_ALL_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch(payload.state or "production-tailoring-craft-all-authority-disabled") end
        end)
        JLP.EventBus:On("PRODUCTION_TAILORING_NATIVE_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("production-tailoring-native-execution-gate-disabled") end
        end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("execution-eligibility-gate-disabled") end
        end)
        JLP.EventBus:On("RESEARCH_NATIVE_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("native-execution-gate-disabled") end
        end)
    end
    return true
end

function ResearchNativeCraftAllSettlement:Validate()
    local errors, warnings = {}, {}
    if self.persistedAuthorization ~= false or self.automaticResume ~= false or self.automaticRouteAdvance ~= false then
        errors[#errors+1] = "research Craft All settlement authority boundary invalid"
    end
    if tonumber(self.stopGraceSeconds) == nil or self.stopGraceSeconds <= 0 then errors[#errors+1] = "research Craft All stop grace must be positive" end
    for _, name in ipairs({"Crafting","TransactionLedger","TransactionRecovery","ResearchNativeCraftAllAuthority","ProductionTailoringCraftAllAuthority"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "research Craft All settlement dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeCraftAllSettlement", ResearchNativeCraftAllSettlement)
