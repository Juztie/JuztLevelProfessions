local _, JLP = ...

-- Converts the planned TravelSession chain into one observable execution stage.
-- The module never claims that a player reached an NPC from coordinates alone:
-- destination-zone and normalized-map proximity are guidance only.  A named
-- source is considered arrived only when the expected trainer/vendor/source
-- workspace is actually open (or a non-source-sensitive workspace is open).
local TravelTransition = {
    contract = "proximity-confidence-travel-transition-v2",
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

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("[%p%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function boundedAppend(list, value, limit)
    list[#list + 1] = value
    while #list > (limit or 40) do table.remove(list, 1) end
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

local function workspaceKey(station, actor)
    local routeSession = JLP:GetModule("RouteSession")
    if routeSession and routeSession.GetWorkspaceKey then
        return routeSession:GetWorkspaceKey(station, actor)
    end
    station = tostring(station or "unknown")
    if SOURCE_SENSITIVE[station] then
        local name = normalize(actor)
        if name ~= "" then return station .. "|" .. name end
    end
    return station
end

local function contextActor(context)
    return context and (context.actorName or context.merchantName or context.trainerName) or nil
end

local function contextMatchesWorkspace(context, station, expectedSource)
    if not context or context.station ~= station then return false, false end
    if not SOURCE_SENSITIVE[station] then return true, true end
    local expected = normalize(expectedSource)
    local observed = normalize(contextActor(context))
    if expected == "" then return true, observed ~= "" end
    if observed == "" then return true, false end
    return expected == observed, true
end

local function originMatchesDestination(origin, destination)
    if not origin or not destination then return false, nil end
    local originMap, destinationMap = tonumber(origin.mapID), tonumber(destination.mapID)
    if originMap and destinationMap and originMap == destinationMap then return true, "destination-map" end
    local originZone, destinationZone = normalize(origin.zone), normalize(destination.zone)
    if originZone ~= "" and destinationZone ~= "" and originZone == destinationZone then return true, "destination-zone" end
    return false, nil
end

local function primaryAction(batch)
    local entry = batch and batch.actions and batch.actions[1] or nil
    return entry and (entry.text or entry.recipe or entry.kind) or nil
end

local function transitionShort(transition)
    local kind = transition and transition.kind or "unknown"
    if kind == "same-zone" then return "same zone" end
    if kind == "same-continent" then return "same continent" end
    if kind == "cross-continent" then return "cross continent" end
    if kind == "dungeon" then return "dungeon source" end
    if kind == "workspace-switch" then return "workspace switch" end
    if kind == "current-workspace" then return "already here" end
    return "travel route partially audited"
end

local function targetLabel(batch)
    return tostring(batch and (batch.label or batch.sourceName or stationLabel(batch.station)) or "next workspace")
end

local function currentPlan(status)
    if status and status.plan then return status.plan end
    if status and status.batches then return status end
    return nil
end

local function sameCompletedWorkspace(context, routeStatus)
    local completed = routeStatus and routeStatus.status == "completed" and routeStatus.session or routeStatus and routeStatus.lastCompleted or nil
    if not completed or not context then return false, completed end
    local match = contextMatchesWorkspace(context, completed.station, completed.expectedSource)
    return match == true, completed
end

local function openInstruction(batch)
    local station = batch and batch.station or nil
    if station == "bank" then return "Open your bank" end
    if station == "auction" then return "Open the Auction House" end
    if station == "trainer" then return "Open " .. targetLabel(batch) end
    if station == "vendor" then return "Open " .. targetLabel(batch) end
    if station == "source" then return "Continue to " .. targetLabel(batch) end
    local profession = tostring(station or ""):match("^craft:(.+)$")
    if profession == "TAILORING" then return "Open Tailoring" end
    if profession == "ENCHANTING" then return "Open Enchanting" end
    return "Open " .. targetLabel(batch)
end

function TravelTransition:BuildFrom(travelStatus, context, origin, routeStatus)
    local plan = currentPlan(travelStatus)
    local batch = plan and plan.currentBatch or travelStatus and travelStatus.currentBatch or nil
    local router = JLP:GetModule("TravelRouter")
    context = context or { station="world", label="World" }
    origin = origin or (router and router.GetPlayerOrigin and router:GetPlayerOrigin()) or nil
    routeStatus = routeStatus or (JLP:GetModule("RouteSession") and JLP:GetModule("RouteSession"):GetStatus()) or nil

    if not batch then
        return {
            contract = self.contract,
            stage = "COMPLETE",
            tone = "good",
            title = "Route complete",
            instruction = "No pending profession travel transition remains.",
            guideText = "Route complete",
            routeComplete = true,
            evidence = "travel-session-route-complete",
        }
    end

    local destination = router and router.GetSourceLocation and batch.source and router:GetSourceLocation(batch.source) or nil
    local actionText = primaryAction(batch)
    local target = targetLabel(batch)
    local status = {
        contract = self.contract,
        stage = "PLANNED",
        tone = "cyan",
        title = target,
        instruction = "Continue to " .. target,
        guideText = "Next · " .. target,
        routeComplete = false,
        batch = batch,
        batchIndex = tonumber(batch.index) or 1,
        workspaceKey = batch.workspaceKey,
        station = batch.station,
        target = target,
        sourceName = batch.sourceName,
        destination = destination,
        actionText = actionText,
        transition = batch.transition,
        transitionKind = batch.transitionKind,
        audited = batch.audited and true or false,
        origin = origin,
    }

    local confidenceModule = JLP:GetModule("SourceConfidence")
    local confidence = confidenceModule and confidenceModule.Evaluate and confidenceModule:Evaluate(batch, context, origin, destination) or nil
    status.sourceConfidence = confidence
    status.confidenceLevel = confidence and confidence.level or "UNKNOWN"
    status.confidenceLabel = confidence and confidence.label or "No source confidence available"
    status.confidenceTone = confidence and confidence.tone or "muted"

    -- An entered RouteSession is authoritative until every action in that
    -- workspace has confirmed completion evidence.
    if routeStatus and routeStatus.active and routeStatus.enteredAt and (tonumber(routeStatus.remainingActions) or 0) > 0 then
        local label = tostring(routeStatus.label or stationLabel(routeStatus.station))
        local done, total = tonumber(routeStatus.completedActions) or 0, tonumber(routeStatus.totalActions) or 0
        status.stage = "FINISH_WORKSPACE"
        status.tone = "cyan"
        status.title = "Finish " .. label
        status.instruction = string.format("Finish the current %s batch before traveling onward: %d / %d actions completed.", label, done, total)
        status.guideText = string.format("Finish %s · %d/%d actions", label, done, total)
        status.evidence = "entered-route-session-with-pending-actions"
        status.routeSessionID = routeStatus.sessionID
        status.completedActions = done
        status.totalActions = total
        status.remainingActions = tonumber(routeStatus.remainingActions) or math.max(0, total - done)
        status.confidenceLevel = "WORKSPACE_ACTIVE"
        status.confidenceLabel = "Current workspace confirmed"
        status.confidenceTone = "good"
        return status
    end

    -- Preserve an explicit handoff while the completed workspace is still open.
    -- The moment the player closes/leaves it, the transition becomes TRAVELING
    -- or OPEN_WORKSPACE depending on the next batch.
    local stillAtCompleted, completed = sameCompletedWorkspace(context, routeStatus)
    if stillAtCompleted and completed and workspaceKey(completed.station, completed.expectedSource) ~= batch.workspaceKey then
        local completedLabel = tostring(completed.label or stationLabel(completed.station))
        local done, total = tonumber(completed.completedActions) or 0, tonumber(completed.totalActions) or 0
        status.stage = "HANDOFF"
        status.tone = "good"
        status.title = completedLabel .. " complete"
        status.instruction = string.format("%s is complete. Next: %s.", completedLabel, openInstruction(batch))
        status.guideText = string.format("%s %d/%d complete → %s", completedLabel, done, total, target)
        status.evidence = "completed-route-session-still-open"
        status.completedWorkspace = completedLabel
        status.confidenceLevel = "HANDOFF_CONFIRMED"
        status.confidenceLabel = "Completed workspace confirmed"
        status.confidenceTone = "good"
        return status
    end

    local workspaceMatch, sourceVerified = contextMatchesWorkspace(context, batch.station, batch.sourceName)
    if workspaceMatch then
        if SOURCE_SENSITIVE[batch.station] and not sourceVerified then
            status.stage = "ARRIVED_UNVERIFIED"
            status.tone = "warn"
            status.title = target .. " open"
            status.instruction = "The required workspace is open, but the source identity could not be verified."
            status.guideText = target .. " open · source unverified"
            status.evidence = "workspace-open-source-unresolved"
        elseif SOURCE_SENSITIVE[batch.station] then
            status.stage = "ARRIVED_SOURCE"
            status.tone = "good"
            status.title = "Arrived at " .. target
            status.instruction = actionText and ("Perform current action: " .. tostring(actionText)) or "Perform the current route action."
            status.guideText = "Arrived · " .. target .. (actionText and (" → " .. tostring(actionText)) or "")
            status.evidence = "verified-source-workspace-open"
        else
            status.stage = "ACTION_READY"
            status.tone = "good"
            status.title = target .. " ready"
            status.instruction = actionText and ("Perform current action: " .. tostring(actionText)) or "Perform the current route action."
            status.guideText = target .. " ready" .. (actionText and (" → " .. tostring(actionText)) or "")
            status.evidence = "required-workspace-open"
        end
        return status
    end

    -- If a source-sensitive workspace of the right type is open but belongs to
    -- a different NPC, never claim arrival merely because the station matches.
    if SOURCE_SENSITIVE[batch.station] and context and context.station == batch.station then
        status.stage = "WRONG_SOURCE"
        status.tone = "bad"
        status.title = "Wrong " .. stationLabel(batch.station)
        status.instruction = "Leave the current source and continue to " .. target .. "."
        status.guideText = "Wrong source → " .. target
        status.evidence = "source-name-mismatch"
        return status
    end

    if confidence and confidence.level == "NEAR_SOURCE" then
        status.stage = "NEAR_SOURCE"
        status.tone = "cyan"
        status.title = "Near " .. target
        status.instruction = "You are near the audited map coordinate for " .. target .. ". Continue locally and interact with the source to verify arrival."
        status.guideText = "Near " .. target .. " · source not verified"
        status.evidence = confidence.evidence or "audited-map-proximity-only"
        status.distanceNormalized = confidence.distanceNormalized
        status.distancePercent = confidence.distancePercent
        return status
    end

    if destination then
        local inDestination, arrivalEvidence = originMatchesDestination(origin, destination)
        if inDestination then
            status.stage = "DESTINATION_ZONE"
            status.tone = "cyan"
            status.title = tostring(destination.zone or target) .. " reached"
            status.instruction = "Destination zone reached. Continue locally to " .. target .. "."
            status.guideText = tostring(destination.zone or "Destination") .. " reached → " .. target
            status.evidence = confidence and confidence.evidence or arrivalEvidence or "destination-zone-match"
            return status
        end
        status.stage = "TRAVELING"
        status.tone = "cyan"
        status.title = "Travel to " .. target
        status.instruction = tostring(batch.transition and batch.transition.label or "Travel normally to the audited source.")
        status.guideText = "Travel to " .. target .. " · " .. transitionShort(batch.transition)
        status.evidence = batch.audited and "audited-travel-transition" or "workspace-travel-guidance"
        return status
    end

    status.stage = "OPEN_WORKSPACE"
    status.tone = "cyan"
    status.title = openInstruction(batch)
    status.instruction = openInstruction(batch) .. "."
    status.guideText = openInstruction(batch)
    status.evidence = "workspace-guidance-no-physical-location"
    return status
end

function TravelTransition:Build()
    local travel = JLP:GetModule("TravelSession")
    local route = JLP:GetModule("RouteSession")
    local workspace = JLP:GetModule("WorkspaceOrchestrator")
    local router = JLP:GetModule("TravelRouter")
    local travelStatus = travel and travel:GetStatus() or nil
    local context = workspace and workspace:GetContext() or { station="world", label="World" }
    local origin = router and router:GetPlayerOrigin() or nil
    local routeStatus = route and route:GetStatus() or nil
    return self:BuildFrom(travelStatus, context, origin, routeStatus)
end

local function identity(status)
    if not status then return "nil" end
    return table.concat({
        tostring(status.stage or "UNKNOWN"),
        tostring(status.workspaceKey or ""),
        tostring(status.routeSessionID or ""),
        tostring(status.evidence or ""),
    }, "|")
end

function TravelTransition:Observe(reason)
    local nextStatus = self:Build()
    local previous = self.current
    local changed = identity(previous) ~= identity(nextStatus)
        or tostring(previous and previous.guideText or "") ~= tostring(nextStatus and nextStatus.guideText or "")
        or tonumber(previous and previous.completedActions) ~= tonumber(nextStatus and nextStatus.completedActions)

    if changed then
        if previous then
            local archived = {}
            for key, value in pairs(previous) do archived[key] = value end
            archived.leftAt = now()
            archived.leaveReason = tostring(reason or "observe")
            boundedAppend(self.history, archived, 40)
        end
        nextStatus.enteredAt = now()
        if nextStatus.stage == "DESTINATION_ZONE" then nextStatus.zoneReachedAt = nextStatus.enteredAt end
        if nextStatus.stage == "NEAR_SOURCE" then nextStatus.nearSourceAt = nextStatus.enteredAt end
        if nextStatus.stage == "ARRIVED_SOURCE" or nextStatus.stage == "ACTION_READY" then nextStatus.arrivedAt = nextStatus.enteredAt end
        if nextStatus.stage == "HANDOFF" then nextStatus.handoffAt = nextStatus.enteredAt end
        self.current = nextStatus
        self.revision = self.revision + 1
        if JLP.EventBus then JLP.EventBus:Emit("TRAVEL_TRANSITION_UPDATED", self.revision, reason, self:GetStatus()) end
    elseif self.current then
        self.current.lastObservedAt = now()
        self.current.lastReason = tostring(reason or "observe")
    end
    return changed, self:GetStatus()
end

function TravelTransition:Initialize()
    if not self.initialized then
        self.initialized = true
        if JLP.EventBus then
            for _, eventName in ipairs({
                "TRAVEL_SESSION_UPDATED", "ROUTE_SESSION_UPDATED",
                "WORKSPACE_ORCHESTRATION_UPDATED", "PROFESSION_EXECUTION_UPDATED",
            }) do
                JLP.EventBus:On(eventName, function() TravelTransition:Observe(eventName) end)
            end
        end
    end
    return self:Observe("player-login")
end

function TravelTransition:GetStatus()
    local status = self.current or self:Build()
    status.revision = self.revision
    return status
end

function TravelTransition:FormatCompact(status)
    status = status or self:GetStatus()
    return string.format("Travel transition: %s - %s", tostring(status.stage or "UNKNOWN"), tostring(status.guideText or status.instruction or "Continue"))
end

function TravelTransition:GetSummary()
    local status = self:GetStatus()
    local lines = {
        self:FormatCompact(status),
        "Evidence: " .. tostring(status.evidence or "unavailable"),
    }
    if status.transitionKind then lines[#lines + 1] = "Transition: " .. tostring(status.transitionKind) end
    lines[#lines + 1] = "Source confidence: " .. tostring(status.confidenceLabel or status.confidenceLevel or "unavailable")
    if tonumber(status.distancePercent) then lines[#lines + 1] = string.format("Normalized map distance: %.2f%%", tonumber(status.distancePercent)) end
    if status.destination and status.destination.zone then lines[#lines + 1] = "Destination zone: " .. tostring(status.destination.zone) end
    if status.actionText then lines[#lines + 1] = "Action: " .. tostring(status.actionText) end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("TravelTransition", TravelTransition)
