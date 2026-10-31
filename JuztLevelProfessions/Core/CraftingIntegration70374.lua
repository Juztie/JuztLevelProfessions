local _,JLP=...
-- Unified reporting surface for all 12 professions. The production
-- Crafting/NativeDispatchService remains the ONLY execution boundary.
local Service={contract="JLP-CRAFTING-INTEGRATION-70374-1",readOnly=true,
    nativeDispatchAllowed=false,executionEligible=false,sourceBuild=70374}
local function mod(k) return JLP:GetModule(k) end
function Service:GetState(key,spellID,crafts)
    local registry=mod("ProfessionRegistry")
    key=registry and registry:NormalizeKey(key)
    if not key then return nil,"UNKNOWN_PROFESSION" end
    local build=mod("ClientBuildInfo")
    local current=build and type(build.GetBuildNumber)=="function" and build:GetBuildNumber()
    -- Report read-only integration state even when GetBuildInfo is missing.
    -- A missing build never authorizes a native operation.
    if type(current)~="number" or current~=math.floor(current) or current<1 or
        current>9007199254740991 then current=nil end
    if spellID~=nil and (type(spellID)~="number" or spellID~=math.floor(spellID) or spellID<1) then
        return nil,"INVALID_RECIPE_ID"
    end
    crafts=crafts or 1
    if type(crafts)~="number" or crafts~=math.floor(crafts) or crafts<1 or crafts>9999 then
        return nil,"INVALID_CRAFT_COUNT"
    end
    local def=registry:Get(key)
    local production=def and def.maturity and def.maturity.production==true or false
    local planEngine=mod("Planner")
    local plan=planEngine and planEngine.GetProfessionPlan and planEngine:GetProfessionPlan(key) or nil
    local state={contract=self.contract,sourceBuild=70374,professionKey=key,
        skillLineID=def.skillLineID,professionEnum=def.professionEnum,
        progressionStrategies=def.progressionStrategies,
        productionMaturity=production,nativeDispatchAllowed=false,
        executionEligible=false,readOnly=true,clientBuild=current,
        clientBuildRelation=not current and "UNKNOWN_CLIENT" or
            (current==70374 and "MATCH" or "HISTORICAL_REFERENCE"),
        actionKind=plan and plan.actionKind or "NOT_READY",
        currentRecipeName=plan and plan.step and plan.step.recipe or nil,
        currentRecipeTarget=plan and plan.step and plan.step.skillTarget or nil,
        -- Dynamic native state describes a pre-existing guarded engine;
        -- exposing it here never grants the permission to use that engine.
        nativeActionState="DISABLED_OR_NOT_QUALIFIED",
        referenceState=spellID and "NOT_QUERIED" or "NO_RECIPE_REQUESTED"}
    if production then
        local crafting=mod("Crafting")
        if crafting then
            local action=key=="ENCHANTING" and crafting.GetEnchantActionState or crafting.GetCraftActionState
            if type(action)=="function" then
                local ok,value=pcall(action,crafting,key,plan)
                if ok and type(value)=="table" then
                    state.nativeActionState=tostring(value.status or "unknown")
                    state.nativeRecipeID=value.recipeID
                    state.nativeRequestedCount=value.requestedCount
                    state.nativeCompletedCount=value.completedCount
                    state.nativeConfirmationRequired=value.confirmationRequired==true
                else
                    state.nativeActionState="NATIVE_STATUS_UNAVAILABLE"
                end
            end
        end
    end
    if spellID then
        local bridge=mod("ProfessionDataBridge70374")
        if not bridge or not bridge.GetRecipeState then return nil,"DATA_BRIDGE_UNAVAILABLE" end
        local reference,err=bridge:GetRecipeState(key,spellID,crafts)
        if not reference then return nil,err end
        local valid,why=bridge:ValidateState(reference)
        if not valid then return nil,why end
        state.recipeID=spellID
        state.referenceState=reference.materialState
        state.referenceRecordKind=reference.recordKind
        state.referenceRecipeAccessVerified=false
        state.materials=reference.materials
        state.referenceRevision=reference.revision
    end
    state.reason=production and "EXISTING_GUARDED_NATIVE_PATH_ONLY" or "RESEARCH_ONLY_NO_NATIVE_AUTHORITY"
    return state
end
function Service:GetSummary(key,spellID,crafts)
    local state,err=self:GetState(key,spellID,crafts)
    if not state then return "Crafting integration: "..tostring(err) end
    return string.format("M5 craft state %s: %s / native=%s / reference=%s / %s. Observations do not authorize crafting.",
        state.professionKey,tostring(state.actionKind),tostring(state.nativeActionState),
        tostring(state.referenceState),tostring(state.reason))
end
JLP:RegisterModule("CraftingIntegration70374",Service)
