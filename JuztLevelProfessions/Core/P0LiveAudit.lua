local _, JLP = ...

-- P0 phase-1 opt-in, passive client evidence recorder.
-- NO protected game API invocation, NO transaction mutation, NO automatic crafting.
-- The recorder is deliberately independent from the execution and recovery paths.
local Audit = { contract = "p0-live-audit-v1", schema = 1, limit = 400 }
local frame = CreateFrame("Frame")
local evidenceScope

local function db()
    if type(JuztLevelP0LiveAuditDB) ~= "table" then
        JuztLevelP0LiveAuditDB = {}
    end
    local store = JuztLevelP0LiveAuditDB
    if type(store.events) ~= "table" then store.events = {} end
    store.schema = 1
    return store
end

local function epoch()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return nil
end

local function elapsed()
    local fn = type(GetTimePreciseSec) == "function" and GetTimePreciseSec or GetTime
    if type(fn) == "function" then
        local ok, value = pcall(fn)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return nil
end

local function receipt()
    local compat = JLP:GetModule("RuntimeCompatibility")
    if compat and type(compat.GetSessionReceipt) == "function" then
        local ok, value = pcall(compat.GetSessionReceipt, compat)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return nil
end

local function client()
    if type(GetBuildInfo) ~= "function" then return nil, nil end
    local ok, _, build, _, interface = pcall(GetBuildInfo)
    if not ok then return nil, nil end
    return tonumber(build), tonumber(interface)
end

local function scalar(value)
    if type(value) == "number" or type(value) == "boolean" then return value end
    if type(value) == "string" then return value:sub(1, 128) end
    return nil
end

local function recoveryState()
    -- Recovery getters lazily create SavedVariables. Read existing records only.
    local module=JLP:GetModule("TransactionRecovery")
    local who
    if type(UnitGUID)=="function"then local ok,v=pcall(UnitGUID,"player");if ok and type(v)=="string"and v:match("^Player%-")then who="guid:"..v end end
    local account=JLP.DB and JLP.DB.account
    local records=account and account.transactionRecovery and account.transactionRecovery.characters
    local record=who and type(records)=="table"and records[who]
    local current=module and module.current
    if type(current)~="table"or current.key~=who then current=nil end
    local result={state=current and scalar(current.state)or "UNKNOWN_READ_ONLY_EXISTING_STATE",pendingState="UNKNOWN"}
    if current then result.reason=scalar(current.reason);result.snapshotID=scalar(current.snapshotID);result.retryAllowed=scalar(current.retryAllowed)end
    local pending=type(record)=="table"and record.pending
    if type(pending)=="table"then
        result.pending=true;result.pendingState="EXISTING_CHECKPOINT";result.recoveryID=scalar(pending.id or pending.recoveryID)
        result.ledgerID=scalar(pending.ledgerID);result.kind=scalar(pending.kind);result.status=scalar(pending.status)
        result.recipeID=scalar(pending.recipeID);result.castGUID=scalar(pending.expectedCastGUID)
        result.operationID=scalar(pending.expectedOperationID);result.clientSessionReceipt=scalar(pending.clientSessionReceipt)
    elseif type(record)=="table"then result.pending=false;result.pendingState="EXISTING_RECORD_NO_CHECKPOINT"end
    return result
end

local function append(event, details, withRecovery)
    local store = db()
    if store.enabled ~= true then return false end
    store.sequence = (tonumber(store.sequence) or 0) + 1
    local build, interface = client()
    local row = {
        sequence = store.sequence,
        event = tostring(event or "UNKNOWN"):sub(1, 64),
        at = epoch(),
        elapsed = elapsed(),
        build = build,
        interface = interface,
        receipt = receipt(),
    }
    if type(details) == "table" then
        for k, v in pairs(details) do
            if type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then
                row[k] = scalar(v)
            end
        end
    end
    if withRecovery then row.recovery = recoveryState() end
    if evidenceScope then row.context=evidenceScope()end
    local events = store.events
    events[#events+1] = row
    if #events > Audit.limit then
        table.remove(events, 1)
        store.dropped = (tonumber(store.dropped) or 0) + 1
    end
    return true
end

local function printMessage(message)
    if JLP.Print then JLP:Print("P0 Live Audit: " .. tostring(message)) end
end

function Audit:Start()
    local store = db()
    store.enabled = true
    append("AUDIT_START", {addonVersion = JLP.version}, true)
    printMessage("Recording enabled. /jlpaudit mark before-reload, then /reload. /jlpaudit status to inspect.")
    return true
end

function Audit:Stop()
    append("AUDIT_STOP", nil, true)
    if self.EndScenario then self:EndScenario() end
    db().enabled = false
    printMessage("Recording stopped. Evidence remains in JuztLevelP0LiveAuditDB SavedVariables.")
    return true
end

function Audit:Mark(label)
    local marker = tostring(label or "manual"):sub(1, 72)
    append("MANUAL_MARK", {label=marker}, true)
    printMessage("Marked: " .. marker)
end

function Audit:Snapshot(reason)
    append("READ_ONLY_SNAPSHOT", {label=tostring(reason or "manual"):sub(1,64)}, true)
    return recoveryState()
end

-- Explicit diagnostic capture for a release candidate. This records what the
-- running client actually exposes; API presence is never release approval or
-- native gameplay permission. Retain only a few bounded snapshots.
function Audit:CaptureReleaseStatus()
    local build,interface=client()
    local result={contract="jlp-release-observation-v1",addonVersion=JLP.version,
        at=epoch(),build=build,interface=interface,sessionReceipt=receipt(),
        APIs={},professions={},nativeDispatchAllowed=false,liveAcceptanceVerified=false}
    local capabilities=JLP:GetModule("RuntimeCompatibility")
    for _,name in ipairs({"C_TradeSkillUI.GetBaseProfessionInfo",
        "C_TradeSkillUI.GetAllRecipeIDs","C_TradeSkillUI.GetRecipeInfo",
        "C_TradeSkillUI.GetRecipeSchematic","C_TradeSkillUI.GetCraftableCount",
        "C_TradeSkillUI.CraftRecipe","C_TradeSkillUI.CraftEnchant",
        "C_AuctionHouse.ReplicateItems","C_AuctionHouse.GetReplicateItemInfo",
        "C_Container.GetContainerItemInfo","C_Map.GetBestMapForUnit",
        "C_Map.GetPlayerMapPosition","C_Map.GetMapInfo"}) do
        local ok,available=false,false
        if capabilities and type(capabilities.CheckAPI)=="function" then
            ok,available=pcall(capabilities.CheckAPI,capabilities,name)
        end
        result.APIs[name]=ok and available==true or false
    end
    local reg=JLP:GetModule("ProfessionRegistry")
    local detected={}
    -- GetDetected synchronizes KnowledgeCache; inspect only the raw current panel.
    if type(C_TradeSkillUI)=="table"and type(C_TradeSkillUI.GetBaseProfessionInfo)=="function"then
        local ok,value=pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        local def=ok and type(value)=="table"and reg and reg.GetBySkillLineID and reg:GetBySkillLineID(value.professionID)
        if def then detected[def.key]={skill=value.skillLevel,maxSkill=value.maxSkillLevel}end
    end
    for _,key in ipairs(reg and reg:GetKeys() or {}) do
        local observed=detected[key]
        local row={professionKey=key,liveDetected=type(observed)=="table" and observed.cached~=true,
            productionDeclared=reg:IsProductionEnabled(key),nativeDispatchAllowed=false,
            workflowEnabled=reg:IsWorkflowEnabled(key)}
        row.nativePathStatus="NOT_REQUESTED_READ_ONLY_AUDIT"
        if type(observed)=="table" then
            row.skill=scalar(observed.skill);row.maxSkill=scalar(observed.maxSkill)
        end
        -- Do not call Planner:GetProfessionPlan from diagnostics: it can replan.
        row.planStatus="NOT_REQUESTED_READ_ONLY_AUDIT"
        result.professions[#result.professions+1]=row
    end
    if evidenceScope then result.context=evidenceScope()end
    local store=db()
    store.releaseSnapshots=type(store.releaseSnapshots)=="table" and store.releaseSnapshots or {}
    store.releaseSnapshots[#store.releaseSnapshots+1]=result
    while #store.releaseSnapshots>3 do table.remove(store.releaseSnapshots,1) end
    printMessage("Release observation saved: "..tostring(JLP.version)..", build "..
        tostring(build or "UNKNOWN")..", interface "..tostring(interface or "UNKNOWN")..
        ". Client action tests are still required.")
    for _,row in ipairs(result.professions) do
        if row.liveDetected then
            printMessage(row.professionKey..": skill "..tostring(row.skill or "?")..
                "/"..tostring(row.maxSkill or "?")..", action "..
                tostring(row.planActionKind or "UNAVAILABLE")..", native "..
                tostring(row.nativePathStatus or "UNKNOWN")..", workflow "..
                tostring(row.workflowEnabled))
        end
    end
    return result
end

-- Explicit, read-only client probe. The observed values are diagnostic and
-- cannot change inventory caches, native policy or recovery state.
function Audit:Probe(itemID, recipeID)
    itemID = tonumber(itemID)
    recipeID = tonumber(recipeID)
    if itemID and (itemID<=0 or itemID~=math.floor(itemID)) then itemID=nil end
    if recipeID and (recipeID<=0 or recipeID~=math.floor(recipeID)) then recipeID=nil end
    local row = {at=epoch(), itemID=itemID, recipeID=recipeID,
        addonVersion=JLP.version, build=select(1,client()),
        clientReceipt=receipt(), readOnly=true, nativeDispatchAllowed=false}
    if itemID then
        if type(C_Item)=="table" and type(C_Item.GetItemCount)=="function" then
            local ok, value = pcall(C_Item.GetItemCount,itemID,false,false,false,false)
            local count = ok and tonumber(value) or nil
            if count and count>=0 and count<math.huge and count==math.floor(count) then
                row.bagCount=count
                row.bagCountState="API_OBSERVED"
            else row.bagCountState="UNKNOWN" end
        else row.bagCountState="UNAVAILABLE" end
        -- Inventory:GetOwned observes/persists item evidence and may scan bags.
        -- The audit already has a raw C_Item count; do not synchronize product caches.
        row.inventoryCacheState="NOT_REQUESTED_READ_ONLY_AUDIT"

    end
    if recipeID then
        local clientAPI=type(C_TradeSkillUI)=="table" and C_TradeSkillUI or nil
        if clientAPI and type(clientAPI.GetRecipeInfo)=="function" then
            local ok,info=pcall(clientAPI.GetRecipeInfo,recipeID)
            if ok and type(info)=="table" then
                row.recipeName=scalar(info.name)
                if type(info.learned)=="boolean"then row.recipeLearned=info.learned else row.recipeLearnedState="UNKNOWN"end
                row.recipeLearnedKnown=type(info.learned)=="boolean"
                row.recipeDifficulty=scalar(info.relativeDifficulty)
            else row.recipeInfoState="UNKNOWN" end
        else row.recipeInfoState="UNAVAILABLE" end
        local crafting=JLP:GetModule("Crafting")
        local selected=crafting and crafting.enchantTargets and crafting.enchantTargets[recipeID]
        if type(selected)=="table" and selected.guid then
            row.targetSelected=true
            row.targetGUID=scalar(selected.guid)
            if clientAPI and type(clientAPI.IsEnchantTargetValid)=="function" then
                local ok,value=pcall(clientAPI.IsEnchantTargetValid,recipeID,selected.guid)
                if ok and type(value)=="boolean" then row.targetValid=value
                else row.targetValidState="UNKNOWN" end
            else row.targetValidState="UNAVAILABLE" end
            if clientAPI and type(clientAPI.GetEnchantItems)=="function" then
                local ok,items=pcall(clientAPI.GetEnchantItems,recipeID)
                if ok and type(items)=="table" then
                    row.targetListed=false
                    for _,guid in pairs(items) do if guid==selected.guid then row.targetListed=true break end end
                else row.targetListState="UNKNOWN" end
            else row.targetListState="UNAVAILABLE" end
        else row.targetSelected=false end
    end
    row.context=evidenceScope and evidenceScope()or {state="UNKNOWN"}
    row.recovery=recoveryState()
    local store=db()
    store.probes=type(store.probes)=="table" and store.probes or {}
    store.probes[#store.probes+1]=row
    while #store.probes>20 do table.remove(store.probes,1) end
    append("CLIENT_API_PROBE",{itemID=itemID,recipeID=recipeID},true)
    printMessage("Probe recorded (bag="..tostring(row.bagCountState or row.bagCount or "n/a")..
        ", target="..tostring(row.targetValid==nil and row.targetValidState or row.targetValid)..").")
    return row
end

-- Snapshot callable runtime APIs without executing any gameplay action.
-- Kept separate from the crafting probe and bounded in SavedVariables.
function Audit:ProbeCapabilities()
    local runtime=JLP:GetModule("RuntimeCompatibility")
    local names={"PROFESSION_PANEL","RECIPE_IDENTITY","RECIPE_QUANTITY",
        "BAG_ITEM_COUNT","ENCHANT_TARGET","CRAFT_RECIPE","CRAFT_ENCHANT"}
    local row={at=epoch(),addonVersion=JLP.version,build=select(1,client()),
        clientReceipt=receipt(),readOnly=true,nativeDispatchAllowed=false,features={}}
    for _,name in ipairs(names) do
        local assessment=runtime and type(runtime.AssessFeature)=="function"
            and runtime:AssessFeature(name) or nil
        local state=assessment and assessment.state or "CAPABILITY_LAYER_UNAVAILABLE"
        local ready=assessment and assessment.available==true or false
        row.features[name]={state=state,available=ready}
        printMessage(name..": "..tostring(state))
    end
    local professions=JLP:GetModule("ProfessionAPI")
    local panel=professions and type(professions.GetReadOnlyProfessionObservation)=="function"
        and professions:GetReadOnlyProfessionObservation() or nil
    row.panelObservation={observed=panel and panel.observed==true or false,
        state=panel and panel.reason or "OBSERVATION_UNAVAILABLE",
        quality=panel and panel.observationQuality or "UNKNOWN",
        professionKey=panel and panel.professionKey or nil,
        skill=panel and panel.skill or nil,maxSkill=panel and panel.maxSkill or nil,
        nativeDispatchAllowed=false}
    printMessage("READ_ONLY_PANEL: "..tostring(row.panelObservation.state)..
        " ("..tostring(row.panelObservation.quality)..")")
    row.context=evidenceScope and evidenceScope()or {state="UNKNOWN"}
    local store=db()
    store.capabilities=type(store.capabilities)=="table" and store.capabilities or {}
    store.capabilities[#store.capabilities+1]=row
    while #store.capabilities>12 do table.remove(store.capabilities,1) end
    append("CLIENT_CAPABILITY_PROBE",{addonVersion=JLP.version},false)
    return row
end

function Audit:Clear()
    JuztLevelP0LiveAuditDB = {schema=1, enabled=false, events={}, sequence=0, dropped=0}
    printMessage("Recorder data cleared; recording disabled.")
end

function Audit:GetSummary()
    local store = db()
    local events = store.events
    local counts = {}
    local uniqueCasts = {}
    local unmatched = 0
    for _, row in ipairs(events) do
        counts[row.event] = (counts[row.event] or 0) + 1
        if row.event == "UNIT_SPELLCAST_SENT" and row.castGUID then
            uniqueCasts[row.castGUID] = true
        elseif row.event == "UNIT_SPELLCAST_SUCCEEDED" and row.castGUID and not uniqueCasts[row.castGUID] then
            -- This can be caused by starting recording mid-cast; it is not
            -- independently proof of a recovery defect.
            unmatched = unmatched + 1
        end
    end
    return {
        enabled=store.enabled == true,
        records=#events,
        dropped=tonumber(store.dropped) or 0,
        sequence=tonumber(store.sequence) or 0,
        events=counts,
        successesWithoutObservedSent=unmatched,
        receipt=receipt(),
        recovery=recoveryState(),
    }
end

-- Client Acceptance Probe: evidence only. No product setters or planner calls.
-- Eight scenarios x twelve snapshots x at most 320 scalar/table nodes per snapshot.
-- Strings <=192 bytes, tables <=64 fields, depth <=10. All losses are explicit.
Audit.scenarioLimits={scenarios=8,snapshots=12,nodes=320,fields=64,depth=10,stringBytes=192}
local definitions={
 campfire={professionKey="COOKING",line=185,recipeID=7751,itemID=279981,useSpellID=1307227,focusID=4},
 ironoven={professionKey="COOKING",line=185,recipeID=18244,itemID=279982,useSpellID=1307226,focusID=2257,placementFocusID=2341},
 fishing6607={professionKey="FISHING",line=356,questID=6607,npcID=12919},
 cooking6610={professionKey="COOKING",line=185,questID=6610,npcID=8125},
 firstaid={professionKey="FIRST_AID",line=129,npcID=12920},
 annora={professionKey="ENCHANTING",line=333,npcID=11073,instanceID=70},
 magnus={professionKey="BLACKSMITHING",line=164,npcID=11278,itemID=13544},
 mining={professionKey="MINING",line=186},
}
local function clean(value)
 local seen,budget={},Audit.scenarioLimits.nodes
 local truncated=false
 local function copy(v,depth)
  budget=budget-1
  if budget<0 then truncated=true;return "TRUNCATED_NODE_LIMIT" end
  local t=type(v)
  if t=="nil"then return "UNKNOWN"end
  if t=="boolean"then return v end
  if t=="number"then if v==v and v~=math.huge and v~=-math.huge then return v end;return "INVALID_NUMBER"end
  if t=="string"then if #v>192 then truncated=true end;return v:sub(1,192)end
  if t~="table"then return "UNSUPPORTED_"..t end
  if depth>=10 or seen[v]then truncated=true;return "TRUNCATED_DEPTH_OR_CYCLE"end
  seen[v]=true;local out,n={},0
  for k,x in pairs(v)do
   if type(k)=="string"or type(k)=="number"then
    n=n+1;if n>64 or budget<1 then truncated=true;break end
    out[type(k)=="string"and k:sub(1,96)or k]=copy(x,depth+1)
   end
  end
  seen[v]=nil;return out
 end
 local out=copy(value,0)
 return out,truncated
end
local function pack(...)return {n=select("#",...),...}end
local function readAPI(path,...)
 local fn=_G
 for name in path:gmatch("[^.]+")do fn=type(fn)=="table"and fn[name]or nil end
 if type(fn)~="function"then return {state="API_UNAVAILABLE"}end
 local values=pack(pcall(fn,...))
 if values[1]~=true then return {state="API_ERROR",error=scalar(values[2])}end
 local result={state="UNKNOWN",values={}}
 for i=2,math.min(values.n,17)do
  local v=values[i];result.values[i-1]=v==nil and "UNKNOWN"or v
  if v~=nil then result.state="OBSERVED"end
 end
 if values.n>17 then result.truncatedReturns=true end
 return result
end
local function first(r)return type(r)=="table"and r.state=="OBSERVED"and r.values and r.values[1]or nil end
local function character()local v=first(readAPI("UnitGUID","player"));return type(v)=="string"and v:match("^Player%-")and v or nil end
local function npc()
 local guid=first(readAPI("UnitGUID","npc"))
 local id=type(guid)=="string"and guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
 return guid,tonumber(id)
end
local function panel()return first(readAPI("C_TradeSkillUI.GetBaseProfessionInfo"))end
local function scenarioDB()
 local s=db();s.clientAcceptanceSchema=1;s.scenarios=type(s.scenarios)=="table"and s.scenarios or {}
 while #s.scenarios>Audit.scenarioLimits.scenarios do table.remove(s.scenarios,1);s.scenariosDropped=(tonumber(s.scenariosDropped)or 0)+1 end
 return s
end
local function activeScenario()
 local s=scenarioDB()
 for _,r in ipairs(s.scenarios)do if type(r)=="table"and r.scenarioID==s.activeScenarioID then return r end end
end
local function requirements(id)
 local raw=readAPI("C_TradeSkillUI.GetRecipeRequirements",id)
 local result={raw=raw,classification="UNKNOWN"}
 if raw.state=="API_UNAVAILABLE"then result.classification="API_UNAVAILABLE";return result end
 local rows=first(raw);if type(rows)~="table"then return result end
 -- Only a runtime-classified SpellFocus requirement identifies a station.
 local focus=type(Enum)=="table"and type(Enum.RecipeRequirementType)=="table"and Enum.RecipeRequirementType.SpellFocus
 if type(focus)~="number"then return result end
 local found=false
 for _,r in pairs(rows)do if type(r)=="table"and r.type==focus then
  found=true
  if r.met==false then result.classification="OBSERVED_UNMET";return result end
  if r.met~=true then return result end
 end end
 if found then result.classification="OBSERVED_MET"end
 return result
end
local function recipe(id)
 return {recipeID=id,info=readAPI("C_TradeSkillUI.GetRecipeInfo",id),
  schematic=readAPI("C_TradeSkillUI.GetRecipeSchematic",id,false),requirements=requirements(id)}
end
local function item(id)
 return {itemID=id,bags=readAPI("C_Item.GetItemCount",id,false,false,false,false),
  spell=readAPI("C_Item.GetItemSpell",id),cooldown=readAPI("C_Item.GetItemCooldown",id),
  usability=readAPI("C_Item.IsUsableItem",id)}
end
local function quest(id)
 return {questID=id,objectives=readAPI("C_QuestLog.GetQuestObjectives",id),
  onQuest=readAPI("C_QuestLog.IsOnQuest",id),ready=readAPI("C_QuestLog.ReadyForTurnIn",id),
  done=readAPI("C_QuestLog.IsQuestFlaggedCompleted",id)}
end
local function geometry()
 local map=readAPI("C_Map.GetBestMapForUnit","player");local id=first(map)
 local out={instance=readAPI("GetInstanceInfo"),mapID=map,projectionQualification="UNKNOWN_REFERENCE_PROJECTION_NOT_PROVEN"}
 if type(id)=="number"then
  out.mapInfo=readAPI("C_Map.GetMapInfo",id);out.art=readAPI("C_Map.GetMapArtID",id)
  out.mapGroup=readAPI("C_Map.GetMapGroupID",id);local group=first(out.mapGroup)
  if type(group)=="number"then out.floors=readAPI("C_Map.GetMapGroupMembersInfo",group)end
  local pos=readAPI("C_Map.GetPlayerMapPosition",id,"player")
  local v=first(pos)
  if type(v)=="table"and type(v.GetXY)=="function"then
   local ok,x,y=pcall(v.GetXY,v);if ok then pos={state="OBSERVED",values={{x=x,y=y,subject="PLAYER_NOT_NPC"}}}end
  end
  out.playerXY=pos
 end
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 -- GetSnapshot revalidates product state; inspect existing fields instead.
 if owner then out.existingOwner={active=owner.active,resumeSource=owner.resumeSource}end
 return out
end
local function validContext(kind,d)
 if not character()then return nil,"PLAYER_GUID_UNAVAILABLE"end
 local build,interface=client();if not build or not interface then return nil,"BUILD_OR_INTERFACE_UNAVAILABLE"end
 local p=panel();local line=type(p)=="table"and p.professionID
 if type(line)=="number"and line~=d.line then return nil,"DIFFERENT_PROFESSION_PANEL"end
 local _,id=npc()
 if kind=="campfire"or kind=="ironoven"then
  if line~=d.line then return nil,"COOKING_PANEL_REQUIRED"end
  local selected=first(readAPI("C_TradeSkillUI.GetSelectedRecipeID"))
  if type(selected)=="number"and selected~=d.recipeID then return nil,"DIFFERENT_SELECTED_CONSUMER_RECIPE"end
  local info=first(readAPI("C_TradeSkillUI.GetRecipeInfo",d.recipeID))
  if type(info)~="table"or info.recipeID and info.recipeID~=d.recipeID then return nil,"CONSUMER_RECIPE_CONTEXT_UNAVAILABLE"end
 elseif d.questID then
  local q=quest(d.questID)
  if first(q.onQuest)~=true and first(q.ready)~=true and first(q.done)~=true then return nil,"QUEST_NOT_OBSERVED"end
 elseif kind=="annora"then
  local inst=readAPI("GetInstanceInfo")
  if not(inst.values and inst.values[8]==70)then return nil,"ULDAMAN_INSTANCE70_REQUIRED"end
 elseif kind=="firstaid"then
  if id~=12920 and line~=129 then return nil,"DOCTOR12920_OR_FIRST_AID_PANEL_REQUIRED"end
 elseif kind=="magnus"then
  local q1,q2,q3=quest(5382),quest(5515),quest(5384)
  if id~=11278 and first(q1.onQuest)~=true and first(q2.onQuest)~=true and first(q3.onQuest)~=true and first(q3.done)~=true then return nil,"MAGNUS_OR_ACCESS_QUEST_CONTEXT_REQUIRED"end
 elseif kind=="mining"and line~=186 then return nil,"MINING_PANEL_REQUIRED_FOR_SMELTING_PROBE"end
 return true
end
local scenarioSerial=0
local pendingCast,seenEvents,liveScenario=nil,{},nil
local bootToken=tostring({}) -- process-local: a reload cannot resume a pending cast.
local function scope(r)
 local build,interface=client()
 if character()~=r.characterKey then return nil,"CHARACTER_CHANGED"end
 if build~=r.build or interface~=r.interface then return nil,"BUILD_OR_INTERFACE_CHANGED"end
 if r~=liveScenario or r.runtimeSession~=bootToken then return nil,"RELOAD_REQUIRES_EXPLICIT_SCENARIO_RESTART"end
 local d=definitions[r.scenarioType]
 local p=panel()
 if type(p)=="table"and type(p.professionID)=="number"and p.professionID~=d.line then return nil,"DIFFERENT_PROFESSION_PANEL"end
 if d.recipeID or r.scenarioType=="mining"then
  local selected=first(readAPI("C_TradeSkillUI.GetSelectedRecipeID"))
  if type(selected)=="number"and selected~=r.recipeID then return nil,"SELECTED_RECIPE_CHANGED"end
 end
 if r.scenarioType=="annora"then
  local inst=readAPI("GetInstanceInfo")
  if inst.state=="OBSERVED"and inst.values[8]~=70 then return nil,"LEFT_ULDAMAN_INSTANCE70"end
 end
 return true
end
local expected={campfire={"consumerRequirements","item","profession","matchedUse","afterConsumerRequirements"},
 ironoven={"consumerRequirements","placementRequirements","item","profession","matchedUse","afterConsumerRequirements"},
 fishing6607={"objectives","readyDone","profession","observedCap"},cooking6610={"objectives","readyDone","profession","observedCap"},
 firstaid={"trainerChannel","gossipChannel","recipes","profession"},annora={"geometry","referenceProjectionProof"},
 magnus={"quests","itemAndEquip","merchant","recipes","geometry","internalAccessProof"},
 mining={"recipe","profession","castReceipt","bagReceipt","skillReceipt","nodeIdentityDifficulty"}}
function Audit:CaptureScenario(reason,eventData)
 if db().enabled~=true then return nil,"AUDIT_OFF"end
 local r=activeScenario();if not r or r.status~="ACTIVE"then return nil,"NO_ACTIVE_SCENARIO"end
 local ok,why=scope(r)
 if not ok then
  r.status="INVALIDATED";r.invalidatingContextChanges[#r.invalidatingContextChanges+1]={at=epoch(),reason=why}
  pendingCast=nil;return nil,why
 end
 local d=definitions[r.scenarioType]
 local build,interface=client()
 local snap={at=epoch(),reason=reason,event=eventData,characterKey=r.characterKey,build=build,interface=interface,
  profession=readAPI("C_TradeSkillUI.GetBaseProfessionInfo"),professionBySkillLine=readAPI("C_TradeSkillUI.GetProfessionInfoBySkillLineID",d.line),nativeDispatchAllowed=false}
 local guid,id=npc();snap.npc={guid=guid or "UNKNOWN",id=id or "UNKNOWN"}
 local got={}
 if d.recipeID then
  snap.consumer=recipe(d.recipeID);snap.item=item(d.itemID)
  snap.consumerRequirementState=snap.consumer.requirements.classification
  got.consumerRequirements=snap.consumerRequirementState=="OBSERVED_MET"or snap.consumerRequirementState=="OBSERVED_UNMET"
  got.item=snap.item.bags.state=="OBSERVED"
  if d.placementFocusID then snap.placement=recipe(d.useSpellID);local state=snap.placement.requirements.classification;got.placementRequirements=state=="OBSERVED_MET"or state=="OBSERVED_UNMET"end
  if reason=="MATCHED_USE_SUCCESS"then
   got.matchedUse=true;got.afterConsumerRequirements=got.consumerRequirements
   snap.requirementComparison={before=r.initialRequirementState or "UNKNOWN",after=snap.consumerRequirementState,useIsNotReadiness=true}
  end
 end
 if d.questID then
  snap.quest=quest(d.questID);got.objectives=snap.quest.objectives.state=="OBSERVED"
  got.readyDone=snap.quest.ready.state=="OBSERVED"and snap.quest.done.state=="OBSERVED"
  local p=first(snap.profession)
  got.observedCap=type(p)=="table"and p.professionID==d.line and type(p.maxSkillLevel)=="number"and p.maxSkillLevel>=300
 end
 if r.scenarioType=="firstaid"then
  snap.recipes={recipe(10841),recipe(18629),recipe(18630)}
  snap.expectedTeachingAliases={ [10841]=10843,[18629]=18631,[18630]=18632 }
  if id==12920 then
   snap.gossip=readAPI("C_GossipInfo.GetOptions");got.gossipChannel=snap.gossip.state=="OBSERVED"
   snap.trainer={};local n=first(readAPI("GetNumTrainerServices"))
   if type(n)=="number"and n>=0 then
    got.trainerChannel=true
    for i=1,math.min(n,32)do snap.trainer[i]={info=readAPI("GetTrainerServiceInfo",i),link=readAPI("GetTrainerServiceItemLink",i),spellID=readAPI("GetTrainerServiceSpellID",i)}end
    snap.trainerTotal=n;snap.trainerTruncated=n>32
   end
  end
  got.recipes=true;for _,v in ipairs(snap.recipes)do if v.info.state~="OBSERVED"then got.recipes=false end end
 end
 if r.scenarioType=="annora"or r.scenarioType=="magnus"then snap.geometry=geometry();got.geometry=snap.geometry.mapID.state=="OBSERVED"and snap.geometry.instance.state=="OBSERVED"end
 if r.scenarioType=="magnus"then
  snap.quests={quest(5382),quest(5515),quest(5384)};got.quests=true;for _,v in ipairs(snap.quests)do if v.onQuest.state~="OBSERVED"or v.done.state~="OBSERVED"then got.quests=false end end
  snap.accessItem=item(13544);snap.equipped=readAPI("IsEquippedItem",13544)
  snap.patterns={item(8030),item(12823)};snap.recipes={recipe(10013),recipe(16971)};got.recipes=true;for _,v in ipairs(snap.recipes)do if v.info.state~="OBSERVED"then got.recipes=false end end
  got.itemAndEquip=snap.accessItem.bags.state=="OBSERVED"and snap.equipped.state=="OBSERVED"
  if id==11278 then
   snap.merchant={};local n=first(readAPI("GetMerchantNumItems"))
   if type(n)=="number"and n>=0 then
    got.merchant=true;snap.merchantTotal=n;snap.merchantTruncated=n>32
    for i=1,math.min(n,32)do snap.merchant[i]={info=readAPI("GetMerchantItemInfo",i),link=readAPI("GetMerchantItemLink",i)}end
   end
  end
  snap.accessQualification="UNKNOWN_REVIEW_REQUIRED"
 end
 if r.scenarioType=="mining"then
  snap.recipe=recipe(r.recipeID);got.recipe=first(snap.recipe.info)~=nil
  snap.target={guid=readAPI("UnitGUID","target"),name=readAPI("UnitName","target"),nodeIdentityDifficulty="UNKNOWN_NO_QUALIFIED_NODE_API"}
  local sc=first(snap.recipe.schematic);snap.bags={}
  if type(sc)=="table"then
   if type(sc.outputItemID)=="number"then snap.bags[#snap.bags+1]=item(sc.outputItemID)end
   for _,slot in ipairs(type(sc.reagentSlotSchematics)=="table"and sc.reagentSlotSchematics or {})do
    for _,reagent in ipairs(type(slot.reagents)=="table"and slot.reagents or {})do
     if #snap.bags<12 and type(reagent.itemID)=="number"then snap.bags[#snap.bags+1]=item(reagent.itemID)end
    end
   end
  end
  got.castReceipt=reason=="MATCHED_CAST_SUCCESS"
  got.bagReceipt=reason=="BAG_UPDATE_DELAYED"and #snap.bags>0 -- snapshot, NOT proof of output causation.
  for _,v in ipairs(snap.bags)do if v.bags.state~="OBSERVED"then got.bagReceipt=false end end
  local observedProfession=first(snap.profession)
  got.skillReceipt=reason=="SKILL_LINES_CHANGED"and type(observedProfession)=="table"and type(observedProfession.skillLevel)=="number" -- no synthetic skill-up.
  if reason=="LOOT_OPENED"then
   snap.loot={};local n=first(readAPI("GetNumLootItems"))
   if type(n)=="number"and n>=0 then
    for i=1,math.min(n,12)do snap.loot[i]={info=readAPI("GetLootSlotInfo",i),link=readAPI("GetLootSlotLink",i)}end
   end
  end
 end
 local p=first(snap.profession);got.profession=type(p)=="table"and p.professionID==d.line
 local stillCurrent,contextReason=scope(r)
 if not stillCurrent then r.status="INVALIDATED";r.invalidatingContextChanges[#r.invalidatingContextChanges+1]={at=epoch(),reason=contextReason};pendingCast=nil;return nil,contextReason end
 local saved,truncated=clean(snap)
 saved.characterKey=r.characterKey;saved.build=build;saved.interface=interface;saved.nativeDispatchAllowed=false;saved.reason=reason
 saved.truncated=truncated;r.observations[#r.observations+1]=saved
 while #r.observations>12 do table.remove(r.observations,1);r.dropped=(r.dropped or 0)+1 end
 r.completedObservationFields=r.completedObservationFields or {}
 -- "completed" means captured evidence, never gameplay/acceptance completion.
 if not truncated then for k,v in pairs(got)do if v then r.completedObservationFields[k]=true end end end
 r.unresolvedFields={}
 for _,name in ipairs(r.expectedObservationFields)do if not r.completedObservationFields[name]then r.unresolvedFields[#r.unresolvedFields+1]=name end end
 if r.initialRequirementState==nil then r.initialRequirementState=snap.consumerRequirementState end
 return clean(saved)
end
function Audit:StartScenario(kind)
 local d=definitions[kind];if not d then return nil,"UNKNOWN_SCENARIO"end
 if db().enabled~=true then return nil,"AUDIT_OFF_RUN_START_FIRST"end
 local ok,why=validContext(kind,d);if not ok then return nil,why end
 local current=activeScenario();if current and current.status=="ACTIVE"then current.status="ENDED_REPLACED"end
 local store=scenarioDB();scenarioSerial=(tonumber(store.scenarioSequence)or 0)+1;store.scenarioSequence=scenarioSerial
 local build,interface=client();local r={scenarioID="CAP-"..tostring(build or "UNKNOWN").."-"..scenarioSerial,
  scenarioType=kind,startedAt=epoch(),build=build,interface=interface,addonVersion=JLP.version,
  characterKey=character(),professionKey=d.professionKey,recipeID=d.recipeID,itemID=d.itemID,
  questID=d.questID,npcID=d.npcID,expectedObservationFields=clean(expected[kind]),
  observations={},unresolvedFields=clean(expected[kind]),invalidatingContextChanges={},
  completedObservationFields={},status="ACTIVE",runtimeSession=bootToken,readOnly=true,nativeDispatchAllowed=false,
  acceptance="NOT_VERIFIED_REQUIRES_HUMAN_REVIEW"}
 if kind=="mining"then
  local selected=first(readAPI("C_TradeSkillUI.GetSelectedRecipeID"))
  if type(selected)~="number"then return nil,"SELECTED_SMELTING_RECIPE_API_UNAVAILABLE"end
  r.recipeID=selected
 end
 store.scenarios[#store.scenarios+1]=r;store.activeScenarioID=r.scenarioID;liveScenario=r;scenarioDB()
 pendingCast=nil;seenEvents={};self:CaptureScenario("BEFORE_MANUAL_ACTION")
 return clean(r)
end
function Audit:EndScenario()
 local r=activeScenario();if r then r.status="ENDED_MANUALLY";r.endedAt=epoch()end
 scenarioDB().activeScenarioID=nil;pendingCast=nil;seenEvents={};liveScenario=nil
 return true
end
function Audit:GetClientAcceptanceSnapshot()
 -- Getter must not initialize or migrate stores, revalidate owners or call Planner.
 local store=type(JuztLevelP0LiveAuditDB)=="table"and JuztLevelP0LiveAuditDB or {}
 local r
 for _,s in ipairs(type(store.scenarios)=="table"and store.scenarios or {})do if type(s)=="table"and s.scenarioID==store.activeScenarioID then r=s end end
 local summary=r and {scenarioID=r.scenarioID,scenarioType=r.scenarioType,status=r.status,characterKey=r.characterKey,
  build=r.build,interface=r.interface,professionKey=r.professionKey,recipeID=r.recipeID,itemID=r.itemID,questID=r.questID,npcID=r.npcID,
  completedObservationFields=r.completedObservationFields,unresolvedFields=r.unresolvedFields,
  capturedObservations=type(r.observations)=="table"and #r.observations or 0,dropped=r.dropped,
  invalidatingContextChanges=r.invalidatingContextChanges,acceptance=r.acceptance}or "NONE"
 if r and r.status=="ACTIVE"and r~=liveScenario then summary.status="INVALIDATED_RESUME_REQUIRES_EXPLICIT_RESTART"end
 return clean({enabled=store.enabled==true,scenario=summary,events=type(store.events)=="table"and #store.events or 0,
  dropped=store.dropped or 0,scenariosDropped=store.scenariosDropped or 0,logicalStore="JuztLevelP0LiveAuditDB",
  exportPath="WTF/Account/<account>/SavedVariables/JuztLevelProfessions.lua",acceptance="NOT_VERIFIED_REQUIRES_HUMAN_REVIEW"})
end
local scenarioEvents={BAG_UPDATE_DELAYED=true,TRADE_SKILL_LIST_UPDATE=true,TRADE_SKILL_UPDATE=true,
 SKILL_LINES_CHANGED=true,TRADE_SKILL_SHOW=true,TRADE_SKILL_CLOSE=true,QUEST_LOG_UPDATE=true,QUEST_TURNED_IN=true,
 TRAINER_SHOW=true,TRAINER_UPDATE=true,GOSSIP_SHOW=true,MERCHANT_SHOW=true,MERCHANT_UPDATE=true,
 PLAYER_EQUIPMENT_CHANGED=true,NEW_RECIPE_LEARNED=true,SPELLS_CHANGED=true,ZONE_CHANGED_NEW_AREA=true,
 PLAYER_ENTERING_WORLD=true,PLAYER_LOGOUT=true,LOOT_OPENED=true}
local extraScenarioEvents={QUEST_LOG_UPDATE=true,QUEST_TURNED_IN=true,TRAINER_SHOW=true,TRAINER_UPDATE=true,GOSSIP_SHOW=true,
 MERCHANT_SHOW=true,MERCHANT_UPDATE=true,PLAYER_EQUIPMENT_CHANGED=true,NEW_RECIPE_LEARNED=true,SPELLS_CHANGED=true,
 ZONE_CHANGED_NEW_AREA=true,LOOT_OPENED=true}
local function observeScenario(event,...)
 local r=activeScenario();if not r or r.status~="ACTIVE"then return end
 local ok,why=scope(r)
 if not ok then r.status="INVALIDATED";r.invalidatingContextChanges[#r.invalidatingContextChanges+1]={at=epoch(),reason=why};pendingCast=nil;return end
 if event=="UNIT_SPELLCAST_SENT"then
  local unit,_,guid,spellID=...
  local d=definitions[r.scenarioType];local expectedSpell=d.useSpellID or r.scenarioType=="mining"and r.recipeID
  if unit=="player"and type(guid)=="string"and #guid<=128 and (spellID==expectedSpell or r.scenarioType=="mining"and spellID==2575)then
   pendingCast={guid=guid,spellID=spellID,characterKey=character(),scenarioID=r.scenarioID,at=elapsed(),actionKind=spellID==2575 and "NODE_GATHERING"or "RECIPE_OR_ITEM_USE"}
  end
 elseif event=="UNIT_SPELLCAST_SUCCEEDED"or event=="UNIT_SPELLCAST_FAILED"or event=="UNIT_SPELLCAST_INTERRUPTED"then
  local unit,guid,spellID=...;local p=pendingCast
  if unit~="player"or not p or p.guid~=guid or p.spellID~=spellID or p.characterKey~=character()or p.scenarioID~=r.scenarioID then return end
  local now=elapsed();if not now or not p.at or now<p.at or now-p.at>30 then pendingCast=nil;return end
  pendingCast=nil;local key=guid..":"..event
  if seenEvents[key]then return end
  seenEvents[key]=true -- bounded with the scenario's event receipts below.
  local n=0;for _ in pairs(seenEvents)do n=n+1 end;if n>24 then seenEvents={[key]=true}end
  Audit:CaptureScenario(event=="UNIT_SPELLCAST_SUCCEEDED"and (definitions[r.scenarioType].useSpellID and "MATCHED_USE_SUCCESS"or "MATCHED_CAST_SUCCESS")or event,{castGUID=guid,spellID=spellID,unit=unit,actionKind=p.actionKind})
 elseif scenarioEvents[event]then
  local kind=r.scenarioType
  if (event=="QUEST_LOG_UPDATE"or event=="QUEST_TURNED_IN")and not r.questID and kind~="magnus"then return end
  if (event=="MERCHANT_SHOW"or event=="MERCHANT_UPDATE"or event=="PLAYER_EQUIPMENT_CHANGED")and kind~="magnus"then return end
  if (event=="TRAINER_SHOW"or event=="TRAINER_UPDATE"or event=="GOSSIP_SHOW")and kind~="firstaid"and kind~="annora"then return end
  if event=="LOOT_OPENED"and kind~="mining"then return end
  if event=="QUEST_TURNED_IN"then local id=...;if definitions[r.scenarioType].questID and id~=r.questID then return end end
  if r.scenarioType=="mining"then
   local selected=first(readAPI("C_TradeSkillUI.GetSelectedRecipeID"))
   if type(selected)=="number"and selected~=r.recipeID then r.status="INVALIDATED";r.invalidatingContextChanges[#r.invalidatingContextChanges+1]={at=epoch(),reason="SELECTED_RECIPE_CHANGED"};pendingCast=nil;return end
  end
  Audit:CaptureScenario(event,{raw=pack(...)})
 end
end

-- Legacy command/event evidence gets explicit context too. NONE/UNKNOWN is
-- honest scope metadata, not an invented profession or scenario association.
evidenceScope=function()
 local who=character();local build,interface=client();local r=activeScenario()
 local matched=r and r==liveScenario and r.status=="ACTIVE"and r.characterKey==who and r.build==build and r.interface==interface
 return {characterKey=who or "UNKNOWN",build=build or "UNKNOWN",interface=interface or "UNKNOWN",
  scenarioID=matched and r.scenarioID or "NONE",professionKey=matched and r.professionKey or "UNKNOWN",
  recipeID=matched and r.recipeID or "UNKNOWN",questID=matched and r.questID or "UNKNOWN"}
end

local function observe(event, ...)
    if db().enabled ~= true then return end
    observeScenario(event,...)
    if extraScenarioEvents[event]then return end
    if event == "UNIT_SPELLCAST_SENT" then
        local unit, _, guid, spellID = ...
        if unit == "player" then append(event, {unit="player", castGUID=guid, spellID=spellID}, true) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED" or
            event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, guid, spellID = ...
        if unit == "player" then append(event, {unit="player", castGUID=guid, spellID=spellID}, true) end
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        local result = ...
        if type(result) == "table" then
            append(event, {
                recipeID=result.recipeID or result.spellID or result.craftingSpellID,
                operationID=result.operationID,
                castGUID=result.castGUID,
                itemGUID=result.itemGUID,
                isEnchant=result.isEnchant,
            }, true)
        else
            append(event, {argumentType=type(result), argument=scalar(result)}, true)
        end
    elseif event == "TRADE_SKILL_CRAFT_BEGIN" then
        local spellID = ...
        append(event, {recipeID=scalar(spellID)}, true)
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        append(event, nil, true)
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == JLP.name then append(event,{addonVersion=JLP.version},false) end
    else
        append(event, nil, false)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    -- Observability must not be able to break core crafting or game events.
    local ok, err = pcall(observe, event, ...)
    if not ok then
        local store = db()
        store.lastError = tostring(err):sub(1,256)
    end
    if event == "PLAYER_LOGIN" and db().enabled == true then
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            pcall(C_Timer.After, 2, function()
                local okSnap, errSnap = pcall(Audit.Snapshot, Audit, "post-login-recovery")
                if not okSnap then db().lastError = tostring(errSnap):sub(1,256) end
            end)
        end
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED",
    "CHAT_MSG_SKILL", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
}) do pcall(frame.RegisterEvent, frame, event) end
for event in pairs(scenarioEvents)do pcall(frame.RegisterEvent,frame,event)end

SLASH_JLPPOAUDIT1 = "/jlpaudit"
local function command(message)
    local verb, rest = tostring(message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    verb = string.lower(verb or "")
    if verb == "scenario"then
        if rest=="end"then Audit:EndScenario();printMessage("Scenario ended; evidence retained.")
        elseif rest=="status"then
            local s=Audit:GetClientAcceptanceSnapshot();local r=type(s.scenario)=="table"and s.scenario
            printMessage(r and (r.scenarioID.." | "..r.status.." | unresolved="..table.concat(r.unresolvedFields or {},", "))or "No active scenario")
        else local r,why=Audit:StartScenario(string.lower(rest));printMessage(r and (r.scenarioID.." started read-only")or why)end
    elseif verb=="exportstatus"then
        local s=Audit:GetClientAcceptanceSnapshot();local r=type(s.scenario)=="table"and s.scenario
        printMessage((r and r.scenarioID.." | "..r.scenarioType.." | "..r.status or "No scenario").." | events="..s.events.." dropped="..s.dropped)
        if r then
            local completed={};for k,v in pairs(r.completedObservationFields or {})do if v then completed[#completed+1]=k end end;table.sort(completed)
            printMessage("Captured fields: "..table.concat(completed,", ").." | unresolved: "..table.concat(r.unresolvedFields or {},", "))
            printMessage("Build/interface: "..tostring(r.build).."/"..tostring(r.interface).." | snapshot drops="..tostring(r.dropped or 0))
        end
        printMessage(s.logicalStore.." → "..s.exportPath.." (flush by normal logout/reload; copy externally). Human review required.")
    elseif verb == "release" then Audit:CaptureReleaseStatus()
    elseif verb == "start" then Audit:Start()
    elseif verb == "stop" then Audit:Stop()
    elseif verb == "clear" then Audit:Clear()
    elseif verb == "mark" then Audit:Mark(rest)
    elseif verb == "snapshot" then Audit:Snapshot(rest);Audit:CaptureScenario("EXPLICIT_SNAPSHOT"); printMessage("Read-only snapshots stored.")
    elseif verb == "capabilities" then Audit:ProbeCapabilities()
    elseif verb == "probe" then
        local itemID,recipeID=rest:match("^(%d+)%s+(%d+)$")
        if not itemID then itemID=rest:match("^(%d+)$") end
        if itemID then Audit:Probe(itemID,recipeID)
        else printMessage("Usage: /jlpaudit probe <itemID> [recipeID] (read-only).") end
    elseif verb == "status" or verb == "check" then
        local sum = Audit:GetSummary()
        local state = sum.recovery and sum.recovery.state or "UNKNOWN"
        printMessage(string.format("%s | events=%d | dropped=%d | recovery=%s | unpaired cast success=%d",
            sum.enabled and "ON" or "OFF", sum.records, sum.dropped, tostring(state), sum.successesWithoutObservedSent))
        if db().lastError then printMessage("Recorder error: " .. tostring(db().lastError)) end
    else
        printMessage("Commands: start | stop | status | snapshot | release | capabilities | probe <itemID> [recipeID] | mark <label> | clear | scenario <name/status/end> | exportstatus. Read-only; no native calls.")
    end
end
SlashCmdList["JLPPOAUDIT"]=function(message)
 local ok,err=pcall(command,message)
 if not ok then db().lastError=tostring(err):sub(1,256)end
end

JLP:RegisterModule("P0LiveAudit", Audit)
