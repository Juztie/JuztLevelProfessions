local _, JLP = ...
local TravelRouter = {}

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function mapMeta(mapID)
    local data = JLP.data and JLP.data.travel
    return data and data.mapMeta and data.mapMeta[tonumber(mapID)] or nil
end

local function zoneContinent(zone)
    local data = JLP.data and JLP.data.travel
    return data and data.zoneContinents and data.zoneContinents[tostring(zone or "")] or nil
end

local function weights()
    local data = JLP.data and JLP.data.travel
    return data and data.weights or {sameMap=0,sameContinent=10,crossContinent=30,unknown=20,dungeon=40}
end

function TravelRouter:GetSourceLocation(source)
    if type(source) ~= "table" then return nil end
    local nav = source.nav
    local mapID = type(nav) == "table" and tonumber(nav.mapID) or nil
    local meta = mapID and mapMeta(mapID) or nil
    local zone = source.zone or (meta and meta.zone) or nil
    local continent = (meta and meta.continent) or zoneContinent(zone)
    return {
        mapID = mapID,
        zone = zone,
        continent = continent,
        x = type(nav) == "table" and tonumber(nav.x) or nil,
        y = type(nav) == "table" and tonumber(nav.y) or nil,
        dungeon = source.dungeon and true or false,
        name = source.name or source.recipe or source.material or zone or "Profession source",
        source = source,
    }
end

function TravelRouter:GetPlayerMapPosition(mapID)
    mapID = tonumber(mapID)
    if not mapID or type(C_Map) ~= "table" or type(C_Map.GetPlayerMapPosition) ~= "function" then return nil, nil, nil end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not position then return nil, nil, nil end
    local okXY, x, y = pcall(function()
        local getXY = position.GetXY
        if type(getXY) == "function" then return getXY(position) end
        return position.x, position.y
    end)
    x, y = okXY and tonumber(x) or nil, okXY and tonumber(y) or nil
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil, nil, nil end
    return x, y, "C_Map.GetPlayerMapPosition"
end

function TravelRouter:GetPlayerOrigin()
    local mapID
    if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, value = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then mapID = tonumber(value) end
    end
    local zone
    if type(GetRealZoneText) == "function" then
        local ok, value = pcall(GetRealZoneText)
        if ok and value and value ~= "" then zone = tostring(value) end
    end
    local meta = mapID and mapMeta(mapID) or nil
    zone = zone or (meta and meta.zone) or nil
    local x, y, positionEvidence = self:GetPlayerMapPosition(mapID)
    local bind
    if type(GetBindLocation) == "function" then
        local ok, value = pcall(GetBindLocation)
        if ok and value and value ~= "" then bind = tostring(value) end
    end
    return {
        mapID = mapID,
        zone = zone,
        continent = (meta and meta.continent) or zoneContinent(zone),
        x = x,
        y = y,
        positionEvidence = positionEvidence,
        bind = bind,
        name = zone or "Current location",
        player = true,
    }
end

function TravelRouter:ProgressionBand(stop)
    local required = tonumber(stop and stop.requiredSkill) or 0
    if required >= 225 then return 3 end
    if required >= 150 then return 2 end
    if required >= 75 then return 1 end
    return 0
end

function TravelRouter:Cost(fromLocation, toLocation)
    if not toLocation then return weights().unknown end
    if toLocation.dungeon then return weights().dungeon end
    if not fromLocation then return weights().unknown end
    if fromLocation.mapID and toLocation.mapID and fromLocation.mapID == toLocation.mapID then
        local cost = weights().sameMap
        if fromLocation.x and fromLocation.y and toLocation.x and toLocation.y then
            local dx, dy = fromLocation.x - toLocation.x, fromLocation.y - toLocation.y
            cost = cost + math.sqrt(dx * dx + dy * dy)
        end
        return cost
    end
    if fromLocation.continent and toLocation.continent then
        if fromLocation.continent == toLocation.continent then return weights().sameContinent end
        return weights().crossContinent
    end
    return weights().unknown
end

function TravelRouter:BindMatches(location, origin)
    if not location or not origin or not origin.bind or not location.zone then return false end
    return lower(origin.bind) == lower(location.zone)
end

function TravelRouter:Transition(fromLocation, toLocation, playerOrigin)
    if not toLocation then
        return {kind="unknown", label="Travel information unavailable.", cost=weights().unknown}
    end
    local out = { cost=self:Cost(fromLocation, toLocation), destination=toLocation }
    if toLocation.dungeon then
        out.kind = "dungeon"
        out.label = "Dungeon source - use the normal dungeon entrance; no internal waypoint is assumed."
    elseif fromLocation and fromLocation.mapID and toLocation.mapID and fromLocation.mapID == toLocation.mapID then
        out.kind = "same-zone"
        out.label = "Same zone - continue with local travel."
    elseif fromLocation and fromLocation.continent and toLocation.continent and fromLocation.continent == toLocation.continent then
        out.kind = "same-continent"
        out.label = "Same continent - use an unlocked flight path when convenient, otherwise travel normally."
    elseif fromLocation and fromLocation.continent and toLocation.continent and fromLocation.continent ~= toLocation.continent then
        out.kind = "cross-continent"
        out.label = "Cross-continent transfer - consider Hearthstone or normal intercontinental transport."
    else
        out.kind = "unknown"
        out.label = "Travel route is not fully audited for this transition."
    end
    local origin = playerOrigin or self:GetPlayerOrigin()
    if self:BindMatches(toLocation, origin) then
        out.hearthRelevant = true
        out.label = out.label .. " Your Hearthstone bind matches the destination zone."
    end
    return out
end

function TravelRouter:ChooseCandidate(candidates, fromLocation)
    if not candidates or #candidates == 0 then return nil end
    local best, bestBand, bestCost, bestIndex
    for _, candidate in ipairs(candidates) do
        local stop = candidate.stop
        local band = self:ProgressionBand(stop)
        local location = stop and stop.travel or self:GetSourceLocation(stop and stop.sourceInfo)
        local cost = self:Cost(fromLocation, location)
        local originalIndex = tonumber(stop and stop.firstActionIndex) or 999999
        if not best or band < bestBand
            or (band == bestBand and cost < bestCost)
            or (band == bestBand and cost == bestCost and originalIndex < bestIndex) then
            best = candidate
            bestBand = band
            bestCost = cost
            bestIndex = originalIndex
        end
    end
    return best
end

function TravelRouter:FormatTransition(transition)
    if not transition then return "Travel: unavailable" end
    return "Travel: " .. tostring(transition.label or "unavailable")
end

JLP:RegisterModule("TravelRouter", TravelRouter)
