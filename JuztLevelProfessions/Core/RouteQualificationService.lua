local _, JLP = ...

-- Read-only qualification of route lifecycle metadata that is deliberately kept
-- separate from recipe/reagent current-build corroboration. This service does
-- not grant Planner or native execution authority.
local Service = {
    contract = "route-qualification-service-v1",
    trainerContract = "route-trainer-gate-contract-v1",
    accessContract = "route-recipe-access-contract-v1",
    nativeDispatchAllowed = false,
    persisted = false,
}

local EXPECTED_TRAINER_GATES = {
    {cap=75, nextCap=150, requiredSkill=50},
    {cap=150, nextCap=225, requiredSkill=125},
    {cap=225, nextCap=300, requiredSkill=200},
}

local function provider()
    return JLP:GetModule("ProfessionDatasetProvider")
end

local function accessEvidence()
    return JLP:GetModule("RecipeAccessEvidence")
end

local function routeFor(dataset)
    return dataset and (dataset.route or dataset.steps) or {}
end

local function trainerAudit(dataset)
    local gates = dataset and dataset.trainerGates or {}
    local errors = {}
    local expected = tonumber(dataset and dataset.skillMax) == 300 and EXPECTED_TRAINER_GATES or nil
    if expected then
        if #gates ~= #expected then
            errors[#errors+1] = "trainer-gate-count"
        end
        for i, wanted in ipairs(expected) do
            local gate = gates[i]
            if type(gate) ~= "table" then
                errors[#errors+1] = "trainer-gate-missing:"..i
            else
                if tonumber(gate.cap) ~= wanted.cap then errors[#errors+1] = "trainer-cap:"..i end
                if tonumber(gate.nextCap) ~= wanted.nextCap then errors[#errors+1] = "trainer-next-cap:"..i end
                if tonumber(gate.requiredSkill) ~= wanted.requiredSkill then errors[#errors+1] = "trainer-required-skill:"..i end
                if not tonumber(gate.minCharacterLevel) or tonumber(gate.minCharacterLevel) < 1 then errors[#errors+1] = "trainer-character-level:"..i end
                if i > 1 and tonumber(gates[i-1].minCharacterLevel or 0) > tonumber(gate.minCharacterLevel or 0) then
                    errors[#errors+1] = "trainer-character-level-order:"..i
                end
            end
        end
    else
        for i, gate in ipairs(gates) do
            if not tonumber(gate.cap) or not tonumber(gate.nextCap) or not tonumber(gate.requiredSkill) then
                errors[#errors+1] = "trainer-gate-shape:"..i
            end
        end
    end
    return {
        contract = Service.trainerContract,
        state = #errors == 0 and "TRAINER_GATE_CONTRACT_VALID" or "TRAINER_GATE_CONTRACT_INVALID",
        ready = #errors == 0,
        gateCount = #gates,
        errors = errors,
    }
end

local function liveRowsByRecipe(liveEvidence)
    local out = {}
    for _, row in ipairs(type(liveEvidence) == "table" and liveEvidence.observationRows or {}) do
        if tonumber(row.recipeID) then out[tonumber(row.recipeID)] = row end
    end
    return out
end

local function targetEvidenceBuild()
    return tonumber(JLP.data and JLP.data.currentBuildEvidence and JLP.data.currentBuildEvidence.targetBuild)
end

local function hasReferenceEligibleSource(reference)
    if type(reference) ~= "table" or reference.conflict then return false end
    for _, source in ipairs(reference.sources or {}) do
        if source.referenceEligible == true then return true end
    end
    return false
end

local function accessAudit(dataset, liveEvidence)
    local access = accessEvidence()
    local liveByRecipe = liveRowsByRecipe(liveEvidence)
    local required, metadataExact, referenceLinked, referenceResolved, liveSatisfied = 0, 0, 0, 0, 0
    local rows, mismatches = {}, {}

    for index, step in ipairs(routeFor(dataset)) do
        if step.recipeSource or step.sourceRequirement then
            required = required + 1
            local requirement = step.sourceRequirement
            local exact = type(requirement) == "table"
                and type(requirement.kind) == "string" and requirement.kind ~= ""
                and type(requirement.name) == "string" and requirement.name ~= ""
                and tonumber(requirement.itemID) ~= nil
            if exact then metadataExact = metadataExact + 1 end

            local reference = nil
            if exact and access and access.GetReference then
                reference = access:GetReference(requirement.kind, requirement.name, requirement.itemID)
            end
            local linked = reference ~= nil and tonumber(reference.itemID) == tonumber(requirement and requirement.itemID)
            if linked then referenceLinked = referenceLinked + 1 end
            local expectedEvidenceBuild = targetEvidenceBuild()
            local capturedBuild = reference and tonumber(reference.capturedBuild) or nil
            local referenceBuildCurrent = linked and expectedEvidenceBuild ~= nil and capturedBuild == expectedEvidenceBuild
            local resolved = referenceBuildCurrent and hasReferenceEligibleSource(reference)
            if resolved then referenceResolved = referenceResolved + 1 end

            local liveRow = liveByRecipe[tonumber(step.recipeID)]
            local learned = liveRow and liveRow.learned == true or false
            local liveSource = false
            if exact and access and access.Resolve then
                local resolution = access:Resolve(requirement.kind, requirement.name, requirement.itemID)
                liveSource = resolution and resolution.liveVerified == true or false
            end
            local liveOK = learned or liveSource
            if liveOK then liveSatisfied = liveSatisfied + 1 end

            local row = {
                routeIndex = index,
                recipeID = tonumber(step.recipeID),
                recipe = step.recipe,
                recipeSource = step.recipeSource,
                requirement = requirement,
                metadataExact = exact,
                referenceLinked = linked,
                referenceCapturedBuild = capturedBuild,
                referenceTargetBuild = expectedEvidenceBuild,
                referenceBuildCurrent = referenceBuildCurrent,
                referenceResolved = resolved,
                liveLearned = learned,
                liveSourceObserved = liveSource,
                liveSatisfied = liveOK,
            }
            rows[#rows+1] = row
            if not exact or not linked or not resolved then
                mismatches[#mismatches+1] = row
            end
        end
    end

    local metadataComplete = required == metadataExact and required == referenceLinked
    local referencesResolved = required == referenceResolved
    local liveComplete = required == 0 or required == liveSatisfied
    local state
    if required == 0 then state = "ROUTE_ACCESS_NOT_REQUIRED"
    elseif not metadataComplete then state = "ROUTE_ACCESS_METADATA_PARTIAL"
    elseif not referencesResolved then state = "ROUTE_ACCESS_REFERENCE_PARTIAL"
    elseif liveEvidence and not liveComplete then state = "ROUTE_ACCESS_LIVE_PARTIAL"
    elseif liveEvidence and liveComplete then state = "ROUTE_ACCESS_LIVE_CORROBORATED"
    else state = "ROUTE_ACCESS_REFERENCE_READY" end

    return {
        contract = Service.accessContract,
        state = state,
        requiredCount = required,
        metadataExactCount = metadataExact,
        referenceLinkedCount = referenceLinked,
        referenceResolvedCount = referenceResolved,
        liveSatisfiedCount = liveSatisfied,
        metadataComplete = metadataComplete,
        referencesResolved = referencesResolved,
        liveComplete = liveComplete,
        rows = rows,
        mismatches = mismatches,
    }
end

function Service:AuditProfession(key, options)
    key = tostring(key or ""):upper()
    options = type(options) == "table" and options or {}
    local dataProvider = provider()
    local dataset = dataProvider and dataProvider:GetRegisteredDataset(key) or nil
    if type(dataset) ~= "table" then
        return {
            contract=self.contract, professionKey=key, state="ROUTE_DATASET_MISSING",
            trainer={state="TRAINER_GATE_CONTRACT_INVALID",ready=false,errors={"dataset-missing"}},
            access={state="ROUTE_ACCESS_METADATA_PARTIAL",metadataComplete=false,referencesResolved=false},
            nativeDispatchAllowed=false, persisted=false,
        }
    end
    local trainer = trainerAudit(dataset)
    local access = accessAudit(dataset, options.liveEvidence)
    local ready = trainer.ready and access.metadataComplete and access.referencesResolved
    return {
        contract = self.contract,
        professionKey = key,
        state = ready and "ROUTE_LIFECYCLE_QUALIFIED" or "ROUTE_LIFECYCLE_INCOMPLETE",
        ready = ready,
        trainer = trainer,
        access = access,
        nativeDispatchAllowed = false,
        persisted = false,
    }
end

function Service:Validate()
    local errors = {}
    local dataProvider = provider()
    for _, key in ipairs(dataProvider and dataProvider:GetEvidenceDatasetKeys() or {}) do
        local row = self:AuditProfession(key)
        if not row.trainer.ready then errors[#errors+1] = "trainer:"..key end
        if not row.access.metadataComplete then errors[#errors+1] = "access-metadata:"..key end
    end
    return errors
end

function Service:GetSummary(key)
    if key then
        local row = self:AuditProfession(key)
        return string.format("Route qualification %s · %s · trainer %s · access %s (%d/%d exact, %d/%d resolved) · native dispatch forbidden",
            tostring(row.professionKey), tostring(row.state), tostring(row.trainer.state), tostring(row.access.state),
            tonumber(row.access.metadataExactCount) or 0, tonumber(row.access.requiredCount) or 0,
            tonumber(row.access.referenceResolvedCount) or 0, tonumber(row.access.requiredCount) or 0)
    end
    local parts = {"Route lifecycle qualification"}
    local dataProvider = provider()
    for _, professionKey in ipairs(dataProvider and dataProvider:GetEvidenceDatasetKeys() or {}) do
        local row = self:AuditProfession(professionKey)
        parts[#parts+1] = string.format("%s %s access %d/%d", professionKey, row.state, tonumber(row.access.referenceResolvedCount) or 0, tonumber(row.access.requiredCount) or 0)
    end
    parts[#parts+1] = "native dispatch forbidden"
    return table.concat(parts, " · ")
end

JLP:RegisterModule("RouteQualificationService", Service)
