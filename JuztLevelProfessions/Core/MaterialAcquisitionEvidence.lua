local _, JLP = ...

-- Build-aware acquisition evidence for external research-route reagents. The
-- richer source class (herbalism, mining, skinning, disenchanting, vendor, etc.)
-- is preserved separately from the compact source token understood by the
-- current production Planner. This module is staging-only and never grants
-- Planner/execution authority.
local MaterialAcquisitionEvidence = {
    contract = "provenance-aware-material-acquisition-evidence-v1",
    storeSchema = 1,
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
}

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function currentBuildProvenance()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    if buildInfo and buildInfo.GetProvenance then
        local provenance = buildInfo:GetProvenance({allowTargetFallback=false})
        if provenance then return provenance end
    end
    -- An unavailable API is evidence UNKNOWN, never historical target evidence.
    return {game="Forever",build=nil,interface=nil,token="forever:unknown|interface:unknown",
        source="unknown",quality="UNKNOWN",addonVersion=JLP.version}
end
local function epochNow()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function catalogue()
    return JLP.data and JLP.data.materialAcquisitionSources or nil
end

local function referenceBuildState()
    local root = catalogue()
    local metadata = root and root.sourceMetadata or nil
    local provenance = currentBuildProvenance()
    local capturedBuild = metadata and tonumber(metadata.capturedAgainstBuild) or nil
    local currentBuild = provenance and tonumber(provenance.build) or nil
    local matches = capturedBuild ~= nil and currentBuild ~= nil and currentBuild == capturedBuild
    return {
        capturedBuild = capturedBuild,
        currentBuild = currentBuild,
        matches = matches and true or false,
        provenance = provenance,
    }
end

local function findReference(name, itemID)
    local root = catalogue()
    if not root then return nil end
    itemID = tonumber(itemID)
    if itemID then
        for _, row in pairs(root.materials or {}) do
            if tonumber(row.itemID) == itemID then return row end
        end
    end
    return root.materials and root.materials[normalize(name)] or nil
end

local function getStore(create)
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    local root = JLP.DB.account.materialAcquisitionEvidence
    if type(root) ~= "table" then
        if not create then return nil end
        root = { schema=MaterialAcquisitionEvidence.storeSchema, builds={} }
        JLP.DB.account.materialAcquisitionEvidence = root
    end
    root.schema = MaterialAcquisitionEvidence.storeSchema
    root.builds = type(root.builds) == "table" and root.builds or {}
    return root
end

local function getBuildStore(create)
    -- Identify a real client build *before* writing to SavedVariables. Unknown
    -- build tokens are not session identities and can collide after updates.
    -- Old unknown-token evidence is preserved as historical data, never reused
    -- as a live/current source by Resolve or planner consumers.
    local provenance = currentBuildProvenance()
    local actual = provenance and provenance.build
    if not provenance or provenance.quality ~= "LIVE" or
       type(actual) ~= "number" or actual ~= actual or actual <= 0 or
       actual == math.huge or actual ~= math.floor(actual) or
       actual > 9007199254740991 or type(provenance.token) ~= "string" or
       provenance.token == "" then
        return nil, nil
    end
    local expectedToken = string.format("forever:%s|interface:%s",
        tostring(actual), tostring(provenance.interface or "unknown"))
    if provenance.token ~= expectedToken then return nil, nil end
    local root = getStore(create)
    if not root then return nil, nil end
    local token = provenance.token
    local build = root.builds[token]
    if type(build) ~= "table" then
        if not create then return root, nil end
        build = { provenance=provenance, materials={} }
        root.builds[token] = build
    end
    -- P0/F1: the lookup key alone cannot establish the provenance of a
    -- persisted SavedVariables bucket. Do not promote legacy/contradictory
    -- buckets into LIVE evidence, and never silently rewrite their receipt.
    local stored = build.provenance
    if type(stored) ~= "table" or stored.quality ~= "LIVE" or
       stored.build ~= actual or stored.token ~= token or
       stored.interface ~= provenance.interface or
       stored.source ~= provenance.source then
        return root, nil
    end
    build.materials = type(build.materials) == "table" and build.materials or {}
    return root, build
end

local function itemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function merchantIdentity()
    local name, guid
    if type(UnitName) == "function" then
        local ok, value = pcall(UnitName, "npc")
        if ok and value and value ~= "" then name = tostring(value) end
    end
    if type(UnitGUID) == "function" then
        local ok, value = pcall(UnitGUID, "npc")
        if ok and value and value ~= "" then guid = tostring(value) end
    end
    return name, guid
end

local function plannerSourceForLive(sourceType, reference)
    sourceType = tostring(sourceType or "")
    if sourceType == "vendor" then return "vendor" end
    if sourceType == "disenchant" then return "disenchant-or-auction" end
    if sourceType == "crafted" then return reference and reference.plannerSource or "auction" end
    if sourceType == "farm" or sourceType == "auction" then return "auction" end
    return reference and reference.plannerSource or nil
end

function MaterialAcquisitionEvidence:ObserveMaterialSource(payload)
    if type(payload) ~= "table" then return false, "invalid-payload" end
    local reference = findReference(payload.name, payload.itemID)
    if not reference then return false, "untracked-material" end
    local sourceType = tostring(payload.sourceType or "")
    if sourceType == "" then return false, "source-type-missing" end

    local _, build = getBuildStore(true)
    if not build then return false, "build-unavailable" end
    local materialKey = normalize(reference.name)
    local row = build.materials[materialKey]
    if type(row) ~= "table" then
        row = {
            name = reference.name,
            itemID = tonumber(payload.itemID) or tonumber(reference.itemID),
            samples = 0,
            sources = {},
            evidenceIndex = {},
            firstObservedAt = epochNow(),
        }
        build.materials[materialKey] = row
    end

    local evidenceID = payload.evidenceID
    if not evidenceID or evidenceID == "" then
        evidenceID = table.concat({sourceType, tostring(payload.npc or payload.sourceName or ""), tostring(payload.itemID or reference.itemID or "")}, "|")
    end
    evidenceID = tostring(evidenceID)
    row.evidenceIndex = type(row.evidenceIndex) == "table" and row.evidenceIndex or {}
    if row.evidenceIndex[evidenceID] then return false, "duplicate-source-observation" end
    row.evidenceIndex[evidenceID] = true

    row.samples = math.max(0, tonumber(row.samples) or 0) + 1
    row.lastObservedAt = epochNow()
    row.lastSourceType = sourceType
    row.lastNpc = payload.npc
    row.lastNpcGUID = payload.npcGUID
    row.lastZone = payload.zone
    row.lastEvidence = payload.evidence or "live-current-build"
    row.itemID = tonumber(payload.itemID) or row.itemID or tonumber(reference.itemID)
    row.sources = type(row.sources) == "table" and row.sources or {}
    local sourceKey = table.concat({sourceType, normalize(payload.npc or payload.sourceName), normalize(payload.zone)}, "|")
    local source = row.sources[sourceKey] or {sourceType=sourceType,npc=payload.npc,npcGUID=payload.npcGUID,zone=payload.zone,samples=0}
    source.samples = math.max(0, tonumber(source.samples) or 0) + 1
    source.lastObservedAt = row.lastObservedAt
    row.sources[sourceKey] = source

    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("MATERIAL_ACQUISITION_EVIDENCE_UPDATED", row) end
    return true, row
end

function MaterialAcquisitionEvidence:ObserveMerchant()
    if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemLink) ~= "function" then
        return 0, "merchant-api-unavailable"
    end
    local okCount, count = pcall(GetMerchantNumItems)
    count = okCount and tonumber(count) or 0
    if not count or count <= 0 then return 0, "merchant-empty" end
    local npc, npcGUID = merchantIdentity()
    local observed = 0
    for index=1,count do
        local okLink, link = pcall(GetMerchantItemLink, index)
        local itemID = okLink and itemIDFromLink(link) or nil
        local reference = itemID and findReference(nil, itemID) or nil
        if reference then
            local accepted = self:ObserveMaterialSource({
                name = reference.name,
                itemID = itemID,
                sourceType = "vendor",
                npc = npc,
                npcGUID = npcGUID,
                evidenceID = table.concat({tostring(npcGUID or npc or "merchant"), tostring(itemID), tostring(index)}, "|"),
                evidence = "live-merchant-inventory",
            })
            if accepted then observed = observed + 1 end
        end
    end
    return observed, observed > 0 and "merchant-materials-observed" or "no-tracked-materials"
end

function MaterialAcquisitionEvidence:GetLive(name, itemID)
    local _, build = getBuildStore(false)
    if not build then return nil end
    local reference = findReference(name, itemID)
    local materialKey = normalize(reference and reference.name or name)
    return build.materials and build.materials[materialKey] or nil
end

function MaterialAcquisitionEvidence:GetReference(name, itemID)
    return findReference(name, itemID)
end

function MaterialAcquisitionEvidence:Resolve(name, itemID)
    local reference = findReference(name, itemID)
    local live = self:GetLive(name, itemID)
    local buildState = referenceBuildState()
    local out = {
        name = name,
        itemID = tonumber(itemID) or (reference and tonumber(reference.itemID)) or nil,
        reference = reference,
        live = live,
        sourceClass = reference and reference.sourceClass or nil,
        plannerSource = nil,
        acquisitionKinds = reference and reference.acquisitionKinds or nil,
        ready = false,
        sourceResolved = false,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        currentBuild = buildState.currentBuild,
        referenceCapturedBuild = buildState.capturedBuild,
        referenceBuildMatch = buildState.matches,
        -- Read-only historical source display is independent of live build.
        planningUsable = false,
        planningOnly = true,
        planningSource = nil,
    }

    if live and (tonumber(live.samples) or 0) >= 1 then
        local best
        for _, source in pairs(live.sources or {}) do
            if not best or (tonumber(source.samples) or 0) > (tonumber(best.samples) or 0) then best = source end
        end
        local sourceType = best and best.sourceType or live.lastSourceType
        out.status = "live-current-build-material-source"
        out.state = out.status
        out.sourceType = sourceType
        out.plannerSource = plannerSourceForLive(sourceType, reference)
        out.sourceClass = sourceType == "vendor" and "vendor" or (reference and reference.sourceClass or sourceType)
        out.ready = out.plannerSource ~= nil
        out.sourceResolved = out.ready
        out.planningUsable = out.ready
        out.planningOnly = false
        out.planningSource = out.plannerSource
        out.evidence = live.lastEvidence or "live-current-build"
        out.confidence = (tonumber(live.samples) or 0) >= 2 and "verified" or "observed"
        out.liveVerified = true
        out.source = best or {sourceType=sourceType,npc=live.lastNpc,zone=live.lastZone}
        return out
    end

    if not reference then
        out.status = "material-source-reference-missing"
        out.state = out.status
        return out
    end
    if reference.conflict then
        out.status = "external-material-source-conflict"
        out.state = out.status
        out.conflict = true
        out.conflictReason = reference.conflictReason
        return out
    end
    if reference.referenceEligible ~= true or not reference.plannerSource then
        out.status = "external-material-source-unresolved"
        out.state = out.status
        return out
    end
    -- Historical source references remain useful for read-only planning,
    -- including on unknown or newer builds. They never qualify live execution.
    out.planningUsable = true
    out.planningSource = reference.plannerSource
    if not buildState.matches then
        out.status = "external-material-source-stale-build"
        out.state = out.status
        out.plannerSource = reference.plannerSource
        out.evidence = reference.evidence
        out.confidence = "historical-reference"
        return out
    end

    out.status = "external-forever-material-source"
    out.state = out.status
    out.planningOnly = true
    out.ready = true
    out.sourceResolved = true
    out.plannerSource = reference.plannerSource
    out.evidence = reference.evidence
    out.confidence = reference.evidenceQuality or "external-reference"
    out.externalVerified = true
    return out
end

function MaterialAcquisitionEvidence:Validate()
    local errors, warnings = {}, {}
    local root = catalogue()
    if not root then return {"material acquisition source catalogue unavailable"}, warnings end
    if root.contract ~= "forever-material-acquisition-source-reference-v1" then errors[#errors+1] = "material acquisition source catalogue contract mismatch" end

    local keepNames = {}
    local research = JLP.data and JLP.data.professionResearchRoutes
    for professionKey, modes in pairs(research and research.professions or {}) do
        if professionKey ~= "HARNESS" and professionKey ~= "HARNESSCLOSURE" and professionKey ~= "HARNESSSEGMENT" and professionKey ~= "HARNESSQUAL" then
            for _, route in pairs(modes or {}) do
                for _, step in ipairs(type(route)=="table" and route.steps or {}) do
                    if step.kind == "craft" and step.keep == true and step.recipe then keepNames[normalize(step.recipe)] = true end
                end
            end
        end
    end
    for professionKey, modes in pairs(research and research.professions or {}) do
        if professionKey ~= "HARNESS" and professionKey ~= "HARNESSCLOSURE" and professionKey ~= "HARNESSSEGMENT" and professionKey ~= "HARNESSQUAL" then
            for _, route in pairs(modes or {}) do
                for _, step in ipairs(type(route)=="table" and route.steps or {}) do
                    for _, requirement in ipairs(step.requirements or {}) do
                        local materialKey = normalize(requirement.name)
                        if materialKey ~= "" and not keepNames[materialKey] and not (root.materials and root.materials[materialKey]) then
                            warnings[#warnings+1] = "missing material acquisition reference: " .. tostring(requirement.name)
                        end
                    end
                end
            end
        end
    end

    for materialKey, row in pairs(root.materials or {}) do
        if normalize(row.name) ~= materialKey then errors[#errors+1] = "material acquisition key mismatch: " .. tostring(materialKey) end
        if not row.sourceClass or not row.evidence then errors[#errors+1] = "incomplete material acquisition reference: " .. tostring(materialKey) end
        if not row.conflict and row.referenceEligible == true and not row.plannerSource then errors[#errors+1] = "eligible material reference missing planner source: " .. tostring(materialKey) end
    end
    return errors, warnings
end

local function acquisitionKindsText(kinds)
    local parts = {}
    for _, value in ipairs(kinds or {}) do parts[#parts+1] = tostring(value) end
    return #parts > 0 and table.concat(parts, "/") or "none"
end

function MaterialAcquisitionEvidence:GetSummary(name)
    if name and tostring(name) ~= "" then
        local row = self:Resolve(name)
        local lines = {
            "Material acquisition evidence: " .. tostring(name),
            "Status: " .. tostring(row.status),
            "Source class: " .. tostring(row.sourceClass or "unresolved"),
            "Acquisition kinds: " .. acquisitionKindsText(row.acquisitionKinds),
            "Planner staging source: " .. tostring(row.plannerSource or "unresolved"),
            "Confidence: " .. tostring(row.confidence or "none"),
            "Current build: " .. tostring(row.currentBuild or "unknown"),
            "Reference build: " .. tostring(row.referenceCapturedBuild or "unknown"),
            "Source resolved: " .. tostring(row.sourceResolved == true),
            "Historical planning source (read-only): " .. tostring(row.planningUsable == true),
            "Planner authority: disabled",
        }
        if row.conflictReason then lines[#lines+1] = "Conflict: " .. tostring(row.conflictReason) end
        return table.concat(lines, "\n")
    end

    local root = catalogue()
    if not root then return "Material acquisition evidence unavailable." end
    local total, eligible, conflicts, vendor, market, disenchant = 0, 0, 0, 0, 0, 0
    for _, row in pairs(root.materials or {}) do
        total = total + 1
        if row.conflict then conflicts = conflicts + 1
        elseif row.referenceEligible == true and row.plannerSource then
            eligible = eligible + 1
            if row.plannerSource == "vendor" then vendor = vendor + 1
            elseif row.plannerSource == "disenchant-or-auction" then disenchant = disenchant + 1
            else market = market + 1 end
        end
    end
    return table.concat({
        "Material acquisition evidence:",
        string.format("External research materials: %d · reference-eligible %d · conflicted %d", total, eligible, conflicts),
        string.format("Planner staging mapping: vendor %d · market/external %d · disenchant-or-auction %d", vendor, market, disenchant),
        "Authority: live current-build source > same-build external Forever reference > unresolved/stale",
        "Gathering/crafting origin is preserved separately from the compact Planner staging source; auction mapping does not assert current AH stock.",
        "Planner authority disabled",
    }, "\n")
end

JLP:RegisterModule("MaterialAcquisitionEvidence", MaterialAcquisitionEvidence)
