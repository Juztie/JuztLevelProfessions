local _, JLP = ...

-- Operational handoff layer between a completed/verified workspace and the
-- next Travel Session destination.  It never creates a waypoint on its own;
-- it only describes the current sequence and exposes whether the next audited
-- source is ready for an explicit user-triggered Show Source action.
local DestinationHandoff = {
    contract = "operational-destination-handoff-v1",
    current = nil,
    history = {},
    revision = 0,
    initialized = false,
}

local SOURCE_SENSITIVE = { vendor=true, trainer=true, source=true }

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return value end
    end
    return nil
end

local function boundedAppend(list, value, limit)
    list[#list + 1] = value
    while #list > (limit or 40) do table.remove(list, 1) end
end

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("[%p%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function stationLabel(station)
    local flow = JLP:GetModule("ExecutionFlow")
    if flow and flow.GetStationLabel then return flow:GetStationLabel(station) end
    if station == "bank" then return "Bank" end
    if station == "auction" then return "Auction House" end
    if station == "trainer" then return "Trainer" end
    if station == "vendor" then return "Vendor" end
    if station == "source" then return "Recipe Source" end
    local key = tostring(station or ""):match("^craft:(.+)$")
    if key == "TAILORING" then return "Tailoring" end
    if key == "ENCHANTING" then return "Enchanting" end
    return "Workspace"
end

local function firstPendingAction(session)
    for _, entry in ipairs(session and session.actions or {}) do
        if entry.status ~= "completed" then return entry end
    end
    return nil
end

local function workspaceVerified(routeStatus, workspaceContext)
    local session = routeStatus and routeStatus.active or nil
    if not session or not session.enteredAt then return false, false end
    if not SOURCE_SENSITIVE[session.station] then return true, true end

    local context = workspaceContext
    if not context then
        local orchestrator = JLP:GetModule("WorkspaceOrchestrator")
        context = orchestrator and orchestrator.GetContext and orchestrator:GetContext() or nil
    end
    if not context or context.station ~= session.station then return false, false end

    local expected = normalize(session.expectedSource)
    local observed = normalize(context.actorName or context.merchantName or context.trainerName)
    if expected == "" then return true, observed ~= "" end
    if observed == "" then return true, false end
    return expected == observed, true
end

local function routeCompletedPrefix(routeStatus)
    local completed = routeStatus and routeStatus.lastCompleted or nil
    if not completed and routeStatus and routeStatus.status == "completed" then completed = routeStatus.session end
    return completed
end

local function nextTarget(transition)
    return tostring(transition and (transition.target or transition.sourceName or (transition.batch and transition.batch.label)) or "next destination")
end

local function navigationAvailable(guidance)
    return guidance and guidance.available and guidance.source ~= nil and true or false
end

local function markerActive(routeMarker)
    local state = tostring(routeMarker and routeMarker.state or "")
    return state == "OWN_ACTIVE" or state == "OWN_ACTIVE_RECOVERED" or state == "USER_MATCHING_TARGET"
end

local function makeSequence(parts)
    local out = {}
    for _, value in ipairs(parts or {}) do
        if value and value ~= "" then out[#out + 1] = tostring(value) end
    end
    return table.concat(out, " → ")
end

function DestinationHandoff:BuildFrom(transition, routeStatus, routeMarker, navigationGuidance, workspaceContext, priorStatus)
    transition = transition or {}
    routeStatus = routeStatus or {}
    local stage = tostring(transition.stage or "PLANNED")
    local target = nextTarget(transition)
    local active = routeStatus.active
    local completed = routeCompletedPrefix(routeStatus)

    if transition.routeComplete or stage == "COMPLETE" then
        return {
            contract = self.contract,
            stage = "COMPLETE",
            tone = "good",
            label = "Route complete",
            guideText = "Route complete",
            sequenceText = "Route complete",
            routeComplete = true,
            evidence = "travel-transition-complete",
            showNextSource = false,
        }
    end

    if active and active.enteredAt and (tonumber(routeStatus.remainingActions) or tonumber(active.remainingActions) or 0) > 0 then
        local pending = firstPendingAction(active)
        local verified, identityVerified = workspaceVerified(routeStatus, workspaceContext)
        local action = tostring(pending and (pending.text or pending.recipe or pending.kind) or transition.actionText or "current action")
        local source = tostring(active.expectedSource or active.label or stationLabel(active.station))
        local prefix
        if SOURCE_SENSITIVE[active.station] then
            prefix = identityVerified and "Source verified" or (verified and "Source open" or "Reach source")
        else
            prefix = verified and "Workspace ready" or "Reach workspace"
        end
        return {
            contract = self.contract,
            stage = "FINISH_ACTION",
            tone = (identityVerified or ((not SOURCE_SENSITIVE[active.station]) and verified)) and "good" or "cyan",
            label = "Finish action",
            guideText = makeSequence({prefix, "Finish " .. action}),
            sequenceText = makeSequence({prefix, "Finish action"}),
            routeComplete = false,
            evidence = identityVerified and "verified-source-action-pending" or "entered-workspace-action-pending",
            currentSource = source,
            currentAction = action,
            currentSessionID = active.id,
            sourceVerified = identityVerified and true or false,
            workspaceVerified = verified and true or false,
            showNextSource = false,
        }
    end

    local completedKey = completed and completed.workspaceKey or nil
    local nextKey = transition.workspaceKey
    local priorContinuesHandoff = priorStatus
        and (priorStatus.stage == "NEXT_DESTINATION_READY" or priorStatus.stage == "NEXT_DESTINATION_ACTIVE")
        and tostring(priorStatus.completedSessionID or "") == tostring(completed and completed.id or "")
        and tostring(priorStatus.workspaceKey or "") == tostring(nextKey or "")
    local hasHandoff = completed and completedKey and nextKey and completedKey ~= nextKey
        and (stage == "HANDOFF" or priorContinuesHandoff)
    if hasHandoff then
        local completedLabel = tostring(completed.expectedSource or completed.label or stationLabel(completed.station))
        local nextReady = target
        local navReady = navigationAvailable(navigationGuidance)
        local markerIsActive = markerActive(routeMarker)
        local explicitShow = navReady and not markerIsActive
        local suffix = explicitShow and "Show next source" or (markerIsActive and "Route marker active" or "Continue to next workspace")
        local state = stage == "HANDOFF" and "NEXT_DESTINATION_READY" or "NEXT_DESTINATION_ACTIVE"
        return {
            contract = self.contract,
            stage = state,
            tone = stage == "HANDOFF" and "good" or "cyan",
            label = stage == "HANDOFF" and "Next destination ready" or "Next destination active",
            guideText = makeSequence({completedLabel .. " complete", "Next destination · " .. nextReady, suffix}),
            sequenceText = makeSequence({"Action complete", "Next destination ready", suffix}),
            routeComplete = false,
            evidence = stage == "HANDOFF" and "completed-workspace-handoff" or "completed-workspace-next-destination-active",
            completedWorkspace = completedLabel,
            completedSessionID = completed.id,
            workspaceKey = nextKey,
            nextDestination = nextReady,
            nextStage = stage,
            showNextSource = explicitShow,
            markerActive = markerIsActive,
            navigationAvailable = navReady,
        }
    end

    if stage == "ARRIVED_SOURCE" or stage == "ACTION_READY" then
        local source = target
        return {
            contract = self.contract,
            stage = "SOURCE_VERIFIED",
            tone = "good",
            label = "Source verified",
            guideText = makeSequence({"Source verified · " .. source, "Action ready"}),
            sequenceText = "Source verified → Action ready",
            routeComplete = false,
            evidence = tostring(transition.evidence or "verified-source-action-ready"),
            currentSource = source,
            sourceVerified = stage == "ARRIVED_SOURCE" and true or false,
            showNextSource = false,
        }
    end

    local navReady = navigationAvailable(navigationGuidance)
    local markerIsActive = markerActive(routeMarker)
    local explicitShow = navReady and not markerIsActive and (stage == "TRAVELING" or stage == "DESTINATION_ZONE" or stage == "NEAR_SOURCE" or stage == "WRONG_SOURCE")
    local fallback = transition.guideText or transition.instruction or ("Continue to " .. target)
    return {
        contract = self.contract,
        stage = "DESTINATION_PROGRESS",
        tone = transition.tone or "cyan",
        label = "Destination progress",
        guideText = explicitShow and makeSequence({tostring(fallback), "Show next source"}) or tostring(fallback),
        sequenceText = tostring(fallback),
        routeComplete = false,
        evidence = tostring(transition.evidence or "travel-transition-progress"),
        workspaceKey = transition.workspaceKey,
        nextDestination = target,
        nextStage = stage,
        showNextSource = explicitShow,
        markerActive = markerIsActive,
        navigationAvailable = navReady,
    }
end

function DestinationHandoff:Build()
    local transition = JLP:GetModule("TravelTransition")
    local routeSession = JLP:GetModule("RouteSession")
    local routeMarker = JLP:GetModule("RouteMarkerLifecycle")
    local navigationGuidance = JLP:GetModule("NavigationGuidance")
    local workspace = JLP:GetModule("WorkspaceOrchestrator")
    local transitionStatus = transition and transition:GetStatus() or nil
    return self:BuildFrom(
        transitionStatus,
        routeSession and routeSession:GetStatus() or nil,
        routeMarker and routeMarker:GetStatus() or nil,
        navigationGuidance and navigationGuidance:BuildFrom(transitionStatus) or nil,
        workspace and workspace:GetContext() or nil,
        self.current
    )
end

local function identity(status)
    if not status then return "nil" end
    return table.concat({
        tostring(status.stage or "UNKNOWN"),
        tostring(status.currentSessionID or status.completedSessionID or ""),
        tostring(status.workspaceKey or ""),
        tostring(status.nextDestination or status.currentSource or ""),
        tostring(status.showNextSource and 1 or 0),
    }, "|")
end

function DestinationHandoff:Observe(reason)
    local nextStatus = self:Build()
    local previous = self.current
    local changed = identity(previous) ~= identity(nextStatus)
        or tostring(previous and previous.guideText or "") ~= tostring(nextStatus and nextStatus.guideText or "")

    if changed then
        if previous then
            local archived = {}
            for key, value in pairs(previous) do archived[key] = value end
            archived.leftAt = now()
            archived.leaveReason = tostring(reason or "observe")
            boundedAppend(self.history, archived, 40)
        end
        nextStatus.enteredAt = now()
        self.current = nextStatus
        self.revision = self.revision + 1
        if JLP.EventBus then JLP.EventBus:Emit("DESTINATION_HANDOFF_UPDATED", self.revision, reason, self:GetStatus()) end
    elseif self.current then
        self.current.lastObservedAt = now()
        self.current.lastReason = tostring(reason or "observe")
    end
    return changed, self:GetStatus()
end

function DestinationHandoff:Initialize()
    if not self.initialized then
        self.initialized = true
        if JLP.EventBus then
            for _, eventName in ipairs({
                "TRAVEL_TRANSITION_UPDATED", "ROUTE_SESSION_UPDATED", "ROUTE_MARKER_UPDATED",
                "WORKSPACE_ORCHESTRATION_UPDATED", "PROFESSION_EXECUTION_UPDATED",
                "CRAFT_ACTION_UPDATED", "ENCHANT_ACTION_UPDATED", "PROFESSION_TRANSACTION_UPDATED",
            }) do
                JLP.EventBus:On(eventName, function() DestinationHandoff:Observe(eventName) end)
            end
        end
    end
    return self:Observe("player-login")
end

function DestinationHandoff:GetStatus()
    local status = self.current or self:Build()
    status.revision = self.revision
    return status
end

function DestinationHandoff:FormatCompact(status)
    status = status or self:GetStatus()
    return string.format("Destination handoff: %s - %s", tostring(status.stage or "UNKNOWN"), tostring(status.guideText or status.label or "Continue"))
end

function DestinationHandoff:GetSummary()
    local status = self:GetStatus()
    local lines = {
        self:FormatCompact(status),
        "Evidence: " .. tostring(status.evidence or "unavailable"),
    }
    if status.currentSource then lines[#lines + 1] = "Current source: " .. tostring(status.currentSource) end
    if status.currentAction then lines[#lines + 1] = "Current action: " .. tostring(status.currentAction) end
    if status.nextDestination then lines[#lines + 1] = "Next destination: " .. tostring(status.nextDestination) end
    lines[#lines + 1] = "Show next source: " .. (status.showNextSource and "yes" or "no")
    return table.concat(lines, "\n")
end

JLP:RegisterModule("DestinationHandoff", DestinationHandoff)
