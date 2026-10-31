local _, JLP = ...

-- P0-164: distinguishes a profession's registered workflow from its native
-- action path. None of these read-only observations grants a production data
-- receipt, CraftRecipe/CraftEnchant permission or gathering automation.
-- No client/build version is checked here: runtime symbols and *current*
-- profession observations are the sole capability signals.
local Matrix = {
    contract = "profession-native-capability-matrix-v1",
    nativeDispatchAllowed = false,
    readOnly = true,
}

local function callable(container, name)
    return type(container)=="table" and type(container[name])=="function"
end

local function nativePath(def)
    if not def then return "UNKNOWN" end
    if def.key=="ENCHANTING" then return "TARGETED_ENCHANT" end
    if def.key=="MINING" then return "NODE_GATHERING_WITH_OPTIONAL_SMELTING" end
    for _,strategy in ipairs(def.progressionStrategies or {}) do
        if strategy=="RECIPE_CRAFTING" then return "CRAFT_RECIPE" end
    end
    return "WORLD_INTERACTION"
end

function Matrix:Assess(professionKey, recipeID)
    local registry=JLP:GetModule("ProfessionRegistry")
    local def=registry and registry:Get(professionKey)
    if not def then
        return {contract=self.contract,professionKey=nil,state="UNSUPPORTED_PROFESSION",
            workflowAvailable=false,nativeDispatchAllowed=false,readOnly=true}
    end
    local path=nativePath(def)
    local client=C_TradeSkillUI
    local apiAvailable=false
    if path=="TARGETED_ENCHANT" then
        apiAvailable=callable(client,"CraftEnchant") and callable(client,"GetRecipeInfo")
            and callable(client,"GetEnchantItems")
    elseif path=="CRAFT_RECIPE" or path=="NODE_GATHERING_WITH_OPTIONAL_SMELTING" then
        apiAvailable=callable(client,"CraftRecipe") and callable(client,"GetRecipeInfo")
            and callable(client,"GetCraftableCount")
    end
    local livePanel=false
    local api=JLP:GetModule("ProfessionAPI")
    if api and type(api.GetOpenProfessionContext)=="function" then
        local ok,panel=pcall(api.GetOpenProfessionContext,api)
        livePanel=ok and type(panel)=="table" and panel.verified==true
            and panel.professionKey==def.key or false
    end
    -- Only the existing, session-fenced ProfessionAPI recipe-context checker
    -- may attest learned/identity; GetRecipeInfo alone cannot establish
    -- membership in the currently open profession panel.
    local learned=nil
    local id=tonumber(recipeID)
    local recipeContext=nil
    if id and id>0 and id==math.floor(id) and livePanel and
        api and type(api.GetExecutionRecipeContext)=="function" then
        local kind=path=="TARGETED_ENCHANT" and "enchant" or "craft"
        local ok,observed=pcall(api.GetExecutionRecipeContext,api,id,def.key,kind)
        if ok and type(observed)=="table" then
            recipeContext=observed
            if observed.verified==true and type(observed.learned)=="boolean" then
                learned=observed.learned
            end
        end
    end
    local state
    if path=="WORLD_INTERACTION" then state="WORLD_INTERACTION_NO_NATIVE_CRAFT_API"
    elseif path=="NODE_GATHERING_WITH_OPTIONAL_SMELTING" then state=apiAvailable and "SMELTING_API_PRESENT_GATHERING_MANUAL" or "GATHERING_MANUAL_SMELTING_API_UNAVAILABLE"
    elseif not apiAvailable then state="NATIVE_API_UNAVAILABLE"
    elseif not livePanel then state="CURRENT_PROFESSION_PANEL_UNVERIFIED"
    elseif learned==false then state="RECIPE_NOT_LEARNED"
    elseif learned==nil then state="RECIPE_IDENTITY_UNVERIFIED"
    else state="NATIVE_API_PRESENT_AUTHORITY_NOT_GRANTED" end
    local allowedByExistingPolicy=def.maturity and def.maturity.production==true or false
    return {
        contract=self.contract,professionKey=def.key,professionLabel=def.label,
        workflowAvailable=registry:IsWorkflowEnabled(def.key),
        path=path,apiAvailable=apiAvailable,verifiedPanel=livePanel,
        recipeID=id,learned=learned,state=state,
        recipeObservation=recipeContext and (recipeContext.reason or "UNKNOWN") or nil,
        productionDatasetEligible=allowedByExistingPolicy,
        nativeDispatchAllowed=false,executionEligible=false,readOnly=true,
        requiresExplicitUserAction=true,
        -- The only authority to dispatch remains the original guarded native
        -- service, current recipe/reagent checks, transaction ledger and recovery.
        authority="NONE_FROM_CAPABILITY_MATRIX",
    }
end

function Matrix:AssessAll()
    local registry=JLP:GetModule("ProfessionRegistry")
    local result={}
    for _,key in ipairs(registry and registry:GetKeys() or {}) do
        result[#result+1]=self:Assess(key)
    end
    return result
end

function Matrix:Validate()
    local registry=JLP:GetModule("ProfessionRegistry")
    if not registry then return {"profession-registry-unavailable"} end
    local errors={}
    for _,key in ipairs(registry:GetKeys() or {}) do
        local row=self:Assess(key)
        if row.workflowAvailable~=true or row.nativeDispatchAllowed~=false or
            row.readOnly~=true or row.path=="UNKNOWN" then
            errors[#errors+1]="capability-contract-invalid:"..key
        end
    end
    return errors
end

JLP:RegisterModule("ProfessionNativeCapabilityMatrix",Matrix)
