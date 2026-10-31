local _, JLP = ...

local function prerequisiteReference(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    if ownership and ownership.owned==true then return nil end
    local state=ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN"
    local reg=JLP:GetModule("ProfessionRegistry")
    local label=reg and reg:GetDisplayNameOrKey(key) or tostring(key)
    local text=state=="PROFESSION_NOT_LEARNED" and
        ("Learn "..label.." before JuztLevel can plan this profession.") or
        ("Verify learned "..label.." ownership before JuztLevel can plan this profession.")
    return {key=ownership and ownership.key or key,ownership=ownership,state=state,
        status=state,terminalReason=state,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,lightweightPrerequisite=true,guidance=text,action=text,actionKind="prerequisite"}
end


-- Single dataset resolver for registered profession datasets. Generic consumers
-- must not hardcode Tailoring/Enchanting/Alchemy data-table names.
local Provider = {
    contract = "profession-dataset-provider-v1",
}

local function registry()
    return JLP:GetModule("ProfessionRegistry")
end

local function directDataset(def)
    if not def or not def.datasetKey or not JLP.data then return nil end
    return JLP.data[def.datasetKey]
end

function Provider:GetRegisteredDataset(key)
    local reg = registry()
    local def = reg and reg:Get(key) or nil
    local dataset = directDataset(def)
    if not def or not dataset then return nil, def and "dataset-unavailable" or "unsupported-profession" end
    return dataset, nil, def
end

function Provider:CheckProductionAuthority(key,dataset,def)
    if not (def and def.maturity and def.maturity.production==true) then return false,"not-production-enabled" end
    if type(dataset)~="table" then return false,"dataset-unavailable" end
    -- A candidate/read-only dataset cannot be promoted by flipping Registry maturity.
    if dataset.productionCandidate==true or dataset.readOnly==true or dataset.executionEligible==false or dataset.nativeDispatchAllowed==false then
        return false,"production-dataset-authority-mismatch"
    end
    if dataset.authorityClass~="PRODUCTION" then return false,"production-dataset-authority-mismatch" end
    if tonumber(dataset.productionBaselineBuild)~=tonumber(dataset.sourceBuild) then return false,"production-baseline-mismatch" end
    if dataset.legacyProductionBaseline==true then
        if tonumber(dataset.productionBaselineBuild)~=70009 then return false,"legacy-baseline-mismatch" end
        -- Source baseline 70009 is immutable provenance, not a required client.
        -- Native execution still requires learned recipe, live reagents, protected
        -- user action and the separate ledger/settlement checks at dispatch.
        return true,"legacy-production-source-admitted"
    end
    local receipt=dataset.promotionReceipt
    if type(receipt)~="table" or receipt.professionKey~=key
        or tonumber(receipt.newBaselineBuild)~=tonumber(dataset.productionBaselineBuild)
        or receipt.datasetContract~=dataset.contract
        or type(receipt.evidenceFingerprint)~="string"
        or receipt.evidenceFingerprint==""
        then return false,"production-promotion-receipt-missing" end
    local proofClass = receipt.proofClass or "WOWHEAD_REFERENCE_IDS"
    if proofClass == "WOWHEAD_REFERENCE_IDS" then
        local idPolicy=JLP:GetModule("PublicIDReferencePolicy")
        local reference=idPolicy and idPolicy:AssessProfession(key)
        if not reference or not reference.accepted or
            tonumber(reference.referenceBuild)~=tonumber(receipt.newBaselineBuild) or
            receipt.publicReferenceFingerprint~=reference.referenceFingerprint then
            return false,"production-public-id-reference-mismatch"
        end
    else
        return false,"production-promotion-proof-class-unsupported"
    end
    -- Receipt build/token are preserved as historical evidence, NEVER compared
    -- against the running client as a universal feature entitlement.
    -- Action readiness is checked against the live client at native dispatch.
    return true,"profession-scoped-source-receipt-present"
end

-- Advisory snapshots are independent from native permission. Current-build DB2
-- data is consulted through the versioned communication bridge, while public
-- source guides remain labelled historical/reference-only when no current
-- client receipt can be produced. This never synthesizes recipe routes.
function Provider:GetReferenceSnapshot(key)
    local prerequisite=prerequisiteReference(key)
    if prerequisite then return prerequisite,prerequisite.terminalReason end
    local reg=registry()
    local def=reg and reg:Get(key)
    if not def then return nil,"unsupported-profession" end
    local guides=JLP:GetModule("ProfessionReferenceGuide")
    local guide=guides and guides:Get(def.key) or nil
    local client=JLP:GetModule("ClientBuildInfo")
    local observed=client and client.GetBuildNumber and client:GetBuildNumber() or nil
    local comm=JLP:GetModule("ProfessionDataCommunication")
    local current=nil
    if comm then
        -- Archived, read-only references remain usable without GetBuildInfo.
        -- The receipt must never claim a CURRENT match without live evidence.
        current=comm:GetProfessionState(def.key)
    end
    if not guide and not current then return nil,"reference-data-unavailable" end
    local alchemyAudit,alchemyAuditError=nil,nil
    if def.key=="ALCHEMY" and current and current.sourceBuild==70450 then
        local audit=JLP:GetModule("Build70450AlchemyRouteAudit")
        if audit and audit.Assess then
            alchemyAudit,alchemyAuditError=audit:Assess(70450)
        else
            alchemyAuditError="ALCHEMY_AUDIT_UNAVAILABLE"
        end
    end
    return {
        contract="profession-reference-snapshot-v1",key=def.key,
        guide=guide,clientBuild=observed,
        alchemySourceCrosscheck=alchemyAudit,
        alchemySourceCrosscheckError=alchemyAuditError,
        current=current,currentSourceBuild=current and current.sourceBuild or nil,
        guideSource=guide and (guide.guideURL or guide.source) or nil,
        sourceClass=current and (not observed and "CLIENT_UNKNOWN_DB2_REFERENCE" or
            (current.sourceBuild==observed and "CURRENT_CLIENT_DB2_REFERENCE" or
             "HISTORICAL_DB2_REFERENCE")) or "HISTORICAL_PUBLIC_GUIDE",
        readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
        completeLevelingRoute=false,materialTotalsVerified=false,
    }
end

-- A documented progression route is independently useful as a *guide*, even
-- when source/native production authority has not been granted. An inventory
-- of recipe identities alone is NOT evidence of a usable skill interval.
local function routeRows(dataset)
    if type(dataset) ~= "table" then return nil end
    local rows = dataset.route or dataset.steps
    return type(rows) == "table" and rows or nil
end

local function guideRouteCoverage(dataset)
    local rows = routeRows(dataset)
    local spans = {}
    for _, step in ipairs(rows or {}) do
        if type(step) == "table" then
            local lo, hi = tonumber(step.skillMin), tonumber(step.skillTarget)
            if lo and hi and lo >= 0 and hi <= 300 and lo < hi and
                lo == math.floor(lo) and hi == math.floor(hi) and
                type(step.recipe) == "string" and step.recipe ~= "" then
                spans[#spans+1] = {fromSkill=lo,toSkill=hi}
            end
        end
    end
    if #spans == 0 then return nil end
    table.sort(spans,function(a,b)
        if a.fromSkill ~= b.fromSkill then return a.fromSkill < b.fromSkill end
        return a.toSkill > b.toSkill
    end)
    local cursor=1
    local gaps={}
    for _, span in ipairs(spans) do
        if span.fromSkill > cursor then
            gaps[#gaps+1]={fromSkill=cursor,toSkill=span.fromSkill}
        end
        if span.toSkill > cursor then cursor=span.toSkill end
    end
    if cursor < 300 then gaps[#gaps+1]={fromSkill=cursor,toSkill=300} end
    return {contract="documented-guide-route-coverage-v1",intervalCount=#spans,
        completeGeometry=#gaps==0,gaps=gaps}
end

-- Copy route-bearing structures before exposing reference-only projections to
-- Planner/UI. A consumer must not mutate the registered original or accidentally
-- retain native flags from its metadata. The reference may contain nested
-- materials/strategy alternatives, so copy recursively (source data only).
local function guideCopy(value,seen)
    if type(value) ~= "table" then return value end
    seen=seen or {}
    if seen[value] then return seen[value] end
    local result={};seen[value]=result
    for k,v in pairs(value) do result[k]=guideCopy(v,seen) end
    return result
end

local function advisoryLegacyRoute(dataset, reason)
    -- Never mutate shared Data/Tailoring.lua or Data/Enchanting.lua. Native
    -- dispatcher continues to examine the ORIGINAL registered dataset and
    -- its production receipt, not this transient planner-only projection.
    local view=guideCopy(dataset)
    local coverage=guideRouteCoverage(dataset)
    view.guideRouteAvailable=coverage~=nil
    view.guideRouteCoverage=coverage
    view.guideRouteSource="REGISTERED_DOCUMENTED_ROUTE"
    -- Position and acquisition guidance are allowed, but no skill-up/craft
    -- quantity, full 1-300 completion, or live/native authority is inferred.
    view.completeLevelingRoute=false
    view.materialTotalsVerified=false
    view.authorityClass="HISTORICAL_REFERENCE"
    view.referenceOnly=true
    view.readOnlyRouteFallback=true
    view.readOnly=true
    view.executionEligible=false
    view.nativeDispatchAllowed=false
    view.plannerEligible=true
    view.routeAuthorityEnabled=false
    view.productionAuthority=false
    view.fallbackReason=reason
    view.guideAvailabilityReason=reason
    view.originalSourceBuild=dataset.sourceBuild
    view.contract="historical-route-reference-projection-v1"
    return view
end

function Provider:GetPlannerDataset(key, options)
    local prerequisite=prerequisiteReference(key)
    if prerequisite then return nil,prerequisite.terminalReason end
    options = type(options) == "table" and options or {}
    local dataset, reason, def = self:GetRegisteredDataset(key)
    local productionReason
    if def and dataset and def.maturity and def.maturity.production == true then
        local allowed
        allowed, productionReason=self:CheckProductionAuthority(key,dataset,def)
        if allowed then return dataset, "production-dataset" end
        -- A failed production receipt revokes native status, NOT the ability
        -- to read a documented route. Still consider a live-qualified bridge.
    end

    -- Runtime-qualified Planner route has priority over historical references.
    -- It is read-only, revocable, and independently guarded at native dispatch.
    if def and options.allowResearch ~= false then
        local bridge = JLP:GetModule("ResearchRouteAuthorityBridge")
        if bridge and bridge.GetPlannerDataset then
            local research = bridge:GetPlannerDataset(key)
            if research and research.routeAuthorityEnabled == true
                and research.plannerEligible == true
                and research.executionEligible == false
                and research.nativeDispatchAllowed ~= true
                and research.readOnly == true then
                return research, "controlled-research-dataset"
            end
        end
    end

    -- Keep the previous, explicitly supported read-only candidate contract.
    -- This is NOT a source production receipt or an execution credential.
    if def and dataset and options.allowCandidate
        and def.maturity and def.maturity.candidate == true
        and dataset.productionCandidate == true and dataset.readOnly == true
        and dataset.executionEligible == false and dataset.nativeDispatchAllowed ~= true
        and dataset.plannerEligible == true then
        return dataset, "production-candidate-readonly"
    end

    -- A route-bearing catalogue may drive a useful, explicitly labelled
    -- reference GUIDE without additional production approval. This also
    -- handles production datasets whose source receipt is stale or missing.
    -- Empty recipe catalogues without skill intervals are not promoted.
    if def and dataset and options.allowHistoricalReference ~= false then
        local coverage=guideRouteCoverage(dataset)
        if coverage then
            local why=productionReason or (def.maturity and def.maturity.candidate == true
                and "candidate-route-not-production-qualified" or "registered-guide-route-only")
            return advisoryLegacyRoute(dataset,why), productionReason and "historical-route-readonly" or "documented-guide-route-readonly"
        end
    end
    return nil, productionReason or reason or "documented-guide-route-unavailable"
end

-- Concrete source-qualified planning steps, independent of native admission.
function Provider:GetProgressionSteps(key,dataset,context)
    local prerequisite=prerequisiteReference(key)
    if prerequisite then return {},prerequisite.terminalReason end
    if key=="TAILORING" then
        local q=JLP:GetModule("TailoringRecipeQualification")
        local steps=q and q.GetPlanningSteps and q:GetPlanningSteps(dataset,context)
        if steps then return steps end
    end
    return dataset and (dataset.route or dataset.steps) or {}
end

-- Separate, non-authorizing evidence to explain what a source-backed guide
-- actually covers. Calling this method cannot grant native craft permissions.
function Provider:GetGuideRouteCoverage(key)
    local dataset,reason=self:GetRegisteredDataset(key)
    if not dataset then return nil,reason end
    local coverage=guideRouteCoverage(dataset)
    return coverage,coverage and nil or "no-documented-skill-route"
end

function Provider:GetCandidateDataset(key)
    local dataset, reason, def = self:GetRegisteredDataset(key)
    if not dataset then return nil, reason end
    if not (def.maturity and def.maturity.candidate == true) then return nil, "not-production-candidate" end
    if dataset.productionCandidate ~= true or dataset.readOnly ~= true or dataset.executionEligible ~= false then
        return nil, "candidate-authority-shape-invalid"
    end
    return dataset, nil
end

function Provider:GetRegisteredDatasetKeys()
    local reg = registry()
    local out = {}
    if not reg then return out end
    for _, key in ipairs(reg:GetKeys() or {}) do
        local def = reg:Get(key)
        if def and def.datasetKey and JLP.data and type(JLP.data[def.datasetKey]) == "table" then
            out[#out+1] = key
        end
    end
    return reg:OrderKeys(out)
end

function Provider:GetEvidenceDatasetKeys()
    local evidence = JLP.data and JLP.data.currentBuildEvidence
    local reg = registry()
    local out = {}
    for key in pairs(evidence and evidence.professions or {}) do
        if reg and reg:IsKnown(key) then out[#out+1] = key end
    end
    if reg then out = reg:OrderKeys(out) else table.sort(out) end
    return out
end

function Provider:Validate()
    local errors = {}
    local reg = registry()
    if not reg then return {"profession-registry-missing"} end
    for _, key in ipairs(reg:GetKeys() or {}) do
        local def = reg:Get(key)
        if def and def.datasetKey then
            local dataset = JLP.data and JLP.data[def.datasetKey]
            if type(dataset) ~= "table" then errors[#errors+1] = "dataset-key-missing:"..key end
            if dataset and tostring(dataset.key or ""):upper() ~= key then errors[#errors+1] = "dataset-key-mismatch:"..key end
        end
    end
    return errors
end

JLP:RegisterModule("ProfessionDatasetProvider", Provider)
