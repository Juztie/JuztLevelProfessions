local _, JLP = ...

-- Alpha87 replaces the native multi-count research Craft All dispatch with a
-- strict one-ordinal-at-a-time orchestrator.  The user still starts one Craft
-- All action and sees one aggregate ledger, but every additional native craft is
-- separately revalidated after the previous ordinal has been confirmed.  The
-- orchestrator is permanently locked to the recipe/target captured at the
-- original click and never consults Planner route advancement for continuation.
local ResearchNativeCraftAllStrictOrchestrator = {
    contract = "strict-target-safe-current-recipe-craft-all-orchestrator-v1",
    ordinalContract = "research-current-recipe-craft-all-ordinal-authorization-v1",
    authority = "in-flight-exact-recipe-single-ordinal-revalidation-only",
    provenanceContract = "research-native-craft-all-provenance-v1",
    nativeDispatchPerOrdinal = 1,
    automaticRouteAdvance = false,
    automaticResume = false,
    persisted = false,
    authorizationTTLSeconds = 3,
    serial = 0,
    authorizations = {},
    lastByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function now()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function currentBuild()
    -- Never manufacture live authority from the historical build baseline.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    return buildInfo and buildInfo:GetBuildNumber() or nil
end

local function copy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function isStrictPending(pending)
    local provenance = pending and pending.authorityProvenance
    local provenanceContract = type(provenance) == "table" and tostring(provenance.contract or "") or ""
    local supportedProvenance = provenanceContract == "research-native-craft-all-provenance-v1"
        or provenanceContract == "production-tailoring-native-craft-all-provenance-v1"
    return type(pending) == "table"
        and pending.mode == "all"
        and (pending.researchNativeCraftAll == true or pending.productionTailoringCraftAll == true)
        and pending.strictTargetSafeCraftAll == true
        and tonumber(pending.nativeDispatchPerOrdinal) == 1
        and type(provenance) == "table"
        and supportedProvenance
        and provenance.recipeLocked == true
        and provenance.automaticRouteAdvance == false
end

local function authorityForPending(pending)
    local provenance = pending and pending.authorityProvenance or nil
    if type(provenance) == "table" and provenance.contract == "production-tailoring-native-craft-all-provenance-v1" then
        return JLP:GetModule("ProductionTailoringCraftAllAuthority")
    end
    return JLP:GetModule("ResearchNativeCraftAllAuthority")
end

local function addGate(model, key, ready, state, detail)
    local row = {key=key,ready=ready and true or false,state=tostring(state or (ready and "pass" or "blocked")),detail=detail}
    model.gates[key] = row
    model.stats.totalGates = model.stats.totalGates + 1
    if row.ready then
        model.stats.passedGates = model.stats.passedGates + 1
    elseif not model.blockedGate then
        model.blockedGate = key
        model.blockedState = row.state
    end
    return row
end

function ResearchNativeCraftAllStrictOrchestrator:_Sweep(nowValue)
    nowValue = tonumber(nowValue) or now()
    for token, row in pairs(self.authorizations or {}) do
        if type(row) ~= "table" or row.consumed == true or (tonumber(row.expiresAt) and nowValue > tonumber(row.expiresAt)) then
            self.authorizations[token] = nil
        end
    end
end

function ResearchNativeCraftAllStrictOrchestrator:_Record(model)
    local key = normalizeKey(model and model.professionKey)
    if key and type(model) == "table" then self.lastByProfession[key] = copy(model) end
    if JLP.EventBus and JLP.EventBus.Emit and type(model) == "table" then
        JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_STRICT_UPDATED", copy(model))
    end
    return model
end

function ResearchNativeCraftAllStrictOrchestrator:Evaluate(pending)
    local provenance = pending and pending.authorityProvenance or nil
    local professionKey = normalizeKey(pending and pending.key or provenance and provenance.professionKey)
    local model = {
        contract=self.contract,ordinalContract=self.ordinalContract,authority=self.authority,
        professionKey=professionKey,recipe=pending and pending.recipeName or provenance and provenance.recipe,
        recipeID=tonumber(pending and pending.recipeID or provenance and provenance.recipeID),
        targetSkill=tonumber(pending and pending.targetSkill or provenance and provenance.skillTarget),
        requestedCount=tonumber(pending and pending.requestedCount or provenance and provenance.requestedCount) or 0,
        completedCount=tonumber(pending and pending.completedCount) or 0,
        nextOrdinal=(tonumber(pending and pending.completedCount) or 0)+1,
        nativeDispatchPerOrdinal=1,automaticRouteAdvance=false,automaticResume=false,persisted=false,
        gates={},stats={totalGates=0,passedGates=0},state="strict-craft-all-ordinal-blocked",
    }

    addGate(model,"pending-contract",isStrictPending(pending),isStrictPending(pending) and "pass" or "strict-craft-all-pending-invalid")

    local authorityModule = authorityForPending(pending)
    local featureReady = authorityModule and authorityModule.IsEffectiveEnabled and authorityModule:IsEffectiveEnabled() or false
    addGate(model,"feature-gates",featureReady,featureReady and "pass" or "strict-craft-all-authority-disabled")

    local build = currentBuild()
    model.currentBuild = build
    local buildReady = tonumber(build) ~= nil and tonumber(provenance and provenance.currentBuild) == tonumber(build)
    addGate(model,"current-build",buildReady,buildReady and "pass" or "strict-craft-all-build-drift")

    local recipeReady = model.recipeID ~= nil and model.recipeID == tonumber(provenance and provenance.recipeID)
        and tostring(model.recipe or "") == tostring(provenance and provenance.recipe or "")
        and provenance and provenance.recipeLocked == true and provenance.automaticRouteAdvance == false
    addGate(model,"recipe-lock",recipeReady,recipeReady and "pass" or "strict-craft-all-recipe-lock-invalid")

    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api.Get and professionKey and api:Get(professionKey) or nil
    local skill = tonumber(profession and profession.skill)
    model.currentSkill = skill
    local targetOpen = skill ~= nil and model.targetSkill ~= nil and skill < model.targetSkill
    addGate(model,"target-open",targetOpen,targetOpen and "pass" or "strict-craft-all-target-reached")

    local budgetReady = model.requestedCount >= 1 and model.completedCount < model.requestedCount
    addGate(model,"ordinal-budget",budgetReady,budgetReady and "pass" or "strict-craft-all-initial-budget-exhausted")

    local crafting = JLP:GetModule("Crafting")
    local craftable,countStatus,countReason
    if crafting and type(crafting.GetCraftableCount)=="function" and model.recipeID then
        craftable,countStatus,countReason=crafting:GetCraftableCount(model.recipeID)
    end
    model.currentRecipeCraftable=craftable
    model.craftabilityStatus=countStatus or "UNKNOWN"
    model.craftabilityReason=countReason or "craftability-module-unavailable"
    local materialsReady=countStatus=="KNOWN" and type(craftable)=="number" and craftable>0
    local craftabilityGate=materialsReady and "pass" or
        (countStatus~="KNOWN" and "strict-craft-all-craftability-unavailable" or "strict-craft-all-current-recipe-materials-exhausted")
    addGate(model,"current-recipe-materials",materialsReady,craftabilityGate)

    local flow = JLP:GetModule("ExecutionFlow")
    local openKey = flow and flow.CaptureProfessionWindow and flow:CaptureProfessionWindow() or nil
    model.professionWindowKey = normalizeKey(openKey)
    local windowReady = professionKey ~= nil and model.professionWindowKey == professionKey
    addGate(model,"profession-window",windowReady,windowReady and "pass" or "strict-craft-all-profession-window-lost")

    local transactionReady = crafting and crafting.pendingCraft == pending and crafting.pendingEnchant == nil
        and pending and pending.repeatStopRequested ~= true
    addGate(model,"transaction-current",transactionReady,transactionReady and "pass" or "strict-craft-all-transaction-not-current")

    if model.stats.passedGates == model.stats.totalGates then
        model.state = "strict-craft-all-ordinal-ready"
        model.ordinalReady = true
    else
        model.ordinalReady = false
        model.state = model.blockedState or "strict-craft-all-ordinal-blocked"
    end
    return model
end

function ResearchNativeCraftAllStrictOrchestrator:PrepareNextOrdinal(pending)
    self:_Sweep(now())
    local model = self:Evaluate(pending)
    self:_Record(model)
    if model.ordinalReady ~= true then return nil, model.state, model end
    self.serial = (tonumber(self.serial) or 0) + 1
    local createdAt = now()
    local token = string.format("craftall-ordinal-%d-%d-%d",self.serial,tonumber(pending.token) or 0,tonumber(model.nextOrdinal) or 0)
    local authorization = {
        contract=self.ordinalContract,token=token,pendingToken=pending.token,ledgerID=pending.ledgerID,
        professionKey=model.professionKey,recipe=model.recipe,recipeID=model.recipeID,targetSkill=model.targetSkill,
        requestedCount=model.requestedCount,expectedCompletedCount=model.completedCount,nextOrdinal=model.nextOrdinal,
        currentSkill=model.currentSkill,currentRecipeCraftable=model.currentRecipeCraftable,currentBuild=model.currentBuild,
        createdAt=createdAt,expiresAt=createdAt+self.authorizationTTLSeconds,singleUse=true,persisted=false,
    }
    self.authorizations[token] = authorization
    return copy(authorization), "strict-craft-all-ordinal-authorized", model
end

function ResearchNativeCraftAllStrictOrchestrator:ValidateOrdinalAuthorization(submitted, pending)
    if type(submitted) ~= "table" or submitted.contract ~= self.ordinalContract then
        return false,"strict-craft-all-ordinal-authorization-invalid",nil,nil
    end
    self:_Sweep(now())
    local stored = self.authorizations[tostring(submitted.token or "")]
    if type(stored) ~= "table" then return false,"strict-craft-all-ordinal-authorization-expired-or-unknown",nil,nil end
    local exact = tostring(submitted.pendingToken or "") == tostring(stored.pendingToken or "")
        and tostring(submitted.ledgerID or "") == tostring(stored.ledgerID or "")
        and tostring(submitted.professionKey or "") == tostring(stored.professionKey or "")
        and tostring(submitted.recipe or "") == tostring(stored.recipe or "")
        and tonumber(submitted.recipeID) == tonumber(stored.recipeID)
        and tonumber(submitted.targetSkill) == tonumber(stored.targetSkill)
        and tonumber(submitted.requestedCount) == tonumber(stored.requestedCount)
        and tonumber(submitted.expectedCompletedCount) == tonumber(stored.expectedCompletedCount)
        and tonumber(submitted.nextOrdinal) == tonumber(stored.nextOrdinal)
        and submitted.singleUse == true and submitted.persisted == false
    if not exact then return false,"strict-craft-all-ordinal-authorization-tampered",nil,copy(stored) end

    local model = self:Evaluate(pending)
    self:_Record(model)
    local current = model.ordinalReady == true
        and tostring(pending and pending.token or "") == tostring(stored.pendingToken or "")
        and tostring(pending and pending.ledgerID or "") == tostring(stored.ledgerID or "")
        and tonumber(model.recipeID) == tonumber(stored.recipeID)
        and tonumber(model.targetSkill) == tonumber(stored.targetSkill)
        and tonumber(model.requestedCount) == tonumber(stored.requestedCount)
        and tonumber(model.completedCount) == tonumber(stored.expectedCompletedCount)
        and tonumber(model.nextOrdinal) == tonumber(stored.nextOrdinal)
        and tonumber(model.currentSkill) == tonumber(stored.currentSkill)
        and tonumber(model.currentRecipeCraftable) == tonumber(stored.currentRecipeCraftable)
        and tonumber(model.currentBuild) == tonumber(stored.currentBuild)
    if not current then return false,"strict-craft-all-ordinal-authorization-stale",model,copy(stored) end
    return true,"strict-craft-all-ordinal-authorization-current",model,copy(stored)
end

function ResearchNativeCraftAllStrictOrchestrator:ConsumeAuthorization(token, reason)
    token = tostring(token or "")
    local row = self.authorizations[token]
    if not row then return false end
    row.consumed = true
    row.consumedReason = tostring(reason or "consumed")
    self.authorizations[token] = nil
    return true
end

function ResearchNativeCraftAllStrictOrchestrator:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ResearchNativeCraftAllStrictOrchestrator:GetSummary(professionKey)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local last = self:GetLast(professionKey)
    local lines = {
        "RESEARCH CRAFT ALL / STRICT TARGET-SAFE ORCHESTRATION",
        professionKey,
        "Contract: " .. self.contract,
        "Ordinal contract: " .. self.ordinalContract,
        "Native dispatch per ordinal: 1",
        "Target check: before every subsequent native dispatch",
        "Recipe policy: exact original recipe only",
        "Planner route advancement: ignored",
        "Automatic resume after reload: disabled",
        "Persistence: none",
        "Last state: " .. tostring(last and last.state or "none"),
    }
    if last then
        lines[#lines+1] = "Progress: " .. tostring(last.completedCount or 0) .. " / " .. tostring(last.requestedCount or 0)
        lines[#lines+1] = "Next ordinal: " .. tostring(last.nextOrdinal or "none")
        lines[#lines+1] = "Current skill / target: " .. tostring(last.currentSkill or "?") .. " / " .. tostring(last.targetSkill or "?")
        lines[#lines+1] = "Current exact-recipe craftable: " .. tostring(last.currentRecipeCraftable ~= nil and last.currentRecipeCraftable or "UNKNOWN")
        lines[#lines+1] = "Gates: " .. tostring(last.stats and last.stats.passedGates or 0) .. " / " .. tostring(last.stats and last.stats.totalGates or 0)
    end
    return table.concat(lines,"\n")
end

function ResearchNativeCraftAllStrictOrchestrator:Validate()
    local errors, warnings = {}, {}
    if self.nativeDispatchPerOrdinal ~= 1 then errors[#errors+1] = "strict Craft All native ordinal count must be exactly one" end
    if self.automaticRouteAdvance ~= false or self.automaticResume ~= false or self.persisted ~= false then
        errors[#errors+1] = "strict Craft All authority boundary invalid"
    end
    for _, name in ipairs({"Crafting","ResearchNativeCraftAllAuthority","ProductionTailoringCraftAllAuthority","ProfessionAPI","ExecutionFlow"}) do
        if not JLP:GetModule(name) then errors[#errors+1] = "strict Craft All dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeCraftAllStrictOrchestrator", ResearchNativeCraftAllStrictOrchestrator)
