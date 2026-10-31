local _, JLP = ...

local function prerequisiteCurrentStep(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    if ownership and ownership.owned==true then return nil end
    local state=ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN"
    local reg=JLP:GetModule("ProfessionRegistry")
    local label=reg and reg:GetDisplayNameOrKey(key) or tostring(key)
    local text=state=="PROFESSION_NOT_LEARNED" and
        ("Learn "..label.." before JuztLevel can plan this profession.") or
        ("Verify learned "..label.." ownership before JuztLevel can plan this profession.")
    return {key=ownership and ownership.key or key,ownership=ownership,state=state,
        status=state,terminalReason=state,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,lightweightPrerequisite=true,guidance=text,action=text,actionKind="prerequisite"}
end

-- Source-backed, character-aware recommendation. No build/session/evidence
-- receipt is REQUIRED for advisory planning. Historical source metadata and
-- live current-character API state are independent inputs. NEVER native dispatch.
local S={contract="universal-current-step-advisory-v1",readOnly=true,
    nativeDispatchAllowed=false,executionEligible=false}
function S:FormatCraftStep(output,plannedCasts)
    if type(output)~="table" then return output end
    -- Current Step batch unit is CASTS, not skill-ups or output items. The
    -- chosen scenario count comes from the existing qualified plan. Forecast
    -- output is never inventory, including yields >1 or unknown yields.
    local casts=tonumber(plannedCasts or output.remainingCrafts)
    if not(casts and casts>0 and casts<math.huge and casts==math.floor(casts))then return output end
    if output.kind=="craft" and casts then
        output.remainingCrafts=casts
        output.craftQuantity=casts;output.craftQuantityUnit="CASTS"
        output.craftInstruction="Craft "..casts.." "..tostring(output.recipe)
        for _,m in ipairs(output.materials or {})do
            m.perCraft=m.perCraft or m.quantity
            m.immediateRequired=m.perCraft -- next manual transaction; preserves existing supply-order identity
            m.required=m.perCraft;m.batchRequired=m.perCraft*casts
            m.batchMissing=m.bagsKnown==true and math.max(0,m.batchRequired-(m.bags or 0))or nil
            m.missing=m.bagsKnown==true and math.max(0,m.required-(m.bags or 0))or nil
        end
        output.craftInstructionDetail=output.nextAction
        if output.learned==true and output.bagReady==true and (output.requiredNextAction==nil or output.requiredNextAction=="manual-craft") and
            not output.manualCraftBlockedByRecipePrerequisite then
            output.nextAction=output.craftInstruction
        end
    end
    return output
end
local indexed=nil -- retain only the last viewed profession to bound addon memory
local function number(v)
    local n=tonumber(v)
    if n and n==n and n>=0 and n<math.huge and n==math.floor(n) then return n end
end
local function integer(v) local n=number(v);return n and n>0 and n or nil end
local function split(s,delimiter)
    local r={};local pos=1
    while true do
        local a,b=string.find(s,delimiter,pos,true)
        if not a then r[#r+1]=string.sub(s,pos);break end
        r[#r+1]=string.sub(s,pos,a-1);pos=b+1
    end
    return r
end
local function safeMaterials(rows)
    if type(rows)~="table" or #rows==0 then return nil end
    local out={};local consolidated={}
    for _,m in ipairs(rows) do
        local id=integer(m.itemID)
        local qty=integer(m.quantity or m.perCraft)
        if not id or not qty or qty>100000 then return nil end
        local row=consolidated[id]
        if row then row.quantity=row.quantity+qty
        else
            row={itemID=id,quantity=qty,name=m.name,source=m.source or "unknown",
                craftedFrom=m.craftedFrom}
            consolidated[id]=row;out[#out+1]=row
        end
    end
    return out
end
local function dbMaterials(raw)
    if type(raw)~="string" or raw=="?" or raw=="-" or raw=="" then return nil end
    local rows={}
    for part in string.gmatch(raw,"[^,]+") do
        local id,qty=string.match(part,"^(%d+):(%d+)$")
        if not id then return nil end
        rows[#rows+1]={itemID=tonumber(id),quantity=tonumber(qty),source="unknown"}
    end
    return safeMaterials(rows)
end
-- Audit F02: source merge requires canonical recipe name parity, not only spellID.
local function canonicalRecipeName(name)
    if type(name)~="string" then return nil end
    local normalized=string.lower(name):gsub("[^%w]","")
    return normalized~="" and normalized or nil
end
local function candidateIndex(key,dataset,skill,fullRoute)
    local provider=JLP:GetModule("ProfessionDatasetProvider")
    local registered=provider and provider.GetRegisteredDataset and provider:GetRegisteredDataset(key)
    dataset=type(registered)=="table" and registered or dataset
    if key=="TAILORING" and type(skill)=="number" and skill>=40 and skill<50 then
        local qualification=JLP:GetModule("TailoringRecipeQualification")
        local choices=qualification and qualification.GetIntervalAlternatives and
            qualification:GetIntervalAlternatives(dataset,skill)
        if choices then return choices end
    end
    if key=="TAILORING" and type(skill)=="number" and skill>=50 and skill<77 then
        local q=JLP:GetModule("TailoringRecipeQualification")
        local choices=q and q.GetJourneymanAlternatives and q:GetJourneymanAlternatives(dataset,skill)
        if choices then return choices end
    end
    if key=="TAILORING" and type(skill)=="number" and skill>=77 and skill<((JLP.data and JLP.data.tailoring and JLP.data.tailoring.woolProgression or {}).artisanTarget or (JLP.data and JLP.data.tailoring and JLP.data.tailoring.woolProgression or {}).expertTarget or 125) and not fullRoute then
        local q=JLP:GetModule("TailoringRecipeQualification")
        local choices=q and q.GetWoolAlternatives and q:GetWoolAlternatives(dataset,skill)
        if choices then return choices end
    end
    if key=="BLACKSMITHING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        if facts and facts.GetBlacksmithingCandidates then return facts:GetBlacksmithingCandidates(skill,fullRoute) end
    end
    if key=="LEATHERWORKING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        if facts then return facts:GetLeatherworkingCandidates(skill,fullRoute) end
    end
    if key=="ENGINEERING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        if facts then return facts:GetEngineeringCandidates(skill,fullRoute) end
    end
    if key=="ALCHEMY" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        if facts and facts.GetAlchemyCandidates then return facts:GetAlchemyCandidates(skill,fullRoute) end
    end
    if (key=="FIRST_AID" or key=="COOKING") and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        return facts and facts:GetEnchantingCandidates(skill,fullRoute,false,key) or {}
    end
    if key=="ENCHANTING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        if facts and facts.GetEnchantingCandidates then return facts:GetEnchantingCandidates(skill,fullRoute) end
    end
    local raw=JLP.data and JLP.data.build70450Recipes
    local source=raw and raw.professions and raw.professions[key]
    local packed=source and source.packed
    local early=key=="TAILORING" and type(dataset)=="table" and dataset.earlyProgression and
        (fullRoute==true or (type(skill)=="number" and skill>=25 and skill<31)) or false
    -- Source data are immutable for this addon lifetime. Dataset identity is
    -- included to avoid merging stale route structures across overrides.
    local old=indexed
    if not early and old and old.key==key and old.packed==packed and old.dataset==dataset and not old.early then return old.rows end
    local byID,rows={},{ }
    local route=type(dataset)=="table" and (dataset.route or dataset.steps) or {}
    if early and provider and provider.GetProgressionSteps then route=provider:GetProgressionSteps(key,dataset) end
    for _,r in ipairs(route) do
        local id=integer(r.recipeID or r.spellID)
        if id and not byID[id] and type(r.recipe)=="string" and r.recipe~="" then
            local row={recipeID=id,recipe=r.recipe,route=true,
                routeSkillMin=number(r.skillMin),routeSkillTarget=number(r.skillTarget),
                requiredSkill=number(r.requiredSkill),
                recipeSource=r.recipeSource or (type(r.sourceRequirement)=="table" and r.sourceRequirement.kind),
                sourceSpellFocusReference=r.sourceSpellFocusReference,
                station=r.station or r.workstation,
                materials=safeMaterials(r.materials),rawGrey=number(r.rawGrey or r.rawDifficultyHigh),
                rawYellow=number(r.rawYellow or r.rawDifficultyLow),
                sourceBuild=dataset.sourceBuild}
            rows[#rows+1]=row;byID[id]=row
        end
    end
    if type(packed)=="string" then
        for line in string.gmatch(packed,"[^\n]+") do
            local f=split(line,"^")
            if #f==12 then
                local id=integer(f[1]);local name=f[12]
                local reagents=dbMaterials(f[10]);local grey=number(f[5]);local yellow=number(f[4])
                if id and name and name~="" and reagents and grey and grey>0 then
                    local row=byID[id]
                    if row and canonicalRecipeName(row.recipe)~=canonicalRecipeName(name) then
                        -- Do not silently replace a route's reagents with a differently
                        -- named DB record merely because its recipe ID matches.
                        row.sourceNameConflict=true
                        row.conflictingDBName=name
                        row.sourceNameConflictReason="SOURCE_RECIPE_NAME_PARITY_FAILED"
                    elseif row then
                        -- Prefer the newer owner DB2 reagent relation where exact ID
                        -- matches. Never manufacture quantities from output effects.
                        local old={}
                        for _,m in ipairs(row.materials or {}) do old[m.itemID]=m end
                        for _,m in ipairs(reagents) do
                            local historical=old[m.itemID]
                            if historical then
                                m.name=historical.name
                                m.source=historical.source
                                m.craftedFrom=historical.craftedFrom
                            end
                        end
                        row.materials=reagents
                        row.rawGrey=grey;row.rawYellow=yellow;row.sourceBuild=70450
                    else
                        row={recipeID=id,recipe=name,route=false,materials=reagents,
                            rawGrey=grey,rawYellow=yellow,sourceBuild=70450,
                            rawMinRank=number(f[3]),acquireMethod=number(f[6])}
                        rows[#rows+1]=row;byID[id]=row
                    end
                end
            end
        end
    end
    -- A future forecast must retain ALL qualified choices, including a belt
    -- learned later than the current panel snapshot. Do not freeze the whole
    -- forecast to the recipe selected for the current character's route view.
    if key=="TAILORING" and fullRoute==true then
        local qualification=JLP:GetModule("TailoringRecipeQualification")
        local choices=qualification and qualification.GetIntervalAlternatives and
            qualification:GetIntervalAlternatives(dataset,40)
        for _,choice in ipairs(choices or {})do
            local row=byID[choice.recipeID]
            if row and not row.sourceNameConflict then
                row.route=true;row.routeSkillMin=math.min(row.routeSkillMin or 40,40)
                row.routeSkillTarget=math.max(row.routeSkillTarget or 50,50)
                row.requiredSkill=choice.requiredSkill;row.materials=choice.materials
            end
        end
    end
    if key=="TAILORING" and fullRoute==true then
        local q=JLP:GetModule("TailoringRecipeQualification")
        for _,start in ipairs({50,60,67,75})do
            local choices=q and q.GetJourneymanAlternatives and q:GetJourneymanAlternatives(dataset,start)
            for _,choice in ipairs(choices or {})do
                local row=byID[choice.recipeID]
                if row and not row.sourceNameConflict then
                    row.route=true;row.routeSkillMin=math.min(row.routeSkillMin or start,start)
                    row.routeSkillTarget=math.max(row.routeSkillTarget or 77,77)
                    row.requiredSkill=choice.requiredSkill;row.materials=choice.materials
                end
            end
        end
    end
    -- Secondary WoWhead guide intervals are advisory; their aggregated
    -- shopping-list quantities must NOT replace DB per-craft reagents.
    local secondary=JLP.data and JLP.data.foreverSecondaryLeveling
    local ref=secondary and secondary.professions and secondary.professions[key]
    local byName={}
    for _,row in ipairs(rows) do
        local name=string.lower(row.recipe):gsub("[^%w]","")
        byName[name]=row
    end
    for _,step in ipairs(ref and ref.steps or {}) do
        local name=type(step.recipe)=="string" and string.lower(step.recipe):gsub("[^%w]","") or ""
        local found=byName[name]
        if found and not found.routeSkillMin then
            found.route=true;found.routeSkillMin=number(step.skillMin)
            found.routeSkillTarget=number(step.skillMax or step.skillTarget)
            found.guideSource="WOWHEAD_FOREVER_SECONDARY_GUIDE_REFERENCE"
        end
    end
    indexed={key=key,packed=packed,dataset=dataset,rows=rows,early=early}
    return rows
end
-- Audit F06/F07: a bounded prioritized read, with a bounded second phase if
-- the first 96 reads found no learned recipe. The full panel identity is
-- enumerated, but no build-specific API allowlist is used. A live recipe tier
-- can supersede historical DB grey cutoffs for read-only planning.
local function liveLearned(key,override,rows,skill)
    if type(override)=="table" then return override,"OVERRIDE",{} end
    local api=JLP:GetModule("ProfessionAPI")
    local panel=api and api.GetReadOnlyProfessionObservation and api:GetReadOnlyProfessionObservation()
    if not (panel and panel.observed==true and panel.professionKey==key) then return nil,"PANEL_NOT_OPEN" end
    local t=C_TradeSkillUI
    if type(t)~="table" or type(t.GetAllRecipeIDs)~="function" or
        type(t.GetRecipeInfo)~="function" then return nil,"RECIPE_API_UNAVAILABLE" end
    local fnIDs,fnInfo=t.GetAllRecipeIDs,t.GetRecipeInfo
    local ok,ids=pcall(fnIDs)
    if not ok or type(ids)~="table" then return nil,"RECIPE_LIST_UNAVAILABLE" end
    local seen={}
    for i=1,math.min(#ids,1600) do
        local id=integer(ids[i]);if id then seen[id]=true end
    end
    local prioritized={}
    for _,row in ipairs(rows or {}) do
        if seen[row.recipeID] and not row.sourceNameConflict and
            (row.route or row.rawGrey or row.rawYellow) then
            prioritized[#prioritized+1]=row
        end
    end
    table.sort(prioritized,function(a,b)
        local function priority(r)
            if r.routeSkillMin and r.routeSkillMin<=skill and
                (not r.routeSkillTarget or skill<r.routeSkillTarget) then return 0 end
            if r.rawGrey and skill<r.rawGrey then return 1 end
            return 2 -- historical gray may be wrong: still read live difficulty
        end
        local pa,pb=priority(a),priority(b)
        if pa~=pb then return pa<pb end
        local da=math.abs(skill-(a.routeSkillMin or a.rawYellow or skill))
        local db=math.abs(skill-(b.routeSkillMin or b.rawYellow or skill))
        if da~=db then return da<db end
        return a.recipeID<b.recipeID
    end)
    local known,tiers={},{}
    local learnedFound=false
    local reads=0
    local firstLimit=math.min(96,#prioritized)
    local lastLimit=math.min(384,#prioritized)
    for i=1,lastLimit do
        if i>firstLimit and learnedFound then break end
        reads=reads+1
        local row=prioritized[i]
        local good,info=pcall(fnInfo,row.recipeID)
        if good and type(info)=="table" and type(info.learned)=="boolean" and
            (info.recipeID==nil or info.recipeID==row.recipeID) and
            (not info.name or canonicalRecipeName(info.name)==canonicalRecipeName(row.recipe)) then
            known[row.recipeID]=info.learned
            if info.learned==true then learnedFound=true end
            if type(info.relativeDifficulty)=="number" and
                info.relativeDifficulty>=0 and info.relativeDifficulty<=3 then
                tiers[row.recipeID]=info.relativeDifficulty
            end
        end
    end
    local again=api:GetReadOnlyProfessionObservation()
    if not again or again.observed~=true or again.observationToken~=panel.observationToken or
        again.skill~=panel.skill or fnIDs~=t.GetAllRecipeIDs or fnInfo~=t.GetRecipeInfo then
        return nil,"PANEL_CHANGED",{}
    end
    -- Caller must never interpret unknown (unread) recipes as learned=false.
    return known,"CURRENT_PANEL",tiers
end
local function inventoryCount(id,memo)
    if memo[id] then return memo[id] end
    local inv=JLP:GetModule("Inventory")
    local owned=inv and inv.GetOwned and inv:GetOwned(id)
    local n=type(owned)=="table" and owned.bagKnown==true and number(owned.bags) or nil
    local row={known=n~=nil,quantity=n}
    memo[id]=row
    return row
end
local function price(id,qty,memo)
    local key=tostring(id)..":"..tostring(qty)
    if memo[key] then return memo[key] end
    local resolver=JLP:GetModule("PriceResolver")
    local r={known=false,status="NO_AUCTION_QUOTE",estimated=true}
    if resolver and type(resolver.GetItemSnapshot)=="function" then
        local row,scope=resolver:GetItemSnapshot(id,true)
        -- Displayable same-realm/faction historical prices are estimates,
        -- even when client build has changed. Missing AH is never a blocker.
        local unit=row and number(row.minUnitBuyout or row.minUnitPrice)
        if unit and scope and scope.displayableAdvisory==true then
            r={known=true,cost=unit*qty,unit=unit,status=scope.status,
                estimated=scope.trustedForCostEstimate~=true}
        end
    end
    memo[key]=r;return r
end
local function scoreCandidate(c,skill,learned,stockMemo,priceMemo,strategy,learnedSource,key,liveTier)
    if not c.materials or c.sourceNameConflict then return nil end
    if c.scenarioCrafts and not c.preparationOnly and liveTier~=nil and
        liveTier~=(skill<c.rawYellow and 0 or (c.rawGreen and skill>=c.rawGreen and 2 or 1)) then return nil end
    -- Historical grey is advisory only. A fresh observed ORANGE/YELLOW/GREEN
    -- learned recipe overrides historical grey, but observed GRAY always blocks.
    -- A currently observed GRAY recipe is retained as a VERIFY candidate, so
    -- the interface can explain the live block instead of silently hiding it.
    if not c.preparationOnly and c.rawGrey and skill>=c.rawGrey and liveTier==nil then return nil end
    local gate=JLP:GetModule("ProfessionRecipeMinimumGate")
    local admitted,reason,minFact=true,nil,nil
    if gate then admitted,reason,minFact=gate:Permits(key,c,skill,learned,learnedSource) end
    if not admitted then return nil end
    -- Registered skill windows provide useful *routing* references, not proof
    -- of learning. DB-only recipes are eligible as alternatives when the
    -- current character has actually learned them.
    local baseline=(c.routeSkillMin and skill>=c.routeSkillMin and
        (not c.routeSkillTarget or skill<c.routeSkillTarget))==true
    if c.route and c.routeSkillMin and skill<c.routeSkillMin and learned~=true then return nil end
    -- P0-195: exact sourced recipe minimums can yield a *learning/verification*
    -- task when the character has not learned the recipe yet. A raw historical
    -- DB recipe with no exact access evidence still cannot become an action.
    -- This admission is advisory and is NOT a trainer/teaching-item proof.
    -- P0-220: strict 217/218/219 receipts also authorize a READ-ONLY LEARN
    -- recommendation. They were accidentally omitted from this whitelist,
    -- despite ProfessionRecipeMinimumGate having verified the live source join.
    -- Route-only/yellow/name-join/cached assertions must never pass this gate.
    local exactReference=minFact and (
        minFact.source=="FOREVER_SELECTED_RECIPE_MINIMUM_194" or
        minFact.source=="FOREVER_SELECTED_RECIPE_MINIMUM_193" or
        minFact.source=="FOREVER_EXACT_SPELL_OR_ITEM" or
        minFact.source=="FOREVER_PATTERN_DB2_70532" or
        minFact.source=="ENCHANTING_70532_QUALIFIED_FLOOR" or minFact.source=="ALCHEMY_70532_QUALIFIED_FLOOR" or minFact.source=="BLACKSMITHING_70532_QUALIFIED_FLOOR" or minFact.source=="ENGINEERING_70532_QUALIFIED_FLOOR" or minFact.source=="LEATHERWORKING_70532_QUALIFIED_FLOOR" or
        (minFact.sourceProofCurrent==true and
            minFact.exactPrimaryDBRouteQualified==true) or
        (minFact.sourceProofCurrent==true and
            minFact.exactPrimarySourceQualified==true) or
        (minFact.source=="FOREVER_EXACT_PRIMARY_DB_ROUTE_MINIMUM_218" and
            minFact.exactPrimaryDBRouteQualified==true))
    if not c.route and learned~=true and not exactReference then return nil end
    if not baseline and not (learned==true or exactReference or (c.route and
        c.routeSkillMin and skill>=c.routeSkillMin)) then return nil end
    local pattern
    local trainerAcquisitionRank=0
    if (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and learned~=true and c.sourceFact and c.sourceFact.trainerReferences then
        local who=type(UnitFactionGroup)=="function" and UnitFactionGroup("player") or nil
        for _,lead in ipairs(c.sourceFact.trainerReferences)do
            if lead.faction=="Neutral" or who and lead.faction==who then trainerAcquisitionRank=3 end
        end
    end
    local sourceBridge=JLP:GetModule("RecipeSourcePlanningBridge")
    if learned~=true and sourceBridge and sourceBridge.GetTrainerAcquisition then
        local training=sourceBridge:GetTrainerAcquisition(key,c.recipeID)
        if training then trainerAcquisitionRank=training.availabilityRank end
    end
    if learned~=true and sourceBridge and sourceBridge.GetPatternAcquisition then
        pattern=sourceBridge:GetPatternAcquisition(key,c.recipeID,skill)
    end
    if key=="COOKING"and learned~=true then
        local secondary=JLP:GetModule("SecondaryLevelingPlanner");local api=JLP:GetModule("ProfessionAPI")
        local a=secondary and secondary:GetOperationalAccess(key,api and api:Get(key),c.recipeID)
        if a then trainerAcquisitionRank=(a.status=="RECHECK_BOOK_SOURCE"and 0 or a.status=="USE_BOOK_MANUALLY"and 6 or a.status=="BUY_BOOK_MANUALLY"and 5 or a.actor and 3 or 1)end
    end
    local total,missing,unknown,quotedCost,allQuoted,units=0,0,0,0,true,0
    local materialStates={}
    for _,m in ipairs(c.materials) do
        local owned=inventoryCount(m.itemID,stockMemo)
        local shortage=owned.known and math.max(0,m.quantity-owned.quantity) or nil
        local q=shortage and shortage>0 and price(m.itemID,shortage,priceMemo) or nil
        if shortage==nil then unknown=unknown+1;allQuoted=false
        elseif shortage>0 then
            missing=missing+shortage
            if q and q.known then quotedCost=quotedCost+q.cost
            else allQuoted=false end
        end
        units=units+m.quantity
        materialStates[#materialStates+1]={itemID=m.itemID,name=m.name,perCraft=m.quantity,
            required=m.quantity,bagsKnown=owned.known,bags=owned.quantity,
            missing=shortage,price=q and q.cost or nil,priceStatus=q and q.status or "UNKNOWN",
            source=m.source,craftedFrom=m.craftedFrom,readOnly=true}
    end
    local scenarioCost,scenarioQuoted,scenarioReady=0,true,true
    local alchemyPreparationChoices,preparationSeconds={},0
    if c.scenarioCrafts then
        for _,m in ipairs(c.materials)do
            local owned=inventoryCount(m.itemID,stockMemo)
            if c.planningInventory then owned={known=c.planningInventory[m.itemID]~=nil,quantity=c.planningInventory[m.itemID]} end
            if not owned.known then scenarioQuoted=false;scenarioReady=false
            else
                local need=math.max(0,m.quantity*c.scenarioCrafts-owned.quantity)
                if need>0 then
                    local id=m.itemID
                    if key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING" then
                        local facts=JLP:GetModule("ProfessionPlanningFacts")
                        local f,live
                        if facts and facts.GetAlchemyProducer then f,live=facts:GetAlchemyProducer(id,key)end
                        if f and live and live.observed and live.learned==true and skill>=f.minimum then
                            local casts=math.ceil(need/f.outputQuantity)
                            local rawCost,rawQuoted,rawReady=0,true,true
                            for _,raw in ipairs(f.referenceMaterials)do
                                local stock=inventoryCount(raw.itemID,stockMemo)
                                local shortage=stock.known and math.max(0,casts*raw.quantity-stock.quantity) or nil
                                if shortage==nil then rawReady=false;rawQuoted=false
                                elseif shortage>0 then
                                    rawReady=false;local q=price(raw.itemID,shortage,priceMemo)
                                    if q.known then rawCost=rawCost+q.cost else rawQuoted=false end
                                end
                            end
                            local direct=price(id,need,priceMemo)
                            local make=(strategy=="self_found" and rawReady) or
                                (strategy=="fastest" and rawReady) or
                                (strategy=="economical" and rawQuoted and (not direct.known or rawCost<direct.cost))
                            if key=="BLACKSMITHING"or key=="ENGINEERING"then
                                -- UNKNOWN comparison is not a verified rejection of a
                                -- learned producer. Preparation can acquire inputs next;
                                -- it never claims those inputs or outputs are in bags.
                                if strategy=="self_found"then make=true
                                elseif strategy=="fastest"and not rawReady then make=nil
                                elseif strategy=="economical"and not rawReady and not (rawQuoted and direct.known)then make=nil end
                            end
                            if key=="ALCHEMY"and not rawReady then
                                local bridge=JLP:GetModule("GatheringMaterialBridge")
                                local sourceable,fishInput=true,false
                                for _,raw in ipairs(f.referenceMaterials)do
                                    local stock=inventoryCount(raw.itemID,stockMemo)
                                    local shortage=stock.known and math.max(0,casts*raw.quantity-stock.quantity)or nil
                                    if shortage==nil then sourceable=false
                                    elseif shortage>0 then
                                        local supply=bridge and bridge.IsFishingMaterial and bridge:IsFishingMaterial(raw.itemID)and bridge:SelectFishingSupply(raw.itemID,casts*raw.quantity,strategy,key)
                                        if supply and (supply.status=="FISHING_AREA"or supply.status=="BANK")then fishInput=true
                                        else sourceable=false end
                                    end
                                end
                                -- A learned fixed-yield oil can acquire qualified fish
                                -- next. Sourceability is not stock/readiness/time/cost.
                                if sourceable and fishInput and (strategy=="self_found"or not direct.known)then make=true end
                            end
                            alchemyPreparationChoices[id]=make
                            if make then
                                need=0;scenarioReady=scenarioReady and rawReady
                                scenarioQuoted=scenarioQuoted and rawQuoted;scenarioCost=scenarioCost+rawCost
                                preparationSeconds=f.castSeconds and preparationSeconds and preparationSeconds+casts*f.castSeconds or nil
                            end
                        end
                    end
                    local producer=m.craftedFrom
                    if producer and (producer.sourceQualificationContract=="linen-2963-client-schematic-70532-v1" or producer.sourceQualificationContract=="wool-2964-client-schematic-70532-v1" or producer.sourceQualificationContract=="cloth-user-output-db2-70532-v1") then
                        -- Match Acquisition's qualified producer path. Raw stock
                        -- can inform Self-found planning, never bagReady/native craft.
                        if producer.sourceQualificationContract=="cloth-user-output-db2-70532-v1" and
                            not (producer.observed and producer.observed.observed and producer.observed.learned==true) then
                            scenarioReady=false;scenarioQuoted=false
                        end
                        id=producer.itemID
                        local raw=inventoryCount(id,stockMemo)
                        if c.planningInventory then raw={known=c.planningInventory[id]~=nil,quantity=c.planningInventory[id]} end
                        if raw.known then need=math.max(0,need*producer.quantity-raw.quantity)
                        else need=nil;scenarioReady=false;scenarioQuoted=false end
                    end
                    if need and need>0 then
                        scenarioReady=false
                        local quote=price(id,need,priceMemo)
                        if quote.known then scenarioCost=scenarioCost+quote.cost else scenarioQuoted=false end
                    end
                end
            end
        end
    end
    local familiarity=learned==true and 3 or learned==false and 0 or 1
    local bagReady=missing==0 and unknown==0
    local near=c.route and c.routeSkillMin and math.abs(skill-c.routeSkillMin) or 300
    -- Prefer known and usable before source price. In equal-knownness choices,
    -- use exact/AH-estimated missing-cost when both sides have complete quotes.
    local affinity=(c.rawYellow and (c.scenarioCrafts and skill<c.rawYellow or not c.scenarioCrafts and skill<=c.rawYellow)) and 1 or 0
    local accessRank=c.requiresAccessVerification and 0 or 1
    if key=="ENCHANTING" and c.actionType=="ENCHANT_APPLICATION" and learned==true then
        local foundation=JLP:GetModule("ProductionEnchantingTargetedExecutionFoundation")
        local target=foundation and foundation.AssessRecipeTarget and foundation:AssessRecipeTarget(c.recipeID)
        accessRank=target and target.ready and 1 or 0
    end
    -- Keep an unknown-output/station recipe as advice, but prefer a currently
    -- usable Leatherworking alternative rather than trapping the player at it.
    if (key=="LEATHERWORKING"or key=="COOKING") and learned==true and c.sourceFact then
        local f=c.sourceFact
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local live=facts and facts:Observe(key,c.recipeID)
        if not (live and live.output and live.output.fixed and live.output.itemID==f.output) then accessRank=0 end
        if (f.focusID or 0)>0 or (f.cooldownMilliseconds or 0)>0 then
            local q=JLP:GetModule("TailoringRecipeQualification")
            local state=q and q:RecipeAccess({recipeID=f.id,sourceSpellFocusReference=f.focusID>0 and f.focusID or nil,
                cooldownMS=f.cooldownMilliseconds>0 and f.cooldownMilliseconds or nil},key)
            if state~="MET" then accessRank=0 end
        end
    end
    return {patternAcquisition=pattern,acquisitionRank=pattern and pattern.availabilityRank or trainerAcquisitionRank,
        accessRank=accessRank,candidate=c,learned=learned,materials=materialStates,learnedRank=familiarity,
        bagReady=bagReady,missing=missing,unknown=unknown,
        priceComplete=allQuoted,cost=allQuoted and quotedCost or nil,
        units=units,affinity=affinity,routeDistance=near,
        scenarioCost=scenarioQuoted and scenarioCost or nil,scenarioQuoted=scenarioQuoted,
        alchemyPreparationChoices=alchemyPreparationChoices,
        craftSeconds=c.qualifiedProgression and c.castSeconds and c.scenarioCrafts and preparationSeconds and (c.castSeconds*c.scenarioCrafts+preparationSeconds) or JLP:GetModule("TailoringRecipeQualification") and
            JLP:GetModule("TailoringRecipeQualification"):ScenarioCastSeconds(c,c.scenarioCrafts) or nil,
        scenarioReady=scenarioReady,strategy=strategy,scenarioCrafts=c.scenarioCrafts,pricedItems=allQuoted and #c.materials or 0,
        minimumSkillFact=minFact,minimumSkillStatus=reason}
end
local function better(a,b,strategy)
    if not b then return true end
    if a.learnedRank~=b.learnedRank then return a.learnedRank>b.learnedRank end
    if a.acquisitionRank~=b.acquisitionRank and a.learned~=true then return a.acquisitionRank>b.acquisitionRank end
    if a.accessRank~=b.accessRank then return a.accessRank>b.accessRank end
    if (a.candidate.qualifiedProgression and b.candidate.qualifiedProgression) or (a.candidate.sourceQualificationContract=="tailoring-77-102-wool-v1" or (a.candidate.sourceQualificationContract=="tailoring-102-107-source-v1" or (a.candidate.sourceQualificationContract=="tailoring-107-125-source-v1" or (a.candidate.sourceQualificationContract=="tailoring-125-225-source-v1" or a.candidate.sourceQualificationContract=="tailoring-225-300-source-v1")))) and
        (b.candidate.sourceQualificationContract=="tailoring-77-102-wool-v1" or (b.candidate.sourceQualificationContract=="tailoring-102-107-source-v1" or (b.candidate.sourceQualificationContract=="tailoring-107-125-source-v1" or (b.candidate.sourceQualificationContract=="tailoring-125-225-source-v1" or b.candidate.sourceQualificationContract=="tailoring-225-300-source-v1")))) then
        if strategy=="self_found" and a.scenarioReady~=b.scenarioReady then return a.scenarioReady end
        if strategy=="economical" and a.scenarioQuoted and b.scenarioQuoted and a.scenarioCost~=b.scenarioCost then
            return a.scenarioCost<b.scenarioCost
        end
        -- Only compare measured cast subtotals when both are known. Travel,
        -- acquisition time and resale remain UNKNOWN, never zero.
        if strategy=="fastest" and a.craftSeconds and b.craftSeconds and a.craftSeconds~=b.craftSeconds then
            return a.craftSeconds<b.craftSeconds
        end
    end
    -- Compare whole-band material scenarios when qualified. No time/profit claim.
    if a.scenarioCrafts and b.scenarioCrafts and a.scenarioCrafts~=b.scenarioCrafts then
        if strategy=="self_found" and a.scenarioReady~=b.scenarioReady then return a.scenarioReady end
        if strategy=="economical" and a.scenarioQuoted and b.scenarioQuoted and
            a.scenarioCost~=b.scenarioCost then
            return a.scenarioCost<b.scenarioCost
        end
        return a.scenarioCrafts<b.scenarioCrafts
    end
    if strategy=="fastest" and a.affinity~=b.affinity then return a.affinity>b.affinity end
    if strategy=="self_found" and a.bagReady~=b.bagReady then return a.bagReady end
    if a.priceComplete and b.priceComplete and a.cost~=b.cost then
        return a.cost<b.cost
    end
    if a.bagReady~=b.bagReady then return a.bagReady end
    if a.unknown~=b.unknown then return a.unknown<b.unknown end
    if a.missing~=b.missing then return a.missing<b.missing end
    if a.affinity~=b.affinity then return a.affinity>b.affinity end
    if a.units~=b.units then return a.units<b.units end
    if a.routeDistance~=b.routeDistance then return a.routeDistance<b.routeDistance end
    return a.candidate.recipeID<b.candidate.recipeID
end
-- Reuse the current-step admission, character, stock and strategy contracts for
-- the shared Planner projection; receives qualified candidates, never recurses.
function S:SelectProgressionAlternative(rows,skill,strategy,knownRecipes)
    local learned,source,tiers=liveLearned("TAILORING",knownRecipes,rows,skill)
    local api=JLP:GetModule("ProfessionAPI")
    local panel=api and api.GetReadOnlyProfessionObservation and api:GetReadOnlyProfessionObservation()
    -- A current color is not an observation at a future forecast skill.
    if not panel or panel.skill~=skill then tiers=nil end
    local winner
    local stock,prices={},{}
    strategy=strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"
    for _,c in ipairs(rows)do
        local status=learned and learned[c.recipeID]
        local score=scoreCandidate(c,skill,status,stock,prices,strategy,source,"TAILORING",tiers and tiers[c.recipeID])
        if score and not (tiers and tiers[c.recipeID]==3) and better(score,winner,strategy) then winner=score end
    end
    if winner and (winner.candidate.sourceQualificationContract=="tailoring-107-125-source-v1" or (winner.candidate.sourceQualificationContract=="tailoring-125-225-source-v1" or winner.candidate.sourceQualificationContract=="tailoring-225-300-source-v1")) then
        winner.candidate.planningLearnedState=winner.learned==true and "LEARNED" or winner.learned==false and "UNLEARNED" or "UNKNOWN"
        winner.candidate.requiresLearningVerification=winner.learned~=true
    end
    return winner and winner.candidate
end
local gathering={HERBALISM=true,MINING=true,SKINNING=true,FISHING=true}
local function gatheringReference(key,skill)
    local data=JLP.data and JLP.data.gatheringReferencePacked
    local maps=data and data.maps
    if type(maps)~="table" then return nil end
    local currentMap=nil
    if type(C_Map)=="table" and type(C_Map.GetBestMapForUnit)=="function" then
        local ok,id=pcall(C_Map.GetBestMapForUnit,"player")
        if ok and number(id) then currentMap=id end
    end
    local strongest,localCandidate=nil,nil
    -- Source node maps are *references*, not live spawn detections. Never
    -- synthesize waypoints, teleport links or guaranteed spawn information.
    for mapID,rows in pairs(maps) do
        for _,r in ipairs(rows) do
            if type(r)=="table" and r[1]=="GATHERSKILLMAP_1_3_0" and
                r[2]==key and integer(r[4]) and type(r[3])=="string" then
                local minimum=number(r[5])
                if minimum and minimum<=skill then
                    local candidate={resource=r[3],objectID=r[4],
                        referenceMapID=mapID,requiredSkill=minimum,
                        source="GATHERSKILLMAP_1_3_0",readOnly=true}
                    if not strongest or minimum>strongest.requiredSkill then
                        strongest=candidate
                    end
                    if currentMap and tonumber(mapID)==currentMap and
                        (not localCandidate or minimum>localCandidate.requiredSkill) then
                        localCandidate=candidate
                    end
                end
            end
        end
    end
    return localCandidate or strongest
end
local function gatheringStep(key,skill)
    local action="Gather resources appropriate to your current profession skill; re-evaluate after every skill-up."
    local zone,resource
    if key=="FISHING" then
        local secondary=JLP.data and JLP.data.foreverSecondaryLeveling
        local tiers=secondary and secondary.fishing and secondary.fishing.tiers
        for _,row in ipairs(tiers or {}) do
            if skill>=(row.skillMin or 0) and skill<(row.skillMax or 0) then
                zone=row.zone;break
            end
        end
        action=zone and ("Fish in "..zone.."; verify the required fishing skill and replan after skill-ups.") or
            "Select a suitable fishing zone in Gathering Map and continue fishing."
    elseif key=="MINING" and JLP:GetModule("ForeverMiningNodeProgression210") then
        local guide=JLP:GetModule("ForeverMiningNodeProgression210")
        local source=guide and guide:AtSkill(key,skill)
        if source and source.nodes and #source.nodes>0 then
            resource=source.nodes[1]
            local zoneName=source.suggestedZones and source.suggestedZones[1]
            action="Mine "..resource.name.." (minimum skill "..resource.minimumSkill..") manually"..
                (zoneName and " in a source-suggested area such as "..zoneName or "")..
                "; verify node presence, rank and skill gain; replan after actual skill changes."
        else
            action="Verify a skill-appropriate Mining node in Gathering Map; no live spawn is confirmed."
        end
        local result={contract=S.contract,profession=key,kind="gather",actionKind="reference",
            action=action,skill=skill,resourceReference=resource,
            sourceProgression=source,sourceCoverage=source and source.coverage,
            navigationStatus="LOCATION_UNVERIFIED",coordinateAuthority=false,
            readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
            skillGainGuaranteed=false,materials={}}
        return result
    elseif key=="SKINNING" then
        local skin=JLP:GetModule("ForeverSkinningEligibility230")
        local advisory=skin and skin.AtSkill and skin:AtSkill(skill) or nil
        action=advisory and ("Skin eligible fully looted beasts manually (source-derived maximum mob level "..
            advisory.maximumEligibleMobLevel.." at unboosted Skinning "..skill..
            "); verify mob skinnability and actual skill gain.") or
            "Verify the skinnable corpse and skill requirement before skinning manually."
        return {contract=S.contract,profession=key,kind="gather",actionKind="reference",
            action=action,skill=skill,skinningEligibility230=advisory,
            navigationStatus="LOCATION_UNVERIFIED",coordinateAuthority=false,
            readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
            skillGainGuaranteed=false,materials={}}

    else
        resource=gatheringReference(key,skill)
        local label=key=="MINING" and "ore node" or "herb"
        if resource then
            local name=string.lower(resource.resource):gsub("_"," ")
            action="Look for "..name.." ("..label..", source minimum "..
                resource.requiredSkill..") using Gathering Map; the listed map and spawn references are not live confirmations."
        else
            action="Use Gathering Map to find a skill-appropriate "..label.."; no supported nearby node is verified."
        end
    end
    return {contract=S.contract,profession=key,kind="gather",actionKind="reference",action=action,
        skill=skill,zone=zone,resourceReference=resource,
        readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,skillGainGuaranteed=false,materials={}}
end
-- P0-227 source receipts are revalidated on demand. The attached advisory
-- is separate from the selected production/current route and cannot grant
-- native dispatch or cause a navigation handoff by itself.
local function attachStitchedCurrent(key,skill,step)
    local module=JLP:GetModule("ForeverStitchedCurrentStep227")
    if module and type(module.Review)=="function" and type(step)=="table" then
        local ok,review=pcall(module.Review,module,key,skill)
        if ok and type(review)=="table" then step.sourceStitchedCurrentReview=review end
    end
    return step
end
-- When the ordinary catalogue cannot select an eligible recipe, a source
-- stitched interval may still give a useful manual VERIFY/material review.
-- This is deliberately not `kind=craft`, even with observed learned/bags.
local function stitchedSourceFallback(key,skill)
    local review=attachStitchedCurrent(key,skill,{})
    review=review and review.sourceStitchedCurrentReview
    if not review or review.sourceGap or not review.recipeID then return nil end
    return {contract=S.contract,kind="verify",actionKind="reference",
        profession=key,skill=skill,recipeID=review.recipeID,
        recipe=review.recipe,sourceStitchedResearchFallback=true,
        sourceStitchedCurrentReview=review,
        nextAction=review.nextAction,materials=review.materials,
        -- Waypoints remain in a separate, manual-only *review*. A research
        -- source can never automatically become CURRENT_STEP navigation.
        navigationStatus=review.navigation and review.navigation.status or "LOCATION_UNVERIFIED",
        readOnly=true,sourceStatus="RESEARCH_SOURCE_REVIEW_ONLY",
        nativeDispatchAllowed=false,executionEligible=false,
        expectedCraftsQualified=false,skillGainGuaranteed=false,
        materialBudgetForecast=nil,remainingCrafts=nil}
end
-- P0-229: an independently source-pinned recipe at the *exact* published
-- minimum gives a manual verification lead when the ordinary planner has
-- no valid candidate. It is not a progression window or native craft step.
local function minimumSourceFallback(key,skill)
 local module=JLP:GetModule("ProfessionFieldChain229")
 if not module or type(module.MinimumLeads)~="function" then return nil end
 local ok,leads=pcall(module.MinimumLeads,module,key,skill)
 local lead=ok and type(leads)=="table" and leads[1] or nil
 if not lead then return nil end
 local materialRows={}
 for _,m in ipairs(lead.reagentsPerCraft or {}) do
  materialRows[#materialRows+1]={itemID=m.itemID,perCraft=m.perCraft,
   bagsKnown=false,missing=nil,readOnly=true}
 end
 local review=module:Review(key,{recipeID=lead.recipeID,recipe=lead.recipe,
  materials=materialRows,learned=nil,learnedSource="UNKNOWN"})
 return {contract=S.contract,profession=key,kind="verify",actionKind="reference",
  skill=skill,recipeID=lead.recipeID,recipe=lead.recipe,
  nextAction="Verify learning and current difficulty of "..lead.recipe..
   " before planning any manual craft.",
  materials=materialRows,source229MinimumFallback=true,
  exactMinimumLead229=lead,sourceReceipt229=review,
  navigationStatus="LOCATION_UNVERIFIED",readOnly=true,
  nativeDispatchAllowed=false,executionEligible=false,
  skillGainGuaranteed=false,expectedCraftsQualified=false}
end
-- P0-232 First Aid: explicit source -> learning -> one-craft reagent review.
-- It never claims a qualified native workflow or publishes research NPC coords.
local function firstAidArtisan232(key,skill,cap,options)
    if key~="FIRST_AID" or skill<225 or skill>=300 then return nil end
    local advisor=JLP:GetModule("ForeverFirstAidArtisan232")
    if not advisor or type(advisor.AtSkill)~="function" then return nil end
    local args={currentFaction=options.currentFaction,inventory=options.inventory,
        learnedRecipes=options.learnedRecipes,maxSkill=cap}
    local ok,result=pcall(advisor.AtSkill,advisor,skill,args)
    return ok and type(result)=="table" and result or nil
end
local function artisanFallback232(key,skill,cap,options)
    local r=firstAidArtisan232(key,skill,cap,options)
    if not r then return nil end
    local output={contract=S.contract,profession=key,kind="verify",actionKind="verify",
        skill=skill,recipeID=r.recipeID,recipe=r.recipe,
        nextAction=r.nextAction,action=r.nextAction,materials=r.perCraftMaterials,
        sourceFirstAidArtisan232=r,sourceFirstAidArtisanFallback232=true,
        navigationStatus="LOCATION_UNVERIFIED",learned=r.learned,
        learnedSource=r.learnedSource,knownInventory=r.bagsKnown,
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
        sourceStatus="FOREVER_FIRST_AID_SOURCE_BAND_REVIEW_ONLY"}
    local nav=JLP:GetModule("CurrentStepTravelBridge")
    if nav and type(nav.Attach)=="function" then nav:Attach(key,output) end
    return output
end
-- P0-233: a documented Forever/DB source window may provide a concrete
-- MANUAL VERIFY task when the normal current route has no qualified choice.
-- Never replace a valid Planner candidate or publish a native/action receipt.
local function primaryFallback233(key,skill,options)
    local module=JLP:GetModule("ForeverPrimarySourceWindows233")
    if not module then return nil end
    local ok,proof=pcall(module.AtSkill,module,key,skill,options)
    if not ok or type(proof)~="table" then return nil end
    local chosen=nil
    local weight={ORANGE_REFERENCE=3,YELLOW_REFERENCE=2,GREEN_REFERENCE=1}
    for _,r in ipairs(proof.recipes or {}) do
        if r.eligibleReferenceCandidate then
            local score=(r.learned==true and 20 or r.learned==nil and 10 or 0) +
                (weight[r.referenceDifficulty] or 0)
            local chosenScore=chosen and ((chosen.learned==true and 20 or
                chosen.learned==nil and 10 or 0) +
                (weight[chosen.referenceDifficulty] or 0)) or -1
            if score>chosenScore then chosen=r end
        end
    end
    if not chosen then return nil end
    local wording=chosen.nextRequiredAction=="VERIFY_LEARNED_STATE" and
        "Check whether this recipe is learned in your profession panel." or
        chosen.nextRequiredAction=="VERIFY_LEARNING_SOURCE" and
        "Verify the exact trainer/pattern source before attempting it." or
        chosen.nextRequiredAction=="VERIFY_BAG_COUNTS" and
        "Read your current bag quantities before planning materials." or
        chosen.nextRequiredAction=="ACQUIRE_REAGENTS_MANUALLY" and
        "Review the known shortage and obtain materials manually." or
        "Verify the live recipe difficulty and manually review one craft."
    local out={contract=S.contract,kind="verify",actionKind="verify",profession=key,
        recipeID=chosen.recipeID,recipe=chosen.recipe,skill=skill,
        learned=chosen.learned,materials=chosen.reagentsPerCraft,
        nextAction=wording,action=wording,sourcePrimaryFallback233=true,
        sourcePrimaryWindows233=proof,sourceStatus=chosen.sourceStatus,
        navigationStatus="LOCATION_UNVERIFIED",readOnly=true,
        skillGainGuaranteed=false,expectedCraftsQualified=false,
        nativeDispatchAllowed=false,executionEligible=false}
    -- Existing teaching-item -> actor join only; this is never a waypoint.
    local source=JLP:GetModule("RecipeSourcePlanningBridge")
    if source and type(source.ForRecipe)=="function" then
        local ok,review=pcall(source.ForRecipe,source,key,chosen.recipeID,chosen.recipe)
        if ok and type(review)=="table" then out.sourceLearningReview233=review end
    end
    local travel=JLP:GetModule("CurrentStepTravelBridge")
    if travel and type(travel.Attach)=="function" then travel:Attach(key,out) end
    return out
end
-- P0-234: same published Current Step, attached read-only source facts only.
local function attachActionChain234(key,skill,options,step)
 if type(step)~="table" then return step end
 local m=JLP:GetModule("ProfessionSourceActionChain234")
 if m and type(m.AtSkill)=="function" then
  local ok,r=pcall(m.AtSkill,m,key,skill,options)
  if ok and type(r)=="table" then step.sourceActionEvidence234=r end
 end
 return step
end
function S:Recommend(key,profession,dataset,options)
    local prerequisite=prerequisiteCurrentStep(key)
    if prerequisite then return prerequisite,prerequisite.terminalReason end
    options=type(options)=="table" and options or {}
    local tailoringRankAdvice
    local reg=JLP:GetModule("ProfessionRegistry")
    if not (reg and reg.Get and reg:Get(key)) then return nil,"UNSUPPORTED_PROFESSION" end
    if type(profession)~="table" then return nil,"PROFESSION_NOT_LEARNED" end
    local skill=number(profession.skill)
    local cap=number(profession.maxSkill)
    if not skill then return nil,"SKILL_UNKNOWN" end
    if key=="COOKING" and dataset and dataset.progression then
        local secondary=JLP:GetModule("SecondaryLevelingPlanner")
        local rank=secondary and secondary:GetOperationalRankStep(key,profession)
        if rank then rank.alchemyRank=true;local nav=JLP:GetModule("CurrentStepTravelBridge");if nav then nav:Attach(key,rank)end;return rank,nil end
    end
    if key=="FIRST_AID" and dataset and dataset.progression then
        local aid=JLP:GetModule("ForeverFirstAidArtisan232")
        local rank=aid and aid:GetOperationalRankStep(profession)
        if rank then rank.alchemyRank=true;local nav=JLP:GetModule("CurrentStepTravelBridge");if nav then nav:Attach(key,rank)end;return rank,nil end
    end
    if key=="BLACKSMITHING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local rank=facts and facts:GetBlacksmithingRankStep(profession)
        if rank then rank.alchemyRank=true;local nav=JLP:GetModule("CurrentStepTravelBridge");if nav then nav:Attach(key,rank)end;return rank,nil end
        if skill<300 and facts and #facts:GetBlacksmithingCandidates(skill,false)==0 then
            return {kind="verify",profession=key,skill=skill,cap=cap,blacksmithingGap=true,
                status="BLOCKED_QUALIFIED_RECIPE_OR_ACQUISITION_GAP",
                nextAction="Verify a current learned, non-gray Blacksmithing recipe and its exact minimum/source at skill "..skill..
                    ". No qualified progression candidate is available. Ebon Shiv requires255; Huge Thorium Battleaxe plans require280. Magnus access is not assumed.",
                readOnly=true,nativeDispatchAllowed=false,executionEligible=false},nil
        end
    end
    if key=="LEATHERWORKING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local rank=facts and facts:GetLeatherworkingRankStep(profession)
        if rank then rank.alchemyRank=true;local nav=JLP:GetModule("CurrentStepTravelBridge");if nav then nav:Attach(key,rank)end;return rank,nil end
        if skill<300 and facts and #facts:GetLeatherworkingCandidates(skill,false)==0 then
            return {kind="verify",profession=key,skill=skill,cap=cap,leatherworkingGap=true,status="BLOCKED_QUALIFIED_RECIPE_OR_ACCESS_GAP",
              nextAction="Verify a qualified learned non-gray Leatherworking recipe and its learning/access prerequisites at skill "..skill..". No specialization is assumed.",readOnly=true,nativeDispatchAllowed=false},nil
        end
    end
    if key=="ENGINEERING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local rank=facts and facts:GetEngineeringRankStep(profession)
        if rank then rank.alchemyRank=true;local nav=JLP:GetModule("CurrentStepTravelBridge");if nav then nav:Attach(key,rank)end;return rank,nil end
        if skill<300 and facts and #facts:GetEngineeringCandidates(skill,false)==0 then
            return {kind="verify",profession=key,skill=skill,cap=cap,engineeringGap=true,status="BLOCKED_QUALIFIED_RECIPE_OR_ACCESS_GAP",
              nextAction="Verify a qualified learned non-gray Engineering recipe and its learning/access prerequisites at skill "..skill..". Specialization is never selected automatically.",readOnly=true,nativeDispatchAllowed=false},nil
        end
    end
    if key=="ALCHEMY" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local rank=facts and facts.GetAlchemyRankStep and facts:GetAlchemyRankStep(profession)
        if rank then rank.alchemyRank=true;local nav=JLP:GetModule("CurrentStepTravelBridge");if nav then nav:Attach(key,rank)end;return rank,nil end
    end
    if key=="ENCHANTING" and dataset and dataset.progression then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local rank=facts and facts.GetEnchantingRankStep and facts:GetEnchantingRankStep(profession)
        if rank then
            rank.enchantingRank=true
            local nav=JLP:GetModule("CurrentStepTravelBridge");if nav then nav:Attach(key,rank)end
            return rank,nil
        end
    end
    if key=="TAILORING" then
        local q=JLP:GetModule("TailoringRecipeQualification")
        local rank,advice
        if q and q.GetRankStep then rank,advice=q:GetRankStep(profession,dataset) end
        tailoringRankAdvice=advice
        if rank then
            rank.tailoringRank=true
            rank.nextAction=rank.p1NextAction or "Train Journeyman Tailoring manually, then observe cap 150 before resuming progression."
            local nav=JLP:GetModule("CurrentStepTravelBridge")
            if rank.kind=="train" and nav and nav.Attach then nav:Attach(key,rank) end
            return rank,nil
        end
    end
    if skill>=300 then return {kind="complete",skill=skill,readOnly=true,nativeDispatchAllowed=false},nil end
    if cap and cap>0 and skill>=cap and cap<300 then
        -- P0-229: Fishing 225->300 is a quest, not a trainer rank.
        -- Public coordinates remain research-only, never a canonical waypoint.
        if key=="FISHING" and skill>=225 then
            local secondary=JLP.data and JLP.data.foreverSecondaryLeveling
            local quest=secondary and secondary.fishing and secondary.fishing.artisanQuest
            return {contract=S.contract,kind="train",actionKind="verify",skill=skill,
              cap=cap,rank="Artisan",profession=key,
              action="Verify the Artisan Fishing quest Nat Pagle, Angler Extreme in Dustwallow Marsh (Fishing 225, character level 35); complete the four quest fish objectives manually.",
              fishingArtisanQuestReference229=quest,trainerReferenceOnly=true,
              navigationStatus="LOCATION_UNVERIFIED",coordinateAuthority=false,
              sourceStatus="QUEST_REFERENCE_NOT_CURRENT_COMPLETION",
              readOnly=true,nativeDispatchAllowed=false,executionEligible=false},nil
        end
        -- Cooking and First Aid Artisan 225->300 are quest-based too.
        -- These source facts are not proof of availability/completion or a
        -- canonical destination; never hand guide coordinates to JuztTom.
        if skill>=225 and (key=="COOKING" or key=="FIRST_AID") then
            local secondary=JLP.data and JLP.data.foreverSecondaryLeveling
            local data=secondary and secondary.professions and secondary.professions[key]
            local gate
            for _,r in ipairs(data and data.gates or {}) do
                if r.skill==225 and r.kind=="ARTISAN_QUEST" then gate=r;break end
            end
            local faction=options.currentFaction
            local restricted=gate and gate.faction and faction and
                faction~=gate.faction
            local displayGate=gate
            if restricted then displayGate=nil end
            return {contract=S.contract,kind="train",actionKind="verify",skill=skill,
                cap=cap,rank="Artisan",profession=key,
                action=gate and not restricted and
                    ("Verify the Artisan "..key.." quest "..gate.name..
                     " (level 35) with "..gate.npcName..
                     "; complete required objectives manually and recheck profession rank.") or
                    "Verify the faction-specific Artisan profession quest and current rank before progressing.",
                artisanQuestReference229=displayGate,
                factionRestrictedSource=restricted==true,
                sourceStatus="QUEST_REFERENCE_NOT_CURRENT_COMPLETION",
                navigationStatus="LOCATION_UNVERIFIED",coordinateAuthority=false,
                readOnly=true,nativeDispatchAllowed=false,executionEligible=false},nil
        end
        local rank=cap<=75 and "Journeyman" or cap<=150 and "Expert" or "Artisan"
        local source=JLP:GetModule("SourceResolver")
        local lead=source and source.GetBestTrainerForRank and
            source:GetBestTrainerForRank(key,rank) or nil
        local result={kind="train",skill=skill,cap=cap,rank=rank,
            trainerLead=lead,trainerReferenceOnly=true,
            action="Verify access and train the "..rank.." profession rank before progressing.",
            nativeDispatchAllowed=false,readOnly=true}
        local rankEvidence=JLP:GetModule("PrimaryCraftingRankSources211")
        if rankEvidence then
            result.rankSourceContinuity=rankEvidence:AtSkill(key,skill,cap,options.currentFaction)
        end
        local nav=JLP:GetModule("CurrentStepTravelBridge")
        if nav and nav.Attach then nav:Attach(key,result) end
        return attachActionChain234(key,skill,options,attachStitchedCurrent(key,skill,result)),nil
    end
    if key=="TAILORING" and skill>=25 and skill<50 and (not cap or cap<=0) then
        return {contract=S.contract,profession=key,kind="verify",skill=skill,
            nextAction="Verify the current Tailoring rank and skill cap before progressing.",
            readOnly=true,nativeDispatchAllowed=false,executionEligible=false},nil
    end
    if gathering[key] then
        local result=gatheringStep(key,skill)
        local nav=JLP:GetModule("CurrentStepTravelBridge")
        if nav and nav.Attach then nav:Attach(key,result) end
        return attachActionChain234(key,skill,options,attachStitchedCurrent(key,skill,result)),nil
    end
    local rows=candidateIndex(key,dataset,skill)
    if #rows==0 then
        local firstAid=artisanFallback232(key,skill,cap,options)
        if firstAid then return attachActionChain234(key,skill,options,firstAid),nil end
        local primary=primaryFallback233(key,skill,options)
        if primary then return attachActionChain234(key,skill,options,primary),nil end
        local fallback=stitchedSourceFallback(key,skill)
        if fallback then return attachActionChain234(key,skill,options,fallback),nil end
        local lead=minimumSourceFallback(key,skill)
        if lead then return attachActionChain234(key,skill,options,lead),nil end
        local evidence=JLP:GetModule("ProfessionSourceActionChain234")
        local ok,review=false,nil
        if evidence and type(evidence.AtSkill)=="function" then
            ok,review=pcall(evidence.AtSkill,evidence,key,skill,options)
        end
        if ok and type(review)=="table" then
            return {contract=S.contract,kind="verify",actionKind="verify",skill=skill,
                profession=key,nextAction=review.instruction,sourceActionEvidence234=review,
                sourceGapFallback234=true,navigationStatus="LOCATION_UNVERIFIED",
                readOnly=true,nativeDispatchAllowed=false,executionEligible=false},nil
        end
        return nil,"RECIPE_CATALOGUE_UNAVAILABLE"
    end
    local learned,learnedSource,liveTiers=liveLearned(key,options.learnedRecipes,rows,skill)
    local strategy=options.strategy or (JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"
    local stockMemo,priceMemo={},{ }
    local winner,considered=nil,0
    local alternatives={}
    local evaluable={}
    for _,c in ipairs(rows) do
        local status=learned and learned[c.recipeID]
        if status==nil then
            local cache=JLP:GetModule("KnowledgeCache")
            if cache and type(cache.GetRecipeKnowledge)=="function" and
                cache:GetRecipeKnowledge(c.recipe,key)=="known" then status="CACHED_KNOWN" end
        end
        -- P0-220: Lua's `a and false or nil` ALWAYS collapses to nil. Keep
        -- an explicitly observed false as false so LEARN_RECIPE is visible
        -- and a cached unknown cannot masquerade as a known recipe state.
        local numericLearned=nil
        if status==true then numericLearned=true
        elseif status==false then numericLearned=false end
        local candidate=scoreCandidate(c,skill,numericLearned,stockMemo,priceMemo,strategy,learnedSource,key,liveTiers and liveTiers[c.recipeID])
        if candidate and status=="CACHED_KNOWN" then
            -- Positive saved learning can improve advisory selection, but is
            -- not a current-session proof or native permission.
            candidate.learnedRank=2
        end
        if candidate then
            evaluable[#evaluable+1]=c
            if status=="CACHED_KNOWN" then candidate.learnedSource="SAVED_ADVISORY" end
            considered=considered+1
            if better(candidate,winner,strategy) then winner=candidate end
            alternatives[#alternatives+1]=candidate
        end
    end
    if JLP.RegisterPlanningDependencies then JLP:RegisterPlanningDependencies(key,evaluable) end
    if not winner then
        local firstAid=artisanFallback232(key,skill,cap,options)
        if firstAid then return attachActionChain234(key,skill,options,firstAid),nil end
        local primary=primaryFallback233(key,skill,options)
        if primary then return attachActionChain234(key,skill,options,primary),nil end
        local fallback=stitchedSourceFallback(key,skill)
        if fallback then return attachActionChain234(key,skill,options,fallback),nil end
        local lead=minimumSourceFallback(key,skill)
        if lead then return attachActionChain234(key,skill,options,lead),nil end
        for _,sourceRow in ipairs(rows) do
            if sourceRow.sourceNameConflict then return nil,"SOURCE_RECIPE_NAME_PARITY_FAILED" end
        end
        local evidence=JLP:GetModule("ProfessionSourceActionChain234")
        local ok,review=false,nil
        if evidence and type(evidence.AtSkill)=="function" then
            ok,review=pcall(evidence.AtSkill,evidence,key,skill,options)
        end
        if ok and type(review)=="table" then
            return {contract=S.contract,kind="verify",actionKind="verify",skill=skill,
                profession=key,nextAction=review.instruction,sourceActionEvidence234=review,
                sourceGapFallback234=true,navigationStatus="LOCATION_UNVERIFIED",
                readOnly=true,nativeDispatchAllowed=false,executionEligible=false},nil
        end
        return nil,"NO_USABLE_RECIPE_REFERENCE"
    end
    table.sort(alternatives,function(a,b) return better(a,b,strategy) end)
    -- Separate bounded lookahead: no native authorization and no implicit AH requirement.
    -- It may recommend a different current source candidate, but only one actually
    -- learned in the current panel can replace the immediately visible recipe.
    local optimizer=JLP:GetModule("UniversalRouteOptimizer")
    local forecast=optimizer and optimizer.Forecast and optimizer:Forecast(key,skill,rows,learned,{
        strategy=strategy,maxSkill=cap,goalSkill=math.min(300,skill+20),
        inventory=options.inventory,prices=options.prices,
        accountCharacters=options.accountCharacters,accountAliases=options.accountAliases,
        currentCharacterKey=options.currentCharacterKey,currentRealm=options.currentRealm,
        currentFaction=options.currentFaction,
        existingAccountReservations=options.existingAccountReservations,
        accountProducerCandidates=options.accountProducerCandidates}) or nil
    if not winner.scenarioCrafts and forecast and forecast.route and forecast.route[1] then
        local wanted=forecast.route[1].recipeID
        for _,choice in ipairs(alternatives) do
            if choice.candidate.recipeID==wanted and choice.learned==true then
                winner=choice;break
            end
        end
    end
    local enchantingConsumer
    if key=="ENCHANTING" and winner.learned~=nil then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local prep=facts and facts.GetEnchantingToolPreparation and facts:GetEnchantingToolPreparation(winner.candidate,skill)
        if prep then
            local observed=facts:Observe(key,prep.recipeID)
            local replacement=scoreCandidate(prep,skill,observed.observed and observed.learned,stockMemo,priceMemo,strategy,learnedSource,key)
            if replacement then enchantingConsumer=winner.candidate;winner=replacement end
        end
    end
    if (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and winner.learned==true then
        local facts=JLP:GetModule("ProfessionPlanningFacts")
        local prep=facts and (key=="ENGINEERING" and facts:GetEngineeringPreparation(winner.candidate,skill,winner.alchemyPreparationChoices) or facts.GetAlchemyPreparation and facts:GetAlchemyPreparation(winner.candidate,skill,winner.alchemyPreparationChoices,key))
        if prep then
            local replacement=scoreCandidate(prep,skill,(facts:Observe(key,prep.recipeID).learned),stockMemo,priceMemo,strategy,learnedSource,key)
            if replacement then winner=replacement end
        end
    end
    local progressionWinner=winner
    local consumer=winner.candidate
    -- Preparation is ONE manual craft, never an inventory/output credit.
    -- The selected finished recipe remains attached to the same plan decision.
    if (consumer.sourceQualificationContract=="tailoring-77-102-wool-v1" or (consumer.sourceQualificationContract=="tailoring-102-107-source-v1" or (consumer.sourceQualificationContract=="tailoring-107-125-source-v1" or (consumer.sourceQualificationContract=="tailoring-125-225-source-v1" or consumer.sourceQualificationContract=="tailoring-225-300-source-v1")))) and winner.learned==true then
        for _,mat in ipairs(consumer.materials)do
            local own=inventoryCount(mat.itemID,{})
            local inventory=JLP:GetModule("Inventory")
            local storage=inventory and inventory.GetOwned and inventory:GetOwned(mat.itemID)
            local retrieveKnownBank=(consumer.sourceQualificationContract=="tailoring-125-225-source-v1" or consumer.sourceQualificationContract=="tailoring-225-300-source-v1") and
                storage and storage.bankKnown==true and type(storage.bank)=="number" and storage.bank>0
            if not retrieveKnownBank and mat.craftedFrom and mat.craftedFrom.producerRecipeID and own.known and own.quantity<mat.quantity and skill>=(mat.craftedFrom.minimum or 75) then
                local preparation={recipeID=2964,recipe="Bolt of Woolen Cloth",requiredSkill=75,
                    requiredSkillAuthority="WOWHEAD_FOREVER",route=true,routeSkillMin=75,routeSkillTarget=150,
                    skillMin=75,skillTarget=150,rawYellow=75,rawGreen=77,rawGrey=85,
                    preparationOnly=true,sourceBuild=70532,materials={{itemID=2592,name="Wool Cloth",quantity=3,source="auction"}}}
                if mat.itemID~=2997 then
                    preparation.recipeID=mat.craftedFrom.producerRecipeID
                    preparation.recipe=mat.name or (mat.itemID==4305 and "Bolt of Silk Cloth" or "Bolt of Mageweave")
                    preparation.requiredSkill=mat.craftedFrom.minimum;preparation.routeSkillMin=preparation.requiredSkill
                    preparation.materials={{itemID=mat.craftedFrom.itemID,name=mat.craftedFrom.name,quantity=mat.craftedFrom.quantity,source="auction"}}
                end
                local obs=mat.craftedFrom.observed
                local known=nil
                if obs and obs.observed then known=obs.learned end
                local nextStep=scoreCandidate(preparation,skill,known,{},priceMemo,strategy,learnedSource,key,nil)
                if nextStep then winner=nextStep;break end
            end
        end
    end
    local c=winner.candidate
    -- Item labels come from the existing versioned item metadata, not a
    -- guessed localized item name or an AH scan requirement.
    local metadata=JLP:GetModule("Build70450ItemMetadata")
    for _,m in ipairs(winner.materials) do
        if not m.name and metadata and type(metadata.GetItem)=="function" then
            local item=metadata:GetItem(m.itemID,70450)
            if type(item)=="table" and type(item.name)=="string" and item.name~="" then
                m.name=item.name
            end
        end
        if not m.name then m.name="Item "..tostring(m.itemID) end
    end
    -- Current panel facts are optional: a missing API/build never blocks guidance.
    -- They provide categorical difficulty and output ranges, not speculative
    -- yellow/green probabilities, cast receipts or native action permissions.
    local factsModule=JLP:GetModule("ProfessionPlanningFacts")
    local facts=factsModule and factsModule.Observe and
        factsModule:Observe(key,c.recipeID) or nil
    local blockedByLiveDifficulty=not c.preparationOnly and facts and facts.observed and facts.skillup and
        (facts.skillup.tier=="GRAY" or facts.skillup.canSkillUp==false)
    local observedUnlearned=facts and facts.observed and facts.learned==false
    -- A fresh, stable client observation outranks route/cache/fixture advice.
    -- Use the same effective state for UI text, chain stage and travel handoff;
    -- previously the UI could say CRAFT while the chain said LEARN.
    local effectiveLearned=winner.learned
    if facts and facts.observed and type(facts.learned)=="boolean" then
        effectiveLearned=facts.learned
    end
    local action
    if blockedByLiveDifficulty then
        action="This recipe cannot currently increase skill; select an alternative recipe or verify a new training rank."
    elseif observedUnlearned then
        action="Learn "..c.recipe.." before attempting to craft it; verify its exact trainer/pattern source."
    elseif effectiveLearned==false then
        action="Learn "..c.recipe.." (recipe "..c.recipeID..") before crafting; check its trainer, pattern or vendor source."
    elseif effectiveLearned~=true then
        action="Check whether "..c.recipe.." (recipe "..c.recipeID..") is learned; open the profession panel if needed."
    elseif winner.bagReady then
        action="Craft ONE "..c.recipe.." and re-evaluate the next Current Step."
    else
        action="Prepare materials for ONE "..c.recipe.."; re-evaluate after acquiring or transferring reagents."
    end
    if c.scenarioCrafts then
        action=action.." Plan toward skill "..c.skillTarget..": "..c.scenarioCrafts..
            " crafts in the orange 100% / yellow 60% / green 25% planning scenario; actual skill-ups must be observed."
    end
    if tailoringRankAdvice then
        action=action.." "..tostring(tailoringRankAdvice.rank).." requires skill "..tostring(tailoringRankAdvice.requiredSkill)..
            " / character level "..tostring(tailoringRankAdvice.minCharacterLevel).."; train during a qualified local visit before cap "..tostring(tailoringRankAdvice.currentCap).."."

    end
    local sources=JLP:GetModule("SourceResolver")
    local access=sources and sources.GetRecipeSource and
        (sources:GetRecipeSource(key,c.recipeID) or sources:GetRecipeSource(key,c.recipe)) or nil
    local output={contract=S.contract,kind="craft",profession=key,skill=skill,
        recipe=c.recipe,recipeID=c.recipeID,learned=effectiveLearned,
        recipeMinimumEvidence=winner.minimumSkillFact,recipeMinimumStatus=winner.minimumSkillStatus,
        db2Evidence=c.db2Evidence,patternReference=c.patternReference,
        recipeItemReference=c.recipeItemReference,learningSourceStatus=c.learningSourceStatus,
        requiredSkill=c.requiredSkill,
        castTimeAuthority=c.castTimeAuthority,castMinimumSeconds=c.castMinimumSeconds,
        learnedSource=winner.learnedSource or learnedSource,
        nextAction=action,materials=winner.materials,sourceBuild=c.sourceBuild,
        expectedOutputQuantity=c.expectedOutputQuantity,outputYieldStatus=c.outputYieldStatus,
        outputQuantityConflict=c.outputQuantityConflict,outputQuantityAuthority=c.outputQuantityAuthority,
        outputQuantityReference=c.outputQuantityReference,
        estimatedMissingCost=winner.cost,auctionPriceAvailable=winner.priceComplete,
        auctionCostAdvisory=true,knownInventory=winner.unknown==0,
        missingQuantity=winner.missing,bagReady=winner.bagReady,
        sourceRoute=c.route==true,sourceStatus="SOURCE_REFERENCE_ONLY",
        recipeAcquisitionLead=access,recipeAcquisitionAdvisory=true,
        recipeAcquisitionVerified=false,
        wowheadLookupURL="https://www.wowhead.com/forever/spell="..tostring(c.recipeID),
        consideredCandidates=considered,strategy=strategy,
        expectedCraftsQualified=false,skillGainGuaranteed=false,
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
        skillTarget=math.min(300,skill+1),remainingCrafts=integer(c.scenarioCrafts) or 1}
    if c.patternReference and effectiveLearned~=true then
        output.nextAction=output.nextAction.." Pattern "..c.patternReference.itemID..
            " has a sourced Tailoring item-use requirement of 75; verify possession and learning eligibility."
    end
    if c.preparationOnly then
        output.preparingIntermediate=true;output.progressionRecipeID=consumer.recipeID
        output.progressionRecipe=consumer.recipe
        output.nextAction=output.nextAction.." Intermediate for "..consumer.recipe.."; observe inventory and skill before replanning."
    end
    if (consumer.sourceQualificationContract=="tailoring-77-102-wool-v1" or (consumer.sourceQualificationContract=="tailoring-102-107-source-v1" or (consumer.sourceQualificationContract=="tailoring-107-125-source-v1" or (consumer.sourceQualificationContract=="tailoring-125-225-source-v1" or consumer.sourceQualificationContract=="tailoring-225-300-source-v1")))) then
        output.woolScenario=consumer.woolScenario
        output.strategyEvidence={totalTimeStatus="UNKNOWN_ACQUISITION_AND_TRAVEL_TIME",
            netCostStatus="UNKNOWN_OUTPUT_REALIZATION",craftSeconds=progressionWinner.craftSeconds,
            materialOutlay=progressionWinner.scenarioCost,materialOutlayKnown=progressionWinner.scenarioQuoted,
            castTimeAuthority=consumer.castTimeAuthority,
            selection="QUALIFIED_SCENARIO_FALLBACK_NOT_PROVEN_GLOBAL_OPTIMUM"}
    end
    if facts and facts.observed and type(facts.learned)=="boolean" then
        output.learnedSource="CURRENT_PANEL_STABLE"
    end
    if c.scenarioCrafts then
        output.progressionScenario={fromSkill=skill,toSkill=c.skillTarget,crafts=c.scenarioCrafts,
            estimated=true,source=c.craftCountAuthority,
            missingMaterialCost=winner.scenarioCost,priceComplete=winner.scenarioQuoted,
            comparisonStatus=winner.scenarioQuoted and "QUALIFIED_MATERIAL_COST_SCENARIO" or "PRICE_UNKNOWN_CAST_SCENARIO_FALLBACK",
            timeStatus="UNKNOWN_TOTAL_TIME",outputCreditStatus="UNKNOWN_CONFLICTING_YIELD"}
    end
    output.rankOpportunity=tailoringRankAdvice
    output.liveRecipeFacts=facts
    output.sourceFirstAidArtisan232=firstAidArtisan232(key,skill,cap,options)
    local six=JLP:GetModule("ForeverPrimarySourceWindows233")
    if six and type(six.AtSkill)=="function" then
        local ok,review=pcall(six.AtSkill,six,key,skill,options)
        if ok and type(review)=="table" then output.sourcePrimaryWindows233=review end
    end
    -- Field-specific public recipe-source reconciliation. This is advisory
    -- context only; no Current Step field confers native or travel authority.
    local primary=JLP.data and JLP.data.foreverPrimaryRecipeParity212
    if primary then
        local conflict=primary.conflicts and primary.conflicts[c.recipeID]
        local match=primary.rows and primary.rows[c.recipeID]
        if conflict and conflict.professionKey==key then
            output.primaryRecipeSourceStatus="SOURCE_NAME_CONFLICT"
            output.primaryRecipeSourceURL=conflict.source
        elseif match and match.professionKey==key then
            local graph=JLP:GetModule("CrossProfessionDependencyPlanner")
            local verified=graph and graph.Resolve and graph:Resolve(key,c.recipeID)
            if verified and verified.primarySourceParity then
                output.primaryRecipeSourceStatus="EXACT_EXTERNAL_DB_PARITY_READ_ONLY"
                output.primaryRecipeSourceURL=verified.primarySourceURL
                output.sourceOutputQuantity=verified.outputPerCraft
                output.sourceOutputItemID=verified.outputItemID
                output.sourceRecipeSkillMinimum=verified.primarySourceSkillMinimum
                output.sourceTrainerNameReferences=verified.primarySourceTrainerNames
                output.sourceTrainerIDsVerified=false
                output.sourceTrainerStockVerified=false
                output.sourceRecipeSkillUpGuaranteed=false
            else
                output.primaryRecipeSourceStatus="PARITY_INCOMPLETE_VERIFY_MANUALLY"
            end
        end
    end
    local odds=JLP:GetModule("SkillUpProbabilityPlanner")
    if odds and odds.ForSource then
        local observedTier=facts and facts.observed and facts.skillup and facts.skillup.tier or nil
        if (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and observedTier=="UNKNOWN" then observedTier=nil end
        -- Existing RecipeTelemetry is OPTIONAL; fallback works offline without a build receipt.
        output.skillUpTelemetry=odds:GetOptionalTelemetry(key,c.recipeID,c.recipe)
        output.skillUpPlanning=odds:ForRecipe(key,c.recipeID,c.recipe,skill,
            c.scenarioCrafts and c.requiredSkill or
                (winner.minimumSkillFact and winner.minimumSkillFact.minimum) or c.requiredSkill or c.routeSkillMin,
            c.rawYellow,c.rawGrey,observedTier,options,output.skillUpTelemetry or false)
        if c.rawGreen and not observedTier then
            local inferred=(key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and c.sourceFact and c.sourceFact.greenStatus=="CATALOG_MIDPOINT_NOT_INDEPENDENT_CLIENT_FIELD"
            output.skillUpPlanning.tierSource=inferred and "INFERRED_MIDPOINT_PLANNING_SCENARIO" or "QUALIFIED_FOREVER_THRESHOLD_REFERENCE"
            output.skillUpPlanning.sourceTransitionDocumented=not inferred
            output.skillUpPlanning.transitionSourceURL=c.evidence
        end
    end
    output.currentRecipeDifficulty=facts and facts.observed and facts.skillup or nil
    output.currentRecipeOutput=facts and facts.observed and facts.output or nil
    output.currentRecipeOutputStatus=facts and facts.observed and facts.outputStatus or "NOT_OBSERVED"
    output.manualCraftBlockedByLiveDifficulty=blockedByLiveDifficulty and true or false
    output.manualCraftBlockedByLiveLearning=observedUnlearned and true or false
    local lead,leadStatus=nil,"SOURCE_RESOLVER_UNAVAILABLE"
    if factsModule and type(factsModule.AccessLead)=="function" then
        lead,leadStatus=factsModule:AccessLead(key,c.recipeID,c.recipeSource,c.recipe)
    end
    local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
    local exact=bridge and type(bridge.ForRecipe)=="function" and
        bridge:ForRecipe(key,c.recipeID,c.recipe) or nil
    output.recipeSourcePlanning=exact
    if output.learned==false and exact then
        output.nextAction="Learn "..c.recipe.." (recipe "..c.recipeID..") before crafting. "..
            (bridge:Describe(exact))
    end
    output.sourceLead=lead
    output.sourceLeadStatus=leadStatus
    output.workstation=factsModule and factsModule.Workstation and
        factsModule:Workstation(c.station or c.workstation,c.sourceSpellFocusReference) or nil
    local rankEvidence=JLP:GetModule("PrimaryCraftingRankSources211")
    if rankEvidence then
        output.rankSourceContinuity=rankEvidence:AtSkill(key,skill,cap,options.currentFaction)
    end
    output.routeForecast=forecast
    output.forecastMaterials=forecast and forecast.materialNeeds or nil
    output.accountMaterialReservations=forecast and forecast.materialAcquisitionPlan
        and forecast.materialAcquisitionPlan.accountMaterialReservations or nil
    output.crossProfessionDependencies=output.accountMaterialReservations
        and output.accountMaterialReservations.dependencyBlueprint or nil
    output.forecastSkillGoal=forecast and forecast.skillGoal or nil
    output.optimizationConfidence=forecast and (forecast.auctionPricesComplete and
        "PRICED_SCENARIO_NOT_LIVE_VERIFIED" or "UNPRICED_SCENARIO") or "NO_FORECAST"
    output.alternatives={}
    for i=2,math.min(4,#alternatives) do
        local alt=alternatives[i]
        output.alternatives[#output.alternatives+1]={recipeID=alt.candidate.recipeID,
            recipe=alt.candidate.recipe,learned=alt.learned,
            bagReady=alt.bagReady,estimatedMissingCost=alt.cost}
    end
    if key=="TAILORING" and skill>=107 and skill<((JLP.data and JLP.data.tailoring and JLP.data.tailoring.woolProgression or {}).artisanTarget or (JLP.data and JLP.data.tailoring and JLP.data.tailoring.woolProgression or {}).expertTarget or 125) then
        output.progressionSourceContract=consumer.sourceQualificationContract
        if output.learned==true and not output.knownInventory then
            output.requiredNextAction="verify"
            output.nextAction="Inspect current material inventory for "..c.recipe.." before choosing a craft or acquisition action."
        elseif output.learned==true and not output.bagReady then
            output.requiredNextAction="acquire"
            output.nextAction="Acquire the missing materials for "..c.recipe.."; observe inventory before the next manual craft."
        elseif output.learned==true then output.requiredNextAction="manual-craft" end
    end
    if (consumer.sourceQualificationContract=="tailoring-125-225-source-v1" or consumer.sourceQualificationContract=="tailoring-225-300-source-v1") and not c.preparationOnly then
        if consumer.sourceSpellFocusReference then
            local qualification=JLP:GetModule("TailoringRecipeQualification")
            local access=qualification and qualification:RecipeAccess(consumer)
            local confirmed=access=="MET"
            output.recipeAccessStatus=access
            output.workstationStatus=confirmed and "CURRENT_PANEL_REQUIREMENTS_MET" or ("VERIFY_SPELL_FOCUS_"..tostring(consumer.sourceSpellFocusReference))
            if not confirmed then output.requiredNextAction="verify";output.nextAction="Verify "..tostring(consumer.sourceFocusLabel or "crafting station").." and any cooldown for "..c.recipe.." in the current Tailoring panel; no station position is qualified." end
        end
        if (consumer.outputQuantityConflict or consumer.outputYieldStatus=="UNKNOWN") and not (facts and facts.observed and facts.output and facts.output.fixed and facts.output.itemID==c.outputItemID) then
            output.requiredNextAction="verify";output.nextAction="Verify the current output of "..c.recipe.."; its fixed yield is unknown or conflicting. No fixed output credit."
        end
    end
    if (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and c.qualifiedProgression and factsModule and factsModule.AnnotateAlchemy then
        factsModule:AnnotateAlchemy(output,c,key)
    end
    if key=="ENCHANTING" and c.qualifiedProgression and factsModule and factsModule.AnnotateEnchanting then
        factsModule:AnnotateEnchanting(output,c)
        if c.toolPreparation then output.preparingTool=true;output.remainingCrafts=1;output.skillTarget=skill
            output.progressionRecipeID=enchantingConsumer and enchantingConsumer.recipeID end
    end
    local pattern=effectiveLearned~=true and bridge and bridge.GetPatternAcquisition and
        bridge:GetPatternAcquisition(key,c.recipeID,skill) or nil
    if pattern then
        output.patternAcquisition=pattern
        local actor=pattern.primary
        local target=actor and (actor.npcName.." in "..actor.zone) or "the documented source"
        local prefix=(key=="ENCHANTING" and "Formula item " or (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and "Recipe item " or "Pattern item ")..pattern.itemID.." for "..c.recipe.." ("..(key=="ENCHANTING" and "Enchanting " or key=="ENGINEERING" and "Engineering " or key=="LEATHERWORKING" and "Leatherworking " or key=="BLACKSMITHING" and "Blacksmithing " or key=="ALCHEMY" and "Alchemy " or "Tailoring ")..pattern.minimum.."). "
        if effectiveLearned==nil then
            output.requiredNextAction="verify"
            output.nextAction=prefix.."Inspect the current profession panel to establish learned-state before acquiring another recipe item."
        elseif pattern.status=="LEARN_ITEM_MANUALLY" then
            output.requiredNextAction="learn-recipe"
            output.nextAction=prefix.."Use the observed bag item manually; wait for a separate learned-state observation before crafting."
        elseif pattern.status=="RETRIEVE_PATTERN_FROM_BANK" then
            output.requiredNextAction="acquire-recipe"
            output.nextAction=prefix.."Withdraw the observed pattern from your bank manually; observe it in bags before learning. Do not buy a duplicate."
        elseif pattern.vendorAccess and pattern.status=="RETRIEVE_ACCESS_ITEM_FROM_BANK" then
            output.requiredNextAction="acquire-recipe"
            output.nextAction=prefix.."Withdraw the observed Spectral Essence (13544) from your bank manually; observe bags and equipment separately. Do not buy another pattern or infer quest completion."
        elseif pattern.vendorAccess and pattern.status=="EQUIP_ACCESS_ITEM_MANUALLY" then
            output.requiredNextAction="verify"
            output.nextAction=prefix.."Bring the observed Spectral Essence (13544) to Caer Darrow and equip it manually at Magnus's house. Observe equipment, then the exact current merchant offer separately."
        elseif pattern.vendorAccess and pattern.status=="VENDOR_ACCESS_QUEST_MANUALLY" then
            output.requiredNextAction="verify"
            local a=pattern.vendorAccess
            output.nextAction=prefix..(a.status=="QUEST_RETURN"and "Return to Eva Sarkhoff for "or "Manually inspect/accept at Eva Sarkhoff: ")..tostring(a.questName)..". Quest guidance is an external beta reference; only current quest flags/offer and the later reward bag receipt establish progress."
        elseif pattern.vendorAccess and (pattern.status=="VERIFY_DUNGEON_QUEST_OBJECTIVES"or pattern.status=="VERIFY_VENDOR_ACCESS_PREREQUISITE") then
            output.requiredNextAction="verify"
            local a=pattern.vendorAccess
            output.nextAction=prefix.."Verify Magnus access: "..a.status..". "..(a.questName or "Spectral Essence13544 bags/bank/equipped state")..". Dungeon objectives, party/key access and any replacement reward require separate evidence; no internal route or completed unlock is invented."
        elseif pattern.status=="VERIFY_PURCHASE_REQUIREMENTS"then
            output.requiredNextAction="verify"
            output.nextAction=prefix.."Verify current purchase requirements: "..tostring(pattern.purchaseAdvice and pattern.purchaseAdvice.status)..". No price, currency, reserved stock or successful purchase is assumed."
        elseif pattern.status=="ACQUIRE_ITEM_MANUALLY" then
            output.requiredNextAction="acquire-recipe"
            output.nextAction=prefix.."Manually buy the currently listed pattern from "..target.."; observe the bag item, then learn it separately. Limited stock is not reserved."
        elseif pattern.status=="VERIFY_DROP_OR_TRADE_ACCESS" then
            output.requiredNextAction="verify"
            output.nextAction=prefix.."Reference lists a drop from "..target.."; verify acquisition or an actual tradeable pattern offer. No loot chance, guaranteed drop, price or farming waypoint is qualified. Observe the bag item and learning separately."
        elseif pattern.status=="SOURCE_UNAVAILABLE" then
            output.requiredNextAction="verify"
            output.nextAction=prefix.."The inspected vendor cannot currently supply this item. Recheck later or select another qualified recipe/source; no restock time is assumed."
        else
            output.requiredNextAction="verify"
            output.nextAction=prefix.."Verify current stock and access at "..target..". No purchase or learning has been observed."
            if actor and actor.accessNote then output.nextAction=output.nextAction.." "..actor.accessNote end
        end
        if pattern.patternPossession=="UNKNOWN" then
            output.requiredNextAction="verify"
            output.nextAction=prefix.."Inspect bags and bank for this pattern before buying another copy; inventory is UNKNOWN. Source candidate: "..target.."."
        end
        if pattern.status~="RETRIEVE_PATTERN_FROM_BANK" then
            output.nextAction=output.nextAction..(actor and actor.navigationQualified and " A qualified source location is available through Current Step; geography is not access, stock or physical transport proof."or " Source coordinates/transport remain unqualified; no automatic waypoint is created.")
        end
        if key=="ALCHEMY" and pattern.merchantFavorRequired then
            output.nextAction=output.nextAction.." Reference requires "..tostring(pattern.reputationReference or "qualified reputation")..
                " and "..tostring(pattern.merchantFavorRequired).." Merchant's Favor. Verify actual eligibility and currency; neither is assumed owned."
        end
    end
    if key=="ENCHANTING" or key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING" then output.manualCraftBlockedByRecipePrerequisite=output.requiredNextAction=="verify"end
    if c.recipeItemReference and effectiveLearned~=true and not pattern then
        output.nextAction=output.nextAction.." Verify Pattern item "..tostring(c.recipeItemReference.itemID)..
            "; documented item requirement "..tostring(c.recipeItemReference.requiredSkill)..
            ". Acquisition source: "..tostring(c.learningSourceStatus)..". No trainer/vendor access or waypoint is inferred."
    end
    self:FormatCraftStep(output)
    local travel=JLP:GetModule("CurrentStepTravelBridge")
    local acquisition=JLP:GetModule("AcquisitionPlanner")
    if acquisition and acquisition.ApplyServiceToStep then acquisition:ApplyServiceToStep(key,output) end
    if travel and travel.Attach then travel:Attach(key,output) end
    local chain=JLP:GetModule("ProfessionFieldChain229")
    if chain and type(chain.Review)=="function" then
        local ok,receipt=pcall(chain.Review,chain,key,output,options.currentFaction)
        if ok and type(receipt)=="table" then
            output.sourceFieldChain229=receipt
            if receipt.sourceStatus=="CURRENT_STEP_REAGENT_CONFLICT" or
               receipt.sourceStatus=="INDEPENDENT_SOURCE_REAGENT_CONFLICT" then
                output.manualCraftBlockedBySourceConflict=true
                output.nextAction="Resolve conflicting source reagent quantities for "..
                   c.recipe.." before planning a manual craft."
            end
        end
    end
    if c.outputQuantityConflict and effectiveLearned==true then
        output.nextAction=output.nextAction.." Output per cast needs verification: individual Forever reference versus catalog/historical schematic; no fixed output credit."
    end
    local yields=JLP:GetModule("RecipeOutputEvidence")
    local reference=yields and yields.GetReference and yields:GetReference(c.recipe,c.recipeID)
    if reference and reference.productFixedOutput==true then
        local resolved=yields:Resolve(c.recipe,c.recipeID)
        output.expectedOutputQuantity=resolved.expectedOutputQuantity
        output.outputContractEvidence=resolved
        if resolved.productContractConflict then
            output.manualCraftBlockedByOutputConflict=true
            output.nextAction="Verify conflicting output for "..c.recipe..
                ": product contract expects one item per successful craft; observed evidence requires review."
        end
    end
    if key=="FIRST_AID" and c.qualifiedProgression then
        local aid=JLP:GetModule("ForeverFirstAidArtisan232")
        if aid then aid:AnnotateOperational(output,c,profession)end
    end
    if key=="COOKING" and c.qualifiedProgression then
        local secondary=JLP:GetModule("SecondaryLevelingPlanner")
        if secondary then secondary:AnnotateOperational(key,output,c,profession)end
        if travel then travel:Attach(key,output)end
    end
    return attachActionChain234(key,skill,options,attachStitchedCurrent(key,skill,output)),nil
end
-- Explicit on-demand route preview. No AH scan or evidence receipt required.
-- Read-only full 1-300 source forecast reports gaps and rank gates rather
-- than inventing missing recipe access, skill points or purchases.
function S:PlanTo300(key,profession,dataset,options)
 local prerequisite=prerequisiteCurrentStep(key)
 if prerequisite then return prerequisite,prerequisite.terminalReason end
 options=type(options)=="table" and options or {}
 if type(profession)~="table" or not number(profession.skill) then
  return nil,"PROFESSION_STATUS_UNKNOWN"
 end
 local reg=JLP:GetModule("ProfessionRegistry")
 if not (reg and reg.Get and reg:Get(key)) then return nil,"UNSUPPORTED_PROFESSION" end
 local skill=number(profession.skill)
 if gathering[key] then
  -- Profession-type progression: gathering/fishing cannot be routed through
  -- CraftRecipe. Present ALL future skill bands as independently verifiable
  -- references, preserving the unknown node spawn, catch odds and rank gates.
  -- Each action is manual: the bands are milestones, not certified routes.
  local bands={};local lower=skill
  local breakpoints=key=="MINING" and {65,75,125,140,155,175,185,225,230,245,275,300}
     or {75,150,225,300}
  for _,capstone in ipairs(breakpoints) do
   if capstone>lower then
    local reference=gatheringStep(key,lower)
    bands[#bands+1]={skillFrom=lower,skillTo=capstone,
     kind="GATHER_REFERENCE",instruction=reference.action,
     resourceReference=reference.resourceReference,zoneReference=reference.zone,
     sourceProgression=reference.sourceProgression,
     rankTrainingRequired="VERIFY_ACTUAL_SKILL_CAP",
     sourceCoverage=reference.sourceCoverage or "REFERENCE_ONLY",nodeConfirmed=false,
     skillGainGuaranteed=false,navigationQualified=false,
     nativeDispatchAllowed=false,readOnly=true}
    lower=capstone
   end
  end
  local auditModule=JLP:GetModule("ProfessionProgressionCoverage228")
  local audit=auditModule and auditModule:Audit(key,math.max(1,math.min(299,skill)),300) or nil
  local gatherPlan={progressionSourceCoverage228=audit,contract="JLP-GATHERING-300-FORECAST-V2",profession=key,
   skillStart=skill,skillGoal=300,readOnly=true,forecastOnly=true,
   nextStep=gatheringStep(key,skill),referenceSegments=bands,
   milestonesModel="UNVERIFIED_MANUAL_SKILL_BANDS",
   rankGateStatus="VERIFY_IN_CURRENT_CLIENT",
   sourceCoverage="REFERENCE_ONLY",routeUnqualified=true,
   reason="GATHERING_NODE_AND_SKILLUP_FREQUENCY_UNKNOWN",
   nativeDispatchAllowed=false,executionEligible=false}
  local evidence=JLP:GetModule("ProfessionSourceActionChain234")
  if evidence and type(evidence.Continuity)=="function" then
   local ok,r=pcall(evidence.Continuity,evidence,key,math.max(1,math.min(300,skill)),options)
   if ok and type(r)=="table" then gatherPlan.sourceActionContinuity234=r end
  end
  return gatherPlan,nil
 end
 local rows=candidateIndex(key,dataset,skill,true)
 local learned,learnedSource,liveTiers=liveLearned(key,options.learnedRecipes,rows,skill)
 local optimizer=JLP:GetModule("UniversalRouteOptimizer")
 if not optimizer then return nil,"FORECAST_ENGINE_UNAVAILABLE" end
 local plan,reason=optimizer:PlanTo300(key,skill,rows,learned,options)
 local rankEvidence=JLP:GetModule("PrimaryCraftingRankSources211")
 if type(plan)=="table" and rankEvidence then
  plan.rankSourceContinuity=rankEvidence:AtSkill(key,math.min(299,math.max(1,skill)),
     profession.maxSkill,options.currentFaction)
  plan.rankSourceCoverage=rankEvidence:Coverage(key,options.currentFaction)
 end
 -- P0-220: only the explicitly requested future forecast pays the cost of
 -- source-window proof analysis. NEVER execute a 1-299 scan per UI repaint.
 -- Source windows are NOT skill-up receipts or guaranteed route segments.
 if type(plan)=="table" then
  local primary=JLP:GetModule("ForeverPrimarySourceWindows233")
  if primary and type(primary.Continuity)=="function" then
   local ok,coverage=pcall(primary.Continuity,primary,key,math.max(1,math.min(300,skill)))
   if ok and type(coverage)=="table" then
    plan.sourcePrimaryContinuity233=coverage
    local okay,current=pcall(primary.AtSkill,primary,key,math.max(1,math.min(299,skill)),options)
    if okay and type(current)=="table" then plan.sourcePrimaryAtStart233=current end
   end
  end
  if key=="FIRST_AID" then
   local advisor=JLP:GetModule("ForeverFirstAidArtisan232")
   if advisor and type(advisor.PlanTo300)=="function" then
    local ok,r=pcall(advisor.PlanTo300,advisor,skill,{
     currentFaction=options.currentFaction,learnedRecipes=options.learnedRecipes,
     inventory=options.inventory,maxSkill=profession.maxSkill,
     scenarioCraftCounts=options.scenarioCraftCounts})
    if ok and type(r)=="table" then plan.sourceFirstAidArtisanPlan232=r end
   end
   if advisor and type(advisor.PlanFullTo300)=="function" then
    local ok,full=pcall(advisor.PlanFullTo300,advisor,skill,{
     currentFaction=options.currentFaction,learnedRecipes=options.learnedRecipes,
     inventory=options.inventory,maxSkill=profession.maxSkill,
     scenarioCraftCountsByBand=options.scenarioCraftCountsByBand})
    if ok and type(full)=="table" then plan.sourceFirstAidFullContinuity236=full end
   end
  end
  -- P0-235: newly sourced alternative recipe windows; read-only and on-demand.
  local added=JLP:GetModule("ForeverProgressionWindows235")
  if added and type(added.Continuity)=="function" then
   local ok,proof=pcall(added.Continuity,added,key,math.max(1,math.min(300,skill)))
   if ok and type(proof)=="table" then plan.sourceAlternativeContinuity235=proof end
  end
  -- P0-234: on-demand source-to-manual-action continuity, NOT optimizer authority.
  local chain234=JLP:GetModule("ProfessionSourceActionChain234")
  if chain234 and type(chain234.Continuity)=="function" then
   local ok,r=pcall(chain234.Continuity,chain234,key,math.max(1,math.min(300,skill)),options)
   if ok and type(r)=="table" then plan.sourceActionContinuity234=r end
  end
  -- P0-228: field-separated source-coverage audit for the selected profession.
  -- Only explicit future planning pays for the 1-300 scan. This result is
  -- not a native route or a claim of observed progression.
  local coverage=JLP:GetModule("ProfessionProgressionCoverage228")
  if coverage and type(coverage.Audit)=="function" then
   local ok,report=pcall(coverage.Audit,coverage,key,math.max(1,math.min(299,skill)),300)
   if ok and type(report)=="table" then plan.progressionSourceCoverage228=report end
  end
  -- P0-230: a separate, source-revalidated CONDITIONAL multi-step BOM.
  -- This neither replaces the existing optimizer ledger nor grants real stock
  -- credits; missing source receipts remain withheld and visible.
  local budget=JLP:GetModule("ProfessionSourceBudget230")
  if budget and type(budget.ReviewRoute)=="function" then
   local ok,bom=pcall(budget.ReviewRoute,budget,key,plan.route or {},{
    inventory=options.inventory,learnedRecipes=learned,
    prices=options.prices,currentFaction=options.currentFaction})
   if ok and type(bom)=="table" then plan.sourceConditionalBudget230=bom end
  end
  -- P0-226: research-only contiguous alternatives, evaluated only on explicit
  -- future PlanTo300 requests. Never used to grant native craft or navigation.
  local stitched=JLP:GetModule("ForeverStitchedSourceRoutes226")
  if stitched and type(stitched.AtSkill)=="function" then
   local ok,value=pcall(stitched.AtSkill,stitched,key,math.min(299,math.max(1,skill)))
   if ok and type(value)=="table" then plan.sourceStitchedCandidates=value end
  end
  local bridge=JLP:GetModule("ForeverStitchedCurrentStep227")
  if bridge and type(bridge.Review)=="function" then
   local ok,review=pcall(bridge.Review,bridge,key,math.min(299,math.max(1,skill)))
   if ok and type(review)=="table" then plan.sourceStitchedCurrentReview=review end
  end
  local bands=JLP:GetModule("ForeverSkillBandPlanner")
  if bands and type(bands.BuildContinuity)=="function" then
   local proof=bands:BuildContinuity(key,math.min(299,math.max(1,skill)),options.strategy)
   if proof then
    -- Read-only checklist of the FIRST unresolved action. No future window
    -- skips gaps, no fixture learned state becomes a live receipt.
    local unblocker=bands.CurrentWindowChecklist and
      bands:CurrentWindowChecklist(proof,{learnedRecipes=learned,learnedSource=learnedSource})
    proof.currentUnblocker=unblocker
    plan.sourceWindowContinuity=proof
   end
  end
 end
 return plan,reason
end
-- Only advisory presentation is replaced. Source/native execution structures,
-- settlement, transaction recovery and recipe learning persistence are untouched.
function S:Apply(key,plan,profession,dataset)
    if not plan then return plan end
    if plan.actionKind=="train" and key~="ENCHANTING" and not ((key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and dataset and dataset.progression) then
        local rankEvidence=JLP:GetModule("PrimaryCraftingRankSources211")
        local skill=type(profession)=="table" and number(profession.skill)
        if rankEvidence and skill then
            plan.rankSourceContinuity=rankEvidence:AtSkill(key,skill,
                number(profession.maxSkill),nil)
        end
        return plan
    end
    if plan.actionKind=="complete" or plan.actionKind=="learn" then return plan end
    local current,err=self:Recommend(key,profession,dataset)
    if not current then
        plan.currentStepSelectionError=err
        return plan
    end
    plan.recommendedCurrentStep=current
    plan.currentStepRecommendationContract=self.contract
    if key=="BLACKSMITHING" and current.blacksmithingGap or key=="ENGINEERING" and current.engineeringGap or key=="LEATHERWORKING" and current.leatherworkingGap then
        plan.actionKind="verify";plan.status=current.status;plan.action=current.nextAction
        plan.step=current;plan.materials={};plan.readOnly=true;plan.nativeDispatchAllowed=false;plan.executionEligible=false
        return plan
    end
    if current.kind=="verify" and current.sourceGapFallback234==true then
        plan.actionKind="verify";plan.status="source-gap-review-234"
        plan.action=current.nextAction;plan.materials={};plan.step=nil
        plan.readOnly=true;plan.referenceOnly=true
        plan.nativeDispatchAllowed=false;plan.executionEligible=false
        plan.sourceActionEvidence234=current.sourceActionEvidence234
        return plan
    end
    if current.kind=="verify" and current.sourceFirstAidArtisanFallback232==true then
        plan.actionKind="verify";plan.status="first-aid-artisan-source-review"
        plan.action=current.nextAction;plan.materials=current.materials
        plan.firstAidArtisanSource232=current.sourceFirstAidArtisan232
        plan.step=nil;plan.readOnly=true;plan.referenceOnly=true
        plan.nativeDispatchAllowed=false;plan.executionEligible=false
        return plan
    end
    if current.kind=="verify" and current.source229MinimumFallback==true then
        plan.actionKind="verify";plan.status="exact-minimum-recipe-source-review"
        plan.action=current.nextAction;plan.materials=current.materials
        plan.exactMinimumLead229=current.exactMinimumLead229
        plan.sourceFieldChain229=current.sourceReceipt229
        plan.step=nil;plan.readOnly=true;plan.nativeDispatchAllowed=false
        plan.executionEligible=false;plan.referenceOnly=true
        return plan
    end
    if current.kind=="verify" and current.sourceStitchedResearchFallback==true then
        -- The existing Planner/Guide receives a concrete source-backed
        -- verification step instead of an empty catalogue result. No route,
        -- output forecast, native CTA or automatic owner sync is promoted.
        plan.actionKind="verify";plan.status="source-stitched-research-review"
        plan.action=current.nextAction;plan.materials=current.materials
        plan.step=nil;plan.readOnly=true;plan.nativeDispatchAllowed=false
        plan.executionEligible=false;plan.referenceOnly=true
        return plan
    end
    if current.kind=="gather" then
        plan.actionKind="reference";plan.status="gather-guidance"
        plan.action=current.action;plan.materials={};plan.step=nil
        plan.readOnly=true;plan.nativeDispatchAllowed=false;plan.executionEligible=false
        return plan
    end
    if current.tailoringRank and current.kind=="verify" then
        plan.actionKind="verify";plan.status=current.skillEligibilityStatus
        plan.action=current.nextAction;plan.step=current;plan.materials={}
        plan.readOnly=true;plan.nativeDispatchAllowed=false;plan.executionEligible=false
        return plan
    end
    if (key=="ENCHANTING" and current.enchantingRank) or ((key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and current.alchemyRank) then
        plan.actionKind=current.kind=="train" and "train" or "verify"
        plan.action=current.nextAction;plan.status=key.."_RANK_OBSERVATION_REQUIRED"
        plan.step=current;plan.materials={};plan.readOnly=true;plan.nativeDispatchAllowed=false;plan.executionEligible=false
        return plan
    end
    if current.kind~="craft" then return plan end
    local old=plan.step
    -- A working native route retains its native capability if it selects the
    -- same recipe. A different recipe is manual/read-only until the existing
    -- native dispatcher independently qualifies it.
    if plan.actionKind=="craft" and type(old)=="table" and
        tonumber(old.recipeID)==current.recipeID and
        plan.nativeDispatchAllowed==true and current.learned==true and
        current.manualCraftBlockedByOutputConflict~=true and
        current.manualCraftBlockedBySourceConflict~=true and
        current.manualCraftBlockedByLiveLearning~=true and
        current.manualCraftBlockedByLiveDifficulty~=true and
        current.manualCraftBlockedByRecipePrerequisite~=true and
        (key~="ENCHANTING" or current.requiredNextAction=="manual-craft") and
        not (current.currentRecipeDifficulty and
            (current.currentRecipeDifficulty.tier=="GRAY" or
             current.currentRecipeDifficulty.canSkillUp==false)) then
        self:FormatCraftStep(current,old.remainingCrafts)
        old.craftInstruction=current.craftInstruction;old.craftQuantity=current.craftQuantity;old.craftQuantityUnit="CASTS"
        plan.action=current.nextAction
        return plan
    end
    local selected=current.learned==true and
        current.manualCraftBlockedByOutputConflict~=true and
        current.manualCraftBlockedBySourceConflict~=true and
        current.manualCraftBlockedByLiveDifficulty~=true and
        current.manualCraftBlockedByLiveLearning~=true and
        current.manualCraftBlockedByRecipePrerequisite~=true
    plan.actionKind=selected and "craft" or "verify"
    plan.status=selected and "manual-one-craft-advisory" or
        (current.manualCraftBlockedByOutputConflict==true and "OUTPUT_CONTRACT_CONFLICT" or
        current.manualCraftBlockedByLiveDifficulty==true and "LIVE_DIFFICULTY_BLOCKED" or
        current.manualCraftBlockedByLiveLearning==true and "LIVE_RECIPE_UNLEARNED" or
        current.learned~=true and "LEARNED_STATE_UNVERIFIED" or
        current.manualCraftBlockedBySourceConflict==true and "SOURCE_CONFLICT" or
        "verify-recipe-knowledge")
    plan.currentStepRequalificationReason=plan.status
    plan.action=current.nextAction
    plan.step={kind="craft",recipe=current.recipe,recipeID=current.recipeID,
        skillMin=current.skill,skillTarget=current.skillTarget,
        materials={},remainingCrafts=current.remainingCrafts,craftInstruction=current.craftInstruction,craftQuantity=current.craftQuantity,craftQuantityUnit="CASTS",ordinaryAnvil=current.ordinaryAnvil,stationStatus=current.stationStatus,sourceBuild=current.sourceBuild,
        navigation=current.navigation,recipeSourcePlanning=current.recipeSourcePlanning,
        preparingIntermediate=current.preparingIntermediate,progressionRecipeID=current.progressionRecipeID,
        progressionRecipe=current.progressionRecipe,woolScenario=current.woolScenario,
        strategyEvidence=current.strategyEvidence,
        actionType=current.actionType,enchantTarget=current.enchantTarget,toolRequirement=current.toolRequirement,requiredTool=current.requiredTool,
        minimumStatus=current.minimumStatus,learningMinimum=current.learningMinimum,
        alchemyPrerequisites=current.alchemyPrerequisites,preparingIntermediate=current.preparingIntermediate,preparationForRecipeID=current.preparationForRecipeID,
        accountMaterialReservations=current.accountMaterialReservations,
        crossProfessionDependencies=current.crossProfessionDependencies,
        sourceInfo=current.navigation and current.navigation.waypointQualified and
            current.navigation.source or nil,
        learned=current.learned,learnedSource=current.learnedSource,
        bagReady=current.bagReady,knownInventory=current.knownInventory,
        manualCraftBlockedByLiveDifficulty=current.manualCraftBlockedByLiveDifficulty,
        manualCraftBlockedByLiveLearning=current.manualCraftBlockedByLiveLearning,
        manualCraftBlockedBySourceConflict=current.manualCraftBlockedBySourceConflict,
        manualCraftBlockedByOutputConflict=current.manualCraftBlockedByOutputConflict,
        sourceFieldChain229=current.sourceFieldChain229,
        sourcePrimaryWindows233=current.sourcePrimaryWindows233,
        recipeMinimumEvidence=current.recipeMinimumEvidence,
        nativeDispatchAllowed=false,executionEligible=false,readOnly=true}
    -- Preserve the SAME read-only reagent snapshot across Planner, action
    -- queue, UI and completion chain. Dropping missing/bagsKnown previously
    -- made the projected step report UNKNOWN after a known bag observation.
    -- These copied fields NEVER authorize native dispatch; a native craft has
    -- to fetch its own fresh client recipe/reagent/transaction evidence.
    for _,m in ipairs(current.materials or {}) do
        plan.step.materials[#plan.step.materials+1]={itemID=m.itemID,name=m.name,
            quantity=m.quantity or m.perCraft,perCraft=m.perCraft or m.quantity,
            required=m.batchRequired or m.required or m.perCraft or m.quantity,
            source=m.source,craftedFrom=m.craftedFrom,batchRequired=m.batchRequired,immediateRequired=m.immediateRequired,missing=m.batchMissing or m.missing,bagsKnown=m.bagsKnown==true,
            bags=m.bagsKnown==true and m.bags or nil,
            price=m.price,priceStatus=m.priceStatus,readOnly=true,
            nativeDispatchAllowed=false}
    end
    plan.step.stationPreparation=current.stationPreparation
    for _,m in ipairs(current.stationPreparation and current.stationPreparation.materials or {})do
        local found
        for _,r in ipairs(plan.step.materials)do if r.itemID==m.itemID then found=r;break end end
        if found then found.required=(found.required or 0)+m.required
        else plan.step.materials[#plan.step.materials+1]={itemID=m.itemID,name=m.name,required=m.required,quantity=m.quantity,source=m.source,bagsKnown=m.bagsKnown,bags=m.bags,missing=m.missing,stationPreparation=true,readOnly=true,nativeDispatchAllowed=false}end
    end
    plan.step.inventoryObservationType="CURRENT_RECOMMENDATION_ADVISORY"
    plan.materials=plan.step.materials
    plan.p1OneCraft=selected
    plan.readOnly=true;plan.referenceOnly=true;plan.readOnlyRouteFallback=false
    plan.executionEligible=false;plan.nativeDispatchAllowed=false
    plan.plannerEligible=true
    plan.routeAuthorityEnabled=false
    if key=="ENCHANTING" and current.requiredNextAction=="verify" then
        plan.actionKind="verify";plan.status="ENCHANTING_PREREQUISITE_VERIFICATION";plan.p1OneCraft=false
    elseif current.secondaryAccess then
        plan.actionKind=current.requiredNextAction=="learn-recipe"and "learn"or current.requiredNextAction=="acquire-recipe"and "acquire"or "verify"
        plan.status=key.."_"..current.secondaryAccess.status;plan.p1OneCraft=false
    elseif key=="FIRST_AID"and current.firstAidAccess then
        plan.actionKind=current.requiredNextAction=="learn-recipe"and "learn"or current.requiredNextAction=="acquire-recipe"and "acquire"or "verify"
        plan.status="FIRST_AID_"..current.firstAidAccess.status;plan.p1OneCraft=false
    elseif current.trainerAcquisition and current.learned~=true then
        plan.trainerAcquisition=current.trainerAcquisition;plan.step.trainerAcquisition=current.trainerAcquisition
        plan.actionKind=current.requiredNextAction=="learn-trainer" and "learn" or "verify"
        plan.status="TRAINER_RECIPE_"..current.trainerAcquisition.status;plan.p1OneCraft=false
    elseif current.patternAcquisition and current.learned~=true then
        plan.patternAcquisition=current.patternAcquisition
        plan.step.patternAcquisition=current.patternAcquisition
        plan.actionKind=current.requiredNextAction=="acquire-recipe" and "acquire" or
            current.requiredNextAction=="learn-recipe" and "learn" or "verify"
        plan.status="RECIPE_ITEM_"..current.patternAcquisition.status;plan.p1OneCraft=false
    elseif current.requiredNextAction=="acquire" and selected then
        plan.actionKind="acquire";plan.status="MATERIAL_ACQUISITION_REQUIRED";plan.p1OneCraft=false
    elseif current.requiredNextAction=="verify" and selected then
        plan.actionKind="verify";plan.status="MATERIAL_INVENTORY_UNKNOWN";plan.p1OneCraft=false
    end
    return plan
end
JLP:RegisterModule("UniversalCurrentStep",S)
