local _, JLP = ...

-- Alpha112 owns the post-dispatch lifecycle of production Enchanting Enchant One.
-- Native execution authority remains in ProductionEnchantingNativeExecutionAuthority.
-- This module makes terminal settlement monotonic/idempotent, keeps live failures
-- provisional long enough for out-of-order positive evidence to win, persists the
-- protected Replace/Bind confirmation lifecycle across /reload, and never invokes
-- protected confirmation APIs itself.
local ProductionEnchantingNativeSettlement = {
    contract = "production-enchanting-native-settlement-orchestrator-v1",
    settlementContract = "production-enchanting-native-single-enchant-settlement-v1",
    confirmationLifecycleContract = "production-enchanting-protected-confirmation-lifecycle-v1",
    provenanceContract = "production-enchanting-native-dispatch-provenance-v1",
    authority = "post-dispatch-target-bound-evidence-reconciliation-only",
    professionKey = "ENCHANTING",
    failureGraceSeconds = 2,
    persistedAuthorization = false,
    confirmationAutomationAllowed = false,
    lastByProfession = {},
    terminalByLedger = {},
    confirmationByLedger = {},
    initialized = false,
}

-- Only an event observed in this live Lua runtime may supply a monotonic
-- confirmation timestamp. Weak keys prevent holding old pending sessions.
-- Never persist this table, use epoch confirmationAt as GetTime, or treat this
-- observation as permission to click Blizzard's protected confirmation.
local transientConfirmationByPending = setmetatable({}, { __mode = "k" })
local function monotonicNow()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    value = ok and tonumber(value) or nil
    return value and value > 0 and value or nil
end

function ProductionEnchantingNativeSettlement:GetTransientConfirmationObservation(pending)
    local crafting = JLP:GetModule("Crafting")
    if not crafting or crafting.pendingEnchant ~= pending or
       type(pending) ~= "table" or pending.productionEnchantingNativeExecution ~= true then
        return nil, "PENDING_NOT_CURRENT"
    end
    local row = transientConfirmationByPending[pending]
    if not row or row.token ~= pending.token or row.recipeID ~= pending.recipeID or
       row.targetGUID ~= pending.targetGUID or row.targetItemID ~= pending.targetItemID or
       row.event ~= pending.confirmationEvent or
       row.signals ~= pending.confirmationSignals or
       pending.confirmationRequired ~= true or pending.status ~= "confirmation-required" then
        return nil, "TRANSIENT_CONFIRMATION_UNAVAILABLE"
    end
    return row.at, "TRANSIENT_EVENT_OBSERVED"
end

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function epochNow()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function copyTable(value, depth)
    if type(value) ~= "table" then return value end
    depth = tonumber(depth) or 0
    if depth > 4 then return nil end
    local out = {}
    for key, item in pairs(value) do
        local itemType = type(item)
        if itemType == "table" then out[key] = copyTable(item, depth + 1)
        elseif itemType == "string" or itemType == "number" or itemType == "boolean" then out[key] = item end
    end
    return out
end

local function actionProvenance(action)
    return type(action) == "table" and type(action.authorityProvenance) == "table" and action.authorityProvenance or nil
end

local function isProductionNative(action)
    local provenance = actionProvenance(action)
    return provenance and provenance.contract == ProductionEnchantingNativeSettlement.provenanceContract or false
end

local function settlementState(status)
    status = tostring(status or "unknown")
    if status == "success" or status == "RECOVERED_SUCCESS" then return "production-enchanting-native-settlement-confirmed", true end
    if status == "failed" or status == "RECOVERED_FAILED" then return "production-enchanting-native-settlement-failed", true end
    if status == "timeout" then return "production-enchanting-native-settlement-timeout", true end
    if status == "aborted_unknown" or status == "ABORTED_UNKNOWN" then return "production-enchanting-native-settlement-aborted-unknown", true end
    if status == "UNRESOLVED" then return "production-enchanting-native-settlement-recovering", false end
    if status == "confirmation-required" then return "production-enchanting-native-protected-confirmation-required", false end
    if status == "settlement-pending" then return "production-enchanting-native-settlement-awaiting-evidence", false end
    return "production-enchanting-native-settlement-in-flight", false
end

local function confirmationReason(kind)
    if kind == "REPLACE_ENCHANT" or kind == "TRADE_REPLACE_ENCHANT" then return "replace-existing-enchant" end
    if kind == "BIND_ENCHANT" or kind == "TRADE_POTENTIAL_BIND_ENCHANT" then return "bind-item" end
    return "native-enchant-confirmation"
end

function ProductionEnchantingNativeSettlement:IsProductionNativeAction(action)
    return isProductionNative(action)
end

function ProductionEnchantingNativeSettlement:_Emit(report)
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_NATIVE_SETTLEMENT_UPDATED", shallowCopy(report))
    end
end

function ProductionEnchantingNativeSettlement:_Record(report)
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

function ProductionEnchantingNativeSettlement:_ReportFromAction(action, sourceOverride)
    local provenance = actionProvenance(action)
    if not provenance then return nil end
    local state, terminal = settlementState(action.status)
    return {
        contract = self.contract,
        settlementContract = self.settlementContract,
        confirmationLifecycleContract = self.confirmationLifecycleContract,
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
        targetGUID = action.targetGUID or provenance.targetGUID,
        targetItemID = tonumber(action.targetItemID) or tonumber(provenance.targetItemID),
        targetLocationKey = action.targetLocationKey or provenance.targetLocationKey,
        targetProofContract = action.targetProofContract or provenance.targetProofContract,
        targetProofFingerprint = action.targetProofFingerprint or provenance.targetProofFingerprint,
        targetValidationSource = action.targetValidationSource or provenance.targetValidationSource,
        confirmationRequired = action.confirmationRequired == true,
        confirmationEvent = action.confirmationEvent,
        confirmationReason = action.confirmationReason,
        confirmationAt = action.confirmationAt,
        confirmationSignals = tonumber(action.confirmationSignals) or 0,
        confirmationDuplicateSignals = tonumber(action.confirmationDuplicateSignals) or 0,
        confirmationHistory = copyTable(action.confirmationHistory),
        settlementState = action.settlementState,
        settledBy = action.settledBy,
        provisionalFailure = copyTable(action.provisionalFailure),
        source = sourceOverride or action.source or "enchant-action",
        recovered = action.recovered == true,
        killSwitchObserved = action.killSwitchObserved == true,
        persistedAuthorization = false,
        confirmationAutomationAllowed = false,
    }
end

function ProductionEnchantingNativeSettlement:ObserveEnchantAction(action)
    if not isProductionNative(action) then return false, "not-production-enchanting-native" end
    local report = self:_ReportFromAction(action)
    if not report then return false, "missing-production-enchanting-provenance" end
    self:_Record(report)
    return true, report.state, report
end

function ProductionEnchantingNativeSettlement:ObserveRecovery(status)
    if type(status) ~= "table" then return false, "invalid-recovery-status" end
    local provenance = type(status.authorityProvenance) == "table" and status.authorityProvenance or nil
    if not provenance or provenance.contract ~= self.provenanceContract then return false, "not-production-enchanting-native" end
    local state, terminal = settlementState(status.state)
    local report = {
        contract = self.contract,
        settlementContract = self.settlementContract,
        confirmationLifecycleContract = self.confirmationLifecycleContract,
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
        targetGUID = status.targetGUID or provenance.targetGUID,
        targetItemID = tonumber(status.targetItemID) or tonumber(provenance.targetItemID),
        targetLocationKey = status.targetLocationKey or provenance.targetLocationKey,
        targetProofContract = status.targetProofContract or provenance.targetProofContract,
        targetProofFingerprint = status.targetProofFingerprint or provenance.targetProofFingerprint,
        targetValidationSource = status.targetValidationSource or provenance.targetValidationSource,
        confirmationRequired = status.confirmationRequired == true,
        confirmationEvent = status.confirmationEvent,
        confirmationReason = status.confirmationReason,
        confirmationAt = status.confirmationAt,
        confirmationSignals = tonumber(status.confirmationSignals) or 0,
        confirmationDuplicateSignals = tonumber(status.confirmationDuplicateSignals) or 0,
        confirmationHistory = copyTable(status.confirmationHistory),
        provisionalFailure = copyTable(status.postReloadFailure or status.provisionalFailure),
        source = "transaction-recovery",
        recovered = true,
        recoveryState = status.state,
        killSwitchObserved = status.killSwitchObserved == true,
        persistedAuthorization = false,
        confirmationAutomationAllowed = false,
    }
    self:_Record(report)
    return true, state, report
end

function ProductionEnchantingNativeSettlement:ObserveConfirmation(pending, event)
    if not pending or not isProductionNative(pending) then return false, "not-production-enchanting-native" end
    local crafting = JLP:GetModule("Crafting")
    if crafting and crafting.pendingEnchant ~= pending then return false, "pending-enchant-no-longer-current" end

    local kind = tostring(event or "ENCHANT_CONFIRMATION")
    local reason = confirmationReason(kind)
    local duplicate = pending.confirmationRequired == true
        and tostring(pending.confirmationEvent or "") == kind
        and tostring(pending.confirmationReason or "") == reason

    pending.status = "confirmation-required"
    pending.settlementState = "protected-confirmation-awaiting-user"
    pending.confirmationRequired = true
    pending.confirmationEvent = kind
    pending.confirmationReason = reason
    pending.confirmationAt = epochNow() -- retained: historical epoch/recovery audit
    pending.confirmationSignals = (tonumber(pending.confirmationSignals) or 0) + 1
    if duplicate then pending.confirmationDuplicateSignals = (tonumber(pending.confirmationDuplicateSignals) or 0) + 1 end
    -- Capture exactly the first correlated event, never a duplicate/reload.
    -- Its monotonic timestamp is process-local and may be compared to Guide's
    -- same-click GetTime() sample, but never authorizes confirmation automation.
    if not duplicate and kind == "REPLACE_ENCHANT" and
       pending.productionEnchantingNativeExecution == true then
        local observed = monotonicNow()
        if observed then
            transientConfirmationByPending[pending] = {
                at = observed, token = pending.token, recipeID = pending.recipeID,
                targetGUID = pending.targetGUID, targetItemID = pending.targetItemID,
                event = kind, signals = pending.confirmationSignals,
            }
        end
    end
    pending.confirmationHistory = type(pending.confirmationHistory) == "table" and pending.confirmationHistory or {}
    if not duplicate then
        pending.confirmationHistory[#pending.confirmationHistory + 1] = {
            event = kind,
            reason = reason,
            at = pending.confirmationAt,
        }
        while #pending.confirmationHistory > 8 do table.remove(pending.confirmationHistory, 1) end
    end

    local ledgerID = pending.ledgerID and tostring(pending.ledgerID) or nil
    if ledgerID then
        local row = self.confirmationByLedger[ledgerID] or {
            ledgerID = pending.ledgerID,
            signals = 0,
            duplicates = 0,
            firstEvent = kind,
            firstReason = reason,
            firstAt = pending.confirmationAt,
        }
        row.signals = row.signals + 1
        if duplicate then row.duplicates = row.duplicates + 1 end
        row.lastEvent = kind
        row.lastReason = reason
        row.lastAt = pending.confirmationAt
        self.confirmationByLedger[ledgerID] = row
    end

    -- Persist the confirmation boundary before surfacing it. The addon only
    -- observes this state; it never accepts ReplaceEnchant/BindEnchant.
    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CapturePending then recovery:CapturePending("enchant", pending) end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED", pending)
    else
        self:ObserveEnchantAction(pending)
    end
    return true, duplicate and "production-enchanting-native-protected-confirmation-duplicate" or "production-enchanting-native-protected-confirmation-required"
end

local function confirmFromExistingEvidence(pending, source)
    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger or not pending or not pending.ledgerID then return false end
    -- lastResult, item GUID, itemID and recipe are non-unique observations.
    -- The ledger must already hold a genuinely correlated confirmation; only
    -- a separate qualified live recovery decision may explicitly reconcile it.
    return (tonumber(ledger:GetConfirmedCount(pending.ledgerID)) or 0) >= 1
end

function ProductionEnchantingNativeSettlement:ConfirmFromCraftResult(pending, data)
    if not pending or pending.productionEnchantingNativeExecution ~= true or not isProductionNative(pending) then
        return false, "not-production-enchanting-native"
    end
    if tostring(pending.mode or "one") ~= "one" or tonumber(pending.requestedCount) ~= 1 then
        return false, "unsupported-production-enchanting-settlement-shape"
    end
    local crafting = JLP:GetModule("Crafting")
    if not crafting or crafting.pendingEnchant ~= pending then return false, "pending-enchant-no-longer-current" end

    if type(data)~="table" or (data.recipeID or data.spellID or data.craftingSpellID)
        and tonumber(data.recipeID or data.spellID or data.craftingSpellID)~=tonumber(pending.recipeID) then
        return false, "crafted-result-recipe-mismatch"
    end
    if data.targetGUID~=nil and tostring(data.targetGUID)~=tostring(pending.targetGUID or "") then
        return false, "crafted-result-target-mismatch"
    end
    if data.operationID==nil or tostring(data.operationID)=="" or tostring(data.operationID)=="0" then
        -- An itemGUID may identify the same enchanted item in several casts.
        return false, "crafted-result-unique-operation-required"
    end
    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger or not pending.ledgerID then return false,"crafted-result-ledger-unavailable" end
    local confirmed=ledger:ConfirmEnchant(pending.ledgerID, data.operationID, "production-enchanting-crafted-result", data)
    if not confirmed then return false,"crafted-result-not-confirmed" end
    pending.lastResult = shallowCopy(data)
    pending.completedCount = 1
    pending.settlementState = "confirmed"
    pending.settledBy = "crafted-result"
    return crafting:CompletePendingEnchant("success", nil, "production-enchanting-settlement-crafted-result", false)
end

function ProductionEnchantingNativeSettlement:ConfirmFromSpellcastSuccess(pending, castGUID, spellID)
    if not pending or pending.productionEnchantingNativeExecution ~= true or not isProductionNative(pending) then
        return false, "not-production-enchanting-native"
    end
    local crafting = JLP:GetModule("Crafting")
    if not crafting or crafting.pendingEnchant ~= pending then return false, "pending-enchant-no-longer-current" end
    if tonumber(spellID) ~= tonumber(pending.recipeID) then return false, "recipe-mismatch" end

    if type(castGUID)~="string" or castGUID=="" then return false,"spellcast-unique-cast-required" end
    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger or not pending.ledgerID then return false,"spellcast-ledger-unavailable" end
    local confirmed=ledger:ConfirmEnchant(pending.ledgerID, castGUID, "production-enchanting-spellcast-success", {castGUID=castGUID, spellID=spellID})
    if not confirmed then return false,"spellcast-success-not-confirmed" end
    pending.completedCount = 1
    pending.settlementState = "confirmed"
    pending.settledBy = "spellcast-success"
    return crafting:CompletePendingEnchant("success", nil, "production-enchanting-settlement-spellcast-success", false)
end

function ProductionEnchantingNativeSettlement:FinalizeProvisional(token, terminalStatus)
    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and crafting.pendingEnchant or nil
    if not pending or pending.token ~= token or pending.productionEnchantingNativeExecution ~= true or not isProductionNative(pending) then
        return false, "pending-production-enchant-no-longer-current"
    end

    if confirmFromExistingEvidence(pending, "production-enchanting-provisional-reconcile") then
        pending.completedCount = 1
        pending.settlementState = "confirmed"
        pending.settledBy = "ledger-evidence-after-provisional"
        return crafting:CompletePendingEnchant("success", nil, "production-enchanting-settlement-reconciled", false)
    end

    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.ReconcileLivePending then
        local success, result = recovery:ReconcileLivePending("enchant", pending, "production-enchanting-provisional-finalize")
        if success then
            -- Reconcile only after the independent recovery evaluator returns
            -- success, not merely because a crafted-result was observed.
            local ledger=JLP:GetModule("TransactionLedger")
            if ledger and pending.ledgerID and ledger.ConfirmThrough then
                ledger:ConfirmThrough(pending.ledgerID,1,"production-enchanting-qualified-live-recovery:"..tostring(pending.token),
                    "qualified-live-recovery",{source="qualified-recovery-evaluator",confidence=result and result.confidence})
            end
            if confirmFromExistingEvidence(pending,"qualified-live-recovery") then
                pending.completedCount = 1
                pending.settlementState = "confirmed"
                pending.settledBy = "live-recovery-evidence"
                return crafting:CompletePendingEnchant("success", nil, "production-enchanting-settlement-live-recovery", false)
            end
        end
    end

    local status = terminalStatus or (pending.provisionalFailure and "failed" or "timeout")
    local detail = pending.provisionalFailure and pending.provisionalFailure.detail or nil
    pending.settlementState = status == "failed" and "failed" or "timeout"
    pending.settledBy = status == "failed" and "failure-grace-expired" or "timeout-no-positive-evidence"
    return crafting:CompletePendingEnchant(status, detail, "production-enchanting-settlement-" .. status, false)
end

function ProductionEnchantingNativeSettlement:HandleProvisionalFailure(event, pending, detail, castGUID, spellID)
    if not pending or pending.productionEnchantingNativeExecution ~= true or not isProductionNative(pending) then
        return false, "not-production-enchanting-native"
    end
    local crafting = JLP:GetModule("Crafting")
    if not crafting or crafting.pendingEnchant ~= pending then return false, "pending-enchant-no-longer-current" end

    local alreadyPending = pending.status == "settlement-pending" and type(pending.provisionalFailure) == "table"
    local signalCount = alreadyPending and ((tonumber(pending.provisionalFailure.signalCount) or 1) + 1) or 1
    pending.provisionalFailure = {
        event = tostring(event or "UNIT_SPELLCAST_FAILED"),
        detail = tostring(detail or "client rejected or failed the enchant cast"),
        castGUID = castGUID,
        spellID = spellID,
        at = epochNow(),
        signalCount = signalCount,
    }
    pending.status = "settlement-pending"
    pending.settlementState = "awaiting-positive-evidence"

    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CapturePending then recovery:CapturePending("enchant", pending) end
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED", pending) end

    if not alreadyPending and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local token = pending.token
        C_Timer.After(self.failureGraceSeconds, function()
            ProductionEnchantingNativeSettlement:FinalizeProvisional(token, "failed")
        end)
    end
    return true, "production-enchanting-native-settlement-failure-provisional"
end

function ProductionEnchantingNativeSettlement:HandleTimeout(pending)
    if not pending or pending.productionEnchantingNativeExecution ~= true or not isProductionNative(pending) then
        return false, "not-production-enchanting-native"
    end
    pending.settlementState = "timeout-reconciliation"
    return self:FinalizeProvisional(pending.token, "timeout")
end

function ProductionEnchantingNativeSettlement:OnKillSwitch(reason)
    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and crafting.pendingEnchant or nil
    if not pending or pending.productionEnchantingNativeExecution ~= true or not isProductionNative(pending) then
        return false, "no-production-enchanting-native-enchant-in-flight"
    end
    pending.killSwitchObserved = true
    pending.killSwitchReason = tostring(reason or "production-enchanting-execution-kill-switch")
    pending.settlementState = "settlement-only-after-kill-switch"
    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CapturePending then recovery:CapturePending("enchant", pending) end
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED", pending) end
    return true, "production-enchanting-native-settlement-in-flight-kill-switch"
end

function ProductionEnchantingNativeSettlement:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey) or self.professionKey]
    return row and shallowCopy(row) or nil
end

function ProductionEnchantingNativeSettlement:GetSummary()
    local last = self:GetLast(self.professionKey)
    local lines = {
        "PRODUCTION ENCHANTING / NATIVE ENCHANT ONE SETTLEMENT",
        self.professionKey,
        "Contract: " .. self.contract,
        "Settlement contract: " .. self.settlementContract,
        "Confirmation lifecycle: " .. self.confirmationLifecycleContract,
        "Authority: post-dispatch reconciliation only",
        "Terminal policy: first terminal ledger settlement is immutable",
        "Failure policy: provisional " .. tostring(self.failureGraceSeconds) .. "s grace; strong success evidence wins",
        "Protected Replace/Bind: observe + persist only; automation forbidden",
        "Reload policy: confirmation/failure state remains correlation evidence, never execution authorization",
        "Authorization persistence: none",
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines + 1] = "Target GUID: " .. tostring(last.targetGUID or "none")
        lines[#lines + 1] = "Ledger: " .. tostring(last.ledgerID or "none")
        lines[#lines + 1] = "Completed: " .. tostring(last.completedCount or 0) .. " / " .. tostring(last.requestedCount or 1)
        lines[#lines + 1] = "Confirmation: " .. (last.confirmationRequired and (tostring(last.confirmationReason or last.confirmationEvent or "required") .. " · signals " .. tostring(last.confirmationSignals or 0) .. " · duplicates " .. tostring(last.confirmationDuplicateSignals or 0)) or "none")
        lines[#lines + 1] = "Settled by: " .. tostring(last.settledBy or "n/a")
        lines[#lines + 1] = "Recovered: " .. (last.recovered and "yes" or "no")
        lines[#lines + 1] = "Kill switch observed: " .. (last.killSwitchObserved and "yes" or "no")
    end
    return table.concat(lines, "\n")
end

function ProductionEnchantingNativeSettlement:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("ENCHANT_ACTION_UPDATED", function(action) self:ObserveEnchantAction(action) end)
        JLP.EventBus:On("TRANSACTION_RECOVERY_UPDATED", function(status) self:ObserveRecovery(status) end)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_NATIVE_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("production-enchanting-native-gate-disabled") end
        end)
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("execution-eligibility-gate-disabled") end
        end)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_AUTHORITY_UPDATED", function(payload)
            if type(payload) == "table" and payload.enabled == false then self:OnKillSwitch("production-enchanting-authority-disabled") end
        end)
    end
    return true
end

function ProductionEnchantingNativeSettlement:Validate()
    local errors, warnings = {}, {}
    if self.persistedAuthorization ~= false then errors[#errors + 1] = "production Enchanting settlement must not persist execution authorization" end
    if self.confirmationAutomationAllowed ~= false then errors[#errors + 1] = "production Enchanting settlement must never automate protected confirmation" end
    if tonumber(self.failureGraceSeconds) == nil or self.failureGraceSeconds < 1 then errors[#errors + 1] = "production Enchanting settlement failure grace must be positive" end
    for _, name in ipairs({"Crafting", "TransactionLedger", "TransactionRecovery", "ProductionEnchantingNativeExecutionAuthority"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "production Enchanting settlement dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingNativeSettlement", ProductionEnchantingNativeSettlement)
