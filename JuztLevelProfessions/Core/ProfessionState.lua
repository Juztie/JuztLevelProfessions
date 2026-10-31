local _, JLP = ...

-- Deterministic profession route-state model.  It translates the Planner,
-- CraftReadiness, ActionQueue and confirmed transaction layers into one stable
-- state contract that the Guide UI can consume without re-deriving semantics.
local ProfessionState = {
    contract = "confirmed-profession-state-machine-v3",
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetKeys() or {}
end
local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local TONES = {
    LEARN = "warn",
    TRAIN = "gold",
    VERIFY = "warn",
    LEARN_RECIPE = "warn",
    RETRIEVE = "cyan",
    ACQUIRE = "warn",
    PREPARE = "cyan",
    NEXT_RECIPE = "cyan",
    CRAFT = "good",
    CRAFTING = "cyan",
    COMPLETE = "good",
    BLOCKED = "bad",
    STAGED = "muted",
    REFERENCE = "gold",
}

local LABELS = {
    LEARN = "LEARN",
    TRAIN = "TRAINER",
    VERIFY = "VERIFY",
    LEARN_RECIPE = "RECIPE",
    RETRIEVE = "RETRIEVE",
    ACQUIRE = "ACQUIRE",
    PREPARE = "PREPARE",
    NEXT_RECIPE = "NEXT RECIPE",
    CRAFT = "READY",
    CRAFTING = "CRAFTING",
    COMPLETE = "COMPLETE",
    BLOCKED = "BLOCKED",
    STAGED = "STAGED",
    REFERENCE = "REFERENCE",
}

local function isPending(state)
    local status = state and tostring(state.status or "") or ""
    return status == "dispatching" or status == "pending" or status == "crafting" or status == "confirmation-required" or status == "recovery_unresolved"
end

local function currentAction(queue)
    if not queue or not queue.actions then return nil end
    local index = tonumber(queue.currentIndex) or 0
    if index < 1 then return nil end
    return queue.actions[index]
end

local function actionState(kind)
    kind = tostring(kind or "")
    if kind == "verify-recipe" then return "VERIFY", "Recipe knowledge must be verified before the route can continue." end
    if kind == "verify-dependency" then return "VERIFY", "Material and tool dependencies must be resolved before crafting." end
    if kind == "learn-recipe" then return "LEARN_RECIPE", "The route recipe is not learned yet." end
    if kind:match("^retrieve") then return "RETRIEVE", "Required profession resources are available in storage and must be moved to bags." end
    if kind:match("^acquire") then return "ACQUIRE", "The current step is missing required profession resources." end
    if kind == "craft-tool" or kind == "craft-intermediate" then return "PREPARE", "A prerequisite craft must be completed before the leveling craft." end
    if kind == "craft-leveling" then return "CRAFT", "The current leveling recipe is ready for direct crafting." end
    if kind == "train-rank" then return "TRAIN", "The current profession rank gate must be trained." end
    if kind == "learn-profession" then return "LEARN", "The profession is not learned on this character." end
    return nil, nil
end

local function nextRecipeArrival(plan, tracking)
    if not plan or plan.actionKind ~= "craft" or not plan.step or not tracking then return false end
    local entry = tracking.lastTransaction
    if not entry or entry.status ~= "success" or not entry.stepAdvanced then return false end
    if tostring(entry.nextActionKind or "") ~= "craft" then return false end
    if tostring(entry.nextRecipe or "") == "" or tostring(entry.nextRecipe) ~= tostring(plan.step.recipe or "") then return false end
    -- NEXT_RECIPE is an arrival state, not a permanent replacement for CRAFT.
    -- The first confirmed/observed craft on the new step advances it to CRAFT.
    if (tonumber(tracking.stepConfirmedCrafts) or 0) > 0 then return false end
    if (tonumber(tracking.stepCraftsObserved) or 0) > 0 then return false end
    return true
end

function ProfessionState:Resolve(key, plan, readiness, queue, tracking, transaction, execution)
    local action = currentAction(queue)
    local state, reason

    if isPending(transaction) then
        state = "CRAFTING"
        reason = key == "ENCHANTING" and "A confirmed enchant transaction is in progress." or "A confirmed profession craft transaction is in progress."
    elseif not plan then
        state, reason = "BLOCKED", "No profession plan is currently available."
    elseif plan.actionKind == "reference" or plan.readOnlyRouteFallback==true then
        state, reason = "REFERENCE", plan.action or "Read-only profession reference; verify current in-game requirements."
    elseif plan.actionKind == "complete" then
        state, reason = "COMPLETE", "The profession leveling route is complete."
    elseif plan.actionKind == "learn" then
        state, reason = "LEARN", "The profession must be learned before route progression can begin."
    elseif plan.actionKind == "train" then
        state, reason = "TRAIN", "The current skill cap requires profession rank training."
    elseif plan.actionKind == "craft" then
        local queueState, queueReason = actionState(action and action.kind)
        state, reason = queueState, queueReason

        if (state == "CRAFT" or not state) and nextRecipeArrival(plan, tracking) then
            state = "NEXT_RECIPE"
            reason = "The previous confirmed craft advanced the route to this recipe."
        end

        if not state and readiness then
            if readiness.status == "ready" then state, reason = "CRAFT", "The current leveling recipe is ready from bag materials."
            elseif readiness.status == "prepare" then state, reason = "PREPARE", "Intermediate materials must be crafted first."
            elseif readiness.status == "bank" then state, reason = "RETRIEVE", "Required resources are available in storage but not ready in bags."
            elseif readiness.blocker == "inventory-unknown" then state, reason = "VERIFY", "Refresh live inventory before determining material shortages."
            elseif readiness.status == "materials" then state, reason = "ACQUIRE", "Additional materials are required for the current route step."
            elseif readiness.status == "verify" then state, reason = "VERIFY", "Recipe knowledge must be verified in the profession window."
            elseif readiness.blocker == "recipe" then state, reason = "LEARN_RECIPE", "The recommended recipe is not learned."
            elseif readiness.blocker == "tool" then state, reason = "ACQUIRE", "A required profession tool is missing."
            end
        end
        if not state then state, reason = "BLOCKED", tostring(readiness and readiness.action or plan.action or "The craft step is not currently actionable.") end
    else
        state, reason = "BLOCKED", tostring(plan.action or "The profession route is blocked.")
    end

    local nextState
    if state == "NEXT_RECIPE" then
        nextState = "CRAFT"
    elseif queue and queue.actions then
        local index = tonumber(queue.currentIndex) or 0
        local nextAction = queue.actions[index + 1]
        nextState = actionState(nextAction and nextAction.kind)
    end

    return {
        contract = self.contract,
        key = key,
        state = state,
        label = LABELS[state] or state,
        tone = TONES[state] or "text",
        reason = reason,
        action = action,
        actionKind = action and action.kind or nil,
        actionText = action and action.text or (plan and plan.action) or nil,
        nextState = nextState,
        planActionKind = plan and plan.actionKind or nil,
        recipe = plan and plan.step and plan.step.recipe or nil,
        targetSkill = plan and plan.step and plan.step.skillTarget or nil,
        readinessStatus = readiness and readiness.status or nil,
        readinessBlocker = readiness and readiness.blocker or nil,
        transactionStatus = transaction and transaction.status or "idle",
        transactionToken = transaction and transaction.token or nil,
        confirmedCrafts = tracking and tracking.stepConfirmedCrafts or 0,
        confirmedSkillGains = tracking and tracking.stepConfirmedSkillGains or 0,
        noSkillCrafts = tracking and tracking.stepNoSkillCrafts or 0,
        execution = execution,
        executionStatus = execution and execution.status or "idle",
        executionGroup = execution and execution.activeGroup or nil,
        executionProgress = execution and execution.progressText or nil,
        lastCompletedExecution = execution and execution.lastCompleted or nil,
    }
end

function ProfessionState:Get(key, plan)
    local planner = JLP:GetModule("Planner")
    plan = plan or (planner and planner:GetProfessionPlan(key))
    local reg=registry()
    local availability=reg and reg:ResolveWorkflowAvailability(key,"executionFlow") or nil
    local policy=JLP:GetModule("PlanAuthorityPolicy")
    local advisory=policy and policy.IsReadOnlyConsumable and policy:IsReadOnlyConsumable(plan)
    if availability and availability.state~="available" and not advisory then
        local hasReference=plan and (plan.referenceSnapshot or plan.readOnlyRouteFallback)
        local notLearned=plan and plan.actionKind=="learn"
        local state=notLearned and "LEARN" or (hasReference and "REFERENCE" or
            (availability.state=="not-production-enabled" and "STAGED" or "BLOCKED"))
        local reason=notLearned and "Learn this profession to unlock character-specific progression; reference data can still be inspected." or
            (hasReference and "Reference and advisory planning available; native execution is not qualified." or
            (availability.state=="not-production-enabled" and "Profession is registered but not production-enabled." or "Profession is unsupported by the current registry."))
        local runtime=JLP:GetModule("ProfessionRuntimeState")
        local runtimeState=runtime and runtime.Get and runtime:Get(availability.key or key) or nil
        return {contract=self.contract,key=availability.key or key,state=state,label=LABELS[state] or state,tone=TONES[state] or "text",reason=reason,
            terminalReason=availability.terminalReason,executionStatus="idle",runtimeState=runtimeState,
            planActionKind=plan and plan.actionKind,referenceSnapshot=plan and plan.referenceSnapshot,
            nativeDispatchAllowed=false}, nil, nil, nil, nil, nil
    end
    if availability then key=availability.key end
    local readinessModule = JLP:GetModule("CraftReadiness")
    local readiness = readinessModule and readinessModule:Get(key, plan) or nil
    local queueModule = JLP:GetModule("ActionQueue")
    local queue = queueModule and queueModule:Build(key, plan, readiness) or nil
    local tracker = JLP:GetModule("ProgressTracker")
    local tracking = tracker and tracker:GetStatus(key) or nil
    local executionModule = JLP:GetModule("ExecutionProgress")
    local execution = executionModule and executionModule:GetStatus(key) or nil
    local crafting = JLP:GetModule("Crafting")
    local transaction
    if crafting then
        if key == "ENCHANTING" and crafting.GetEnchantActionState then
            transaction = crafting:GetEnchantActionState(key, plan)
        elseif crafting.GetCraftActionState then
            transaction = crafting:GetCraftActionState(key, plan)
        end
    end
    local model=self:Resolve(key, plan, readiness, queue, tracking, transaction, execution)
    -- A shared presentation queue is useful for every registered profession.
    -- Being able to show its next action never promotes native capabilities.
    model.readOnly=advisory==true
    model.nativeDispatchAllowed=false
    return model, readiness, queue, tracking, transaction, execution
end

function ProfessionState:FormatCompact(model)
    if not model then return "Profession state: unavailable" end
    local text = tostring(model.label or model.state or "UNKNOWN")
    if model.recipe and (model.state == "CRAFT" or model.state == "NEXT_RECIPE" or model.state == "CRAFTING" or model.state == "VERIFY" or model.state == "LEARN_RECIPE") then
        text = text .. " - " .. tostring(model.recipe)
    end
    if model.reason and model.reason ~= "" then text = text .. " - " .. tostring(model.reason) end
    return "Profession state: " .. text
end

function ProfessionState:GetSummary()
    local lines = {}
    for _, key in ipairs(productionKeys()) do
        local model = self:Get(key)
        local label = professionLabel(key)
        lines[#lines + 1] = label .. ": " .. self:FormatCompact(model):gsub("^Profession state:%s*", "")
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ProfessionState", ProfessionState)
