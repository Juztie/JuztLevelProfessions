local _, JLP = ...

-- Alpha81 classifies the point at which a bounded alpha80 sequence must stop
-- because the freshly rebuilt post-settlement state no longer authorizes an
-- immediate Craft One.  It never dispatches, never creates execution authority
-- and never persists continuation state.  Instead it produces one explicit
-- handoff describing the next action the Profession Guide should surface.
local ResearchSequentialStopPolicy = {
    contract = "bounded-sequence-stop-policy-v1",
    boundaryContract = "research-sequential-non-craft-boundary-v1",
    authority = "post-settlement-no-dispatch-handoff-only",
    persisted = false,
    nativeDispatchAllowed = false,
    automaticResume = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(value)
    return value == "aggressive" and "aggressive" or "normal"
end

local function currentAction(queue)
    local index = tonumber(queue and queue.currentIndex) or 0
    return queue and queue.actions and queue.actions[index] or nil
end

local function actionCategory(action)
    local kind = tostring(action and action.kind or "")
    if kind == "train-rank" then return "TRAIN", "Train profession rank" end
    if kind == "learn-recipe" then return "LEARN_RECIPE", "Learn recipe" end
    if kind == "verify-recipe" then return "VERIFY_RECIPE", "Verify recipe" end
    if kind == "learn-profession" then return "LEARN_PROFESSION", "Learn profession" end
    if kind:match("^retrieve") then return "RETRIEVE", "Retrieve materials" end
    if kind:match("^acquire") then return "ACQUIRE", "Acquire materials" end
    if kind == "craft-tool" or kind == "craft-intermediate" then return "PREPARE", "Prepare prerequisite" end
    if kind == "craft-leveling" then return "CRAFT", "Craft current recipe" end
    if kind ~= "" then return "OTHER", "Complete next action" end
    return nil, nil
end

local function boundary(model, category, state, label, text, detail, action, consumer, readiness)
    model.terminal = true
    model.sequenceMayContinue = false
    model.state = state
    model.category = category
    model.label = label
    model.nextActionText = text
    model.detail = detail
    model.action = action
    model.actionKind = action and action.kind or nil
    model.consumerState = consumer and consumer.state or model.consumerState
    model.sourceAuthorityState = consumer and consumer.sourceAuthorityState or model.sourceAuthorityState
    model.snapshotToken = consumer and consumer.snapshotToken or nil
    model.stateFingerprint = consumer and consumer.stateFingerprint or nil
    model.recipe = consumer and consumer.plan and consumer.plan.step and consumer.plan.step.recipe or nil
    model.recipeID = consumer and consumer.plan and consumer.plan.step and (tonumber(consumer.plan.step.recipeID) or tonumber(consumer.plan.step.rawStep and consumer.plan.step.rawStep.recipeID) or tonumber(consumer.plan.step.datasetStep and consumer.plan.step.datasetStep.recipeID)) or nil
    model.routeIndex = consumer and consumer.plan and consumer.plan.step and tonumber(consumer.plan.step.routeIndex) or nil
    model.skillTarget = consumer and consumer.plan and consumer.plan.step and tonumber(consumer.plan.step.skillTarget) or nil
    model.readinessState = readiness and readiness.state or nil
    model.blockedGate = readiness and readiness.blockedGate or nil
    model.blockedState = readiness and readiness.blockedState or nil
    return model
end

local function qualificationBoundary(model, professionKey, mode, options, consumer)
    local qualification = JLP:GetModule("ResearchRouteSegmentQualification")
    local q = qualification and qualification.Build and qualification:Build(professionKey, mode, options) or nil
    if not q then return nil end
    local active
    local allPassed = #(q.segments or {}) > 0
    for _, row in ipairs(q.segments or {}) do
        if row.relevance == "active" and not active then active = row end
        if row.relevance ~= "already-passed" then allPassed = false end
    end
    if allPassed then
        return boundary(model, "COMPLETE", "sequence-boundary-route-complete", "Route complete",
            "The current research profession route is complete; no further sequence craft is authorized.", nil, nil, consumer, nil)
    end
    if not active then return nil end
    local status = tostring(active.status or "")
    if status == "blocked-live-trainer-rank" or status == "blocked-live-trainer-source" or status == "blocked-live-character-level" then
        local gate
        for _, row in ipairs(active.trainerRank and active.trainerRank.gates or {}) do
            if row.ready ~= true then gate = row break end
        end
        local tier = gate and gate.tier or "next profession rank"
        local detail
        if status == "blocked-live-character-level" and gate and gate.requiredLevel then
            detail = "Reach character level " .. tostring(gate.requiredLevel) .. ", then train " .. tostring(tier) .. "."
        elseif status == "blocked-live-trainer-source" then
            detail = "Resolve the live trainer source for " .. tostring(tier) .. " before continuing."
        else
            detail = "Train " .. tostring(tier) .. " to unlock the next profession skill band."
        end
        return boundary(model, "TRAIN", "sequence-boundary-train", "Train profession rank", detail, status, nil, consumer, nil)
    elseif status == "blocked-live-recipe-not-known" then
        local recipe
        for _, row in ipairs(active.recipes and active.recipes.recipes or {}) do
            if row.knowledge == "not-known" then recipe = row.recipe break end
        end
        return boundary(model, "LEARN_RECIPE", "sequence-boundary-learn-recipe", "Learn recipe",
            "Learn " .. tostring(recipe or "the required recipe") .. " before continuing the sequence.", status, nil, consumer, nil)
    elseif status == "awaiting-live-recipe-availability" or status == "awaiting-current-build-recipe-revalidation" then
        local recipe = active.recipes and active.recipes.recipes and active.recipes.recipes[1] and active.recipes.recipes[1].recipe or nil
        return boundary(model, "VERIFY_RECIPE", "sequence-boundary-verify-recipe", "Verify recipe",
            "Open the profession window and verify " .. tostring(recipe or "the required recipe") .. " on the current Forever build.", status, nil, consumer, nil)
    end
    return nil
end

local function routeAuthorityBoundary(model, consumer, professionKey, mode, options)
    local qualified = qualificationBoundary(model, professionKey, mode, options, consumer)
    if qualified then return qualified end
    local state = tostring(consumer and (consumer.sourceAuthorityState or consumer.blockedReason or consumer.state) or "consumer-authority-unavailable")
    model.consumerState = consumer and consumer.state or "consumer-authority-unavailable"
    model.sourceAuthorityState = state
    if state == "blocked-live-shadow-parity" or state == "blocked-adaptive-telemetry-provenance" then
        return boundary(model, "PLANNER_PARITY", "sequence-boundary-planner-parity-revoked", "Planner parity revoked",
            "Revalidate current-build Planner/shadow parity before continuing the sequence.", state, nil, consumer, nil)
    elseif state == "route-authority-feature-gate-disabled" then
        return boundary(model, "AUTHORITY_DISABLED", "sequence-boundary-route-authority-disabled", "Route authority disabled",
            "Re-enable controlled route authority and revalidate the current route before crafting again.", state, nil, consumer, nil)
    elseif state == "awaiting-authority-ready-segment" or state == "consumer-authority-revoked" then
        return boundary(model, "AUTHORITY_REVALIDATION", "sequence-boundary-authority-revalidation", "Revalidate route authority",
            "Re-establish current-build research authority before starting another guarded craft.", state, nil, consumer, nil)
    end
    return boundary(model, "AUTHORITY_REVALIDATION", "sequence-boundary-authority-unavailable", "Revalidate route authority",
        "Resolve the current research-authority blocker before starting another guarded craft.", state, nil, consumer, nil)
end

function ResearchSequentialStopPolicy:Evaluate(professionKey, mode, options, consumerOverride)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}
    local model = {
        contract = self.contract,
        boundaryContract = self.boundaryContract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        state = "sequence-boundary-evaluating",
        terminal = false,
        sequenceMayContinue = false,
        persisted = false,
        nativeDispatchAllowed = false,
        automaticResume = false,
    }

    local bridge = JLP:GetModule("ResearchPlannerConsumerBridge")
    local consumer = consumerOverride or (bridge and bridge.Build and bridge:Build(professionKey, mode, options) or nil)
    model.consumerState = consumer and consumer.state or "consumer-authority-unavailable"
    model.sourceAuthorityState = consumer and consumer.sourceAuthorityState or nil

    if not consumer or consumer.state ~= "consumer-authority-active" or consumer.consumerAuthorityEnabled ~= true
        or consumer.routeAuthorityEnabled ~= true or consumer.plannerEligible ~= true then
        return routeAuthorityBoundary(model, consumer, professionKey, mode, options), consumer
    end

    local plan = consumer.plan
    local queue = consumer.actionQueue
    local action = currentAction(queue)
    local category, label = actionCategory(action)

    if not plan then
        return boundary(model, "ROUTE_BLOCKED", "sequence-boundary-plan-unavailable", "Planner unavailable",
            "Wait for a current Planner plan before starting another guarded craft.", "plan-unavailable", action, consumer, nil), consumer
    end

    if plan.actionKind == "complete" then
        return boundary(model, "COMPLETE", "sequence-boundary-route-complete", "Route complete",
            tostring(plan.action or "The current profession route is complete."), nil, action, consumer, nil), consumer
    elseif plan.actionKind == "train" then
        return boundary(model, "TRAIN", "sequence-boundary-train", "Train profession rank",
            tostring(action and action.text or plan.action or "Train the next profession rank before continuing."), action and action.detail or nil, action, consumer, nil), consumer
    elseif plan.actionKind == "learn" then
        return boundary(model, "LEARN_PROFESSION", "sequence-boundary-learn-profession", "Learn profession",
            tostring(action and action.text or plan.action or "Learn the profession before continuing."), action and action.detail or nil, action, consumer, nil), consumer
    elseif plan.actionKind ~= "craft" or not plan.step then
        return boundary(model, "ROUTE_BLOCKED", "sequence-boundary-route-blocked", "Resolve route blocker",
            tostring(action and action.text or plan.action or "Resolve the current route blocker before crafting again."), action and action.detail or nil, action, consumer, nil), consumer
    end

    local readiness = consumer.readiness
    if category == "LEARN_RECIPE" then
        return boundary(model, category, "sequence-boundary-learn-recipe", label,
            tostring(action.text or ("Learn " .. tostring(plan.step.recipe or "the current recipe") .. ".")), action.detail, action, consumer, nil), consumer
    elseif category == "VERIFY_RECIPE" then
        return boundary(model, category, "sequence-boundary-verify-recipe", label,
            tostring(action.text or "Open the profession window and verify the current recipe."), action.detail, action, consumer, nil), consumer
    elseif category == "RETRIEVE" then
        return boundary(model, category, "sequence-boundary-retrieve", label,
            tostring(action.text or "Retrieve the required materials from storage."), action.detail, action, consumer, nil), consumer
    elseif category == "ACQUIRE" then
        return boundary(model, category, "sequence-boundary-acquire", label,
            tostring(action.text or "Acquire the missing materials before continuing."), action.detail, action, consumer, nil), consumer
    elseif category == "PREPARE" then
        return boundary(model, category, "sequence-boundary-prepare", label,
            tostring(action.text or "Prepare the prerequisite material or tool before continuing."), action.detail, action, consumer, nil), consumer
    end

    local exec = JLP:GetModule("ResearchExecutionReadiness")
    local execution = exec and exec.Evaluate and exec:Evaluate(professionKey, mode, options) or nil
    model.executionReadinessState = execution and execution.state or "unavailable"
    model.blockedGate = execution and execution.blockedGate or nil
    model.blockedState = execution and execution.blockedState or nil

    if execution and execution.executionReadinessReady == true then
        model.state = "sequence-boundary-craft-ready"
        model.category = "CRAFT"
        model.label = "Craft current recipe"
        model.nextActionText = tostring(action and action.text or plan.action or "Craft the current recipe.")
        model.detail = action and action.detail or nil
        model.action = action
        model.actionKind = action and action.kind or nil
        model.snapshotToken = consumer.snapshotToken
        model.stateFingerprint = consumer.stateFingerprint
        model.recipe = plan.step.recipe
        model.recipeID = tonumber(plan.step.recipeID) or tonumber(plan.step.rawStep and plan.step.rawStep.recipeID) or tonumber(plan.step.datasetStep and plan.step.datasetStep.recipeID)
        model.routeIndex = tonumber(plan.step.routeIndex)
        model.skillTarget = tonumber(plan.step.skillTarget)
        model.sequenceMayContinue = true
        return model, consumer
    end

    local blockedGate = tostring(execution and execution.blockedGate or "")
    if blockedGate == "profession-window" then
        return boundary(model, "OPEN_PROFESSION_WINDOW", "sequence-boundary-profession-window", "Open profession window",
            "Open the matching profession window before starting another guarded craft.", execution and execution.blockedState or nil, action, consumer, execution), consumer
    elseif blockedGate == "recipe-identity" or blockedGate == "native-craft-api" then
        return boundary(model, "RECIPE_ACCESS", "sequence-boundary-recipe-access", "Resolve recipe access",
            "Re-open or learn the exact current recipe so its live recipe identity can be verified.", execution and execution.blockedState or nil, action, consumer, execution), consumer
    elseif blockedGate == "material-readiness" then
        return boundary(model, "MATERIALS", "sequence-boundary-materials", "Prepare materials",
            tostring(action and action.text or "Acquire, retrieve, or prepare the materials required for the next craft."), action and action.detail or execution and execution.blockedState or nil, action, consumer, execution), consumer
    elseif blockedGate == "native-craftability" then
        -- Readiness may be blocked because the count is UNKNOWN/ERROR, not zero.
        -- A missing live API receipt never proves that materials are depleted.
        local knownZero = execution and execution.craftabilityStatus == "KNOWN" and execution.nativeCraftable == 0
        local label = knownZero and "Client confirms zero crafts" or "Verify live craftability"
        local detail = knownZero
            and "The current profession API confirms zero crafts available for this recipe. Recheck the recipe and reagents."
            or ("The current profession API could not confirm craftability (" .. tostring(execution and execution.craftabilityReason or "unknown") .. "). Reopen the matching profession panel and verify the recipe; material exhaustion is NOT confirmed.")
        return boundary(model, "NATIVE_CRAFTABILITY", "sequence-boundary-native-craftability", label,
            detail, execution and execution.blockedState or nil, action, consumer, execution), consumer
    elseif blockedGate == "transaction-clear" then
        return boundary(model, "WAIT_TRANSACTION", "sequence-boundary-transaction", "Wait for transaction settlement",
            "Finish or recover the current profession transaction before starting another guarded craft.", execution and execution.blockedState or nil, action, consumer, execution), consumer
    elseif blockedGate == "consumer-authority" or blockedGate == "snapshot-current" or blockedGate == "build-provenance" or blockedGate == "live-profession" then
        return boundary(model, "AUTHORITY_REVALIDATION", "sequence-boundary-authority-revalidation", "Revalidate current authority",
            "Re-establish the current profession, build and consumer snapshot before continuing.", execution and execution.blockedState or nil, action, consumer, execution), consumer
    end

    return boundary(model, category or "PREPARE", "sequence-boundary-execution-readiness", label or "Resolve execution blocker",
        tostring(action and action.text or "Resolve the current execution-readiness blocker before continuing."), execution and execution.blockedState or nil, action, consumer, execution), consumer
end

function ResearchSequentialStopPolicy:IsCurrentHandoff(lastSequence, professionKey, mode, options)
    if type(lastSequence) ~= "table" or (lastSequence.state ~= "bounded-sequence-stopped-boundary" and lastSequence.state ~= "auto-route-stopped-boundary") or type(lastSequence.stopBoundary) ~= "table" then
        return nil
    end
    local current = self:Evaluate(professionKey or lastSequence.professionKey, mode or lastSequence.mode, options)
    if not current or current.terminal ~= true then return nil end
    if tostring(current.category or "") ~= tostring(lastSequence.stopBoundary.category or "") then return nil end
    return current
end

function ResearchSequentialStopPolicy:GetSummary(professionKey, mode, options)
    local model = self:Evaluate(professionKey, mode, options)
    local lines = {
        "RESEARCH BOUNDED SEQUENCE / NON-CRAFT STOP POLICY",
        tostring(model.professionKey) .. " / " .. tostring(model.mode),
        "Contract: " .. self.contract,
        "Boundary contract: " .. self.boundaryContract,
        "Authority: post-settlement handoff only · no dispatch",
        "State: " .. tostring(model.state),
        "Terminal boundary: " .. (model.terminal and "yes" or "no"),
        "Category: " .. tostring(model.category or "none"),
        "Next action: " .. tostring(model.nextActionText or "none"),
        "Consumer state: " .. tostring(model.consumerState or "unknown"),
        "Source route authority: " .. tostring(model.sourceAuthorityState or "unknown"),
        "Native dispatch: forbidden",
        "Automatic resume: disabled",
        "Persistence: none",
    }
    if model.blockedGate then lines[#lines + 1] = "Blocked gate: " .. tostring(model.blockedGate) .. " / " .. tostring(model.blockedState or "blocked") end
    return table.concat(lines, "\n")
end

function ResearchSequentialStopPolicy:Validate()
    local errors, warnings = {}, {}
    if self.persisted ~= false then errors[#errors + 1] = "sequential stop policy must not persist state" end
    if self.nativeDispatchAllowed ~= false then errors[#errors + 1] = "sequential stop policy must not dispatch native crafting" end
    if self.automaticResume ~= false then errors[#errors + 1] = "sequential stop policy must not auto-resume sequences" end
    for _, name in ipairs({"ResearchPlannerConsumerBridge", "ResearchExecutionReadiness", "ActionQueue"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "sequential stop-policy dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchSequentialStopPolicy", ResearchSequentialStopPolicy)
