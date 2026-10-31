local _, JLP = ...

-- Reload-safe recovery for in-flight Craft One / Craft All / Enchant actions.
-- SavedVariables are treated only as a correlation checkpoint.  A recovered
-- success requires new live evidence after reload (or already-confirmed progress
-- that was persisted before reload); otherwise the transaction remains unresolved
-- for a short grace period and is eventually released as aborted/unknown.
local TransactionRecovery = {
    contract = "evidence-reconciled-transaction-recovery-v2",
    checkpointSchema = 1,
    initialized = false,
    current = nil,
    revision = 0,
    graceSeconds = 8,
    liveSnapshotID = nil,
    recoveringSnapshotID = nil,
}

local function epochNow()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

-- The client build is not an entitlement. The full live receipt is used only
-- to prevent cross-client SavedVariables from being treated as current proof.
local function liveReceipt()
    local runtime = JLP:GetModule("RuntimeCompatibility")
    if not runtime or type(runtime.GetSessionReceipt) ~= "function" then return nil end
    local ok, receipt = pcall(runtime.GetSessionReceipt, runtime)
    if ok and type(receipt) == "string" and receipt ~= "" then return receipt end
    return nil
end

local function checkpointMatchesLive(snapshot)
    return type(snapshot) == "table" and type(snapshot.clientSessionReceipt) == "string"
        and snapshot.clientSessionReceipt ~= "" and
        snapshot.clientSessionReceipt == liveReceipt()
end

local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function copyTable(value, depth)
    if type(value) ~= "table" then return value end
    depth = tonumber(depth) or 0
    if depth > 5 then return nil end
    local out = {}
    for k, v in pairs(value) do
        local kt = type(k)
        local vt = type(v)
        if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
            out[k] = vt == "table" and copyTable(v, depth + 1) or v
        end
    end
    return out
end

local function getStore()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.transactionRecovery = JLP.DB.account.transactionRecovery or { characters = {} }
    JLP.DB.account.transactionRecovery.characters = JLP.DB.account.transactionRecovery.characters or {}
    local key = characterKey()
    local record = JLP.DB.account.transactionRecovery.characters[key]
    if type(record) ~= "table" then
        record = { pending=nil, lastByKey={}, history={}, updatedAt=nil }
        JLP.DB.account.transactionRecovery.characters[key] = record
    end
    record.lastByKey = type(record.lastByKey) == "table" and record.lastByKey or {}
    record.history = type(record.history) == "table" and record.history or {}
    return record, key
end

local function bagCount(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local inventory = JLP:GetModule("Inventory")
    if inventory and inventory.GetOwned then
        local owned = inventory:GetOwned(itemID)
        if type(owned) == "table" and owned.bagKnown == true and
            type(owned.bags) == "number" and owned.bags >= 0 and
            owned.bags == math.floor(owned.bags) and owned.bags < math.huge then
            return owned.bags
        end
    end
    -- Material delta compares BAG counts only. The fourth argument is
    -- includeReagentBank (not an optional bag-count flag).
    if type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        local ok, value = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
        local count = ok and tonumber(value) or nil
        if count and count >= 0 and count < math.huge and count == math.floor(count) then
            return count
        end
    end
    -- Missing client capability is UNKNOWN, not evidence of zero inventory.
    return nil
end

local function itemLinkByGUID(guid)
    if not guid or type(C_Item) ~= "table" then return nil end
    if type(C_Item.GetItemLinkByGUID) == "function" then
        local ok, link = pcall(C_Item.GetItemLinkByGUID, guid)
        if ok and link then return link end
    end
    local location
    if type(C_Item.GetItemLocation) == "function" then
        local ok, value = pcall(C_Item.GetItemLocation, guid)
        if ok then location = value end
    end
    if location and type(C_Item.GetItemLink) == "function" then
        local ok, link = pcall(C_Item.GetItemLink, location)
        if ok and link then return link end
    end
    if type(Item) == "table" and type(Item.CreateFromItemGUID) == "function" then
        local ok, object = pcall(function() return Item:CreateFromItemGUID(guid) end)
        if not ok or not object then ok, object = pcall(Item.CreateFromItemGUID, guid) end
        if ok and object and type(object.GetItemLink) == "function" then
            local okLink, link = pcall(object.GetItemLink, object)
            if okLink and link then return link end
        end
    end
    return nil
end

local function enchantIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local itemString = link:match("item:([^|]+)")
    if not itemString then return nil end
    local _, enchant = itemString:match("^([^:]+):([^:]*)")
    if enchant == nil or enchant == "" then return 0 end
    return tonumber(enchant)
end

local function snapshotID(kind, pending)
    local existing = pending and pending.recoveryID
    if existing and existing ~= "" then return existing end
    return table.concat({
        tostring(kind or "transaction"),
        tostring(pending and pending.recipeID or "unknown"),
        tostring(epochNow()),
        tostring(pending and pending.token or "0"),
    }, ":")
end

local function materialSnapshot(pending)
    local snapshot = pending and pending.materialSnapshot
    if type(snapshot) ~= "table" then return nil end
    return copyTable(snapshot)
end

local function recoveryLedger(snapshot)
    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger then return nil, nil, nil end
    local requestedID = snapshot.ledgerID or ("recovery:"..tostring(snapshot.id or snapshot.token or "unknown"))
    local tx = ledger.GetTransaction and ledger:GetTransaction(requestedID) or nil
    if tx and (tx.kind ~= snapshot.kind or tx.key ~= snapshot.key or tonumber(tx.recipeID) ~= tonumber(snapshot.recipeID)
        or (snapshot.kind == "enchant" and tostring(tx.targetGUID or "") ~= tostring(snapshot.targetGUID or ""))) then
        return ledger, nil, nil, "ledger-identity-conflict"
    end
    -- Preserve stable confirmed ordinals even if a partial batch was stopped.
    -- EnsureSnapshot deliberately refuses to reopen a settled transaction.
    if tx and (tx.closedAt or tx.status=="success" or tx.status=="failed" or tx.status=="timeout" or tx.status=="aborted_unknown") then
        return ledger, requestedID, tx
    end
    if ledger.EnsureSnapshot then
        local id, ensured = ledger:EnsureSnapshot(snapshot)
        return ledger, id, ensured
    end
    return ledger, snapshot.ledgerID, tx
end

local function normalizePending(kind, pending)
    if type(pending) ~= "table" then return nil end
    local id = snapshotID(kind, pending)
    pending.recoveryID = id
    -- Bind once on the first capture; later event updates or logout must not
    -- silently rebind an in-flight request to a different client session.
    if pending.recoverySessionReceipt == nil then
        pending.recoverySessionReceipt = liveReceipt() or false
    end
    local snapshot = {
        schema = 1,
        id = id,
        ledgerID = pending.ledgerID or pending.transactionID,
        kind = kind,
        key = pending.key or (kind == "enchant" and "ENCHANTING" or nil),
        token = pending.token,
        recipeID = tonumber(pending.recipeID),
        recipeName = pending.recipeName,
        mode = pending.mode,
        requestedCount = tonumber(pending.requestedCount) or 1,
        completedCount = math.max(0, math.floor(tonumber(pending.completedCount) or 0)),
        targetSkill = tonumber(pending.targetSkill),
        startedSkill = tonumber(pending.startedSkill),
        status = pending.status,
        savedAt = epochNow(),
        clientSessionReceipt = pending.recoverySessionReceipt or nil,
        materialSnapshot = materialSnapshot(pending),
        authorityProvenance = copyTable(pending.authorityProvenance),
        lastResult = copyTable(pending.lastResult),
        settlementState = pending.settlementState,
        settledBy = pending.settledBy,
        killSwitchObserved = pending.killSwitchObserved == true,
        killSwitchReason = pending.killSwitchReason,
        provisionalFailure = copyTable(pending.provisionalFailure),
        productionEnchantingNativeExecution = pending.productionEnchantingNativeExecution == true,
        researchNativeCraftAll = pending.researchNativeCraftAll == true,
        -- A completed batch ordinal awaiting a fresh Guide click is not an
        -- in-flight request. Do not attribute late events to its next ordinal.
        strictTargetSafeCraftAll = pending.strictTargetSafeCraftAll == true,
        strictAwaitingUserClick = pending.strictAwaitingUserClick == true,
        strictOrdinalInFlight = pending.strictOrdinalInFlight == true,
        strictCurrentOrdinal = tonumber(pending.strictCurrentOrdinal),
        repeatStopRequested = pending.repeatStopRequested == true,
        repeatStopReason = pending.repeatStopReason,
        repeatStopSource = pending.repeatStopSource,
        repeatStopAt = pending.repeatStopAt,
        targetGUID = pending.targetGUID,
        targetName = pending.targetName,
        targetItemID = tonumber(pending.targetItemID),
        targetLocationKey = pending.targetLocationKey,
        targetProofContract = pending.targetProofContract,
        targetProofFingerprint = pending.targetProofFingerprint,
        targetValidationSource = pending.targetValidationSource,
        confirmationRequired = pending.confirmationRequired == true,
        confirmationEvent = pending.confirmationEvent,
        confirmationReason = pending.confirmationReason,
        confirmationAt = pending.confirmationAt,
        confirmationSignals = tonumber(pending.confirmationSignals) or 0,
        confirmationDuplicateSignals = tonumber(pending.confirmationDuplicateSignals) or 0,
        confirmationHistory = copyTable(pending.confirmationHistory),
        settlementContract = pending.settlementContract,
        confirmationLifecycleContract = pending.confirmationLifecycleContract,
        targetLinkBefore = pending.targetLink,
        targetEnchantIDBefore = tonumber(pending.targetEnchantID),
        expectedCastGUID = pending.expectedCastGUID,
        expectedOperationID = pending.expectedOperationID,
    }
    if kind == "enchant" and snapshot.targetGUID and not snapshot.targetLinkBefore then
        snapshot.targetLinkBefore = itemLinkByGUID(snapshot.targetGUID)
        snapshot.targetEnchantIDBefore = enchantIDFromLink(snapshot.targetLinkBefore)
    end
    local _, ledgerID, tx, ledgerError = recoveryLedger(snapshot)
    snapshot.ledgerID = ledgerID or snapshot.ledgerID
    snapshot.ledgerError = ledgerError
    if tx then snapshot.completedCount = math.max(snapshot.completedCount or 0, tonumber(tx.confirmedCount) or 0) end
    return snapshot
end

local function professionSkill(key)
    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get(key) or nil
    return tonumber(profession and profession.skill)
end

local function materialEvidence(snapshot)
    local material = snapshot and snapshot.materialSnapshot
    if type(material) ~= "table" or type(material.items) ~= "table" or #material.items == 0 then
        return { confirmed=0, rows=0, changedRows=0, detail="no material baseline" }
    end
    local minConfirmed, rows, changedRows, unknownRows = nil, 0, 0, 0
    local details = {}
    for _, item in ipairs(material.items) do
        local perCraft = tonumber(item.perCraft)
        local id = tonumber(item.itemID)
        if perCraft and perCraft > 0 and perCraft < math.huge and
            id and id > 0 and id == math.floor(id) then
            rows = rows + 1
            local before = tonumber(item.beforeBags)
            local after = bagCount(id)
            local validBefore = before and before >= 0 and before < math.huge and before == math.floor(before)
            local validAfter = after and after >= 0 and after < math.huge and after == math.floor(after)
            local consumed, possible
            if validBefore and validAfter then
                consumed = math.max(0, before - after)
                if consumed > 0 then changedRows = changedRows + 1 end
                possible = math.floor(consumed / perCraft)
                minConfirmed = minConfirmed == nil and possible or math.min(minConfirmed, possible)
            else
                -- A missing API or unknown cached bag state must never be
                -- reconstructed as zero consumption/zero remaining items.
                unknownRows = unknownRows + 1
            end
            details[#details + 1] = {
                itemID = id, name = item.name,
                before = validBefore and before or nil,
                after = validAfter and after or nil,
                consumed = consumed, perCraft = perCraft,
                possibleCrafts = possible,
                observationKnown = validBefore and validAfter and true or false,
            }
        end
    end
    return {
        confirmed = rows > 0 and unknownRows == 0 and math.max(0, tonumber(minConfirmed) or 0) or 0,
        rows = rows, changedRows = changedRows, unknownRows = unknownRows,
        details = details,
        detail = unknownRows > 0 and string.format("%d/%d reagent rows unobserved",unknownRows,rows)
            or (rows > 0 and string.format("%d/%d reagent rows changed",changedRows,rows)
                or "no consumable reagent rows"),
    }
end

local function evaluateSnapshot(snapshot)
    if type(snapshot) ~= "table" then return { success=false, evidence={} } end
    local evidence = {}
    local endingSkill = professionSkill(snapshot.key)
    local startedSkill = tonumber(snapshot.startedSkill)
    local skillGain = endingSkill and startedSkill and math.max(0, endingSkill - startedSkill) or 0
    if skillGain > 0 then evidence[#evidence + 1] = string.format("profession skill increased by %d", skillGain) end

    local materials = materialEvidence(snapshot)
    local ledger, ledgerID, ledgerTx, ledgerError = recoveryLedger(snapshot)
    local confirmed = math.max(0, tonumber(snapshot.completedCount) or 0, tonumber(ledgerTx and ledgerTx.confirmedCount) or 0)
    local terminalLedgerFailure = ledgerTx and (ledgerTx.status == "failed" or ledgerTx.status == "timeout" or ledgerTx.status == "aborted_unknown")
    if terminalLedgerFailure then
        evidence[#evidence + 1] = "ledger already settled terminal as " .. tostring(ledgerTx.status)
    end
    if (tonumber(snapshot.completedCount) or 0) > 0 then
        evidence[#evidence + 1] = string.format("%d craft%s already confirmed before reload", tonumber(snapshot.completedCount) or 0, tonumber(snapshot.completedCount) == 1 and "" or "s")
    end
    if materials.confirmed > 0 then
        evidence[#evidence + 1] = string.format("reagent delta could cover %d craft%s (advisory; operation uncorrelated)", materials.confirmed, materials.confirmed == 1 and "" or "s")
    elseif materials.changedRows > 0 then
        evidence[#evidence + 1] = "partial reagent delta observed"
    end
    if snapshot.lastResult then
        -- A result packet alone does not prove that the protected craft
        -- completed. The same recipe may produce several result events; only
        -- ledger confirmation or independent persisted/live state can settle.
        evidence[#evidence + 1] = "crafted-result observed before reload (advisory; completion unconfirmed)"
    end
    if snapshot.postReloadSuccess then evidence[#evidence + 1] = tostring(snapshot.postReloadSuccess).." (ledger confirmation required)" end

    local targetLinkAfter, targetEnchantAfter, targetChanged
    if snapshot.kind == "enchant" and snapshot.targetGUID then
        targetLinkAfter = itemLinkByGUID(snapshot.targetGUID)
        targetEnchantAfter = enchantIDFromLink(targetLinkAfter)
        local before = tonumber(snapshot.targetEnchantIDBefore)
        if before == nil then before = enchantIDFromLink(snapshot.targetLinkBefore) end
        if targetEnchantAfter ~= nil and before ~= nil and targetEnchantAfter ~= before and targetEnchantAfter ~= 0 then
            targetChanged = true
            evidence[#evidence + 1] = string.format("target enchant changed %s -> %s (advisory; operation uncorrelated)", tostring(before), tostring(targetEnchantAfter))
        end
    end

    -- Skill, reagent loss and target changes do not identify the operation that
    -- caused them. Only prior confirmed ordinals or accepted, correlated ledger
    -- evidence can establish success. Never synthesize another ordinal here.
    if ledgerError or snapshot.ledgerError then
        confirmed = 0
        evidence[#evidence + 1] = ledgerError or snapshot.ledgerError
    end
    if snapshot.kind == "enchant" then confirmed = math.min(confirmed, 1) end
    local requested = math.max(1, tonumber(snapshot.requestedCount) or 1)
    confirmed = math.min(confirmed, requested)
    if ledgerID then snapshot.ledgerID = ledgerID end

    return {
        success = confirmed > 0 and not terminalLedgerFailure,
        confirmedCount = confirmed,
        requestedCount = requested,
        endingSkill = endingSkill,
        skillGain = skillGain,
        materials = materials,
        targetLinkAfter = targetLinkAfter,
        targetEnchantIDAfter = targetEnchantAfter,
        evidence = evidence,
        confidence = confirmed > 0 and "confirmed" or ((skillGain > 0 or materials.changedRows > 0 or targetChanged) and "possible" or "unresolved"),
    }
end

local function appendHistory(record, status)
    record.history[#record.history + 1] = copyTable(status)
    while #record.history > 24 do table.remove(record.history, 1) end
end

local function emit(status)
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("TRANSACTION_RECOVERY_UPDATED", status) end
end

function TransactionRecovery:CapturePending(kind, pending)
    local record = getStore()
    if not record then return false end
    local snapshot = normalizePending(kind, pending)
    if not snapshot then return false end
    record.pending = snapshot
    record.updatedAt = epochNow()
    self.liveSnapshotID = snapshot.id
    self.recoveringSnapshotID = nil
    return true, snapshot
end

function TransactionRecovery:ClearPending(reason)
    local record = getStore()
    if not record then return false end
    if record.pending then
        record.lastCleared = { id=record.pending.id, reason=reason, at=epochNow() }
    end
    local clearedID = record.pending and record.pending.id or nil
    record.pending = nil
    record.updatedAt = epochNow()
    if clearedID and self.liveSnapshotID == clearedID then self.liveSnapshotID = nil end
    if clearedID and self.recoveringSnapshotID == clearedID then self.recoveringSnapshotID = nil end
    return true
end

function TransactionRecovery:OnActionUpdated(kind, action)
    local crafting = JLP:GetModule("Crafting")
    local pending = kind == "enchant" and crafting and crafting.pendingEnchant or crafting and crafting.pendingCraft
    local status = tostring(action and action.status or "")
    if pending and (status == "dispatching" or status == "pending" or status == "crafting" or status == "confirmation-required" or status == "settlement-pending" or status == "") then
        return self:CapturePending(kind, pending)
    end
    if status == "success" or status == "failed" or status == "timeout" or status == "aborted_unknown" then
        local record = getStore()
        local pendingID = record and record.pending and record.pending.id or nil
        local wasLive = pendingID and self.liveSnapshotID == pendingID
        self:ClearPending("live-terminal-" .. status)
        if wasLive then
            self.current = {
                contract=self.contract,state="IDLE",label="No interrupted Craft/Enchant transaction",tone="muted",
                terminal=true,retryAllowed=true,key=action and action.key or nil,reason="live-transaction-completed",
            }
            self.revision = self.revision + 1
            self.current.revision = self.revision
            emit(self.current)
        end
        return true
    end
    return false
end

function TransactionRecovery:_SetStatus(status)
    self.current = status
    self.revision = self.revision + 1
    status.revision = self.revision
    local record = getStore()
    if record then
        record.lastByKey[status.key or "UNKNOWN"] = copyTable(status)
        record.updatedAt = epochNow()
        if status.terminal then appendHistory(record, status) end
    end
    emit(status)
    return status
end

function TransactionRecovery:_ApplyRecoveredSuccess(snapshot, result, reason)
    -- A verified prefix of a Craft All batch is NOT full batch success. The
    -- remaining ordinals stay unresolved and may never auto-resume after reload.
    local partial = snapshot.kind == "craft" and
        (snapshot.mode == "all" or (tonumber(result.requestedCount) or 1)>1) and
        (tonumber(result.confirmedCount) or 0) < (tonumber(result.requestedCount) or 1)
    result.partialBatch = partial
    local crafting = JLP:GetModule("Crafting")
    if crafting and crafting.ApplyRecoveredTransaction then
        crafting:ApplyRecoveredTransaction(snapshot.kind, snapshot, result)
    end
    local evidenceText = #result.evidence > 0 and table.concat(result.evidence, "; ") or "live evidence"
    local label
    if snapshot.kind == "enchant" then
        label = "Recovered success · Enchant"
    elseif snapshot.mode == "all" then
        label = string.format(partial and "Recovered partial · Craft All %d/%d" or "Recovered success · Craft All %d/%d", result.confirmedCount or 0, result.requestedCount or 1)
    else
        label = "Recovered success · Craft One"
    end
    local status = {
        contract = self.contract,
        state = partial and "RECOVERED_PARTIAL" or "RECOVERED_SUCCESS",
        label = label,
        tone = "good",
        terminal = true,
        retryAllowed = true,
        key = snapshot.key,
        kind = snapshot.kind,
        recipeID = snapshot.recipeID,
        recipeName = snapshot.recipeName,
        targetGUID = snapshot.targetGUID,
        targetName = snapshot.targetName,
        targetItemID = tonumber(snapshot.targetItemID),
        targetLocationKey = snapshot.targetLocationKey,
        targetProofContract = snapshot.targetProofContract,
        targetProofFingerprint = snapshot.targetProofFingerprint,
        targetValidationSource = snapshot.targetValidationSource,
        confirmationRequired = snapshot.confirmationRequired == true,
        confirmationEvent = snapshot.confirmationEvent,
        confirmationReason = snapshot.confirmationReason,
        confirmationAt = snapshot.confirmationAt,
        confirmationSignals = tonumber(snapshot.confirmationSignals) or 0,
        confirmationDuplicateSignals = tonumber(snapshot.confirmationDuplicateSignals) or 0,
        confirmationHistory = copyTable(snapshot.confirmationHistory),
        provisionalFailure = copyTable(snapshot.provisionalFailure),
        confirmedCount = result.confirmedCount,
        requestedCount = result.requestedCount,
        batchComplete = not partial,
        automaticResume = false,
        skillGain = result.skillGain,
        endingSkill = result.endingSkill,
        confidence = result.confidence,
        evidence = result.evidence,
        evidenceText = evidenceText,
        reason = reason or "reconciled-live-evidence",
        recoveredAt = epochNow(),
        snapshotID = snapshot.id,
        ledgerID = snapshot.ledgerID,
        authorityProvenance = copyTable(snapshot.authorityProvenance),
        killSwitchObserved = snapshot.killSwitchObserved == true,
        repeatStopRequested = snapshot.repeatStopRequested == true,
        repeatStopReason = snapshot.repeatStopReason,
        repeatStopSource = snapshot.repeatStopSource,
    }
    self:ClearPending("recovered-success")
    return self:_SetStatus(status)
end

function TransactionRecovery:_SetUnresolved(snapshot, result, reason)
    local age = math.max(0, epochNow() - (tonumber(snapshot.savedAt) or epochNow()))
    local kindLabel = snapshot.kind == "enchant" and "Enchant" or snapshot.mode == "all" and "Craft All" or "Craft One"
    local status = {
        contract = self.contract,
        state = "UNRESOLVED",
        label = "Checking interrupted " .. kindLabel .. "...",
        tone = "cyan",
        terminal = false,
        retryAllowed = false,
        key = snapshot.key,
        kind = snapshot.kind,
        recipeID = snapshot.recipeID,
        recipeName = snapshot.recipeName,
        targetGUID = snapshot.targetGUID,
        targetName = snapshot.targetName,
        targetItemID = tonumber(snapshot.targetItemID),
        targetLocationKey = snapshot.targetLocationKey,
        targetProofContract = snapshot.targetProofContract,
        targetProofFingerprint = snapshot.targetProofFingerprint,
        targetValidationSource = snapshot.targetValidationSource,
        confirmationRequired = snapshot.confirmationRequired == true,
        confirmationEvent = snapshot.confirmationEvent,
        confirmationReason = snapshot.confirmationReason,
        confirmationAt = snapshot.confirmationAt,
        confirmationSignals = tonumber(snapshot.confirmationSignals) or 0,
        confirmationDuplicateSignals = tonumber(snapshot.confirmationDuplicateSignals) or 0,
        confirmationHistory = copyTable(snapshot.confirmationHistory),
        provisionalFailure = copyTable(snapshot.provisionalFailure),
        confirmedCount = result and result.confirmedCount or 0,
        requestedCount = tonumber(snapshot.requestedCount) or 1,
        endingSkill = result and result.endingSkill or nil,
        confidence = "unresolved",
        evidence = result and result.evidence or {},
        evidenceText = result and #result.evidence > 0 and table.concat(result.evidence, "; ") or "No conclusive post-reload evidence yet",
        reason = reason or "awaiting-live-evidence",
        age = age,
        snapshotID = snapshot.id,
        ledgerID = snapshot.ledgerID,
        authorityProvenance = copyTable(snapshot.authorityProvenance),
        killSwitchObserved = snapshot.killSwitchObserved == true,
        repeatStopRequested = snapshot.repeatStopRequested == true,
        repeatStopReason = snapshot.repeatStopReason,
        repeatStopSource = snapshot.repeatStopSource,
        postReloadFailure = copyTable(snapshot.postReloadFailure),
    }
    return self:_SetStatus(status)
end

function TransactionRecovery:_ApplyRecoveredFailure(snapshot, reason)
    local ledger = JLP:GetModule("TransactionLedger")
    if ledger and snapshot.ledgerID then
        ledger:Close(snapshot.ledgerID,"failed",{source="reload-recovery",detail=reason or "matching post-reload failure"})
    end
    local crafting = JLP:GetModule("Crafting")
    if crafting and crafting.ApplyRecoveredFailure then
        crafting:ApplyRecoveredFailure(snapshot.kind, snapshot, reason or "matching post-reload failure")
    end
    local status = {
        contract = self.contract,
        state = "RECOVERED_FAILED",
        label = snapshot.kind == "enchant" and "Interrupted Enchant · failure confirmed after reload" or "Interrupted Craft One · failure confirmed after reload",
        tone = "warn",
        terminal = true,
        retryAllowed = true,
        key = snapshot.key,
        kind = snapshot.kind,
        recipeID = snapshot.recipeID,
        recipeName = snapshot.recipeName,
        targetGUID = snapshot.targetGUID,
        targetName = snapshot.targetName,
        targetItemID = tonumber(snapshot.targetItemID),
        targetLocationKey = snapshot.targetLocationKey,
        targetProofContract = snapshot.targetProofContract,
        targetProofFingerprint = snapshot.targetProofFingerprint,
        targetValidationSource = snapshot.targetValidationSource,
        confirmationRequired = snapshot.confirmationRequired == true,
        confirmationEvent = snapshot.confirmationEvent,
        confirmationReason = snapshot.confirmationReason,
        confirmationAt = snapshot.confirmationAt,
        confirmationSignals = tonumber(snapshot.confirmationSignals) or 0,
        confirmationDuplicateSignals = tonumber(snapshot.confirmationDuplicateSignals) or 0,
        confirmationHistory = copyTable(snapshot.confirmationHistory),
        provisionalFailure = copyTable(snapshot.provisionalFailure or snapshot.postReloadFailure),
        confirmedCount = math.max(0, tonumber(snapshot.completedCount) or 0),
        requestedCount = tonumber(snapshot.requestedCount) or 1,
        confidence = "matched-failure-after-grace",
        evidence = snapshot.postReloadFailure and { tostring(snapshot.postReloadFailure.detail or snapshot.postReloadFailure.event or "matching failure event") } or {},
        evidenceText = snapshot.postReloadFailure and tostring(snapshot.postReloadFailure.detail or snapshot.postReloadFailure.event or "matching failure event") or "matching failure event",
        reason = reason or "post-reload-failure-grace-expired",
        recoveredAt = epochNow(),
        snapshotID = snapshot.id,
        ledgerID = snapshot.ledgerID,
        authorityProvenance = copyTable(snapshot.authorityProvenance),
        killSwitchObserved = snapshot.killSwitchObserved == true,
        repeatStopRequested = snapshot.repeatStopRequested == true,
        repeatStopReason = snapshot.repeatStopReason,
        repeatStopSource = snapshot.repeatStopSource,
    }
    self:ClearPending("recovered-failed")
    return self:_SetStatus(status)
end

function TransactionRecovery:_AbortUnknown(snapshot, reason, evidence)
    local kindLabel = snapshot.kind == "enchant" and "Enchant" or snapshot.mode == "all" and "Craft All" or "Craft One"
    local ledger=JLP:GetModule("TransactionLedger")
    local ledgerConfirmed=ledger and snapshot.ledgerID and ledger:GetConfirmedCount(snapshot.ledgerID) or 0
    local status = {
        contract = self.contract,
        state = "ABORTED_UNKNOWN",
        label = "Interrupted " .. kindLabel .. " · result unknown · retry available",
        tone = "warn",
        terminal = true,
        retryAllowed = true,
        key = snapshot.key,
        kind = snapshot.kind,
        recipeID = snapshot.recipeID,
        recipeName = snapshot.recipeName,
        targetGUID = snapshot.targetGUID,
        targetName = snapshot.targetName,
        targetItemID = tonumber(snapshot.targetItemID),
        targetLocationKey = snapshot.targetLocationKey,
        targetProofContract = snapshot.targetProofContract,
        targetProofFingerprint = snapshot.targetProofFingerprint,
        targetValidationSource = snapshot.targetValidationSource,
        confirmationRequired = snapshot.confirmationRequired == true,
        confirmationEvent = snapshot.confirmationEvent,
        confirmationReason = snapshot.confirmationReason,
        confirmationAt = snapshot.confirmationAt,
        confirmationSignals = tonumber(snapshot.confirmationSignals) or 0,
        confirmationDuplicateSignals = tonumber(snapshot.confirmationDuplicateSignals) or 0,
        confirmationHistory = copyTable(snapshot.confirmationHistory),
        provisionalFailure = copyTable(snapshot.provisionalFailure or snapshot.postReloadFailure),
        confirmedCount = math.max(0, tonumber(snapshot.completedCount) or 0, tonumber(ledgerConfirmed) or 0),
        requestedCount = tonumber(snapshot.requestedCount) or 1,
        confidence = "unknown",
        evidence = evidence or {},
        evidenceText = evidence and #evidence > 0 and table.concat(evidence, "; ") or "No conclusive success evidence after reload",
        reason = reason or "recovery-grace-expired",
        recoveredAt = epochNow(),
        snapshotID = snapshot.id,
        ledgerID = snapshot.ledgerID,
        authorityProvenance = copyTable(snapshot.authorityProvenance),
        killSwitchObserved = snapshot.killSwitchObserved == true,
        repeatStopRequested = snapshot.repeatStopRequested == true,
        repeatStopReason = snapshot.repeatStopReason,
        repeatStopSource = snapshot.repeatStopSource,
    }
    if ledger and snapshot.ledgerID then ledger:Close(snapshot.ledgerID,"aborted_unknown",{source="reload-recovery",detail=reason}) end
    self:ClearPending("aborted-unknown")
    return self:_SetStatus(status)
end

function TransactionRecovery:RecoverPending(reason, forceFinalize)
    local record = getStore()
    local snapshot = record and record.pending or nil
    if type(snapshot) ~= "table" then
        local status = {
            contract = self.contract,
            state = "IDLE",
            label = "No interrupted Craft/Enchant transaction",
            tone = "muted",
            terminal = true,
            retryAllowed = true,
            reason = reason or "no-checkpoint",
        }
        self.current = status
        return status
    end
    -- Never calculate new skill, reagent or target deltas across an unknown
    -- or changed client interface. Legacy checkpoints remain historical but
    -- cannot certify a live success after reload without this receipt.
    if self.recoveringSnapshotID == snapshot.id and not checkpointMatchesLive(snapshot) then
        local uncertain = {success=false, confirmedCount=0,
            evidence={"checkpoint client session unknown or changed"}, confidence="unresolved"}
        if forceFinalize then
            return self:_AbortUnknown(snapshot, "recovery-session-unverified", uncertain.evidence)
        end
        return self:_SetUnresolved(snapshot, uncertain, "recovery-session-unverified")
    end
    local result = evaluateSnapshot(snapshot)
    if result.success then return self:_ApplyRecoveredSuccess(snapshot, result, reason) end
    if forceFinalize and snapshot.postReloadFailure then
        return self:_ApplyRecoveredFailure(snapshot, reason or "post-reload-failure-grace-expired")
    end
    if forceFinalize then return self:_AbortUnknown(snapshot, reason or "forced-finalize", result.evidence) end
    return self:_SetUnresolved(snapshot, result, reason)
end

function TransactionRecovery:ReconcileLivePending(kind, pending, reason)
    if type(pending) ~= "table" then return false, nil, nil end
    local snapshot = normalizePending(kind or "craft", pending)
    if not snapshot then return false, nil, nil end
    local result = evaluateSnapshot(snapshot)
    return result.success == true, result, snapshot
end

function TransactionRecovery:Observe(reason, forceFinalize)
    local record = getStore()
    if not record or type(record.pending) ~= "table" then return self:GetStatus() end
    if self.recoveringSnapshotID ~= record.pending.id then return self:GetStatus(record.pending.key) end
    return self:RecoverPending(reason or "observe", forceFinalize)
end

local function recoveryEventEligible(pending)
    if type(pending) ~= "table" then return false end
    if pending.kind == "craft" and pending.mode == "all" then
        -- Old checkpoints do not contain ordinal-in-flight evidence. A late
        -- recipe-matching event must not promote an unissued batch ordinal.
        if pending.strictTargetSafeCraftAll ~= true or
            pending.strictAwaitingUserClick == true or pending.strictOrdinalInFlight ~= true then
            return false
        end
    end
    return true
end

-- Bind an in-flight client cast GUID while the original transaction is still
-- live. This is only an observational correlation receipt; it never dispatches
-- a protected action. After reload an arbitrary new cast of the same recipe
-- must not be mistaken for the interrupted cast.
function TransactionRecovery:OnSpellcastSent(unitTarget, target, castGUID, spellID)
    if unitTarget ~= "player" or type(castGUID) ~= "string" or castGUID == "" then return false end
    local record = getStore()
    local snapshot = record and record.pending or nil
    if not snapshot or self.liveSnapshotID ~= snapshot.id or
        not checkpointMatchesLive(snapshot) or
        tonumber(snapshot.recipeID) ~= tonumber(spellID) or
        (snapshot.status ~= "dispatching" and snapshot.status ~= "pending") or
        (snapshot.kind == "craft" and snapshot.mode == "all" and
            (snapshot.strictOrdinalInFlight ~= true or snapshot.strictAwaitingUserClick == true)) then return false end
    if snapshot.expectedCastGUID and snapshot.expectedCastGUID ~= castGUID then return false end
    local crafting = JLP:GetModule("Crafting")
    local active = crafting and (snapshot.kind == "enchant" and crafting.pendingEnchant or crafting.pendingCraft)
    if not active or tostring(active.transactionID or "") ~= tostring(snapshot.ledgerID or "") or
        tonumber(active.recipeID) ~= tonumber(spellID) then return false end
    snapshot.expectedCastGUID = castGUID
    active.expectedCastGUID = castGUID
    record.updatedAt = epochNow()
    return true
end

function TransactionRecovery:OnTradeSkillCraftBegin(recipeSpellID)
    local record = getStore()
    local pending = record and record.pending or nil
    if not recoveryEventEligible(pending) or tonumber(recipeSpellID) ~= tonumber(pending.recipeID) then return false end
    if self.recoveringSnapshotID ~= pending.id then return false end
    pending.postReloadCraftBegin = true
    pending.status = "crafting"
    return self:Observe("matching-craft-begin", false)
end

-- A matching recipe is necessary, but is not sufficient to correlate a
-- post-reload event with an interrupted native request. An event denied by the
-- ledger (duplicate, cross-transaction replay, terminal tx, etc.) must never
-- become an independent success flag in the recovery snapshot.
function TransactionRecovery:OnTradeSkillItemCraftedResult(data)
    local record = getStore()
    local pending = record and record.pending or nil
    if not recoveryEventEligible(pending) or type(data) ~= "table" then return false end
    if self.recoveringSnapshotID ~= pending.id or not checkpointMatchesLive(pending) then return false end
    if pending.kind == "enchant" and data.isEnchant ~= true then return false end
    if pending.kind == "craft" and data.isEnchant == true then return false end
    if pending.kind == "enchant" and (tostring(pending.targetGUID or "") == "" or
        (data.targetGUID ~= nil and tostring(data.targetGUID) ~= tostring(pending.targetGUID))) then
        return false
    end
    local resultRecipe = data.recipeID or data.spellID or data.craftingSpellID
    if resultRecipe == nil or tonumber(resultRecipe) ~= tonumber(pending.recipeID) then return false end
    local ledger,ledgerID,_,ledgerError = recoveryLedger(pending)
    if not ledger or ledgerError or pending.ledgerError then return false end
    pending.ledgerID = ledgerID
    if not ledgerID then return false end
    if pending.kind == "enchant" then
        -- The recipe alone is not a unique result identity. Do not confirm an
        -- anonymous result or a result rejected by the persistent ledger.
        local evidenceID = data.operationID or data.itemGUID
        if evidenceID == nil or tostring(evidenceID) == "" then return false end
        -- A post-reload operation ID never proves ownership of the interrupted
        -- operation unless that ID was persisted before logout. Without it,
        -- this event could belong to a new craft of the same recipe.
        if data.operationID == nil or pending.expectedOperationID == nil or
            tostring(data.operationID) == "" or tostring(data.operationID) == "0" or
            tostring(pending.expectedOperationID) ~= tostring(data.operationID) then return false end
        local confirmed = ledger:ConfirmEnchant(ledgerID,evidenceID,"recovery-crafted-result",data)
        if not confirmed then return false end
        pending.postReloadSuccess = "ledger-confirmed matching enchant result after reload"
    else
        -- Craft-result payloads are secondary observations: the ledger records
        -- them but does not confirm a cast. A uniquely correlated, accepted
        -- spellcast or previously confirmed ordinal is still required.
        local _, _, _, evidenceState = ledger:RecordCraftResult(ledgerID,data,"recovery-crafted-result")
        if evidenceState ~= "recorded" then return false end
    end
    pending.postReloadResult = copyTable(data)
    self:RecoverPending("crafted-result-after-reload",false)
    return true
end

function TransactionRecovery:OnSpellcastSucceeded(unitTarget, castGUID, spellID)
    if unitTarget ~= "player" then return false end
    local record = getStore()
    local pending = record and record.pending or nil
    if not recoveryEventEligible(pending) or tonumber(spellID) ~= tonumber(pending.recipeID) then return false end
    if self.recoveringSnapshotID ~= pending.id or not checkpointMatchesLive(pending) then return false end
    if pending.kind == "enchant" and tostring(pending.targetGUID or "") == "" then return false end
    -- Recipe ID alone does not correlate a cast across /reload. Require a
    -- pre-reload persisted cast identity; otherwise retain only already
    -- confirmed ledger ordinals and leave the cast advisory.
    if type(castGUID) ~= "string" or castGUID == "" or
        type(pending.expectedCastGUID) ~= "string" or
        pending.expectedCastGUID ~= castGUID then return false end
    local ledger,ledgerID,_,ledgerError = recoveryLedger(pending)
    if not ledger or ledgerError or pending.ledgerError then return false end
    pending.ledgerID = ledgerID
    if not ledgerID then return false end
    local confirmed
    if pending.kind == "enchant" then
        -- Do not identify separate enchant requests by SpellID alone.
        if castGUID == nil or tostring(castGUID) == "" then return false end
        confirmed = ledger:ConfirmEnchant(ledgerID,castGUID,"recovery-spellcast-success",{castGUID=castGUID,spellID=spellID})
    else
        confirmed = ledger:ConfirmCraft(ledgerID,castGUID,spellID,"recovery-spellcast-success")
    end
    if not confirmed then return false end
    pending.postReloadSuccess = "ledger-confirmed matching spellcast success after reload"
    pending.postReloadCastGUID = castGUID
    self:RecoverPending("spellcast-success-after-reload",false)
    return true
end

function TransactionRecovery:OnSpellcastFailed(event, unitTarget, castGUID, spellID)
    if unitTarget ~= "player" then return false end
    local record = getStore()
    local pending = record and record.pending or nil
    if not recoveryEventEligible(pending) or tonumber(spellID) ~= tonumber(pending.recipeID) then return false end
    if self.recoveringSnapshotID ~= pending.id or not checkpointMatchesLive(pending) then return false end
    if type(castGUID) ~= "string" or castGUID == "" or
        type(pending.expectedCastGUID) ~= "string" or
        pending.expectedCastGUID ~= castGUID then return false end
    local detail = event == "UNIT_SPELLCAST_INTERRUPTED" and "matching cast interrupted after reload" or "matching cast failed after reload"
    local provenance = type(pending.authorityProvenance) == "table" and pending.authorityProvenance or nil
    if provenance and (provenance.contract == "research-native-dispatch-provenance-v1" or provenance.contract == "production-enchanting-native-dispatch-provenance-v1") then
        -- Alpha77 keeps a matching native-research failure provisional until the
        -- existing reload grace expires. A crafted-result or success event can
        -- still arrive out of order and must win before terminal failure.
        pending.postReloadFailure = { event=tostring(event or "UNIT_SPELLCAST_FAILED"), castGUID=castGUID, spellID=spellID, detail=detail, at=epochNow() }
        self:RecoverPending("matching-failure-awaiting-settlement-grace", false)
        return true
    end
    self:_AbortUnknown(pending, string.lower(tostring(event or "spellcast-failed")), { detail })
    return true
end

function TransactionRecovery:CanStart(kind, key)
    local record = getStore()
    local pending = record and record.pending or nil
    if type(pending) ~= "table" then return true end
    if self.recoveringSnapshotID ~= pending.id then return true end
    local current = self.current or self:RecoverPending("preflight", false)
    if current and current.state == "RECOVERED_SUCCESS" then return true end
    if current and current.state == "ABORTED_UNKNOWN" then return true end
    local label = kind == "enchant" and "enchant" or "craft"
    return false, "An interrupted " .. label .. " is still being reconciled after /reload. Wait for live inventory/profession state to settle before retrying."
end

function TransactionRecovery:Initialize()
    if self.initialized then return self:GetStatus() end
    self.initialized = true
    if JLP.EventBus then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action) TransactionRecovery:OnActionUpdated("craft", action) end)
        JLP.EventBus:On("ENCHANT_ACTION_UPDATED", function(action) TransactionRecovery:OnActionUpdated("enchant", action) end)
    end
    local record = getStore()
    if record and record.pending then self.recoveringSnapshotID = record.pending.id end
    local status = self:RecoverPending("player-login", false)
    if record and record.pending and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local id = record.pending.id
        C_Timer.After(self.graceSeconds, function()
            local liveRecord = getStore()
            if liveRecord and liveRecord.pending and liveRecord.pending.id == id then
                TransactionRecovery:Observe("recovery-grace-expired", true)
            end
        end)
    end
    return status
end

function TransactionRecovery:OnLogout()
    local crafting = JLP:GetModule("Crafting")
    if crafting and crafting.pendingEnchant then self:CapturePending("enchant", crafting.pendingEnchant)
    elseif crafting and crafting.pendingCraft then self:CapturePending("craft", crafting.pendingCraft) end
    return true
end

function TransactionRecovery:GetStatus(key)
    local current = self.current
    if current and (not key or current.key == key or current.state == "IDLE") then return current end
    local record = getStore()
    local last = record and record.lastByKey and record.lastByKey[key] or nil
    if last then return last end
    return {
        contract = self.contract,
        state = "IDLE",
        label = "No interrupted Craft/Enchant transaction",
        tone = "muted",
        terminal = true,
        retryAllowed = true,
        revision = self.revision,
    }
end

function TransactionRecovery:GetActionState(key, kind)
    local status = self:GetStatus(key)
    if not status or status.kind ~= kind then return nil end
    if status.state == "UNRESOLVED" then
        return {
            status = "recovery_unresolved",
            recovery = true,
            key = status.key,
            recipeID = status.recipeID,
            recipeName = status.recipeName,
            mode = status.kind == "craft" and ((status.requestedCount or 1) > 1 and "all" or "one") or nil,
            requestedCount = status.requestedCount,
            completedCount = status.confirmedCount or 0,
            targetGUID = status.targetGUID,
            targetName = status.targetName,
            token = status.snapshotID,
        }
    end
    return nil
end

function TransactionRecovery:GetCheckpoint()
    local record = getStore()
    return record and record.pending or nil
end

function TransactionRecovery:GetSummary()
    local record = getStore()
    local pending = record and record.pending or nil
    local lines = { "Transaction recovery: " .. tostring((self:GetStatus() or {}).label or "Unavailable") }
    if pending then
        lines[#lines + 1] = string.format("Pending: %s · %s · %s", tostring(pending.kind or "transaction"), tostring(pending.recipeName or pending.recipeID or "unknown recipe"), tostring(pending.status or "unknown"))
        lines[#lines + 1] = string.format("Confirmed before reload: %d/%d", tonumber(pending.completedCount) or 0, tonumber(pending.requestedCount) or 1)
        if pending.ledgerID then lines[#lines + 1] = "Ledger: " .. tostring(pending.ledgerID) end
    else
        lines[#lines + 1] = "Pending checkpoint: none"
    end
    local current = self.current
    if current and current.evidenceText then lines[#lines + 1] = "Evidence: " .. tostring(current.evidenceText) end
    lines[#lines + 1] = "Policy: success requires live/confirmed evidence; otherwise retry is released only as aborted/unknown."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("TransactionRecovery", TransactionRecovery)
