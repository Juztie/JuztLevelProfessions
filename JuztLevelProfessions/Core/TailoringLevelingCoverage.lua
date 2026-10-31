local _, JLP = ...
-- Tailoring 1-300: source coverage is NOT proven skill-up progression.
-- This module never scans the profession panel, writes SavedVariables,
-- or grants route/native execution authority.
local Coverage = {contract="tailoring-1-300-coverage-audit-v1"}

local function integer(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and n%1==0
end

local function sourceRoute()
    return JLP.data and JLP.data.tailoring and JLP.data.tailoring.route or nil
end

function Coverage:Build()
    local route=sourceRoute()
    local model={contract=self.contract,professionKey="TAILORING",fromSkill=1,toSkill=300,
        sourceBuild=JLP.data and JLP.data.tailoring and JLP.data.tailoring.sourceBuild,
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
        sourcePositions=0,liveQualifiedPositions=0,uncovered={},overlaps={},
        steps={},trainerCaps={},sourceRouteComplete=false,liveRouteComplete=false,
        reasons={}}
    if type(route)~="table" then model.reasons[1]="TAILORING_ROUTE_UNAVAILABLE";return model end
    local occupancy={}
    for index,step in ipairs(route) do
        local lo,hi=step.skillMin,step.skillTarget
        local valid=integer(lo) and integer(hi) and lo>=1 and hi<=300 and hi>lo
        local identity=integer(step.recipeID) and step.recipeID>0
        local materials=type(step.materials)=="table" and #step.materials>0
        local materialRowsValid=materials
        if materials then
            for _,row in ipairs(step.materials) do
                if type(row)~="table" or not integer(row.itemID) or row.itemID<=0 or
                   not integer(row.quantity) or row.quantity<=0 then
                    materialRowsValid=false;break
                end
            end
        end
        local qualified=step.routeQualified==true and step.craftCountQualified==true and
            step.recipeAccessObserved==true and step.outputYieldLiveVerified==true
        model.steps[#model.steps+1]={index=index,fromSkill=lo,toSkill=hi,
            recipe=step.recipe,recipeID=step.recipeID,sourceWindowValid=valid,
            recipeIdentityReferenced=identity,materialRowsReferenced=materialRowsValid,
            recipeLearnedLiveVerified=step.recipeAccessObserved==true,
            craftCountLiveQualified=step.craftCountQualified==true,
            outputYieldLiveVerified=step.outputYieldLiveVerified==true,
            progressionQualified=qualified,readOnly=true,nativeDispatchAllowed=false}
        if valid then
            for skill=lo,hi-1 do
                occupancy[skill]=occupancy[skill] or {}
                occupancy[skill][#occupancy[skill]+1]=index
            end
        end
    end
    for skill=1,299 do
        local hits=occupancy[skill]
        if not hits then model.uncovered[#model.uncovered+1]=skill
        else
            model.sourcePositions=model.sourcePositions+1
            if #hits>1 then model.overlaps[#model.overlaps+1]=skill end
            if #hits==1 and model.steps[hits[1]].progressionQualified then
                model.liveQualifiedPositions=model.liveQualifiedPositions+1
            end
        end
    end
    for _,gate in ipairs(JLP.data.tailoring.trainerGates or {}) do
        model.trainerCaps[#model.trainerCaps+1]={atSkill=gate.cap,toCap=gate.nextCap,
            requiredSkill=gate.requiredSkill,minCharacterLevel=gate.minCharacterLevel,
            sourceOnly=true,requiresLiveTrainerAccess=true}
    end
    model.sourceRouteComplete=#model.uncovered==0 and #model.overlaps==0 and #model.steps>0
    model.liveRouteComplete=model.sourceRouteComplete and model.liveQualifiedPositions==299
    if model.sourceRouteComplete and not model.liveRouteComplete then
        model.reasons[#model.reasons+1]="SOURCE_ROUTE_COVERS_1_300_BUT_LIVE_SKILLUP_UNVERIFIED"
    end
    for _,row in ipairs(model.steps) do
        if not row.recipeIdentityReferenced or not row.materialRowsReferenced then
            model.reasons[#model.reasons+1]="INCOMPLETE_REFERENCE_STEP_"..tostring(row.index)
        end
    end
    return model
end

function Coverage:GetAtSkill(skill)
    local model=self:Build()
    if not integer(skill) or skill<1 or skill>=300 then return nil,"OUTSIDE_1_299" end
    for _,row in ipairs(model.steps) do
        if row.sourceWindowValid and skill>=row.fromSkill and skill<row.toSkill then
            return row,nil
        end
    end
    return nil,"NO_DOCUMENTED_SKILL_WINDOW"
end

function Coverage:GetSummary()
    local audit=self:Build()
    return string.format("Tailoring 1-300: source windows %d/299; live-qualified progression %d/299; gaps %d; overlaps %d; native permission: none from audit.",
        audit.sourcePositions,audit.liveQualifiedPositions,#audit.uncovered,#audit.overlaps)
end

JLP:RegisterModule("TailoringLevelingCoverage",Coverage)
