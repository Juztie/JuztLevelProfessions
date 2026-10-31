local _, JLP = ...
local ExecutionFlow = {
    merchantOpen = false,
    merchantName = nil,
    trainerOpen = false,
    trainerName = nil,
    professionOpenKey = nil,
}

local STATION_ORDER = {
    bank = 10,
    vendor = 20,
    auction = 30,
    trainer = 40,
    source = 45,
    acquisition = 46,
    world = 90,
    unknown = 99,
}

local RETRIEVE_KINDS = {
    ["retrieve-material"] = true,
    ["retrieve-raw"] = true,
    ["retrieve-tool"] = true,
    ["retrieve-tool-material"] = true,
}

local ACQUIRE_KINDS = {
    ["acquire-material"] = true,
    ["acquire-raw"] = true,
    ["acquire-tool-material"] = true,
}

local CRAFT_KINDS = {
    ["craft-tool"] = true,
    ["craft-intermediate"] = true,
    ["craft-leveling"] = true,
    ["verify-recipe"] = true,
}

local function registry() return JLP:GetModule("ProfessionRegistry") end

local function professionLabel(key)
    local reg = registry()
    local label = reg and reg:GetDisplayName(key) or nil
    if label then return label end
    key = tostring(key or ""):upper()
    return key ~= "" and key:gsub("_", " "):gsub("(%a)([%w']*)", function(a,b) return string.upper(a)..string.lower(b) end) or "Profession"
end

local function stationOrder(station)
    local fixed = STATION_ORDER[station]
    if fixed then return fixed end
    local craftKey = tostring(station or ""):match("^craft:(.+)$")
    if craftKey then
        local reg = registry()
        return 50 + (reg and reg:GetOrder(craftKey) or 999)
    end
    return 90
end

local function stationLabel(station)
    if station == "bank" then return "Bank" end
    if station == "vendor" then return "Vendor" end
    if station == "auction" then return "Auction House" end
    if station == "trainer" then return "Trainer" end
    if station == "source" then return "Recipe Source" end
    if station == "acquisition" then return "Material Source" end
    local craftKey = tostring(station or ""):match("^craft:(.+)$")
    if craftKey then return professionLabel(craftKey) end
    if station == "world" then return "World" end
    return "Other"
end

local function safeNpcName()
    if type(UnitName) ~= "function" then return nil end
    local ok, name = pcall(UnitName, "npc")
    if ok and name and name ~= "" then return tostring(name) end
    return nil
end

function ExecutionFlow:SetMerchantOpen(open)
    self.merchantOpen = open and true or false
    self.merchantName = self.merchantOpen and safeNpcName() or nil
end

function ExecutionFlow:SetTrainerOpen(open)
    self.trainerOpen = open and true or false
    self.trainerName = self.trainerOpen and safeNpcName() or nil
end

function ExecutionFlow:SetProfessionOpen(key)
    if key ~= nil then
        key = tostring(key):upper()
        local reg = registry()
        local routeAuthority = JLP:GetModule("ResearchRouteAuthorityBridge")
        local supportedResearch = routeAuthority and routeAuthority.IsSupported and routeAuthority:IsSupported(key) or false
        if not (reg and reg:IsKnown(key)) and not supportedResearch then key = nil end
    end
    self.professionOpenKey = key
end

function ExecutionFlow:CaptureProfessionWindow()
    local api=JLP:GetModule("ProfessionAPI")
    if api and type(api.GetOpenProfessionContext)=="function" then
        local ok,ctx=pcall(api.GetOpenProfessionContext,api)
        if ok and type(ctx)=="table" and ctx.verified==true and ctx.professionKey then
            self.professionOpenKey=ctx.professionKey
            return ctx.professionKey
        end
        -- No verified live window. Preserve UI station history for display,
        -- but never report it as a currently captured native profession.
        return nil
    end
    return nil -- Never infer a verified live panel from an unverified legacy API.
end

function ExecutionFlow:GetCurrentStation()
    local inventory = JLP:GetModule("Inventory")
    if inventory and inventory:IsBankOpen() then return "bank" end
    local scanner = JLP:GetModule("AuctionScanner")
    if scanner and scanner.isAuctionHouseOpen then return "auction" end
    if self.merchantOpen then return "vendor" end
    if self.trainerOpen then return "trainer" end
    if self.professionOpenKey then return "craft:" .. self.professionOpenKey end
    return "world"
end

function ExecutionFlow:GetCurrentContext()
    local station = self:GetCurrentStation()
    return {
        station = station,
        label = stationLabel(station),
        merchantName = station == "vendor" and self.merchantName or nil,
        trainerName = station == "trainer" and self.trainerName or nil,
        actorName = station == "vendor" and self.merchantName or station == "trainer" and self.trainerName or nil,
        profession = station:match("^craft:(.+)$"),
    }
end

function ExecutionFlow:StationForAction(key, action)
    action = action or {}
    local kind = tostring(action.kind or "")
    if RETRIEVE_KINDS[kind] then return "bank" end
    if ACQUIRE_KINDS[kind] then
        local source = tostring(action.source or "unknown")
        if source == "vendor" then return "vendor" end
        if source == "auction" or source == "disenchant-or-auction" then return "auction" end
        return "acquisition"
    end
    if CRAFT_KINDS[kind] then return "craft:" .. tostring(key or "UNKNOWN") end
    if kind == "learn-recipe" then
        local sourceKind = action.sourceInfo and tostring(action.sourceInfo.kind or "") or ""
        if sourceKind:match("^vendor") then return "vendor" end
        if sourceKind == "trainer" then return "trainer" end
        return "source"
    end
    if kind == "train-rank" or kind == "learn-profession" then return "trainer" end
    if kind == "planner" or kind == "route" then return "unknown" end
    return "unknown"
end

function ExecutionFlow:GetStationLabel(station)
    return stationLabel(station)
end

local function buildQueue(key)
    local module = JLP:GetModule("ActionQueue")
    return module and module:Build(key) or { key=key, status="unavailable", currentIndex=0, actions={} }
end

local function queueKeys(requestedKey)
    local reg = registry()
    if requestedKey ~= nil then
        local normalized = reg and reg:NormalizeKey(requestedKey) or tostring(requestedKey):upper()
        if not normalized or not (reg and reg:IsKnown(normalized)) then return {}, "unsupported-profession", normalized end
        if not reg:IsWorkflowEnabled(normalized) or not reg:HasCapability(normalized, "executionFlow") then
            return { normalized }, "not-production-enabled", normalized
        end
        return { normalized }, nil, normalized
    end
    local keys = reg and reg:GetWorkflowKeys("executionFlow") or {}
    return keys, nil, nil
end

local function actionAt(queues, pointers, key)
    local queue = queues[key]
    local index = pointers[key] or 1
    return queue and queue.actions and queue.actions[index] or nil
end

local function addBatchAction(batches, station, key, action)
    local batch = batches[#batches]
    if not batch or batch.station ~= station then
        batch = { station=station, label=stationLabel(station), actions={} }
        batches[#batches + 1] = batch
    end
    batch.actions[#batch.actions + 1] = {
        profession = key,
        professionLabel = professionLabel(key),
        action = action,
        text = action and action.text or "Continue.",
        kind = action and action.kind or "unknown",
    }
end

local function countImmediateStation(flow, queues, pointers, keys, station)
    local count = 0
    for _, key in ipairs(keys) do
        local action = actionAt(queues, pointers, key)
        if action and flow:StationForAction(key, action) == station then count = count + 1 end
    end
    return count
end

local function lookaheadSameStation(flow, queue, index, key, station)
    local count = 0
    for i = index, math.min(#(queue.actions or {}), index + 3) do
        local action = queue.actions[i]
        if flow:StationForAction(key, action) ~= station then break end
        count = count + 1
    end
    return count
end

function ExecutionFlow:_ChooseHead(queues, pointers, keys, preferredStation)
    local bestKey, bestAction, bestStation, bestScore
    for _, key in ipairs(keys) do
        local action = actionAt(queues, pointers, key)
        if action then
            local station = self:StationForAction(key, action)
            local score = stationOrder(station)
            if station == preferredStation then score = score - 1000 end
            score = score - (countImmediateStation(self, queues, pointers, keys, station) * 30)
            score = score - (lookaheadSameStation(self, queues[key], pointers[key] or 1, key, station) * 5)
            if not bestScore or score < bestScore or (score == bestScore and tostring(key) < tostring(bestKey)) then
                bestKey, bestAction, bestStation, bestScore = key, action, station, score
            end
        end
    end
    return bestKey, bestAction, bestStation
end

function ExecutionFlow:_AvailableHere(queues, keys, station)
    if station == "world" or station == "unknown" then return {} end
    local pointers, out = {}, {}
    for _, key in ipairs(keys) do pointers[key] = 1 end
    local advanced = true
    while advanced do
        advanced = false
        for _, key in ipairs(keys) do
            local action = actionAt(queues, pointers, key)
            if action and self:StationForAction(key, action) == station then
                out[#out + 1] = {
                    profession = key,
                    professionLabel = professionLabel(key),
                    action = action,
                    text = action.text,
                }
                pointers[key] = (pointers[key] or 1) + 1
                advanced = true
            end
        end
    end
    return out
end

function ExecutionFlow:Build(requestedKey, preparedQueue, preparedContext)
    local keys, keyState, normalizedRequestedKey = queueKeys(requestedKey)
    local queues, pointers = {}, {}
    local context = preparedContext or self:GetCurrentContext()
    if keyState then
        return {
            requestedKey = requestedKey, normalizedRequestedKey = normalizedRequestedKey, keys = keys, queues = {}, batches = {},
            currentContext = context, availableHere = {}, availableHereCount = 0, actionCount = 0, switchCount = 0,
            status = keyState, terminalReason = string.upper(keyState:gsub("%-", "_")), routeComplete = false,
            registryContract = registry() and registry().contract or nil, contract = "source-aware-workspace-batching-v2",
        }
    end
    local totalActions = 0
    for _, key in ipairs(keys) do
        queues[key] = (preparedQueue and #keys == 1 and key == (normalizedRequestedKey or requestedKey)) and preparedQueue or buildQueue(key)
        pointers[key] = 1
        totalActions = totalActions + #(queues[key].actions or {})
    end

    local batches = {}
    local preferred = context.station
    local safety = 0
    while safety < (totalActions + 8) do
        safety = safety + 1
        local key, action, station = self:_ChooseHead(queues, pointers, keys, preferred)
        if not key or not action then break end
        addBatchAction(batches, station, key, action)
        pointers[key] = (pointers[key] or 1) + 1
        preferred = station
    end

    local availableHere = self:_AvailableHere(queues, keys, context.station)
    local nextBatch = batches[1]
    local nextStation = nextBatch and nextBatch.station or nil
    return {
        requestedKey = requestedKey,
        keys = keys,
        queues = queues,
        batches = batches,
        currentContext = context,
        availableHere = availableHere,
        availableHereCount = #availableHere,
        nextStation = nextStation,
        nextStationLabel = nextStation and stationLabel(nextStation) or nil,
        actionCount = totalActions,
        switchCount = math.max(0, #batches - 1),
        status = totalActions > 0 and "active" or "complete",
        terminalReason = totalActions > 0 and nil or "ROUTE_COMPLETE",
        routeComplete = totalActions == 0,
        registryContract = registry() and registry().contract or nil,
        contract = "source-aware-workspace-batching-v2",
    }
end

function ExecutionFlow:FormatCompact(flow)
    flow = flow or self:Build()
    if not flow then return "Execution flow: unavailable" end
    if flow.status == "complete" then return "Execution flow: complete" end
    if flow.status == "not-production-enabled" then return "Execution flow: " .. professionLabel(flow.normalizedRequestedKey) .. " is not production-enabled" end
    if flow.status == "unsupported-profession" then return "Execution flow: unsupported profession" end
    local context = flow.currentContext or { label="World", station="world" }
    if (flow.availableHereCount or 0) > 0 then
        return string.format("Execution flow: %s - %d action%s available here now", tostring(context.label), flow.availableHereCount, flow.availableHereCount == 1 and "" or "s")
    end
    return string.format("Execution flow: next workspace %s - %d switch%s planned", tostring(flow.nextStationLabel or "Other"), tonumber(flow.switchCount) or 0, (flow.switchCount or 0) == 1 and "" or "es")
end

function ExecutionFlow:Format(flow, maxBatches, maxActionsPerBatch)
    flow = flow or self:Build()
    if not flow then return "EXECUTION FLOW\nUnavailable." end
    if flow.status == "complete" then return "EXECUTION FLOW\nNo pending profession actions." end
    if flow.status == "not-production-enabled" then return "EXECUTION FLOW\n" .. professionLabel(flow.normalizedRequestedKey) .. " is known but not production-enabled." end
    if flow.status == "unsupported-profession" then return "EXECUTION FLOW\nUnsupported profession request." end
    maxBatches = math.max(1, math.floor(tonumber(maxBatches) or 4))
    maxActionsPerBatch = math.max(1, math.floor(tonumber(maxActionsPerBatch) or 3))

    local context = flow.currentContext or { label="World", station="world" }
    local lines = {
        "EXECUTION FLOW",
        "Current context: " .. tostring(context.label or "World"),
    }
    if (flow.availableHereCount or 0) > 0 then
        lines[#lines + 1] = string.format("Available here now: %d action%s", flow.availableHereCount, flow.availableHereCount == 1 and "" or "s")
    else
        lines[#lines + 1] = "Next workspace: " .. tostring(flow.nextStationLabel or "Other")
    end

    for batchIndex, batch in ipairs(flow.batches or {}) do
        if batchIndex > maxBatches then
            lines[#lines + 1] = string.format("+ %d more workspace batch%s", #flow.batches - maxBatches, (#flow.batches - maxBatches) == 1 and "" or "es")
            break
        end
        local marker = ((flow.availableHereCount or 0) > 0 and batch.station == context.station) or (flow.availableHereCount or 0) == 0 and batchIndex == 1
        lines[#lines + 1] = string.format("%s %s - %d action%s", marker and ">" or " ", tostring(batch.label), #batch.actions, #batch.actions == 1 and "" or "s")
        for actionIndex, row in ipairs(batch.actions or {}) do
            if actionIndex > maxActionsPerBatch then
                lines[#lines + 1] = string.format("    + %d more", #batch.actions - maxActionsPerBatch)
                break
            end
            lines[#lines + 1] = string.format("    %s: %s", tostring(row.professionLabel), tostring(row.text or "Continue."))
        end
    end
    return table.concat(lines, "\n")
end

function ExecutionFlow:GetSummary()
    return self:Format(self:Build(), 5, 2)
end

JLP:RegisterModule("ExecutionFlow", ExecutionFlow)
