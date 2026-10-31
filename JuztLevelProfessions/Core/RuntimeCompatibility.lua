local _, JLP = ...
-- P0/F1: build-agnostic runtime capability inspection. Build IDs describe
-- provenance; they do not grant or revoke a feature. No native calls are made
-- and no production, purchase, transport or protected action is authorized.
local Layer = {contract="jlp-runtime-capability-layer-v1",readOnly=true,
    nativeDispatchAllowed=false,productionAuthority=false}
local function validBuild(n)
    return type(n)=="number" and n==n and n>0 and n==math.floor(n)
        and n<math.huge and n<=9007199254740991
end
local function resolve(path)
    if type(path)~="string" or path=="" or path:find("[^%w_%.]") then return nil end
    local node=_G
    for part in path:gmatch("[^%.]+") do
        if type(node)~="table" then return nil end
        node=rawget(node,part)
    end
    return node
end
function Layer:Read(options)
    options=type(options)=="table" and options or {}
    local info=JLP:GetModule("ClientBuildInfo")
    local result=nil
    if info and type(info.Read)=="function" then
        -- A failing build-info provider must not break read-only UI services.
        -- Missing identity is UNKNOWN, not a valid current-client receipt.
        local ok,read=pcall(info.Read,info,options.provider)
        if ok and type(read)=="table" then result=read end
    end
    local build=result and result.buildNumber or nil
    local interface=result and result.interfaceVersion or nil
    if interface~=nil and not validBuild(interface) then interface=nil end
    local expected=string.format("forever:%s|interface:%s",
        tostring(build or "unknown"),tostring(interface or "unknown"))
    -- A provider's `known` flag without a matching token is not a verified
    -- current session. Capability checks remain independent of this identity.
    local known=validBuild(build) and result and result.known==true and
        result.token==expected and
        (result.interfaceVersion==nil or validBuild(result.interfaceVersion))
    return {contract=self.contract,known=known==true,clientBuild=known and build or nil,
        clientBuildToken=known and expected or nil,interface=interface,
        clientSessionVerified=known==true and interface~=nil,
        source=known and "LIVE_CLIENT" or "UNKNOWN_CLIENT",nativeDispatchAllowed=false}
end
-- Return an observed client session receipt, never a historical build constant.
-- Consumers that require current evidence must fail closed on UNKNOWN.
function Layer:GetSessionReceipt(options)
    local live=self:Read(options)
    if live.clientSessionVerified == true and
        type(live.clientBuildToken)=="string" and live.clientBuildToken~="" then
        return live.clientBuildToken,live
    end
    return nil,live
end

function Layer:SessionUnchanged(token,options)
    if type(token)~="string" or token=="" then return false,"SESSION_UNVERIFIED" end
    local now=self:GetSessionReceipt(options)
    if now==nil then return false,"SESSION_UNVERIFIED" end
    if now~=token then return false,"SESSION_CHANGED" end
    return true,"SESSION_CURRENT"
end

function Layer:CheckAPI(name)
    if type(name)~="string" or name=="" or name:find("[^%w_%.]") or
        name:sub(1,1)=="." or name:sub(-1)=="." or name:find("..",1,true) then
        return false,"INVALID_API_SYMBOL"
    end
    local symbol=resolve(name)
    return type(symbol)=="function",type(symbol)=="function" and "API_AVAILABLE" or "API_UNAVAILABLE"
end
local function requirements(required)
    if required==nil then return {} end
    if type(required)~="table" then return nil end
    local count,highest=0,0
    for k in pairs(required) do
        if type(k)~="number" or k~=math.floor(k) or k<1 or k>128 then return nil end
        count=count+1
        if k>highest then highest=k end
    end
    if count~=highest then return nil end
    for i=1,count do
        local name=required[i]
        if type(name)~="string" or name=="" then return nil end
    end
    return required
end
function Layer:Assess(required,sourceBuild,options)
    local live=self:Read(options)
    local names=requirements(required)
    local missing={}
    if names then
        for i=1,#names do
            local ok=self:CheckAPI(names[i])
            if not ok then missing[#missing+1]=names[i] end
        end
    end
    -- Provenance selectors must be explicit numeric IDs; string conversion is
    -- not evidence of an independently identified source.
    local source=sourceBuild
    local sourceValid=validBuild(source)
    local invalidSource=sourceBuild~=nil and not sourceValid
    local relation=invalidSource and "INVALID_SOURCE_BUILD" or
        (sourceValid and (live.known and (source==live.clientBuild and "MATCH" or
        "HISTORICAL_REFERENCE") or "UNKNOWN_CLIENT") or "NO_SOURCE")
    local status=not names and "INVALID_API_REQUIREMENTS" or
        invalidSource and "INVALID_SOURCE_BUILD" or
        (#missing==0 and "AVAILABLE" or "API_UNAVAILABLE")
    -- A missing LIVE API must not hide an independently installed static
    -- reference. Source-build identity and actual source integrity are checked
    -- by the relevant dataset provider, not inferred from this numeric ID.
    -- Conversely an API being present cannot grant native action authority.
    local staticEligible=sourceValid and not invalidSource
    return {contract=self.contract,status=status,
        client=live,sourceBuild=sourceValid and source or nil,sourceRelation=relation,
        missing=missing,apiAvailable=names~=nil and #missing==0,
        dataCanBeRead=staticEligible==true and names~=nil,staticReferenceEligible=staticEligible==true,
        staticReferenceVerified=false,clientAPIAvailable=names~=nil and #missing==0,
        readOnly=true,nativeDispatchAllowed=false,
        productionAuthority=false,purchaseAllowed=false}
end
-- A feature is an observed set of callable APIs, not a build allowlist.
-- `any` names are alternative capabilities; `all` names are mandatory.
-- No feature assessment performs native calls or authorizes actions.
local FEATURE_REQUIREMENTS = {
    PROFESSION_PANEL = {all={}, any={"C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetTradeSkillLine"}},
    RECIPE_IDENTITY = {all={"C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetAllRecipeIDs"}, any={}},
    RECIPE_QUANTITY = {all={"C_TradeSkillUI.GetCraftableCount"}, any={}},
    ENCHANT_TARGET = {all={"C_TradeSkillUI.IsEnchantTargetValid"}, any={}},
    BAG_ITEM_COUNT = {all={}, any={"C_Item.GetItemCount",
        {"C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo"}}},
    CRAFT_RECIPE = {all={"C_TradeSkillUI.CraftRecipe"}, any={}},
    CRAFT_ENCHANT = {all={"C_TradeSkillUI.CraftEnchant"}, any={}},
}
function Layer:AssessFeature(feature, options)
    local rule=FEATURE_REQUIREMENTS[feature]
    local missing,alternatives={},{}
    if rule then
        for _,name in ipairs(rule.all) do
            if not self:CheckAPI(name) then missing[#missing+1]=name end
        end
        for _,alternative in ipairs(rule.any) do
            if type(alternative)=="string" then
                if self:CheckAPI(alternative) then alternatives[#alternatives+1]=alternative end
            elseif type(alternative)=="table" and #alternative>0 then
                local allPresent=true
                for _,name in ipairs(alternative) do
                    if not self:CheckAPI(name) then allPresent=false;break end
                end
                if allPresent then alternatives[#alternatives+1]=table.concat(alternative," + ") end
            end
        end
    end
    local hasAlternative=rule~=nil and (#rule.any==0 or #alternatives>0)
    local available=rule~=nil and #missing==0 and hasAlternative
    local live=self:Read(options)
    return {
        contract="jlp-runtime-feature-capabilities-v1",feature=feature,
        state=not rule and "UNKNOWN_FEATURE" or available and "API_CAPABILITIES_AVAILABLE" or "API_CAPABILITIES_UNAVAILABLE",
        available=available,missing=missing,satisfiedAlternatives=alternatives,
        alternativeRequired=rule~=nil and #rule.any>0,
        clientBuild=live.clientBuild,clientSessionVerified=live.clientSessionVerified==true,
        clientBuildToken=live.clientBuildToken,
        -- Existence is not proof of a valid UI panel, learned recipe, target,
        -- materials, fresh native receipt or protected user gesture.
        readOnly=true,plannerEligible=false,productionAuthority=false,
        nativeDispatchAllowed=false,executionEligible=false,
    }
end

function Layer:Validate()
    local issues={}
    local a=self:Assess({},70450,{provider=function()return "1.60.1","70532","test",16001 end})
    if a.status~="AVAILABLE" or a.sourceRelation~="HISTORICAL_REFERENCE" then issues[#issues+1]="historical-reference-unavailable" end
    local b=self:Assess({"C_TradeSkillUI.__jlp_missing_never_exists"},70009)
    if b.status~="API_UNAVAILABLE" or b.nativeDispatchAllowed~=false then issues[#issues+1]="missing-api-failopen" end
    return issues
end
JLP:RegisterModule("RuntimeCompatibility",Layer)
