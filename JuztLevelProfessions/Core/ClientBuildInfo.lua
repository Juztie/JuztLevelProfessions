local _, JLP = ...

-- Single authoritative parser for the WoW GetBuildInfo() contract.
-- GetBuildInfo returns: buildVersion, buildNumber, buildDate, interfaceVersion, ...
-- This module never treats missing/invalid client evidence as a target-build match.
local ClientBuildInfo = {
    contract = "client-build-info-v1",
    comparisonContract = "client-build-comparison-v1",
    states = {
        CURRENT = "CURRENT",
        DRIFT = "DRIFT",
        UNKNOWN = "UNKNOWN",
    },
}

local function providerOrGlobal(provider)
    if type(provider) == "function" then return provider end
    if type(GetBuildInfo) == "function" then return GetBuildInfo end
    return nil
end

function ClientBuildInfo:Read(provider)
    local fn = providerOrGlobal(provider)
    if not fn then
        return {
            contract = self.contract,
            known = false,
            state = self.states.UNKNOWN,
            reason = "build-api-unavailable",
            token = "forever:unknown|interface:unknown",
        }
    end

    local ok, version, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo, currentVersion = pcall(fn)
    if not ok then
        return {
            contract = self.contract,
            known = false,
            state = self.states.UNKNOWN,
            reason = "build-api-error",
            token = "forever:unknown|interface:unknown",
        }
    end

    local build = tonumber(buildNumber)
    local interface = tonumber(interfaceVersion)
    -- Interface version is optional, but invalid values must never poison the
    -- session identity token or be confused with a verified API capability.
    if not interface or interface ~= interface or interface <= 0 or
       interface == math.huge or interface ~= math.floor(interface) or
       interface > 9007199254740991 then interface = nil end
    -- No NaN, infinities, fractional, zero or negative builds may become
    -- trusted session tokens. A malformed build remains UNKNOWN, not a match.
    if not build or build ~= build or build <= 0 or build == math.huge or
       build ~= math.floor(build) or build > 9007199254740991 then
        return {
            contract = self.contract,
            known = false,
            state = self.states.UNKNOWN,
            reason = "build-number-invalid",
            version = version,
            rawBuildNumber = buildNumber,
            buildDate = buildDate,
            interfaceVersion = interface,
            localizedVersion = localizedVersion,
            buildInfo = buildInfo,
            currentVersion = currentVersion,
            token = string.format("forever:unknown|interface:%s", tostring(interface or "unknown")),
        }
    end

    return {
        contract = self.contract,
        known = true,
        state = "KNOWN",
        reason = nil,
        version = version,
        buildNumber = build,
        buildDate = buildDate,
        interfaceVersion = interface,
        localizedVersion = localizedVersion,
        buildInfo = buildInfo,
        currentVersion = currentVersion,
        token = string.format("forever:%s|interface:%s", tostring(build), tostring(interface or "unknown")),
    }
end

function ClientBuildInfo:Compare(expectedBuild, provider)
    local expected = tonumber(expectedBuild)
    if not expected or expected ~= expected or expected <= 0 or
       expected == math.huge or expected ~= math.floor(expected) or
       expected > 9007199254740991 then expected = nil end
    local info = self:Read(provider)
    local state = self.states.UNKNOWN
    if info.known and expected then
        state = info.buildNumber == expected and self.states.CURRENT or self.states.DRIFT
    end
    return {
        contract = self.comparisonContract,
        state = state,
        current = state == self.states.CURRENT,
        drift = state == self.states.DRIFT,
        unknown = state == self.states.UNKNOWN,
        expectedBuild = expected,
        clientBuild = info.buildNumber,
        clientBuildToken = info.token,
        client = info,
    }
end

function ClientBuildInfo:GetBuildNumber(provider)
    local info = self:Read(provider)
    return info.known and info.buildNumber or nil
end

function ClientBuildInfo:GetSummary(expectedBuild)
    local info = self:Read()
    local state = self.states.UNKNOWN
    if tonumber(expectedBuild) then
        state = self:Compare(expectedBuild).state
    elseif info.known then
        state = "KNOWN"
    end
    return string.format("Client build: version %s · build %s · date %s · interface %s · state %s · token %s",
        tostring(info.version or "unknown"), tostring(info.buildNumber or "unknown"), tostring(info.buildDate or "unknown"),
        tostring(info.interfaceVersion or "unknown"), tostring(state), tostring(info.token or "forever:unknown|interface:unknown"))
end

function ClientBuildInfo:GetProvenance(options)
    options = type(options) == "table" and options or {}
    local info = self:Read(options.provider)
    local constants = JLP.Constants or {}
    local targetBuild = tonumber(options.targetBuild) or tonumber(constants.CURRENT_FOREVER_BUILD)
    local targetInterface = tonumber(options.targetInterface) or tonumber(constants.TARGET_INTERFACE)
    -- Target constants are historical metadata, never observed client evidence.
    -- Validate them before constructing even a TARGET_FALLBACK receipt.
    if not targetBuild or targetBuild ~= targetBuild or targetBuild <= 0 or
       targetBuild == math.huge or targetBuild ~= math.floor(targetBuild) or
       targetBuild > 9007199254740991 then targetBuild = nil end
    if not targetInterface or targetInterface ~= targetInterface or targetInterface <= 0 or
       targetInterface == math.huge or targetInterface ~= math.floor(targetInterface) or
       targetInterface > 9007199254740991 then targetInterface = nil end

    local build = info.known and info.buildNumber or (options.allowTargetFallback and targetBuild or nil)
    -- Never splice a TARGET_INTERFACE constant into a known live build. A
    -- verified build with unknown interface stays interface:unknown; making
    -- up that field would manufacture a forged LIVE session receipt.
    local interface = info.interfaceVersion
    if not info.known and options.allowTargetFallback and interface == nil then
        interface = targetInterface
    end
    if type(interface) ~= "number" or interface ~= interface or interface <= 0 or
       interface == math.huge or interface ~= math.floor(interface) or
       interface > 9007199254740991 then interface = nil end
    if not build and not interface then return nil end

    local source
    if info.known then
        source = (targetBuild and info.buildNumber ~= targetBuild) and "live-client-with-historical-source" or "live-client"
    else
        source = options.allowTargetFallback and "target-constant" or "unknown"
    end

    return {
        game = "Forever",
        build = build,
        interface = interface,
        token = string.format("forever:%s|interface:%s", tostring(build or "unknown"), tostring(interface or "unknown")),
        clientVersion = info.version,
        buildDate = info.buildDate,
        targetBuild = targetBuild,
        targetInterface = targetInterface,
        source = source,
        -- A verified build without an observed interface is build-only evidence,
        -- not a complete LIVE session receipt for persisted or native evidence.
        quality = info.known and (interface and "LIVE" or "LIVE_BUILD_ONLY") or
            (options.allowTargetFallback and "TARGET_FALLBACK" or "UNKNOWN"),
        liveSessionVerified = info.known == true and interface ~= nil,
        clientBuildToken = info.token,
        addonVersion = JLP.version,
    }
end

function ClientBuildInfo:Validate()
    local target = tonumber(JLP.Constants and JLP.Constants.CURRENT_FOREVER_BUILD) or 70450
    local current = self:Compare(target, function() return "1.60.1", tostring(target), "Oct 18 2026", 16001 end)
    local historical = self:Compare(target, function() return "1.60.1", "70374", "Oct 18 2026", 16001 end)
    local unknown = self:Compare(target, function() return "1.60.1", nil, "Oct 18 2026", 16001 end)
    local errors = {}
    if current.state ~= self.states.CURRENT or current.clientBuild ~= target then errors[#errors+1] = "current-70450-mapping" end
    if historical.state ~= self.states.DRIFT or historical.clientBuild ~= 70374 then errors[#errors+1] = "historical-drift-mapping" end
    if unknown.state ~= self.states.UNKNOWN or unknown.current then errors[#errors+1] = "unknown-fail-open" end
    return errors
end

JLP:RegisterModule("ClientBuildInfo", ClientBuildInfo)
