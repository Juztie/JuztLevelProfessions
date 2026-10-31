local _, JLP = ...
local Navigation = {}

local function numeric(value)
    value = tonumber(value)
    if type(value) ~= "number" or value ~= value or
        value == math.huge or value == -math.huge then return nil end
    return value
end
local function validMapID(value)
    return value and value >= 1 and value == math.floor(value)
end
-- A protected API call can complete successfully but return false. Nil is
-- permitted for Blizzard APIs that intentionally have no return value.
local function apiAccepted(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, ...)
    return ok and result ~= false
end

local function targetMatches(a, b)
    if not a or not b then return false end
    if tonumber(a.mapID or a.uiMapID) ~= tonumber(b.mapID or b.uiMapID) then return false end
    local ax, ay = tonumber(a.x), tonumber(a.y)
    local bx, by = tonumber(b.x), tonumber(b.y)
    if not ax or not ay or not bx or not by then return false end
    return math.abs(ax - bx) <= 0.0001 and math.abs(ay - by) <= 0.0001
end

local function pointCoordinates(point)
    if type(point) ~= "table" then return nil end
    local mapID = numeric(point.uiMapID or point.mapID)
    local x, y = numeric(point.x), numeric(point.y)
    local position = point.position
    if (not x or not y) and position then
        local getXY = position.GetXY
        if type(getXY) == "function" then
            local ok, px, py = pcall(getXY, position)
            if ok then x, y = numeric(px), numeric(py) end
        else
            x, y = numeric(position.x), numeric(position.y)
        end
    end
    if not validMapID(mapID) or not x or not y or x<0 or x>1 or y<0 or y>1 then return nil end
    return { mapID=mapID, uiMapID=mapID, x=x, y=y }
end

local function mapPoint(target)
    if not target or not UiMapPoint or type(UiMapPoint.CreateFromCoordinates) ~= "function" then return nil end
    local ok, point = pcall(UiMapPoint.CreateFromCoordinates, tonumber(target.mapID or target.uiMapID), tonumber(target.x), tonumber(target.y))
    if ok then return point end
    return nil
end

function Navigation:TargetMatches(a, b)
    return targetMatches(a, b)
end

function Navigation:GetTarget(source)
    local nav = source and source.nav
    if type(nav) ~= "table" then return nil end
    local mapID = numeric(nav.mapID)
    local x, y = numeric(nav.x), numeric(nav.y)
    if not validMapID(mapID) or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return {
        mapID = mapID,
        x = x,
        y = y,
        name = source.name or source.recipe or source.material or source.zone or "Profession source",
        zone = source.zone,
        area = source.area,
        evidence = nav.evidence or source.evidence,
        source = source,
    }
end

function Navigation:GetCapabilities()
    local canWaypoint = type(C_Map) == "table" and type(C_Map.SetUserWaypoint) == "function"
        and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function"
    local canReadWaypoint = type(C_Map) == "table" and type(C_Map.GetUserWaypoint) == "function"
    local canClearWaypoint = type(C_Map) == "table" and type(C_Map.ClearUserWaypoint) == "function"
    local canOpenMap = type(C_Map) == "table" and type(C_Map.OpenWorldMap) == "function"
        or (WorldMapFrame and type(WorldMapFrame.SetMapID) == "function")
    return {
        canWaypoint=canWaypoint and true or false,
        canReadWaypoint=canReadWaypoint and true or false,
        canClearWaypoint=canClearWaypoint and true or false,
        canOpenMap=canOpenMap and true or false,
    }
end

function Navigation:GetActiveWaypoint()
    local capabilities = self:GetCapabilities()
    if not capabilities.canReadWaypoint then return nil end
    local ok, value = pcall(C_Map.GetUserWaypoint)
    if not ok or not value then return nil end
    return pointCoordinates(value)
end

function Navigation:SetWaypointPoint(target, options)
    options = options or {}
    local capabilities = self:GetCapabilities()
    if not capabilities.canWaypoint then return false end
    local point = mapPoint(target)
    if not point then return false end
    if not apiAccepted(C_Map.SetUserWaypoint, point) then return false end
    if options.superTrack ~= false and type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

function Navigation:ClearWaypointIfMatches(target)
    local capabilities = self:GetCapabilities()
    if not capabilities.canReadWaypoint then return false, "cannot-read-active-waypoint" end
    local active = self:GetActiveWaypoint()
    if not active then return false, "no-active-waypoint" end
    if not targetMatches(active, target) then return false, "active-waypoint-does-not-match" end
    if not capabilities.canClearWaypoint then return false, "clear-waypoint-api-unavailable" end
    if not apiAccepted(C_Map.ClearUserWaypoint) then return false, "clear-waypoint-failed" end
    if self.lastTarget and targetMatches(self.lastTarget, target) then self.lastWaypointSet = false end
    if type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
    end
    return true, "cleared"
end

function Navigation:CanNavigate(source, options)
    local target = self:GetTarget(source)
    if not target then return false, "NO_MAP_COORDINATES" end
    local common=JLP:GetModule("UnifiedDestinationNavigation")
    local actions=JLP:GetModule("IntegratedNavigationActions")
    if not common or type(common.CanNavigate)~="function" then
        return false,"COMMON_NAVIGATION_UNAVAILABLE" end
    options=type(options)=="table" and options or {}
    local category=options.category or
      (actions and actions.CategoryForSource and actions:CategoryForSource(source)) or "RECIPE_SOURCE"
    local context=options.context or {explicit=true}
    local allowed,reason=common:CanNavigate(category,source,context)
    if not allowed then return false,reason end
    local capabilities=self:GetCapabilities()
    if capabilities.canWaypoint or capabilities.canOpenMap then return true,"MAP_API_AVAILABLE" end
    return false,"MAP_API_UNAVAILABLE"
end

function Navigation:FormatCoordinates(source)
    local target = self:GetTarget(source)
    if not target then return nil end
    return string.format("%.1f, %.1f", target.x * 100, target.y * 100)
end

function Navigation:GetMarkerStatus(source)
    local target = self:GetTarget(source)
    if not target then
        return { state="NO_TARGET", label="No audited map target", tone="muted", navigable=false }
    end
    local capabilities = self:GetCapabilities()
    local activePoint = self:GetActiveWaypoint()
    if activePoint then
        if targetMatches(target, activePoint) then
            return { state="ACTIVE", label="Waypoint active", tone="good", navigable=true, verified=true, target=target }
        end
        return { state="OTHER_WAYPOINT", label="Another waypoint is active", tone="warn", navigable=true, verified=true, target=target, activePoint=activePoint }
    end
    if self.lastWaypointSet and targetMatches(self.lastTarget, target) then
        return { state="SET_SESSION", label="Waypoint set this session", tone="good", navigable=true, verified=false, target=target }
    end
    if capabilities.canWaypoint then
        return { state="AVAILABLE", label="Waypoint available", tone="cyan", navigable=true, verified=false, target=target }
    end
    if capabilities.canOpenMap then
        return { state="MAP_ONLY", label="Map-only guidance available", tone="cyan", navigable=true, verified=false, target=target }
    end
    return { state="UNAVAILABLE", label="Map marker unavailable on this client", tone="muted", navigable=false, verified=false, target=target }
end

function Navigation:FormatTarget(source)
    local target = self:GetTarget(source)
    if not target then return nil end
    local place = target.zone or "Map"
    return string.format("%s - %s %.1f, %.1f", tostring(target.name), tostring(place), target.x * 100, target.y * 100)
end

function Navigation:_OpenMap(target)
    if not target then return false end
    if type(C_Map) == "table" and
        apiAccepted(C_Map.OpenWorldMap, target.mapID) then return true end
    if WorldMapFrame and type(WorldMapFrame.SetMapID) == "function" then
        if apiAccepted(WorldMapFrame.SetMapID, WorldMapFrame, target.mapID) then
            if type(WorldMapFrame.Show) ~= "function" or
                apiAccepted(WorldMapFrame.Show, WorldMapFrame) then return true end
        end
    end
    return false
end

-- Explicit user action only. By default an existing different user waypoint is
-- preserved and only the map is opened. Callers may pass replaceExisting=true
-- (for example /jlp localmap replace) to replace it deliberately; the marker
-- lifecycle then saves/restores the prior waypoint when the route destination
-- changes or the source is verified.
function Navigation:ShowSource(source, options)
    -- All explicit map requests share one source qualification, destination
    -- owner and user-waypoint preservation policy. Fail closed if unavailable.
    local service=JLP:GetModule("UnifiedDestinationNavigation")
    if not service or type(service.ShowSource)~="function" then
        return false,"COMMON_NAVIGATION_UNAVAILABLE" end
    return service:ShowSource(source,options)
end

JLP:RegisterModule("Navigation", Navigation)
