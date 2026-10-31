local _, JLP = ...

-- Strategy-agnostic runtime envelope for every profession known to the registry.
-- This is intentionally non-persistent until versioned DB migrations exist.
-- Production execution remains owned by the existing Planner/Execution layers.
local ProfessionRuntimeState = {
    contract = "generic-profession-runtime-state-v1",
    envelopeContract = "generic-profession-state-envelope-v1",
    persistent = false,
    states = {},
    revision = 0,
}

local function registry()
    return JLP:GetModule("ProfessionRegistry")
end

local function now()
    if type(time)=="function" then
        local ok,value=pcall(time)
        if ok then return value end
    end
    return nil
end

local function copyTable(source)
    local out={}
    for k,v in pairs(source or {}) do out[k]=v end
    return out
end

local function defaultStage(reg,key)
    return reg and reg:IsProductionEnabled(key) and "production-enabled" or "staged"
end

function ProfessionRuntimeState:_Build(key, options)
    local reg=registry()
    if not reg then return nil,"REGISTRY_UNAVAILABLE" end
    local normalized=reg:NormalizeKey(key)
    if not normalized then return nil,"UNSUPPORTED_PROFESSION" end
    options=type(options)=="table" and options or {}
    local envelope,err=reg:BuildStateEnvelope(normalized,{
        strategyKey=options.strategyKey,
        skill=options.skill,
        stage=options.stage or defaultStage(reg,normalized),
        routeRef=options.routeRef,
        checkpoint=options.checkpoint,
        payload=options.payload,
    })
    if not envelope then return nil,err end
    envelope.runtimeContract=self.contract
    envelope.persistent=false
    envelope.revision=tonumber(options.revision) or 0
    envelope.updatedAt=options.updatedAt
    return envelope,nil
end

function ProfessionRuntimeState:Ensure(key)
    local reg=registry()
    local normalized=reg and reg:NormalizeKey(key) or nil
    if not normalized then return nil,"UNSUPPORTED_PROFESSION" end
    if not self.states[normalized] then
        local envelope,err=self:_Build(normalized,{revision=0,updatedAt=now()})
        if not envelope then return nil,err end
        self.states[normalized]=envelope
    end
    return self.states[normalized],nil
end

function ProfessionRuntimeState:Get(key)
    local state,err=self:Ensure(key)
    if not state then return nil,err end
    local out=copyTable(state)
    out.payload=copyTable(state.payload)
    return out,nil
end

function ProfessionRuntimeState:Update(key, patch)
    patch=type(patch)=="table" and patch or {}
    local current,err=self:Ensure(key)
    if not current then return nil,err end
    local reg=registry()
    local normalized=current.professionKey
    local strategy=patch.strategyKey
    if strategy==nil then strategy=current.strategyKey end
    if strategy~=nil and not reg:HasStrategy(normalized,strategy) then return nil,"UNSUPPORTED_STRATEGY" end

    local payload
    if patch.payload~=nil then
        payload=copyTable(patch.payload)
    else
        payload=copyTable(current.payload)
    end
    if type(patch.mergePayload)=="table" then
        for k,v in pairs(patch.mergePayload) do payload[k]=v end
    end

    local nextState,buildErr=self:_Build(normalized,{
        strategyKey=strategy,
        skill=patch.skill~=nil and patch.skill or current.skill,
        stage=patch.stage~=nil and patch.stage or current.stage,
        routeRef=patch.routeRef~=nil and patch.routeRef or current.routeRef,
        checkpoint=patch.checkpoint~=nil and patch.checkpoint or current.checkpoint,
        payload=payload,
        revision=(tonumber(current.revision) or 0)+1,
        updatedAt=now(),
    })
    if not nextState then return nil,buildErr end
    self.states[normalized]=nextState
    self.revision=self.revision+1
    local snapshot=self:Get(normalized)
    if JLP.EventBus then JLP.EventBus:Emit("PROFESSION_RUNTIME_STATE_UPDATED",normalized,snapshot) end
    return snapshot
end

function ProfessionRuntimeState:Reset(key)
    local reg=registry()
    local normalized=reg and reg:NormalizeKey(key) or nil
    if not normalized then return false,"UNSUPPORTED_PROFESSION" end
    self.states[normalized]=nil
    self.revision=self.revision+1
    local state=self:Ensure(normalized)
    local snapshot=self:Get(normalized)
    if JLP.EventBus then JLP.EventBus:Emit("PROFESSION_RUNTIME_STATE_UPDATED",normalized,snapshot) end
    return true,state
end

function ProfessionRuntimeState:GetKeys()
    local reg=registry()
    return reg and reg:GetStateKeys() or {}
end

function ProfessionRuntimeState:Validate()
    local reg=registry()
    local errors={}
    if not reg then return {"registry-unavailable"} end
    for _,key in ipairs(reg:GetStateKeys()) do
        local state,err=self:Ensure(key)
        if not state then
            errors[#errors+1]=tostring(key)..":"..tostring(err)
        else
            local ok,reason=reg:ValidateStateEnvelope(state)
            if not ok then errors[#errors+1]=tostring(key)..":"..tostring(reason) end
        end
    end
    return errors
end

function ProfessionRuntimeState:GetSummary()
    local reg=registry()
    local lines={"Profession runtime state: generic · non-persistent · registry-scoped"}
    for _,key in ipairs(self:GetKeys()) do
        local state=self:Get(key)
        lines[#lines+1]=string.format(
            "%s · %s · strategy %s · revision %d",
            reg and reg:GetDisplayNameOrKey(key) or key,
            tostring(state and state.stage or "unavailable"),
            tostring(state and state.strategyKey or "unassigned"),
            tonumber(state and state.revision) or 0
        )
    end
    return table.concat(lines,"\n")
end

JLP:RegisterModule("ProfessionRuntimeState",ProfessionRuntimeState)
