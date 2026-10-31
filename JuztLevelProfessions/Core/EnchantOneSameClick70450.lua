local _, JLP = ...

-- A *transient* same-click bridge. It never persists an authorization, hooks
-- StaticPopup, or invokes ReplaceEnchant/BindEnchant directly. A protected
-- Blizzard confirmation is always a separate secure user-action boundary.
-- Only try the visible button when Blizzard reports that our *current* stack
-- is secure and neither control is protected. Otherwise show the manual popup.
local Bridge = {
    contract = "enchant-one-same-click-70450-v1",
    authority = "same-hardware-click-only; never asynchronous",
    nativeCraftsPerClick = 1,
    persistedAuthorization = false,
    last = nil,
}
local active = nil
local serial = 0

local function clock()
    if type(GetTime) ~= "function" then return nil end
    local ok, t = pcall(GetTime)
    t = ok and tonumber(t) or nil
    return t and t > 0 and t or nil
end
local function isShown(frame)
    return frame and type(frame.IsShown) == "function" and frame:IsShown() == true
end
local function currentCapability()
    local layer=JLP:GetModule("RuntimeCompatibility")
    if type(layer)~="table" or type(layer.CheckAPI)~="function" then
        return nil,"CAPABILITY_LAYER_UNAVAILABLE"
    end
    local ok,available=pcall(layer.CheckAPI,layer,"C_TradeSkillUI.CraftEnchant")
    if not ok or available~=true then return nil,"CRAFT_ENCHANT_API_UNAVAILABLE" end
    local build=JLP:GetModule("ClientBuildInfo")
    if type(build)~="table" or type(build.Read)~="function" then
        return nil,"LIVE_CLIENT_IDENTITY_UNAVAILABLE"
    end
    -- Bind the ephemeral same-click ticket to one coherent GetBuildInfo read:
    -- build AND interface identity must remain unchanged through confirmation.
    local safe,identity=pcall(build.Read,build)
    local current=safe and type(identity)=="table" and identity.buildNumber or nil
    if not safe or type(identity)~="table" or identity.known~=true or
       type(current)~="number" or current<=0 or
       current~=math.floor(current) or current==math.huge or
       type(identity.token)~="string" or identity.token=="" then
        return nil,"LIVE_CLIENT_IDENTITY_UNVERIFIED"
    end
    return current,nil,identity.token
end
local function reason(state)
    Bridge.last = { contract = Bridge.contract, state = state, at = clock(), executed = false }
    return false, state
end

function Bridge:Begin(crafting, recipeID, target)
    -- Begin must be called INSIDE the native Enchant button's OnClick, before
    -- the client dispatch. This is not an independent authority to craft.
    active = nil
    local clientBuild,capabilityReason,clientToken=currentCapability()
    if not clientBuild then return nil,capabilityReason end
    if type(crafting) ~= "table" or type(target) ~= "table" or
       not tonumber(recipeID) or not target.guid or not tonumber(target.itemID) then
        return nil, "TARGET_OR_RECIPE_UNAVAILABLE"
    end
    local t = clock()
    if not t then return nil, "CLICK_TIME_UNAVAILABLE" end
    serial = serial + 1
    local popup = StaticPopup1
    active = {
        serial = serial, crafting = crafting,
        recipeID = tonumber(recipeID), targetGUID = tostring(target.guid),
        targetItemID = tonumber(target.itemID),
        clickedAt = t, clientBuild = clientBuild, clientToken = clientToken,
        preexistingPopup = isShown(popup), consumed = false,
    }
    return active, "ARMED"
end

function Bridge:Cancel(session)
    if active == session then
        session.consumed = true
        active = nil
    end
end

function Bridge:TrySameClick(session, inspected)
    if type(session) ~= "table" or active ~= session or session.consumed then
        return reason("NO_LIVE_SINGLE_USE_CLICK")
    end
    -- Burn this one-time ticket BEFORE interacting with Blizzard. Reentrancy,
    -- repeated events and a second call cannot confirm a popup twice.
    session.consumed = true
    active = nil
    if inspected ~= true or session.preexistingPopup then return reason("NO_BOUND_NEW_POPUP") end
    local liveBuild,capabilityReason,liveToken=currentCapability()
    if not liveBuild then return reason(capabilityReason) end
    if session.clientBuild~=liveBuild or session.clientToken~=liveToken then
        return reason("LIVE_CLIENT_IDENTITY_CHANGED")
    end
    local crafting, pending = session.crafting, session.crafting.pendingEnchant
    if type(pending) ~= "table" or pending.productionEnchantingNativeExecution ~= true or
       pending.key ~= "ENCHANTING" or pending.status ~= "confirmation-required" or
       pending.confirmationRequired ~= true or pending.confirmationEvent ~= "REPLACE_ENCHANT" or
       pending.confirmationReason ~= "replace-existing-enchant" or
       pending.ledgerID == nil or pending.transactionID == nil or
       tonumber(pending.requestedCount) ~= 1 or
       tonumber(pending.recipeID) ~= session.recipeID or
       tostring(pending.targetGUID) ~= session.targetGUID or
       tonumber(pending.targetItemID) ~= session.targetItemID then
        return reason("TRANSACTION_OR_TARGET_CHANGED")
    end
    local chosen = crafting.enchantTargets and crafting.enchantTargets[session.recipeID]
    if type(chosen) ~= "table" or tostring(chosen.guid) ~= session.targetGUID or
       tonumber(chosen.itemID) ~= session.targetItemID then
        return reason("SELECTED_TARGET_CHANGED")
    end
    local settlement = JLP:GetModule("ProductionEnchantingNativeSettlement")
    local at, src
    -- The two return values must come from ONE observation call.
    if settlement and type(settlement.GetTransientConfirmationObservation) == "function" then
        at, src = settlement:GetTransientConfirmationObservation(pending)
    end
    local t = clock()
    if src ~= "TRANSIENT_EVENT_OBSERVED" or not t or not tonumber(at) or
       at < session.clickedAt or t < at or t - session.clickedAt > 2 then
        return reason("NO_FRESH_CLIENT_CONFIRMATION_EVENT")
    end
    local popup, accept = StaticPopup1, StaticPopup1Button1
    if not isShown(popup) or not isShown(accept) or popup.which ~= "REPLACE_ENCHANT" or
       type(accept.GetParent) ~= "function" or accept:GetParent() ~= popup or
       type(accept.IsEnabled) ~= "function" or not accept:IsEnabled() or
       type(accept.Click) ~= "function" then
        return reason("POPUP_NOT_EXACT_REPLACE_ENCHANT")
    end
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then
        return reason("COMBAT_OR_LOCKDOWN_UNKNOWN")
    end
    -- A same hardware click does NOT automatically make addon Lua secure.
    -- Never try a protected click from a tainted addon call stack.
    if type(issecure) ~= "function" or issecure() ~= true or
       type(popup.IsProtected) ~= "function" or popup:IsProtected() ~= false or
       type(accept.IsProtected) ~= "function" or accept:IsProtected() ~= false then
        return reason("PROTECTED_OR_TAINTED_CONFIRMATION_MANUAL_ONLY")
    end
    -- FINAL identity/state check immediately before the only optional click.
    if crafting.pendingEnchant ~= pending or not isShown(popup) or
       popup.which ~= "REPLACE_ENCHANT" then
        return reason("POPUP_OR_TRANSACTION_CHANGED")
    end
    -- One attempt; never retry on callback/error, never schedule delayed work.
    local ok, result = pcall(accept.Click, accept)
    if not ok or result == false then return reason("CLIENT_REFUSED_CONFIRMATION_MANUAL_ONLY") end
    self.last = { contract = self.contract, state = "POPUP_CLICK_REQUESTED_NOT_SETTLED",
        at = t, executed = true, recipeID = session.recipeID,
        transactionID = tostring(pending.transactionID) }
    return true, self.last.state
end

function Bridge:GetLastStatus()
    if not self.last then return nil end
    local copy = {}
    for k, v in pairs(self.last) do copy[k] = v end
    return copy
end

JLP:RegisterModule("EnchantOneSameClick70450", Bridge)
