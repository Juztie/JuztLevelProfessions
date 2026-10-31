local _, JLP = ...

-- Alpha122: read-only 12-profession regression matrix.  The matrix does not
-- promote maturity and does not dispatch native profession work; it makes the
-- Registry/strategy invariants auditable from one place before Alchemy is
-- considered for production promotion.
local ProfessionRegressionMatrix = {
    contract = "profession-regression-matrix-v1",
    rowContract = "profession-regression-matrix-row-v1",
    strategyContract = "profession-multi-strategy-regression-v1",
    targetCount = 12,
}

local EXPECTED = {
    TAILORING={category="PRIMARY",production=true,strategies={"RECIPE_CRAFTING"}},
    ENCHANTING={category="PRIMARY",production=true,strategies={"TARGETED_CRAFTING","DISENCHANT"}},
    ALCHEMY={category="PRIMARY",production=false,strategies={"RECIPE_CRAFTING"}},
    BLACKSMITHING={category="PRIMARY",production=false,strategies={"RECIPE_CRAFTING"}},
    ENGINEERING={category="PRIMARY",production=false,strategies={"RECIPE_CRAFTING"}},
    LEATHERWORKING={category="PRIMARY",production=false,strategies={"RECIPE_CRAFTING"}},
    HERBALISM={category="PRIMARY",production=false,strategies={"NODE_GATHERING"}},
    MINING={category="PRIMARY",production=false,strategies={"NODE_GATHERING"}},
    SKINNING={category="PRIMARY",production=false,strategies={"AREA_GATHERING"}},
    COOKING={category="SECONDARY",production=false,strategies={"RECIPE_CRAFTING"}},
    FIRST_AID={category="SECONDARY",production=false,strategies={"RECIPE_CRAFTING"}},
    FISHING={category="SECONDARY",production=false,strategies={"FISHING_AREA"}},
}

local function shallowCopy(source)
    local out={}
    for k,v in pairs(source or {}) do out[k]=v end
    return out
end

local function sameStrategies(registry,key,expected)
    local def=registry:Get(key)
    if not def then return false end
    local actual={}
    for _,strategy in ipairs(def.progressionStrategies or {}) do actual[strategy]=true end
    if #(def.progressionStrategies or {}) ~= #expected then return false end
    for _,strategy in ipairs(expected) do if not actual[strategy] then return false end end
    return true
end

function ProfessionRegressionMatrix:Evaluate()
    local registry=JLP:GetModule("ProfessionRegistry")
    local dispatch=JLP:GetModule("NativeDispatchService")
    if not registry then return {contract=self.contract,state="blocked",reason="profession-registry-unavailable",rows={},pass=0,total=0,errors={"profession-registry-unavailable"}} end

    local before=dispatch and #(dispatch:GetHistory() or {}) or 0
    local buildInfo=JLP:GetModule("ClientBuildInfo")
    local liveBuild=buildInfo and buildInfo:GetBuildNumber() or nil
    -- Regression targets the current Forever client, not the historical
    -- production dataset baseline (TARGET_BUILD = 70009).
    local targetBuild=JLP.Constants and tonumber(JLP.Constants.CURRENT_FOREVER_BUILD) or nil
    local rows,errors,pass={},{},0
    local keys=registry:GetKeys()
    for _,key in ipairs(keys) do
        local expected=EXPECTED[key]
        local def=registry:Get(key)
        local stableBySkill=def and registry:GetBySkillLineID(def.skillLineID) or nil
        local stableByEnum=def and registry:GetByProfessionEnum(def.professionEnum) or nil
        local stateEnvelope,stateReason=registry:BuildStateEnvelope(key,{strategyKey=def and def.progressionStrategies and def.progressionStrategies[1] or nil,stage="alpha122-regression-matrix",payload={readOnly=true}})
        local stateValid=stateEnvelope and registry:ValidateStateEnvelope(stateEnvelope) == true or false
        local availability=registry:ResolveAvailability(key,"executionFlow",true)
        local production=registry:IsProductionEnabled(key)
        local availabilityOK
        if production then
            availabilityOK=availability and availability.state=="available"
        else
            availabilityOK=availability and availability.terminalReason=="NOT_PRODUCTION_ENABLED"
        end
        local row={
            contract=self.rowContract,
            professionKey=key,
            label=def and def.label or key,
            category=def and def.category or nil,
            professionEnum=def and def.professionEnum or nil,
            skillLineID=def and def.skillLineID or nil,
            strategies=def and def.progressionStrategies or {},
            productionEnabled=production==true,
            stableIdentity=(stableBySkill and stableBySkill.key==key and stableByEnum and stableByEnum.key==key) and true or false,
            stateEnvelope=stateValid==true,
            stateReason=stateReason,
            availability=availability and availability.state or nil,
            terminalReason=availability and availability.terminalReason or nil,
            expectedCategory=expected and expected.category or nil,
            expectedProduction=expected and expected.production or nil,
            expectedStrategies=expected and expected.strategies or {},
        }
        row.pass=expected~=nil and row.category==expected.category and row.productionEnabled==expected.production and row.stableIdentity and row.stateEnvelope and availabilityOK and sameStrategies(registry,key,expected.strategies)
        if row.pass then pass=pass+1 else errors[#errors+1]="matrix-row-failed:"..tostring(key) end
        rows[#rows+1]=row
    end

    local unknown=registry:ResolveAvailability("UNKNOWN_PROFESSION","executionFlow",true)
    if not unknown or unknown.terminalReason~="UNSUPPORTED_PROFESSION" then errors[#errors+1]="unknown-profession-not-fail-closed" end
    local after=dispatch and #(dispatch:GetHistory() or {}) or before
    if after~=before then errors[#errors+1]="native-dispatch-delta:"..tostring(after-before) end
    if #keys~=self.targetCount then errors[#errors+1]="profession-count:"..tostring(#keys) end
    -- The registry invariant test is source-build independent. Report the
    -- live/reference relation as advisory metadata, never as a failing row.

    return {
        contract=self.contract,
        strategyContract=self.strategyContract,
        state=(#errors==0 and pass==self.targetCount) and "profession-regression-matrix-ready" or "profession-regression-matrix-blocked",
        pass=pass,total=#keys,rows=rows,errors=errors,
        nativeDispatchDelta=after-before,
        productionKeys=registry:GetProductionKeys("executionFlow"),
        targetBuild=targetBuild,liveBuild=liveBuild,buildMatch=(targetBuild and liveBuild and targetBuild==liveBuild) or false,
        buildDrift=(targetBuild and liveBuild and targetBuild~=liveBuild) and true or false,
    }
end

function ProfessionRegressionMatrix:GetRow(key)
    key=tostring(key or ""):upper():gsub("[%s%-]+","_")
    local report=self:Evaluate()
    for _,row in ipairs(report.rows or {}) do if row.professionKey==key then return shallowCopy(row) end end
    return nil
end

function ProfessionRegressionMatrix:GetSummary()
    local report=self:Evaluate()
    local production=table.concat(report.productionKeys or {},",")
    local buildState=(not report.liveBuild and " · BUILD UNKNOWN" or report.buildDrift and (" · reference build "..tostring(report.targetBuild).." / client "..tostring(report.liveBuild)) or "")
    return string.format("Profession regression matrix: %d / %d PASS · errors %d · native dispatch delta %d · production %s%s",tonumber(report.pass) or 0,tonumber(report.total) or 0,#(report.errors or {}),tonumber(report.nativeDispatchDelta) or 0,production~="" and production or "none",buildState)
end

JLP:RegisterModule("ProfessionRegressionMatrix",ProfessionRegressionMatrix)
