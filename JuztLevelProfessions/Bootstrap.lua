local ADDON_NAME, JLP = ...

_G.JuztLevelProfessions = JLP
JLP.name = ADDON_NAME
JLP.version = "0.34.236-p0-first-aid-continuity-owner-travel-tests"
JLP.modules = JLP.modules or {}
JLP.data = JLP.data or {}
JLP.runtime = JLP.runtime or {}
-- Internal travel/Tom namespaces; not exported as standalone addons.
JLP._integratedTravel = JLP._integratedTravel or {}
JLP._integratedTom = JLP._integratedTom or {}

-- Errors are runtime-only: bounded and coalesced so a failing event handler
-- cannot grow memory indefinitely or flood SavedVariables. The original
-- event remains recoverable for diagnostics; no exception grants gameplay rights.
local MAX_RUNTIME_ERRORS = 64
function JLP:RecordRuntimeError(eventName, message)
    self.runtime = self.runtime or {}
    local runtime = self.runtime
    if type(runtime.errors) ~= "table" then runtime.errors = {} end
    local event = tostring(eventName or "UNKNOWN"):sub(1,96)
    local reason = tostring(message or "UNKNOWN"):sub(1,384)
    local entries = runtime.errors
    -- Also coalesce interleaved HUD/travel failures. Keep an index only for
    -- retained entries so its memory cannot grow beyond the 64-row log.
    local signatures=runtime.errorSignatures
    if type(signatures)~="table" then signatures={};runtime.errorSignatures=signatures end
    local signature=event.."\n"..reason
    local previous=signatures[signature]
    if previous then
        previous.occurrences = (tonumber(previous.occurrences) or 1) + 1
        runtime.errorCoalesced = (runtime.errorCoalesced or 0) + 1
        return false, "COALESCED"
    end
    if #entries >= MAX_RUNTIME_ERRORS then
        local removed=table.remove(entries, 1)
        if removed then signatures[removed.event.."\n"..removed.error]=nil end
        runtime.errorDropped = (runtime.errorDropped or 0) + 1
    end
    local row={ event=event, error=reason, occurrences=1 }
    entries[#entries+1] = row
    signatures[signature]=row
    return true
end

function JLP:Print(message)
    local prefix = "|cffffb72bJuztLevel - Professions|r"
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. (self.SafeText and self:SafeText(message) or tostring(message)))
    end
end

function JLP:RegisterModule(name, module)
    assert(type(name) == "string" and name ~= "", "module name required")
    assert(type(module) == "table", "module table required")
    self.modules[name] = module
end

function JLP:GetModule(name)
    return self.modules[name]
end

-- One synchronous observation/request, never a cross-event Planner cache.
-- Only derived read-only inputs/models are memoized. Receipt/native validation
-- keeps its existing live checks. Reentrant client events get their own scope.
local observationPass
local function pack(...) return {n=select("#",...),...} end
local unpackValues=unpack or table.unpack
local function observationError(err)
    if type(debugstack)=="function" then return tostring(err).."\n"..debugstack(2) end
    return tostring(err)
end
function JLP:GetObservationPass() return observationPass end
function JLP:MarkObservationsDirty(reason,key,itemIDs)
    self.runtime.observationRevision=(self.runtime.observationRevision or 0)+1
    self.runtime.observationReason=reason
    local state=self:GetPlanningRevisions()
    local relevantKeys
    if not key and not itemIDs then relevantKeys={};for _,k in ipairs(self:GetObservationKeys()) do relevantKeys[k]=true end end
    for candidate,row in pairs(state.professions) do
        local affected=key==candidate
        if itemIDs then
            for id in pairs(itemIDs) do if row.dependencies[id] then affected=true;break end end
        elseif not key then
            -- Broad events dirty only already demanded/relevant owned work.
            affected=relevantKeys[candidate]==true
        end
        if affected then
            row.revision=row.revision+1;row.reason=reason
            if observationPass then
                for group in pairs(observationPass.memo) do
                    if group:find(candidate,1,true) then observationPass.memo[group]=nil end
                end
            end
        end
    end
end
local function isProfessionOwned(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    return ownership~=nil and ownership.owned==true
end
-- Revision/dependency metadata only. No recipe choice, queue, plan or client
-- fact survives an evaluation pass here. At most 12 keys / 1024 input IDs each.
function JLP:GetPlanningRevisions()
    local identity=self:GetModule("CharacterIdentity")
    local owner=identity and identity:GetKey(true)
    local state=self.runtime.planningRevisions
    if not state or state.characterKey~=owner then
        state={characterKey=owner,professions={}};self.runtime.planningRevisions=state
    end
    return state
end
function JLP:RegisterPlanningDependencies(key,candidates)
    if not isProfessionOwned(key) then return end
    local state=self:GetPlanningRevisions()
    local row=state.professions[key] or {revision=0,evaluatedRevision=-1,dependencies={}}
    state.professions[key]=row;row.dependencies={};local count=0
    local function add(materials,depth)
        if depth>8 then return end
        for _,m in ipairs(materials or {}) do
            local id=tonumber(m.itemID)
            if id and not row.dependencies[id] and count<1024 then row.dependencies[id]=true;count=count+1 end
            local conversion=m.craftedFrom
            if conversion then add(conversion.materials or conversion.reagents or {conversion},depth+1) end
        end
    end
    for _,candidate in ipairs(candidates or {}) do add(candidate.materials or candidate.recipe and candidate.recipe.materials,0) end
end
function JLP:WithObservationPass(reason, evaluate, fresh)
    if observationPass and not fresh then return evaluate() end
    local previous=observationPass
    local identity=self:GetModule("CharacterIdentity")
    observationPass={reason=reason,token={},memo={},evaluating={},memoCount=0,readOnly=true,
        characterKey=identity and identity:GetKey(true) or nil}
    local result
    local ok,err=xpcall(function() result=pack(evaluate()) end,observationError)
    observationPass=previous
    if not ok then error(err,0) end
    return unpackValues(result,1,result.n)
end
function JLP:MemoObservation(group,key,evaluate)
    local pass=observationPass
    if not pass then return evaluate() end
    local rows=pass.memo[group]
    if not rows then rows={};pass.memo[group]=rows end
    local row=rows[key]
    if row then return unpackValues(row,1,row.n) end
    if pass.memoCount>=256 then return evaluate() end -- bounded transient storage
    -- Recursive derivations must not install a partially built model.
    local busy=pass.evaluating[group]
    if not busy then busy={};pass.evaluating[group]=busy end
    if busy[key] then return evaluate() end
    busy[key]=true
    row=pack(evaluate());busy[key]=nil;rows[key]=row;pass.memoCount=pass.memoCount+1
    return unpackValues(row,1,row.n)
end

-- Execution/session observers reconcile real workflow owners, not every
-- registry recommendation. The union is bounded by the 12 workflow keys.
function JLP:GetObservationKeys()
    local reg=self:GetModule("ProfessionRegistry")
    if not reg then return {} end
    local relevant={}
    local function add(key)
        key=reg:NormalizeKey(key)
        if key and isProfessionOwned(key) and reg:ResolveWorkflowAvailability(key,"executionFlow").state=="available" then relevant[key]=true end
    end
    local api=self:GetModule("ProfessionAPI")
    for key in pairs(observationPass and observationPass.affectedProfessions or {}) do add(key) end
    local identity=self:GetModule("CharacterIdentity")
    local character=identity and identity:GetKey()
    local store=self.DB and self.DB.account and self.DB.account.executionProgress
    store=store and store.characters and store.characters[character]
    for key,row in pairs(store and store.professions or {}) do if row.active then add(key) end end
    local workspace=self:GetModule("WorkspaceOrchestrator")
    for key in pairs(workspace and workspace.sessions or {}) do add(key) end
    local route=self:GetModule("RouteSession")
    for _,entry in ipairs(route and route.active and route.active.actions or {}) do if entry.status~="completed" then add(entry.key or entry.profession) end end
    local flow=self:GetModule("ExecutionFlow")
    add(flow and flow.professionOpenKey)
    local profile=self.DB and self.DB.profile
    add(profile and profile.activeSecondaryCurrentStep)
    local window=self.MainWindow
    if window and window.frame and window.frame:IsShown() and window.activePage=="Guide" then
        local guide=self.UIPages and self.UIPages.Guide
        local mode=guide and guide.mode or profile and profile.guideMode
        add(mode)
        if mode=="primary1" or mode=="primary2" then
            local pair=api and api:GetPrimaryPair() or {};add(pair[mode=="primary1" and 1 or 2] and pair[mode=="primary1" and 1 or 2].key)
        end
    end
    local owner=self:GetModule("IntegratedDestinationOwner")
    local target=owner and owner.active
    if target and target.category=="CURRENT_STEP" then
        local source=owner.resumeSource
        add(target.professionKey or (source and (source.workflowProfessionKey or source.professionKey or source.profession)) or
            (target.point and (target.point.professionKey or target.point.profession)) or target.owner)
    end
    local acquisition=self:GetModule("AcquisitionPlanner")
    add(acquisition and acquisition.materialServiceWatch and acquisition.materialServiceWatch.key)
    add(acquisition and acquisition.recipeServiceWatch and acquisition.recipeServiceWatch.key)
    local recovery=self:GetModule("TransactionRecovery")
    local checkpoint=recovery and recovery.GetCheckpoint and recovery:GetCheckpoint()
    add(checkpoint and checkpoint.key)
    local shared=self:GetModule("GatheringSharedMapState")
    local state=shared and shared:GetCharacterState()
    local goal=state and state.automaticSupplyGoal
    add(goal and goal.ownerProfession)
    local craft=self:GetModule("Crafting")
    for _,field in ipairs({"pendingCraft","pendingEnchant","activeRepeat","pending"}) do
        local pending=craft and craft[field]
        if type(pending)=="table" then add(pending.professionKey or pending.key or pending.profession) end
    end
    local keys={};for _,key in ipairs(reg:GetWorkflowKeys("executionFlow")) do if relevant[key] then keys[#keys+1]=key end end
    return keys
end
