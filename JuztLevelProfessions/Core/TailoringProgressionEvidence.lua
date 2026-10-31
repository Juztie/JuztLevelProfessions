local _, JLP = ...
-- P1 skill 1-300: read-only qualification and passive evidence explanation.
-- This module never updates route flags, SavedVariables, native permissions,
-- or turns historical recipe thresholds into a craft count.
local Evidence = {contract="tailoring-progression-field-evidence-v1",readOnly=true,
    executionEligible=false,nativeDispatchAllowed=false}
local BANDS={{1,75},{75,150},{150,225},{225,270},{270,300}}
local function validInt(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and n%1==0
end
local function source()
    return JLP.data and JLP.data.tailoring or nil
end
local function bandFor(skill)
    for _,b in ipairs(BANDS) do
        if skill>=b[1] and skill<b[2] then return tostring(b[1]).."-"..tostring(b[2]) end
    end
end
local function copyMaterials(rows)
    local result={}
    for _,m in ipairs(rows or {}) do
        result[#result+1]={itemID=m.itemID,quantity=m.quantity,name=m.name,
            source=m.source,referenceOnly=true}
    end
    return result
end
local function forStep(step,index)
    local lastGrey=validInt(step.rawGreyThreshold) and step.rawGreyThreshold or nil
    local out={index=index,fromSkill=step.skillMin,toSkill=step.skillTarget,
        recipe=step.recipe,recipeID=step.recipeID,
        expectedCraftsReference=step.expectedCrafts,
        expectedCraftsQualified=false,materialsOneCraftReference=copyMaterials(step.materials),
        materialEvidence=step.materialEvidence,materialSourceBuild=step.materialSourceBuild,
        recipeSourceReference=step.recipeSource,
        recipeSourceEvidence=step.recipeSourceEvidence,
        requiredSkillReference=step.requiredSkill,
        requiredSkillAuthority=step.requiredSkillAuthority,
        patternItemID=step.sourceRequirement and step.sourceRequirement.itemID or nil,
        patternStatus="NOT_OBSERVED",learnedState="NOT_OBSERVED",
        rawYellow=step.rawYellowThreshold,rawGrey=lastGrey,
        thresholdSourceBuild=step.rawDifficultySourceBuild,
        stationFocusID=step.sourceSpellFocusReference,
        stationReference=step.sourceFocusLabel,
        stationStatus=step.sourceSpellFocusReference and "NOT_OBSERVED" or "NOT_SPECIFIED",
        referenceOutputItemID=step.outputItemID,
        referenceOutputYield=step.outputQuantityReference,
        outputYieldQualified=false,skillGainQualified=false,
        referenceOnly=true,readOnly=true,executionEligible=false,
        nativeDispatchAllowed=false,skillWindowBand=bandFor(step.skillMin),
        issues={}}
    local issues=out.issues
    if step.recipeAccessObserved~=true then issues[#issues+1]="RECIPE_ACCESS_NOT_OBSERVED" end
    if step.craftCountQualified~=true then issues[#issues+1]="CRAFT_COUNT_NOT_QUALIFIED" end
    if step.outputYieldLiveVerified~=true then issues[#issues+1]="OUTPUT_YIELD_NOT_LIVE_QUALIFIED" end
    if step.sourceRequirement then issues[#issues+1]="PATTERN_ACCESS_NOT_OBSERVED" end
    if step.sourceSpellFocusReference then issues[#issues+1]="STATION_ACCESS_NOT_OBSERVED" end
    if lastGrey and validInt(step.skillTarget) and step.skillTarget>lastGrey then
        issues[#issues+1]="SOURCE_WINDOW_EXTENDS_BEYOND_REFERENCE_GREY" end
    return out
end
function Evidence:Build()
    local d=source();local route=d and d.route or {}
    local rows={}
    local model={contract=self.contract,professionKey="TAILORING",sourceBuild=d and d.sourceBuild,
        fromSkill=1,toSkill=300,steps=rows,bands={},readOnly=true,
        executionEligible=false,nativeDispatchAllowed=false,
        sourceSteps=0,skillGainsQualified=0,sourceWindowsComplete=false}
    local positions={}
    for i,step in ipairs(route) do
        rows[#rows+1]=forStep(step,i)
        if validInt(step.skillMin) and validInt(step.skillTarget) then
            for pos=math.max(1,step.skillMin),math.min(299,step.skillTarget-1) do
                positions[pos]=(positions[pos] or 0)+1
            end
        end
    end
    model.sourceSteps=#rows
    model.sourceWindowsComplete=#rows>0
    for _,b in ipairs(BANDS) do
        local band={fromSkill=b[1],toSkill=b[2],name=tostring(b[1]).."-"..tostring(b[2]),
            sourceCovered=0,liveQualified=0,sourceStepCount=0,readOnly=true,
            executionEligible=false}
        for skill=b[1],b[2]-1 do
            if positions[skill]==1 then band.sourceCovered=band.sourceCovered+1
            else model.sourceWindowsComplete=false end
        end
        for _,s in ipairs(rows) do
            if s.fromSkill<b[2] and s.toSkill>b[1] then
                band.sourceStepCount=band.sourceStepCount+1
            end
        end
        model.bands[#model.bands+1]=band
    end
    return model
end
function Evidence:GetAtSkill(skill)
    if not validInt(skill) or skill<1 or skill>=300 then return nil,"SKILL_OUTSIDE_1_299" end
    local d=source()
    for i,step in ipairs(d and d.route or {}) do
        if validInt(step.skillMin) and validInt(step.skillTarget) and
           skill>=step.skillMin and skill<step.skillTarget then
            local result=forStep(step,i)
            result.skill=skill
            result.skillBand=bandFor(skill)
            -- Raw yellow/grey are SOURCE provenance, not live difficulty.
            if result.rawGrey and skill>=result.rawGrey then
                result.issues[#result.issues+1]="REFERENCE_RECIPE_GREY_AT_SKILL"
            end
            if validInt(result.requiredSkillReference) and skill<result.requiredSkillReference then
                result.issues[#result.issues+1]="REFERENCE_LEARN_MINIMUM_NOT_REACHED"
            end
            return result
        end
    end
    return nil,"NO_SOURCE_ROUTE_AT_SKILL"
end
-- Saved observation history is deliberately not used to calculate success
-- probabilities, bulk material orders, or native authorization. Historical
-- rows may belong to different client builds and game sessions.
function Evidence:GetObservedResults(recipeID,limit)
    if not validInt(recipeID) or recipeID<1 then return nil,"RECIPE_ID_INVALID" end
    local journal=JLP:GetModule("CraftObservationJournal70450")
    if not journal or type(journal.GetHistory)~="function" then
        return {observedResults=0,observedSkillGains=0,observedNoGains=0,
            outputUnitsObserved=0,historyWindow="UNAVAILABLE",readOnly=true} end
    local n=validInt(limit) and math.max(1,math.min(150,limit)) or 150
    local ok,rows=pcall(journal.GetHistory,journal,n,"TAILORING")
    if not ok or type(rows)~="table" then return nil,"HISTORY_UNAVAILABLE" end
    local result={observedResults=0,observedSkillGains=0,observedNoGains=0,
        outputUnitsObserved=0,ambiguous=0,historyWindow="LAST_"..n.."_RESULT_ROWS",
        readOnly=true,skillRateQualified=false,nativeDispatchAllowed=false}
    for _,r in ipairs(rows) do
        if type(r)=="table" and r.recipeID==recipeID then
            result.observedResults=result.observedResults+1
            if r.skillObservationStatus=="OBSERVED_GAIN" and r.skillGain==1 and
               validInt(r.skillBefore) and validInt(r.skillAfter) and
               r.skillAfter==r.skillBefore+1 then
                result.observedSkillGains=result.observedSkillGains+1
            elseif r.skillObservationStatus=="OBSERVED_NO_GAIN" and r.skillGain==0 and
               validInt(r.skillBefore) and r.skillBefore==r.skillAfter then
                result.observedNoGains=result.observedNoGains+1
            else
                result.ambiguous=result.ambiguous+1
            end
            if validInt(r.outputQuantity) and r.outputQuantity>0 then
                result.outputUnitsObserved=result.outputUnitsObserved+r.outputQuantity
            end
        end
    end
    return result
end
function Evidence:InspectAtSkill(skill)
    local row,why=self:GetAtSkill(skill)
    if not row then return {status=why,readOnly=true,executionEligible=false} end
    local q=JLP:GetModule("TailoringRecipeQualification")
    local observed=q and type(q.InspectAtSkill)=="function" and q:InspectAtSkill(skill) or nil
    local history=self:GetObservedResults(row.recipeID,150)
    row.liveStatus=type(observed)=="table" and observed.status or "LIVE_UNAVAILABLE"
    row.currentMaxSkill=type(observed)=="table" and observed.currentMaxSkill or nil
    row.liveLearned=type(observed)=="table" and observed.recipeStatus or "UNKNOWN"
    row.liveDifficulty=type(observed)=="table" and observed.difficultyStatus or "UNKNOWN"
    row.liveCraftability=type(observed)=="table" and observed.craftabilityStatus or "UNKNOWN"
    row.liveReagents=type(observed)=="table" and observed.reagentsStatus or "UNKNOWN"
    row.observedHistory=history
    row.manualOneCandidate=type(observed)=="table" and observed.manualOneCandidate==true or false
    row.skillGainQualified=false
    row.outputYieldQualified=false
    if validInt(row.currentMaxSkill) and skill>=row.currentMaxSkill and skill<300 then
        row.nextAction="VERIFY_TRAIN_NEXT_RANK"
        row.manualOneCandidate=false
    elseif row.manualOneCandidate then
        row.nextAction="MANUAL_ONE_THEN_OBSERVE"
    elseif row.liveLearned=="NOT_LEARNED" then
        row.nextAction=row.patternItemID and "VERIFY_PATTERN_ACCESS" or "VERIFY_TRAINER_ACCESS"
    elseif row.stationFocusID then
        row.nextAction="VERIFY_STATION_AND_RECIPE"
    else
        row.nextAction="VERIFY_LIVE_RECIPE_AND_SKILL"
    end
    row.status="READ_ONLY_EVIDENCE_PREVIEW"
    return row
end
JLP:RegisterModule("TailoringProgressionEvidence",Evidence)
