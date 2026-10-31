local _, JLP = ...

-- F-17 preflight is strictly informational; it never grants or revokes
-- execution privileges. Only the existing independent authority gates can
-- decide whether native crafting is permitted.
local Preflight = {
    contract = "jlp-build-preflight-readonly-v1",
    nativeDispatchAllowed = false,
    persisted = false,
    requalificationBuild = 70245, -- Historical dataset audit only; NOT current-build proof.
    referenceBuild = 70450,
}

function Preflight:Assess(options)
    options = type(options) == "table" and options or {}
    local build = JLP:GetModule("ClientBuildInfo")
    local constants = JLP.Constants or {}
    -- A preflight's installed read-only reference is an immutable source;
    -- CURRENT_FOREVER_BUILD is presentation metadata, not its identity.
    -- A future addon update must not hide the still-installed 70450 archive.
    local target = self.referenceBuild
    local compare = build and build:Compare(target, options.provider) or nil
    local client = compare and compare.client or nil
    local state = "BUILD_UNKNOWN"
    if compare and compare.state == "CURRENT" then state = "BUILD_MATCH"
    elseif compare and compare.state == "DRIFT" then state = "REFERENCE_HISTORICAL" end

    local out = {
        contract = self.contract,
        state = state,
        buildState = compare and compare.state or "UNKNOWN",
        clientBuild = compare and compare.clientBuild or nil,
        clientBuildToken = compare and compare.clientBuildToken or "forever:unknown|interface:unknown",
        expectedEvidenceBuild = target,
        legacyRequalificationBuild = self.requalificationBuild,
        legacyDatasetRequalifiedForCurrentBuild = false,
        historicalSourceBuild = tonumber(constants.TARGET_BUILD),
        clientInterface = client and client.interfaceVersion or nil,
        nativeDispatchAllowed = false,
        persisted = false,
        datasetRows = {},
        datasetRequalifiedCount = 0, -- Historical metric: never incremented by 70450 source presence.
        sourceReferenceCount = 0,
        datasetBlockedCount = 0,
    }
    if options.includeDatasets then
        local ref = JLP:GetModule("Build70450RecipeCatalogue")
        local coverage = ref and ref.GetCoverage and ref:GetCoverage() or nil
        if coverage and coverage.sourceBuild == self.referenceBuild and
           coverage.readOnly == true and
           coverage.nativeDispatchAllowed == false then
            for key, row in pairs(coverage.byProfession or {}) do
                out.datasetRows[#out.datasetRows+1] = {
                    profession = key, state = "SOURCE_REFERENCE_ONLY",
                    readOnlyQualified = false, -- No 70245-style dataset requalification.
                    sourceReferenceAvailable = true,
                    nativeDispatchAllowed = false,
                    recipeCount = row.recipeCandidates,
                    liveAcquisitionVerified = false,
                }
                out.sourceReferenceCount = out.sourceReferenceCount + 1
            end
            table.sort(out.datasetRows, function(a,b) return a.profession < b.profession end)
        else
            out.datasetBlockedCount = 12
        end
    end
    if state == "BUILD_MATCH" then
        out.reason = "70450 source reference matches the client; older 70245 requalification and native execution rights remain independent and are not promoted."
    elseif state == "REFERENCE_HISTORICAL" then
        out.reason = "Client build differs from reference; historical read-only source data remain available, never native authority."
    else
        out.reason = "Client build unavailable; source references remain read-only; native readiness requires live evidence."
    end
    return out
end

function Preflight:GetSummary(options)
    options = type(options) == "table" and options or {}
    local result = self:Assess({provider = options.provider, includeDatasets = options.includeDatasets ~= false})
    return string.format("Build preflight: %s | client %s | evidence target %d | historical baseline %s | 70450 source-reference professions %d | blocked %d | legacy requalification 70245 NOT transferred | native authority NOT GRANTED. %s",
        result.state, tostring(result.clientBuild or "unknown"), result.expectedEvidenceBuild,
        tostring(result.historicalSourceBuild or "unknown"), result.sourceReferenceCount,
        result.datasetBlockedCount, result.reason)
end

JLP:RegisterModule("BuildPreflightPresentation", Preflight)
