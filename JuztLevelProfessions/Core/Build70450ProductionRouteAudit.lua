local _, JLP = ...
-- Field-by-field build 70450 audit of the retained 70009 production routes.
-- This receipt is never an execution entitlement: trainer availability, yield,
-- skill progression, per-character learning, license and target validation
-- require separate review and the existing native guards.
local Audit = {
    contract="JLP-70450-PRODUCTION-ROUTE-AUDIT-1", sourceBuild=70450,
    readOnly=true, nativeDispatchAllowed=false, executionEligible=false,
    productionAuthority=false,
}
local BUILD=70450
local HASHES={
    SkillLineAbility="df6018b459f851bdee27edfc74d2f45678177cba50aeed4bf12bc9d5fa4973e4",
    SpellReagents="47a239be7aca0043dea181311d86d0956edcea46c52d7491ee04140372b3846d",
    SpellEffect="855a3d89a295f55131443e42f69a6d8306f99b3dab085b7d790d62631c66a451",
    SpellName="88f0e96ad902ab1a15da366018edfc73ecf0b0ad3e02402c064527bdf9d1a912",
    SpellItemEnchantment="5cab2410297859ad6f7a679af477c14b34c3754716d612e28fd9fabe30f68095",
}
local function fail(reason) return nil,reason end
local function exactReagents(lhs,rhs)
    if type(lhs)~="table" or type(rhs)~="table" or #lhs~=#rhs then return false end
    local counts={}
    for _,r in ipairs(lhs) do
        if type(r)~="table" or type(r.itemID)~="number" or type(r.quantity)~="number" or
            r.quantity<=0 or r.quantity~=math.floor(r.quantity) then return false end
        local k=tostring(r.itemID)..":"..tostring(r.quantity)
        counts[k]=(counts[k] or 0)+1
    end
    for _,r in ipairs(rhs) do
        if type(r)~="table" then return false end
        local id,qty=tonumber(r.itemID or r[1]),tonumber(r.quantity or r[2])
        local k=tostring(id)..":"..tostring(qty)
        if not counts[k] or counts[k]==0 then return false end
        counts[k]=counts[k]-1
    end
    for _,n in pairs(counts) do if n~=0 then return false end end
    return true
end
local function sourceProof()
    local ref=JLP.data and JLP.data.build70450ProductionRouteEvidence
    local recipe=JLP.data and JLP.data.build70450Recipes
    local output=JLP.data and JLP.data.build70450CraftOutputs
    if type(ref)~="table" or ref.contract~="JLP-70450-PRODUCTION-ROUTE-EVIDENCE-1" or
        ref.sourceBuild~=BUILD or ref.readOnly~=true or ref.nativeDispatchAllowed~=false or
        ref.productionAuthority~=false or ref.executionEligible~=false or
        type(ref.professions)~="table" or type(ref.inputSHA256)~="table" or
        type(recipe)~="table" or recipe.sourceBuild~=BUILD or recipe.readOnly~=true or
        recipe.nativeDispatchAllowed~=false or type(recipe.inputSHA256)~="table" or
        type(output)~="table" or output.sourceBuild~=BUILD or output.readOnly~=true or
        output.nativeDispatchAllowed~=false or type(output.inputSHA256)~="table" then
        return nil,"SOURCE_CONTRACT_OR_AUTHORITY_CONFLICT"
    end
    for name,sha in pairs(HASHES) do
        if ref.inputSHA256[name]~=sha then return nil,"PRODUCTION_SOURCE_HASH_CONFLICT:"..name end
        if name~="SpellItemEnchantment" and recipe.inputSHA256[name]~=sha then
            return nil,"RECIPE_SOURCE_HASH_CONFLICT:"..name
        end
        if (name=="SpellEffect" or name=="SpellName" or name=="SpellItemEnchantment") and
            output.inputSHA256[name]~=sha then return nil,"OUTPUT_SOURCE_HASH_CONFLICT:"..name end
    end
    return ref
end
function Audit:AssessRecipe(professionKey,recipeID,requestedBuild)
    if requestedBuild~=BUILD then return fail("EXPLICIT_BUILD_70450_REQUIRED") end
    local key=tostring(professionKey or ""):upper()
    if key~="TAILORING" and key~="ENCHANTING" then return fail("UNSUPPORTED_PRODUCTION_PROFESSION") end
    local id=tonumber(recipeID)
    if not id or id<1 or id~=math.floor(id) then return fail("INVALID_RECIPE_ID") end
    local ref,err=sourceProof();if not ref then return fail(err) end
    local proof=ref.professions[key] and ref.professions[key][id]
    if type(proof)~="table" then return fail("NOT_IN_VERIFIED_70450_ROUTE") end
    local dataset=JLP.data and JLP.data[key:lower()]
    if type(dataset)~="table" or dataset.key~=key or dataset.sourceBuild~=70009 or
        dataset.productionBaselineBuild~=70009 or dataset.legacyProductionBaseline~=true then
        return fail("HISTORICAL_DATASET_IDENTITY_CONFLICT")
    end
    local step, segments, variants = nil, {}, {}
    local identity=JLP:GetModule("ProductionTailoringRecipeIdentity")
    for index,v in ipairs(dataset.route or {}) do
        if tonumber(v.recipeID)==id then
            -- A route segment is not a new recipe. Check every occurrence
            -- against canonical identity/reagents before accepting reuse.
            if v.recipe~=proof.name then return fail("ROUTE_RECIPE_IDENTITY_CONFLICT") end
            if not exactReagents(v.materials,proof.reagents) then return fail("HISTORICAL_ROUTE_REAGENT_MISMATCH_70450") end
            for _,prior in ipairs(variants) do
                if identity and identity.RecipeFieldsMatch and not identity:RecipeFieldsMatch(prior,v) then
                    return fail("CONFLICTING_ROUTE_RECIPE_IDENTITY")
                end
                for _,field in ipairs({"outputPerCraft","outputQuantityReference","requiredSkill","rawYellowThreshold","rawGreyThreshold","rawMinSkillLineRank"}) do
                    if prior[field]~=nil and v[field]~=nil and prior[field]~=v[field] then return fail("CONFLICTING_ROUTE_RECIPE_IDENTITY") end
                end
            end
            variants[#variants+1]=v
            local minimum,target=tonumber(v.skillMin),tonumber(v.skillTarget)
            if not minimum or not target or minimum<1 or target<=minimum or
                minimum~=math.floor(minimum) or target~=math.floor(target) then return fail("INVALID_ROUTE_SEGMENT_INTERVAL") end
            if segments[#segments] and minimum < segments[#segments].skillTarget then return fail("OVERLAPPING_ROUTE_RECIPE_SEGMENTS") end
            if v.outputItemID~=nil and v.outputItemID~=proof.itemID then return fail("CREATE_ITEM_EFFECT_CONFLICT") end
            if v.enchantmentID~=nil and v.enchantmentID~=proof.enchantmentID then return fail("TARGET_ENCHANT_EFFECT_CONFLICT") end
            segments[#segments+1]={index=index,segmentID=key..":"..tostring(index)..":"..tostring(minimum).."-"..tostring(target),skillMin=minimum,skillTarget=target}
            step=step or v
        end
    end
    if not step or step.recipe~=proof.name or
        proof.skillLineID~=(key=="TAILORING" and 197 or 333) then
        return fail("ROUTE_RECIPE_IDENTITY_CONFLICT")
    end
    if not exactReagents(step.materials,proof.reagents) then
        return fail("HISTORICAL_ROUTE_REAGENT_MISMATCH_70450")
    end
    local recipes=JLP:GetModule("Build70450RecipeCatalogue")
    local outputs=JLP:GetModule("Build70450CraftOutput")
    if not recipes or not outputs then return fail("CANONICAL_REFERENCE_MODULE_MISSING") end
    local canonical,reason=recipes:GetRecipe(key,id,BUILD)
    if not canonical then return fail("CANONICAL_RECIPE_"..tostring(reason)) end
    if canonical.sourceBuild~=BUILD or canonical.spellID~=id or
        canonical.skillLineID~=proof.skillLineID or canonical.professionKey~=key or
        canonical.name~=proof.name or canonical.recordKind~="RECIPE_CANDIDATE" or
        canonical.readOnly~=true or canonical.nativeDispatchAllowed~=false or
        canonical.productionAuthority~=false then
        return fail("CANONICAL_RECIPE_IDENTITY_OR_AUTHORITY_CONFLICT")
    end
    if not exactReagents(canonical.reagents,proof.reagents) then
        return fail("CANONICAL_REAGENTS_MISMATCH")
    end
    if canonical.rawMinSkillLineRank~=proof.minSkill or
        canonical.rawYellowThreshold~=proof.yellowRaw or
        canonical.rawGreyThreshold~=proof.greyRaw then
        return fail("RAW_SKILL_RANGES_MISMATCH")
    end
    local effects,e=outputs:ForKnownRecipe(key,id,1,BUILD)
    if not effects then return fail("OUTPUT_REFERENCE_"..tostring(e)) end
    if effects.effectCount~=1 or type(effects.effects)~="table" or #effects.effects~=1 then
        return fail("OUTPUT_EFFECT_CARDINALITY_UNKNOWN")
    end
    local effect=effects.effects[1]
    if key=="TAILORING" then
        if proof.kind~="CREATE_ITEM" or effect.kind~="CREATED_ITEM" or
            effect.itemID~=proof.itemID then return fail("CREATE_ITEM_EFFECT_CONFLICT") end
    else
        if proof.kind~="ENCHANT_ITEM" or effect.kind~="TARGET_ITEM_ENCHANTMENT" or
            effect.enchantmentID~=proof.enchantmentID or
            effects.outputRangeState~="NO_SEPARATE_CREATED_ITEM" then
            return fail("TARGET_ENCHANT_EFFECT_CONFLICT")
        end
    end
    return {contract=self.contract,professionKey=key,recipeID=id,sourceBuild=BUILD,
        segments=segments,segmentCount=#segments,
        legacyProductionBaselineBuild=70009,sourceFieldsMatch=true,
        verifiedFields={"SPELL_ID","SPELL_NAME","SKILL_LINE_ID","REAGENT_ID_AND_QUANTITY",
            "RAW_SKILL_RANKS","EFFECT_TYPE_AND_ITEM_OR_ENCHANT_ID"},
        outputKind=proof.kind,outputItemID=proof.itemID,enchantmentID=proof.enchantmentID,
        yieldVerified=false,liveRecipeLearnedVerified=false,acquisitionVerified=false,
        licenseAndRightsReviewed=false,fullProductionAuthority=false,
        state="70450_SOURCE_FIELDS_MATCH_NOT_PRODUCTION_AUTHORIZED",
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
        productionAuthority=false},nil
end
function Audit:AssessAll()
    local out={contract=self.contract,sourceBuild=BUILD,expected=29,matched=0,
        rejected=0,errors={},readOnly=true,nativeDispatchAllowed=false,
        productionAuthority=false,executionEligible=false}
    local ref,error=sourceProof()
    if not ref then out.status="SOURCE_INVALID";out.errors[1]=error;return out end
    for _,key in ipairs({"TAILORING","ENCHANTING"}) do
        for id in pairs(ref.professions[key] or {}) do
            local receipt,reason=self:AssessRecipe(key,id,BUILD)
            if receipt then out.matched=out.matched+1 else
                out.rejected=out.rejected+1
                out.errors[#out.errors+1]=key..":"..tostring(id)..":"..tostring(reason)
            end
        end
    end
    out.status=out.matched==29 and out.rejected==0 and "REFERENCE_FIELDS_MATCH" or "BLOCKED"
    return out
end
JLP:RegisterModule("Build70450ProductionRouteAudit",Audit)
