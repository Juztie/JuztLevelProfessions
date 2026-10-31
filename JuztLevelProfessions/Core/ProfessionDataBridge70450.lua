local _, JLP = ...

-- M4 successor for Forever 1.60.1.70450. This is a versioned, read-only
-- communications boundary, NOT a replacement for the native crafting gate.
-- In particular, historical 70374 economics/receipts are never reused here.
local Bridge = {
    contract="JLP-PROFESSION-DATA-BRIDGE-70450-1", sourceBuild=70450,
    readOnly=true, executionEligible=false, nativeDispatchAllowed=false,
    productionAuthority=false, purchaseAllowed=false, routeAllowed=false,
    revisions={price=0,inventory=0,profession=0}, initialized=false,
}
local BUILD=70450
local function mod(k) return JLP:GetModule(k) end
local function uint(n,zero,max)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and
        n==math.floor(n) and n>=(zero and 0 or 1) and n<=(max or 999999999)
end
local function observed()
    local info=mod("ClientBuildInfo")
    if not info or type(info.GetBuildNumber)~="function" then return nil end
    local ok,n=pcall(info.GetBuildNumber,info)
    -- Client builds are NOT bounded by the 999,999,999 data/quantity limit.
    return ok and type(n)=="number" and n==n and n>0 and
        n==math.floor(n) and n<=9007199254740991 and n or nil
end
local function rev()
    return {price=Bridge.revisions.price,inventory=Bridge.revisions.inventory,
        profession=Bridge.revisions.profession}
end
local function context(key,options)
    options=type(options)=="table" and options or {}
    if options.sourceBuild~=nil and options.sourceBuild~=BUILD then return nil,"SOURCE_BUILD_MISMATCH" end
    -- Reading an archived, read-only source does not require a live build.
    -- Actual client evidence and native execution remain separate gates.
    local live=observed()
    local registry=mod("ProfessionRegistry")
    if not registry or not registry.NormalizeKey or not registry.Get then return nil,"REGISTRY_UNAVAILABLE" end
    local normalized=registry:NormalizeKey(key)
    local def=normalized and registry:Get(normalized)
    if not def or not uint(def.skillLineID) then return nil,"UNKNOWN_PROFESSION" end
    if options.skillLineID~=nil and options.skillLineID~=def.skillLineID then
        return nil,"SKILL_LINE_ID_CONFLICT"
    end
    if options.professionEnum~=nil and options.professionEnum~=def.professionEnum then
        return nil,"PROFESSION_ENUM_CONFLICT"
    end
    local recipes=JLP.data and JLP.data.build70450Recipes
    local source=recipes and recipes.professions and recipes.professions[normalized]
    if not recipes or recipes.contract~="JLP-OWNER-BUILD70450-RECIPES-1" or
       recipes.sourceBuild~=BUILD or recipes.readOnly~=true or
       recipes.nativeDispatchAllowed~=false or not source or
       source.skillLineID~=def.skillLineID or type(source.packed)~="string" then
        return nil,"SOURCE_REGISTRY_OR_AUTHORITY_CONFLICT"
    end
    return {professionKey=normalized,skillLineID=def.skillLineID,
        professionEnum=def.professionEnum,category=def.category,
        progressionStrategy=def.progressionStrategies and def.progressionStrategies[1] or "UNKNOWN",
        sourceBuild=BUILD,clientBuild=live,productionMaturity=def.maturity and
        def.maturity.production==true or false,revision=rev()}
end
local function shell(ctx,kind)
    return {contract=Bridge.contract,kind=kind,sourceBuild=BUILD,
        clientBuild=ctx.clientBuild,professionKey=ctx.professionKey,
        skillLineID=ctx.skillLineID,professionEnum=ctx.professionEnum,
        category=ctx.category,progressionStrategy=ctx.progressionStrategy,
        revision=ctx.revision,sourceQualification="OWNER_70450_DB2_REFERENCE_ONLY",
        currentBuildSourceMatched=ctx.clientBuild==BUILD,
        clientBuildRelation=not ctx.clientBuild and "UNKNOWN_CLIENT" or
            (ctx.clientBuild==BUILD and "MATCH" or "HISTORICAL_REFERENCE"),
        clientRecipeVerified=false,
        recipeAccessVerified=false,craftingReady=false,
        productionAuthority=false,executionEligible=false,nativeDispatchAllowed=false,
        purchaseAllowed=false,routeAllowed=false,readOnly=true}
end
local function recipeIdentity(row,ctx,spellID)
    return type(row)=="table" and row.sourceBuild==BUILD and
        row.professionKey==ctx.professionKey and row.skillLineID==ctx.skillLineID and
        row.spellID==spellID and row.nativeDispatchAllowed==false and
        row.executionEligible==false and row.productionAuthority==false and
        row.readOnly==true
end
function Bridge:MarkChanged(domain)
    if self.revisions[domain]==nil then return false,"UNKNOWN_REVISION_DOMAIN" end
    self.revisions[domain]=self.revisions[domain]<1000000000 and self.revisions[domain]+1 or 1
    if JLP.EventBus and type(JLP.EventBus.Emit)=="function" then
        JLP.EventBus:Emit("PROFESSION_DATA_70450_INVALIDATED",domain,self.revisions[domain])
    end
    return true
end
function Bridge:Initialize()
    if self.initialized then return true end
    local bus=JLP.EventBus
    if not bus or type(bus.On)~="function" then return false,"EVENT_BUS_UNAVAILABLE" end
    local groups={
        price={"AH_SNAPSHOT_UPDATED","AH_SCAN_EXPIRED","AH_SCAN_STARTED"},
        inventory={"PROFESSION_TRANSACTION_UPDATED","PROFESSION_CRAFT_OBSERVED","JLP_INVENTORY_DATA_REFRESHED"},
        profession={"PROFESSION_PROGRESS_UPDATED","PROFESSION_CRAFT_OBSERVED",
            "RECIPE_ACCESS_EVIDENCE_UPDATED","PROFESSION_RUNTIME_STATE_UPDATED"},
    }
    for domain,events in pairs(groups) do
        for _,event in ipairs(events) do
            local d=domain
            bus:On(event,function() self:MarkChanged(d) end)
        end
    end
    self.initialized=true
    return true
end
function Bridge:OnClientDataEvent(event)
    if event=="BAG_UPDATE_DELAYED" or event=="BANKFRAME_OPENED" or
       event=="BANKFRAME_CLOSED" or event=="PLAYERBANKSLOTS_CHANGED" or
       event=="PLAYERBANKBAGSLOTS_CHANGED" or event=="BAG_CONTAINER_UPDATE" or
       event=="PLAYERREAGENTBANKSLOTS_CHANGED" or event=="PLAYER_LOGIN" then
        self:MarkChanged("inventory")
    elseif event=="SKILL_LINES_CHANGED" or event=="TRADE_SKILL_LIST_UPDATE" or
           event=="NEW_RECIPE_LEARNED" or event=="LEARNED_SPELL_IN_TAB" or
           event=="TRADE_SKILL_UPDATE" then self:MarkChanged("profession") end
end
function Bridge:GetProfessionState(key,options)
    local ctx,why=context(key,options)
    if not ctx then return nil,why end
    local recipes=mod("Build70450RecipeCatalogue")
    if not recipes then return nil,"CATALOGUE_UNAVAILABLE" end
    local coverage,err=recipes:GetCoverage()
    if not coverage then return nil,err end
    local c=coverage.byProfession and coverage.byProfession[ctx.professionKey]
    if not c or coverage.sourceBuild~=BUILD or
        coverage.nativeDispatchAllowed~=false then return nil,"COVERAGE_CONTRACT_CONFLICT" end
    local result=shell(ctx,"PROFESSION_STATE")
    result.abilityRows=c.abilityRows
    result.uniqueSpells=c.uniqueSpells
    result.recipeCandidates=c.recipeCandidates
    result.abilityOnly=c.abilityOnly
    result.reagentRecords=c.reagentRecords
    result.missingSpellNames=c.missingSpellNames
    result.fullProductionCatalogueComplete=false
    result.acquisitionQualification="UNVERIFIED_SERVER_ACCESS"
    return result,nil
end
function Bridge:GetRecipeState(key,spellID,crafts,options)
    local ctx,why=context(key,options)
    if not ctx then return nil,why end
    if not uint(spellID) then return nil,"INVALID_SPELL_ID" end
    if not uint(crafts,false,9999) then return nil,"INVALID_CRAFT_COUNT" end
    local ref=mod("Build70450RecipeCatalogue")
    local combined=mod("MaterialsSources70450")
    if not ref or not combined then return nil,"REFERENCE_MODULE_UNAVAILABLE" end
    local recipe,err=ref:GetRecipe(ctx.professionKey,spellID,BUILD)
    if not recipe then return nil,err end
    if not recipeIdentity(recipe,ctx,spellID) then return nil,"RECIPE_IDENTITY_OR_AUTHORITY_CONFLICT" end
    local material,materialError=ref:GetMaterialNeeds(ctx.professionKey,spellID,crafts,BUILD)
    if not material and materialError~="NO_REAGENT_RECORD" then
        return nil,materialError or "MATERIAL_REFERENCE_INVALID"
    end
    if material and (material.sourceBuild~=BUILD or material.professionKey~=ctx.professionKey or
        material.spellID~=spellID or material.crafts~=crafts or
        material.nativeDispatchAllowed~=false or material.readOnly~=true) then
        return nil,"MATERIALS_CONTRACT_CONFLICT"
    end
    local flow,flowError=combined:GetRecipe(ctx.professionKey,spellID,crafts,BUILD)
    if not flow then return nil,flowError end
    if flow.sourceBuild~=BUILD or flow.professionKey~=ctx.professionKey or
        flow.spellID~=spellID or flow.crafts~=crafts or
        flow.nativeDispatchAllowed~=false or flow.productionAuthority~=false then
        return nil,"FLOW_CONTRACT_CONFLICT"
    end
    local result=shell(ctx,"RECIPE_STATE")
    result.spellID=spellID;result.crafts=crafts
    result.recipeName=recipe.name;result.recordKind=recipe.recordKind
    result.materials=material;result.materialState=flow.materialState
    result.itemRows=flow.itemRows;result.stockComplete=flow.stockComplete
    result.output=flow.output;result.outputState=flow.outputStatus
    result.skillDifficulty=recipe.skillDifficulty
    result.sourceStatus=flow.sourceStatus
    result.acquisitionVerifiedLive=false;result.outputYieldVerifiedLive=false
    -- Independent source/rights receipt is advisory even when SOURCE_QUALIFIED.
    -- It does not update native execution flags or purchase/route permissions.
    local admission=mod("Build70450ProductionQualification")
    if not admission then return nil,"PRODUCTION_QUALIFICATION_MODULE_UNAVAILABLE" end
    local qualified=admission:AssessRecipe(ctx.professionKey,spellID,BUILD)
    if type(qualified)~="table" or qualified.nativeDispatchAllowed~=false or
        qualified.executionEligible~=false or qualified.productionAuthority~=false or
        qualified.readOnly~=true then
        return nil,"QUALIFICATION_AUTHORITY_CONTRACT_CONFLICT"
    end
    result.sourceQualification={state=qualified.state,reason=qualified.reason,
        sourceQualified=qualified.sourceQualified,sourceBuild=BUILD,
        productionAuthority=false,executionEligible=false,nativeDispatchAllowed=false,
        readOnly=true}
    result.recipeAccess="UNKNOWN";result.learnedOnCharacter="UNKNOWN"
    result.priceState="NO_CURRENT_70450_MARKET_RECEIPT";result.economy=nil
    return result,nil
end
function Bridge:BuildMaterialsState(steps,options)
    options=type(options)=="table" and options or {}
    if type(steps)~="table" or #steps<1 or #steps>200 then return nil,"INVALID_STEPS" end
    local catalogue=mod("Build70450RecipeCatalogue")
    if not catalogue then return nil,"CATALOGUE_UNAVAILABLE" end
    local aggregated,stepReceipts,keys={}, {}, {}
    local count=0;local incomplete=0;local first=nil
    for index,step in ipairs(steps) do
        if type(step)~="table" then return nil,"INVALID_STEP_"..index end
        local ctx,why=context(step.professionKey,options)
        if not ctx then return nil,"STEP_"..index.."_"..tostring(why) end
        if not uint(step.spellID) or not uint(step.crafts,false,9999) then
            return nil,"STEP_"..index.."_INVALID_RECIPE_OR_CRAFT_COUNT"
        end
        first=first or ctx
        keys[ctx.professionKey]=true
        local recipe,err=catalogue:GetRecipe(ctx.professionKey,step.spellID,BUILD)
        if not recipe or not recipeIdentity(recipe,ctx,step.spellID) then
            return nil,"STEP_"..index.."_"..tostring(err or "RECIPE_CONTRACT_CONFLICT")
        end
        local materials,reason=catalogue:GetMaterialNeeds(ctx.professionKey,step.spellID,step.crafts,BUILD)
        if not materials and reason~="NO_REAGENT_RECORD" then
            return nil,"STEP_"..index.."_"..tostring(reason)
        end
        if materials and (materials.sourceBuild~=BUILD or materials.nativeDispatchAllowed~=false or
            materials.readOnly~=true or materials.professionKey~=ctx.professionKey or
            materials.spellID~=step.spellID or materials.crafts~=step.crafts) then
            return nil,"STEP_"..index.."_MATERIALS_CONTRACT_CONFLICT"
        end
        stepReceipts[#stepReceipts+1]={professionKey=ctx.professionKey,spellID=step.spellID,
            crafts=step.crafts,reagentState=recipe.reagentState,
            complete=materials~=nil,readOnly=true,nativeDispatchAllowed=false}
        if not materials then incomplete=incomplete+1 else
            for _,item in ipairs(materials.requirements or {}) do
                if not uint(item.itemID) or not uint(item.rawTotal) or
                    not uint(item.perCraft) or item.perCraft*step.crafts~=item.rawTotal then
                    return nil,"STEP_"..index.."_INVALID_MATERIAL_QUANTITY"
                end
                local n=(aggregated[item.itemID] or 0)+item.rawTotal
                if n>999999999 then return nil,"MATERIAL_TOTAL_OVERFLOW" end
                aggregated[item.itemID]=n
            end
        end
        count=count+1
    end
    local state=shell(first,"CROSS_PROFESSION_MATERIALS")
    state.professionKey=nil;state.skillLineID=nil;state.professionEnum=nil
    state.professionKeys={}
    for key in pairs(keys) do state.professionKeys[#state.professionKeys+1]=key end
    table.sort(state.professionKeys)
    state.steps=stepReceipts;state.stepCount=count
    state.unresolvedStepCount=incomplete
    state.materialState=incomplete==0 and "SOURCE_REAGENTS_COMPLETE" or "INCOMPLETE_REAGENT_EVIDENCE"
    state.requirements=nil
    if incomplete==0 then
        state.requirements={}
        for id,total in pairs(aggregated) do
            state.requirements[#state.requirements+1]={itemID=id,rawTotal=total,
                sourceBuild=BUILD,readOnly=true,nativeDispatchAllowed=false}
        end
        table.sort(state.requirements,function(a,b) return a.itemID<b.itemID end)
    end
    state.costStatus="NO_70450_MARKET_RECEIPT"
    state.purchaseQuantitiesVerified=false
    return state,nil
end
function Bridge:GetProgressionState(key,skill,options)
    local ctx,why=context(key,options)
    if not ctx then return nil,why end
    if not uint(skill,true,9999) then return nil,"INVALID_SKILL" end
    options=type(options)=="table" and options or {}
    local offset=options.offset or 0;local limit=options.limit or 10
    if not uint(offset,true,100000) or not uint(limit,false,30) then
        return nil,"INVALID_CANDIDATE_PAGE"
    end
    local catalogue=mod("Build70450RecipeCatalogue")
    if not catalogue then return nil,"CATALOGUE_UNAVAILABLE" end
    -- Raw source order, not a recommended leveling path. Colour between
    -- yellow/grey and trainer access are explicitly not inferred.
    local page,err=catalogue:GetPage(ctx.professionKey,offset,limit,BUILD,
        {recordKind="RECIPE_CANDIDATE"})
    if not page then return nil,err end
    if page.sourceBuild~=BUILD or page.professionKey~=ctx.professionKey or
        page.nativeDispatchAllowed~=false then return nil,"PAGE_CONTRACT_CONFLICT" end
    local result=shell(ctx,"PROGRESSION_STATE")
    result.skill=skill;result.offset=offset;result.limit=limit
    result.totalReferenceCandidates=page.totalMatches
    result.candidates={}
    for _,row in ipairs(page.rows) do
        if not recipeIdentity(row,ctx,row.spellID) then return nil,"CANDIDATE_CONTRACT_CONFLICT" end
        local difficulty=row.skillDifficulty
        result.candidates[#result.candidates+1]={spellID=row.spellID,name=row.name,
            yellow=difficulty and difficulty.yellow or nil,
            grey=difficulty and difficulty.grey or nil,
            boundaryStatus=difficulty and difficulty.yellowGreyState or "UNKNOWN",
            orange=nil,green=nil,accessVerified=false,craftEligible=false,
            productionAuthority=false,readOnly=true,nativeDispatchAllowed=false}
    end
    result.completeLevelingRoute=false
    result.skillUpProbability="UNKNOWN"
    return result,nil
end
-- A communicated receipt must be revalidated at the point of consumption;
-- externally edited receipts never imply a trusted command or production plan.
local forbidden={"nativeDispatchAllowed","executionEligible","productionAuthority",
    "purchaseAllowed","routeAllowed","craftingReady","productionReady","craftEligible",
    "routeEligible","cannotAutoBuy","cannotAutoCraft","cannotAutoRoute"}
local function safeTree(value,depth,seen)
    if type(value)~="table" then return true end
    if depth>8 or seen[value] then return false end
    seen[value]=true
    for k,v in pairs(value) do
        if k=="readOnly" and v==false then return false end
        if (k=="cannotAutoBuy" or k=="cannotAutoCraft" or k=="cannotAutoRoute") and v==false then return false end
        for _,field in ipairs(forbidden) do
            if k==field and field~="cannotAutoBuy" and field~="cannotAutoCraft" and
               field~="cannotAutoRoute" and v==true then return false end
        end
        if type(v)=="table" and not safeTree(v,depth+1,seen) then return false end
    end
    seen[value]=nil
    return true
end
local function sameMaterials(a,b)
    if (a==nil)~=(b==nil) then return false end
    if not a then return true end
    if a.sourceBuild~=BUILD or a.nativeDispatchAllowed~=false or a.readOnly~=true or
        #a.requirements~=#b.requirements then return false end
    for i,row in ipairs(a.requirements) do
        local expected=b.requirements[i]
        if not expected or row.itemID~=expected.itemID or
            row.perCraft~=expected.perCraft or row.rawTotal~=expected.rawTotal then
            return false
        end
    end
    return true
end
local function deepEqual(a,b,depth)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    if depth>14 then return false end
    for k,v in pairs(a) do
        if b[k]==nil or not deepEqual(v,b[k],depth+1) then return false end
    end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function Bridge:ValidateState(state)
    if type(state)~="table" or state.contract~=self.contract or state.sourceBuild~=BUILD or
       (state.clientBuild~=nil and (type(state.clientBuild)~="number" or
           state.clientBuild<=0 or state.clientBuild~=math.floor(state.clientBuild) or
           state.clientBuild>9007199254740991)) or state.nativeDispatchAllowed~=false or
       state.productionAuthority~=false or state.executionEligible~=false or
       state.readOnly~=true or state.purchaseAllowed~=false or state.routeAllowed~=false or
       type(state.revision)~="table" or not safeTree(state,0,{}) then
        return false,"INVALID_OR_PRIVILEGED_COMMUNICATION_CONTRACT"
    end
    -- UNKNOWN-to-known is a different session; reissue the read-only receipt.
    if observed()~=state.clientBuild then return false,"CLIENT_BUILD_CHANGED_OR_UNKNOWN" end
    for domain,n in pairs(self.revisions) do
        if state.revision[domain]~=n then return false,"STALE_"..string.upper(domain).."_REVISION" end
    end
    if state.kind=="CROSS_PROFESSION_MATERIALS" then
        if type(state.steps)~="table" or #state.steps~=state.stepCount or
           type(state.professionKeys)~="table" then return false,"INVALID_BATCH_STATE" end
        local steps={}
        for _,r in ipairs(state.steps) do
            steps[#steps+1]={professionKey=r.professionKey,spellID=r.spellID,crafts=r.crafts}
        end
        local fresh,err=self:BuildMaterialsState(steps,{sourceBuild=BUILD})
        if not fresh then return false,err end
        if fresh.materialState~=state.materialState or
            fresh.unresolvedStepCount~=state.unresolvedStepCount or
            #fresh.professionKeys~=#state.professionKeys then return false,"BATCH_SOURCE_CHANGED" end
        for i,key in ipairs(fresh.professionKeys) do
            if state.professionKeys[i]~=key then return false,"BATCH_IDENTITY_CHANGED" end
        end
        if (fresh.requirements==nil)~=(state.requirements==nil) then return false,"BATCH_MATERIALS_CHANGED" end
        if fresh.requirements then
            if #fresh.requirements~=#state.requirements then return false,"BATCH_QUANTITY_CHANGED" end
            for i,row in ipairs(fresh.requirements) do
                local actual=state.requirements[i]
                if not actual or actual.itemID~=row.itemID or actual.rawTotal~=row.rawTotal then
                    return false,"BATCH_QUANTITY_CHANGED"
                end
            end
        end
        if not deepEqual(state,fresh,0) then return false,"BATCH_RECEIPT_TAMPERED" end
    else
        local ctx,err=context(state.professionKey,{sourceBuild=BUILD,
            skillLineID=state.skillLineID,professionEnum=state.professionEnum})
        if not ctx then return false,err end
        if state.kind=="RECIPE_STATE" then
            if not uint(state.spellID) or not uint(state.crafts,false,9999) then
                return false,"INVALID_RECIPE_STATE" end
            local fresh,why=self:GetRecipeState(ctx.professionKey,state.spellID,state.crafts,
                {sourceBuild=BUILD})
            if not fresh then return false,why end
            if state.recipeName~=fresh.recipeName or state.recordKind~=fresh.recordKind or
               state.materialState~=fresh.materialState or state.outputState~=fresh.outputState or
               state.sourceStatus~=fresh.sourceStatus or not sameMaterials(state.materials,fresh.materials) then
                return false,"RECIPE_REFERENCE_CHANGED"
            end
            if type(state.itemRows)~="table" or #state.itemRows~=#fresh.itemRows then
                return false,"ITEM_RECEIPT_CHANGED" end
            for i,row in ipairs(state.itemRows) do
                local expected=fresh.itemRows[i]
                if not row or row.itemID~=expected.itemID or row.required~=expected.required or
                    row.sourceStatus~=expected.sourceStatus then return false,"ITEM_RECEIPT_CHANGED" end
            end
            if not deepEqual(state,fresh,0) then return false,"RECIPE_RECEIPT_TAMPERED" end
        elseif state.kind=="PROFESSION_STATE" then
            local fresh,why=self:GetProfessionState(ctx.professionKey,{sourceBuild=BUILD})
            if not fresh then return false,why end
            for _,field in ipairs({"abilityRows","uniqueSpells","recipeCandidates","abilityOnly",
                "reagentRecords","missingSpellNames"}) do
                if state[field]~=fresh[field] then return false,"PROFESSION_REFERENCE_CHANGED" end
            end
            if not deepEqual(state,fresh,0) then return false,"PROFESSION_RECEIPT_TAMPERED" end
        elseif state.kind=="PROGRESSION_STATE" then
            local fresh,why=self:GetProgressionState(ctx.professionKey,state.skill,
                {sourceBuild=BUILD,offset=state.offset,limit=state.limit})
            if not fresh then return false,why end
            if state.totalReferenceCandidates~=fresh.totalReferenceCandidates or
                type(state.candidates)~="table" or #state.candidates~=#fresh.candidates then
                return false,"PROGRESSION_REFERENCE_CHANGED" end
            for i,row in ipairs(state.candidates) do
                local expected=fresh.candidates[i]
                if row.spellID~=expected.spellID or row.yellow~=expected.yellow or
                    row.grey~=expected.grey or row.boundaryStatus~=expected.boundaryStatus then
                    return false,"PROGRESSION_REFERENCE_CHANGED" end
            end
            if not deepEqual(state,fresh,0) then return false,"PROGRESSION_RECEIPT_TAMPERED" end
        else return false,"UNKNOWN_COMMUNICATION_KIND" end
    end
    return true,"CURRENT_70450_READ_ONLY_REFERENCE"
end
JLP:RegisterModule("ProfessionDataBridge70450",Bridge)
