local _, JLP = ...

-- Persistent idempotency ledger for direct Craft One / Craft All / Enchant
-- transactions.  TransactionRecovery persists correlation checkpoints; this
-- ledger persists the finer-grained confirmation identity of each individual
-- craft so duplicate/overlapping result events cannot advance a batch twice.
local TransactionLedger = {
    contract = "build-provenance-craft-transaction-ledger-v4",
    ledgerSchema = 5,
    maxTransactions = 64,
    maxEvidencePerUnit = 8,
    initialized = false,
}

local function currentBuildProvenance()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    if buildInfo and buildInfo.GetProvenance then
        local provenance = buildInfo:GetProvenance({allowTargetFallback=false})
        if provenance then return provenance end
    end
    -- An unavailable API is evidence UNKNOWN, never historical target evidence.
    return {game="Forever",build=nil,interface=nil,token="forever:unknown|interface:unknown",
        source="unknown",quality="UNKNOWN",addonVersion=JLP.version}
end
local function epochNow()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function copyScalarTable(value, depth)
    if type(value) ~= "table" then return value end
    depth = tonumber(depth) or 0
    if depth > 4 then return nil end
    local out = {}
    for k, v in pairs(value) do
        local kt, vt = type(k), type(v)
        if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
            out[k] = vt == "table" and copyScalarTable(v, depth + 1) or v
        end
    end
    return out
end

local function getStore()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.transactionLedger = JLP.DB.account.transactionLedger or { characters = {} }
    JLP.DB.account.transactionLedger.characters = JLP.DB.account.transactionLedger.characters or {}
    local key = characterKey()
    local store = JLP.DB.account.transactionLedger.characters[key]
    if type(store) ~= "table" then
        store = { schema=TransactionLedger.ledgerSchema, nextSerial=0, transactions={}, order={}, castEvidenceIndex={}, updatedAt=nil }
        JLP.DB.account.transactionLedger.characters[key] = store
    end
    store.schema = TransactionLedger.ledgerSchema
    store.nextSerial = math.max(0, tonumber(store.nextSerial) or 0)
    store.transactions = type(store.transactions) == "table" and store.transactions or {}
    store.order = type(store.order) == "table" and store.order or {}
    store.castEvidenceIndex = type(store.castEvidenceIndex) == "table" and store.castEvidenceIndex or {}
    return store, key
end

local function emit(tx)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("TRANSACTION_LEDGER_UPDATED", tx)
    end
end

local function trimStore(store)
    local guard = 0
    while #store.order > TransactionLedger.maxTransactions and guard < #store.order + 4 do
        guard = guard + 1
        local id = store.order[1]
        local tx = store.transactions[id]
        if tx and not tx.closedAt and tx.status ~= "success" and tx.status ~= "failed" and tx.status ~= "timeout" and tx.status ~= "aborted_unknown" then
            table.remove(store.order, 1)
            store.order[#store.order + 1] = id
        else
            table.remove(store.order, 1)
            store.transactions[id] = nil
            for castGUID, owner in pairs(store.castEvidenceIndex or {}) do
                if owner == id then store.castEvidenceIndex[castGUID] = nil end
            end
        end
    end
end

local function normalizeKind(kind, action)
    if kind == "enchant" or kind == "craft" then return kind end
    return action and action.targetGUID and "enchant" or "craft"
end

local function requestedCount(kind, action)
    if kind == "enchant" then return 1 end
    return math.max(1, math.floor(tonumber(action and action.requestedCount) or 1))
end

local function ensureTransactionShape(tx)
    tx.units = type(tx.units) == "table" and tx.units or {}
    tx.evidenceIndex = type(tx.evidenceIndex) == "table" and tx.evidenceIndex or {}
    tx.confirmedCount = math.max(0, tonumber(tx.confirmedCount) or 0)
    tx.requestedCount = math.max(1, tonumber(tx.requestedCount) or 1)
    tx.reconciliation = type(tx.reconciliation) == "table" and tx.reconciliation or {}
    if tx.buildProvenance ~= nil and type(tx.buildProvenance) ~= "table" then tx.buildProvenance = nil end
    if tx.authorityProvenance ~= nil and type(tx.authorityProvenance) ~= "table" then tx.authorityProvenance = nil end
    for index, unit in pairs(tx.units) do
        if type(unit) == "table" then
            unit.index = tonumber(unit.index) or tonumber(index)
            unit.id = unit.id or (tostring(tx.id or "transaction") .. "#" .. tostring(unit.index or index))
            unit.evidence = type(unit.evidence) == "table" and unit.evidence or {}
            unit.reconciliation = type(unit.reconciliation) == "table" and unit.reconciliation or {}
            unit.reconciliation.materials = type(unit.reconciliation.materials) == "table" and unit.reconciliation.materials or {}
        end
    end
    return tx
end

local function recomputeConfirmed(tx)
    local count = 0
    for i = 1, tx.requestedCount do
        local unit = tx.units[i]
        if unit and unit.state == "confirmed" then count = count + 1 else break end
    end
    tx.confirmedCount = count
    return count
end

local function evidenceKey(prefix, value)
    if value == nil or value == "" then return nil end
    return tostring(prefix) .. ":" .. tostring(value)
end

local function isTerminalStatus(status)
    status = tostring(status or "")
    return status == "success" or status == "failed" or status == "timeout" or status == "aborted_unknown"
end

function TransactionLedger:Initialize()
    self.initialized = true
    local store = getStore()
    return store ~= nil
end

function TransactionLedger:Begin(kind, action, explicitID)
    if type(action) ~= "table" then return nil end
    kind = normalizeKind(kind, action)
    local store = getStore()
    if not store then return nil end

    local id = explicitID or action.ledgerID or action.transactionID
    local tx = id and store.transactions[id] or nil
    if not tx then
        if not id then
            store.nextSerial = store.nextSerial + 1
            id = string.format("%s:%d", kind, store.nextSerial)
        end
        tx = {
            schema = self.ledgerSchema,
            id = id,
            kind = kind,
            key = action.key or (kind == "enchant" and "ENCHANTING" or nil),
            recipeID = tonumber(action.recipeID),
            recipeName = action.recipeName,
            mode = action.mode or (kind == "craft" and (requestedCount(kind, action) > 1 and "all" or "one") or nil),
            requestedCount = requestedCount(kind, action),
            confirmedCount = 0,
            targetGUID = action.targetGUID,
            targetName = action.targetName,
            difficultyStart = copyScalarTable(action.difficultySnapshot or action.currentDifficulty),
            buildProvenance = copyScalarTable(action.buildProvenance) or currentBuildProvenance(),
            authorityProvenance = copyScalarTable(action.authorityProvenance),
            status = action.status or "pending",
            units = {},
            evidenceIndex = {},
            createdAt = epochNow(),
            updatedAt = epochNow(),
        }
        store.transactions[id] = tx
        store.order[#store.order + 1] = id
        trimStore(store)
    else
        ensureTransactionShape(tx)
        -- A settled identifier must never be reopened by Begin/EnsureSnapshot.
        -- Otherwise a stale checkpoint could change tx.status and make the
        -- terminal ledger writable again despite tx.closedAt still existing.
        if tx.closedAt ~= nil or isTerminalStatus(tx.status) then
            return nil, tx, "terminal-transaction-cannot-reopen"
        end
        tx.kind = tx.kind or kind
        tx.key = tx.key or action.key or (kind == "enchant" and "ENCHANTING" or nil)
        tx.recipeID = tx.recipeID or tonumber(action.recipeID)
        tx.recipeName = tx.recipeName or action.recipeName
        tx.mode = tx.mode or action.mode
        tx.requestedCount = math.max(tx.requestedCount or 1, requestedCount(kind, action))
        tx.targetGUID = tx.targetGUID or action.targetGUID
        tx.targetName = tx.targetName or action.targetName
        tx.difficultyStart = tx.difficultyStart or copyScalarTable(action.difficultySnapshot or action.currentDifficulty)
        tx.buildProvenance = tx.buildProvenance or copyScalarTable(action.buildProvenance)
        tx.authorityProvenance = tx.authorityProvenance or copyScalarTable(action.authorityProvenance)
        if action.status then tx.status = action.status end
        tx.updatedAt = epochNow()
    end

    action.ledgerID = id
    action.transactionID = id
    store.updatedAt = epochNow()
    return id, tx
end

function TransactionLedger:EnsureSnapshot(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local kind = normalizeKind(snapshot.kind, snapshot)
    local explicitID = snapshot.ledgerID
    if not explicitID then
        explicitID = "recovery:" .. tostring(snapshot.id or snapshot.token or "unknown")
    end
    local id, tx = self:Begin(kind, snapshot, explicitID)
    if not id then return nil end
    snapshot.ledgerID = id
    local confirmed = math.max(0, tonumber(snapshot.completedCount) or 0)
    if confirmed > 0 then
        self:ConfirmThrough(id, confirmed, "snapshot:" .. tostring(snapshot.id or id), "pre-reload-confirmed", {
            source = "transaction-recovery-checkpoint",
        })
    end
    return id, self:GetTransaction(id)
end

function TransactionLedger:GetTransaction(id)
    if not id then return nil end
    local store = getStore()
    local tx = store and store.transactions[id] or nil
    if tx then ensureTransactionShape(tx) end
    return tx
end

function TransactionLedger:GetConfirmedCount(id)
    local tx = self:GetTransaction(id)
    return tx and math.max(0, tonumber(tx.confirmedCount) or 0) or 0
end

local function ensureUnit(tx, index)
    if not tx then return nil end
    index = math.max(1, math.floor(tonumber(index) or 1))
    if index > tx.requestedCount then return nil end
    local unit = tx.units[index]
    if type(unit) ~= "table" then
        unit = {
            id = tostring(tx.id) .. "#" .. tostring(index),
            index = index,
            state = "provisional",
            evidence = {},
            reconciliation = { materials = {} },
            createdAt = epochNow(),
        }
        tx.units[index] = unit
    end
    unit.evidence = type(unit.evidence) == "table" and unit.evidence or {}
    unit.reconciliation = type(unit.reconciliation) == "table" and unit.reconciliation or {}
    unit.reconciliation.materials = type(unit.reconciliation.materials) == "table" and unit.reconciliation.materials or {}
    return unit
end

local function sameScalar(a, b)
    if a == nil and b == nil then return true end
    return tostring(a) == tostring(b)
end

local function mergeSkill(unit, skill)
    if type(skill) ~= "table" then return false end
    local current = unit.reconciliation.skill
    local source = tostring(skill.source or "aggregate-skill-inference")
    local observed = source == "live-unit-skill" or source == "single-unit-transaction"
    local currentObserved = current and (current.source == "live-unit-skill" or current.source == "single-unit-transaction")
    if currentObserved and not observed then return false end
    local nextSkill = {
        before = tonumber(skill.before),
        after = tonumber(skill.after),
        gain = math.max(0, tonumber(skill.gain) or 0),
        status = skill.status or ((tonumber(skill.gain) or 0) > 0 and "skill-up" or "no-skill-up"),
        source = source,
        confidence = skill.confidence or (observed and "observed" or "aggregate"),
        reconciledAt = epochNow(),
    }
    local changed = not current
        or not sameScalar(current.before, nextSkill.before)
        or not sameScalar(current.after, nextSkill.after)
        or not sameScalar(current.gain, nextSkill.gain)
        or current.status ~= nextSkill.status
        or current.source ~= nextSkill.source
        or current.confidence ~= nextSkill.confidence
    if changed then unit.reconciliation.skill = nextSkill end
    return changed
end

local function mergeDifficulty(unit, difficulty)
    if type(difficulty) ~= "table" or not difficulty.token then return false end
    local token = string.lower(tostring(difficulty.token or ""))
    if token ~= "orange" and token ~= "yellow" and token ~= "green" and token ~= "gray" then return false end
    local current = unit.reconciliation.difficulty
    local nextDifficulty = {
        token = token,
        label = difficulty.label or (token:sub(1,1):upper() .. token:sub(2)),
        apiName = difficulty.apiName,
        relativeDifficulty = tonumber(difficulty.relativeDifficulty),
        source = difficulty.source or "recipe-difficulty",
        confidence = difficulty.confidence or "verified",
        observedAt = tonumber(difficulty.observedAt),
        reconciledAt = epochNow(),
    }
    -- A verified pre-craft observation is stronger than inferred or unknown
    -- metadata.  Never replace it with weaker evidence during reload recovery.
    if current and current.confidence == "verified" and nextDifficulty.confidence ~= "verified" then return false end
    local changed = not current
        or current.token ~= nextDifficulty.token
        or current.source ~= nextDifficulty.source
        or current.confidence ~= nextDifficulty.confidence
        or not sameScalar(current.relativeDifficulty, nextDifficulty.relativeDifficulty)
    if changed then unit.reconciliation.difficulty = nextDifficulty end
    return changed
end

local function mergeMaterial(unit, material)
    if type(material) ~= "table" or not tonumber(material.itemID) then return false end
    local key = tostring(math.floor(tonumber(material.itemID)))
    local current = unit.reconciliation.materials[key]
    local nextMaterial = {
        itemID = math.floor(tonumber(material.itemID)),
        name = material.name,
        expected = math.max(0, tonumber(material.expected) or 0),
        consumed = math.max(0, tonumber(material.consumed) or 0),
        status = material.status or "unverified",
        source = material.source or "batch-material-delta",
        confidence = material.confidence or "aggregate",
        batchBeforeBags = tonumber(material.batchBeforeBags),
        batchAfterBags = tonumber(material.batchAfterBags),
        reconciledAt = epochNow(),
    }
    local changed = not current
        or not sameScalar(current.expected, nextMaterial.expected)
        or not sameScalar(current.consumed, nextMaterial.consumed)
        or current.status ~= nextMaterial.status
        or current.source ~= nextMaterial.source
        or current.confidence ~= nextMaterial.confidence
        or not sameScalar(current.batchBeforeBags, nextMaterial.batchBeforeBags)
        or not sameScalar(current.batchAfterBags, nextMaterial.batchAfterBags)
    if changed then unit.reconciliation.materials[key] = nextMaterial end
    return changed
end

function TransactionLedger:ReconcileUnit(id, index, payload)
    local tx = self:GetTransaction(id)
    local unit = tx and ensureUnit(tx, index) or nil
    if not tx or not unit or type(payload) ~= "table" then return false, tx, unit end
    local changed = false
    if payload.skill then changed = mergeSkill(unit, payload.skill) or changed end
    if payload.difficulty then changed = mergeDifficulty(unit, payload.difficulty) or changed end
    for _, material in ipairs(payload.materials or {}) do changed = mergeMaterial(unit, material) or changed end
    if payload.recovered ~= nil and unit.reconciliation.recovered ~= (payload.recovered and true or false) then
        unit.reconciliation.recovered = payload.recovered and true or false
        changed = true
    end
    if payload.recoveryEvidence and unit.reconciliation.recoveryEvidence ~= payload.recoveryEvidence then
        unit.reconciliation.recoveryEvidence = tostring(payload.recoveryEvidence)
        changed = true
    end
    if changed then
        unit.reconciliation.updatedAt = epochNow()
        tx.updatedAt = epochNow()
        local store = getStore()
        if store then store.updatedAt = epochNow() end
        emit(tx)
    end
    return changed, tx, unit
end

function TransactionLedger:ReconcileDifficulty(id, index, difficulty)
    if type(difficulty) ~= "table" or not difficulty.token then return false, self:GetTransaction(id), nil end
    return self:ReconcileUnit(id, index, { difficulty = difficulty })
end

-- Reconcile an aggregate skill delta back onto stable confirmed ordinals.  Live
-- per-unit observations are preserved; any remaining aggregate gain is assigned
-- deterministically to unobserved ordinals and explicitly labelled as inferred.
-- This makes the ledger useful after reload without claiming more precision than
-- the client actually supplied.
function TransactionLedger:ReconcileSkillAggregate(id, startedSkill, endingSkill)
    local tx = self:GetTransaction(id)
    if not tx then return false, nil end
    local confirmed = math.max(0, tonumber(tx.confirmedCount) or 0)
    if confirmed <= 0 then return false, tx end
    startedSkill, endingSkill = tonumber(startedSkill), tonumber(endingSkill)
    if not startedSkill or not endingSkill then return false, tx end
    local totalGain = math.min(confirmed, math.max(0, endingSkill - startedSkill))
    local observedGain = 0
    local unobserved = {}
    for index = 1, confirmed do
        local unit = ensureUnit(tx, index)
        local skill = unit and unit.reconciliation and unit.reconciliation.skill or nil
        if skill and (skill.source == "live-unit-skill" or skill.source == "single-unit-transaction") then
            observedGain = observedGain + math.max(0, tonumber(skill.gain) or 0)
        else
            unobserved[#unobserved + 1] = index
        end
    end
    local remaining = math.max(0, totalGain - observedGain)
    local changed = false
    -- Keep a deterministic skill-position cursor so every inferred stable
    -- ordinal also carries the skill at which the craft occurred.  This is
    -- aggregate evidence (not a claim of a live per-craft observation), but it
    -- lets downstream telemetry keep 150, 155 and 160-era outcomes separated.
    local cursorSkill = startedSkill
    for index = 1, confirmed do
        local unit = ensureUnit(tx, index)
        local currentSkill = unit and unit.reconciliation and unit.reconciliation.skill or nil
        if currentSkill and (currentSkill.source == "live-unit-skill" or currentSkill.source == "single-unit-transaction") then
            local before = tonumber(currentSkill.before) or cursorSkill
            local gain = math.max(0, tonumber(currentSkill.gain) or 0)
            local after = tonumber(currentSkill.after) or (before + gain)
            -- Existing observed evidence remains authoritative; only advance the
            -- aggregate cursor from it.
            cursorSkill = math.max(cursorSkill, after)
        else
            local gain = remaining > 0 and 1 or 0
            if gain > 0 then remaining = remaining - 1 end
            local source = confirmed == 1 and "single-unit-transaction" or "aggregate-skill-inference"
            local confidence = confirmed == 1 and "transaction" or "aggregate"
            local before = cursorSkill
            local after = before + gain
            local c = self:ReconcileUnit(id, index, { skill = {
                before = before,
                after = after,
                gain = gain,
                status = gain > 0 and "skill-up" or "no-skill-up",
                source = source,
                confidence = confidence,
            } })
            changed = c or changed
            cursorSkill = after
        end
    end
    tx = self:GetTransaction(id)
    tx.reconciliation.skillGain = totalGain
    tx.reconciliation.noSkillCount = math.max(0, confirmed - totalGain)
    tx.reconciliation.startedSkill = startedSkill
    tx.reconciliation.endingSkill = endingSkill
    tx.reconciliation.skillReconciledAt = epochNow()
    return changed, tx
end

-- Split the observed batch material delta across stable confirmed ordinals.  If
-- the aggregate delta exactly matches perCraft * confirmedCount, each unit gets
-- an exact reconciled consumption record.  Partial/ambiguous totals remain
-- explicitly marked aggregate-partial rather than being promoted to certainty.
function TransactionLedger:ReconcileMaterialAggregate(id, consumption)
    local tx = self:GetTransaction(id)
    if not tx or type(consumption) ~= "table" then return false, tx end
    local confirmed = math.max(0, tonumber(tx.confirmedCount) or 0)
    if confirmed <= 0 then return false, tx end
    -- The aggregate must contain independently observed before+after bag
    -- readings for every reagent. Never settle a material receipt on a nil
    -- reading normalized to zero or on incomplete half-observed batches.
    for _,row in ipairs(consumption) do
        if type(row)~="table" or type(row.beforeBags)~="number" or
            type(row.afterBags)~="number" or row.beforeBags~=row.beforeBags or
            row.afterBags~=row.afterBags or row.beforeBags<0 or row.afterBags<0 or
            row.beforeBags==math.huge or row.afterBags==math.huge then
            return false,tx,"MATERIAL_OBSERVATION_UNKNOWN"
        end
    end
    local changed = false
    for _, row in ipairs(consumption) do
        local itemID = tonumber(row.itemID)
        local perCraft = math.max(0, tonumber(row.perCraft) or ((confirmed > 0 and tonumber(row.expected)) and (tonumber(row.expected) / confirmed)) or 0)
        local observedTotal = math.max(0, tonumber(row.consumed) or 0)
        local expectedTotal = perCraft * confirmed
        local exact = math.abs(observedTotal - expectedTotal) < 0.0001
        local remaining = observedTotal
        for index = 1, confirmed do
            local allocated = math.min(perCraft, math.max(0, remaining))
            remaining = math.max(0, remaining - allocated)
            local status = perCraft <= 0 and "not-required" or (allocated >= perCraft and "consumed" or (allocated > 0 and "partial" or "unverified"))
            local c = self:ReconcileUnit(id, index, { materials = {{
                itemID = itemID,
                name = row.name,
                expected = perCraft,
                consumed = allocated,
                status = status,
                source = "batch-material-delta",
                confidence = exact and "aggregate-exact" or "aggregate-partial",
                batchBeforeBags = row.beforeBags,
                batchAfterBags = row.afterBags,
            }} })
            changed = c or changed
        end
    end
    tx = self:GetTransaction(id)
    tx.reconciliation.materialsReconciledAt = epochNow()
    return changed, tx
end

function TransactionLedger:_AddEvidence(id, index, key, evidenceType, data, confirm)
    local tx = self:GetTransaction(id)
    if not tx or not key or key == "" then return false, tx, nil, "invalid" end
    if tx.closedAt ~= nil or isTerminalStatus(tx.status) then
        return false, tx, nil, "terminal-closed"
    end
    local existingIndex = tx.evidenceIndex[key]
    if existingIndex then
        local existing = tx.units[existingIndex]
        return false, tx, existing, "duplicate"
    end

    index = math.max(1, math.floor(tonumber(index) or (tx.confirmedCount + 1)))
    if index > tx.requestedCount then return false, tx, nil, "beyond-requested" end
    local unit = ensureUnit(tx, index)
    if not unit then return false, tx, nil, "beyond-requested" end
    if #unit.evidence < self.maxEvidencePerUnit then
        unit.evidence[#unit.evidence + 1] = {
            key = key,
            type = evidenceType or "evidence",
            at = epochNow(),
            data = copyScalarTable(data),
        }
    end
    tx.evidenceIndex[key] = index

    local newlyConfirmed = false
    if confirm and unit.state ~= "confirmed" then
        unit.state = "confirmed"
        unit.confirmedAt = epochNow()
        unit.confirmedBy = evidenceType or "evidence"
        newlyConfirmed = true
    end
    tx.updatedAt = epochNow()
    recomputeConfirmed(tx)
    local store = getStore()
    if store then store.updatedAt = epochNow() end
    emit(tx)
    return newlyConfirmed, tx, unit, newlyConfirmed and "confirmed" or "recorded"
end

function TransactionLedger:RecordCraftResult(id, data, source)
    local tx = self:GetTransaction(id)
    if not tx or tx.kind ~= "craft" then return false, tx end
    local index = math.min(tx.requestedCount, math.max(1, tx.confirmedCount + 1))
    local operation = data and data.operationID
    local guid = data and data.itemGUID
    local fingerprint = table.concat({
        "result",
        tostring(index),
        tostring(operation or "none"),
        tostring(guid or "none"),
        tostring(data and data.itemID or "none"),
        tostring(data and data.quantity or "none"),
    }, ":")
    return self:_AddEvidence(id, index, fingerprint, source or "crafted-result", data, false)
end

function TransactionLedger:ConfirmCraft(id, castGUID, spellID, source)
    local tx = self:GetTransaction(id)
    if not tx or tx.kind ~= "craft" then return false, tx end
    -- A valid GUID is not sufficient when the submitted spell identifies a
    -- different recipe. Keep this check at the ledger boundary as well as in
    -- Crafting/TransactionRecovery; no build-specific API is required.
    if tonumber(spellID)==nil or tonumber(tx.recipeID)==nil or
        tonumber(spellID)~=tonumber(tx.recipeID) then
        return false, tx, nil, "recipe-mismatch"
    end
    if tx.confirmedCount >= tx.requestedCount then return false, tx, nil, "complete" end
    local index = tx.confirmedCount + 1
    local key
    local store = getStore()
    if castGUID and castGUID ~= "" then
        local owner = store and store.castEvidenceIndex and store.castEvidenceIndex[tostring(castGUID)] or nil
        if owner and owner ~= id then return false, tx, nil, "cross-transaction-duplicate" end
        key = evidenceKey("cast", castGUID)
    else
        -- A multi-craft success without a cast identity is deliberately not used
        -- as confirmation. A duplicate crafted-result can arrive after the prior
        -- unit was confirmed, making an anonymous event impossible to correlate
        -- safely to the next ordinal. Recovery may still raise the high-water mark
        -- later from independent reagent/skill evidence.
        if tx.requestedCount > 1 then return false, tx, nil, "anonymous-batch-unresolved" end
        key = string.format("cast-anonymous:%s:%d", tostring(tx.recipeID or spellID or "unknown"), index)
    end
    local newlyConfirmed, updated, unit, reason = self:_AddEvidence(id, index, key, source or "spellcast-success", { castGUID=castGUID, spellID=spellID }, true)
    if castGUID and castGUID ~= "" and store and reason ~= "invalid" and reason ~= "beyond-requested" then
        store.castEvidenceIndex[tostring(castGUID)] = id
    end
    return newlyConfirmed, updated, unit, reason
end

function TransactionLedger:ConfirmEnchant(id, evidenceID, source, data)
    local tx = self:GetTransaction(id)
    if not tx or tx.kind ~= "enchant" then return false, tx end
    local sourceText = tostring(source or "enchant-success")
    -- A client result with operationID=0 is an unidentified event, not a
    -- unique operation receipt. Enforce this centrally as a fail-closed gate.
    if sourceText:find("crafted-result", 1, true) and
        (type(data)~="table" or data.operationID==nil or
         tostring(data.operationID)=="" or tostring(data.operationID)=="0" or
         tostring(data.operationID)~=tostring(evidenceID)) then
        return false, tx, nil, "crafted-result-operation-unverified"
    end
    local store = getStore()
    local isSpellcastEvidence = sourceText:find("spellcast", 1, true) ~= nil
    local isOperationEvidence = sourceText:find("crafted-result", 1, true) ~= nil
        and type(data)=="table" and data.operationID~=nil
        and tostring(data.operationID)==tostring(evidenceID) and tostring(evidenceID)~=""
    local replayIndexKey = isSpellcastEvidence and tostring(evidenceID)
        or (isOperationEvidence and ("enchant-operation:"..tostring(evidenceID)) or nil)
    if replayIndexKey then
        local owner = store and store.castEvidenceIndex and store.castEvidenceIndex[replayIndexKey] or nil
        if owner and owner ~= id then return false, tx, nil, "cross-transaction-duplicate" end
    end
    local key = evidenceKey(source or "enchant", evidenceID)
    if not key then key = "enchant-confirmed:1" end
    local newlyConfirmed, updated, unit, reason = self:_AddEvidence(id, 1, key, source or "enchant-success", data, true)
    if replayIndexKey and store and (reason=="confirmed" or reason=="recorded" or reason=="duplicate") then
        store.castEvidenceIndex[replayIndexKey] = id
    end
    return newlyConfirmed, updated, unit, reason
end

function TransactionLedger:ConfirmThrough(id, count, prefix, evidenceType, data)
    local tx = self:GetTransaction(id)
    if not tx then return 0, nil end
    count = math.min(tx.requestedCount, math.max(0, math.floor(tonumber(count) or 0)))
    local before = tx.confirmedCount
    for index = 1, count do
        local key = tostring(prefix or "confirmed-through") .. ":" .. tostring(index)
        self:_AddEvidence(id, index, key, evidenceType or "reconciled-evidence", data, true)
    end
    tx = self:GetTransaction(id)
    return math.max(0, (tx and tx.confirmedCount or 0) - before), tx
end

function TransactionLedger:Close(id, status, metadata)
    local tx = self:GetTransaction(id)
    if not tx then return false end
    local nextStatus = status or tx.status or "closed"
    if tx.closedAt ~= nil or isTerminalStatus(tx.status) then
        -- Alpha77 terminal monotonicity: once an irreversible transaction has
        -- settled, duplicate/out-of-order evidence cannot rewrite its outcome.
        return false, tx, "terminal-already-closed"
    end
    tx.status = nextStatus
    tx.closedAt = isTerminalStatus(nextStatus) and (tx.closedAt or epochNow()) or tx.closedAt
    tx.updatedAt = epochNow()
    if type(metadata) == "table" then
        tx.closeSource = metadata.source or tx.closeSource
        tx.recovered = metadata.recovered == true or tx.recovered
        tx.recoveryConfidence = metadata.recoveryConfidence or tx.recoveryConfidence
        tx.detail = metadata.detail or tx.detail
    end
    local store = getStore()
    if store then store.updatedAt = epochNow(); trimStore(store) end
    emit(tx)
    return true, tx
end

function TransactionLedger:GetTransactions()
    local store = getStore()
    local out = {}
    if not store then return out end
    for _, id in ipairs(store.order or {}) do
        local tx = store.transactions and store.transactions[id] or nil
        if tx then
            ensureTransactionShape(tx)
            out[#out + 1] = tx
        end
    end
    return out
end

function TransactionLedger:GetStatus(id)
    local tx = id and self:GetTransaction(id) or nil
    if not tx then
        local store = getStore()
        local lastID = store and store.order[#store.order] or nil
        tx = lastID and store.transactions[lastID] or nil
    end
    if not tx then return nil end
    ensureTransactionShape(tx)
    return {
        contract = self.contract,
        id = tx.id,
        kind = tx.kind,
        key = tx.key,
        recipeID = tx.recipeID,
        recipeName = tx.recipeName,
        mode = tx.mode,
        requestedCount = tx.requestedCount,
        confirmedCount = tx.confirmedCount,
        status = tx.status,
        closedAt = tx.closedAt,
        targetGUID = tx.targetGUID,
        difficultyStart = tx.difficultyStart,
        authorityProvenance = tx.authorityProvenance,
        recovered = tx.recovered == true,
        reconciledSkillGain = tonumber(tx.reconciliation and tx.reconciliation.skillGain) or 0,
        noSkillCount = tonumber(tx.reconciliation and tx.reconciliation.noSkillCount) or 0,
        units = tx.units,
    }
end

function TransactionLedger:GetSummary()
    local store = getStore()
    if not store or #store.order == 0 then return "Transaction ledger: no direct craft/enchant transactions recorded." end
    local lines = { "Transaction ledger: idempotent per-unit confirmation + reconciliation history" }
    local first = math.max(1, #store.order - 4)
    for i = first, #store.order do
        local id = store.order[i]
        local tx = store.transactions[id]
        if tx then
            local provenance = type(tx.buildProvenance) == "table" and tx.buildProvenance or nil
            local buildLabel = provenance and string.format(
                "Forever %s / interface %s",
                tostring(provenance.build or "unknown"),
                tostring(provenance.interface or "unknown")
            ) or "build provenance unknown"
            lines[#lines + 1] = string.format(
                "%s · %s · %s · %d/%d confirmed · %s · +%d skill / %d no-skill · %s",
                tostring(id),
                tx.kind == "enchant" and "Enchant" or (tx.mode == "all" and "Craft All" or "Craft One"),
                tostring(tx.recipeName or tx.recipeID or "unknown recipe"),
                tonumber(tx.confirmedCount) or 0,
                tonumber(tx.requestedCount) or 1,
                tostring(tx.status or "pending"),
                tonumber(tx.reconciliation and tx.reconciliation.skillGain) or 0,
                tonumber(tx.reconciliation and tx.reconciliation.noSkillCount) or 0,
                buildLabel
            )
            for unitIndex = 1, math.min(tonumber(tx.confirmedCount) or 0, 5) do
                local unit = tx.units and tx.units[unitIndex] or nil
                local skill = unit and unit.reconciliation and unit.reconciliation.skill or nil
                local difficulty = unit and unit.reconciliation and unit.reconciliation.difficulty or nil
                local materialCount = 0
                for _ in pairs(unit and unit.reconciliation and unit.reconciliation.materials or {}) do materialCount = materialCount + 1 end
                lines[#lines + 1] = string.format(
                    "  #%d · %s · skill %s · difficulty %s · %d material%s reconciled",
                    unitIndex,
                    tostring(unit and unit.state or "unknown"),
                    skill and ((tonumber(skill.gain) or 0) > 0 and ("+" .. tostring(skill.gain) .. " (" .. tostring(skill.confidence or skill.source or "evidence") .. ")") or ("no-up (" .. tostring(skill.confidence or skill.source or "evidence") .. ")")) or "unresolved",
                    difficulty and tostring(difficulty.label or difficulty.token or "unknown") or "unresolved",
                    materialCount, materialCount == 1 and "" or "s"
                )
            end
        end
    end
    lines[#lines + 1] = "Policy: duplicate evidence keys merge into the existing craft unit; difficulty/skill/material reconciliation updates that same ordinal idempotently, recovered high-water marks never create a second confirmed unit, and missing legacy build provenance is never restamped as current-build evidence."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("TransactionLedger", TransactionLedger)
