local _, JLP = ...

-- Owns only waypoints that JuztLevel explicitly set for the active Travel
-- Session destination.  A player's existing waypoint is never silently
-- replaced, and a waypoint that no longer matches the JuztLevel-owned target is
-- treated as user-owned from that point forward.  Route markers are retired on
-- destination changes or verified source arrival; if JuztLevel explicitly
-- replaced a user waypoint, the prior waypoint is restored when possible.
local RouteMarkerLifecycle = {
    contract = "route-marker-lifecycle-v1",
    current = nil,
    history = {},
    revision = 0,
    initialized = false,
}

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return value end
    end
    return nil
end

local function clonePoint(point)
    if type(point) ~= "table" then return nil end
    local mapID = tonumber(point.mapID or point.uiMapID)
    local x, y = tonumber(point.x), tonumber(point.y)
    if not mapID or not x or not y then return nil end
    return { mapID=mapID, uiMapID=mapID, x=x, y=y }
end

local function targetKey(target)
    if type(target) ~= "table" then return nil end
    local mapID = tonumber(target.mapID or target.uiMapID)
    local x, y = tonumber(target.x), tonumber(target.y)
    if not mapID or not x or not y then return nil end
    return string.format("%d:%.5f:%.5f", mapID, x, y)
end

local function boundedAppend(list, value, limit)
    list[#list + 1] = value
    while #list > (limit or 30) do table.remove(list, 1) end
end

local function sourceFor(status)
    if not status then return nil end
    if status.batch and status.batch.source then return status.batch.source end
    if status.destination and status.destination.source then return status.destination.source end
    return nil
end

local function archivedCopy(session, reason)
    local out = {}
    for key, value in pairs(session or {}) do out[key] = value end
    out.archivedAt = now()
    out.archiveReason = tostring(reason or "archive")
    return out
end

function RouteMarkerLifecycle:_Emit(reason)
    self.revision = self.revision + 1
    if JLP.EventBus then JLP.EventBus:Emit("ROUTE_MARKER_UPDATED", self.revision, reason, self:GetStatus()) end
end

function RouteMarkerLifecycle:_Destination(status)
    status = status or (JLP:GetModule("TravelTransition") and JLP:GetModule("TravelTransition"):GetStatus()) or nil
    if not status or status.routeComplete or status.stage == "COMPLETE" then return nil end
    local source = sourceFor(status)
    local navigation = JLP:GetModule("Navigation")
    local target = navigation and source and navigation:GetTarget(source) or nil
    if not target then return nil end
    return {
        key = targetKey(target),
        target = target,
        source = source,
        sourceName = source and (source.name or source.recipe or source.material) or status.sourceName or status.target,
        stage = status.stage,
        workspaceKey = status.workspaceKey,
    }
end

function RouteMarkerLifecycle:_Begin(destination, reason)
    if not destination or not destination.key then return nil end
    self.current = {
        id = string.format("marker:%s:%s", destination.key, tostring(now() or self.revision + 1)),
        destinationKey = destination.key,
        target = destination.target,
        source = destination.source,
        sourceName = destination.sourceName,
        workspaceKey = destination.workspaceKey,
        createdAt = now(),
        lastReason = tostring(reason or "destination"),
        routeBound = true,
        markerOwned = false,
        state = "READY",
        label = "Route marker ready",
        tone = "cyan",
    }
    return self.current
end

function RouteMarkerLifecycle:_ActivePoint()
    local navigation = JLP:GetModule("Navigation")
    return navigation and navigation.GetActiveWaypoint and navigation:GetActiveWaypoint() or nil
end

function RouteMarkerLifecycle:_Matches(a, b)
    local navigation = JLP:GetModule("Navigation")
    return navigation and navigation.TargetMatches and navigation:TargetMatches(a, b) or false
end

function RouteMarkerLifecycle:_Retire(reason)
    local session = self.current
    if not session then return false, "no-session" end
    local navigation = JLP:GetModule("Navigation")
    local retirement = "no-owned-marker"

    if session.markerOwned and navigation then
        local capabilities = navigation.GetCapabilities and navigation:GetCapabilities() or {}
        if not capabilities.canReadWaypoint then
            -- Without a readable active waypoint JuztLevel cannot prove that the
            -- marker is still its own. Do not clear anything in this state.
            retirement = "cannot-verify-owned-waypoint"
        else
            local active = self:_ActivePoint()
            if active and self:_Matches(active, session.target) then
                if session.replacedUserWaypoint and session.previousUserWaypoint and navigation.SetWaypointPoint then
                    local restored = navigation:SetWaypointPoint(session.previousUserWaypoint, { notify=false })
                    if restored then
                        retirement = "restored-user-waypoint"
                        session.restoredUserWaypoint = true
                    else
                        retirement = "restore-failed"
                    end
                elseif navigation.ClearWaypointIfMatches then
                    local cleared, clearReason = navigation:ClearWaypointIfMatches(session.target)
                    if cleared then
                        retirement = "cleared-owned-waypoint"
                        session.clearedOwnedWaypoint = true
                    else
                        retirement = tostring(clearReason or "clear-failed")
                    end
                end
            elseif active then
                -- The player changed the waypoint. Ownership is relinquished and the
                -- active user waypoint must never be cleared/restored automatically.
                retirement = "ownership-lost-user-waypoint-active"
                session.ownershipLost = true
            else
                retirement = "owned-waypoint-not-active"
            end
        end
    end

    session.markerOwned = false
    session.retiredAt = now()
    session.retireReason = tostring(reason or "retired")
    session.retirement = retirement
    session.state = reason == "source-verified" and "RETIRED_VERIFIED" or "RETIRED"
    session.label = retirement == "restored-user-waypoint" and "Previous waypoint restored"
        or retirement == "cleared-owned-waypoint" and "Route marker retired"
        or retirement == "ownership-lost-user-waypoint-active" and "Player waypoint preserved"
        or retirement == "cannot-verify-owned-waypoint" and "Route marker left unchanged · ownership cannot be verified"
        or retirement == "clear-waypoint-api-unavailable" and "Route marker left active · clear API unavailable"
        or retirement == "restore-failed" and "Route marker handoff incomplete · restore failed"
        or "Route marker retired"
    session.tone = (retirement == "ownership-lost-user-waypoint-active" or retirement == "cannot-verify-owned-waypoint" or retirement == "clear-waypoint-api-unavailable" or retirement == "restore-failed") and "warn" or "muted"
    boundedAppend(self.history, archivedCopy(session, reason), 30)
    return true, retirement
end

function RouteMarkerLifecycle:Observe(reason, status)
    local destination = self:_Destination(status)
    local current = self.current
    local changed = false

    if not destination then
        if current and current.routeBound and current.state ~= "RETIRED" and current.state ~= "RETIRED_VERIFIED" then
            self:_Retire("route-complete")
            changed = true
        end
        if changed then self:_Emit(reason or "route-complete") end
        return changed, self:GetStatus()
    end

    if not current or current.destinationKey ~= destination.key then
        if current and current.routeBound and current.state ~= "RETIRED" and current.state ~= "RETIRED_VERIFIED" then
            self:_Retire("destination-changed")
        end
        self:_Begin(destination, reason or "destination-changed")
        current = self.current
        changed = true
    else
        current.source = destination.source
        current.sourceName = destination.sourceName
        current.workspaceKey = destination.workspaceKey
        current.lastReason = tostring(reason or "observe")
    end

    local stage = tostring(destination.stage or "")
    if current and (stage == "ARRIVED_SOURCE" or stage == "ACTION_READY")
        and current.markerOwned and current.state ~= "RETIRED_VERIFIED" then
        self:_Retire("source-verified")
        current.verifiedAt = now()
        changed = true
    end

    if changed then self:_Emit(reason or "observe") end
    return changed, self:GetStatus()
end

-- Called by Navigation only after an explicit user-triggered ShowSource action.
-- routeBound=true means the marker belongs to the current Travel Session and may
-- be retired later. Non-route map actions are intentionally left unmanaged.
function RouteMarkerLifecycle:RecordNavigation(source, target, details)
    details = details or {}
    if not details.routeBound then return false end
    local destination = self:_Destination(details.travelStatus)
    if not destination or not self:_Matches(destination.target, target) then return false end

    if not self.current or self.current.destinationKey ~= destination.key then
        self:Observe("navigation-bind", details.travelStatus)
    end
    local session = self.current
    if not session then return false end

    session.lastNavigationAt = now()
    session.mapOpened = details.mapOpened and true or false
    session.userWaypointPreserved = details.preservedUserWaypoint and true or false
    session.userWaypointMatching = details.activeMatching and true or false

    if details.waypointSet then
        session.markerOwned = true
        session.markerSetAt = now()
        session.replacedUserWaypoint = details.replacedExisting and true or false
        session.previousUserWaypoint = details.replacedExisting and clonePoint(details.previousWaypoint) or nil
        session.state = "OWN_ACTIVE"
        session.label = session.replacedUserWaypoint and "Route marker active · previous waypoint saved" or "Route marker active"
        session.tone = "good"
    elseif details.preservedUserWaypoint then
        session.markerOwned = false
        session.state = "USER_WAYPOINT_PRESERVED"
        session.label = "Player waypoint preserved"
        session.tone = "warn"
    elseif details.activeMatching then
        session.markerOwned = false
        session.state = "USER_MATCHING_TARGET"
        session.label = "Matching player waypoint already active"
        session.tone = "good"
    elseif details.mapOpened then
        session.state = "MAP_ONLY"
        session.label = "Map opened · route marker not owned"
        session.tone = "cyan"
    end
    self:_Emit("navigation-user-action")
    return true
end


function RouteMarkerLifecycle:GetCheckpoint()
    local session = self.current
    if not session then return { state="IDLE", markerOwned=false } end
    return {
        state = session.state,
        destinationKey = session.destinationKey,
        sourceName = session.sourceName,
        workspaceKey = session.workspaceKey,
        target = clonePoint(session.target),
        markerOwned = session.markerOwned and true or false,
        replacedUserWaypoint = session.replacedUserWaypoint and true or false,
        previousUserWaypoint = clonePoint(session.previousUserWaypoint),
        userWaypointPreserved = session.userWaypointPreserved and true or false,
        markerSetAt = session.markerSetAt,
    }
end

-- Recover ownership only when three independent facts agree after /reload:
-- the saved checkpoint says JuztLevel owned the marker, the rebuilt live route
-- has the same destination, and the client can read an active waypoint that
-- still matches that exact target.  SavedVariables alone are never sufficient.
function RouteMarkerLifecycle:RestoreCheckpoint(checkpoint)
    if type(checkpoint) ~= "table" or checkpoint.markerOwned ~= true then return false, "checkpoint-not-owned" end
    local session = self.current
    if not session or not session.destinationKey then return false, "no-live-destination" end
    if tostring(session.destinationKey) ~= tostring(checkpoint.destinationKey or "") then return false, "destination-mismatch" end
    local savedTarget = clonePoint(checkpoint.target)
    if not savedTarget or not self:_Matches(savedTarget, session.target) then return false, "target-mismatch" end
    local navigation = JLP:GetModule("Navigation")
    local capabilities = navigation and navigation.GetCapabilities and navigation:GetCapabilities() or {}
    if not capabilities.canReadWaypoint then return false, "waypoint-readback-unavailable" end
    local active = self:_ActivePoint()
    if not active then return false, "saved-route-marker-not-active" end
    if not self:_Matches(active, savedTarget) then return false, "active-waypoint-mismatch" end

    session.markerOwned = true
    session.recoveredOwnership = true
    session.recoveredAt = now()
    session.recoveryEvidence = "checkpoint-owned-target+active-waypoint-match"
    session.replacedUserWaypoint = checkpoint.replacedUserWaypoint and true or false
    session.previousUserWaypoint = session.replacedUserWaypoint and clonePoint(checkpoint.previousUserWaypoint) or nil
    session.state = "OWN_ACTIVE_RECOVERED"
    session.label = session.replacedUserWaypoint and "Route marker recovered · previous waypoint preserved" or "Route marker ownership recovered"
    session.tone = "good"
    self:_Emit("checkpoint-recovery")
    return true, session.recoveryEvidence
end

function RouteMarkerLifecycle:GetStatus()
    local session = self.current
    if not session then
        return {
            contract = self.contract,
            state = "IDLE",
            label = "No route marker session",
            tone = "muted",
            revision = self.revision,
            historyCount = #self.history,
        }
    end

    local active = self:_ActivePoint()
    local state, label, tone = session.state, session.label, session.tone
    if session.markerOwned and state ~= "RETIRED" and state ~= "RETIRED_VERIFIED" then
        if active and self:_Matches(active, session.target) then
            if session.recoveredOwnership then
                state, label, tone = "OWN_ACTIVE_RECOVERED", session.label or "Route marker ownership recovered", "good"
            else
                state, label, tone = "OWN_ACTIVE", "Route marker active", "good"
            end
        elseif active then
            state, label, tone = "OWNERSHIP_LOST", "Player waypoint replaced the route marker", "warn"
        else
            state, label, tone = "OWN_MISSING", "Route marker no longer active", "warn"
        end
    elseif not session.markerOwned and active and self:_Matches(active, session.target)
        and state ~= "RETIRED" and state ~= "RETIRED_VERIFIED" then
        state, label, tone = "USER_MATCHING_TARGET", "Matching player waypoint active", "good"
    end

    return {
        contract = self.contract,
        id = session.id,
        state = state or "READY",
        label = label or "Route marker ready",
        tone = tone or "cyan",
        destinationKey = session.destinationKey,
        sourceName = session.sourceName,
        target = session.target,
        markerOwned = session.markerOwned and true or false,
        routeBound = session.routeBound and true or false,
        replacedUserWaypoint = session.replacedUserWaypoint and true or false,
        userWaypointPreserved = session.userWaypointPreserved and true or false,
        recoveredOwnership = session.recoveredOwnership and true or false,
        recoveryEvidence = session.recoveryEvidence,
        ownershipLost = state == "OWNERSHIP_LOST" or session.ownershipLost and true or false,
        retirement = session.retirement,
        retireReason = session.retireReason,
        revision = self.revision,
        historyCount = #self.history,
    }
end

function RouteMarkerLifecycle:GetSummary()
    local status = self:GetStatus()
    local lines = {
        "Route marker: " .. tostring(status.label or status.state or "Unavailable"),
        "State: " .. tostring(status.state or "UNKNOWN"),
        "Owned by JuztLevel: " .. (status.markerOwned and "yes" or "no"),
    }
    if status.sourceName then lines[#lines + 1] = "Destination: " .. tostring(status.sourceName) end
    if status.retirement then lines[#lines + 1] = "Last retirement: " .. tostring(status.retirement) end
    if status.replacedUserWaypoint then lines[#lines + 1] = "Previous player waypoint saved: yes" end
    return table.concat(lines, "\n")
end

function RouteMarkerLifecycle:Initialize()
    if not self.initialized then
        self.initialized = true
        if JLP.EventBus then
            JLP.EventBus:On("TRAVEL_TRANSITION_UPDATED", function(_, _, status)
                RouteMarkerLifecycle:Observe("travel-transition", status)
            end)
        end
    end
    return self:Observe("player-login")
end

JLP:RegisterModule("RouteMarkerLifecycle", RouteMarkerLifecycle)
