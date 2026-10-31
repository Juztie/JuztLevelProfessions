local _, JLP = ...

-- Converts the global Next Best Action decision into one user-invoked CTA.
-- The CTA is progress-aware and source-session-aware: it keeps the persisted
-- execution baseline as the source of truth for partial actions, while the
-- workspace session decides whether the user still needs navigation or can act
-- in the current source.  It deliberately never performs protected world
-- interactions (bank/vendor/trainer/AH purchases) on the player's behalf.
local ContextAction = {
    contract = "progress-aware-source-session-cta-v3",
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end
local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local function currentPlan(key)
    local planner = JLP:GetModule("Planner")
    return planner and planner:GetProfessionPlan(key) or nil
end

local function currentAssist(key, plan)
    local assist = JLP:GetModule("ActionAssist")
    return assist and assist:Get(key, plan) or nil
end

local function currentReadiness(key, plan)
    local readiness = JLP:GetModule("CraftReadiness")
    return readiness and readiness:Get(key, plan) or nil
end

local function sourceNavigable(candidate)
    local navigation = JLP:GetModule("Navigation")
    return candidate and candidate.source and navigation and navigation:CanNavigate(candidate.source) and true or false
end

local function nonNegativeInt(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function positiveInt(value, fallback)
    return math.max(1, math.floor(tonumber(value) or tonumber(fallback) or 1))
end

local function rankShort(plan, action)
    local rank = plan and plan.step and plan.step.trainer and plan.step.trainer.rank or nil
    if not rank and action and action.text then
        rank = tostring(action.text):match("[Tt]rain%s+([^%.]-)%s+[Tt]o%s+[Uu]nlock")
            or tostring(action.text):match("[Tt]rain%s+([^%.]+)")
    end
    rank = tostring(rank or ""):gsub("%s+Tailoring$", ""):gsub("%s+Enchanting$", "")
    rank = rank:gsub("^%s+", ""):gsub("%s+$", "")
    if rank == "" or #rank > 18 then return "Rank" end
    return rank
end

local function recipeLearningLabel(candidate, active)
    local source = candidate and candidate.source or nil
    local sourceKind = tostring(source and source.kind or "")
    if sourceKind:match("formula") then return "Learn Formula" end
    if sourceKind:match("pattern") then return "Learn Pattern" end
    local recipe = active and active.recipe or candidate and candidate.action and candidate.action.recipe or nil
    if tostring(recipe or ""):lower():match("formula") then return "Learn Formula" end
    if tostring(recipe or ""):lower():match("pattern") then return "Learn Pattern" end
    return "Learn Recipe"
end

-- Project the current queue assignment; saved sessions/records never assign it.
local function assignedID(candidate)
    local action = type(candidate)=="table" and candidate.action or nil
    if type(action)~="table" or type(action.kind)~="string" or action.kind=="" or action.identityUnresolved or
        action.identityContract~="semantic-plan-action-v1" then return nil end
    local id = action.actionID
    if type(id)~="string" or id=="" or candidate.actionID~=id or
        (candidate.workspaceActionID~=nil and candidate.workspaceActionID~=id) then return nil end
    return id
end

local function baseModel(candidate, decision)
    local id = assignedID(candidate)
    return {
        contract = ContextAction.contract,
        key = candidate and candidate.key or nil,
        profession = candidate and candidate.profession or nil,
        candidate = candidate,
        decision = decision,
        action = candidate and candidate.action or nil,
        actionID = id,
        stableActionID = id,
        routeSession = candidate and candidate.routeSession or nil,
        routeSessionProgress = candidate and candidate.routeSession and candidate.routeSession.progressText or nil,
        travelTransition = decision and decision.travelTransition or nil,
        journeyStage = decision and decision.travelTransition and decision.travelTransition.stage or nil,
        navigationGuidance = decision and decision.navigationGuidance or nil,
        destinationHandoff = decision and decision.destinationHandoff or nil,
        handoffStage = decision and decision.destinationHandoff and decision.destinationHandoff.stage or nil,
        enabled = true,
        tone = "gold",
    }
end

-- Returns the persisted execution baseline for the selected queue-head.  The
-- ActionQueue quantity may shrink after partial progress; active.progress.required
-- intentionally stays anchored to the original action so the CTA does not jump
-- from e.g. "Retrieve 2 / 4" back to "Retrieve 0 / 2" after a refresh.
function ContextAction:ResolveProgress(candidate, plan)
    if type(candidate)~="table" then return nil end
    local id = assignedID(candidate)
    local execution = id and candidate.execution or nil
    if id and not execution then
        local module = JLP:GetModule("ExecutionProgress")
        execution = module and module:GetStatus(candidate.key) or nil
    end
    local active = type(execution)=="table" and execution.active or nil
    local action = type(candidate.action)=="table" and candidate.action or {}
    if type(active)~="table" or not id or active.id~=id or active.kind~=action.kind then
        active = nil
    end

    local session = candidate.session
    if type(session)~="table" or not id or session.actionID~=id or
        (session.executionID~=nil and session.executionID~=id) then session=nil end
    local current = active and nonNegativeInt(active.progress and active.progress.current) or 0
    local required = active and positiveInt(active.progress and active.progress.required, active.requestedQuantity)
        or positiveInt(action.quantity, 1)
    local remaining = math.max(0, required - current)
    local group = active and active.group or candidate.machineState
    local entered = session and (candidate.workspaceEntered==true or session.enteredAt~=nil) or false
    local sessionStatus = session and (session.status or candidate.sessionStatus) or nil

    local label
    if group == "RETRIEVE" then
        label = string.format("Retrieve %d / %d", math.min(current, required), required)
    elseif group == "ACQUIRE" then
        local station = tostring(candidate.requiredStation or "")
        label = string.format("%s %d", (station == "auction" or station == "vendor") and "Buy" or "Acquire", math.max(0, remaining))
    elseif group == "PREPARE" then
        label = string.format("Prepare %d / %d", math.min(current, required), required)
    elseif group == "TRAIN" then
        label = "Train " .. rankShort(plan, action)
    elseif group == "VERIFY" then
        label = "Verify Recipe"
    elseif group == "LEARN_RECIPE" then
        label = recipeLearningLabel(candidate, active)
    elseif group == "LEARN" then
        label = "Learn " .. professionLabel(candidate.key)
    end

    local progressText = active and execution.progressText or nil
    if not progressText and active and active.group == "RETRIEVE" then
        progressText = string.format("%d / %d moved to bags", math.min(current, required), required)
    elseif not progressText and active and active.group == "ACQUIRE" then
        progressText = string.format("%d / %d acquired", math.min(current, required), required)
    elseif not progressText and active and active.group == "PREPARE" then
        progressText = string.format("%d / %d prepared", math.min(current, required), required)
    end

    return {
        execution = active and execution or nil,
        active = active,
        group = group,
        current = current,
        required = required,
        remaining = remaining,
        ratio = required > 0 and math.min(1, current / required) or 0,
        label = label,
        progressText = progressText,
        session = session,
        sessionStatus = sessionStatus,
        workspaceEntered = entered,
        stableActionID = id,
    }
end

local function applyProgress(model, progress)
    model.progress = progress
    if not progress then return model end
    model.stableActionID = progress.stableActionID
    model.session = progress.session
    model.sessionStatus = progress.sessionStatus
    model.workspaceEntered = progress.workspaceEntered
    model.progressCurrent = progress.current
    model.progressRequired = progress.required
    model.progressRemaining = progress.remaining
    model.progressText = progress.progressText
    return model
end

local function progressDetail(progress, fallback)
    if progress and progress.progressText and progress.progressText ~= "" then
        return tostring(progress.progressText) .. ". " .. tostring(fallback or "Complete the current route action manually; JuztLevel will confirm it from live client evidence.")
    end
    return fallback
end

local function navigationDetail(model, fallback)
    local guidance = model and model.navigationGuidance or nil
    local handoff = model and model.destinationHandoff or nil
    local prefix = ""
    if handoff and handoff.showNextSource and handoff.nextDestination then
        prefix = "Next destination ready: " .. tostring(handoff.nextDestination) .. ". "
    end
    if not guidance or not guidance.available then return prefix .. tostring(fallback or "") end
    local localText = tostring(guidance.guideText or "")
    if localText == "" then return prefix .. tostring(fallback or "") end
    if fallback and fallback ~= "" then return prefix .. tostring(fallback) .. " Local guidance: " .. localText .. "." end
    return prefix .. "Local guidance: " .. localText .. "."
end

function ContextAction:_CraftCTA(candidate, decision, plan)
    local model = baseModel(candidate, decision)
    local readiness = currentReadiness(candidate.key, plan)
    local bagUnknown=readiness and readiness.immediateBagsKnown == false
    local immediate = not bagUnknown and tonumber(readiness and readiness.immediateBags) or 0
    local crafting = JLP:GetModule("Crafting")

    -- Registry workflow participation cannot authorize a read-only research or
    -- historical route to offer a working native Craft One/Enchant CTA.
    if not plan or plan.actionKind~="craft" or plan.executionEligible==false
        or plan.readOnly==true or plan.readOnlyRouteFallback==true or
        (plan.step and plan.step.executionEligible==false) then
        model.kind="REFERENCE"
        model.label="Verify native route"
        model.enabled=false
        model.tone="muted"
        model.detail="This profession participates in the workflow, but this route has no current native execution authorization."
        return model
    end

    if candidate.machineState == "CRAFTING" then
        model.kind = "WAIT"
        model.label = candidate.key == "ENCHANTING" and "Enchanting..." or "Crafting..."
        model.enabled = false
        model.tone = "muted"
        model.detail = "The current profession transaction is waiting for client confirmation."
        return model
    end

    if candidate.key == "ENCHANTING" then
        local target = crafting and crafting.GetSelectedEnchantTarget and crafting:GetSelectedEnchantTarget(candidate.key, plan) or nil
        if not target then
            model.kind = "CHOOSE_TARGET"
            model.label = "Choose Target"
            model.detail = "Choose the exact item instance to enchant in Optional Target."
            return model
        end
        model.kind = "ENCHANT"
        model.label = "Enchant"
        model.enabled = immediate > 0
        model.target = target
        model.detail = model.enabled and "Enchant the selected Optional Target." or (bagUnknown and "Bag stock is unverified; refresh live inventory." or "Required reagents are not currently available in bags.")
        if not model.enabled then model.tone = "muted" end
        return model
    end

    model.kind = "CRAFT_ONE"
    model.label = "Craft One"
    model.enabled = immediate > 0
    model.detail = model.enabled and "Craft one confirmed route recipe." or (bagUnknown and "Bag stock is unverified; refresh live inventory." or "Required materials are not currently available in bags.")
    if not model.enabled then model.tone = "muted" end
    return model
end

function ContextAction:Build(decision, viewingKey)
    local nextBest = JLP:GetModule("NextBestAction")
    decision = decision or (nextBest and nextBest:Build()) or nil
    if viewingKey and viewingKey~="dual" then
        local reg=registry()
        local availability=reg and reg:ResolveWorkflowAvailability(viewingKey,"executionFlow") or nil
        if availability and availability.state~="available" then
            local key=availability.key or viewingKey
            return {contract=self.contract,kind=availability.state=="not-production-enabled" and "STAGED" or "UNSUPPORTED",label=professionLabel(key),enabled=false,tone=availability.state=="not-production-enabled" and "muted" or "bad",decision=decision,key=key,terminalReason=availability.terminalReason,detail=availability.state=="not-production-enabled" and (professionLabel(key).." is registered but not production-enabled.") or "Profession is unsupported."}
        end
        if reg and availability and availability.key then viewingKey=availability.key end
    end
    local candidate = decision and decision.selected or nil

    -- A focused profession card must always own its CTA.  Alpha31 originally
    -- reused the global cross-profession selection here, which meant the
    -- Tailoring READINESS & WORKSPACE button could become "Open Enchanting"
    -- and actually switch/open Enchanting.  Global prioritization still drives
    -- Dual Mode, but a focused Tailoring/Enchanting page now resolves the
    -- dependency-safe candidate for that specific profession.
    if viewingKey and viewingKey ~= "dual" and nextBest and nextBest.GetCandidate then
        local localCandidate = nextBest:GetCandidate(decision, viewingKey)
        if localCandidate then
            if not candidate or candidate.key ~= viewingKey then
                local scoped = {}
                for key, value in pairs(decision or {}) do scoped[key] = value end
                scoped.selected = localCandidate
                scoped.selectedKey = localCandidate.key
                scoped.selectedAction = localCandidate.action
                -- TravelTransition/NavigationGuidance/DestinationHandoff describe
                -- the globally selected destination.  Never attach another
                -- profession's journey metadata to a focused local CTA.
                scoped.travelTransition = nil
                scoped.navigationGuidance = nil
                scoped.destinationHandoff = nil
                decision = scoped
            end
            candidate = localCandidate
        else
            candidate = nil
        end
    end

    if candidate and not assignedID(candidate) then candidate=nil end
    if not candidate then
        local localPlan=viewingKey and viewingKey~="dual" and currentPlan(viewingKey) or nil
        local terminal
        if localPlan and localPlan.actionKind=="complete" then
            local workspace=JLP:GetModule("WorkspaceOrchestrator")
            terminal=workspace and workspace.Build and workspace:Build(viewingKey,{plan=localPlan}) or nil
        end
        local actuallyComplete=terminal and terminal.key==viewingKey and terminal.plan==localPlan and
            terminal.workspaceState=="COMPLETE" and not terminal.action and not terminal.actionID and not terminal.terminalReason
        return {
            contract = self.contract,
            kind = actuallyComplete and "COMPLETE" or "UNQUALIFIED",
            label = actuallyComplete and (professionLabel(viewingKey) .. " Complete") or "No qualified route action",
            enabled = false,
            tone = actuallyComplete and "good" or "muted",
            decision = decision,
            key = viewingKey and viewingKey ~= "dual" and viewingKey or nil,
            detail = actuallyComplete and ("No pending " .. professionLabel(viewingKey) .. " route action remains.") or "No current executable action is qualified. Reference guidance remains available.",
        }
    end

    local plan = currentPlan(candidate.key)
    local assist = currentAssist(candidate.key, plan)
    local model = baseModel(candidate, decision)
    model.plan = plan
    model.assist = assist
    local progress = self:ResolveProgress(candidate, plan)
    applyProgress(model, progress)

    if candidate.machineState == "CRAFTING" then
        local craft = self:_CraftCTA(candidate, decision, plan)
        applyProgress(craft, progress)
        return craft
    end

    local station = tostring(candidate.requiredStation or "")
    local arrival = tostring(candidate.arrivalState or "GO")
    local isCraftStation = station:match("^craft:") ~= nil

    -- A direct craft/enchant is only offered after the profession workspace is
    -- actually ready. Otherwise the CTA first gets the player to that workspace.
    if candidate.machineState == "CRAFT" and (candidate.workspaceReady or arrival == "HERE_VERIFIED" or arrival == "HERE_UNVERIFIED") then
        local craft = self:_CraftCTA(candidate, decision, plan)
        applyProgress(craft, progress)
        return craft
    end

    if arrival == "OPEN_PROFESSION" or (isCraftStation and not candidate.workspaceReady) then
        model.kind = "OPEN_PROFESSION"
        model.label = "Open " .. professionLabel(candidate.key)
        model.detail = progressDetail(progress, "Open the profession window required by the current route action.")
        return model
    end

    -- Bank and AH actions retain the execution-baseline label across quantity
    -- changes and workspace entry/exit. The click still only opens guidance.
    if arrival == "OPEN_AUCTION" or station == "auction" then
        model.kind = "AH_GUIDANCE"
        model.label = progress and progress.label or "AH Guidance"
        model.enabled = assist and assist.canAH and true or false
        local fallback = candidate.workspaceReady
            and "Auction House workspace is open. Complete the purchase manually; JuztLevel will confirm owned-quantity evidence."
            or "Open JuztLevel Auction House guidance for the selected acquisition."
        model.detail = model.enabled and progressDetail(progress, fallback) or "Auction House guidance is unavailable for this action."
        if not model.enabled then model.tone = "muted" end
        return model
    end

    if arrival == "OPEN_BANK" or station == "bank" then
        model.kind = "GUIDANCE"
        model.label = progress and progress.label or "Bank Guidance"
        local fallback = candidate.workspaceReady
            and "Bank workspace is open. Move the requested items into your bags; JuztLevel will confirm inventory evidence."
            or (assist and assist.detail or "Open your bank manually and move the requested items into your bags. JuztLevel will confirm completion from inventory evidence.")
        model.detail = progressDetail(progress, fallback)
        return model
    end

    -- Source navigation remains explicit until the audited source/session has
    -- actually been entered. Once there, the CTA becomes the stable task label
    -- (Train Expert, Learn Formula, Buy N, etc.) instead of generic "Steps".
    if arrival == "TRAVEL_REQUIRED" or arrival == "WRONG_SOURCE" or arrival == "OPEN_TRAINER" or arrival == "OPEN_VENDOR" or arrival == "SWITCH_WORKSPACE" then
        if sourceNavigable(candidate) then
            model.kind = "SHOW_SOURCE"
            local journey = tostring(model.journeyStage or "")
            if model.destinationHandoff and model.destinationHandoff.showNextSource then model.label = "Show next source"
            elseif journey == "DESTINATION_ZONE" or journey == "NEAR_SOURCE" then model.label = "Show Local Map"
            elseif station == "trainer" then model.label = "Show Trainer"
            elseif station == "vendor" then model.label = "Show Vendor"
            else model.label = "Show Source" end
            local task = progress and progress.label and ("Current action: " .. progress.label .. ". ") or ""
            local fallback = task .. tostring(candidate.sourceGuidance or candidate.arrivalText or "Show the audited source on the map.")
            model.detail = navigationDetail(model, fallback)
            return model
        end
    end

    if candidate.workspaceReady then
        model.kind = "GUIDANCE"
        model.label = progress and progress.label or (station == "trainer" and "Trainer Steps" or station == "vendor" and "Vendor Steps" or station == "source" and "Source Steps" or "Continue")
        local fallback = assist and assist.detail or candidate.arrivalText or (candidate.action and candidate.action.text) or "Continue the current route action manually."
        model.detail = progressDetail(progress, fallback)
        return model
    end

    if sourceNavigable(candidate) then
        model.kind = "SHOW_SOURCE"
        local journey = tostring(model.journeyStage or "")
        if model.destinationHandoff and model.destinationHandoff.showNextSource then model.label = "Show next source"
        else model.label = (journey == "DESTINATION_ZONE" or journey == "NEAR_SOURCE") and "Show Local Map" or "Show Source" end
        local task = progress and progress.label and ("Current action: " .. progress.label .. ". ") or ""
        model.detail = navigationDetail(model, task .. tostring(candidate.sourceGuidance or "Show the audited source on the map."))
        return model
    end

    model.kind = "GUIDANCE"
    model.label = progress and progress.label or "Next Step"
    model.detail = progressDetail(progress, assist and assist.detail or candidate.sourceGuidance or candidate.arrivalText or (candidate.action and candidate.action.text) or "Continue the current route action manually.")
    return model
end

function ContextAction:Execute(model)
    model = model or self:Build()
    if not model then return false, "No contextual action is available." end
    if model.enabled == false then return false, model.detail or "The contextual action is not currently available." end

    if model.kind == "SWITCH_GUIDE" then
        if JLP.MainWindow and JLP.MainWindow.ShowGuideMode then
            JLP.MainWindow:Create():Show()
            JLP.MainWindow:ShowGuideMode(model.key)
            return true, "Opened " .. professionLabel(model.key) .. " guide."
        end
        return false, "Profession Guide navigation is unavailable."
    elseif model.kind == "OPEN_PROFESSION" then
        local api = JLP:GetModule("ProfessionAPI")
        if not api or not api.Open then return false, "Profession-open API is unavailable." end
        local ok = api:Open(model.key)
        return ok and true or false, ok and ("Opened " .. professionLabel(model.key) .. ".") or ("Could not open " .. professionLabel(model.key) .. ".")
    elseif model.kind == "AH_GUIDANCE" then
        local assist = JLP:GetModule("ActionAssist")
        if not assist then return false, "Action assistance is unavailable." end
        return assist:OpenAHGuidance(model.assist)
    elseif model.kind == "SHOW_SOURCE" then
        local navigation = JLP:GetModule("Navigation")
        if not navigation or not model.candidate or not model.candidate.source then return false, "No audited map source is available." end
        return navigation:ShowSource(model.candidate.source, { routeBound=true, travelStatus=model.travelTransition })
    elseif model.kind == "CRAFT_ONE" then
        local crafting = JLP:GetModule("Crafting")
        if not crafting then return false, "Direct profession crafting is unavailable." end
        return crafting:ExecuteCraft(model.key, model.plan or currentPlan(model.key), "one")
    elseif model.kind == "ENCHANT" then
        local crafting = JLP:GetModule("Crafting")
        if not crafting then return false, "Direct profession crafting is unavailable." end
        return crafting:Enchant(model.key, model.plan or currentPlan(model.key))
    elseif model.kind == "GUIDANCE" then
        return true, model.detail or "Continue the current route action manually."
    elseif model.kind == "CHOOSE_TARGET" then
        return false, "Choose Target must be opened from the Profession Guide Optional Target control."
    elseif model.kind == "COMPLETE" then
        return false, model.detail or "Profession route complete."
    elseif model.kind == "WAIT" then
        return false, model.detail or "The current profession action is still in progress."
    end

    return false, model.detail or "No safe contextual action is available for this route state."
end

function ContextAction:FormatCompact(model)
    model = model or self:Build()
    if not model then return "CTA: unavailable" end
    local suffix = model.enabled == false and " [disabled]" or ""
    if model.progress and model.progress.sessionStatus then suffix = suffix .. " [session " .. tostring(model.progress.sessionStatus) .. "]" end
    if model.progressCurrent ~= nil and model.progressRequired ~= nil and model.progress and model.progress.active then
        suffix = suffix .. string.format(" [%d/%d]", nonNegativeInt(model.progressCurrent), positiveInt(model.progressRequired, 1))
    end
    local routeSession = model.routeSession
    if routeSession and routeSession.totalActions and routeSession.totalActions > 0 then
        suffix = suffix .. string.format(" [batch %d/%d]", nonNegativeInt(routeSession.completedActions), positiveInt(routeSession.totalActions, 1))
    end
    if model.journeyStage then suffix = suffix .. " [journey " .. tostring(model.journeyStage) .. "]" end
    if model.handoffStage then suffix = suffix .. " [handoff " .. tostring(model.handoffStage) .. "]" end
    return string.format("CTA: %s - %s%s", tostring(model.kind or "NONE"), tostring(model.label or "Unavailable"), suffix)
end

function ContextAction:GetSummary()
    local nextBest = JLP:GetModule("NextBestAction")
    local decision = nextBest and nextBest:Build() or nil
    local lines={self:FormatCompact(self:Build(decision))}
    for _,key in ipairs(productionKeys()) do
        local scoped=self:Build(decision,key)
        lines[#lines+1]=professionLabel(key).." view: "..self:FormatCompact(scoped):gsub("^CTA:%s*", "")
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ContextAction", ContextAction)
