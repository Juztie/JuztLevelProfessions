local _, JLP = ...

local Service = {
    contract = "build-requalification-service-v1",
    rowContract = "build-requalification-row-v1",
    liveContract = "build-requalification-live-corroboration-v1",
    targetBuild = 70245,
    persisted = false,
    nativeDispatchAllowed = false,
}

local function buildInfo()
    return JLP:GetModule("ClientBuildInfo")
end

local function provider()
    return JLP:GetModule("ProfessionDatasetProvider")
end

local function evidenceRegistry()
    return JLP.data and JLP.data.currentBuildEvidence or nil
end

local function routeQualification()
    return JLP:GetModule("RouteQualificationService")
end

local function normalizeMaterials(materials)
    local out = {}
    for _, m in ipairs(materials or {}) do
        local itemID = tonumber(m.itemID or m[1])
        local quantity = tonumber(m.quantity or m.quantityRequired or m[2])
        if itemID and quantity and quantity > 0 then out[#out+1] = {itemID, quantity} end
    end
    table.sort(out, function(a,b)
        if a[1] == b[1] then return a[2] < b[2] end
        return a[1] < b[1]
    end)
    return out
end

local function sameMaterials(a, b)
    a = normalizeMaterials(a)
    b = normalizeMaterials(b)
    if #a ~= #b then return false end
    for i=1,#a do
        if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] then return false end
    end
    return true
end

local function routeByRecipeID(dataset)
    local out = {}
    for _, step in ipairs(dataset and (dataset.route or dataset.steps) or {}) do
        local id = tonumber(step.recipeID)
        if id then
            out[id] = out[id] or {}
            out[id][#out[id]+1] = step
        end
    end
    return out
end

local function countRows(rows)
    return type(rows) == "table" and #rows or 0
end

local function structuralAudit(dataset)
    local errors = {}
    local route = dataset and (dataset.route or dataset.steps) or {}
    local seen = {}
    for i, step in ipairs(route) do
        local id = tonumber(step.recipeID)
        if not id then
            errors[#errors+1] = "recipe-id:"..i
        elseif seen[id] then
            local identity=JLP:GetModule("ProductionTailoringRecipeIdentity")
            local same=true
            for _,first in ipairs(seen[id]) do
                same=same and first.recipe==step.recipe and sameMaterials(first.materials,step.materials)
                for _,field in ipairs({"outputItemID","outputPerCraft","outputQuantityReference","requiredSkill","rawYellowThreshold","rawGreyThreshold","rawMinSkillLineRank"}) do
                    if first[field]~=nil and step[field]~=nil and first[field]~=step[field] then same=false end
                end
                if identity and identity.RecipeFieldsMatch then same=same and identity:RecipeFieldsMatch(first,step) end
            end
            if not same then errors[#errors+1] = "conflicting-recipe-id:"..id end
            seen[id][#seen[id]+1]=step
        else
            seen[id] = {step}
        end
        local minimum,target=tonumber(step.skillMin),tonumber(step.skillTarget)
        if not minimum or not target or target<=minimum or minimum<1 or
            minimum~=math.floor(minimum) or target~=math.floor(target) or
            (i>1 and tonumber(route[i-1].skillTarget)~=minimum) then
            errors[#errors+1]="segment-interval:"..i
        end
        if type(step.materials) ~= "table" then
            errors[#errors+1] = "materials:"..i
        else
            for _, m in ipairs(step.materials) do
                if not tonumber(m.itemID) or not tonumber(m.quantity) or tonumber(m.quantity) <= 0 then
                    errors[#errors+1] = "material:"..i
                end
            end
        end
    end
    return #errors == 0 and #route > 0, errors, #route
end

local function publicEvidenceAudit(dataset, evidence)
    local rows = evidence and evidence.rows or {}
    local byID = routeByRecipeID(dataset)
    local matches, mismatches, seenEvidence = 0, {}, {}
    local recipeCount=0
    for _ in pairs(byID) do recipeCount=recipeCount+1 end
    for _, row in ipairs(rows) do
        local id = tonumber(row.recipeID)
        local segments = id and byID[id] or nil
        local materialMatch,toolMatch,targetMatch = segments~=nil,true,true
        for _,step in ipairs(segments or {}) do
            materialMatch=materialMatch and sameMaterials(step.materials,row.materials)
            if tonumber(row.requiredToolItemID) then
                toolMatch=toolMatch and type(step.requiredTool)=="table" and tonumber(step.requiredTool.itemID)==tonumber(row.requiredToolItemID)
            end
            if type(row.targetSlot)=="string" then
                targetMatch=targetMatch and tostring(step.targetSlot or ""):upper()==tostring(row.targetSlot):upper()
            end
        end
        if segments and materialMatch and toolMatch and targetMatch and not seenEvidence[id] then
            matches = matches + 1
        else
            mismatches[#mismatches+1] = {
                recipeID = id or "invalid-recipe-id",
                recipePresent = segments ~= nil,
                materials = materialMatch,
                tool = toolMatch,
                target = targetMatch,
            }
        end
        if id then seenEvidence[id]=true end
    end
    local routeCount = #(dataset and (dataset.route or dataset.steps) or {})
    local rowCount = countRows(rows)
    local complete = evidence and evidence.publicComplete == true
        and rowCount == recipeCount
        and matches == recipeCount
        and #mismatches == 0
    local state
    if complete then state = "PUBLIC_CURRENT_CORROBORATED"
    elseif matches > 0 then state = "PUBLIC_CURRENT_PARTIAL"
    else state = "PUBLIC_CURRENT_NOT_CORROBORATED" end
    return {
        state = state,
        complete = complete,
        matchCount = matches,
        rowCount = rowCount,
        routeCount = routeCount,
        recipeCount = recipeCount,
        mismatches = mismatches,
    }
end

local function buildComparison(targetBuild, options)
    options = type(options) == "table" and options or {}
    local svc = buildInfo()
    if not svc then return {state="UNKNOWN",current=false,unknown=true,expectedBuild=targetBuild,clientBuild=nil,clientBuildToken="unknown"} end
    if tonumber(options.buildOverride) then
        local override = tonumber(options.buildOverride)
        return svc:Compare(targetBuild, function() return "test-override", tostring(override), "test", JLP.Constants and JLP.Constants.TARGET_INTERFACE or 16001 end)
    end
    return svc:Compare(targetBuild, options.buildProvider)
end

local function policySatisfied(policy, public, live, lifecycle)
    policy = policy or {}
    live = live or {}
    lifecycle = lifecycle or {}
    if policy.requirePublicComplete and not public.complete then return false, "public-current-evidence-required" end
    if policy.requireTrainerContract and not (lifecycle.trainer and lifecycle.trainer.ready) then return false, "trainer-gate-contract-required" end
    if policy.requireRouteAccessMetadata and not (lifecycle.access and lifecycle.access.metadataComplete) then return false, "route-access-metadata-required" end
    if policy.requireAccessReferenceResolved and not (lifecycle.access and lifecycle.access.referencesResolved) then return false, "route-access-reference-required" end
    -- Client/window observations are optional diagnostics; public Forever source
    -- data and route contracts are the dataset qualification boundary.
    -- Observations never become a hidden validation or promotion requirement.
    return true, nil
end

function Service:AuditProfession(key, options)
    key = tostring(key or ""):upper()
    options = type(options) == "table" and options or {buildOverride=options}
    local dataProvider = provider()
    local dataset = dataProvider and dataProvider:GetRegisteredDataset(key) or nil
    local evidenceRoot = evidenceRegistry()
    local evidence = evidenceRoot and evidenceRoot.professions and evidenceRoot.professions[key] or nil
    if not evidence then
        return {contract=self.rowContract,professionKey=key,state="unsupported-profession-evidence",structuralReady=false,datasetRequalified=false,errors={"evidence-policy-missing"},nativeDispatchAllowed=false,persisted=false}
    end
    if type(dataset) ~= "table" then
        return {contract=self.rowContract,professionKey=key,state="dataset-missing",structuralReady=false,datasetRequalified=false,errors={"dataset-missing"},nativeDispatchAllowed=false,persisted=false}
    end

    local structuralReady, errors, routeCount = structuralAudit(dataset)
    local public = publicEvidenceAudit(dataset, evidence)
    local compare = buildComparison(self.targetBuild, options)
    local datasetBuild = tonumber(dataset.sourceBuild)
    local sourceCurrent = datasetBuild == self.targetBuild
    local live = options.liveEvidence or {}
    local lifecycleService = routeQualification()
    local lifecycle = lifecycleService and lifecycleService:AuditProfession(key, {liveEvidence=live}) or nil
    local idPolicy = JLP:GetModule("PublicIDReferencePolicy")
    local publicIDs = idPolicy and idPolicy:AssessProfession(key) or nil
    local evidenceReady, evidenceBlocker = policySatisfied(evidence.policy, public, live, lifecycle)
    -- Requalification exists specifically to prove that an older captured dataset still
    -- matches the current client. Requiring sourceBuild==targetBuild here would create
    -- a promotion catch-22 and invite callers to rewrite provenance before proof exists.
    -- Source qualification is an advisory dataset review, not an execution
    -- entitlement tied to the running client. A live comparison remains a
    -- separate optional diagnostic, never proof of current server access.
    local sourceReviewed = structuralReady and evidenceReady and public.complete
    local datasetRequalified = sourceReviewed and compare.state=="CURRENT"

    local state
    if not structuralReady then state = "source-structural-blocked"
    elseif not public.complete and not sourceCurrent then state = "source-requalification-required"
    elseif not public.complete then state = "source-public-evidence-incomplete"
    elseif evidenceBlocker then state = "source-reference-evidence-required"
    elseif sourceReviewed then state = "source-reviewed-readonly"
    else state = "source-requalification-required" end

    return {
        contract = self.rowContract,
        professionKey = key,
        state = state,
        structuralReady = structuralReady,
        datasetRequalified = datasetRequalified,
        sourceReviewedReadOnly = sourceReviewed,
        routeCount = routeCount,
        datasetBuild = datasetBuild,
        targetBuild = self.targetBuild,
        buildState = compare.state,
        liveBuild = compare.clientBuild,
        clientBuildToken = compare.clientBuildToken,
        sourceCurrent = sourceCurrent,
        requalifiedFromPriorBuild = datasetRequalified and not sourceCurrent and compare.state=="CURRENT" or false,
        publicEvidenceState = public.state,
        publicComplete = public.complete,
        publicCorroboratedCount = public.matchCount,
        publicEvidenceRowCount = public.rowCount,
        publicRecipeCount = public.recipeCount,
        publicCorroborationMismatches = public.mismatches,
        publicSemanticContract = "recipe-id+exact-reagents+optional-tool+optional-target-v1",
        publicIDValidationState = publicIDs and publicIDs.state or "REFERENCE_POLICY_UNAVAILABLE",
        publicIDMatchAccepted = publicIDs and publicIDs.accepted == true or false,
        clientObservationRequired = false,
        referenceValidationBasis = "WOWHEAD_FOREVER",
        liveIdentityState = live.identityState or "LIVE_EVIDENCE_NOT_OBSERVED",
        liveIdentityMatches = tonumber(live.identityMatches) or 0,
        liveReagentState = live.reagentState or "LIVE_EVIDENCE_NOT_OBSERVED",
        liveReagentMatches = tonumber(live.reagentMatches) or 0,
        liveReagentMismatches = live.reagentMismatches or {},
        liveAccessState = live.accessState or "LIVE_EVIDENCE_NOT_OBSERVED",
        liveAccessMatches = tonumber(live.accessMatches) or 0,
        liveAccessRequiredCount = tonumber(live.accessRequiredCount) or 0,
        routeLifecycleState = lifecycle and lifecycle.state or "ROUTE_LIFECYCLE_UNAVAILABLE",
        trainerQualificationState = lifecycle and lifecycle.trainer and lifecycle.trainer.state or "TRAINER_GATE_CONTRACT_UNAVAILABLE",
        routeAccessQualificationState = lifecycle and lifecycle.access and lifecycle.access.state or "ROUTE_ACCESS_UNAVAILABLE",
        routeAccessMetadataComplete = lifecycle and lifecycle.access and lifecycle.access.metadataComplete == true or false,
        routeAccessReferencesResolved = lifecycle and lifecycle.access and lifecycle.access.referencesResolved == true or false,
        evidenceBlocker = evidenceBlocker,
        evidencePolicy = evidence.policy,
        errors = errors,
        persisted = false,
        nativeDispatchAllowed = false,
    }
end

function Service:AuditAll(options)
    options = type(options) == "table" and options or {buildOverride=options}
    local dataProvider = provider()
    local keys = dataProvider and dataProvider:GetEvidenceDatasetKeys() or {}
    local rows, structural, requalified = {}, 0, 0
    for _, key in ipairs(keys) do
        local row = self:AuditProfession(key, options)
        rows[key] = row
        if row.structuralReady then structural = structural + 1 end
        if row.datasetRequalified then requalified = requalified + 1 end
    end
    return {
        contract = self.contract,
        targetBuild = self.targetBuild,
        rows = rows,
        structuralReadyCount = structural,
        datasetRequalifiedCount = requalified,
        nativeDispatchAllowed = false,
        persisted = false,
    }
end

local function schematicMaterials(recipeID)
    if type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.GetRecipeSchematic) ~= "function" then
        return nil, "recipe-schematic-api-unavailable"
    end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" then return nil, "recipe-schematic-unavailable" end
    local out = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local quantity = tonumber(slot.quantityRequired)
        if quantity and quantity > 0 and slot.required ~= false then
            local reagents = slot.reagents or {}
            if #reagents ~= 1 or not tonumber(reagents[1].itemID) then
                return nil, "ambiguous-or-unsupported-reagent-slot"
            end
            out[#out+1] = {tonumber(reagents[1].itemID), quantity}
        end
    end
    return out, nil
end

function Service:AssessOpenProfession()
    local api = JLP:GetModule("ProfessionAPI")
    local key, openSkillLineID, openDisplayName, professionIdentitySource
    if api and api.GetOpenProfessionKey then
        key, openSkillLineID, openDisplayName, professionIdentitySource = api:GetOpenProfessionKey()
    end
    local out = {
        contract = self.liveContract,
        professionKey = key,
        openSkillLineID = tonumber(openSkillLineID),
        openDisplayName = openDisplayName,
        professionIdentitySource = professionIdentitySource,
        state = "LIVE_EVIDENCE_NOT_OBSERVED",
        identityState = "LIVE_EVIDENCE_NOT_OBSERVED",
        reagentState = "LIVE_EVIDENCE_NOT_OBSERVED",
        accessState = "LIVE_ACCESS_NOT_REQUIRED",
        identityMatches = 0,
        reagentMatches = 0,
        accessMatches = 0,
        accessRequiredCount = 0,
        learnedMatches = 0,
        identityMismatches = {},
        reagentMismatches = {},
        accessMismatches = {},
        observationRows = {},
        nativeDispatchAllowed = false,
        persisted = false,
    }
    local evidenceRoot = evidenceRegistry()
    local professionEvidence = key and evidenceRoot and evidenceRoot.professions and evidenceRoot.professions[key] or nil
    if not professionEvidence then return out end
    if professionIdentitySource ~= "skill-line-id" then
        out.state = "LIVE_PROFESSION_IDENTITY_UNSTABLE"
        return out
    end
    if professionEvidence.policy and professionEvidence.policy.requireLiveAccess then
        out.accessState = "LIVE_ACCESS_NOT_OBSERVED"
    end

    local compare = buildComparison(self.targetBuild)
    out.buildState = compare.state
    out.liveBuild = compare.clientBuild
    -- Observe the actually opened profession on every client build. Reference
    -- provenance cannot be used as a shortcut for live learned/reagent checks.
    out.sourceBuildRelation = compare.state=="CURRENT" and "MATCH" or
        (compare.state=="DRIFT" and "HISTORICAL_REFERENCE" or "UNKNOWN")

    -- Historical 70245 dataset comparison remains read-only. Live recipe
    -- identity, learned status, and panel stability have ONE owner: ProfessionAPI.
    if not api or type(api.GetOpenProfessionContext)~="function" or
        type(api.GetRecipeContext)~="function" then
        out.state="UNIFIED_PROFESSION_API_UNAVAILABLE";return out
    end
    local firstPanel=api:GetOpenProfessionContext()
    if not firstPanel or firstPanel.verified~=true or
        firstPanel.professionKey~=key or
        tonumber(firstPanel.baseSkillLineID)~=tonumber(openSkillLineID) then
        out.state="LIVE_PROFESSION_CONTEXT_UNVERIFIED";return out
    end
    local function stablePanel()
        local now=api:GetOpenProfessionContext()
        return now and now.verified==true and
            now.clientBuildToken==firstPanel.clientBuildToken and
            now.panelToken==firstPanel.panelToken and
            now.panelRevision==firstPanel.panelRevision and
            now.characterKey==firstPanel.characterKey
    end
    local function revokeChangedPanel()
        -- A partial scan may have counted positive rows before a later API
        -- callback changed the session. None of those rows remain live proof.
        out.state="LIVE_PROFESSION_CONTEXT_CHANGED"
        out.identityState="LIVE_EVIDENCE_UNVERIFIED"
        out.reagentState="LIVE_EVIDENCE_UNVERIFIED"
        out.accessState="LIVE_EVIDENCE_UNVERIFIED"
        out.identityMatches=0;out.reagentMatches=0
        out.learnedMatches=0;out.accessMatches=0
        out.observationRows={}
        return out
    end
    local dataProvider=provider()
    local dataset=dataProvider and dataProvider:GetRegisteredDataset(key) or nil
    local route=dataset and (dataset.route or dataset.steps) or {}
    local reg=JLP:GetModule("ProfessionRegistry")
    local expectedSkillLineID=reg and reg:GetSkillLineID(key) or nil
    if not stablePanel() then return revokeChangedPanel() end
    for index, step in ipairs(route) do
        if not stablePanel() then return revokeChangedPanel() end
        local id=tonumber(step.recipeID)
        local context=id and api:GetRecipeContext(id,key) or nil
        if not stablePanel() then return revokeChangedPanel() end
        local visibleMatch=context and context.visible==true or false
        -- Source-70245 requalification historically requires an exact base
        -- skill line. The 70450 lineage table belongs to a DIFFERENT source
        -- epoch and must never silently enlarge 70245's identity contract.
        local observedLineID=context and context.recipeSkillLineID or nil
        local lineageAllowed=context and context.verified==true and
            (context.lineage=="EXACT_BASE_MATCH" or context.lineage=="VERIFIED_DESCENDANT_MATCH")
        local lineMatch=(tonumber(self.targetBuild)==70450 and lineageAllowed) or
            (context and context.verified==true and observedLineID==tonumber(expectedSkillLineID)) or false
        -- A missing optional lineage API leaves a valid observation, but
        -- does not establish route identity authority.
        local lineReason=lineMatch and nil or
            (context and context.reason or "recipe-context-unavailable")
        local identityMatch=visibleMatch and lineMatch
        if identityMatch then
            out.identityMatches = out.identityMatches + 1
        else
            out.identityMismatches[#out.identityMismatches+1] = {recipeID=id or "missing-id", reason=lineReason, observedSkillLineID=observedLineID, expectedSkillLineID=expectedSkillLineID}
        end

        local learned=context and context.verified==true and context.learned==true or false
        if learned then out.learnedMatches=out.learnedMatches+1 end

        local observation = {
            routeIndex=index, recipeID=id, identityMatch=identityMatch, visible=visibleMatch,
            observedSkillLineID=observedLineID, expectedSkillLineID=expectedSkillLineID,
            expectedMaterials=step.materials, learned=learned, sourceRequirement=step.sourceRequirement,
        }
        out.observationRows[#out.observationRows+1] = observation
    end
    if not stablePanel() then return revokeChangedPanel() end
    out.routeCount = #route
    out.identityState = (#route > 0 and out.identityMatches == #route) and "LIVE_RECIPE_IDENTITY_CORROBORATED" or "LIVE_RECIPE_IDENTITY_PARTIAL"

    if out.identityState == "LIVE_RECIPE_IDENTITY_CORROBORATED" then
        for index, step in ipairs(route) do
            local id = tonumber(step.recipeID)
            local mats, reason = schematicMaterials(id)
            local reagentMatch = mats and sameMaterials(step.materials, mats) or false
            local observation = out.observationRows[index]
            if observation then
                observation.observedMaterials = mats
                observation.reagentMatch = reagentMatch
                observation.reagentReason = reason
            end
            if reagentMatch then
                out.reagentMatches = out.reagentMatches + 1
            else
                out.reagentMismatches[#out.reagentMismatches+1] = {recipeID=id, reason=reason or "reagent-mismatch"}
            end
        end
    end
    if not stablePanel() then return revokeChangedPanel() end
    out.reagentState = (#route > 0 and out.reagentMatches == #route) and "LIVE_REAGENT_CORROBORATED" or "LIVE_REAGENT_PARTIAL"

    local accessModule = JLP:GetModule("RecipeAccessEvidence")
    for index, step in ipairs(route) do
        local requirement = step.sourceRequirement
        if type(requirement) == "table" then
            out.accessRequiredCount = out.accessRequiredCount + 1
            local observation = out.observationRows[index]
            local satisfied = observation and observation.learned == true or false
            local liveSourceObserved = false
            if not satisfied and accessModule and accessModule.Resolve then
                local access = accessModule:Resolve(requirement.kind, requirement.name, requirement.itemID)
                liveSourceObserved = access and access.liveVerified == true or false
                satisfied = liveSourceObserved
            end
            if observation then
                observation.accessSatisfied = satisfied
                observation.liveAccessSourceObserved = liveSourceObserved
            end
            if satisfied then
                out.accessMatches = out.accessMatches + 1
            else
                out.accessMismatches[#out.accessMismatches+1] = {recipeID=tonumber(step.recipeID), requirement=requirement}
            end
        end
    end
    if out.accessRequiredCount > 0 then
        out.accessState = out.accessMatches == out.accessRequiredCount and "LIVE_ACCESS_CORROBORATED" or "LIVE_ACCESS_PARTIAL"
    else
        out.accessState = "LIVE_ACCESS_NOT_REQUIRED"
    end

    if not stablePanel() then return revokeChangedPanel() end
    local accessReady = not (professionEvidence.policy and professionEvidence.policy.requireLiveAccess) or out.accessState == "LIVE_ACCESS_CORROBORATED"
    out.state = (out.identityState == "LIVE_RECIPE_IDENTITY_CORROBORATED" and out.reagentState == "LIVE_REAGENT_CORROBORATED" and accessReady)
        and "LIVE_CURRENT_BUILD_CORROBORATED" or "LIVE_CURRENT_BUILD_PARTIAL"
    out.clientBuildToken = firstPanel.clientBuildToken
    out.panelToken=firstPanel.panelToken
    out.panelRevision=firstPanel.panelRevision
    local lifecycleService = routeQualification()
    out.lifecycle = lifecycleService and lifecycleService:AuditProfession(key,{liveEvidence=out}) or nil
    out.audit = self:AuditProfession(key, {liveEvidence=out})
    if not stablePanel() then return revokeChangedPanel() end
    return out
end

function Service:GetSummary()
    local live = self:AssessOpenProfession()
    local all = self:AuditAll()
    if live.professionKey and all.rows[live.professionKey] then
        all.rows[live.professionKey] = self:AuditProfession(live.professionKey, {liveEvidence=live})
    end
    local client = buildInfo() and buildInfo():Read() or nil
    local parts = {string.format("Current-build requalification %d · client %s", self.targetBuild, tostring(client and client.token or "forever:unknown|interface:unknown"))}
    local dataProvider = provider()
    for _, key in ipairs(dataProvider and dataProvider:GetEvidenceDatasetKeys() or {}) do
        local row = all.rows[key]
        parts[#parts+1] = string.format("%s %s (source %s, build %s, public %d/%d, lifecycle %s, live-id %s, live-reagents %s, live-access %s)",
            key, tostring(row.state), tostring(row.datasetBuild), tostring(row.buildState),
            tonumber(row.publicCorroboratedCount) or 0, tonumber(row.publicEvidenceRowCount) or 0, tostring(row.routeLifecycleState),
            tostring(row.liveIdentityState), tostring(row.liveReagentState), tostring(row.liveAccessState))
    end
    parts[#parts+1] = "native dispatch forbidden"
    return table.concat(parts, " · ")
end

function Service:ValidateStaticDatasets()
    local errors = {}
    local all = self:AuditAll({buildOverride=self.targetBuild})
    for key, row in pairs(all.rows or {}) do
        if not row.structuralReady then errors[#errors+1] = "structural:"..key end
        if row.publicCorroboratedCount ~= row.publicEvidenceRowCount then errors[#errors+1] = "public-evidence-mismatch:"..key end
    end
    local registry = evidenceRegistry()
    for key, professionEvidence in pairs(registry and registry.professions or {}) do
        if tonumber(professionEvidence.build) ~= self.targetBuild then
            errors[#errors+1] = "evidence-build:"..tostring(key)
        end
        local seenEvidenceKeys = {}
        for index, row in ipairs(professionEvidence.rows or {}) do
            if tonumber(row.capturedBuild) ~= self.targetBuild then errors[#errors+1] = "evidence-row-build:"..tostring(key)..":"..index end
            if type(row.sourceKey) ~= "string" or not (registry.sources and registry.sources[row.sourceKey]) then errors[#errors+1] = "evidence-source:"..tostring(key)..":"..index end
            if type(row.evidenceKey) ~= "string" or row.evidenceKey == "" then errors[#errors+1] = "evidence-key:"..tostring(key)..":"..index end
            if seenEvidenceKeys[row.evidenceKey] then errors[#errors+1] = "duplicate-evidence-key:"..tostring(key)..":"..index end
            seenEvidenceKeys[row.evidenceKey] = true
        end
    end
    local expectedPublic = {TAILORING=21, ENCHANTING=8, ALCHEMY=13}
    for key, expected in pairs(expectedPublic) do
        local row = all.rows[key]
        if not row or row.publicComplete ~= true or row.publicCorroboratedCount ~= expected or row.publicEvidenceRowCount ~= expected then
            errors[#errors+1] = string.lower(key).."-public-evidence-not-linked"
        end
    end
    return errors
end

-- P1-178: separate optional read-only route/recipe status. The existing
-- AuditProfession and AssessOpenProfession stay STRICT and are not changed.
-- A matching current-client recipe never promotes a reference-build dataset.
function Service:AssessOpenProfessionReadOnly(maxRecipes)
    maxRecipes=maxRecipes==nil and 12 or maxRecipes
    if type(maxRecipes)~="number" or maxRecipes<1 or maxRecipes>12 or
        maxRecipes~=math.floor(maxRecipes) then
        return nil,"INVALID_SCAN_LIMIT" end
    local out={contract="volatile-reference-route-preview-v1",
        state="UNVERIFIED",readOnly=true,observed=false,
        nativeDispatchAllowed=false,productionAuthority=false,
        executionEligible=false,plannerHandoffEligible=false,
        datasetRequalified=false,sourceReviewedReadOnly=false,
        persistentReceiptEligible=false,rows={},errors={},scanned=0,
        matched=0,learned=0,complete=false}
    local api=JLP:GetModule("ProfessionAPI")
    local client=JLP:GetModule("ClientRecipeEvidence")
    if not api or type(api.GetReadOnlyProfessionObservation)~="function" or
        not client or type(client.ObserveReadOnly)~="function" then
        out.reason="VOLATILE_OBSERVATION_API_UNAVAILABLE";return out end
    local first=api:GetReadOnlyProfessionObservation()
    if not first or first.observed~=true then
        out.reason=first and first.reason or "READ_ONLY_PANEL_UNVERIFIED"
        return out end
    local datasetProvider=provider()
    local dataset=datasetProvider and datasetProvider.GetRegisteredDataset and
        datasetProvider:GetRegisteredDataset(first.professionKey) or nil
    if type(dataset)~="table" then out.reason="REFERENCE_DATASET_UNAVAILABLE";return out end
    out.professionKey=first.professionKey
    out.observationQuality=first.observationQuality
    out.referenceSourceBuild=dataset.sourceBuild
    local seen={}
    for _,step in ipairs(dataset.route or dataset.steps or {}) do
        if out.scanned>=maxRecipes then break end
        local id=step.recipeID
        if type(id)=="number" and id>0 and id==math.floor(id) and
           id<2147483648 and not seen[id] then
            seen[id]=true
            out.scanned=out.scanned+1
            local row,why=client:ObserveReadOnly(first.professionKey,id,dataset.sourceBuild)
            if row then
                out.matched=out.matched+1
                if row.learned then out.learned=out.learned+1 end
                out.rows[#out.rows+1]={recipeID=id,name=row.name,learned=row.learned,
                    observationQuality=row.observationQuality,readOnly=true,
                    nativeDispatchAllowed=false,referenceSourceBuild=dataset.sourceBuild}
            else
                out.errors[#out.errors+1]={recipeID=id,reason=why}
            end
        end
    end
    local last=api:GetReadOnlyProfessionObservation()
    if not last or last.observed~=true or
        last.professionKey~=first.professionKey or
        last.characterKey~=first.characterKey or
        last.observationToken~=first.observationToken or
        last.skill~=first.skill or last.maxSkill~=first.maxSkill or
        last.observationQuality~=first.observationQuality or
        last.clientBuild~=first.clientBuild then
        out.rows={};out.errors={};out.scanned=0;out.matched=0;out.learned=0
        out.reason="READ_ONLY_PANEL_CHANGED_DURING_SCAN";return out
    end
    out.observed=true
    out.state=#out.errors==0 and "VOLATILE_REFERENCE_PREVIEW" or "VOLATILE_PARTIAL"
    out.reason="LIVE_REFERENCE_PREVIEW_READ_ONLY"
    return out
end
JLP:RegisterModule("BuildRequalificationService", Service)
