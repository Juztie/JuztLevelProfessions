local _, JLP = ...

-- Alpha115 replaces caller-supplied Craft All progress with a proof-driven,
-- runtime-only Enchanting sequence session. Enchanting is not treated like
-- CraftRecipe batching: every ordinal represents one separate target-bound
-- enchant, and the next ordinal remains locked until TransactionLedger proves
-- terminal success for the exact previous recipe/target/proof. This module is
-- planning/session state only and never calls CraftEnchant.
local ProductionEnchantingCraftAllSession = {
    contract = "production-enchanting-proof-driven-craft-all-session-v1",
    settlementProofContract = "production-enchanting-craft-all-ledger-settlement-proof-v2",
    ordinalOriginContract = "production-enchanting-sequence-ordinal-origin-v1",
    batchContract = "production-enchanting-explicit-target-batch-v1",
    authorityContract = "production-enchanting-current-recipe-craft-all-planning-authority-v1",
    professionKey = "ENCHANTING",
    readOnly = true,
    executionEligible = false,
    nativeDispatchAllowed = false,
    automaticQueueAllowed = false,
    requiresExplicitUserActionPerOrdinal = true,
    nativeNumCastsPerAction = 1,
    persisted = false,
    maxSessions = 16,
    sessionTTLSeconds = 1800,
    serial = 0,
    sessions = {},
    order = {},
    ledgerOwners = {},
    last = nil,
    initialized = false,
}

local function now()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function stateHash(parts)
    local value = table.concat(parts or {}, "\31")
    local hash = 5381
    for index = 1, #value do hash = (hash * 33 + string.byte(value, index)) % 2147483647 end
    return string.format("%08x", hash)
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, row in pairs(value) do out[copy(key, seen)] = copy(row, seen) end
    return out
end

local function terminalSuccess(tx)
    return type(tx) == "table" and tostring(tx.status or "") == "success" and (tonumber(tx.confirmedCount) or 0) >= 1
end

function ProductionEnchantingCraftAllSession:_Drop(token, reason)
    token = tostring(token or "")
    local session = self.sessions[token]
    if not session then return false end
    self.sessions[token] = nil
    for ledgerID, owner in pairs(self.ledgerOwners or {}) do
        if tostring(owner or "") == token then self.ledgerOwners[ledgerID] = nil end
    end
    session.revoked = true
    session.revokedReason = tostring(reason or "revoked")
    session.revokedAt = now()
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_CRAFT_ALL_SESSION_UPDATED", copy(session))
    end
    return true
end

function ProductionEnchantingCraftAllSession:_Sweep()
    local current = now()
    local kept = {}
    for _, token in ipairs(self.order or {}) do
        local session = self.sessions[token]
        if session then
            local expired = tonumber(session.expiresAt) and current > tonumber(session.expiresAt)
            if expired then
                self:_Drop(token, "session-ttl-expired")
            else
                kept[#kept + 1] = token
            end
        end
    end
    self.order = kept
    while #self.order > self.maxSessions do
        local token = table.remove(self.order, 1)
        self:_Drop(token, "session-store-cap")
    end
end

function ProductionEnchantingCraftAllSession:RevokeAll(reason)
    local tokens = {}
    for token in pairs(self.sessions or {}) do tokens[#tokens + 1] = token end
    local count = 0
    for _, token in ipairs(tokens) do
        if self:_Drop(token, reason or "revoked-all") then count = count + 1 end
    end
    self.order = {}
    self.ledgerOwners = {}
    self.last = {state="production-enchanting-craft-all-sessions-revoked",reason=tostring(reason or "revoked-all"),count=count,at=now()}
    return count
end

function ProductionEnchantingCraftAllSession:Create(batch)
    self:_Sweep()
    local authority = JLP:GetModule("ProductionEnchantingCraftAllAuthority")
    if type(batch) ~= "table" or batch.contract ~= self.batchContract then
        return nil, "production-enchanting-craft-all-session-batch-invalid"
    end
    if not authority or not authority.ValidateTargetBatch then
        return nil, "production-enchanting-craft-all-session-authority-unavailable"
    end
    local current, state = authority:ValidateTargetBatch(batch)
    if current ~= true then return nil, state or "production-enchanting-craft-all-session-batch-stale" end
    local generation = authority.GetAuthorityGeneration and authority:GetAuthorityGeneration() or nil
    if not generation or tonumber(batch.authorityGeneration) ~= tonumber(generation) then
        return nil, "production-enchanting-craft-all-session-generation-stale"
    end

    self.serial = (tonumber(self.serial) or 0) + 1
    local createdAt = now()
    local fingerprint = stateHash({
        self.contract,
        tostring(self.serial),
        tostring(batch.token or ""),
        tostring(batch.fingerprint or ""),
        tostring(generation),
        tostring(batch.recipeID or ""),
        tostring(batch.requestedCount or ""),
        tostring(createdAt),
    })
    local token = "enchant-craft-all-session-" .. fingerprint
    local session = {
        contract=self.contract,
        settlementProofContract=self.settlementProofContract,
        token=token,
        fingerprint=fingerprint,
        batchToken=batch.token,
        batchFingerprint=batch.fingerprint,
        authorityGeneration=generation,
        professionKey=self.professionKey,
        mode=batch.mode,
        recipe=batch.recipe,
        recipeID=tonumber(batch.recipeID),
        routeIndex=tonumber(batch.routeIndex),
        skillTarget=tonumber(batch.skillTarget),
        requestedCount=math.max(0, math.floor(tonumber(batch.requestedCount) or 0)),
        nextOrdinal=1,
        settledCount=0,
        settledOrdinals={},
        expectedOrdinalPlan=nil,
        terminal=false,
        state="production-enchanting-craft-all-session-ready",
        readOnly=true,
        executionEligible=false,
        nativeDispatchAllowed=false,
        automaticQueueAllowed=false,
        requiresExplicitUserActionPerOrdinal=true,
        nativeNumCastsPerAction=1,
        persisted=false,
        createdAt=createdAt,
        expiresAt=createdAt + self.sessionTTLSeconds,
    }
    self.sessions[token] = session
    self.order[#self.order + 1] = token
    self.last = copy(session)
    self:_Sweep()
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_CRAFT_ALL_SESSION_UPDATED", copy(session))
    end
    return copy(session), "production-enchanting-craft-all-session-created"
end

function ProductionEnchantingCraftAllSession:Get(sessionOrToken)
    self:_Sweep()
    local token = type(sessionOrToken) == "table" and sessionOrToken.token or sessionOrToken
    local session = self.sessions[tostring(token or "")]
    return session and copy(session) or nil
end

function ProductionEnchantingCraftAllSession:GetVerifiedProgress(batchToken, sessionOrToken)
    self:_Sweep()
    local token = type(sessionOrToken) == "table" and sessionOrToken.token or sessionOrToken
    local stored = self.sessions[tostring(token or "")]
    if not stored then return nil, "production-enchanting-craft-all-session-expired-or-unknown" end
    if tostring(batchToken or "") ~= tostring(stored.batchToken or "") then
        return nil, "production-enchanting-craft-all-session-batch-mismatch"
    end
    local authority = JLP:GetModule("ProductionEnchantingCraftAllAuthority")
    local generation = authority and authority.GetAuthorityGeneration and authority:GetAuthorityGeneration() or nil
    if tonumber(stored.authorityGeneration) ~= tonumber(generation) then
        self:_Drop(stored.token, "authority-generation-revoked")
        return nil, "production-enchanting-craft-all-session-generation-revoked"
    end
    return {
        contract=self.contract,
        sessionToken=stored.token,
        sessionFingerprint=stored.fingerprint,
        batchToken=stored.batchToken,
        authorityGeneration=stored.authorityGeneration,
        settledCount=stored.settledCount,
        nextOrdinal=stored.nextOrdinal,
        requestedCount=stored.requestedCount,
        terminal=stored.terminal == true,
        state=stored.state,
    }, "production-enchanting-craft-all-session-progress-current"
end

function ProductionEnchantingCraftAllSession:RegisterOrdinalPlan(sessionOrToken, batch, plan)
    self:_Sweep()
    local token = type(sessionOrToken) == "table" and sessionOrToken.token or sessionOrToken
    local stored = self.sessions[tostring(token or "")]
    if not stored then return false, "production-enchanting-craft-all-session-expired-or-unknown" end
    if stored.terminal == true then return false, "production-enchanting-craft-all-session-already-terminal" end
    if type(batch) ~= "table" or tostring(batch.token or "") ~= tostring(stored.batchToken or "")
        or tostring(batch.fingerprint or "") ~= tostring(stored.batchFingerprint or "") then
        return false, "production-enchanting-craft-all-session-batch-mismatch"
    end
    if type(plan) ~= "table"
        or tostring(plan.sessionToken or "") ~= tostring(stored.token or "")
        or tostring(plan.sessionFingerprint or "") ~= tostring(stored.fingerprint or "")
        or tostring(plan.batchToken or "") ~= tostring(stored.batchToken or "")
        or tostring(plan.batchFingerprint or "") ~= tostring(stored.batchFingerprint or "")
        or tonumber(plan.authorityGeneration) ~= tonumber(stored.authorityGeneration)
        or tonumber(plan.ordinal) ~= tonumber(stored.nextOrdinal)
        or tonumber(plan.recipeID) ~= tonumber(stored.recipeID) then
        return false, "production-enchanting-craft-all-session-ordinal-plan-mismatch"
    end
    local target = batch.targets and batch.targets[tonumber(stored.nextOrdinal) or 1] or nil
    if not target
        or tostring(plan.targetGUID or "") ~= tostring(target.targetGUID or "")
        or tonumber(plan.targetItemID) ~= tonumber(target.targetItemID)
        or tostring(plan.targetProofFingerprint or "") ~= tostring(target.fingerprint or "") then
        return false, "production-enchanting-craft-all-session-ordinal-target-mismatch"
    end
    stored.expectedOrdinalPlan = {
        contract=self.ordinalOriginContract,
        ordinal=tonumber(plan.ordinal),
        planToken=tostring(plan.token or ""),
        batchToken=stored.batchToken,
        batchFingerprint=stored.batchFingerprint,
        sessionToken=stored.token,
        sessionFingerprint=stored.fingerprint,
        authorityGeneration=stored.authorityGeneration,
        recipeID=stored.recipeID,
        routeIndex=stored.routeIndex,
        skillTarget=stored.skillTarget,
        targetGUID=target.targetGUID,
        targetItemID=target.targetItemID,
        targetProofFingerprint=target.fingerprint,
    }
    stored.updatedAt=now()
    return true, "production-enchanting-sequence-ordinal-origin-registered", copy(stored.expectedOrdinalPlan)
end

function ProductionEnchantingCraftAllSession:GetOrdinalOrigin(sessionOrToken)
    local token = type(sessionOrToken) == "table" and sessionOrToken.token or sessionOrToken
    local stored = self.sessions[tostring(token or "")]
    return stored and stored.expectedOrdinalPlan and copy(stored.expectedOrdinalPlan) or nil
end

function ProductionEnchantingCraftAllSession:RecordSettlement(sessionOrToken, ledgerID, batch)
    self:_Sweep()
    local token = type(sessionOrToken) == "table" and sessionOrToken.token or sessionOrToken
    local stored = self.sessions[tostring(token or "")]
    if not stored then return false, "production-enchanting-craft-all-session-expired-or-unknown" end
    if stored.terminal == true then return false, "production-enchanting-craft-all-session-already-terminal" end
    if type(batch) ~= "table" or tostring(batch.token or "") ~= tostring(stored.batchToken or "")
        or tostring(batch.fingerprint or "") ~= tostring(stored.batchFingerprint or "") then
        return false, "production-enchanting-craft-all-session-batch-mismatch"
    end

    local authority = JLP:GetModule("ProductionEnchantingCraftAllAuthority")
    local generation = authority and authority.GetAuthorityGeneration and authority:GetAuthorityGeneration() or nil
    if tonumber(stored.authorityGeneration) ~= tonumber(generation) or tonumber(batch.authorityGeneration) ~= tonumber(generation) then
        self:_Drop(stored.token, "authority-generation-revoked")
        return false, "production-enchanting-craft-all-session-generation-revoked"
    end

    ledgerID = tostring(ledgerID or "")
    if ledgerID == "" then return false, "production-enchanting-craft-all-settlement-ledger-required" end
    local owner = self.ledgerOwners[ledgerID]
    if owner and tostring(owner) ~= tostring(stored.token) then
        return false, "production-enchanting-craft-all-settlement-ledger-replayed"
    end

    local ordinal = tonumber(stored.nextOrdinal) or 1
    local target = batch.targets and batch.targets[ordinal] or nil
    if not target then return false, "production-enchanting-craft-all-settlement-target-missing" end

    local ledger = JLP:GetModule("TransactionLedger")
    local tx = ledger and ledger.GetTransaction and ledger:GetTransaction(ledgerID) or nil
    if not terminalSuccess(tx) then
        return false, "production-enchanting-craft-all-settlement-not-terminal-success"
    end
    local provenance = tx.authorityProvenance or {}
    local expected = stored.expectedOrdinalPlan
    if type(expected) ~= "table" then
        return false, "production-enchanting-craft-all-settlement-origin-not-minted"
    end
    local exact = tostring(tx.kind or "") == "enchant"
        and tostring(tx.key or "") == self.professionKey
        and tostring(tx.mode or "") == "one"
        and tonumber(tx.requestedCount) == 1
        and tonumber(tx.recipeID) == tonumber(stored.recipeID)
        and tostring(tx.targetGUID or "") == tostring(target.targetGUID or "")
        and tostring(provenance.sequenceContract or "") == tostring(self.ordinalOriginContract)
        and tostring(provenance.batchToken or "") == tostring(expected.batchToken or "")
        and tostring(provenance.batchFingerprint or "") == tostring(expected.batchFingerprint or "")
        and tostring(provenance.sessionToken or "") == tostring(expected.sessionToken or "")
        and tostring(provenance.sessionFingerprint or "") == tostring(expected.sessionFingerprint or "")
        and tonumber(provenance.ordinal) == tonumber(expected.ordinal)
        and tonumber(provenance.authorityGeneration) == tonumber(expected.authorityGeneration)
        and tostring(provenance.ordinalPlanToken or "") == tostring(expected.planToken or "")
        and tonumber(provenance.recipeID) == tonumber(stored.recipeID)
        and tonumber(provenance.routeIndex) == tonumber(stored.routeIndex)
        and tonumber(provenance.skillTarget) == tonumber(stored.skillTarget)
        and tostring(provenance.targetGUID or "") == tostring(target.targetGUID or "")
        and tonumber(provenance.targetItemID) == tonumber(target.targetItemID)
        and tostring(provenance.targetProofFingerprint or "") == tostring(target.fingerprint or "")
    if not exact then
        return false, "production-enchanting-craft-all-settlement-origin-proof-mismatch"
    end

    if stored.settledOrdinals[ordinal] ~= nil then
        return false, "production-enchanting-craft-all-settlement-duplicate-ordinal"
    end
    -- No out-of-order input exists: the session derives the only eligible ordinal
    -- from its own verified state, and the ledger must match that exact target.
    local proof = {
        contract=self.settlementProofContract,
        ordinal=ordinal,
        ledgerID=ledgerID,
        recipeID=stored.recipeID,
        targetGUID=target.targetGUID,
        targetItemID=target.targetItemID,
        targetProofFingerprint=target.fingerprint,
        terminalStatus="success",
        confirmedCount=tonumber(tx.confirmedCount) or 0,
        authorityGeneration=stored.authorityGeneration,
        batchToken=stored.batchToken,
        batchFingerprint=stored.batchFingerprint,
        sessionToken=stored.token,
        sessionFingerprint=stored.fingerprint,
        ordinalPlanToken=expected.planToken,
        recordedAt=now(),
    }
    proof.fingerprint = stateHash({
        proof.contract,
        tostring(stored.token),
        tostring(proof.ordinal),
        tostring(proof.ledgerID),
        tostring(proof.recipeID),
        tostring(proof.targetGUID),
        tostring(proof.targetProofFingerprint),
        tostring(proof.authorityGeneration),
    })
    stored.settledOrdinals[ordinal] = proof
    stored.expectedOrdinalPlan = nil
    stored.settledCount = ordinal
    stored.nextOrdinal = ordinal + 1
    stored.updatedAt = now()
    stored.expiresAt = stored.updatedAt + self.sessionTTLSeconds
    self.ledgerOwners[ledgerID] = stored.token
    if stored.settledCount >= stored.requestedCount then
        stored.terminal = true
        stored.state = "production-enchanting-craft-all-session-complete"
    else
        stored.state = "production-enchanting-craft-all-session-awaiting-explicit-next-action"
    end
    self.last = copy(stored)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_CRAFT_ALL_SESSION_UPDATED", copy(stored))
    end
    return true, "production-enchanting-craft-all-settlement-proof-accepted", copy(proof), copy(stored)
end

function ProductionEnchantingCraftAllSession:GetSummary()
    self:_Sweep()
    local last = self.last
    local active = 0
    for _ in pairs(self.sessions or {}) do active = active + 1 end
    local lines = {
        "PRODUCTION ENCHANTING / PROOF-DRIVEN TARGET SEQUENCE SESSION",
        "Contract: " .. self.contract,
        "Settlement proof: " .. self.settlementProofContract,
        "Native queue semantics: disabled",
        "Native casts per explicit action: 1",
        "Explicit user action required for every ordinal: yes",
        "Progress source: terminal TransactionLedger success with exact batch/session/ordinal provenance only",
        "Caller-supplied completedCount: forbidden",
        "Automatic next-target dispatch: forbidden",
        "Persistence / reload resume: none",
        "Active sessions: " .. tostring(active) .. " / " .. tostring(self.maxSessions),
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = string.format("Last verified progress: %d / %d", tonumber(last.settledCount) or 0, tonumber(last.requestedCount) or 0)
        lines[#lines + 1] = "Last next ordinal: " .. tostring(last.nextOrdinal or "none")
    end
    return table.concat(lines, "\n")
end

function ProductionEnchantingCraftAllSession:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("PRODUCTION_ENCHANTING_CRAFT_ALL_AUTHORITY_REVOKED", function(payload)
            self:RevokeAll(type(payload) == "table" and payload.reason or "authority-revoked")
        end)
    end
    return true
end

function ProductionEnchantingCraftAllSession:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.nativeDispatchAllowed ~= false
        or self.automaticQueueAllowed ~= false or self.requiresExplicitUserActionPerOrdinal ~= true
        or self.nativeNumCastsPerAction ~= 1 or self.persisted ~= false then
        errors[#errors + 1] = "production Enchanting Craft All session safety boundary invalid"
    end
    if tostring(self.settlementProofContract) ~= "production-enchanting-craft-all-ledger-settlement-proof-v2"
        or tostring(self.ordinalOriginContract) ~= "production-enchanting-sequence-ordinal-origin-v1" then
        errors[#errors + 1] = "production Enchanting sequence origin contracts invalid"
    end
    for _, name in ipairs({"ProductionEnchantingCraftAllAuthority","TransactionLedger"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "production Enchanting Craft All session dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingCraftAllSession", ProductionEnchantingCraftAllSession)
