local _, JLP = ...
-- Non-persisted live context for the *displayed* Cooking / First Aid step.
-- This module cannot create an action receipt, permission, route or inventory
-- credit. Every invocation independently rechecks panel, recipe and identity.
local V={contract="secondary-volatile-advisory-evidence-v208",readOnly=true,
    nativeDispatchAllowed=false,executionEligible=false}
local function positive(v)
    return type(v)=="number" and v==v and v>0 and v<2147483647 and
        v==math.floor(v)
end
function V:Observe(key,skill,recipeID,expectedName,expectedOutputID)
    local out={contract=self.contract,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,learnedState="UNKNOWN",yieldState="UNKNOWN",
        recipeID=recipeID,source="NONE",reason="LIVE_PANEL_NOT_OBSERVED"}
    if (key~="COOKING" and key~="FIRST_AID") or not positive(recipeID) or
        type(expectedName)~="string" or expectedName=="" or
        type(skill)~="number" or skill~=math.floor(skill) or skill<1 or skill>300 then
        out.reason="RECIPE_IDENTITY_INVALID";return out
    end
    local prof=JLP:GetModule("ProfessionAPI")
    if not prof or type(prof.GetReadOnlyProfessionObservation)~="function" or
        type(prof.GetReadOnlyRecipeObservation)~="function" then
        return out
    end
    local okFirst,first=pcall(prof.GetReadOnlyProfessionObservation,prof)
    if not okFirst or type(first)~="table" or first.observed~=true or
        first.professionKey~=key or first.skill~=skill or
        type(first.observationToken)~="string" then
        out.reason="PANEL_OR_SKILL_NOT_MATCHED";return out
    end
    local okRecipe,recipe=pcall(prof.GetReadOnlyRecipeObservation,prof,recipeID,key)
    if not okRecipe or type(recipe)~="table" or recipe.readOnlyObserved~=true or
        recipe.recipeID~=recipeID or recipe.professionKey~=key or
        recipe.name~=expectedName or type(recipe.learned)~="boolean" or
        recipe.observationToken~=first.observationToken then
        out.reason="RECIPE_NOT_STABLY_OBSERVED";return out
    end
    local okLast,last=pcall(prof.GetReadOnlyProfessionObservation,prof)
    if not okLast or type(last)~="table" or last.observed~=true or
        last.professionKey~=key or last.skill~=skill or
        last.observationToken~=first.observationToken or
        last.observationQuality~=first.observationQuality or
        last.clientBuild~=first.clientBuild or
        last.characterKey~=first.characterKey then
        out.reason="PANEL_CHANGED";return out
    end
    out.learnedState=recipe.learned and "LEARNED" or "NOT_LEARNED"
    out.source="VOLATILE_CURRENT_PANEL_READ_ONLY"
    out.reason="LIVE_RECIPE_READ_ONLY"
    out.observationQuality=first.observationQuality
    -- A second read-only service may return the current output interval;
    -- it MUST NOT be used to generate estimated crafts or ledger credits.
    local yieldService=JLP:GetModule("RecipeOutputEvidence")
    if yieldService and type(yieldService.ObserveCurrentSchematic)=="function" then
        local good,ob=pcall(yieldService.ObserveCurrentSchematic,yieldService,recipeID,key)
        if good and type(ob)=="table" and ob.readOnlyObserved==true and
            ob.recipeID==recipeID and ob.professionKey==key and
            ob.panelToken==recipe.panelToken and
            (ob.status=="OBSERVED_FIXED" or ob.status=="OBSERVED_VARIABLE") then
            if positive(expectedOutputID) and ob.outputItemID~=expectedOutputID then
                out.yieldState="LIVE_SOURCE_OUTPUT_ID_CONFLICT"
            elseif positive(ob.outputItemID) and positive(ob.outputMin) and
                positive(ob.outputMax) and ob.outputMin<=ob.outputMax then
                out.yieldState=ob.status
                out.outputItemID=ob.outputItemID
                out.outputMin=ob.outputMin
                out.outputMax=ob.outputMax
            end
        end
    end
    return out
end
JLP:RegisterModule("SecondaryVolatileAdvisory",V)
