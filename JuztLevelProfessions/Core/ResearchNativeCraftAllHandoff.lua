local _, JLP = ...

-- Alpha86 owns the read-only handoff after a guarded research Craft All has
-- terminally settled.  It never dispatches work.  Target completion is allowed
-- to expose the freshly replanned next route step; material exhaustion remains
-- pinned to the exact recipe that Craft All was authorized for and exposes the
-- concrete acquisition/retrieval action needed to make that same recipe
-- craftable again.
local ResearchNativeCraftAllHandoff = {
    contract = "craft-all-post-settlement-planner-handoff-v1",
    handoffContract = "research-craft-all-post-settlement-handoff-v1",
    provenanceContract = "research-native-craft-all-provenance-v1",
    authority = "post-settlement-read-only-planner-handoff-only",
    automaticExecution = false,
    automaticRouteAdvance = false,
    persistence = "none",
    lastSettlementByProfession = {},
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

local function copy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function currentAction(queue)
    if type(queue) ~= "table" or type(queue.actions) ~= "table" then return nil end
    return queue.actions[tonumber(queue.currentIndex) or 0]
end

local function isResearchCraftAllSettlement(report)
    return type(report) == "table"
        and report.contract == "native-current-recipe-craft-all-settlement-orchestrator-v1"
        and report.settlementContract == "research-native-craft-all-settlement-v1"
        and report.terminal == true
end

local function isPositiveTerminal(report)
    local state = tostring(report and report.state or "")
    local status = tostring(report and report.transactionStatus or "")
    return state == "craft-all-settlement-confirmed"
        or state == "craft-all-settlement-recovered-success"
        or status == "success"
        or status == "RECOVERED_SUCCESS"
end

local function actionText(action, fallback)
    if type(action) ~= "table" then return fallback end
    local text = tostring(action.text or fallback or "Continue the profession plan.")
    if action.detail and tostring(action.detail) ~= "" then
        text = text .. " " .. tostring(action.detail)
    end
    return text
end

local function stepRecipeID(step, consumer)
    return tonumber(step and step.recipeID)
        or tonumber(step and step.rawStep and step.rawStep.recipeID)
        or tonumber(step and step.datasetStep and step.datasetStep.recipeID)
        or tonumber(consumer and consumer.recipeID)
end

local function materialAction(action)
    local kind = tostring(action and action.kind or "")
    return kind:match("^retrieve") ~= nil
        or kind:match("^acquire") ~= nil
        or kind == "craft-intermediate"
        or kind == "craft-tool"
        or kind == "retrieve-tool"
        or kind == "retrieve-tool-material"
        or kind == "acquire-tool-material"
end

function ResearchNativeCraftAllHandoff:_Emit(report)
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_HANDOFF_UPDATED", copy(report))
    end
end

function ResearchNativeCraftAllHandoff:_Record(professionKey, report)
    professionKey = normalizeKey(professionKey)
    if not professionKey or type(report) ~= "table" then return nil end
    self.lastByProfession[professionKey] = report
    self:_Emit(report)
    return report
end

function ResearchNativeCraftAllHandoff:Clear(professionKey, reason)
    professionKey = normalizeKey(professionKey)
    if not professionKey then return false end
    local had = self.lastSettlementByProfession[professionKey] ~= nil or self.lastByProfession[professionKey] ~= nil
    self.lastSettlementByProfession[professionKey] = nil
    self.lastByProfession[professionKey] = nil
    if had and JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_HANDOFF_UPDATED", {
            contract=self.contract,handoffContract=self.handoffContract,professionKey=professionKey,
            state="craft-all-handoff-cleared",reason=tostring(reason or "superseded"),terminal=true,
            automaticExecution=false,automaticRouteAdvance=false,persisted=false,
        })
    end
    return had
end

function ResearchNativeCraftAllHandoff:ObserveSettlement(report)
    if not isResearchCraftAllSettlement(report) then return false, "not-terminal-research-craft-all" end
    local professionKey = normalizeKey(report.professionKey)
    if not professionKey then return false, "craft-all-handoff-profession-unresolved" end
    if not isPositiveTerminal(report) then
        self:Clear(professionKey, "non-success-terminal")
        return false, "craft-all-handoff-non-success-terminal"
    end
    self.lastSettlementByProfession[professionKey] = copy(report)
    local model = self:Build(professionKey, "normal")
    self:_Record(professionKey, model)
    return true, model.state, model
end

function ResearchNativeCraftAllHandoff:Build(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    local settlement = options.settlement or self.lastSettlementByProfession[professionKey]
    local model = {
        contract = self.contract,
        handoffContract = self.handoffContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        state = "craft-all-handoff-none",
        active = false,
        terminal = true,
        automaticExecution = false,
        automaticRouteAdvance = false,
        persisted = false,
        sourceLedgerID = settlement and settlement.ledgerID or nil,
        sourceRecipe = settlement and settlement.recipe or nil,
        sourceRecipeID = settlement and tonumber(settlement.recipeID) or nil,
        sourceTargetSkill = settlement and tonumber(settlement.targetSkill) or nil,
        completedCount = settlement and tonumber(settlement.completedCount) or 0,
        requestedCount = settlement and tonumber(settlement.requestedCount) or 0,
        targetReached = settlement and settlement.targetReached == true or false,
        sourceStopReason = settlement and settlement.stopReason or nil,
        recovered = settlement and settlement.recovered == true or false,
    }
    if not settlement or not isResearchCraftAllSettlement(settlement) or not isPositiveTerminal(settlement) then
        return model
    end

    local consumerBridge = JLP:GetModule("ResearchPlannerConsumerBridge")
    local consumer = consumerBridge and consumerBridge.Build and consumerBridge:Build(professionKey, mode, options) or nil
    model.consumerState = consumer and consumer.state or "consumer-unavailable"
    model.currentBuild = consumer and consumer.currentBuild or nil
    model.currentSnapshotToken = consumer and consumer.snapshotToken or nil
    model.currentStateFingerprint = consumer and consumer.stateFingerprint or nil

    local plan = consumer and consumer.consumerAuthorityEnabled == true and consumer.plan or nil
    local step = plan and plan.step or nil
    local queue = consumer and consumer.actionQueue or nil
    local action = currentAction(queue)
    model.nextActionKind = action and action.kind or (plan and plan.actionKind) or nil
    model.nextActionText = actionText(action, plan and plan.action or "Revalidate the profession route.")
    model.nextRecipe = step and step.recipe or nil
    model.nextRecipeID = stepRecipeID(step, consumer)
    model.nextRouteIndex = step and tonumber(step.routeIndex) or nil
    model.nextSkillTarget = step and tonumber(step.skillTarget) or nil
    model.recipeChanged = model.nextRecipeID and model.sourceRecipeID and model.nextRecipeID ~= model.sourceRecipeID or false

    if settlement.targetReached == true then
        model.handoffKind = "TARGET_REACHED"
        model.label = "TARGET REACHED"
        model.active = true
        if consumer and consumer.consumerAuthorityEnabled == true and plan then
            model.state = "craft-all-handoff-target-replanned"
            if plan.actionKind == "complete" then
                model.nextActionText = "Craft All target reached. Profession route complete."
            elseif plan.actionKind == "craft" and step then
                model.nextActionText = "Craft All target reached. Next verified route step: " .. tostring(step.recipe or "next recipe") .. "."
            elseif action then
                model.nextActionText = actionText(action, "Craft All target reached. Continue with the newly verified route action.")
            else
                model.nextActionText = "Craft All target reached. Continue with the newly verified Planner step."
            end
        else
            model.state = "craft-all-handoff-target-awaiting-authority"
            model.nextActionText = "Craft All target reached. Waiting for the current Planner route to revalidate; no automatic craft will start."
        end
        return model
    end

    local stopReason = tostring(settlement.stopReason or "")
    local exhaustedByReason = stopReason:lower():find("no more materials", 1, true) ~= nil
    local exhaustedByBatch = (tonumber(settlement.requestedCount) or 0) > 0
        and (tonumber(settlement.completedCount) or 0) >= (tonumber(settlement.requestedCount) or 0)
    if exhaustedByReason or exhaustedByBatch then
        model.handoffKind = "MATERIALS"
        model.label = "MATERIALS NEEDED"
        model.active = true
        local sameRecipe = step and ((model.nextRecipeID and model.sourceRecipeID and model.nextRecipeID == model.sourceRecipeID)
            or (not model.nextRecipeID and tostring(step.recipe or "") == tostring(model.sourceRecipe or ""))) or false
        model.sameRecipe = sameRecipe
        if consumer and consumer.consumerAuthorityEnabled == true and plan and plan.actionKind == "craft" and sameRecipe then
            if materialAction(action) then
                model.state = "craft-all-handoff-materials-action"
                model.nextActionText = actionText(action, "Acquire materials for " .. tostring(model.sourceRecipe or "the current recipe") .. ".")
            else
                -- If the inventory has already changed again by the time this is
                -- rendered, the material boundary is resolved.  Do not preserve a
                -- stale stop banner and never auto-resume the old Craft All.
                model.state = "craft-all-handoff-materials-resolved"
                model.active = false
                model.nextActionText = "Materials are available again for " .. tostring(model.sourceRecipe or "the current recipe") .. ". Start a new action explicitly."
            end
        elseif consumer and consumer.consumerAuthorityEnabled == true and plan and not sameRecipe then
            model.state = "craft-all-handoff-recipe-drift-blocked"
            model.nextActionText = "Craft All stopped before target because the locked recipe is no longer the verified current step. Revalidate before starting a new action."
        else
            model.state = "craft-all-handoff-materials-awaiting-authority"
            model.nextActionText = "Craft All stopped before target because the locked recipe ran out of materials. Waiting for current route/material authority; no automatic continuation is allowed."
        end
        return model
    end

    model.handoffKind = "OTHER"
    model.state = "craft-all-handoff-external-stop"
    model.active = false
    model.nextActionText = "Craft All stopped. Revalidate before starting another action."
    return model
end

function ResearchNativeCraftAllHandoff:GetCurrent(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local model = self:Build(professionKey, mode, options)
    self.lastByProfession[professionKey] = model
    if model.active ~= true then return nil, model.state, model end
    return model, model.state, model
end

function ResearchNativeCraftAllHandoff:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ResearchNativeCraftAllHandoff:GetSummary(professionKey, mode, options)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local model = self:Build(professionKey, mode, options)
    local lines = {
        "RESEARCH CRAFT ALL POST-SETTLEMENT / PLANNER HANDOFF",
        professionKey .. " / " .. normalizeMode(mode),
        "Contract: " .. self.contract,
        "State: " .. tostring(model.state),
        "Handoff: " .. tostring(model.handoffKind or "none"),
        "Source recipe: " .. tostring(model.sourceRecipe or "none") .. " / " .. tostring(model.sourceRecipeID or "unresolved"),
        "Source target: " .. tostring(model.sourceTargetSkill or "unknown"),
        "Target reached: " .. (model.targetReached and "yes" or "no"),
        "Next action: " .. tostring(model.nextActionText or "none"),
        "Next recipe: " .. tostring(model.nextRecipe or "none") .. " / " .. tostring(model.nextRecipeID or "unresolved"),
        "Recipe changed: " .. (model.recipeChanged and "yes" or "no"),
        "Automatic next-recipe craft: forbidden",
        "Automatic Craft All resume: forbidden",
        "Auto Route: separate explicit control",
        "Persistence: none",
    }
    return table.concat(lines, "\n")
end

function ResearchNativeCraftAllHandoff:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("RESEARCH_CRAFT_ALL_SETTLEMENT_UPDATED", function(report)
            if type(report) == "table" and report.terminal == true then self:ObserveSettlement(report) end
        end)
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action)
            if type(action) ~= "table" then return end
            local key = normalizeKey(action.key)
            if not key then return end
            local status = tostring(action.status or "")
            if status == "pending" or status == "dispatching" or status == "crafting" or status == "settlement-pending" then
                local last = self.lastSettlementByProfession[key]
                if last and tostring(last.ledgerID or "") ~= tostring(action.ledgerID or action.transactionID or "") then
                    self:Clear(key, "new-craft-action")
                end
            end
        end)
    end
    return true
end

function ResearchNativeCraftAllHandoff:Validate()
    local errors, warnings = {}, {}
    if self.automaticExecution ~= false or self.automaticRouteAdvance ~= false or self.persistence ~= "none" then
        errors[#errors+1] = "Craft All post-settlement handoff authority boundary invalid"
    end
    for _, name in ipairs({"ResearchNativeCraftAllSettlement","ResearchPlannerConsumerBridge","ActionQueue"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "Craft All post-settlement handoff dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeCraftAllHandoff", ResearchNativeCraftAllHandoff)
