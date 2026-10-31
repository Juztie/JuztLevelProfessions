local _, JLP = ...

local function prerequisitePlan(key)
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
        executionEligible=false,lightweightPrerequisite=true,actionKind="prerequisite",action=text,guidance=text}
end

local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end
local function memoObservation(group,key,fn)
    if JLP.MemoObservation then return JLP:MemoObservation(group,key,fn) end
    return fn()
end
local Planner = {}


local function getPlayerLevel()
    if type(UnitLevel) ~= "function" then return 0 end
    local ok, value = pcall(UnitLevel, "player")
    return ok and (tonumber(value) or 0) or 0
end

local function routeFor(key)
    local provider = JLP:GetModule("ProfessionDatasetProvider")
    if provider and provider.GetPlannerDataset then
        return provider:GetPlannerDataset(key, {allowCandidate=true, allowResearch=true,
            allowHistoricalReference=true})
    end
    return nil
end

-- P0.2B-QAFix: a missing qualification flag or empty gap list is never
-- affirmative proof of craft counts. Historical route estimates are advisory.
-- Only explicitly qualified counts with a matching current-build/observed
-- source can be promoted, independently of recipe minimum-skill evidence.
local function craftEstimateEvidence(step)
    if type(step)~="table" then return "UNKNOWN",false end
    if step.craftCountEvidenceStatus=="INVALID" then return "INVALID",false end
    if step.craftCountQualified==false then return "UNVERIFIED",false end
    if step.craftCountQualified~=true then return "UNKNOWN",false end
    local crafts=tonumber(step.expectedCrafts)
    local authority=step.craftCountAuthority
    if not crafts or crafts~=crafts or crafts<=0 or crafts==math.huge or
        crafts==-math.huge then return "INVALID",false end
    if authority=="CURRENT_BUILD_VERIFIED" or
        authority=="CLIENT_OBSERVED_CURRENT_BUILD" then
        return "QUALIFIED",true
    end
    return "UNVERIFIED",false
end

local function selectedStrategy(explicit)
    local configured=JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy
    local value=explicit or configured or "economical"
    if value=="fastest" or value=="economical" or value=="self_found" then return value end
    return "economical"
end

-- The registered step is the stable default. Alternative rows are considered
-- only if the registered dataset explicitly carries equally scoped, qualified
-- advisory candidates. Never infer these from a recipe catalogue or AH prices.
local function selectStrategyStep(key,dataset,step,fromSkill,toSkill,strategy)
    strategy=selectedStrategy(strategy)
    local selection={strategy=strategy,reason="REGISTERED_ROUTE_ONLY",candidateCount=1,
        selectedRecipe=step and step.recipe,qualifiedAlternatives=0,
        readOnly=true,nativeDispatchAllowed=false}
    if type(step)~="table" then return step,selection end
    local options={step}
    local alternatives=type(step.strategyAlternatives)=="table" and step.strategyAlternatives or {}
    for _,alt in ipairs(alternatives) do
        if type(alt)=="table" and alt.plannerEligible==true and alt.routeQualified==true and
            tonumber(alt.skillMin)==tonumber(step.skillMin) and
            tonumber(alt.skillTarget)==tonumber(step.skillTarget) and
            type(alt.recipeID)=="number" and alt.recipeID>0 and
            type(alt.recipe)=="string" and alt.recipe~="" and
            tonumber(alt.expectedCrafts) and tonumber(alt.expectedCrafts)>0 and
            tonumber(alt.sourceBuild) and tonumber(alt.sourceBuild)==tonumber(dataset and dataset.sourceBuild) and
            type(alt.evidence)=="string" and alt.evidence~="" and
            type(alt.materials)=="table" then
            local valid=#alt.materials>0
            for _,m in ipairs(alt.materials) do
                if type(m)~="table" or not tonumber(m.itemID) or not tonumber(m.quantity) or
                    tonumber(m.quantity)<=0 or not m.source then valid=false;break end
            end
            if valid then
                local assessor=JLP:GetModule("RecipeDifficulty")
                local eligibility=assessor and assessor.AssessProgression and
                    assessor:AssessProgression(key,alt,fromSkill,toSkill) or nil
                -- A sourced minimum-gate conflict cannot become a strategy
                -- alternative, regardless of lower price or claimed speed.
                if not eligibility or eligibility.progressionAllowed then
                    options[#options+1]=alt
                end
            end
        end
    end
    selection.qualifiedAlternatives=#options-1
    selection.candidateCount=#options
    if #options==1 then
        if #alternatives>0 then selection.reason="ALTERNATIVES_NOT_QUALIFIED" end
        return step,selection
    end
    local inventory=JLP:GetModule("Inventory")
    local optimizer=JLP:GetModule("CostOptimizer")
    -- Q120: numeric cached bags are not evidence that inventory was observed.
    -- nil means UNKNOWN, never an observed zero or a verified supply.
    local function bags(id)
        local owned=inventory and inventory.GetOwned and inventory:GetOwned(id)
        if type(owned)~="table" or owned.bagKnown~=true then return nil end
        local count=tonumber(owned.bags)
        if not count or count~=count or count<0 or count==math.huge or
            count%1~=0 then return nil end
        return count
    end
    -- Q121: qualify the entire candidate's demand once per ItemID. Checking
    -- each row against the same bag count independently double-spends stock.
    -- Keep source-backed gathering/vendor separate from inventory, and fail
    -- closed on conflicting source claims or unresolved material transforms.
    local function selfFoundQualified(candidate)
        local crafts=tonumber(candidate.expectedCrafts)
        local span=(tonumber(candidate.skillTarget) or 0)-(tonumber(candidate.skillMin) or 0)
        if not crafts or crafts~=crafts or crafts<=0 or crafts==math.huge or
            crafts==-math.huge or not span or span<=0 or span==math.huge then return false end
        crafts=math.max(1,math.ceil(crafts*math.max(0,math.min(toSkill,candidate.skillTarget)-
            math.max(fromSkill,candidate.skillMin))/span))
        if crafts==math.huge then return false end
        if type(candidate.materials)~="table" or #candidate.materials==0 then return false end
        local demands={}
        for _,m in ipairs(candidate.materials) do
            if type(m)~="table" then return false end
            local id=tonumber(m.itemID)
            local quantity=tonumber(m.quantity)
            if not id or id~=id or id<=0 or id==math.huge or id%1~=0 or
                not quantity or quantity~=quantity or quantity<=0 or
                quantity==math.huge or quantity%1~=0 then return false end
            -- We do not infer intermediate recipe output yields or treat their
            -- inputs as already available completed components.
            if type(m.craftedFrom)=="table" or type(m.craftedRecipe)=="table" then return false end
            local required=crafts*quantity
            if required==math.huge or required~=required then return false end
            local source=m.source
            local kind=(source=="gather" or source=="gathering" or source=="self-found")
                and "gathering" or source
            local row=demands[id]
            if row then
                local total=row.required+required
                if total==math.huge or total~=total or row.kind~=kind then return false end
                row.required=total
                -- Every gathering line must carry its own qualification.
                row.gatherQualified=row.gatherQualified and m.acquisitionQualified==true
            else
                demands[id]={required=required,kind=kind,
                    gatherQualified=m.acquisitionQualified==true}
            end
        end
        for id,row in pairs(demands) do
            local bagCount=bags(id)
            -- A bank cache never substitutes for bags. If total demand is not
            -- observed in bags, only the candidate's *consistently qualified*
            -- vendor/gathering source may independently satisfy it.
            if (bagCount==nil or row.required>bagCount) and row.kind~="vendor" and
                not (row.kind=="gathering" and row.gatherQualified) then return false end
        end
        return true
    end
    local best=step
    if strategy=="self_found" then
        local defaultQualified=selfFoundQualified(step)
        if not defaultQualified then
            for i=2,#options do
                if selfFoundQualified(options[i]) then best=options[i];break end
            end
        end
        selection.reason=best~=step and "SELF_FOUND_QUALIFIED_SOURCE" or
            (defaultQualified and "REGISTERED_SELF_FOUND_FEASIBLE" or "SELF_FOUND_SOURCE_UNRESOLVED")
    elseif strategy=="fastest" then
        local function time(candidate)
            if candidate.timeEvidence=="qualified" and type(candidate.estimatedSeconds)=="number" and
                candidate.estimatedSeconds>=0 and candidate.estimatedSeconds<math.huge then
                return candidate.estimatedSeconds
            end
            return nil
        end
        local current=time(step)
        local allTimes=current~=nil
        for i=2,#options do if time(options[i])==nil then allTimes=false end end
        if allTimes then
            selection.reason="QUALIFIED_TIME_COMPARISON"
            for i=2,#options do
                local seconds=time(options[i])
                if seconds<current then current=seconds;best=options[i] end
            end
        else selection.reason="TIME_EVIDENCE_UNAVAILABLE" end
    else
        local quotes={}
        local complete=true
        for _,candidate in ipairs(options) do
            local q=optimizer and optimizer.QuoteRouteCandidate and
                optimizer:QuoteRouteCandidate(candidate,fromSkill,toSkill,dataset and dataset.sourceBuild)
            quotes[#quotes+1]=q
            if not q or q.complete~=true or type(q.knownCost)~="number" then complete=false end
        end
        if complete then
            local exact=true
            for _,quote in ipairs(quotes) do if quote.costOptimal~=true then exact=false end end
            selection.costOptimal=exact
            selection.reason=exact and "QUALIFIED_COST_COMPARISON" or "FEASIBLE_COST_ESTIMATE_COMPARISON"
            local current=quotes[1].knownCost
            for i=2,#options do
                if quotes[i].knownCost<current then current=quotes[i].knownCost;best=options[i] end
            end
        else selection.reason="COST_EVIDENCE_UNAVAILABLE" end
    end
    selection.selectedRecipe=best.recipe
    selection.changed=best~=step
    return best,selection
end

-- A selected strategy alternative is an advisory recipe candidate, not a
-- promotion of the registered route's execution authority. Project only the
-- already exposed fields; never mutate the canonical dataset or candidate.
-- Use the same projection for rawStep, step.dataset and scope segments, since
-- downstream consumers may inspect any of these rather than the plan header.
local function advisoryAuthorityView(record)
    if type(record)~="table" then return record end
    local view={}
    for k,v in pairs(record) do view[k]=v end
    view.executionEligible=false
    view.nativeDispatchAllowed=false
    view.routeAuthorityEnabled=false
    view.readOnly=true
    view.researchAuthority=false
    view.productionAuthority=false
    view.executionAuthorityEnabled=false
    view.dispatchAllowed=false
    view.authority="advisory-strategy-alternative-no-native-authority"
    return view
end

local function sourceResolver()
    return JLP:GetModule("SourceResolver")
end

local function findTrainerGate(dataset, maxSkill)
    if not dataset or not maxSkill then return nil end
    for _, gate in ipairs(dataset.trainerGates or {}) do
        if tonumber(gate.cap) == tonumber(maxSkill) then return gate end
    end
    return nil
end

-- P0-C: an observed rank cap is independent of historical route completeness.
-- Some candidate datasets intentionally have no trainerGates; the existing
-- SourceResolver rank requirements are only a *read-only* rank reference.
-- Never infer a new cap, NPC, permission or native training from the route.
-- A saved/previous-session profession snapshot can be displayed as history,
-- but must never create a CURRENT trainer step or navigation intent. Check
-- against the authoritative ProfessionAPI a second time for direct scope callers.
-- The stamped build is SESSION identity, NOT a hardcoded build compatibility gate.
local function freshRankCapObservation(key, snapshot, skill, cap)
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and type(reg.Get)=="function" and reg:Get(key) or nil
    local owner=JLP:GetModule("CharacterIdentity")
    local build=JLP:GetModule("ClientBuildInfo")
    local api=JLP:GetModule("ProfessionAPI")
    if not def or type(snapshot)~="table" or snapshot.cached~=false or
       snapshot.key~=key or not owner or type(owner.GetKey)~="function" or
       not build or type(build.GetBuildNumber)~="function" or
       not api or type(api.Get)~="function" then return false end
    local source=snapshot.detectionSource
    if source~="get-professions-primary" and source~="get-professions-secondary" and
       source~="stable-id-query" then return false end
    local character=owner:GetKey(true)
    local activeBuild=build:GetBuildNumber()
    if type(character)~="string" or character=="" or
       character:find("UnknownCharacter",1,true) or
       character:find("UnknownRealm",1,true) or
       type(activeBuild)~="number" or activeBuild<=0 or
       activeBuild~=math.floor(activeBuild) then return false end
    local function verified(row)
        return type(row)=="table" and row.cached==false and row.key==key and
            row.detectionSource==source and row.characterKey==character and
            row.observedClientBuild==activeBuild and
            tonumber(row.skillLine)==tonumber(def.skillLineID) and
            (row.professionEnum==nil or tonumber(row.professionEnum)==tonumber(def.professionEnum)) and
            type(row.skill)=="number" and row.skill==skill and
            type(row.maxSkill)=="number" and row.maxSkill==cap
    end
    if not verified(snapshot) then return false end
    local ok,current=pcall(api.Get,api,key)
    if not ok or not verified(current) then return false end
    -- An identity or build change DURING the second read invalidates the proof.
    return owner:GetKey(true)==character and build:GetBuildNumber()==activeBuild
end

local function referenceTrainerGate(key, cap, currentSkill, professionState)
    if type(cap)~="number" or currentSkill~=cap or
       not freshRankCapObservation(key,professionState,currentSkill,cap) then return nil end
    local tierByCap={[75]="Journeyman",[150]="Expert",[225]="Artisan"}
    local tier=tierByCap[cap]
    if not tier then return nil end
    local resolver=sourceResolver()
    if not resolver or type(resolver.GetRankRequirement)~="function" then return nil end
    local record=resolver:GetRankRequirement(key,tier)
    if type(record)~="table" or type(record.rank)~="string" or
       tonumber(record.skillCap)~=({[75]=150,[150]=225,[225]=300})[cap] or
       type(record.requiredSkill)~="number" or record.requiredSkill<0 or
       record.requiredSkill>cap or
       type(record.minCharacterLevel)~="number" or
       record.minCharacterLevel<0 then return nil end
    return {cap=cap,nextCap=record.skillCap,rank=record.rank,
       requiredSkill=record.requiredSkill,
       minCharacterLevel=record.minCharacterLevel,
       advisoryOnly=true,readOnly=true,nativeDispatchAllowed=false,
       sourceAuthority="SOURCE_RANK_REFERENCE_ONLY"}
end

-- A missing current route step can still have a documented next interval.
-- This is a SOURCE POSITION for a targeted verification, never a synthetic
-- craft, learned recipe, travel destination or complete skill route.
local function nextDocumentedRoutePosition(dataset, skill)
    if type(dataset)~="table" or type(skill)~="number" or skill~=skill or
        skill<0 or skill>=300 or skill~=math.floor(skill) then return nil end
    local nearest
    for index, row in ipairs(dataset.route or dataset.steps or {}) do
        if type(row)=="table" then
            local lo, hi=tonumber(row.skillMin),tonumber(row.skillTarget)
            if lo and hi and lo==math.floor(lo) and hi==math.floor(hi) and
                lo>=0 and hi<=300 and lo<hi and lo>skill and
                type(row.recipe)=="string" and row.recipe~="" and
                (not nearest or lo<nearest.fromSkill) then
                nearest={fromSkill=lo,toSkill=hi,recipe=row.recipe,
                    recipeID=row.recipeID,routeIndex=index,
                    evidence=row.evidence or dataset.evidence,
                    sourceBuild=dataset.sourceBuild,
                    reason="NEXT_DOCUMENTED_SKILL_INTERVAL"}
            end
        end
    end
    return nearest
end

local function progressionSteps(key,dataset,context)
    local provider=JLP:GetModule("ProfessionDatasetProvider")
    if provider and provider.GetProgressionSteps then return provider:GetProgressionSteps(key,dataset,context) end
    return dataset and (dataset.route or dataset.steps) or {}
end
local function findRouteStep(dataset, skill)
    if not dataset then return nil, nil end
    for index, step in ipairs(progressionSteps(dataset.key,dataset,{currentOnly=true,skill=skill})) do
        if skill >= (step.skillMin or 0) and skill < (step.skillTarget or 0) then
            return step, step.routeIndex or index
        end
    end
    return nil, nil
end

-- Source-specific skill qualification does not confer native craft authority.
local function skillEligibility(key,step,fromSkill,toSkill)
    if type(step)=="table" and (type(step.expectedCrafts)~="number" or
        step.expectedCrafts<=0 or step.expectedCrafts~=math.floor(step.expectedCrafts)) then
        return {status="CRAFT_COUNT_UNVERIFIED",progressionAllowed=false,
            progressionQualified=false,minimumSkill=nil,
            readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
    end
    local validator=JLP:GetModule("RecipeDifficulty")
    local eligibility
    if validator and validator.AssessProgression then
        eligibility=validator:AssessProgression(key,step,fromSkill,toSkill)
    else
        eligibility={status="MINIMUM_SKILL_UNVERIFIED",progressionAllowed=true,
            progressionQualified=false,readOnly=true,nativeDispatchAllowed=false}
    end
    -- P0.2L: source-qualified learning MINIMUM is not proof that the live
    -- player knows this recipe or that historical 70009 crafts grant skill.
    -- Limit the additional advisory gate to the explicitly unqualified
    -- Tailoring 143-145 step. No change to generic professions or native gates.
    if key=="TAILORING" and
       ((step.recipeID==3852 and step.skillMin==143 and step.skillTarget==145) or
        (step.recipeID==3813 and step.skillMin==153 and step.skillTarget==160) or
        (step.recipeID==8786 and step.skillMin==160 and step.skillTarget==170) or
        (step.recipeID==8791 and step.skillMin==170 and step.skillTarget==180) or
        (step.recipeID==8799 and step.skillMin==180 and step.skillTarget==190) or
        (step.recipeID==8799 and step.skillMin==190 and step.skillTarget==195) or
        (step.recipeID==12053 and step.skillMin==195 and step.skillTarget==200) or
        (step.recipeID==12053 and step.skillMin==200 and step.skillTarget==205) or
        (step.recipeID==12072 and step.skillMin==205 and step.skillTarget==210) or
        (step.recipeID==12072 and step.skillMin==210 and step.skillTarget==220) or
        (step.recipeID==12072 and step.skillMin==220 and step.skillTarget==225) or
        (step.recipeID==18402 and step.skillMin==225 and step.skillTarget==230) or
        (step.recipeID==18402 and step.skillMin==230 and step.skillTarget==240) or
        (step.recipeID==18402 and step.skillMin==240 and step.skillTarget==245) or
        (step.recipeID==18420 and step.skillMin==245 and step.skillTarget==250) or
        (step.recipeID==18420 and step.skillMin==250 and step.skillTarget==260) or
        (step.recipeID==18420 and step.skillMin==260 and step.skillTarget==262) or
        (step.recipeID==18438 and step.skillMin==262 and step.skillTarget==270)) and
       step.advisoryOnly==true and step.routeQualified==false and
       (step.sourceQualificationContract=="tailoring-143-145-gloves-evidence-p02l-v1" or
        step.sourceQualificationContract=="tailoring-153-160-small-silk-pack-evidence-p02n-v1" or
        step.sourceQualificationContract=="tailoring-160-170-azure-silk-cloak-evidence-p02o-v1" or
        (step.sourceQualificationContract=="tailoring-170-180-crimson-silk-vest-evidence-p02p-v1" or
        step.sourceQualificationContract=="tailoring-180-190-crimson-silk-pantaloons-evidence-p02q-v1" or
        step.sourceQualificationContract=="tailoring-190-195-crimson-silk-pantaloons-evidence-p02r-v1" or
        step.sourceQualificationContract=="tailoring-195-200-black-mageweave-gloves-evidence-p02r-v1" or
        step.sourceQualificationContract=="tailoring-200-205-black-mageweave-gloves-evidence-p02s-v1" or
        step.sourceQualificationContract=="tailoring-205-210-black-mageweave-headband-evidence-p02s-v1" or
        step.sourceQualificationContract=="tailoring-210-220-black-mageweave-headband-evidence-p02t-v1" or
        step.sourceQualificationContract=="tailoring-220-225-black-mageweave-headband-evidence-p02u-v1" or        step.sourceQualificationContract=="tailoring-225-230-runecloth-belt-evidence-p02u-v1" or
        step.sourceQualificationContract=="tailoring-230-240-runecloth-belt-evidence-p02v-v1" or
        step.sourceQualificationContract=="tailoring-240-245-runecloth-belt-evidence-p02w-v1" or
        step.sourceQualificationContract=="tailoring-245-250-brightcloth-cloak-evidence-p02w-v1" or
step.sourceQualificationContract=="tailoring-250-260-brightcloth-cloak-evidence-p02x-v1" or
        step.sourceQualificationContract=="tailoring-260-262-brightcloth-cloak-evidence-p02y-v1" or
        step.sourceQualificationContract=="tailoring-262-270-runecloth-pants-evidence-p02y-v1")) and
       eligibility.progressionAllowed then
        eligibility.progressionAllowed=false
        eligibility.status="ROUTE_EVIDENCE_UNVERIFIED"
        eligibility.routeQualification="UNVERIFIED"
    end
    return eligibility
end

-- P1-174: live one-craft advice is distinct from progression authority.
-- A historical step with an unqualified bulk count may nevertheless name an
-- actual, learned, non-gray, currently craftable recipe. This never approves
-- the predicted route length, recipe yield, material budget or native dispatch.
local function liveManualOneCraft(key, profession, dataset, step, skill, cap)
    local recipeID=type(step)=="table" and step.recipeID or nil
    if type(recipeID)~="number" or recipeID~=math.floor(recipeID) or
        recipeID<=0 or recipeID>=2147483648 or
        type(profession)~="table" or profession.cached~=false or
        type(skill)~="number" or skill~=math.floor(skill) or skill<0 or
        type(cap)~="number" or cap~=math.floor(cap) or cap<=skill then return nil end
    local api=JLP:GetModule("ProfessionAPI")
    local crafting=JLP:GetModule("Crafting")
    local difficulty=JLP:GetModule("RecipeDifficulty")
    if not api or type(api.GetRecipeContext)~="function" or
       type(api.Get)~="function" or
       not crafting or type(crafting.GetCraftableCountState)~="function" or
       not difficulty or type(difficulty.GetForRecipe)~="function" then return nil end
    local function context()
        -- Prefer the existing full-session validation. A missing build/interface
        -- permits ONLY a second, volatile read-only observational path.
        local ok,full=pcall(api.GetRecipeContext,api,recipeID,key)
        if ok and type(full)=="table" and full.verified==true then return full end
        if type(api.GetReadOnlyRecipeObservation)~="function" then return nil end
        local observed,view=pcall(api.GetReadOnlyRecipeObservation,api,recipeID,key)
        return observed and type(view)=="table" and view or nil
    end
    local before=context()
    if not before or (before.verified~=true and before.readOnlyObserved~=true) or
       before.visible~=true or before.learned~=true or
       before.recipeID~=recipeID or before.professionKey~=key or
       type(before.name)~="string" or before.name=="" or
       before.panelToken==nil or before.panelRevision==nil or
       (before.verified==true and before.clientSessionToken==nil) then return nil end
    local difficultyOK,grade=pcall(difficulty.GetForRecipe,difficulty,key,recipeID,before.name)
    if not difficultyOK or type(grade)~="table" or
       (grade.confidence~="verified" and grade.confidence~="verified-recipe-link") or
       (grade.token~="orange" and grade.token~="yellow" and grade.token~="green") or
       grade.canSkillUp==false or
       (grade.recipeID~=nil and tonumber(grade.recipeID)~=recipeID) then return nil end
    local countOK,count=pcall(crafting.GetCraftableCountState,crafting,recipeID)
    if not countOK or type(count)~="table" or count.status~="KNOWN" or
       type(count.count)~="number" or count.count<1 or
       count.count~=math.floor(count.count) or count.count==math.huge or
       count.recipeID~=recipeID then return nil end
    local after=context()
    if not after or (after.verified~=true and after.readOnlyObserved~=true) or
       after.verified~=before.verified or
       after.readOnlyObserved~=before.readOnlyObserved or
       after.visible~=true or after.learned~=true or after.recipeID~=recipeID or
       after.professionKey~=key or after.name~=before.name or
       after.panelToken~=before.panelToken or
       after.panelRevision~=before.panelRevision or
       after.observationQuality~=before.observationQuality or
       after.clientSessionToken~=before.clientSessionToken then return nil end
    local liveOK,live=pcall(api.Get,api,key)
    if not liveOK or type(live)~="table" or live.cached~=false or
       live.key~=key or tonumber(live.skill)~=skill or
       tonumber(live.maxSkill)~=cap then return nil end
    -- The captured count does not become an inventory receipt or batch size.
    -- No historical reagent rows are used for this ONE manual action.
    return {kind="craft",profession=key,skill=skill,skillTarget=math.min(300,skill+1),
        recipe=before.name,recipeID=recipeID,liveRecipeName=before.name,
        p1OneCraft=true,p1LiveOneCraft=true,
        p1NextAction="Open the current profession window and manually craft ONE "..
           before.name.." (RecipeID "..tostring(recipeID).."). Confirm the actual "..
           "skill and received items, then refresh Planner. "..
           "No automatic crafting, batch count or bulk material estimate is authorized.",
        p1MaterialStates={},materials={},remainingCrafts=1,
        craftCountQualified=false,craftEstimateEvidenceStatus="UNVERIFIED",
        liveCraftObservation={recipeID=recipeID,difficulty=grade.token,
           craftableCountObserved=count.count,panelToken=before.panelToken,
           panelRevision=before.panelRevision,
           clientSessionToken=before.clientSessionToken,
           observationQuality=before.observationQuality or "FULL_SESSION",
           volatileReadOnly=before.readOnlyObserved==true,
           nativeDispatchAllowed=false},
        dataset=advisoryAuthorityView(dataset),rawStep=advisoryAuthorityView(step),
        readOnly=true,plannerEligible=false,executionEligible=false,
        nativeDispatchAllowed=false,routeAuthorityEnabled=false}
end

local function remainingCrafts(step, currentSkill)
    if not step then return 0 end
    if step.sourceQualificationContract=="tailoring-25-31-source-planning-v1" or
        (step.sourceQualificationContract=="tailoring-40-50-forever-v1" or
        (step.sourceQualificationContract=="tailoring-50-77-forever-v1" or (step.sourceQualificationContract=="tailoring-77-102-wool-v1" or (step.sourceQualificationContract=="tailoring-102-107-source-v1" or (step.sourceQualificationContract=="tailoring-107-125-source-v1" or (step.sourceQualificationContract=="tailoring-125-225-source-v1" or step.sourceQualificationContract=="tailoring-225-300-source-v1")))))) then
        if (step.sourceQualificationContract=="tailoring-40-50-forever-v1" or
        (step.sourceQualificationContract=="tailoring-50-77-forever-v1" or (step.sourceQualificationContract=="tailoring-77-102-wool-v1" or (step.sourceQualificationContract=="tailoring-102-107-source-v1" or (step.sourceQualificationContract=="tailoring-107-125-source-v1" or (step.sourceQualificationContract=="tailoring-125-225-source-v1" or step.sourceQualificationContract=="tailoring-225-300-source-v1")))))) then
            return JLP:GetModule("TailoringRecipeQualification"):ScenarioCrafts(step,currentSkill,step.skillTarget)
        end
        return math.max(0,31-math.max(25,currentSkill))
    end
    if step.historicalEstimateSkillTarget then
        return math.max(0,math.ceil(step.expectedCrafts*(step.skillTarget-math.max(step.skillMin,currentSkill))/
            (step.historicalEstimateSkillTarget-step.skillMin)))
    end
    local total = tonumber(step.expectedCrafts) or 0
    local a = tonumber(step.skillMin) or 0
    local b = tonumber(step.skillTarget) or a
    local current = math.max(a, tonumber(currentSkill) or a)
    if current <= a then return total end
    if current >= b then return 0 end
    local span = math.max(1, b - a)
    local remaining = b - current
    return math.max(1, math.ceil(total * remaining / span))
end

local function telemetryEstimate(key, step, fromSkill, toSkill, staticCrafts, useLiveDifficulty)
    if not step then return staticCrafts or 0, nil end
    local a = tonumber(step.skillMin) or 0
    local b = tonumber(step.skillTarget) or a
    local startSkill = math.max(a, tonumber(fromSkill) or a)
    local endSkill = math.min(b, tonumber(toSkill) or b)
    local remainingSkill = math.max(0, endSkill - startSkill)
    local total = math.max(0, tonumber(step.expectedCrafts) or 0)
    local span = math.max(1, b - a)
    local staticRate = total > 0 and math.min(1, span / total) or 1
    local telemetry = JLP:GetModule("RecipeTelemetry")
    if telemetry and telemetry.GetPlannerEstimate then
        local currentDifficulty
        if useLiveDifficulty then
            local difficulty = JLP:GetModule("RecipeDifficulty")
            if difficulty and difficulty.GetForRecipe then currentDifficulty = difficulty:GetForRecipe(key, nil, step.recipe) end
        end
        local estimate = telemetry:GetPlannerEstimate(key, step.recipe, staticCrafts or 0, remainingSkill, staticRate, startSkill, endSkill, currentDifficulty)
        if estimate then return tonumber(estimate.remainingCrafts) or staticCrafts or 0, estimate end
    end
    return staticCrafts or 0, nil
end

-- Shared, side-effect-free telemetry calculation used by the production Planner
-- and the research shadow parity layer.  Keeping the adaptive math behind the
-- production Planner boundary prevents research from reimplementing or drifting
-- from the live craft-count algorithm.  Callers are still responsible for
-- deciding whether the returned telemetry provenance is authoritative for their
-- own surface.
function Planner:GetTelemetryCraftEstimate(key, step, fromSkill, toSkill, staticCrafts, useLiveDifficulty)
    return telemetryEstimate(key, step, fromSkill, toSkill, staticCrafts, useLiveDifficulty)
end

local function normalizeScope(scope)
    if scope == "next_trainer" or scope == "to_300" then return scope end
    return "current"
end

local function scopeLabel(scope)
    scope = normalizeScope(scope)
    if scope == "next_trainer" then return "To Next Trainer" end
    if scope == "to_300" then return "To 300" end
    return "Current Segment"
end

local function craftsForRange(key, step, fromSkill, toSkill, liveSkill)
    if not step then return 0, nil, 0 end
    if key=="TAILORING" and (step.sourceQualificationContract=="tailoring-40-50-forever-v1" or
        (step.sourceQualificationContract=="tailoring-50-77-forever-v1" or (step.sourceQualificationContract=="tailoring-77-102-wool-v1" or (step.sourceQualificationContract=="tailoring-102-107-source-v1" or (step.sourceQualificationContract=="tailoring-107-125-source-v1" or (step.sourceQualificationContract=="tailoring-125-225-source-v1" or step.sourceQualificationContract=="tailoring-225-300-source-v1")))))) then
        local crafts=JLP:GetModule("TailoringRecipeQualification"):ScenarioCrafts(step,fromSkill,toSkill)
        return crafts,{source=step.craftCountAuthority,remainingCrafts=crafts,estimated=true},crafts
    end
    if key=="TAILORING" and step.sourceQualificationContract=="tailoring-25-31-source-planning-v1" then
        local crafts=math.max(0,math.min(31,toSkill)-math.max(25,fromSkill))
        return crafts,{source="USER_APPROVED_ORANGE_100_SCENARIO",remainingCrafts=crafts,estimated=true},crafts
    end
    local a = tonumber(step.skillMin) or 0
    local b = tonumber(step.skillTarget) or a
    local total = tonumber(step.expectedCrafts) or 0
    local startSkill = math.max(a, tonumber(fromSkill) or a)
    local endSkill = math.min(b, tonumber(toSkill) or b)
    if endSkill <= startSkill then return 0, nil, 0 end
    local span = math.max(1, (step.historicalEstimateSkillTarget or b) - a)
    local covered = endSkill - startSkill
    local staticCrafts = math.max(1, math.ceil(total * covered / span))
    local adaptiveCrafts, estimate = telemetryEstimate(key, step, startSkill, endSkill, staticCrafts, tonumber(liveSkill) ~= nil and startSkill == tonumber(liveSkill))
    return adaptiveCrafts, estimate, staticCrafts
end

local function supportsAH(source)
    return source == "auction" or source == "disenchant-or-auction"
end

local function ownedState(itemID)
    local inventory = JLP:GetModule("Inventory")
    if inventory and inventory.GetOwned then return inventory:GetOwned(itemID) end
    -- Without an Inventory observation the guide cannot assert an actual
    -- shortfall; do not silently promote an API fallback to stock authority.
    return { itemID=tonumber(itemID), bags=0, bank=0, total=0,
        bagKnown=false,bankKnown=false,inventoryEvidence="UNAVAILABLE" }
end

-- Expands a nested crafted-recipe definition into a read-only material-state
-- tree. This is backward-compatible with the legacy one-level `craftedFrom`
-- shape and is only exercised when a caller explicitly supplies `craftedRecipe`.
local function craftedRecipeState(node, outputNeeded, resolver, depth, active, reserveStock, allocation, outputItemID)
    if type(node) ~= "table" then return nil end
    depth = tonumber(depth) or 0
    if depth > 12 then return { resolved=false, status="max-recursion-depth", materials={} } end
    local token = tostring(outputItemID or node.producerStepIndex or node.recipe or node.name or depth)
    active = active or {}
    if active[token] then return { resolved=false, status="dependency-cycle", materials={} } end
    active[token] = true

    local outputPerCraft = math.max(1, tonumber(node.outputPerCraft) or 1)
    local needed = math.max(0, tonumber(outputNeeded) or 0)
    local craftsNeeded = needed > 0 and math.ceil(needed / outputPerCraft) or 0
    local sharedPreparation=false
    if allocation then
        local id=tonumber(outputItemID or node.itemID)
        local production=id and allocation.production[id]
        sharedPreparation=id and allocation.used[id]==true or false
        craftsNeeded=not sharedPreparation and production and production.crafts or 0
        if production and id then allocation.used[id]=true end
    end
    local state = {
        contract = node.contract or "recursive-crafted-recipe-node-v1",
        itemID = node.itemID,
        name = node.name,
        recipe = node.recipe,
        recipeID = node.recipeID,
        producerStepIndex = node.producerStepIndex,
        outputPerCraft = outputPerCraft,
        outputNeeded = needed,
        craftsNeeded = craftsNeeded,
        producedOutput = craftsNeeded * outputPerCraft,
        yieldStatus = node.yieldStatus,
        promotionStatus = node.promotionStatus,
        currentBuildObserved = node.currentBuildObserved == true,
        observedBuild = node.observedBuild,
        currentBuild = node.currentBuild,
        resolved = node.resolved ~= false,
        materials = {},
        readOnly = true,
        plannerEligible = false,
        sharedPreparation = sharedPreparation,
    }

    if allocation and not allocation.resolved then
        state.resolved=false;state.status=allocation.reason;active[token]=nil;return state
    end
    if sharedPreparation then active[token]=nil;return state end

    for _, reagent in ipairs(node.materials or {}) do
        local perCraft = math.max(0, tonumber(reagent.quantity) or 0)
        local required = perCraft * craftsNeeded
        local storage = reserveStock and reserveStock(reagent.itemID,required) or ownedState(reagent.itemID)
        local owned = tonumber(storage.total) or 0
        local missing = math.max(0, required - owned)
        local row = {
            itemID = reagent.itemID,
            name = reagent.name,
            source = reagent.source or "unknown",
            perCraft = perCraft,
            required = required,
            owned = owned,
            missing = missing,
            storage = storage,
            relation = reagent.relation,
            producerStepIndex = reagent.producerStepIndex,
            acquisition = reagent.acquisition,
            currentBuildCorroborated = reagent.currentBuildCorroborated == true,
            exactSamples = reagent.exactSamples,
        }
        if reagent.craftedRecipe and missing > 0 then
            row.craftedRecipe = craftedRecipeState(reagent.craftedRecipe, missing, resolver, depth + 1, active, reserveStock, allocation, reagent.itemID)
            if not row.craftedRecipe or row.craftedRecipe.resolved == false then state.resolved = false end
        elseif reagent.craftedFrom and missing > 0 and allocation then
            local rawNode={itemID=reagent.itemID,name=reagent.name,recipe=reagent.name,outputPerCraft=1,materials={reagent.craftedFrom}}
            row.craftedRecipe=craftedRecipeState(rawNode,missing,resolver,depth+1,active,reserveStock,allocation,reagent.itemID)
            if not row.craftedRecipe or row.craftedRecipe.resolved==false then state.resolved=false end
        elseif resolver and missing ~= nil and missing > 0 and supportsAH(row.source) then
            row.ah = resolver:GetFulfillmentCost(reagent.itemID, missing)
        end
        state.materials[#state.materials + 1] = row
    end

    active[token] = nil
    return state
end

-- K102-01: Mooncloth 278-280 alone has an additional availability gate.
-- Current-session recipe learned/non-gray/bags do NOT establish that a timed
-- recipe is craftable at its required location. Do not reuse cache as readiness.
-- API shapes: GetRecipeInfo.disabled/craftable; C_Spell.GetSpellCooldown
-- startTime/duration/isEnabled; GetRecipeRequirements type/met/name.
-- In an unavailable/ambiguous API environment this ONLY blocks a read-only
-- ONE suggestion, never a source reference or native crafting action.
local function p1MoonclothAvailability()
    local api=type(C_TradeSkillUI)=="table" and C_TradeSkillUI or nil
    local profession=JLP:GetModule("ProfessionAPI")
    -- A successfully opened Tailoring panel must own this recipe observation.
    if not profession or type(profession.GetOpenProfessionKey)~="function" or
        profession:GetOpenProfessionKey()~="TAILORING" then
        return false,"VERIFY: Open the current character's Tailoring profession panel and check Mooncloth SpellID 18560 before an immediate craft."
    end
    if not api or type(api.GetRecipeInfo)~="function" then
        return false,"VERIFY: Mooncloth recipe availability is not exposed; check disabled/craftable state in the live Tailoring panel."
    end
    local ok,info=pcall(api.GetRecipeInfo,18560)
    if not ok or type(info)~="table" or
        (info.recipeID~=nil and tonumber(info.recipeID)~=18560) then
        return false,"VERIFY: Mooncloth SpellID 18560 availability could not be attested in the current Tailoring panel."
    end
    if info.disabled==true or info.craftable==false then
        local reason=type(info.disabledReason)=="string" and info.disabledReason or nil
        if reason and #reason>140 then reason=reason:sub(1,140) end
        return false,"VERIFY: Mooncloth is explicitly disabled/not craftable in the current Tailoring panel"..
            (reason and (" ("..reason..")") or "").."; resolve the recipe requirement or wait for availability."
    end
    -- Optional fields are not proof of a positive availability state.
    if info.disabled~=false or info.craftable~=true then
        return false,"VERIFY: Confirm Mooncloth is enabled and craftable in the current Tailoring panel (unreported availability is unknown)."
    end
    local spell=type(C_Spell)=="table" and C_Spell or nil
    if not spell or type(spell.GetSpellCooldown)~="function" or type(GetTime)~="function" then
        return false,"VERIFY: Current Mooncloth cooldown cannot be confirmed; inspect the recipe cooldown before crafting."
    end
    local coolOK,cool=pcall(spell.GetSpellCooldown,18560)
    if not coolOK or type(cool)~="table" then
        return false,"VERIFY: Current Mooncloth cooldown is unknown; inspect the recipe cooldown before crafting."
    end
    if cool.isEnabled==false then
        return false,"VERIFY: Mooncloth cooldown is currently disabled/on hold; inspect the live recipe before crafting."
    end
    local start,duration=tonumber(cool.startTime),tonumber(cool.duration)
    local timeOK,now=pcall(GetTime)
    now=timeOK and tonumber(now) or nil
    if cool.isEnabled~=true or not start or not duration or not now or
        start<0 or duration<0 or now~=now then
        return false,"VERIFY: Mooncloth cooldown values cannot be validated; inspect the live recipe before crafting."
    end
    local remaining=start+duration-now
    if duration>0 and start>0 and remaining>0 then
        return false,"WAIT: Mooncloth cooldown is active (approximately "..
            tostring(math.ceil(remaining)).." seconds remaining per current client observation); check again before ONE craft."
    end
    -- A completed cooldown does not attest the required crafting area.
    if type(api.GetRecipeRequirements)~="function" then
        return false,"VERIFY: Mooncloth crafting location/requirements are unverified; check the required area in the Tailoring panel."
    end
    local reqOK,requirements=pcall(api.GetRecipeRequirements,18560)
    if not reqOK or type(requirements)~="table" then
        return false,"VERIFY: Mooncloth crafting-location requirements could not be read; verify them in the Tailoring panel."
    end
    local foundLocation=false
    for _,requirement in ipairs(requirements) do
        if type(requirement)=="table" and
            (tonumber(requirement.type)==2 or tonumber(requirement.type)==0) then
            foundLocation=true
            if requirement.met~=true then
                local label=type(requirement.name)=="string" and requirement.name or "required crafting area"
                return false,"VERIFY: Mooncloth requires "..label..
                    "; its location requirement is not currently confirmed. Travel manually only after identifying a valid location."
            end
        end
    end
    if not foundLocation then
        return false,"VERIFY: Mooncloth's crafting location is not attested by the current client; verify the required area (no inferred waypoint)."
    end
    return true,nil
end

-- P1 0.34.104: Spell22902 has a DB70450 required spell focus (2250),
-- but no current Forever in-client station evidence. It is a distinct recipe
-- from Mooncloth18560 and MUST NOT inherit Mooncloth cooldown semantics.
-- Only positive current-panel recipe and location attestations allow ONE.
local function p1MoonclothRobeAvailability()
    local api=type(C_TradeSkillUI)=="table" and C_TradeSkillUI or nil
    local profession=JLP:GetModule("ProfessionAPI")
    if not profession or type(profession.GetOpenProfessionKey)~="function" or
        profession:GetOpenProfessionKey()~="TAILORING" then
        return false,"VERIFY: Open the current Tailoring panel and check Mooncloth Robe SpellID 22902 and its crafting station."
    end
    if not api or type(api.GetRecipeInfo)~="function" then
        return false,"VERIFY: Mooncloth Robe recipe availability is not exposed in the current Tailoring panel."
    end
    local ok,info=pcall(api.GetRecipeInfo,22902)
    if not ok or type(info)~="table" or
        (info.recipeID~=nil and tonumber(info.recipeID)~=22902) then
        return false,"VERIFY: Mooncloth Robe SpellID 22902 has no verified current-panel availability."
    end
    if info.disabled==true or info.craftable==false then
        return false,"VERIFY: Mooncloth Robe is disabled or not craftable; check the actual pattern, station and recipe requirements."
    end
    if info.disabled~=false or info.craftable~=true then
        return false,"VERIFY: Mooncloth Robe enabled/craftable state is unknown."
    end
    if type(api.GetRecipeRequirements)~="function" then
        return false,"VERIFY: Mooncloth Robe crafting-station requirement (DB focus 2250) is unverified."
    end
    local got,requirements=pcall(api.GetRecipeRequirements,22902)
    if not got or type(requirements)~="table" then
        return false,"VERIFY: Mooncloth Robe crafting-station requirement could not be checked."
    end
    local locationConfirmed=false
    for _,requirement in ipairs(requirements) do
        if type(requirement)=="table" then
            if requirement.met==false then
                return false,"VERIFY: Mooncloth Robe recipe requirement "..
                    tostring(requirement.name or "crafting station").." is not met."
            end
            if tonumber(requirement.type)==2 or tonumber(requirement.type)==0 then
                if requirement.met~=true then
                    return false,"VERIFY: Mooncloth Robe crafting station is not confirmed in the current panel."
                end
                locationConfirmed=true
            end
        end
    end
    if not locationConfirmed then
        return false,"VERIFY: Mooncloth Robe crafting station is unknown (DB focus 2250 is not a waypoint)."
    end
    return true,nil
end

-- P1: optional and fail-closed SINGLE-CRAFT fallback for scoped Tailoring windows.
-- The same-build knowledge observation and NON-GRAY client difficulty must both
-- be affirmative. A raw DB cutoff or an external minimum never suffices.
-- This does NOT grant any native action, recipe authority or bulk craft count.
local function p1TailoringOneCraft(key,dataset,skill,strategy,maxSkill)
    -- P1-QAFix2: never return Tailoring-specific rank advice for another
    -- profession or outside this Tailoring interval, even if maxSkill is unknown.
    if key~="TAILORING" or skill<137 or skill>=300 or
        type(dataset)~="table" or type(dataset.progressionCandidates)~="table" then return nil,nil end
    -- The current profession rank is a hard cap for *next skillpoint* advice.
    -- A known non-gray recipe does not make 150 -> 151 possible at 150/150.
    local cap=tonumber(maxSkill) or 0
    if cap<=0 then
        return nil,"Verify the current profession rank and skill cap before another skill-up."
    end
    if skill>=cap then
        return nil,"Train the next profession rank before attempting another skill-up."
    end
    local runtimeBuild=JLP:GetModule("ClientBuildInfo")
    local activeBuild=runtimeBuild and runtimeBuild.GetBuildNumber and runtimeBuild:GetBuildNumber()
    -- Only the source-audited 270-300 intervals get a stricter fresh-session
    -- identity/build gate; older Tailoring evidence semantics are untouched.
    if skill>=270 then
        local current=JLP:GetModule("ProfessionAPI")
        current=current and current.Get and current:Get("TAILORING")
        if type(current)~="table" or current.cached==true or current.key~="TAILORING" or
            tonumber(current.skill)~=skill or tonumber(current.maxSkill)~=cap or
            (current.skillLine~=nil and tonumber(current.skillLine)~=197) or
            (current.professionEnum~=nil and tonumber(current.professionEnum)~=((JLP:GetModule("ProfessionRegistry") or {}).GetProfessionEnum and JLP:GetModule("ProfessionRegistry"):GetProfessionEnum("TAILORING") or 7)) or
            (type(activeBuild)~="number" or activeBuild<=0 or activeBuild~=math.floor(activeBuild)) then
            return nil,"Verify current Tailoring character, profession and skill/rank before ONE manual craft in 270-300. A live recipe observation is required; a historical build is not permission."
        end
    end
    local cache=JLP:GetModule("KnowledgeCache")
    local difficulty=JLP:GetModule("RecipeDifficulty")
    if not cache or type(cache.GetRecipeKnowledgeState)~="function" or
        not difficulty or type(difficulty.GetForRecipe)~="function" then
        return nil,"Open your Tailoring profession window to confirm learned recipes and current difficulty."
    end
    local offers={};local missing={};local preparationGaps={};local availabilityGaps={}
    local preferred=selectedStrategy(strategy)
    local inventory=JLP:GetModule("Inventory")
    local priceResolver=JLP:GetModule("PriceResolver")
    -- Only an observed BAG count makes a direct reagent immediately usable.
    -- Bank snapshots and raw inputs are distinct advisory prerequisites.
    -- P1-QAFix3: only explicit true is a live BAG observation; nil, false
    -- and malformed inventory flags are unknown, regardless of numeric count.
    local function stock(id)
        local v=inventory and inventory.GetOwned and inventory:GetOwned(id)
        return math.max(0,tonumber(v and v.bags) or 0),
            math.max(0,tonumber(v and v.bank) or 0),
            v and v.bagKnown==true,v and v.bankKnown==true
    end
    local identityConflictRecipe=nil
    local function observedLearned(recipe,id)
        local v=cache:GetRecipeKnowledgeState(recipe,key)
        -- F1 cross-profession: same-build saved positives are not advisory
        -- authority when an explicit transient name/SpellID conflict exists.
        -- Do not impose Blacksmithing's session-freshness policy on Tailoring.
        if type(v)=="table" and v.sessionIdentityConflict==true then
            identityConflictRecipe=recipe
            return false
        end
        -- An exact fresh learned=false supersedes a saved same-build positive
        -- for read-only ONE advice. It is not missing-list inference, and does
        -- not introduce a global session-freshness requirement for Tailoring.
        if type(v)=="table" and v.sessionExplicitUnlearned==true and
            tonumber(v.recipeID)==id then return false end
        return type(v)=="table" and v.knowledge=="known" and
            v.currentBuildObserved==true and tonumber(v.currentBuild)==tonumber(activeBuild) and
            tonumber(v.observedBuild)==tonumber(activeBuild) and tonumber(v.recipeID)==id
    end
    -- DB70450 recipe identity/reagents: 3839 consumes four Silk Cloth per bolt.
    -- This mapping grants no trainer access, recipe knowledge or native action.
    local intermediate={
        [4305]={recipe="Bolt of Silk Cloth",recipeID=3839,inputItemID=4306,
            inputName="Silk Cloth",quantity=4},
        [2997]={recipe="Bolt of Woolen Cloth",recipeID=2964,inputItemID=2592,
            inputName="Wool Cloth",quantity=3},
        -- P0.2U: DB70450 Spell18401 reagent14047x5 -> output14048.
        -- Only a current-build observed learned recipe can advise preparation.
        [14048]={recipe="Bolt of Runecloth",recipeID=18401,inputItemID=14047,
            inputName="Runecloth",quantity=5},
    }
    local function prerequisite(row)
        for _,m in ipairs(row.materials) do
            local need=math.max(0,tonumber(m.quantity) or 0)
            local bags,bank,bagKnown,bankKnown=stock(m.itemID)
            local deficit=math.max(0,need-bags)
            local name=tostring(m.name or m.itemID)
            if not bagKnown then
                return {kind="verify",itemID=m.itemID,recipe=row.recipe,
                    text="Verify live bag quantity of "..name.." before ONE "..row.recipe.." craft; cached inventory is not live bags."}
            end
            if deficit>0 then
                if bank>0 and bankKnown then
                    return {kind="bank",itemID=m.itemID,quantity=math.min(deficit,bank),recipe=row.recipe,
                        text="Retrieve "..tostring(math.min(deficit,bank)).." x "..name.." from current-character bank (cached bank count; verify at the bank), then recheck bags for ONE "..row.recipe.." craft."}
                end
                local mid=intermediate[tonumber(m.itemID)]
                if mid and type(m.craftedFrom)=="table" and
                    tonumber(m.craftedFrom.itemID)==mid.inputItemID and
                    tonumber(m.craftedFrom.quantity)==mid.quantity then
                    local rawBags,rawBank,rawKnown,rawBankKnown=stock(mid.inputItemID)
                    local rawNeed=deficit*mid.quantity
                    if not observedLearned(mid.recipe,mid.recipeID) then
                        return {kind="verify",recipe=row.recipe,itemID=m.itemID,recipeID=mid.recipeID,
                            text="Verify learned "..mid.recipe.." (SpellID "..mid.recipeID..") in this character's current-build Tailoring window before preparing "..name.." for ONE "..row.recipe.." craft."}
                    end
                    if not rawKnown then
                        return {kind="verify",recipe=row.recipe,itemID=mid.inputItemID,
                            text="Verify live bags contain "..rawNeed.." x "..mid.inputName.." for "..mid.recipe.."; historical inventory is not sufficient."}
                    end
                    if rawBags>=rawNeed then
                        return {kind="prepare",recipe=row.recipe,recipeID=mid.recipeID,
                            itemID=m.itemID,quantity=deficit,
                            text="Prepare "..deficit.." x "..mid.recipe.." (SpellID "..mid.recipeID..") using "..rawNeed.." x "..mid.inputName.."; then recheck finished "..name.." in bags before ONE "..row.recipe.." craft. Manual action only."}
                    end
                    if rawBankKnown and rawBank>0 then
                        return {kind="bank",recipe=row.recipe,itemID=mid.inputItemID,
                            quantity=math.min(rawNeed-rawBags,rawBank),
                            text="Retrieve "..math.min(rawNeed-rawBags,rawBank).." x "..mid.inputName.." from cached current-character bank, then prepare "..mid.recipe.."; recheck actual bags."}
                    end
                    return {kind="materials",recipe=row.recipe,itemID=mid.inputItemID,
                        quantity=rawNeed-rawBags,
                        text="Obtain "..(rawNeed-rawBags).." x "..mid.inputName.." for "..mid.recipe.." before ONE "..row.recipe.." craft; no verified AH stock or bulk budget."}
                end
                if m.source=="vendor" then
                    return {kind="vendor",recipe=row.recipe,itemID=m.itemID,quantity=deficit,
                        text="Acquire "..deficit.." x "..name.." from a vendor before ONE "..row.recipe.." craft; vendor identity, stock and price unverified. Recheck bags after purchase."}
                end
                if not bankKnown then
                    return {kind="verify",recipe=row.recipe,itemID=m.itemID,
                        text="Check current-character bank cache and acquire "..deficit.." x "..name.." if absent; confirm live bags before ONE "..row.recipe.." craft."}
                end
                return {kind="materials",recipe=row.recipe,itemID=m.itemID,quantity=deficit,
                    text="Obtain "..deficit.." x "..name.." before ONE "..row.recipe.." craft"..
                        (preferred=="self_found" and " (Self-found: no AH)." or "; AH availability and prices unverified.")}
            end
        end
        return nil
    end
    for _,row in ipairs(dataset.progressionCandidates) do
        local id=tonumber(row.recipeID)
        local min=tonumber(row.requiredSkill)
        local gray=tonumber(row.rawGreyThreshold)
        -- P0.2U: DB70450 lacks a proven learning minimum for Runecloth Belt.
        -- Current-build observed learned identity supersedes this *metadata*
        -- gap for ONE advisory craft; it cannot authorize a bulk plan.
        local currentBuildOnlyBelt=id==18402 and
            (row.sourceQualificationContract=="tailoring-225-230-runecloth-belt-evidence-p02u-v1" or
             row.sourceQualificationContract=="tailoring-230-240-runecloth-belt-evidence-p02v-v1" or
             row.sourceQualificationContract=="tailoring-240-245-runecloth-belt-evidence-p02w-v1")
        local currentBuildOnlyCloak=id==18420 and
            (row.sourceQualificationContract=="tailoring-245-250-brightcloth-cloak-evidence-p02w-v1" or
             row.sourceQualificationContract=="tailoring-250-260-brightcloth-cloak-evidence-p02x-v1" or
             row.sourceQualificationContract=="tailoring-260-262-brightcloth-cloak-evidence-p02y-v1")
        local currentBuildOnlyPants=id==18438 and
            row.sourceQualificationContract=="tailoring-262-270-runecloth-pants-evidence-p02y-v1"
        local audited270300=(row.sourceQualificationContract==
            "tailoring-270-278-runecloth-pants-field-db70450-v1" or
            row.sourceQualificationContract=="tailoring-278-280-mooncloth-field-db70450-v1" or
            row.sourceQualificationContract=="tailoring-280-293-mooncloth-progression-evidence-db70450-v1" or
            row.sourceQualificationContract=="tailoring-293-300-mooncloth-robe-progression-evidence-db70450-v1")
        -- Do not silently carry an earlier 262-270 advisory into this newly
        -- source-scoped interval; only its own live-confirmed candidate counts.
        local inAuditedWindow=(skill<270 and not audited270300) or
            (skill>=270 and skill<300 and audited270300 and
             skill>=tonumber(row.skillMin) and skill<tonumber(row.skillTarget))
        if id and inAuditedWindow and (min or currentBuildOnlyBelt or currentBuildOnlyCloak or
            currentBuildOnlyPants or audited270300) and gray and tonumber(row.rawDifficultySourceBuild)==70450 and
            tonumber(row.materialSourceBuild or row.rawDifficultySourceBuild)==70450 and
            type(row.materials)=="table" and #row.materials>0 and
            tonumber(row.outputItemID) and skill<gray then
            local freshOK=true
            if audited270300 then
                local currentState=cache:GetRecipeKnowledgeState(row.recipe,key)
                freshOK=type(currentState)=="table" and currentState.sessionLearnedObserved==true and
                    currentState.sessionIdentityConflict~=true and
                    currentState.sessionExplicitUnlearned~=true
            end
            -- A documented *actual* minimum (if later supplied by the current
            -- character's evidence source) may not exceed current skill.
            local verifiedMinimum=tonumber(row.requiredSkill)
            local minAuthority=row.requiredSkillAuthority
            if audited270300 and verifiedMinimum and
                (minAuthority=="CLIENT_OBSERVED_CURRENT_BUILD" or
                 minAuthority=="CURRENT_BUILD_VERIFIED") and
                (verifiedMinimum>skill or verifiedMinimum>=300) then
                freshOK=false
            end
            if freshOK and observedLearned(row.recipe,id) then
                local live=difficulty:GetForRecipe(key,id,row.recipe)
                if live and live.confidence=="verified" and
                    (live.token=="orange" or live.token=="yellow" or live.token=="green") and
                    live.canSkillUp~=false then
                    -- K102-01: positive Mooncloth availability is not implied
                    -- by learned state, non-gray difficulty, or bag contents.
                    local available,availabilityText=true,nil
                    if audited270300 and id==18560 then
                        available,availabilityText=p1MoonclothAvailability()
                    elseif audited270300 and id==22902 then
                        available,availabilityText=p1MoonclothRobeAvailability()
                    end
                    if not available then
                        availabilityGaps[#availabilityGaps+1]={text=availabilityText,recipe=row.recipe,recipeID=id}
                    else
                    local pending=prerequisite(row)
                    if pending then
                        preparationGaps[#preparationGaps+1]={row=row,need=pending,
                            score=({orange=30,yellow=20,green=10})[live.token] or 0}
                    else
                        local score=0
                        if preferred=="fastest" then
                            score=({orange=30,yellow=20,green=10})[live.token] or 0
                        end
                        -- No missing direct reagents: zero additional material price.
                        -- All three strategies may choose only an immediately
                        -- bag-ready advisory recipe, never infer stock from AH.
                        offers[#offers+1]={row=row,live=live,score=score,priceTrusted=true}
                    end
                    end -- Mooncloth availability gate
                else missing[#missing+1]=row.recipe..": live non-gray difficulty not observed" end
            else
                missing[#missing+1]=row.recipe..": current-build learned state/recipe identity not observed"
            end
        end
    end
    if preferred=="economical" and #offers>1 then
        local allTrusted=true
        for _,offer in ipairs(offers) do
            if not offer.priceTrusted then allTrusted=false;break end
        end
        if not allTrusted then
            local inventory=JLP:GetModule("Inventory")
            for _,offer in ipairs(offers) do
                local ownedCount=0
                for _,m in ipairs(offer.row.materials) do
                    local o=inventory and inventory.GetOwned and inventory:GetOwned(m.itemID)
                    if o and (tonumber(o.bags) or 0)>=(tonumber(m.quantity) or 0) then
                        ownedCount=ownedCount+1
                    end
                end
                offer.score=ownedCount
            end
        end
    end
    if #offers==0 then
        if identityConflictRecipe then
            return nil,"Conflicting Tailoring recipe identities for "..tostring(identityConflictRecipe)..
                ". Reopen the current character's Tailoring window and verify a unique learned SpellID before ONE manual craft; saved positives remain historical."
        end
        if #availabilityGaps>0 then
            local gap=availabilityGaps[1]
            return nil,gap.text,{kind="verify",recipe=gap.recipe,recipeID=gap.recipeID,
                text=gap.text}
        end
        if #preparationGaps>0 then
            table.sort(preparationGaps,function(a,b)
                if a.score~=b.score then return a.score>b.score end
                return a.row.recipeID<b.row.recipeID
            end)
            local pending=preparationGaps[1].need
            return nil,pending.text.." Recalculate after each prerequisite; total crafts UNKNOWN.",pending
        end
        if skill>=280 and skill<300 then
            return nil,"No fresh, unique, non-gray and currently available Tailoring recipe "..
                "is qualified for 280-300. Verify Mooncloth SpellID18560 cooldown/location "..
                "or Mooncloth Robe SpellID22902 pattern, crafting station, rank, live "..
                "reagent bags and learned identity. A physical Mooncloth reagent is "..
                "not implied by Felcloth or a known recipe. Skill-up rates, future "..
                "craft count and strategy/material budgets remain UNKNOWN."
        end
        if skill>=270 and skill<280 then
            return nil,"No fresh, unique, non-gray Tailoring recipe is verified for 270-280. "..
                "Open this character's Tailoring window; confirm Runecloth Pants SpellID18438 "..
                "or Mooncloth SpellID18560, exact learned state, difficulty and actual bag materials. "..
                "Pattern references and DB70450 difficulty do not establish learning, "..
                "a skill-up, or a craft budget."
        end
        if skill>=262 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 262-270. "..
                "Verify Runecloth Pants SpellID 18438 in the current Tailoring window, "..
                "pattern14491 actual access and learned-state, non-gray difficulty, rank "..
                "and live bag reagents. DB70450 pattern RequiredSkillRank240 is item metadata, "..
                "not observed learning; historical 35 crafts and material budgets UNKNOWN."
        end
        if skill>=260 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 260-262. "..
                "Verify Brightcloth Cloak SpellID 18420 in the current Tailoring window, "..
                "actual pattern access, learned-state, non-gray difficulty, rank and live bags. "..
                "Historical 25 crafts are NOT a qualified budget."
        end
        if skill>=250 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 250-260. "..
                "Verify Brightcloth Cloak SpellID 18420 in the current Tailoring window, "..
                "confirm pattern access and actual learned state, non-gray difficulty, Artisan rank "..
                "and live bag reagents. DB70450 item14484 RequiredSkillRank230 is pattern ITEM metadata, "..
                "not verified learning access. Historical 25 crafts and material budgets UNKNOWN."
        end
        if skill>=245 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 245-250. "..
                "Verify Brightcloth Cloak SpellID 18420 in this character's current Tailoring window, "..
                "learn the pattern if actually accessible, and verify non-gray difficulty, Artisan rank "..
                "and live bag reagents. DB70450 pattern-item 14484 has RequiredSkillRank230, "..
                "NOT verified recipe learning. Historical 25 crafts and budgets are UNKNOWN."
        end
        if skill>=240 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 240-245. "..
                "Verify Runecloth Belt SpellID 18402, actual learned state, non-gray difficulty, "..
                "Artisan rank and live bags. DB70450 raw225/255 is not a learning minimum; "..
                "historical 32 crafts and material budgets are UNKNOWN."
        end
        if skill>=230 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 230-240. "..
                "Verify Runecloth Belt SpellID 18402 in the current Tailoring window, "..
                "its actual learning and non-gray difficulty, Artisan rank and live bags. "..
                "DB70450 raw225/255 is not a learning minimum; historical 32 crafts "..
                "and material budgets are UNKNOWN; use an actually accessible recipe."
        end
        if skill>=225 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 225-230. "..
                "Verify Runecloth Belt SpellID 18402 in the current Tailoring window, "..
                "its actual learning and non-gray difficulty, Artisan rank and live bags. "..
                "DB70450 raw225/255 is not a learning minimum. Historical 32 crafts "..
                "and material budgets are UNKNOWN; choose a genuinely accessible recipe."
        end
        if skill>=220 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 220-225. "..
                "Verify Black Mageweave Headband SpellID 12072 (external unpinned min230), "..
                "current learned identity, non-gray difficulty and live bags. "..
                "Historical 32 crafts are UNKNOWN, not a craft budget."
        end
        if skill>=190 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 190-200. "..
                "Verify Crimson Silk Pantaloons SpellID 8799 (unconfirmed external min180/195) "..
                "or Black Mageweave Gloves SpellID 12053 (external min215). "..
                "Open the actual Tailoring panel and confirm learned spell identity and "..
                "non-gray difficulty; acquire or train a genuinely accessible alternative if needed. "..
                "Historical 27/12 craft budgets are UNKNOWN and not usable."
        end
        if skill>=180 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 180-190. "..
                "Verify Crimson Silk Pantaloons SpellID 8799 and its disputed min180/195; "..
                "confirm current-build learned state, non-gray difficulty and live bags. "..
                "Total crafts UNKNOWN."
        end
        if skill>=170 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 170-180. "..
                "Open Tailoring and verify Crimson Silk Vest SpellID 8791 (Wowhead Forever min185, "..
                "ForeverDB70425 min170), or learn an actually accessible alternative. "..
                "Verify live learned identity/difficulty before ONE manual craft; total crafts UNKNOWN."
        end
        if skill>=160 then
            return nil,"No current-build learned, non-gray Tailoring recipe is observed for 160-170. "..
                "Open Tailoring and verify a learned Small Silk Pack or Azure Silk Gloves, or acquire "..
                "and learn an actually accessible alternative. Azure Silk Cloak SpellID 8786 has "..
                "external minimum 175 (pattern item lists 140), not confirmed access at 160. "..
                "Verify spell identity and live difficulty before ONE manual craft; total crafts UNKNOWN."
        end
        return nil,"No qualified single-craft recipe is currently observed. Open Tailoring, learn or acquire "..
            "a documented recipe if missing (Gloves of Meditation via trainer; Azure Silk Gloves via vendor pattern), "..
            "then verify its identity and non-gray difficulty. Recheck at each skill; no bulk budget."
    end
    table.sort(offers,function(a,b)
        if a.score~=b.score then return a.score>b.score end
        return a.row.recipeID<b.row.recipeID
    end)
    local winner=offers[1]
    local recipe=winner.row
    local exposed=advisoryAuthorityView(recipe)
    return {kind="craft",profession=key,skill=skill,skillTarget=skill+1,
        recipe=recipe.recipe,recipeID=recipe.recipeID,recipeSource=recipe.recipeSource,
        materials=recipe.materials,rawStep=exposed,dataset=advisoryAuthorityView(dataset),
        remainingCrafts=1,staticRemainingCrafts=nil,expectedCrafts=nil,
        craftCountQualified=false,craftCountAuthority="NO_VERIFIED_TOTAL_CRAFTS",
        craftEstimateEvidenceStatus="UNVERIFIED",p1OneCraft=true,
        p1ObservedDifficulty=winner.live.token,p1ObservedCurrentBuild=(JLP:GetModule("ClientBuildInfo") and JLP:GetModule("ClientBuildInfo"):GetBuildNumber()),
        p1ObservedAccessOverridesExternalMinimum=skill<(tonumber(recipe.requiredSkill) or 0),
        p1SourceRequirement=recipe.sourceRequirement,
        skillEligibility={status="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
            progressionAllowed=true,progressionQualified=true,readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false},
        skillEligibilityStatus="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
        strategy=preferred,routeSelection={strategy=preferred,changed=true,
            reason="P1_OBSERVED_ONE_CRAFT_FALLBACK",selectedRecipe=recipe.recipe,
            candidateCount=#offers,qualifiedAlternatives=#offers},
        plannerEligible=false,readOnly=true,executionEligible=false,
        nativeDispatchAllowed=false,routeAuthorityEnabled=false},nil
end

-- P1-Blacksmithing-Access: only ONE current-character, current-build manual
-- advisory craft. Editorial 1-300 windows and raw difficulty are not recipe
-- learning minimums, craft rates, trainer sources or native rights.
local function p1BlacksmithOneCraft(key,dataset,profession,skill,maxSkill,strategy,step)
    if key~="BLACKSMITHING" or type(dataset)~="table" or
       dataset.contract~="blacksmithing-1-75-db70450-field-reference-v1" or
       dataset.readOnly~=true or dataset.referenceOnly~=true or
       tonumber(dataset.sourceBuild)~=70450 or type(step)~="table" or
       step.sourceQualificationContract~=dataset.contract then return nil,nil,nil end
    local function unresolved(reason,prerequisite)
        return nil,reason.." One manual craft only after rechecking; total skill-ups, future materials and prices UNKNOWN.",prerequisite
    end
    if type(profession)~="table" or profession.key~=key or profession.cached==true or
       (profession.skillLine~=nil and tonumber(profession.skillLine)~=164) or
       (profession.professionEnum~=nil and tonumber(profession.professionEnum)~=((JLP:GetModule("ProfessionRegistry") or {}).GetProfessionEnum and JLP:GetModule("ProfessionRegistry"):GetProfessionEnum("BLACKSMITHING") or 1)) or
       type(profession.skill)~="number" or profession.skill~=skill or
       skill~=skill or skill<1 or skill>=300 or type(profession.maxSkill)~="number" or
       profession.maxSkill~=maxSkill or maxSkill~=maxSkill or maxSkill<skill or maxSkill<=0 then
        return unresolved("Verify this character's current Blacksmithing identity, skill and rank; cached or conflicting state is not sufficient.")
    end
    if skill>=maxSkill then
        return unresolved("Verify and train the next Blacksmithing rank before another skill point; trainer and location are not yet verified.",
            {kind="train",text="Verify the next Blacksmithing rank with an actual trainer; no NPC is confirmed."})
    end
    local build=JLP:GetModule("ClientBuildInfo")
    local observedBuild=build and build.GetBuildNumber and build:GetBuildNumber() or nil
    if type(observedBuild)~="number" or observedBuild<=0 or observedBuild~=math.floor(observedBuild) then
        return unresolved("Verify the actual client build and current profession session before ONE manual craft.")
    end
    -- Never use a recipe with a documented required minimum >=300 to reach skill 300.
    -- Raw difficulty thresholds are not learning requirements.
    if tonumber(step.requiredSkill) and tonumber(step.requiredSkill)>=300 then
        return unresolved("Recorded learning minimum 300 or higher: reference only, not 1-300 progression.")
    end
    local id=tonumber(step.recipeID)
    if not id or not tonumber(step.outputItemID) or
       type(step.materials)~="table" or #step.materials==0 or
       tonumber(step.materialSourceBuild)~=70450 or
       tonumber(step.rawDifficultySourceBuild)~=70450 then
        return unresolved("Blacksmithing recipe or reagent source relation is incomplete; verify its DB fields.")
    end
    local cache=JLP:GetModule("KnowledgeCache")
    local observed=cache and cache.GetRecipeKnowledgeState and cache:GetRecipeKnowledgeState(step.recipe,key)
    if type(observed)=="table" and (observed.sessionIdentityConflict==true or observed.sessionExplicitUnlearned==true) then
        return unresolved("Conflicting or explicitly unlearned SpellID was observed for "..tostring(step.recipe)..
            "; reopen the current profession panel and confirm its unique numeric recipe identity.")
    end
    if type(observed)~="table" or observed.knowledge~="known" or
       observed.currentBuildObserved~=true or observed.sessionLearnedObserved~=true or
       tonumber(observed.currentBuild)~=observedBuild or
       tonumber(observed.observedBuild)~=observedBuild or tonumber(observed.recipeID)~=id then
        return unresolved("Open or refresh the current character's Blacksmithing profession window for a fresh-session learned confirmation of "..
            tostring(step.recipe).." (SpellID "..id.."); source AcquireMethod and trainer access are unverified.")
    end
    local difficulty=JLP:GetModule("RecipeDifficulty")
    local live=difficulty and difficulty.GetForRecipe and difficulty:GetForRecipe(key,id,step.recipe)
    if not live or live.confidence~="verified" or
       (live.token~="orange" and live.token~="yellow" and live.token~="green") or
       live.canSkillUp==false then
        return unresolved("Verify observed non-gray difficulty for learned "..tostring(step.recipe).."; DB difficulty bounds do not establish live skill-up potential.")
    end
    local inventory=JLP:GetModule("Inventory")
    if not inventory or type(inventory.GetOwned)~="function" then
        return unresolved("Verify current character live bag contents before crafting.")
    end
    local materialStates={}
    for _,m in ipairs(step.materials) do
        local qty=tonumber(m.quantity)
        if not tonumber(m.itemID) or not qty or qty<=0 or qty~=math.floor(qty) then
            return unresolved("Reagent identity or per-craft quantity is not qualified.")
        end
        local owned=inventory:GetOwned(m.itemID)
        if type(owned)~="table" or owned.bagKnown~=true or
           type(owned.bags)~="number" or owned.bags<0 then
            return unresolved("Verify live bag quantity of "..tostring(m.name or m.itemID).."; bank/cache is not a bag observation.",
                {kind="verify",itemID=m.itemID})
        end
        local bankKnown=owned.bankKnown==true
        local bank=bankKnown and math.max(0,tonumber(owned.bank) or 0) or 0
        materialStates[#materialStates+1]={itemID=m.itemID,name=m.name,perCraft=qty,
            required=qty,owned=owned.bags,missing=math.max(0,qty-owned.bags),
            source=m.source,storage={bags=owned.bags,bagKnown=true,bank=bank,bankKnown=bankKnown}}
        if owned.bags<qty then
            local missing=qty-owned.bags
            if bankKnown and bank>0 then
                local take=math.min(missing,bank)
                return unresolved("Verify/retrieve "..take.." x "..tostring(m.name or m.itemID)..
                    " from this character's bank, then recheck live bags. No automatic withdrawal.",
                    {kind="bank",itemID=m.itemID,quantity=take})
            end
            return unresolved("Acquire "..missing.." x "..tostring(m.name or m.itemID)..
                " for ONE manual craft; price, source, stock and bulk requirements are unverified"..
                (selectedStrategy(strategy)=="self_found" and " (Self-found: no AH)." or "."),
                {kind="materials",itemID=m.itemID,quantity=missing})
        end
    end
    local exposed=advisoryAuthorityView(step)
    return {kind="craft",profession=key,skill=skill,skillTarget=skill+1,
        recipe=step.recipe,recipeID=id,recipeSource="unknown",materials=step.materials,
        p1MaterialStates=materialStates,rawStep=exposed,dataset=advisoryAuthorityView(dataset),
        remainingCrafts=1,staticRemainingCrafts=nil,expectedCrafts=nil,
        craftCountQualified=false,craftCountAuthority="NO_VERIFIED_TOTAL_CRAFTS",
        craftEstimateEvidenceStatus="UNVERIFIED",p1OneCraft=true,
        p1ObservedDifficulty=live.token,p1ObservedCurrentBuild=observedBuild,
        skillEligibility={status="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
            progressionAllowed=true,progressionQualified=true,readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false},
        skillEligibilityStatus="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
        strategy=selectedStrategy(strategy),routeSelection={strategy=selectedStrategy(strategy),
            changed=true,reason="P1_OBSERVED_ONE_CRAFT_FALLBACK",
            selectedRecipe=step.recipe,candidateCount=1,qualifiedAlternatives=0},
        plannerEligible=false,readOnly=true,executionEligible=false,
        nativeDispatchAllowed=false,routeAuthorityEnabled=false},nil,nil
end

-- Engineering uses the same observed ONE-only evidence chain without promoting DB references.
local function p1EngineeringOneCraft(key,dataset,profession,skill,maxSkill,strategy,step)
    if key~="ENGINEERING" or type(dataset)~="table" or
       dataset.contract~="engineering-1-75-db70450-field-reference-v1" or
       dataset.readOnly~=true or dataset.referenceOnly~=true or
       tonumber(dataset.sourceBuild)~=70450 or type(step)~="table" or
       step.sourceQualificationContract~=dataset.contract then return nil,nil,nil end
    local function unresolved(reason,prerequisite)
        return nil,reason.." One manual craft only after rechecking; total skill-ups, future materials and prices UNKNOWN.",prerequisite
    end
    if type(profession)~="table" or profession.key~=key or profession.cached==true or
       (profession.skillLine~=nil and tonumber(profession.skillLine)~=202) or
       (profession.professionEnum~=nil and tonumber(profession.professionEnum)~=8) or
       type(profession.skill)~="number" or profession.skill~=skill or
       skill~=skill or skill<1 or skill>=300 or type(profession.maxSkill)~="number" or
       profession.maxSkill~=maxSkill or maxSkill~=maxSkill or maxSkill<skill or maxSkill<=0 then
        return unresolved("Verify this character's current Engineering identity, skill and rank; cached or conflicting state is not sufficient.")
    end
    if skill>=maxSkill then
        return unresolved("Verify and train the next Engineering rank before another skill point; trainer and location are not yet verified.",
            {kind="train",text="Verify the next Engineering rank with an actual trainer; no NPC is confirmed."})
    end
    local build=JLP:GetModule("ClientBuildInfo")
    local observedBuild=build and build.GetBuildNumber and build:GetBuildNumber() or nil
    if type(observedBuild)~="number" or observedBuild<=0 or observedBuild~=math.floor(observedBuild) then
        return unresolved("Verify the actual client build and current profession session before ONE manual craft.")
    end
    -- A VERIFIED learning/usage minimum >=300 cannot contribute to reaching 300.
    -- Raw TrivialSkillLineRankHigh=300 is difficulty metadata, not that minimum.
    if tonumber(step.requiredSkill) and tonumber(step.requiredSkill)>=300 then
        return unresolved("Recorded Engineering learning minimum 300 or higher: reference only, not 1-300 progression.")
    end
    local id=tonumber(step.recipeID)
    if not id or not tonumber(step.outputItemID) or
       type(step.materials)~="table" or #step.materials==0 or
       tonumber(step.materialSourceBuild)~=70450 or
       tonumber(step.rawDifficultySourceBuild)~=70450 then
        return unresolved("Engineering recipe or reagent source relation is incomplete; verify its DB fields.")
    end
    local cache=JLP:GetModule("KnowledgeCache")
    local observed=cache and cache.GetRecipeKnowledgeState and cache:GetRecipeKnowledgeState(step.recipe,key)
    if type(observed)=="table" and (observed.sessionIdentityConflict==true or observed.sessionExplicitUnlearned==true) then
        return unresolved("Conflicting or explicitly unlearned SpellID was observed for "..tostring(step.recipe)..
            "; reopen the current profession panel and confirm its unique numeric recipe identity.")
    end
    if type(observed)~="table" or observed.knowledge~="known" or
       observed.currentBuildObserved~=true or observed.sessionLearnedObserved~=true or
       tonumber(observed.currentBuild)~=observedBuild or
       tonumber(observed.observedBuild)~=observedBuild or tonumber(observed.recipeID)~=id then
        return unresolved("Open or refresh the current character's Engineering profession window for a fresh-session learned confirmation of "..
            tostring(step.recipe).." (SpellID "..id.."); source AcquireMethod and trainer access are unverified.")
    end
    local difficulty=JLP:GetModule("RecipeDifficulty")
    local live=difficulty and difficulty.GetForRecipe and difficulty:GetForRecipe(key,id,step.recipe)
    if not live or live.confidence~="verified" or
       (live.token~="orange" and live.token~="yellow" and live.token~="green") or
       live.canSkillUp==false then
        return unresolved("Verify observed non-gray difficulty for learned "..tostring(step.recipe).."; DB difficulty bounds do not establish live skill-up potential.")
    end
    local inventory=JLP:GetModule("Inventory")
    if not inventory or type(inventory.GetOwned)~="function" then
        return unresolved("Verify current character live bag contents before crafting.")
    end
    local materialStates={}
    for _,m in ipairs(step.materials) do
        local qty=tonumber(m.quantity)
        if not tonumber(m.itemID) or not qty or qty<=0 or qty~=math.floor(qty) then
            return unresolved("Reagent identity or per-craft quantity is not qualified.")
        end
        local owned=inventory:GetOwned(m.itemID)
        if type(owned)~="table" or owned.bagKnown~=true or
           type(owned.bags)~="number" or owned.bags<0 then
            return unresolved("Verify live bag quantity of "..tostring(m.name or m.itemID).."; bank/cache is not a bag observation.",
                {kind="verify",itemID=m.itemID})
        end
        local bankKnown=owned.bankKnown==true
        local bank=bankKnown and math.max(0,tonumber(owned.bank) or 0) or 0
        materialStates[#materialStates+1]={itemID=m.itemID,name=m.name,perCraft=qty,
            required=qty,owned=owned.bags,missing=math.max(0,qty-owned.bags),
            source=m.source,storage={bags=owned.bags,bagKnown=true,bank=bank,bankKnown=bankKnown}}
        if owned.bags<qty then
            local missing=qty-owned.bags
            if bankKnown and bank>0 then
                local take=math.min(missing,bank)
                return unresolved("Verify/retrieve "..take.." x "..tostring(m.name or m.itemID)..
                    " from this character's bank, then recheck live bags. No automatic withdrawal.",
                    {kind="bank",itemID=m.itemID,quantity=take})
            end
            return unresolved("Acquire "..missing.." x "..tostring(m.name or m.itemID)..
                " for ONE manual craft; price, source, stock and bulk requirements are unverified"..
                (selectedStrategy(strategy)=="self_found" and " (Self-found: no AH)." or "."),
                {kind="materials",itemID=m.itemID,quantity=missing})
        end
    end
    local exposed=advisoryAuthorityView(step)
    return {kind="craft",profession=key,skill=skill,skillTarget=skill+1,
        recipe=step.recipe,recipeID=id,recipeSource="unknown",materials=step.materials,
        p1MaterialStates=materialStates,rawStep=exposed,dataset=advisoryAuthorityView(dataset),
        remainingCrafts=1,staticRemainingCrafts=nil,expectedCrafts=nil,
        craftCountQualified=false,craftCountAuthority="NO_VERIFIED_TOTAL_CRAFTS",
        craftEstimateEvidenceStatus="UNVERIFIED",p1OneCraft=true,
        p1ObservedDifficulty=live.token,p1ObservedCurrentBuild=observedBuild,
        skillEligibility={status="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
            progressionAllowed=true,progressionQualified=true,readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false},
        skillEligibilityStatus="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
        strategy=selectedStrategy(strategy),routeSelection={strategy=selectedStrategy(strategy),
            changed=true,reason="P1_OBSERVED_ONE_CRAFT_FALLBACK",
            selectedRecipe=step.recipe,candidateCount=1,qualifiedAlternatives=0},
        plannerEligible=false,readOnly=true,executionEligible=false,
        nativeDispatchAllowed=false,routeAuthorityEnabled=false},nil,nil
end


-- Leatherworking is read-only: equivalent observed ONE contract, no bulk/native permission.
-- Leatherworking uses the same observed ONE-only evidence chain without promoting DB references.
local function p1LeatherworkingOneCraft(key,dataset,profession,skill,maxSkill,strategy,step)
    if key~="LEATHERWORKING" or type(dataset)~="table" or
       dataset.contract~="leatherworking-1-75-db70450-field-reference-v1" or
       dataset.readOnly~=true or dataset.referenceOnly~=true or
       tonumber(dataset.sourceBuild)~=70450 or type(step)~="table" or
       step.sourceQualificationContract~=dataset.contract then return nil,nil,nil end
    local function unresolved(reason,prerequisite)
        return nil,reason.." One manual craft only after rechecking; total skill-ups, future materials and prices UNKNOWN.",prerequisite
    end
    if type(profession)~="table" or profession.key~=key or profession.cached==true or
       (profession.skillLine~=nil and tonumber(profession.skillLine)~=165) or
       (profession.professionEnum~=nil and tonumber(profession.professionEnum)~=2) or
       type(profession.skill)~="number" or profession.skill~=skill or
       skill~=skill or skill<1 or skill>=300 or type(profession.maxSkill)~="number" or
       profession.maxSkill~=maxSkill or maxSkill~=maxSkill or maxSkill<skill or maxSkill<=0 then
        return unresolved("Verify this character's current Leatherworking identity, skill and rank; cached or conflicting state is not sufficient.")
    end
    if skill>=maxSkill then
        return unresolved("Verify and train the next Leatherworking rank before another skill point; trainer and location are not yet verified.",
            {kind="train",text="Verify the next Leatherworking rank with an actual trainer; no NPC is confirmed."})
    end
    local build=JLP:GetModule("ClientBuildInfo")
    local observedBuild=build and build.GetBuildNumber and build:GetBuildNumber() or nil
    if type(observedBuild)~="number" or observedBuild<=0 or observedBuild~=math.floor(observedBuild) then
        return unresolved("Verify the actual client build and current profession session before ONE manual craft.")
    end
    -- Verified learning minimum at the target cannot contribute to the 1ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ300 goal.
    -- Raw DB difficulty high=300 is NOT a learning minimum.
    if tonumber(step.requiredSkill) and tonumber(step.requiredSkill)>=300 then
        return unresolved("Recorded Leatherworking learning minimum 300 or higher: reference only, not 1-300 progression.")
    end
    local id=tonumber(step.recipeID)
    if not id or not tonumber(step.outputItemID) or
       type(step.materials)~="table" or #step.materials==0 or
       tonumber(step.materialSourceBuild)~=70450 or
       tonumber(step.rawDifficultySourceBuild)~=70450 then
        return unresolved("Leatherworking recipe or reagent source relation is incomplete; verify its DB fields.")
    end
    local cache=JLP:GetModule("KnowledgeCache")
    local observed=cache and cache.GetRecipeKnowledgeState and cache:GetRecipeKnowledgeState(step.recipe,key)
    if type(observed)=="table" and (observed.sessionIdentityConflict==true or observed.sessionExplicitUnlearned==true) then
        return unresolved("Conflicting or explicitly unlearned SpellID was observed for "..tostring(step.recipe)..
            "; reopen the current profession panel and confirm its unique numeric recipe identity.")
    end
    if type(observed)~="table" or observed.knowledge~="known" or
       observed.currentBuildObserved~=true or observed.sessionLearnedObserved~=true or
       tonumber(observed.currentBuild)~=observedBuild or
       tonumber(observed.observedBuild)~=observedBuild or tonumber(observed.recipeID)~=id then
        return unresolved("Open or refresh the current character's Leatherworking profession window for a fresh-session learned confirmation of "..
            tostring(step.recipe).." (SpellID "..id.."); source AcquireMethod and trainer access are unverified.")
    end
    local difficulty=JLP:GetModule("RecipeDifficulty")
    local live=difficulty and difficulty.GetForRecipe and difficulty:GetForRecipe(key,id,step.recipe)
    if not live or live.confidence~="verified" or
       (live.token~="orange" and live.token~="yellow" and live.token~="green") or
       live.canSkillUp==false then
        return unresolved("Verify observed non-gray difficulty for learned "..tostring(step.recipe).."; DB difficulty bounds do not establish live skill-up potential.")
    end
    local inventory=JLP:GetModule("Inventory")
    if not inventory or type(inventory.GetOwned)~="function" then
        return unresolved("Verify current character live bag contents before crafting.")
    end
    local materialStates={}
    for _,m in ipairs(step.materials) do
        local qty=tonumber(m.quantity)
        if not tonumber(m.itemID) or not qty or qty<=0 or qty~=math.floor(qty) then
            return unresolved("Reagent identity or per-craft quantity is not qualified.")
        end
        local owned=inventory:GetOwned(m.itemID)
        if type(owned)~="table" or owned.bagKnown~=true or
           type(owned.bags)~="number" or owned.bags<0 then
            return unresolved("Verify live bag quantity of "..tostring(m.name or m.itemID).."; bank/cache is not a bag observation.",
                {kind="verify",itemID=m.itemID})
        end
        local bankKnown=owned.bankKnown==true
        local bank=bankKnown and math.max(0,tonumber(owned.bank) or 0) or 0
        materialStates[#materialStates+1]={itemID=m.itemID,name=m.name,perCraft=qty,
            required=qty,owned=owned.bags,missing=math.max(0,qty-owned.bags),
            source=m.source,storage={bags=owned.bags,bagKnown=true,bank=bank,bankKnown=bankKnown}}
        if owned.bags<qty then
            local missing=qty-owned.bags
            if bankKnown and bank>0 then
                local take=math.min(missing,bank)
                return unresolved("Verify/retrieve "..take.." x "..tostring(m.name or m.itemID)..
                    " from this character's bank, then recheck live bags. No automatic withdrawal.",
                    {kind="bank",itemID=m.itemID,quantity=take})
            end
            return unresolved("Acquire "..missing.." x "..tostring(m.name or m.itemID)..
                " for ONE manual craft; price, source, stock and bulk requirements are unverified"..
                (selectedStrategy(strategy)=="self_found" and " (Self-found: no AH)." or "."),
                {kind="materials",itemID=m.itemID,quantity=missing})
        end
    end
    local exposed=advisoryAuthorityView(step)
    return {kind="craft",profession=key,skill=skill,skillTarget=skill+1,
        recipe=step.recipe,recipeID=id,recipeSource="unknown",materials=step.materials,
        p1MaterialStates=materialStates,rawStep=exposed,dataset=advisoryAuthorityView(dataset),
        remainingCrafts=1,staticRemainingCrafts=nil,expectedCrafts=nil,
        craftCountQualified=false,craftCountAuthority="NO_VERIFIED_TOTAL_CRAFTS",
        craftEstimateEvidenceStatus="UNVERIFIED",p1OneCraft=true,
        p1ObservedDifficulty=live.token,p1ObservedCurrentBuild=observedBuild,
        skillEligibility={status="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
            progressionAllowed=true,progressionQualified=true,readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false},
        skillEligibilityStatus="P1_LIVE_RECIPE_AND_DIFFICULTY_OBSERVED",
        strategy=selectedStrategy(strategy),routeSelection={strategy=selectedStrategy(strategy),
            changed=true,reason="P1_OBSERVED_ONE_CRAFT_FALLBACK",
            selectedRecipe=step.recipe,candidateCount=1,qualifiedAlternatives=0},
        plannerEligible=false,readOnly=true,executionEligible=false,
        nativeDispatchAllowed=false,routeAuthorityEnabled=false},nil,nil
end



function Planner:GetTailoringRecipeQualification(skill, live)
    local qual=JLP:GetModule("TailoringRecipeQualification")
    if not qual then return nil end
    if live==true then return qual:InspectAtSkill(skill) end
    return skill and qual:GetAtSkill(skill) or qual:Build()
end

-- P1: Explicit Tailoring 1-300 source and observed-skill evidence review.
-- A source row or observed sample is NEVER a native action authorization.
function Planner:GetTailoringProgressionEvidence(skill, includeLive)
    local audit=JLP:GetModule("TailoringProgressionEvidence")
    if not audit then return nil end
    if includeLive==true then return audit:InspectAtSkill(skill) end
    if skill~=nil then return audit:GetAtSkill(skill) end
    return audit:Build()
end

function Planner:GetTailoringLevelingAudit()
    local audit=JLP:GetModule("TailoringLevelingCoverage")
    return audit and audit:Build() or nil
end

function Planner:GetDataset(key)
    local prerequisite=prerequisitePlan(key)
    if prerequisite then return nil,prerequisite.terminalReason end
    return routeFor(key)
end

function Planner:GetCurrentStep(key, professionState, datasetOverride, strategyOverride)
    local prerequisite=prerequisitePlan(key)
    if prerequisite then return prerequisite end
    local dataset = datasetOverride or routeFor(key)
    if not dataset or not professionState then return nil end
    local skill = tonumber(professionState.skill) or 0
    local cap = tonumber(professionState.maxSkill) or 0

    if skill >= 300 then
        return {
            kind = "complete",
            profession = key,
            skill = skill,
            skillTarget = 300,
            dataset = dataset,
        }
    end

    if (key=="ENCHANTING" or key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and dataset.progression then
        local universal=JLP:GetModule("UniversalCurrentStep")
        local current=universal and universal:Recommend(key,professionState,dataset,{strategy=strategyOverride or selectedStrategy()})
        if current then
            if current.kind~="craft" then
                current.dataset=dataset;current.skillTarget=skill;current.p1NextAction=current.nextAction
                current.trainer=current.kind=="train" and {rank=current.rank} or nil
                return current
            end
            local materials={};for _,m in ipairs(current.materials or {})do materials[#materials+1]={itemID=m.itemID,quantity=m.perCraft or m.quantity,source=m.source}end
            return {kind="craft",recipe=current.recipe,recipeID=current.recipeID,skillMin=skill,skillTarget=current.skillTarget,
                dataset=dataset,materials=materials,remainingCrafts=current.remainingCrafts or 1,expectedCrafts=current.remainingCrafts,
                readOnly=true,nativeDispatchAllowed=false,actionType=current.actionType,stationPreparation=current.stationPreparation}
        end
    end
    if key=="TAILORING" then
        local qualification=JLP:GetModule("TailoringRecipeQualification")
        local rank=qualification and qualification.GetRankStep and qualification:GetRankStep(professionState,dataset)
        if rank then rank.dataset=dataset;rank.tailoringRank=true;return rank end
    end
    if cap > 0 and cap < 300 then
        local gate = findTrainerGate(dataset, cap)
        if not gate and skill >= cap then
            -- Only when the character has *actually reached* the observed cap.
            -- The owner-qualified trainer is looked up separately and may be
            -- unavailable; do not elevate this advisory to native access.
            gate = referenceTrainerGate(key, cap, skill, professionState)
        end
        if gate then
            local optimizer = JLP:GetModule("TrainerOptimizer")
            local decision = optimizer and optimizer.Evaluate and optimizer:Evaluate(key, professionState, gate) or nil
            local mandatory = skill >= cap
            local recommendEarly = decision and decision.recommendEarly and not mandatory or false
            if mandatory or recommendEarly then
                return {
                    kind = "train",
                    profession = key,
                    skill = skill,
                    skillTarget = gate.nextCap,
                    trainer = gate,
                    sourceInfo = decision and decision.sourceInfo or (sourceResolver() and sourceResolver():GetTrainerForGate(key, gate) or nil),
                    blockedByLevel = getPlayerLevel() < (tonumber(gate.minCharacterLevel) or 0),
                    early = recommendEarly,
                    trainingDecision = decision,
                    dataset = dataset,
                }
            end
        end
    end

    local step, index = findRouteStep(dataset, skill)
    if not step and skill < 1 then step, index = findRouteStep(dataset, 1) end
    -- Public Forever source is the ONLY effective Alchemy candidate-step authority.
    -- Keep the registered 13-step historical dataset immutable and read-only.
    if key=="ALCHEMY" and dataset.productionCandidate==true and dataset.readOnly==true then
        local view=JLP:GetModule("ForeverAlchemyCandidateView")
        if not view or not view.GetAtSkill then return nil end
        local effective,ordinal=view:GetAtSkill(key,dataset,skill)
        if not effective then return nil end -- fail closed on source drift
        step,index=effective,ordinal
    elseif dataset.productionCandidate==true and dataset.readOnly==true then
        local starter=JLP:GetModule("ForeverStarterRoute")
        if starter and starter.GetCandidateStep then
            local corrected,handled=starter:GetCandidateStep(key,dataset,skill)
            if handled then
                if not corrected then return nil end
                step,index=corrected,corrected.routeIndex or 0
            end
        end
    end
    if not step then return nil end
    if step.sourceQualificationContract=="tailoring-25-31-source-planning-v1" or
        (step.sourceQualificationContract=="tailoring-40-50-forever-v1" or
        (step.sourceQualificationContract=="tailoring-50-77-forever-v1" or (step.sourceQualificationContract=="tailoring-77-102-wool-v1" or (step.sourceQualificationContract=="tailoring-102-107-source-v1" or (step.sourceQualificationContract=="tailoring-107-125-source-v1" or (step.sourceQualificationContract=="tailoring-125-225-source-v1" or step.sourceQualificationContract=="tailoring-225-300-source-v1")))))) then
        if (step.sourceQualificationContract=="tailoring-40-50-forever-v1" or
            (step.sourceQualificationContract=="tailoring-50-77-forever-v1" or (step.sourceQualificationContract=="tailoring-77-102-wool-v1" or (step.sourceQualificationContract=="tailoring-102-107-source-v1" or (step.sourceQualificationContract=="tailoring-107-125-source-v1" or (step.sourceQualificationContract=="tailoring-125-225-source-v1" or step.sourceQualificationContract=="tailoring-225-300-source-v1")))))) and skill>=40 then
            local qualification=JLP:GetModule("TailoringRecipeQualification")
            local selector=JLP:GetModule("UniversalCurrentStep")
            local choices=skill>=77 and qualification:GetWoolAlternatives(dataset,skill) or skill>=50 and qualification:GetJourneymanAlternatives(dataset,skill) or qualification:GetIntervalAlternatives(dataset,skill)
            local selected=choices and selector:SelectProgressionAlternative(choices,skill,strategyOverride)
            if selected then step=selected end
        end
        if cap<=skill then
            return {kind="verify",profession=key,skill=skill,skillTarget=step.skillTarget,
                recipeID=step.recipeID,recipe=step.recipe,rawStep=step,
                dataset=advisoryAuthorityView(dataset),readOnly=true,
                skillEligibilityStatus="PROFESSION_RANK_UNVERIFIED",
                p1NextAction="Verify the current Tailoring rank and skill cap before progressing.",
                nativeDispatchAllowed=false,executionEligible=false}
        end
        local out={};for k,v in pairs(step) do out[k]=v end
        out.kind="craft";out.profession=key;out.skill=skill;out.dataset=dataset
        out.remainingCrafts=remainingCrafts(step,skill)
        out.skillEligibility=skillEligibility(key,step,skill,step.skillTarget)
        out.skillEligibilityStatus=out.skillEligibility.status
        return out
    end
    -- Tailoring 1-300: give precedence to ONE actual live-observed craft over
    -- historical route counts, regardless of the player's skill bracket.
    -- A validated previous recipe may remain non-gray after its old reference
    -- window. Check at most five recent distinct IDs; no catalogue scan.
    -- This is advisory ONLY and cannot authorize the native Craft buttons.
    if key=="TAILORING" and type(step)=="table" and
       step.craftCountQualified~=true and cap>skill then
        local checked={}
        local function tryOne(row)
            if type(row)~="table" or type(row.recipeID)~="number" or
               checked[row.recipeID] then return nil end
            checked[row.recipeID]=true
            return liveManualOneCraft(key,professionState,dataset,row,skill,cap)
        end
        local observed=tryOne(step)
        local searched=0
        if not observed and type(dataset.route)=="table" then
            for i=math.min((tonumber(index) or 1)-1,#dataset.route),1,-1 do
                local prior=dataset.route[i]
                if type(prior)=="table" and tonumber(prior.skillMin) and
                   prior.skillMin<=skill and not checked[prior.recipeID] then
                    searched=searched+1
                    if searched>5 then break end
                    observed=tryOne(prior)
                    if observed then
                        observed.routeSelection={strategy=selectedStrategy(strategyOverride),
                            changed=true,reason="TAILORING_PRIOR_LIVE_ONE_CRAFT",
                            selectedRecipe=observed.recipe,candidateCount=searched+1,
                            qualifiedAlternatives=0}
                        break
                    end
                end
            end
        end
        if observed then return observed end
    end
    local p1Craft,p1Unresolved,p1Prerequisite=p1TailoringOneCraft(key,dataset,skill,strategyOverride,cap)
    if key=="BLACKSMITHING" then
        p1Craft,p1Unresolved,p1Prerequisite=p1BlacksmithOneCraft(
            key,dataset,professionState,skill,cap,strategyOverride,step)
    elseif key=="ENGINEERING" then
        p1Craft,p1Unresolved,p1Prerequisite=p1EngineeringOneCraft(
            key,dataset,professionState,skill,cap,strategyOverride,step)
    elseif key=="LEATHERWORKING" then
        p1Craft,p1Unresolved,p1Prerequisite=p1LeatherworkingOneCraft(
            key,dataset,professionState,skill,cap,strategyOverride,step)
    end
    if p1Craft then return p1Craft end
    local choice
    step,choice=selectStrategyStep(key,dataset,step,skill,step.skillTarget,strategyOverride)
    local eligibility=skillEligibility(key,step,skill,step.skillTarget)
    if p1Unresolved then choice.p1NextAction=p1Unresolved;choice.p1Prerequisite=p1Prerequisite end
    -- F01 / 0.34.115: the Tailoring 70009 route is a *position reference*,
    -- not a presently qualified crafting action. The preceding P1 ONE
    -- fallback is the only Tailoring historical-route craft advisory allowed
    -- from observed learned RecipeID, non-gray difficulty and live bags.
    -- Never turn source-only eligibility or expectedCrafts into a current craft.
    if key=="TAILORING" and dataset.readOnlyRouteFallback==true then
        if eligibility.progressionAllowed then
            eligibility={status="TAILORING_HISTORICAL_ROUTE_REQUIRES_LIVE_ONE",
                progressionAllowed=false,progressionQualified=false,
                readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
        end
        if not p1Unresolved then
            p1Unresolved="Open the current character's Tailoring window and "..
                "verify exact learned RecipeID, non-gray current-client difficulty, "..
                "profession rank and live reagent counts in bags. "..
                "The historical route is a reference, not a crafting instruction; "..
                "total skill-ups and bulk materials are UNKNOWN."
        end
        choice.p1NextAction=p1Unresolved
    end
    -- A read-only source position may have a fully observed live ONE-craft
    -- opportunity even when the minimum-skill gate is qualified on paper.
    -- Treat this as current manual evidence, never as source-route authority.
    local referenceRoute=dataset.readOnly==true or
        dataset.referenceOnly==true or dataset.readOnlyRouteFallback==true
    if not eligibility.progressionAllowed or referenceRoute then
        local manual=liveManualOneCraft(key,professionState,dataset,step,skill,cap)
        if manual then return manual end
    end
    if not eligibility.progressionAllowed then
        return {kind="verify",profession=key,skill=skill,skillTarget=step.skillTarget,
            recipe=step.recipe,recipeID=step.recipeID,
            skillEligibility=eligibility,skillEligibilityStatus=eligibility.status,
            craftCountQualified=step.craftCountQualified,
            craftCountAuthority=step.craftCountAuthority,
            craftEstimateEvidenceStatus=craftEstimateEvidence(step),
            p1NextAction=p1Unresolved,p1Prerequisite=p1Prerequisite,
            strategy=choice.strategy,routeSelection=choice,
            dataset=advisoryAuthorityView(dataset),rawStep=advisoryAuthorityView(step),
            nativeDispatchAllowed=false,executionEligible=false,
            routeAuthorityEnabled=false,plannerEligible=false,readOnly=true}
    end
    local changed=choice.changed==true
    local exposedStep=changed and advisoryAuthorityView(step) or step
    local exposedDataset=changed and advisoryAuthorityView(dataset) or dataset
    local executionEligible=step.executionEligible
    local routeAuthorityEnabled=dataset.routeAuthorityEnabled==true or nil
    local researchAuthority=step.researchAuthority==true or nil
    if changed then
        executionEligible=false
        routeAuthorityEnabled=false
        researchAuthority=false
    end

    local staticRemaining = remainingCrafts(step, skill)
    local adaptiveRemaining, estimate = telemetryEstimate(key, step, skill, step.skillTarget, staticRemaining, true)
    return {
        kind = "craft",
        profession = key,
        skill = skill,
        skillTarget = step.skillTarget,
        routeIndex = tonumber(step.routeIndex) or index,
        recipe = step.recipe,
        recipeID = step.recipeID,
        recipeSource = step.recipeSource or "trainer",
        sourceInfo = sourceResolver() and sourceResolver():GetRecipeSource(key, step.recipe) or nil,
        expectedCrafts = step.expectedCrafts,
        -- P0.2B: never upgrade historical craft-counts or external yield
        -- references into current-build skill-up / native authority.
        craftCountAuthority = step.craftCountAuthority,
        craftCountQualified = step.craftCountQualified,
        craftCountEvidenceStatus = step.craftCountEvidenceStatus,
        craftEstimateEvidenceStatus = craftEstimateEvidence(step),
        craftEstimateGapFromSkill = step.craftEstimateGapFromSkill,
        craftEstimateGapToSkill = step.craftEstimateGapToSkill,
        materialEvidence = step.materialEvidence,
        outputItemID = step.outputItemID,
        outputQuantityReference = step.outputQuantityReference,
        outputQuantityEvidence = step.outputQuantityEvidence,
        outputQuantityConflictingReference = step.outputQuantityConflictingReference,
        outputQuantityConflictEvidence = step.outputQuantityConflictEvidence,
        recipeSourceEvidence = step.recipeSourceEvidence,
        recipeLearnSourceEvidence = step.recipeLearnSourceEvidence,
        outputYieldLiveVerified = step.outputYieldLiveVerified,
        sourceQualificationContract = step.sourceQualificationContract,
        staticRemainingCrafts = staticRemaining,
        remainingCrafts = adaptiveRemaining,
        estimateSource = estimate and estimate.source or "route-static",
        estimateSourceDetail = estimate and estimate.sourceDetail or "route-static",
        estimateWeight = estimate and estimate.weight or 0,
        telemetryEstimate = estimate,
        telemetry = estimate and estimate.telemetry or nil,
        materials = step.materials or {},
        requiredTool = step.requiredTool,
        evidence = step.evidence or dataset.evidence,
        dataset = exposedDataset,
        rawStep = exposedStep,
        strategy = choice.strategy,
        routeSelection = choice,
        skillEligibility = eligibility,
        skillEligibilityStatus = eligibility.status,
        authority = changed and exposedStep.authority or dataset.authority,
        plannerEligible = dataset.plannerEligible == true and step.plannerEligible == true or nil,
        executionEligible = executionEligible,
        nativeDispatchAllowed = false,
        readOnly = changed or dataset.readOnly==true,
        routeAuthorityEnabled = routeAuthorityEnabled,
        researchAuthority = researchAuthority,
    }
end

function Planner:GetMaterialStates(plan)
    local out = {}
    if plan and prerequisitePlan(plan.key or plan.professionKey or plan.profession) then return out end
    if not plan or plan.kind ~= "craft" then return out end
    local resolver = JLP:GetModule("PriceResolver")
    local disenchant = JLP:GetModule("Disenchant")
    local optimizer = JLP:GetModule("CostOptimizer")
    local crafts = tonumber(plan.remainingCrafts) or 0
    -- All displayed requirements share one stock reservation, including tool
    -- inputs and recursive branches. Reserve direct materials before expanding
    -- intermediates so a shared raw input cannot be promised twice.
    local reserved,entries,graphAllocation={},{},nil
    local function reserveStock(itemID,required)
        local observed=ownedState(itemID)
        observed=type(observed)=="table" and observed or {}
        if itemID==nil then return {bags=0,bank=0,total=0} end
        local prior=reserved[itemID] or {bags=0,bank=0,total=0}
        local bags=observed.bagKnown==true and math.max(0,(tonumber(observed.bags) or 0)-prior.bags) or 0
        local bank=observed.bankKnown==true and math.max(0,(tonumber(observed.bank) or 0)-prior.bank) or 0
        local total=bags+bank
        local take=math.min(math.max(0,tonumber(required) or 0),total)
        local bagTake=math.min(take,bags)
        local bankTake=math.min(take-bagTake,bank)
        reserved[itemID]={bags=prior.bags+bagTake,bank=prior.bank+bankTake,total=prior.total+take}
        local storage={}
        for k,v in pairs(observed) do storage[k]=v end
        storage.observedBags,storage.observedBank,storage.observedTotal=observed.bags,observed.bank,observed.total
        storage.bags,storage.bank,storage.total=bagTake,bankTake,take
        storage.stockReserved=true
        return storage
    end
    local function stage(material,required,context)
        if type(material)~="table" or material.itemID==nil then return end
        entries[#entries+1]={material=material,required=required,context=context,
            storage=reserveStock(material.itemID,required)}
    end

    local function addMaterial(material, required, context, reservedStorage)
        local inventory = JLP:GetModule("Inventory")
        local storage = reservedStorage or reserveStock(material.itemID,required)
        local owned = storage.total or 0
        local liveBank = storage.bankKnown==true and
            (storage.bankEvidence ~= "SAVED_ORDINARY_BANK_SNAPSHOT" or storage.bankOpenedAt~=nil)
        local stockKnown = storage.bagKnown==true and (liveBank or (storage.bags or 0)>=required)
        local missing = stockKnown and math.max(0, required - owned) or nil
        local row = {
            itemID = material.itemID,
            name = material.name,
            source = material.source or "auction",
            perCraft = material.quantity or 0,
            required = required,
            owned = owned,
            missing = missing,
            missingKnown = stockKnown,
            bagsKnown = storage.bagKnown==true,
            bankKnown = storage.bankKnown==true,
            inventoryUnknown = not stockKnown,
            nativeDispatchAllowed=false,
            context = context,
            storage = storage,
        }

        if material.craftedRecipe and missing ~= nil and missing > 0 then
            row.craftedRecipe = craftedRecipeState(material.craftedRecipe, missing, resolver, 1, {}, reserveStock, graphAllocation, material.itemID)
        elseif material.craftedFrom and missing ~= nil and missing > 0 then
            local rawNeeded = missing * (tonumber(material.craftedFrom.quantity) or 0)
            if graphAllocation then
                local id=tonumber(material.itemID)
                local production=id and graphAllocation.production[id]
                local shared=id and graphAllocation.used[id]==true
                rawNeeded=not shared and production and production.crafts*(tonumber(material.craftedFrom.quantity) or 0) or 0
                row.sharedPreparation=shared==true
                if production and id then graphAllocation.used[id]=true end
                if not graphAllocation.resolved then
                    row.craftedRecipe={resolved=false,status=graphAllocation.reason,materials={},readOnly=true,plannerEligible=false}
                end
            end
            local rawStorage = reserveStock(material.craftedFrom.itemID,rawNeeded)
            local rawOwned = rawStorage.total or 0
            local rawBankLive = rawStorage.bankKnown==true and
                (rawStorage.bankEvidence~="SAVED_ORDINARY_BANK_SNAPSHOT" or rawStorage.bankOpenedAt~=nil)
            local rawKnown=rawStorage.bagKnown==true and (rawBankLive or (rawStorage.bags or 0)>=rawNeeded)
            row.craftedFrom = {
                itemID = material.craftedFrom.itemID,
                name = material.craftedFrom.name,
                quantityPerCraft = material.craftedFrom.quantity,
                producerRecipeID=material.craftedFrom.producerRecipeID,
                outputPerCraft=material.craftedFrom.outputPerCraft,
                sourceBuild=material.craftedFrom.sourceBuild,
                sourceSHA256=material.craftedFrom.sourceSHA256,
                quantityAuthority=material.craftedFrom.authority,
                readOnly=true,nativeDispatchAllowed=false,
                required = rawNeeded,
                owned = rawOwned,
                missing = rawKnown and math.max(0, rawNeeded - rawOwned) or nil,
                missingKnown=rawKnown,
                storage = rawStorage,
            }
            if resolver and row.craftedFrom.missing ~= nil and row.craftedFrom.missing > 0 then
                row.rawAH = resolver:GetFulfillmentCost(material.craftedFrom.itemID, row.craftedFrom.missing)
            end
        elseif resolver and missing ~= nil and missing > 0 and supportsAH(row.source) then
            row.ah = resolver:GetFulfillmentCost(material.itemID, missing)
        end

        if disenchant and missing ~= nil and missing > 0 and row.source == "disenchant-or-auction" then
            row.disenchant = disenchant:DescribeMaterial(material.itemID)
            if optimizer then
                row.economy = optimizer:GetComparison(material.itemID, missing)
            end
        end

        out[#out + 1] = row
    end

    for _, material in ipairs(plan.materials or {}) do
        stage(material, (tonumber(material.quantity) or 0) * crafts, nil)
    end

    local tool = tostring(plan.key or plan.professionKey or plan.profession or "") == "ENCHANTING" and plan.requiredTool
    local toolSatisfied = false
    if tool and tostring(plan.key or plan.professionKey or plan.profession or "") == "ENCHANTING" then
        local resolver = JLP:GetModule("EnchantingToolResolver")
        if resolver and resolver.IsSatisfied then toolSatisfied = select(1, resolver:IsSatisfied(tool, false)) end
    end
    local toolStock=tool and not toolSatisfied and ownedState(tool.itemID) or nil
    if tool and not toolSatisfied and toolStock and toolStock.bagKnown==true and
        toolStock.bankKnown==true and
        (toolStock.bankEvidence~="SAVED_ORDINARY_BANK_SNAPSHOT" or toolStock.bankOpenedAt~=nil) and
        (tonumber(toolStock.total) or 0)<=0 then
        for _, material in ipairs(tool.materials or {}) do
            stage(material, tonumber(material.quantity) or 0, "Craft " .. tostring(tool.name or "required tool"))
        end
    end

    local readiness=JLP:GetModule("CraftReadiness")
    if readiness and type(readiness.AllocateMaterials)=="function" then
        local materials,entryIndexes={},{}
        for index,entry in ipairs(entries) do
            if entry.required>0 then
                local material={}
                for k,v in pairs(entry.material) do material[k]=v end
                material.quantity=entry.required
                materials[#materials+1]=material;entryIndexes[#entryIndexes+1]=index
            end
        end
        local allocation=readiness:AllocateMaterials(materials,1,{useStorage=true,prepare=true})
        graphAllocation={production={},used={},remaining={},reason=allocation.reason,
            resolved=allocation.feasible==true or allocation.reason=="insufficient-materials"}
        -- A later raw shortage can replace an earlier producer error in the
        -- allocator summary. An unresolved declared producer is never a valid
        -- zero-craft preparation, even when other leaves can be purchased.
        for _,requirement in pairs(allocation.requirements or {}) do
            local material=requirement.material
            if (tonumber(requirement.missing) or 0)>0 and type(material)=="table" and
                (type(material.craftedRecipe)=="table" or type(material.craftedFrom)=="table") then
                graphAllocation.resolved=false
                graphAllocation.reason="unresolved-producer"
            end
        end
        for _,production in ipairs(allocation.production or {}) do graphAllocation.production[production.itemID]=production end
        -- Direct requirements (including tool inputs) are reserved before any
        -- dependency expansion. Keep those reservations in the displayed rows.
        reserved={}
        for index,allocated in ipairs(allocation.rows or {}) do
            local entry=entries[entryIndexes[index]]
            if entry then
                entry.storage=reserveStock(entry.material.itemID,allocated.allocated)
            end
        end
        for id,requirement in pairs(allocation.requirements or {}) do
            graphAllocation.remaining[id]=math.max(0,(tonumber(requirement.allocated) or 0)-(reserved[id] and reserved[id].total or 0))
        end
        local reserveObserved=reserveStock
        reserveStock=function(itemID,required)
            local id=tonumber(itemID)
            local remaining=id and graphAllocation.remaining[id] or 0
            local storage=reserveObserved(itemID,math.min(math.max(0,tonumber(required) or 0),remaining))
            if id then graphAllocation.remaining[id]=math.max(0,remaining-(tonumber(storage.total) or 0)) end
            return storage
        end
    end

    for _,entry in ipairs(entries) do
        addMaterial(entry.material,entry.required,entry.context,entry.storage)
    end

    return out
end

function Planner:BuildProfessionPlanForDataset(key, profession, dataset)
    local prerequisite=prerequisitePlan(key)
    if prerequisite then return prerequisite end
    if not profession then
        local resolver = sourceResolver()
        local sourceInfo = resolver and resolver.GetTrainerForRank and resolver:GetTrainerForRank(key, "Apprentice") or nil
        local definition = JLP.data and JLP.data.professions and JLP.data.professions[key] or nil
        local professionName = definition and definition.name or ((JLP:GetModule("ProfessionRegistry") and JLP:GetModule("ProfessionRegistry"):GetDisplayNameOrKey(key)) or tostring(key or "Profession"))
        local sourceText = sourceInfo and resolver and resolver:Format(sourceInfo, false) or nil
        return {
            status = "not-learned",
            key = key,
            profession = nil,
            sourceInfo = sourceInfo,
            action = sourceText and string.format("Learn %s with %s.", professionName, sourceText) or "Profession not detected.",
            actionKind = "learn",
            materials = {},
            plannerEligible = dataset and dataset.plannerEligible == true or nil,
            executionEligible = dataset and dataset.executionEligible,
            routeAuthorityEnabled = dataset and dataset.routeAuthorityEnabled == true or nil,
            readOnly = dataset and dataset.readOnly == true or false,
            productionCandidate = dataset and dataset.productionCandidate == true or false,
            nativeDispatchAllowed = dataset and dataset.nativeDispatchAllowed == true or false,
            datasetContract = dataset and dataset.contract or nil,
        }
    end

    local step = self:GetCurrentStep(key, profession, dataset)
    if not step then
        return {
            status = "no-route",
            key = key,
            profession = profession,
            action = "No route step is available for the current skill.",
            actionKind = "blocked",
            materials = {},
            plannerEligible = dataset and dataset.plannerEligible == true or nil,
            executionEligible = dataset and dataset.executionEligible,
            routeAuthorityEnabled = dataset and dataset.routeAuthorityEnabled == true or nil,
            readOnly = dataset and dataset.readOnly == true or false,
            productionCandidate = dataset and dataset.productionCandidate == true or false,
            nativeDispatchAllowed = dataset and dataset.nativeDispatchAllowed == true or false,
            datasetContract = dataset and dataset.contract or nil,
        }
    end

    local authorityFields = {
        plannerEligible = dataset and dataset.plannerEligible == true or nil,
        executionEligible = dataset and dataset.executionEligible,
        routeAuthorityEnabled = dataset and dataset.routeAuthorityEnabled == true or nil,
        authority = dataset and dataset.authority or nil,
        readOnly = dataset and dataset.readOnly == true or false,
        productionCandidate = dataset and dataset.productionCandidate == true or false,
        nativeDispatchAllowed = dataset and dataset.nativeDispatchAllowed == true or false,
        datasetContract = dataset and dataset.contract or nil,
    }

    if step.sourceQualificationContract=="tailoring-25-31-source-planning-v1" or
        (step.sourceQualificationContract=="tailoring-40-50-forever-v1" or
        (step.sourceQualificationContract=="tailoring-50-77-forever-v1" or (step.sourceQualificationContract=="tailoring-77-102-wool-v1" or (step.sourceQualificationContract=="tailoring-102-107-source-v1" or (step.sourceQualificationContract=="tailoring-107-125-source-v1" or (step.sourceQualificationContract=="tailoring-125-225-source-v1" or step.sourceQualificationContract=="tailoring-225-300-source-v1")))))) then
        authorityFields.executionEligible=false;authorityFields.nativeDispatchAllowed=false
        authorityFields.routeAuthorityEnabled=false;authorityFields.readOnly=true
    end
    if step.tailoringRank then
        authorityFields.readOnly=true;authorityFields.nativeDispatchAllowed=false
        authorityFields.executionEligible=false;authorityFields.routeAuthorityEnabled=false
    end
    -- Qualified advisory alternatives never inherit a registered production
    -- dataset's execution/native authority. Native access must be qualified
    -- separately for the selected recipe and actual live character.
    if step.routeSelection and step.routeSelection.changed==true then
        authorityFields.executionEligible=false
        authorityFields.routeAuthorityEnabled=false
        authorityFields.nativeDispatchAllowed=false
        authorityFields.readOnly=true
        authorityFields.authority=step.authority -- advisory, not registered production authority
    end

    if step.kind == "verify" then
        -- P0.2J: a source-backed gap candidate is a targeted NEXT VERIFICATION,
        -- not a route step or a shopping/crafting commitment.  Never infer a
        -- craft count, recipe access or any native permission from DB raw ranks.
        local raw=step.rawStep
        local candidate=raw and raw.gapResolutionCandidate
        if not candidate and raw and raw.recipeID==3852 and
            raw.sourceQualificationContract=="tailoring-143-145-gloves-evidence-p02l-v1" and
            raw.advisoryOnly==true and raw.routeQualified==false then
            candidate=raw -- same evidence, distinct historical interval
        end
        local nextAction="Recipe skill gate is not qualified for this route position ("..
            tostring(step.skillEligibilityStatus or "UNKNOWN").. "). Verify the recipe minimum before proceeding."
        if type(candidate)=="table" and candidate.advisoryOnly==true and
            candidate.routeQualified==false and candidate.recipeID==3852 then
            local targetInterval=raw and raw.skillMin==143 and "143-145" or "137-143"
            nextAction="Verify Gloves of Meditation (SpellID 3852) with your Tailoring trainer. "..
                "External minimum 130 and DB70450 difficulty 125/155 suggest a candidate "..
                "for skill "..targetInterval.."; confirm it is learned, available and can grant a "..
                "skill-up in the actual client. Craft quantity and bulk materials "..
                "are UNKNOWN; Silk Headband's 13 crafts and Gloves' historical 6 "..
                "crafts are NOT verified counts."
        end
        -- P0.2M: don't sell a build-70009 15-craft budget when 70450 raw
        -- difficulty and external minimum/learned state disagree.
        if raw and raw.recipeID==3871 and raw.skillMin==145 and
            raw.sourceQualificationContract=="tailoring-145-153-formal-white-shirt-evidence-p02m-v1" then
            nextAction="Verify Formal White Shirt (SpellID 3871) with your Tailoring trainer "..
                "at skill 145-153: Wowhead Forever lists minimum 170, but DB70450 "..
                "difficulty is 145/155 and older ForeverDB70425 lists 145. "..
                "Check actual learning requirement, known recipe and skill-ups "..
                "in your client; historical 15 crafts and bulk materials are UNVERIFIED."
        end
        -- P0.2N: qualified REFERENCE to source min150 is not learned-state,
        -- reliable skill-up count, or a shopping/native crafting authority.
        if raw and raw.recipeID==3813 and raw.skillMin==153 and
            raw.sourceQualificationContract=="tailoring-153-160-small-silk-pack-evidence-p02n-v1" then
            nextAction="Verify Small Silk Pack (SpellID 3813) with a real Tailoring trainer "..
                "at skill 153-160: Forever overview lists external minimum 150; "..
                "DB70450 difficulty 145/175 does NOT prove actual access, "..
                "skill-ups or 12 casts. Check learned/rank and progression in "..
                "the client; historical 12 crafts and bulk materials are UNVERIFIED."
        end
        if step.p1NextAction and key=="TAILORING" and
            step.skillEligibilityStatus=="TAILORING_HISTORICAL_ROUTE_REQUIRES_LIVE_ONE" then
            nextAction=step.p1NextAction
        elseif step.p1NextAction then
            nextAction=((key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING") and ((key=="ENGINEERING" and "Engineering prerequisite: ") or (key=="LEATHERWORKING" and "Leatherworking prerequisite: ") or "Blacksmithing prerequisite: ") or
                nextAction.." P1 fallback: ")..step.p1NextAction
        end
        return {status="recipe-skill-unverified",key=key,profession=profession,
            step=step,actionKind="verify",materials={},
            candidateVerification=candidate and advisoryAuthorityView(candidate) or nil,
            p1Prerequisite=step.p1Prerequisite,
            action=nextAction,
            skillEligibility=step.skillEligibility,skillEligibilityStatus=step.skillEligibilityStatus,
            plannerEligible=false,executionEligible=false,routeAuthorityEnabled=false,
            readOnly=true,nativeDispatchAllowed=false,
            routeQualification=step.skillEligibilityStatus=="ROUTE_EVIDENCE_UNVERIFIED" and
                "ROUTE_EVIDENCE_UNVERIFIED" or "SKILL_GATE_UNRESOLVED"}
    end

    if step.kind == "complete" then
        return {
            status = "complete",
            key = key,
            profession = profession,
            step = step,
            action = (profession.name or key) .. " is at 300/300.",
            actionKind = "complete",
            materials = {},
            plannerEligible = authorityFields.plannerEligible,
            executionEligible = authorityFields.executionEligible,
            routeAuthorityEnabled = authorityFields.routeAuthorityEnabled,
            authority = authorityFields.authority,
            readOnly = authorityFields.readOnly,
            productionCandidate = authorityFields.productionCandidate,
            nativeDispatchAllowed = authorityFields.nativeDispatchAllowed,
            datasetContract = authorityFields.datasetContract,
        }
    end

    if step.kind == "train" then
        local gate = step.trainer
        local action
        local sourceText = step.sourceInfo and sourceResolver() and sourceResolver():Format(step.sourceInfo, false) or nil
        if step.blockedByLevel then
            action = string.format("Reach character level %d, then train %s%s.", gate.minCharacterLevel or 0, gate.rank or "the next rank", sourceText and (" with " .. sourceText) or "")
        elseif step.early then
            action = string.format("Train %s now while it is a low-detour opportunity%s to unlock skill %d.", gate.rank or "the next rank", sourceText and (" with " .. sourceText) or "", gate.nextCap or 300)
        else
            action = string.format("Train %s%s to unlock skill %d.", gate.rank or "the next rank", sourceText and (" with " .. sourceText) or "", gate.nextCap or 300)
        end
        return {
            status = step.blockedByLevel and "level-blocked" or "train",
            key = key,
            profession = profession,
            step = step,
            action = action,
            actionKind = "train",
            materials = {},
            plannerEligible = authorityFields.plannerEligible,
            executionEligible = authorityFields.executionEligible,
            routeAuthorityEnabled = authorityFields.routeAuthorityEnabled,
            authority = authorityFields.authority,
            readOnly = authorityFields.readOnly,
            productionCandidate = authorityFields.productionCandidate,
            nativeDispatchAllowed = authorityFields.nativeDispatchAllowed,
            datasetContract = authorityFields.datasetContract,
        }
    end

    if step.p1OneCraft then
        return {status="craft",key=key,profession=profession,step=step,
            actionKind="craft",action=step.p1LiveOneCraft and step.p1NextAction or
                ("Advisory: prepare and craft ONE "..tostring(step.recipe)..
                " using the normal player-controlled profession window; check the actual skill "..
                "and difficulty afterward, then refresh Planner. No automatic or native dispatch."),
            materials=step.p1MaterialStates or self:GetMaterialStates(step),p1OneCraft=true,
            p1LiveOneCraft=step.p1LiveOneCraft==true,
            requiresManualConfirmation=true,liveCraftObservation=step.liveCraftObservation,
            craftEstimateEvidenceStatus="UNVERIFIED",craftCountQualified=false,
            plannerEligible=false,executionEligible=false,routeAuthorityEnabled=false,
            readOnly=true,nativeDispatchAllowed=false}
    end
    local materialStates = self:GetMaterialStates(step)
    local professionName = profession.name or (step.dataset and step.dataset.name) or key
    return {
        status = "craft",
        key = key,
        profession = profession,
        step = step,
        skillEligibility=step.skillEligibility,
        skillEligibilityStatus=step.skillEligibilityStatus,
        action = string.format("Craft %s until %s %d.", step.recipe or "the recommended recipe", professionName, step.skillTarget or 0),
        actionKind = "craft",
        materials = materialStates,
        plannerEligible = authorityFields.plannerEligible,
        executionEligible = authorityFields.executionEligible,
        routeAuthorityEnabled = authorityFields.routeAuthorityEnabled,
        authority = authorityFields.authority,
        readOnly = authorityFields.readOnly,
        productionCandidate = authorityFields.productionCandidate,
        nativeDispatchAllowed = authorityFields.nativeDispatchAllowed,
        datasetContract = authorityFields.datasetContract,
    }
end

-- Shared recommendation API for Guide/Overview/third-party read-only consumers.
-- Requires neither Auction House scans nor client build evidence receipts.
function Planner:GetBestCurrentStep(key,professionOverride,options)
    local reg=JLP:GetModule("ProfessionRegistry")
    key=reg and reg:NormalizeKey(key) or key
    if not key then return nil,"UNKNOWN_PROFESSION" end
    if not professionOverride then
        local prerequisite=prerequisitePlan(key);if prerequisite then return prerequisite,prerequisite.terminalReason end
    end
    local api=JLP:GetModule("ProfessionAPI")
    local profession=professionOverride or (api and api:Get(key))
    local universal=JLP:GetModule("UniversalCurrentStep")
    if not universal then return nil,"RECOMMENDER_UNAVAILABLE" end
    return universal:Recommend(key,profession,routeFor(key),options)
end

-- On-demand full progression scenario. Never a native Craft All queue.
function Planner:GetProfessionRouteForecast(key,options)
    local registry=JLP:GetModule("ProfessionRegistry")
    key=registry and registry:NormalizeKey(key) or key
    if not key then return nil,"UNKNOWN_PROFESSION" end
    if not (options and options.profession) then
        local prerequisite=prerequisitePlan(key);if prerequisite then return prerequisite,prerequisite.terminalReason end
    end
    local api=JLP:GetModule("ProfessionAPI")
    local profession=options and options.profession or (api and api:Get(key))
    local universal=JLP:GetModule("UniversalCurrentStep")
    if not universal then return nil,"FORECAST_ENGINE_UNAVAILABLE" end
    return universal:PlanTo300(key,profession,routeFor(key),options)
end

function Planner:GetProfessionPlan(key,context)
    local reg=JLP:GetModule("ProfessionRegistry")
    key=reg and reg:NormalizeKey(key) or key
    if not key then return nil end
    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api:Get(key)
    if key=="FISHING"then
        local secondary=JLP:GetModule("SecondaryLevelingPlanner")
        if secondary and secondary.GetFishingPlan then return secondary:GetFishingPlan(profession,context)end
    end
    if key=="HERBALISM"then
        local herb=JLP:GetModule("ForeverHerbalismProgression209")
        if herb and herb.GetPlan then return herb:GetPlan(profession)end
    end
    if key=="MINING" then
        local mining=JLP:GetModule("ForeverMiningNodeProgression210")
        if mining and mining.GetPlan then return mining:GetPlan(profession)end
    end
    if key=="SKINNING" then
        local skinning=JLP:GetModule("ForeverSkinningEligibility230")
        if skinning and skinning.GetPlan then return skinning:GetPlan(profession) end
    end
    -- Reaching the observed goal is independent of whether a crafting route
    -- exists. Gathering and secondary professions must not revert to a staged
    -- reference just because their skill is already 300.
    local observedSkill=profession and profession.cached~=true and tonumber(profession.skill)
    if observedSkill and observedSkill==observedSkill and observedSkill>=300 and
        observedSkill<math.huge and observedSkill==math.floor(observedSkill) then
        local supply=JLP:GetModule("GatheringMaterialBridge")
        if supply and supply.RetirePlanSupply then supply:RetirePlanSupply(key,"OWNER_GOAL_OBSERVED_COMPLETE",context) end
        return {key=key,profession=profession,status="complete",actionKind="complete",
            action="Profession skill goal reached.",materials={},readOnly=true,
            executionEligible=false,nativeDispatchAllowed=false,goalObserved=true,
            strategy=selectedStrategy()}
    end
    local dataset = routeFor(key)
    local provider=JLP:GetModule("ProfessionDatasetProvider")
    local reference=not dataset and provider and provider.GetReferenceSnapshot and provider:GetReferenceSnapshot(key) or nil
    local plan=self:BuildProfessionPlanForDataset(key, profession, dataset)
    if plan then
        plan.strategy=selectedStrategy()
        plan.routeSelection=plan.step and plan.step.routeSelection or nil
    end
    if not dataset and profession and reference then
        -- Reference is a genuine actionable UI state, not an invented craft
        -- recipe, material basket, skill-up prediction or execution receipt.
        plan={key=key,profession=profession,status="reference-only",
            actionKind="reference",materials={},readOnly=true,
            nativeDispatchAllowed=false,executionEligible=false,plannerEligible=false,
            action="Inspect the source-backed profession guide and verify the next step in game.",
            referenceOnly=true}
    end
    if plan and plan.actionKind=="blocked" and dataset and
        (dataset.readOnly==true or dataset.readOnlyRouteFallback==true) then
        -- A documented NEXT interval is useful as a targeted research task,
        -- even when today's skill falls in a GAP. Never misrepresent the next
        -- historical recipe as learned/available or infer the missing steps.
        local skill=profession and tonumber(profession.skill)
        local nextPosition=nextDocumentedRoutePosition(dataset,skill)
        if nextPosition then
            plan.status="reference-only"
            plan.actionKind="reference"
            plan.referenceOnly=true
            plan.readOnly=true
            plan.executionEligible=false
            plan.nativeDispatchAllowed=false
            plan.plannerEligible=false
            plan.routeAuthorityEnabled=false
            plan.materials={}
            plan.step=nil
            plan.routeQualification="INCOMPLETE"
            plan.referencePosition=nextPosition
            plan.referenceGap={fromSkill=skill,toSkill=nextPosition.fromSkill,
                reason="NO_DOCUMENTED_CURRENT_SKILL_STEP"}
            plan.action=string.format(
                "No documented route from skill %d to %d. Next source reference: %s (%d-%d). Verify an eligible step for the uncovered interval before proceeding; the later recipe is NOT authorized for crafting.",
                skill,nextPosition.fromSkill,nextPosition.recipe,
                nextPosition.fromSkill,nextPosition.toSkill)
        end
    end
    if plan and dataset and dataset.readOnlyRouteFallback==true then
        plan.readOnlyRouteFallback=true
        plan.referenceOnly=true
        plan.readOnly=true
        plan.executionEligible=false
        plan.nativeDispatchAllowed=false
        -- A known uncovered current-skill gap cannot become an eligible
        -- Planner route simply because the dataset is a historical fallback.
        plan.plannerEligible=plan.referenceGap==nil
        plan.fallbackSourceBuild=dataset.originalSourceBuild
        plan.fallbackReason=dataset.fallbackReason
        plan.advisoryStepAction=plan.action
        if plan.actionKind=="craft" and not plan.p1OneCraft then
            plan.action="Historical build "..tostring(dataset.originalSourceBuild or "unknown")..
                " route estimate; verify the recipe and reagents for the current client."
        end
    end
    if plan and plan.actionKind=="reference" and not reference and provider then reference=provider:GetReferenceSnapshot(key) end
    if plan then
        plan.referenceSnapshot=reference
        local current=reference and reference.current
        local count=current and tonumber(current.recipeCandidates)
        if count and plan.actionKind=="reference" then
            -- Catalogue counts enrich the reference, but MUST NOT replace an
            -- actionable, interval-specific verification from the Planner.
            plan.referenceRecipeCandidates=count
            if not plan.referencePosition then
                plan.action=string.format("Read-only build %s catalogue: %d recipe candidates. Verify live recipe access and next steps.",
                    tostring(reference.currentSourceBuild),count)
            end
            local crosscheck=reference.alchemySourceCrosscheck
            if key=="ALCHEMY" and crosscheck then
                plan.alchemySourceCrosscheck=crosscheck
                if not plan.referencePosition then
                    plan.action=plan.action..string.format(
                        " Historical %s route: %d/%d recipe/reagent records match 70450; progression and crafting remain unverified.",
                        tostring(crosscheck.historicalSourceBuild),crosscheck.matched,crosscheck.stepCount)
                end
            elseif key=="ALCHEMY" and reference.alchemySourceCrosscheckError and
                not plan.referencePosition then
                plan.action=plan.action.." Historical route crosscheck unavailable; verify recipe source evidence."
            end
        end
    end
    -- The unified static catalogue is the shared read-only source for visible
    -- recipe evidence. Never override the protected dataset or plan authority.
    if plan and plan.actionKind=="craft" and type(plan.step)=="table" then
        local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
        if catalogue then
            local build,buildEvidence=catalogue:GetObservedClientBuild()
            local record,kind=catalogue:ForPlanStep(key,plan.step,build)
            plan.catalogueClientBuild=build
            plan.catalogueBuildEvidence=buildEvidence
            local pilot,pilotReason=catalogue:ForPrivatePilotPlanStep(key,plan.step,build)
            plan.privateResearchPilot=pilot
            plan.privateResearchPilotReason=pilotReason
            -- Sidecar consumers must share exactly this canonical raw identity.
            -- No requirements/stock/price/source/dispatch authority is modified.
            plan.privateResearchAdvisory=nil
            plan.privateResearchMaterialPreview=nil
            plan.privateResearchAcquisitionPreview=nil
            if pilot and type(pilot.spellID)=="number" and
                type(catalogue.GetPrivateResearchAdvisory)=="function" then
                local advisory=catalogue:GetPrivateResearchAdvisory(key,pilot.spellID,build)
                plan.privateResearchAdvisory=advisory
                local materials=JLP:GetModule("MaterialCatalog")
                if materials and type(materials.GetPrivateResearchReagentPreview)=="function" then
                    plan.privateResearchMaterialPreview=materials:GetPrivateResearchReagentPreview(key,pilot.spellID,build)
                end
                local acquisition=JLP:GetModule("AcquisitionPlanner")
                if acquisition and type(acquisition.GetPrivateResearchAcquisitionPreview)=="function" then
                    plan.privateResearchAcquisitionPreview=acquisition:GetPrivateResearchAcquisitionPreview(key,pilot.spellID,build)
                end
            end
            plan.catalogueEvidence=record
            plan.catalogueEvidenceKind=kind
            local id=plan.step.recipeID or plan.step.spellID
            plan.catalogueFieldReceipt=nil
            if type(id)=="number" and type(catalogue.GetRecipeFieldReceipt)=="function" then
                plan.catalogueFieldReceipt=catalogue:GetRecipeFieldReceipt(key,id,build)
            end
            plan.catalogueProfessionSnapshot=nil
            if type(catalogue.GetProfessionDataSnapshot)=="function" then
                plan.catalogueProfessionSnapshot=catalogue:GetProfessionDataSnapshot(key,build)
            end
            -- Ephemeral read-only reagent display. This must NOT replace the
            -- requirement planner, stock model, native craft input or pricing.
            plan.catalogueClientObservedReagents=nil
            plan.catalogueClientObservedReagentReason=nil
            if kind=="CLIENT_OBSERVED_SPELL_ID" and type(record)=="table" and
                record.reagentObservationComplete~=true then
                plan.catalogueClientObservedReagentReason=record.reagentObservationReason or "CLIENT_REAGENTS_UNKNOWN"
            end
            if kind=="CLIENT_OBSERVED_SPELL_ID" and type(record)=="table" and
                record.reagentObservationComplete==true and type(record.reagents)=="table" then
                local rows={}
                for _,reagent in ipairs(record.reagents) do
                    rows[#rows+1]={itemID=reagent.itemID,perCraft=reagent.quantity}
                end
                plan.catalogueClientObservedReagents=rows
            end
            -- An independently admitted actor is advisory only. Keep legacy
            -- step/source and the protected planning result untouched.
            plan.catalogueAcquisition=nil
            if record and record.state=="SOURCE_QUALIFIED" and record.verifiedAcquisition then
                local resolver=JLP:GetModule("SourceResolver")
                local id=plan.step.recipeID or plan.step.spellID
                if resolver and type(id)=="number" then
                    plan.catalogueAcquisition=resolver:GetRecipeSource(key,id)
                end
            end
            -- No nativeDispatchAllowed/executionEligible mutation here.
        end
    end
    -- P1-184: Dynamic, build-independent source catalogue recommendation.
    -- Never promote a selected advisory recipe to native action authority.
    local universal=JLP:GetModule("UniversalCurrentStep")
    if universal and type(universal.Apply)=="function" then
        plan=universal:Apply(key,plan,profession,dataset)
    end
    local supply=JLP:GetModule("GatheringMaterialBridge")
    if supply and supply.ApplyToPlan then plan=supply:ApplyToPlan(key,plan,context) end
    local acquisition=JLP:GetModule("AcquisitionPlanner")
    if acquisition and acquisition.ApplyServicesToPlan then plan=acquisition:ApplyServicesToPlan(key,plan,context) end
    local travel=JLP:GetModule("CurrentStepTravelBridge")
    if travel and travel.AttachPlan and not (context and context.navigationRequested==false) then travel:AttachPlan(key,plan) end
    -- Complete read-only Current Step contract, including training and
    -- reference/gathering. Never turn this stage selection into native rights.
    local chain=JLP:GetModule("CurrentStepCompletionChain")
    if chain and chain.Attach then
        local current=type(plan.recommendedCurrentStep)=="table" and
            plan.recommendedCurrentStep or nil
        if not current and plan.actionKind=="train" then
            local info=plan.step and plan.step.trainer
            current={kind="train",rank=info and info.rank,
                navigation=plan.currentStepNavigation}
        elseif not current and plan.actionKind=="learn" then
            current={kind="learn",navigation=plan.currentStepNavigation}
        elseif not current and plan.actionKind=="complete" then
            current={kind="complete"}
        end
        chain:Attach(key,current,plan)
    end
    return plan
end

-- Pure coverage computation: a target skill is not a route proof. The public
-- route may have holes; do not invent bridging crafts or discard valid segments.
local function measureRouteCoverage(segments, fromSkill, targetSkill)
    local spans={}
    for _,segment in ipairs(segments or {}) do
        local lo=tonumber(segment.skill)
        local hi=tonumber(segment.skillTarget)
        if lo and hi and hi>lo then
            spans[#spans+1]={lo=lo,hi=hi}
        end
    end
    table.sort(spans,function(a,b)
        if a.lo~=b.lo then return a.lo<b.lo end
        return a.hi>b.hi
    end)
    local cursor=math.max(0,tonumber(fromSkill) or 0)
    local target=math.max(cursor,tonumber(targetSkill) or cursor)
    local gaps={}
    for _,span in ipairs(spans) do
        if span.lo>cursor then
            local toSkill=math.min(span.lo,target)
            if toSkill>cursor then
                gaps[#gaps+1]={fromSkill=cursor,toSkill=toSkill,reason="NO_QUALIFIED_ROUTE_STEP"}
            end
        end
        if span.hi>cursor and span.lo<target then
            cursor=math.min(span.hi,target)
        end
    end
    if cursor<target then
        gaps[#gaps+1]={fromSkill=cursor,toSkill=target,reason="NO_QUALIFIED_ROUTE_STEP"}
    end
    return #gaps==0,gaps
end

-- P1 PrimaryCoverageEnvelope: one derived, read-only evidence contract.
-- Geometrical route coverage does not prove crafts, sourcing, learned state,
-- craft counts, cost, or native authority. No duplicated persistent state.
local function finalizeScopeCoverage(plan, dataset, providerReason)
    local datasetStatus
    if type(plan.profession)~="table" then
        datasetStatus="PROFESSION_STATE_UNAVAILABLE"
    elseif type(dataset)~="table" then
        datasetStatus="DATASET_UNAVAILABLE"
    elseif dataset.readOnlyRouteFallback==true then
        datasetStatus="HISTORICAL_REFERENCE"
    elseif dataset.readOnly==true or dataset.productionCandidate==true or
        dataset.executionEligible==false then
        datasetStatus="READ_ONLY_CANDIDATE"
    else
        datasetStatus="ROUTE_DATASET_PRESENT"
    end

    local gaps=plan.routeCoverageGaps or {}
    local intervalKnown=type(dataset)=="table" and type(plan.profession)=="table" and
        plan.routeCoverageStatus~="CURRENT_STEP_UNAVAILABLE"
    -- A verified 1-300 goal is a character observation, NOT recipe-route
    -- coverage. Validate stable profession identity, an observed finite skill
    -- and rank cap, and reject cached/unknown snapshots. No dataset required.
    local profession=plan.profession
    local registry=JLP:GetModule("ProfessionRegistry")
    local identity=registry and registry.NormalizeKey and registry:NormalizeKey(plan.key)
    local observedKey=registry and registry.NormalizeKey and type(profession)=="table" and
        registry:NormalizeKey(profession.key)
    local observedSkill=type(profession)=="table" and profession.skill or nil
    local observedCap=type(profession)=="table" and profession.maxSkill or nil
    local validSkill=type(observedSkill)=="number" and observedSkill==observedSkill and
        observedSkill~=math.huge and observedSkill~=-math.huge
    local validCap=type(observedCap)=="number" and observedCap==observedCap and
        observedCap~=math.huge and observedCap~=-math.huge
    local stableID=identity and type(registry.Get)=="function" and registry:Get(identity) or nil
    local skillLineOK=not profession or profession.skillLine==nil or
        (stableID and tonumber(profession.skillLine)==tonumber(stableID.skillLineID))
    local enumOK=not profession or profession.professionEnum==nil or
        (stableID and tonumber(profession.professionEnum)==tonumber(stableID.professionEnum))
    local skillComplete=identity~=nil and observedKey==identity and
        type(profession)=="table" and profession.cached~=true and
        skillLineOK and enumOK and validSkill and validCap and observedSkill>=300 and observedCap>=300 and
        tonumber(plan.currentSkill)==observedSkill
    local coverageStatus=skillComplete and "COMPLETE" or
        not intervalKnown and "UNKNOWN" or
        plan.routeCoverageComplete==true and "INTERVAL_COVERED" or "INCOMPLETE"
    local buildInfo=JLP:GetModule("ClientBuildInfo")
    local clientBuild=buildInfo and buildInfo.GetBuildNumber and buildInfo:GetBuildNumber() or nil
    local sourceBuild=dataset and tonumber(dataset.sourceBuild) or nil
    -- A route's SOURCE build is provenance, never a required LIVE build.
    -- Fresh recipe eligibility and craft-rate receipts remain independent gates.
    local sourceProvenanceKnown=sourceBuild~=nil and sourceBuild>0 and
        sourceBuild==math.floor(sourceBuild)
    local buildMatch=sourceBuild~=nil and tonumber(clientBuild)==sourceBuild
    local rateQualified=plan.craftEstimatesFullyQualified==true
    local recipeQualified=plan.recipeEligibilityFullyQualified==true
    local routeQualified=intervalKnown and plan.routeCoverageComplete==true and
        rateQualified and recipeQualified and sourceProvenanceKnown and
        dataset.routeAuthorityEnabled==true and dataset.plannerEligible==true and
        dataset.readOnlyRouteFallback~=true and dataset.referenceOnly~=true
    local routeQualification=skillComplete and "NOT_APPLICABLE" or
        routeQualified and "QUALIFIED" or
        not intervalKnown and "UNKNOWN" or "UNVERIFIED"

    local selections={}
    if plan.currentStep and plan.currentStep.routeSelection then
        selections[1]=plan.currentStep.routeSelection
    else
        for _,segment in ipairs(plan.segments or {}) do
            if segment.routeSelection then selections[#selections+1]=segment.routeSelection end
        end
    end
    local comparable=#selections>0
    for _,choice in ipairs(selections) do
        if not (tonumber(choice.qualifiedAlternatives) and choice.qualifiedAlternatives>0 and
            (choice.reason=="QUALIFIED_TIME_COMPARISON" or
             choice.reason=="QUALIFIED_COST_COMPARISON" or
             choice.reason=="SELF_FOUND_QUALIFIED_SOURCE")) then
            comparable=false
        end
    end
    -- A comparison receipt can never qualify a historic or partial route.
    local strategyStatus=skillComplete and "NOT_APPLICABLE" or
        comparable and routeQualified and "QUALIFIED" or "UNVERIFIED"
    local nextCode,nextAction
    if skillComplete then
        nextCode="COMPLETE"
        nextAction="Profession skill 300 is already observed; no further 1-300 progression needed."
    elseif datasetStatus=="PROFESSION_STATE_UNAVAILABLE" then
        nextCode="VERIFY_PROFESSION_STATE"
        nextAction="Refresh the current character's profession state and retry the plan."
    elseif datasetStatus=="DATASET_UNAVAILABLE" then
        nextCode="VERIFY_DATASET"
        nextAction="Inspect the profession reference guide and verify a build-qualified progression dataset."
    elseif coverageStatus=="UNKNOWN" then
        nextCode="VERIFY_COVERAGE"
        nextAction="Verify the current profession skill and its documented route coverage."
    elseif coverageStatus=="INCOMPLETE" then
        nextCode="VERIFY_ROUTE_INTERVAL"
        nextAction="Review the uncovered skill intervals and verify eligible progression steps."
    elseif routeQualification~="QUALIFIED" then
        nextCode=not recipeQualified and "VERIFY_RECIPE_ACCESS" or
            not rateQualified and "VERIFY_CRAFT_RATE" or "VERIFY_ROUTE_EVIDENCE"
        nextAction=nextCode=="VERIFY_RECIPE_ACCESS" and
            "Verify learned recipes, current-build skill requirements and non-gray difficulty." or
            nextCode=="VERIFY_CRAFT_RATE" and
            "Verify craft quantities, materials and skill-up evidence before calculating a budget." or
            "Verify source provenance and fresh recipe/skill-up evidence on the running client."
    elseif strategyStatus~="QUALIFIED" then
        nextCode="VERIFY_STRATEGY_COMPARISON"
        nextAction="Verify comparable alternatives and sourcing evidence before claiming a strategy optimum."
    else
        nextCode="REVIEW_ADVISORY"
        nextAction="Review the qualified advisory plan and verify current inventory before any manual action."
    end
    -- Blacksmithing references: the next *manual*, currently observed craft may be
    -- actionable even though the surrounding reference route is NOT qualified.
    -- Carry that distinction into the EXISTING envelope consumed by Guide and
    -- Acquisition; never mark coverage/budget/strategy/native as qualified.
    if (plan.key=="BLACKSMITHING" or plan.key=="ENGINEERING" or plan.key=="LEATHERWORKING") and plan.scope=="current" and
       type(dataset)=="table" and
       (dataset.contract=="blacksmithing-1-75-db70450-field-reference-v1" or
        dataset.contract=="engineering-1-75-db70450-field-reference-v1" or
        dataset.contract=="leatherworking-1-75-db70450-field-reference-v1") and
       type(plan.currentStep)=="table" then
        local one=plan.currentStep
        if one.kind=="craft" and one.p1OneCraft==true then
            nextCode="ONE_MANUAL_CRAFT_ADVISORY"
            nextAction="Observed learned, non-gray "..tostring(one.recipe)..
                " (SpellID "..tostring(one.recipeID)..") with verified live bag reagents: "..
                "consider ONE manual craft, then observe actual skill and replan. "..
                "No guaranteed skill-up, verified rate, bulk budget or native authorization."
        elseif one.kind=="verify" and one.p1NextAction then
            nextCode=plan.key=="ENGINEERING" and "VERIFY_ENGINEERING_PREREQUISITE" or
                plan.key=="LEATHERWORKING" and "VERIFY_LEATHERWORKING_PREREQUISITE" or "VERIFY_BLACKSMITHING_PREREQUISITE"
            nextAction=one.p1NextAction
        end
    end
    local envelope={contract="primary-coverage-envelope-v1",key=plan.key,
        scope=plan.scope,strategy=plan.strategy,datasetStatus=datasetStatus,
        datasetReason=providerReason or plan.routeCoverageReason,
        sourceBuild=sourceBuild,clientBuild=clientBuild,
        buildEvidenceStatus=not clientBuild and "CLIENT_BUILD_UNKNOWN" or
            not sourceBuild and "SOURCE_BUILD_UNKNOWN" or
            buildMatch and "SOURCE_BUILD_MATCH" or "SOURCE_BUILD_MISMATCH",
        coverageStatus=coverageStatus,intervalGapsKnown=intervalKnown,
        intervalGaps=gaps,routeQualification=routeQualification,
        recipeEvidenceStatus=plan.recipeEligibilityStatus or "UNKNOWN",
        craftRateStatus=plan.craftEstimateStatus or "UNKNOWN",
        strategyComparisonStatus=strategyStatus,
        nextActionCode=nextCode,nextAction=nextAction,
        readOnly=true,nativeDispatchAllowed=false,
        materialBudgetQualified=routeQualified and rateQualified,
        -- A coverage receipt never grants native execution rights.
        executionEligible=false}
    plan.coverageEnvelope=envelope
    plan.datasetStatus=datasetStatus
    plan.coverageStatus=coverageStatus
    plan.routeQualification=routeQualification
    plan.strategyComparisonStatus=strategyStatus
    plan.nextAction=nextAction
    plan.nextActionCode=nextCode
    plan.routeCoverageGapsKnown=intervalKnown
    return plan
end

function Planner:GetScopePlan(key, professionState, scope, strategyOverride)
    local prerequisite=prerequisitePlan(key)
    if prerequisite then return prerequisite end
    scope = normalizeScope(scope)
    local strategy=selectedStrategy(strategyOverride)
    local dataset, datasetReason = routeFor(key)
    if type(professionState) ~= "table" then
        return finalizeScopeCoverage({
            key=key,strategy=strategy,scope=scope,scopeLabel=scopeLabel(scope),segments={},trainers={},
            routeCoverageComplete=false,routeCoverageStatus="PROFESSION_STATE_UNAVAILABLE",
            routeCoverageReason="profession-state-unavailable",routeCoverageGaps={},
            routeCoverageAdvisory=true,nativeDispatchAllowed=false,
        }, dataset, datasetReason)
    end
    if type(dataset) ~= "table" then
        -- Keep the provider's actual refusal/missing-data reason. A missing
        -- dataset is not an empty, qualified route and has no provable gaps.
        return finalizeScopeCoverage({
            key=key,strategy=strategy,profession=professionState,scope=scope,scopeLabel=scopeLabel(scope),
            currentSkill=tonumber(professionState.skill),
            targetSkill=scope=="to_300" and 300 or
                (scope=="next_trainer" and tonumber(professionState.maxSkill) or nil),
            segments={},trainers={},dataset=nil,
            routeCoverageComplete=false,routeCoverageStatus="DATASET_UNAVAILABLE",
            routeCoverageReason=datasetReason or "planner-dataset-unavailable",
            routeCoverageGaps={},routeCoverageAdvisory=true,nativeDispatchAllowed=false,
        }, dataset, datasetReason)
    end

    local skill = tonumber(professionState.skill) or 0
    local cap = tonumber(professionState.maxSkill) or 0
    local targetSkill
    if scope == "current" then
        local current = self:GetCurrentStep(key, professionState, dataset, strategy)
        if not current then
            return finalizeScopeCoverage({
                key=key,strategy=strategy,profession=professionState,scope=scope,scopeLabel=scopeLabel(scope),
                currentSkill=skill,segments={},trainers={},dataset=dataset,
                routeCoverageComplete=false,routeCoverageStatus="CURRENT_STEP_UNAVAILABLE",
                routeCoverageReason="current-step-unavailable",routeCoverageGaps={},
                routeCoverageAdvisory=true,nativeDispatchAllowed=false,
            }, dataset, datasetReason)
        end
        -- Step availability and recipe evidence are independent contracts.
        -- In particular, a verify step is not recipe-qualified just because
        -- its kind is different from craft. Train/complete do not assess any
        -- recipe and must not claim recipe qualification either.
        local recipeStatus, recipeFullyQualified, recipeIssues
        if current.kind == "craft" then
            recipeFullyQualified=type(current.skillEligibility)=="table" and
                current.skillEligibility.progressionQualified==true
            recipeStatus=current.skillEligibilityStatus or "RECIPE_ELIGIBILITY_UNAVAILABLE"
            recipeIssues=recipeFullyQualified and {} or
                {current.skillEligibility or {status=recipeStatus}}
        elseif current.kind == "verify" then
            recipeFullyQualified=false
            recipeStatus=current.skillEligibilityStatus or "RECIPE_ELIGIBILITY_UNAVAILABLE"
            recipeIssues={current.skillEligibility or {status=recipeStatus}}
        else
            recipeFullyQualified=false
            recipeStatus="NOT_APPLICABLE"
            recipeIssues={}
        end
        local estimateGaps={}
        local estimateStatus,estimateQualified="NOT_APPLICABLE",false
        local estimateIssues={}
        if current.kind=="craft" or
            (current.kind=="verify" and
                (current.skillEligibilityStatus=="CRAFT_COUNT_UNVERIFIED" or
                 current.skillEligibilityStatus=="ROUTE_EVIDENCE_UNVERIFIED" or
                 (current.rawStep and (current.rawStep.sourceQualificationContract==
                  "tailoring-145-153-formal-white-shirt-evidence-p02m-v1" or
                  (current.rawStep.sourceQualificationContract==
                  "tailoring-153-160-small-silk-pack-evidence-p02n-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-160-170-azure-silk-cloak-evidence-p02o-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-170-180-crimson-silk-vest-evidence-p02p-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-180-190-crimson-silk-pantaloons-evidence-p02q-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-190-195-crimson-silk-pantaloons-evidence-p02r-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-195-200-black-mageweave-gloves-evidence-p02r-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-200-205-black-mageweave-gloves-evidence-p02s-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-205-210-black-mageweave-headband-evidence-p02s-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-210-220-black-mageweave-headband-evidence-p02t-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-220-225-black-mageweave-headband-evidence-p02u-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-225-230-runecloth-belt-evidence-p02u-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-230-240-runecloth-belt-evidence-p02v-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-240-245-runecloth-belt-evidence-p02w-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-245-250-brightcloth-cloak-evidence-p02w-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-250-260-brightcloth-cloak-evidence-p02x-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-260-262-brightcloth-cloak-evidence-p02y-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-262-270-runecloth-pants-evidence-p02y-v1"))))) then
            estimateStatus,estimateQualified=craftEstimateEvidence(
                current.kind=="craft" and current or current.rawStep)
            -- A source-invalid craft count has already been transformed into
            -- a verify step; do not mislabel that failure as NOT_APPLICABLE.
            if current.kind=="verify" and
                current.skillEligibilityStatus=="CRAFT_COUNT_UNVERIFIED" then
                estimateStatus,estimateQualified="INVALID",false
            end
            if not estimateQualified then
                estimateIssues[1]={recipe=current.recipe,recipeID=current.recipeID,
                    fromSkill=skill,toSkill=current.skillTarget,
                    reason="CRAFT_ESTIMATE_"..estimateStatus,
                    craftCountAuthority=current.craftCountAuthority}
            end
        end
        if (current.kind=="craft" or
            (current.kind=="verify" and
                (current.skillEligibilityStatus=="ROUTE_EVIDENCE_UNVERIFIED" or
                 (current.rawStep and (current.rawStep.sourceQualificationContract==
                  "tailoring-145-153-formal-white-shirt-evidence-p02m-v1" or
                  (current.rawStep.sourceQualificationContract==
                  "tailoring-153-160-small-silk-pack-evidence-p02n-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-160-170-azure-silk-cloak-evidence-p02o-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-170-180-crimson-silk-vest-evidence-p02p-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-180-190-crimson-silk-pantaloons-evidence-p02q-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-190-195-crimson-silk-pantaloons-evidence-p02r-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-195-200-black-mageweave-gloves-evidence-p02r-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-200-205-black-mageweave-gloves-evidence-p02s-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-205-210-black-mageweave-headband-evidence-p02s-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-210-220-black-mageweave-headband-evidence-p02t-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-220-225-black-mageweave-headband-evidence-p02u-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-225-230-runecloth-belt-evidence-p02u-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-230-240-runecloth-belt-evidence-p02v-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-240-245-runecloth-belt-evidence-p02w-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-245-250-brightcloth-cloak-evidence-p02w-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-250-260-brightcloth-cloak-evidence-p02x-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-260-262-brightcloth-cloak-evidence-p02y-v1" or
                  current.rawStep.sourceQualificationContract==
                  "tailoring-262-270-runecloth-pants-evidence-p02y-v1"))))))
            and current.craftCountQualified==false and current.planningEstimateQualified~=true then
            local gapFrom=math.max(skill,tonumber(current.craftEstimateGapFromSkill) or skill)
            local gapTo=math.min(tonumber(current.skillTarget) or skill,
                tonumber(current.craftEstimateGapToSkill) or (current.skillTarget or skill))
            if gapTo>gapFrom then estimateGaps[1]={fromSkill=gapFrom,toSkill=gapTo,
                reason="CRAFT_RATE_UNVERIFIED",recipe=current.recipe,recipeID=current.recipeID} end
        end
        return finalizeScopeCoverage({
            key = key,
            strategy = strategy,
            routeSelection = current and current.routeSelection,
            p1Prerequisite = current and current.p1Prerequisite,
            p1NextAction = current and current.p1NextAction,
            profession = professionState,
            scope = scope,
            scopeLabel = scopeLabel(scope),
            currentSkill = skill,
            targetSkill = current.skillTarget or skill,
            segments = current.kind == "craft" and {current} or {},
            trainers = current.kind == "train" and {current.trainer} or {},
            currentStep = current,
            dataset = current.dataset,
            routeCoverageComplete=current.kind~="verify",
            routeCoverageStatus=current.kind=="verify" and "RECIPE_SKILL_GATE_UNQUALIFIED" or "CURRENT_STEP_AVAILABLE",
            routeCoverageReason=current.kind=="verify" and current.skillEligibilityStatus or nil,
            recipeEligibilityFullyQualified=recipeFullyQualified,
            recipeEligibilityStatus=recipeStatus,
            recipeEligibilityIssues=recipeIssues,
            craftEstimatesFullyQualified=estimateQualified,
            craftEstimateStatus=estimateStatus,
            craftEstimateIssues=estimateIssues,
            craftEstimateGaps=estimateGaps,
            routeCoverageGaps=current.kind=="verify" and {{fromSkill=skill,toSkill=current.skillTarget,reason=current.skillEligibilityStatus}} or {},
            routeCoverageAdvisory=true,nativeDispatchAllowed=false,
        }, dataset, datasetReason)
    elseif scope == "next_trainer" then
        targetSkill = cap > 0 and math.min(cap, 300) or 300
    else
        targetSkill = 300
    end

    local segments = {}
    local scopeEligibilityIssues={}
    local scopeCraftEstimateGaps={}
    local scopeCraftEstimateIssues={}
    local allCraftEstimatesQualified=true
    local scopeCraftEstimateStatus="NOT_APPLICABLE"
    local exposedScopeDataset=dataset
    if targetSkill > skill then
        for index, step in ipairs(progressionSteps(key,dataset)) do
            local stepMin = tonumber(step.skillMin) or 0
            local stepTarget = tonumber(step.skillTarget) or stepMin
            local fromSkill = math.max(skill, stepMin)
            local toSkill = math.min(targetSkill, stepTarget)
            if toSkill > fromSkill then
                local choice
                step,choice=selectStrategyStep(key,dataset,step,fromSkill,toSkill,strategy)
                if (step.sourceQualificationContract=="tailoring-107-125-source-v1" or (step.sourceQualificationContract=="tailoring-125-225-source-v1" or step.sourceQualificationContract=="tailoring-225-300-source-v1")) and step.requiresLearningVerification then
                    scopeEligibilityIssues[#scopeEligibilityIssues+1]={recipe=step.recipe,recipeID=step.recipeID,
                        fromSkill=fromSkill,toSkill=toSkill,reason="RECIPE_LEARNING_"..tostring(step.planningLearnedState)}
                end
                local eligibility=skillEligibility(key,step,fromSkill,toSkill)
                if eligibility.minimumSkill and eligibility.minimumSkill<300 and
                    eligibility.minimumSkill>fromSkill and eligibility.minimumSkill<toSkill then
                    scopeEligibilityIssues[#scopeEligibilityIssues+1]={
                        recipe=step.recipe,recipeID=step.recipeID,fromSkill=fromSkill,
                        toSkill=eligibility.minimumSkill,
                        reason="BAND_START_BELOW_REQUIRED_SKILL",
                        minimumSkill=eligibility.minimumSkill}
                    fromSkill=eligibility.minimumSkill
                    eligibility=skillEligibility(key,step,fromSkill,toSkill)
                end
                if not eligibility.progressionAllowed then
                    -- A confirmed ineligible band becomes a genuine coverage gap;
                    -- no guessed bridging recipe or shopping commitment.
                    scopeEligibilityIssues[#scopeEligibilityIssues+1]={
                        recipe=step.recipe,recipeID=step.recipeID,
                        fromSkill=math.max(skill,tonumber(step.skillMin) or 0),
                        toSkill=toSkill,reason=eligibility.status,
                        minimumSkill=eligibility.minimumSkill}
                    -- P0.2L/P0.2M: minimum/route authority and historical
                    -- craft-rate evidence are independent, never a bulk budget.
                    if key=="TAILORING" and
                        ((step.deferredProgression==true and step.readOnly==true) or
                         (step.recipeID==3852 and eligibility.status=="ROUTE_EVIDENCE_UNVERIFIED") or
                         (step.recipeID==3871 and step.skillMin==145 and
                          step.sourceQualificationContract=="tailoring-145-153-formal-white-shirt-evidence-p02m-v1") or
                         (step.recipeID==3813 and step.skillMin==153 and
                          step.sourceQualificationContract=="tailoring-153-160-small-silk-pack-evidence-p02n-v1") or
                         (step.recipeID==8786 and step.skillMin==160 and
                          step.sourceQualificationContract=="tailoring-160-170-azure-silk-cloak-evidence-p02o-v1") or
                         (step.recipeID==8791 and step.skillMin==170 and
                          step.sourceQualificationContract=="tailoring-170-180-crimson-silk-vest-evidence-p02p-v1") or
                         (step.recipeID==8799 and step.skillMin==180 and
                          step.sourceQualificationContract=="tailoring-180-190-crimson-silk-pantaloons-evidence-p02q-v1") or
                         (step.recipeID==8799 and step.skillMin==190 and
                          step.sourceQualificationContract=="tailoring-190-195-crimson-silk-pantaloons-evidence-p02r-v1") or
                         (step.recipeID==12053 and step.skillMin==195 and
                          step.sourceQualificationContract=="tailoring-195-200-black-mageweave-gloves-evidence-p02r-v1") or
                         (step.recipeID==12053 and step.skillMin==200 and
                          step.sourceQualificationContract=="tailoring-200-205-black-mageweave-gloves-evidence-p02s-v1") or
                         (step.recipeID==12072 and step.skillMin==205 and
                          step.sourceQualificationContract=="tailoring-205-210-black-mageweave-headband-evidence-p02s-v1") or
                         (step.recipeID==12072 and step.skillMin==210 and
                          step.sourceQualificationContract=="tailoring-210-220-black-mageweave-headband-evidence-p02t-v1") or
                         (step.recipeID==12072 and step.skillMin==220 and
                          step.sourceQualificationContract=="tailoring-220-225-black-mageweave-headband-evidence-p02u-v1") or
                         (step.recipeID==18402 and step.skillMin==225 and
                          step.sourceQualificationContract=="tailoring-225-230-runecloth-belt-evidence-p02u-v1") or
                         (step.recipeID==18402 and step.skillMin==230 and
                          step.sourceQualificationContract=="tailoring-230-240-runecloth-belt-evidence-p02v-v1") or
                         (step.recipeID==18402 and step.skillMin==240 and
                          step.sourceQualificationContract=="tailoring-240-245-runecloth-belt-evidence-p02w-v1") or
                         (step.recipeID==18420 and step.skillMin==245 and
                          step.sourceQualificationContract=="tailoring-245-250-brightcloth-cloak-evidence-p02w-v1") or
                         (step.recipeID==18420 and step.skillMin==250 and
                          step.sourceQualificationContract=="tailoring-250-260-brightcloth-cloak-evidence-p02x-v1") or
                         (step.recipeID==18420 and step.skillMin==260 and
                          step.sourceQualificationContract=="tailoring-260-262-brightcloth-cloak-evidence-p02y-v1") or
                         (step.recipeID==18438 and step.skillMin==262 and
                          step.sourceQualificationContract=="tailoring-262-270-runecloth-pants-evidence-p02y-v1")) and
                        step.craftCountQualified==false then
                        allCraftEstimatesQualified=false
                        scopeCraftEstimateStatus="UNVERIFIED"
                        scopeCraftEstimateGaps[#scopeCraftEstimateGaps+1]={
                            fromSkill=fromSkill,toSkill=toSkill,
                            reason="CRAFT_RATE_UNVERIFIED",recipe=step.recipe,recipeID=step.recipeID}
                        scopeCraftEstimateIssues[#scopeCraftEstimateIssues+1]={
                            recipe=step.recipe,recipeID=step.recipeID,fromSkill=fromSkill,toSkill=toSkill,
                            reason="CRAFT_ESTIMATE_UNVERIFIED",
                            craftCountAuthority=step.craftCountAuthority}
                    end
                else
                local changed=choice.changed==true
                local exposedStep=changed and advisoryAuthorityView(step) or step
                local exposedDataset=changed and advisoryAuthorityView(dataset) or dataset
                if changed then exposedScopeDataset=exposedDataset end
                local adaptiveCrafts, estimate, staticCrafts = craftsForRange(key, step, fromSkill, toSkill, skill)
                local craftStatus,craftQualified=craftEstimateEvidence(step)
                if not craftQualified then
                    allCraftEstimatesQualified=false
                    if scopeCraftEstimateStatus=="NOT_APPLICABLE" then
                        scopeCraftEstimateStatus=craftStatus
                    elseif scopeCraftEstimateStatus~=craftStatus then
                        scopeCraftEstimateStatus="MIXED"
                    end
                    scopeCraftEstimateIssues[#scopeCraftEstimateIssues+1]={
                        recipe=step.recipe,recipeID=step.recipeID,
                        fromSkill=fromSkill,toSkill=toSkill,
                        reason="CRAFT_ESTIMATE_"..craftStatus,
                        craftCountAuthority=step.craftCountAuthority}
                elseif scopeCraftEstimateStatus=="NOT_APPLICABLE" then
                    scopeCraftEstimateStatus="QUALIFIED"
                elseif scopeCraftEstimateStatus~="QUALIFIED" then
                    scopeCraftEstimateStatus="MIXED"
                end
                segments[#segments + 1] = {
                    kind = "craft",
                    profession = key,
                    skill = fromSkill,
                    skillTarget = toSkill,
                    routeIndex = tonumber(step.routeIndex) or index,
                    recipe = step.recipe,
                    recipeSource = step.recipeSource or "trainer",
                    sourceInfo = sourceResolver() and sourceResolver():GetRecipeSource(key, step.recipe) or nil,
                    expectedCrafts = step.expectedCrafts,
                    craftCountAuthority=step.craftCountAuthority,
                    craftCountQualified=step.craftCountQualified,
                    planningEstimateQualified=step.planningEstimateQualified==true,
                    planningEstimateBasis=step.planningEstimateQualified and step.craftCountAuthority or nil,
                    planningLearnedState=step.planningLearnedState,requiresLearningVerification=step.requiresLearningVerification,
                    craftCountEvidenceStatus=step.craftCountEvidenceStatus,
                    craftEstimateEvidenceStatus=craftStatus,
                    sourceQualificationContract=step.sourceQualificationContract,
                    outputQuantityReference=step.outputQuantityReference,
                    outputQuantityConflictingReference=step.outputQuantityConflictingReference,
                    outputQuantityEvidence=step.outputQuantityEvidence,
                    outputYieldLiveVerified=step.outputYieldLiveVerified,
                    recipeSourceEvidence=step.recipeSourceEvidence,
                    recipeLearnSourceEvidence=step.recipeLearnSourceEvidence,
                    staticRemainingCrafts = staticCrafts,
                    remainingCrafts = adaptiveCrafts,
                    estimateSource = estimate and estimate.source or "route-static",
                    estimateSourceDetail = estimate and estimate.sourceDetail or "route-static",
                    estimateWeight = estimate and estimate.weight or 0,
                    telemetryEstimate = estimate,
                    telemetry = estimate and estimate.telemetry or nil,
                    materials = step.materials or {},
                    requiredTool = step.requiredTool,
                    evidence = step.evidence or dataset.evidence,
                    dataset = exposedDataset,
                    rawStep = exposedStep,
                    strategy = strategy,
                    routeSelection = choice,
                    recipeID = step.recipeID,
                    plannerEligible = dataset.plannerEligible == true and step.plannerEligible == true or nil,
                    executionEligible = exposedStep.executionEligible,
                    nativeDispatchAllowed = false,
                    routeAuthorityEnabled = exposedDataset.routeAuthorityEnabled == true,
                    readOnly = changed or dataset.readOnly == true or step.readOnly==true,
                    researchAuthority = exposedStep.researchAuthority == true,
                    authority = exposedStep.authority or exposedDataset.authority,
                    skillEligibility=eligibility,skillEligibilityStatus=eligibility.status,
                }
                if step.craftCountQualified==false and step.planningEstimateQualified~=true then
                    local gapFrom=math.max(fromSkill,tonumber(step.craftEstimateGapFromSkill) or fromSkill)
                    local gapTo=math.min(toSkill,tonumber(step.craftEstimateGapToSkill) or toSkill)
                    if gapTo>gapFrom then
                        scopeCraftEstimateGaps[#scopeCraftEstimateGaps+1]={fromSkill=gapFrom,toSkill=gapTo,
                            reason="CRAFT_RATE_UNVERIFIED",recipe=step.recipe,recipeID=step.recipeID}
                    end
                end
                if not eligibility.progressionQualified then
                    scopeEligibilityIssues[#scopeEligibilityIssues+1]={recipe=step.recipe,
                        recipeID=step.recipeID,fromSkill=fromSkill,toSkill=toSkill,
                        reason=eligibility.status,minimumSkill=eligibility.minimumSkill}
                end
                end
            end
        end
    end

    local trainers = {}
    if scope == "next_trainer" then
        if cap > 0 and cap < 300 then
            local gate = findTrainerGate(dataset, cap)
            if gate then trainers[#trainers + 1] = gate end
        end
    else
        local firstRelevantCap = cap > 0 and cap or skill
        for _, gate in ipairs(dataset.trainerGates or {}) do
            local gateCap = tonumber(gate.cap) or 0
            if gateCap >= firstRelevantCap and gateCap < 300 then
                trainers[#trainers + 1] = gate
            end
        end
    end

    -- P1-QAFix: match GetCurrentStep's profession-rank boundary. For a
    -- future to_300 view, expose the trainer as a prerequisite, not an
    -- immediately actionable 150 -> 151 single craft at skill/maxSkill 150/150.
    local p1RankCapReached=key=="TAILORING" and cap>0 and cap<300 and skill>=cap
    local p1RankGate=p1RankCapReached and findTrainerGate(dataset,cap) or nil
    -- P1: only the NEXT observed single craft is covered. Keep all later
    -- 137-190 intervals as real gaps; one observed recipe is no route forecast.
    local p1ScopePrerequisite,p1ScopeNextAction
    if (key=="TAILORING" and skill>=137 and skill<300) or
       (key=="BLACKSMITHING" and skill>=1 and skill<300) or
       (key=="ENGINEERING" and skill>=1 and skill<300 and not dataset.progression) then
        local observed,unresolved,prerequisite
        if key=="BLACKSMITHING" then
            local reference=findRouteStep(dataset,skill)
            observed,unresolved,prerequisite=p1BlacksmithOneCraft(
                key,dataset,professionState,skill,cap,strategy,reference)
        elseif key=="ENGINEERING" then
            local reference=findRouteStep(dataset,skill)
            observed,unresolved,prerequisite=p1EngineeringOneCraft(
                key,dataset,professionState,skill,cap,strategy,reference)
        else
            observed,unresolved,prerequisite=p1TailoringOneCraft(key,dataset,skill,strategy,cap)
        end
        p1ScopePrerequisite=prerequisite
        p1ScopeNextAction=unresolved
        if observed and targetSkill>skill then
            observed.skillTarget=math.min(skill+1,targetSkill)
            segments[#segments+1]=observed
            scopeCraftEstimateGaps[#scopeCraftEstimateGaps+1]={fromSkill=skill,
                toSkill=observed.skillTarget,reason="CRAFT_RATE_UNVERIFIED",
                recipe=observed.recipe,recipeID=observed.recipeID}
            allCraftEstimatesQualified=false
            scopeCraftEstimateStatus="UNVERIFIED"
        end
    end
    local routeComplete,routeGaps=measureRouteCoverage(segments,skill,targetSkill)
    -- P0.2L/P0.2M: consecutive unresolved Tailoring intervals have distinct
    -- evidence causes. Geometrical coverage coalesces them; split only at
    -- documented Tailoring 143 and 145 route boundaries before typing gaps.
    local boundaryStep=key=="TAILORING" and dataset.route and dataset.route[9]
    local formalStep=key=="TAILORING" and dataset.route and dataset.route[10]
    local boundaries={}
    if boundaryStep and boundaryStep.recipeID==3852 and
        boundaryStep.sourceQualificationContract=="tailoring-143-145-gloves-evidence-p02l-v1" then
        boundaries[#boundaries+1]=143
    end
    if formalStep and formalStep.recipeID==3871 and
        formalStep.sourceQualificationContract=="tailoring-145-153-formal-white-shirt-evidence-p02m-v1" then
        boundaries[#boundaries+1]=145
    end
    local smallSilkStep=key=="TAILORING" and dataset.route and dataset.route[11]
    if smallSilkStep and smallSilkStep.recipeID==3813 and
        smallSilkStep.sourceQualificationContract=="tailoring-153-160-small-silk-pack-evidence-p02n-v1" then
        boundaries[#boundaries+1]=153
    end
    local cloakStep=key=="TAILORING" and dataset.route and dataset.route[12]
    if cloakStep and cloakStep.recipeID==8786 and
        cloakStep.sourceQualificationContract=="tailoring-160-170-azure-silk-cloak-evidence-p02o-v1" then
        boundaries[#boundaries+1]=160
    end
    local vestStep=key=="TAILORING" and dataset.route and dataset.route[13]
    if vestStep and vestStep.recipeID==8791 and
        vestStep.sourceQualificationContract=="tailoring-170-180-crimson-silk-vest-evidence-p02p-v1" then
        boundaries[#boundaries+1]=170
    end
    local pantaloonsStep=key=="TAILORING" and dataset.route and dataset.route[14]
    if pantaloonsStep and pantaloonsStep.recipeID==8799 and
        pantaloonsStep.skillMin==180 and pantaloonsStep.skillTarget==190 and
        pantaloonsStep.sourceQualificationContract=="tailoring-180-190-crimson-silk-pantaloons-evidence-p02q-v1" then
        boundaries[#boundaries+1]=180
    end
    local p02rPantaloons=key=="TAILORING" and dataset.route and dataset.route[15]
    if p02rPantaloons and p02rPantaloons.recipeID==8799 and
        p02rPantaloons.skillMin==190 and p02rPantaloons.skillTarget==195 and
        p02rPantaloons.sourceQualificationContract=="tailoring-190-195-crimson-silk-pantaloons-evidence-p02r-v1" then
        boundaries[#boundaries+1]=190
    end
    local p02rGloves=key=="TAILORING" and dataset.route and dataset.route[16]
    if p02rGloves and p02rGloves.recipeID==12053 and
        p02rGloves.skillMin==195 and p02rGloves.skillTarget==200 and
        p02rGloves.sourceQualificationContract=="tailoring-195-200-black-mageweave-gloves-evidence-p02r-v1" then
        boundaries[#boundaries+1]=195
    end
    local p02sGloves=key=="TAILORING" and dataset.route and dataset.route[17]
    if p02sGloves and p02sGloves.recipeID==12053 and
        p02sGloves.skillMin==200 and p02sGloves.skillTarget==205 and
        p02sGloves.sourceQualificationContract=="tailoring-200-205-black-mageweave-gloves-evidence-p02s-v1" then
        boundaries[#boundaries+1]=200
    end
    local p02sHeadband=key=="TAILORING" and dataset.route and dataset.route[18]
    if p02sHeadband and p02sHeadband.recipeID==12072 and
        p02sHeadband.skillMin==205 and p02sHeadband.skillTarget==210 and
        p02sHeadband.sourceQualificationContract=="tailoring-205-210-black-mageweave-headband-evidence-p02s-v1" then
        boundaries[#boundaries+1]=205
    end
    local p02tHeadband=key=="TAILORING" and dataset.route and dataset.route[19]
    if p02tHeadband and p02tHeadband.recipeID==12072 and
        p02tHeadband.skillMin==210 and p02tHeadband.skillTarget==220 and
        p02tHeadband.sourceQualificationContract=="tailoring-210-220-black-mageweave-headband-evidence-p02t-v1" then
        boundaries[#boundaries+1]=210
    end
    local p02uHeadband=key=="TAILORING" and dataset.route and dataset.route[20]
    if p02uHeadband and p02uHeadband.recipeID==12072 and
        p02uHeadband.skillMin==220 and p02uHeadband.skillTarget==225 and
        p02uHeadband.sourceQualificationContract=="tailoring-220-225-black-mageweave-headband-evidence-p02u-v1" then
        boundaries[#boundaries+1]=220
    end
    local p02uBelt=key=="TAILORING" and dataset.route and dataset.route[21]
    if p02uBelt and p02uBelt.recipeID==18402 and
        p02uBelt.skillMin==225 and p02uBelt.skillTarget==230 and
        p02uBelt.sourceQualificationContract=="tailoring-225-230-runecloth-belt-evidence-p02u-v1" then
        boundaries[#boundaries+1]=225
    end
    local p02vBelt=key=="TAILORING" and dataset.route and dataset.route[22]
    if p02vBelt and p02vBelt.recipeID==18402 and
        p02vBelt.skillMin==230 and p02vBelt.skillTarget==240 and
        p02vBelt.sourceQualificationContract=="tailoring-230-240-runecloth-belt-evidence-p02v-v1" then
        boundaries[#boundaries+1]=230
    end
    local p02wBelt=key=="TAILORING" and dataset.route and dataset.route[23]
    if p02wBelt and p02wBelt.recipeID==18402 and
        p02wBelt.skillMin==240 and p02wBelt.skillTarget==245 and
        p02wBelt.sourceQualificationContract=="tailoring-240-245-runecloth-belt-evidence-p02w-v1" then
        boundaries[#boundaries+1]=240
    end
    local p02wCloak=key=="TAILORING" and dataset.route and dataset.route[24]
    if p02wCloak and p02wCloak.recipeID==18420 and
        p02wCloak.skillMin==245 and p02wCloak.skillTarget==250 and
        p02wCloak.sourceQualificationContract=="tailoring-245-250-brightcloth-cloak-evidence-p02w-v1" then
        boundaries[#boundaries+1]=245
    end
    local p02xCloak=key=="TAILORING" and dataset.route and dataset.route[25]
    if p02xCloak and p02xCloak.recipeID==18420 and
        p02xCloak.skillMin==250 and p02xCloak.skillTarget==260 and
        p02xCloak.sourceQualificationContract=="tailoring-250-260-brightcloth-cloak-evidence-p02x-v1" then
        boundaries[#boundaries+1]=250
    end
    local p02yCloak=key=="TAILORING" and dataset.route and dataset.route[26]
    if p02yCloak and p02yCloak.recipeID==18420 and p02yCloak.skillMin==260 and
        p02yCloak.skillTarget==262 and
        p02yCloak.sourceQualificationContract=="tailoring-260-262-brightcloth-cloak-evidence-p02y-v1" then
        boundaries[#boundaries+1]=260
    end
    local p02yPants=key=="TAILORING" and dataset.route and dataset.route[27]
    if p02yPants and p02yPants.recipeID==18438 and p02yPants.skillMin==262 and
        p02yPants.skillTarget==270 and
        p02yPants.sourceQualificationContract=="tailoring-262-270-runecloth-pants-evidence-p02y-v1" then
        boundaries[#boundaries+1]=262
    end
    for _,boundary in ipairs(boundaries) do
        local separated={}
        for _,gap in ipairs(routeGaps) do
            if gap.fromSkill<boundary and gap.toSkill>boundary then
                separated[#separated+1]={fromSkill=gap.fromSkill,toSkill=boundary,reason=gap.reason}
                separated[#separated+1]={fromSkill=boundary,toSkill=gap.toSkill,reason=gap.reason}
            else separated[#separated+1]=gap end
        end
        routeGaps=separated
    end
    -- Carry the qualified minimum-skill cause into exact uncovered intervals.
    -- Pure missing-route gaps continue to report NO_QUALIFIED_ROUTE_STEP.
    for _,gap in ipairs(routeGaps) do
        for _,issue in ipairs(scopeEligibilityIssues) do
            if issue.fromSkill<=gap.fromSkill and
                issue.toSkill>=gap.toSkill and issue.reason then
                gap.reason=issue.reason
                gap.recipe=issue.recipe
                gap.minimumSkill=issue.minimumSkill
                break
            end
        end
    end
    return finalizeScopeCoverage({
        key = key,
        strategy = strategy,
        profession = professionState,
        scope = scope,
        scopeLabel = scopeLabel(scope),
        currentSkill = skill,
        targetSkill = targetSkill,
        segments = segments,
        trainers = trainers,
        -- Exposes the mandatory rank unlock to scope/Guide consumers. It does
        -- not convert future route rows into current craft permissions.
        p1Prerequisite=p1ScopePrerequisite,
        p1NextAction=p1ScopeNextAction,
        p1TrainerPrerequisite=p1RankCapReached and {
            status="TRAIN_REQUIRED",atSkill=cap,
            nextCap=p1RankGate and p1RankGate.nextCap or nil,
            rank=p1RankGate and p1RankGate.rank or nil,
            trainer=p1RankGate,requiredBeforeSkill=skill+1,
            action="Train the next Tailoring rank before gaining another skill point."
        } or nil,
        dataset = exposedScopeDataset,
        routeCoverageComplete = routeComplete,
        routeCoverageStatus = routeComplete and "COVERED_BY_ROUTE_STEPS" or "COVERAGE_INCOMPLETE",
        routeCoverageGaps = routeGaps,
        recipeEligibilityIssues=scopeEligibilityIssues,
        craftEstimatesFullyQualified=#segments>0 and allCraftEstimatesQualified,
        craftEstimateStatus=scopeCraftEstimateStatus,
        craftEstimateIssues=scopeCraftEstimateIssues,
        craftEstimateGaps=scopeCraftEstimateGaps,
        -- An empty interval (for example at skill 300) does not assess a
        -- recipe. Interval coverage must not imply source qualification.
        recipeEligibilityFullyQualified=routeComplete and #segments>0 and #scopeEligibilityIssues==0,
        recipeEligibilityStatus=#segments==0 and #scopeEligibilityIssues==0 and
            "NOT_APPLICABLE" or (routeComplete and #scopeEligibilityIssues==0 and
            "SOURCE_QUALIFIED" or "RECIPE_ELIGIBILITY_INCOMPLETE"),
        routeCoverageAdvisory = true, -- interval coverage is not proof of recipe learned/access/yield
        nativeDispatchAllowed = false,
    }, dataset, datasetReason)
end

function Planner:GetState(preferredKey)
    local api = JLP:GetModule("ProfessionAPI")
    local detected = api and api:GetDetected() or {}
    local workspace = JLP:GetModule("ProfessionWorkspace")
    local primary = workspace and workspace:GetPrimaryLearned() or (api and api:GetPrimaryPair() or {})
    local focused
    local secondaryKey=preferredKey or JLP.DB and JLP.DB.profile and JLP.DB.profile.activeSecondaryCurrentStep
    local secondary=secondaryKey=="FIRST_AID"or secondaryKey=="COOKING"or secondaryKey=="FISHING"
    if secondary then focused=detected[secondaryKey]
    else focused=workspace and workspace:GetFocusedPrimary(preferredKey)or primary[1]end

    if not focused then
        return {
            status = "blocked",
            action = "Learn a primary profession to begin.",
            actionKind = "learn",
            detected = detected,
            primaryPair = primary,
            focusedProfession = nil,
            terminalReason = "NO_PRIMARY_PROFESSION",
        }
    end

    local plan = self:GetProfessionPlan(focused.key) or {
        status="blocked", key=focused.key, profession=focused, action="Planner unavailable for "..tostring(focused.name or focused.key)..".", actionKind="blocked", materials={}
    }
    plan.detected = detected
    plan.primaryPair = primary
    plan.focusedProfession = focused
    local paired=nil
    for _, row in ipairs(primary) do if row.key ~= focused.key then paired=row break end end
    plan.pairedProfession = paired
    return plan
end

-- P0-171: expose the settled craft/output comparison without mutating the
-- active progression plan. A route's expectedCrafts is a COUNT OF CASTS, not
-- an observed count of received items. Never infer a fixed yield from it.
function Planner:GetLastOutputSettlement(key, plan)
    local crafting=JLP:GetModule("Crafting")
    local last=crafting and crafting.lastCraft or nil
    if type(last)~="table" or last.key~=key then return nil end
    local step=plan and plan.step or nil
    if step and step.recipeID and tonumber(step.recipeID)~=tonumber(last.recipeID) then return nil end
    local out=last.outputSettlement
    if type(out)~="table" then return nil end
    return {
        contract="planner-output-settlement-comparison-v1",
        recipeID=tonumber(last.recipeID),
        confirmedCrafts=tonumber(last.completedCount) or 0,
        requestedCrafts=tonumber(last.requestedCount) or 1,
        expectedCraftsAdvisory=step and step.expectedCrafts or nil,
        confirmedOutputUnits=out.confirmedOutputUnits,
        expectedOutputUnits=out.expectedOutputUnits,
        expectedSource=out.expectedSource,
        comparison=out.comparison,
        outputStatus=out.status,
        outputItems=out.confirmedOutputByItem and (function()
            local copy={};for id,qty in pairs(out.confirmedOutputByItem) do copy[id]=qty end;return copy
        end)() or nil,
        lateReview=crafting.GetLateOutputReview and crafting:GetLateOutputReview(last.recipeID,last.ledgerID) or nil,
        authority="READ_ONLY_TRANSACTION_RECEIPT",
        nativeDispatchAllowed=false,
        automaticRouteAdvance=false,
    }
end

-- Full reference communication is requested by source UI/fallback, not background reconciliation.
function Planner:EnsureReferenceSnapshot(plan)
    if not plan then return nil end
    if plan.lightweightPrerequisite then return nil end
    if not plan.referenceSnapshot then
        local provider=JLP:GetModule("ProfessionDatasetProvider")
        plan.referenceSnapshot=provider and provider:GetReferenceSnapshot(plan.key) or nil
    end
    return plan.referenceSnapshot
end
do
    local build=Planner.GetProfessionPlan
    function Planner:GetProfessionPlan(key,context)
        local reg=JLP:GetModule("ProfessionRegistry")
        key=reg and reg:NormalizeKey(key) or key
        if not key then return nil end
        return withObservationPass("Planner.request",function()
            local ownershipPrerequisite=prerequisitePlan(key)
            if ownershipPrerequisite then return ownershipPrerequisite end
            if JLP.GetPlanningRevisions then
                local row=JLP:GetPlanningRevisions().professions[key]
                if row and row.strategy and row.strategy~=selectedStrategy() then JLP:MarkObservationsDirty("STRATEGY_CHANGED",key) end
            end
            -- Context table identity keeps preview/material projections separate.
            local plan=memoObservation("plan:"..key..":"..selectedStrategy(),context or "current",function() return build(self,key,context) end)
            if JLP.GetPlanningRevisions then
                local row=JLP:GetPlanningRevisions().professions[key]
                if row then row.evaluatedRevision=row.revision;row.strategy=selectedStrategy() end
            end
            return plan
        end)
    end
end

JLP:RegisterModule("Planner", Planner)
