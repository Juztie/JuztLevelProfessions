local _, JLP = ...

-- Runtime-only, read-only capture of the optional profession-window data
-- compared against public Forever reference data by BuildRequalificationService. A capture is diagnostic evidence only;
-- it is never persisted and never authorizes native execution.
local Session = {
    contract = "optional-profession-observation-session-v1",
    snapshotContract = "optional-profession-observation-snapshot-v1",
    nativeDispatchAllowed = false,
    persisted = false,
    lastByProfession = {},
}

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function materialToken(materials)
    local rows = {}
    for _, m in ipairs(materials or {}) do
        local itemID = tonumber(m.itemID or m[1])
        local quantity = tonumber(m.quantity or m.quantityRequired or m[2])
        if itemID and quantity then rows[#rows+1] = tostring(itemID).."x"..tostring(quantity) end
    end
    table.sort(rows)
    return table.concat(rows, ",")
end

local function digest(text)
    -- Diagnostic checksum only. It is intentionally not an authorization token.
    local hash = 5381
    text = tostring(text or "")
    for i=1,#text do hash = (hash * 33 + string.byte(text, i)) % 2147483647 end
    return string.format("%08x", hash)
end

local function fingerprint(live)
    local parts = {
        tostring(live.clientBuildToken or "unknown"), tostring(live.professionKey or "unknown"),
        tostring(live.openSkillLineID or "unknown"), tostring(live.routeCount or 0),
        tostring(live.identityMatches or 0), tostring(live.reagentMatches or 0), tostring(live.accessMatches or 0),
    }
    for _, row in ipairs(live.observationRows or {}) do
        parts[#parts+1] = table.concat({
            tostring(row.recipeID or "?"), tostring(row.observedSkillLineID or "?"),
            tostring(row.identityMatch == true), materialToken(row.expectedMaterials), materialToken(row.observedMaterials),
            tostring(row.reagentMatch == true), tostring(row.learned == true), tostring(row.accessSatisfied == true),
        }, ":")
    end
    return "diag-"..digest(table.concat(parts, "|"))
end

function Session:CaptureOpenProfession()
    local requal = JLP:GetModule("BuildRequalificationService")
    if not requal or not requal.AssessOpenProfession then
        return {contract=self.snapshotContract,state="QUALIFICATION_SERVICE_MISSING",nativeDispatchAllowed=false,persisted=false}
    end
    local live = requal:AssessOpenProfession()
    local route = JLP:GetModule("RouteQualificationService")
    local lifecycle = live.professionKey and route and route:AuditProfession(live.professionKey,{liveEvidence=live}) or nil
    local snapshot = {
        contract = self.snapshotContract,
        capturedAt = now(),
        professionKey = live.professionKey,
        clientBuildToken = live.clientBuildToken,
        liveBuild = live.liveBuild,
        buildState = live.buildState,
        openSkillLineID = live.openSkillLineID,
        state = live.state,
        identityState = live.identityState,
        reagentState = live.reagentState,
        accessState = live.accessState,
        routeCount = tonumber(live.routeCount) or 0,
        identityMatches = tonumber(live.identityMatches) or 0,
        reagentMatches = tonumber(live.reagentMatches) or 0,
        accessMatches = tonumber(live.accessMatches) or 0,
        accessRequiredCount = tonumber(live.accessRequiredCount) or 0,
        observationRows = live.observationRows or {},
        audit = live.audit,
        lifecycle = lifecycle,
        nativeDispatchAllowed = false,
        persisted = false,
        optional = true,
    }
    snapshot.diagnosticFingerprint = fingerprint(snapshot)
    if snapshot.professionKey then self.lastByProfession[snapshot.professionKey] = snapshot end
    return snapshot
end

function Session:GetLast(key)
    key = tostring(key or ""):upper()
    return self.lastByProfession[key]
end

function Session:Clear()
    self.lastByProfession = {}
end

local function summary(snapshot)
    if type(snapshot) ~= "table" then return "No optional profession snapshot capture available." end
    return string.format("Optional profession snapshot %s · %s · build %s · identity %d/%d %s · reagents %d/%d %s · access %d/%d %s · lifecycle %s · fingerprint %s · runtime-only · native dispatch forbidden",
        tostring(snapshot.professionKey or "unknown"), tostring(snapshot.state or "unknown"), tostring(snapshot.buildState or "unknown"),
        tonumber(snapshot.identityMatches) or 0, tonumber(snapshot.routeCount) or 0, tostring(snapshot.identityState or "unknown"),
        tonumber(snapshot.reagentMatches) or 0, tonumber(snapshot.routeCount) or 0, tostring(snapshot.reagentState or "unknown"),
        tonumber(snapshot.accessMatches) or 0, tonumber(snapshot.accessRequiredCount) or 0, tostring(snapshot.accessState or "unknown"),
        tostring(snapshot.lifecycle and snapshot.lifecycle.state or "not-observed"), tostring(snapshot.diagnosticFingerprint or "none"))
end

function Session:GetLastSummary(key)
    if key then return summary(self:GetLast(key)) end
    local keys = {}
    for professionKey in pairs(self.lastByProfession) do keys[#keys+1] = professionKey end
    table.sort(keys)
    if #keys == 0 then return "No optional profession snapshot capture available." end
    local parts = {}
    for _, professionKey in ipairs(keys) do parts[#parts+1] = summary(self.lastByProfession[professionKey]) end
    return table.concat(parts, " | ")
end

function Session:GetSummary(key)
    if key then return summary(self:GetLast(key)) end
    local live = self:CaptureOpenProfession()
    return summary(live)
end

function Session:Validate()
    local errors = {}
    if self.persisted ~= false then errors[#errors+1] = "live-qualification-persisted" end
    if self.nativeDispatchAllowed ~= false then errors[#errors+1] = "live-qualification-native-authority" end
    return errors
end

JLP:RegisterModule("ProfessionObservationSnapshot", Session)
