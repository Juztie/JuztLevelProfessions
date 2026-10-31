local _, JLP = ...

local function prerequisiteExecution(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    if ownership and ownership.owned==true then return nil end
    local state=ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN"
    local reg=JLP:GetModule("ProfessionRegistry")
    local label=reg and reg:GetDisplayNameOrKey(key) or tostring(key)
    local text=state=="PROFESSION_NOT_LEARNED" and
        ("Learn "..label.." before JuztLevel can plan this profession.") or
        ("Verify learned "..label.." ownership before JuztLevel can plan this profession.")
    return {key=ownership and ownership.key or key,ownership=ownership,state=state,
        status=state,terminalReason=state,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,lightweightPrerequisite=true,guidance=text}
end

local function withObservationPass(reason,fn,fresh)
    if JLP.WithObservationPass then return JLP:WithObservationPass(reason,fn,fresh) end
    return fn()
end

-- Stateful completion tracking for non-crafting route actions.  The ActionQueue
-- remains a live derivation of current requirements; this layer records the
-- baseline for the actionable head and only marks it complete when client data
-- proves the requested change actually happened.
local ExecutionProgress = {
    contract = "stateful-route-action-progress-v2",
    initialized = false,
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end
local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local SUPPORTED = {
    ["retrieve-material"] = "RETRIEVE",
    ["retrieve-raw"] = "RETRIEVE",
    ["retrieve-tool"] = "RETRIEVE",
    ["retrieve-tool-material"] = "RETRIEVE",
    ["acquire-material"] = "ACQUIRE",
    ["acquire-raw"] = "ACQUIRE",
    ["acquire-tool-material"] = "ACQUIRE",
    ["craft-tool"] = "PREPARE",
    ["craft-intermediate"] = "PREPARE",
    ["train-rank"] = "TRAIN",
    ["verify-recipe"] = "VERIFY",
    ["learn-recipe"] = "LEARN_RECIPE",
    ["learn-profession"] = "LEARN",
}

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return value end
    end
    return nil
end

local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function getStore()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.executionProgress = JLP.DB.account.executionProgress or { characters = {} }
    JLP.DB.account.executionProgress.characters = JLP.DB.account.executionProgress.characters or {}
    local key = characterKey()
    local store = JLP.DB.account.executionProgress.characters[key]
    if type(store) ~= "table" then
        store = { professions = {}, updatedAt = nil }
        JLP.DB.account.executionProgress.characters[key] = store
    end
    store.professions = store.professions or {}
    return store
end

local function ensureRecord(store, key)
    local record = store.professions[key]
    if type(record) ~= "table" then
        record = { active = nil, history = {}, transitions = 0 }
        store.professions[key] = record
    end
    record.history = type(record.history) == "table" and record.history or {}
    return record
end

local function whole(v)
    return type(v)=="number" and v==v and v>=0 and v<math.huge and v==math.floor(v) and v or nil
end
-- An inventory API can return numeric zero while explicitly declaring the
-- reading unavailable. This is NOT a confirmed zero for route receipts.
local function owned(itemID)
    itemID = whole(itemID)
    local unavailable={bags=nil,bank=nil,total=nil,bagsKnown=false,
        bankKnown=false,totalKnown=false}
    if not itemID or itemID==0 then return unavailable end
    local inventory=JLP:GetModule("Inventory")
    if not inventory or type(inventory.GetOwned)~="function" then return unavailable end
    local ok,value=pcall(inventory.GetOwned,inventory,itemID)
    if not ok or type(value)~="table" then return unavailable end
    local bags=value.bagKnown==true and whole(value.bags) or nil
    local bank=value.bankKnown==true and whole(value.bank) or nil
    local bankCurrent=bank~=nil and value.bankEvidence~="SAVED_ORDINARY_BANK_SNAPSHOT" and
        (value.bankEvidence=="GENERIC_INCLUDE_BANK_API" or
         value.bankObservationLive==true)
    local total=(bags~=nil and bankCurrent) and bags+bank or nil
    return {bags=bags,bank=bank,total=total,bagsKnown=bags~=nil,
        bankKnown=bank~=nil,totalKnown=total~=nil}
end

local function professionFacts(key)
    local api = JLP:GetModule("ProfessionAPI")
    local info = api and api:Get(key) or nil
    return {
        skill = tonumber(info and info.skill) or 0,
        maxSkill = tonumber(info and info.maxSkill) or 0,
        maxSkillKnown = info~=nil and info.cached~=true and
            whole(info.maxSkill)~=nil and whole(info.maxSkill)>0,
        -- A cached profession snapshot is useful for display/fallback, but it is
        -- not strong enough evidence that a just-requested LEARN action completed.
        -- Require a live profession observation for that transition.
        professionDetected = info ~= nil and info.cached ~= true,
        professionCached = info ~= nil and info.cached == true,
        professionName = info and info.name or nil,
    }
end

local function targetCap(plan, action)
    local gate = plan and plan.step and plan.step.trainer or nil
    return tonumber(gate and gate.nextCap)
        or tonumber(action and action.targetCap)
        or tonumber(plan and plan.step and plan.step.skillTarget)
end

local function recipeName(plan)
    return plan and plan.actionKind == "craft" and plan.step and plan.step.recipe or nil
end

local function actionRecipe(action, plan)
    return (action and (action.recipe or action.recipeName)) or recipeName(plan)
end

local function recipeKnowledge(key, recipe)
    if not recipe or recipe == "" then return "unknown" end
    local progress = JLP:GetModule("RouteProgress")
    if progress and progress.GetRecipeKnowledge then
        local value = progress:GetRecipeKnowledge(recipe, key, false)
        if value == "known" or value == "not-known" then return value end
    end
    return "unknown"
end

local function assignedIdentity(action)
    if type(action)=="table" and action.identityContract=="semantic-plan-action-v1" and not action.identityUnresolved
        and type(action.actionID)=="string" and action.actionID~="" then
        return action.actionID
    end
    return nil -- Only project an execution ID already assigned by ActionQueue.
end

local function actionIdentity(key, action, plan)
    if type(action)~="table" or not SUPPORTED[tostring(action.kind or "")] then return nil end
    return assignedIdentity(action)
end

local function factsFor(key, action, plan)
    local storage = owned(action and action.itemID)
    local profession = professionFacts(key)
    local recipe = actionRecipe(action, plan)
    return {
        bags = storage.bags,
        bank = storage.bank,
        total = storage.total,
        bankKnown = storage.bankKnown,
        bagsKnown = storage.bagsKnown,
        totalKnown = storage.totalKnown,
        skill = profession.skill,
        maxSkill = profession.maxSkill,
        maxSkillKnown = profession.maxSkillKnown,
        targetCap = targetCap(plan, action),
        professionDetected = profession.professionDetected and true or false,
        professionCached = profession.professionCached and true or false,
        professionName = profession.professionName,
        recipe = recipe,
        recipeKnowledge = recipeKnowledge(key, recipe),
        observedAt = now(),
    }
end

-- Semantic route provenance is distinct from the queue action ID and from a
-- mutable planning revision.  Reuse the existing identity encoder without
-- depending on quantities currently owned, queue position, prices or strategy.
local function routeContextID(key, plan)
    local queue=JLP:GetModule("ActionQueue")
    if not plan or not plan.step or not queue or not queue.GetActionID then return nil end
    return queue:GetActionID(key, {
        kind="plan-route-context", sourceInfo=plan.step.sourceInfo,
    }, plan, 1)
end

-- Read the existing v1 wire format, never encode or assign an action identity.
-- Compare character/profession/route atoms with the separate provenance encoder.
local function contextMatches(action, context, scopeOnly, plan, key)
    local function fields(value, compact)
        if type(value)~="string" or (not compact and value:sub(1,27)~="23:semantic-plan-action-v1|") then return nil end
        local out,offset={},1
        local count=compact and 2 or 20
        for index=1,count do
            local start,finish,length=value:find("^(%d+):",offset)
            length=tonumber(length)
            if not start or not length or tostring(length)~=value:sub(start,finish-1) or finish+length>#value then return nil end
            out[index]=value:sub(finish+1,finish+length)
            offset=finish+length+1
            if index<count and not compact then
                if value:sub(offset,offset)~="|" then return nil end
                offset=offset+1
            end
        end
        return offset==#value+1 and out or nil
    end
    local actual=fields(action.actionID)
    local expected=fields(context)
    local reg=registry()
    key=key or (plan and plan.key) or (expected and expected[3])
    key=reg and reg.NormalizeKey and reg:NormalizeKey(key) or key
    if not actual or key==nil or actual[2]~=tostring(characterKey()) or actual[3]~=tostring(key) then return false end
    -- A route step requires qualified provenance; a genuine no-step LEARN does not.
    if (context~=nil and not expected) or (plan and plan.step and not expected) then return false end
    -- Saved records retain only kind/item/source and original route provenance;
    -- sourceInfo/recipe-context atoms were checked at admission, not persisted.
    if scopeOnly then
        if actual[4]~=tostring(action.kind or "unknown") then return false end
        if actual[5]~=tostring(action.itemID or "") then return false end
        if actual[6]~=tostring(action.source or "") then return false end
    end
    if not scopeOnly then
        if actual[4]~=tostring(action.kind or "unknown") or actual[5]~=tostring(action.itemID or "")
            or actual[6]~=tostring(action.source or "") then return false end
        local source=type(action.sourceInfo)=="table" and action.sourceInfo or {}
        for offset,value in ipairs({source.kind or "",source.name or "",source.zone or "",source.id or source.npcID or ""}) do
            if actual[offset+12]~=tostring(value) then return false end
        end
        local step=plan and plan.step
        local recipe=action.recipeID or action.recipe or action.recipeName or (step and (step.recipeID or step.recipe)) or ""
        local cap=action.targetCap or (plan and plan.actionKind=="train" and step and step.trainer and step.trainer.nextCap) or ""
        if actual[7]~=tostring(recipe) or actual[18]~=tostring(action.exceptionSource or "") or
            actual[19]~=tostring(cap) or actual[20]~=tostring(action.identityOccurrence or 1) then return false end
        if action.kind=="transfer-alt-material" or action.source=="alt-bank" then
            local nested=fields(actual[17],true)
            if not nested or type(action.characterKey)~="string" or action.characterKey=="" or
                nested[1]~=tostring(action.identityContext or "") or nested[2]~=action.characterKey then return false end
        elseif actual[17]~=tostring(action.identityContext or "") then return false end
    end
    if expected then
        for _,index in ipairs({1,2,3,8,9,10,11,12}) do
            if actual[index]~=expected[index] then return false end
        end
    else
        for index=8,12 do
            if actual[index]~="" then return false end
        end
    end
    return true
end

local function queueHead(key, plan, queue)
    if type(plan)~="table" or (plan.step~=nil and type(plan.step)~="table") or
        type(queue)~="table" or type(queue.actions)~="table" then return nil,false end
    local reg=registry()
    local function sameKey(value)
        return value==nil or (reg and reg.NormalizeKey and reg:NormalizeKey(value) or value)==key
    end
    if not sameKey(queue.key) or not sameKey(plan.key) or (queue.plan~=nil and queue.plan~=plan) then return nil,false end
    local index=queue.currentIndex
    if type(index)~="number" or index<0 or index%1~=0 then return nil,false end
    if index==0 then
        return nil,queue.status=="complete" and next(queue.actions)==nil,routeContextID(key,plan)
    end
    if queue.key==nil or queue.plan~=plan then return nil,false end
    local action=queue.actions[index]
    if queue.status~="active" or index>#queue.actions or type(action)~="table" or
        type(action.kind)~="string" or not sameKey(action.professionKey) then return nil,false end
    if not assignedIdentity(action) then return nil,false end
    local context=routeContextID(key,plan)
    if not contextMatches(action,context,false,plan) then return nil,false end
    return action,true,context
end

local function clamp(value, low, high)
    value = tonumber(value) or 0
    if value < low then return low end
    if high ~= nil and value > high then return high end
    return value
end

function ExecutionProgress:Classify(action)
    return action and SUPPORTED[tostring(action.kind or "")] or nil
end

function ExecutionProgress:Evaluate(active, facts)
    if type(active) ~= "table" or type(facts) ~= "table" then
        return { complete=false, current=0, required=0, ratio=0, reason=nil }
    end
    local baseline = active.baseline or {}
    local required = math.max(1, math.floor(tonumber(active.requestedQuantity) or 1))
    local group = active.group
    local current, complete, reason = 0, false, nil

    local bagsObserved=baseline.bagsKnown==true and facts.bagsKnown==true and
        whole(baseline.bags)~=nil and whole(facts.bags)~=nil
    local totalObserved=baseline.totalKnown==true and facts.totalKnown==true and
        whole(baseline.total)~=nil and whole(facts.total)~=nil
    local observationQualified=true
    if group == "RETRIEVE" then
        observationQualified=bagsObserved
        if bagsObserved then
            current=math.max(0,facts.bags-baseline.bags)
            complete=current>=required
            if complete then reason="moved-to-bags" end
        end
    elseif group == "ACQUIRE" or group == "PREPARE" then
        -- A bank cache does not prove an acquisition; use only independently
        -- known before/after bags or independently known total holdings.
        observationQualified=bagsObserved or totalObserved
        if observationQualified then
            local deltaBags=bagsObserved and math.max(0,facts.bags-baseline.bags) or 0
            local deltaTotal=totalObserved and math.max(0,facts.total-baseline.total) or 0
            current=math.max(deltaBags,deltaTotal)
            if group=="PREPARE" and active.kind=="craft-tool" and bagsObserved and
                facts.bags>0 and baseline.bags==0 then current=math.max(current,1) end
            complete=current>=required
            if complete then reason=group=="PREPARE" and "prerequisite-crafted" or "inventory-acquired" end
        end
    elseif group == "TRAIN" then
        -- A cached or absent profession cap is not evidence of training.
        observationQualified=baseline.maxSkillKnown==true and facts.maxSkillKnown==true
        if observationQualified then
            local before=math.max(0,tonumber(baseline.maxSkill) or 0)
            local after=math.max(0,tonumber(facts.maxSkill) or 0)
            local target=tonumber(active.targetCap) or tonumber(facts.targetCap)
            current=math.max(0,after-before)
            required=target and math.max(1,target-before) or 1
            complete=(target and after>=target and after>before) or after>before
            if complete then reason="skill-cap-increased" end
        end
    elseif group == "VERIFY" then
        required = 1
        local knowledge = tostring(facts.recipeKnowledge or "unknown")
        current = knowledge ~= "unknown" and 1 or 0
        complete = current >= 1
        if complete then
            reason = knowledge == "known" and "recipe-verified-known" or "recipe-verified-not-known"
        end
    elseif group == "LEARN_RECIPE" then
        required = 1
        current = facts.recipeKnowledge == "known" and 1 or 0
        complete = current >= 1
        if complete then reason = "recipe-learned" end
    elseif group == "LEARN" then
        required = 1
        current = facts.professionDetected and 1 or 0
        complete = current >= 1
        if complete then reason = "profession-learned" end
    end

    return {
        complete = complete and true or false,
        current = clamp(current, 0),
        required = required,
        ratio = required > 0 and clamp(current / required, 0, 1) or 0,
        reason = reason,
        recipeKnowledge = facts.recipeKnowledge,
        professionDetected = facts.professionDetected and true or false,
        observationQualified = observationQualified,
        observationState = observationQualified and "OBSERVED" or "INVENTORY_UNKNOWN",
    }
end

local function makeActive(key, action, plan, facts, reason, context)
    local group = SUPPORTED[tostring(action.kind or "")]
    local id = actionIdentity(key, action, plan)
    if not group or not id then return nil end
    local quantity = math.max(1, math.floor(tonumber(action.quantity) or 1))
    local cap = targetCap(plan, action)
    local active = {
        id = id,
        routeContextID = context,
        key = key,
        group = group,
        kind = action.kind,
        text = action.text,
        detail = action.detail,
        itemID = tonumber(action.itemID),
        itemName = action.itemName,
        source = action.source,
        requestedQuantity = quantity,
        recipe = actionRecipe(action, plan),
        professionName = (plan and plan.profession and plan.profession.name) or professionLabel(key),
        targetSkill = plan and plan.step and tonumber(plan.step.skillTarget) or nil,
        targetCap = cap,
        status = "active",
        startedAt = now(),
        startedReason = tostring(reason or "observe"),
        baseline = {
            bags = facts.bags,
            bank = facts.bank,
            total = facts.total,
            bagsKnown = facts.bagsKnown==true,
            bankKnown = facts.bankKnown==true,
            totalKnown = facts.totalKnown==true,
            skill = facts.skill,
            maxSkill = facts.maxSkill,
            maxSkillKnown = facts.maxSkillKnown==true,
            recipeKnowledge = facts.recipeKnowledge,
            professionDetected = facts.professionDetected and true or false,
        },
        progress = { current=0, required=(group == "TRAIN" and cap and math.max(1, cap - (facts.maxSkill or 0)) or quantity), ratio=0 },
        lastObservedAt = facts.observedAt,
    }
    return active
end

local function appendHistory(record, entry)
    record.history[#record.history + 1] = entry
    while #record.history > 40 do table.remove(record.history, 1) end
end

local function completeActive(record, active, evaluation, facts, reason)
    active.status = "completed"
    active.completedAt = now()
    active.completionReason = reason or evaluation.reason or "confirmed"
    active.progress = {
        current = evaluation.current,
        required = evaluation.required,
        ratio = evaluation.ratio,
    }
    active.final = {
        bags = facts.bags,
        bank = facts.bank,
        total = facts.total,
        skill = facts.skill,
        maxSkill = facts.maxSkill,
        recipeKnowledge = facts.recipeKnowledge,
        professionDetected = facts.professionDetected and true or false,
    }
    active.evidence = {
        recipeKnowledge = evaluation.recipeKnowledge,
        professionDetected = evaluation.professionDetected and true or false,
    }
    record.lastCompleted = active
    record.transitions = (tonumber(record.transitions) or 0) + 1
    appendHistory(record, active)
    record.active = nil
    return active
end

local function supersedeActive(record, active, facts, reason)
    active.status = "superseded"
    active.completedAt = now()
    active.completionReason = reason or "route-changed-before-confirmation"
    active.final = {
        bags = facts.bags,
        bank = facts.bank,
        total = facts.total,
        skill = facts.skill,
        maxSkill = facts.maxSkill,
        recipeKnowledge = facts.recipeKnowledge,
        professionDetected = facts.professionDetected and true or false,
    }
    record.lastSuperseded = active
    appendHistory(record, active)
    record.active = nil
    return active
end

function ExecutionProgress:Observe(key, reason, prepared)
    local prerequisite=prerequisiteExecution(key)
    if prerequisite then return false,prerequisite,nil end
    local reg=registry()
    local availability=reg and reg:ResolveWorkflowAvailability(key,"executionFlow") or nil
    if availability and availability.state~="available" then return false, self:GetStatus(availability.key or key), nil end
    if reg then key=availability.key end
    local store = getStore()
    if not store then return false end
    local record = ensureRecord(store, key)
    prepared=type(prepared)=="table" and prepared or nil
    local planner = JLP:GetModule("Planner")
    local plan = prepared and prepared.plan
    if plan==nil and prepared and type(prepared.queue)=="table" then plan=prepared.queue.plan end
    if plan==nil then plan=planner and planner:GetProfessionPlan(key) or nil end
    local queue=prepared and prepared.queue
    if queue==nil then
        local module=JLP:GetModule("ActionQueue")
        queue=module and module:Build(key,plan) or nil
    end
    local action,queueQualified,context=queueHead(key,plan,queue)
    local currentGroup = self:Classify(action)
    local currentID = currentGroup and actionIdentity(key, action, plan) or nil
    local changed = false
    local transition = nil

    if record.active then
        local active = record.active
        if type(active.id)~="string" or active.id=="" or active.identityUnresolved or
            (active.identityContract~=nil and active.identityContract~="semantic-plan-action-v1") or
            (active.key~=nil and active.key~=key) or
            not SUPPORTED[tostring(active.kind or "")] or active.group~=SUPPORTED[active.kind] or
            (queueQualified and not contextMatches({actionID=active.id,kind=active.kind,itemID=active.itemID,source=active.source},active.routeContextID,true,nil,key)) then
            transition=supersedeActive(record,active,{},"unqualified-saved-execution-identity")
            changed=true
        elseif queueQualified then
        local activeFacts = factsFor(key, active, plan)
        local evaluation = self:Evaluate(active, activeFacts)
        active.progress = {
            current = evaluation.current,
            required = evaluation.required,
            ratio = evaluation.ratio,
            observationQualified = evaluation.observationQualified,
            observationState = evaluation.observationState,
        }
        active.lastObservedAt = activeFacts.observedAt
        active.lastReason = tostring(reason or "observe")
        -- Completion evidence must belong to the SAME semantic transaction.
        -- For inventory actions, a queue-head change can be legitimate after a
        -- successful acquisition (the next reagent/craft becomes current).
        -- Only admit that case when route provenance is unchanged and the new
        -- head cannot be another operation for the same item, regardless of kind.  A recipe,
        -- route or material-source switch must never complete an old action
        -- merely because a generic inventory delta happened at the same time.
        local sameAction = currentID ~= nil and currentID == active.id
        local directEvidence = active.group == "TRAIN" or active.group == "LEARN"
            or active.group == "LEARN_RECIPE" or active.group == "VERIFY"
        local sameRoute = active.routeContextID ~= nil and
            active.routeContextID == context
        -- Inventory deltas do not identify a vendor, AH listing, or action
        -- kind. Another operation for the same item competes, even when the
        -- source or kind differs. A dependency-safe advance to the route's
        -- craft head is the separate, legitimate case: it is not an inventory
        -- acquisition operation and still requires unchanged routeContextID.
        local previousItemID = tonumber(active.itemID)
        local nextItemID = action and tonumber(action.itemID) or nil
        local competingAction = previousItemID ~= nil and nextItemID ~= nil
            and previousItemID == nextItemID
            and action.kind ~= "craft-leveling"
        local attributed = sameAction or (directEvidence and not competingAction)
            or (sameRoute and not competingAction)
        if evaluation.complete and attributed then
            transition = completeActive(record, active, evaluation, activeFacts, evaluation.reason)
            changed = true
        elseif currentID ~= active.id then
            transition = supersedeActive(record, active, activeFacts,
                "route-or-action-changed-before-qualified-confirmation")
            changed = true
        end
        end
    end

    if not record.active and currentGroup and currentID then
        -- Do not immediately re-open the exact action that was just completed in
        -- the same observation.  Live Planner/Inventory data normally removes it,
        -- but this guard avoids one-frame cache races on Forever.
        if not (transition and transition.status == "completed" and transition.id == currentID) then
            local currentFacts = factsFor(key, action, plan)
            record.active = makeActive(key, action, plan, currentFacts, reason, context)
            changed = true
        end
    end

    record.lastObservedAt = now()
    record.lastReason = tostring(reason or "observe")
    record.currentActionID = currentID
    record.currentActionKind = action and action.kind or nil
    store.updatedAt = now()

    if changed and JLP.EventBus then
        JLP.EventBus:Emit("PROFESSION_EXECUTION_UPDATED", key, self:GetStatus(key), transition)
    end
    return changed, self:GetStatus(key), transition
end

function ExecutionProgress:ObserveAll(reason)
    local changed = false
    for _, key in ipairs((JLP.GetObservationKeys and JLP:GetObservationKeys() or productionKeys())) do
        local one = self:Observe(key, reason)
        if one then changed = true end
    end
    return changed
end

function ExecutionProgress:Initialize()
    self.initialized = true
    return self:ObserveAll("player-login")
end

local function progressText(active)
    if not active then return nil end
    local progress = active.progress or {}
    local current = math.max(0, math.floor(tonumber(progress.current) or 0))
    local required = math.max(1, math.floor(tonumber(progress.required) or tonumber(active.requestedQuantity) or 1))
    if active.group == "TRAIN" and progress.observationQualified==false then
        return "Waiting for verified profession cap observation" end
    if active.group == "TRAIN" then
        local before = tonumber(active.baseline and active.baseline.maxSkill) or 0
        local cap = tonumber(active.targetCap) or (before + required)
        return string.format("Skill cap %d -> %d", before + current, cap)
    end
    if (active.group=="RETRIEVE" or active.group=="ACQUIRE" or active.group=="PREPARE") and
        progress.observationQualified==false then return "Waiting for verified inventory observation" end
    if active.group == "RETRIEVE" then return string.format("%d / %d moved to bags", math.min(current, required), required) end
    if active.group == "ACQUIRE" then return string.format("%d / %d acquired", math.min(current, required), required) end
    if active.group == "PREPARE" then return string.format("%d / %d prepared", math.min(current, required), required) end
    if active.group == "VERIFY" then
        return current >= 1 and "Recipe verification complete" or "Waiting for recipe verification"
    end
    if active.group == "LEARN_RECIPE" then
        return current >= 1 and "Recipe learned" or ("Waiting to learn " .. tostring(active.recipe or "the recipe"))
    end
    if active.group == "LEARN" then
        return current >= 1 and "Profession learned" or ("Waiting to learn " .. tostring(active.professionName or "the profession"))
    end
    return string.format("%d / %d", math.min(current, required), required)
end

function ExecutionProgress:GetStatus(key)
    local reg=registry()
    local normalized=reg and reg:NormalizeKey(key) or key
    if reg and not normalized then return {contract=self.contract,key=key,status="unsupported-profession",terminalReason="UNSUPPORTED_PROFESSION"} end
    key=normalized or key
    local availability=reg and reg:ResolveWorkflowAvailability(key,"executionFlow") or nil
    if availability and availability.state~="available" then
        return {contract=self.contract,key=key,status=availability.state,terminalReason=availability.terminalReason,active=nil,historyCount=0,transitions=0}
    end
    local store = getStore()
    if not store then return nil end
    local record = ensureRecord(store, key)
    local active = record.active
    local last = record.lastCompleted
    return {
        contract = self.contract,
        key = key,
        status = active and "active" or "idle",
        active = active,
        activeID = active and active.id or nil,
        activeGroup = active and active.group or nil,
        activeKind = active and active.kind or nil,
        progressText = progressText(active),
        lastCompleted = last,
        lastCompletedGroup = last and last.group or nil,
        lastCompletedKind = last and last.kind or nil,
        lastCompletedAt = last and last.completedAt or nil,
        lastSuperseded = record.lastSuperseded,
        transitions = tonumber(record.transitions) or 0,
        historyCount = #(record.history or {}),
        lastObservedAt = record.lastObservedAt,
        lastReason = record.lastReason,
    }
end

function ExecutionProgress:HasCompleted(key, id, since)
    if type(id)~="string" or id=="" then return false, nil end
    local store = getStore()
    if not store then return false, nil end
    local record = ensureRecord(store, key)
    for i = #(record.history or {}), 1, -1 do
        local entry = record.history[i]
        if entry and entry.id == id and entry.status == "completed" then
            if not since or not entry.completedAt or entry.completedAt >= since then return true, entry end
        end
    end
    return false, nil
end

function ExecutionProgress:FormatCompact(status)
    if type(status) == "string" then status = self:GetStatus(status) end
    if not status then return "Execution progress: unavailable" end
    if status.active then
        local name = status.active.itemName or status.active.text or status.active.group or "route action"
        return string.format("Execution progress: %s - %s - %s", tostring(status.active.group), tostring(name), tostring(status.progressText or "in progress"))
    end
    if status.lastCompleted then
        local name = status.lastCompleted.itemName or status.lastCompleted.text or status.lastCompleted.group or "route action"
        return string.format("Execution progress: last confirmed %s - %s", tostring(status.lastCompleted.group), tostring(name))
    end
    return "Execution progress: no tracked route action yet"
end

function ExecutionProgress:GetSummary()
    local lines = {}
    for _, key in ipairs(productionKeys()) do
        local label = professionLabel(key)
        local text = self:FormatCompact(self:GetStatus(key)):gsub("^Execution progress:%s*", "")
        lines[#lines + 1] = label .. ": " .. text
    end
    return table.concat(lines, "\n")
end

-- Synchronous request scope; discarded before the caller returns.
do
    local build=ExecutionProgress.Observe
    function ExecutionProgress:Observe(...)
        local args={n=select("#",...),...}
        local function evaluate() return build(self,(unpack or table.unpack)(args,1,args.n)) end
        return withObservationPass("ExecutionProgress.Observe",evaluate)
    end
end
do
    local build=ExecutionProgress.ObserveAll
    function ExecutionProgress:ObserveAll(...)
        local args={n=select("#",...),...}
        local function evaluate() return build(self,(unpack or table.unpack)(args,1,args.n)) end
        return withObservationPass("ExecutionProgress.ObserveAll",evaluate)
    end
end

JLP:RegisterModule("ExecutionProgress", ExecutionProgress)
