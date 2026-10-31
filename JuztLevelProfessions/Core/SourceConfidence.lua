local _, JLP = ...

-- Conservative source confidence derived only from observable client state and
-- audited source metadata.  Normalized map proximity is guidance, never proof
-- of NPC identity or action completion; named sources are VERIFIED only when
-- the matching trainer/vendor/source workspace is actually open.
local SourceConfidence = {
    contract = "conservative-source-confidence-v1",
}

local SOURCE_SENSITIVE = { vendor=true, trainer=true, source=true }

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("[%p%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function actorName(context)
    return context and (context.actorName or context.merchantName or context.trainerName) or nil
end

local function proximitySettings()
    local travel = JLP.data and JLP.data.travel
    local settings = travel and travel.proximity or nil
    return {
        nearNormalized = tonumber(settings and settings.nearNormalized) or 0.025,
        evidence = tostring(settings and settings.evidence or "normalized-map-distance-guidance"),
    }
end

local function auditedCoordinate(destination)
    local source = destination and destination.source or nil
    local nav = source and source.nav or nil
    return type(nav) == "table"
        and tonumber(destination.mapID) ~= nil
        and tonumber(destination.x) ~= nil
        and tonumber(destination.y) ~= nil
        and nav.evidence ~= nil
end

local function sameZone(origin, destination)
    if not origin or not destination then return false, nil end
    local om, dm = tonumber(origin.mapID), tonumber(destination.mapID)
    if om and dm and om == dm then return true, "destination-map" end
    local oz, dz = normalize(origin.zone), normalize(destination.zone)
    if oz ~= "" and dz ~= "" and oz == dz then return true, "destination-zone" end
    return false, nil
end

function SourceConfidence:DistanceNormalized(origin, destination)
    if not origin or not destination then return nil end
    local om, dm = tonumber(origin.mapID), tonumber(destination.mapID)
    if not om or not dm or om ~= dm then return nil end
    local ox, oy = tonumber(origin.x), tonumber(origin.y)
    local dx, dy = tonumber(destination.x), tonumber(destination.y)
    if not ox or not oy or not dx or not dy then return nil end
    if ox < 0 or ox > 1 or oy < 0 or oy > 1 or dx < 0 or dx > 1 or dy < 0 or dy > 1 then return nil end
    local x, y = ox - dx, oy - dy
    return math.sqrt(x * x + y * y)
end

local function result(level, label, tone, evidence, rank)
    return {
        contract = SourceConfidence.contract,
        level = level,
        label = label,
        tone = tone,
        evidence = evidence,
        rank = rank,
        identityVerified = level == "VERIFIED_SOURCE",
    }
end

function SourceConfidence:Evaluate(batch, context, origin, destination)
    batch = batch or {}
    context = context or { station="world" }
    local station = batch.station
    local expected = normalize(batch.sourceName or (batch.source and batch.source.name))
    local observed = normalize(actorName(context))
    local sensitive = SOURCE_SENSITIVE[station] == true

    if context.station == station then
        if not sensitive then
            local out = result("WORKSPACE_READY", "Workspace open · verified", "good", "required-workspace-open", 100)
            out.workspaceMatched = true
            return out
        end
        if expected ~= "" and observed ~= "" and expected ~= observed then
            local out = result("WRONG_SOURCE", "Source mismatch", "bad", "source-name-mismatch", 0)
            out.workspaceMatched = false
            out.expectedSource = batch.sourceName
            out.observedSource = actorName(context)
            return out
        end
        if expected ~= "" and observed == expected then
            local out = result("VERIFIED_SOURCE", "Verified source · " .. tostring(batch.sourceName or "source"), "good", "verified-source-workspace-open", 100)
            out.workspaceMatched = true
            out.expectedSource = batch.sourceName
            out.observedSource = actorName(context)
            return out
        end
        local out = result("UNVERIFIED_WORKSPACE", "Workspace open · source identity unverified", "warn", "workspace-open-source-unresolved", 65)
        out.workspaceMatched = true
        out.expectedSource = batch.sourceName
        out.observedSource = actorName(context)
        return out
    end

    if destination then
        local inDestination, zoneEvidence = sameZone(origin, destination)
        if inDestination then
            local settings = proximitySettings()
            local distance = auditedCoordinate(destination) and self:DistanceNormalized(origin, destination) or nil
            if sensitive and distance and distance <= settings.nearNormalized then
                local out = result("NEAR_SOURCE", "Near audited coordinate · source not verified", "cyan", "audited-map-proximity-only", 45)
                out.distanceNormalized = distance
                out.distancePercent = distance * 100
                out.thresholdNormalized = settings.nearNormalized
                out.coordinateEvidence = destination.source and destination.source.nav and destination.source.nav.evidence or settings.evidence
                out.positionEvidence = origin and origin.positionEvidence or (origin and origin.x and origin.y and "provided-map-position" or nil)
                out.destinationEvidence = zoneEvidence
                out.nearSource = true
                return out
            end
            local out = result("DESTINATION_ZONE", "Destination zone only", "cyan", zoneEvidence or "destination-zone-match", 30)
            out.positionAvailable = origin and origin.x ~= nil and origin.y ~= nil or false
            out.coordinateAudited = auditedCoordinate(destination)
            return out
        end
        return result("TRAVEL_REQUIRED", "Travel evidence only", "muted", "outside-destination-zone", 10)
    end

    return result("UNKNOWN", "No source confidence available", "muted", "no-physical-source-evidence", 0)
end

function SourceConfidence:FormatCompact(confidence)
    confidence = confidence or {}
    local text = tostring(confidence.label or confidence.level or "Unknown")
    if tonumber(confidence.distancePercent) then
        text = text .. string.format(" · %.2f%% map distance", tonumber(confidence.distancePercent))
    end
    return text
end

function SourceConfidence:GetSummary()
    local transition = JLP:GetModule("TravelTransition")
    local status = transition and transition:GetStatus() or nil
    local confidence = status and status.sourceConfidence or nil
    if not confidence then return "Source confidence: unavailable" end
    local lines = {
        "Source confidence: " .. self:FormatCompact(confidence),
        "Level: " .. tostring(confidence.level or "UNKNOWN"),
        "Evidence: " .. tostring(confidence.evidence or "unavailable"),
    }
    if confidence.expectedSource then lines[#lines + 1] = "Expected source: " .. tostring(confidence.expectedSource) end
    if confidence.observedSource then lines[#lines + 1] = "Observed source: " .. tostring(confidence.observedSource) end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("SourceConfidence", SourceConfidence)
