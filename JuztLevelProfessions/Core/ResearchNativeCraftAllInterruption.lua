local _, JLP = ...

-- Alpha88 gives strict research Craft All a deterministic interruption matrix.
-- It does not authorize or dispatch crafting. It only classifies why the next
-- single-ordinal continuation was blocked and records a stable, recipe-local
-- stop reason for diagnostics / Guide handoff / regression coverage.
local ResearchNativeCraftAllInterruption = {
    contract = "strict-current-recipe-craft-all-interruption-matrix-v1",
    interruptionContract = "research-current-recipe-craft-all-interruption-v1",
    productionTailoringInterruptionContract = "production-tailoring-current-recipe-craft-all-interruption-v1",
    productionTailoringProvenanceContract = "production-tailoring-native-craft-all-provenance-v1",
    authority = "post-confirmation-no-dispatch-classification-only",
    automaticRouteAdvance = false,
    automaticResume = false,
    persisted = false,
    serial = 0,
    lastByProfession = {},
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function copy(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end
    return out
end

local function classifyState(state, detail)
    state = tostring(state or "")
    detail = tostring(detail or "")
    if state == "strict-craft-all-target-reached" then return "TARGET_REACHED", "Target skill reached" end
    if state == "strict-craft-all-initial-budget-exhausted" then return "MATERIALS", "Initial exact-recipe material budget exhausted" end
    if state == "strict-craft-all-current-recipe-materials-exhausted" then return "MATERIALS", "Exact current-recipe materials exhausted" end
    if state == "strict-craft-all-profession-window-lost" then return "WINDOW_LOST", "Profession window is no longer open" end
    if state == "strict-craft-all-build-drift" then return "BUILD_CHANGED", "Forever client build changed" end
    if state == "strict-craft-all-authority-disabled" then return "AUTHORITY_REVOKED", "Research Craft All authority was revoked" end
    if state == "strict-craft-all-transaction-not-current" then return "TRANSACTION_CHANGED", "Craft All transaction is no longer current" end
    if state == "strict-craft-all-recipe-lock-invalid" then return "RECIPE_LOCK", "Exact recipe lock no longer matches" end
    if state == "strict-craft-all-pending-invalid" then return "PENDING_INVALID", "Strict Craft All pending contract is invalid" end
    if state == "strict-craft-all-native-dispatch-failed" then return "API_FAILURE", detail ~= "" and detail or "Native CraftRecipe dispatch failed" end
    if state == "strict-craft-all-ordinal-authorization-stale" then return "STALE_AUTHORIZATION", "Ordinal authorization became stale before dispatch" end
    if state == "strict-craft-all-ordinal-authorization-tampered" then return "TAMPERED_AUTHORIZATION", "Ordinal authorization identity mismatch" end
    if state == "strict-craft-all-ordinal-authorization-expired-or-unknown" then return "AUTHORIZATION_EXPIRED", "Ordinal authorization expired or is unknown" end
    if state == "reload-no-resume" then return "RELOAD_NO_RESUME", "Reload recovery settles confirmed progress only; Craft All never auto-resumes" end
    if state:find("material",1,true) then return "MATERIALS", detail ~= "" and detail or state end
    if state:find("window",1,true) then return "WINDOW_LOST", detail ~= "" and detail or state end
    if state:find("build",1,true) then return "BUILD_CHANGED", detail ~= "" and detail or state end
    if state:find("authority",1,true) or state:find("feature",1,true) then return "AUTHORITY_REVOKED", detail ~= "" and detail or state end
    return "OTHER", detail ~= "" and detail or (state ~= "" and state or "Unknown strict Craft All interruption")
end

function ResearchNativeCraftAllInterruption:Record(professionKey, state, detail, pending, source)
    professionKey = normalizeKey(professionKey or pending and pending.key) or "UNKNOWN"
    local category, description = classifyState(state, detail)
    local provenance = type(pending) == "table" and type(pending.authorityProvenance) == "table" and pending.authorityProvenance or nil
    local provenanceContract = type(provenance) == "table" and tostring(provenance.contract or "") or ""
    local interruptionContract = provenanceContract == self.productionTailoringProvenanceContract
        and self.productionTailoringInterruptionContract or self.interruptionContract
    self.serial = (tonumber(self.serial) or 0) + 1
    local row = {
        contract = self.contract,
        interruptionContract = interruptionContract,
        authority = self.authority,
        professionKey = professionKey,
        state = tostring(state or "unknown"),
        category = category,
        detail = description,
        source = tostring(source or "strict-orchestrator"),
        provenanceContract = provenanceContract ~= "" and provenanceContract or nil,
        authorityContract = provenance and provenance.authorityContract or nil,
        boundaryContract = provenance and provenance.boundaryContract or nil,
        interruptionToken = "craftall-interruption-" .. tostring(self.serial),
        recordedAt = type(GetTime) == "function" and GetTime() or nil,
        ledgerID = pending and (pending.ledgerID or pending.transactionID) or nil,
        recipe = pending and pending.recipeName or provenance and provenance.recipe or nil,
        recipeID = tonumber(pending and pending.recipeID or provenance and provenance.recipeID),
        routeIndex = tonumber(provenance and provenance.routeIndex),
        targetSkill = tonumber(pending and pending.targetSkill or provenance and provenance.skillTarget),
        startedSkill = tonumber(pending and pending.startedSkill or provenance and provenance.startedSkill),
        currentBuild = tonumber(provenance and provenance.currentBuild),
        snapshotToken = provenance and provenance.snapshotToken or nil,
        stateFingerprint = provenance and provenance.stateFingerprint or nil,
        completedCount = tonumber(pending and pending.completedCount) or 0,
        requestedCount = tonumber(pending and pending.requestedCount) or 0,
        nativeDispatchPerOrdinal = 1,
        automaticRouteAdvance = false,
        automaticResume = false,
        persisted = false,
    }
    self.lastByProfession[professionKey] = row
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("RESEARCH_CRAFT_ALL_INTERRUPTION_UPDATED", copy(row)) end
    return row
end

function ResearchNativeCraftAllInterruption:Classify(state, detail)
    local category, description = classifyState(state, detail)
    return category, description
end

function ResearchNativeCraftAllInterruption:GetLast(professionKey)
    local row = self.lastByProfession[normalizeKey(professionKey)]
    return row and copy(row) or nil
end

function ResearchNativeCraftAllInterruption:GetSummary(professionKey)
    professionKey = normalizeKey(professionKey) or "ENGINEERING"
    local last = self:GetLast(professionKey)
    local lines = {
        (last and last.provenanceContract == self.productionTailoringProvenanceContract) and "PRODUCTION TAILORING CRAFT ALL / INTERRUPTION-RECOVERY MATRIX" or "RESEARCH CRAFT ALL / INTERRUPTION-RECOVERY MATRIX",
        professionKey,
        "Contract: " .. self.contract,
        "Authority: " .. self.authority,
        "Native dispatch: one ordinal at a time",
        "Recipe policy: exact original recipe only",
        "Automatic route advance: disabled",
        "Automatic resume after reload: disabled",
        "Persistence: none",
        "Last interruption: " .. tostring(last and last.category or "none"),
    }
    if last then
        lines[#lines+1] = "State: " .. tostring(last.state)
        lines[#lines+1] = "Detail: " .. tostring(last.detail)
        lines[#lines+1] = "Recipe: " .. tostring(last.recipe or "unknown") .. " / " .. tostring(last.recipeID or "unresolved")
        lines[#lines+1] = "Progress: " .. tostring(last.completedCount or 0) .. " / " .. tostring(last.requestedCount or 0)
    end
    return table.concat(lines, "\n")
end

function ResearchNativeCraftAllInterruption:Initialize()
    if self.initialized then return true end
    self.initialized = true
    if JLP.EventBus and JLP.EventBus.On then
        JLP.EventBus:On("TRANSACTION_RECOVERY_UPDATED", function(status)
            local provenance = status and status.authorityProvenance
            local recoveryState = tostring(status and status.state or "")
            local recoveredTerminal = status and status.terminal == true
                and (recoveryState == "RECOVERED_SUCCESS" or recoveryState == "RECOVERED_PARTIAL" or recoveryState == "RECOVERED_FAILED" or recoveryState == "ABORTED_UNKNOWN")
            if type(provenance) == "table" and (provenance.contract == "research-native-craft-all-provenance-v1" or provenance.contract == "production-tailoring-native-craft-all-provenance-v1") and recoveredTerminal then
                self:Record(provenance.professionKey, "reload-no-resume", nil, {
                    key=provenance.professionKey, recipeName=provenance.recipe, recipeID=provenance.recipeID,
                    targetSkill=provenance.skillTarget, startedSkill=provenance.startedSkill,
                    completedCount=status.confirmedCount, requestedCount=status.requestedCount,
                    ledgerID=status.ledgerID, transactionID=status.ledgerID, authorityProvenance=provenance,
                }, "transaction-recovery")
            end
        end)
    end
    return true
end

function ResearchNativeCraftAllInterruption:Validate()
    local errors, warnings = {}, {}
    if self.automaticRouteAdvance ~= false or self.automaticResume ~= false or self.persisted ~= false then
        errors[#errors+1] = "strict Craft All interruption boundary invalid"
    end
    if self.productionTailoringInterruptionContract ~= "production-tailoring-current-recipe-craft-all-interruption-v1" then
        errors[#errors+1] = "production Tailoring Craft All interruption contract invalid"
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ResearchNativeCraftAllInterruption", ResearchNativeCraftAllInterruption)
