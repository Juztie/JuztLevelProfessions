local _, JLP = ...

local function prerequisiteGuide(key)
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
        executionEligible=false,lightweightPrerequisite=true,guidance=text,action=text,actionKind="prerequisite",rows={},window={},total=0}
end

local GuideSteps = {}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetKeys() or {}
end
local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local function datasetFor(key, datasetOverride)
    if datasetOverride then return datasetOverride end
    local planner = JLP:GetModule("Planner")
    return planner and planner:GetDataset(key) or nil
end

local function gateMap(dataset)
    local out = {}
    for _, gate in ipairs(dataset and dataset.trainerGates or {}) do
        out[tonumber(gate.cap) or 0] = gate
    end
    return out
end

local function addCraft(rows, key, routeIndex, step, fromSkill, toSkill, part)
    if toSkill <= fromSkill then return end
    rows[#rows + 1] = {
        id = string.format("%s:craft:%d:%d:%d", key, routeIndex, fromSkill, toSkill),
        kind = "craft",
        key = key,
        routeIndex = routeIndex,
        title = step.recipe or "Profession craft",
        fromSkill = fromSkill,
        toSkill = toSkill,
        recipe = step.recipe,
        recipeSource = step.recipeSource or "trainer",
        rawStep = step,
        part = part,
    }
end

local function addTrainer(rows, key, gate)
    rows[#rows + 1] = {
        id = string.format("%s:trainer:%d", key, tonumber(gate.cap) or 0),
        kind = "train",
        key = key,
        title = gate.rank or "Profession rank training",
        cap = tonumber(gate.cap) or 0,
        nextCap = tonumber(gate.nextCap) or 300,
        gate = gate,
    }
end

local function buildTimeline(key, dataset)
    local rows = {}
    local gates = gateMap(dataset)
    local gateAdded = {}
    local steps=dataset and (dataset.route or dataset.steps) or {}
    local provider=JLP:GetModule("ProfessionDatasetProvider")
    if provider and provider.GetProgressionSteps then steps=provider:GetProgressionSteps(key,dataset) end
    for routeIndex, step in ipairs(steps) do
        local startSkill = tonumber(step.skillMin) or 0
        local targetSkill = tonumber(step.skillTarget) or startSkill
        local cursor = startSkill
        local part = 1
        local splitCaps = {}
        for cap in pairs(gates) do
            if cap > startSkill and cap < targetSkill then splitCaps[#splitCaps + 1] = cap end
        end
        table.sort(splitCaps)
        for _, cap in ipairs(splitCaps) do
            addCraft(rows, key, routeIndex, step, cursor, cap, part)
            part = part + 1
            addTrainer(rows, key, gates[cap])
            gateAdded[cap] = true
            cursor = cap
        end
        addCraft(rows, key, routeIndex, step, cursor, targetSkill, part)
        if gates[targetSkill] and not gateAdded[targetSkill] then
            addTrainer(rows, key, gates[targetSkill])
            gateAdded[targetSkill] = true
        end
    end
    for cap, gate in pairs(gates) do
        if not gateAdded[cap] then addTrainer(rows, key, gate) end
    end
    return rows
end

local function annotate(rows, profession, plan, dataset)
    -- Reference provenance belongs to the provider dataset, not VERIFY itself.
    local historicalFallback = dataset and dataset.readOnlyRouteFallback == true
    local datasetReadOnly = dataset and dataset.readOnly == true
    local skill = tonumber(profession and profession.skill) or 0
    local maxSkill = tonumber(profession and profession.maxSkill) or 0
    local currentIndex

    for i, row in ipairs(rows) do
        if row.kind == "train" then
            if maxSkill > (row.cap or 0) then
                row.status = "completed"
            elseif plan and plan.actionKind == "train" and maxSkill == (row.cap or 0) then
                row.status = "current"
                currentIndex = i
            else
                row.status = "upcoming"
            end
        else
            -- All historical/candidate route rows are informational, even if
            -- their recipe title and skill interval can be displayed.
            row.readOnly=datasetReadOnly and true or nil
            if datasetReadOnly then row.nativeDispatchAllowed=false end
            row.referenceOnly=(historicalFallback or (dataset and dataset.referenceOnly==true)) and true or nil
            if skill >= (row.toSkill or 0) then
                row.status = "completed"
            elseif plan and type(plan.recommendedCurrentStep)=="table" and
                plan.recommendedCurrentStep.kind=="craft" and
                skill >= (row.fromSkill or 0) and skill < (row.toSkill or 0) then
                -- The selected recipe may differ from the registered historic
                -- route. Display the *actual recommendation*, preserve the
                -- original row title for provenance and never grant crafting.
                local recommended=plan.recommendedCurrentStep
                row.referenceRecipe=row.title
                row.title=recommended.requiredNextAction=="manual-craft" and recommended.craftInstruction or recommended.nextAction or ("Current Step: "..tostring(recommended.recipe))
                row.craftQuantity=recommended.craftQuantity;row.craftQuantityUnit="CASTS"
                row.currentObservedRecipe=recommended.recipe
                row.currentObservedRecipeID=recommended.recipeID
                row.requiredSkill=recommended.requiredSkill;row.patternAcquisition=recommended.patternAcquisition
                row.actionType=recommended.actionType;row.toolRequirement=recommended.toolRequirement
                row.ordinaryRodAcquisition=recommended.ordinaryRodAcquisition;row.learningMethod=recommended.learningMethod
                row.enchantTarget=recommended.enchantTarget;row.minimumStatus=recommended.minimumStatus
                row.alchemyPrerequisites=recommended.alchemyPrerequisites
                row.blacksmithingPrerequisites=recommended.blacksmithingPrerequisites
                row.engineeringPrerequisites=recommended.engineeringPrerequisites
                row.productUseRequirements=recommended.productUseRequirements
                row.specializationObserved=recommended.specializationObserved;row.specializationRequired=recommended.specializationRequired
                row.hammerStatus=recommended.hammerStatus;row.stationStatus=recommended.stationStatus
                row.learningMinimumStatus=recommended.learningMinimumStatus;row.recipeQualification=recommended.recipeQualification
                row.trainerAcquisition=recommended.trainerAcquisition
                row.materialService=recommended.materialService;row.navigation=recommended.navigation
                row.preparingIntermediate=recommended.preparingIntermediate;row.preparationForRecipeID=recommended.preparationForRecipeID
                row.currentActionKind=plan.actionKind=="craft" and "manual-one" or plan.actionKind=="acquire" and "acquire" or plan.actionKind=="learn" and "learn" or "verify"
                row.verificationAction=plan.action
                row.status="current"
                row.readOnly=true;row.nativeDispatchAllowed=false
                currentIndex=i
            elseif plan and plan.actionKind == "verify" and plan.step and
                skill >= (row.fromSkill or 0) and skill < (row.toSkill or 0) then
                -- VERIFY marks today's documented interval for all supported
                -- professions, independently of native execution authority.
                -- Do not turn this reference position into craft/native authority.
                row.status = "current"
                row.currentActionKind = "verify"
                row.referenceOnly = historicalFallback and true or nil
                row.readOnly = datasetReadOnly and true or nil
                row.nativeDispatchAllowed = false
                row.verificationAction = plan.action
                currentIndex = i
            elseif plan and plan.actionKind == "reference" and skill >= (row.fromSkill or 0) and skill < (row.toSkill or 0) then
                row.status = "current"
                row.currentActionKind = "reference"
                row.readOnly = true
                row.nativeDispatchAllowed = false
                currentIndex = i
            elseif plan and plan.actionKind == "craft" and plan.p1LiveOneCraft==true and
                skill >= (row.fromSkill or 0) and skill < (row.toSkill or 0) then
                -- Highlight the CURRENT skill interval even if a previously
                -- learned recipe is the live-confirmed, non-gray alternative.
                -- Do not mislabel the historical recipe as executable.
                row.status="current"
                row.currentActionKind="manual-one"
                row.currentObservedRecipe=plan.step and plan.step.recipe or nil
                row.currentObservedRecipeID=plan.step and plan.step.recipeID or nil
                row.verificationAction=plan.action
                row.readOnly=true
                row.nativeDispatchAllowed=false
                currentIndex=i
            elseif plan and plan.actionKind == "craft" and plan.step and row.recipe == plan.step.recipe and skill >= (row.fromSkill or 0) and skill < (row.toSkill or 0) then
                row.status = "current"
                currentIndex = i
            else
                row.status = "upcoming"
            end
        end
    end

    if not currentIndex and plan and plan.actionKind == "complete" then
        currentIndex = #rows
    end
    if not currentIndex then
        for i, row in ipairs(rows) do
            if row.status == "upcoming" then currentIndex = i break end
        end
    end
    currentIndex = currentIndex or math.max(1, #rows)
    return currentIndex
end

local function makeWindow(rows, currentIndex, before, after)
    before = math.max(0, math.floor(tonumber(before) or 1))
    after = math.max(0, math.floor(tonumber(after) or 2))
    local first = math.max(1, currentIndex - before)
    local last = math.min(#rows, currentIndex + after)
    local out = {}
    for i = first, last do
        local copy = rows[i]
        copy.timelineIndex = i
        out[#out + 1] = copy
    end
    return out
end

function GuideSteps:Build(key, plan, datasetOverride)
    local reg=registry()
    key=reg and reg:NormalizeKey(key) or nil
    if not key then return {key=key,rows={},window={},total=0,status="unsupported-profession"} end
    local prerequisite=prerequisiteGuide(key)
    if prerequisite then return prerequisite end
    local dataset = datasetFor(key, datasetOverride)
    local api = JLP:GetModule("ProfessionAPI")
    local profession = api and api:Get(key) or (plan and plan.profession)
    local planner = JLP:GetModule("Planner")
    plan = plan or (planner and planner:GetProfessionPlan(key))
    -- The same read-only scope evidence as AcquisitionPlanner; never promote
    -- guide reference rows to qualified recipe actions.
    local scopeModel=profession and planner and planner.GetScopePlan and
        planner:GetScopePlan(key,profession,"current",JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy)
    local coverage=scopeModel and scopeModel.coverageEnvelope
    -- Reference-only ACTION is not evidence that the documented ROUTE is
    -- missing. Preserve the route timeline, but never turn its steps into
    -- an authorized craft action. Public skill-band fallback is used only
    -- when no actual documented route is available.
    if plan and plan.actionKind=="reference" then
        local rows=type(dataset)=="table" and (dataset.route or dataset.steps) or nil
        local hasIntervals=false
        for _,step in ipairs(type(rows)=="table" and rows or {}) do
            local lo,hi=type(step)=="table" and tonumber(step.skillMin),
                type(step)=="table" and tonumber(step.skillTarget)
            if lo and hi and lo>=0 and hi<=300 and hi>lo and
                type(step.recipe)=="string" and step.recipe~="" then
                hasIntervals=true;break
            end
        end
        if not hasIntervals then dataset=nil end
    end
    if not dataset then
        local provider=JLP:GetModule("ProfessionDatasetProvider")
        local ref=plan and plan.referenceSnapshot or
            (provider and provider.GetReferenceSnapshot and provider:GetReferenceSnapshot(key))
        local rows={}
        local skill=tonumber(profession and profession.skill)
        for i,band in ipairs(ref and ref.guide and ref.guide.bands or {}) do
            if type(band.skillMin)=="number" and type(band.skillMax)=="number" and
                band.skillMax>band.skillMin then
                local status=not skill and "reference" or
                    (skill>=band.skillMax and "completed" or
                    (skill>=band.skillMin and "current" or "upcoming"))
                rows[#rows+1]={id=key..":reference:"..i,kind="reference",key=key,
                    title=band.action or "Public profession guidance",fromSkill=band.skillMin,
                    toSkill=band.skillMax,status=status,source=ref.guideSource,
                    readOnly=true,nativeDispatchAllowed=false}
            end
        end
        local currentIndex=1;local completed=0
        for i,row in ipairs(rows) do
            if row.status=="completed" then completed=completed+1 end
            if row.status=="current" then currentIndex=i end
        end
        if skill and #rows>0 and rows[currentIndex].status=="completed" then
            currentIndex=math.min(#rows,completed+1)
        end
        -- No registered route is required to display a source-backed best
        -- Current Step. Dynamic advice never invents a 1-300 route interval.
        local recommended=plan and plan.recommendedCurrentStep
        if type(recommended)=="table" and skill and (skill<300 or recommended.materialSupply) then
            local description=recommended.kind=="craft" and
                (recommended.requiredNextAction=="manual-craft" and recommended.craftInstruction or recommended.nextAction or ("Current Step: "..tostring(recommended.recipe))) or
                tostring(recommended.nextAction or recommended.action or "Gather resources")
            local current={id=key..":recommended:"..tostring(skill),kind=recommended.kind,
                key=key,title=description,fromSkill=skill,toSkill=math.min(300,skill+1),
                status="current",currentActionKind=plan.actionKind,
                recipe=recommended.recipe,recipeID=recommended.recipeID,craftQuantity=recommended.craftQuantity,craftQuantityUnit="CASTS",
                verificationAction=plan.action,source="SOURCE_BACKED_ADVISORY",
                navigation=recommended.navigation,
                currentStepCompletionChain=plan.currentStepCompletionChain,
                recipeSourcePlanning=recommended.recipeSourcePlanning,
                requiredSkill=recommended.requiredSkill,patternAcquisition=recommended.patternAcquisition,
                actionType=recommended.actionType,toolRequirement=recommended.toolRequirement,
                enchantTarget=recommended.enchantTarget,minimumStatus=recommended.minimumStatus,
                blacksmithingPrerequisites=recommended.blacksmithingPrerequisites,
                    engineeringPrerequisites=recommended.engineeringPrerequisites,productUseRequirements=recommended.productUseRequirements,
                    specializationObserved=recommended.specializationObserved,specializationRequired=recommended.specializationRequired,
                hammerStatus=recommended.hammerStatus,stationStatus=recommended.stationStatus,
                learningMinimumStatus=recommended.learningMinimumStatus,recipeQualification=recommended.recipeQualification,
                trainerAcquisition=recommended.trainerAcquisition,
                skillUpPlanning=recommended.skillUpPlanning,
                materials=recommended.materials,materialSupply=recommended.materialSupply,materialService=recommended.materialService,
                secondaryAccess=recommended.secondaryAccess,fishingArea=recommended.fishingArea,fishingContext=recommended.fishingContext,
                readOnly=true,nativeDispatchAllowed=false}
            table.insert(rows,1,current)
            currentIndex=1
        end
        return {key=key,profession=profession,plan=plan,rows=rows,
            window=makeWindow(rows,currentIndex,1,2),current=rows[currentIndex],
            currentIndex=#rows>0 and currentIndex or 0,total=#rows,
            completed=completed,remaining=math.max(0,#rows-completed),
            status=ref and "reference-only" or "unavailable",
            reason=#rows==0 and "NO_DOCUMENTED_SKILL_BANDS" or nil,
            referenceSnapshot=ref,readOnly=true,nativeDispatchAllowed=false,
            coverageEnvelope=coverage,coverageStatus=coverage and coverage.coverageStatus,
            datasetStatus=coverage and coverage.datasetStatus,
            nextAction=coverage and coverage.nextAction,
            executionEligible=false,contract="live-profession-step-progression"}
    end
    if not profession then
        return {key=key,rows={},window={},currentIndex=0,total=0,completed=0,
            status="not-learned",readOnly=true,contract="live-profession-step-progression",
            coverageEnvelope=coverage,coverageStatus=coverage and coverage.coverageStatus,
            datasetStatus=coverage and coverage.datasetStatus,
            nextAction=coverage and coverage.nextAction}
    end

    local rows = buildTimeline(key, dataset)
    if dataset.readOnlyRouteFallback == true then
        -- Route numbers are historical estimates, not currently verified crafts.
        for _, row in ipairs(rows) do
            row.readOnlyRouteFallback = true
            row.originalSourceBuild = dataset.originalSourceBuild or dataset.sourceBuild
            row.nativeDispatchAllowed = false
        end
    end
    local currentIndex = annotate(rows, profession, plan, dataset)
    local completed = 0
    for _, row in ipairs(rows) do if row.status == "completed" then completed = completed + 1 end end
    return {
        key = key,
        profession = profession,
        plan = plan,
        rows = rows,
        window = makeWindow(rows, currentIndex, 1, 2),
        current = rows[currentIndex],
        currentIndex = currentIndex,
        total = #rows,
        completed = completed,
        remaining = math.max(0, #rows - completed),
        status = plan and plan.actionKind == "complete" and "complete" or
            (plan and plan.actionKind == "reference" and "reference-route" or "active"),
        nativeDispatchAllowed = dataset and dataset.readOnly == true and false or
            (dataset and dataset.nativeDispatchAllowed == true or false),
        guideRouteCoverage = dataset and dataset.guideRouteCoverage or nil,
        tailoringRecipeSourceQualification=key=="TAILORING" and profession and
            (JLP:GetModule("TailoringRecipeQualification") and
             JLP:GetModule("TailoringRecipeQualification"):GetAtSkill(profession.skill)) or nil,
        tailoringProgressionEvidence=key=="TAILORING" and profession and
            (JLP:GetModule("TailoringProgressionEvidence") and
             JLP:GetModule("TailoringProgressionEvidence"):GetAtSkill(profession.skill)) or nil,
        tailoringLevelingAudit=key=="TAILORING" and
            (JLP:GetModule("TailoringLevelingCoverage") and
             JLP:GetModule("TailoringLevelingCoverage"):Build()) or nil,
        coverageEnvelope=coverage,coverageStatus=coverage and coverage.coverageStatus,
        datasetStatus=coverage and coverage.datasetStatus,
        nextAction=coverage and coverage.nextAction,
        contract = "live-profession-step-progression",
        authority = dataset and dataset.authority or nil,
        plannerEligible = dataset and dataset.plannerEligible == true or nil,
        executionEligible = dataset and dataset.executionEligible,
        routeAuthorityEnabled = dataset and dataset.routeAuthorityEnabled == true or nil,
        readOnly = dataset and dataset.readOnly == true or nil,
    }
end

local function compactCoverage(model)
    local evidence=model and model.coverageEnvelope
    if type(evidence)~="table" or evidence.nextActionCode=="COMPLETE" or
        evidence.routeQualification=="QUALIFIED" then return "" end
    return " | Coverage "..tostring(evidence.datasetStatus or "UNKNOWN")..
        "/"..tostring(evidence.coverageStatus or "UNKNOWN")..
        " ["..tostring(evidence.nextActionCode or "VERIFY").."]"..
        " | Next: "..tostring(evidence.nextAction or "Verify profession route evidence.")
end

function GuideSteps:FormatCompact(model)
    if not model then return "Route steps: unavailable" end
    if model.lightweightPrerequisite then return model.guidance end
    local suffix=compactCoverage(model)
    if model.status=="unavailable" then return "Route steps: unavailable"..suffix end
    if model.status=="complete" then
        return string.format("Route steps: complete - %d/%d",model.total or 0,model.total or 0)..suffix
    end
    local current=model.current
    return string.format(
        "Route step %d/%d - %s%s",
        model.currentIndex or 0,
        model.total or 0,
        current and current.title or "Current step",
        current and current.currentActionKind == "verify" and
            (current.referenceOnly == true and " [NOW: VERIFY, historical recipe reference only]" or " [NOW: VERIFY]") or
            (current and current.currentActionKind == "acquire" and " [NOW: ACQUIRE]" or
            current and current.currentActionKind == "learn" and " [NOW: LEARN RECIPE MANUALLY]" or
            current and current.currentActionKind == "reference" and " [NOW: REFERENCE - VERIFY]" or
            (current and current.currentActionKind == "manual-one" and
                ((current.craftQuantity==1 or current.craftQuantity==nil and model.plan and model.plan.step and model.plan.step.remainingCrafts==1)and " [NOW: manual ONE observed cast]" or (" [NOW: manual; casts "..tostring(current.craftQuantity or "verify").."]")) or
                (current and current.kind == "train" and " [trainer]" or "")))
    )..suffix
end

function GuideSteps:GetSummary()
    local lines = {}
    local planner = JLP:GetModule("Planner")
    for _, key in ipairs(productionKeys()) do
        local model = self:Build(key, planner and planner:GetProfessionPlan(key))
        lines[#lines + 1] = professionLabel(key) .. ": " .. self:FormatCompact(model):gsub("^Route steps:%s*", "")
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("GuideSteps", GuideSteps)
