local _, JLP = ...

-- Shared profession-crafting execution layer. UI pages call this module instead
-- of invoking TradeSkill APIs directly so current and future profession guides
-- can reuse the same safety/target/stop behavior.
local Crafting = {
    pending = nil,
    pendingCraft = nil,
    lastCraft = nil,
    craftAttemptSerial = 0,
    activeRepeat = nil,
    enchantTargets = {},
    enchantTargetOptions = {},
    pendingEnchant = nil,
    lastEnchant = nil,
    enchantAttemptSerial = 0,
}

local ACTION_FEEDBACK_SECONDS = 14

local function actionNow()
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

local function recentAction(action)
    if type(action) ~= "table" or not tonumber(action.finishedAt) then return false end
    local current = actionNow()
    if current <= 0 then return true end
    return current - tonumber(action.finishedAt) <= ACTION_FEEDBACK_SECONDS
end

local function scheduleFeedbackExpiry(kind, token)
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    C_Timer.After(ACTION_FEEDBACK_SECONDS + 0.25, function()
        local action = kind == "enchant" and Crafting.lastEnchant or Crafting.lastCraft
        if not action or action.token ~= token then return end
        local eventName = kind == "enchant" and "ENCHANT_ACTION_UPDATED" or "CRAFT_ACTION_UPDATED"
        if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit(eventName, action) end
    end)
end

local function normalize(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return value
end

local function professionOpenKey()
    local api=JLP:GetModule("ProfessionAPI")
    if api and type(api.GetOpenProfessionContext)=="function" then
        local ok,ctx=pcall(api.GetOpenProfessionContext,api)
        return (ok and type(ctx)=="table" and ctx.verified==true)
            and ctx.professionKey or nil
    end
    return nil -- Native requests require the shared verified profession context.
end

local function recipeInfo(recipeID)
    if type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.GetRecipeInfo) ~= "function" then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    return ok and type(info) == "table" and info or nil
end

local function captureRecipeDifficulty(recipeID, recipeName)
    local resolver = JLP:GetModule("RecipeDifficulty")
    if not resolver or not resolver.Get then return nil end
    local ok, value = pcall(resolver.Get, resolver, recipeID, recipeName)
    return ok and type(value) == "table" and value or nil
end

local function rememberRecipeID(key, recipeName, recipeID)
    local cache = JLP:GetModule("KnowledgeCache")
    if not cache or not key or not recipeName or not recipeID then return end
    if cache.RememberRecipeID then cache:RememberRecipeID(key,recipeName,recipeID) end
    -- Also retain a session-local copy so a single successful lookup is enough
    -- even before SavedVariables are flushed.
    Crafting.recipeIDs = Crafting.recipeIDs or {}
    Crafting.recipeIDs[key] = Crafting.recipeIDs[key] or {}
    Crafting.recipeIDs[key][normalize(recipeName)] = tonumber(recipeID)
end

function Crafting:ResolveRecipeID(key, recipeName)
    local nameKey = normalize(recipeName)
    if nameKey == "" then return nil end

    local cache = JLP:GetModule("KnowledgeCache")
    local cached = cache and cache.GetRecipeID and cache:GetRecipeID(recipeName, key) or nil
    if cached then return tonumber(cached) end
    local transient = self.recipeIDs and self.recipeIDs[key] and self.recipeIDs[key][nameKey]
    if transient then return tonumber(transient) end

    if type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.GetAllRecipeIDs) == "function" then
        local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do
                local info = recipeInfo(id)
                if info and normalize(info.name) == nameKey then
                    rememberRecipeID(key, recipeName, id)
                    return tonumber(id)
                end
            end
        end
    end
    return nil
end

-- A valid zero is a client verdict, not a fallback for missing/failed APIs.
-- No SavedVariables/cache data may authorize a native craft. The read is
-- current-client only; UNKNOWN/ERROR stay distinct from KNOWN(0).
function Crafting:GetCraftableCountState(recipeID)
    local id=tonumber(recipeID)
    if not id or id~=id or id==math.huge or id==-math.huge or id<1 or id>=2147483648 or id%1~=0 then
        return {status="ERROR",reason="invalid-recipe-id",recipeID=recipeID}
    end
    local client=type(C_TradeSkillUI)=="table" and C_TradeSkillUI or nil
    if not client or type(client.GetCraftableCount)~="function" then
        return {status="UNKNOWN",reason="craftability-api-unavailable",recipeID=id}
    end
    local ok,count=pcall(client.GetCraftableCount,id)
    if not ok then
        return {status="ERROR",reason="craftability-api-call-failed",recipeID=id}
    end
    if count==nil then
        return {status="UNKNOWN",reason="craftability-api-returned-nil",recipeID=id}
    end
    -- API documentation specifies number; do not silently coerce malformed
    -- strings, negative numbers, NaN, infinities or fractional values to zero.
    if type(count)~="number" or count~=count or count==math.huge or count==-math.huge
        or count<0 or count%1~=0 then
        return {status="ERROR",reason="craftability-api-invalid-result",recipeID=id}
    end
    return {status="KNOWN",count=count,recipeID=id,reason=count==0 and "confirmed-zero" or "confirmed-positive"}
end

function Crafting:GetCraftableCount(recipeID)
    local result=self:GetCraftableCountState(recipeID)
    return result.count,result.status,result.reason
end

local function stopClientRepeat()
    if type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.StopRecipeRepeat) == "function" then
        return pcall(C_TradeSkillUI.StopRecipeRepeat) and true or false
    elseif type(StopTradeSkillRepeat) == "function" then
        return pcall(StopTradeSkillRepeat) and true or false
    end
    return false
end

local function craftCompletionMessage(status, pending, detail)
    local recipe=tostring(pending and pending.recipeName or "the recipe")
    local completed=math.max(0,math.floor(tonumber(pending and pending.completedCount) or 0))
    local requested=math.max(1,math.floor(tonumber(pending and pending.requestedCount) or 1))
    if status=="success" then
        if pending and pending.mode=="all" then
            local suffix=detail and tostring(detail)~="" and (" ("..tostring(detail)..")") or ""
            return string.format("Craft All complete: %d/%d %s craft%s completed%s.",completed,requested,recipe,completed==1 and "" or "s",suffix)
        end
        return "Craft complete: "..recipe.."."
    elseif status=="timeout" then
        return string.format("Craft completion could not be confirmed for %s after %d/%d craft%s. Check the profession window before retrying.",recipe,completed,requested,completed==1 and "" or "s")
    end
    local partial=completed>0 and string.format(" after %d/%d completed craft%s",completed,requested,completed==1 and "" or "s") or ""
    local suffix=detail and tostring(detail)~="" and (": "..tostring(detail)) or "."
    return "Craft failed for "..recipe..partial..suffix
end

function Crafting:GetCraftActionState(key, plan)
    local recipeID=plan and plan.step and plan.step.recipe and self:ResolveRecipeID(key,plan.step.recipe) or nil
    local pending=self.pendingCraft
    if pending and pending.key==key then
        return {
            status=pending.status or "pending",
            key=pending.key,
            recipeID=pending.recipeID,
            recipeName=pending.recipeName,
            mode=pending.mode,
            requestedCount=pending.requestedCount,
            completedCount=pending.completedCount or 0,
            targetSkill=pending.targetSkill,
            startedSkill=pending.startedSkill,
            token=pending.token,
            ledgerID=pending.ledgerID,
            researchNativeCraftAll=pending.researchNativeCraftAll==true,
            productionTailoringCraftAll=pending.productionTailoringCraftAll==true,
            strictTargetSafeCraftAll=pending.strictTargetSafeCraftAll==true,
            nativeDispatchPerOrdinal=tonumber(pending.nativeDispatchPerOrdinal),
            strictOrdinalDispatchCount=tonumber(pending.strictOrdinalDispatchCount) or 0,
            strictOrdinalInFlight=pending.strictOrdinalInFlight==true,
            strictAwaitingUserClick=pending.strictAwaitingUserClick==true,
        }
    end
    local recovery=JLP:GetModule("TransactionRecovery")
    local recoveryState=recovery and recovery.GetActionState and recovery:GetActionState(key,"craft") or nil
    if recoveryState then return recoveryState end
    if self.lastCraft and self.lastCraft.key==key and recentAction(self.lastCraft) then
        self.lastCraft.currentRecipeID=recipeID
        self.lastCraft.recipeChanged=recipeID and tonumber(self.lastCraft.recipeID)~=tonumber(recipeID) or false
        return self.lastCraft
    end
    return {status="idle",key=key,recipeID=recipeID}
end

function Crafting:CompletePendingCraft(status, detail, source, suppressPrint)
    local pending=self.pendingCraft
    if not pending then return false,nil end
    self.pendingCraft=nil
    if self.activeRepeat and self.activeRepeat.token==pending.token then
        stopClientRepeat()
        self.activeRepeat=nil
    end

    local ledger=JLP:GetModule("TransactionLedger")
    if ledger and pending.ledgerID then
        pending.completedCount=math.max(tonumber(pending.completedCount) or 0,ledger:GetConfirmedCount(pending.ledgerID) or 0)
        ledger:Close(pending.ledgerID,status,{source=source or "unknown",detail=detail})
    end

    -- Output quantity is reconciled separately from confirmed cast ordinals.
    -- No item quantity is ever added to completedCount or used as a route gate.
    local output=JLP:GetModule("CraftOutputReconciliation")
    local outputSettlement=output and output.Finalize and output:Finalize(pending,pending.completedCount) or nil

    if status=="success" then
        local inventory=JLP:GetModule("Inventory")
        if inventory and inventory.RefreshBagCache then inventory:RefreshBagCache() end
    end

    local currentProfession
    local api=JLP:GetModule("ProfessionAPI")
    if api and api.Get then currentProfession=api:Get(pending.key) end
    local endingSkill=tonumber(currentProfession and currentProfession.skill)
    local startedSkill=tonumber(pending.startedSkill)
    local skillGain=(status=="success" and endingSkill and startedSkill) and math.max(0,endingSkill-startedSkill) or 0
    local message=craftCompletionMessage(status,pending,detail)
    self.lastCraft={
        status=status,
        transactionKind="craft",
        key=pending.key,
        recipeID=pending.recipeID,
        recipeName=pending.recipeName,
        mode=pending.mode,
        requestedCount=pending.requestedCount,
        completedCount=pending.completedCount or 0,
        outputSettlement=outputSettlement,
        confirmedOutputUnits=outputSettlement and outputSettlement.confirmedOutputUnits or nil,
        outputSettlementStatus=outputSettlement and outputSettlement.status or "OUTPUT_UNKNOWN",
        expectedOutputUnits=outputSettlement and outputSettlement.expectedOutputUnits or nil,
        targetSkill=pending.targetSkill,
        startedSkill=startedSkill,
        endingSkill=endingSkill,
        skillGain=skillGain,
        targetReached=endingSkill and pending.targetSkill and endingSkill>=pending.targetSkill or false,
        startedAt=pending.startedAt,
        finishedAt=actionNow(),
        detail=detail,
        token=pending.token,
        ledgerID=pending.ledgerID,
        transactionID=pending.ledgerID,
        source=source or "unknown",
        materialSnapshot=pending.materialSnapshot,
        authorityProvenance=pending.authorityProvenance,
        researchNativeExecution=pending.researchNativeExecution==true,
        productionTailoringNativeExecution=pending.productionTailoringNativeExecution==true,
        researchNativeCraftAll=pending.researchNativeCraftAll==true,
            productionTailoringCraftAll=pending.productionTailoringCraftAll==true,
        strictTargetSafeCraftAll=pending.strictTargetSafeCraftAll==true,
        nativeDispatchPerOrdinal=tonumber(pending.nativeDispatchPerOrdinal),
        strictOrdinalDispatchCount=tonumber(pending.strictOrdinalDispatchCount) or 0,
        strictLastSettledOrdinal=tonumber(pending.strictLastSettledOrdinal) or 0,
        settlementState=pending.settlementState,
        settledBy=pending.settledBy,
        killSwitchObserved=pending.killSwitchObserved==true,
        provisionalFailure=pending.provisionalFailure,
        repeatStopRequested=pending.repeatStopRequested==true,
        repeatStopReason=pending.repeatStopReason,
        repeatStopSource=pending.repeatStopSource,
        repeatStopAt=pending.repeatStopAt,
        postStopOrdinalObserved=pending.postStopOrdinalObserved==true,
        postStopOrdinalSource=pending.postStopOrdinalSource,
        postStopOrdinalCount=tonumber(pending.postStopOrdinalCount) or 0,
        message=message,
    }
    local tracker=JLP:GetModule("ProgressTracker")
    if tracker and tracker.RecordTransaction then tracker:RecordTransaction(self.lastCraft) end
    scheduleFeedbackExpiry("craft",pending.token)
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("CRAFT_ACTION_UPDATED",self.lastCraft) end
    if not suppressPrint and message and JLP.Print then JLP:Print(message) end
    return true,message
end

function Crafting:ScheduleCraftTimeout(token, heartbeat)
    if type(C_Timer)~="table" or type(C_Timer.After)~="function" then return end
    C_Timer.After(15,function()
        local pending=Crafting.pendingCraft
        if pending and pending.token==token and (pending.heartbeat or 0)==heartbeat then
            -- Waiting for a new player action is not an in-flight native cast.
            if pending.strictAwaitingUserClick==true and pending.strictOrdinalInFlight~=true then return end
            if pending.researchNativeExecution==true then
                local settlement=JLP:GetModule("ResearchNativeExecutionSettlement")
                if settlement and settlement.HandleTimeout then
                    settlement:HandleTimeout(pending)
                    return
                end
            elseif pending.researchNativeCraftAll==true or pending.productionTailoringCraftAll==true then
                local settlement=JLP:GetModule("ResearchNativeCraftAllSettlement")
                if settlement and settlement.HandleTimeout then
                    settlement:HandleTimeout(pending)
                    return
                end
            end
            Crafting:CompletePendingCraft("timeout",nil,"timeout",false)
        end
    end)
end

function Crafting:TouchPendingCraft(status)
    local pending=self.pendingCraft
    if not pending then return nil end
    if status then pending.status=status end
    pending.heartbeat=(pending.heartbeat or 0)+1
    self:ScheduleCraftTimeout(pending.token,pending.heartbeat)
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("CRAFT_ACTION_UPDATED",pending) end
    return pending
end

function Crafting:RecordCraftCompletion(spellID, castGUID, source)
    local pending=self.pendingCraft
    if not pending or tonumber(spellID)~=tonumber(pending.recipeID) then return false end
    -- A late/duplicate success must never authorize an ordinal that the user
    -- has not explicitly clicked. Only the single in-flight batch ordinal is
    -- eligible for settlement, regardless of matching spellID.
    if pending.strictTargetSafeCraftAll == true and
        (pending.strictOrdinalInFlight ~= true or pending.strictAwaitingUserClick == true) then
        return false
    end
    local observedAfterStopRequest = pending.mode=="all" and pending.repeatStopRequested==true
    local ledger=JLP:GetModule("TransactionLedger")
    if ledger and pending.ledgerID then
        local newlyConfirmed,tx,unit=ledger:ConfirmCraft(pending.ledgerID,castGUID,spellID,source or "spellcast-success")
        if not newlyConfirmed then return false end
        if unit and ledger.ReconcileDifficulty and (pending.currentDifficulty or pending.difficultySnapshot) then
            ledger:ReconcileDifficulty(pending.ledgerID,unit.index,pending.currentDifficulty or pending.difficultySnapshot)
        end
        pending.completedCount=tx and tonumber(tx.confirmedCount) or (tonumber(pending.completedCount) or 0)
        -- Refresh only after the confirmed unit has consumed its pre-craft
        -- snapshot. If the skill-up changed recipe difficulty, this becomes the
        -- verified starting state for the next Craft All ordinal.
        pending.currentDifficulty=captureRecipeDifficulty(pending.recipeID,pending.recipeName) or pending.currentDifficulty
    else
        if castGUID and castGUID~="" then
            pending.seenCastGUIDs=pending.seenCastGUIDs or {}
            if pending.seenCastGUIDs[castGUID] then return false end
            pending.seenCastGUIDs[castGUID]=true
        end
        pending.completedCount=(tonumber(pending.completedCount) or 0)+1
    end
    if observedAfterStopRequest then
        pending.postStopOrdinalObserved = true
        pending.postStopOrdinalSource = source or "spellcast-success"
        pending.postStopOrdinalCount = (tonumber(pending.postStopOrdinalCount) or 0) + 1
    end
    self:TouchPendingCraft("crafting")

    local inventory=JLP:GetModule("Inventory")
    if inventory and inventory.RefreshBagCache then inventory:RefreshBagCache() end

    if pending.strictTargetSafeCraftAll==true then
        -- Alpha87 only ever has one native ordinal in flight.  Once this event
        -- confirms it, there is no hidden repeat work to cancel before target /
        -- material checks run.
        pending.strictOrdinalInFlight=false
        pending.strictLastSettledOrdinal=tonumber(pending.completedCount) or 0
    end

    if pending.mode=="all" and pending.repeatStopRequested then
        return self:FinalizeResearchCraftAllStop(pending.token,pending.repeatStopReason,pending.repeatStopSource or source or "spellcast-success")
    end

    if pending.mode=="all" and pending.strictTargetSafeCraftAll==true then
        local api=JLP:GetModule("ProfessionAPI")
        local profession=api and api.Get and api:Get(pending.key) or nil
        local skill=tonumber(profession and profession.skill)
        local target=tonumber(pending.targetSkill)
        -- Target has absolute first priority.  No subsequent CraftRecipe call is
        -- prepared until this check has completed for the confirmed ordinal.
        if skill and target and skill>=target then
            local interruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
            if interruption and interruption.Record then interruption:Record(pending.key,"strict-craft-all-target-reached","target skill "..tostring(target).." reached",pending,"strict-target-check") end
            return self:FinalizeResearchCraftAllStop(pending.token,"target skill "..tostring(target).." reached","strict-target-check")
        end
        if (tonumber(pending.completedCount) or 0)>=math.max(1,tonumber(pending.requestedCount) or 1) then
            local detail=(pending.authorityProvenance and pending.authorityProvenance.requestedCount and
                "requested ordinal budget reached for " or "no more materials are available for ")..tostring(pending.recipeName or "the current recipe")
            local interruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
            if interruption and interruption.Record then interruption:Record(pending.key,"strict-craft-all-initial-budget-exhausted",detail,pending,"strict-initial-budget") end
            return self:FinalizeResearchCraftAllStop(pending.token,detail,"strict-initial-budget")
        end
        local liveCount,countStatus,countReason=self:GetCraftableCount(pending.recipeID)
        if countStatus~="KNOWN" then
            -- Do not call a further protected ordinal or claim material exhaustion.
            -- A completed prefix is retained, but final outcome remains uncertain.
            pending.craftabilityUnknownAtStop=true
            pending.craftabilityFailureStatus=countStatus
            local detail="current craftability could not be verified ("..tostring(countReason or countStatus)..")"
            local interruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
            if interruption and interruption.Record then interruption:Record(pending.key,"strict-craft-all-craftability-unavailable",detail,pending,"strict-craftability-check") end
            return self:RequestResearchCraftAllStop(detail,"strict-craftability-check")
        end
        if liveCount==0 then
            local detail="the native client confirms no crafts available for "..tostring(pending.recipeName or "the current recipe")
            local interruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
            if interruption and interruption.Record then interruption:Record(pending.key,"strict-craft-all-current-recipe-materials-exhausted",detail,pending,"strict-material-check") end
            return self:FinalizeResearchCraftAllStop(pending.token,detail,"strict-material-check")
        end
        -- Window loss is observable at this boundary without another protected
        -- action. Settle the confirmed ordinal, classify the terminal state,
        -- and DO NOT leave an apparently clickable pending batch behind after
        -- the native profession window has already closed.
        local flow=JLP:GetModule("ExecutionFlow")
        if flow and type(flow.CaptureProfessionWindow)=="function" then
            local ok,openKey=pcall(flow.CaptureProfessionWindow,flow)
            if not ok or tostring(openKey or ""):upper()~=tostring(pending.key or ""):upper() then
                local interruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
                if interruption and interruption.Record then
                    interruption:Record(pending.key,"strict-craft-all-profession-window-lost",
                        "profession window unavailable after settled ordinal",pending,"strict-window-check")
                end
                return self:FinalizeResearchCraftAllStop(pending.token,
                    "profession window is no longer available","strict-window-check")
            end
        end
        -- A completion callback has no independently verified hardware event.
        -- NEVER issue the next protected native craft from this callback.
        -- Keep the same immutable recipe/owner ledger and require a fresh Guide
        -- button click; the next ordinal is fully revalidated on that click.
        pending.strictAwaitingUserClick=true
        pending.settlementState="strict-awaiting-new-user-click"
        self:TouchPendingCraft("awaiting-user")
        local recovery=JLP:GetModule("TransactionRecovery")
        if recovery and recovery.CapturePending then recovery:CapturePending("craft",pending) end
        return true

    end

    if pending.mode~="all" or pending.completedCount>=math.max(1,tonumber(pending.requestedCount) or 1) then
        return self:CompletePendingCraft("success",nil,source or "spellcast-success",false)
    end
    -- Legacy/non-research Craft All retains the older native-repeat stop check.
    if pending.mode=="all" and self:CheckAutoStop() then return true end
    return true
end

function Crafting:StopRepeat(reason, completionStatus)
    local previous=self.activeRepeat
    local pending=self.pendingCraft
    local provenance=pending and pending.authorityProvenance or nil
    if previous and pending and pending.token==previous.token and pending.mode=="all" and (pending.researchNativeCraftAll==true or pending.productionTailoringCraftAll==true)
        and type(provenance)=="table" and (provenance.contract=="research-native-craft-all-provenance-v1" or provenance.contract=="production-tailoring-native-craft-all-provenance-v1")
        and self.RequestResearchCraftAllStop then
        return self:RequestResearchCraftAllStop(reason, "repeat-stop")
    end
    local stopped=stopClientRepeat()
    self.activeRepeat=nil
    if previous and self.pendingCraft and self.pendingCraft.token==previous.token then
        self:CompletePendingCraft(completionStatus or "success",reason,"repeat-stop",false)
    elseif previous and reason and reason~="silent" then
        JLP:Print("Craft All stopped: "..tostring(reason))
    end
    return stopped
end

function Crafting:CheckAutoStop()
    local repeatState = self.activeRepeat
    if not repeatState then return false end

    -- Craft All is deliberately recipe-local.  It must never follow a Planner
    -- route transition into a different recipe.  The first stop condition is the
    -- skill target captured when the button was pressed; only if that target has
    -- not been reached do we consider exhaustion of materials for this exact
    -- recipe.
    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api:Get(repeatState.key) or nil
    local skill = profession and tonumber(profession.skill) or nil
    if skill and repeatState.targetSkill and skill >= repeatState.targetSkill then
        self:StopRepeat("target skill " .. tostring(repeatState.targetSkill) .. " reached")
        return true
    end

    local craftable,status,reason=self:GetCraftableCount(repeatState.recipeID)
    if status~="KNOWN" then
        -- Fail closed on repeat continuation, but never claim confirmed zero.
        self:StopRepeat("craftability verification unavailable ("..tostring(reason or status)..")", "timeout")
        return true
    end
    if craftable==0 then
        self:StopRepeat("client reports zero crafts available for "..tostring(repeatState.recipeName or "the current recipe"))
        return true
    end
    return false
end

local function isResearchCraftAllPending(pending)
    local provenance = pending and pending.authorityProvenance
    local contract = type(provenance) == "table" and tostring(provenance.contract or "") or ""
    return type(pending) == "table" and pending.mode == "all"
        and (pending.researchNativeCraftAll == true or pending.productionTailoringCraftAll == true)
        and type(provenance) == "table"
        and (contract == "research-native-craft-all-provenance-v1" or contract == "production-tailoring-native-craft-all-provenance-v1")
end

function Crafting:FinalizeResearchCraftAllStop(token, reason, source)
    local pending = self.pendingCraft
    if not pending or pending.token ~= token or not isResearchCraftAllPending(pending) then return false, "research-craft-all-stop-not-current" end
    -- Strict alpha87 paths can reach terminal stop directly because no subsequent
    -- ordinal has been authorized yet. Preserve the same stop provenance fields
    -- that alpha85's asynchronous RequestStop path would have populated.
    if reason and not pending.repeatStopReason then pending.repeatStopReason=tostring(reason) end
    if source and not pending.repeatStopSource then pending.repeatStopSource=tostring(source) end
    local ledger = JLP:GetModule("TransactionLedger")
    if ledger and pending.ledgerID then
        pending.completedCount = math.max(tonumber(pending.completedCount) or 0, ledger:GetConfirmedCount(pending.ledgerID) or 0)
    end
    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.ReconcileLivePending then
        local success, result = recovery:ReconcileLivePending("craft", pending, "research-craft-all-stop-finalize")
        if success then pending.completedCount = math.max(tonumber(pending.completedCount) or 0, tonumber(result and result.confirmedCount) or 0) end
    end
    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and api:Get(pending.key) or nil
    local skill = tonumber(profession and profession.skill)
    local targetReached = skill and tonumber(pending.targetSkill) and skill >= tonumber(pending.targetSkill) or false
    pending.targetReachedAtStop = targetReached
    pending.settlementState = targetReached and "craft-all-stopped-target" or (pending.killSwitchObserved and "craft-all-stopped-kill-switch" or "craft-all-stopped-boundary")
    pending.settledBy = "research-craft-all-stop-reconciliation"
    local detail = reason or pending.repeatStopReason or "research Craft All stopped"
    if (pending.killSwitchObserved or pending.craftabilityUnknownAtStop) and not targetReached
        and (tonumber(pending.completedCount) or 0) < (tonumber(pending.requestedCount) or 1) then
        -- Preserve the confirmed prefix, but never report unperformed ordinals
        -- as successful after a runtime kill switch or interrupted transaction.
        return self:CompletePendingCraft("aborted_unknown", detail .. "; confirmed prefix only", source or pending.repeatStopSource or "craft-all-interrupted", false)
    end
    if (tonumber(pending.completedCount) or 0) > 0 or targetReached then
        return self:CompletePendingCraft("success", detail, source or pending.repeatStopSource or "research-craft-all-stop", false)
    end
    return self:CompletePendingCraft("timeout", detail .. "; final in-flight craft could not be confirmed", source or pending.repeatStopSource or "research-craft-all-stop", false)
end

function Crafting:RequestResearchCraftAllStop(reason, source)
    local pending = self.pendingCraft
    if not isResearchCraftAllPending(pending) then return false, "no-research-craft-all-in-flight" end
    if pending.repeatStopRequested then return true, "research-craft-all-stop-already-requested" end
    stopClientRepeat()
    if self.activeRepeat and self.activeRepeat.token == pending.token then self.activeRepeat = nil end
    pending.repeatStopRequested = true
    pending.repeatStopReason = tostring(reason or "research Craft All stop requested")
    pending.repeatStopSource = tostring(source or "repeat-stop")
    pending.repeatStopAt = actionNow()
    pending.status = "settlement-pending"
    pending.settlementState = "craft-all-stop-grace"
    if pending.repeatStopSource == "kill-switch" then pending.killSwitchObserved = true end
    local interruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
    if interruption and interruption.Record then
        local state = pending.killSwitchObserved and "strict-craft-all-authority-disabled" or "strict-craft-all-transaction-not-current"
        interruption:Record(pending.key,state,pending.repeatStopReason,pending,pending.repeatStopSource)
    end
    local recovery = JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CapturePending then recovery:CapturePending("craft", pending) end
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("CRAFT_ACTION_UPDATED", pending) end
    -- Alpha87 strict Craft All has at most one explicitly dispatched ordinal in
    -- flight.  If none is in flight, there is no native repeat race to wait for
    -- and we can settle immediately.  Kill-switch/failure while an ordinal is
    -- actually in flight still uses alpha85's grace/reconciliation path.
    if pending.strictTargetSafeCraftAll==true and pending.strictOrdinalInFlight~=true then
        return self:FinalizeResearchCraftAllStop(pending.token,pending.repeatStopReason,pending.repeatStopSource)
    end
    local settlement = JLP:GetModule("ResearchNativeCraftAllSettlement")
    local grace = settlement and tonumber(settlement.stopGraceSeconds) or 1.5
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local token = pending.token
        C_Timer.After(grace, function()
            Crafting:FinalizeResearchCraftAllStop(token, pending.repeatStopReason, pending.repeatStopSource)
        end)
    else
        -- Test/compatibility runtimes without timers settle synchronously. Live
        -- Forever always has C_Timer and therefore receives the race grace.
        return self:FinalizeResearchCraftAllStop(pending.token, pending.repeatStopReason, pending.repeatStopSource)
    end
    return true, "research-craft-all-stop-pending"
end

local function craftRecipe(recipeID, count, dispatchContext)
    local nativeDispatch = JLP:GetModule("NativeDispatchService")
    if not nativeDispatch or not nativeDispatch.Dispatch then
        return false, "Native profession dispatch service is unavailable."
    end
    dispatchContext = dispatchContext or {}
    local ok, state, audit = nativeDispatch:Dispatch({
        contract = nativeDispatch.intentContract,
        professionKey = dispatchContext.professionKey or "TAILORING",
        strategy = "CRAFT_RECIPE",
        policy = dispatchContext.policy or "MANUAL_DIRECT_CRAFT",
        recipeID = recipeID,
        count = count,
        nativeDispatchAllowed = dispatchContext.nativeDispatchAllowed ~= false,
        guardPolicy = dispatchContext.guardPolicy == true,
        boundaryValidated = dispatchContext.boundaryValidated == true,
        ledgerReserved = dispatchContext.ledgerReserved == true,
        recoveryReserved = dispatchContext.recoveryReserved == true,
        transactionID = dispatchContext.transactionID,
        authorityContract = dispatchContext.authorityContract,
        boundaryContract = dispatchContext.boundaryContract,
    })
    if not ok then return false, audit and audit.detail or state end
    return true
end


function Crafting:DispatchNextResearchCraftAllOrdinal(pending, source)
    pending = pending or self.pendingCraft
    if not pending or self.pendingCraft ~= pending or pending.strictTargetSafeCraftAll ~= true then
        return false, "strict-craft-all-pending-not-current"
    end
    if pending.strictOrdinalInFlight == true then return false, "strict-craft-all-ordinal-already-in-flight" end
    if source~="initial" and source~="guide-new-click" then
        return false,"strict-craft-all-new-hardware-click-required"
    end
    if source=="guide-new-click" and pending.strictAwaitingUserClick~=true then
        return false,"strict-craft-all-not-awaiting-click"
    end

    local orchestrator=JLP:GetModule("ResearchNativeCraftAllStrictOrchestrator")
    if not orchestrator or not orchestrator.PrepareNextOrdinal or not orchestrator.ValidateOrdinalAuthorization then
        return false,"strict-craft-all-orchestrator-unavailable"
    end
    local authorization,prepareState=orchestrator:PrepareNextOrdinal(pending)
    if not authorization then return false,prepareState end
    local valid,validationState,model=orchestrator:ValidateOrdinalAuthorization(authorization,pending)
    orchestrator:ConsumeAuthorization(authorization.token,"native-single-ordinal-boundary")
    if not valid then return false,validationState end

    local recovery=JLP:GetModule("TransactionRecovery")
    pending.strictAwaitingUserClick=false
    pending.strictOrdinalAuthorizationToken=authorization.token
    pending.strictOrdinalInFlight=true
    pending.strictOrdinalDispatchCount=(tonumber(pending.strictOrdinalDispatchCount) or 0)+1
    pending.strictCurrentOrdinal=tonumber(authorization.nextOrdinal)
    -- Each strict ordinal has a distinct client cast. Never carry the
    -- preceding ordinal's event identity into a newly protected click.
    pending.expectedCastGUID=nil
    pending.nativeDispatchPerOrdinal=1
    pending.status="dispatching"
    pending.settlementState="craft-all-strict-ordinal-dispatch"
    pending.strictLastDispatchSource=tostring(source or "strict-orchestrator")
    -- M24: fail closed if the ordinal checkpoint cannot be persisted. A prior
    -- ledger reservation alone is not enough to dispatch an irreversible cast.
    local checkpointOK = false
    if recovery and type(recovery.CapturePending) == "function" then
        local callOK, saved = pcall(recovery.CapturePending, recovery, "craft", pending)
        checkpointOK = callOK and saved == true
    end
    if not checkpointOK then
        pending.strictOrdinalInFlight = false
        pending.strictDispatchFailure = "strict-ordinal-recovery-checkpoint-failed"
        self:CompletePendingCraft("failed", pending.strictDispatchFailure, "pre-dispatch", true)
        return false, "strict-ordinal-recovery-checkpoint-failed"
    end
    self:TouchPendingCraft("dispatching")

    local ok,err=craftRecipe(pending.recipeID,1,{
        professionKey=pending.key,
        policy=pending.productionTailoringCraftAll and "PRODUCTION_CRAFT_ALL_ORDINAL" or "RESEARCH_CRAFT_ALL_ORDINAL",
        transactionID=pending.transactionID or pending.ledgerID,
        authorityContract=pending.authorityProvenance and pending.authorityProvenance.authorityContract or nil,
        boundaryContract="native-strict-craft-all-ordinal-boundary-v1",
        guardPolicy=true,
        boundaryValidated=true,
        ledgerReserved=pending.ledgerID~=nil and pending.transactionID~=nil,
        recoveryReserved=checkpointOK==true,
        nativeDispatchAllowed=true,
    })
    if not ok then
        pending.strictOrdinalInFlight=false
        pending.strictDispatchFailure=tostring(err or "unknown client error")
        local detail="unable to dispatch strict research Craft All ordinal #"..tostring(authorization.nextOrdinal)..": "..pending.strictDispatchFailure
        local interruption=JLP:GetModule("ResearchNativeCraftAllInterruption")
        if interruption and interruption.Record then interruption:Record(pending.key,"strict-craft-all-native-dispatch-failed",detail,pending,"strict-native-api") end
        self:CompletePendingCraft("failed",detail,"strict-native-api",true)
        if recovery and recovery.ClearPending then recovery:ClearPending("strict-craft-all-native-api-failure") end
        return false,"strict-craft-all-native-dispatch-failed"
    end

    -- Synchronous client events may already have settled this ordinal (and even
    -- the aggregate transaction) while CraftRecipe() was on the stack.
    if not self.pendingCraft or self.pendingCraft.token~=pending.token then
        return true,"strict-craft-all-ordinal-dispatched-and-settled",model
    end
    if self.pendingCraft.status=="dispatching" then self.pendingCraft.status="pending" end
    self:TouchPendingCraft(self.pendingCraft.status)
    if recovery and recovery.CapturePending then recovery:CapturePending("craft",self.pendingCraft) end
    return true,"strict-craft-all-ordinal-dispatched",model
end

-- Only called by the existing Guide's direct button handler; no OnUpdate,
-- timer, settlement callback or SavedVariables restore may invoke it. The
-- actual native protected-action verdict still belongs to the Forever client.
function Crafting:ResumeStrictCraftAllFromGuide(key,plan)
    local pending=self.pendingCraft
    if key~="TAILORING" or not pending or pending.key~=key or
        pending.strictTargetSafeCraftAll~=true or
        pending.productionTailoringCraftAll~=true or
        pending.strictAwaitingUserClick~=true or pending.strictOrdinalInFlight==true then
        return false,"STRICT_CRAFT_CLICK_NOT_READY"
    end
    local newRecipe=plan and plan.step and plan.step.recipe and self:ResolveRecipeID(key,plan.step.recipe)
    if not newRecipe or tonumber(newRecipe)~=tonumber(pending.recipeID) then
        self:FinalizeResearchCraftAllStop(pending.token,"recipe changed; current session stopped","guide-recipe-drift")
        return false,"STRICT_CRAFT_RECIPE_CHANGED"
    end
    local ok,reason=self:DispatchNextResearchCraftAllOrdinal(pending,"guide-new-click")
    if not ok and self.pendingCraft==pending then
        pending.strictAwaitingUserClick=true
        self:TouchPendingCraft("awaiting-user")
        local recovery=JLP:GetModule("TransactionRecovery")
        if recovery and recovery.CapturePending then recovery:CapturePending("craft",pending) end
    end
    return ok,reason
end

local function shadowBoundaryReport(handoff)
    return {
        contract = "shadow-pre-dispatch-boundary-v1",
        state = "shadow-pre-dispatch-blocked",
        professionKey = handoff and handoff.professionKey or nil,
        mode = handoff and handoff.mode or nil,
        craftMode = handoff and handoff.craftMode or nil,
        intentToken = handoff and handoff.intentToken or nil,
        snapshotToken = handoff and handoff.snapshotToken or nil,
        stateFingerprint = handoff and handoff.stateFingerprint or nil,
        recipe = handoff and handoff.recipe or nil,
        recipeID = handoff and handoff.recipeID or nil,
        shadowOnly = true,
        executionEligible = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        nativeDispatchAttempted = false,
        persisted = false,
        boundaryValidated = false,
        singleUseConsumed = false,
    }
end

function Crafting:ShadowResearchDispatchBoundary(handoff, options)
    local report = shadowBoundaryReport(handoff)
    if type(handoff) ~= "table"
        or handoff.contract ~= "research-execution-intent-handoff-v1"
        or handoff.boundaryContract ~= "shadow-pre-dispatch-boundary-v1"
        or handoff.shadowOnly ~= true
        or handoff.executionEligible ~= false
        or handoff.dispatchAllowed ~= false
        or handoff.nativeDispatchAllowed ~= false then
        report.state = "shadow-pre-dispatch-invalid-handoff"
        return false, report.state, report
    end

    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    if not readiness or not readiness.ValidateIntent then
        report.state = "shadow-pre-dispatch-readiness-unavailable"
        return false, report.state, report
    end

    local valid, validationState, current = readiness:ValidateIntent(
        handoff.intentToken,
        handoff.professionKey,
        handoff.mode,
        options
    )
    report.intentValidationState = validationState
    report.intentValidated = valid and true or false
    if readiness.RevokeIntent then
        report.singleUseConsumed = readiness:RevokeIntent(handoff.intentToken) and true or false
    end
    if not valid or not current then
        report.state = "shadow-pre-dispatch-intent-rejected"
        report.readinessState = current and current.state or nil
        report.blockedGate = current and current.blockedGate or nil
        report.blockedState = current and current.blockedState or nil
        return false, report.state, report
    end

    local craftMode = handoff.craftMode == "all" and "all" or "one"
    local plan = current.plan
    local currentRecipe = plan and plan.step and plan.step.recipe or nil
    local currentRecipeID = tonumber(current.recipeID)
    local identityReady = plan ~= nil
        and plan.actionKind == "craft"
        and tostring(currentRecipe or "") == tostring(handoff.recipe or "")
        and currentRecipeID ~= nil
        and currentRecipeID == tonumber(handoff.recipeID)
        and tostring(current.snapshotToken or "") == tostring(handoff.snapshotToken or "")
        and tostring(current.stateFingerprint or "") == tostring(handoff.stateFingerprint or "")
        and tostring(current.professionKey or "") == tostring(handoff.professionKey or "")
        and tostring(current.mode or "") == tostring(handoff.mode or "")
    if not identityReady then
        report.state = "shadow-pre-dispatch-identity-mismatch"
        return false, report.state, report
    end

    local nativeCraftable=tonumber(current.nativeCraftable)
    if current.craftabilityStatus~="KNOWN" or nativeCraftable==nil then
        report.state="shadow-pre-dispatch-craftability-unavailable"
        return false,report.state,report
    end
    local count = craftMode == "all" and nativeCraftable or 1
    if count < 1 then
        report.state = "shadow-pre-dispatch-zero-craftable"
        return false, report.state, report
    end

    report.recipe = currentRecipe
    report.recipeID = currentRecipeID
    report.currentBuild = current.currentBuild
    report.snapshotToken = current.snapshotToken
    report.stateFingerprint = current.stateFingerprint
    report.craftMode = craftMode
    report.nativeCraftable = nativeCraftable
    report.wouldDispatchCount = count
    report.boundaryValidated = true
    report.state = "shadow-pre-dispatch-validated"
    return true, report.state, report
end


local function guardedBoundaryReport(reservation)
    return {
        contract = "guarded-native-dispatch-boundary-v1",
        state = "guarded-native-dispatch-blocked",
        professionKey = reservation and reservation.professionKey or nil,
        mode = reservation and reservation.mode or nil,
        craftMode = reservation and reservation.craftMode or nil,
        reservationToken = reservation and reservation.token or nil,
        snapshotToken = reservation and reservation.snapshotToken or nil,
        stateFingerprint = reservation and reservation.stateFingerprint or nil,
        recipe = reservation and reservation.recipe or nil,
        recipeID = reservation and reservation.recipeID or nil,
        candidateEligible = false,
        executionEligible = false,
        executionAuthorityEnabled = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        nativeDispatchAttempted = false,
        persisted = false,
        boundaryValidated = false,
        singleUseConsumed = false,
        hardLock = "alpha75-native-dispatch-disabled",
    }
end

function Crafting:GuardedResearchDispatchBoundary(reservation, options)
    local report = guardedBoundaryReport(reservation)
    if type(reservation) ~= "table"
        or reservation.contract ~= "research-native-dispatch-reservation-v1"
        or reservation.boundaryContract ~= "guarded-native-dispatch-boundary-v1"
        or reservation.candidateEligible ~= true
        or reservation.executionEligible ~= false
        or reservation.executionAuthorityEnabled ~= false
        or reservation.dispatchAllowed ~= false
        or reservation.nativeDispatchAllowed ~= false
        or reservation.persisted ~= false then
        report.state = "guarded-native-dispatch-invalid-reservation"
        return false, report.state, report
    end

    local authorityGate = JLP:GetModule("ResearchExecutionAuthorityGate")
    if not authorityGate or not authorityGate.ValidateReservation then
        report.state = "guarded-native-dispatch-authority-gate-unavailable"
        return false, report.state, report
    end

    local valid, validationState, current, stored = authorityGate:ValidateReservation(
        reservation,
        reservation.professionKey,
        reservation.mode,
        options
    )
    report.reservationValidationState = validationState
    report.reservationValidated = valid and true or false
    if authorityGate.RevokeReservation then
        report.singleUseConsumed = authorityGate:RevokeReservation(reservation.token, "guarded-boundary-attempt") and true or false
    end
    if not valid or not current or not stored then
        report.state = "guarded-native-dispatch-reservation-rejected"
        report.readinessState = current and current.state or nil
        report.blockedGate = current and current.blockedGate or nil
        report.blockedState = current and current.blockedState or nil
        return false, report.state, report
    end

    local identityReady = tostring(current.professionKey or "") == tostring(stored.professionKey or "")
        and tostring(current.mode or "") == tostring(stored.mode or "")
        and tostring(current.snapshotToken or "") == tostring(stored.snapshotToken or "")
        and tostring(current.stateFingerprint or "") == tostring(stored.stateFingerprint or "")
        and tostring(current.recipe or "") == tostring(stored.recipe or "")
        and tonumber(current.recipeID) == tonumber(stored.recipeID)
        and tostring(stored.craftMode or "") == "one"
        and tonumber(stored.requestedCount) == 1
        and (tonumber(current.nativeCraftable) or 0) >= 1
    if not identityReady then
        report.state = "guarded-native-dispatch-identity-mismatch"
        return false, report.state, report
    end

    -- Alpha75 stops here by design. This is the final pre-native boundary, but
    -- successful validation returns only eligibility metadata.  No transaction
    -- is created and craftRecipe() is never called from this path.
    report.recipe = current.recipe
    report.recipeID = tonumber(current.recipeID)
    report.currentBuild = current.currentBuild
    report.snapshotToken = current.snapshotToken
    report.stateFingerprint = current.stateFingerprint
    report.nativeCraftable = math.max(0, math.floor(tonumber(current.nativeCraftable) or 0))
    report.wouldDispatchCount = 1
    report.candidateEligible = true
    report.boundaryValidated = true
    report.state = "guarded-native-dispatch-eligible"
    return true, report.state, report
end


local function nativeResearchBoundaryReport(reservation)
    return {
        contract = "native-single-craft-dispatch-boundary-v1",
        state = "native-single-craft-dispatch-blocked",
        professionKey = reservation and reservation.professionKey or nil,
        mode = reservation and reservation.mode or nil,
        craftMode = reservation and reservation.craftMode or nil,
        reservationToken = reservation and reservation.token or nil,
        snapshotToken = reservation and reservation.snapshotToken or nil,
        stateFingerprint = reservation and reservation.stateFingerprint or nil,
        recipe = reservation and reservation.recipe or nil,
        recipeID = reservation and reservation.recipeID or nil,
        executionEligible = false,
        executionAuthorityEnabled = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        nativeDispatchAttempted = false,
        nativeDispatchAccepted = false,
        transactionReserved = false,
        recoveryReserved = false,
        rollbackComplete = false,
        persistedAuthorization = false,
        boundaryValidated = false,
        singleUseConsumed = false,
    }
end

local function nativeSingleCraftBoundary(self, reservation, options, authorityModuleName)
    local report = nativeResearchBoundaryReport(reservation)
    local nativeAuthority = JLP:GetModule(authorityModuleName)
    if not nativeAuthority or not nativeAuthority.EvaluateReservation then
        report.state = "native-single-craft-authority-unavailable"
        return false, report.state, report
    end
    report.contract = nativeAuthority.boundaryContract or report.contract
    report.provenanceContract = nativeAuthority.provenanceContract

    local authorityModel, current, stored = nativeAuthority:EvaluateReservation(reservation, options)
    report.authorityState = authorityModel and authorityModel.state or nil
    report.blockedGate = authorityModel and authorityModel.blockedGate or nil
    report.blockedState = authorityModel and authorityModel.blockedState or nil
    report.reservationValidationState = authorityModel and authorityModel.reservationValidationState or nil

    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if eligibility and eligibility.RevokeReservation and type(reservation) == "table" and reservation.token then
        report.singleUseConsumed = eligibility:RevokeReservation(reservation.token, "native-single-craft-boundary-attempt") and true or false
    end

    if not authorityModel or authorityModel.nativeExecutionAuthorityReady ~= true or not current or not stored then
        report.state = "native-single-craft-authority-rejected"
        return false, report.state, report
    end

    local plan = current.plan
    local identityReady = plan ~= nil
        and plan.actionKind == "craft"
        and plan.step ~= nil
        and tostring(current.professionKey or "") == tostring(stored.professionKey or "")
        and tostring(current.mode or "") == tostring(stored.mode or "")
        and tostring(current.snapshotToken or "") == tostring(stored.snapshotToken or "")
        and tostring(current.stateFingerprint or "") == tostring(stored.stateFingerprint or "")
        and tostring(current.recipe or "") == tostring(stored.recipe or "")
        and tonumber(current.recipeID) == tonumber(stored.recipeID)
        and tostring(plan.step.recipe or "") == tostring(stored.recipe or "")
        and tostring(stored.craftMode or "") == "one"
        and tonumber(stored.requestedCount) == 1
        and (tonumber(current.nativeCraftable) or 0) >= 1
    if not identityReady then
        report.state = "native-single-craft-identity-mismatch"
        return false, report.state, report
    end

    if self.pendingCraft or self.pendingEnchant or self.activeRepeat then
        report.state = "native-single-craft-transaction-busy"
        return false, report.state, report
    end

    local recovery = JLP:GetModule("TransactionRecovery")
    if not recovery or not recovery.CanStart or not recovery.CapturePending then
        report.state = "native-single-craft-recovery-boundary-unavailable"
        return false, report.state, report
    end
    local recoveryOK, recoveryMessage = recovery:CanStart("craft", current.professionKey)
    if not recoveryOK then
        report.state = "native-single-craft-recovery-blocked"
        report.detail = recoveryMessage
        return false, report.state, report
    end

    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger or not ledger.Begin then
        report.state = "native-single-craft-ledger-unavailable"
        return false, report.state, report
    end

    local recipeID = tonumber(current.recipeID)
    local recipeName = tostring(current.recipe or "")
    if not recipeID or recipeName == "" then
        report.state = "native-single-craft-recipe-unresolved"
        return false, report.state, report
    end

    -- Re-read native craftability at the irreversible boundary, after all prior
    -- authority validation but before reserving the persistent transaction.
    local nativeCraftable,countStatus,countReason=self:GetCraftableCount(recipeID)
    report.craftabilityStatus=countStatus
    report.craftabilityReason=countReason
    if countStatus~="KNOWN" then
        report.state="native-single-craft-craftability-unavailable"
        return false,report.state,report
    end
    if nativeCraftable==0 then
        report.state="native-single-craft-zero-craftable"
        return false,report.state,report
    end

    self.craftAttemptSerial=(self.craftAttemptSerial or 0)+1
    local token=self.craftAttemptSerial
    local api=JLP:GetModule("ProfessionAPI")
    local currentProfession=api and api.Get and api:Get(current.professionKey) or nil
    local progressTracker=JLP:GetModule("ProgressTracker")
    local materialSnapshot=progressTracker and progressTracker.CaptureMaterialSnapshot and progressTracker:CaptureMaterialSnapshot(current.professionKey,plan) or nil
    local provenance={
        contract=nativeAuthority.provenanceContract or "research-native-dispatch-provenance-v1",
        source=stored.clickOriginSource or "profession-guide",
        authorityContract=nativeAuthority.contract,
        boundaryContract=nativeAuthority.boundaryContract or "native-single-craft-dispatch-boundary-v1",
        eligibilityContract=eligibility and eligibility.contract or nil,
        reservationToken=stored.token,
        clickOriginToken=stored.clickOriginToken,
        clickOriginSource=stored.clickOriginSource,
        sequenceSessionToken=stored.sequenceSessionToken,
        sequenceOrdinal=tonumber(stored.sequenceOrdinal),
        sequenceRequestedCount=tonumber(stored.sequenceRequestedCount),
        sequenceDirectGuideClick=stored.sequenceDirectGuideClick==true,
        autoRouteSessionToken=stored.autoRouteSessionToken,
        autoRouteOrdinal=tonumber(stored.autoRouteOrdinal),
        autoRouteDirectGuideClick=stored.autoRouteDirectGuideClick==true,
        autoRouteDelegationContract=stored.autoRouteDelegationContract,
        autoRouteSourceAuthorityContract=stored.autoRouteSourceAuthorityContract,
        autoRouteSourcePromotionContract=stored.autoRouteSourcePromotionContract,
        autoRouteRecipeID=tonumber(stored.autoRouteRecipeID),
        autoRouteRouteIndex=tonumber(stored.autoRouteRouteIndex),
        autoRouteSkillTarget=tonumber(stored.autoRouteSkillTarget),
        autoRouteSnapshotToken=stored.autoRouteSnapshotToken,
        restartCandidateToken=stored.restartCandidateToken,
        restartAuthorizationToken=stored.restartAuthorizationToken,
        restartedFromSessionToken=stored.restartedFromSessionToken,
        restartedFromBoundaryState=stored.restartedFromBoundaryState,
        restartedFromBoundaryCategory=stored.restartedFromBoundaryCategory,
        restartRouteTransitionKind=stored.restartRouteTransitionKind,
        restartRouteChanged=stored.restartRouteChanged==true,
        restartPriorRecipeID=tonumber(stored.restartPriorRecipeID),
        restartPriorRouteIndex=tonumber(stored.restartPriorRouteIndex),
        restartCurrentRecipeID=tonumber(stored.restartCurrentRecipeID),
        restartCurrentRouteIndex=tonumber(stored.restartCurrentRouteIndex),
        restartExplicitUserClick=stored.restartExplicitUserClick==true,
        restartSourceProofContract=stored.restartSourceProofContract,
        restartSourceProofToken=stored.restartSourceProofToken,
        restartSourceAutoRouteAuthorityContract=stored.restartSourceAutoRouteAuthorityContract,
        restartSourceAutoRoutePromotionContract=stored.restartSourceAutoRoutePromotionContract,
        routeChangeBasis=stored.routeChangeBasis,
        routeChangeProofToken=stored.routeChangeProofToken,
        routeChangePurgeReceiptToken=stored.routeChangePurgeReceiptToken,
        routeChangePurgeVerified=stored.routeChangePurgeVerified==true,
        routeChangePostPurgeRevalidated=stored.routeChangePostPurgeRevalidated==true,
        routeChangePurgedIntentCount=tonumber(stored.routeChangePurgedIntentCount) or 0,
        routeChangePurgedReservationCount=tonumber(stored.routeChangePurgedReservationCount) or 0,
        routeChangePurgedClickOriginCount=tonumber(stored.routeChangePurgedClickOriginCount) or 0,
        autoRouteLineageContract=stored.autoRouteLineageContract,
        autoRouteLineageChainToken=stored.autoRouteLineageChainToken,
        autoRouteLineageRootSessionToken=stored.autoRouteLineageRootSessionToken,
        autoRouteLineageParentSessionToken=stored.autoRouteLineageParentSessionToken,
        autoRouteLineageDepth=tonumber(stored.autoRouteLineageDepth),
        autoRouteLineageGeneration=tonumber(stored.autoRouteLineageGeneration),
        autoRouteLineagePredecessorProofToken=stored.autoRouteLineagePredecessorProofToken,
        autoRouteLineageSessionProofToken=stored.autoRouteLineageSessionProofToken,
        autoRouteLineageInterruptionToken=stored.autoRouteLineageInterruptionToken,
        snapshotToken=current.snapshotToken,
        stateFingerprint=current.stateFingerprint,
        sourceReadinessPolicyContract=current.sourceReadinessPolicyContract,
        sourceReadinessProofContract=current.sourceReadinessProofContract,
        sourceReadinessFingerprint=current.sourceReadinessFingerprint,
        professionKey=current.professionKey,
        mode=current.mode,
        currentBuild=current.currentBuild,
        recipe=recipeName,
        recipeID=recipeID,
        routeIndex=tonumber(plan.step.routeIndex),
        skillTarget=tonumber(plan.step.skillTarget),
        startedSkill=tonumber(currentProfession and currentProfession.skill),
        requestedCount=1,
    }
    local pending={
        token=token,
        key=current.professionKey,
        recipeID=recipeID,
        recipeName=recipeName,
        mode="one",
        requestedCount=1,
        completedCount=0,
        targetSkill=tonumber(plan.step.skillTarget),
        startedSkill=tonumber(currentProfession and currentProfession.skill),
        startedAt=actionNow(),
        status="dispatching",
        heartbeat=0,
        seenCastGUIDs={},
        materialSnapshot=materialSnapshot,
        difficultySnapshot=captureRecipeDifficulty(recipeID,recipeName),
        researchNativeExecution=provenance.contract=="research-native-dispatch-provenance-v1",
        productionTailoringNativeExecution=provenance.contract=="production-tailoring-native-dispatch-provenance-v1",
        authorityProvenance=provenance,
    }
    pending.currentDifficulty=pending.difficultySnapshot

    local ledgerID=ledger:Begin("craft",pending)
    if not ledgerID then
        report.state = "native-single-craft-ledger-reservation-failed"
        return false, report.state, report
    end
    pending.ledgerID=ledgerID
    pending.transactionID=ledgerID
    self.pendingCraft=pending
    self.activeRepeat=nil
    report.transactionReserved=true
    report.ledgerID=ledgerID
    report.transactionID=ledgerID

    local recoveryCaptured = recovery:CapturePending("craft",pending)
    if not recoveryCaptured then
        self:CompletePendingCraft("failed","unable to reserve transaction recovery checkpoint before native dispatch","pre-dispatch",true)
        if recovery.ClearPending then recovery:ClearPending("native-dispatch-recovery-reservation-failed") end
        report.rollbackComplete=self.pendingCraft==nil
        report.state="native-single-craft-recovery-reservation-failed"
        return false,report.state,report
    end
    report.recoveryReserved=true
    report.boundaryValidated=true
    report.executionEligible=true
    report.executionAuthorityEnabled=true
    report.dispatchAllowed=true
    report.nativeDispatchAllowed=true
    report.recipe=recipeName
    report.recipeID=recipeID
    report.currentBuild=current.currentBuild
    report.snapshotToken=current.snapshotToken
    report.stateFingerprint=current.stateFingerprint
    report.nativeCraftable=nativeCraftable
    report.wouldDispatchCount=1

    -- This is alpha76's only irreversible operation. Every mutable transaction
    -- boundary above is installed first so synchronous result events and reload
    -- recovery can correlate the exact reservation and recipe.
    report.nativeDispatchAttempted=true
    local ok,err=craftRecipe(recipeID,1,{
        professionKey=current.professionKey,
        policy=authorityModuleName=="ProductionTailoringNativeExecutionAuthority" and "PRODUCTION_GUARDED_CRAFT_ONE" or "RESEARCH_GUARDED_CRAFT_ONE",
        guardPolicy=true,
        boundaryValidated=true,
        ledgerReserved=true,
        recoveryReserved=true,
        transactionID=pending.transactionID or pending.ledgerID,
        authorityContract=nativeAuthority.contract,
        boundaryContract=nativeAuthority.boundaryContract,
    })
    if not ok then
        self:CompletePendingCraft("failed","unable to dispatch guarded research craft: "..tostring(err or "unknown client error"),"native-api",true)
        if recovery.ClearPending then recovery:ClearPending("native-dispatch-api-failure") end
        report.rollbackComplete=self.pendingCraft==nil
        report.state="native-single-craft-dispatch-failed"
        report.detail=tostring(err or "unknown client error")
        return false,report.state,report
    end
    report.nativeDispatchAccepted=true

    -- CraftRecipe can synchronously complete on some Forever clients. If the
    -- normal result pipeline already closed this exact transaction, surface the
    -- terminal state without recreating pending state.
    if not self.pendingCraft or self.pendingCraft.token~=token then
        local last=self.lastCraft
        report.confirmedSynchronously=last and last.token==token and last.status=="success" or false
        report.completedCount=last and last.token==token and last.completedCount or 0
        report.state=report.confirmedSynchronously and "native-single-craft-dispatched-and-confirmed" or "native-single-craft-dispatched"
        return true,report.state,report
    end

    if self.pendingCraft.status=="dispatching" then self.pendingCraft.status="pending" end
    self:TouchPendingCraft(self.pendingCraft.status)
    report.state="native-single-craft-dispatched"
    return true,report.state,report
end


function Crafting:NativeResearchSingleCraftBoundary(reservation, options)
    return nativeSingleCraftBoundary(self, reservation, options, "ResearchNativeExecutionAuthority")
end

function Crafting:NativeTailoringSingleCraftBoundary(reservation, options)
    return nativeSingleCraftBoundary(self, reservation, options, "ProductionTailoringNativeExecutionAuthority")
end


local function nativeResearchCraftAllReport(authorization)
    return {
        contract = "native-current-recipe-craft-all-boundary-v1",
        state = "native-current-recipe-craft-all-blocked",
        professionKey = authorization and authorization.professionKey or nil,
        mode = authorization and authorization.mode or nil,
        authorizationToken = authorization and authorization.token or nil,
        snapshotToken = authorization and authorization.snapshotToken or nil,
        stateFingerprint = authorization and authorization.stateFingerprint or nil,
        recipe = authorization and authorization.recipe or nil,
        recipeID = authorization and authorization.recipeID or nil,
        routeIndex = authorization and authorization.routeIndex or nil,
        skillTarget = authorization and authorization.skillTarget or nil,
        requestedCount = authorization and authorization.requestedCount or nil,
        recipeLocked = true,
        targetFirst = true,
        materialExhaustionSecond = true,
        automaticRouteAdvance = false,
        boundaryValidated = false,
        nativeDispatchAttempted = false,
        nativeDispatchAccepted = false,
        transactionReserved = false,
        recoveryReserved = false,
        singleUseConsumed = false,
        persistedAuthorization = false,
    }
end

local function nativeCraftAllBoundary(self, authorization, options, authorityModuleName)
    local report = nativeResearchCraftAllReport(authorization)
    local authority = JLP:GetModule(authorityModuleName)
    if not authority or not authority.ValidateAuthorization then
        report.state = "native-current-recipe-craft-all-authority-unavailable"
        return false, report.state, report
    end

    local valid, validationState, current, stored = authority:ValidateAuthorization(authorization, options)
    report.authorizationValidationState = validationState
    if type(authorization) == "table" and authorization.token then
        report.singleUseConsumed = authority:RevokeAuthorization(authorization.token, "native-craft-all-boundary-attempt") and true or false
    end
    if not valid or not current or not stored then
        report.state = "native-current-recipe-craft-all-authorization-rejected"
        report.readinessState = current and current.state or nil
        return false, report.state, report
    end

    local plan = current.plan
    local step = plan and plan.step or nil
    local recipeID = tonumber(current.recipeID)
    local recipeName = tostring(current.recipe or "")
    local routeIndex = tonumber(step and step.routeIndex)
    local skillTarget = tonumber(step and step.skillTarget)
    local api = JLP:GetModule("ProfessionAPI")
    local currentProfession = api and api.Get and api:Get(current.professionKey) or nil
    local currentSkill = tonumber(currentProfession and currentProfession.skill)
    local nativeCraftable,countStatus,countReason=self:GetCraftableCount(recipeID)
    report.craftabilityStatus=countStatus
    report.craftabilityReason=countReason
    if countStatus~="KNOWN" then
        report.state="native-current-recipe-craft-all-craftability-unavailable"
        return false,report.state,report
    end

    local identityReady = plan ~= nil and plan.actionKind == "craft" and step ~= nil
        and recipeID ~= nil and recipeName ~= ""
        and tostring(stored.professionKey or "") == tostring(current.professionKey or "")
        and tostring(stored.mode or "") == tostring(current.mode or "")
        and tonumber(stored.currentBuild) == tonumber(current.currentBuild)
        and tostring(stored.snapshotToken or "") == tostring(current.snapshotToken or "")
        and tostring(stored.stateFingerprint or "") == tostring(current.stateFingerprint or "")
        and tostring(stored.recipe or "") == recipeName
        and tonumber(stored.recipeID) == recipeID
        and tonumber(stored.routeIndex) == routeIndex
        and tonumber(stored.skillTarget) == skillTarget
        and currentSkill ~= nil and skillTarget ~= nil and currentSkill < skillTarget
        and tonumber(stored.nativeCraftable) == tonumber(nativeCraftable)
        and tonumber(stored.requestedCount) >= 1 and tonumber(stored.requestedCount) <= tonumber(nativeCraftable)
        and tonumber(nativeCraftable) >= 1
        and stored.recipeLocked == true
        and stored.targetFirst == true
        and stored.materialExhaustionSecond == true
        and stored.automaticRouteAdvance == false
    if not identityReady then
        report.state = "native-current-recipe-craft-all-identity-mismatch"
        return false, report.state, report
    end

    if self.pendingCraft or self.pendingEnchant or self.activeRepeat then
        report.state = "native-current-recipe-craft-all-transaction-busy"
        return false, report.state, report
    end

    local recovery = JLP:GetModule("TransactionRecovery")
    if not recovery or not recovery.CanStart or not recovery.CapturePending then
        report.state = "native-current-recipe-craft-all-recovery-boundary-unavailable"
        return false, report.state, report
    end
    local recoveryOK, recoveryMessage = recovery:CanStart("craft", current.professionKey)
    if not recoveryOK then
        report.state = "native-current-recipe-craft-all-recovery-blocked"
        report.detail = recoveryMessage
        return false, report.state, report
    end

    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger or not ledger.Begin then
        report.state = "native-current-recipe-craft-all-ledger-unavailable"
        return false, report.state, report
    end

    local requestedCount = tonumber(stored.requestedCount)
    self.craftAttemptSerial = (tonumber(self.craftAttemptSerial) or 0) + 1
    local token = self.craftAttemptSerial
    local progressTracker = JLP:GetModule("ProgressTracker")
    local materialSnapshot = progressTracker and progressTracker.CaptureMaterialSnapshot and progressTracker:CaptureMaterialSnapshot(current.professionKey, plan) or nil
    local provenance = {
        contract = authority.provenanceContract,
        source = "profession-guide",
        authorityContract = authority.contract,
        boundaryContract = authority.boundaryContract,
        authorizationToken = stored.token,
        clickOriginToken = stored.clickOriginToken,
        clickOriginSource = stored.clickOriginSource,
        restartCandidateToken = stored.restartCandidateToken,
        restartAuthorizationToken = stored.restartAuthorizationToken,
        restartedFromInterruptionToken = stored.restartedFromInterruptionToken,
        restartedFromInterruptionCategory = stored.restartedFromInterruptionCategory,
        restartedFromInterruptionState = stored.restartedFromInterruptionState,
        restartedFromLedgerID = stored.restartedFromLedgerID,
        restartPriorRecipeID = tonumber(stored.restartPriorRecipeID),
        restartPriorRouteIndex = tonumber(stored.restartPriorRouteIndex),
        restartPriorSkillTarget = tonumber(stored.restartPriorSkillTarget),
        restartExplicitUserClick = stored.restartExplicitUserClick == true,
        freshRestartTransaction = stored.freshRestartTransaction == true,
        snapshotToken = current.snapshotToken,
        stateFingerprint = current.stateFingerprint,
        professionKey = current.professionKey,
        mode = current.mode,
        currentBuild = current.currentBuild,
        recipe = recipeName,
        recipeID = recipeID,
        routeIndex = routeIndex,
        skillTarget = skillTarget,
        startedSkill = currentSkill,
        requestedCount = requestedCount,
        recipeLocked = true,
        targetFirst = true,
        materialExhaustionSecond = true,
        automaticRouteAdvance = false,
        strictTargetSafeCraftAll = true,
        nativeDispatchPerOrdinal = 1,
    }
    local pending = {
        token = token,
        key = current.professionKey,
        recipeID = recipeID,
        recipeName = recipeName,
        mode = "all",
        requestedCount = requestedCount,
        completedCount = 0,
        targetSkill = skillTarget,
        startedSkill = currentSkill,
        startedAt = actionNow(),
        status = "dispatching",
        heartbeat = 0,
        seenCastGUIDs = {},
        materialSnapshot = materialSnapshot,
        difficultySnapshot = captureRecipeDifficulty(recipeID, recipeName),
        researchNativeCraftAll = authority.provenanceContract == "research-native-craft-all-provenance-v1",
        productionTailoringCraftAll = authority.provenanceContract == "production-tailoring-native-craft-all-provenance-v1",
        strictTargetSafeCraftAll = true,
        nativeDispatchPerOrdinal = 1,
        strictOrdinalDispatchCount = 0,
        strictOrdinalInFlight = false,
        authorityProvenance = provenance,
    }
    pending.currentDifficulty = pending.difficultySnapshot

    local ledgerID = ledger:Begin("craft", pending)
    if not ledgerID then
        report.state = "native-current-recipe-craft-all-ledger-reservation-failed"
        return false, report.state, report
    end
    pending.ledgerID = ledgerID
    pending.transactionID = ledgerID
    self.pendingCraft = pending
    self.activeRepeat = {
        token = token,
        key = current.professionKey,
        recipeID = recipeID,
        recipeName = recipeName,
        targetSkill = skillTarget,
        requestedCount = requestedCount,
        startedSkill = currentSkill,
        ledgerID = ledgerID,
        researchNativeCraftAll = authority.provenanceContract == "research-native-craft-all-provenance-v1",
        productionTailoringCraftAll = authority.provenanceContract == "production-tailoring-native-craft-all-provenance-v1",
        recipeLocked = true,
        strictTargetSafeCraftAll = true,
        nativeDispatchPerOrdinal = 1,
        automaticRouteAdvance = false,
    }
    report.transactionReserved = true
    report.ledgerID = ledgerID
    report.transactionID = ledgerID

    local recoveryCaptured = recovery:CapturePending("craft", pending)
    if not recoveryCaptured then
        self:CompletePendingCraft("failed", "unable to reserve transaction recovery checkpoint before guarded Craft All dispatch", "pre-dispatch", true)
        if recovery.ClearPending then recovery:ClearPending("guarded-craft-all-recovery-reservation-failed") end
        report.rollbackComplete = self.pendingCraft == nil
        report.state = "native-current-recipe-craft-all-recovery-reservation-failed"
        return false, report.state, report
    end

    report.recoveryReserved = true
    report.boundaryValidated = true
    report.recipe = recipeName
    report.recipeID = recipeID
    report.routeIndex = routeIndex
    report.skillTarget = skillTarget
    report.startedSkill = currentSkill
    report.currentBuild = current.currentBuild
    report.snapshotToken = current.snapshotToken
    report.stateFingerprint = current.stateFingerprint
    report.nativeCraftable = nativeCraftable
    report.requestedCount = requestedCount
    report.maxSessionCrafts = requestedCount
    report.nativeDispatchPerOrdinal = 1
    report.strictTargetSafeCraftAll = true
    report.restartCandidateToken = stored.restartCandidateToken
    report.restartAuthorizationToken = stored.restartAuthorizationToken
    report.restartedFromInterruptionToken = stored.restartedFromInterruptionToken
    report.restartedFromInterruptionCategory = stored.restartedFromInterruptionCategory
    report.restartedFromLedgerID = stored.restartedFromLedgerID
    report.restartExplicitUserClick = stored.restartExplicitUserClick == true
    report.freshRestartTransaction = stored.freshRestartTransaction == true
    report.wouldDispatchCount = 1

    report.nativeDispatchAttempted = true
    local ok, dispatchState = self:DispatchNextResearchCraftAllOrdinal(pending,"initial")
    if not ok then
        report.rollbackComplete = self.pendingCraft == nil
        report.state = dispatchState or "native-current-recipe-craft-all-dispatch-failed"
        report.detail = tostring(pending.strictDispatchFailure or dispatchState or "strict ordinal dispatch failed")
        return false, report.state, report
    end
    report.nativeDispatchAccepted = true
    report.strictOrdinalState = dispatchState

    if not self.pendingCraft or self.pendingCraft.token ~= token then
        local last = self.lastCraft
        report.confirmedSynchronously = last and last.token == token and last.status == "success" or false
        report.completedCount = last and last.token == token and last.completedCount or 0
        report.state = "native-current-recipe-craft-all-dispatched-and-settled"
        return true, report.state, report
    end

    report.state = "native-current-recipe-craft-all-dispatched"
    return true, report.state, report
end

function Crafting:NativeResearchCraftAllBoundary(authorization, options)
    return nativeCraftAllBoundary(self, authorization, options, "ResearchNativeCraftAllAuthority")
end

function Crafting:NativeTailoringCraftAllBoundary(authorization, options)
    return nativeCraftAllBoundary(self, authorization, options, "ProductionTailoringCraftAllAuthority")
end

function Crafting:ExecuteCraft(key, plan, mode)
    -- Prevent the legacy all-mode single-dispatch fallback and queued all-mode replay.
    if mode == "all" then return false,"GUARDED_CRAFT_ALL_AUTHORITY_REQUIRED" end
    if not plan or plan.actionKind ~= "craft" or not plan.step or not plan.step.recipe then
        return false, "The current guide step is not a craftable recipe."
    end
    if plan.executionEligible == false or plan.step.executionEligible == false then
        return false, "This Planner route has read authority only; execution authority is disabled."
    end
    if plan.routeAuthorityEnabled == true or plan.researchAuthority == true or plan.step.researchAuthority == true
        or (plan.step.dataset and plan.step.dataset.contract == "controlled-research-planner-dataset-v1") then
        return false, "Research execution-readiness is evaluation-only; execution authority and dispatch remain disabled."
    end
    if key == "ENCHANTING" then
        return false, "Enchanting uses the Enchant action and an Optional Target."
    end
    if self.pendingCraft then
        return false, "A profession craft is already in progress. Wait for the current craft to finish."
    end
    if self.pendingEnchant then
        return false, "An enchant is already in progress. Wait for the current cast to finish."
    end
    local recovery=JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CanStart then
        local allowed,message=recovery:CanStart("craft",key)
        if not allowed then return false,message end
    end

    local recipeName = plan.step.recipe
    local recipeID = self:ResolveRecipeID(key, recipeName)
    if not recipeID then return self:QueueAfterOpen(key, plan, mode) end
    -- A deferred profession-open request is only discovery state. A fresh
    -- direct user click may use the resolved recipe, but must never inherit
    -- an earlier event's authorization or target selection.
    self.pending = nil

    local api = JLP:GetModule("ProfessionAPI")
    local currentProfession = api and api:Get(key) or nil
    local targetSkill = tonumber(plan.step.skillTarget)
    if targetSkill and currentProfession and tonumber(currentProfession.skill) and tonumber(currentProfession.skill) >= targetSkill then
        return false, "The target skill " .. tostring(targetSkill) .. " has already been reached."
    end
    -- CraftReadiness.immediateBags is a plan/Inventory-cache estimate; it
    -- cannot override a negative live TradeSkillUI material verdict.  A recipe
    -- may consume different reagent amounts than an older route snapshot.
    local craftable,status,reason=self:GetCraftableCount(recipeID)
    if status~="KNOWN" then
        return false,"Live craftability could not be verified ("..tostring(reason or status).."). Refresh the profession window and try again; material availability is unknown."
    end
    if craftable==0 then
        return false,"The current profession API confirms zero crafts available for "..tostring(recipeName)..". Check reagents, recipe and profession window."
    end

    -- Native multi-craft dispatch cannot be stopped at an intermediate skill target.
    -- The sole multi-ordinal route is NativeTailoringCraftAllBoundary, which
    -- issues one ordinal at a time after an explicit, bound Guide click.
    if mode == "all" and craftable > 1 then
        return false, "TARGET_UNSAFE_NATIVE_BATCH: use guarded Craft All or Craft X; manual batch dispatch disabled."
    end
    local count = 1
    self.craftAttemptSerial=(self.craftAttemptSerial or 0)+1
    local token=self.craftAttemptSerial
    local progressTracker=JLP:GetModule("ProgressTracker")
    local materialSnapshot=progressTracker and progressTracker.CaptureMaterialSnapshot and progressTracker:CaptureMaterialSnapshot(key,plan) or nil
    self.pendingCraft={
        token=token,
        key=key,
        recipeID=recipeID,
        recipeName=recipeName,
        mode=mode=="all" and "all" or "one",
        requestedCount=count,
        completedCount=0,
        targetSkill=targetSkill,
        startedSkill=tonumber(currentProfession and currentProfession.skill),
        startedAt=actionNow(),
        status="dispatching",
        heartbeat=0,
        seenCastGUIDs={},
        materialSnapshot=materialSnapshot,
        difficultySnapshot=captureRecipeDifficulty(recipeID,recipeName),
    }
    self.pendingCraft.currentDifficulty=self.pendingCraft.difficultySnapshot
    local ledger=JLP:GetModule("TransactionLedger")
    if ledger and ledger.Begin then
        local ledgerID=ledger:Begin("craft",self.pendingCraft)
        self.pendingCraft.ledgerID=ledgerID
        self.pendingCraft.transactionID=ledgerID
    end
    if mode == "all" and count > 1 then
        self.activeRepeat = {
            token=token,
            key = key,
            recipeID = recipeID,
            recipeName = recipeName,
            targetSkill = targetSkill,
            requestedCount=count,
            startedSkill = tonumber(currentProfession and currentProfession.skill),
            ledgerID = self.pendingCraft.ledgerID,
        }
    else
        self.activeRepeat = nil
    end

    local ok, err = craftRecipe(recipeID, count,{
        professionKey=key,
        policy=mode=="all" and "MANUAL_DIRECT_CRAFT_ALL" or "MANUAL_DIRECT_CRAFT_ONE",
        transactionID=self.pendingCraft and (self.pendingCraft.transactionID or self.pendingCraft.ledgerID) or nil,
        boundaryContract="manual-direct-craft-policy-v1",
    })
    if not ok then
        local _,message=self:CompletePendingCraft("failed","unable to dispatch craft: "..tostring(err or "unknown client error"),"api",true)
        return false,message
    end

    -- A synchronous client event can complete a one-craft transaction during
    -- CraftRecipe().  Do not recreate pending state after that completion.
    if not self.pendingCraft or self.pendingCraft.token~=token then
        local last=self.lastCraft
        return last and last.status=="success" or false,nil
    end
    if self.pendingCraft.status=="dispatching" then self.pendingCraft.status="pending" end
    self:TouchPendingCraft(self.pendingCraft.status)
    return true, mode == "all" and ("Craft All started for " .. tostring(recipeName) .. ". Current recipe only; stops at target skill or material exhaustion.") or ("Crafting one " .. tostring(recipeName) .. ".")
end

-- Opening the profession window is a *read-only recipe discovery* step.
-- TRADE_SKILL_UPDATE is an asynchronous client event, not a hardware click.
-- Never queue an executable closure or preserve an authorization through it.
function Crafting:QueueAfterOpen(key, plan, mode, selectedGUID)
    local api = JLP:GetModule("ProfessionAPI")
    if not api or type(api.Open) ~= "function" then return false, "Profession API is unavailable." end
    self.pending = {
        key = key,
        recipeName = plan and plan.step and plan.step.recipe,
        mode = mode,
        targetSkill = plan and plan.step and tonumber(plan.step.skillTarget),
        -- For diagnostics only: this GUID is never restored or submitted from
        -- an event. Enchant One must revalidate the live selection on new click.
        selectedGUID = selectedGUID,
        discoveryOnly = true,
    }
    local ok, message = api:Open(key)
    if not ok then self.pending = nil; return false, message end
    return true, "Opening the profession to resolve the recipe. Click the action again after it is available; no craft was started."
end

-- Retained public method name for event-hook compatibility. This routine now
-- performs discovery ONLY: it cannot call ExecuteCraft(), Enchant(), or any
-- native dispatch. A second explicit Guide/ContextAction OnClick is required.
function Crafting:ExecutePending()
    local pending = self.pending
    if not pending then return false end
    local planner = JLP:GetModule("Planner")
    local plan = planner and planner.GetProfessionPlan and planner:GetProfessionPlan(pending.key) or nil
    if not plan or not plan.step or tostring(plan.step.recipe or "") ~= tostring(pending.recipeName or "") then
        self.pending = nil
        return false, "recipe-plan-changed"
    end
    local recipeID = self:ResolveRecipeID(pending.key, pending.recipeName)
    if not recipeID then return false, "recipe-not-resolved" end
    -- Drop the deferred state before notifying UI. Never auto-select a stored
    -- enchant target, make a ledger reservation or issue a protected action.
    self.pending = nil
    if JLP.Print then
        JLP:Print("Recipe resolved for " .. tostring(pending.key) .. ": " .. tostring(pending.recipeName) .. ". Click the action again to craft; the previous click was used only to open the profession.")
    end
    return true, "recipe-resolved-await-new-click"
end

local function validItemIcon(value)
    if value == nil or value == false or value == 0 or value == "" then return nil end
    return value
end

local function itemObjectForGUID(guid)
    if not guid or type(Item)~="table" or type(Item.CreateFromItemGUID)~="function" then return nil,nil end
    local candidates={}
    local ok,value=pcall(function() return Item:CreateFromItemGUID(guid) end)
    if ok and value then candidates[#candidates+1]=value end
    local okDot,valueDot=pcall(Item.CreateFromItemGUID,guid)
    if okDot and valueDot and valueDot~=value then candidates[#candidates+1]=valueDot end
    for _,candidate in ipairs(candidates) do
        if type(candidate)=="table" and type(candidate.GetItemID)=="function" then
            local okID,valueID=pcall(candidate.GetItemID,candidate)
            local id=okID and tonumber(valueID) or nil
            if id then return candidate,id end
        end
    end
    return candidates[1],nil
end

local function itemDescriptor(guid)
    if not guid or type(C_Item) ~= "table" then return nil end
    local itemObject, objectID=itemObjectForGUID(guid)
    local location
    if type(C_Item.GetItemLocation) == "function" then
        local okLoc, value = pcall(C_Item.GetItemLocation, guid)
        if okLoc then location=value end
    end
    if not location and itemObject and type(itemObject.GetItemLocation)=="function" then
        local okLoc,value=pcall(itemObject.GetItemLocation,itemObject)
        if okLoc then location=value end
    end

    local itemID, link, icon, iconSource
    itemID=objectID
    if location and type(C_Item.GetItemID) == "function" then local ok,v=pcall(C_Item.GetItemID,location); if ok then itemID=tonumber(v) or itemID end end
    if not itemID and type(C_Item.GetItemIDByGUID) == "function" then local ok,v=pcall(C_Item.GetItemIDByGUID,guid); if ok then itemID=tonumber(v) end end
    if location and type(C_Item.GetItemLink) == "function" then local ok,v=pcall(C_Item.GetItemLink,location); if ok then link=v end end
    if not link and type(C_Item.GetItemLinkByGUID) == "function" then local ok,v=pcall(C_Item.GetItemLinkByGUID,guid); if ok then link=v end end
    if not link and itemObject and type(itemObject.GetItemLink)=="function" then local ok,v=pcall(itemObject.GetItemLink,itemObject); if ok then link=v end end

    -- Some Forever target paths expose the exact link or an Item object before
    -- C_Item can resolve the GUID directly. Derive the base item ID through all
    -- modern identity surfaces before attempting texture lookup.
    if not itemID and type(link)=="string" then itemID=tonumber(link:match("item:(%d+)")) end
    if not itemID and link and type(C_Item.GetItemIDForItemInfo)=="function" then
        local ok,v=pcall(C_Item.GetItemIDForItemInfo,link)
        if ok then itemID=tonumber(v) end
    end

    if location and type(C_Item.GetItemIcon) == "function" then
        local ok,v=pcall(C_Item.GetItemIcon,location)
        if ok then icon=validItemIcon(v); if icon then iconSource="location" end end
    end
    if not icon and type(C_Item.GetItemIconByGUID)=="function" then
        local ok,v=pcall(C_Item.GetItemIconByGUID,guid)
        if ok then icon=validItemIcon(v); if icon then iconSource="guid" end end
    end
    if not icon and itemObject and type(itemObject.GetItemIcon)=="function" then
        local ok,v=pcall(itemObject.GetItemIcon,itemObject)
        if ok then icon=validItemIcon(v); if icon then iconSource="item-object" end end
    end
    if not icon and itemID and type(C_Item.GetItemIconByID) == "function" then
        local ok,v=pcall(C_Item.GetItemIconByID,itemID)
        if ok then icon=validItemIcon(v); if icon then iconSource="item-id" end end
    end
    if not icon and type(C_Item.GetItemInfoInstant)=="function" then
        local ok,instantID,_,_,_,instantIcon=pcall(C_Item.GetItemInfoInstant,itemID or link or guid)
        if ok then
            itemID=itemID or tonumber(instantID)
            icon=validItemIcon(instantIcon) or icon
            if icon then iconSource="instant" end
        end
    end
    if not icon and type(GetItemInfoInstant)=="function" then
        local ok,instantID,_,_,_,instantIcon=pcall(GetItemInfoInstant,itemID or link or guid)
        if ok then
            itemID=itemID or tonumber(instantID)
            icon=validItemIcon(instantIcon) or icon
            if icon then iconSource="legacy-instant" end
        end
    end

    local name
    -- Forever 1.60 uses the modern C_Item namespace. Query it before the legacy
    -- global so cached item records can supply both the exact link/name and icon.
    if type(C_Item.GetItemInfo) == "function" then
        local ok, liveName, liveLink, _, _, _, _, _, _, _, liveIcon = pcall(C_Item.GetItemInfo, itemID or link or guid)
        if ok then
            name=liveName
            link=liveLink or link
            if not icon then icon=validItemIcon(liveIcon); if icon then iconSource="item-info" end end
        end
    end
    if not name and itemObject and type(itemObject.GetItemName)=="function" then
        local ok,v=pcall(itemObject.GetItemName,itemObject)
        if ok and v and v~="" then name=v end
    end
    if type(GetItemInfo) == "function" and (not name or not icon) then
        local ok, liveName, liveLink, _, _, _, _, _, _, _, liveIcon = pcall(GetItemInfo, itemID or link or guid)
        if ok then
            name=name or liveName
            link=liveLink or link
            if not icon then icon=validItemIcon(liveIcon); if icon then iconSource="legacy-item-info" end end
        end
    end

    if not icon and itemID and type(C_Item.RequestLoadItemDataByID)=="function" then
        pcall(C_Item.RequestLoadItemDataByID,itemID)
    end

    return {
        guid=guid,
        location=location,
        itemID=itemID,
        name=name or (link and link:match("%[(.-)%]")) or "Enchant target",
        link=link,
        icon=icon,
        iconSource=iconSource,
    }
end

function Crafting:RefreshEnchantTargetDescriptor(target)
    if type(target)~="table" or not target.guid then return target end
    return itemDescriptor(target.guid) or target
end

local function guidStillInInventory(guid)
    if not guid or type(C_Item) ~= "table" or type(C_Item.IsItemGUIDInInventory) ~= "function" then return nil end
    local ok,value=pcall(C_Item.IsItemGUIDInInventory,guid)
    if not ok then return nil end
    return value and true or false
end

function Crafting:GetEnchantTargets(key, plan)
    if not plan or not plan.step or not plan.step.recipe then return {}, nil end
    local recipeID = self:ResolveRecipeID(key, plan.step.recipe)
    if not recipeID then return {}, nil end

    -- GetEnchantItems() is the same source Blizzard uses to populate the native
    -- Optional Target strip. On Forever it can briefly return a partial list
    -- after a target is selected. Never let a partial refresh shrink a previously
    -- known-good option set while those item GUIDs still exist in inventory.
    local merged, liveSeen = {}, {}
    local cached = self.enchantTargetOptions[recipeID]
    if type(cached)=="table" then
        for _,row in ipairs(cached) do
            if row and row.guid then
                local present=guidStillInInventory(row.guid)
                if present~=false then
                    merged[row.guid]=itemDescriptor(row.guid) or row
                end
            end
        end
    end

    local liveAvailable=false
    if type(C_TradeSkillUI)=="table" and type(C_TradeSkillUI.GetEnchantItems)=="function" then
        local ok,guids=pcall(C_TradeSkillUI.GetEnchantItems,recipeID)
        if ok and type(guids)=="table" then
            liveAvailable=true
            -- Do not pre-filter with IsEnchantTargetValid here. GetEnchantItems()
            -- already represents the client's target choices and the extra check
            -- can lag behind the native UI during a target transition.
            for _,guid in pairs(guids) do
                if guid then
                    liveSeen[guid]=true
                    local row=itemDescriptor(guid)
                    if row then merged[guid]=row end
                end
            end
        end
    end

    local out={}
    for _,row in pairs(merged) do out[#out+1]=row end
    table.sort(out,function(a,b)
        local an,bn=tostring(a.name or ""),tostring(b.name or "")
        if an==bn then return tostring(a.guid or "")<tostring(b.guid or "") end
        return an<bn
    end)

    if #out>0 then
        local nextCache={}
        for i,row in ipairs(out) do nextCache[i]=row end
        self.enchantTargetOptions[recipeID]=nextCache
        return out,recipeID,false
    end

    local needsContext = ((not liveAvailable or #out == 0) and professionOpenKey() ~= key) and true or false
    return out,recipeID,needsContext
end

local function targetCachedForRecipe(self, recipeID, guid)
    local cached=self and self.enchantTargetOptions and self.enchantTargetOptions[tonumber(recipeID)]
    if type(cached)~="table" then return false end
    for _,row in ipairs(cached) do
        if row and row.guid==guid then return true end
    end
    return false
end

local function targetListedForRecipe(recipeID, guid)
    if not recipeID or not guid or type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.GetEnchantItems) ~= "function" then return false end
    local ok, guids = pcall(C_TradeSkillUI.GetEnchantItems, recipeID)
    if not ok or type(guids) ~= "table" then return false end
    for _, value in pairs(guids) do
        if value == guid then return true end
    end
    return false
end

local function emitEnchantTargetUpdated(recipeID, target, reason)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_ENCHANTING_TARGET_UPDATED", {
            professionKey="ENCHANTING",
            recipeID=tonumber(recipeID),
            targetGUID=target and target.guid or nil,
            targetItemID=target and tonumber(target.itemID) or nil,
            reason=tostring(reason or "selection-updated"),
        })
    end
end

function Crafting:SelectEnchantTarget(recipeID, target)
    recipeID = tonumber(recipeID)
    if not recipeID or type(target) ~= "table" or not target.guid then return false end
    -- Target rows originate from GetEnchantTargets(), which mirrors the same
    -- GUID source used by Blizzard's native Optional Target strip. Replace the
    -- prior selection atomically; transient live-list changes must not pin the
    -- first selected item forever. Final validity is checked when enchanting.
    local fresh = itemDescriptor(target.guid) or target
    if not fresh or not fresh.guid then return false end
    self.enchantTargets[recipeID] = fresh
    emitEnchantTargetUpdated(recipeID, fresh, "selected")
    return true
end

function Crafting:SetEnchantTarget(recipeID, guid)
    recipeID = tonumber(recipeID)
    if not recipeID then return false end
    if not guid then
        self.enchantTargets[recipeID]=nil
        emitEnchantTargetUpdated(recipeID, nil, "cleared")
        return true
    end
    local row = itemDescriptor(guid)
    if not row then return false end
    local valid = targetListedForRecipe(recipeID, guid)
    if not valid and type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.IsEnchantTargetValid) == "function" then
        local ok, value = pcall(C_TradeSkillUI.IsEnchantTargetValid, recipeID, guid)
        if ok then valid = value and true or false end
    end
    if not valid then return false end
    self.enchantTargets[recipeID] = row
    emitEnchantTargetUpdated(recipeID, row, "selected")
    return true
end

function Crafting:GetSelectedEnchantTarget(key, plan)
    if not plan or not plan.step or not plan.step.recipe then return nil,nil end
    local recipeID = self:ResolveRecipeID(key, plan.step.recipe)
    if not recipeID then return nil,nil end
    local selected = self.enchantTargets[recipeID]
    if selected then
        local fresh = itemDescriptor(selected.guid) or selected
        local present=guidStillInInventory(selected.guid)
        -- Preserve a selected target across transient partial GetEnchantItems()
        -- responses as long as it is still one of this recipe's cached targets
        -- and the GUID has not disappeared from inventory/equipment.
        if fresh and present~=false and (targetCachedForRecipe(self,recipeID,selected.guid) or targetListedForRecipe(recipeID,selected.guid)) then
            self.enchantTargets[recipeID]=fresh
            return fresh,recipeID
        end
        if fresh and present~=false and type(C_TradeSkillUI)=="table" and type(C_TradeSkillUI.IsEnchantTargetValid)=="function" then
            local ok,value=pcall(C_TradeSkillUI.IsEnchantTargetValid,recipeID,selected.guid)
            if ok and value then self.enchantTargets[recipeID]=fresh; return fresh,recipeID end
        end
        self.enchantTargets[recipeID]=nil
    end
    return nil,recipeID
end

function Crafting:GetEnchantActionState(key, plan)
    local recipeID=plan and plan.step and plan.step.recipe and self:ResolveRecipeID(key,plan.step.recipe) or nil
    if self.pendingEnchant and self.pendingEnchant.key==key then
        return {
            status=self.pendingEnchant.status or "pending",
            key=self.pendingEnchant.key,
            recipeID=self.pendingEnchant.recipeID,
            recipeName=self.pendingEnchant.recipeName,
            targetGUID=self.pendingEnchant.targetGUID,
            targetName=self.pendingEnchant.targetName,
            targetSkill=self.pendingEnchant.targetSkill,
            startedSkill=self.pendingEnchant.startedSkill,
            token=self.pendingEnchant.token,
            confirmationRequired=self.pendingEnchant.confirmationRequired and true or false,
            confirmationEvent=self.pendingEnchant.confirmationEvent,
            confirmationReason=self.pendingEnchant.confirmationReason,
        }
    end
    local recovery=JLP:GetModule("TransactionRecovery")
    local recoveryState=recovery and recovery.GetActionState and recovery:GetActionState(key,"enchant") or nil
    if recoveryState then return recoveryState end
    if self.lastEnchant and self.lastEnchant.key==key and recentAction(self.lastEnchant) then
        self.lastEnchant.currentRecipeID=recipeID
        self.lastEnchant.recipeChanged=recipeID and tonumber(self.lastEnchant.recipeID)~=tonumber(recipeID) or false
        return self.lastEnchant
    end
    return {status="idle",key=key,recipeID=recipeID}
end

function Crafting:ReconcileEnchantTarget(recipeID)
    recipeID=tonumber(recipeID)
    if not recipeID then return nil end
    local selected=self.enchantTargets[recipeID]
    if not selected or not selected.guid then return nil end
    local present=guidStillInInventory(selected.guid)
    local fresh=itemDescriptor(selected.guid) or selected
    if present==false or not fresh then
        self.enchantTargets[recipeID]=nil
        return nil
    end
    self.enchantTargets[recipeID]=fresh
    return fresh
end

local function enchantLocationKey(location)
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

function Crafting:GetEnchantExecutionTarget(recipeID)
    recipeID=tonumber(recipeID)
    local selected=recipeID and self.enchantTargets[recipeID] or nil
    if not selected or not selected.guid then return nil,"Select an Optional Target before enchanting." end

    local present=guidStillInInventory(selected.guid)
    if present==false then
        self.enchantTargets[recipeID]=nil
        return nil,"The selected Optional Target is no longer in your inventory or equipment."
    end

    -- Resolve ItemLocation again immediately before CraftEnchant.  A selected
    -- item can move between bags/equipment after the picker click; the GUID is
    -- the stable identity, while ItemLocation is intentionally treated as live.
    local fresh=itemDescriptor(selected.guid) or selected
    if not fresh or not fresh.location then
        return nil,"The selected Optional Target no longer has a usable ItemLocation."
    end

    local valid=targetListedForRecipe(recipeID,selected.guid)
    if not valid and type(C_TradeSkillUI)=="table" and type(C_TradeSkillUI.IsEnchantTargetValid)=="function" then
        local ok,value=pcall(C_TradeSkillUI.IsEnchantTargetValid,recipeID,selected.guid)
        if ok and value then valid=true end
    end
    -- Forever can briefly publish a partial GetEnchantItems() list during a
    -- target transition.  A picker row already validated by the client remains
    -- usable while its exact GUID still exists, but unknown/stale GUIDs do not.
    if not valid and not targetCachedForRecipe(self,recipeID,selected.guid) then
        self.enchantTargets[recipeID]=nil
        return nil,"The selected Optional Target is no longer valid for this enchant."
    end

    self.enchantTargets[recipeID]=fresh
    return fresh
end

local function nativeEnchantingBoundaryReport(reservation)
    return {
        contract = "production-enchanting-native-single-enchant-boundary-v1",
        state = "production-enchanting-native-single-enchant-boundary-blocked",
        professionKey = reservation and reservation.professionKey or "ENCHANTING",
        mode = reservation and reservation.mode or "normal",
        craftMode = reservation and reservation.craftMode or nil,
        reservationToken = reservation and reservation.token or nil,
        snapshotToken = reservation and reservation.snapshotToken or nil,
        stateFingerprint = reservation and reservation.stateFingerprint or nil,
        recipe = reservation and reservation.recipe or nil,
        recipeID = reservation and tonumber(reservation.recipeID) or nil,
        targetGUID = reservation and reservation.targetGUID or nil,
        targetItemID = reservation and tonumber(reservation.targetItemID) or nil,
        targetLocationKey = reservation and reservation.targetLocationKey or nil,
        targetProofContract = reservation and reservation.targetProofContract or nil,
        targetProofFingerprint = reservation and reservation.targetProofFingerprint or nil,
        executionEligible = false,
        executionAuthorityEnabled = false,
        dispatchAllowed = false,
        nativeDispatchAllowed = false,
        nativeDispatchAttempted = false,
        nativeDispatchAccepted = false,
        confirmationAutomationAllowed = false,
        protectedConfirmationInvoked = false,
        transactionReserved = false,
        recoveryReserved = false,
        rollbackComplete = false,
        persistedAuthorization = false,
        boundaryValidated = false,
        singleUseConsumed = false,
    }
end

function Crafting:NativeEnchantingSingleCraftBoundary(reservation, options)
    local report = nativeEnchantingBoundaryReport(reservation)
    local nativeAuthority = JLP:GetModule("ProductionEnchantingNativeExecutionAuthority")
    if not nativeAuthority or not nativeAuthority.EvaluateReservation then
        report.state = "production-enchanting-native-authority-unavailable"
        return false, report.state, report
    end
    report.contract = nativeAuthority.boundaryContract or report.contract
    report.provenanceContract = nativeAuthority.provenanceContract
    report.confirmationContract = nativeAuthority.confirmationContract

    -- Re-run the complete authority/readiness chain at the irreversible boundary.
    local authorityModel, current, stored = nativeAuthority:EvaluateReservation(reservation, options)
    report.authorityState = authorityModel and authorityModel.state or nil
    report.blockedGate = authorityModel and authorityModel.blockedGate or nil
    report.blockedState = authorityModel and authorityModel.blockedState or nil
    report.reservationValidationState = authorityModel and authorityModel.reservationValidationState or nil

    -- The reservation is single use even when final revalidation fails. A new
    -- explicit Guide click is required for every subsequent attempt.
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    if eligibility and eligibility.RevokeReservation and type(reservation) == "table" and reservation.token then
        report.singleUseConsumed = eligibility:RevokeReservation(reservation.token, "production-enchanting-native-boundary-attempt") and true or false
    end

    if not authorityModel or authorityModel.nativeExecutionAuthorityReady ~= true or not current or not stored then
        report.state = "production-enchanting-native-authority-rejected"
        return false, report.state, report
    end

    local plan = current.plan
    local step = plan and plan.step or nil
    local recipeID = tonumber(current.recipeID)
    local recipeName = tostring(current.recipe or "")
    local identityReady = plan ~= nil and plan.actionKind == "craft" and step ~= nil
        and tostring(current.professionKey or "") == "ENCHANTING"
        and tostring(stored.professionKey or "") == "ENCHANTING"
        and tostring(current.mode or "") == tostring(stored.mode or "")
        and tostring(current.snapshotToken or "") == tostring(stored.snapshotToken or "")
        and tostring(current.stateFingerprint or "") == tostring(stored.stateFingerprint or "")
        and recipeID ~= nil and recipeName ~= ""
        and tonumber(stored.recipeID) == recipeID
        and tostring(stored.recipe or "") == recipeName
        and tostring(step.recipe or "") == recipeName
        and tonumber(stored.routeIndex) == tonumber(step.routeIndex)
        and tonumber(stored.skillTarget) == tonumber(step.skillTarget)
        and tostring(stored.craftMode or "") == "one"
        and tonumber(stored.requestedCount) == 1
        and tostring(stored.targetGUID or "") ~= ""
        and tonumber(stored.targetItemID) ~= nil
        and tostring(stored.targetLocationKey or "") ~= ""
        and tostring(stored.targetProofContract or "") ~= ""
        and tostring(stored.targetProofFingerprint or "") ~= ""
    if not identityReady then
        report.state = "production-enchanting-native-identity-mismatch"
        return false, report.state, report
    end

    if self.pendingCraft or self.pendingEnchant or self.activeRepeat then
        report.state = "production-enchanting-native-transaction-busy"
        return false, report.state, report
    end

    local recovery = JLP:GetModule("TransactionRecovery")
    if not recovery or not recovery.CanStart or not recovery.CapturePending then
        report.state = "production-enchanting-native-recovery-boundary-unavailable"
        return false, report.state, report
    end
    local recoveryOK, recoveryMessage = recovery:CanStart("enchant", "ENCHANTING")
    if not recoveryOK then
        report.state = "production-enchanting-native-recovery-blocked"
        report.detail = recoveryMessage
        return false, report.state, report
    end

    local ledger = JLP:GetModule("TransactionLedger")
    if not ledger or not ledger.Begin then
        report.state = "production-enchanting-native-ledger-unavailable"
        return false, report.state, report
    end
    local settlementOrchestrator = JLP:GetModule("ProductionEnchantingNativeSettlement")
    if not settlementOrchestrator
        or type(settlementOrchestrator.ObserveConfirmation) ~= "function"
        or type(settlementOrchestrator.HandleProvisionalFailure) ~= "function"
        or type(settlementOrchestrator.ConfirmFromCraftResult) ~= "function"
        or type(settlementOrchestrator.ConfirmFromSpellcastSuccess) ~= "function"
        or type(settlementOrchestrator.HandleTimeout) ~= "function" then
        report.state = "production-enchanting-native-settlement-unavailable"
        return false, report.state, report
    end

    -- Final target revalidation deliberately does NOT accept the UI cache as a
    -- substitute for native validity. Re-resolve ItemLocation from the bound GUID
    -- and require the exact alpha110 target identity immediately before dispatch.
    local selected = self.enchantTargets and self.enchantTargets[recipeID] or nil
    if not selected or tostring(selected.guid or "") ~= tostring(stored.targetGUID or "") then
        report.state = "production-enchanting-native-target-replaced"
        return false, report.state, report
    end
    if guidStillInInventory(selected.guid) ~= true then
        report.state = "production-enchanting-native-target-not-present"
        return false, report.state, report
    end
    local target = itemDescriptor(selected.guid)
    if not target or not target.location then
        report.state = "production-enchanting-native-target-location-unavailable"
        return false, report.state, report
    end
    local valid, validationSource = targetListedForRecipe(recipeID, selected.guid), nil
    if valid then
        validationSource = "GetEnchantItems"
    elseif type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.IsEnchantTargetValid) == "function" then
        local ok, value = pcall(C_TradeSkillUI.IsEnchantTargetValid, recipeID, selected.guid)
        if ok and value then valid, validationSource = true, "IsEnchantTargetValid" end
    end
    if not valid then
        report.state = "production-enchanting-native-target-not-ready"
        return false, report.state, report
    end

    local finalLocationKey = enchantLocationKey(target.location)
    local targetIdentityReady = tostring(target.guid or "") == tostring(stored.targetGUID or "")
        and tonumber(target.itemID) == tonumber(stored.targetItemID)
        and tostring(finalLocationKey or "") == tostring(stored.targetLocationKey or "")
        and tostring(current.targetGUID or "") == tostring(stored.targetGUID or "")
        and tonumber(current.targetItemID) == tonumber(stored.targetItemID)
        and tostring(current.targetLocationKey or "") == tostring(stored.targetLocationKey or "")
        and tostring(current.targetProofContract or "") == tostring(stored.targetProofContract or "")
        and tostring(current.targetProofFingerprint or "") == tostring(stored.targetProofFingerprint or "")
        and (not stored.targetValidationSource or tostring(validationSource or "") == tostring(stored.targetValidationSource or ""))
    if not targetIdentityReady then
        report.state = "production-enchanting-native-target-identity-drift"
        report.liveTargetLocationKey = finalLocationKey
        report.liveTargetValidationSource = validationSource
        return false, report.state, report
    end

    -- Re-check the production readiness source one final time after resolving the
    -- target. This catches reagent/window/recipe/recovery drift that happened
    -- after reservation evaluation but before the transaction is reserved.
    local readinessEvaluator = JLP:GetModule("ResearchExecutionReadiness")
    local finalReadiness = readinessEvaluator and readinessEvaluator.Evaluate and readinessEvaluator:Evaluate("ENCHANTING", current.mode, options) or nil
    if not finalReadiness or finalReadiness.executionReadinessReady ~= true
        or tostring(finalReadiness.state or "") ~= "execution-readiness-ready"
        or tonumber(finalReadiness.recipeID) ~= recipeID
        or tostring(finalReadiness.snapshotToken or "") ~= tostring(stored.snapshotToken or "")
        or tostring(finalReadiness.stateFingerprint or "") ~= tostring(stored.stateFingerprint or "")
        or tostring(finalReadiness.targetGUID or "") ~= tostring(stored.targetGUID or "")
        or tonumber(finalReadiness.targetItemID) ~= tonumber(stored.targetItemID)
        or tostring(finalReadiness.targetValidationSource or "") ~= tostring(stored.targetValidationSource or "")
        or tostring(finalReadiness.targetLocationKey or "") ~= tostring(stored.targetLocationKey or "")
        or tostring(finalReadiness.targetProofContract or "") ~= tostring(stored.targetProofContract or "")
        or tostring(finalReadiness.targetProofFingerprint or "") ~= tostring(stored.targetProofFingerprint or "") then
        report.state = "production-enchanting-native-final-readiness-stale"
        report.finalReadinessState = finalReadiness and finalReadiness.state or "unavailable"
        return false, report.state, report
    end

    self.enchantAttemptSerial = (tonumber(self.enchantAttemptSerial) or 0) + 1
    local token = self.enchantAttemptSerial
    local api = JLP:GetModule("ProfessionAPI")
    local currentProfession = api and api.Get and api:Get("ENCHANTING") or nil
    local progressTracker = JLP:GetModule("ProgressTracker")
    local materialSnapshot = progressTracker and progressTracker.CaptureMaterialSnapshot and progressTracker:CaptureMaterialSnapshot("ENCHANTING", plan) or nil
    local provenance = {
        contract = nativeAuthority.provenanceContract,
        source = stored.clickOriginSource or "profession-guide",
        authorityContract = nativeAuthority.contract,
        boundaryContract = nativeAuthority.boundaryContract,
        confirmationContract = nativeAuthority.confirmationContract,
        settlementContract = settlementOrchestrator and settlementOrchestrator.settlementContract or nil,
        confirmationLifecycleContract = settlementOrchestrator and settlementOrchestrator.confirmationLifecycleContract or nil,
        eligibilityContract = eligibility and eligibility.contract or nil,
        reservationToken = stored.token,
        clickOriginToken = stored.clickOriginToken,
        clickOriginSource = stored.clickOriginSource,
        snapshotToken = current.snapshotToken,
        stateFingerprint = current.stateFingerprint,
        sourceReadinessPolicyContract = current.sourceReadinessPolicyContract,
        sourceReadinessProofContract = current.sourceReadinessProofContract,
        sourceReadinessFingerprint = current.sourceReadinessFingerprint,
        professionKey = "ENCHANTING",
        mode = current.mode,
        currentBuild = current.currentBuild,
        recipe = recipeName,
        recipeID = recipeID,
        routeIndex = tonumber(step.routeIndex),
        skillTarget = tonumber(step.skillTarget),
        startedSkill = tonumber(currentProfession and currentProfession.skill),
        requestedCount = 1,
        targetGUID = stored.targetGUID,
        targetItemID = tonumber(stored.targetItemID),
        targetValidationSource = validationSource,
        targetLocationKey = finalLocationKey,
        targetProofContract = stored.targetProofContract,
        targetProofFingerprint = stored.targetProofFingerprint,
        confirmationAutomationAllowed = false,
        automaticExecutionAllowed = false,
        craftAllAllowed = false,
        autoRouteAllowed = false,
    }
    local pending = {
        token = token,
        key = "ENCHANTING",
        recipeID = recipeID,
        recipeName = recipeName,
        mode = "one",
        requestedCount = 1,
        completedCount = 0,
        targetGUID = target.guid,
        targetName = target.name,
        targetItemID = tonumber(target.itemID),
        targetLink = target.link,
        targetEnchantID = type(target.link) == "string" and tonumber(target.link:match("item:%d+:([%-]?%d+)")) or 0,
        targetLocation = target.location,
        targetLocationKey = finalLocationKey,
        targetProofContract = stored.targetProofContract,
        targetProofFingerprint = stored.targetProofFingerprint,
        targetValidationSource = validationSource,
        targetSkill = tonumber(step.skillTarget),
        startedSkill = tonumber(currentProfession and currentProfession.skill),
        startedAt = actionNow(),
        status = "dispatching",
        settlementState = "dispatched-awaiting-evidence",
        confirmationSignals = 0,
        confirmationDuplicateSignals = 0,
        confirmationHistory = {},
        settlementContract = settlementOrchestrator and settlementOrchestrator.settlementContract or nil,
        confirmationLifecycleContract = settlementOrchestrator and settlementOrchestrator.confirmationLifecycleContract or nil,
        materialSnapshot = materialSnapshot,
        difficultySnapshot = captureRecipeDifficulty(recipeID, recipeName),
        productionEnchantingNativeExecution = true,
        authorityProvenance = provenance,
    }
    pending.currentDifficulty = pending.difficultySnapshot

    local ledgerID = ledger:Begin("enchant", pending)
    if not ledgerID then
        report.state = "production-enchanting-native-ledger-reservation-failed"
        return false, report.state, report
    end
    pending.ledgerID = ledgerID
    pending.transactionID = ledgerID
    self.pendingEnchant = pending
    report.transactionReserved = true
    report.ledgerID = ledgerID
    report.transactionID = ledgerID

    local recoveryCaptured = recovery:CapturePending("enchant", pending)
    if not recoveryCaptured then
        self:CompletePendingEnchant("failed", "unable to reserve transaction recovery checkpoint before native enchant dispatch", "pre-dispatch", true)
        if recovery.ClearPending then recovery:ClearPending("production-enchanting-native-recovery-reservation-failed") end
        report.rollbackComplete = self.pendingEnchant == nil
        report.state = "production-enchanting-native-recovery-reservation-failed"
        return false, report.state, report
    end

    report.recoveryReserved = true
    report.boundaryValidated = true
    report.executionEligible = true
    report.executionAuthorityEnabled = true
    report.dispatchAllowed = true
    report.nativeDispatchAllowed = true
    report.recipe = recipeName
    report.recipeID = recipeID
    report.currentBuild = current.currentBuild
    report.snapshotToken = current.snapshotToken
    report.stateFingerprint = current.stateFingerprint
    report.targetGUID = target.guid
    report.targetItemID = tonumber(target.itemID)
    report.targetValidationSource = validationSource
    report.targetLocationKey = finalLocationKey
    report.targetProofContract = stored.targetProofContract
    report.targetProofFingerprint = stored.targetProofFingerprint
    report.wouldDispatchCount = 1

    -- Alpha111's only irreversible Enchanting operation. Ledger and recovery are
    -- installed first because result/confirmation events can be synchronous.
    report.nativeDispatchAttempted = true
    local nativeDispatch = JLP:GetModule("NativeDispatchService")
    local ok, dispatchState, dispatchAudit = nativeDispatch and nativeDispatch.Dispatch and nativeDispatch:Dispatch({
        contract = nativeDispatch.intentContract,
        professionKey = "ENCHANTING",
        strategy = "TARGETED_ENCHANT",
        policy = "PRODUCTION_GUARDED_ENCHANT_ONE",
        recipeID = recipeID,
        count = 1,
        itemTarget = target.location,
        targetGUID = target.guid,
        nativeDispatchAllowed = true,
        guardPolicy = true,
        boundaryValidated = true,
        ledgerReserved = true,
        recoveryReserved = true,
        transactionID = pending.transactionID or pending.ledgerID,
        authorityContract = nativeAuthority.contract,
        boundaryContract = nativeAuthority.boundaryContract,
    })
    if not ok then
        local detail = dispatchAudit and dispatchAudit.detail or tostring(dispatchState or "unknown client error")
        self:CompletePendingEnchant("failed", detail, "native-api", true)
        if recovery.ClearPending then recovery:ClearPending("production-enchanting-native-api-failure") end
        report.rollbackComplete = self.pendingEnchant == nil
        report.state = "production-enchanting-native-single-enchant-dispatch-failed"
        report.detail = detail
        return false, report.state, report
    end
    report.nativeDispatchAccepted = true

    -- CraftEnchant may synchronously complete or raise a secure confirmation.
    -- Never invoke ReplaceEnchant/BindEnchant here; the Blizzard button remains
    -- the protected hardware-event boundary.
    if not self.pendingEnchant or self.pendingEnchant.token ~= token then
        local last = self.lastEnchant
        report.confirmedSynchronously = last and last.token == token and last.status == "success" or false
        report.completedCount = report.confirmedSynchronously and 1 or 0
        report.state = report.confirmedSynchronously and "production-enchanting-native-single-enchant-dispatched-and-confirmed" or "production-enchanting-native-single-enchant-dispatched"
        return true, report.state, report
    end

    if self.pendingEnchant.status == "dispatching" then self.pendingEnchant.status = "pending" end
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED", self.pendingEnchant) end
    self:ScheduleEnchantTimeout(token)
    report.confirmationRequired = self.pendingEnchant.confirmationRequired == true
    report.confirmationEvent = self.pendingEnchant.confirmationEvent
    report.confirmationReason = self.pendingEnchant.confirmationReason
    report.state = report.confirmationRequired and "production-enchanting-native-protected-confirmation-required" or "production-enchanting-native-single-enchant-dispatched"
    return true, report.state, report
end

local function enchantCompletionMessage(status,pending,detail)
    local target=tostring(pending and pending.targetName or "selected target")
    local recipe=tostring(pending and pending.recipeName or "the enchant")
    if status=="success" then
        return "Enchant complete: "..recipe.." applied to "..target.."."
    elseif status=="timeout" then
        return "Enchant completion could not be confirmed for "..target..". Check the item before retrying."
    end
    local suffix=detail and tostring(detail)~="" and (": "..tostring(detail)) or "."
    return "Enchant failed for "..target..suffix
end

function Crafting:ApplyRecoveredTransaction(kind,snapshot,result)
    if type(snapshot)~="table" or type(result)~="table" then return false end
    local key=snapshot.key or (kind=="enchant" and "ENCHANTING" or nil)
    local completed=math.max(1,tonumber(result.confirmedCount) or tonumber(snapshot.completedCount) or 1)
    local requested=math.max(1,tonumber(snapshot.requestedCount) or 1)
    local partialBatch = kind=="craft" and (snapshot.mode=="all" or requested>1) and
        (result.partialBatch==true or completed<requested)
    local ledger=JLP:GetModule("TransactionLedger")
    if ledger then
        local ledgerID=snapshot.ledgerID or select(1,ledger:EnsureSnapshot(snapshot))
        if ledgerID then
            ledger:ConfirmThrough(ledgerID,math.min(completed,requested),"recovery:"..tostring(snapshot.id or ledgerID),"reload-recovery",{evidence=result.evidence})
            completed=math.max(completed,ledger:GetConfirmedCount(ledgerID) or 0)
            snapshot.ledgerID=ledgerID
        end
    end
    local action={
        status=partialBatch and "aborted_unknown" or "success",
        partialRecoveredBatch=partialBatch,
        automaticResume=false,
        transactionKind=kind,
        key=key,
        recipeID=snapshot.recipeID,
        recipeName=snapshot.recipeName,
        mode=snapshot.mode or (kind=="craft" and (requested>1 and "all" or "one") or nil),
        requestedCount=requested,
        completedCount=kind=="craft" and math.min(completed,requested) or math.min(completed,1),
        targetGUID=snapshot.targetGUID,
        targetName=snapshot.targetName,
        targetItemID=tonumber(snapshot.targetItemID),
        targetLocationKey=snapshot.targetLocationKey,
        targetProofContract=snapshot.targetProofContract,
        targetProofFingerprint=snapshot.targetProofFingerprint,
        targetValidationSource=snapshot.targetValidationSource,
        confirmationRequired=snapshot.confirmationRequired==true,
        confirmationEvent=snapshot.confirmationEvent,
        confirmationReason=snapshot.confirmationReason,
        confirmationAt=snapshot.confirmationAt,
        confirmationSignals=tonumber(snapshot.confirmationSignals) or 0,
        confirmationDuplicateSignals=tonumber(snapshot.confirmationDuplicateSignals) or 0,
        confirmationHistory=snapshot.confirmationHistory,
        settlementState=snapshot.settlementState,
        settledBy=snapshot.settledBy or "reload-recovery",
        provisionalFailure=snapshot.provisionalFailure or snapshot.postReloadFailure,
        targetSkill=snapshot.targetSkill,
        startedSkill=tonumber(snapshot.startedSkill),
        endingSkill=tonumber(result.endingSkill),
        skillGain=math.max(0,tonumber(result.skillGain) or 0),
        targetReached=tonumber(result.endingSkill) and tonumber(snapshot.targetSkill) and tonumber(result.endingSkill)>=tonumber(snapshot.targetSkill) or false,
        startedAt=nil,
        finishedAt=actionNow(),
        detail="recovered after /reload",
        token="recovery:"..tostring(snapshot.id or snapshot.token or "unknown"),
        ledgerID=snapshot.ledgerID,
        transactionID=snapshot.ledgerID,
        source="reload-recovery",
        materialSnapshot=snapshot.materialSnapshot,
        authorityProvenance=snapshot.authorityProvenance,
        researchNativeExecution=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="research-native-dispatch-provenance-v1" or false,
        productionTailoringNativeExecution=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="production-tailoring-native-dispatch-provenance-v1" or false,
        productionEnchantingNativeExecution=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="production-enchanting-native-dispatch-provenance-v1" or false,
        researchNativeCraftAll=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="research-native-craft-all-provenance-v1" or false,
        productionTailoringCraftAll=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="production-tailoring-native-craft-all-provenance-v1" or false,
        repeatStopRequested=snapshot.repeatStopRequested==true,
        repeatStopReason=snapshot.repeatStopReason,
        repeatStopSource=snapshot.repeatStopSource,
        killSwitchObserved=snapshot.killSwitchObserved==true,
        recovered=true,
        recoveryConfidence=result.confidence or "high",
        recoveryEvidence=result.evidence,
    }
    if kind=="enchant" then
        action.message=enchantCompletionMessage("success",snapshot,"recovered after /reload")
        self.lastEnchant=action
        if snapshot.recipeID then self:ReconcileEnchantTarget(snapshot.recipeID) end
    else
        action.message=partialBatch and
            string.format("Craft All partially recovered: %d/%d verified crafts; remaining ordinals unresolved after /reload. No automatic resume.", action.completedCount, requested)
            or craftCompletionMessage("success",action,"recovered after /reload")
        self.lastCraft=action
    end
    if ledger and action.ledgerID then
        ledger:Close(action.ledgerID,action.status,{source="reload-recovery",recovered=true,recoveryConfidence=result.confidence,detail=partialBatch and "confirmed prefix only; remaining ordinals unknown" or "recovered after /reload"})
    end
    local tracker=JLP:GetModule("ProgressTracker")
    if tracker and tracker.RecordTransaction then tracker:RecordTransaction(action) end
    scheduleFeedbackExpiry(kind,action.token)
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit(kind=="enchant" and "ENCHANT_ACTION_UPDATED" or "CRAFT_ACTION_UPDATED",action)
    end
    return true,action
end

function Crafting:ApplyRecoveredFailure(kind,snapshot,reason)
    if type(snapshot)~="table" then return false end
    local action={
        status="failed",
        transactionKind=kind or snapshot.kind or "craft",
        key=snapshot.key,
        recipeID=snapshot.recipeID,
        recipeName=snapshot.recipeName,
        targetGUID=snapshot.targetGUID,
        targetName=snapshot.targetName,
        targetItemID=tonumber(snapshot.targetItemID),
        targetLocationKey=snapshot.targetLocationKey,
        targetProofContract=snapshot.targetProofContract,
        targetProofFingerprint=snapshot.targetProofFingerprint,
        targetValidationSource=snapshot.targetValidationSource,
        confirmationRequired=snapshot.confirmationRequired==true,
        confirmationEvent=snapshot.confirmationEvent,
        confirmationReason=snapshot.confirmationReason,
        confirmationAt=snapshot.confirmationAt,
        confirmationSignals=tonumber(snapshot.confirmationSignals) or 0,
        confirmationDuplicateSignals=tonumber(snapshot.confirmationDuplicateSignals) or 0,
        confirmationHistory=snapshot.confirmationHistory,
        provisionalFailure=snapshot.provisionalFailure or snapshot.postReloadFailure,
        mode=snapshot.mode or "one",
        requestedCount=math.max(1,tonumber(snapshot.requestedCount) or 1),
        completedCount=math.max(0,tonumber(snapshot.completedCount) or 0),
        targetSkill=snapshot.targetSkill,
        startedSkill=tonumber(snapshot.startedSkill),
        finishedAt=actionNow(),
        detail=reason or "failure confirmed after /reload",
        token="recovery-failed:"..tostring(snapshot.id or snapshot.token or "unknown"),
        ledgerID=snapshot.ledgerID,
        transactionID=snapshot.ledgerID,
        source="reload-recovery-failed",
        materialSnapshot=snapshot.materialSnapshot,
        authorityProvenance=snapshot.authorityProvenance,
        researchNativeExecution=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="research-native-dispatch-provenance-v1" or false,
        productionTailoringNativeExecution=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="production-tailoring-native-dispatch-provenance-v1" or false,
        productionEnchantingNativeExecution=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="production-enchanting-native-dispatch-provenance-v1" or false,
        researchNativeCraftAll=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="research-native-craft-all-provenance-v1" or false,
        productionTailoringCraftAll=type(snapshot.authorityProvenance)=="table" and snapshot.authorityProvenance.contract=="production-tailoring-native-craft-all-provenance-v1" or false,
        repeatStopRequested=snapshot.repeatStopRequested==true,
        repeatStopReason=snapshot.repeatStopReason,
        repeatStopSource=snapshot.repeatStopSource,
        recovered=true,
        recoveryConfidence="matched-failure-after-grace",
        settlementState="failed",
        settledBy="post-reload-failure-grace",
        killSwitchObserved=snapshot.killSwitchObserved==true,
    }
    if action.transactionKind=="enchant" then
        action.message=enchantCompletionMessage("failed",action,action.detail)
        self.lastEnchant=action
    else
        action.message=craftCompletionMessage("failed",action,action.detail)
        self.lastCraft=action
    end
    local tracker=JLP:GetModule("ProgressTracker")
    if tracker and tracker.RecordTransaction then tracker:RecordTransaction(action) end
    scheduleFeedbackExpiry(action.transactionKind=="enchant" and "enchant" or "craft",action.token)
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit(action.transactionKind=="enchant" and "ENCHANT_ACTION_UPDATED" or "CRAFT_ACTION_UPDATED",action) end
    return true,action
end

function Crafting:CompletePendingEnchant(status, detail, source, suppressPrint)
    local pending=self.pendingEnchant
    if not pending then return false,nil end
    local ledger=JLP:GetModule("TransactionLedger")
    -- Terminal success must consume an already confirmed receipt. Never
    -- synthesize an enchant receipt merely because a caller says "success".
    -- Recovery records its independently qualified result through its own path.
    if status=="success" then
        local tx=ledger and pending.ledgerID and ledger.GetTransaction and ledger:GetTransaction(pending.ledgerID) or nil
        local confirmed=tx and tonumber(tx.confirmedCount) or nil
        if not tx or tx.kind~="enchant" or tonumber(tx.recipeID)~=tonumber(pending.recipeID)
            or tostring(tx.targetGUID or "")~=tostring(pending.targetGUID or "")
            or tx.closedAt or not confirmed or confirmed<1 then
            return false,"enchant-success-not-ledger-confirmed"
        end
    end
    self.pendingEnchant=nil
    if ledger and pending.ledgerID then
        ledger:Close(pending.ledgerID,status,{source=source or "unknown",detail=detail})
    end

    -- Re-resolve the currently selected GUID after the craft.  If the user has
    -- already selected another target while the cast was in flight, that newer
    -- selection remains authoritative and is never overwritten by completion.
    self:ReconcileEnchantTarget(pending.recipeID)

    if status=="success" then
        local inventory=JLP:GetModule("Inventory")
        if inventory and inventory.RefreshBagCache then inventory:RefreshBagCache() end
    end

    local currentProfession
    local api=JLP:GetModule("ProfessionAPI")
    if api and api.Get then currentProfession=api:Get(pending.key or "ENCHANTING") end
    local endingSkill=tonumber(currentProfession and currentProfession.skill)
    local startedSkill=tonumber(pending.startedSkill)
    local skillGain=(status=="success" and endingSkill and startedSkill) and math.max(0,endingSkill-startedSkill) or 0
    local message=enchantCompletionMessage(status,pending,detail)
    self.lastEnchant={
        status=status,
        transactionKind="enchant",
        key=pending.key or "ENCHANTING",
        recipeID=pending.recipeID,
        recipeName=pending.recipeName,
        targetGUID=pending.targetGUID,
        targetName=pending.targetName,
        targetItemID=tonumber(pending.targetItemID),
        targetLink=pending.targetLink,
        targetLocationKey=pending.targetLocationKey,
        targetProofContract=pending.targetProofContract,
        targetProofFingerprint=pending.targetProofFingerprint,
        targetValidationSource=pending.targetValidationSource,
        targetSkill=pending.targetSkill,
        startedSkill=startedSkill,
        endingSkill=endingSkill,
        skillGain=skillGain,
        targetReached=endingSkill and pending.targetSkill and endingSkill>=pending.targetSkill or false,
        startedAt=pending.startedAt,
        finishedAt=actionNow(),
        detail=detail,
        token=pending.token,
        ledgerID=pending.ledgerID,
        transactionID=pending.ledgerID,
        source=source or "unknown",
        materialSnapshot=pending.materialSnapshot,
        mode=pending.mode or "one",
        requestedCount=math.max(1,tonumber(pending.requestedCount) or 1),
        completedCount=status=="success" and 1 or math.max(0,tonumber(pending.completedCount) or 0),
        confirmationRequired=pending.confirmationRequired==true,
        confirmationEvent=pending.confirmationEvent,
        confirmationReason=pending.confirmationReason,
        confirmationAt=pending.confirmationAt,
        confirmationSignals=tonumber(pending.confirmationSignals) or 0,
        confirmationDuplicateSignals=tonumber(pending.confirmationDuplicateSignals) or 0,
        confirmationHistory=pending.confirmationHistory,
        settlementState=pending.settlementState,
        settledBy=pending.settledBy,
        provisionalFailure=pending.provisionalFailure,
        killSwitchObserved=pending.killSwitchObserved==true,
        killSwitchReason=pending.killSwitchReason,
        settlementContract=pending.settlementContract,
        confirmationLifecycleContract=pending.confirmationLifecycleContract,
        authorityProvenance=pending.authorityProvenance,
        productionEnchantingNativeExecution=pending.productionEnchantingNativeExecution==true,
        message=message,
    }
    local tracker=JLP:GetModule("ProgressTracker")
    if tracker and tracker.RecordTransaction then tracker:RecordTransaction(self.lastEnchant) end
    scheduleFeedbackExpiry("enchant",pending.token)
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED",self.lastEnchant) end
    if not suppressPrint and message and JLP.Print then JLP:Print(message) end
    return true,message
end

function Crafting:ScheduleEnchantTimeout(token)
    if type(C_Timer)~="table" or type(C_Timer.After)~="function" then return end
    C_Timer.After(12,function()
        local pending=Crafting.pendingEnchant
        if pending and pending.token==token then
            if pending.productionEnchantingNativeExecution==true then
                local settlement=JLP:GetModule("ProductionEnchantingNativeSettlement")
                if settlement and settlement.HandleTimeout then
                    settlement:HandleTimeout(pending)
                    return
                end
            end
            Crafting:CompletePendingEnchant("timeout",nil,"timeout",false)
        end
    end)
end

function Crafting:OnTradeSkillCraftBegin(recipeSpellID)
    -- Do not resurrect an already-settled strict ordinal while awaiting a
    -- fresh hardware click for the next ordinal.
    local active = self.pendingCraft
    if active and active.strictTargetSafeCraftAll == true and
        (active.strictAwaitingUserClick == true or active.strictOrdinalInFlight ~= true) and
        tonumber(recipeSpellID) == tonumber(active.recipeID) then return false end
    local enchant=self.pendingEnchant
    if enchant and tonumber(recipeSpellID)==tonumber(enchant.recipeID) then
        enchant.currentDifficulty=captureRecipeDifficulty(enchant.recipeID,enchant.recipeName) or enchant.currentDifficulty or enchant.difficultySnapshot
        enchant.status="crafting"
        if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED",enchant) end
        return true
    end
    local pending=self.pendingCraft
    if not pending or tonumber(recipeSpellID)~=tonumber(pending.recipeID) then return false end
    pending.currentDifficulty=captureRecipeDifficulty(pending.recipeID,pending.recipeName) or pending.currentDifficulty or pending.difficultySnapshot
    self:TouchPendingCraft("crafting")
    return true
end

function Crafting:OnTradeSkillItemCraftedResult(data)
    if type(data)~="table" then return false end
    local ledger=JLP:GetModule("TransactionLedger")
    -- Forever result payloads differ between clients. If the payload carries
    -- an explicit recipe identity, reject a mismatch before ledger/history
    -- mutation. Anonymous crafted results are observations, not proof of a
    -- separate additional batch ordinal.
    local observedRecipe = data.recipeID or data.spellID or data.craftingSpellID
    local inFlight = data.isEnchant == true and self.pendingEnchant or self.pendingCraft
    if data.isEnchant~=true then
        local output=JLP:GetModule("CraftOutputReconciliation")
        if output and output.IsTerminalReplay then
            local known,reason=output:IsTerminalReplay(data)
            if known then
                if not inFlight and output.ObserveLate then output:ObserveLate(data) end
                return false,reason
            end
        end
        if not inFlight then
            -- Late results are observational only: NEVER reopen pendingCraft,
            -- ledger, fixed-yield evidence or protected client actions.
            return output and output.ObserveLate and output:ObserveLate(data) or false
        end
    end
    if not inFlight then return false end
    if observedRecipe ~= nil and tonumber(observedRecipe) ~= tonumber(inFlight.recipeID) then return false end
    if observedRecipe == nil and (inFlight.productionEnchantingNativeExecution == true or
        inFlight.productionTailoringNativeExecution == true or
        inFlight.researchNativeExecution == true or inFlight.strictTargetSafeCraftAll == true) then
        -- Without an explicit recipe identity, a native result from another
        -- activity cannot be safely attributed to the guarded ledger.
        -- Correlated spellcast successes and independent recovery evidence
        -- remain valid confirmation channels.
        return false
    end
    if data.isEnchant ~= true and inFlight.strictTargetSafeCraftAll == true and
        (inFlight.strictOrdinalInFlight ~= true or inFlight.strictAwaitingUserClick == true) then
        return false
    end
    if data.isEnchant==true then
        local pending=self.pendingEnchant
        if not pending then return false end
        -- The specialized production settlement owns its evidence lifecycle.
        -- Never fall through to a less strict manual receipt if it rejects one.
        if pending.productionEnchantingNativeExecution==true then
            local settlement=JLP:GetModule("ProductionEnchantingNativeSettlement")
            if settlement and settlement.ConfirmFromCraftResult then
                return settlement:ConfirmFromCraftResult(pending,data)
            end
            return false
        end
        if data.targetGUID~=nil and tostring(data.targetGUID)~=tostring(pending.targetGUID or "") then return false end
        -- An item GUID (including the target GUID) can recur across enchant
        -- transactions; only an operation identity can correlate this result.
        if data.operationID==nil or tostring(data.operationID)=="" or tostring(data.operationID)=="0"
            or not ledger or not pending.ledgerID then return false end
        local confirmed,_,unit=ledger:ConfirmEnchant(pending.ledgerID,data.operationID,"crafted-result",data)
        if not confirmed then return false end
        if unit and ledger.ReconcileDifficulty and (pending.currentDifficulty or pending.difficultySnapshot) then
            ledger:ReconcileDifficulty(pending.ledgerID,unit.index,pending.currentDifficulty or pending.difficultySnapshot)
        end
        return self:CompletePendingEnchant("success",nil,"craft-result",false)
    end

    local pending=self.pendingCraft
    if not pending then return false end
    -- Reconcile output receipts before storing them. Do not convert an
    -- arbitrary recipe-result event into a verified per-craft yield sample.
    local output=JLP:GetModule("CraftOutputReconciliation")
    local accepted,receiptStatus=output and output.Observe and output:Observe(pending,data)
    if output and not accepted then
        -- A replay or malformed result must not overwrite lastResult.
        if receiptStatus=="duplicate-output-receipt" or
           receiptStatus=="conflicting-replayed-result" or
           receiptStatus=="receipt-capacity-exceeded" or
           receiptStatus=="invalid-item-or-quantity" then
            return false,receiptStatus
        end
        -- Missing optional identifiers are not a client/build lock. Retain the
        -- previous observational path, but NEVER qualify these item quantities
        -- as fixed yield evidence or as a confirmed craft ordinal.
    end
    pending.lastResult={itemID=data.itemID,itemGUID=data.itemGUID,quantity=data.quantity,
        hyperlink=data.hyperlink,operationID=data.operationID,
        recipeID=data.recipeID or data.spellID or data.craftingSpellID}
    if ledger and pending.ledgerID then ledger:RecordCraftResult(pending.ledgerID,pending.lastResult,"crafted-result") end
    local inventory=JLP:GetModule("Inventory")
    if inventory and inventory.RefreshBagCache then inventory:RefreshBagCache() end
    if pending.researchNativeExecution==true then
        local settlement=JLP:GetModule("ResearchNativeExecutionSettlement")
        if settlement and settlement.ConfirmFromCraftResult then
            local settled=settlement:ConfirmFromCraftResult(pending,pending.lastResult)
            if settled then return true end
        end
    end
    self:TouchPendingCraft("crafting")
    return true
end

function Crafting:OnEnchantConfirmationRequired(event, ...)
    local pending=self.pendingEnchant
    if not pending then return false end
    if pending.productionEnchantingNativeExecution==true then
        local settlement=JLP:GetModule("ProductionEnchantingNativeSettlement")
        if settlement and settlement.ObserveConfirmation then
            return settlement:ObserveConfirmation(pending,event,...)
        end
    end
    local kind=tostring(event or "ENCHANT_CONFIRMATION")
    pending.status="confirmation-required"
    pending.confirmationRequired=true
    pending.confirmationEvent=kind
    pending.confirmationAt=actionNow()
    if kind=="REPLACE_ENCHANT" or kind=="TRADE_REPLACE_ENCHANT" then
        pending.confirmationReason="replace-existing-enchant"
    elseif kind=="BIND_ENCHANT" or kind=="TRADE_POTENTIAL_BIND_ENCHANT" then
        pending.confirmationReason="bind-item"
    else
        pending.confirmationReason="native-enchant-confirmation"
    end
    -- C_Item.ReplaceEnchant / C_Item.BindEnchant (and their legacy aliases)
    -- are protected client functions. Addon code must not invoke them here; the
    -- Blizzard confirmation button is the secure hardware-event boundary.
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED",pending) end
    return true
end

function Crafting:OnSpellcastSucceeded(unitTarget,castGUID,spellID)
    if unitTarget~="player" then return false end
    local enchant=self.pendingEnchant
    if enchant and tonumber(spellID)==tonumber(enchant.recipeID) then
        if enchant.productionEnchantingNativeExecution==true then
            local settlement=JLP:GetModule("ProductionEnchantingNativeSettlement")
            if settlement and settlement.ConfirmFromSpellcastSuccess then
                return settlement:ConfirmFromSpellcastSuccess(enchant,castGUID,spellID)
            end
            return false
        end
        -- A recipe-only / anonymous success could be an old cast of the same
        -- enchant. Require a unique cast receipt and an open ledger reservation.
        if type(castGUID)~="string" or castGUID=="" then return false end
        local ledger=JLP:GetModule("TransactionLedger")
        if not ledger or not enchant.ledgerID then return false end
        local confirmed,_,unit=ledger:ConfirmEnchant(enchant.ledgerID,castGUID,"spellcast-success",{castGUID=castGUID,spellID=spellID})
        if not confirmed then return false end
        if unit and ledger.ReconcileDifficulty and (enchant.currentDifficulty or enchant.difficultySnapshot) then
            ledger:ReconcileDifficulty(enchant.ledgerID,unit.index,enchant.currentDifficulty or enchant.difficultySnapshot)
        end
        return self:CompletePendingEnchant("success",nil,"spellcast-success",false)
    end
    return self:RecordCraftCompletion(spellID,castGUID,"spellcast-success")
end

function Crafting:OnSpellcastFailed(event,unitTarget,castGUID,spellID)
    if unitTarget~="player" then return false end
    local detail=event=="UNIT_SPELLCAST_INTERRUPTED" and "cast interrupted" or "client rejected or failed the cast"
    local enchant=self.pendingEnchant
    if enchant and tonumber(spellID)==tonumber(enchant.recipeID) then
        if enchant.productionEnchantingNativeExecution==true then
            local settlement=JLP:GetModule("ProductionEnchantingNativeSettlement")
            if settlement and settlement.HandleProvisionalFailure then
                return settlement:HandleProvisionalFailure(event,enchant,detail,castGUID,spellID)
            end
        end
        return self:CompletePendingEnchant("failed",detail,string.lower(tostring(event or "spellcast-failed")),false)
    end
    local pending=self.pendingCraft
    if pending and tonumber(spellID)==tonumber(pending.recipeID) then
        if pending.strictTargetSafeCraftAll == true and
            (pending.strictAwaitingUserClick == true or pending.strictOrdinalInFlight ~= true) then
            return false
        end
        if pending.researchNativeExecution==true then
            local settlement=JLP:GetModule("ResearchNativeExecutionSettlement")
            if settlement and settlement.HandleProvisionalFailure then
                return settlement:HandleProvisionalFailure(event,pending,detail)
            end
        elseif pending.researchNativeCraftAll==true or pending.productionTailoringCraftAll==true then
            local settlement=JLP:GetModule("ResearchNativeCraftAllSettlement")
            if settlement and settlement.HandleProvisionalFailure then
                return settlement:HandleProvisionalFailure(event,pending,detail)
            end
        end
        return self:CompletePendingCraft("failed",detail,string.lower(tostring(event or "spellcast-failed")),false)
    end
    return false
end

function Crafting:GetEnchantTargetDiagnostics(key,plan)
    key=key or "ENCHANTING"
    if not plan then
        local planner=JLP:GetModule("Planner")
        plan=planner and planner:GetProfessionPlan(key) or nil
    end
    local recipeID=plan and plan.step and plan.step.recipe and self:ResolveRecipeID(key,plan.step.recipe) or nil
    if not recipeID then return "Enchant target diagnostics: current recipe ID unresolved." end
    local liveCount=0
    if type(C_TradeSkillUI)=="table" and type(C_TradeSkillUI.GetEnchantItems)=="function" then
        local ok,guids=pcall(C_TradeSkillUI.GetEnchantItems,recipeID)
        if ok and type(guids)=="table" then for _,guid in pairs(guids) do if guid then liveCount=liveCount+1 end end end
    end
    local cached=self.enchantTargetOptions[recipeID] or {}
    local merged=select(1,self:GetEnchantTargets(key,plan)) or {}
    local selected=self.enchantTargets[recipeID]
    local action=self:GetEnchantActionState(key,plan)
    return string.format("Enchant targets: recipe=%s live=%d cached=%d picker=%d selected=%s action=%s token=%s",tostring(recipeID),liveCount,#cached,#merged,tostring(selected and selected.guid or "none"),tostring(action and action.status or "idle"),tostring(action and action.token or "none"))
end

function Crafting:Enchant(key, plan, fromPending)
    if not plan or plan.actionKind ~= "craft" or not plan.step or not plan.step.recipe then
        return false, "The current Enchanting guide step is not craftable."
    end
    if plan.executionEligible == false or plan.step.executionEligible == false then
        return false, "This Planner route has read authority only; execution authority is disabled."
    end
    if plan.routeAuthorityEnabled == true or plan.researchAuthority == true or plan.step.researchAuthority == true
        or (plan.step.dataset and plan.step.dataset.contract == "controlled-research-planner-dataset-v1") then
        return false, "Research execution-readiness is evaluation-only; execution authority and dispatch remain disabled."
    end
    if self.pendingEnchant then
        return false, "An enchant is already in progress. Wait for the current cast to finish."
    end
    if self.pendingCraft then
        return false, "A profession craft is already in progress. Wait for the current craft to finish."
    end
    local recovery=JLP:GetModule("TransactionRecovery")
    if recovery and recovery.CanStart then
        local allowed,message=recovery:CanStart("enchant",key)
        if not allowed then return false,message end
    end

    local recipeID = self:ResolveRecipeID(key, plan.step.recipe)
    if not recipeID then
        if fromPending then return false, "The current enchant recipe could not be resolved." end
        local selected=self:GetSelectedEnchantTarget(key,plan)
        return self:QueueAfterOpen(key, plan, "enchant", selected and selected.guid or nil)
    end
    -- Do not carry an earlier deferred click or target GUID into native Enchant.
    -- The live target is looked up and validated again on this direct action.
    self.pending = nil
    local target,targetError=self:GetEnchantExecutionTarget(recipeID)
    if not target then return false,targetError end
    -- Reagent authority is live TradeSkillUI craftability, not a cached
    -- CraftReadiness estimate or the selected item's presence alone.
    local enchantCraftable,craftStatus,craftReason=self:GetCraftableCount(recipeID)
    if craftStatus~="KNOWN" then
        return false,"Live Enchanting craftability cannot be verified ("..tostring(craftReason or craftStatus).."). Reopen the profession panel before retrying."
    end
    if enchantCraftable==0 then
        return false,"The client currently reports zero Enchanting crafts available. Check reagents and the selected target before retrying."
    end
    local nativeDispatch = JLP:GetModule("NativeDispatchService")
    if not nativeDispatch or not nativeDispatch.Dispatch then
        return false, "Native profession dispatch service is unavailable."
    end

    -- Install pending state BEFORE invoking CraftEnchant because
    -- TRADE_SKILL_ITEM_CRAFTED_RESULT is synchronous on supported clients.
    self.enchantAttemptSerial=(self.enchantAttemptSerial or 0)+1
    local token=self.enchantAttemptSerial
    local progressTracker=JLP:GetModule("ProgressTracker")
    local materialSnapshot=progressTracker and progressTracker.CaptureMaterialSnapshot and progressTracker:CaptureMaterialSnapshot(key,plan) or nil
    local api=JLP:GetModule("ProfessionAPI")
    local currentProfession=api and api.Get and api:Get(key) or nil
    self.pendingEnchant={
        token=token,
        key=key,
        recipeID=recipeID,
        recipeName=plan.step.recipe,
        targetGUID=target.guid,
        targetName=target.name,
        targetItemID=tonumber(target.itemID),
        targetLink=target.link,
        targetEnchantID=type(target.link)=="string" and tonumber(target.link:match("item:%d+:([%-]?%d+)")) or 0,
        targetLocation=target.location,
        targetSkill=tonumber(plan.step.skillTarget),
        startedSkill=tonumber(currentProfession and currentProfession.skill),
        startedAt=actionNow(),
        status="dispatching",
        materialSnapshot=materialSnapshot,
        difficultySnapshot=captureRecipeDifficulty(recipeID,plan.step.recipe),
    }
    self.pendingEnchant.currentDifficulty=self.pendingEnchant.difficultySnapshot
    local ledger=JLP:GetModule("TransactionLedger")
    if ledger and ledger.Begin then
        local ledgerID=ledger:Begin("enchant",self.pendingEnchant)
        self.pendingEnchant.ledgerID=ledgerID
        self.pendingEnchant.transactionID=ledgerID
    end

    local ok,dispatchState,dispatchAudit = nativeDispatch:Dispatch({
        contract = nativeDispatch.intentContract,
        professionKey = key,
        strategy = "TARGETED_ENCHANT",
        policy = "MANUAL_DIRECT_ENCHANT_ONE",
        recipeID = recipeID,
        count = 1,
        itemTarget = target.location,
        targetGUID = target.guid,
        nativeDispatchAllowed = true,
        transactionID = self.pendingEnchant and (self.pendingEnchant.transactionID or self.pendingEnchant.ledgerID) or nil,
        boundaryContract = "manual-direct-enchant-policy-v1",
    })
    if not ok then
        local detail=dispatchAudit and dispatchAudit.detail or tostring(dispatchState or "unknown client error")
        local _,message=self:CompletePendingEnchant("failed",detail,"api",true)
        return false,message
    end

    -- A synchronous success/failure event may already have completed the
    -- transaction inside CraftEnchant.  In that case the event supplied the
    -- user-facing completion feedback and no second message is needed here.
    if not self.pendingEnchant or self.pendingEnchant.token~=token then
        local last=self.lastEnchant
        return last and last.status=="success" or false,nil
    end

    if self.pendingEnchant.status=="dispatching" then self.pendingEnchant.status="pending" end
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED",self.pendingEnchant) end
    self:ScheduleEnchantTimeout(token)
    return true, "Enchant started on " .. tostring(target.name or "selected target") .. "."
end

function Crafting:OnTradeSkillUpdate()
    local progress = JLP:GetModule("RouteProgress")
    if progress and progress.ScanKnownRecipes then progress:ScanKnownRecipes() end
    self:ExecutePending()
    self:CheckAutoStop()
end

local function enrichCompletedAction(action)
    if type(action)~="table" or action.status~="success" or not recentAction(action) then return false end
    local changed=false
    local api=JLP:GetModule("ProfessionAPI")
    local profession=api and api.Get and api:Get(action.key) or nil
    local currentSkill=tonumber(profession and profession.skill)
    local startedSkill=tonumber(action.startedSkill)
    if currentSkill then
        -- Successful progression is monotonic within the short feedback window.
        -- A transient stale profession read must never erase a skill-up or route
        -- boundary that the client already confirmed on a previous event.
        local previousEnding=tonumber(action.endingSkill)
        local endingSkill=previousEnding and math.max(previousEnding,currentSkill) or currentSkill
        if previousEnding~=endingSkill then action.endingSkill=endingSkill; changed=true end
        if startedSkill then
            local gain=math.max(tonumber(action.skillGain) or 0,math.max(0,endingSkill-startedSkill))
            if tonumber(action.skillGain or 0)~=gain then action.skillGain=gain; changed=true end
        end
        local reached=(action.targetReached==true) or (tonumber(action.targetSkill) and endingSkill>=tonumber(action.targetSkill) or false)
        if action.targetReached~=reached then action.targetReached=reached; changed=true end
    end

    local planner=JLP:GetModule("Planner")
    local plan=planner and planner:GetProfessionPlan(action.key) or nil
    local nextRecipe=plan and plan.actionKind=="craft" and plan.step and plan.step.recipe or nil
    local computedAdvanced=(plan and plan.actionKind~="craft") or (nextRecipe and tostring(nextRecipe)~=tostring(action.recipeName)) or action.targetReached or false
    local advanced=(action.stepAdvanced==true) or computedAdvanced
    if action.stepAdvanced~=advanced then action.stepAdvanced=advanced; changed=true end
    local nextActionKind=plan and plan.actionKind or nil
    if nextActionKind and action.nextActionKind~=nextActionKind then action.nextActionKind=nextActionKind; changed=true end
    if nextRecipe and action.nextRecipe~=nextRecipe then action.nextRecipe=nextRecipe; changed=true end
    if changed then
        local tracker=JLP:GetModule("ProgressTracker")
        if tracker and tracker.RecordTransaction then tracker:RecordTransaction(action) end
    end
    return changed
end

function Crafting:GetActionFeedback(key, plan)
    local isEnchant=key=="ENCHANTING"
    local state=isEnchant and self:GetEnchantActionState(key,plan) or self:GetCraftActionState(key,plan)
    local status=state and state.status or "idle"
    if status=="idle" then return {visible=false,status="idle",tone="muted",text=""} end

    local tone="text"
    local text=""
    if status=="recovery_unresolved" then
        tone="warn"
        if isEnchant then text="Interrupted Enchant · reconciling after /reload"
        elseif state.mode=="all" then text=string.format("Interrupted Craft All · %d / %d previously confirmed · reconciling",tonumber(state.completedCount) or 0,math.max(1,tonumber(state.requestedCount) or 1))
        else text="Interrupted Craft One · reconciling after /reload" end
    elseif status=="awaiting-user" then
        tone="warn"
        text=string.format("Craft X · %d / %d confirmed · click Next Craft to authorize next ordinal",tonumber(state.completedCount) or 0,math.max(1,tonumber(state.requestedCount) or 1))
    elseif status=="confirmation-required" then
        tone="warn"
        local reason=state and state.confirmationReason or nil
        if reason=="replace-existing-enchant" then
            text="Enchant · Blizzard confirmation required to replace the existing enchant"
        elseif reason=="bind-item" then
            text="Enchant · Blizzard confirmation required to bind the target item"
        else
            text="Enchant · Blizzard confirmation required"
        end
    elseif status=="dispatching" or status=="pending" or status=="crafting" then
        tone="cyan"
        if isEnchant then
            text=status=="crafting" and "Enchant · crafting" or "Enchant · awaiting client confirmation"
        elseif state.mode=="all" then
            text=string.format("Craft All · %d / %d confirmed",tonumber(state.completedCount) or 0,math.max(1,tonumber(state.requestedCount) or 1))
        else
            text=status=="crafting" and "Craft One · crafting" or "Craft One · awaiting client confirmation"
        end
    elseif status=="success" then
        tone="good"
        if isEnchant then
            text="Enchant complete"
        elseif state.mode=="all" then
            text=string.format("Complete · %d / %d confirmed",tonumber(state.completedCount) or 0,math.max(1,tonumber(state.requestedCount) or 1))
        else
            text="Complete · 1 craft confirmed"
        end
        if not isEnchant then
            local settlement=state.outputSettlement
            if type(settlement)=="table" and settlement.status=="CORRELATED_SINGLE_CRAFT_MULTI_OUTPUT" then
                text=text..string.format(" · %d items across multiple outputs (single craft)",
                    tonumber(settlement.confirmedOutputUnits) or 0)
            elseif type(settlement)=="table" and settlement.status=="CORRELATED_SINGLE_CRAFT_RECEIPT" then
                text=text..string.format(" · %d items received (item %s)",
                    tonumber(settlement.confirmedOutputUnits) or 0,
                    tostring(settlement.confirmedOutputItemID or "?"))
                if settlement.comparison=="DEVIATION" then
                    text=text.." · differs from previous yield reference"
                end
            else
                text=text.." · output quantity unverified"
            end
        end
        if (tonumber(state.skillGain) or 0)>0 then text=text..string.format(" · +%d skill",tonumber(state.skillGain) or 0) end
        if state.stepAdvanced or state.targetReached then text=text.." · step advanced" end
    elseif status=="timeout" then
        tone="warn"
        if isEnchant then text="Enchant unconfirmed · check the target before retrying"
        else text=string.format("Unconfirmed · %d / %d confirmed · check profession window",tonumber(state.completedCount) or 0,math.max(1,tonumber(state.requestedCount) or 1)) end
    else
        tone="bad"
        if isEnchant then text="Enchant failed · retry available"
        else text=string.format("Failed · %d / %d confirmed · retry available",tonumber(state.completedCount) or 0,math.max(1,tonumber(state.requestedCount) or 1)) end
    end
    return {
        visible=true,
        status=status,
        tone=tone,
        text=text,
        token=state and state.token or nil,
        completedCount=state and state.completedCount or nil,
        requestedCount=state and state.requestedCount or nil,
        skillGain=state and state.skillGain or nil,
        stepAdvanced=state and state.stepAdvanced or false,
        outputSettlement=state and state.outputSettlement or nil,
        confirmedOutputUnits=state and state.confirmedOutputUnits or nil,
        expectedOutputUnits=state and state.expectedOutputUnits or nil,
    }
end

-- Read-only late diagnostic observations (including observations after /reload).
-- They never modify lastCraft, its terminal settlement, or the ledger.
function Crafting:GetLateOutputReview(recipeID,ledgerID)
    local output=JLP:GetModule("CraftOutputReconciliation")
    return output and output.GetLateReview and output:GetLateReview(recipeID,ledgerID) or nil
end

function Crafting:OnProgressUpdate()
    self:CheckAutoStop()
    local craftChanged=enrichCompletedAction(self.lastCraft)
    local enchantChanged=enrichCompletedAction(self.lastEnchant)
    if craftChanged and JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("CRAFT_ACTION_UPDATED",self.lastCraft) end
    if enchantChanged and JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("ENCHANT_ACTION_UPDATED",self.lastEnchant) end
end

function Crafting:GetSummary()
    if self.pendingCraft then return string.format("Craft %s: %s %d/%d -> target %s",tostring(self.pendingCraft.status or "pending"),tostring(self.pendingCraft.recipeName),tonumber(self.pendingCraft.completedCount) or 0,tonumber(self.pendingCraft.requestedCount) or 1,tostring(self.pendingCraft.targetSkill or "?")) end
    local repeatState=self.activeRepeat
    if repeatState then return string.format("Craft All active (current recipe only): %s -> target %s",tostring(repeatState.recipeName),tostring(repeatState.targetSkill or "?")) end
    if self.pendingEnchant then return string.format("Enchant pending: %s -> %s",tostring(self.pendingEnchant.recipeName),tostring(self.pendingEnchant.targetName or self.pendingEnchant.targetGUID)) end
    if self.lastCraft then
        local skill=(tonumber(self.lastCraft.skillGain) or 0)>0 and string.format(" +%d skill",tonumber(self.lastCraft.skillGain) or 0) or ""
        local advanced=(self.lastCraft.stepAdvanced or self.lastCraft.targetReached) and " step-advanced" or ""
        return string.format("Last craft: %s -> %s (%d/%d)%s%s",tostring(self.lastCraft.status),tostring(self.lastCraft.recipeName),tonumber(self.lastCraft.completedCount) or 0,tonumber(self.lastCraft.requestedCount) or 1,skill,advanced)
    end
    if self.lastEnchant then
        local skill=(tonumber(self.lastEnchant.skillGain) or 0)>0 and string.format(" +%d skill",tonumber(self.lastEnchant.skillGain) or 0) or ""
        local advanced=(self.lastEnchant.stepAdvanced or self.lastEnchant.targetReached) and " step-advanced" or ""
        return string.format("Last enchant: %s -> %s%s%s",tostring(self.lastEnchant.status),tostring(self.lastEnchant.targetName or self.lastEnchant.targetGUID),skill,advanced)
    end
    return "No direct profession craft is currently repeating."
end

JLP:RegisterModule("Crafting", Crafting)
