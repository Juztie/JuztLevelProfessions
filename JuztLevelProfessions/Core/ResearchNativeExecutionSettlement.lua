local _, JLP = ...

-- Alpha77 owns only the post-dispatch side of guarded research Craft One.
-- Native dispatch authority remains in alpha76. This module reconciles the
-- irreversible operation after CraftRecipe() has accepted it, guarantees one
-- terminal settlement per ledger transaction, tolerates duplicate/out-of-order
-- result signals, and keeps kill switches from destroying an already in-flight
-- transaction that still needs to be reconciled.
local ResearchNativeExecutionSettlement = {
    contract = "native-single-craft-settlement-orchestrator-v1",
    settlementContract = "research-native-single-craft-settlement-v1",
    provenanceContract = "research-native-dispatch-provenance-v1",
    authority = "post-dispatch-evidence-reconciliation-only",
    failureGraceSeconds = 2,
    persistedAuthorization = false,
    lastByProfession = {},
    terminalByLedger = {},
    initialized = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function actionProvenance(action)
    return type(action) == "table" and type(action.authorityProvenance) == "table" and action.authorityProvenance or nil
end

local function isResearchNative(action)
    local provenance = actionProvenance(action)
    return provenance and provenance.contract == ResearchNativeExecutionSettlement.provenanceContract or false
end

local function settlementState(status)
    status = tostring(status or "unknown")
    if status == "success" then return "native-settlement-confirmed", true end
    if status == "failed" then return "native-settlement-failed", true end
    if status == "timeout" then return "native-settlement-timeout", true end
    if status == "aborted_unknown" or status == "ABORTED_UNKNOWN" then return "native-settlement-aborted-unknown", true end
    if status == "RECOVERED_SUCCESS" then return "native-settlement-confirmed", true end
    if status == "RECOVERED_FAILED" then return "native-settlement-failed", true end
    if status == "UNRESOLVED" then return "native-settlement-recovering", false end
    if status == "settlement-pending" then return "native-settlement-awaiting-evidence", false end
    return "native-settlement-in-flight", false
end

function ResearchNativeExecutionSettlement:IsResearchNativeAction(action)
    return isResearchNative(action)
end

function ResearchNativeExecutionSettlement:_Emit(report)
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("RESEARCH_NATIVE_SETTLEMENT_UPDATED", shallowCopy(report))
    end
end

function ResearchNativeExecutionSettlement:_Record(report)
    if type(report) ~= "table" then return nil end
    local professionKey = normalizeKey(report.professionKey)
    local ledgerID = report.ledgerID and tostring(report.ledgerID) or nil
    if ledgerID and report.terminal == true then
        local existing = self.terminalByLedger[ledgerID]
        if existing then
            existing.duplicateTerminalSignals = (tonumber(existing.duplicateTerminalSignals) or 0) + 1
            existing.lastDuplicateState = report.state
            existing.lastDuplicateSource = report.source
            return existing, "terminal-already-settled"
        end
        self.terminalByLedger[ledgerID] = report
    end
    if professionKey then self.lastByProfession[professionKey] = report end
    self:_Emit(report)
    return report, report.terminal and "terminal-settled" or "observed"
end

function ResearchNativeExecutionSettlement:_InvalidateConsumer(professionKey)
    local invalidation = JLP:GetModule("ResearchConsumerInvalidation")
    if not invalidation or not invalidation.Observe then return nil, "consumer-invalidation-unavailable" end
    local state, transition = invalidation:Observe(professionKey, "native-settlement-confirmed")
    return state, transition
end

function ResearchNativeExecutionSettlement:ObserveCraftAction(action)
    if not isResearchNative(action) then return false, "not-research-native" end
    local provenance = actionProvenance(action)
    local state, terminal = settlementState(action.status)
    local report = {
        contract = self.contract,
        settlementContract = self.settlementContract,
        authority = self.authority,
        professionKey = normalizeKey(action.key or provenance.professionKey),
        mode = action.mode or provenance.mode or "one",
        state = state,
        transactionStatus = tostring(action.status or "unknown"),
        terminal = terminal,
        recipe = action.recipeName or provenance.recipe,
        recipeID = tonumber(action.recipeID or provenance.recipeID),
        requestedCount = tonumber(action.requestedCount) or 1,
        completedCount = tonumber(action.completedCount) or 0,
        ledgerID = action.ledgerID or action.transactionID,
        reservationToken = provenance.reservationToken,
        snapshotToken = provenance.snapshotToken,
        stateFingerprint = provenance.stateFingerprint,
        currentBuild = provenance.currentBuild,
        source = action.source or "craft-action",
        recovered = action.recovered == true,
        settledBy = action.settledBy,
        killSwitchObserved = action.killSwitchObserved == true,
        persistedAuthorization = false,
    }
    if terminal and state == "native-settlement-confirmed" and report.professionKey then
        local _, transition = self:_InvalidateConsumer(report.professionKey)
        report.consumerInvalidation = transition or "observed"
    end
    self:_Record(report)
    return true, state, report
end

function ResearchNativeExecutionSettlement:ObserveRecovery(status)
    if type(status) ~= "table" then return false, "invalid-recovery-status" end
    local provenance = type(status.authorityProvenance) == "table" and status.authorityProvenance or nil
    if not provenance or provenance.contract ~= self.provenanceContract then return false, "not-research-native" end
    local state, terminal = settlementState(status.state)
    local report = {
        contract = self.contract,
        settlementContract = self.settlementContract,
        authority = self.authority,
        professionKey = normalizeKey(status.key or provenance.professionKey),
        mode = provenance.mode or "one",
        state = state,
        transactionStatus = tostring(status.state or "unknown"),
        terminal = terminal,
        recipe = status.recipeName or provenance.recipe,
        recipeID = tonumber(status.recipeID or provenance.recipeID),
        requestedCount = tonumber(status.requestedCount) or 1,
        completedCount = tonumber(status.confirmedCount) or 0,
        ledgerID = status.ledgerID,
        reservationToken = provenance.reservationToken,
        snapshotToken = provenance.snapshotToken,
        stateFingerprint = provenance.stateFingerprint,
        currentBuild = provenance.currentBuild,
        source = "transaction-recovery",
        recovered = true,
        recoveryState = status.state,
        persistedAuthorization = false,
    }
    if terminal and state == "native-settlement-confirmed" and report.professionKey then
        local _, transition = self:_InvalidateConsumer(report.professionKey)
        report.consumerInvalidation = transition or "observed"
    end
    self:_Record(report)
    return true, state, report
end

function ResearchNativeExecutionSettlement:OnKillSwitch(reason)
    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and crafting.pendingCraft or nil
    if not pending or pending.researchNativeExecution ~= true or not isResearchNative(pending) then
        return false, "no-native-research-craft-in-flight"
    end
    pending.killSwitchObserved = true
    pending.killSwitchReason = tostring(reason or "execution-kill-switch")
    pending.settlementState = "settlement-only-after-kill-switch"
    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CapturePending then recovery:CapturePending("craft", pending) end
    local provenance = actionProvenance(pending)
    local report = {
        contract=self.contract,settlementContract=self.settlementContract,authority=self.authority,
        professionKey=normalizeKey(pending.key or provenance.professionKey),mode=pending.mode or "one",
        state="native-settlement-in-flight-kill-switch",transactionStatus=tostring(pending.status or "pending"),
        terminal=false,recipe=pending.recipeName,recipeID=tonumber(pending.recipeID),requestedCount=1,
        completedCount=tonumber(pending.completedCount) or 0,ledgerID=pending.ledgerID,reservationToken=provenance.reservationToken,
        snapshotToken=provenance.snapshotToken,stateFingerprint=provenance.stateFingerprint,currentBuild=provenance.currentBuild,
        source=tostring(reason or "execution-kill-switch"),killSwitchObserved=true,persistedAuthorization=false,
    }
    self:_Record(report)
    return true, report.state, report
end

local function confirmFromExistingEvidence(pending, source)
    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger or not pending or not pending.ledgerID then return false end
    local confirmed = tonumber(ledger:GetConfirmedCount(pending.ledgerID)) or 0
    if confirmed < 1 and pending.lastResult then
        local identity = pending.lastResult.operationID or pending.lastResult.itemGUID or pending.lastResult.itemID or pending.recipeID or "result"
        ledger:ConfirmThrough(pending.ledgerID, 1, "native-settlement:" .. tostring(identity), source or "native-settlement-evidence", pending.lastResult)
        confirmed = tonumber(ledger:GetConfirmedCount(pending.ledgerID)) or 0
    end
    return confirmed >= 1
end

function ResearchNativeExecutionSettlement:ConfirmFromCraftResult(pending, data)
    if not pending or pending.researchNativeExecution ~= true or not isResearchNative(pending) then return false, "not-research-native" end
    if tostring(pending.mode or "one") ~= "one" or tonumber(pending.requestedCount) ~= 1 then return false, "unsupported-native-settlement-shape" end
    pending.lastResult = pending.lastResult or shallowCopy(data)
    if not confirmFromExistingEvidence(pending, "native-settlement-crafted-result") then
        return false, "crafted-result-not-confirmed"
    end
    pending.settlementState = "confirmed"
    pending.settledBy = "crafted-result"
    pending.completedCount = 1
    local crafting = JLP:GetModule("Crafting")
    if crafting and crafting.CompletePendingCraft and crafting.pendingCraft == pending then
        return crafting:CompletePendingCraft("success", nil, "native-settlement-crafted-result", false)
    end
    return false, "pending-craft-no-longer-current"
end

function ResearchNativeExecutionSettlement:FinalizeProvisional(token, terminalStatus)
    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and crafting.pendingCraft or nil
    if not pending or pending.token ~= token or pending.researchNativeExecution ~= true then return false, "pending-native-craft-not-current" end
    if confirmFromExistingEvidence(pending, "native-settlement-provisional-reconcile") then
        pending.settlementState = "confirmed"
        pending.settledBy = pending.lastResult and "crafted-result-after-provisional" or "ledger-evidence-after-provisional"
        pending.completedCount = 1
        return crafting:CompletePendingCraft("success", nil, "native-settlement-reconciled", false)
    end
    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.ReconcileLivePending then
        local success, result = recovery:ReconcileLivePending("craft", pending, "native-settlement-provisional-finalize")
        if success then
            pending.completedCount = math.max(1, tonumber(result and result.confirmedCount) or 1)
            pending.settlementState = "confirmed"
            pending.settledBy = "live-recovery-evidence"
            return crafting:CompletePendingCraft("success", nil, "native-settlement-live-recovery", false)
        end
    end
    local status = terminalStatus or (pending.provisionalFailure and "failed" or "timeout")
    local detail = pending.provisionalFailure and pending.provisionalFailure.detail or nil
    pending.settlementState = status == "failed" and "failed" or "timeout"
    pending.settledBy = status == "failed" and "failure-grace-expired" or "timeout-no-positive-evidence"
    return crafting:CompletePendingCraft(status, detail, "native-settlement-" .. status, false)
end

function ResearchNativeExecutionSettlement:HandleProvisionalFailure(event, pending, detail)
    if not pending or pending.researchNativeExecution ~= true or not isResearchNative(pending) then return false, "not-research-native" end
    pending.provisionalFailure = {
        event = tostring(event or "UNIT_SPELLCAST_FAILED"),
        detail = tostring(detail or "client rejected or failed the cast"),
    }
    pending.status = "settlement-pending"
    pending.settlementState = "awaiting-positive-evidence"
    local crafting = JLP:GetModule("Crafting")
    if crafting and crafting.TouchPendingCraft then crafting:TouchPendingCraft("settlement-pending") end
    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CapturePending then recovery:CapturePending("craft", pending) end
    local provenance = actionProvenance(pending)
    self:_Record({
        contract=self.contract,settlementContract=self.settlementContract,authority=self.authority,
        professionKey=normalizeKey(pending.key or provenance.professionKey),mode=pending.mode or "one",
        state="native-settlement-awaiting-evidence",transactionStatus="settlement-pending",terminal=false,
        recipe=pending.recipeName,recipeID=tonumber(pending.recipeID),requestedCount=1,completedCount=tonumber(pending.completedCount) or 0,
        ledgerID=pending.ledgerID,reservationToken=provenance.reservationToken,snapshotToken=provenance.snapshotToken,
        stateFingerprint=provenance.stateFingerprint,currentBuild=provenance.currentBuild,source=tostring(event or "spellcast-failed"),
        provisionalFailure=true,persistedAuthorization=false,
    })
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local token = pending.token
        C_Timer.After(self.failureGraceSeconds, function()
            ResearchNativeExecutionSettlement:FinalizeProvisional(token, "failed")
        end)
    end
    return true, "native-settlement-failure-provisional"
end

function ResearchNativeExecutionSettlement:HandleTimeout(pending)
    if not pending or pending.researchNativeExecution ~= true or not isResearchNative(pending) then return false, "not-research-native" end
    pending.settlementState = "timeout-reconciliation"
    return self:FinalizeProvisional(pending.token, "timeout")
end

function ResearchNativeExecutionSettlement:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and shallowCopy(row) or nil
end

function ResearchNativeExecutionSettlement:GetSummary(professionKey)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local last = self:GetLast(professionKey)
    local lines = {
        "RESEARCH NATIVE SETTLEMENT / EXACTLY-ONCE RECONCILIATION",
        professionKey,
        "Contract: " .. self.contract,
        "Settlement contract: " .. self.settlementContract,
        "Authority: post-dispatch reconciliation only",
        "Terminal policy: immutable ledger terminal + first strong success evidence wins",
        "Failure policy: provisional " .. tostring(self.failureGraceSeconds) .. "s grace for out-of-order success",
        "Kill switch during in-flight craft: settlement continues; new dispatch remains blocked",
        "Authorization persistence: none",
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines + 1] = "Ledger: " .. tostring(last.ledgerID or "none")
        lines[#lines + 1] = "Completed: " .. tostring(last.completedCount or 0) .. " / " .. tostring(last.requestedCount or 1)
        lines[#lines + 1] = "Recovered: " .. (last.recovered and "yes" or "no")
        lines[#lines + 1] = "Kill switch observed: " .. (last.killSwitchObserved and "yes" or "no")
        lines[#lines + 1] = "Consumer invalidation: " .. tostring(last.consumerInvalidation or "n/a")
    end
    return table.concat(lines, "\n")
end

function ResearchNativeExecutionSettlement:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) self:ObserveCraftAction(action) end)
        JLP.EventBus:On("TRANSACTION_RECOVERY_UPDATED", function(status) self:ObserveRecovery(status) end)
        JLP.EventBus:On("RESEARCH_NATIVE_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("native-execution-gate-disabled") end
        end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("execution-eligibility-gate-disabled") end
        end)
    end
    return true
end

function ResearchNativeExecutionSettlement:Validate()
    local errors, warnings = {}, {}
    if self.persistedAuthorization ~= false then errors[#errors + 1] = "native settlement must not persist execution authorization" end
    if tonumber(self.failureGraceSeconds) == nil or self.failureGraceSeconds < 1 then errors[#errors + 1] = "native settlement failure grace must be positive" end
    for _, name in ipairs({"Crafting", "TransactionLedger", "TransactionRecovery", "ResearchNativeExecutionAuthority", "ResearchConsumerInvalidation"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "native settlement dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeExecutionSettlement", ResearchNativeExecutionSettlement)
