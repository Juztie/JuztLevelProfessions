local _, JLP = ...
local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end
local frame=CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")

-- Bank events are registered defensively because Forever API surfaces can vary by build.
for _, optionalEvent in ipairs({
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED", "BAG_CONTAINER_UPDATE", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
    "TRADE_SKILL_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
    "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
    "CHAT_MSG_SKILL", "UNIT_SPELLCAST_SENT", "LOOT_OPENED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "REPLACE_ENCHANT", "BIND_ENCHANT", "TRADE_REPLACE_ENCHANT", "TRADE_POTENTIAL_BIND_ENCHANT",
    "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED", "PLAYER_LOGOUT", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
    "PLAYER_LEVEL_UP", "PLAYERREAGENTBANKSLOTS_CHANGED", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_MONEY",
    "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_EQUIPMENT_CHANGED"
}) do
    local available=pcall(frame.RegisterEvent, frame, optionalEvent)
    local sensor=JLP:GetModule("GatheringObservationSensor")
    if sensor then
        sensor.manualReceiptEventAvailable=sensor.manualReceiptEventAvailable or {}
        sensor.manualReceiptEventAvailable[optionalEvent]=available
        if optionalEvent=="LOOT_SLOT_CLEARED" then sensor.manualSlotEventAvailable=available end
    end
end
-- These existing direct registrations above have already succeeded.
local gatheringSensor=JLP:GetModule("GatheringObservationSensor")
if gatheringSensor then
    gatheringSensor.manualReceiptEventAvailable.BAG_UPDATE_DELAYED=true
    gatheringSensor.manualReceiptEventAvailable.AUCTION_HOUSE_SHOW=true
end

local uiRefreshQueued=false
local function runUIRefresh()
    if JLP.MainWindow and JLP.MainWindow.Refresh then JLP.MainWindow:Refresh() end
end

local function refreshUI()
    if type(C_Timer)=="table" and type(C_Timer.After)=="function" then
        if uiRefreshQueued then return end
        uiRefreshQueued=true
        local ok,err=pcall(C_Timer.After,0,function()
            uiRefreshQueued=false
            runUIRefresh()
        end)
        if ok then return end
        uiRefreshQueued=false
        if JLP.RecordRuntimeError then JLP:RecordRuntimeError("UI_REFRESH_TIMER",err) end
    end
    runUIRefresh()
end

local function distributeOwnership(result)
    if not result or result.scope~="OWNERSHIP" then return end
    local owner=JLP:GetModule("IntegratedDestinationOwner")
    if owner and owner.ObserveProfessionOwnership then owner:ObserveProfessionOwnership()end
    if result.reason=="OWNERSHIP_SETTLED" then
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.ObserveAll then execution:ObserveAll(result.reason) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(result.reason) end
        refreshUI()
    end
end

local itemDataRefreshPending=false
local function refreshItemDataSettled()
    if itemDataRefreshPending then return end
    itemDataRefreshPending=true
    local function run()
        itemDataRefreshPending=false
        if JLP.MainWindow and JLP.MainWindow.RefreshActiveData then JLP.MainWindow:RefreshActiveData() end
        local guide=JLP.UIPages and JLP.UIPages.Guide
        if guide and guide.RefreshEnchantTargetIcons then guide:RefreshEnchantTargetIcons() end
    end
    if type(C_Timer)=="table" and type(C_Timer.After)=="function" then
        local ok,err=pcall(C_Timer.After,0.12,run)
        if not ok then
            if JLP.RecordRuntimeError then JLP:RecordRuntimeError("ITEM_REFRESH_TIMER",err) end
            run()
        end
    else
        run()
    end
end

local settledRefreshPending=false
local function refreshUISettled()
    local supply=JLP:GetModule("GatheringSharedMapState")
    if supply and supply.ObserveSupplyInventory then supply:ObserveSupplyInventory() end
    local acquisition=JLP:GetModule("AcquisitionPlanner")
    if acquisition and acquisition.ObserveMaterialServiceInventory then acquisition:ObserveMaterialServiceInventory() end
    refreshUI()
    -- A single craft/route transition can emit several internal events in the
    -- same frame. Keep one settled read instead of allocating one timer per
    -- event; the active page still receives the immediate coalesced refresh.
    if settledRefreshPending then return end
    if type(C_Timer)=="table" and type(C_Timer.After)=="function" then
        settledRefreshPending=true
        local ok,err=pcall(C_Timer.After,0.05,function()
            settledRefreshPending=false
            if JLP.MainWindow and JLP.MainWindow.RefreshActiveData then JLP.MainWindow:RefreshActiveData() end
        end)
        if not ok then
            settledRefreshPending=false
            if JLP.RecordRuntimeError then JLP:RecordRuntimeError("SETTLED_REFRESH_TIMER",err) end
            if JLP.MainWindow and JLP.MainWindow.RefreshActiveData then JLP.MainWindow:RefreshActiveData() end
        end
    elseif JLP.MainWindow and JLP.MainWindow.RefreshActiveData then
        JLP.MainWindow:RefreshActiveData()
    end
end

local function observeEvent(self,event,...)
    if event=="TRADE_SKILL_DATA_SOURCE_CHANGING" or event=="TRADE_SKILL_DATA_SOURCE_CHANGED" then
        local api=JLP:GetModule("ProfessionAPI")
        if api and api.InvalidateOpenProfessionContext then api:InvalidateOpenProfessionContext(event) end
        return -- event invalidates evidence; it does not train, craft or settle anything
    end
    if event=="QUEST_TURNED_IN" then
        local sensor=JLP:GetModule("GatheringObservationSensor")
        if sensor then pcall(sensor.Observe,sensor,event,...) end
    end
    if event=="QUEST_LOG_UPDATE"or event=="QUEST_TURNED_IN"or event=="PLAYER_EQUIPMENT_CHANGED"then
        -- Re-read current prerequisite fields; an event alone is not a
        -- quest/reward/equipment receipt and never settles a craft.
        local owner=JLP:GetModule("IntegratedDestinationOwner")
        if owner and owner.RevalidateRecipeAcquisition then owner:RevalidateRecipeAcquisition()end
        refreshUISettled()
        return
    end
    for _,name in ipairs({"ProfessionDataBridge70374","ProfessionDataBridge70450"}) do
        local bridge=JLP:GetModule(name)
        if bridge and bridge.OnClientDataEvent then bridge:OnClientDataEvent(event) end
    end
    if event=="TRADE_SKILL_SHOW"or event=="TRADE_SKILL_LIST_UPDATE"or event=="TRADE_SKILL_UPDATE"then
        local smelting=JLP:GetModule("MiningSmeltingProgression")
        if smelting and smelting.ObserveCurrentPanel then
            local ok,err=pcall(smelting.ObserveCurrentPanel,smelting)
            if not ok and JLP.RecordRuntimeError then JLP:RecordRuntimeError("SMELTING_READ_ONLY_OBSERVATION",err)end
        end
    end
    -- Read-only gathering observation; isolated from protected crafting dispatch.
    local secondary=JLP:GetModule("SecondaryWorkspace")
    if secondary and secondary.ObserveCookingStationUse and secondary:ObserveCookingStationUse(event,...)then refreshUISettled()end
    if event=="UNIT_SPELLCAST_SENT" or event=="UNIT_SPELLCAST_SUCCEEDED" or
        event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" or
        event=="LOOT_OPENED" or event=="LOOT_SLOT_CLEARED" or event=="LOOT_CLOSED" or event=="BAG_UPDATE_DELAYED" or
        event=="BANKFRAME_OPENED" or event=="BANKFRAME_CLOSED" or event=="PLAYERBANKSLOTS_CHANGED" or event=="PLAYERBANKBAGSLOTS_CHANGED" or
        event=="PLAYERREAGENTBANKSLOTS_CHANGED" or event=="PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" or
        event=="MERCHANT_SHOW" or event=="MERCHANT_UPDATE" or event=="MERCHANT_CLOSED" or
        event=="TRADE_SHOW" or event=="TRADE_CLOSED" or event=="TRADE_PLAYER_ITEM_CHANGED" or event=="TRADE_TARGET_ITEM_CHANGED" or
        event=="MAIL_SHOW" or event=="MAIL_CLOSED" or event=="MAIL_INBOX_UPDATE" or
        event=="AUCTION_HOUSE_SHOW" or event=="AUCTION_HOUSE_CLOSED" or event=="TRADE_SKILL_CRAFT_BEGIN" or event=="TRADE_SKILL_ITEM_CRAFTED_RESULT" or
        event=="PLAYER_ENTERING_WORLD" or
        event=="ZONE_CHANGED" or event=="ZONE_CHANGED_NEW_AREA" or
        event=="ZONE_CHANGED_INDOORS" or event=="PLAYER_LOGOUT" then
        local sensor=JLP:GetModule("GatheringObservationSensor")
        if sensor then
            local ok,err=pcall(sensor.Observe,sensor,event,...)
            if not ok and JLP.runtime then
                if JLP.RecordRuntimeError then
                    JLP:RecordRuntimeError("GATHERING_OBSERVATION_SENSOR",err)
                end
            end
        end
    end
    if event=="ADDON_LOADED" then
        local addonName=...
        if addonName~=JLP.name then return end
        local db=JLP:GetModule("DB"); db:Initialize()
        local progress=JLP:GetModule("RouteProgress")
        if progress and progress.Initialize then progress:Initialize() end
        for _,name in ipairs({"ProfessionDataBridge70374","ProfessionDataBridge70450"}) do
            local dataBridge=JLP:GetModule(name)
            if dataBridge and dataBridge.Initialize then dataBridge:Initialize() end
        end
        JLP.EventBus:On("AH_SNAPSHOT_UPDATED",refreshUI)
        JLP.EventBus:On("SETTINGS_CHANGED",refreshUI)
        JLP.EventBus:On("GATHERING_OBSERVATION_UPDATED",refreshUISettled)
        JLP.EventBus:On("PROFESSION_PROGRESS_UPDATED",refreshUISettled)
        JLP.EventBus:On("PROFESSION_CRAFT_OBSERVED",refreshUISettled)
        JLP.EventBus:On("ENCHANT_ACTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("CRAFT_ACTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("PROFESSION_TRANSACTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("PROFESSION_EXECUTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("WORKSPACE_ORCHESTRATION_UPDATED",refreshUISettled)
        JLP.EventBus:On("ROUTE_SESSION_UPDATED",refreshUISettled)
        JLP.EventBus:On("TRAVEL_SESSION_UPDATED",refreshUISettled)
        JLP.EventBus:On("TRAVEL_TRANSITION_UPDATED",refreshUISettled)
        JLP.EventBus:On("ROUTE_MARKER_UPDATED",refreshUISettled)
        JLP.EventBus:On("DESTINATION_HANDOFF_UPDATED",refreshUISettled)
        JLP.EventBus:On("ROUTE_RECOVERY_UPDATED",refreshUISettled)
        JLP.EventBus:On("TRANSACTION_RECOVERY_UPDATED",refreshUISettled)
        JLP.EventBus:On("TRANSACTION_LEDGER_UPDATED",refreshUISettled)
        JLP.EventBus:On("RECIPE_TELEMETRY_UPDATED",refreshUISettled)
        JLP.EventBus:On("RECIPE_ACCESS_EVIDENCE_UPDATED",refreshUISettled)
        JLP.EventBus:On("MATERIAL_ACQUISITION_EVIDENCE_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_CONSUMER_AUTHORITY_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_NATIVE_SETTLEMENT_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_TAILORING_NATIVE_EXECUTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_TAILORING_NATIVE_EXECUTION_AUTHORITY_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_NATIVE_EXECUTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_NATIVE_EXECUTION_AUTHORITY_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_NATIVE_SETTLEMENT_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_CRAFT_ALL_AUTHORITY_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_CRAFT_ALL_READINESS_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_CRAFT_ALL_ORCHESTRATOR_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_ENCHANTING_CRAFT_ALL_SESSION_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_CRAFT_ALL_AUTHORITY_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_CRAFT_ALL_STRICT_UPDATED",refreshUISettled)
        JLP.EventBus:On("PRODUCTION_TAILORING_CRAFT_ALL_AUTHORITY_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_CRAFT_ALL_INTERRUPTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_CRAFT_ALL_SETTLEMENT_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_CRAFT_ALL_HANDOFF_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_NATIVE_STEP_TRANSITION_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_BOUNDED_SEQUENCE_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_AUTO_ROUTE_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_AUTO_ROUTE_INTERRUPTION_UPDATED",refreshUISettled)
        JLP.EventBus:On("RESEARCH_AUTO_ROUTE_LINEAGE_UPDATED",refreshUISettled)
        local adaptiveParity=JLP:GetModule("ResearchAdaptivePlannerParity")
        if adaptiveParity and adaptiveParity.Initialize then adaptiveParity:Initialize() end
        local consumerInvalidation=JLP:GetModule("ResearchConsumerInvalidation")
        if consumerInvalidation and consumerInvalidation.Initialize then consumerInvalidation:Initialize() end
        local executionAuthority=JLP:GetModule("ResearchExecutionAuthorityGate")
        if executionAuthority and executionAuthority.Initialize then executionAuthority:Initialize() end
        local nativeExecutionAuthority=JLP:GetModule("ResearchNativeExecutionAuthority")
        if nativeExecutionAuthority and nativeExecutionAuthority.Initialize then nativeExecutionAuthority:Initialize() end
        local tailoringNativeExecutionAuthority=JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
        if tailoringNativeExecutionAuthority and tailoringNativeExecutionAuthority.Initialize then tailoringNativeExecutionAuthority:Initialize() end
        local enchantingNativeExecutionAuthority=JLP:GetModule("ProductionEnchantingNativeExecutionAuthority")
        if enchantingNativeExecutionAuthority and enchantingNativeExecutionAuthority.Initialize then enchantingNativeExecutionAuthority:Initialize() end
        local enchantingNativeSettlement=JLP:GetModule("ProductionEnchantingNativeSettlement")
        if enchantingNativeSettlement and enchantingNativeSettlement.Initialize then enchantingNativeSettlement:Initialize() end
        local enchantingCraftAllAuthority=JLP:GetModule("ProductionEnchantingCraftAllAuthority")
        if enchantingCraftAllAuthority and enchantingCraftAllAuthority.Initialize then enchantingCraftAllAuthority:Initialize() end
        local enchantingCraftAllSession=JLP:GetModule("ProductionEnchantingCraftAllSession")
        if enchantingCraftAllSession and enchantingCraftAllSession.Initialize then enchantingCraftAllSession:Initialize() end
        local enchantingCraftAllOrchestrator=JLP:GetModule("ProductionEnchantingCraftAllOrchestrator")
        if enchantingCraftAllOrchestrator and enchantingCraftAllOrchestrator.Initialize then enchantingCraftAllOrchestrator:Initialize() end
        local tailoringCraftAllAuthority=JLP:GetModule("ProductionTailoringCraftAllAuthority")
        if tailoringCraftAllAuthority and tailoringCraftAllAuthority.Initialize then tailoringCraftAllAuthority:Initialize() end
        local nativeCraftAllAuthority=JLP:GetModule("ResearchNativeCraftAllAuthority")
        if nativeCraftAllAuthority and nativeCraftAllAuthority.Initialize then nativeCraftAllAuthority:Initialize() end
        local nativeCraftAllInterruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
        if nativeCraftAllInterruption and nativeCraftAllInterruption.Initialize then nativeCraftAllInterruption:Initialize() end
        local nativeCraftAllSettlement=JLP:GetModule("ResearchNativeCraftAllSettlement")
        if nativeCraftAllSettlement and nativeCraftAllSettlement.Initialize then nativeCraftAllSettlement:Initialize() end
        local nativeCraftAllHandoff=JLP:GetModule("ResearchNativeCraftAllHandoff")
        if nativeCraftAllHandoff and nativeCraftAllHandoff.Initialize then nativeCraftAllHandoff:Initialize() end
        local nativeSettlement=JLP:GetModule("ResearchNativeExecutionSettlement")
        if nativeSettlement and nativeSettlement.Initialize then nativeSettlement:Initialize() end
        local nativeStepTransition=JLP:GetModule("ResearchNativeStepTransition")
        if nativeStepTransition and nativeStepTransition.Initialize then nativeStepTransition:Initialize() end
        local autoRouteInterruption=JLP:GetModule("ResearchAutoRouteInterruption")
        if autoRouteInterruption and autoRouteInterruption.Initialize then autoRouteInterruption:Initialize() end
        local autoRoute=JLP:GetModule("ResearchAutoRouteOrchestrator")
        if autoRoute and autoRoute.Initialize then autoRoute:Initialize() end
        local tailoringNativeEndurance=JLP:GetModule("ProductionTailoringAutoRouteNativeEndurance")
        if tailoringNativeEndurance and tailoringNativeEndurance.Initialize then tailoringNativeEndurance:Initialize() end
        local tailoringNativeCoverage=JLP:GetModule("ProductionTailoringAutoRouteNativeCoverage")
        if tailoringNativeCoverage and tailoringNativeCoverage.Initialize then tailoringNativeCoverage:Initialize() end
        local boundedSequential=JLP:GetModule("ResearchBoundedSequentialCraft")
        if boundedSequential and boundedSequential.Initialize then boundedSequential:Initialize() end
        JLP:Print("Loaded. Use /jlp ui, /jlp scan or /jlp status.")
    elseif event=="PLAYER_LOGIN" then
        local inventory=JLP:GetModule("Inventory")
        if inventory and inventory.RefreshBagCache then inventory:RefreshBagCache() end
        local professions=JLP:GetModule("ProfessionAPI")
        if professions and professions.GetDetected then professions:GetDetected() end
        local progress=JLP:GetModule("RouteProgress")
        if progress and progress.Initialize then progress:Initialize() end
        local tracker=JLP:GetModule("ProgressTracker")
        if tracker then tracker:Initialize() end
        local transactionLedger=JLP:GetModule("TransactionLedger")
        if transactionLedger and transactionLedger.Initialize then transactionLedger:Initialize() end
        local recipeTelemetry=JLP:GetModule("RecipeTelemetry")
        if recipeTelemetry and recipeTelemetry.Initialize then recipeTelemetry:Initialize() end
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.Initialize then transactionRecovery:Initialize() end
        local eventCorrelation=JLP:GetModule("CraftEventCorrelation")
        if eventCorrelation and eventCorrelation.Initialize then eventCorrelation:Initialize() end
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.Initialize then execution:Initialize() end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.Initialize then workspace:Initialize() end
        local routeSession=JLP:GetModule("RouteSession")
        if routeSession and routeSession.Initialize then routeSession:Initialize() end
        local travelSession=JLP:GetModule("TravelSession")
        if travelSession and travelSession.Initialize then travelSession:Initialize() end
        local travelTransition=JLP:GetModule("TravelTransition")
        if travelTransition and travelTransition.Initialize then travelTransition:Initialize() end
        local routeMarker=JLP:GetModule("RouteMarkerLifecycle")
        if routeMarker and routeMarker.Initialize then routeMarker:Initialize() end
        local destinationHandoff=JLP:GetModule("DestinationHandoff")
        if destinationHandoff and destinationHandoff.Initialize then destinationHandoff:Initialize() end
        local checkpoint=JLP:GetModule("RouteCheckpoint")
        if checkpoint and checkpoint.Initialize then checkpoint:Initialize() end
        local coreTravel=JLP:GetModule("IntegratedTravelEngine")
        if coreTravel and coreTravel.Initialize then coreTravel:Initialize() end
        local continuity=JLP:GetModule("TravelContinuity70450")
        if continuity and continuity.Initialize then continuity:Initialize() end
        local jt=JLP:GetModule("IntegratedJuztTom")
        if jt and jt.Initialize then
            local ok,why=jt:Initialize()
            if ok~=false then jt:CreateUI();jt:Refresh(true)
            elseif JLP.RecordRuntimeError then JLP:RecordRuntimeError("JUZTTOM_INIT",why) end
        end
        if JLP.MinimapButton and JLP.MinimapButton.Create then JLP.MinimapButton:Create() end
        if JLP.DB and JLP.DB.profile and JLP.DB.profile.showWindow and JLP.MainWindow then JLP.MainWindow:Create():Show() end
        refreshUI()
    elseif event=="PLAYER_ENTERING_WORLD" or event=="ZONE_CHANGED" or event=="ZONE_CHANGED_NEW_AREA" or event=="ZONE_CHANGED_INDOORS" or event=="PLAYER_STARTED_MOVING" or event=="PLAYER_STOPPED_MOVING" then
        local unified=JLP:GetModule("IntegratedDestinationOwner")
        if unified and unified.ObserveEvent then unified:ObserveEvent(event) end
        -- Reload/login fires PLAYER_ENTERING_WORLD after SavedVariables are loaded.
        -- Retry briefly if C_Map position has not materialized yet.
        if event=="PLAYER_ENTERING_WORLD" then
            local continuity=JLP:GetModule("TravelContinuity70450")
            if continuity and continuity.TryAutoResume then
                local ok,why=continuity:TryAutoResume()
                if not ok and why=="WAITING_FOR_PLAYER_POSITION" and
                    type(C_Timer)=="table" and type(C_Timer.After)=="function" then
                    C_Timer.After(0.8,function()
                        local service=JLP:GetModule("TravelContinuity70450")
                        if service then service:TryAutoResume() end
                    end)
                    C_Timer.After(2.5,function()
                        local service=JLP:GetModule("TravelContinuity70450")
                        if service then service:TryAutoResume() end
                    end)
                    C_Timer.After(7.0,function()
                        local service=JLP:GetModule("TravelContinuity70450")
                        if service then service:TryAutoResume() end
                    end)
                end
            end
        end
        local travelTransition=JLP:GetModule("TravelTransition")
        if travelTransition and travelTransition.Observe then travelTransition:Observe(event) end
        refreshUISettled()
    elseif event=="PLAYER_LOGOUT" then
        local owner=JLP:GetModule('IntegratedDestinationOwner')
        if owner and owner.ObserveEvent then owner:ObserveEvent(event) end
        local inventory=JLP:GetModule("Inventory")
        if inventory then
            if inventory.RefreshBagCache then inventory:RefreshBagCache() end
            if inventory:IsBankOpen() then inventory:RefreshBankCache({allowContraction=true}) end
        end
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.OnLogout then transactionRecovery:OnLogout() end
        local checkpoint=JLP:GetModule("RouteCheckpoint")
        if checkpoint and checkpoint.OnLogout then checkpoint:OnLogout() end
    elseif event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if event=="GET_ITEM_INFO_RECEIVED" then success = select(2, ...) end
        local knowledge=JLP:GetModule("KnowledgeCache")
        if knowledge and knowledge.CaptureItem and tonumber(itemID) and success ~= false then knowledge:CaptureItem(itemID) end
        -- Item-data callbacks can arrive in large bursts (and exact-instance
        -- tooltips can trigger additional loads).  Rebuilding the entire window
        -- for each callback caused Optional Target to Hide/Show continuously
        -- while the cursor was over a selected item.  Coalesce the burst and
        -- refresh only the active page once after it settles.
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.Observe then transactionRecovery:Observe(event,false) end
        refreshItemDataSettled()
    elseif event=="BANKFRAME_OPENED" then
        local inventory=JLP:GetModule("Inventory")
        if inventory then
            inventory:SetBankOpen(true)
            inventory:RefreshBankCache({allowContraction=false})
            local execution=JLP:GetModule("ExecutionProgress")
            if execution and execution.ObserveAll then execution:ObserveAll(event) end
            local workspace=JLP:GetModule("WorkspaceOrchestrator")
            if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
            -- Forever can finish exposing purchased bank-bag container sizes a
            -- fraction of a frame after BANKFRAME_OPENED. Re-scan once after
            -- the bank has settled so the snapshot/UI uses the final capacity.
            if type(C_Timer)=="table" and type(C_Timer.After)=="function" then
                local function settledBankRefresh(label)
                    return withObservationPass(label,function()
                    if inventory:IsBankOpen() then
                        inventory:RefreshBankCache({allowContraction=true})
                        local execution=JLP:GetModule("ExecutionProgress")
                        if execution and execution.ObserveAll then execution:ObserveAll(label) end
                        local workspace=JLP:GetModule("WorkspaceOrchestrator")
                        if workspace and workspace.ObserveAll then workspace:ObserveAll(label) end
                        refreshUI()
                    end
                    end,true)
                end
                C_Timer.After(0.05,function() settledBankRefresh("BANKFRAME_OPENED_SETTLED") end)
                C_Timer.After(0.20,function() settledBankRefresh("BANKFRAME_OPENED_MATERIALIZED") end)
            end
        end
        refreshUI()
    elseif event=="BANKFRAME_CLOSED" then
        local inventory=JLP:GetModule("Inventory")
        if inventory then inventory:SetBankOpen(false) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="MERCHANT_SHOW" or event=="MERCHANT_UPDATE" then
        local accessEvidence=JLP:GetModule("RecipeAccessEvidence")
        if accessEvidence and accessEvidence.ObserveMerchant then accessEvidence:ObserveMerchant() end
        local materialEvidence=JLP:GetModule("MaterialAcquisitionEvidence")
        if materialEvidence and materialEvidence.ObserveMerchant then materialEvidence:ObserveMerchant() end
        local flow=JLP:GetModule("ExecutionFlow")
        if flow then flow:SetMerchantOpen(true) end
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.ObserveAll then execution:ObserveAll(event) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="MERCHANT_CLOSED" then
        local flow=JLP:GetModule("ExecutionFlow")
        if flow then flow:SetMerchantOpen(false) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="TRAINER_SHOW" then
        local flow=JLP:GetModule("ExecutionFlow")
        if flow then flow:SetTrainerOpen(true) end
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.ObserveAll then execution:ObserveAll(event) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="TRAINER_CLOSED" then
        local flow=JLP:GetModule("ExecutionFlow")
        if flow then flow:SetTrainerOpen(false) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="TRADE_SKILL_SHOW" then
        local journal=JLP:GetModule("CraftObservationJournal70450")
        if journal and journal.OnPanelLifecycle then journal:OnPanelLifecycle(event) end
        local profession=JLP:GetModule("ProfessionAPI")
        -- Panel lifecycle was invalidated before positive ownership admission.
        local progress=JLP:GetModule("RouteProgress")
        if progress then progress:ScanKnownRecipes() end
        local flow=JLP:GetModule("ExecutionFlow")
        if flow then flow:CaptureProfessionWindow() end
        local crafting=JLP:GetModule("Crafting")
        if crafting and crafting.OnTradeSkillUpdate then crafting:OnTradeSkillUpdate(event) end
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.ObserveAll then execution:ObserveAll(event) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="TRADE_SKILL_CLOSE" then
        local journal=JLP:GetModule("CraftObservationJournal70450")
        if journal and journal.OnPanelLifecycle then journal:OnPanelLifecycle(event) end
        local profession=JLP:GetModule("ProfessionAPI")
        if profession and profession.InvalidateOpenProfessionContext then
            profession:InvalidateOpenProfessionContext("TRADE_SKILL_CLOSE")
        end
        local flow=JLP:GetModule("ExecutionFlow")
        if flow then flow:SetProfessionOpen(nil) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="PLAYERBANKSLOTS_CHANGED" or event=="PLAYERBANKBAGSLOTS_CHANGED" or event=="PLAYERREAGENTBANKSLOTS_CHANGED" or event=="BAG_CONTAINER_UPDATE" or event=="PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
        local inventory=JLP:GetModule("Inventory")
        if inventory and inventory:IsBankOpen() then inventory:RefreshBankCache({allowContraction=true}) end
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.ObserveAll then execution:ObserveAll(event) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="AUCTION_HOUSE_SHOW" then
        local scanner=JLP:GetModule("AuctionScanner"); scanner.isAuctionHouseOpen=true
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.ObserveAll then execution:ObserveAll(event) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="AUCTION_HOUSE_CLOSED" then
        local scanner=JLP:GetModule("AuctionScanner"); scanner.isAuctionHouseOpen=false
        if scanner and scanner.scanInProgress and scanner.CancelScan then scanner:CancelScan("AUCTION_HOUSE_CLOSED") end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        refreshUI()
    elseif event=="REPLICATE_ITEM_LIST_UPDATE" then
        local scanner=JLP:GetModule("AuctionScanner")
        local scanGuard=JLP:GetModule("AuctionScanGuard")
        -- Reject a late event before the protected scanner can persist it.
        if scanGuard then scanGuard:ExpirePendingScan() end
        if scanner.scanInProgress then
            local ok,result=scanner:ProcessReplicateList()
            if ok and result and result.pending then
                JLP:Print(string.format("AH scan: processing %d auctions incrementally; previous snapshot retained until completion.",result.auctionCount or 0))
            elseif ok then JLP:Print(string.format("AH scan complete: %d auctions, %d item types. Snapshot replaced successfully.",result.auctionCount or 0,result.itemCount or 0))
            else JLP:Print(tostring(result)) end
        end
        refreshUI()
    elseif event=="TRADE_SKILL_CRAFT_BEGIN" then
        local eventCorrelation=JLP:GetModule("CraftEventCorrelation")
        local ticket=eventCorrelation and eventCorrelation:BeginEvent(event,...)
        local journal=JLP:GetModule("CraftObservationJournal70450")
        if journal and journal.OnCraftBegin then journal:OnCraftBegin((...)) end
        local crafting=JLP:GetModule("Crafting")
        if crafting and crafting.OnTradeSkillCraftBegin then crafting:OnTradeSkillCraftBegin(...) end
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.OnTradeSkillCraftBegin then transactionRecovery:OnTradeSkillCraftBegin(...) end
        if ticket then eventCorrelation:EndEvent(ticket) end
    elseif event=="TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        local eventCorrelation=JLP:GetModule("CraftEventCorrelation")
        local ticket=eventCorrelation and eventCorrelation:BeginEvent(event,...)
        -- Strictly observational: correlate a player cast and the Blizzard
        -- result, without changing the original authoritative crafting path.
        local observation=JLP:GetModule("CraftObservationJournal70374")
        if observation then observation:OnCraftedResult((...)) end
        local currentObservation=JLP:GetModule("CraftObservationJournal70450")
        if currentObservation then currentObservation:OnCraftedResult((...)) end
        local crafting=JLP:GetModule("Crafting")
        if crafting and crafting.OnTradeSkillItemCraftedResult then crafting:OnTradeSkillItemCraftedResult(...) end
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.OnTradeSkillItemCraftedResult then transactionRecovery:OnTradeSkillItemCraftedResult(...) end
        if ticket then eventCorrelation:EndEvent(ticket) end
    elseif event=="REPLACE_ENCHANT" or event=="BIND_ENCHANT" or event=="TRADE_REPLACE_ENCHANT" or event=="TRADE_POTENTIAL_BIND_ENCHANT" then
        -- Blizzard's corresponding accept functions are protected and require a
        -- hardware-secure click. Never call them from addon execution. Track the
        -- native confirmation instead so the guide remains transaction-correct
        -- while the Blizzard popup is awaiting the player's confirmation.
        local crafting=JLP:GetModule("Crafting")
        if crafting and crafting.OnEnchantConfirmationRequired then crafting:OnEnchantConfirmationRequired(event,...) end
        refreshUI()
    elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
        local eventCorrelation=JLP:GetModule("CraftEventCorrelation")
        local ticket=eventCorrelation and eventCorrelation:BeginEvent(event,...)
        local crafting=JLP:GetModule("Crafting")
        if crafting and crafting.OnSpellcastFailed then crafting:OnSpellcastFailed(event,...) end
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.OnSpellcastFailed then transactionRecovery:OnSpellcastFailed(event,...) end
        if ticket then eventCorrelation:EndEvent(ticket) end
    elseif event=="UNIT_SPELLCAST_SENT" then
        local eventCorrelation=JLP:GetModule("CraftEventCorrelation")
        local ticket=eventCorrelation and eventCorrelation:BeginEvent(event,...)
        -- Capture the genuine client cast GUID before a possible /reload.
        -- This event is observational and never authorizes a native call.
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.OnSpellcastSent then
            transactionRecovery:OnSpellcastSent(...)
        end
        if ticket then eventCorrelation:EndEvent(ticket) end
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
        local eventCorrelation=JLP:GetModule("CraftEventCorrelation")
        local ticket=eventCorrelation and eventCorrelation:BeginEvent(event,...)
        local unitTarget,castGUID,spellID=...
        local completed=false
        local crafting=JLP:GetModule("Crafting")
        if crafting and crafting.OnSpellcastSucceeded then completed=crafting:OnSpellcastSucceeded(unitTarget,castGUID,spellID) and true or false end
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.OnSpellcastSucceeded then transactionRecovery:OnSpellcastSucceeded(unitTarget,castGUID,spellID) end
        if unitTarget=="player" then
            local observation=JLP:GetModule("CraftObservationJournal70374")
            if observation then observation:OnSpellcastSucceeded(unitTarget,castGUID,spellID) end
            local currentObservation=JLP:GetModule("CraftObservationJournal70450")
            if currentObservation then currentObservation:OnSpellcastSucceeded(unitTarget,castGUID,spellID) end
            local tracker=JLP:GetModule("ProgressTracker")
            local observed=tracker and tracker:RecordSpellcast(spellID,castGUID)
            if observed and not completed then refreshUI() end
        end
        if ticket then eventCorrelation:EndEvent(ticket) end
    elseif event=="PLAYER_MONEY" then
        -- Cash changes invalidate affordability shown by material/acquisition
        -- views even when no bag or profession event accompanies the change.
        refreshUISettled()
    elseif event=="SKILL_LINES_CHANGED" or event=="TRADE_SKILL_LIST_UPDATE" or event=="TRADE_SKILL_UPDATE" or event=="CHAT_MSG_SKILL" or event=="BAG_UPDATE_DELAYED" or event=="PLAYER_LEVEL_UP" or event=="NEW_RECIPE_LEARNED" or event=="LEARNED_SPELL_IN_TAB" then
        local inventory=JLP:GetModule("Inventory")
        if event=="BAG_UPDATE_DELAYED" and inventory then
            if inventory.RefreshBagCache then inventory:RefreshBagCache() end
            if inventory:IsBankOpen() then inventory:RefreshBankCache({allowContraction=true}) end
            local tracker=JLP:GetModule("ProgressTracker")
            if tracker and tracker.ReconcileMaterials then tracker:ReconcileMaterials() end
        end
        if event=="TRADE_SKILL_LIST_UPDATE" or event=="TRADE_SKILL_UPDATE" or event=="NEW_RECIPE_LEARNED" then
            local progress=JLP:GetModule("RouteProgress")
            if progress then progress:ScanKnownRecipes() end
            local flow=JLP:GetModule("ExecutionFlow")
            if flow then flow:CaptureProfessionWindow() end
            local crafting=JLP:GetModule("Crafting")
            if crafting and crafting.OnTradeSkillUpdate then crafting:OnTradeSkillUpdate(event) end
        end
        if event=="SKILL_LINES_CHANGED" or event=="TRADE_SKILL_UPDATE" then
            local journal=JLP:GetModule("CraftObservationJournal70450")
            if journal and journal.OnSkillUpdate then journal:OnSkillUpdate(event) end
        elseif event=="CHAT_MSG_SKILL" or event=="TRADE_SKILL_LIST_UPDATE" then
            local journal=JLP:GetModule("CraftObservationJournal70450")
            if journal and journal.ObserveAuxiliaryEvent then journal:ObserveAuxiliaryEvent(event) end
        end
        if event~="BAG_UPDATE_DELAYED" then
            local tracker=JLP:GetModule("ProgressTracker")
            if tracker then tracker:Capture(event,false) end
        end
        local crafting=JLP:GetModule("Crafting")
        if crafting and crafting.OnProgressUpdate then crafting:OnProgressUpdate(event) end
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        if transactionRecovery and transactionRecovery.Observe then transactionRecovery:Observe(event,false) end
        local execution=JLP:GetModule("ExecutionProgress")
        if execution and execution.ObserveAll then execution:ObserveAll(event) end
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        if workspace and workspace.ObserveAll then workspace:ObserveAll(event) end
        local consumerInvalidation=JLP:GetModule("ResearchConsumerInvalidation")
        if consumerInvalidation and consumerInvalidation.ObserveTracked then consumerInvalidation:ObserveTracked(event) end
        local executionAuthority=JLP:GetModule("ResearchExecutionAuthorityGate")
        if executionAuthority and executionAuthority.Invalidate then executionAuthority:Invalidate(event) end
        local annoraOwner=JLP:GetModule("IntegratedDestinationOwner")
        if annoraOwner and annoraOwner.RevalidateAnnoraApproach then annoraOwner:RevalidateAnnoraApproach() end
        if annoraOwner and annoraOwner.RevalidateRecipeAcquisition then annoraOwner:RevalidateRecipeAcquisition() end
        refreshUISettled()
    end
end
frame:SetScript("OnEvent",function(self,event,...)
    local args={n=select("#",...),...}
    return withObservationPass(event,function()
        local api=JLP:GetModule("ProfessionAPI")
        if api and api.ObserveOwnershipEvent then
            distributeOwnership(api:ObserveOwnershipEvent(event,distributeOwnership))
        end
        if JLP.MarkObservationsDirty then JLP:MarkObservationsDirty(event) end
        return observeEvent(self,event,(unpack or table.unpack)(args,1,args.n))
    end,true)
end)

SLASH_JUZTLEVELPROFESSIONS1="/jlp"
-- One event/update owner. Transport continues to use world-verified JLP
-- geometry; only the original JuztTom renderer draws the arrow.
local tomElapsed,travelElapsed=0,0
frame:SetScript("OnUpdate",function(_,elapsed)
    local dt=type(elapsed)=="number" and math.max(0,elapsed) or 0
    tomElapsed=tomElapsed+dt
    travelElapsed=travelElapsed+dt
    if travelElapsed>=0.75 then
        travelElapsed=0
        local owner=JLP:GetModule("IntegratedDestinationOwner")
        if owner and owner.RevalidateAnnoraApproach then owner:RevalidateAnnoraApproach() end
        if owner and owner.RevalidateRecipeAcquisition then owner:RevalidateRecipeAcquisition() end
        if owner and owner.active then
            -- A zone event can precede C_Map's new position sample. Retry
            -- only this existing qualified destination, never select a new one.
            if owner.AttemptLocalRouteAfterMapChange then
                local ok,err=pcall(owner.AttemptLocalRouteAfterMapChange,owner)
                if not ok and JLP.RecordRuntimeError then JLP:RecordRuntimeError("CITY_INGRESS_REPLAN",err) end
            end
            local travel=JLP:GetModule("IntegratedTravelEngine")
            if travel and travel.ObserveLive then
                local ok,err=pcall(travel.ObserveLive,travel,"PERIODIC_NATIVE_OBSERVATION")
                if not ok and JLP.RecordRuntimeError then JLP:RecordRuntimeError("TRAVEL_PERIODIC",err) end
            end
        end
    end
    local jt=JLP:GetModule("IntegratedJuztTom")
    if jt and jt.profile then
        if jt.UpdateArrowMotion then
            local ok,err=pcall(jt.UpdateArrowMotion,jt,dt)
            if not ok and JLP.RecordRuntimeError then JLP:RecordRuntimeError("JUZTTOM_MOTION",err) end
        end
        if tomElapsed>=0.30 then
            tomElapsed=tomElapsed%0.30
            local ok,err=pcall(jt.Refresh,jt,false)
            if not ok and JLP.RecordRuntimeError then JLP:RecordRuntimeError("JUZTTOM_REFRESH",err) end
        end
    else tomElapsed=0 end
end)

SLASH_JLPINTEGRATEDTOM1="/jt"
SLASH_JLPINTEGRATEDTOM2="/juzttom"
SlashCmdList.JLPINTEGRATEDTOM=function(raw)
    local jt=JLP:GetModule("IntegratedJuztTom")
    if not jt then return end
    local words={}
    for token in tostring(raw or ""):gmatch("%S+") do words[#words+1]=token end
    local command=tostring(words[1] or ""):lower()
    if command=="goto" then
        local x,y=tonumber(words[3]),tonumber(words[4])
        local ok,reason=jt:SetWaypoint(tonumber(words[2]),x and x/100,y and y/100,"Manual waypoint")
        JLP:Print(ok and "JuztTom manual waypoint selected" or (reason or "Invalid manual waypoint"))
    elseif command=="clear" then jt:ClearWaypoint()
    elseif command=="next" or command=="skip" then jt:Advance()
    elseif command=="gather" or command=="gathering" then jt:SetMode("GATHERING")
    elseif command=="step" or command=="current" then jt:SetMode("CURRENT_STEP")
    elseif command=="style" then
        local requested=({["1"]="classic",["2"]="updated",["3"]="clean"})[words[2]] or words[2]
        if not jt:SetArrowStyle(requested) then JLP:Print("Use /jt style 1, 2 or 3") end
    elseif command=="arrow" then jt.profile.arrowShown=not jt.profile.arrowShown;jt:Refresh(true)
    elseif command=="lock" then jt.profile.locked=not jt.profile.locked;jt:Refresh(true)
    elseif command=="smooth" then jt.profile.smoothMotion=not jt.profile.smoothMotion;jt:Refresh(true)
    elseif command=="legacy" or command=="compact" then jt:TogglePanel()
    elseif command=="help" then
        JLP:Print("/jt opens menu; /jt settings opens settings; /jt goto mapID X% Y%; /jt next; /jt clear; /jt demo; /jt status")
    elseif command=="status" then
        local status=jt:GetState();JLP:Print("JuztTom: "..tostring(status.status).." / "..tostring(status.target and status.target.title or "No target"))
    elseif command=="display" or command=="design" or command=="menu" or command=="" then jt:OpenPage("Navigation")
    elseif command=="settings" then jt:OpenSettings()
    elseif command=="nav" then jt:OpenPage("Navigation")
    elseif command=="demo" then
        if words[2]=="off" then jt:StopDemo() else jt:StartDemo() end
    elseif command=="travel" then
        local engine=JLP:GetModule("IntegratedTravelEngine")
        local g=engine and engine.GetGuidance and engine:GetGuidance()
        JLP:Print("JuztTravel: "..tostring(g and g.phase or "INACTIVE").." / "..tostring(g and g.instruction or "No active journey"))
    elseif command=="travelauto" then
        JLP:Print("Current Step travel is managed by JuztLevel's verified destination owner; separate auto-travel override is not available.")
    else jt:OpenPage("Navigation") end
end

SlashCmdList.JUZTLEVELPROFESSIONS=function(msg)
    msg=string.lower((msg or ""):match("^%s*(.-)%s*$"))
    if msg=="" or msg=="ui" then
        JLP.MainWindow:Toggle()
    elseif msg=="perfaudit70450" then
        local audit=JLP:GetModule("PerformanceAudit70450")
        if audit and audit.Print then audit:Print()
        else JLP:Print("Performance audit unavailable") end
    elseif msg=="uiaudit70450" then
        local audit=JLP:GetModule("UIPresentationAudit70450")
        if audit then audit:Print() else JLP:Print("UI diagnostic unavailable") end
    elseif msg=="navqa" or msg:match("^navqa%s+") then
        local qa=JLP:GetModule("NavigationMapRouteAudit")
        local scope=msg:match("^navqa%s+(%S+)") or "all"
        if not qa then JLP:Print("Navigation QA module unavailable")
        else
            local ok,reason=qa:Print(scope)
            if not ok then JLP:Print("Navigation QA: "..tostring(reason)) end
        end
    elseif msg=="cataloguequalification" then
        local checker=JLP:GetModule("ProfessionsCatalogueQualification")
        if not checker then JLP:Print("Catalogue admission verifier unavailable")
        else
            local audit=checker:AssessInstalled()
            JLP:Print("70374 static catalogue qualification: "..audit.status..
                " / approved="..audit.approved.." / rejected="..audit.rejected..
                " / declared="..audit.declared.."; native dispatch NOT authorized")
            if audit.reason then JLP:Print("Qualification gate: "..audit.reason) end
            for reason,n in pairs(audit.rejectionReasons or {}) do
                JLP:Print("Rejected "..n..": "..reason)
            end
        end
    elseif msg=="craftingunlock" or msg:match("^craftingunlock%s+") then
        -- Explicit, user-requested opt-in for feature switches that used to
        -- require several slash commands. No native call is made here.
        local arg=msg:match("^craftingunlock%s*(%S*)") or ""
        local modules={
            {"Tailoring consumer", "ProductionTailoringAuthorityAdapter"},
            {"Enchanting consumer", "ProductionEnchantingAuthorityAdapter"},
            {"Execution eligibility", "ResearchExecutionAuthorityGate"},
            {"Tailoring native", "ProductionTailoringNativeExecutionAuthority"},
            {"Enchant One native", "ProductionEnchantingNativeExecutionAuthority"},
            {"Tailoring Craft All/X", "ProductionTailoringCraftAllAuthority"},
        }
        if arg=="on" then
            local success=true
            for _,entry in ipairs(modules) do
                local module=JLP:GetModule(entry[2])
                local ok,state=false,"module unavailable"
                if module and module.SetFeatureEnabled then ok,state=module:SetFeatureEnabled(true) end
                JLP:Print(entry[1]..": "..tostring(state))
                if not ok then success=false; break end
            end
            JLP:Print(success and "Feature preferences updated. Native Craft All/X requires individual recipe readiness, valid source rights, ledger/recovery, and an explicit Guide click for each ordinal." or "Some feature gates were not enabled; inspect the message above.")
        else
            JLP:Print("Use /jlp craftingunlock on to explicitly enable guarded Tailoring Craft All/X and Enchant One feature switches. Current per-feature state:")
            for _,entry in ipairs(modules) do
                local module=JLP:GetModule(entry[2])
                JLP:Print(entry[1]..": "..tostring(module and module.IsFeatureEnabled and module:IsFeatureEnabled() or false))
            end
        end
    elseif msg=="batchready70450" or msg:match("^batchready70450%s+") then
        local audit=JLP:GetModule("CraftBatchReadiness70450")
        local key,spell,count=msg:match("^batchready70450%s+(%a+)%s+(%d+)%s+(%d+)$")
        if not key then key,spell=msg:match("^batchready70450%s+(%a+)%s+(%d+)$") end
        if not audit then JLP:Print("Batch 70450 readiness audit unavailable")
        elseif key and spell then JLP:Print(audit:Summary(key:upper(),tonumber(spell),count and tonumber(count) or 1))
        else JLP:Print("Usage: /jlp batchready70450 TAILORING SPELLID [COUNT] (read-only)") end
    elseif msg=="sourcequalification70450" or msg:match("^sourcequalification70450%s+") then
        local checker=JLP:GetModule("Build70450ProductionQualification")
        if not checker then JLP:Print("70450 source qualification module unavailable")
        else
            local profession,spell=msg:match("^sourcequalification70450%s+(%w+)%s+(%d+)$")
            if profession and spell then
                local receipt=checker:AssessRecipe(profession:upper(),tonumber(spell),70450)
                JLP:Print("70450 "..tostring(receipt.professionKey).." #"..tostring(receipt.spellID)..
                    ": "..receipt.state.." / "..tostring(receipt.reason)..
                    "; native execution remains independently gated")
            elseif msg=="sourcequalification70450" then
                local audit=checker:AuditInstalled()
                JLP:Print("70450 qualification: "..audit.status.." / reviewed="..audit.declared..
                    " / source-qualified="..audit.qualified.." / rejected="..audit.rejected..
                    "; production/native dispatch NOT granted")
                for reason,n in pairs(audit.rejectionReasons or {}) do
                    JLP:Print("Rejected "..n..": "..reason)
                end
            else JLP:Print("Usage: /jlp sourcequalification70450 [PROFESSION SPELLID]") end
        end
    elseif msg=="economy70450" or msg:match("^economy70450%s+") or
        msg=="economystep70450" or msg:match("^economystep70450%s+") then
        local cmd=JLP:GetModule("EconomyCommand70450")
        if cmd then cmd:Handle(msg) else JLP:Print("70450 economy integration unavailable") end
    elseif msg=="materialsources70450" or msg:match("^materialsources70450%s+") then
        local cmd=JLP:GetModule("MaterialsSourcesCommand70450")
        if cmd then cmd:Handle(msg) else JLP:Print("Materials & Sources 70450 unavailable") end
    elseif msg=="sourcecover70450" or msg=="source70450" or msg=="sourcepage70450" or
        msg=="sourcenpc70450" or msg=="sourceobserve70450" or
        msg:match("^source70450%s+") or msg:match("^sourcepage70450%s+") or
        msg:match("^sourcenpc70450%s+") or msg:match("^sourceobserve70450%s+") then
        local command=JLP:GetModule("RecipeAcquisitionCommand70450")
        if command then command:Handle(msg) else JLP:Print("Recipe acquisition 70450 command unavailable") end
    elseif msg=="itemcover70450" or msg=="itemmeta70450" or msg=="itemaudit70450" or msg=="itemgaps70450" or msg=="itemlinks70450" or msg=="itemissues70450" or msg=="itemscan70450" or
        msg:match("^itemmeta70450%s+") or msg:match("^itemaudit70450%s+") or msg:match("^itemgaps70450%s+%d+$") or msg=="itemprobe70450" or msg:match("^itemprobe70450%s+") or msg:match("^itemlinks70450%s+") or msg:match("^itemissues70450%s+") or msg:match("^itemscan70450%s+") then
        local command=JLP:GetModule("ItemMetadataCommand70450")
        if command then command:Handle(msg) else JLP:Print("Item metadata 70450 command unavailable") end
    elseif msg=="difficultycover70450" or msg=="difficulty70450" or msg=="difficultyissues70450" or
        msg=="difficultylive70450" or msg:match("^difficulty70450%s+") or
        msg:match("^difficultylive70450%s+") or msg:match("^difficultyissues70450%s+") then
        local command=JLP:GetModule("SkillDifficultyCommand70450")
        if command then command:Handle(msg) else JLP:Print("Skill difficulty 70450 command unavailable") end
    elseif msg=="yieldcover70450" or msg=="yield70450" or msg=="yieldlive70450" or msg=="yieldissues70450" or
        msg:match("^yield70450%s+") or msg:match("^yieldlive70450%s+") or msg:match("^yieldissues70450%s+") then
        local command=JLP:GetModule("CraftOutputCommand70450")
        if command then command:Handle(msg) else JLP:Print("Output 70450 command unavailable") end
    elseif msg=="recipecoverage70450" or msg=="recipemissing70450" or
        msg=="recipeaudit70450" or msg=="recipeissues70450" or msg:match("^recipeissues70450%s+") or
        msg:match("^recipeproof70450%s+") or msg=="recipeproof70450" or
        msg:match("^recipe70450%s+") or msg:match("^recipes70450%s+") or
        msg=="recipe70450" or msg=="recipes70450" then
        local command=JLP:GetModule("RecipeCommand70450")
        if command then command:Handle(msg) else JLP:Print("Recipe 70450 command unavailable") end
    elseif msg:match("^datacheck70374%s+") or msg:match("^recipecheck70374%s+") or
        msg:match("^progresscheck70374%s+") or
        msg=="datacheck70374" or msg=="recipecheck70374" or msg=="progresscheck70374" or
        msg:match("^econ%s+") or msg:match("^mats%s+") or msg:match("^progress70374%s+") or msg:match("^econplan70374%s+") or
        msg:match("^profit70374%s+") or
        msg=="econ" or msg=="mats" or msg=="progress70374" or
        msg=="econplan70374" or msg=="profit70374" then
        local command=JLP:GetModule("EconomyCommand70374")
        if command then command:Handle(msg) else JLP:Print("Economy command module unavailable") end
    elseif msg=="scan" then
        local guard=JLP:GetModule("AuctionScanGuard")
        local ok,reason=false,"Auction scan guard unavailable."
        if guard then ok,reason=guard:BeginManualScan() end
        JLP:Print(reason or (ok and "Auction scan requested." or "Auction scan unavailable."))
    elseif msg=="gatherstatus70450" or msg=="gatherstop70450" or
        msg:match("^gatherfollow70450%s+") or msg=="gatherfollow70450" or
        msg=="gathertick70450" then
        local follow=JLP:GetModule("GatheringWaypointProgress70450")
        if not follow then JLP:Print("Gathering 70450 waypoint module unavailable")
        elseif msg=="gatherstop70450" then
            local _,why=follow:Stop("STOPPED_BY_USER")
            JLP:Print("Gathering navigation: "..tostring(why))
        elseif msg=="gathertick70450" then
            -- Manual diagnostic only; never triggers player movement.
            local _,why=follow:Tick()
            JLP:Print("Gathering waypoint observation: "..tostring(why))
        elseif msg=="gatherstatus70450" then
            local current=follow:GetStatus()
            JLP:Print("Gathering waypoint: "..tostring(current.status)..
                " / "..tostring(current.professionKey or "NONE")..
                " / stop "..tostring(current.index or 0).."/"..tostring(current.stopCount or 0)..
                " / walkability UNVERIFIED")
        else
            local prof,map,mode=msg:match("^gatherfollow70450%s+(%a+)%s+(%d+)%s*(%a*)$")
            if not prof or (mode~="" and mode~="advisory" and mode~="waypoint") then
                JLP:Print("Usage: /jlp gatherfollow70450 HERBALISM|MINING MAPID [advisory|waypoint]. Waypoint mode is explicit consent; never overwrites another user waypoint.")
            else
                local ok,why=follow:Begin(tonumber(map),prof:upper(),mode=="waypoint")
                JLP:Print("Gathering route follow: "..tostring(why)..
                    (ok and " (geometry only, not walkability)" or ""))
            end
        end
    elseif msg=="gatheringqa" or msg:match("^gatheringqa%s+") then
        local acceptance=JLP:GetModule("GatheringClientAcceptance")
        local sub=msg:match("^gatheringqa%s+(%S+)")
        if not acceptance then JLP:Print("Gathering QA unavailable")
        elseif sub=="start" then
            local ok,reason=acceptance:StartFPS()
            JLP:Print(ok and "60-second gathering FPS measurement started. Use /jlp gatheringqa to inspect." or reason)
        elseif sub=="stop" then
            local complete,result=acceptance:StopFPS()
            if type(result)=="table" then
                JLP:Print("FPS "..result.state.." ("..tostring(result.sampleCount).." samples, "..
                 tostring(result.durationSeconds).."s); average "..tostring(result.average or "unavailable")..
                 ", min "..tostring(result.minimum or "unavailable")..
                 ", max "..tostring(result.maximum or "unavailable"))
            else JLP:Print(result) end
        else JLP:Print(acceptance:GetSummary()) end
    elseif msg:match("^miningsmelt") then
        local raw=msg:match("^miningsmelt%s+(%d+)")
        local skill=tonumber(raw)
        local api=JLP:GetModule("ProfessionAPI")
        local mining=api and api.Get and api:Get("MINING")
        skill=skill or mining and tonumber(mining.skill)
        local resolver=JLP:GetModule("MiningSmeltingProgression")
        local result=resolver and resolver:Evaluate(skill)
        JLP:Print(result and result.explanation or "Mining Smelting unavailable")
    elseif msg=="status" then
        local api=JLP:GetModule("ProfessionAPI"); local scanner=JLP:GetModule("AuctionScanner")
        JLP:Print(api:GetSummary())
        JLP:Print(scanner:GetStatusText())
    elseif msg=="cache" then
        local knowledge=JLP:GetModule("KnowledgeCache")
        local inventory=JLP:GetModule("Inventory")
        JLP:Print(knowledge and knowledge:GetSummary() or "Persistent knowledge cache unavailable.")
        JLP:Print(inventory and inventory:GetCacheSummary() or "Persistent inventory cache unavailable.")
    elseif msg=="progress" then
        local tracker=JLP:GetModule("ProgressTracker")
        JLP:Print(tracker and tracker:GetSummary() or "Progress tracker unavailable.")
    elseif msg=="ready" then
        local readiness=JLP:GetModule("CraftReadiness")
        JLP:Print(readiness and readiness:GetSummary() or "Craft readiness unavailable.")
    elseif msg=="state" then
        local state=JLP:GetModule("ProfessionState")
        JLP:Print(state and state:GetSummary() or "Profession state machine unavailable.")
    elseif msg=="execution" then
        local execution=JLP:GetModule("ExecutionProgress")
        JLP:Print(execution and execution:GetSummary() or "Stateful execution progress unavailable.")
    elseif msg=="workspace" or msg=="orchestrate" then
        local workspace=JLP:GetModule("WorkspaceOrchestrator")
        JLP:Print(workspace and workspace:GetSummary() or "Workspace orchestration unavailable.")
    elseif msg=="next" or msg=="nextbest" then
        local nextBest=JLP:GetModule("NextBestAction")
        JLP:Print(nextBest and nextBest:GetSummary() or "Next Best Action unavailable.")
    elseif msg=="guidescope" or msg=="professionscope" then
        local scope=JLP:GetModule("ProfessionGuideScope")
        JLP:Print(scope and scope:GetSummary() or "Profession Guide scope unavailable.")
    elseif msg=="cta" or msg=="context" then
        local context=JLP:GetModule("ContextAction")
        JLP:Print(context and context:GetSummary() or "Contextual action unavailable.")
    elseif msg=="batch" or msg=="routesession" then
        local routeSession=JLP:GetModule("RouteSession")
        JLP:Print(routeSession and routeSession:GetSummary() or "Workspace route session unavailable.")
    elseif msg=="travelchain" or msg=="travelsession" then
        local travelSession=JLP:GetModule("TravelSession")
        JLP:Print(travelSession and travelSession:GetSummary() or "Travel session unavailable.")
    elseif msg=="transport70450" or msg:match("^transport70450%s+") then
        local networkAudit=JLP:GetModule("TransportNetworkAudit70450")
        if not networkAudit then JLP:Print("70450 transport source audit unavailable")
        else
            local id=msg:match("^transport70450%s+(%w+)$")
            if id then
                local row,why
                if id:match("^ST%d%d%d$") then row,why=networkAudit:GetPlace(id)
                elseif id:match("^R%d%d%d$") then row,why=networkAudit:GetRoute(id)
                else why="INVALID_SOURCE_ID" end
                if not row then JLP:Print("Transport "..id..": "..tostring(why))
                elseif row.fromST then
                    JLP:Print("70450 "..id.." "..row.fromST.." -> "..row.toST..
                     " / "..row.mode.." / faction="..row.faction..
                     " / class="..tostring(row.requiresClass or "ANY")..
                     " / native boarding NOT VERIFIED")
                else
                    JLP:Print("70450 "..id.." "..row.name.." / "..row.zone..
                     " / UiMap="..tostring(row.mapID or "UNKNOWN")..
                     " / "..row.mapEvidence.."; coordinates from owner workbook")
                end
            else
                local a=networkAudit:Audit()
                JLP:Print("70450 Transport: "..a.status.." / stops="..a.expectedPlaces..
                  " / routes="..a.expectedRoutes.." (flight="..a.expectedFlightRoutes..
                  ", zeppelin="..a.expectedZeppelins..", boat="..a.expectedBoats..")")
                JLP:Print("Workbook header claims 36 flight masters; 35 identified rows; live NPC/boarding NOT VERIFIED. Use /jlp transport70450 ST022 or R108")
            end
        end
    elseif msg=="travel70450" or msg=="travelstatus70450" then
        local continuity=JLP:GetModule("TravelContinuity70450")
        local engine=JLP:GetModule("IntegratedTravelEngine")
        local snapshot=engine and engine.GetGuidance and engine:GetGuidance() or nil
        JLP:Print(continuity and continuity:GetSummary() or "Travel continuity unavailable")
        JLP:Print("Current guidance: "..tostring(snapshot and snapshot.phase or "UNKNOWN")..
            " · step "..tostring(snapshot and snapshot.index or "?").."/"..tostring(snapshot and snapshot.total or "?"))
    elseif msg=="travelresume70450" then
        local continuity=JLP:GetModule("TravelContinuity70450")
        local ok,why=continuity and continuity:ResumeManual()
        JLP:Print("Manual travel checkpoint: "..tostring(ok and "REBOUND" or "NOT RESUMED").." / "..tostring(why))
    elseif msg=="travelconfirm70450" then
        local travel=JLP:GetModule("IntegratedTravelEngine")
        local ok,reason=travel and travel:ConfirmSameMapArrival()
        JLP:Print("Manual transfer guidance: "..tostring(ok and "ADVANCED" or "NOT VERIFIED").." / "..tostring(reason))
    elseif msg=="travelclear70450" then
        local continuity=JLP:GetModule("TravelContinuity70450")
        local ok,why=continuity and continuity:Clear("EXPLICIT_USER_CLEAR")
        JLP:Print("Travel checkpoint: "..tostring(ok and "CLEARED" or "UNAVAILABLE").." / "..tostring(why))
    elseif msg=="journey" or msg=="transition" then
        local travelTransition=JLP:GetModule("TravelTransition")
        JLP:Print(travelTransition and travelTransition:GetSummary() or "Travel transition unavailable.")
    elseif msg=="confidence" or msg=="proximity" then
        local sourceConfidence=JLP:GetModule("SourceConfidence")
        JLP:Print(sourceConfidence and sourceConfidence:GetSummary() or "Source confidence unavailable.")
    elseif msg=="navigation" or msg=="localnav" then
        local navigationGuidance=JLP:GetModule("NavigationGuidance")
        JLP:Print(navigationGuidance and navigationGuidance:GetSummary() or "Local navigation guidance unavailable.")
    elseif msg=="marker" or msg=="markerstate" then
        local routeMarker=JLP:GetModule("RouteMarkerLifecycle")
        JLP:Print(routeMarker and routeMarker:GetSummary() or "Route marker lifecycle unavailable.")
    elseif msg=="handoff" or msg=="destination" then
        local destinationHandoff=JLP:GetModule("DestinationHandoff")
        JLP:Print(destinationHandoff and destinationHandoff:GetSummary() or "Destination handoff unavailable.")
    elseif msg=="recovery" or msg=="checkpoint" then
        local checkpoint=JLP:GetModule("RouteCheckpoint")
        JLP:Print(checkpoint and checkpoint:GetSummary() or "Route checkpoint recovery unavailable.")
    elseif msg=="craftstate70374" or msg:match("^craftstate70374%s+") then
        local key,spell,crafts=msg:match("^craftstate70374%s+(%S+)%s*(%S*)%s*(%S*)")
        local api=JLP:GetModule("CraftingIntegration70374")
        JLP:Print(api and api:GetSummary(key,tonumber(spell),tonumber(crafts)) or "M5 crafting integration unavailable.")
    elseif msg=="crafthistory70450" or msg:match("^crafthistory70450%s+") then
        local key=msg:match("^crafthistory70450%s+(%S+)")
        local history=JLP:GetModule("CraftHistoryIntegration70374")
        JLP:Print(history and history:GetSummary(key) or "Unified craft history unavailable.")
    elseif msg=="craftobs70450" or msg:match("^craftobs70450%s+") then
        local key=msg:match("^craftobs70450%s+(%S+)")
        local journal=JLP:GetModule("CraftObservationJournal70450")
        JLP:Print(journal and journal:GetSummary(key) or "70450 passive crafting observations unavailable.")
    elseif msg=="crafthistory70374" or msg:match("^crafthistory70374%s+") then
        local key=msg:match("^crafthistory70374%s+(%S+)")
        local journal=JLP:GetModule("CraftHistoryIntegration70374")
        JLP:Print(journal and journal:GetSummary(key) or "M5 craft history unavailable.")
    elseif msg=="tracker70374" or msg:match("^tracker70374%s+") then
        local key=msg:match("^tracker70374%s+(%S+)")
        local tracker=JLP.ObjectiveStepTracker
        if not tracker then JLP:Print("M5 tracker unavailable.")
        else
            local model,why=tracker:BuildModel(key or (JLP.DB and JLP.DB.profile and JLP.DB.profile.guideMode))
            JLP:Print(model and ("M5 tracker: "..tostring(model.key).." - "..tostring(model.recipe).." - "..tostring(model.description or model.remainingCrafts or "read-only")) or ("M5 tracker: "..tostring(why)))
        end
    elseif msg=="history" or msg=="routehistory" then
        local checkpoint=JLP:GetModule("RouteCheckpoint")
        JLP:Print(checkpoint and checkpoint:GetHistorySummary() or "Profession-scoped route history unavailable.")
    elseif msg=="transaction" or msg=="txrecovery" then
        local transactionRecovery=JLP:GetModule("TransactionRecovery")
        JLP:Print(transactionRecovery and transactionRecovery:GetSummary() or "Craft/Enchant transaction recovery unavailable.")
    elseif msg=="ledger" or msg=="txledger" then
        local transactionLedger=JLP:GetModule("TransactionLedger")
        JLP:Print(transactionLedger and transactionLedger:GetSummary() or "Craft/Enchant transaction ledger unavailable.")
    elseif msg=="nativedispatch" or msg=="dispatchaudit" then
        local nativeDispatch=JLP:GetModule("NativeDispatchService")
        JLP:Print(nativeDispatch and nativeDispatch:GetSummary() or "Native profession dispatch service unavailable.")
    elseif msg=="traineropt" or msg=="earlytrainer" then
        local trainerOptimizer=JLP:GetModule("TrainerOptimizer")
        JLP:Print(trainerOptimizer and trainerOptimizer:GetSummary() or "Travel-aware trainer optimization unavailable.")
    elseif msg=="professionids" or msg=="professionidentity" then
        local professionAPI=JLP:GetModule("ProfessionAPI")
        JLP:Print(professionAPI and professionAPI:GetIdentitySummary() or "Stable profession identity unavailable.")
    elseif msg=="characteridentity" or msg=="characterid" then
        local characterIdentity=JLP:GetModule("CharacterIdentity")
        JLP:Print(characterIdentity and characterIdentity:GetSummary() or "Stable character identity unavailable.")
    elseif msg=="professions" or msg=="registry" or msg=="professionregistry" then
        local professionRegistry=JLP:GetModule("ProfessionRegistry")
        JLP:Print(professionRegistry and professionRegistry:GetSummary() or "Profession registry unavailable.")
    elseif msg=="runtimestate" or msg=="professionstateall" then
        local runtimeState=JLP:GetModule("ProfessionRuntimeState")
        JLP:Print(runtimeState and runtimeState:GetSummary() or "Profession runtime state unavailable.")
    elseif msg=="professionmatrix" or msg=="regressionmatrix" then
        local matrix=JLP:GetModule("ProfessionRegressionMatrix")
        JLP:Print(matrix and matrix:GetSummary() or "Profession regression matrix unavailable.")
    elseif msg=="preflight" or msg=="buildpreflight" then
        local preflight=JLP:GetModule("BuildPreflightPresentation")
        JLP:Print(preflight and preflight:GetSummary() or "Build preflight unavailable · native authority not granted.")
    elseif msg=="buildinfo" or msg=="clientbuildinfo" then
        local buildInfo=JLP:GetModule("ClientBuildInfo")
        JLP:Print(buildInfo and buildInfo:GetSummary(70245) or "Client build information unavailable.")
    elseif msg=="alchemycandidate" or msg=="alchemyfoundation" then
        local foundation=JLP:GetModule("ProductionAlchemyFoundation")
        JLP:Print(foundation and foundation:GetSummary() or "Alchemy production-candidate foundation unavailable.")
    elseif msg=="requalify snapshot" or msg=="buildaudit snapshot" or msg=="currentbuild snapshot" then
        local session=JLP:GetModule("ProfessionObservationSnapshot")
        JLP:Print(session and session:GetSummary() or "Optional profession snapshot unavailable.")
    elseif msg:match("^requalify%s+last") or msg:match("^buildaudit%s+last") or msg:match("^currentbuild%s+last") then
        local session=JLP:GetModule("ProfessionObservationSnapshot")
        local profession=msg:match("^%S+%s+last%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or nil
        JLP:Print(session and session:GetLastSummary(profession) or "Optional profession snapshot unavailable.")
    elseif msg=="npcsnapshot" or msg=="sourceobservation" then
        local snapshot=JLP:GetModule("OptionalNPCSnapshot")
        JLP:Print(snapshot and snapshot:GetSummary() or "Optional NPC snapshot unavailable.")
    elseif msg:match("^routeacquire%s+") or msg=="routeacquire" then
        local key,mode=msg:match("^routeacquire%s+(%S+)%s*(%S*)")
        local advisor=self:GetModule("ForeverRouteAcquisition")
        self:Print(advisor and advisor:GetSummary(key or "ENGINEERING",mode=="aggressive" and "aggressive" or "normal") or "Forever route acquisition unavailable")
    elseif msg:match("^materialflow%s+") or msg=="materialflow" then
        local key=msg:match("^materialflow%s+(%S+)") or "ENGINEERING"
        local flow=self:GetModule("ForeverMaterialFlow")
        self:Print(flow and flow:GetSummary(key) or "Forever material flow unavailable")
    elseif msg:match("^skillband%s+") or msg=="skillband" then
        local key,skill,mode=msg:match("^skillband%s+(%S+)%s*(%d*)%s*(%S*)")
        local planner=self:GetModule("ForeverSkillBandPlanner")
        self:Print(planner and planner:GetSummary(key or "BLACKSMITHING",mode=="aggressive" and "aggressive" or "normal",tonumber(skill)) or "Skill-band planner unavailable")
    elseif msg:match("^foreverroute%s+") or msg=="foreverroute" then
        local authority=JLP:GetModule("ForeverRecipeAuthority")
        local key,mode=msg:match("^foreverroute%s+(%S+)%s*(%S*)")
        JLP:Print(authority and authority:GetSummary(key,mode) or "Forever recipe authority unavailable.")
    elseif msg:match("^routecompare%s+") or msg=="routecompare" or msg:match("^publicrecipes%s+") or msg=="publicrecipes" then
        local comparison=JLP:GetModule("PublicCraftingRouteComparison")
        local profession=msg:match("^%S+%s+(%S+)")
        JLP:Print(comparison and comparison:GetSummary(profession) or "Public crafting route comparison unavailable.")
    elseif msg:match("^professionguide%s+") or msg=="professionguide" then
        local guide=JLP:GetModule("ProfessionReferenceGuide")
        local profession=msg:match("^professionguide%s+(%S+)")
        JLP:Print(guide and guide:GetSummary(profession) or "Reference guide unavailable.")
    elseif msg=="routequal" or msg=="routequalification" or msg:match("^routequal%s+") or msg:match("^routequalification%s+") then
        local qualification=JLP:GetModule("RouteQualificationService")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or nil
        JLP:Print(qualification and qualification:GetSummary(profession) or "Route lifecycle qualification unavailable.")
    elseif msg=="requalify" or msg=="buildaudit" or msg=="currentbuild" then
        local requal=JLP:GetModule("CurrentBuildRequalification")
        JLP:Print(requal and requal:GetSummary() or "Current-build requalification audit unavailable.")
    elseif msg=="research" or msg=="profresearch" or
        msg:match("^research%s+") or msg:match("^profresearch%s+") then
        local research=JLP:GetModule("ProfessionResearch")
        local profession,mode,skill=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(%S*)")
        if profession and research and type(research.DescribeSourceStep)=="function" then
            JLP:Print(research:DescribeSourceStep(profession:upper(),mode,tonumber(skill) or 1))
        else
            JLP:Print(research and research:GetSummary() or "Profession research catalogue unavailable.")
        end
    elseif msg=="researchdeps" or msg=="dependencies" or msg:match("^researchdeps%s+") or msg:match("^dependencies%s+") then
        local graph=JLP:GetModule("ProfessionDependencyGraph")
        local profession,mode=msg:match("^%S+%s+(%S+)%s*(%S*)")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(graph and graph:GetSummary(profession,mode) or "Profession dependency graph unavailable.")
    elseif msg=="supplements" or msg=="researchplan" or msg:match("^supplements%s+") or msg:match("^researchplan%s+") then
        local supplemental=JLP:GetModule("ResearchSupplementPlanner")
        local profession,mode=msg:match("^%S+%s+(%S+)%s*(%S*)")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(supplemental and supplemental:GetSummary(profession,mode) or "Research supplemental planner unavailable.")
    elseif msg=="candidates" or msg=="researchcandidates" or msg:match("^candidates%s+") or msg:match("^researchcandidates%s+") then
        local verifier=JLP:GetModule("ResearchCandidateVerifier")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(verifier and verifier:GetSummary(profession,mode,selector) or "Research candidate verification unavailable.")
    elseif msg=="promotion" or msg=="promotecandidates" or msg:match("^promotion%s+") or msg:match("^promotecandidates%s+") then
        local policy=JLP:GetModule("ResearchPromotionPolicy")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(policy and policy:GetSummary(profession,mode,selector) or "Research promotion policy unavailable.")
    elseif msg=="closure" or msg=="promotionclosure" or msg:match("^closure%s+") or msg:match("^promotionclosure%s+") then
        local closure=JLP:GetModule("ResearchPromotionClosure")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(closure and closure:GetSummary(profession,mode,selector) or "Research promotion closure unavailable.")
    elseif msg=="segments" or msg=="routesegments" or msg:match("^segments%s+") or msg:match("^routesegments%s+") then
        local bridge=JLP:GetModule("ResearchRouteSegmentBridge")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(bridge and bridge:GetSummary(profession,mode,selector) or "Provisional route segment bridge unavailable.")
    elseif msg=="segmentqual" or msg=="qualifysegments" or msg:match("^segmentqual%s+") or msg:match("^qualifysegments%s+") then
        local qualification=JLP:GetModule("ResearchRouteSegmentQualification")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(qualification and qualification:GetSummary(profession,mode,selector) or "Live route-segment qualification unavailable.")
    elseif msg=="segmentstage" or msg=="plannerstage" or msg:match("^segmentstage%s+") or msg:match("^plannerstage%s+") then
        local handoff=JLP:GetModule("ResearchRouteSegmentHandoff")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(handoff and handoff:GetSummary(profession,mode,selector) or "Qualified route-segment handoff unavailable.")
    elseif msg=="recursiveadapter" or msg=="crafttree" or msg:match("^recursiveadapter%s+") or msg:match("^crafttree%s+") then
        local adapter=JLP:GetModule("ResearchRecursiveMaterialAdapter")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(adapter and adapter:GetSummary(profession,mode,selector) or "Recursive crafted-material adapter unavailable.")
    elseif msg=="shadowplan" or msg=="planparity" or msg:match("^shadowplan%s+") or msg:match("^planparity%s+") then
        local shadow=JLP:GetModule("ResearchShadowPlanner")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(shadow and shadow:GetSummary(profession,mode,selector) or "Planner contract parity shadow audit unavailable.")
    elseif msg=="adaptiveparity" or msg=="telemetryparity" or msg:match("^adaptiveparity%s+") or msg:match("^telemetryparity%s+") then
        local adaptive=JLP:GetModule("ResearchAdaptivePlannerParity")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(adaptive and adaptive:GetSummary(profession,mode,selector) or "Adaptive research Planner parity unavailable.")
    elseif msg=="authorityready" or msg=="plannerready" or msg:match("^authorityready%s+") or msg:match("^plannerready%s+") then
        local readiness=JLP:GetModule("ResearchPlannerAuthorityReadiness")
        local profession,mode,selector=msg:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)$")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        selector=selector and selector~="" and selector or nil
        JLP:Print(readiness and readiness:GetSummary(profession,mode,selector) or "Planner authority-readiness gate unavailable.")
    elseif msg=="routeauthority" or msg=="plannerauthority" or msg:match("^routeauthority%s+") or msg:match("^plannerauthority%s+") then
        local bridge=JLP:GetModule("ResearchRouteAuthorityBridge")
        if not bridge then
            JLP:Print("Controlled route-authority bridge unavailable.")
        else
            local command,rest=msg:match("^%S+%s*(%S*)%s*(.*)$")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=bridge:SetFeatureEnabled(true)
                JLP:Print(ok and ("Research Planner route-authority feature gate: "..tostring(state)..".") or ("Unable to enable research route authority: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=bridge:SetFeatureEnabled(false)
                JLP:Print(ok and ("Research Planner route-authority feature gate: "..tostring(state)..".") or ("Unable to disable research route authority: "..tostring(state).."."))
            elseif command=="normal" or command=="aggressive" then
                local ok,state=bridge:SetMode(command)
                JLP:Print(ok and ("Research Planner route-authority mode: "..tostring(state)..".") or ("Unable to change research route-authority mode: "..tostring(state).."."))
            else
                local profession=command~="" and command:upper() or "ENGINEERING"
                local mode=rest and rest:match("^(%S+)") or nil
                mode=(mode=="aggressive") and "aggressive" or bridge:GetConfiguredMode()
                JLP:Print(bridge:GetSummary(profession,mode))
            end
        end
    elseif msg=="tailoringauthority" or msg=="tailoringconsumer" or msg:match("^tailoringauthority%s+") or msg:match("^tailoringconsumer%s+") then
        local adapter=JLP:GetModule("ProductionTailoringAuthorityAdapter")
        if not adapter then
            JLP:Print("Production Tailoring authority adapter unavailable.")
        else
            local command=msg:match("^%S+%s*(%S*)")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=adapter:SetFeatureEnabled(true)
                JLP:Print(ok and ("Production Tailoring consumer-authority feature gate: "..tostring(state)..". Native execution remains disabled.") or ("Unable to enable Tailoring consumer authority: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=adapter:SetFeatureEnabled(false)
                JLP:Print(ok and ("Production Tailoring consumer-authority feature gate: "..tostring(state)..".") or ("Unable to disable Tailoring consumer authority: "..tostring(state).."."))
            else
                JLP:Print(adapter:GetSummary())
            end
        end
    elseif msg=="enchantingauthority" or msg=="enchantingconsumer" or msg:match("^enchantingauthority%s+") or msg:match("^enchantingconsumer%s+") then
        local adapter=JLP:GetModule("ProductionEnchantingAuthorityAdapter")
        if not adapter then
            JLP:Print("Production Enchanting authority adapter unavailable.")
        else
            local command=msg:match("^%S+%s*(%S*)")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=adapter:SetFeatureEnabled(true)
                JLP:Print(ok and ("Production Enchanting target-bound consumer-authority feature gate: "..tostring(state)..". Native Enchant One remains behind the separate /jlp enchantingnative gate.") or ("Unable to enable Enchanting consumer authority: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=adapter:SetFeatureEnabled(false)
                JLP:Print(ok and ("Production Enchanting target-bound consumer-authority feature gate: "..tostring(state)..".") or ("Unable to disable Enchanting consumer authority: "..tostring(state).."."))
            else
                JLP:Print(adapter:GetSummary())
            end
        end
    elseif msg=="consumerauthority" or msg=="consumerready" or msg:match("^consumerauthority%s+") or msg:match("^consumerready%s+") then
        local consumer=JLP:GetModule("ResearchPlannerConsumerBridge")
        local profession,mode=msg:match("^%S+%s*(%S*)%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or "ENGINEERING"
        local source=consumer and consumer.GetAuthoritySource and consumer:GetAuthoritySource(profession) or nil
        mode=(mode=="aggressive") and "aggressive" or (source and source.GetConfiguredMode and source:GetConfiguredMode() or "normal")
        JLP:Print(consumer and consumer:GetSummary(profession,mode) or "Research Planner consumer authority unavailable.")
    elseif msg=="consumerwatch" or msg=="consumerstate" or msg:match("^consumerwatch%s+") or msg:match("^consumerstate%s+") then
        local invalidation=JLP:GetModule("ResearchConsumerInvalidation")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(invalidation and invalidation:GetSummary(profession) or "Research consumer invalidation orchestration unavailable.")
    elseif msg=="executionready" or msg=="execgate" or msg:match("^executionready%s+") or msg:match("^execgate%s+") then
        local executionReadiness=JLP:GetModule("ResearchExecutionReadiness")
        local profession,mode=msg:match("^%S+%s+(%S+)%s*(%S*)")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(executionReadiness and executionReadiness:GetSummary(profession,mode) or "Research execution-readiness gate unavailable.")
    elseif msg=="predispatch" or msg=="shadowdispatch" or msg:match("^predispatch%s+") or msg:match("^shadowdispatch%s+") then
        local handoff=JLP:GetModule("ResearchExecutionIntentHandoff")
        local profession,mode=msg:match("^%S+%s+(%S+)%s*(%S*)")
        profession=profession and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(handoff and handoff:GetSummary(profession,mode) or "Research shadow pre-dispatch handoff unavailable.")
    elseif msg=="executionauthority" or msg=="nativegate" or msg:match("^executionauthority%s+") or msg:match("^nativegate%s+") then
        local gate=JLP:GetModule("ResearchExecutionAuthorityGate")
        if not gate then
            JLP:Print("Controlled execution-authority eligibility gate unavailable.")
        else
            local command,rest=msg:match("^%S+%s*(%S*)%s*(.*)$")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=gate:SetFeatureEnabled(true)
                JLP:Print(ok and ("Controlled execution-authority eligibility gate: "..tostring(state)..". Native dispatch still requires the separate default-off /jlp nativeexecution gate.") or ("Unable to enable controlled execution-authority eligibility: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=gate:SetFeatureEnabled(false)
                JLP:Print(ok and ("Controlled execution-authority eligibility gate: "..tostring(state)..".") or ("Unable to disable controlled execution-authority eligibility: "..tostring(state).."."))
            else
                local profession=command~="" and command:upper() or "ENGINEERING"
                local mode=rest and rest:match("^(%S+)") or nil
                mode=(mode=="aggressive") and "aggressive" or "normal"
                JLP:Print(gate:GetSummary(profession,mode))
            end
        end
    elseif msg=="nativeexecution" or msg=="nativecraft" or msg:match("^nativeexecution%s+") or msg:match("^nativecraft%s+") then
        local native=JLP:GetModule("ResearchNativeExecutionAuthority")
        if not native then
            JLP:Print("Research native single-craft execution authority unavailable.")
        else
            local command,rest=msg:match("^%S+%s*(%S*)%s*(.*)$")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=native:SetFeatureEnabled(true)
                JLP:Print(ok and ("Research native Craft One authority: "..tostring(state)..". Only guarded single-craft research dispatch is permitted.") or ("Unable to enable native research execution: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=native:SetFeatureEnabled(false)
                JLP:Print(ok and ("Research native Craft One authority: "..tostring(state)..".") or ("Unable to disable native research execution: "..tostring(state).."."))
            else
                local profession=command~="" and command:upper() or "ENGINEERING"
                local mode=rest and rest:match("^(%S+)") or nil
                mode=(mode=="aggressive") and "aggressive" or "normal"
                JLP:Print(native:GetSummary(profession,mode))
            end
        end
    elseif msg=="tailoringnative" or msg=="tailoringcraftone" or msg:match("^tailoringnative%s+") or msg:match("^tailoringcraftone%s+") then
        local native=JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
        if not native then
            JLP:Print("Production Tailoring native Craft One authority unavailable.")
        else
            local command=msg:match("^%S+%s*(%S*)")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=native:SetFeatureEnabled(true)
                JLP:Print(ok and ("Production Tailoring native Craft One authority: "..tostring(state)..". Craft All and Auto Route remain separate default-off authorities.") or ("Unable to enable production Tailoring Craft One: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=native:SetFeatureEnabled(false)
                JLP:Print(ok and ("Production Tailoring native Craft One authority: "..tostring(state)..".") or ("Unable to disable production Tailoring Craft One: "..tostring(state).."."))
            else
                JLP:Print(native:GetSummary())
            end
        end
    elseif msg=="enchantingnative" or msg=="enchantingcraftone" or msg:match("^enchantingnative%s+") or msg:match("^enchantingcraftone%s+") then
        local native=JLP:GetModule("ProductionEnchantingNativeExecutionAuthority")
        if not native then
            JLP:Print("Production Enchanting native Enchant One authority unavailable.")
        else
            local command=msg:match("^%S+%s*(%S*)")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=native:SetFeatureEnabled(true)
                JLP:Print(ok and ("Production Enchanting native Enchant One authority: "..tostring(state)..". Exactly one target-bound CraftEnchant is permitted per explicit Guide click; Craft All, Auto Route and protected confirmation automation remain disabled.") or ("Unable to enable production Enchanting Enchant One: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=native:SetFeatureEnabled(false)
                JLP:Print(ok and ("Production Enchanting native Enchant One authority: "..tostring(state)..".") or ("Unable to disable production Enchanting Enchant One: "..tostring(state).."."))
            else
                JLP:Print(native:GetSummary())
            end
        end
    elseif msg=="enchantingsettlement" or msg=="enchantinglifecycle" then
        local settlement=JLP:GetModule("ProductionEnchantingNativeSettlement")
        JLP:Print(settlement and settlement:GetSummary() or "Production Enchanting native settlement unavailable.")
    elseif msg=="enchantingcoverage" or msg=="enchantingrouteproof" then
        local coverage=JLP:GetModule("ProductionEnchantingNativeRouteCoverage")
        JLP:Print(coverage and coverage:GetSummary() or "Production Enchanting native route coverage unavailable.")
    elseif msg=="enchantingcraftall" or msg=="enchantingall" or msg=="enchantingsequence" or msg:match("^enchantingcraftall%s+") or msg:match("^enchantingall%s+") or msg:match("^enchantingsequence%s+") then
        local craftAll=JLP:GetModule("ProductionEnchantingCraftAllAuthority")
        local sequence=JLP:GetModule("ProductionEnchantingCraftAllSession")
        local orchestrator=JLP:GetModule("ProductionEnchantingCraftAllOrchestrator")
        if not craftAll then
            JLP:Print("Production Enchanting target-sequence planning authority unavailable.")
        else
            local command=msg:match("^%S+%s*(%S*)")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=craftAll:SetFeatureEnabled(true)
                JLP:Print(ok and ("Production Enchanting target-sequence planning authority: "..tostring(state)..". Planning is read-only; each enchant remains a separate explicit action and native multi-target queuing is disabled.") or ("Unable to enable production Enchanting target-sequence planning: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=craftAll:SetFeatureEnabled(false)
                JLP:Print(ok and ("Production Enchanting target-sequence planning authority: "..tostring(state)..". All runtime batch/session/ordinal tokens are revoked; no native queue existed to cancel.") or ("Unable to disable production Enchanting target-sequence planning: "..tostring(state).."."))
            else
                local summary=craftAll:GetSummary()
                if sequence then summary=summary.."\n\n"..sequence:GetSummary() end
                if orchestrator then summary=summary.."\n\n"..orchestrator:GetSummary() end
                JLP:Print(summary)
            end
        end
    elseif msg=="tailoringcraftall" or msg=="tailoringall" or msg:match("^tailoringcraftall%s+") or msg:match("^tailoringall%s+") then
        local craftAll=JLP:GetModule("ProductionTailoringCraftAllAuthority")
        if not craftAll then
            JLP:Print("Production Tailoring Craft All authority unavailable.")
        else
            local command=msg:match("^%S+%s*(%S*)")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=craftAll:SetFeatureEnabled(true)
                JLP:Print(ok and ("Production Tailoring Craft All authority: "..tostring(state)..". Craft All remains recipe-locked; Auto Route is a separate default-off authority.") or ("Unable to enable production Tailoring Craft All: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=craftAll:SetFeatureEnabled(false)
                JLP:Print(ok and ("Production Tailoring Craft All authority: "..tostring(state)..". Any in-flight ordinal may settle, but no new ordinal will start.") or ("Unable to disable production Tailoring Craft All: "..tostring(state).."."))
            else
                JLP:Print(craftAll:GetSummary("TAILORING","normal"))
            end
        end
    elseif msg=="tailoringautoroute" or msg=="tailoringauto" or msg:match("^tailoringautoroute%s+") or msg:match("^tailoringauto%s+") then
        local authority=JLP:GetModule("ProductionTailoringAutoRouteAuthority")
        if not authority then
            JLP:Print("Production Tailoring Auto Route authority unavailable.")
        else
            local command=msg:match("^%S+%s*(%S*)")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=authority:SetFeatureEnabled(true)
                JLP:Print(ok and ("Production Tailoring Auto Route authority: "..tostring(state)..". Auto Route dispatches one Craft One ordinal at a time and stops at non-craft boundaries.") or ("Unable to enable production Tailoring Auto Route: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=authority:SetFeatureEnabled(false)
                JLP:Print(ok and ("Production Tailoring Auto Route authority: "..tostring(state)..". Any irreversible in-flight ordinal may settle; no later ordinal is authorized.") or ("Unable to disable production Tailoring Auto Route: "..tostring(state).."."))
            else
                JLP:Print(authority:GetSummary())
            end
        end
    elseif msg=="tailoringautorouterestart" or msg=="tailoringrestartproof" or msg:match("^tailoringautorouterestart%s+") or msg:match("^tailoringrestartproof%s+") then
        local hardening=JLP:GetModule("ProductionTailoringAutoRouteRestart")
        JLP:Print(hardening and hardening:GetSummary() or "Production Tailoring Auto Route fresh-restart source hardening unavailable.")
    elseif msg=="tailoringautoendurance" or msg=="tailoringendurance" or msg:match("^tailoringautoendurance%s+") or msg:match("^tailoringendurance%s+") then
        local endurance=JLP:GetModule("ProductionTailoringAutoRouteEndurance")
        JLP:Print(endurance and endurance:GetSummary() or "Production Tailoring Auto Route 1-300 endurance simulation unavailable.")
    elseif msg=="tailoringnativeendurance" or msg=="tailoringruntimeendurance" or msg:match("^tailoringnativeendurance%s+") or msg:match("^tailoringruntimeendurance%s+") then
        local endurance=JLP:GetModule("ProductionTailoringAutoRouteNativeEndurance")
        JLP:Print(endurance and endurance:GetSummary() or "Production Tailoring native Auto Route endurance monitor unavailable.")
    elseif msg=="tailoringnativecoverage" or msg=="tailoringroutecoverage" or msg:match("^tailoringnativecoverage%s+") or msg:match("^tailoringroutecoverage%s+") then
        local coverage=JLP:GetModule("ProductionTailoringAutoRouteNativeCoverage")
        JLP:Print(coverage and coverage:GetSummary() or "Production Tailoring all-step native Auto Route coverage monitor unavailable.")
    elseif msg=="nativesettlement" or msg=="settlement" or msg:match("^nativesettlement%s+") or msg:match("^settlement%s+") then
        local settlement=JLP:GetModule("ResearchNativeExecutionSettlement")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(settlement and settlement:GetSummary(profession) or "Research native settlement orchestration unavailable.")
    elseif msg=="steptransition" or msg=="routehandoff" or msg:match("^steptransition%s+") or msg:match("^routehandoff%s+") then
        local transition=JLP:GetModule("ResearchNativeStepTransition")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(transition and transition:GetSummary(profession) or "Research native route-step transition orchestration unavailable.")
    elseif msg=="sequencestop" or msg=="sequenceboundary" or msg:match("^sequencestop%s+") or msg:match("^sequenceboundary%s+") then
        local policy=JLP:GetModule("ResearchSequentialStopPolicy")
        local profession,mode=msg:match("^%S+%s*(%S*)%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(policy and policy:GetSummary(profession,mode) or "Research bounded sequence stop policy unavailable.")
    elseif msg=="sequencerestart" or msg=="boundaryrestart" or msg:match("^sequencerestart%s+") or msg:match("^boundaryrestart%s+") then
        local restart=JLP:GetModule("ResearchBoundaryResolutionRestart")
        local profession,mode=msg:match("^%S+%s*(%S*)%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(restart and restart:GetSummary(profession,mode) or "Research boundary-resolution restart planner unavailable.")
    elseif msg=="routerestart" or msg=="routeboundaryrestart" or msg:match("^routerestart%s+") or msg:match("^routeboundaryrestart%s+") then
        local transition=JLP:GetModule("ResearchRouteChangingRestart")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(transition and transition:GetSummary(profession) or "Research route-changing restart matrix unavailable.")
    elseif msg=="craftallstrict" or msg=="targetsafeall" or msg:match("^craftallstrict%s+") or msg:match("^targetsafeall%s+") then
        local strict=JLP:GetModule("ResearchNativeCraftAllStrictOrchestrator")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(strict and strict:GetSummary(profession) or "Strict target-safe Craft All orchestrator unavailable.")
    elseif msg=="craftallinterrupt" or msg=="craftallmatrix" or msg:match("^craftallinterrupt%s+") or msg:match("^craftallmatrix%s+") then
        local matrix=JLP:GetModule("ResearchNativeCraftAllInterruption")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(matrix and matrix:GetSummary(profession) or "Research Craft All interruption matrix unavailable.")
    elseif msg=="craftallsettlement" or msg=="craftallrecovery" or msg:match("^craftallsettlement%s+") or msg:match("^craftallrecovery%s+") then
        local settlement=JLP:GetModule("ResearchNativeCraftAllSettlement")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(settlement and settlement:GetSummary(profession) or "Research Craft All settlement orchestrator unavailable.")
    elseif msg=="craftallhandoff" or msg=="craftallnext" or msg:match("^craftallhandoff%s+") or msg:match("^craftallnext%s+") then
        local handoff=JLP:GetModule("ResearchNativeCraftAllHandoff")
        local profession,mode=msg:match("^%S+%s*(%S*)%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(handoff and handoff:GetSummary(profession,mode) or "Research Craft All post-settlement handoff unavailable.")
    elseif msg=="craftallrestart" or msg=="craftallresume" or msg:match("^craftallrestart%s+") or msg:match("^craftallresume%s+") then
        local profession,mode=msg:match("^%S+%s*(%S*)%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        local restart=profession=="TAILORING" and JLP:GetModule("ProductionTailoringCraftAllRestart") or JLP:GetModule("ResearchNativeCraftAllRestart")
        JLP:Print(restart and restart:GetSummary(profession,mode) or "Craft All fresh-click restart planner unavailable.")
    elseif msg=="craftallresolution" or msg=="craftallrestartmatrix" or msg:match("^craftallresolution%s+") or msg:match("^craftallrestartmatrix%s+") then
        local matrix=JLP:GetModule("ResearchNativeCraftAllResolutionMatrix")
        local profession,mode=msg:match("^%S+%s*(%S*)%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(matrix and matrix:GetSummary(profession,mode) or "Research Craft All restart-resolution matrix unavailable.")
    elseif msg=="craftallauthority" or msg=="researchcraftall" or msg:match("^craftallauthority%s+") or msg:match("^researchcraftall%s+") then
        local craftAll=JLP:GetModule("ResearchNativeCraftAllAuthority")
        if not craftAll then
            JLP:Print("Research-native Craft All authority unavailable.")
        else
            local command,rest=msg:match("^%S+%s*(%S*)%s*(.*)$")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=craftAll:SetFeatureEnabled(true)
                JLP:Print(ok and ("Research Craft All authority: "..tostring(state)..". Craft All is recipe-locked and dispatches one native ordinal at a time; target skill is checked before the next ordinal.") or ("Unable to enable research Craft All: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=craftAll:SetFeatureEnabled(false)
                JLP:Print(ok and ("Research Craft All authority: "..tostring(state)..". Any active guarded repeat is stopped; Auto Route is separate.") or ("Unable to disable research Craft All: "..tostring(state).."."))
            else
                local profession=command~="" and command:upper() or "ENGINEERING"
                local mode=rest and rest:match("^(%S+)") or nil
                mode=(mode=="aggressive") and "aggressive" or "normal"
                JLP:Print(craftAll:GetSummary(profession,mode))
            end
        end
    elseif msg=="routeendurance" or msg=="realrouteaudit" or msg:match("^routeendurance%s+") or msg:match("^realrouteaudit%s+") then
        local audit=JLP:GetModule("ProductionRouteEnduranceAudit")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "TAILORING"
        JLP:Print(audit and audit:GetSummary(profession) or "Production route 1-300 endurance audit unavailable.")
    elseif msg=="tailoringidentity" or msg=="tailoringpromotion" then
        local identity=JLP:GetModule("ProductionTailoringRecipeIdentity")
        JLP:Print(identity and identity:GetSummary() or "Tailoring recipe identity / promotion readiness unavailable.")
    elseif msg=="enchantingidentity" or msg=="enchantingpromotion" then
        local identity=JLP:GetModule("ProductionEnchantingRecipeIdentity")
        JLP:Print(identity and identity:GetSummary() or "Enchanting recipe identity / targeted promotion readiness unavailable.")
    elseif msg=="enchantingtargetfoundation" or msg=="enchantingtargetproof" then
        local foundation=JLP:GetModule("ProductionEnchantingTargetedExecutionFoundation")
        JLP:Print(foundation and foundation:GetSummary() or "Enchanting targeted execution foundation unavailable.")
    elseif msg=="enchantingreadiness" or msg=="enchantingexecgate" then
        local readiness=JLP:GetModule("ResearchExecutionReadiness")
        JLP:Print(readiness and readiness:GetSummary("ENCHANTING","normal") or "Enchanting execution-readiness gate unavailable.")
    elseif msg=="autoroutelineage" or msg=="routelineage" or msg:match("^autoroutelineage%s+") or msg:match("^routelineage%s+") then
        local lineage=JLP:GetModule("ResearchAutoRouteSessionLineage")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(lineage and lineage:GetSummary(profession) or "Auto Route multi-session lineage unavailable.")
    elseif msg=="autorouteinterrupt" or msg=="routeinterrupt" or msg:match("^autorouteinterrupt%s+") or msg:match("^routeinterrupt%s+") then
        local interruption=JLP:GetModule("ResearchAutoRouteInterruption")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(interruption and interruption:GetSummary(profession) or "Auto Route interruption lifecycle unavailable.")
    elseif msg=="autorouteroutechange" or msg=="routechangeproof" or msg:match("^autorouteroutechange%s+") or msg:match("^routechangeproof%s+") then
        local hardening=JLP:GetModule("ResearchAutoRouteRouteChangeRestart")
        local profession=msg:match("^%S+%s+(%S+)")
        profession=profession and profession:upper() or "ENGINEERING"
        JLP:Print(hardening and hardening:GetSummary(profession) or "Auto Route route-change restart hardening unavailable.")
    elseif msg=="autorouterestart" or msg=="routeresume" or msg:match("^autorouterestart%s+") or msg:match("^routeresume%s+") then
        local restart=JLP:GetModule("ResearchAutoRouteRestart")
        local profession,mode=msg:match("^%S+%s*(%S*)%s*(%S*)")
        profession=profession and profession~="" and profession:upper() or "ENGINEERING"
        mode=(mode=="aggressive") and "aggressive" or "normal"
        JLP:Print(restart and restart:GetSummary(profession,mode) or "Auto Route fresh-click restart planner unavailable.")
    elseif msg=="autoroute" or msg=="routeauto" or msg:match("^autoroute%s+") or msg:match("^routeauto%s+") or msg=="sequentialcraft" or msg=="sequencecraft" or msg=="boundedcraft" or msg:match("^sequentialcraft%s+") or msg:match("^sequencecraft%s+") or msg:match("^boundedcraft%s+") then
        local sequence=JLP:GetModule("ResearchAutoRouteOrchestrator")
        if not sequence then
            JLP:Print("Research Auto Route production orchestration unavailable.")
        else
            local command,rest=msg:match("^%S+%s*(%S*)%s*(.*)$")
            command=tostring(command or ""):lower()
            if command=="on" or command=="enable" or command=="enabled" then
                local ok,state=sequence:SetFeatureEnabled(true)
                JLP:Print(ok and ("Auto Route: "..tostring(state)..". One explicit Guide click may continue through target-aware, individually revalidated Craft One transactions until a non-craft boundary or safety stop. Craft All remains current-recipe-only.") or ("Unable to enable Auto Route: "..tostring(state).."."))
            elseif command=="off" or command=="disable" or command=="disabled" then
                local ok,state=sequence:SetFeatureEnabled(false)
                JLP:Print(ok and ("Auto Route: "..tostring(state)..". In-flight native craft settlement is preserved; no route continuation is authorized.") or ("Unable to disable Auto Route: "..tostring(state).."."))
            elseif command=="stop" or command=="cancel" then
                local profession=rest and rest:match("^(%S+)") or nil
                profession=profession and profession:upper() or "ENGINEERING"
                local ok,state=sequence:Cancel(profession,"user-cancelled")
                JLP:Print(ok and ("Auto Route "..tostring(state).." for "..profession..".") or ("Unable to stop Auto Route: "..tostring(state).."."))
            elseif command=="limit" then
                JLP:Print("Auto Route no longer uses the alpha80 2/3-craft production bound. Production Auto Route remains target-aware and instead uses an internal safety cap of "..tostring(sequence:GetSafetyCraftCap()).." crafts per runtime session.")
            else
                local profession=command~="" and command:upper() or "ENGINEERING"
                JLP:Print(sequence:GetSummary(profession))
            end
        end
    elseif msg=="yields" or msg=="outputyield" or msg:match("^yields%s+") or msg:match("^outputyield%s+") then
        local evidence=JLP:GetModule("RecipeOutputEvidence")
        local recipe=msg:match("^%S+%s+(.+)$")
        JLP:Print(evidence and evidence:GetSummary(recipe) or "Recipe output yield evidence unavailable.")
    elseif msg=="accesssources" or msg=="accessevidence" or msg:match("^accesssources%s+") or msg:match("^accessevidence%s+") then
        local evidence=JLP:GetModule("RecipeAccessEvidence")
        local kind,name=msg:match("^%S+%s+(%S+)%s+(.+)$")
        JLP:Print(evidence and evidence:GetSummary(kind,name) or "Recipe access-source evidence unavailable.")
    elseif msg=="matsources" or msg=="materialsource" or msg:match("^matsources%s+") or msg:match("^materialsource%s+") then
        local evidence=JLP:GetModule("MaterialAcquisitionEvidence")
        local name=msg:match("^%S+%s+(.+)$")
        JLP:Print(evidence and evidence:GetSummary(name) or "Material acquisition evidence unavailable.")
    elseif msg=="telemetry" or msg=="efficiency" then
        local recipeTelemetry=JLP:GetModule("RecipeTelemetry")
        JLP:Print(recipeTelemetry and recipeTelemetry:GetSummary() or "Recipe efficiency telemetry unavailable.")
    elseif msg=="localmap" or msg=="localmap replace" then
        local navigationGuidance=JLP:GetModule("NavigationGuidance")
        if navigationGuidance and navigationGuidance.ShowCurrent then
            local _,message=navigationGuidance:ShowCurrent(nil,{replaceExisting=msg=="localmap replace"})
            JLP:Print(message)
        else
            JLP:Print("Local navigation guidance unavailable.")
        end
    elseif msg=="actions" then
        local queue=JLP:GetModule("ActionQueue")
        JLP:Print(queue and queue:GetSummary() or "Action queue unavailable.")
    elseif msg=="assist" then
        local assist=JLP:GetModule("ActionAssist")
        JLP:Print(assist and assist:GetSummary() or "Action assistance unavailable.")
    elseif msg=="flow" then
        local flow=JLP:GetModule("ExecutionFlow")
        JLP:Print(flow and flow:GetSummary() or "Execution flow unavailable.")
    elseif msg=="sessions" then
        local sessions=JLP:GetModule("AcquisitionSession")
        JLP:Print(sessions and sessions:GetSummary() or "Acquisition sessions unavailable.")
    elseif msg=="steps" then
        local steps=JLP:GetModule("GuideSteps")
        JLP:Print(steps and steps:GetSummary() or "Guide-step progression unavailable.")
    elseif msg=="craft" then
        local crafting=JLP:GetModule("Crafting")
        JLP:Print(crafting and crafting:GetSummary() or "Direct profession crafting unavailable.")
    elseif msg=="enchanttargets" then
        local crafting=JLP:GetModule("Crafting")
        JLP:Print(crafting and crafting:GetEnchantTargetDiagnostics("ENCHANTING") or "Enchant target diagnostics unavailable.")
        local guide=JLP.UIPages and JLP.UIPages.Guide
        if guide and guide.GetEnchantTargetUIDiagnostics then JLP:Print("Enchant target UI: "..guide:GetEnchantTargetUIDiagnostics()) end
    elseif msg=="overview" then JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowPage("Overview")
    elseif msg=="guide" or msg=="guide dual" then JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowGuideMode("dual")
    elseif msg:match("^guide%s+%S+$") then
        local requested=string.upper(msg:match("^guide%s+(%S+)$") or "")
        local api=JLP:GetModule("ProfessionAPI")
        local supported=false
        for _,profession in ipairs(api and api:GetPrimaryPair() or {}) do
            if profession and profession.key==requested then supported=true break end
        end
        if supported then
            JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowGuideMode(requested)
        else
            JLP:Print("That profession is not one of the character's detected primary professions.")
        end
    elseif msg=="ah current" or msg=="ah trainer" or msg=="ah 300" then
        local acquisition=JLP:GetModule("AcquisitionPlanner")
        local scope=msg=="ah trainer" and "next_trainer" or msg=="ah 300" and "to_300" or "current"
        if acquisition then acquisition:SetSelectedScope(scope) end
        JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowPage("Auction House")
    elseif msg=="ah" then JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowPage("Auction House")
    elseif msg=="map" then
        local acquisition=JLP:GetModule("AcquisitionPlanner")
        local route=JLP:GetModule("SourceRoute")
        local plan=acquisition and acquisition:BuildSelected()
        if route and plan then
            route:Sync(plan)
            local stop=route:GetCurrent()
            if stop and stop.navigable then
                local ok,message=route:ShowCurrent()
                JLP:Print(message)
            else
                JLP:Print("The current source-route stop has no audited map target. Use /jlp route next to continue.")
            end
        else
            JLP:Print("No source route is available in the selected plan.")
        end
    elseif msg=="route" or msg=="route next" or msg=="route prev" or msg=="route map" or msg=="route optimize" or msg=="route skip" or msg=="route clear-skips" then
        local acquisition=JLP:GetModule("AcquisitionPlanner")
        local route=JLP:GetModule("SourceRoute")
        local plan=acquisition and acquisition:BuildSelected()
        if not route or not plan then JLP:Print("Source route unavailable."); return end
        if msg=="route optimize" then route:Reoptimize(plan) else route:Sync(plan) end
        if msg=="route next" then
            route:Next()
        elseif msg=="route prev" then
            route:Previous()
        elseif msg=="route skip" then
            local _,message=route:SkipCurrent(plan)
            JLP:Print(message)
        elseif msg=="route clear-skips" then
            local cleared=route:ClearSkipped(plan)
            JLP:Print(string.format("Cleared %d skipped source action%s in the selected plan.",cleared,cleared==1 and "" or "s"))
        end
        if msg=="route map" then
            local ok,message=route:ShowCurrent()
            JLP:Print(message)
        elseif msg~="route skip" and msg~="route clear-skips" then
            local stop,index,count=route:GetCurrent()
            if stop then
                local resolver=JLP:GetModule("SourceResolver")
                local label=resolver and resolver:Format(stop.sourceInfo,false) or tostring(stop.sourceInfo and stop.sourceInfo.name or "Source")
                JLP:Print(string.format("Source route %d/%d: %s",index,count,label))
                local hint=route:GetTravelHint()
                if hint then JLP:Print(hint) end
            else
                local synced=route:Sync(plan)
                if synced and synced.count>0 and synced.pendingCount==0 then
                    JLP:Print("All source-route stops in the selected scope are completed or skipped.")
                else
                    JLP:Print("No trainer/vendor stops are present in the selected scope.")
                end
            end
        end
    elseif msg=="nav stop" or msg=="nav pause" or msg=="nav resume" or msg=="nav status" then
        local nav=JLP:GetModule("UnifiedDestinationNavigation")
        if nav then
            local ok,reason
            if msg=="nav stop" then ok,reason=nav:Stop("USER_STOP")
            elseif msg=="nav pause" then ok,reason=nav:Pause()
            elseif msg=="nav resume" then ok,reason=nav:Resume()
            else ok,reason=true,nav:GetSnapshot().status end
            JLP:Print("Navigation: "..tostring(reason))
        end
    elseif msg=="nav inspect" or msg=="nav handoff" then
        local common=JLP:GetModule("UnifiedDestinationNavigation")
        if not common then JLP:Print("Common navigation unavailable.")
        elseif msg=="nav inspect" then
            local result=common:Inspect()
            JLP:Print("Navigation: "..tostring(result.status).." / "..
                tostring(result.waypointConsistency).." / "..
                tostring(result.activeCategory or "none").." / generation="..
                tostring(result.generation or 0))
        else
            local result,reason=common:ExportHandoff()
            JLP:Print("Navigation handoff: "..tostring(reason)..
                " / map="..tostring(result and result.mapID or "none")..
                " / read-only; no standalone addon called")
        end
    elseif msg:match("^nav manual%s+") then
        local map,x,y=msg:match("^nav manual%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)$")
        local nav=JLP:GetModule("UnifiedDestinationNavigation")
        local ok,reason=nav and nav:Request("MANUAL",{
            nav={mapID=tonumber(map),x=tonumber(x),y=tonumber(y),
                evidence="EXPLICIT_USER_ENTERED_COORDINATES"},name="Manual waypoint"},
            {explicit=true,owner="LOCAL_USER"})
        JLP:Print("Manual navigation: "..tostring(reason or "INVALID_MANUAL_COORDINATES"))
    elseif msg:match("^nav gather%s+") then
        local profession,index=msg:match("^nav gather%s+([%a]+)%s+(%d+)$")
        local router=JLP:GetModule("TravelRouter")
        local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin()
        local nav=JLP:GetModule("UnifiedDestinationNavigation")
        local ok,reason=nav and nav:SelectGatheringStop(origin and origin.mapID,
            profession and profession:upper(),tonumber(index))
        JLP:Print("Gathering navigation: "..tostring(reason or "UNAVAILABLE"))
    elseif msg=="navrecover70450" then
        local owner=JLP:GetModule("IntegratedDestinationOwner")
        local router=JLP:GetModule("TravelRouter")
        local state=owner and owner.GetSnapshot and owner:GetSnapshot() or nil
        local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
        if not state or state.category~="MANUAL" then
            JLP:Print("Manual navigation recovery: ONLY_MANUAL_DESTINATIONS")
        elseif not origin or origin.positionEvidence~="C_Map.GetPlayerMapPosition" then
            JLP:Print("Manual navigation recovery: NATIVE_POSITION_UNAVAILABLE")
        else
            local ok,reason=owner:Revalidate({explicit=true,currentMapID=origin.mapID,
                characterKey=state.characterKey})
            JLP:Print("Manual navigation recovery: "..tostring(reason))
        end
    elseif msg=="navarrow70450" then
        local hud=JLP:GetModule("IntegratedNavigationHUD")
        local owner=JLP:GetModule("IntegratedDestinationOwner")
        local state=owner and owner.GetSnapshot and owner:GetSnapshot() or nil
        local record=hud and hud.GetSnapshot and hud:GetSnapshot() or nil
        JLP:Print("Navigation arrow: "..tostring(record and record.arrowReason or "HUD_UNAVAILABLE")..
            " / target="..tostring(state and state.category or "NONE")..
            " / state="..tostring(state and state.status or "UNKNOWN")..
            " / worldBearing="..tostring(record and record.bearingAvailable or false)..
            " / crossMap="..tostring(record and record.crossMapBearing or false)..
            " / terrain=UNVERIFIED")
    elseif msg=="nav hud" then
        local hud=JLP:GetModule("IntegratedNavigationHUD")
        if hud then
            hud:SetVisible(not hud.enabled)
            if hud.enabled and hud.Refresh then hud:Refresh(0.12) end
            JLP:Print("Navigation HUD "..(hud.enabled and "on" or "off"))
        end
    elseif msg=="bank" then JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowPage("Bank")
    elseif msg=="settings" then JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowPage("Settings")
    elseif msg=="minimap" then
        if JLP.MinimapButton then JLP.MinimapButton:ToggleVisibility() end
    else
        JLP:Print("Commands: /jlp ui | scan | status | progress | ready | state | execution | workspace | next | cta | batch | travelchain | journey | confidence | navigation | marker | handoff | recovery | history | traineropt | research | researchdeps | supplements [profession] [normal|aggressive] | candidates [profession] [normal|aggressive] [step|recipe] | promotion [profession] [normal|aggressive] [step|recipe] | closure [profession] [normal|aggressive] [step|recipe] | segments [profession] [normal|aggressive] [segment|recipe] | segmentqual [profession] [normal|aggressive] [segment|recipe] | segmentstage [profession] [normal|aggressive] [segment|recipe] | recursiveadapter [profession] [normal|aggressive] [step|recipe] | shadowplan [profession] [normal|aggressive] [segment|recipe] | adaptiveparity [profession] [normal|aggressive] [segment|recipe] | authorityready [profession] [normal|aggressive] [segment|recipe] | routeauthority [on|off|normal|aggressive|profession mode] | tailoringauthority [on|off] | enchantingauthority [on|off] | consumerauthority [profession] [normal|aggressive] | consumerwatch [profession] | executionready [profession] [normal|aggressive] | predispatch [profession] [normal|aggressive] | executionauthority [on|off|profession mode] | nativeexecution [on|off|profession mode] | tailoringnative [on|off] | enchantingnative [on|off] | enchantingcraftall [on|off] | enchantingsequence [on|off] | tailoringcraftall [on|off] | tailoringautoroute [on|off] | tailoringautorouterestart | tailoringautoendurance | tailoringnativeendurance | tailoringnativecoverage | nativesettlement [profession] | craftallinterrupt [profession] | craftallsettlement [profession] | craftallhandoff [profession] [normal|aggressive] | craftallrestart [profession] [normal|aggressive] | craftallresolution [profession] [normal|aggressive] | steptransition [profession] | sequencestop [profession] [normal|aggressive] | sequencerestart [profession] [normal|aggressive] | routerestart [profession] | autoroute [on|off|stop|limit|profession] | routeendurance [TAILORING|ENCHANTING] | tailoringidentity | enchantingidentity | enchantingtargetfoundation | enchantingreadiness | autoroutelineage [profession] | autorouteinterrupt [profession] | autorouterestart [profession] [normal|aggressive] | sequentialcraft [compat alias] | yields [recipe] | accesssources [formula|pattern|schematic|recipe] [name] | matsources [material] | telemetry | craftstate70374 [profession] [spell] [crafts] | crafthistory70374 [profession] | tracker70374 [profession] | crafthistory70450 [profession] | craftobs70450 [profession] | datacheck70374 [profession] | recipecheck70374 [profession] [spell] [crafts] | progresscheck70374 [profession] [skill] | localmap | actions | assist | flow | sessions | steps | enchanttargets | overview | guide [dual|profession] | ah [current|trainer|300] | route [next|prev|map|skip|clear-skips|optimize] | map | bank | settings | minimap")
    end
end

