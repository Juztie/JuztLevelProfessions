local _, JLP = ...

-- Local, audited navigation guidance layered on top of TravelTransition.
-- Coordinates/waypoints help the player find a source, but never count as
-- source identity or action-completion evidence.  ARRIVED_SOURCE still comes
-- exclusively from the matching source workspace in TravelTransition.
local NavigationGuidance = {
    contract = "route-marker-lifecycle-navigation-guidance-v2",
}

local function sourceFor(status)
    if not status then return nil end
    if status.batch and status.batch.source then return status.batch.source end
    if status.destination and status.destination.source then return status.destination.source end
    return nil
end

local function compactArea(source)
    source = source or {}
    local area = tostring(source.area or "")
    local zone = tostring(source.zone or "")
    if area ~= "" and zone ~= "" and area ~= zone then return area .. ", " .. zone end
    if area ~= "" then return area end
    if zone ~= "" then return zone end
    return nil
end

local function markerShort(marker)
    local state = marker and marker.state or "UNAVAILABLE"
    if state == "ACTIVE" then return "marker active" end
    if state == "SET_SESSION" then return "marker set" end
    if state == "OTHER_WAYPOINT" then return "other marker active" end
    if state == "AVAILABLE" then return "marker ready" end
    if state == "MAP_ONLY" then return "map only" end
    if state == "NO_TARGET" then return "no audited marker" end
    return "marker unavailable"
end

function NavigationGuidance:BuildFrom(status)
    status = status or {}
    if status.routeComplete or status.stage == "COMPLETE" then
        return {
            contract = self.contract,
            available = false,
            routeComplete = true,
            stage = status.stage or "COMPLETE",
            guideText = "Route complete",
            detail = "No local navigation guidance is required.",
            tone = "good",
            marker = { state="NOT_APPLICABLE", label="Route complete", tone="good" },
        }
    end

    local source = sourceFor(status)
    local navigation = JLP:GetModule("Navigation")
    local target = navigation and navigation.GetTarget and source and navigation:GetTarget(source) or nil
    local marker = navigation and navigation.GetMarkerStatus and source and navigation:GetMarkerStatus(source)
        or { state="NO_TARGET", label="No audited map target", tone="muted", navigable=false }
    local lifecycle = JLP:GetModule("RouteMarkerLifecycle")
    local routeMarker = lifecycle and lifecycle.GetStatus and lifecycle:GetStatus() or nil
    local sourceName = source and (source.name or source.recipe or source.material) or status.sourceName or status.target
    local area = compactArea(source)
    local coordinates = navigation and navigation.FormatCoordinates and source and navigation:FormatCoordinates(source) or nil
    local stage = tostring(status.stage or "PLANNED")

    local out = {
        contract = self.contract,
        available = target ~= nil,
        stage = stage,
        source = source,
        sourceName = sourceName,
        zone = source and source.zone or (target and target.zone) or (status.destination and status.destination.zone) or nil,
        area = source and source.area or nil,
        target = target,
        coordinates = coordinates,
        marker = marker,
        markerState = marker and marker.state or "UNAVAILABLE",
        markerLabel = marker and marker.label or "Marker unavailable",
        markerTone = marker and marker.tone or "muted",
        routeMarker = routeMarker,
        routeMarkerState = routeMarker and routeMarker.state or "IDLE",
        routeMarkerLabel = routeMarker and routeMarker.label or "No route marker session",
        routeMarkerTone = routeMarker and routeMarker.tone or "muted",
        evidence = target and (target.evidence or (source and source.evidence)) or "no-audited-map-target",
        navigationOnly = true,
        identityVerified = status.confidenceLevel == "VERIFIED_SOURCE",
    }

    if not target then
        out.guideText = "Workspace guidance only"
        out.detail = tostring(status.instruction or "Use the current workspace guidance; no audited local map coordinate is available.")
        out.tone = status.tone or "muted"
        return out
    end

    local localParts = {}
    if area then localParts[#localParts + 1] = area
    elseif out.zone then localParts[#localParts + 1] = tostring(out.zone) end
    if coordinates then localParts[#localParts + 1] = coordinates end
    localParts[#localParts + 1] = markerShort(marker)
    local localText = table.concat(localParts, " · ")

    if stage == "ARRIVED_SOURCE" or stage == "ACTION_READY" then
        out.guideText = "Verified · " .. tostring(sourceName or "source") .. (area and (" · " .. area) or "")
        out.detail = "Source identity is verified by the open workspace. Map guidance remains informational only."
        out.tone = "good"
    elseif stage == "ARRIVED_UNVERIFIED" then
        out.guideText = "Source unverified · " .. localText
        out.detail = "The workspace is open, but source identity is not verified. Use the audited local location as guidance only."
        out.tone = "warn"
    elseif stage == "WRONG_SOURCE" then
        out.guideText = "Expected " .. tostring(sourceName or "source") .. " · " .. localText
        out.detail = "The current source does not match the audited route source. Use the local map guidance to find the expected source."
        out.tone = "bad"
    elseif stage == "NEAR_SOURCE" then
        out.guideText = localText
        out.detail = "You are near the audited coordinate. Interact with the expected source to verify arrival."
        out.tone = "cyan"
    elseif stage == "DESTINATION_ZONE" then
        out.guideText = localText
        out.detail = "Destination zone reached. Continue locally using the audited area and coordinate; this does not verify source identity."
        out.tone = "cyan"
    elseif stage == "TRAVELING" or stage == "HANDOFF" or stage == "PLANNED" then
        local travelParts = {}
        if sourceName then travelParts[#travelParts + 1] = tostring(sourceName) end
        if out.zone then travelParts[#travelParts + 1] = tostring(out.zone) end
        if coordinates then travelParts[#travelParts + 1] = coordinates end
        travelParts[#travelParts + 1] = markerShort(marker)
        out.guideText = table.concat(travelParts, " · ")
        out.detail = area and ("Local destination: " .. area .. ".") or "Use the audited map target for local navigation."
        out.tone = "cyan"
    else
        out.guideText = localText
        out.detail = "Audited local map guidance is available for the current route source."
        out.tone = "cyan"
    end
    return out
end

function NavigationGuidance:Build()
    local transition = JLP:GetModule("TravelTransition")
    return self:BuildFrom(transition and transition:GetStatus() or nil)
end

function NavigationGuidance:ShowCurrent(status, options)
    status = status or (JLP:GetModule("TravelTransition") and JLP:GetModule("TravelTransition"):GetStatus() or nil)
    local guidance = self:BuildFrom(status)
    if not guidance.source then return false, "No audited local source is available for the current journey step." end
    local navigation = JLP:GetModule("Navigation")
    if not navigation then return false, "Navigation module unavailable." end
    options = options or {}
    options.routeBound = true
    options.travelStatus = status
    return navigation:ShowSource(guidance.source, options)
end

function NavigationGuidance:GetSummary()
    local guidance = self:Build()
    local lines = {
        "Local navigation: " .. tostring(guidance.guideText or "Unavailable"),
        "Stage: " .. tostring(guidance.stage or "UNKNOWN"),
        "Marker: " .. tostring(guidance.markerLabel or "Unavailable"),
        "Route marker: " .. tostring(guidance.routeMarkerLabel or "Unavailable"),
        "Evidence: " .. tostring(guidance.evidence or "unavailable"),
    }
    if guidance.sourceName then lines[#lines + 1] = "Source: " .. tostring(guidance.sourceName) end
    if guidance.area then lines[#lines + 1] = "Area: " .. tostring(guidance.area) end
    if guidance.zone then lines[#lines + 1] = "Zone: " .. tostring(guidance.zone) end
    if guidance.coordinates then lines[#lines + 1] = "Coordinates: " .. tostring(guidance.coordinates) end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("NavigationGuidance", NavigationGuidance)
