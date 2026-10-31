local _, JLP = ...
-- Passive event correlation ONLY. Never casts, targets, moves, loots or crafts.
local Sensor={contract="jlp-gathering-sensor-v1",nativeDispatchAllowed=false,
    windowSeconds=12,lootSeconds=2,positionTolerance=0.025}
local SPELLS={[1235236]="HERBALISM",[2366]="HERBALISM",[2575]="MINING",[8613]="SKINNING"}
local function secret(v)
    return type(issecretvalue)=="function" and issecretvalue(v)
end
local function stamp() return type(time)=="function" and time() or 0 end
local function safezone()
    if type(IsInInstance)=="function" then
        local ok,inside=pcall(IsInInstance)
        if not ok or inside then return nil end
    end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local ok,zone=pcall(function() return map and map:GetCurrentZone() end)
    if not ok or not zone or not zone.playerPosition or type(zone.mapID)~="number" then return nil end
    return {mapID=zone.mapID,x=zone.playerPosition.x,y=zone.playerPosition.y}
end
local function normalize(s)
    if type(s)~="string" or secret(s) then return nil end
    return s:lower():gsub("[^%w]","")
end
local function candidate(prof,target,mapID)
    local norm=normalize(target)
    if not norm or #norm==0 then return nil,"TARGET_UNKNOWN" end
    local registry=JLP:GetModule("GatheringDataRegistry")
    local summary=registry and registry:GetZoneResourceSummary(mapID,prof)
    local found
    for _,r in ipairs(summary and summary.resources or {}) do
        if normalize(r.resourceKey)==norm then
            if found then return nil,"TARGET_AMBIGUOUS" end
            found=r.resourceKey
        end
    end
    if not found then return nil,"TARGET_UNMAPPED_OR_UNLOCALIZED" end
    return found
end
local function profession(spell)
    if type(spell)~="number" or secret(spell) then return nil end
    if SPELLS[spell] then return SPELLS[spell] end
    -- Rank variants: localized spell *identity*, never translated node display names.
    if type(GetSpellInfo)=="function" then
        local ok,name=pcall(GetSpellInfo,spell)
        if ok and type(name)=="string" then
            for known,kind in pairs(SPELLS) do
                local valid,reference=pcall(GetSpellInfo,known)
                if valid and type(reference)=="string" and reference==name then return kind end
            end
        end
    end
end
function Sensor:Reset() self.pending=nil end
local function fishingObserver()
 if type(UnitGUID)~="function"then return nil end
 local ok,guid=pcall(UnitGUID,"player")
 if ok and not secret(guid)and type(guid)=="string"and guid:match("^Player%-")then return guid end
end
-- Transient receipt context; never restore a loot candidate from SavedVariables.
local function bagCount(itemID)
    local fn=type(C_Item)=="table" and C_Item.GetItemCount or GetItemCount
    if type(fn)~="function" then return nil end
    local ok,n=pcall(fn,itemID,false,false,false)
    if ok and not secret(n) and type(n)=="number" and n==n and n>=0 and n<1e9 and n==math.floor(n) then return n end
end
local function receiptState()
    return JLP:GetModule("GatheringSharedMapState")
end
-- Correlation uses only public finite GetTime samples. Wall-clock stamps below
-- are historical labels, never an alternative elapsed-time authority.
local function timeValue(v)
    local ok,valid=pcall(function()
        return not secret(v) and type(v)=="number" and v==v and v>=0 and v<math.huge
    end)
    return ok and valid==true
end
local function rejectTime(self,reason)
    self.timeStatus=reason
    local state=receiptState();local task=state and state:GetManualTargetTask()
    if task and task.status=="ACTIVE" then state:SetManualReceiptStatus(task.taskID,task.epoch,reason) end
    if self.pending then self.pending.manualIntent=nil end
    if self.fishingPending then self.fishingPending.manualIntent=nil end
    self.pending=nil;self.fishingPending=nil;self.manualReceipt=nil
    return nil
end
local function readTime(self)
    if type(GetTime)~="function" then return rejectTime(self,"TIME_UNAVAILABLE") end
    local ok,value=pcall(GetTime)
    if not ok or not timeValue(value) then return rejectTime(self,"TIME_INVALID") end
    local previous=self.lastQualifiedTime
    if previous~=nil and not timeValue(previous) then return rejectTime(self,"TIME_INVALID") end
    if previous~=nil and value<previous then return rejectTime(self,"TIME_ORDER_INVALID") end
    self.lastQualifiedTime=value;self.timeStatus="VALID_MONOTONIC_TIME"
    return value
end
local function orderedTime(self,at,started)
    if not timeValue(started) then return rejectTime(self,"TIME_INVALID") end
    if at<started then return rejectTime(self,"TIME_ORDER_INVALID") end
    return true
end
local function timeWindow(self,at,started,seconds)
    if not orderedTime(self,at,started) then return end
    if at-started>seconds then return rejectTime(self,"TIME_WINDOW_EXPIRED") end
    return true
end
local function receiptWindow(self,r,at)
    if not timeValue(r.opened) then return rejectTime(self,"TIME_INVALID") end
    -- One qualified sample per check, including a fresh check at admission.
    local function now() return at end
    if now()<r.opened or now()-r.opened>3 then
        return rejectTime(self,at<r.opened and "TIME_ORDER_INVALID" or "TIME_WINDOW_EXPIRED")
    end
    return true
end
function Sensor:BeginManualIntent(p,key)
    local state=receiptState();local task=state and state:GetManualTargetTask()
    if not task or task.status~="ACTIVE" or task.professionKey~=key then return end
    local at=readTime(self)
    if not at or not timeWindow(self,at,p.started,key=="FISHING" and 60 or self.windowSeconds) then return end
    for _,open in pairs(self.manualServiceContexts or {}) do if open then
        state:SetManualReceiptStatus(task.taskID,task.epoch,"UNRESOLVED_SERVICE_CONTEXT");return end end
    if self.manualSlotEventAvailable~=true then
        state:SetManualReceiptStatus(task.taskID,task.epoch,"BLOCKED_CLIENT_EVIDENCE_SLOT_EVENT");return
    end
    for _,event in ipairs({"BAG_UPDATE_DELAYED","LOOT_SLOT_CLEARED","BANKFRAME_OPENED","MERCHANT_SHOW",
        "TRADE_SHOW","MAIL_SHOW","AUCTION_HOUSE_SHOW","QUEST_TURNED_IN","TRADE_SKILL_ITEM_CRAFTED_RESULT"}) do
        if not self.manualReceiptEventAvailable or self.manualReceiptEventAvailable[event]~=true then
            state:SetManualReceiptStatus(task.taskID,task.epoch,"BLOCKED_CLIENT_EVIDENCE_"..event);return
        end
    end
    local owner=fishingObserver()
    if owner~=task.observerCharacter then return end
    local baseline={}
    for itemID in pairs(task.selectedItemIDs) do
        local n=bagCount(itemID)
        if n==nil then state:SetManualReceiptStatus(task.taskID,task.epoch,"UNRESOLVED_INVENTORY");return end
        baseline[itemID]=n
    end
    p.manualIntent={taskID=task.taskID,epoch=task.epoch,observerCharacter=owner,professionKey=key,
        stateOwner=state,baseline=baseline,started=p.started,mapID=p.mapID,x=p.x,y=p.y,castGUID=p.guid}
end
local function currentIntent(intent)
    local state=receiptState()
    local task=state and state:GetManualTargetTask()
    local z=safezone()
    local api=JLP:GetModule("ProfessionAPI")
    local owned=api and api.GetOwnership and api:GetOwnership(intent.professionKey)
    return owned and owned.owned==true and task and task.status=="ACTIVE" and state==intent.stateOwner and task.taskID==intent.taskID and
        task.epoch==intent.epoch and task.observerCharacter==fishingObserver() and
        intent.observerCharacter==task.observerCharacter and z and z.mapID==intent.mapID and
        math.sqrt((z.x-intent.x)^2+(z.y-intent.y)^2)<=Sensor.positionTolerance and task or nil
end
function Sensor:CaptureManualSlot(p,key,row,slot,sourceID)
    local intent=p.manualIntent
    if not intent then return end
    local at=readTime(self)
    if not at or not timeWindow(self,at,p.started,key=="FISHING" and 60 or self.windowSeconds) or
        not timeWindow(self,at,p.completed,key=="FISHING" and 60 or self.lootSeconds) then return end
    local task=currentIntent(intent)
    if not task or task.professionKey~=key or not task.selectedItemIDs[row.itemID] or
        ((key=="MINING" or key=="HERBALISM") and not task.selectedResourceKeys[row.resourceKey]) then return end
    if intent.baseline[row.itemID]==nil or bagCount(row.itemID)~=intent.baseline[row.itemID] then
        intent.stateOwner:SetManualReceiptStatus(intent.taskID,intent.epoch,"UNRESOLVED_PRELOOT_DELTA");return
    end
    local info,_,_,qty=pcall(function()return GetLootSlotInfo(slot)end)
    if not info or secret(qty) or type(qty)~="number" or qty<1 or qty>9999 or qty~=math.floor(qty) then return end
    if key~="FISHING" then
        local sources={pcall(function()return GetLootSourceInfo(slot)end)}
        if #sources~=3 or sources[1]~=true or secret(sources[2]) or secret(sources[3]) or
            sources[2]~=sourceID or sources[3]~=qty then return end
    end
    local r=self.manualReceipt
    if not r then r={intent=intent,opened=at,slots={}};self.manualReceipt=r end
    if not receiptWindow(self,r,at) then return end
    if r.intent~=intent or r.slots[slot] then return end
    r.slots[slot]={itemID=row.itemID,quantity=qty,resourceKey=row.resourceKey,sourceID=sourceID,
        receiptID=intent.castGUID..":"..slot..":"..row.itemID..":"..sourceID}
    intent.stateOwner:SetManualReceiptStatus(intent.taskID,intent.epoch,"PENDING_SLOT_AND_BAG_RECEIPT")
end
local OPEN_CONTEXT={BANKFRAME_OPENED="BANK",MERCHANT_SHOW="MERCHANT",TRADE_SHOW="TRADE",MAIL_SHOW="MAIL",AUCTION_HOUSE_SHOW="AH"}
local CLOSE_CONTEXT={BANKFRAME_CLOSED="BANK",MERCHANT_CLOSED="MERCHANT",TRADE_CLOSED="TRADE",MAIL_CLOSED="MAIL",AUCTION_HOUSE_CLOSED="AH"}
local CONFLICT_EVENT={QUEST_TURNED_IN=true,PLAYERBANKSLOTS_CHANGED=true,PLAYERBANKBAGSLOTS_CHANGED=true,PLAYERREAGENTBANKSLOTS_CHANGED=true,
    PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED=true,MERCHANT_UPDATE=true,TRADE_PLAYER_ITEM_CHANGED=true,
    TRADE_TARGET_ITEM_CHANGED=true,MAIL_INBOX_UPDATE=true,TRADE_SKILL_ITEM_CRAFTED_RESULT=true,TRADE_SKILL_CRAFT_BEGIN=true}
function Sensor:ObserveManualReceipt(event,...)
    local context=OPEN_CONTEXT[event] or CLOSE_CONTEXT[event]
    if context then
        self.manualServiceContexts=self.manualServiceContexts or {}
        self.manualServiceContexts[context]=OPEN_CONTEXT[event]~=nil
    end
    local reset=context or CONFLICT_EVENT[event] or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LOGOUT" or
        event=="ZONE_CHANGED" or event=="ZONE_CHANGED_NEW_AREA" or event=="ZONE_CHANGED_INDOORS"
    if event=="UNIT_SPELLCAST_SENT" then local unit=...;reset=not secret(unit) and unit=="player" or reset end
    if reset then
        local r=self.manualReceipt
        if r then r.intent.stateOwner:SetManualReceiptStatus(r.intent.taskID,r.intent.epoch,"UNRESOLVED_CONTEXT_CHANGED") end
        self.manualReceipt=nil
        if context or CONFLICT_EVENT[event] then
            if self.pending then self.pending.manualIntent=nil end
            if self.fishingPending then self.fishingPending.manualIntent=nil end
        end
        return
    end
    local r=self.manualReceipt
    if not r then return end
    local intent=r.intent
    local at=readTime(self)
    if not at or not receiptWindow(self,r,at) then return end
    if not currentIntent(intent) then
        intent.stateOwner:SetManualReceiptStatus(intent.taskID,intent.epoch,"UNRESOLVED_RECEIPT_EXPIRED")
        self.manualReceipt=nil;return
    end
    if event=="LOOT_OPENED" then
        -- Duplicate notification is harmless only while the same source/slot
        -- snapshot remains open. A different loot window cannot inherit it.
        for slot,row in pairs(r.slots) do
            local ok,link=pcall(function()return GetLootSlotLink(slot)end)
            local itemID=ok and not secret(link) and type(link)=="string" and tonumber(link:match("item:(%d+)"))
            local matches=not row.cleared and itemID==row.itemID
            if matches and intent.professionKey=="FISHING" then
                local valid,fishing=pcall(function()return IsFishingLoot()end)
                matches=valid and not secret(fishing) and fishing==true
            elseif matches then
                local sources={pcall(function()return GetLootSourceInfo(slot)end)}
                matches=#sources==3 and sources[1]==true and not secret(sources[2]) and not secret(sources[3]) and
                    sources[2]==row.sourceID and sources[3]==row.quantity
            end
            if not matches then
                intent.stateOwner:SetManualReceiptStatus(intent.taskID,intent.epoch,"UNRESOLVED_COMPETING_LOOT_WINDOW")
                self.manualReceipt=nil;return
            end
        end
        return
    end
    if event=="LOOT_SLOT_CLEARED" then
        local slot=...
        if not secret(slot) and type(slot)=="number" and slot==math.floor(slot) and r.slots[slot] then r.slots[slot].cleared=true;r.slots[slot].clearedAt=at end
        return
    end
    if event=="LOOT_CLOSED" then
        for _,slot in pairs(r.slots) do if not slot.cleared then
            intent.stateOwner:SetManualReceiptStatus(intent.taskID,intent.epoch,"UNRESOLVED_LOOT_NOT_RECEIVED")
            self.manualReceipt=nil;return end end
        return -- a delayed bag event may still qualify within the original bound
    end
    if event~="BAG_UPDATE_DELAYED" then return end
    local expected={}
    for _,slot in pairs(r.slots) do
        if slot.cleared and not slot.credited then expected[slot.itemID]=(expected[slot.itemID] or 0)+slot.quantity end
    end
    local ready=true
    for itemID,baseline in pairs(intent.baseline) do
        local actual=bagCount(itemID);local amount=expected[itemID] or 0
        if actual==nil or actual<baseline or actual-baseline>amount then
            intent.stateOwner:SetManualReceiptStatus(intent.taskID,intent.epoch,"UNRESOLVED_COMPETING_BAG_DELTA")
            self.manualReceipt=nil;return
        end
        if amount>0 and actual-baseline~=amount then ready=false end
    end
    if not ready then return end
    -- Clear must refer to a slot which is no longer reporting that item. A
    -- mismatched slot API/event timing waits for a later qualified bag event.
    for slot,row in pairs(r.slots) do if row.cleared and not row.credited then
        local ok,link=pcall(function()return GetLootSlotLink(slot)end)
        if not ok or secret(link) or (type(link)=="string" and link:match("item:(%d+)")) then return end
    end end
    for slot,row in pairs(r.slots) do if row.cleared and not row.credited then
        local received=readTime(self)
        if not received or not receiptWindow(self,r,received) or
            not orderedTime(self,received,row.clearedAt) then return end
        local accepted=intent.stateOwner:AdmitManualReceipt({contract="qualified-gathering-receipt-v1",
            taskID=intent.taskID,epoch=intent.epoch,observerCharacter=intent.observerCharacter,professionKey=intent.professionKey,
            itemID=row.itemID,resourceKey=row.resourceKey,quantity=row.quantity,receiptID=row.receiptID,
            slotCleared=true,exactBagDelta=true,unambiguous=true})
        if accepted then
            row.credited=true;intent.baseline[row.itemID]=intent.baseline[row.itemID]+row.quantity
        end
    end end
    for _,row in pairs(r.slots) do if not row.credited then return end end
    self.manualReceipt=nil
end

-- Fishing has its own loot context; no Creature/GameObject node inference.
function Sensor:ObserveFishing(event,...)
 if event=="PLAYER_ENTERING_WORLD"or event=="PLAYER_LOGOUT"or event=="ZONE_CHANGED"or event=="ZONE_CHANGED_NEW_AREA"or event=="ZONE_CHANGED_INDOORS"then self.fishingPending=nil;return end
 local p=self.fishingPending
 if event=="UNIT_SPELLCAST_SENT"then
  local unit,target,guid,spell=...
  if secret(unit)or unit~="player"or secret(guid)or secret(spell)then return end
  self.fishingPending=nil
  local spells={[7620]=true,[7731]=true,[7732]=true,[18248]=true,[1240948]=true,[1240959]=true,[1240970]=true,[1240983]=true}
  if not spells[spell]or type(guid)~="string"or guid==""then return end
  local z=safezone();local observer=fishingObserver();if not z or not observer then return end
  local at=readTime(self);if not at then return end
  self.fishingPending={observerGUID=observer,guid=guid,spellID=spell,started=at,mapID=z.mapID,x=z.x,y=z.y,status="SENT"};self:BeginManualIntent(self.fishingPending,"FISHING");return
 end
 if not p then return end
 local at=readTime(self);if not at or not timeWindow(self,at,p.started,60) then return end
 if event=="UNIT_SPELLCAST_SUCCEEDED"or event=="UNIT_SPELLCAST_FAILED"or event=="UNIT_SPELLCAST_INTERRUPTED"then
  local unit,guid,spell=...
  if unit~="player"or secret(guid)or secret(spell)or guid~=p.guid or spell~=p.spellID then return end
  if event=="UNIT_SPELLCAST_SUCCEEDED"then p.status="SUCCEEDED";p.completed=at else self.fishingPending=nil end
  return
 end
 if event~="LOOT_OPENED"then return end
 -- IsFishingLoot must exist and return the exact public boolean true. Missing
 -- API or unrelated trade/kill loot cannot create personal Fishing history.
 local ok,fishing=pcall(function()return IsFishingLoot()end)
 local z=safezone()
 if p.status~="SUCCEEDED"or not ok or secret(fishing)or fishing~=true or not z or z.mapID~=p.mapID or
  math.sqrt((z.x-p.x)^2+(z.y-p.y)^2)>self.positionTolerance then self.fishingPending=nil;return end
 local observer=fishingObserver()
 if not observer or observer~=p.observerGUID then self.fishingPending=nil;return end
 local store=JLP:GetModule("GatheringObservationStore");local b=store and store:GetBucket()
 local shared=JLP:GetModule("GatheringSharedMapState");local state=shared and shared:GetCharacterState()
 if not b or not state or state.observerCharacter~=p.observerGUID or state.observations~=b then self.fishingPending=nil;return end
 local good,n=pcall(function()return GetNumLootItems()end)
 local observed={}
 if good and not secret(n)and type(n)=="number"and n>=0 and n<=100 and n==math.floor(n)then
  for slot=1,n do
   local valid,link=pcall(function()return GetLootSlotLink(slot)end)
   local info,_,_,qty=pcall(function()return GetLootSlotInfo(slot)end)
   local id=valid and not secret(link)and type(link)=="string"and tonumber(link:match('item:(%d+)'))
   if id and id>0 and info and not secret(qty)and type(qty)=="number"and qty>0 and qty<10000 and qty==math.floor(qty)then
    observed[#observed+1]={identity=p.guid..":"..slot..":"..id,observerCharacter=p.observerGUID,
     castGUID=p.guid,itemID=id,quantity=qty,mapID=p.mapID,x=p.x,y=p.y,
     geometryType="PLAYER_OBSERVED_APPROXIMATE_AREA",poolID=nil,observedAt=stamp(),
     evidence="FISHING_LOOT_CONTEXT_CAST_NOT_BAG_OR_SKILL_RECEIPT",nativeDispatchAllowed=false}
   end
  end
 end
 -- Commit only a coherent snapshot to the exact intent observer's existing
 -- bucket. A character change during any loot API read discards the capture.
 local current=shared and shared:GetCharacterState()
 if fishingObserver()==p.observerGUID and current==state and current.observerCharacter==p.observerGUID and current.observations==b then
  b.fishingLoot=type(b.fishingLoot)=="table"and b.fishingLoot or {}
  for _,row in ipairs(observed)do
   local duplicate=false;for _,r in ipairs(b.fishingLoot)do if r.identity==row.identity then duplicate=true end end
   if not duplicate then
    b.fishingLoot[#b.fishingLoot+1]=row
    self:CaptureManualSlot(p,"FISHING",row,tonumber(row.identity:match(":(%d+):%d+$")),"FISHING:"..p.guid)
    if #b.fishingLoot>240 then table.remove(b.fishingLoot,1)end;b.revision=(b.revision or 0)+1
   end
  end
 end
 self.fishingPending=nil
end

function Sensor:Observe(event,...)
    self:ObserveManualReceipt(event,...)
    self:ObserveFishing(event,...)
    if event=="LOOT_OPENED"then
        local bridge=JLP:GetModule("GatheringMaterialBridge")
        if bridge and bridge.ObserveClothLoot then bridge:ObserveClothLoot()end
    end
    if event=="PLAYER_ENTERING_WORLD" or event=="ZONE_CHANGED" or event=="ZONE_CHANGED_NEW_AREA" or
       event=="ZONE_CHANGED_INDOORS" or event=="PLAYER_LOGOUT" then self:Reset();return end
    if event=="UNIT_SPELLCAST_SENT" then
        local unit,target,guid,spell=...
        -- Party/pet/other-unit casts are not a new player gathering intent.
        -- Clearing before unit validation would discard an active player cast
        -- and its subsequent loot evidence whenever someone else casts.
        if secret(unit) or secret(guid) or secret(target) or secret(spell) or unit~="player" then return end
        self:Reset()
        local prof=profession(spell)
        if not prof or type(guid)~="string" or guid=="" then return end
        local zone=safezone()
        if not zone then return end
        local resource,why=candidate(prof,target,zone.mapID)
        local targetGUID,mobLevel
        if prof=="SKINNING" then
            if type(UnitGUID)=="function" then
                local ok,value=pcall(UnitGUID,"target")
                if ok and not secret(value) and type(value)=="string" and value:match("^Creature%-") then targetGUID=value end
            end
            if type(UnitLevel)=="function" then
                local ok,value=pcall(UnitLevel,"target")
                if ok and not secret(value) and type(value)=="number" and value>0 then mobLevel=value end
            end
        end
        local at=readTime(self);if not at then return end
        self.pending={guid=guid,spellID=spell,professionKey=prof,resourceKey=resource,
            targetGUID=targetGUID,mobLevel=mobLevel,
            issue=why,mapID=zone.mapID,x=zone.x,y=zone.y,started=at,status="SENT"}
        self:BeginManualIntent(self.pending,prof)
        return
    end
    local p=self.pending
    if not p then return end
    local at=readTime(self);if not at or not timeWindow(self,at,p.started,self.windowSeconds) then return end
    if event=="UNIT_SPELLCAST_SUCCEEDED" or event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
        local unit,guid,spell=...
        if secret(unit) or secret(guid) or secret(spell) or unit~="player" or p.guid~=guid or p.spellID~=spell then return end
        if event=="UNIT_SPELLCAST_SUCCEEDED" then
            p.status="SUCCEEDED";p.completed=at
        else
            local store=JLP:GetModule("GatheringObservationStore")
            if store then store:RecordUnresolved({professionKey=p.professionKey,resourceKey=p.resourceKey,
                mapID=p.mapID,x=p.x,y=p.y,reason=event}) end
            self:Reset()
        end
        return
    end
    if event~="LOOT_OPENED" then return end
    if p.status~="SUCCEEDED" then self:Reset();return end
    if not timeWindow(self,at,p.completed,self.lootSeconds) then return end
    local zone=safezone()
    local good=zone and zone.mapID==p.mapID and math.sqrt((zone.x-p.x)^2+(zone.y-p.y)^2)<=self.positionTolerance
    local store=JLP:GetModule("GatheringObservationStore")
    if store then
        if good and p.professionKey=="SKINNING" then
            -- Ordinary kill loot is not skinning loot. Require the successful
            -- Skinning cast AND the exact captured creature as this slot's source.
            local ok,count=pcall(function()return GetNumLootItems()end)
            local recorded=false
            if ok and not secret(count) and type(count)=="number" and count>=0 and count<=100 then
                for slot=1,count do
                    local valid,sources={pcall(function()return GetLootSourceInfo(slot)end)},{}
                    if valid[1] and p.targetGUID then
                        for i=2,#valid,2 do if not secret(valid[i]) and type(valid[i])=="string" then sources[valid[i]]=true end end
                    end
                    local linkOK,link=pcall(function()return GetLootSlotLink(slot)end)
                    local infoOK,_,_,quantity=pcall(function()return GetLootSlotInfo(slot)end)
                    local itemID=linkOK and not secret(link) and type(link)=="string" and tonumber(link:match("item:(%d+)"))
                    if sources[p.targetGUID] and infoOK and not secret(quantity) and type(quantity)=="number" and quantity>0 and itemID then
                        local accepted=store:RecordSkinningLoot({castGUID=p.guid,targetGUID=p.targetGUID,mobLevel=p.mobLevel,
                            itemID=itemID,quantity=quantity,mapID=p.mapID,x=p.x,y=p.y,observedAt=stamp(),
                            castSucceeded=true,lootSourceMatched=true})
                        if accepted then self:CaptureManualSlot(p,"SKINNING",{itemID=itemID},slot,p.targetGUID) end
                        recorded=accepted or recorded
                    end
                end
            end
            if not recorded then store:RecordUnresolved({professionKey="SKINNING",mapID=p.mapID,x=p.x,y=p.y,reason="EXACT_SKINNING_LOOT_SOURCE_UNAVAILABLE"}) end
        elseif good and (p.professionKey=="MINING"or p.professionKey=="HERBALISM") then
            local guide=JLP:GetModule(p.professionKey=="MINING"and "ForeverMiningNodeProgression210"or "ForeverHerbalismProgression209")
            local ok,count=pcall(function()return GetNumLootItems()end)
            local grouped={};local recorded=false
            if ok and not secret(count)and type(count)=="number"and count>=0 and count<=100 then
                for slot=1,count do
                    local sources={pcall(function()return GetLootSourceInfo(slot)end)}
                    local linkOK,link=pcall(function()return GetLootSlotLink(slot)end)
                    local itemID=linkOK and not secret(link)and type(link)=="string"and tonumber(link:match("item:(%d+)"))
                    if sources[1]and itemID then
                        for i=2,#sources,2 do
                            local guid,quantity=sources[i],sources[i+1]
                            local objectID=not secret(guid)and type(guid)=="string"and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
                            local node=objectID and guide and guide:GetObjectContract(objectID)
                            if node and (not p.resourceKey or p.resourceKey==node.resourceKey)and not secret(quantity)and type(quantity)=="number"and quantity>0 and quantity==math.floor(quantity)then
                                local key=guid..":"..itemID;local r=grouped[key]
                                if not r then r={castGUID=p.guid,objectGUID=guid,resourceKey=node.resourceKey,itemID=itemID,quantity=0,
                                    mapID=p.mapID,x=p.x,y=p.y,observedAt=stamp(),castSucceeded=true,lootSourceMatched=true,slots={}};grouped[key]=r end
                                r.quantity=r.quantity+quantity;r.slots[#r.slots+1]=slot
                            end
                        end
                    end
                end
            end
            for _,r in pairs(grouped)do
                local accepted=store:RecordNodeLoot(p.professionKey,r);recorded=accepted or recorded
                if accepted then for _,slot in ipairs(r.slots) do self:CaptureManualSlot(p,p.professionKey,r,slot,r.objectGUID) end end
            end
            if not recorded then store:RecordUnresolved({professionKey=p.professionKey,resourceKey=p.resourceKey,mapID=p.mapID,x=p.x,y=p.y,reason="EXACT_"..p.professionKey.."_OBJECT_LOOT_SOURCE_UNAVAILABLE"})end
            -- Preserve the older cast/location observation as a weaker class,
            -- never as item-output attribution or inventory credit.
            if p.resourceKey and (p.professionKey=="MINING"or recorded)then store:Record({professionKey=p.professionKey,resourceKey=p.resourceKey,mapID=p.mapID,x=p.x,y=p.y,observedAt=stamp(),
                evidenceKind="CAST_SUCCESS_AND_LOOT_OPENED",castSucceeded=true,lootOpened=true})end
        elseif good and p.resourceKey then
            store:Record({professionKey=p.professionKey,resourceKey=p.resourceKey,
                mapID=p.mapID,x=p.x,y=p.y,observedAt=stamp(),
                evidenceKind="CAST_SUCCESS_AND_LOOT_OPENED",castSucceeded=true,lootOpened=true})
        else
            store:RecordUnresolved({professionKey=p.professionKey,resourceKey=p.resourceKey,
                mapID=p.mapID,x=p.x,y=p.y,reason=not good and "POSITION_OR_ZONE_CHANGED" or (p.issue or "RESOURCE_UNRESOLVED")})
        end
    end
    self:Reset()
end
JLP:RegisterModule("GatheringObservationSensor",Sensor)
