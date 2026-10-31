local _, JLP = ...
-- Per-field comparison of the retained Alchemy build-70245 candidate against
-- canonical build-70450 client rows. Never promotes steps, skill bands, yields,
-- trainers or native permissions. Does not modify Data/Alchemy.lua.
local Audit={contract="JLP-70450-ALCHEMY-ROUTE-CROSSCHECK-1",sourceBuild=70450,
    historicalBuild=70245,readOnly=true,productionAuthority=false,
    executionEligible=false,nativeDispatchAllowed=false}
local BUILD=70450
local function positive(n)
    return type(n)=="number" and n>0 and n==math.floor(n) and n<2147483647
end
local function amounts(rows)
    if type(rows)~="table" then return nil end
    local out={}
    for _,r in ipairs(rows) do
        if type(r)~="table" or not positive(r.itemID) or not positive(r.quantity) or
            out[r.itemID] then return nil end
        out[r.itemID]=r.quantity
    end
    return out
end
local function equal(a,b)
    local left,right=amounts(a),amounts(b)
    if not left or not right then return false end
    for id,quantity in pairs(left) do if right[id]~=quantity then return false end end
    for id,quantity in pairs(right) do if left[id]~=quantity then return false end end
    return true
end
function Audit:Assess(requestedBuild)
    if requestedBuild~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local dataset=JLP.data and JLP.data.alchemy
    if type(dataset)~="table" or dataset.key~="ALCHEMY" or
        dataset.sourceBuild~=self.historicalBuild or
        dataset.contract~="production-alchemy-readonly-candidate-dataset-v1" or
        dataset.readOnly~=true or dataset.productionCandidate~=true or
        dataset.nativeDispatchAllowed~=false or dataset.executionEligible~=false or
        dataset.routeAuthorityEnabled~=false or type(dataset.route)~="table" then
        return nil,"HISTORICAL_CANDIDATE_CONTRACT_INVALID"
    end
    local catalogue=JLP:GetModule("Build70450RecipeCatalogue")
    if not catalogue then return nil,"70450_CATALOGUE_UNAVAILABLE" end
    local coverage,why=catalogue:GetCoverage()
    if not coverage then return nil,"70450_CATALOGUE_"..tostring(why) end
    if coverage.sourceBuild~=BUILD or not coverage.clientCSVIntegrityQualified or
        type(coverage.sourceSHA256)~="table" then
        return nil,"70450_SOURCE_INTEGRITY_UNVERIFIED"
    end
    local rows,seen={},{}
    local matched,conflicts,missing=0,0,0
    local expected=1
    local skillsContinuous=true
    for i,step in ipairs(dataset.route) do
        if type(step)~="table" or not positive(step.recipeID) or seen[step.recipeID] then
            return nil,"HISTORICAL_ROUTE_IDENTITY_CONFLICT:"..i
        end
        seen[step.recipeID]=true
        if step.skillMin~=expected or type(step.skillTarget)~="number" or
            step.skillTarget<=expected then skillsContinuous=false end
        expected=step.skillTarget
        local recipe,err=catalogue:GetRecipe("ALCHEMY",step.recipeID,BUILD)
        local state
        if not recipe then
            state="CURRENT_REFERENCE_MISSING";missing=missing+1
        elseif recipe.recordKind~="RECIPE_CANDIDATE" or recipe.name~=step.recipe or
            recipe.professionKey~="ALCHEMY" or recipe.sourceBuild~=BUILD or
            recipe.readOnly~=true or recipe.nativeDispatchAllowed~=false or
            recipe.executionEligible~=false then
            state="CURRENT_RECIPE_IDENTITY_CONFLICT";conflicts=conflicts+1
        elseif recipe.reagentState~="RAW_REAGENT_SLOTS" or not recipe.reagents then
            state="CURRENT_REAGENTS_UNQUALIFIED";conflicts=conflicts+1
        elseif not equal(step.materials,recipe.reagents) then
            state="HISTORICAL_REAGENT_DRIFT";conflicts=conflicts+1
        else
            state="70450_RECIPE_AND_REAGENTS_MATCH";matched=matched+1
        end
        rows[#rows+1]={routeIndex=i,spellID=step.recipeID,
            historicalSourceBuild=self.historicalBuild,currentSourceBuild=BUILD,
            historicalSkillMin=step.skillMin,historicalSkillTarget=step.skillTarget,
            historicalExpectedCrafts=step.expectedCrafts,rawCurrentMinSkillRank=recipe and recipe.rawMinSkillLineRank or nil,
            currentYellowRaw=recipe and recipe.rawYellowThreshold or nil,
            currentGreyRaw=recipe and recipe.rawGreyThreshold or nil,
            status=state,detail=not recipe and err or nil,
            currentRecipeIdentityAndReagentsMatch=state=="70450_RECIPE_AND_REAGENTS_MATCH",
            currentServerLearned="UNKNOWN",skillBandsVerified=false,expectedCraftsVerified=false,
            acquisitionVerified=false,outputYieldVerified=false,
            readOnly=true,productionAuthority=false,nativeDispatchAllowed=false}
    end
    return {contract=self.contract,sourceBuild=BUILD,
        historicalSourceBuild=self.historicalBuild,sourceSHA256=coverage.sourceSHA256,
        rows=rows,stepCount=#rows,matched=matched,conflicts=conflicts,missing=missing,
        historicalSkillBandsContinuous=skillsContinuous and expected==300,
        historicalRouteEnd=expected,
        fullRouteQualified=false,fullCurrentBuildProgressionQualified=false,
        alchemyCandidatePromotionAllowed=false,readOnly=true,
        productionAuthority=false,executionEligible=false,nativeDispatchAllowed=false,
        status=(conflicts==0 and missing==0 and matched==#rows) and
            "70450_RECIPE_REAGENT_FIELDS_MATCH_ONLY" or "PARTIAL_OR_CONFLICTED_RECIPE_FIELDS"},nil
end
JLP:RegisterModule("Build70450AlchemyRouteAudit",Audit)
