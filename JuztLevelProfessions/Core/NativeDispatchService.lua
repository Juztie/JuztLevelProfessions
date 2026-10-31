local _, JLP = ...

-- Alpha119: the single physical boundary for irreversible profession crafting APIs.
-- Callers remain responsible for policy-specific authority/readiness/ledger/recovery
-- setup, while this service enforces a uniform DispatchIntent shape immediately
-- before entering the client API. No UI or planner module may call CraftRecipe or
-- CraftEnchant directly after this promotion.
-- Native dispatch has no batch-specific entitlement toggle.
-- Strict batch ordinals remain subject to transaction, recovery and single-
-- user-action evidence; Craft All/X never send a native count above one.
local NativeDispatchService = {
    contract = "native-profession-dispatch-service-v1",
    intentContract = "native-profession-dispatch-intent-v1",
    auditContract = "native-profession-dispatch-audit-v1",
    historyLimit = 32,
    serial = 0,
    history = {},
    last = nil,
    -- In-memory replay fence: a protected native ordinal must be attempted
    -- at most once even when an OnClick handler reenters synchronously.
    attemptedOrdinals = {},
    attemptOrder = {},
    -- Keep every in-session attempted ordinal until reload. If the generous
    -- ceiling is reached, fail closed rather than evicting a replay fence.
    attemptLimit = 16384,
}

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

local function currentSessionReceipt()
    local runtime=JLP:GetModule("RuntimeCompatibility")
    return runtime and type(runtime.GetSessionReceipt)=="function"
        and runtime:GetSessionReceipt() or nil
end

local function positiveInteger(value)
    value = tonumber(value)
    if not value or value < 1 or value > 2147483646 or
        value ~= math.floor(value) then return nil end
    return value
end

local function copyAudit(audit)
    local out = {}
    for k, v in pairs(audit or {}) do out[k] = v end
    return out
end

function NativeDispatchService:ValidateIntent(intent)
    if type(intent) ~= "table" then return false, "dispatch-intent-required" end
    if tostring(intent.contract or "") ~= self.intentContract then return false, "dispatch-intent-contract-mismatch" end
    if tostring(intent.professionKey or "") == "" then return false, "dispatch-profession-required" end
    if tostring(intent.policy or "") == "" then return false, "dispatch-policy-required" end
    -- Do not let an unknown or renamed batch request masquerade as an ordinary
    -- one-craft dispatch. Existing Craft One/Enchant One call sites are listed
    -- explicitly. In particular, MANUAL_DIRECT_CRAFT_ALL is NEVER an escape.
    local knownPolicies = {
        MANUAL_DIRECT_CRAFT_ONE = "CRAFT_RECIPE",
        PRODUCTION_GUARDED_CRAFT_ONE = "CRAFT_RECIPE",
        RESEARCH_GUARDED_CRAFT_ONE = "CRAFT_RECIPE",
        PRODUCTION_CRAFT_ALL_ORDINAL = "CRAFT_RECIPE",
        RESEARCH_CRAFT_ALL_ORDINAL = "CRAFT_RECIPE",
        PRODUCTION_GUARDED_ENCHANT_ONE = "TARGETED_ENCHANT",
        MANUAL_DIRECT_ENCHANT_ONE = "TARGETED_ENCHANT",
    }
    if knownPolicies[tostring(intent.policy)] ~= tostring(intent.strategy) then
        return false, "unrecognized-or-mismatched-dispatch-policy"
    end
    -- A policy name cannot serve as authority on its own. Guarded native
    -- dispatch must agree with a current in-memory transaction and its
    -- separately persisted ledger/recovery records.
    local policyName = tostring(intent.policy)
    local guardedPolicy = policyName == "PRODUCTION_GUARDED_CRAFT_ONE"
        or policyName == "RESEARCH_GUARDED_CRAFT_ONE"
        or policyName == "PRODUCTION_CRAFT_ALL_ORDINAL"
        or policyName == "RESEARCH_CRAFT_ALL_ORDINAL"
        or policyName == "PRODUCTION_GUARDED_ENCHANT_ONE"
    if (policyName == "PRODUCTION_GUARDED_CRAFT_ONE" or policyName == "PRODUCTION_CRAFT_ALL_ORDINAL")
            and intent.professionKey ~= "TAILORING" then
        return false, "production-tailoring-policy-profession-mismatch"
    end
    if (policyName == "PRODUCTION_GUARDED_ENCHANT_ONE" or policyName == "MANUAL_DIRECT_ENCHANT_ONE")
            and intent.professionKey ~= "ENCHANTING" then
        return false, "enchant-policy-profession-mismatch"
    end
    if guardedPolicy and (intent.guardPolicy ~= true or intent.boundaryValidated ~= true or
            intent.ledgerReserved ~= true or intent.recoveryReserved ~= true or
            type(intent.transactionID) ~= "string" or intent.transactionID == "") then
        return false, "guarded-policy-reservation-required"
    end
    if not positiveInteger(intent.recipeID) or tonumber(intent.recipeID) ~= math.floor(tonumber(intent.recipeID)) then
        return false, "dispatch-recipe-id-invalid"
    end
    if intent.nativeDispatchAllowed ~= true then return false, "native-dispatch-not-allowed" end

    local strategy = tostring(intent.strategy or "")
    if strategy ~= "CRAFT_RECIPE" and strategy ~= "TARGETED_ENCHANT" then
        return false, "unsupported-native-dispatch-strategy"
    end

    local count = positiveInteger(intent.count)
    if not count or tonumber(intent.count) ~= count then return false, "dispatch-count-invalid" end
    -- A guarded Craft All ordinal cannot pass as an unguarded/manual
    -- single craft by altering its dispatch identity.
    local policyName = tostring(intent.policy or "")
    local boundaryName = tostring(intent.boundaryContract or "")
    local strictBatch = policyName == "RESEARCH_CRAFT_ALL_ORDINAL"
        or policyName == "PRODUCTION_CRAFT_ALL_ORDINAL"
        or boundaryName == "native-strict-craft-all-ordinal-boundary-v1"
        or boundaryName == "native-current-recipe-craft-all-boundary-v1"
        or boundaryName == "production-tailoring-native-current-recipe-craft-all-boundary-v1"
    if strictBatch then
        -- An ordinary Craft One policy must not carry batch boundary metadata,
        -- and a batch ordinal must have an explicit guarded native policy.
        if policyName ~= "RESEARCH_CRAFT_ALL_ORDINAL" and policyName ~= "PRODUCTION_CRAFT_ALL_ORDINAL" then
            return false, "batch-policy-boundary-mismatch"
        end
        if boundaryName ~= "native-strict-craft-all-ordinal-boundary-v1" then
            return false, "strict-ordinal-boundary-mismatch"
        end
        if intent.guardPolicy ~= true or intent.boundaryValidated ~= true or
            intent.ledgerReserved ~= true or intent.recoveryReserved ~= true or
            not intent.transactionID or intent.transactionID == "" then
            return false, "strict-craft-all-boundary-not-reserved"
        end
    end
    -- No alternate unguarded multi-count CraftRecipe bypass may enter the client.
    -- Craft All/X use count=1 per separately verified, explicit Guide click.
    if strategy == "CRAFT_RECIPE" and count > 1 then
        return false, "unguarded-multi-count-native-dispatch-rejected"
    end
    if strategy == "TARGETED_ENCHANT" then
        if count ~= 1 then return false, "targeted-enchant-count-must-be-one" end
        if intent.itemTarget == nil or intent.itemTarget == false then return false, "targeted-enchant-item-target-required" end
    end

    -- Guarded policies must arrive after their transaction boundary has already
    -- been installed. Manual/direct compatibility remains intentionally distinct
    -- in alpha119 so behavior does not change during physical call-site consolidation.
    if intent.guardPolicy == true then
        if intent.boundaryValidated ~= true then return false, "guarded-boundary-not-validated" end
        if intent.ledgerReserved ~= true then return false, "guarded-ledger-not-reserved" end
        if intent.recoveryReserved ~= true then return false, "guarded-recovery-not-reserved" end
    end
    if guardedPolicy then
        local crafting = JLP:GetModule("Crafting")
        local pending = crafting and (strategy == "TARGETED_ENCHANT" and crafting.pendingEnchant or crafting.pendingCraft)
        local kind = strategy == "TARGETED_ENCHANT" and "enchant" or "craft"
        local provenance = pending and pending.authorityProvenance or nil
        local expectedProvenance = {
            PRODUCTION_GUARDED_CRAFT_ONE = "production-tailoring-native-dispatch-provenance-v1",
            RESEARCH_GUARDED_CRAFT_ONE = "research-native-dispatch-provenance-v1",
            PRODUCTION_CRAFT_ALL_ORDINAL = "production-tailoring-native-craft-all-provenance-v1",
            RESEARCH_CRAFT_ALL_ORDINAL = "research-native-craft-all-provenance-v1",
            PRODUCTION_GUARDED_ENCHANT_ONE = "production-enchanting-native-dispatch-provenance-v1",
        }
        if type(provenance) ~= "table" or provenance.contract ~= expectedProvenance[policyName] or
            provenance.authorityContract ~= intent.authorityContract or
            (kind == "enchant" and provenance.boundaryContract ~= intent.boundaryContract) then
            return false, "guarded-authority-provenance-mismatch"
        end
        -- A reservation is executable only while the original native click is
        -- being dispatched. A recovered, settling or already-active cast is
        -- not a second authorization to call a protected API.
        if not pending or pending.status ~= "dispatching" or
            pending.transactionID ~= intent.transactionID or
            pending.ledgerID ~= intent.transactionID or
            pending.key ~= intent.professionKey or tonumber(pending.recipeID) ~= tonumber(intent.recipeID) or
            (kind == "enchant" and (pending.productionEnchantingNativeExecution ~= true or
                tostring(pending.targetGUID or "") ~= tostring(intent.targetGUID or ""))) or
            (kind == "craft" and (pending.status == "awaiting-user" or
                ((policyName == "PRODUCTION_CRAFT_ALL_ORDINAL" or policyName == "RESEARCH_CRAFT_ALL_ORDINAL") and
                    (pending.strictTargetSafeCraftAll ~= true or pending.strictAwaitingUserClick == true or pending.strictOrdinalInFlight ~= true)) or
                (policyName == "PRODUCTION_CRAFT_ALL_ORDINAL" and pending.productionTailoringCraftAll ~= true) or
                (policyName == "RESEARCH_CRAFT_ALL_ORDINAL" and pending.researchNativeCraftAll ~= true))) then
            return false, "guarded-current-pending-mismatch"
        end
        local ledger = JLP:GetModule("TransactionLedger")
        local tx = ledger and ledger.GetTransaction and ledger:GetTransaction(intent.transactionID)
        if not tx or tx.id ~= intent.transactionID or tx.kind ~= kind or
            tx.key ~= intent.professionKey or tonumber(tx.recipeID) ~= tonumber(intent.recipeID) or
            (kind == "enchant" and tostring(tx.targetGUID or "") ~= tostring(intent.targetGUID or "")) or
            tx.closedAt ~= nil or
            (tx.status ~= "pending" and tx.status ~= "dispatching") then
            return false, "guarded-ledger-identity-mismatch"
        end
        local recovery = JLP:GetModule("TransactionRecovery")
        local checkpoint = recovery and recovery.GetCheckpoint and recovery:GetCheckpoint()
        if not checkpoint or checkpoint.status ~= "dispatching" or
            checkpoint.ledgerID ~= intent.transactionID or
            checkpoint.kind ~= kind or checkpoint.key ~= intent.professionKey or
            tonumber(checkpoint.recipeID) ~= tonumber(intent.recipeID) or
            (kind == "enchant" and tostring(checkpoint.targetGUID or "") ~= tostring(intent.targetGUID or "")) then
            return false, "guarded-recovery-checkpoint-mismatch"
        end
    end
    -- Last physical boundary: a 70009 production route may not be dispatched
    -- as verified build-70450 material/output authority, even via a manual or
    -- renamed UI entry point. Static DB2 equality is not production permission.
    if intent.professionKey == "TAILORING" or intent.professionKey == "ENCHANTING" then
        local buildInfo = JLP:GetModule("ClientBuildInfo")
        -- A missing/unavailable build module is UNKNOWN, not a bypass for the
        -- Tailoring/Enchanting production source authority boundary.
        if not buildInfo or type(buildInfo.GetBuildNumber)~="function" then
            return false,"production-live-client-build-unknown"
        end
        local ok,liveBuild=pcall(buildInfo.GetBuildNumber,buildInfo)
        if not ok or type(liveBuild)~="number" or
            liveBuild~=math.floor(liveBuild) or liveBuild<1 then
            return false,"production-live-client-build-unknown"
        end
        -- Any build may use an already qualified SOURCE; no fixed build list.
        -- This is NOT an authorization on its own. Existing pending transaction,
        -- recovery, learned-recipe, reagent and click safety gates still apply.
        local provider=JLP:GetModule("ProfessionDatasetProvider")
        local dataset,definition
        if provider and type(provider.GetRegisteredDataset) == "function" then
            local sourceDataset, _, sourceDefinition = provider:GetRegisteredDataset(intent.professionKey)
            dataset, definition = sourceDataset, sourceDefinition
        end
        local eligible=provider and provider.CheckProductionAuthority and
            provider:CheckProductionAuthority(intent.professionKey,dataset,definition)
        if not eligible then
            return false,"production-source-authority-unverified"
        end
        -- Source-field parity is source integrity, not a right reserved for
        -- (or bypassed by) clients with a particular numeric build. Apply the
        -- same cross-source proof to the legacy production route on all builds.
        if dataset and dataset.legacyProductionBaseline == true then
            local audit = JLP:GetModule("Build70450ProductionRouteAudit")
            if not audit or not audit.AssessRecipe then return false,"70450-production-data-audit-unavailable" end
            local proof,why = audit:AssessRecipe(intent.professionKey,tonumber(intent.recipeID),70450)
            if not proof or proof.sourceFieldsMatch ~= true or proof.nativeDispatchAllowed ~= false then
                return false,"70450-production-data-"..tostring(why or "unqualified")
            end
            local provider=JLP:GetModule("ProfessionDatasetProvider")
            if not provider then return false,"70450-production-provider-unavailable" end
            local dataset, _, definition = provider:GetRegisteredDataset(intent.professionKey)
            local allowed,reason=provider:CheckProductionAuthority(intent.professionKey,dataset,definition)
            if not allowed then return false,tostring(reason or "70450-production-not-qualified") end
        end
    end
    -- Legacy manual/direct policies also enter this physical client boundary.
    -- A policy name or stale recipe-cache ID alone is not native permission:
    -- require the same current pending transaction, its ledger reservation and
    -- positive LIVE learned/recipe identity. Read-only catalogue data do not
    -- establish any of these facts. Guarded policies retain their own checks.
    if policyName == "MANUAL_DIRECT_CRAFT_ONE" or policyName == "MANUAL_DIRECT_ENCHANT_ONE" then
        local kind = policyName == "MANUAL_DIRECT_ENCHANT_ONE" and "enchant" or "craft"
        local boundary = kind == "enchant" and "manual-direct-enchant-policy-v1" or "manual-direct-craft-policy-v1"
        if tostring(intent.boundaryContract or "") ~= boundary or
            type(intent.transactionID) ~= "string" or intent.transactionID == "" then
            return false, "manual-direct-reservation-required"
        end
        local craft = JLP:GetModule("Crafting")
        local pending = craft and (kind == "enchant" and craft.pendingEnchant or craft.pendingCraft)
        if not pending or pending.status ~= "dispatching" or
            (kind == "craft" and pending.mode ~= "one") or
            pending.key ~= intent.professionKey or
            tonumber(pending.recipeID) ~= tonumber(intent.recipeID) or
            pending.ledgerID ~= intent.transactionID or pending.transactionID ~= intent.transactionID or
            (kind == "enchant" and
                (tostring(pending.targetGUID or "") ~= tostring(intent.targetGUID or "") or
                 pending.targetLocation ~= intent.itemTarget)) then
            return false, "manual-direct-current-pending-mismatch"
        end
        local ledger = JLP:GetModule("TransactionLedger")
        local tx = ledger and type(ledger.GetTransaction) == "function" and ledger:GetTransaction(intent.transactionID) or nil
        if not tx or tx.id ~= intent.transactionID or tx.kind ~= kind or
            tx.key ~= intent.professionKey or tonumber(tx.recipeID) ~= tonumber(intent.recipeID) or
            tonumber(tx.requestedCount) ~= 1 or tx.closedAt ~= nil or
            tx.status == "success" or tx.status == "failed" or tx.status == "timeout" or tx.status == "aborted_unknown" or
            (kind == "enchant" and tostring(tx.targetGUID or "") ~= tostring(intent.targetGUID or "")) then
            return false, "manual-direct-ledger-identity-mismatch"
        end
        if type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.GetRecipeInfo) ~= "function" then
            return false, "manual-direct-live-recipe-unavailable"
        end
        local infoOK, info = pcall(C_TradeSkillUI.GetRecipeInfo, tonumber(intent.recipeID))
        if not infoOK or type(info) ~= "table" or info.learned ~= true then
            return false, "manual-direct-recipe-not-learned-or-unknown"
        end
        local function normalizedName(name)
            return tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
        end
        if normalizedName(info.name) == "" or
            normalizedName(info.name) ~= normalizedName(pending.recipeName) then
            return false, "manual-direct-recipe-identity-drift"
        end
    end
    return true
end

function NativeDispatchService:_ReplayKey(intent)
    local policy = tostring(intent and intent.policy or "")
    if policy ~= "MANUAL_DIRECT_CRAFT_ONE" and
        policy ~= "MANUAL_DIRECT_ENCHANT_ONE" and
        policy ~= "PRODUCTION_GUARDED_CRAFT_ONE" and
        policy ~= "RESEARCH_GUARDED_CRAFT_ONE" and
        policy ~= "PRODUCTION_CRAFT_ALL_ORDINAL" and
        policy ~= "RESEARCH_CRAFT_ALL_ORDINAL" and
        policy ~= "PRODUCTION_GUARDED_ENCHANT_ONE" then return nil end
    local crafting = JLP:GetModule("Crafting")
    local pending = crafting and (intent.strategy == "TARGETED_ENCHANT" and crafting.pendingEnchant or crafting.pendingCraft)
    local ordinal = (policy == "PRODUCTION_CRAFT_ALL_ORDINAL" or policy == "RESEARCH_CRAFT_ALL_ORDINAL")
        and tonumber(pending and pending.strictCurrentOrdinal) or 1
    if type(ordinal) ~= "number" or ordinal ~= math.floor(ordinal) or ordinal < 1 then
        return nil, "guarded-current-ordinal-invalid"
    end
    return table.concat({tostring(intent.transactionID),tostring(intent.strategy),tostring(ordinal)}, ":")
end

function NativeDispatchService:_ReserveAttempt(key)
    if self.attemptedOrdinals[key] then return false, "native-dispatch-replay-rejected" end
    -- A bounded rolling cache permits the oldest transaction to replay. Never
    -- discard an attempt within this live session; exhaust the fence closed.
    if #self.attemptOrder >= self.attemptLimit then
        return false, "native-dispatch-attempt-capacity-exhausted"
    end
    self.attemptedOrdinals[key] = true
    self.attemptOrder[#self.attemptOrder + 1] = key
    return true
end

function NativeDispatchService:_Record(intent, accepted, state, detail)
    -- Malformed caller inputs are rejected and audited, not a Lua exception.
    if type(intent) ~= "table" then intent = nil end
    self.serial = (tonumber(self.serial) or 0) + 1
    local audit = {
        contract = self.auditContract,
        serial = self.serial,
        at = now(),
        professionKey = intent and intent.professionKey or nil,
        strategy = intent and intent.strategy or nil,
        policy = intent and intent.policy or nil,
        recipeID = intent and tonumber(intent.recipeID) or nil,
        count = intent and tonumber(intent.count) or nil,
        targetGUID = intent and intent.targetGUID or nil,
        transactionID = intent and intent.transactionID or nil,
        authorityContract = intent and intent.authorityContract or nil,
        boundaryContract = intent and intent.boundaryContract or nil,
        accepted = accepted == true,
        state = tostring(state or "unknown"),
        detail = detail and tostring(detail) or nil,
    }
    self.last = audit
    self.history[#self.history + 1] = audit
    while #self.history > self.historyLimit do table.remove(self.history, 1) end
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("NATIVE_DISPATCH_AUDIT_UPDATED", copyAudit(audit)) end
    return audit
end

-- Every physical native policy (manual, guarded one-craft, strict batch
-- ordinal, and targeted enchant) must pass the same last-moment live reagent
-- and recipe check.  Advisory CraftReadiness/Inventory snapshots are never
-- authoritative here. This check is intentionally repeated after reservation:
-- bags/recipes may change between plan render and actual native dispatch.
function NativeDispatchService:ValidateLiveCraftability(intent)
    local client=C_TradeSkillUI
    if type(client)~="table" or type(client.GetRecipeInfo)~="function" then
        return false,"native-live-recipe-api-unavailable"
    end
    local recipeID=tonumber(intent.recipeID)
    local recipeInfoFunction=client.GetRecipeInfo
    local craftableFunction=client.GetCraftableCount
    local schematicFunction=client.GetRecipeSchematic
    local crafting=JLP:GetModule("Crafting")
    local pending=crafting and (intent.strategy=="TARGETED_ENCHANT" and crafting.pendingEnchant or crafting.pendingCraft)
    if not pending or tonumber(pending.recipeID)~=recipeID or
        pending.key~=intent.professionKey or pending.transactionID~=intent.transactionID then
        return false,"native-live-transaction-recipe-drift"
    end
    local function canonical(name)
        return tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    end
    local function readRecipe()
        local ok,info=pcall(client.GetRecipeInfo,recipeID)
        if not ok or type(info)~="table" or info.learned~=true then
            return nil,"native-live-recipe-not-learned-or-unknown"
        end
        if info.recipeID~=nil and tonumber(info.recipeID)~=recipeID then
            return nil,"native-live-recipe-id-conflict"
        end
        if canonical(info.name)=="" or canonical(info.name)~=canonical(pending.recipeName) then
            return nil,"native-live-recipe-name-drift"
        end
        return info
    end
    local info,why=readRecipe()
    if not info then return false,why end
    local professionAPI=JLP:GetModule("ProfessionAPI")
    local initialPanel=nil
    if professionAPI and type(professionAPI.GetOpenProfessionContext)=="function" then
        local ok,panel=pcall(professionAPI.GetOpenProfessionContext,professionAPI)
        if not ok or type(panel)~="table" or panel.verified~=true or
            panel.professionKey~=intent.professionKey then
            return false,"native-live-profession-panel-unverified"
        end
        initialPanel=panel
    end
    -- Optional receipt enrichment: if this client exposes a live recipe list,
    -- reconcile the recipe against that very panel. Older APIs with no list
    -- retain the independent learned/name/craftability gates, not a build ban.
    if type(client.GetAllRecipeIDs)=="function" and professionAPI then
        local fn=professionAPI.GetExecutionRecipeContext
        local isExecutionContext=type(fn)=="function"
        if not isExecutionContext then fn=professionAPI.GetRecipeContext end
        if type(fn)=="function" then
            local kind=intent.strategy=="TARGETED_ENCHANT" and "enchant" or "craft"
            local ok,context
            if isExecutionContext then
                ok,context=pcall(fn,professionAPI,recipeID,intent.professionKey,kind)
            else
                ok,context=pcall(fn,professionAPI,recipeID,intent.professionKey)
            end
            if not ok or type(context)~="table" or context.verified~=true or context.learned~=true or
                canonical(context.name)~=canonical(pending.recipeName) or
                (isExecutionContext and context.executionReady~=true) then
                return false,"native-live-panel-recipe-identity-unverified"
            end
        end
    end
    local function snapshot()
        if not professionAPI or type(professionAPI.GetNativeReagentSnapshot)~="function" then return nil end
        local ok,value=pcall(professionAPI.GetNativeReagentSnapshot,professionAPI,recipeID)
        if not ok then return {status="ERROR",reason="SCHEMATIC_SNAPSHOT_EXCEPTION"} end
        return value
    end
    local first=snapshot()
    if first and (first.status=="INVALID" or first.status=="ERROR") then
        return false,"native-live-reagent-schematic-invalid:"..tostring(first.reason)
    end
    if not crafting or type(crafting.GetCraftableCount)~="function" then
        return false,"native-live-craftability-module-unavailable"
    end
    local crafts,countStatus,countReason=crafting:GetCraftableCount(recipeID)
    if countStatus~="KNOWN" then
        return false,"native-live-craftability-unavailable:"..tostring(countReason or countStatus)
    end
    if crafts==0 then return false,"native-live-zero-crafts-confirmed" end
    local later,latestWhy=readRecipe()
    if not later then return false,"native-live-recipe-changed:"..tostring(latestWhy) end
    if C_TradeSkillUI~=client or client.GetRecipeInfo~=recipeInfoFunction or
        client.GetCraftableCount~=craftableFunction or client.GetRecipeSchematic~=schematicFunction then
        return false,"native-live-recipe-api-provider-changed"
    end
    local second=snapshot()
    if second and (second.status=="INVALID" or second.status=="ERROR") then
        return false,"native-live-reagent-schematic-invalid:"..tostring(second.reason)
    end
    if first and second and first.status~=second.status then
        return false,"native-live-reagent-observation-changed"
    end
    if first and second and first.fingerprint~=second.fingerprint then
        return false,"native-live-reagent-schematic-changed"
    end
    if initialPanel then
        local ok,final=pcall(professionAPI.GetOpenProfessionContext,professionAPI)
        if not ok or type(final)~="table" or final.verified~=true or
            final.professionKey~=initialPanel.professionKey or
            final.panelToken~=initialPanel.panelToken or
            final.panelRevision~=initialPanel.panelRevision then
            return false,"native-live-profession-panel-changed"
        end
    end
    -- Actual reagent sufficiency is the CLIENT's confirmed craftable count.
    -- An independent schematic is a current structural consistency witness,
    -- never a substitute for GetCraftableCount or a historical material list.
    -- Re-resolve target after all reads, so recipe/schematic callbacks cannot
    -- leave a changed enchant GUID or ItemLocation authorized.
    if intent.strategy=="TARGETED_ENCHANT" then
        if type(crafting.GetEnchantExecutionTarget)~="function" then
            return false,"native-live-enchant-target-validator-unavailable"
        end
        local targetOK,target=pcall(crafting.GetEnchantExecutionTarget,crafting,recipeID)
        if not targetOK or type(target)~="table" or
            tostring(target.guid or "")=="" or tostring(target.guid)~=tostring(intent.targetGUID or "") then
            return false,"native-live-enchant-target-changed"
        end
        local function locationKey(location)
            if type(location)=="table" then
                local bag=location.bagID or location.bag or location.bagIndex
                local slot=location.slotIndex or location.slot or location.inventorySlot
                local equip=location.equipmentSlot or location.equipSlot
                if bag~=nil or slot~=nil or equip~=nil then
                    return table.concat({"slot",tostring(bag or ""),tostring(slot or ""),tostring(equip or "")},":")
                end
            end
            if type(location)=="table" or type(location)=="userdata" then
                if type(location.IsBagAndSlot)=="function" and type(location.GetBagAndSlot)=="function" then
                    local okBag,isBag=pcall(location.IsBagAndSlot,location)
                    if okBag and isBag then
                        local okSlot,bag,slot=pcall(location.GetBagAndSlot,location)
                        if okSlot then return "bag:"..tostring(bag)..":"..tostring(slot) end
                    end
                end
                if type(location.IsEquipmentSlot)=="function" and type(location.GetEquipmentSlot)=="function" then
                    local okEquip,isEquip=pcall(location.IsEquipmentSlot,location)
                    if okEquip and isEquip then
                        local okSlot,slot=pcall(location.GetEquipmentSlot,location)
                        if okSlot then return "equip:"..tostring(slot) end
                    end
                end
            end
            return nil
        end
        local oldKey,newKey=locationKey(intent.itemTarget),locationKey(target.location)
        if not oldKey or not newKey or oldKey~=newKey then
            return false,"native-live-enchant-location-changed"
        end
    end
    return true
end

function NativeDispatchService:Dispatch(intent)
    -- A native transaction must have a real and stable client session receipt.
    -- This is deliberately *not* a comparison against any source/target build.
    local startReceipt=currentSessionReceipt()
    if not startReceipt then
        return false,"native-live-session-unverified",
            self:_Record(intent,false,"native-live-session-unverified")
    end
    local valid, reason = self:ValidateIntent(intent)
    if not valid then
        local audit = self:_Record(intent, false, reason, reason)
        return false, reason, audit
    end
    local liveOK, liveReason = self:ValidateLiveCraftability(intent)
    if not liveOK then
        return false, liveReason, self:_Record(intent, false, liveReason, liveReason)
    end

    -- ValidateIntent and live recipe/reagent checks can themselves invoke API
    -- calls. If the session changed, no physical native call is permitted.
    local endReceipt=currentSessionReceipt()
    if not endReceipt or endReceipt~=startReceipt then
        return false,"native-live-session-changed",
            self:_Record(intent,false,"native-live-session-changed")
    end
    local strategy = tostring(intent.strategy)
    local recipeID = tonumber(intent.recipeID)
    local count = positiveInteger(intent.count)
    local ok, result

    if strategy == "CRAFT_RECIPE" then
        if type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.CraftRecipe) ~= "function" then
            local state = "craft-recipe-api-unavailable"
            return false, state, self:_Record(intent, false, state, "Forever TradeSkill crafting API is unavailable.")
        end
        local key, err = self:_ReplayKey(intent)
        if err then return false, err, self:_Record(intent, false, err, err) end
        if key then
            local reserved, denial = self:_ReserveAttempt(key)
            if not reserved then
                local state = denial or "native-dispatch-replay-rejected"
                return false, state, self:_Record(intent, false, state, "ordinal attempt not authorized")
            end
        end
        ok, result = pcall(C_TradeSkillUI.CraftRecipe, recipeID, count)
    else
        if type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.CraftEnchant) ~= "function" then
            local state = "craft-enchant-api-unavailable"
            return false, state, self:_Record(intent, false, state, "Forever enchant crafting API is unavailable.")
        end
        local key, err = self:_ReplayKey(intent)
        if err then return false, err, self:_Record(intent, false, err, err) end
        if key then
            local reserved, denial = self:_ReserveAttempt(key)
            if not reserved then
                local state = denial or "native-dispatch-replay-rejected"
                return false, state, self:_Record(intent, false, state, "ordinal attempt not authorized")
            end
        end
        ok, result = pcall(C_TradeSkillUI.CraftEnchant, recipeID, 1, nil, intent.itemTarget)
    end

    if not ok then
        local detail = tostring(result or "unknown client error")
        return false, "native-api-error", self:_Record(intent, false, "native-api-error", detail)
    end
    if result == false then
        return false, "client-rejected-dispatch", self:_Record(intent, false, "client-rejected-dispatch", "client rejected the profession request")
    end
    return true, nil, self:_Record(intent, true, "native-dispatch-accepted")
end

function NativeDispatchService:GetLastAudit()
    return self.last and copyAudit(self.last) or nil
end

function NativeDispatchService:GetHistory()
    local out = {}
    for i, item in ipairs(self.history) do out[i] = copyAudit(item) end
    return out
end

function NativeDispatchService:GetSummary()
    local last = self.last
    if not last then return "Native Dispatch: no irreversible dispatch observed this session." end
    return string.format("Native Dispatch: #%d %s %s recipe=%s count=%s policy=%s", tonumber(last.serial) or 0, tostring(last.state), tostring(last.strategy), tostring(last.recipeID or "?"), tostring(last.count or "?"), tostring(last.policy or "?"))
end

JLP:RegisterModule("NativeDispatchService", NativeDispatchService)
