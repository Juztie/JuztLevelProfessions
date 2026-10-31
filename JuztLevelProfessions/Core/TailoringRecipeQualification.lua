local _, JLP = ...
-- Tailoring 1-300: field-wise read-only qualification. Nothing in this
-- module can grant native dispatch, persist a receipt or prove future skillups.
local Qualification={contract="tailoring-recipe-progression-qualification-v1"}
-- Field-wise DB2 evidence joins the existing qualified recipe, never grants
-- learned-state, green thresholds, yield, rank cap or native authority.
function Qualification:DB2Recipe(id,reagents,outputID)
    local data=JLP.data and JLP.data.tailoring and JLP.data.tailoring.db2
    if not data then return nil,"DB2_NOT_IMPORTED" end
    local row=data.contract=="tailoring-db2-70532-fields-v1" and data.sourceBuild==70532 and
        data.recipes and data.recipes[id]
    if not row or row.skillLineID~=197 or row.skillupSkillLineID~=2948 or
        row.reagents~=reagents or row.outputItemID~=outputID then return nil,"DB2_RECIPE_FIELD_CONFLICT" end
    return row,"DB2_FIELDS_MATCH"
end
function Qualification:AnnotateDB2(row)
    local data=JLP.data and JLP.data.tailoring and JLP.data.tailoring.db2
    if not (data and data.recipes and data.recipes[row.recipeID]) then return row end
    local reagents={}
    for _,m in ipairs(row.materials or {})do reagents[#reagents+1]=tostring(m.itemID)..":"..tostring(m.quantity) end
    local fact,status=self:DB2Recipe(row.recipeID,table.concat(reagents,","),row.outputItemID or data.recipes[row.recipeID].outputItemID)
    if not fact then return nil,status end
    row.db2Evidence={sourceBuild=70532,manifestSHA256=data.manifestSHA256,
        abilityID=fact.abilityID,reagentRecordID=fact.reagentRecordID,effectID=fact.effectID,
        rawMinimum=fact.minSkillLineRank,rawTrivialLow=fact.trivialLow,rawTrivialHigh=fact.trivialHigh,
        minimumStatus="DB2_NOT_LEARNING_MINIMUM",greenStatus="DB2_DOES_NOT_PROVE_GREEN",
        outputStatus="ITEM_IDENTITY_NOT_YIELD",readOnly=true,nativeDispatchAllowed=false}
    -- Raw base and minimum cast durations are a conditional source scenario,
    -- not measured runtime cast/total time or a reason to assume free travel.
    if type(fact.castBaseMS)=="number" and fact.castBaseMS>0 and
        type(fact.castMinimumMS)=="number" and fact.castMinimumMS>0 and fact.castMinimumMS<=fact.castBaseMS then
        row.castSeconds=fact.castBaseMS/1000;row.castMinimumSeconds=fact.castMinimumMS/1000
        row.castTimeAuthority="DB2_70532_BASE_DURATION_SCENARIO_NOT_LIVE_TIME"
    end
    if row.recipeID==3758 then
        local pattern=data.pattern4292
        if pattern and pattern.itemID==4292 and pattern.requiredSkill==197 and pattern.requiredSkillRank==75 and
            pattern.relatedRecipeID==3758 and pattern.recipeTriggerType==6 and pattern.useSpellID==402265 then
            row.patternReference={itemID=4292,requiredSkill=197,requiredSkillRank=75,
                relatedRecipeID=3758,useSpellID=402265,sourceBuild=70532,
                source="ITEM_SPARSE_AND_ITEM_EFFECT_JOIN",recipeMinimumStatus="UNKNOWN",
                possessionStatus="UNKNOWN",readOnly=true,nativeDispatchAllowed=false}
        end
    end
    return row
end
function Qualification:ScenarioCastSeconds(row,crafts)
    if not (crafts and row.castTimeAuthority and row.castSeconds) then return nil end
    local seconds=row.castSeconds*crafts
    if row.cooldownMS then seconds=seconds+math.max(0,crafts-1)*row.cooldownMS/1000 end
    local pool=row.planningInventory or self:PlanningInventory()
    for _,material in ipairs(row.materials or {})do
        if material.source=="crafted" then
            local owned=pool[material.itemID]
            if owned==nil then return nil end
            local missing=math.max(0,material.quantity*crafts-owned)
            if missing>0 then
                local producer=material.craftedFrom
                local data=JLP.data.tailoring.db2
                local fact=producer and data and data.recipes[producer.producerRecipeID]
                if not (fact and producer.outputPerCraft==1 and fact.castBaseMS>0 and
                    self:DB2Recipe(producer.producerRecipeID,tostring(producer.itemID)..":"..tostring(producer.quantity),material.itemID)) then
                    return nil
                end
                seconds=seconds+missing*fact.castBaseMS/1000
            end
        end
    end
    return seconds
end
function Qualification:DB2Alternatives(rows)
    local result={}
    for _,row in ipairs(rows)do
        local joined=self:AnnotateDB2(row)
        if joined then result[#result+1]=joined end
    end
    return #result>0 and result or nil
end
local function integer(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge and v%1==0
end
local function stepAt(skill)
    local dataset=JLP.data and JLP.data.tailoring
    if not dataset or not integer(skill) or skill<1 or skill>=300 then return nil,nil end
    for i,step in ipairs(dataset.route or {}) do
        if type(step.skillMin)=="number" and type(step.skillTarget)=="number" and
           skill>=step.skillMin and skill<step.skillTarget then return step,i end
    end
    return nil,nil
end
local function copyMaterials(materials)
    local out={}
    if type(materials)~="table" then return out,false end
    local valid=true
    for _,m in ipairs(materials) do
        if type(m)~="table" or not integer(m.itemID) or m.itemID<=0 or
           not integer(m.quantity) or m.quantity<=0 then valid=false
        else out[#out+1]={itemID=m.itemID,quantity=m.quantity,name=m.name,
                source=m.source,sourceBuild=nil} end
    end
    return out,valid and #out==#materials and #out>0
end
local function aggregate(list)
    local t={}
    for _,m in ipairs(list) do t[m.itemID]=(t[m.itemID] or 0)+m.quantity end
    return t
end
local function equalMaterials(a,b)
    local x,y=aggregate(a),aggregate(b)
    for k,n in pairs(x) do if y[k]~=n then return false end end
    for k,n in pairs(y) do if x[k]~=n then return false end end
    return true
end
local function describe(step,index,duplicates)
    local materials,valid=copyMaterials(step.materials)
    local validID=integer(step.recipeID) and step.recipeID>0
    local craftCount=integer(step.expectedCrafts) and step.expectedCrafts>0 and step.expectedCrafts or nil
    local conflicted=step.outputQuantityConflictingReference~=nil and
       step.outputQuantityConflictingReference~=step.outputQuantityReference
    local repeatEstimate=craftCount~=nil and duplicates[index]==true
    local warnings={}
    if not validID then warnings[#warnings+1]="RECIPE_ID_NOT_DOCUMENTED" end
    if not valid then warnings[#warnings+1]="REAGENT_REFERENCE_INCOMPLETE" end
    if step.recipeAccessObserved~=true then warnings[#warnings+1]="LEARNED_STATE_NOT_OBSERVED" end
    if not craftCount or step.craftCountQualified~=true then warnings[#warnings+1]="CRAFT_COUNT_NOT_LIVE_QUALIFIED" end
    if repeatEstimate then warnings[#warnings+1]="SPLIT_WINDOW_REUSES_HISTORICAL_CRAFT_ESTIMATE" end
    if step.outputYieldLiveVerified~=true then warnings[#warnings+1]="OUTPUT_YIELD_NOT_LIVE_QUALIFIED" end
    if conflicted then warnings[#warnings+1]="EXTERNAL_OUTPUT_YIELD_CONFLICT" end
    if type(step.sourceRequirement)=="table" then warnings[#warnings+1]="PATTERN_ACCESS_NOT_OBSERVED" end
    if step.sourceSpellFocusReference then warnings[#warnings+1]="SPELL_FOCUS_REQUIREMENT_REFERENCE_ONLY" end
    if type(step.requiredSkill)~="number" then warnings[#warnings+1]="LEARNING_MINIMUM_NOT_QUALIFIED" end
    return {index=index,fromSkill=step.skillMin,toSkill=step.skillTarget,
        recipe=step.recipe,recipeID=step.recipeID,
        sourceContract=step.sourceQualificationContract,materialEvidence=step.materialEvidence,
        materialSourceBuild=step.materialSourceBuild,
        referenceReagents=materials,referenceReagentsValid=valid,
        referenceExpectedCrafts=craftCount,referenceCraftCountAuthority=step.craftCountAuthority,
        duplicateSplitCraftEstimate=repeatEstimate,craftCountLiveQualified=step.craftCountQualified==true,
        learnedObservedInSource=step.recipeAccessObserved==true,
        requiredSkillReference=step.requiredSkill,requiredSkillSource=step.requiredSkillAuthority,
        rawYellowThreshold=step.rawYellowThreshold,rawGreyThreshold=step.rawGreyThreshold,
        rawThresholdSourceBuild=step.rawDifficultySourceBuild,
        outputItemIDReference=step.outputItemID,outputQuantityReference=step.outputQuantityReference,
        externalYieldConflict=conflicted,sourceRequirement=type(step.sourceRequirement)=="table" and
          {kind=step.sourceRequirement.kind,itemID=step.sourceRequirement.itemID,name=step.sourceRequirement.name} or nil,
        focusIDReference=step.sourceSpellFocusReference,
        outputLiveQualified=step.outputYieldLiveVerified==true,
        routeQualified=step.routeQualified==true,
        issues=warnings,readOnly=true,executionEligible=false,nativeDispatchAllowed=false}
end
function Qualification:Build()
    local data=JLP.data and JLP.data.tailoring
    local route=data and data.route
    local result={contract=self.contract,professionKey="TAILORING",sourceBuild=data and data.sourceBuild,
        readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
        steps={},bands={},sourceSteps=0,liveProgressionSteps=0,splitEstimateWarnings=0,
        yieldConflictSteps=0,sourceWindowsComplete=false}
    if type(route)~="table" then result.reason="ROUTE_UNAVAILABLE";return result end
    local duplicates={}
    -- Same recipe and same total estimate reused in adjacent source windows is
    -- evidence of ambiguity, NOT proof that either count is correct/incorrect.
    for i=2,#route do
        local a,c=route[i-1],route[i]
        if a.recipeID==c.recipeID and a.skillTarget==c.skillMin and
           integer(a.expectedCrafts) and a.expectedCrafts>0 and
           a.expectedCrafts==c.expectedCrafts then
            duplicates[i-1]=true;duplicates[i]=true
        end
    end
    local bands={{name="1-75",lo=1,hi=75},{name="75-150",lo=75,hi=150},
                 {name="150-225",lo=150,hi=225},{name="225-270",lo=225,hi=270},
                 {name="270-300",lo=270,hi=300}}
    for _,band in ipairs(bands) do
        local row={name=band.name,fromSkill=band.lo,toSkill=band.hi,
            sourcePositions=0,liveQualifiedPositions=0,sourceStepCount=0,
            missingSourcePositions={},readOnly=true}
        result.bands[#result.bands+1]=row
    end
    local coverage={}
    for i,step in ipairs(route) do
        local row=describe(step,i,duplicates)
        result.steps[#result.steps+1]=row
        result.sourceSteps=result.sourceSteps+1
        if row.duplicateSplitCraftEstimate then result.splitEstimateWarnings=result.splitEstimateWarnings+1 end
        if row.externalYieldConflict then result.yieldConflictSteps=result.yieldConflictSteps+1 end
        if integer(step.skillMin) and integer(step.skillTarget) and step.skillMin>=1 and
           step.skillTarget<=300 and step.skillTarget>step.skillMin then
            for skill=step.skillMin,step.skillTarget-1 do
                coverage[skill]=(coverage[skill] or 0)+1
            end
            for _,band in ipairs(result.bands) do
                if step.skillMin<band.toSkill and step.skillTarget>band.fromSkill then
                    band.sourceStepCount=band.sourceStepCount+1
                end
            end
        end
    end
    result.sourceWindowsComplete=true
    for _,band in ipairs(result.bands) do
        for skill=band.fromSkill,band.toSkill-1 do
            if coverage[skill]==1 then band.sourcePositions=band.sourcePositions+1
            else band.missingSourcePositions[#band.missingSourcePositions+1]=skill;result.sourceWindowsComplete=false end
        end
    end
    -- Static reference rows are never current-character live skill-up proof.
    return result
end
function Qualification:GetAtSkill(skill)
    local step,index=stepAt(skill)
    if not step then return nil,"NO_SOURCE_STEP_FOR_SKILL" end
    local audit=self:Build()
    return audit.steps[index]
end
-- Explicitly invoked from diagnostics, never per-frame GUI, planner bulk math,
-- or native crafting. Live values are momentary and are not saved.
function Qualification:InspectAtSkill(skill)
    local ref=self:GetAtSkill(skill)
    local out={contract="tailoring-volatile-recipe-qualification-v1",skill=skill,
        source=ref,readOnly=true,executionEligible=false,nativeDispatchAllowed=false,
        manualOneCandidate=false,skillUpProven=false,outputYieldVerified=false,
        recipeStatus="UNKNOWN",reagentsStatus="UNKNOWN",craftabilityStatus="UNKNOWN",
        difficultyStatus="UNKNOWN",status="UNVERIFIED"}
    if not ref then out.status="NO_SOURCE_STEP_FOR_SKILL";return out end
    local api=JLP:GetModule("ProfessionAPI")
    if not api or type(api.GetReadOnlyProfessionObservation)~="function" or
       type(api.GetReadOnlyRecipeObservation)~="function" then
        out.status="VOLATILE_API_UNAVAILABLE";return out
    end
    local ok,prior=pcall(api.GetReadOnlyProfessionObservation,api)
    if not ok or type(prior)~="table" or prior.observed~=true or
       prior.professionKey~="TAILORING" or prior.skill~=skill or
       type(prior.maxSkill)~="number" or prior.maxSkill<skill then
        out.status="LIVE_PROFESSION_NOT_STABLE";return out
    end
    out.observationQuality=prior.observationQuality
    out.currentSkill=prior.skill;out.currentMaxSkill=prior.maxSkill
    local okRecipe,recipe=pcall(api.GetReadOnlyRecipeObservation,api,ref.recipeID,"TAILORING")
    if not okRecipe or type(recipe)~="table" or recipe.readOnlyObserved~=true or
       recipe.recipeID~=ref.recipeID or recipe.professionKey~="TAILORING" or
       recipe.panelToken~=prior.observationToken then
        out.status="LIVE_RECIPE_UNVERIFIED"
        out.recipeReason=type(recipe)=="table" and recipe.reason or "RECIPE_READ_FAILED"
        return out
    end
    out.recipeStatus=recipe.learned==true and "LEARNED" or "NOT_LEARNED"
    out.liveRecipeName=recipe.name
    out.nameMatchesReference=recipe.name==ref.recipe
    local resolver=JLP:GetModule("RecipeDifficulty")
    if resolver and type(resolver.GetForRecipe)=="function" then
        local okDiff,diff=pcall(resolver.GetForRecipe,resolver,"TAILORING",ref.recipeID,recipe.name)
        if okDiff and type(diff)=="table" and
           (diff.confidence=="verified" or diff.confidence=="verified-recipe-link") and
           (diff.token=="orange" or diff.token=="yellow" or diff.token=="green" or diff.token=="gray") and
           diff.canSkillUp~=false and
           (diff.recipeID==nil or diff.recipeID==ref.recipeID) then
            out.difficultyStatus=diff.token
        end
    end
    local craft=JLP:GetModule("Crafting")
    if craft and type(craft.GetCraftableCountState)=="function" then
        local okCount,count=pcall(craft.GetCraftableCountState,craft,ref.recipeID)
        if okCount and type(count)=="table" and count.recipeID==ref.recipeID and
           (count.status=="KNOWN" or count.status=="ERROR" or count.status=="UNKNOWN") then
            out.craftabilityStatus=count.status
            if count.status=="KNOWN" and integer(count.count) and count.count>=0 then
                out.craftableCount=count.count
            end
        end
    end
    if type(api.GetNativeReagentSnapshot)=="function" then
        local okM,m=pcall(api.GetNativeReagentSnapshot,api,ref.recipeID)
        if okM and type(m)=="table" and m.recipeID==ref.recipeID then
            out.reagentsStatus=m.status or "UNKNOWN"
            if m.status=="OBSERVED" and type(m.materials)=="table" and ref.referenceReagentsValid then
                out.reagentsMatchReference=equalMaterials(ref.referenceReagents,m.materials)
                out.reagentsStatus=out.reagentsMatchReference and "LIVE_REFERENCE_MATCH" or "LIVE_REFERENCE_CONFLICT"
            end
            out.reagentFingerprint=m.fingerprint
        end
    end
    local okAfter,after=pcall(api.GetReadOnlyProfessionObservation,api)
    if not okAfter or type(after)~="table" or after.observed~=true or
       prior.observationToken~=after.observationToken or
       prior.skill~=after.skill or prior.maxSkill~=after.maxSkill or
       prior.observationQuality~=after.observationQuality then
        out.status="LIVE_PANEL_CHANGED_DURING_OBSERVATION"
        out.manualOneCandidate=false
        out.craftableCount=nil
        return out
    end
    out.status="VOLATILE_LIVE_OBSERVATION"
    -- Exact RecipeID and live panel membership are the identity proof;
    -- localized names can differ from the English source catalogue.
    out.manualOneCandidate=recipe.learned==true and
        (out.difficultyStatus=="orange" or out.difficultyStatus=="yellow" or
         out.difficultyStatus=="green") and out.craftabilityStatus=="KNOWN" and
         type(out.craftableCount)=="number" and out.craftableCount>=1 and skill<prior.maxSkill
    -- Even LIVE_REFERENCE_MATCH is not proof that the player owns the reagents.
    -- No inferred per-recipe skillup chance, batch quantity or output yield.
    return out
end
-- Exact Forever spell identity joined to the shipped build70450 reagents.
-- Thresholds authorize scenarios only; outputs never authorize inventory credit.
function Qualification:ScenarioCrafts(row,fromSkill,toSkill)
    if (row.sourceQualificationContract=="tailoring-77-102-wool-v1" or (row.sourceQualificationContract=="tailoring-102-107-source-v1" or (row.sourceQualificationContract=="tailoring-107-125-source-v1" or (row.sourceQualificationContract=="tailoring-125-225-source-v1" or row.sourceQualificationContract=="tailoring-225-300-source-v1")))) then
        return self:WoolScenario(row,fromSkill,toSkill,row.planningInventory).consumerCrafts
    end
    local total=0
    for point=math.max(row.skillMin or 31,fromSkill),math.min(row.skillTarget or 50,toSkill)-1 do
        if row.rawGrey and point>=row.rawGrey then return nil end
        local chance=point<row.rawYellow and 1 or
            (row.rawGreen and point>=row.rawGreen and .25 or .6)
        total=total+1/chance
    end
    return math.ceil(total-0.00000001)
end
local function scenarioChance(row,skill)
    if skill>=row.rawGrey then return 0 end
    if skill<row.rawYellow then return 1 end
    return row.rawGreen and skill>=row.rawGreen and .25 or .6
end
-- Projection-only stock. Never edit Inventory/SavedVariables or mint observed output.
function Qualification:PlanningInventory(reserved)
    local pool={};local inventory=JLP:GetModule("Inventory")
    for _,id in ipairs({2589,2996,2320,2592,2997,2321,2318,4340,2605,4306,4305,2319,4338,4339,4291,8343,2324,2604,6260,4234,3383,5500,7067,6371,3829,4337,7068,3827,14047,14048,14227,14341,7076,8170,9210,14342,14256,10285,4304,4589})do
        local row=inventory and inventory.GetOwned and inventory:GetOwned(id)
        local n=row and row.bagKnown==true and row.bankKnown==true and tonumber(row.total)
        if n and n>=0 then pool[id]=math.max(0,n-math.max(0,tonumber(reserved and reserved[id]) or 0)) end
    end
    return pool
end
function Qualification:GetWoolProducer(dataset)
    local evidence=JLP:GetModule("RecipeOutputEvidence")
    if evidence and evidence.Resolve and evidence:Resolve(nil,2964).productContractConflict then
        return nil,"USER_FIXED_OUTPUT_CONFLICT_REVIEW_REQUIRED"
    end
    local f=dataset and dataset.woolProgression
    if not (f and f.contract=="tailoring-77-102-wool-v1" and f.sourceBuild==70532 and
        f.sourceSHA256=="ad9c51f68e1cdb8359f15058054ffe1f5e4fc5cfefc51a6abe6ac65f2e949f6a" and
        f.capturedAt==1792708450 and f.producerRecipeID==2964 and f.producerOutputItemID==2997 and
        f.producerInputItemID==2592 and f.producerInputQuantity==3 and f.producerOutputQuantity==1 and
        f.producerMinimum==75 and f.producerYellow==75 and f.producerGreen==77 and f.producerGray==85 and
        f.producerCastSeconds==5.125) then return nil,"WOOL_YIELD_SOURCE_UNKNOWN" end
    local db=JLP.data.build70450Recipes
    local packed=db and db.professions and db.professions.TAILORING and db.professions.TAILORING.packed
    if type(packed)~="string" or not packed:find("2964^2370^1^70^85^0^2576^0^0^2592:3^2997:1:0^Bolt of Woolen Cloth",1,true) then
        return nil,"WOOL_PRODUCER_IDENTITY_CONFLICT"
    end
    if dataset.db2 and not self:DB2Recipe(2964,"2592:3",2997) then return nil,"DB2_WOOL_REAGENT_CONFLICT" end
    local facts=JLP:GetModule("ProfessionPlanningFacts")
    local observed=facts and facts.Observe and facts:Observe("TAILORING",2964)
    if type(C_TradeSkillUI)=="table" and type(C_TradeSkillUI.GetRecipeSchematic)=="function" then
        local output=observed and observed.observed and observed.output
        if not (output and output.fixed and output.itemID==2997 and output.minimum==1 and output.maximum==1) then
            return nil,"WOOL_CURRENT_OUTPUT_UNKNOWN_OR_CONFLICT"
        end
        local fn=C_TradeSkillUI.GetRecipeSchematic
        local function inputsMatch(s)
            local slots=s and s.reagentSlotSchematics
            local slot=slots and slots[1]
            return s and s.recipeID==2964 and s.outputItemID==2997 and s.quantityMin==1 and s.quantityMax==1 and
                slots and #slots==1 and slot.required==true and slot.quantityRequired==3 and
                type(slot.reagents)=="table" and #slot.reagents==1 and slot.reagents[1].itemID==2592
        end
        local ok,a=pcall(fn,2964,false);local again,b=pcall(fn,2964,false)
        if not (ok and again and inputsMatch(a) and inputsMatch(b) and C_TradeSkillUI.GetRecipeSchematic==fn) then
            return nil,"WOOL_CURRENT_INPUT_UNKNOWN_OR_CONFLICT"
        end
    end
    return {itemID=2592,name="Wool Cloth",quantity=3,outputPerCraft=1,producerRecipeID=2964,
        sourceQualificationContract="wool-2964-client-schematic-70532-v1",sourceBuild=70532,
        authority="HISTORICAL_CLIENT_SCHEMATIC_70532",sourceSHA256=f.sourceSHA256,
        observed=observed,readOnly=true,nativeDispatchAllowed=false},"SOURCE_QUALIFIED_READ_ONLY"
end
-- Same material contract for the two user-fixed later cloth producers.
function Qualification:GetClothProducer(dataset,itemID)
    if itemID==2997 then return self:GetWoolProducer(dataset) end
    if itemID==2996 then return self:GetLinenConversion(dataset) end
    local id,input,qty,minimum,name
    if itemID==4305 then id,input,qty,minimum,name=3839,4306,4,100,"Silk Cloth"
    elseif itemID==4339 then id,input,qty,minimum,name=3865,4338,5,175,"Mageweave Cloth"
    elseif itemID==14048 then id,input,qty,minimum,name=18401,14047,5,250,"Runecloth"
    else return nil,"UNKNOWN_PRODUCER" end
    if id==3839 and not self:GetSilkContract(dataset) then return nil,"SILK_CONTRACT_CONFLICT" end
    local db=self:DB2Recipe(id,tostring(input)..":"..qty,itemID)
    if not db then return nil,"DB2_PRODUCER_CONFLICT" end
    local evidence=JLP:GetModule("RecipeOutputEvidence")
    if evidence and evidence.Resolve and evidence:Resolve(nil,id).productContractConflict then return nil,"USER_FIXED_OUTPUT_CONFLICT" end
    local facts=JLP:GetModule("ProfessionPlanningFacts")
    local observed=facts and facts.Observe and facts:Observe("TAILORING",id)
    if type(C_TradeSkillUI)=="table" and type(C_TradeSkillUI.GetRecipeSchematic)=="function" then
        local o=observed and observed.observed and observed.output
        if not (o and o.fixed and o.itemID==itemID and o.minimum==1 and o.maximum==1) then return nil,"CURRENT_PRODUCER_OUTPUT_UNKNOWN_OR_CONFLICT" end
        local fn=C_TradeSkillUI.GetRecipeSchematic
        local function matches()
            local ok,a=pcall(fn,id,false);local slots=ok and a and a.reagentSlotSchematics
            local slot=slots and slots[1]
            return a and a.recipeID==id and a.outputItemID==itemID and slots and #slots==1 and slot.required==true and
                slot.quantityRequired==qty and slot.reagents and #slot.reagents==1 and slot.reagents[1].itemID==input
        end
        if not (matches() and matches() and C_TradeSkillUI.GetRecipeSchematic==fn) then return nil,"CURRENT_PRODUCER_INPUT_UNKNOWN_OR_CONFLICT" end
    end
    return {itemID=input,name=name,quantity=qty,outputPerCraft=1,producerRecipeID=id,minimum=minimum,
        sourceQualificationContract="cloth-user-output-db2-70532-v1",sourceBuild=70532,
        authority="USER_FIXED_OUTPUT_DB2_INPUT_NOT_TRANSACTION",observed=observed,readOnly=true,nativeDispatchAllowed=false},"SOURCE_QUALIFIED_READ_ONLY"
end
function Qualification:WoolScenario(row,fromSkill,toSkill,pool)
    pool=pool or self:PlanningInventory()
    local skill=fromSkill;local crafts,producers,gain=0,0,0
    local boltPerCraft,producer
    for _,m in ipairs(row.materials)do if m.itemID==2997 then boltPerCraft=m.quantity;producer=m.craftedFrom end end
    local bolts=pool[2997]
    local observed=producer and producer.observed
    local canGain=producer and bolts~=nil and observed and observed.observed and observed.learned==true
    -- A fresh GRAY/canSkillUp=false revokes skill credit, not material preparation.
    if observed and observed.observed and observed.skillup and
        (observed.skillup.tier=="GRAY" or observed.skillup.canSkillUp==false) then canGain=false end
    -- Decimal yellow scenarios must not add an extra cast at e.g.112+5*.6=115.
    while skill+1e-9<toSkill and crafts<2000 do
        if boltPerCraft and producer and bolts~=nil then
            while bolts<boltPerCraft do
                producers=producers+1;bolts=bolts+1
                local delta=canGain and skill<85 and .25 or 0
                gain=gain+delta;skill=skill+delta
            end
            bolts=bolts-boltPerCraft
        end
        local chance=scenarioChance(row,skill)
        if chance<=0 then return {consumerCrafts=nil,status="GRAY_BEFORE_TARGET"} end
        crafts=crafts+1;skill=skill+chance
    end
    return {consumerCrafts=crafts,producerCrafts=boltPerCraft and producer and pool[2997]~=nil and producers or nil,
        expectedPreparationSkill=gain,expectedEndSkill=skill,startSkill=fromSkill,targetSkill=toSkill,
        status="EXPECTED_VALUE_FLOW_SCENARIO_NOT_EXACT_DISTRIBUTION",estimated=true,
        observedSkillCredit=0,observedInventoryCredit=0,readOnly=true}
end
-- Field-wise user-confirmed spell contract, joined to existing build fields.
-- Learning eligibility is not observed recipe ownership or trainer stock.
function Qualification:GetSilkContract(dataset)
    local rows=dataset and dataset.woolProgression and dataset.woolProgression.recipes
    local fact,count=nil,0
    for _,r in ipairs(rows or {})do if r.id==3839 then fact=r;count=count+1 end end
    local db=self:DB2Recipe(3839,"4306:4",4305)
    if not (count==1 and fact.minimum==100 and fact.yellow==110 and fact.green==115 and fact.gray==120 and
        fact.output==4305 and fact.reagents=="4306:4" and
        fact.minimumAuthority=="USER_CONFIRMED_FOREVER_QUICK_FACTS_2026_10_25" and
        fact.sourceURL=="https://www.wowhead.com/forever/spell=3839/bolt-of-silk-cloth" and
        db and db.trivialLow==110 and db.trivialHigh==120) then return nil end
    return fact
end
-- Parse immutable packed source once. Candidate field mutation is still checked below.
local packedSource,packedRows
local function indexPacked(source)
    if packedSource~=source then
        packedSource=source;packedRows={}
        for line in source:gmatch("[^\n]+")do
            local cells={};for v in (line.."^"):gmatch("([^%^]*)%^")do cells[#cells+1]=v end
            local id=tonumber(cells[1])
            if id then
                local record=packedRows[id]
                if record then record.count=record.count+1 else packedRows[id]={count=1,cells=cells} end
            end
        end
    end
    return packedRows
end
-- Location requirements are current-panel facts, never a station waypoint.
function Qualification:RecipeAccess(row,professionKey)
    professionKey=professionKey or "TAILORING"
    if not row.sourceSpellFocusReference and not row.cooldownMS then return "NO_SPECIAL_REQUIREMENT" end
    local api=JLP:GetModule("ProfessionAPI")
    local panel=api and api.GetReadOnlyProfessionObservation and api:GetReadOnlyProfessionObservation()
    local t=type(C_TradeSkillUI)=="table" and C_TradeSkillUI
    if not (panel and panel.observed and panel.professionKey==professionKey and t) then return "UNKNOWN" end
    local fn=t.GetRecipeRequirements;local cd=t.GetRecipeCooldown
    local function check()
        if row.sourceSpellFocusReference then
            if type(fn)~="function" then return "UNKNOWN" end
            local ok,requirements=pcall(fn,row.recipeID)
            if not ok or type(requirements)~="table" then return "UNKNOWN" end
            local location=false
            for _,r in ipairs(requirements)do
                if r.met==false then return "UNMET" end
                if r.met~=true then return "UNKNOWN" end
                if r.type==0 or r.type==2 then location=true end
            end
            if not location then return "UNKNOWN" end
        end
        if row.cooldownMS then
            if type(cd)~="function" then return "COOLDOWN_UNKNOWN" end
            local ok,remaining=pcall(cd,row.recipeID)
            if not ok or type(remaining)~="number" or remaining~=remaining or remaining<0 or remaining==math.huge then return "COOLDOWN_UNKNOWN" end
            if remaining>0 then return "COOLDOWN_ACTIVE" end
        end
        return "MET"
    end
    local a,b=check(),check()
    local after=api:GetReadOnlyProfessionObservation()
    if a~=b or not after or not after.observed or panel.observationToken~=after.observationToken or
        panel.skill~=after.skill or panel.maxSkill~=after.maxSkill or t.GetRecipeRequirements~=fn or t.GetRecipeCooldown~=cd then return "UNKNOWN" end
    return a
end
-- Pattern use requirement is joined to its exact recipe effect; it is not a
-- generic interpretation of SkillLineAbility.MinSkillLineRank (which is1).
function Qualification:GetVendorPatternContract(dataset,id)
    if id~=18423 and id~=18417 and id~=27659 then return nil end
    local db=dataset and dataset.db2
    local row=db and db.sourceBuild==70532 and db.recipes and db.recipes[id]
    if not row or row.patternProfessionID~=197 or row.patternTriggerType~=6 or
        not row.patternLinkID or not row.patternEffectID then return nil end
    local found
    for _,f in ipairs(dataset.woolProgression and dataset.woolProgression.recipes or {})do
        if f.id==id then if found then return nil end;found=f end
    end
    if not found or found.minimumAuthority~="FOREVER_PATTERN_DB2_70532" or
        found.recipeItemID~=row.patternItemID or found.minimum~=row.patternRequiredSkill or
        found.recipeItemRequiredSkill~=row.patternRequiredSkill or
        found.name~=row.name or found.reagents~=row.reagents or found.output~=row.outputItemID or
        found.yellow~=row.trivialLow or found.gray~=row.trivialHigh then return nil end
    return found,row
end
function Qualification:GetWoolAlternatives(dataset,skill,target,context)
    local f=dataset and dataset.woolProgression
    if not (f and f.contract=="tailoring-77-102-wool-v1" and skill>=77 and skill<(f.artisanTarget or f.expertTarget or 125)) then return nil end
    if skill>=107 and not (f.nextContract=="tailoring-107-125-source-v1" and f.nextTarget==125) then return nil end
    if skill>=102 and not (f.continuationContract=="tailoring-102-107-source-v1" and f.continuationTarget==107) then return nil end
    if skill>=225 and f.artisanContract~="tailoring-225-300-source-v1" then return nil end
    if skill>=125 and f.expertContract~="tailoring-125-225-source-v1" then return nil end
    local bounds={77,80,85,90,95,97,100,102,107,110,112,115,120,125,130,135,140,142,145,150,155,160,165,170,175,180,185,190,195,200,205,210,215,220,225,230,235,240,245,250,255,260,265,270,275,280,285,290,295,300};local first,last
    for i=1,#bounds-1 do if skill>=bounds[i] and skill<bounds[i+1] then first,last=bounds[i],bounds[i+1];break end end
    if not last then return nil end
    target=math.min(target or last,last,f.artisanTarget or f.expertTarget or 125)
    local db=JLP.data.build70450Recipes
    local packed=db and db.professions and db.professions.TAILORING and db.professions.TAILORING.packed
    if type(packed)~="string" then return nil end
    local pool=self:PlanningInventory(context and context.reservedStock)
    if context and context.inventory then
        pool={};for id,n in pairs(context.inventory)do
            pool[id]=math.max(0,n-math.max(0,tonumber(context.reservedStock and context.reservedStock[id]) or 0))
        end
    end
    local names={[2996]="Bolt of Linen Cloth",[2320]="Coarse Thread",[2997]="Bolt of Woolen Cloth",[2321]="Fine Thread",
        [2318]="Light Leather",[4340]="Gray Dye",[2605]="Green Dye",[4306]="Silk Cloth",[2319]="Medium Leather",[14047]="Runecloth",[14048]="Bolt of Runecloth",[14227]="Ironweb Spider Silk",[14341]="Rune Thread",[14342]="Mooncloth",[14256]="Felcloth",[7076]="Essence of Earth",[8170]="Rugged Leather",[9210]="Ghost Dye",[16203]="Greater Eternal Essence"}
    local signatures={
        [2402]="75:80:97:115",[12046]="75:75:92:110",[2397]="60:60:77:95",
        [8776]="15:50:67:85",[2401]="95:95:112:130",[2406]="100:100:100:110",
        [3758]="95:100:nil:135",[3839]="100:110:115:120",[3848]="110:110:127:145",[3849]="120:120:137:155",[3852]="130:125:140:155",[3868]="125:125:142:160",[3813]="150:145:160:175",[3854]="145:140:155:170",[8784]="165:150:165:180",[8764]="170:155:170:185",[8786]="175:160:175:190",[8791]="185:170:180:190",[8789]="180:165:180:195",[8799]="195:180:190:200",[8774]="180:165:180:195",[3862]="200:185:200:215",[12048]="205:185:200:215",[8802]="205:185:200:215",[12050]="210:190:205:220",[12053]="215:195:210:225",[12065]="225:205:220:235",[12072]="230:205:220:235",[12074]="230:205:220:235",[12079]="235:210:225:240",[12082]="240:215:230:245",[12081]="240:215:230:245",[18423]="235:250:265:280",[18417]="230:245:260:275",[27659]="230:245:260:275",[18409]="265:240:255:270",[18440]="290:270:285:300",[18560]="250:270:285:300",[1257472]="225:240:255:270",[1257485]="240:255:270:285",[1257488]="245:260:275:290",[1257486]="250:265:280:295",[1257489]="250:265:280:295",[1257490]="255:265:280:295",[1257491]="255:270:285:300",[1257493]="260:275:290:305",[1257494]="260:275:290:305",[1257487]="250:265:280:295"}
    local rows={}
    for _,fct in ipairs(f.recipes or {})do
        local signature=tostring(fct.minimum)..":"..tostring(fct.yellow)..":"..tostring(fct.green)..":"..tostring(fct.gray)

        local indexed=indexPacked(packed)[fct.id]
        local match,count=indexed and indexed.cells,indexed and indexed.count or 0
        if (not fct.fromSkill or skill>=fct.fromSkill) and (fct.id~=18560 or (fct.cooldownMS==342000000 and fct.sourceSpellFocusReference==883 and fct.outputQuantityReference==1)) and signatures[fct.id]==signature and count==1 and #match==12 and match[12]==fct.name and match[10]==fct.reagents and
            tonumber(match[4])==fct.dbYellow and tonumber(match[5])==fct.gray and
            tonumber(match[11]:match("^(%d+):"))==fct.output and skill>=fct.minimum and target<=fct.gray and
            (fct.id~=3758 or target<=100) and (fct.id~=3839 or self:GetSilkContract(dataset)) then
            local row={recipeID=fct.id,recipe=fct.name,recipeSource=fct.learning,requiredSkill=fct.minimum,
                requiredSkillAuthority=fct.minimumAuthority or (fct.learningConflict and "CONSERVATIVE_CONFLICT_FLOOR" or "WOWHEAD_FOREVER"),
                learningConflict=fct.learningConflict,difficultyConflict=fct.difficultyConflict,
                route=true,routeSkillMin=first,routeSkillTarget=target,skillMin=first,skillTarget=target,routeIndex=skill>=102 and 5 or 4,
                rawYellow=fct.yellow,rawGreen=fct.id~=3758 and fct.green or nil,rawGrey=fct.gray,
                rawYellowThreshold=fct.yellow,rawGreyThreshold=fct.gray,sourceBuild=70450,
                fieldEvidence={difficulty="FOREVER_PUBLIC_PLUS_DB70450_FIELD_JOIN",
                    output="CLIENT_SCHEMATIC_70532_NOT_CRAFT_TRANSACTION",green=fct.id==3758 and "UNKNOWN" or "FOREVER_PUBLIC"},
                evidence="https://www.wowhead.com/forever/spell="..fct.id.."/"..fct.slug,
                sourceQualificationContract=skill>=225 and f.artisanContract or skill>=125 and f.expertContract or skill>=107 and f.nextContract or skill>=102 and f.continuationContract or f.contract,materials={},outputItemID=fct.output,
                outputYieldStatus=fct.outputQuantityStatus,castSeconds=fct.castSeconds,planningInventory=pool,
                planningEstimateQualified=true,craftCountQualified=false,
                craftCountAuthority="USER_APPROVED_ORANGE_100_YELLOW_60_GREEN_25_FLOW_SCENARIO",
                readOnly=true,executionEligible=false,nativeDispatchAllowed=false,plannerEligible=true}
            for id,qty in fct.reagents:gmatch("(%d+):(%d+)")do
                id,qty=tonumber(id),tonumber(qty)
                local material={itemID=id,name=names[id],quantity=qty,source=(id==2996 or id==2997 or id==4305 or id==4339 or id==14048 or id==14342) and "crafted" or ((id==2318 or id==2319 or id==4306) and "auction" or "vendor")}
                if id==2997 then material.craftedFrom,material.conversionStatus=self:GetWoolProducer(dataset)
                elseif id==2996 then material.craftedFrom=self:GetLinenConversion(dataset)
                elseif id==4305 or id==4339 or id==14048 then
                    material.craftedFrom,material.conversionStatus=self:GetClothProducer(dataset,id)
                    if material.craftedFrom and skill<material.craftedFrom.minimum then
                        material.craftedFrom=nil;material.conversionStatus="PRODUCER_MINIMUM_NOT_MET"
                    end
                elseif id==14342 then material.conversionStatus="MOONCLOTH_STATION_COOLDOWN_NOT_AUTOMATIC_SUPPLIER" end
                if fct.artisan then
                    local vendors={[2320]=true,[2321]=true,[4291]=true,[8343]=true,[14341]=true,[2604]=true,[2605]=true}
                    if material.source~="crafted" then material.source=vendors[id] and "vendor" or "auction" end
                end
                row.materials[#row.materials+1]=material
            end
            if fct.expert or fct.artisan then
                row.sourceBuild=70532;row.requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes"
                row.fieldEvidence.minimum=fct.minimumAuthority
                row.fieldEvidence.green="DERIVED_FOREVERTALENT_MIDPOINT_NOT_LIVE"
                row.fieldEvidence.difficulty="FOREVERTALENT_PLUS_DB2_70532_YELLOW_GRAY"
                row.learningSourceStatus=fct.acquisitionSourceStatus or (fct.learning=="unknown" and "UNKNOWN_LEARNING_METHOD" or "SOURCE_CATEGORY_ONLY_VERIFY_ACTUAL_ACCESS")
                row.recipeItemReference=fct.recipeItemID and {itemID=fct.recipeItemID,requiredSkill=fct.recipeItemRequiredSkill,sourceBuild=70532,possession="UNKNOWN",trainerOrVendorAccess="UNKNOWN"} or nil
                row.outputQuantityReference=fct.outputQuantityReference
                row.outputQuantityConflict=fct.outputQuantityConflict
                row.outputYieldStatus=fct.outputQuantityConflict and "CONFLICT_HISTORICAL_SCHEMATIC_1_VS_INDIVIDUAL_FOREVER_2" or "HISTORICAL_SCHEMATIC_70532"
                row.expectedOutputQuantity=not fct.outputQuantityConflict and fct.outputQuantityReference or nil
                row.sourceSpellFocusReference=fct.sourceSpellFocusReference
                row.cooldownMS=fct.cooldownMS;row.sourceFocusLabel=fct.sourceSpellFocusReference==883 and "Moonwell" or "Spinning Wheel"
                row.accessStatus=self:RecipeAccess(row);row.requiresAccessVerification=row.accessStatus~="MET" and row.accessStatus~="NO_SPECIAL_REQUIREMENT"
            end
            if fct.id==3839 then
                row.fieldEvidence.minimum=fct.minimumAuthority
                row.fieldEvidence.difficulty=fct.minimumAuthority
                row.fieldEvidence.green=fct.minimumAuthority
                row.fieldEvidence.output="USER_FIXED_TAILORING_OUTPUT_2026_10_25"
                row.categoryMinimumConflict=fct.categoryMinimumConflict
                row.expectedOutputQuantity=1;row.liveVerified=false
            end
            if fct.id==3848 or fct.id==3849 then
                row.requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes"
                row.fieldEvidence.minimum="WOWHEAD_FOREVER_OVERVIEW_SOURCE_CATEGORY_NOT_TRAINER_STOCK"
                row.fieldEvidence.difficulty="FOREVERTALENT_PLUS_DB2_70532_YELLOW_GRAY"
                row.fieldEvidence.green="DERIVED_FOREVERTALENT_MIDPOINT_NOT_LIVE"
                row.learningSourceStatus="TRAINER_CATEGORY_ONLY_VERIFY_ACTUAL_ACCESS"
            end
            if fct.id==3848 then
                row.outputQuantityReference=fct.outputQuantityReference
                row.outputQuantityAuthority=fct.outputQuantityAuthority
                row.outputQuantityConflict=fct.outputQuantityConflict
                row.outputYieldStatus="CONFLICT_USER_REPORTED_2_VS_CATALOG_1"
            end
            row.woolScenario=self:WoolScenario(row,skill,target,pool)
            row.expectedCrafts=row.woolScenario.consumerCrafts;row.scenarioCrafts=row.expectedCrafts
            if row.expectedCrafts and row.expectedCrafts>0 then rows[#rows+1]=row end
        end
    end
    return self:DB2Alternatives(rows)
end
function Qualification:GetLinenConversion(dataset)
    local evidence=JLP:GetModule("RecipeOutputEvidence")
    if evidence and evidence.Resolve and evidence:Resolve(nil,2963).productContractConflict then
        return nil,"USER_FIXED_OUTPUT_CONFLICT_REVIEW_REQUIRED"
    end
    local f=dataset and dataset.linenProducer
    if not (f and f.contract=="linen-2963-client-schematic-70532-v1" and f.recipeID==2963 and
        f.outputItemID==2996 and f.quantityMin==1 and f.quantityMax==1 and
        f.inputItemID==2589 and f.inputQuantity==2 and f.sourceBuild==70532 and
        f.panelBaseSkillLineID==197 and f.capturedAt==1792708450 and
        f.sourceSHA256=="ad9c51f68e1cdb8359f15058054ffe1f5e4fc5cfefc51a6abe6ac65f2e949f6a") then return nil,"SOURCE_YIELD_UNKNOWN" end
    local db=JLP.data.build70450Recipes
    local packed=db and db.professions and db.professions.TAILORING and db.professions.TAILORING.packed
    if type(packed)~="string" or not packed:find("2963^2359^1^25^50^1^2576^0^0^2589:2^2996:1:0^Bolt of Linen Cloth",1,true) then
        return nil,"PRODUCER_REAGENT_IDENTITY_UNVERIFIED"
    end
    if dataset.db2 and not self:DB2Recipe(2963,"2589:2",2996) then return nil,"DB2_LINEN_REAGENT_CONFLICT" end
    -- A fresh contradictory/variable/unstable schematic revokes the historical
    -- model. Absence of the optional API does not erase the documented source.
    local t=type(C_TradeSkillUI)=="table" and C_TradeSkillUI
    if t and type(t.GetRecipeSchematic)=="function" then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local observed=facts and facts.Observe and facts:Observe("TAILORING",2963)
        local output=observed and observed.observed and observed.output
        if not (output and output.fixed and output.itemID==2996 and output.minimum==1 and output.maximum==1) then
            return nil,"CURRENT_OUTPUT_UNKNOWN_OR_SOURCE_CONFLICT"
        end
    end
    return {itemID=2589,name="Linen Cloth",quantity=2,producerRecipeID=2963,
        outputPerCraft=1,sourceBuild=70532,sourceSHA256=f.sourceSHA256,
        sourceQualificationContract=f.contract,authority="HISTORICAL_CLIENT_SCHEMATIC_70532",
        readOnly=true,nativeDispatchAllowed=false},"SOURCE_QUALIFIED_READ_ONLY"
end
function Qualification:GetJourneymanAlternatives(dataset,skill,target)
    local receipt=dataset and dataset.journeymanProgression
    local db=JLP.data.build70450Recipes
    local source=db and db.professions and db.professions.TAILORING
    if not (receipt and receipt.contract=="tailoring-50-77-forever-v1" and db and
        db.sourceBuild==70450 and source and source.skillLineID==197) then return nil end
    local windowEnd=skill<60 and 60 or skill<67 and 67 or skill<75 and 75 or 77
    local windowStart=skill<60 and 50 or skill<67 and 60 or skill<75 and 67 or 75
    target=math.min(target or windowEnd,windowEnd)
    local exact={
        [8776]={"Linen Belt",15,50,67,85,7026,"2996:1,2320:1","linen-belt"},
        [2385]={"Brown Linen Vest",10,45,57,70,2568,"2996:1,2320:1","brown-linen-vest"},
        [2397]={"Reinforced Linen Cape",60,60,77,95,2580,"2996:2,2320:3","reinforced-linen-cape"},
        [2402]={"Woolen Cape",75,80,97,115,2584,"2997:1,2321:1","woolen-cape"},
        [12046]={"Simple Kilt",75,75,92,110,10047,"2996:4,2321:1","simple-kilt"}}
    local names={[2996]="Bolt of Linen Cloth",[2320]="Coarse Thread",[2997]="Bolt of Woolen Cloth",[2321]="Fine Thread"}
    local rows,seen={},{}
    for _,f in ipairs(receipt.recipes or {})do
        local e=exact[f.recipeID]
        if e and not seen[f.recipeID] and f.recipe==e[1] and f.requiredSkill==e[2] and
            f.yellow==e[3] and f.green==e[4] and f.gray==e[5] and f.outputItemID==e[6] and
            f.reagents==e[7] and f.slug==e[8] and skill>=f.requiredSkill and target<=f.gray then
            seen[f.recipeID]=true
            local count,valid=0,false
            for line in source.packed:gmatch("[^\n]+")do
                if tonumber(line:match("^(%d+)%^"))==f.recipeID then
                    count=count+1;local c={}
                    for v in (line.."^"):gmatch("([^%^]*)%^")do c[#c+1]=v end
                    valid=#c==12 and c[12]==f.recipe and tonumber(c[4])==f.yellow and
                        tonumber(c[5])==f.gray and c[10]==f.reagents and
                        tonumber(c[11]:match("^(%d+):"))==f.outputItemID
                end
            end
            if count==1 and valid then
                local row={recipeID=f.recipeID,recipe=f.recipe,requiredSkill=f.requiredSkill,
                    requiredSkillAuthority="WOWHEAD_FOREVER",route=true,routeSkillMin=windowStart,
                    routeSkillTarget=target,skillMin=windowStart,skillTarget=target,routeIndex=3,
                    rawYellow=f.yellow,rawGreen=f.green,rawGrey=f.gray,
                    rawYellowThreshold=f.yellow,rawGreyThreshold=f.gray,rawDifficultySourceBuild=70450,
                    sourceBuild=70450,evidence="https://www.wowhead.com/forever/spell="..f.recipeID.."/"..f.slug,
                    materials={},recipeSource="trainer",outputItemID=f.outputItemID,
                    outputYieldStatus="CONFLICTING_EXTERNAL_REFERENCES",outputYieldLiveVerified=false,
                    sourceQualificationContract=receipt.contract,craftCountQualified=false,planningEstimateQualified=true,
                    craftCountAuthority="USER_APPROVED_ORANGE_100_YELLOW_60_GREEN_25_SCENARIO",
                    readOnly=true,plannerEligible=true,executionEligible=false,nativeDispatchAllowed=false}
                for id,qty in f.reagents:gmatch("(%d+):(%d+)")do
                    id,qty=tonumber(id),tonumber(qty)
                    local material={itemID=id,name=names[id],quantity=qty,
                        source=(id==2996 or id==2997 or id==4305 or id==4339 or id==14048 or id==14342) and "crafted" or "vendor"}
                    if id==2996 then
                        material.craftedFrom,material.conversionStatus=self:GetLinenConversion(dataset)
                    end
                    row.materials[#row.materials+1]=material
                end
                row.requiredSkillSourceURL=row.evidence
                row.scenarioCrafts=self:ScenarioCrafts(row,skill,target)
                row.expectedCrafts=self:ScenarioCrafts(row,windowStart,target)
                local facts=JLP:GetModule("ProfessionPlanningFacts")
                local observed=facts and facts.Observe and facts:Observe("TAILORING",f.recipeID)
                if not (observed and observed.observed and observed.skill==skill and
                    observed.learned==true and observed.skillup and observed.skillup.canSkillUp==false) then
                    rows[#rows+1]=row
                end
            end
        end
    end
    return self:DB2Alternatives(rows)
end
function Qualification:GetRankStep(profession,dataset)
    local data=dataset and dataset.journeymanProgression
    local gate=data and data.rank
    local skill=profession and tonumber(profession.skill)
    if not (data and data.contract=="tailoring-50-77-forever-v1" and skill and skill>=50 and skill<300) then return nil end
    local function verify(reason,text)
        return {kind="verify",profession="TAILORING",skill=skill,skillTarget=75,
            skillEligibilityStatus=reason,p1NextAction=text,readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false}
    end
    if not (gate and gate.cap==75 and gate.nextCap==150 and gate.requiredSkill==50 and
        gate.minCharacterLevel==10 and gate.rank=="Journeyman Tailoring" and
        gate.sourceURL=="https://www.wow-professions.com/forever/tailoring-trainers") then
        return verify("RANK_SOURCE_UNVERIFIED","Verify Journeyman training requirements; source contract is incomplete.")
    end
    local api=JLP:GetModule("ProfessionAPI")
    local current=api and api.Get and api:Get("TAILORING")
    local cap=tonumber(profession.maxSkill)
    if (cap~=75 and cap~=150 and cap~=225 and cap~=300) or profession.cached~=false or not current or current.cached~=false or
        current.key~="TAILORING" or current.skill~=skill or current.maxSkill~=cap then
        return verify("PROFESSION_RANK_UNVERIFIED","Observe the current Tailoring skill and cap before progressing; cached/unknown rank is not proof of Journeyman.")
    end
    if (cap==150 and skill>=125) or (cap==225 and skill>=200) then
        local artisan=cap==225
        local requiredSkill=artisan and 200 or 125
        local requiredLevel=artisan and 35 or 20
        local nextCap=artisan and 300 or 225
        local rankName=artisan and "Artisan Tailoring" or "Expert Tailoring"
        local expert
        for _,g in ipairs(dataset.trainerGates or {})do if g.cap==cap then expert=g end end
        if not (expert and expert.nextCap==nextCap and expert.requiredSkill==requiredSkill and expert.minCharacterLevel==requiredLevel and
            expert.sourceURL=="https://www.wow-professions.com/forever/tailoring-trainers") then
            if skill>=cap then return verify("EXPERT_SOURCE_UNVERIFIED","Verify "..rankName.." requirements before progressing past cap"..cap..".") end
            return nil
        end
        local level
        if type(UnitLevel)=="function" then local ok,n=pcall(UnitLevel,"player");if ok and type(n)=="number" and n>0 then level=n end end
        local mandatory=skill>=cap
        if mandatory and (not level or level<requiredLevel) then
            local blocked=verify(level and "CHARACTER_LEVEL_TOO_LOW" or "CHARACTER_LEVEL_UNKNOWN",
                "Verify character level"..requiredLevel.." eligibility, train "..rankName.." and observe cap"..nextCap.." before progressing.")
            blocked.skillTarget=cap;return blocked
        end
        local optimizer=JLP:GetModule("TrainerOptimizer")
        local decision=optimizer and optimizer.Evaluate and optimizer:Evaluate("TAILORING",profession,expert)
        if mandatory or (level and level>=requiredLevel and decision and decision.recommendEarly) then
            return {kind="train",profession="TAILORING",skill=skill,skillTarget=nextCap,trainer=expert,
                rank=expert.rank,sourceInfo=decision and decision.sourceInfo,trainingDecision=decision,
                p1NextAction="Train "..rankName.." manually, then observe the new profession cap"..nextCap.." before resuming.",
                early=not mandatory,mandatory=mandatory,readOnly=true,rankObservationRequired=true,
                nativeDispatchAllowed=false,executionEligible=false}
        end
        return nil,{rank=expert.rank,requiredSkill=requiredSkill,minCharacterLevel=requiredLevel,currentCap=cap,nextCap=nextCap,
            mandatoryAtSkill=cap,mandatory=false,canLearn=level and level>=requiredLevel or false,characterLevelKnown=level~=nil,
            status=not level and "VERIFY_CHARACTER_LEVEL" or level<requiredLevel and "LEVEL_REQUIREMENT_NOT_MET" or "AVAILABLE_NOT_YET_MANDATORY",
            readOnly=true,nativeDispatchAllowed=false}
    end
    if cap>=150 then return nil end
    if cap~=75 then return verify("PROFESSION_RANK_UNVERIFIED","Verify the current Tailoring rank and cap.") end
    local level
    if type(UnitLevel)=="function" then local ok,n=pcall(UnitLevel,"player");if ok and type(n)=="number" and n>0 then level=n end end
    local mandatory=skill>=75
    if mandatory and (not level or level<10) then
        return verify(level and "CHARACTER_LEVEL_TOO_LOW" or "CHARACTER_LEVEL_UNKNOWN",
            level and "Reach character level 10, then train Journeyman Tailoring and observe the new cap 150 before continuing." or
            "Verify character level 10 eligibility before training Journeyman Tailoring; current skill cap is 75.")
    end
    local optimizer=JLP:GetModule("TrainerOptimizer")
    local decision=optimizer and optimizer.Evaluate and optimizer:Evaluate("TAILORING",profession,gate)
    if mandatory or (level and level>=10 and decision and decision.recommendEarly) then
        return {kind="train",profession="TAILORING",skill=skill,skillTarget=150,trainer=gate,
            rank=gate.rank,sourceInfo=decision and decision.sourceInfo,trainingDecision=decision,
            early=not mandatory,mandatory=mandatory,blockedByLevel=false,readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false,rankObservationRequired=true}
    end
    return nil,{rank="Journeyman Tailoring",requiredSkill=50,minCharacterLevel=10,
        currentCap=75,nextCap=150,mandatoryAtSkill=75,mandatory=false,
        canLearn=level and level>=10 or false,characterLevelKnown=level~=nil,
        status=not level and "VERIFY_CHARACTER_LEVEL" or level<10 and "LEVEL_REQUIREMENT_NOT_MET" or "AVAILABLE_NOT_YET_MANDATORY",
        readOnly=true,nativeDispatchAllowed=false}
end
function Qualification:GetIntervalAlternatives(dataset,skill)
    local receipt=dataset and dataset.linenProgression
    if not (receipt and receipt.contract=="tailoring-40-50-forever-v1") then return nil end
    local db=JLP.data.build70450Recipes
    local source=db and db.professions and db.professions.TAILORING
    if not (db and db.sourceBuild==70450 and source and source.skillLineID==197 and type(source.packed)=="string") then return nil end
    local result={}
    local identities={[12044]={"Simple Linen Pants",1,40,60,10045},
        [2385]={"Brown Linen Vest",10,45,70,2568},[8776]={"Linen Belt",15,50,85,7026}}
    for _,f in ipairs(receipt.recipes or {}) do
        local expected=identities[f.recipeID]
        if expected and f.recipe==expected[1] and f.requiredSkill==expected[2] and
            f.yellow==expected[3] and f.gray==expected[4] and f.outputItemID==expected[5] and
            f.sourceURL=="https://www.wowhead.com/forever/spell="..f.recipeID.."/"..f.slug then
            local matches,valid=0,false
            for line in source.packed:gmatch("[^\n]+") do
                if tonumber(line:match("^(%d+)%^"))==f.recipeID then
                    matches=matches+1
                    local c={};for v in (line.."^"):gmatch("([^%^]*)%^")do c[#c+1]=v end
                    valid=#c==12 and c[12]==f.recipe and tonumber(c[4])==f.yellow and
                        tonumber(c[5])==f.gray and c[10]=="2996:1,2320:1" and
                        tonumber(c[11]:match("^(%d+):"))==f.outputItemID
                end
            end
            if matches==1 and valid then
                local row={recipeID=f.recipeID,recipe=f.recipe,requiredSkill=f.requiredSkill,
                    route=true,routeSkillMin=40,routeSkillTarget=50,skillMin=40,skillTarget=50,routeIndex=2,
                    rawYellow=f.yellow,rawGrey=f.gray,rawYellowThreshold=f.yellow,rawGreyThreshold=f.gray,
                    sourceBuild=70450,evidence=f.sourceURL,recipeSource=f.learning,
                    requiredSkillAuthority="WOWHEAD_FOREVER",requiredSkillSourceURL=f.sourceURL,
                    materials={{itemID=2996,name="Bolt of Linen Cloth",quantity=1,source="crafted"},
                        {itemID=2320,name="Coarse Thread",quantity=1,source="vendor"}},
                    outputItemID=f.outputItemID,outputYieldStatus="CONFLICTING_EXTERNAL_REFERENCES",
                    outputYieldLiveVerified=false,craftCountQualified=false,planningEstimateQualified=true,
                    craftCountAuthority="USER_APPROVED_ORANGE_100_YELLOW_60_SCENARIO",
                    sourceQualificationContract="tailoring-40-50-forever-v1",
                    plannerEligible=true,readOnly=true,executionEligible=false,nativeDispatchAllowed=false}
                row.scenarioCrafts=self:ScenarioCrafts(row,skill or 40,50)
                row.expectedCrafts=self:ScenarioCrafts(row,40,50)
                result[#result+1]=row
            end
        end
    end
    return #result>0 and result or nil
end
-- Shared concrete route projection for DatasetProvider/Planner/Current Step.
-- Every call checks current source inputs. Registered historical rows stay intact.
local function earlyPlanningSteps(self,dataset)
    local route=type(dataset)=="table" and dataset.route
    local f=type(dataset)=="table" and dataset.earlyProgression
    if type(route)~="table" or type(f)~="table" then return nil end
    if dataset.key~="TAILORING" or f.fromSkill~=25 or f.toSkill~=31 or
        f.recipeID~=12044 or f.recipe~="Simple Linen Pants" or f.requiredSkill~=1 or
        f.yellow~=40 or f.green~=50 or f.gray~=60 or f.outputItemID~=10045 or
        f.sourceBuild~=70450 or f.sourceURL~="https://www.wowhead.com/forever/spell=12044/simple-linen-pants" then return nil end
    local first,second=route[1],route[2]
    if not (first and first.recipeID==2963 and first.skillMin==1 and first.skillTarget==31 and
        second and second.recipeID==12044 and second.recipe==f.recipe and
        second.skillMin==31 and second.skillTarget==50 and second.requiredSkill==1 and
        second.requiredSkillAuthority=="WOWHEAD_FOREVER" and
        second.rawYellowThreshold==40 and second.rawGreyThreshold==60 and
        second.outputItemID==10045 and type(first.expectedCrafts)=="number" and first.expectedCrafts>0 and
        type(second.materials)=="table" and #second.materials==2) then return nil end
    local expected={[2996]=1,[2320]=1}
    for _,m in ipairs(second.materials) do
        if expected[m.itemID]~=m.quantity then return nil end
        expected[m.itemID]=nil
    end
    if next(expected) then return nil end
    local source=JLP.data.build70450Recipes
    local packed=source and source.professions and source.professions.TAILORING and source.professions.TAILORING.packed
    if type(packed)~="string" or source.sourceBuild~=70450 then return nil end
    local matched=0
    for line in packed:gmatch("[^\n]+") do
        if line:match("^12044%^") then
            matched=matched+1
            local cols={};for v in (line.."^"):gmatch("([^%^]*)%^") do cols[#cols+1]=v end
            if #cols~=12 or cols[12]~=f.recipe or tonumber(cols[4])~=40 or tonumber(cols[5])~=60 then return nil end
            local reagents,count={},0
            for token in cols[10]:gmatch("[^,]+") do
                local id,qty=token:match("^(%d+):(%d+)$")
                id,qty=tonumber(id),tonumber(qty)
                if not id or not qty or reagents[id] then return nil end
                reagents[id]=qty;count=count+1
            end
            if count~=2 or reagents[2996]~=1 or reagents[2320]~=1 or not cols[11]:match("^10045:") then return nil end
        end
    end
    if matched~=1 then return nil end
    -- A fresh contradictory live color revokes the orange planning scenario,
    -- without disabling the historical route or other valid recipes.
    local api=JLP:GetModule("ProfessionAPI")
    local facts=JLP:GetModule("ProfessionPlanningFacts")
    local panel=api and api.GetReadOnlyProfessionObservation and api:GetReadOnlyProfessionObservation()
    if panel and panel.observed==true and panel.professionKey=="TAILORING" and
        type(panel.skill)=="number" and panel.skill>=25 and panel.skill<31 and facts and facts.Observe then
        local current=facts:Observe("TAILORING",12044)
        local tier=current and current.observed and current.skillup and current.skillup.tier
        if tier and tier~="UNKNOWN" and tier~="ORANGE" then return nil end
    end
    local function shallow(row)local out={};for k,v in pairs(row)do out[k]=v end;return out end
    local result={}
    for index,row in ipairs(route) do
        local copy=shallow(row);copy.routeIndex=row.routeIndex or index
        if index==1 then
            copy.skillTarget=25
            -- Keep the historical proportional estimate on the preceding band.
            copy.historicalEstimateSkillTarget=row.skillTarget
            result[#result+1]=copy
            result[#result+1]={skillMin=25,skillTarget=31,routeIndex=index,
                recipeID=12044,recipe=f.recipe,requiredSkill=1,requiredSkillAuthority="WOWHEAD_FOREVER",
                requiredSkillSourceURL=f.sourceURL,rawYellowThreshold=40,rawGreyThreshold=60,
                rawDifficultySourceBuild=70450,materialSourceBuild=70450,
                materials={{itemID=2996,name="Bolt of Linen Cloth",quantity=1,source="crafted"},
                    {itemID=2320,name="Coarse Thread",quantity=1,source="vendor"}},
                outputItemID=10045,outputYieldLiveVerified=false,outputYieldStatus=f.outputYieldStatus,
                recipeSource="trainer",recipeAccessObserved=false,recipeLearnSourceEvidence=f.learning,
                expectedCrafts=6,craftCountQualified=false,planningEstimateQualified=true,
                craftCountAuthority="USER_APPROVED_ORANGE_100_SCENARIO",
                sourceQualificationContract="tailoring-25-31-source-planning-v1",
                evidence=f.sourceURL,sourceBuild=70450,readOnly=true,
                plannerEligible=true,executionEligible=false,nativeDispatchAllowed=false}
        else result[#result+1]=copy end
    end
    return result
end
function Qualification:GetPlanningSteps(dataset,context)
    local result=earlyPlanningSteps(self,dataset)
    if context and context.currentOnly then
        -- A demanded next action must not score/reserve every future band.
        -- Full projections remain explicit GetScopePlan/GetProgressionSteps
        -- requests. This projection carries no hypothetical future inventory.
        local skill=tonumber(context.skill)
        if skill and skill>=31 and skill<40 then
            return self:GetPlanningSteps(dataset,{skill=skill,boundedForecast=true,goalSkill=40})
        end
        local choices
        if skill and skill>=40 and skill<50 then choices=self:GetIntervalAlternatives(dataset,skill)
        elseif skill and skill>=50 and skill<77 then choices=self:GetJourneymanAlternatives(dataset,skill)
        elseif skill and skill>=77 and skill<300 then choices=self:GetWoolAlternatives(dataset,skill) end
        if choices then
            local selector=JLP:GetModule("UniversalCurrentStep")
            local chosen=selector and selector:SelectProgressionAlternative(choices,skill,context.strategy,context.learnedRecipes)
            if chosen then return {chosen} end
        end
        for index,row in ipairs(result or dataset and dataset.route or {}) do
            if skill and skill>=(row.skillMin or 0) and skill<(row.skillTarget or 0) then
                local copy={};for k,v in pairs(row) do copy[k]=v end
                copy.routeIndex=row.routeIndex or index
                return {copy}
            end
        end
        return {}
    end
    if not (dataset and dataset.linenProgression) then return result end
    if not result then
        result={}
        for index,row in ipairs(dataset.route or {})do
            local copy={};for k,v in pairs(row)do copy[k]=v end
            copy.routeIndex=row.routeIndex or index;result[#result+1]=copy
        end
    end
    local api=JLP:GetModule("ProfessionAPI")
    local panel=api and api.Get and api:Get("TAILORING")
    local at=context and context.skill or panel and tonumber(panel.skill) or 40
    local ceiling=context and context.boundedForecast and math.min(300,context.goalSkill or at+20) or 300
    if context and context.boundedForecast then
        local scoped={};for _,row in ipairs(result) do
            if (row.skillTarget or 0)>at and (row.skillMin or 0)<ceiling then scoped[#scoped+1]=row end
        end;result=scoped
    end
    local choices
    if not (context and context.boundedForecast and at>=50) then
        choices=self:GetIntervalAlternatives(dataset,(at>=40 and at<50) and at or 40)
    end
    local selector=JLP:GetModule("UniversalCurrentStep")
    local chosen=choices and selector and selector.SelectProgressionAlternative and
        selector:SelectProgressionAlternative(choices,(at>=40 and at<50) and at or 40)
    if chosen then
        local expanded={}
        for _,row in ipairs(result)do
            if row.recipeID==12044 and row.skillMin==31 then
                row.skillTarget=40;row.historicalEstimateSkillTarget=50
                row.rawYellow=40;row.rawGrey=60
                local pants
                for _,option in ipairs(choices)do if option.recipeID==12044 then pants=option end end
                if pants then row.materials=pants.materials end
                if pants and at>=31 and at<40 then
                    local facts=JLP:GetModule("ProfessionPlanningFacts")
                    local observation=facts and facts.Observe and facts:Observe("TAILORING",12044)
                    local tier=observation and observation.observed and observation.skillup and observation.skillup.tier
                    if tier and tier~="UNKNOWN" and tier~="ORANGE" then pants=nil end
                end
                if pants then row.historicalEstimateSkillTarget=nil;row.sourceQualificationContract="tailoring-40-50-forever-v1"
                row.expectedCrafts=9;row.craftCountQualified=false;row.planningEstimateQualified=true
                row.readOnly=true;row.executionEligible=false;row.nativeDispatchAllowed=false
                row.craftCountAuthority="USER_APPROVED_ORANGE_100_YELLOW_60_SCENARIO" end
                -- Source-qualified orange transition when available; otherwise preserve the historical denominator.
                expanded[#expanded+1]=row;expanded[#expanded+1]=chosen
            else expanded[#expanded+1]=row end
        end
        result=expanded
    end
    if dataset.journeymanProgression and selector and selector.SelectProgressionAlternative then
        local expanded={}
        for _,row in ipairs(result)do
            if row.recipeID==8776 and row.skillMin==50 then
                for _,band in ipairs({{50,60},{60,67},{67,75},{75,77}})do
                    local start=(at>=band[1] and at<band[2]) and at or band[1]
                    local finish=math.min(ceiling,band[2])
                    local options=start<finish and self:GetJourneymanAlternatives(dataset,start,finish)
                    local chosen=options and selector:SelectProgressionAlternative(options,start)
                    if chosen then expanded[#expanded+1]=chosen
                    else
                        local fallback={};for k,v in pairs(row)do fallback[k]=v end
                        fallback.skillMin=band[1];fallback.skillTarget=band[2]
                        fallback.historicalEstimateSkillTarget=77
                        expanded[#expanded+1]=fallback
                    end
                end
            else expanded[#expanded+1]=row end
        end
        result=expanded
    end
    if dataset.woolProgression and selector then
        local initial=context and context.inventory or self:PlanningInventory(context and context.reservedStock)
        local pool={};for id,n in pairs(initial)do
            local reserved=context and context.inventory and context.reservedStock and context.reservedStock[id]
            pool[id]=math.max(0,n-math.max(0,tonumber(reserved) or 0))
        end
        local expanded={}
        local function reserve(row,crafts)
            for _,m in ipairs(row.materials or {})do
                local gross=m.quantity*crafts;local available=pool[m.itemID]
                if available~=nil then
                    local shortage=math.max(0,gross-available);pool[m.itemID]=math.max(0,available-gross)
                    if m.craftedFrom and pool[m.craftedFrom.itemID]~=nil then
                        pool[m.craftedFrom.itemID]=math.max(0,pool[m.craftedFrom.itemID]-shortage*m.craftedFrom.quantity)
                    end
                end
            end
        end
        for _,row in ipairs(result)do
            if (row.recipeID==12046 and row.skillMin==77) or (row.recipeID==2402 and row.skillMin==102) or
               (row.recipeID==2399 and row.skillMin==107) or (row.recipeID==3848 and row.skillMin==110) then
                local bands=row.skillMin==110 and {{110,112},{112,115},{115,120},{120,125}} or
                    row.skillMin==107 and {{107,110}} or row.skillMin==102 and {{102,107}} or
                    {{77,80},{80,85},{85,90},{90,95},{95,97},{97,100},{100,102}}
                for _,band in ipairs(bands)do
                    local start=math.max(at,band[1])
                    local finish=math.min(ceiling,band[2])
                    if start<finish then
                        local snapshot={};for id,n in pairs(pool)do snapshot[id]=n end
                        local choices=self:GetWoolAlternatives(dataset,start,finish,{inventory=snapshot})
                        local chosen=choices and selector:SelectProgressionAlternative(choices,start,context and context.strategy,context and context.learnedRecipes)
                        if chosen then expanded[#expanded+1]=chosen;reserve(chosen,chosen.scenarioCrafts)
                        else
                            local fallback={};for k,v in pairs(row)do fallback[k]=v end
                            fallback.skillMin=start;fallback.skillTarget=finish
                            fallback.historicalEstimateSkillTarget=row.skillTarget
                            expanded[#expanded+1]=fallback
                        end
                    elseif at<77 then expanded[#expanded+1]=row end
                end
                if row.recipeID==3848 and row.skillMin==110 then
                    local future={};for k,v in pairs(row)do future[k]=v end
                    future.skillMin=125;future.expectedCrafts=nil;future.deferredProgression=true;future.readOnly=true
                    future.craftEstimateGapFromSkill=125
                    future.historicalEstimateSkillTarget=row.skillTarget
                    expanded[#expanded+1]=future
                end
            else
                expanded[#expanded+1]=row
                if row.skillTarget and row.skillTarget>at and row.skillMin and row.skillMin<77 and row.expectedCrafts then
                    local casts=row.rawYellow and self:ScenarioCrafts(row,math.max(at,row.skillMin),row.skillTarget) or row.expectedCrafts
                    if casts then reserve(row,casts) end
                end
            end
        end
        result=expanded
        local limit=math.min(ceiling,dataset.woolProgression.artisanTarget or dataset.woolProgression.expertTarget or 125)
        if limit and limit>125 then
            local expert={};local inserted=false
            for _,row in ipairs(result)do
                if row.skillTarget and row.skillTarget>125 and row.skillMin and row.skillMin<limit then
                    if not inserted then
                        inserted=true
                        local bounds={125,130,135,140,142,145,150,155,160,165,170,175,180,185,190,195,200,205,210,215,220,225,230,235,240,245,250,255,260,265,270,275,280,285,290,295,300}
                        for i=1,#bounds-1 do
                            local start=math.max(at,bounds[i]);local finish=math.min(limit,bounds[i+1])
                            if start<finish then
                                local choices=self:GetWoolAlternatives(dataset,start,finish,{inventory=pool})
                                local chosen=choices and selector:SelectProgressionAlternative(choices,start,context and context.strategy,context and context.learnedRecipes)
                                if chosen then expert[#expert+1]=chosen;reserve(chosen,chosen.scenarioCrafts)
                                else expert[#expert+1]={skillMin=start,skillTarget=finish,recipeID=row.recipeID,recipe=row.recipe,
                                    deferredProgression=true,readOnly=true,craftEstimateGapFromSkill=start,historicalEstimateSkillTarget=finish} end
                            end
                        end
                    end
                    if row.skillTarget>limit then
                        local future={};for k,v in pairs(row)do future[k]=v end
                        future.skillMin=limit;future.expectedCrafts=nil;future.craftCountQualified=false;future.deferredProgression=true;future.readOnly=true;future.craftEstimateGapFromSkill=limit
                        expert[#expert+1]=future
                    end
                else expert[#expert+1]=row end
            end
            result=expert
        end
    end
    for _,row in ipairs(result)do
        if row.recipeID==12044 and row.skillMin<40 then
            local joined=self:AnnotateDB2(row)
            if not joined then
                row.planningEstimateQualified=false;row.craftCountQualified=false
                row.sourceQualificationContract=nil;row.recipeDataStatus="DB2_RECIPE_FIELD_CONFLICT"
            end
        end
    end
    if context and context.boundedForecast then
        local scoped={};for _,row in ipairs(result) do
            if (row.skillTarget or 0)>at and (row.skillMin or 0)<ceiling then scoped[#scoped+1]=row end
        end;result=scoped
    end
    return result
end
JLP:RegisterModule("TailoringRecipeQualification",Qualification)
