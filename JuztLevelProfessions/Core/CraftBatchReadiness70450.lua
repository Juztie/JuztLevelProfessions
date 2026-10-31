local _, JLP = ...

-- READ-ONLY Craft All/Craft X runtime readiness checklist.
-- This service does not issue click origins, authorizations, dispatch intents,
-- batch authorizations, or transaction reservations. In particular, a successful
-- data review is not a hardware-click or live-client acceptance test.
local Audit = {
    contract = "jlp-70450-batch-runtime-readiness-v2",
    sourceBuild = 70450,
    readOnly = true,
    productionAuthority = false,
    nativeDispatchAllowed = false,
    maxCraftX = 9999,
}

local function strictUInt(value, maxValue)
    local n = tonumber(value)
    if not n or n ~= math.floor(n) or n < 1 or n > (maxValue or 2147483646) then return nil end
    return n
end

local function add(row, name, ok, code)
    local item = {gate=name, passed=ok==true, code=ok==true and "PASS" or code}
    row.gates[#row.gates+1] = item
    if not item.passed then
        row.blockers[#row.blockers+1] = code
    end
    return item.passed
end

function Audit:Evaluate(profession, spellID, count)
    local key = tostring(profession or ""):upper()
    local recipeID = strictUInt(spellID)
    local units = strictUInt(count or 1, self.maxCraftX)
    local row = {
        contract=self.contract, sourceBuild=self.sourceBuild,
        professionKey=key, recipeID=recipeID, requestedCount=units,
        readOnly=true, productionAuthority=false, nativeDispatchAllowed=false,
        automaticContinuationAllowed=false, liveClientTested=false,
        state="RUNTIME_GATES_BLOCKED", gates={}, blockers={},
    }

    local validKey = key == "TAILORING" -- only the dedicated Tailoring production owner
    add(row,"production-profession", validKey, "UNAPPROVED_PROFESSION")
    add(row,"request", recipeID ~= nil and units ~= nil, "INVALID_RECIPE_OR_QUANTITY")

    local buildInfo = JLP:GetModule("ClientBuildInfo")
    local live = buildInfo and buildInfo.GetBuildNumber and buildInfo:GetBuildNumber() or nil
    row.clientBuild = live
    add(row,"current-client", type(live)=="number" and live>0 and live==math.floor(live), "LIVE_CLIENT_BUILD_UNVERIFIED")

    local native = type(C_TradeSkillUI)=="table" and type(C_TradeSkillUI.CraftRecipe)=="function"
    add(row,"native-api",native,"NATIVE_API_NOT_OBSERVED")

    local source = JLP:GetModule("Build70450ProductionQualification")
    local receipt = validKey and recipeID and source and source.AssessRecipe and
        source:AssessRecipe(key,recipeID,self.sourceBuild) or nil
    row.sourceStatus = receipt and receipt.state or "UNKNOWN"
    add(row,"source-and-rights", type(receipt)=="table" and receipt.state=="SOURCE_QUALIFIED"
        and receipt.sourceQualified==true, "SOURCE_QUALIFIED_REVIEW_MISSING")

    local crafting = JLP:GetModule("Crafting")
    add(row,"transaction-idle", crafting ~= nil and not crafting.pendingCraft
        and not crafting.pendingEnchant and not crafting.activeRepeat,
        "NATIVE_TRANSACTION_BUSY_OR_UNAVAILABLE")
    local ledger = JLP:GetModule("TransactionLedger")
    local recovery = JLP:GetModule("TransactionRecovery")
    add(row,"ledger-and-recovery", ledger ~= nil and type(ledger.Begin)=="function"
        and recovery ~= nil and type(recovery.CapturePending)=="function"
        and type(recovery.CanStart)=="function", "LEDGER_RECOVERY_CONTRACT_MISSING")

    local orchestrator=JLP:GetModule("ResearchNativeCraftAllStrictOrchestrator")
    local authority=JLP:GetModule("ProductionTailoringCraftAllAuthority")
    add(row,"strict-ordinal-owner", type(orchestrator)=="table"
        and orchestrator.nativeDispatchPerOrdinal==1
        and orchestrator.automaticResume==false
        and type(authority)=="table" and authority.automaticRouteAdvance==false,
        "STRICT_ORDINAL_OWNER_INVALID")

    -- This receipt is informative; it does not authorize dispatch. Runtime
    -- qualification and native authority remain separate from diagnostics.
    row.state = #row.blockers==0 and "RUNTIME_READY_FOR_USER_ACTION" or "RUNTIME_GATES_BLOCKED"
    return row
end

function Audit:Summary(profession, spellID, count)
    local row=self:Evaluate(profession,spellID,count)
    local parts={"Craft All/Craft X (70450 source): "..row.state, "read-only diagnostic; no native call"}
    parts[#parts+1]="recipe="..tostring(row.recipeID or "unknown")
    parts[#parts+1]="requested="..tostring(row.requestedCount or "invalid")
    parts[#parts+1]="client="..tostring(row.clientBuild or "unknown")
    parts[#parts+1]="source="..tostring(row.sourceStatus)
    parts[#parts+1]="blockers="..table.concat(row.blockers,",")
    return table.concat(parts," | ")
end

JLP:RegisterModule("CraftBatchReadiness70450",Audit)
