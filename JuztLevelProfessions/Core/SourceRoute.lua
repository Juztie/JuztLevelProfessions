local _, JLP = ...
local SourceRoute = { index = 1, signature = nil, route = nil }

local function sourceKey(source)
    if not source then return nil end
    local nav = source.nav or {}
    return table.concat({
        tostring(source.name or source.recipe or source.material or "unknown"),
        tostring(source.zone or ""),
        tostring(nav.mapID or ""),
        tostring(nav.x or ""),
        tostring(nav.y or ""),
    }, "|")
end

local function addUnique(list, seen, value)
    value = tostring(value or "")
    if value == "" or seen[value] then return end
    seen[value] = true
    list[#list + 1] = value
end

local function actionRequiredSkill(action)
    return tonumber(action and action.requiredSkill)
        or tonumber(action and action.skillCap)
        or tonumber(action and action.skillTarget)
        or 0
end

local function newStop(action, actionIndex, navigation, travel)
    local source = action.sourceInfo
    local location = travel and travel:GetSourceLocation(source) or nil
    return {
        key = sourceKey(source),
        sourceInfo = source,
        firstActionIndex = actionIndex,
        lastActionIndex = actionIndex,
        actions = {action},
        professions = {tostring(action.profession or "UNKNOWN")},
        professionSeen = {[tostring(action.profession or "UNKNOWN")]=true},
        requiredSkill = actionRequiredSkill(action),
        navigable = navigation and navigation:GetTarget(source) ~= nil or false,
        travel = location,
    }
end

local function canMergeConsecutive(stop, action, actionIndex)
    if not stop or stop.key ~= sourceKey(action and action.sourceInfo) then return false end
    if actionIndex ~= (tonumber(stop.lastActionIndex) or 0) + 1 then return false end
    return actionRequiredSkill(action) == (tonumber(stop.requiredSkill) or 0)
end

local function mergeAction(stop, action, actionIndex)
    stop.actions[#stop.actions + 1] = action
    stop.lastActionIndex = math.max(tonumber(stop.lastActionIndex) or actionIndex, actionIndex)
    stop.requiredSkill = math.max(tonumber(stop.requiredSkill) or 0, actionRequiredSkill(action))
    addUnique(stop.professions, stop.professionSeen, action.profession)
end

local function canMergeReadyStops(a, b)
    if not a or not b or a.key ~= b.key then return false end
    -- Cross-profession co-visits are only merged when both independent queues
    -- reach the same physical source at the same skill milestone. We do not
    -- speculate that a later trainer/BoP recipe can be consumed early.
    return (tonumber(a.requiredSkill) or 0) == (tonumber(b.requiredSkill) or 0)
end

function SourceRoute:PlanSignature(plan)
    local parts = { tostring(plan and plan.scope or "") }
    for index, action in ipairs((plan and plan.actions) or {}) do
        local key = sourceKey(action.sourceInfo)
        if key then
            parts[#parts + 1] = table.concat({
                tostring(index),
                tostring(action.profession or ""),
                tostring(action.kind or ""),
                tostring(actionRequiredSkill(action)),
                key,
            }, ":")
        end
    end
    return table.concat(parts, ";")
end

function SourceRoute:Build(plan)
    local navigation = JLP:GetModule("Navigation")
    local travel = JLP:GetModule("TravelRouter")
    local queues, queueOrder = {}, {}

    -- Preserve progression order inside each profession. Independent profession
    -- queues may later be interleaved by travel cost, but a Tailoring stop can
    -- never jump over an earlier Tailoring stop (same for Enchanting).
    for actionIndex, action in ipairs((plan and plan.actions) or {}) do
        if action.sourceInfo then
            local profession = tostring(action.profession or "OTHER")
            if not queues[profession] then
                queues[profession] = {}
                queueOrder[#queueOrder + 1] = profession
            end
            local queue = queues[profession]
            local previous = queue[#queue]
            if canMergeConsecutive(previous, action, actionIndex) then
                mergeAction(previous, action, actionIndex)
            else
                queue[#queue + 1] = newStop(action, actionIndex, navigation, travel)
            end
        end
    end

    local positions = {}
    for _, profession in ipairs(queueOrder) do positions[profession] = 1 end
    local origin = travel and travel:GetPlayerOrigin() or nil
    local currentLocation = origin
    local stops = {}
    local transitionCounts = { ["same-zone"]=0, ["same-continent"]=0, ["cross-continent"]=0, dungeon=0, unknown=0 }
    local visitGroup = 0
    local previousTransitionKind

    while true do
        local candidates = {}
        for _, profession in ipairs(queueOrder) do
            local queue = queues[profession]
            local pos = positions[profession] or 1
            local stop = queue and queue[pos]
            if stop then candidates[#candidates + 1] = {profession=profession, stop=stop} end
        end
        if #candidates == 0 then break end

        local chosen = travel and travel:ChooseCandidate(candidates, currentLocation) or candidates[1]
        if not chosen then chosen = candidates[1] end
        local stop = chosen.stop
        positions[chosen.profession] = (positions[chosen.profession] or 1) + 1

        -- If another profession has independently reached the same exact source
        -- at the same milestone, one visit can safely satisfy both queue heads.
        for _, profession in ipairs(queueOrder) do
            if profession ~= chosen.profession then
                local queue = queues[profession]
                local pos = positions[profession] or 1
                local other = queue and queue[pos]
                if canMergeReadyStops(stop, other) then
                    for _, action in ipairs(other.actions or {}) do
                        mergeAction(stop, action, other.lastActionIndex or other.firstActionIndex or 0)
                    end
                    positions[profession] = pos + 1
                end
            end
        end

        stop.professionSeen = nil
        stop.travel = stop.travel or (travel and travel:GetSourceLocation(stop.sourceInfo) or nil)
        stop.transition = travel and travel:Transition(currentLocation, stop.travel, origin) or nil
        local kind = stop.transition and stop.transition.kind or "unknown"
        transitionCounts[kind] = (transitionCounts[kind] or 0) + 1

        if #stops == 0 or kind ~= "same-zone" or previousTransitionKind ~= "same-zone" then
            visitGroup = visitGroup + 1
        end
        stop.visitGroup = visitGroup
        stops[#stops + 1] = stop
        previousTransitionKind = kind

        if stop.travel and not stop.travel.dungeon then currentLocation = stop.travel end
    end

    return {
        scope = plan and plan.scope or "current",
        stops = stops,
        count = #stops,
        origin = origin,
        transitionCounts = transitionCounts,
        visitGroups = visitGroup,
        travelAware = true,
        evidence = "progression-safe-travel-aware-source-route",
    }
end

local function firstPendingAtOrAfter(route, startIndex)
    if not route or not route.pendingIndices or #route.pendingIndices == 0 then return 0 end
    startIndex = math.max(1, tonumber(startIndex) or 1)
    for _, index in ipairs(route.pendingIndices) do
        if index >= startIndex then return index end
    end
    return route.pendingIndices[1] or 0
end

local function adjacentPending(route, currentIndex, direction)
    if not route or not route.pendingIndices or #route.pendingIndices == 0 then return 0 end
    currentIndex = tonumber(currentIndex) or 0
    if direction > 0 then
        for _, index in ipairs(route.pendingIndices) do
            if index > currentIndex then return index end
        end
        return route.pendingIndices[#route.pendingIndices]
    end
    for i = #route.pendingIndices, 1, -1 do
        local index = route.pendingIndices[i]
        if index < currentIndex then return index end
    end
    return route.pendingIndices[1]
end

function SourceRoute:Sync(plan, force)
    local planSignature = self:PlanSignature(plan)
    local rebuilt = force or planSignature ~= self.signature or not self.route
    if rebuilt then
        local route = self:Build(plan)
        self.route = route
        self.signature = planSignature
    end

    local route = self.route
    local progress = JLP:GetModule("RouteProgress")
    if progress then progress:AnnotateRoute(route, plan) end

    if not route or route.count == 0 or (route.pendingCount ~= nil and route.pendingCount == 0) then
        self.index = 0
    elseif rebuilt then
        self.index = firstPendingAtOrAfter(route, 1)
    elseif self.index < 1 or not route.stops[self.index] or route.stops[self.index].status ~= "pending" then
        self.index = firstPendingAtOrAfter(route, math.max(1, self.index))
    end
    return route
end

function SourceRoute:Reoptimize(plan)
    return self:Sync(plan, true)
end

function SourceRoute:GetCurrent(plan)
    local route = plan and self:Sync(plan) or self.route
    if not route or route.count == 0 or self.index < 1 then return nil, 0, route and route.count or 0 end
    return route.stops[self.index], self.index, route.count
end

function SourceRoute:Next(plan)
    local route = plan and self:Sync(plan) or self.route
    if not route or route.count == 0 or (route.pendingCount ~= nil and route.pendingCount == 0) then return nil, 0, route and route.count or 0 end
    self.index = adjacentPending(route, self.index, 1)
    return route.stops[self.index], self.index, route.count
end

function SourceRoute:Previous(plan)
    local route = plan and self:Sync(plan) or self.route
    if not route or route.count == 0 or (route.pendingCount ~= nil and route.pendingCount == 0) then return nil, 0, route and route.count or 0 end
    self.index = adjacentPending(route, self.index, -1)
    return route.stops[self.index], self.index, route.count
end

function SourceRoute:SkipCurrent(plan)
    local route = plan and self:Sync(plan) or self.route
    local stop = route and self.index > 0 and route.stops[self.index] or nil
    if not stop then return 0, "No pending source stop is selected." end
    local progress = JLP:GetModule("RouteProgress")
    if not progress then return 0, "Route progress module unavailable." end
    local skipped = progress:SkipStop(stop)
    self:Sync(plan, false)
    if skipped > 0 then
        return skipped, string.format("Skipped %d pending action%s at this source stop.", skipped, skipped == 1 and "" or "s")
    end
    return 0, "This source stop has no pending actions to skip."
end

function SourceRoute:ClearSkipped(plan)
    local progress = JLP:GetModule("RouteProgress")
    if not progress then return 0 end
    local cleared = progress:ClearSkipped(plan)
    self:Sync(plan, false)
    return cleared
end

function SourceRoute:GetTravelHint(plan)
    local stop = self:GetCurrent(plan)
    if not stop then return nil end
    local travel = JLP:GetModule("TravelRouter")
    return travel and travel:FormatTransition(stop.transition) or nil
end

function SourceRoute:Format(plan, limit)
    local route = self:Sync(plan)
    if not route or route.count == 0 then return "Source Route: no trainer/vendor stops in this scope." end
    limit = tonumber(limit) or 4
    local resolver = JLP:GetModule("SourceResolver")
    local counts = route.progressCounts or {pending=route.count, completed=0, skipped=0}
    local currentText = self.index > 0 and string.format("current %d/%d", self.index, route.count) or "route complete"
    local lines = { string.format("Source Route: %d stop%s - %d pending / %d done / %d skipped - %s - travel-aware", route.count, route.count == 1 and "" or "s", counts.pending or 0, counts.completed or 0, counts.skipped or 0, currentText) }
    local current = self.index > 0 and route.stops[self.index] or nil
    local travel = JLP:GetModule("TravelRouter")
    if current and travel then lines[#lines + 1] = travel:FormatTransition(current.transition) end
    local focusIndex = self.index > 0 and self.index or route.count
    local first = math.max(1, focusIndex - 1)
    local last = math.min(route.count, first + limit - 1)
    if last - first + 1 < limit then first = math.max(1, last - limit + 1) end
    local progress = JLP:GetModule("RouteProgress")
    for i = first, last do
        local stop = route.stops[i]
        local marker = i == self.index and ">" or " "
        local state = progress and progress:FormatStatus(stop) or tostring(stop.status or "pending")
        local label = resolver and resolver:Format(stop.sourceInfo, false) or tostring(stop.sourceInfo and stop.sourceInfo.name or "Source")
        local merged = #(stop.actions or {}) > 1 and string.format(" [%d actions]", #(stop.actions or {})) or ""
        local map = stop.navigable and " [map]" or ""
        local region = stop.travel and stop.travel.continent and (" [" .. tostring(stop.travel.continent) .. "]") or ""
        lines[#lines + 1] = string.format("%s %d. [%s] %s%s%s%s", marker, i, state, tostring(label), merged, map, region)
    end
    return table.concat(lines, "\n")
end

-- A manual map click may carry a frozen receipt from the *displayed* stop.
-- GetCurrent(plan) can Sync/AnnotateRoute, which may advance the pending index.
-- Compare the POST-Sync target against the frozen pre-click receipt before the
-- sole Navigation:ShowSource call. No navigation is allowed on a mismatch.
local function receiptMatches(route, plan, stop, index, count, expected)
    if type(expected) ~= "table" or type(stop) ~= "table" or
       stop ~= expected.stop or route.route ~= expected.route or
       route.signature ~= expected.signature or
       tonumber(index) ~= expected.index or tonumber(count) ~= expected.count or
       stop.navigable ~= true or stop.status ~= "pending" or
       stop.key ~= expected.stopKey or
       type(stop.sourceInfo) ~= "table" or stop.sourceInfo ~= expected.source then return false end
    if (plan and plan.scope) ~= expected.planScope or
       route:PlanSignature(plan) ~= route.signature then return false end
    local source = stop.sourceInfo
    local nav = source.nav
    if type(nav) ~= "table" or type(expected.nav) ~= "table" then return false end
    if source.name ~= expected.name or source.zone ~= expected.zone or
       source.recipe ~= expected.recipe or source.material ~= expected.material or
       sourceKey(source) ~= expected.stopKey or
       nav.mapID ~= expected.nav.mapID or nav.uiMapID ~= expected.nav.uiMapID or
       tonumber(nav.x) ~= expected.nav.x or tonumber(nav.y) ~= expected.nav.y then return false end
    return true
end

function SourceRoute:ShowCurrent(plan, expected)
    -- Backwards-compatible direct/manual slash flow retains its original
    -- behavior; the AH Map Stop UI ALWAYS supplies a frozen expected receipt.
    local stop, index, count = self:GetCurrent(plan)
    if expected ~= nil and not receiptMatches(self, plan, stop, index, count, expected) then
        return false, "Source stop changed while refreshing route; review the route and select Map Stop again."
    end
    if not stop then return false, "No trainer/vendor source stop is available in the selected plan." end
    local navigation = JLP:GetModule("Navigation")
    if not navigation or type(navigation.ShowSource) ~= "function" then
        return false, "Navigation module unavailable."
    end
    if expected ~= nil then
        if type(navigation.GetTarget) ~= "function" then return false, "Navigation target unavailable." end
        local target = navigation:GetTarget(stop.sourceInfo)
        if type(target) ~= "table" then return false, "Navigation target unavailable; verify the source manually." end
        local mapID = tonumber(target.mapID or target.uiMapID)
        local x, y = tonumber(target.x), tonumber(target.y)
        if not mapID or mapID ~= expected.targetMapID or
           not x or not y or x ~= expected.targetX or y ~= expected.targetY then
            return false, "Navigation target changed; refresh the source route."
        end
    end
    return navigation:ShowSource(stop.sourceInfo)
end

JLP:RegisterModule("SourceRoute", SourceRoute)
