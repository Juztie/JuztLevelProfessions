local _, JLP = ...

-- Alpha115 hardens the production Enchanting target-sequence planning authority.
-- Enchanting is explicitly not modeled as Tailoring-style native Craft All: each
-- ordinal is one separate target-bound enchant and requires a new explicit user
-- action after verified settlement of the previous ordinal. This module remains
-- read-only, captures immutable ordered target intent, and never calls CraftEnchant.
local ProductionEnchantingCraftAllAuthority = {
    contract = "production-enchanting-current-recipe-craft-all-planning-authority-v1",
    readinessContract = "production-enchanting-current-recipe-craft-all-readiness-v1",
    batchContract = "production-enchanting-explicit-target-batch-v1",
    targetProofContract = "production-enchanting-craft-all-target-proof-v1",
    authority = "feature-gated-read-only-explicit-target-batch-current-recipe-craft-all-v1",
    professionKey = "ENCHANTING",
    targetPolicy = "ordered-explicit-distinct-guid-batch",
    selectionSource = "profession-guide-explicit-target-batch",
    maxTargetBatchSize = 250,
    readOnly = true,
    executionEligible = false,
    executionAuthorityEnabled = false,
    nativeDispatchAllowed = false,
    craftAllNativeExecutionAllowed = false,
    automaticTargetSelectionAllowed = false,
    automaticTargetSkippingAllowed = false,
    automaticRouteAdvance = false,
    confirmationAutomationAllowed = false,
    persistedAuthorization = false,
    automaticQueueAllowed = false,
    requiresExplicitUserActionPerOrdinal = true,
    nativeNumCastsPerAction = 1,
    authorityGeneration = 1,
    dependencySignature = nil,
    revocationSerial = 0,
    batchSerial = 0,
    lastByProfession = {},
    initialized = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

-- A pending Enchant target sequence is session-bound, not fixed-build-
-- authorized. Source build numbers are never substituted for live identity.
local function currentClientReceipt()
    local module=JLP:GetModule("ClientBuildInfo")
    if not module or type(module.Read)~="function" then return nil end
    local ok,info=pcall(module.Read,module)
    if not ok or type(info)~="table" or info.known~=true then return nil end
    local build,interface=info.buildNumber,info.interfaceVersion
    if type(build)~="number" or build<=0 or build~=math.floor(build) or
       build>9007199254740991 or type(interface)~="number" or
       interface<=0 or interface~=math.floor(interface) or interface>9007199254740991 then
        return nil
    end
    local token=string.format("forever:%s|interface:%s",tostring(build),tostring(interface))
    if info.token~=token then return nil end
    return {build=build,interface=interface,token=token}
end

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

local function profile()
    local root = JLP.DB and JLP.DB.profile
    return root and root.productionEnchantingCraftAllAuthority or nil
end

local function featureEnabled()
    local row = profile()
    return row and row.enabled == true or false
end

local function guidInInventory(guid)
    if not guid or type(C_Item) ~= "table" or type(C_Item.IsItemGUIDInInventory) ~= "function" then return nil end
    local ok, value = pcall(C_Item.IsItemGUIDInInventory, guid)
    if not ok then return nil end
    return value and true or false
end

local function getLocation(guid)
    if not guid or type(C_Item) ~= "table" or type(C_Item.GetItemLocation) ~= "function" then return nil end
    local ok, value = pcall(C_Item.GetItemLocation, guid)
    return ok and value or nil
end

local function locationKey(location)
    if not location then return nil end
    if type(location) == "table" then
        local bag = location.bagID or location.bag or location.bagIndex
        local slot = location.slotIndex or location.slot or location.inventorySlot
        local equipment = location.equipmentSlot or location.equipSlot
        local itemID = location.itemID
        if bag ~= nil or slot ~= nil or equipment ~= nil or itemID ~= nil then
            return table.concat({"table", tostring(bag or ""), tostring(slot or ""), tostring(equipment or ""), tostring(itemID or "")}, ":")
        end
    end
    local kind = type(location)
    if kind == "table" or kind == "userdata" then
        if type(location.IsBagAndSlot) == "function" and type(location.GetBagAndSlot) == "function" then
            local okBag, isBag = pcall(location.IsBagAndSlot, location)
            if okBag and isBag then
                local ok, bag, slot = pcall(location.GetBagAndSlot, location)
                if ok then return table.concat({"bag", tostring(bag or ""), tostring(slot or "")}, ":") end
            end
        end
        if type(location.IsEquipmentSlot) == "function" and type(location.GetEquipmentSlot) == "function" then
            local okEquip, isEquip = pcall(location.IsEquipmentSlot, location)
            if okEquip and isEquip then
                local ok, slot = pcall(location.GetEquipmentSlot, location)
                if ok then return "equipment:" .. tostring(slot or "") end
            end
        end
    end
    return tostring(location)
end

local function itemIDFor(guid, location)
    if location and type(C_Item) == "table" and type(C_Item.GetItemID) == "function" then
        local ok, value = pcall(C_Item.GetItemID, location)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if guid and type(C_Item) == "table" and type(C_Item.GetItemIDByGUID) == "function" then
        local ok, value = pcall(C_Item.GetItemIDByGUID, guid)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return nil
end

local function targetValidated(recipeID, guid)
    if recipeID and guid and type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.GetEnchantItems) == "function" then
        local ok, values = pcall(C_TradeSkillUI.GetEnchantItems, recipeID)
        if ok and type(values) == "table" then
            for _, value in pairs(values) do
                if value == guid then return true, "GetEnchantItems" end
            end
        end
    end
    if recipeID and guid and type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.IsEnchantTargetValid) == "function" then
        local ok, value = pcall(C_TradeSkillUI.IsEnchantTargetValid, recipeID, guid)
        if ok and value then return true, "IsEnchantTargetValid" end
    end
    return false, nil
end

local function addGate(model, key, ready, state, detail)
    local row = {
        key = key,
        ready = ready and true or false,
        state = tostring(state or (ready and "pass" or "blocked")),
        detail = detail,
    }
    model.gates[key] = row
    model.stats.totalGates = model.stats.totalGates + 1
    if row.ready then
        model.stats.passedGates = model.stats.passedGates + 1
    elseif not model.blockedGate then
        model.blockedGate = key
        model.blockedState = row.state
    end
    return row
end

local function exactCurrentIdentity()
    local identity = JLP:GetModule("ProductionEnchantingRecipeIdentity")
    return identity and identity.AssessCurrent and identity:AssessCurrent() or nil
end

local function currentConsumer(mode, options)
    local bridge = JLP:GetModule("ResearchPlannerConsumerBridge")
    return bridge and bridge.Build and bridge:Build("ENCHANTING", normalizeMode(mode), options or {}) or nil
end

function ProductionEnchantingCraftAllAuthority:_DependencyState()
    local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local adapterEnabled = adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled() or false
    local eligibilityEnabled = eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled() or false
    local supported = self:IsSupported(self.professionKey)
    return table.concat({adapterEnabled and "1" or "0", eligibilityEnabled and "1" or "0", supported and "1" or "0"}, ":")
end

function ProductionEnchantingCraftAllAuthority:GetAuthorityGeneration()
    return math.max(1, math.floor(tonumber(self.authorityGeneration) or 1))
end

function ProductionEnchantingCraftAllAuthority:_RevokeGeneration(reason)
    self.authorityGeneration = self:GetAuthorityGeneration() + 1
    self.revocationSerial = (tonumber(self.revocationSerial) or 0) + 1
    self.lastByProfession = {}
    local session = JLP:GetModule("ProductionEnchantingCraftAllSession")
    if session and session.RevokeAll then session:RevokeAll(reason or "authority-generation-revoked") end
    local orchestrator = JLP:GetModule("ProductionEnchantingCraftAllOrchestrator")
    if orchestrator and orchestrator.RevokeAll then orchestrator:RevokeAll(reason or "authority-generation-revoked") end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_CRAFT_ALL_AUTHORITY_REVOKED", {
            professionKey=self.professionKey,
            generation=self.authorityGeneration,
            reason=tostring(reason or "authority-generation-revoked"),
            nativeDispatchAllowed=false,
        })
    end
    return self.authorityGeneration
end

function ProductionEnchantingCraftAllAuthority:_RefreshDependencyGeneration(reason)
    local signature = self:_DependencyState()
    if self.dependencySignature == nil then
        self.dependencySignature = signature
        return self:GetAuthorityGeneration(), false
    end
    if tostring(self.dependencySignature) ~= tostring(signature) then
        self.dependencySignature = signature
        return self:_RevokeGeneration(reason or "planning-dependency-state-changed"), true
    end
    return self:GetAuthorityGeneration(), false
end

function ProductionEnchantingCraftAllAuthority:IsFeatureEnabled()
    return featureEnabled()
end

function ProductionEnchantingCraftAllAuthority:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    if professionKey ~= self.professionKey then return false end
    local native = JLP:GetModule("ProductionEnchantingNativeExecutionAuthority")
    local coverage = JLP:GetModule("ProductionEnchantingNativeRouteCoverage")
    local coverageModel = coverage and coverage.Audit and coverage:Audit() or nil
    return native and native.IsSupported and native:IsSupported(professionKey)
        and coverageModel and coverageModel.routeReady == true or false
end

function ProductionEnchantingCraftAllAuthority:IsEffectiveEnabled()
    if not featureEnabled() then return false end
    local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    return adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()
        and eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()
        and self:IsSupported(self.professionKey) or false
end

function ProductionEnchantingCraftAllAuthority:SetFeatureEnabled(enabled)
    local row = profile()
    if not row then return false, "profile-unavailable" end
    if enabled == true then
        local adapter = JLP:GetModule("ProductionEnchantingAuthorityAdapter")
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        if not (adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) then
            return false, "production-enchanting-authority-gate-disabled"
        end
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
        if not self:IsSupported(self.professionKey) then
            return false, "production-enchanting-all-route-coverage-not-ready"
        end
    end
    row.enabled = enabled == true
    self.dependencySignature = self:_DependencyState()
    self:_RevokeGeneration("feature-gate-changed")
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_CRAFT_ALL_AUTHORITY_UPDATED", {
            professionKey=self.professionKey,
            enabled=row.enabled,
            nativeDispatchAllowed=false,
            automaticTargetSelectionAllowed=false,
        })
        JLP.EventBus:Emit("SETTINGS_CHANGED", "productionEnchantingCraftAllAuthority", row.enabled)
    end
    return true, row.enabled and "enabled-readiness-only" or "disabled"
end

function ProductionEnchantingCraftAllAuthority:CaptureTargetProof(recipeID, guid)
    recipeID = tonumber(recipeID)
    guid = tostring(guid or "")
    if not recipeID or guid == "" then return nil, "enchanting-craft-all-target-identity-invalid" end

    local identity = exactCurrentIdentity()
    if not identity or identity.liveCurrentStepCorroborated ~= true or tonumber(identity.stagedRecipeID) ~= recipeID then
        return nil, "enchanting-craft-all-recipe-identity-not-current"
    end

    local present = guidInInventory(guid)
    if present ~= true then return nil, "enchanting-craft-all-target-not-in-inventory" end
    local valid, validationSource = targetValidated(recipeID, guid)
    if not valid then return nil, "enchanting-craft-all-target-not-native-valid" end
    local location = getLocation(guid)
    local liveLocationKey = locationKey(location)
    if not location or not liveLocationKey then return nil, "enchanting-craft-all-target-location-unavailable" end
    local itemID = itemIDFor(guid, location)
    if not itemID then return nil, "enchanting-craft-all-target-item-identity-unavailable" end

    local session=currentClientReceipt()
    if not session then return nil,"enchanting-craft-all-live-session-unverified" end
    local build=session.build
    local fingerprint = stateHash({
        self.targetProofContract,
        session.token,
        tostring(build or ""),
        tostring(recipeID),
        guid,
        tostring(itemID),
        tostring(validationSource or ""),
        tostring(liveLocationKey),
    })
    return {
        contract=self.targetProofContract,
        fingerprint=fingerprint,
        professionKey=self.professionKey,
        currentBuild=build,
        clientBuildToken=session.token,
        recipe=tostring(identity.recipe or ""),
        recipeID=recipeID,
        targetGUID=guid,
        targetItemID=itemID,
        targetValidationSource=validationSource,
        targetLocationKey=liveLocationKey,
        explicitUserSelectionRequired=true,
        automaticSelection=false,
        singleUseTarget=true,
        readOnly=true,
        executionEligible=false,
        nativeDispatchAllowed=false,
        persisted=false,
    }, "enchanting-craft-all-target-proof-current"
end

function ProductionEnchantingCraftAllAuthority:PrepareTargetBatch(professionKey, mode, targetGUIDs, options)
    professionKey = normalizeKey(professionKey) or self.professionKey
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    local generation = self:_RefreshDependencyGeneration("prepare-target-batch-dependency-change")
    local model = {
        contract=self.readinessContract,
        authorityContract=self.contract,
        batchContract=self.batchContract,
        targetProofContract=self.targetProofContract,
        professionKey=professionKey,
        mode=mode,
        state="production-enchanting-craft-all-readiness-blocked",
        craftAllReadinessReady=false,
        executionEligible=false,
        executionAuthorityEnabled=false,
        dispatchAllowed=false,
        nativeDispatchAllowed=false,
        craftAllNativeExecutionAllowed=false,
        automaticTargetSelectionAllowed=false,
        automaticTargetSkippingAllowed=false,
        automaticRouteAdvance=false,
        confirmationAutomationAllowed=false,
        automaticQueueAllowed=false,
        requiresExplicitUserActionPerOrdinal=true,
        nativeNumCastsPerAction=1,
        persisted=false,
        authorityGeneration=generation,
        gates={},
        stats={passedGates=0,totalGates=0},
    }

    addGate(model, "feature-gate", self:IsEffectiveEnabled(), self:IsEffectiveEnabled() and "production-enchanting-craft-all-readiness-gate-enabled" or "production-enchanting-craft-all-readiness-gate-disabled", "default-off planning gate; never grants native dispatch")
    addGate(model, "supported-profession", self:IsSupported(professionKey), self:IsSupported(professionKey) and "production-enchanting-craft-all-profession-supported" or "production-enchanting-craft-all-profession-unsupported", "Enchanting production route with 8/8 Enchant One coverage")

    local explicitSource = options.explicitUserSelection == true and tostring(options.selectionSource or "") == self.selectionSource
    addGate(model, "explicit-target-selection-origin", explicitSource, explicitSource and "explicit-target-batch-origin-valid" or "explicit-target-batch-origin-required", "batch must originate from an explicit Profession Guide target selection flow")

    local consumer = currentConsumer(mode, options.consumerOptions)
    model.consumer = consumer
    local consumerReady = consumer and consumer.state == "consumer-authority-active" and consumer.consumerAuthorityEnabled == true
    addGate(model, "consumer-authority", consumerReady, consumerReady and "production-enchanting-consumer-current" or "production-enchanting-consumer-unavailable", consumer and tostring(consumer.state) or "consumer unavailable")

    local identity = exactCurrentIdentity()
    model.identity = identity
    local recipeID = identity and tonumber(identity.stagedRecipeID) or nil
    local recipe = identity and identity.recipe or nil
    local identityReady = identity and identity.liveCurrentStepCorroborated == true and recipeID ~= nil
    model.recipeID = recipeID
    model.recipe = recipe
    addGate(model, "recipe-identity", identityReady, identityReady and "production-enchanting-craft-all-recipe-current" or "production-enchanting-craft-all-recipe-not-current", identity and tostring(identity.state) or "identity unavailable")

    local plan = consumer and consumer.plan or nil
    local step = plan and plan.step or nil
    local planReady = consumerReady and plan and plan.actionKind == "craft" and step ~= nil
        and tonumber(step.recipeID or (step.rawStep and step.rawStep.recipeID)) == recipeID
        and tostring(step.recipe or "") == tostring(recipe or "")
    model.plan = plan
    model.routeIndex = tonumber(step and step.routeIndex)
    model.skillTarget = tonumber(step and step.skillTarget)
    addGate(model, "current-recipe-lock", planReady, planReady and "production-enchanting-craft-all-current-recipe-locked" or "production-enchanting-craft-all-current-recipe-mismatch", "Craft All never changes recipe/route")

    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get(self.professionKey) or nil
    model.professionSkill = tonumber(profession and profession.skill)
    local targetOpen = model.professionSkill ~= nil and model.skillTarget ~= nil and model.professionSkill < model.skillTarget
    addGate(model, "skill-target-open", targetOpen, targetOpen and "production-enchanting-craft-all-skill-target-open" or "production-enchanting-craft-all-skill-target-reached", string.format("skill=%s target=%s", tostring(model.professionSkill), tostring(model.skillTarget)))

    local readiness = consumer and consumer.readiness or nil
    model.readiness = readiness
    model.materialUpperBound = readiness and readiness.immediateBagsKnown == false and 0 or math.max(0, math.floor(tonumber(readiness and readiness.immediateBags) or 0))
    local materialReady = model.materialUpperBound >= 1
    addGate(model, "material-upper-bound", materialReady, materialReady and "production-enchanting-craft-all-material-bound-ready" or "production-enchanting-craft-all-materials-unavailable", "bag-material upper bound=" .. tostring(model.materialUpperBound))

    local listReady = type(targetGUIDs) == "table" and #targetGUIDs >= 1 and #targetGUIDs <= self.maxTargetBatchSize
    model.submittedTargetCount = type(targetGUIDs) == "table" and #targetGUIDs or 0
    addGate(model, "target-batch-shape", listReady, listReady and "production-enchanting-explicit-target-batch-shaped" or "production-enchanting-explicit-target-batch-invalid", string.format("submitted=%d max=%d", model.submittedTargetCount, self.maxTargetBatchSize))

    local firstSelectedGUID = consumer and consumer.snapshot and consumer.snapshot.targetGUID or nil
    local firstReady = listReady and tostring(targetGUIDs[1] or "") ~= "" and tostring(targetGUIDs[1]) == tostring(firstSelectedGUID or "")
    addGate(model, "first-target-anchor", firstReady, firstReady and "production-enchanting-craft-all-first-target-bound-to-current-selection" or "production-enchanting-craft-all-first-target-not-current-selection", "first batch target must equal the current Optional Target selection")

    local proofs, seen = {}, {}
    local proofReady = listReady and identityReady
    if proofReady then
        for index, rawGUID in ipairs(targetGUIDs) do
            local guid = tostring(rawGUID or "")
            if guid == "" or seen[guid] then
                proofReady = false
                model.targetProofError = seen[guid] and "duplicate-target-guid" or "empty-target-guid"
                model.targetProofErrorIndex = index
                break
            end
            seen[guid] = true
            local proof, state = self:CaptureTargetProof(recipeID, guid)
            if not proof then
                proofReady = false
                model.targetProofError = state
                model.targetProofErrorIndex = index
                break
            end
            proof.ordinal = index
            proofs[#proofs + 1] = proof
        end
    end
    model.targetProofs = proofs
    model.explicitTargetCount = #proofs
    addGate(model, "explicit-distinct-target-proofs", proofReady and #proofs == model.submittedTargetCount, proofReady and #proofs == model.submittedTargetCount and "production-enchanting-craft-all-target-proofs-current" or "production-enchanting-craft-all-target-proof-blocked", model.targetProofError and (tostring(model.targetProofError) .. " at index " .. tostring(model.targetProofErrorIndex or "?")) or ("validated=" .. tostring(#proofs)))

    model.requestedCount = math.min(model.materialUpperBound, model.explicitTargetCount)
    local bounded = model.requestedCount >= 1
    addGate(model, "bounded-request-count", bounded, bounded and "production-enchanting-craft-all-bounded-count-ready" or "production-enchanting-craft-all-bounded-count-zero", string.format("materials=%d explicitTargets=%d requested=%d", model.materialUpperBound, model.explicitTargetCount, model.requestedCount))

    local targetBound = consumer and consumer.targetBound == true and consumer.snapshot and tostring(consumer.snapshot.targetGUID or "") == tostring(firstSelectedGUID or "")
    addGate(model, "target-bound-consumer", targetBound, targetBound and "production-enchanting-craft-all-consumer-target-bound" or "production-enchanting-craft-all-consumer-target-not-bound", "first target remains part of the consumer snapshot")

    if model.stats.passedGates ~= model.stats.totalGates then
        model.state = model.blockedState or "production-enchanting-craft-all-readiness-blocked"
        return nil, model.state, model
    end

    local session=currentClientReceipt()
    if not session then return nil,"production-enchanting-batch-live-session-unverified",model end
    -- Target observation and batch creation must belong to one session.
    for _,proof in ipairs(proofs) do
        if proof.clientBuildToken~=session.token then
            return nil,"production-enchanting-batch-target-session-changed",model
        end
    end
    local authorizedTargets = {}
    local fingerprintParts = {
        self.batchContract,
        tostring(generation),
        tostring(session.build),
        session.token,
        tostring(consumer and consumer.snapshotToken or ""),
        tostring(consumer and consumer.stateFingerprint or ""),
        tostring(recipe or ""),
        tostring(recipeID or ""),
        tostring(model.routeIndex or ""),
        tostring(model.skillTarget or ""),
        tostring(model.professionSkill or ""),
        tostring(model.materialUpperBound),
        tostring(model.requestedCount),
    }
    for index = 1, model.requestedCount do
        local proof = proofs[index]
        authorizedTargets[index] = copy(proof)
        fingerprintParts[#fingerprintParts + 1] = tostring(proof and proof.fingerprint or "")
    end
    local batchFingerprint = stateHash(fingerprintParts)
    self.batchSerial = (tonumber(self.batchSerial) or 0) + 1
    local batch = {
        contract=self.batchContract,
        readinessContract=self.readinessContract,
        authorityContract=self.contract,
        token="enchant-craft-all-batch-" .. stateHash({batchFingerprint, tostring(self.batchSerial), tostring(now())}),
        fingerprint=batchFingerprint,
        authorityGeneration=generation,
        professionKey=self.professionKey,
        mode=mode,
        currentBuild=session.build,
        clientBuildToken=session.token,
        snapshotToken=consumer.snapshotToken,
        stateFingerprint=consumer.stateFingerprint,
        sourceAuthorityContract=consumer.snapshot and consumer.snapshot.sourceAuthorityContract or nil,
        sourceDatasetContract=consumer.snapshot and consumer.snapshot.sourceDatasetContract or nil,
        recipe=recipe,
        recipeID=recipeID,
        routeIndex=model.routeIndex,
        skillTarget=model.skillTarget,
        startedSkill=model.professionSkill,
        materialUpperBound=model.materialUpperBound,
        submittedTargetCount=model.submittedTargetCount,
        explicitTargetCount=model.explicitTargetCount,
        requestedCount=model.requestedCount,
        targets=authorizedTargets,
        selectionSource=self.selectionSource,
        explicitUserSelection=true,
        targetPolicy=self.targetPolicy,
        targetOrderLocked=true,
        targetGUIDDistinct=true,
        targetSingleUse=true,
        recipeLocked=true,
        skillTargetFirst=true,
        automaticTargetSelection=false,
        automaticTargetSkipping=false,
        automaticRouteAdvance=false,
        nativeDispatchPerOrdinal=0,
        futureNativeDispatchPerOrdinal=1,
        readOnly=true,
        executionEligible=false,
        executionAuthorityEnabled=false,
        dispatchAllowed=false,
        nativeDispatchAllowed=false,
        craftAllNativeExecutionAllowed=false,
        confirmationAutomationAllowed=false,
        automaticQueueAllowed=false,
        requiresExplicitUserActionPerOrdinal=true,
        nativeNumCastsPerAction=1,
        persisted=false,
        createdAt=now(),
    }
    model.batchFingerprint = batchFingerprint
    model.craftAllReadinessReady = true
    model.state = "production-enchanting-craft-all-readiness-ready"
    self.lastByProfession[self.professionKey] = copy(model)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_CRAFT_ALL_READINESS_UPDATED", copy(model))
    end
    return batch, "production-enchanting-explicit-target-batch-prepared", model
end

function ProductionEnchantingCraftAllAuthority:ValidateTargetBatch(submitted, options)
    options = type(options) == "table" and options or {}
    if type(submitted) ~= "table" or submitted.contract ~= self.batchContract then
        return false, "production-enchanting-target-batch-invalid", nil
    end
    if submitted.readOnly ~= true or submitted.executionEligible ~= false or submitted.dispatchAllowed ~= false
        or submitted.nativeDispatchAllowed ~= false or submitted.automaticTargetSelection ~= false
        or submitted.automaticTargetSkipping ~= false or submitted.automaticRouteAdvance ~= false
        or submitted.automaticQueueAllowed ~= false or submitted.requiresExplicitUserActionPerOrdinal ~= true
        or tonumber(submitted.nativeNumCastsPerAction) ~= 1 or submitted.persisted ~= false then
        return false, "production-enchanting-target-batch-safety-shape-invalid", nil
    end
    if options.completedCount ~= nil then
        return false, "production-enchanting-target-batch-caller-completed-count-forbidden", nil
    end
    local generation = self:_RefreshDependencyGeneration("validate-target-batch-dependency-change")
    if tonumber(submitted.authorityGeneration) ~= tonumber(generation) then
        return false, "production-enchanting-target-batch-generation-revoked", nil
    end
    if not self:IsEffectiveEnabled() then return false, "production-enchanting-craft-all-readiness-gate-disabled", nil end
    local session=currentClientReceipt()
    if not session or type(submitted.clientBuildToken)~="string" or
       submitted.clientBuildToken~=session.token or
       tonumber(submitted.currentBuild)~=session.build then
        return false,"production-enchanting-target-batch-session-stale",nil
    end

    local consumer = currentConsumer(submitted.mode, options.consumerOptions)
    if not consumer or consumer.state ~= "consumer-authority-active" or consumer.consumerAuthorityEnabled ~= true then
        return false, "production-enchanting-target-batch-consumer-revoked", consumer
    end
    local currentSnapshot = consumer.snapshot or {}
    local sameAuthority = tostring(currentSnapshot.sourceAuthorityContract or "") == tostring(submitted.sourceAuthorityContract or "")
        and tostring(currentSnapshot.sourceDatasetContract or "") == tostring(submitted.sourceDatasetContract or "")
        and tonumber(currentSnapshot.currentBuild) == tonumber(submitted.currentBuild)
    if not sameAuthority then
        return false, "production-enchanting-target-batch-consumer-source-drift", consumer
    end

    local currentStep = consumer.plan and consumer.plan.step or nil
    local sameRecipe = currentStep ~= nil
        and tostring(currentStep.recipe or "") == tostring(submitted.recipe or "")
        and tonumber(currentStep.recipeID or (currentStep.rawStep and currentStep.rawStep.recipeID)) == tonumber(submitted.recipeID)
        and tonumber(currentStep.routeIndex) == tonumber(submitted.routeIndex)
        and tonumber(currentStep.skillTarget) == tonumber(submitted.skillTarget)
    local identity = exactCurrentIdentity()
    if not sameRecipe or not identity or identity.liveCurrentStepCorroborated ~= true
        or tonumber(identity.stagedRecipeID) ~= tonumber(submitted.recipeID)
        or tostring(identity.recipe or "") ~= tostring(submitted.recipe or "") then
        self:_RevokeGeneration("route-or-recipe-invalidated")
        return false, "production-enchanting-target-batch-revoked-route-drift", consumer
    end

    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get(self.professionKey) or nil
    local skill = tonumber(profession and profession.skill)
    if not skill or not tonumber(submitted.skillTarget) or skill >= tonumber(submitted.skillTarget) then
        return false, "production-enchanting-target-batch-skill-target-reached", consumer
    end

    local completedCount = 0
    if options.sessionToken ~= nil then
        local session = JLP:GetModule("ProductionEnchantingCraftAllSession")
        local progress, progressState
        if session and session.GetVerifiedProgress then progress, progressState = session:GetVerifiedProgress(submitted.token, options.sessionToken) end
        if not progress then return false, progressState or "production-enchanting-craft-all-session-proof-required", consumer end
        completedCount = math.max(0, math.floor(tonumber(progress.settledCount) or 0))
    end
    local requestedCount = math.max(0, math.floor(tonumber(submitted.requestedCount) or 0))
    if completedCount > requestedCount then return false, "production-enchanting-target-batch-settled-count-invalid", consumer end
    local materialNow = consumer.readiness and consumer.readiness.immediateBagsKnown == false and 0 or math.max(0, math.floor(tonumber(consumer.readiness and consumer.readiness.immediateBags) or 0))
    if completedCount < requestedCount and materialNow < 1 then
        return false, "production-enchanting-target-batch-materials-exhausted", consumer
    end

    if type(submitted.targets) ~= "table" or #submitted.targets ~= requestedCount or #submitted.targets < 1 then
        return false, "production-enchanting-target-batch-target-count-invalid", consumer
    end
    local seen = {}
    local fingerprintParts = {
        self.batchContract,
        tostring(submitted.authorityGeneration or ""),
        tostring(session.build),
        session.token,
        tostring(submitted.snapshotToken or ""),
        tostring(submitted.stateFingerprint or ""),
        tostring(submitted.recipe or ""),
        tostring(submitted.recipeID or ""),
        tostring(submitted.routeIndex or ""),
        tostring(submitted.skillTarget or ""),
        tostring(submitted.startedSkill or ""),
        tostring(submitted.materialUpperBound or ""),
        tostring(submitted.requestedCount or ""),
    }
    for index, stored in ipairs(submitted.targets) do
        local guid = tostring(stored and stored.targetGUID or "")
        if guid == "" or seen[guid] then return false, "production-enchanting-target-batch-duplicate-or-empty-target", consumer end
        seen[guid] = true
        fingerprintParts[#fingerprintParts + 1] = tostring(stored and stored.fingerprint or "")
        -- Completed targets are immutable historical intent. Only the next and
        -- later targets must remain live/current; this lets normal skill/material
        -- changes from earlier ordinals occur without silently changing the batch.
        if index > completedCount then
            local live, state = self:CaptureTargetProof(submitted.recipeID, guid)
            if not live then return false, state or "production-enchanting-target-batch-target-stale", consumer end
            local exact = tostring(live.fingerprint or "") == tostring(stored.fingerprint or "")
                and tonumber(live.targetItemID) == tonumber(stored.targetItemID)
                and tostring(live.targetValidationSource or "") == tostring(stored.targetValidationSource or "")
                and tostring(live.targetLocationKey or "") == tostring(stored.targetLocationKey or "")
            if not exact then return false, "production-enchanting-target-batch-target-proof-stale-" .. tostring(index), consumer end
        end
    end
    if stateHash(fingerprintParts) ~= tostring(submitted.fingerprint or "") then
        return false, "production-enchanting-target-batch-fingerprint-mismatch", consumer
    end
    return true, "production-enchanting-target-batch-current", consumer
end

function ProductionEnchantingCraftAllAuthority:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ProductionEnchantingCraftAllAuthority:GetSummary()
    local consumer = currentConsumer("normal")
    local currentTarget = consumer and consumer.snapshot and consumer.snapshot.targetGUID or nil
    local readiness = consumer and consumer.readiness or nil
    local lines = {
        "PRODUCTION ENCHANTING / TARGET-SEQUENCE PLANNING READINESS",
        "Contract: " .. self.contract,
        "Readiness contract: " .. self.readinessContract,
        "Batch contract: " .. self.batchContract,
        "Target proof: " .. self.targetProofContract,
        "Feature gate: " .. (self:IsFeatureEnabled() and "enabled" or "disabled"),
        "Effective planning authority: " .. (self:IsEffectiveEnabled() and "enabled" or "disabled"),
        "Authority generation: " .. tostring(self:GetAuthorityGeneration()),
        "Native Enchant One gate required for planning: no",
        "Target policy: explicit ordered distinct GUID batch",
        "Current selected target anchor: " .. tostring(currentTarget or "none"),
        "Current material upper bound: " .. tostring(readiness and readiness.immediateBags or 0),
        "Per-target policy: one target may be consumed at most once",
        "Invalid/stale next target policy: stop; never skip to a later target",
        "Automatic target selection: forbidden",
        "Automatic target skipping: forbidden",
        "Planner route changes: forbidden",
        "Sequence model: one enchant per explicit user action; settlement unlocks the next ordinal",
        "Native numCasts per action: 1",
        "Automatic enchant queue: disabled",
        "Native sequence execution: NOT PROMOTED",
        "Native dispatch from alpha115 planning authority: forbidden",
        "Protected Replace/Bind automation: not implemented; secure client boundary",
        "Persistence: none",
    }
    return table.concat(lines, "\n")
end

function ProductionEnchantingCraftAllAuthority:Initialize()
    if self.initialized then return true end
    self.initialized = true
    self.dependencySignature = self:_DependencyState()
    if JLP.EventBus and JLP.EventBus.On then
        local function revokeDependency(payload)
            self.dependencySignature = self:_DependencyState()
            self:_RevokeGeneration(type(payload) == "table" and payload.state or "planning-parent-authority-changed")
        end
        -- Read-only sequence planning intentionally does not depend on the native
        -- Enchant One runtime kill-switch. Consumer/execution-readiness parent
        -- gates still revoke every batch/session/plan generation.
        JLP.EventBus:On("RESEARCH_EXECUTION_AUTHORITY_UPDATED", revokeDependency)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_AUTHORITY_UPDATED", revokeDependency)
    end
    return true
end

function ProductionEnchantingCraftAllAuthority:Validate()
    local errors, warnings = {}, {}
    if self.readOnly ~= true or self.executionEligible ~= false or self.executionAuthorityEnabled ~= false
        or self.nativeDispatchAllowed ~= false or self.craftAllNativeExecutionAllowed ~= false
        or self.automaticTargetSelectionAllowed ~= false or self.automaticTargetSkippingAllowed ~= false
        or self.automaticRouteAdvance ~= false or self.confirmationAutomationAllowed ~= false
        or self.persistedAuthorization ~= false or self.automaticQueueAllowed ~= false
        or self.requiresExplicitUserActionPerOrdinal ~= true or self.nativeNumCastsPerAction ~= 1 then
        errors[#errors + 1] = "production Enchanting Craft All planning authority safety boundary invalid"
    end
    if self.targetPolicy ~= "ordered-explicit-distinct-guid-batch" then
        errors[#errors + 1] = "production Enchanting Craft All target policy invalid"
    end
    for _, name in ipairs({
        "ProductionEnchantingAuthorityAdapter",
        "ProductionEnchantingRecipeIdentity",
        "ProductionEnchantingNativeExecutionAuthority",
        "ProductionEnchantingNativeRouteCoverage",
        "ResearchPlannerConsumerBridge",
        "ResearchExecutionAuthorityGate",
        "ProfessionAPI",
    }) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "production Enchanting Craft All dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionEnchantingCraftAllAuthority", ProductionEnchantingCraftAllAuthority)
