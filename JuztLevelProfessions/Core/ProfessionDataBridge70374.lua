local _, JLP = ...
-- M4 read-only integration boundary. It is intentionally NOT an authority for
-- crafting, vendor purchases, known recipes, skill-ups, or execution readiness.
local Bridge = {
    contract="JLP-PROFESSION-DATA-BRIDGE-70374-1", sourceBuild=70374,
    nativeDispatchAllowed=false, executionEligible=false, readOnly=true,
    revisions={price=0,inventory=0,profession=0}, initialized=false,
}
local BUILD=70374
local function module(name) return JLP:GetModule(name) end
local function integer(n, allowZero)
    return type(n)=="number" and n==math.floor(n) and n<(2^53) and n>= (allowZero and 0 or 1)
end
local function copyRevisions()
    return {price=Bridge.revisions.price,inventory=Bridge.revisions.inventory,
        profession=Bridge.revisions.profession}
end
local function actualBuild()
    local buildInfo=module("ClientBuildInfo")
    if not buildInfo or type(buildInfo.GetBuildNumber)~="function" then return nil end
    local ok,build=pcall(buildInfo.GetBuildNumber,buildInfo)
    if ok and integer(build) then return build end
    return nil
end
local function matchingIdentity(key, options)
    options=options or {}
    local registry=module("ProfessionRegistry")
    if not registry or not registry.NormalizeKey then return nil,"REGISTRY_UNAVAILABLE" end
    local normalized=registry:NormalizeKey(key)
    if not normalized then return nil,"UNKNOWN_PROFESSION" end
    local def=registry:Get(normalized)
    if not def or not integer(def.skillLineID) or type(def.progressionStrategies)~="table" then
        return nil,"INCOMPLETE_REGISTRY_ENTRY"
    end
    if options.skillLineID~=nil and (not integer(options.skillLineID) or options.skillLineID~=def.skillLineID) then
        return nil,"SKILL_LINE_ID_CONFLICT"
    end
    if options.professionEnum~=nil and (not integer(options.professionEnum,true) or options.professionEnum~=def.professionEnum) then
        return nil,"PROFESSION_ENUM_CONFLICT"
    end
    local data=JLP.data and JLP.data.build70374Professions
    local src=data and data.professions and data.professions[normalized]
    if not data or data.contract~="JLP-OWNER-BUILD70374-CSV-1" or data.sourceBuild~=BUILD or
       not src or src.skillLineID~=def.skillLineID or type(src.packed)~="string" then
        return nil,"SOURCE_REGISTRY_ID_CONFLICT"
    end
    return normalized,def
end
local function context(key,options)
    options=type(options)=="table" and options or {}
    if options.sourceBuild~=nil and options.sourceBuild~=BUILD then
        return nil,"SOURCE_BUILD_MISMATCH"
    end
    local observed=actualBuild()
    -- Historical reference data remains browsable even if GetBuildInfo is
    -- temporarily unavailable. Any live/session proof still fails closed.
    local normalized,def=matchingIdentity(key,options)
    if not normalized then return nil,def end
    return {professionKey=normalized,skillLineID=def.skillLineID,
        professionEnum=def.professionEnum,category=def.category,
        progressionStrategy=def.progressionStrategies[1] or "UNKNOWN",
        productionMaturity=def.maturity and def.maturity.production==true or false,
        sourceBuild=BUILD,clientBuild=observed,revision=copyRevisions()}
end
local function isReferenceRecipe(row,ctx,id)
    return type(row)=="table" and row.professionKey==ctx.professionKey and
       row.skillLineID==ctx.skillLineID and row.spellID==id and
       row.sourceBuild==BUILD and row.nativeDispatchAllowed==false and
       row.productionAuthority==false
end
local function shell(ctx,kind)
    return {contract=Bridge.contract,kind=kind,professionKey=ctx.professionKey,
        skillLineID=ctx.skillLineID,professionEnum=ctx.professionEnum,
        category=ctx.category,progressionStrategy=ctx.progressionStrategy,
        sourceBuild=BUILD,clientBuild=ctx.clientBuild,revision=ctx.revision,
        sourceQualification="OWNER_CSV_REFERENCE_ONLY",clientRecipeVerified=false,
        currentBuildRecipeAccessVerified=false,craftingReady=false,
        nativeDispatchAllowed=false,executionEligible=false,readOnly=true}
end
-- Public notification contains no raw AH, character, or profession payload.
function Bridge:MarkChanged(domain)
    if self.revisions[domain]==nil then return false,"UNKNOWN_REVISION_DOMAIN" end
    local current=self.revisions[domain]
    self.revisions[domain]=current<1000000000 and current+1 or 1
    if JLP.EventBus and type(JLP.EventBus.Emit)=="function" then
        JLP.EventBus:Emit("PROFESSION_DATA_70374_INVALIDATED",domain,self.revisions[domain])
    end
    return true
end
function Bridge:Initialize()
    if self.initialized then return true end
    local bus=JLP.EventBus
    if not bus or type(bus.On)~="function" then return false,"EVENT_BUS_UNAVAILABLE" end
    local groups={
        price={"AH_SNAPSHOT_UPDATED","AH_SCAN_EXPIRED","AH_SCAN_STARTED"},
        profession={"PROFESSION_PROGRESS_UPDATED","PROFESSION_CRAFT_OBSERVED",
            "RECIPE_ACCESS_EVIDENCE_UPDATED","PROFESSION_RUNTIME_STATE_UPDATED"},
        inventory={"PROFESSION_TRANSACTION_UPDATED","PROFESSION_CRAFT_OBSERVED",
            "JLP_INVENTORY_DATA_REFRESHED"},
    }
    for domain,events in pairs(groups) do
        for _,event in ipairs(events) do
            local domainName=domain
            bus:On(event,function()
                -- Do not keep raw event payloads (AH tables can be very large).
                self:MarkChanged(domainName)
            end)
        end
    end
    self.initialized=true
    return true
end
-- Called after inventory/skill events; does not alter SavedVariables.
function Bridge:OnClientDataEvent(event)
    if event=="BAG_UPDATE_DELAYED" or event=="BANKFRAME_OPENED" or
       event=="BANKFRAME_CLOSED" or event=="PLAYERBANKSLOTS_CHANGED" or
       event=="PLAYERBANKBAGSLOTS_CHANGED" or event=="BAG_CONTAINER_UPDATE" or
       event=="PLAYERREAGENTBANKSLOTS_CHANGED" or event=="PLAYER_LOGIN" then
        self:MarkChanged("inventory")
    elseif event=="SKILL_LINES_CHANGED" or event=="TRADE_SKILL_LIST_UPDATE" or
           event=="NEW_RECIPE_LEARNED" or event=="LEARNED_SPELL_IN_TAB" or
           event=="TRADE_SKILL_UPDATE" then
        self:MarkChanged("profession")
    end
end
function Bridge:GetProfessionState(key,options)
    local ctx,err=context(key,options)
    if not ctx then return nil,err end
    local ref=module("Build70374ProfessionReference")
    if not ref or type(ref.GetCoverage)~="function" then return nil,"REFERENCE_UNAVAILABLE" end
    local coverage,reason=ref:GetCoverage()
    if not coverage then return nil,reason or "COVERAGE_UNAVAILABLE" end
    local row=coverage.byProfession and coverage.byProfession[ctx.professionKey]
    if type(row)~="table" then return nil,"PROFESSION_COVERAGE_MISSING" end
    local state=shell(ctx,"PROFESSION_STATE")
    state.abilityRows=row.skillLineAbilityRows
    state.rowsWithReagents=row.reagentRecordRows
    state.rowsWithItemOutputs=row.outputEffectRows
    state.fullProductionCatalogueComplete=false
    return state
end
function Bridge:GetRecipeState(key,spellID,crafts,options)
    local ctx,err=context(key,options)
    if not ctx then return nil,err end
    if not integer(spellID) then return nil,"INVALID_SPELL_ID" end
    if not integer(crafts) or crafts>9999 then return nil,"INVALID_CRAFT_COUNT" end
    options=type(options)=="table" and options or {}
    local ref=module("Build70374ProfessionReference")
    local econ=module("ProfessionEconomy70374")
    if not ref or not econ then return nil,"REFERENCE_OR_ECONOMY_UNAVAILABLE" end
    local raw,why=ref:GetRecipe(ctx.professionKey,spellID,BUILD)
    if not raw then return nil,why end
    if not isReferenceRecipe(raw,ctx,spellID) then return nil,"RECIPE_IDENTITY_OR_AUTHORITY_CONFLICT" end
    local result=shell(ctx,"RECIPE_STATE")
    result.spellID=spellID;result.crafts=crafts;result.recipeName=raw.name
    result.recordKind=raw.recordKind;result.reagentDataState=raw.reagentStatus
    result.outputItems=raw.outputs;result.outputYieldVerified=false
    result.learnedState="UNKNOWN";result.recipeAccessVerified=false
    if raw.reagents==nil then
        result.materialState="REAGENTS_UNKNOWN";result.materials=nil
    else
        local materials,reason=econ:GetRecipeMaterials(ctx.professionKey,spellID,crafts,BUILD)
        if not materials then return nil,reason end
        if materials.professionKey~=ctx.professionKey or materials.spellID~=spellID or
           materials.sourceBuild~=BUILD or materials.nativeDispatchAllowed~=false then
            return nil,"MATERIALS_CONTRACT_CONFLICT"
        end
        result.materials=materials;result.materialState=materials.emptyReagents and
            "EMPTY_REAGENT_SLOTS_NOT_FREE_CRAFT" or "RAW_REAGENTS_AVAILABLE"
    end
    result.priceState="NOT_REQUESTED"
    if options.includeEconomy==true then
        if result.materials==nil or result.materials.emptyReagents then
            result.priceState="REAGENT_EVIDENCE_INSUFFICIENT"
        else
            local receipt,reason=econ:QuoteRecipe(ctx.professionKey,spellID,crafts,BUILD,options)
            if not receipt then return nil,reason end
            if receipt.professionKey~=ctx.professionKey or receipt.spellID~=spellID or
               receipt.sourceBuild~=BUILD or receipt.nativeDispatchAllowed~=false then
                return nil,"ECONOMY_CONTRACT_CONFLICT"
            end
            result.economy=receipt
            result.priceState=receipt.cost.grossVerified and "AH_PRICE_VERIFIED_AT_READ_TIME" or
                (receipt.cost.grossComplete and "INDICATIVE_NOT_MARKET_VERIFIED" or "PRICE_INCOMPLETE")
        end
    end
    return result
end
function Bridge:BuildMaterialsState(steps,options)
    options=type(options)=="table" and options or {}
    if type(steps)~="table" or #steps<1 or #steps>200 then return nil,"INVALID_STEPS" end
    local first
    local normalized={}
    for index,step in ipairs(steps) do
        if type(step)~="table" then return nil,"INVALID_STEP" end
        local ctx,err=context(step.professionKey,options)
        if not ctx then return nil,"STEP_"..index.."_"..tostring(err) end
        if not first then first=ctx end
        normalized[#normalized+1]={professionKey=ctx.professionKey,
            spellID=step.spellID,crafts=step.crafts}
    end
    local econ=module("ProfessionEconomy70374")
    if not econ then return nil,"ECONOMY_UNAVAILABLE" end
    local bill,reason=econ:BuildBill(normalized,BUILD,options)
    if not bill then return nil,reason end
    if bill.sourceBuild~=BUILD or bill.nativeDispatchAllowed~=false then
        return nil,"BATCH_CONTRACT_CONFLICT"
    end
    local result=shell(first,"CROSS_PROFESSION_MATERIALS")
    result.professionKey=nil;result.skillLineID=nil;result.professionEnum=nil
    result.professionKeys={}
    local seen={}
    for _,step in ipairs(normalized) do
        if not seen[step.professionKey] then
            seen[step.professionKey]=true
            result.professionKeys[#result.professionKeys+1]=step.professionKey
        end
    end
    result.bill=bill;result.priceState="NOT_REQUESTED"
    if options.includeEconomy==true then
        local quote,why=econ:QuoteBill(bill,options)
        if not quote then return nil,why end
        result.quote=quote
        result.priceState=quote.grossVerified and "AH_PRICE_VERIFIED_AT_READ_TIME" or
            (quote.grossComplete and "INDICATIVE_NOT_MARKET_VERIFIED" or "PRICE_INCOMPLETE")
    end
    return result
end
function Bridge:GetProgressionState(key,skill,options)
    local ctx,err=context(key,options)
    if not ctx then return nil,err end
    if not integer(skill,true) or skill>999 then return nil,"INVALID_SKILL" end
    options=type(options)=="table" and options or {}
    local econ=module("ProfessionEconomy70374")
    if not econ then return nil,"ECONOMY_UNAVAILABLE" end
    local offset=options.offset or 0
    local limit=options.limit or 10
    local candidates,reason=econ:GetProgressionCandidates(ctx.professionKey,skill,BUILD,offset,limit)
    if not candidates then return nil,reason end
    if candidates.professionKey~=ctx.professionKey or candidates.sourceBuild~=BUILD or
       candidates.nativeDispatchAllowed~=false then return nil,"PROGRESSION_CONTRACT_CONFLICT" end
    local result=shell(ctx,"PROGRESSION_STATE")
    result.skill=skill;result.candidates=candidates
    result.progressionVerified=false;result.completeLevelingRoute=false
    if options.targetSkill~=nil then
        local worksheet,why=econ:BuildProgressionWorksheet(ctx.professionKey,skill,
            options.targetSkill,BUILD,{interval=options.interval or 25})
        if not worksheet then return nil,why end
        result.worksheet=worksheet
    end
    return result
end
function Bridge:ValidateState(state)
    if type(state)~="table" or state.contract~=self.contract or state.sourceBuild~=BUILD or
       (state.clientBuild~=nil and (type(state.clientBuild)~="number" or
           state.clientBuild<=0 or state.clientBuild~=math.floor(state.clientBuild) or
           state.clientBuild>9007199254740991)) or
       state.nativeDispatchAllowed~=false or state.executionEligible~=false or
       state.readOnly~=true or type(state.revision)~="table" then
        return false,"INVALID_COMMUNICATION_CONTRACT"
    end
    -- UNKNOWN-to-known is a different session; reissue the read-only receipt.
    if actualBuild()~=state.clientBuild then return false,"CLIENT_BUILD_CHANGED_OR_UNKNOWN" end
    for domain,number in pairs(self.revisions) do
        if state.revision[domain]~=number then
            return false,"STALE_"..string.upper(domain).."_REVISION"
        end
    end
    if state.kind=="CROSS_PROFESSION_MATERIALS" then
        if type(state.professionKeys)~="table" or type(state.bill)~="table" or
           state.bill.nativeDispatchAllowed~=false or state.bill.sourceBuild~=BUILD then
            return false,"INVALID_BATCH_CONTRACT"
        end
        for _,key in ipairs(state.professionKeys) do
            if not matchingIdentity(key) then return false,"BATCH_PROFESSION_IDENTITY_CONFLICT" end
        end
    else
        local ctx,why=context(state.professionKey,{skillLineID=state.skillLineID,
            professionEnum=state.professionEnum})
        if not ctx then return false,why end
    end
    if state.kind=="RECIPE_STATE" then
        local econ=module("ProfessionEconomy70374")
        local raw=module("Build70374ProfessionReference")
        if not econ or not raw or not integer(state.spellID) or not integer(state.crafts) then
            return false,"INVALID_RECIPE_CONTRACT"
        end
        local expected,err=raw:GetRecipe(state.professionKey,state.spellID,BUILD)
        if not expected or expected.name~=state.recipeName or
           not isReferenceRecipe(expected,{professionKey=state.professionKey,
               skillLineID=state.skillLineID},state.spellID) then
            return false,err or "RECIPE_SOURCE_CHANGED"
        end
        if expected.reagents then
            local verified= econ:GetRecipeMaterials(state.professionKey,state.spellID,state.crafts,BUILD)
            if not verified or type(state.materials)~="table" or
               #verified.requirements~=#(state.materials.requirements or {}) then
                return false,"MATERIALS_REFERENCE_CHANGED"
            end
            for index,row in ipairs(verified.requirements) do
                local actual=state.materials.requirements[index]
                if not actual or actual.itemID~=row.itemID or
                   actual.perCraft~=row.perCraft or actual.rawTotal~=row.rawTotal then
                    return false,"MATERIAL_QUANTITY_MISMATCH"
                end
            end
        elseif state.materials~=nil then
            return false,"MISSING_REAGENT_EVIDENCE_CONFLICT"
        end
        if state.economy and state.priceState=="AH_PRICE_VERIFIED_AT_READ_TIME" then
            local ok,reason=econ:RecheckQuoteReceipts(state.economy.cost)
            if not ok then return false,reason end
        end
    elseif state.kind=="CROSS_PROFESSION_MATERIALS" and state.quote and
           state.priceState=="AH_PRICE_VERIFIED_AT_READ_TIME" then
        local econ=module("ProfessionEconomy70374")
        if not econ then return false,"ECONOMY_UNAVAILABLE" end
        local ok,reason=econ:RecheckQuoteReceipts(state.quote)
        if not ok then return false,reason end
    end
    return true,"COMMUNICATION_CURRENT_READ_ONLY"
end
JLP:RegisterModule("ProfessionDataBridge70374",Bridge)
