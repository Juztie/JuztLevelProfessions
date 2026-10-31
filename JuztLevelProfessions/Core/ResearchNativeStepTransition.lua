local _, JLP = ...

-- Alpha79 owns the post-settlement handoff when a guarded native Craft One
-- crosses a research route-step boundary.  It never grants route or execution
-- authority itself.  Instead it destroys any remaining in-memory authorization
-- artifacts tied to the old snapshot, rebuilds the read-only consumer from live
-- profession state, and proves that the next recipe/route index is represented
-- by a new current snapshot before the transition is considered ready.
local ResearchNativeStepTransition = {
    contract = "native-skill-route-step-transition-orchestrator-v1",
    transitionContract = "research-native-route-step-handoff-v1",
    provenanceContract = "research-native-dispatch-provenance-v1",
    productionTailoringProvenanceContract = "production-tailoring-native-dispatch-provenance-v1",
    productionTailoringTransitionContract = "production-tailoring-native-route-step-handoff-v1",
    authority = "post-settlement-current-step-handoff-only",
    persisted = false,
    executionEligible = false,
    executionAuthorityEnabled = false,
    lastByProfession = {},
    transitionByLedger = {},
    initialized = false,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function normalizeMode(value)
    return value == "aggressive" and "aggressive" or "normal"
end

local function shallowCopy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function provenanceOf(action)
    local provenance = type(action) == "table" and action.authorityProvenance or nil
    if type(provenance) ~= "table" then return nil end
    if provenance.contract == ResearchNativeStepTransition.provenanceContract then return provenance end
    if provenance.contract == ResearchNativeStepTransition.productionTailoringProvenanceContract and provenance.autoRouteSessionToken then return provenance end
    return nil
end

local function currentRecipeID(plan)
    local step = plan and plan.step or nil
    if not step then return nil end
    return tonumber(step.recipeID)
        or tonumber(step.rawStep and step.rawStep.recipeID)
        or tonumber(step.datasetStep and step.datasetStep.recipeID)
end

function ResearchNativeStepTransition:_Emit(report)
    if JLP.EventBus and JLP.EventBus.Emit and type(report) == "table" then
        JLP.EventBus:Emit("RESEARCH_NATIVE_STEP_TRANSITION_UPDATED", shallowCopy(report))
    end
end

function ResearchNativeStepTransition:_Record(report)
    if type(report) ~= "table" then return nil end
    local key = normalizeKey(report.professionKey)
    if key then self.lastByProfession[key] = shallowCopy(report) end
    if report.ledgerID and report.transitionReady == true then
        self.transitionByLedger[tostring(report.ledgerID)] = shallowCopy(report)
    end
    self:_Emit(report)
    return report
end

function ResearchNativeStepTransition:_PurgeOldExecutionArtifacts(professionKey, reason)
    professionKey = normalizeKey(professionKey)
    local result = { intents=0, reservations=0, clickOrigins=0 }
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    if readiness and readiness.RevokeIntentsForProfession then
        result.intents = tonumber((select(1, readiness:RevokeIntentsForProfession(professionKey, reason)))) or 0
    end
    local gate = JLP:GetModule("ResearchExecutionAuthorityGate")
    if gate and gate.InvalidateProfession then
        local invalidated = gate:InvalidateProfession(professionKey, reason)
        if type(invalidated) == "table" then
            result.reservations = tonumber(invalidated.reservations) or 0
            result.clickOrigins = tonumber(invalidated.clickOrigins) or 0
        end
    end
    return result
end

function ResearchNativeStepTransition:Evaluate(action, options)
    options = type(options) == "table" and options or {}
    local provenance = provenanceOf(action)
    if not provenance then return nil, "not-supported-native-route-transition" end

    local professionKey = normalizeKey(action.key or provenance.professionKey)
    local mode = normalizeMode(provenance.mode or action.mode)
    local ledgerID = action.ledgerID or action.transactionID
    local existing = ledgerID and self.transitionByLedger[tostring(ledgerID)] or nil
    if existing then return shallowCopy(existing), "transition-already-ready" end

    local report = {
        contract = self.contract,
        transitionContract = provenance.contract == self.productionTailoringProvenanceContract and self.productionTailoringTransitionContract or self.transitionContract,
        sourceProvenanceContract = provenance.contract,
        authority = self.authority,
        professionKey = professionKey,
        mode = mode,
        ledgerID = ledgerID,
        transactionStatus = tostring(action.status or "unknown"),
        fromRecipe = action.recipeName or provenance.recipe,
        fromRecipeID = tonumber(action.recipeID or provenance.recipeID),
        fromRouteIndex = tonumber(provenance.routeIndex),
        fromSkill = tonumber(action.startedSkill or provenance.startedSkill),
        toSkill = tonumber(action.endingSkill),
        targetSkill = tonumber(action.targetSkill or provenance.skillTarget),
        oldSnapshotToken = provenance.snapshotToken,
        oldStateFingerprint = provenance.stateFingerprint,
        transitionReady = false,
        routeAuthorityReacquired = false,
        executionEligible = false,
        executionAuthorityEnabled = false,
        persisted = false,
    }

    if tostring(action.status or "") ~= "success" then
        report.state = "native-step-transition-not-successful"
        return self:_Record(report), report.state
    end

    local api = JLP:GetModule("ProfessionAPI")
    local liveProfession = options.professionState or (api and api.Get and api:Get(professionKey)) or nil
    report.toSkill = tonumber(liveProfession and liveProfession.skill) or report.toSkill
    report.maxSkill = tonumber(liveProfession and liveProfession.maxSkill)
    report.skillGain = math.max(0, tonumber(action.skillGain) or ((report.toSkill and report.fromSkill) and (report.toSkill - report.fromSkill) or 0))
    report.crossedTarget = report.targetSkill ~= nil and report.toSkill ~= nil and report.toSkill >= report.targetSkill or false

    -- Any confirmed skill movement invalidates authorization derived from the old
    -- snapshot, even when the recipe band has not changed yet.  At a route-step
    -- boundary this purge is mandatory before the new consumer is evaluated.
    if report.skillGain > 0 or report.crossedTarget then
        report.purged = self:_PurgeOldExecutionArtifacts(professionKey, "native-route-step-progress")
    else
        report.purged = { intents=0, reservations=0, clickOrigins=0 }
    end

    if not report.crossedTarget then
        report.state = report.skillGain > 0 and "native-step-progress-within-route" or "native-step-transition-not-reached"
        return self:_Record(report), report.state
    end

    local consumerBridge = JLP:GetModule("ResearchPlannerConsumerBridge")
    local consumer = consumerBridge and consumerBridge.Build and consumerBridge:Build(professionKey, mode, options) or nil
    report.consumerState = consumer and consumer.state or "consumer-bridge-unavailable"
    report.sourceAuthorityState = consumer and consumer.sourceAuthorityState or nil
    report.newSnapshotToken = consumer and consumer.snapshotToken or nil
    report.newStateFingerprint = consumer and consumer.stateFingerprint or nil
    local plan = consumer and consumer.plan or nil
    local step = plan and plan.step or nil
    report.toRecipe = step and step.recipe or nil
    report.toRecipeID = currentRecipeID(plan)
    report.toRouteIndex = step and tonumber(step.routeIndex) or nil

    local consumerReady = consumer
        and consumer.state == "consumer-authority-active"
        and consumer.consumerAuthorityEnabled == true
        and consumer.routeAuthorityEnabled == true
        and consumer.plannerEligible == true
        and consumer.executionEligible == false
    local snapshotChanged = report.newSnapshotToken ~= nil
        and tostring(report.newSnapshotToken or "") ~= tostring(report.oldSnapshotToken or "")
    local recipeChanged = report.toRecipeID ~= nil and report.fromRecipeID ~= nil and report.toRecipeID ~= report.fromRecipeID
    local routeChanged = report.toRouteIndex ~= nil and report.fromRouteIndex ~= nil and report.toRouteIndex ~= report.fromRouteIndex

    report.consumerReady = consumerReady and true or false
    report.snapshotChanged = snapshotChanged
    report.recipeChanged = recipeChanged
    report.routeChanged = routeChanged

    if consumerReady and snapshotChanged and recipeChanged and routeChanged then
        report.state = "native-route-step-transition-ready"
        report.transitionReady = true
        report.routeAuthorityReacquired = true
    elseif not consumerReady then
        report.state = "native-route-step-transition-awaiting-authority"
    elseif not snapshotChanged then
        report.state = "native-route-step-transition-stale-snapshot"
    elseif not recipeChanged or not routeChanged then
        report.state = "native-route-step-transition-identity-mismatch"
    end

    return self:_Record(report), report.state
end

function ResearchNativeStepTransition:ObserveCraftAction(action, options)
    local provenance = provenanceOf(action)
    if not provenance then return false, "not-supported-native-route-transition" end
    if tostring(action.status or "") ~= "success" then return false, "native-craft-not-successful" end
    local report, state = self:Evaluate(action, options)
    return report ~= nil, state, report
end

function ResearchNativeStepTransition:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and shallowCopy(row) or nil
end

function ResearchNativeStepTransition:GetSummary(professionKey)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local last = self:GetLast(professionKey)
    local lines = {
        "RESEARCH NATIVE SKILL-UP / ROUTE-STEP HANDOFF",
        professionKey,
        "Contract: " .. self.contract,
        "Transition contract: " .. self.transitionContract,
        "Authority: post-settlement handoff only",
        "Persistence: none",
        "Execution authority: not granted by this module",
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines + 1] = string.format("Skill: %s -> %s · target %s", tostring(last.fromSkill or "?"), tostring(last.toSkill or "?"), tostring(last.targetSkill or "?"))
        lines[#lines + 1] = string.format("Recipe: %s / %s -> %s / %s", tostring(last.fromRecipe or "unknown"), tostring(last.fromRecipeID or "unresolved"), tostring(last.toRecipe or "unknown"), tostring(last.toRecipeID or "unresolved"))
        lines[#lines + 1] = string.format("Route index: %s -> %s", tostring(last.fromRouteIndex or "?"), tostring(last.toRouteIndex or "?"))
        lines[#lines + 1] = "Snapshot changed: " .. (last.snapshotChanged and "yes" or "no")
        lines[#lines + 1] = "Route authority reacquired: " .. (last.routeAuthorityReacquired and "yes" or "no")
        local purged = last.purged or {}
        lines[#lines + 1] = string.format("Old auth artifacts purged: %d intents · %d reservations · %d click origins", tonumber(purged.intents) or 0, tonumber(purged.reservations) or 0, tonumber(purged.clickOrigins) or 0)
    end
    return table.concat(lines, "\n")
end

function ResearchNativeStepTransition:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("CRAFT_ACTION_UPDATED", function(action)
            self:ObserveCraftAction(action)
        end)
    end
    return true
end

function ResearchNativeStepTransition:Validate()
    local errors, warnings = {}, {}
    if self.persisted ~= false or self.executionEligible ~= false or self.executionAuthorityEnabled ~= false then
        errors[#errors + 1] = "native route-step transition authority boundary invalid"
    end
    for _, name in ipairs({"ResearchPlannerConsumerBridge", "ResearchExecutionReadiness", "ResearchExecutionAuthorityGate", "ProfessionAPI"}) do
        if not JLP:GetModule(name) then errors[#errors + 1] = "native route-step transition dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeStepTransition", ResearchNativeStepTransition)
