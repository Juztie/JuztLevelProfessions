local _, JLP = ...

-- Alpha108 defines the target-aware boundary that future Enchanting readiness and
-- native authority must satisfy. It observes the current Optional Target state but
-- never calls CraftEnchant or any protected enchant-confirmation function.
local ProductionEnchantingTargetedExecutionFoundation = {
    contract = "production-enchanting-targeted-execution-foundation-v1",
    targetProofContract = "production-enchanting-optional-target-proof-v1",
    authority = "read-only-selected-guid-live-itemlocation-target-proof",
    nativeDispatchAllowed = false,
    automaticExecutionAllowed = false,
    confirmationAutomationAllowed = false,
    persisted = false,
}

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
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
    if ok then return value end
    return nil
end

local function stateHash(parts)
    local value = table.concat(parts or {}, "\31")
    local hash = 5381
    for index = 1, #value do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return string.format("%08x", hash)
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
    local locationType = type(location)
    if locationType == "table" or locationType == "userdata" then
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
                if ok then return "equipment:"..tostring(slot or "") end
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

local function targetListed(recipeID, guid)
    if not recipeID or not guid or type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.GetEnchantItems) ~= "function" then return false end
    local ok, rows = pcall(C_TradeSkillUI.GetEnchantItems, recipeID)
    if not ok or type(rows) ~= "table" then return false end
    for _, value in pairs(rows) do
        if value == guid then return true end
    end
    return false
end

local function targetValidated(recipeID, guid)
    if targetListed(recipeID, guid) then return true, "GetEnchantItems" end
    if recipeID and guid and type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.IsEnchantTargetValid) == "function" then
        local ok, value = pcall(C_TradeSkillUI.IsEnchantTargetValid, recipeID, guid)
        if ok and value then return true, "IsEnchantTargetValid" end
    end
    return false, nil
end

-- Recipe-specific read-only target observation; deliberately independent of
-- the legacy native identity allowlist. This NEVER enables native authority.
function ProductionEnchantingTargetedExecutionFoundation:AssessRecipeTarget(id)
 local crafting=JLP:GetModule("Crafting")
 local selected=crafting and crafting.enchantTargets and crafting.enchantTargets[id]
 local guid=selected and selected.guid
 local result={recipeID=id,guid=guid,status="UNKNOWN",ready=false,readOnly=true,nativeDispatchAllowed=false}
 if type(guid)~="string" or guid=="" then result.status="TARGET_NOT_SELECTED";return result end
 local a,b=guidInInventory(guid),guidInInventory(guid)
 if a~=true or b~=true then result.status=a==false and "TARGET_NOT_IN_BAGS" or "TARGET_INVENTORY_UNKNOWN";return result end
 local valid=targetValidated(id,guid);local again=targetValidated(id,guid)
 if valid~=true or again~=true then result.status="TARGET_NOT_VALIDATED";return result end
 if crafting.enchantTargets[id]~=selected or selected.guid~=guid then return result end
 result.ready=true;result.status="CURRENT_TARGET_GUID_VALIDATED";return result
end
function ProductionEnchantingTargetedExecutionFoundation:AssessCurrent()
    local model = {
        contract = self.contract,
        targetProofContract = self.targetProofContract,
        professionKey = "ENCHANTING",
        state = "enchanting-targeted-execution-foundation-blocked",
        currentBuild = currentBuild(),
        targetFoundationReady = false,
        nativeAuthorityEnabled = false,
        nativeDispatchAllowed = false,
        automaticExecutionAllowed = false,
        confirmationAutomationAllowed = false,
        persisted = false,
        gates = {},
    }
    local function gate(key, ready, detail)
        model.gates[key] = { ready=ready and true or false, detail=detail }
        return ready and true or false
    end

    local identity = JLP:GetModule("ProductionEnchantingRecipeIdentity")
    local identityModel = identity and identity.AssessCurrent and identity:AssessCurrent() or nil
    model.identity = identityModel
    local identityReady = gate("recipe-identity", identityModel and identityModel.liveCurrentStepCorroborated == true,
        identityModel and tostring(identityModel.state) or "recipe-identity-module-unavailable")
    local recipeID = identityModel and tonumber(identityModel.stagedRecipeID) or nil
    model.recipeID = recipeID
    model.recipe = identityModel and identityModel.recipe or nil

    local crafting = JLP:GetModule("Crafting")
    local selected = crafting and crafting.enchantTargets and recipeID and crafting.enchantTargets[recipeID] or nil
    model.selectedTarget = selected
    model.targetGUID = selected and selected.guid or nil
    local selectedReady = gate("optional-target-selected", selected ~= nil and selected.guid ~= nil,
        selected and tostring(selected.guid) or "no Optional Target selected for current recipe")

    local present = nil
    if selected then present = guidInInventory(selected.guid) end
    model.targetInInventory = present
    local inventoryReady = gate("target-guid-in-inventory", present == true,
        present == true and "selected GUID is still in inventory/equipment" or (present == false and "selected GUID left inventory/equipment" or "GUID inventory status unavailable"))

    local valid, validationSource = false, nil
    if selected then valid, validationSource = targetValidated(recipeID, selected.guid) end
    model.targetValid = valid and true or false
    model.targetValidationSource = validationSource
    local validReady = gate("native-target-valid", valid == true,
        valid and ("validated by "..tostring(validationSource)) or "selected GUID is not a current native Optional Target")

    local location = selected and getLocation(selected.guid) or nil
    model.targetLocation = location
    model.targetLocationKey = locationKey(location)
    local locationReady = gate("live-item-location", location ~= nil and model.targetLocationKey ~= nil,
        location and "live ItemLocation resolved from selected GUID" or "selected GUID has no current ItemLocation")
    model.targetItemID = itemIDFor(model.targetGUID, location) or tonumber(selected and selected.itemID)
    local itemIdentityReady = gate("target-item-identity", model.targetItemID ~= nil,
        model.targetItemID and ("itemID="..tostring(model.targetItemID)) or "target item ID unavailable")

    local craftEnchantAvailable = type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.CraftEnchant) == "function"
    gate("craft-enchant-api", craftEnchantAvailable, craftEnchantAvailable and "C_TradeSkillUI.CraftEnchant available" or "CraftEnchant unavailable")

    local recovery = JLP:GetModule("TransactionRecovery")
    local recoveryReady, recoveryMessage = true, nil
    if recovery and recovery.CanStart then recoveryReady, recoveryMessage = recovery:CanStart("enchant", "ENCHANTING") end
    gate("transaction-clear", recoveryReady == true, recoveryReady and "no unresolved enchant recovery" or tostring(recoveryMessage or "recovery blocks new enchant"))

    local noPendingEnchant = not (crafting and crafting.pendingEnchant)
    local noPendingCraft = not (crafting and crafting.pendingCraft)
    gate("no-pending-enchant", noPendingEnchant, noPendingEnchant and "no enchant transaction in flight" or "an enchant transaction is in flight")
    gate("no-pending-craft", noPendingCraft, noPendingCraft and "no craft transaction in flight" or "a craft transaction is in flight")

    model.targetFoundationReady = identityReady and selectedReady and inventoryReady and validReady and locationReady and itemIdentityReady
        and craftEnchantAvailable and recoveryReady == true and noPendingEnchant and noPendingCraft
    if model.targetFoundationReady then model.state = "enchanting-targeted-execution-foundation-ready" end

    -- Proof is diagnostic/readiness material only. A later authority must bind it
    -- to a fresh consumer/readiness snapshot and must re-resolve ItemLocation just
    -- before CraftEnchant; this module never makes the call itself.
    if model.targetFoundationReady then
        local proofParts = {
            self.targetProofContract, "ENCHANTING", tostring(model.recipe or ""), tostring(recipeID or ""),
            tostring(model.targetGUID or ""), tostring(model.targetItemID or ""), tostring(validationSource or ""),
            tostring(model.targetLocationKey or ""), tostring(model.currentBuild or ""), tostring(identityModel and identityModel.corroborationContract or ""),
        }
        model.targetProofFingerprint = stateHash(proofParts)
        model.targetProof = {
            contract = self.targetProofContract,
            fingerprint = model.targetProofFingerprint,
            professionKey = "ENCHANTING",
            recipe = model.recipe,
            recipeID = recipeID,
            targetGUID = model.targetGUID,
            targetItemID = model.targetItemID,
            targetValidationSource = validationSource,
            targetLocationKey = model.targetLocationKey,
            currentBuild = model.currentBuild,
            itemLocationPresent = location ~= nil,
            exactRecipeIdentity = identityReady,
        }
    end
    return model
end

function ProductionEnchantingTargetedExecutionFoundation:GetSummary()
    local model = self:AssessCurrent()
    local lines = {
        "ENCHANTING / TARGETED EXECUTION FOUNDATION",
        "Contract: "..self.contract,
        "Target proof: "..self.targetProofContract,
        "State: "..tostring(model.state),
        "Current recipe: "..tostring(model.recipe or "unavailable"),
        "Recipe ID: "..tostring(model.recipeID or "n/a"),
        "Selected target GUID: "..tostring(model.targetGUID or "none"),
        "Target item ID: "..tostring(model.targetItemID or "n/a"),
        "Target in inventory/equipment: "..(model.targetInInventory == true and "yes" or "no"),
        "Native target valid: "..(model.targetValid and "yes" or "no"),
        "Validation source: "..tostring(model.targetValidationSource or "none"),
        "Live ItemLocation: "..(model.targetLocation and "yes" or "no"),
        "ItemLocation key: "..tostring(model.targetLocationKey or "none"),
        "Target proof fingerprint: "..tostring(model.targetProofFingerprint or "none"),
        "Target foundation ready: "..(model.targetFoundationReady and "yes" or "no"),
        "CraftEnchant authority: disabled by this module",
        "Protected confirmation automation: forbidden",
        "Native dispatch: forbidden",
        "Persistence: none",
    }
    return table.concat(lines, "\n")
end

function ProductionEnchantingTargetedExecutionFoundation:Validate()
    local errors = {}
    if self.nativeDispatchAllowed ~= false or self.automaticExecutionAllowed ~= false or self.confirmationAutomationAllowed ~= false or self.persisted ~= false then
        errors[#errors+1] = "Enchanting targeted execution foundation safety boundary invalid"
    end
    local identity = JLP:GetModule("ProductionEnchantingRecipeIdentity")
    if not identity or identity.contract ~= "production-enchanting-recipe-identity-evidence-v1" then
        errors[#errors+1] = "Enchanting target foundation requires alpha108 recipe identity evidence"
    end
    return #errors == 0, errors, {}
end

JLP:RegisterModule("ProductionEnchantingTargetedExecutionFoundation", ProductionEnchantingTargetedExecutionFoundation)
