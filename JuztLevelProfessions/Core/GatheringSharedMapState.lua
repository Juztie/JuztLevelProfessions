local _, JLP = ...
-- One persistent content-state owner for later embedded/standalone map views.
-- Viewport geometry belongs to each view and is NOT shared content state.
local State={contract="gathering-shared-map-state-v3",nativeDispatchAllowed=false,schema=1}
local retireRoute -- shared cancellation owner; declared before material selection callbacks
local function validMap(id) return type(id)=="number" and id==math.floor(id) and id>0 end
local function newState(guid)
    return {schema=1,observerCharacter=guid,selectedMapID=nil,mode="CUSTOM_LOOP",focus="BALANCED",
            selectedProfessionKeys={},selectedResourceKeys={},sourceFilter="ALL",
            showHeatmap=false,showPins=true,routesByProfession={},
            layerEnabled={},resourceFilters={},resourceSelectionsByMap={},smartMaterialTargets={},routeShape="LOOP",standalone={visible=false,x=0,y=0,width=760,height=550,backgroundOpacity=0.85,chromeOpacity=1}}
end
local function currentIdentity()
    if type(UnitGUID)~="function" then return nil end
    local ok,guid=pcall(UnitGUID,"player")
    if not ok or (type(issecretvalue)=="function" and issecretvalue(guid)) or type(guid)~="string" or guid=="" then return nil end
    return "guid:"..guid,guid
end
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=copy(v) end
    return out
end
-- SavedVariables are account-wide. Keep exactly one active state under the
-- stable GUID; never persist an alias in db.character to the same table.
-- Legacy settings have no owner proof and remain available in the archive.
local function migrateLegacy(db,root)
    local legacy=type(db.character)=="table" and db.character.gathering
    if type(legacy)~="table" then return true end
    if type(legacy.schema)=="number" and legacy.schema>1 then return nil,"FUTURE_GATHERING_SCHEMA" end
    if root.legacyState==nil then root.legacyState=legacy
    else
        root.legacyStates=type(root.legacyStates)=="table" and root.legacyStates or {}
        root.legacyStates[#root.legacyStates+1]=legacy
    end
    local observations=legacy.observations
    if type(observations)=="table" and observations.schema==1 then
        for _,kind in ipairs({"verified","unresolved"}) do
            for _,row in ipairs(type(observations[kind])=="table" and observations[kind] or {}) do
                -- Older unresolved rows lack observer identity. Preserve them
                -- in the archive without claiming the current player saw them.
                local guid=type(row)=="table" and row.observerCharacter
                if type(guid)=="string" and guid:match("^Player%-.+") then
                    local key="guid:"..guid
                    local target=root.characters[key]
                    if target==nil then target=newState(guid);root.characters[key]=target end
                    if type(target)=="table" and target.schema==1 and
                        (target.observerCharacter==nil or target.observerCharacter==guid) then
                        if target.observations==nil then
                            target.observations={schema=1,revision=0,verified={},unresolved={}}
                        end
                        local bucket=target.observations
                        if type(bucket)=="table" and bucket.schema==1 then
                            bucket[kind]=type(bucket[kind])=="table" and bucket[kind] or {}
                            local duplicate=false
                            for _,existing in ipairs(bucket[kind]) do
                                if row.id and existing.id==row.id then duplicate=true;break end
                            end
                            if not duplicate then
                                bucket[kind][#bucket[kind]+1]=copy(row)
                                bucket.revision=(tonumber(bucket.revision) or 0)+1
                            end
                        end
                    end
                end
            end
        end
    end
    db.character.gathering=nil
    return true
end
local function store()
    local db=JLP.DB
    if type(db)~="table" then return nil,"DB_NOT_READY" end
    local key,guid=currentIdentity()
    if not key then return nil,"CHARACTER_GUID_UNAVAILABLE" end
    db.account=type(db.account)=="table" and db.account or {}
    local root=db.account.gathering
    if root~=nil and (type(root)~="table" or root.schema~=1) then return nil,"GATHERING_STORE_SCHEMA_UNSUPPORTED" end
    if not root then root={schema=1,characters={}};db.account.gathering=root end
    root.characters=type(root.characters)=="table" and root.characters or {}
    local ok,reason=migrateLegacy(db,root)
    if not ok then return nil,reason end
    local state=root.characters[key]
    if state==nil then state=newState(guid);root.characters[key]=state end
    if type(state)~="table" or state.schema~=1 then return nil,"FUTURE_GATHERING_SCHEMA" end
    if state.observerCharacter~=nil and state.observerCharacter~=guid then return nil,"GATHERING_CHARACTER_MISMATCH" end
    state.observerCharacter=guid
    return state
end
function State:GetCharacterState() return store() end
function State:GetCharacterKey() return currentIdentity() end
-- Requalify one existing order, never call a profession planner from a getter.
-- The memo is transient: original owner/recipe/item/required remain the intent.
local supplyRevision=0
local qualifiedGoal,qualifiedKey,requalifying
function State:ObserveSupplyInventory()
    supplyRevision=supplyRevision+1
    return self:RequalifyAutomaticSupplyGoal()
end
function State:RequalifyAutomaticSupplyGoal()
    local s=store()
    local goal=s and s.automaticSupplyGoal
    if not goal or requalifying then return goal end
    local api=JLP:GetModule("ProfessionAPI")
    local owner=api and api.Get and api:Get(goal.ownerProfession)
    local ownerKnown=owner and owner.cached~=true and type(owner.skill)=="number"
    if ownerKnown and owner.skill>=300 then
        self:ClearAutomaticSupplyGoal(goal.ownerProfession,"OWNER_GOAL_OBSERVED_COMPLETE")
        return nil
    end
    if type(goal.required)~="number" or goal.required<0 or goal.required~=goal.required or goal.required==math.huge then return goal end
    local inventory=JLP:GetModule("Inventory")
    local stock=inventory and inventory.GetOwned and inventory:GetOwned(goal.itemID) or {}
    local key=table.concat({supplyRevision,tostring(ownerKnown),tostring(owner and owner.skill),
        tostring(stock.bagKnown),tostring(stock.bags),tostring(stock.bankKnown),tostring(stock.bank)},":")
    if qualifiedGoal==goal and qualifiedKey==key then return goal end
    local bridge=JLP:GetModule("GatheringMaterialBridge")
    if not bridge or not bridge.RefreshSupply then return goal end
    requalifying=true
    local ok,fresh
    if not ownerKnown then
        ok=true;fresh={status="VERIFY_OWNER",scope="OWNER_PROFESSION_NOT_CURRENTLY_OBSERVED"}
    else ok,fresh=pcall(bridge.RefreshSupply,bridge,goal) end
    requalifying=false
    -- Do not apply a receipt to an order replaced during requalification.
    if s.automaticSupplyGoal~=goal then return s.automaticSupplyGoal end
    if not ok or type(fresh)~="table" then fresh={status="VERIFY_SUPPLY",scope="SUPPLY_REQUALIFICATION_UNAVAILABLE"} end
    local oldSource=goal.sourceID
    for _,field in ipairs({"quantity","status","scope","mapID","sourceID","gatherItemID","gatherQuantity","actionItemID","actionQuantity","nextAction"}) do
        goal[field]=fresh[field]
    end
    -- Skinning's bank quantity is the withdrawal action, not the whole order.
    if fresh.status=="BANK" and stock.bagKnown==true and stock.bankKnown==true then
        goal.quantity=math.max(0,goal.required-stock.bags)
        goal.actionQuantity=fresh.actionQuantity or fresh.quantity
    end
    goal.resourceKey=fresh.source and fresh.source.resourceKey
    goal.sourceName=fresh.source and fresh.source.name
    goal.sourceKind=fresh.source and fresh.source.kind
    if fresh.status=="BAGS_READY" then
        goal.quantity=0
        goal.nextAction="Required material is observed in bags; resume "..goal.ownerProfession.." and requalify the next manual action."
    elseif fresh.status=="VERIFY_OWNER" then
        goal.nextAction="Observe the material order's consumer profession; preserve intent without a current shortage claim."
    end
    qualifiedGoal=goal;qualifiedKey=key
    if oldSource~=goal.sourceID or goal.status=="BAGS_READY" or goal.quantity==nil then
        local destination=JLP:GetModule("IntegratedDestinationOwner")
        if destination and destination.InvalidateSupplySource then destination:InvalidateSupplySource(oldSource,"SUPPLY_OBSERVATION_CHANGED",goal.ownerToken) end
    end
    return goal
end
-- Manual collection is a forward-only task, never an inventory shortage.
local MANUAL_PROFESSIONS={MINING=true,HERBALISM=true,SKINNING=true,FISHING=true}
local function integer(v,maximum)
    return type(v)=="number" and v==v and v>=0 and v<=maximum and v==math.floor(v)
end
-- The recent receipts ring is diagnostic only. Replay authority is an exact,
-- append-only set scoped to this task; no hashing/collision or aging inference.
-- Both entry count and identity bytes are bounded independently of the goal.
local REPLAY_IDENTITIES,REPLAY_BYTES=1024,131072
local function replayLedger(t)
    local ledger=t.receiptLedger
    if ledger==nil then return nil,"BLOCKED_RECEIPT_HISTORY_UNQUALIFIED" end
    if type(ledger)~="table" or ledger.contract~="manual-receipt-replay-v1" or type(ledger.ids)~="table" or
        not integer(ledger.count,REPLAY_IDENTITIES) or not integer(ledger.bytes,REPLAY_BYTES) or
        type(ledger.sealed)~="boolean" then return nil,"BLOCKED_RECEIPT_LEDGER_INVALID" end
    local count,bytes=0,0
    for id,accepted in pairs(ledger.ids) do
        if type(id)~="string" or #id<1 or #id>512 or accepted~=true then return nil,"BLOCKED_RECEIPT_LEDGER_INVALID" end
        count=count+1;bytes=bytes+#id
        if count>REPLAY_IDENTITIES or bytes>REPLAY_BYTES then return nil,"BLOCKED_RECEIPT_LEDGER_INVALID" end
    end
    if count~=ledger.count or bytes~=ledger.bytes or count>t.collected or
        (count==0 and t.collected~=0) or #t.receipts~=math.min(count,256) then return nil,"BLOCKED_RECEIPT_LEDGER_INVALID" end
    for _,id in ipairs(t.receipts) do if ledger.ids[id]~=true then return nil,"BLOCKED_RECEIPT_LEDGER_INVALID" end end
    if ledger.sealed or count==REPLAY_IDENTITIES or bytes==REPLAY_BYTES then
        return ledger,"BLOCKED_RECEIPT_LEDGER_CAPACITY"
    end
    return ledger
end
local function manualTask(s)
    local t=s and s.manualTargetTask
    if type(t)~="table" or t.schema~=1 or t.observerCharacter~=s.observerCharacter or
        not MANUAL_PROFESSIONS[t.professionKey] or type(t.taskID)~="string" or
        #t.taskID>256 or not integer(t.sequence,1000000000) or t.sequence<1 or
        not integer(t.total,1000000) or t.total<1 or not integer(t.collected,1009999) or
        t.remaining~=math.max(0,t.total-t.collected) or not integer(t.epoch,1000000000) or
        type(t.selectedItemIDs)~="table" or type(t.selectedResourceKeys)~="table" or
        type(t.receipts)~="table" or #t.receipts>256 or
        not ({ACTIVE=true,PAUSED=true,COMPLETED=true,STOPPED=true})[t.status] then return nil end
    local itemCount,resourceCount=0,0
    for itemID,selected in pairs(t.selectedItemIDs) do
        itemCount=itemCount+1
        if itemCount>64 or selected~=true or not integer(itemID,2147483647) or itemID<1 then return nil end
    end
    for key,selected in pairs(t.selectedResourceKeys) do
        resourceCount=resourceCount+1
        if resourceCount>64 or selected~=true or type(key)~="string" or #key>80 or not key:match("^[A-Z0-9_]+$") then return nil end
    end
    if itemCount==0 then return nil end
    for _,id in ipairs(t.receipts) do if type(id)~="string" or #id>512 then return nil end end
    local ledger,blocked=replayLedger(t)
    if blocked and t.status~="COMPLETED" then t.proofStatus=blocked end
    return t,ledger,blocked
end
function State:GetManualTargetTask()
    return copy(manualTask(store()))
end
-- Reuse existing identity catalogues. These rows grant no spawn/yield authority.
function State:GetManualTargetChoices(professionKey,mapID)
    local rows,seen={},{}
    local function add(itemID,name,resourceKey)
        if not integer(itemID,2147483647) or itemID<1 then return end
        local key=tostring(itemID)..":"..tostring(resourceKey or "")
        if not seen[key] then
            seen[key]=true;rows[#rows+1]={itemID=itemID,name=name or ("Item "..itemID),resourceKey=resourceKey}
        end
    end
    local data=JLP.data or {}
    if professionKey=="MINING" or professionKey=="HERBALISM" then
        local catalogue=professionKey=="MINING" and data.foreverMiningNodeProgression210 or data.foreverHerbalismProgression209
        for _,node in ipairs(catalogue and catalogue.nodeContracts or {}) do
            for _,itemID in ipairs(node.itemIDs or {}) do add(itemID,(node.name or node.resourceKey).." · item "..itemID,node.resourceKey) end
        end
    elseif professionKey=="SKINNING" then
        for _,catalogue in ipairs({data.skinningMaterialResearch or {},data.skinningHideScaleResearch or {},data.skinningScaleResearch or {}}) do
            for _,row in ipairs(catalogue.materials or {}) do add(row.itemID,row.name) end
        end
    elseif professionKey=="FISHING" then
        -- Species identities can be chosen across maps; this is NOT a location claim.
        local source=data.fishingCatchAreaReference
        for _,fish in pairs(source and source.maps or {}) do for _,row in ipairs(fish) do add(row.itemID,row.name) end end
        local secondary=data.foreverSecondaryLeveling
        for itemID,row in pairs(secondary and secondary.fishing and secondary.fishing.speciesZoneReferences or {}) do add(itemID,row.name) end
    end
    table.sort(rows,function(a,b) if a.name==b.name then return a.itemID<b.itemID end;return a.name<b.name end)
    return rows
end
function State:StartManualTarget(goal)
    local s,why=store();if not s then return false,why end
    if s.manualTargetTask~=nil and not manualTask(s) then return false,"MANUAL_TASK_SCHEMA_UNSUPPORTED" end
    if type(goal)~="table" or not MANUAL_PROFESSIONS[goal.professionKey] or
        not integer(goal.required,1000000) or goal.required<1 then return false,"MANUAL_TARGET_INVALID" end
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(goal.professionKey)
    if not ownership or ownership.owned~=true then return false,"PROFESSION_OWNERSHIP_NOT_QUALIFIED" end
    if goal.selectedItemIDs~=nil and type(goal.selectedItemIDs)~="table" then return false,"MANUAL_ITEM_SET_INVALID" end
    if goal.selectedResourceKeys~=nil and type(goal.selectedResourceKeys)~="table" then return false,"MANUAL_RESOURCE_SET_INVALID" end
    if goal.source~=nil and type(goal.source)~="table" then return false,"MANUAL_SOURCE_INVALID" end
    if goal.selectedItemIDs==nil and (not integer(goal.itemID,2147483647) or goal.itemID<1) then return false,"MANUAL_ITEM_INVALID" end
    local items,resources={},{}
    for id,enabled in pairs(goal.selectedItemIDs or {[goal.itemID]=true}) do
        if enabled~=true or not integer(id,2147483647) or id<1 then return false,"MANUAL_ITEM_INVALID" end
        items[id]=true
    end
    local input=goal.selectedResourceKeys or (goal.source and goal.source.resourceKey and {[goal.source.resourceKey]=true}) or {}
    local resourceCount=0
    for key,enabled in pairs(input) do
        resourceCount=resourceCount+1;if resourceCount>64 then return false,"MANUAL_RESOURCE_SET_INVALID" end
        if enabled~=true or type(key)~="string" or #key>80 or not key:match("^[A-Z0-9_]+$") then return false,"MANUAL_RESOURCE_INVALID" end
        resources[key]=true
    end
    local qualifiedItems,qualifiedResources={},{}
    for _,row in ipairs(self:GetManualTargetChoices(goal.professionKey,goal.mapID)) do
        if not row.resourceKey or resources[row.resourceKey] then
            qualifiedItems[row.itemID]=true
            if row.resourceKey then qualifiedResources[row.resourceKey]=true end
        end
    end
    local count=0
    for id in pairs(items) do count=count+1;if not qualifiedItems[id] then return false,"MANUAL_ITEM_NOT_QUALIFIED" end end
    if count<1 or count>64 then return false,"MANUAL_ITEM_SET_INVALID" end
    if goal.professionKey=="MINING" or goal.professionKey=="HERBALISM" then
        if not next(resources) then return false,"MANUAL_RESOURCE_SET_REQUIRED" end
        for key in pairs(resources) do if not qualifiedResources[key] then return false,"MANUAL_RESOURCE_NOT_QUALIFIED" end end
    elseif next(resources) then return false,"MANUAL_NODE_FILTER_NOT_APPLICABLE" end
    local prior=manualTask(s);local sequence=(prior and prior.sequence or 0)+1
    if not integer(sequence,1000000000) then return false,"MANUAL_TASK_SEQUENCE_EXHAUSTED" end
    local started=type(time)=="function" and time() or nil
    if not integer(started,9999999999) then return false,"MANUAL_TASK_CLOCK_UNAVAILABLE" end
    local taskID="manual-target-v1:"..s.observerCharacter..":"..started..":"..sequence
    s.manualTargetTask={schema=1,taskID=taskID,sequence=sequence,epoch=1,observerCharacter=s.observerCharacter,
        professionKey=goal.professionKey,startedAt=started,startProvenance="EXPLICIT_MANUAL_TARGET_START",
        total=goal.required,collected=0,remaining=goal.required,status="ACTIVE",selectedItemIDs=items,
        selectedResourceKeys=resources,mapID=goal.mapID,routeIntent={mode="CUSTOM_LOOP",shape=s.routeShape},
        receipts={},receiptLedger={contract="manual-receipt-replay-v1",ids={},count=0,bytes=0,sealed=false},
        proofStatus="AWAITING_QUALIFIED_RECEIPT",nativeDispatchAllowed=false}
    s.manualSupplyGoal={origin="MANUAL_TARGET",status="MANUAL_TARGET",taskID=taskID,professionKey=goal.professionKey,
        itemID=goal.itemID,required=goal.required,quantity=goal.required,mapID=goal.mapID,
        notLiveSpawn=true,nativeDispatchAllowed=false}
    if validMap(goal.mapID) then s.selectedMapID=goal.mapID end
    if retireRoute then retireRoute("MANUAL_TARGET_STARTED") end
    return true,taskID
end
local function changeManualStatus(self,status)
    local s=store();local t=manualTask(s)
    if not t then return false,"MANUAL_TASK_UNAVAILABLE" end
    if status=="ACTIVE" and t.status~="PAUSED" then return false,"MANUAL_TASK_NOT_PAUSED" end
    if status=="PAUSED" and t.status~="ACTIVE" then return false,"MANUAL_TASK_NOT_ACTIVE" end
    if t.epoch>=1000000000 then return false,"MANUAL_TASK_EPOCH_EXHAUSTED" end
    t.epoch=t.epoch+1;t.status=status;t.proofStatus="AWAITING_QUALIFIED_RECEIPT"
    if retireRoute then retireRoute("MANUAL_TARGET_"..status) end
    return true,status
end
function State:PauseManualTarget() return changeManualStatus(self,"PAUSED") end
function State:ResumeManualTarget() return changeManualStatus(self,"ACTIVE") end
function State:StopManualTarget() return changeManualStatus(self,"STOPPED") end
function State:SetManualReceiptStatus(taskID,epoch,status)
    local t,_,blocked=manualTask(store())
    if not t or t.taskID~=taskID or t.epoch~=epoch or t.status~="ACTIVE" or blocked then return false end
    t.proofStatus=status;return true
end
function State:AdmitManualReceipt(receipt)
    local s=store();local t,ledger,blocked=manualTask(s)
    if not t or t.status~="ACTIVE" or type(receipt)~="table" or receipt.contract~="qualified-gathering-receipt-v1" or
        receipt.taskID~=t.taskID or receipt.epoch~=t.epoch or receipt.observerCharacter~=t.observerCharacter or
        receipt.professionKey~=t.professionKey or not t.selectedItemIDs[receipt.itemID] or
        ((t.professionKey=="MINING" or t.professionKey=="HERBALISM") and not t.selectedResourceKeys[receipt.resourceKey]) or
        receipt.slotCleared~=true or receipt.exactBagDelta~=true or receipt.unambiguous~=true or
        not integer(receipt.quantity,9999) or receipt.quantity<1 or type(receipt.receiptID)~="string" or
        #receipt.receiptID<1 or #receipt.receiptID>512 then return false,"MANUAL_RECEIPT_UNQUALIFIED" end
    if not ledger or blocked then return false,blocked or "BLOCKED_RECEIPT_HISTORY_UNQUALIFIED" end
    if ledger.ids[receipt.receiptID] then return false,"MANUAL_RECEIPT_DUPLICATE" end
    if ledger.count>=REPLAY_IDENTITIES or ledger.bytes+#receipt.receiptID>REPLAY_BYTES then
        ledger.sealed=true;t.proofStatus="BLOCKED_RECEIPT_LEDGER_CAPACITY"
        return false,"BLOCKED_RECEIPT_LEDGER_CAPACITY"
    end
    ledger.ids[receipt.receiptID]=true;ledger.count=ledger.count+1;ledger.bytes=ledger.bytes+#receipt.receiptID
    if ledger.count==REPLAY_IDENTITIES or ledger.bytes==REPLAY_BYTES then ledger.sealed=true end
    t.receipts[#t.receipts+1]=receipt.receiptID
    if #t.receipts>256 then table.remove(t.receipts,1) end
    t.collected=t.collected+receipt.quantity;t.remaining=math.max(0,t.total-t.collected)
    t.proofStatus="SOURCE_SLOT_AND_EXACT_BAG_DELTA";t.lastReceiptID=receipt.receiptID
    if t.remaining==0 then t.status="COMPLETED";if retireRoute then retireRoute("MANUAL_TARGET_COMPLETED") end end
    if ledger.sealed and t.status=="ACTIVE" then t.proofStatus="BLOCKED_RECEIPT_LEDGER_CAPACITY" end
    return true,t.remaining
end

function State:GetSnapshot()
    local s,reason=store()
    if not s then return nil,reason or "DB_NOT_READY" end
    -- Previous revisions stored an unowned selection. Preserve it as an
    -- explicitly unowned reference; never present it as a live LW shortage.
    if s.supplyGoal then
        s.legacySupplyGoal=s.legacySupplyGoal or copy(s.supplyGoal)
        s.supplyGoal=nil
    end
    local automatic=self:RequalifyAutomaticSupplyGoal()
    local ownerUnknown=false
    if automatic then
        local api=JLP:GetModule("ProfessionAPI")
        local owner=api and api.Get and api:Get(automatic.ownerProfession)
        ownerUnknown=not owner or owner.cached==true or type(owner.skill)~="number"
        if owner and owner.cached~=true and type(owner.skill)=="number" and owner.skill>=300 then
            self:ClearAutomaticSupplyGoal(automatic.ownerProfession,"OWNER_GOAL_OBSERVED_COMPLETE")
            automatic=nil
        end
    end
    local task=manualTask(s)
    local manual=copy(s.manualSupplyGoal)
    if manual and manual.origin=="MANUAL_TARGET" then
        if task and manual.taskID==task.taskID then
            manual.quantity=task.remaining;manual.required=task.total;manual.taskStatus=task.status
        else manual=nil end
    end
    local effective=copy(manual or automatic or s.legacySupplyGoal)
    if effective and effective.origin=="AUTOMATIC_PLAN" and ownerUnknown then
        effective.status="VERIFY_OWNER";effective.quantity=nil;effective.sourceID=nil;effective.mapID=nil
        effective.scope="OWNER_PROFESSION_NOT_CURRENTLY_OBSERVED"
    end
    if effective and not effective.origin then effective.origin="LEGACY_UNOWNED_REFERENCE" end
    local selected=validMap(s.selectedMapID) and s.selectedMapID or nil
    local selectedResources={}
    for k,perMap in pairs(type(s.resourceSelectionsByMap)=="table" and s.resourceSelectionsByMap or {}) do
        if validMap(tonumber(k)) and type(perMap)=="table" then
            selectedResources[k]={}
            for _,professionKey in ipairs({"HERBALISM","MINING"}) do
                local values=perMap[professionKey]
                if type(values)=="table" then
                    local good={}
                    for key,enabled in pairs(values) do
                        if enabled==true and type(key)=="string" and key:match("^[A-Z0-9_]+$") and #key<=80 then good[key]=true end
                    end
                    selectedResources[k][professionKey]=good
                end
            end
        end
    end
    local targets={HERBALISM={},MINING={}}
    for _,profession in ipairs({"HERBALISM","MINING"}) do
        local values=type(s.smartMaterialTargets)=="table" and s.smartMaterialTargets[profession]
        for key,value in pairs(type(values)=="table" and values or {}) do
            if type(key)=="string" and #key<=80 and key:match("^[A-Z0-9_]+$") and value==true then
                targets[profession][key]=true
            end
        end
    end
    if task and not task.dismissed and (task.professionKey=="MINING" or task.professionKey=="HERBALISM") then
        for _,mapID in ipairs({s.selectedMapID or task.mapID,task.mapID}) do if validMap(mapID) then
            selectedResources[mapID]={MINING={},HERBALISM={}}
            selectedResources[mapID][task.professionKey]=copy(task.selectedResourceKeys)
        end end
    end
    local mode=(s.mode=="SMART_PROFESSION") and s.mode or "CUSTOM_LOOP"
    if task and not task.dismissed then mode="CUSTOM_LOOP" end
    local focus=(s.focus=="MATERIALS" or s.focus=="SKILL") and s.focus or "BALANCED"
    return {schema=1,selectedMapID=selected,supplyGoal=effective,automaticSupplyGoal=copy(automatic),manualSupplyGoal=manual,manualTargetTask=copy(task),zoneBrowseScope=s.zoneBrowseScope=="CONTINENT" and "CONTINENT" or "GUIDE",mode=mode,focus=focus,
        sourceFilter=s.sourceFilter=="OBSERVED_ONLY" and "OBSERVED_ONLY" or "ALL",
        routeSource=s.routeSource=="OBSERVED_ONLY" and "OBSERVED_ONLY" or
            s.routeSource=="PREFER_OBSERVED" and "PREFER_OBSERVED" or "ALL",
        showHeatmap=s.showHeatmap==true,showPins=s.showPins~=false,
        showFishingAreas=s.showFishingAreas~=false,
        userFishingAreaFilter=s.fishingAreaFilter,userFishingSelectedItemID=s.fishingSelectedItemID,
        fishingAreaFilter=effective and effective.origin~="MANUAL_TARGET" and effective.professionKey=="FISHING"and "SINGLE_FISH"or s.fishingAreaFilter=="COOKING_NEEDS" and "COOKING_NEEDS" or
            s.fishingAreaFilter=="SINGLE_FISH" and "SINGLE_FISH" or "ALL",
        fishingSelectedItemID=effective and effective.origin~="MANUAL_TARGET" and effective.professionKey=="FISHING"and effective.itemID or type(s.fishingSelectedItemID)=="number" and s.fishingSelectedItemID or nil,
        -- Route/layer editing intentionally not enabled in this foundation milestone.
        routesByProfession={},selectedProfessionKeys={},selectedResourceKeys={},
        resourceSelectionsByMap=selectedResources,smartMaterialTargets=targets,routeShape=s.routeShape=="FROM_PLAYER" and "FROM_PLAYER" or "LOOP",
        layerEnabled={HERBALISM=task and not task.dismissed and task.professionKey=="HERBALISM" or type(s.layerEnabled)=="table" and s.layerEnabled.HERBALISM==true or false,
            MINING=task and not task.dismissed and task.professionKey=="MINING" or type(s.layerEnabled)=="table" and s.layerEnabled.MINING==true or false},
        resourceFilters={HERBALISM=type(s.resourceFilters)=="table" and s.resourceFilters.HERBALISM or nil,
            MINING=type(s.resourceFilters)=="table" and s.resourceFilters.MINING or nil},
        nativeDispatchAllowed=false}
end
function State:SelectSupplyGoal(goal,owner)
    if type(goal)=="table" and goal.status=="MANUAL_TARGET" and owner==nil then return self:StartManualTarget(goal) end
    if type(goal)~="table" or type(goal.itemID)~="number" then return false end
    if owner~=nil and not (type(owner)=="table"and type(owner.profession)=="string"and type(owner.recipeID)=="number"and
        owner.recipeID>0 and owner.recipeID==math.floor(owner.recipeID))then return false,"INVALID_SUPPLY_OWNER"end
    local s,why=store();if not s then return false,why end
    local task=manualTask(s)
    if owner==nil and task and not task.dismissed and task.status=="ACTIVE" then return false,"MANUAL_TASK_RESTART_REQUIRED" end
    local selected={professionKey=goal.professionKey=="FISHING"and "FISHING"or goal.professionKey=="CLOTH"and "CLOTH"or goal.professionKey=="MINING"and "MINING"or goal.professionKey=="HERBALISM"and "HERBALISM"or "SKINNING",itemID=goal.itemID,quantity=goal.quantity,
        required=goal.required,strategy=goal.strategy,gatherItemID=goal.gatherItemID,gatherQuantity=goal.gatherQuantity,
        actionItemID=goal.actionItemID,actionQuantity=goal.actionQuantity,
        resourceKey=goal.source and goal.source.resourceKey,sourceName=goal.source and goal.source.name,sourceKind=goal.source and goal.source.kind,
        status=goal.status,mapID=goal.mapID,sourceID=goal.sourceID,scope=goal.scope,
        notLiveSpawn=true,nativeDispatchAllowed=false}
    if type(owner)=="table" and type(owner.profession)=="string" and type(owner.recipeID)=="number" then
        selected.origin="AUTOMATIC_PLAN";selected.ownerProfession=owner.profession
        selected.ownerRecipeID=owner.recipeID
        selected.ownerToken=owner.profession..":"..owner.recipeID..":"..goal.itemID
        s.automaticSupplyGoal=selected
    else selected.origin="MANUAL_SELECTION";s.manualSupplyGoal=selected;s.legacySupplyGoal=nil end
    if validMap(goal.mapID) and (selected.origin=="MANUAL_SELECTION" or not s.manualSupplyGoal) then s.selectedMapID=goal.mapID end
    return true
end
function State:ClearSupplyGoal()
    local s=store();if s then
        local t=manualTask(s);if t then t.status="STOPPED";t.epoch=t.epoch+1;t.dismissed=true end
        s.manualSupplyGoal=nil;s.legacySupplyGoal=nil;s.supplyGoal=nil
    end
end
function State:ClearAutomaticSupplyGoal(owner,reason)
    local s=store()
    if s and s.automaticSupplyGoal and s.automaticSupplyGoal.ownerProfession==owner then
        s.lastAutomaticSupplyRetirement={owner=owner,reason=reason}
        s.automaticSupplyGoal=nil
        return true
    end
    return false
end
function State:ObserveSupplyProfessionFocus(key)
    local s=store()
    if s and s.automaticSupplyGoal and key~="dual" and key~="SKINNING" and key~="MINING" and key~="HERBALISM" and key~="FISHING" and
       key~=s.automaticSupplyGoal.ownerProfession then
        return self:ClearAutomaticSupplyGoal(s.automaticSupplyGoal.ownerProfession,"ACTIVE_PROFESSION_CHANGED")
    end
    return false
end
-- Transient, deterministic receipt identity. No saved schema/version changes.
-- A missing selection differs from an explicit empty set; sorted keys make
-- the token deterministic regardless of Lua table iteration order.
function State:GetRouteContextKey(mapID)
    if not validMap(mapID) then return nil,"MAP_ID_INVALID" end
    local snapshot,err=self:GetSnapshot()
    if type(snapshot)~="table" then return nil,err or "STATE_UNAVAILABLE" end
    local pieces={"character="..tostring(currentIdentity()),"map="..mapID,"selected="..tostring(snapshot.selectedMapID or "CURRENT"),
        "mode="..tostring(snapshot.mode),"focus="..tostring(snapshot.focus),
        "shape="..tostring(snapshot.routeShape),"routeSource="..tostring(snapshot.routeSource),
        "sourceFilter="..tostring(snapshot.sourceFilter)}
    local zone=snapshot.resourceSelectionsByMap and snapshot.resourceSelectionsByMap[mapID]
    for _,profession in ipairs({"HERBALISM","MINING"}) do
        local selected=zone and zone[profession]
        local keys={}
        if type(selected)=="table" then
            for key,isSelected in pairs(selected) do
                if isSelected==true then keys[#keys+1]=key end
            end
            table.sort(keys)
        end
        pieces[#pieces+1]=profession..":"..tostring(snapshot.layerEnabled and snapshot.layerEnabled[profession])..
            ":"..tostring(snapshot.resourceFilters and snapshot.resourceFilters[profession])..
            ":"..(type(selected)=="table" and "explicit" or "unset")..":"..table.concat(keys,",")
    end
    for _,profession in ipairs({"HERBALISM","MINING"}) do
        local targets=snapshot.smartMaterialTargets and snapshot.smartMaterialTargets[profession] or {}
        local keys={}
        for key,value in pairs(targets) do if value then keys[#keys+1]=key end end
        table.sort(keys)
        pieces[#pieces+1]="smart:"..profession..":"..table.concat(keys,",")
    end
    local task=snapshot.manualTargetTask
    if task and not task.dismissed then pieces[#pieces+1]=task.taskID..":"..task.epoch..":"..task.status end
    return table.concat(pieces,"|")
end
-- Global material targets are intentionally separate from zone-local Custom
-- selections. The packed registry is the only accepted identity catalogue.
function State:GetSmartMaterialChoices(profession)
    if profession~="HERBALISM" and profession~="MINING" then return {},"PROFESSION_INVALID" end
    local packed=JLP.data and JLP.data.gatheringReferencePacked
    if self._smartMaterialCatalogSource==packed and self._smartMaterialCatalog and
        self._smartMaterialCatalog[profession] then return self._smartMaterialCatalog[profession] end
    local unique={}
    local manifest=JLP.data and JLP.data.gatheringSourceManifest
    for _,rows in pairs(type(packed)=="table" and packed.maps or {}) do
        for _,row in ipairs(rows) do
            local meta=manifest and manifest.sources and manifest.sources[row[1]]
            if meta and meta.redistributionApproved==true and meta.licenseVerified==true and
                meta.buildVerified==true and type(row[6])=="string" and #row[6]%6==0 and
                row[2]==profession and type(row[3])=="string" and row[3]:match("^[A-Z0-9_]+$") then
                local key=row[3]
                local entry=unique[key]
                if not entry then entry={resourceKey=key,requiredSkill=row[5],referenceCount=0};unique[key]=entry end
                if type(row[5])=="number" and (type(entry.requiredSkill)~="number" or row[5]<entry.requiredSkill) then
                    entry.requiredSkill=row[5]
                end
                if type(row[6])=="string" then entry.referenceCount=entry.referenceCount+math.floor(#row[6]/6) end
            end
        end
    end
    local choices={}
    local bridge=JLP:GetModule("GatheringMaterialBridge")
    for _,entry in pairs(unique) do
        if bridge and bridge:HasQualifiedGenericOutput(profession,entry.resourceKey) then
            choices[#choices+1]=entry
        end
    end
    table.sort(choices,function(a,b) return a.resourceKey<b.resourceKey end)
    if self._smartMaterialCatalogSource~=packed then
        self._smartMaterialCatalogSource=packed;self._smartMaterialCatalog={}
    end
    self._smartMaterialCatalog[profession]=choices
    return choices
end
function State:SetSmartMaterialTarget(profession,key,selected)
    if (profession~="HERBALISM" and profession~="MINING") or
        type(key)~="string" or #key>80 or not key:match("^[A-Z0-9_]+$") or
        type(selected)~="boolean" then return false,"TARGET_INVALID" end
    local snapshot=self:GetSnapshot()
    if not snapshot or snapshot.mode~="SMART_PROFESSION" or snapshot.focus~="MATERIALS" then
        return false,"SMART_MATERIALS_REQUIRED" end
    local api=JLP:GetModule("ProfessionAPI")
    local learned=api and api.Get and api:Get(profession)
    if type(learned)~="table" or learned.cached==true or type(learned.skill)~="number" then
        return false,"PROFESSION_NOT_LEARNED" end
    local found=false
    for _,entry in ipairs(self:GetSmartMaterialChoices(profession)) do
        if entry.resourceKey==key then found=true;break end
    end
    if not found then return false,"UNQUALIFIED_TARGET" end
    local s=store();if not s then return false,"DB_NOT_READY" end
    s.smartMaterialTargets=type(s.smartMaterialTargets)=="table" and s.smartMaterialTargets or {}
    local selection=type(s.smartMaterialTargets[profession])=="table" and s.smartMaterialTargets[profession] or {}
    s.smartMaterialTargets[profession]=selection
    if (selection[key]==true)==selected then return true end
    selection[key]=selected and true or nil
    local assessor=JLP:GetModule("GatheringZoneSuitability")
    if assessor then assessor:CancelRecommendation("MATERIAL_TARGETS_CHANGED") end
    retireRoute("SMART_MATERIALS_CHANGED")
    return true
end
function State:SetAllSmartMaterials(profession,selected)
    if type(selected)~="boolean" then return false,"VALUE_INVALID" end
    local snapshot=self:GetSnapshot()
    if not snapshot or snapshot.mode~="SMART_PROFESSION" or snapshot.focus~="MATERIALS" then
        return false,"SMART_MATERIALS_REQUIRED" end
    local api=JLP:GetModule("ProfessionAPI")
    local learned=api and api.Get and api:Get(profession)
    if type(learned)~="table" or learned.cached==true or type(learned.skill)~="number" then
        return false,"PROFESSION_NOT_LEARNED" end
    local s=store();if not s then return false,"DB_NOT_READY" end
    s.smartMaterialTargets=type(s.smartMaterialTargets)=="table" and s.smartMaterialTargets or {}
    local result={}
    if selected then
        for _,item in ipairs(self:GetSmartMaterialChoices(profession)) do
            if type(item.requiredSkill)=="number" and item.requiredSkill<=learned.skill then
                result[item.resourceKey]=true
            end
        end
    end
    local previous=s.smartMaterialTargets[profession]
    -- Global smart targets have no nil-vs-explicit-empty distinction in the
    -- route context. Compare effective selected keys before retiring a route.
    local changed=false
    for k,v in pairs(type(previous)=="table" and previous or {}) do
        if v==true and result[k]~=true then changed=true;break end
    end
    if not changed then
        for k,v in pairs(result) do
            if v==true and not (type(previous)=="table" and previous[k]==true) then
                changed=true;break
            end
        end
    end
    if not changed then return true end
    s.smartMaterialTargets[profession]=result
    local assessor=JLP:GetModule("GatheringZoneSuitability")
    if assessor then assessor:CancelRecommendation("MATERIAL_TARGETS_CHANGED") end
    retireRoute("SMART_MATERIALS_CHANGED")
    return true
end
function State:CycleFishingAreaFilter(mapID)
    if not validMap(mapID) then return false,"MAP_ID_INVALID" end
    local s,err=store();if not s then return false,err end
    local ref=JLP.data and JLP.data.fishingCatchAreaReference
    local rows=ref and ref.maps and ref.maps[mapID] or {}
    local ids={}
    for _,row in ipairs(rows) do
        if type(row.itemID)=="number" and row.itemID>0 and row.itemID==math.floor(row.itemID) then
            ids[#ids+1]=row.itemID
        end
    end
    table.sort(ids)
    local mode=s.fishingAreaFilter
    if mode~="COOKING_NEEDS" and mode~="SINGLE_FISH" then
        s.fishingAreaFilter="COOKING_NEEDS";s.fishingSelectedItemID=nil
    elseif mode=="COOKING_NEEDS" then
        if #ids==0 then s.fishingAreaFilter="ALL";s.fishingSelectedItemID=nil
        else s.fishingAreaFilter="SINGLE_FISH";s.fishingSelectedItemID=ids[1] end
    else
        local index=0
        for i,id in ipairs(ids) do if id==s.fishingSelectedItemID then index=i;break end end
        if index>0 and index<#ids then s.fishingSelectedItemID=ids[index+1]
        else s.fishingAreaFilter="ALL";s.fishingSelectedItemID=nil end
    end
    return true
end
function State:SetFishingAreaFilter(mode,itemID,mapID)
    if mode~="ALL" and mode~="COOKING_NEEDS" and mode~="SINGLE_FISH" then
        return false,"FISHING_FILTER_INVALID" end
    if mode=="SINGLE_FISH" and (type(itemID)~="number" or itemID<1 or itemID~=math.floor(itemID)) then
        return false,"FISH_ID_INVALID" end
    -- A species may only be selected for a documented zone/item relation.
    -- Zone-only entries remain selectable, but never create invented markers.
    if mode=="SINGLE_FISH" then
        local catalogue=JLP:GetModule("FishingResourceCatalogue70450")
        local current=mapID
        if not validMap(current) then
            local saved=store();current=saved and saved.selectedMapID
        end
        local found=validMap(current) and catalogue and catalogue:Find(current,itemID)
        if not found then return false,"FISH_NOT_DOCUMENTED_IN_ZONE" end
    end
    local s,err=store();if not s then return false,err end
    s.fishingAreaFilter=mode;s.fishingSelectedItemID=mode=="SINGLE_FISH" and itemID or nil
    return true
end
function State:SetFishingAreas(enabled)
    if type(enabled)~="boolean" then return false,"VALUE_INVALID" end
    local s,err=store();if not s then return false,err end
    s.showFishingAreas=enabled
    return true
end
-- All shared-state edits use the SINGLE route-service owner. A rejected,
-- missing or thrown Cancel is NOT a successful stop: quarantine the old
-- generation so standalone and embedded cannot publish a stale READY route.
-- This helper changes no DB schema, route engine or native authority.
retireRoute=function(reason)
    local route=JLP:GetModule("GatheringRouteService")
    if not route or type(route.Cancel)~="function" then return false,"ROUTE_SERVICE_UNAVAILABLE" end
    local ok,accepted,why=pcall(route.Cancel,route,reason)
    if ok and accepted==true then return true end
    local failure=not ok and "ROUTE_CANCEL_EXCEPTION" or
        (type(why)=="string" and why or "ROUTE_CANCEL_UNCONFIRMED")
    if type(route.QuarantineUnconfirmedCancellation)=="function" then
        pcall(route.QuarantineUnconfirmedCancellation,route,failure)
    end
    return false,failure
end
function State:SetSourceFilter(source)
    if source~="ALL" and source~="OBSERVED_ONLY" then return false,"SOURCE_FILTER_INVALID" end
    local s,err=store();if not s then return false,err end
    if s.sourceFilter~=source then
        s.sourceFilter=source
        retireRoute("SOURCE_FILTER_CHANGED")
    end
    return true
end
-- Route-source policy is never inferred from pin visibility. Upgrades default
-- to ALL regardless of a preexisting OBSERVED_ONLY display filter.
function State:SetRouteSource(value)
    if value~="ALL" and value~="OBSERVED_ONLY" and value~="PREFER_OBSERVED" then
        return false,"ROUTE_SOURCE_INVALID" end
    local s,err=store();if not s then return false,err end
    if s.routeSource~=value then
        s.routeSource=value
        retireRoute("ROUTE_SOURCE_CHANGED")
    end
    return true
end
function State:CycleRouteSource()
    local snapshot=self:GetSnapshot()
    if not snapshot then return false,"STATE_UNAVAILABLE" end
    return self:SetRouteSource(snapshot.routeSource=="ALL" and "OBSERVED_ONLY" or
        snapshot.routeSource=="OBSERVED_ONLY" and "PREFER_OBSERVED" or "ALL")
end
function State:SelectMap(id,browseScope)
    if id~=nil and not validMap(id) then return false,"MAP_ID_INVALID" end
    if browseScope~=nil and browseScope~="CONTINENT" and browseScope~="GUIDE" then
        return false,"MAP_BROWSE_SCOPE_INVALID" end
    local s,err=store();if not s then return false,err or "DB_NOT_READY" end
    -- A fish species is only a valid single-species filter in zones with an
    -- explicit source record for that exact ItemID. A cross-zone browse or a
    -- return to the player's current zone must not carry an unsupported fish
    -- selection into another map. Keep valid cross-zone selections and the
    -- unrelated Cooking-needs/ALL filters as they were.
    if s.fishingAreaFilter=="SINGLE_FISH" then
        local fish=JLP:GetModule("FishingResourceCatalogue70450")
        local documented=validMap(id) and fish and type(fish.Find)=="function" and
            fish:Find(id,s.fishingSelectedItemID)
        if not documented then
            s.fishingAreaFilter="ALL"
            s.fishingSelectedItemID=nil
        end
    end
    -- A repeated zone selection (from either map UI or a recommendation)
    -- is not a route change. Preserve a committed route, its generation and
    -- any ongoing recommendation when only the browse-menu scope changes.
    -- Actual map changes still retire the route through the single owner.
    local mapChanged=s.selectedMapID~=id
    s.selectedMapID=id
    -- Optional persisted selection origin; the source is not a new mapID or
    -- authority, only whether arrows use native continent or Fishing guide.
    s.zoneBrowseScope=id and browseScope=="CONTINENT" and "CONTINENT" or nil
    if mapChanged then
        local recommendations=JLP:GetModule("GatheringZoneSuitability")
        if recommendations then recommendations:CancelRecommendation("MAP_CHANGED") end
        retireRoute("MAP_SELECTION_CHANGED")
    end
    return true
end
function State:SetMode(mode,focus)
    if mode~="CUSTOM_LOOP" and mode~="SMART_PROFESSION" then return false,"MODE_INVALID" end
    if focus~=nil and focus~="MATERIALS" and focus~="SKILL" and focus~="BALANCED" then
        return false,"FOCUS_INVALID" end
    local s,err=store();if not s then return false,err or "DB_NOT_READY" end
    local changed=s.mode~=mode or (focus~=nil and s.focus~=focus)
    s.mode=mode
    if focus then s.focus=focus end
    if changed then
        local recommendations=JLP:GetModule("GatheringZoneSuitability")
        if recommendations then recommendations:CancelRecommendation("MODE_CHANGED") end
        retireRoute("MODE_OR_FOCUS_CHANGED")
    end
    return true
end
-- Layer preferences only. Learning a profession is *never* inferred from a saved toggle.
function State:SetLayerEnabled(professionKey,enabled)
    if professionKey~="HERBALISM" and professionKey~="MINING" then return false,"LAYER_INVALID" end
    if type(enabled)~="boolean" then return false,"VALUE_INVALID" end
    local s,err=store();if not s then return false,err or "DB_NOT_READY" end
    s.layerEnabled=type(s.layerEnabled)=="table" and s.layerEnabled or {}
    -- The saved nil default is logically disabled. Repeating the same UI
    -- choice must not revoke a still-authorized route generation.
    if (s.layerEnabled[professionKey]==true)==enabled then return true end
    s.layerEnabled[professionKey]=enabled
    local recommendations=JLP:GetModule("GatheringZoneSuitability")
    if recommendations then recommendations:CancelRecommendation("LAYER_CHANGED") end
    retireRoute("LAYER_CHANGED")
    return true
end
function State:SetResourceFilter(professionKey,key)
    if professionKey~="HERBALISM" and professionKey~="MINING" then return false,"LAYER_INVALID" end
    if key~=nil and (type(key)~="string" or not key:match("^[A-Z0-9_]+$") or #key>80) then
        return false,"FILTER_INVALID" end
    local s,err=store();if not s then return false,err or "DB_NOT_READY" end
    s.resourceFilters=type(s.resourceFilters)=="table" and s.resourceFilters or {}
    if s.resourceFilters[professionKey]==key then return true end
    s.resourceFilters[professionKey]=key
    retireRoute("FILTER_CHANGED")
    return true
end

-- Multi-selection is per map/per profession. nil means unrestricted overlay;
-- an explicit empty set means no selected resources (and never creates a route).
-- Compare effective selected keys, not table identity or entry insertion order.
-- An absent selection is different from an explicit empty set.
local function sameSelectionKeys(current,desired)
    if type(current)~="table" or type(desired)~="table" then return false end
    for key,on in pairs(current) do
        if on==true and desired[key]~=true then return false end
    end
    for key,on in pairs(desired) do
        if on==true and current[key]~=true then return false end
    end
    return true
end
function State:GetResourceSelection(mapID,professionKey)
    if not validMap(mapID) or (professionKey~="HERBALISM" and professionKey~="MINING") then return nil,"SELECTION_INVALID" end
    local snapshot,err=self:GetSnapshot()
    if not snapshot then return nil,err end
    local zone=snapshot.resourceSelectionsByMap[mapID]
    if not zone or zone[professionKey]==nil then return nil,nil end
    return zone[professionKey],nil
end
function State:SetResourceSelection(mapID,professionKey,resourceKey,selected)
    if not validMap(mapID) or (professionKey~="HERBALISM" and professionKey~="MINING") or
       type(resourceKey)~="string" or not resourceKey:match("^[A-Z0-9_]+$") or #resourceKey>80 or
       type(selected)~="boolean" then return false,"SELECTION_INVALID" end
    local registry=JLP:GetModule("GatheringDataRegistry")
    local info=registry and registry:GetZoneResourceSummary(mapID,professionKey)
    local known=false
    for _,record in ipairs(info and info.resources or {}) do if record.resourceKey==resourceKey then known=true;break end end
    if not known then return false,"RESOURCE_NOT_IN_ZONE" end
    local s,err=store();if not s then return false,err end
    s.resourceSelectionsByMap=type(s.resourceSelectionsByMap)=="table" and s.resourceSelectionsByMap or {}
    local zone=s.resourceSelectionsByMap[mapID]
    if type(zone)~="table" then zone={};s.resourceSelectionsByMap[mapID]=zone end
    local selection=zone[professionKey]
    s.resourceFilters=type(s.resourceFilters)=="table" and s.resourceFilters or {}
    -- First explicit empty selection IS a change from unrestricted (nil).
    -- Removing the obsolete legacy single-filter is also a real route change.
    local changed=type(selection)~="table" or
        (type(selection)=="table" and (selection[resourceKey]==true)~=selected) or
        s.resourceFilters[professionKey]~=nil
    if not changed then return true end
    if type(selection)~="table" then selection={};zone[professionKey]=selection end
    selection[resourceKey]=selected and true or nil
    s.resourceFilters[professionKey]=nil -- the multi-select supersedes the legacy single filter
    retireRoute("SELECTION_CHANGED")
    return true
end
function State:SetResourceSelectionAll(mapID,professionKey,enabled)
    if not validMap(mapID) or (professionKey~="HERBALISM" and professionKey~="MINING") or type(enabled)~="boolean" then
        return false,"SELECTION_INVALID" end
    local registry=JLP:GetModule("GatheringDataRegistry")
    local summary=registry and registry:GetZoneResourceSummary(mapID,professionKey)
    if type(summary)~="table" or type(summary.resources)~="table" then return false,"ZONE_UNAVAILABLE" end
    local s,err=store();if not s then return false,err end
    s.resourceSelectionsByMap=type(s.resourceSelectionsByMap)=="table" and s.resourceSelectionsByMap or {}
    local zone=s.resourceSelectionsByMap[mapID] or {};s.resourceSelectionsByMap[mapID]=zone
    local selected={}
    if enabled then for _,row in ipairs(summary.resources) do selected[row.resourceKey]=true end end
    s.resourceFilters=type(s.resourceFilters)=="table" and s.resourceFilters or {}
    if sameSelectionKeys(zone[professionKey],selected) and s.resourceFilters[professionKey]==nil then
        return true
    end
    zone[professionKey]=selected
    s.resourceFilters[professionKey]=nil
    retireRoute("SELECTION_CHANGED")
    return true
end
-- Individual node selection is the same user intent as Custom All, but
-- scoped to ONE qualified resource. Do not let a saved/unknown key grant a
-- profession, or leave a selected node behind a disabled gathering layer.
-- All mutations and cancellation remain owned by this shared state.
function State:SelectQualifiedZoneResource(mapID,professionKey,resourceKey,selected)
    if not validMap(mapID) or (professionKey~="HERBALISM" and professionKey~="MINING") or
       type(resourceKey)~="string" or not resourceKey:match("^[A-Z0-9_]+$") or
       #resourceKey>80 or type(selected)~="boolean" then
        return false,"SELECTION_INVALID" end
    local snapshot=self:GetSnapshot()
    if type(snapshot)~="table" or snapshot.mode~="CUSTOM_LOOP" then
        return false,"CUSTOM_MODE_REQUIRED" end
    local controller=JLP:GetModule("GatheringMapLayerController")
    local ok,info=pcall(function()return controller and controller:GetLayerState(mapID) end)
    local layer=ok and type(info)=="table" and type(info.layers)=="table" and info.layers[professionKey]
    if type(layer)~="table" or layer.learned~=true then return false,"PROFESSION_NOT_LEARNED" end
    local qualified=false
    for _,record in ipairs(type(layer.resources)=="table" and layer.resources or {}) do
        if record.resourceKey==resourceKey and (tonumber(record.referenceCount) or 0)>0 then
            qualified=true;break end
    end
    if not qualified then return false,"RESOURCE_NOT_QUALIFIED_IN_ZONE" end
    local priorSelection=self:GetResourceSelection(mapID,professionKey)
    local priorLayer=snapshot.layerEnabled and snapshot.layerEnabled[professionKey]==true
    local applied,reason=self:SetResourceSelection(mapID,professionKey,resourceKey,selected)
    if not applied then return false,reason end
    -- A newly-enabled layer still changes route identity even when the
    -- resource was already selected. Do not double-cancel if the selection
    -- itself has just changed or was previously unrestricted.
    if selected then
        local s=store()
        if not s then return false,"STATE_UNAVAILABLE" end
        s.layerEnabled=type(s.layerEnabled)=="table" and s.layerEnabled or {}
        s.layerEnabled[professionKey]=true
        if not priorLayer and type(priorSelection)=="table" and priorSelection[resourceKey]==true and
            not (snapshot.resourceFilters and snapshot.resourceFilters[professionKey]~=nil) then
            retireRoute("LAYER_CHANGED")
        end
    end
    return true,selected and "QUALIFIED_RESOURCE_AND_LAYER_SELECTED" or "QUALIFIED_RESOURCE_DESELECTED"
end
-- A deliberate "All" click is a complete Custom-resource setup: select
-- qualified resources in this zone AND enable the actually learned layer.
-- The existing shared state and layer controller remain the only owners.
-- Nothing is gathered, bought, crafted or promoted to production authority.
function State:ActivateZoneResources(mapID,professionKey,query)
    if not validMap(mapID) or (professionKey~="HERBALISM" and professionKey~="MINING") then
        return false,"SELECTION_INVALID" end
    local layers=JLP:GetModule("GatheringMapLayerController")
    local ok,info=pcall(function() return layers and layers:GetLayerState(mapID) end)
    local layer=ok and type(info)=="table" and info.layers and info.layers[professionKey]
    if type(layer)~="table" or layer.learned~=true then
        return false,"PROFESSION_NOT_LEARNED" end
    -- When a user searches and then chooses All, select all qualified
    -- matches, not unrelated hidden rows on the other pages. Empty search
    -- retains the original full-zone All behavior and its source policy.
    if query~=nil and type(query)~="string" then return false,"SEARCH_INVALID" end
    query=(query or ""):match("^%s*(.-)%s*$")
    if #query>80 then return false,"SEARCH_TOO_LONG" end
    local matching={}
    if query~="" then
        local browser=JLP:GetModule("GatheringResourceBrowser")
        if not browser or type(browser.Build)~="function" then
            return false,"RESOURCE_BROWSER_UNAVAILABLE" end
        local ok,listing=pcall(browser.Build,browser,layer,query,0,
            math.max(1,#(layer.resources or {})))
        if not ok or type(listing)~="table" or type(listing.rows)~="table" then
            return false,"RESOURCE_FILTER_UNAVAILABLE" end
        for _,item in ipairs(listing.rows) do
            if item.sourceQualified==true and type(item.resourceKey)=="string" then
                matching[item.resourceKey]=true
            end
        end
    end
    local count=0
    for _,record in ipairs(layer.resources or {}) do
        if type(record.resourceKey)=="string" and (tonumber(record.referenceCount) or 0)>0 and
            (query=="" or matching[record.resourceKey]==true) then
            count=count+1
        end
    end
    if count==0 then return false,query~="" and "NO_MATCHING_QUALIFIED_RESOURCES" or "NO_ZONE_RESOURCE_REFERENCES" end
    local s,err=store();if not s then return false,err or "DB_NOT_READY" end
    s.layerEnabled=type(s.layerEnabled)=="table" and s.layerEnabled or {}
    s.resourceSelectionsByMap=type(s.resourceSelectionsByMap)=="table" and s.resourceSelectionsByMap or {}
    local zone=s.resourceSelectionsByMap[mapID]
    if type(zone)~="table" then zone={};s.resourceSelectionsByMap[mapID]=zone end
    local selected={}
    for _,record in ipairs(layer.resources or {}) do
        if type(record.resourceKey)=="string" and (tonumber(record.referenceCount) or 0)>0 and
            (query=="" or matching[record.resourceKey]==true) then
            selected[record.resourceKey]=true
        end
    end
    s.resourceFilters=type(s.resourceFilters)=="table" and s.resourceFilters or {}
    local unchanged=sameSelectionKeys(zone[professionKey],selected) and
        s.layerEnabled[professionKey]==true and s.resourceFilters[professionKey]==nil
    if unchanged then
        return true,query~="" and "MATCHING_RESOURCES_ENABLED" or "ZONE_RESOURCES_ENABLED",count
    end
    zone[professionKey]=selected
    s.layerEnabled[professionKey]=true
    s.resourceFilters[professionKey]=nil
    local retirement,why=retireRoute("ZONE_RESOURCE_SETUP_CHANGED")
    -- Cancellation may fail on a parallel route engine. Existing quarantine
    -- guards suppress that generation; selections remain the user's intent.
    return true,retirement and (query~="" and "MATCHING_RESOURCES_ENABLED" or "ZONE_RESOURCES_ENABLED") or
        "ZONE_RESOURCES_ENABLED_ROUTE_QUARANTINED",count
end
function State:SetRouteShape(shape)
    if shape~="LOOP" and shape~="FROM_PLAYER" then return false,"ROUTE_SHAPE_INVALID" end
    local s,err=store();if not s then return false,err end
    if (s.routeShape=="FROM_PLAYER" and "FROM_PLAYER" or "LOOP")==shape then return true end
    s.routeShape=shape
    retireRoute("SHAPE_CHANGED")
    return true
end
-- Viewport-only settings: shared zone, routes, filters and source data stay
-- in the existing character gathering namespace. No duplicate route persistence.
local function bounded(value,low,high,default)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return default end
    return math.max(low,math.min(high,value))
end
function State:GetStandaloneSettings()
    local s,err=store();if not s then return nil,err end
    local v=type(s.standalone)=="table" and s.standalone or {}
    return {visible=v.visible==true,
        x=bounded(v.x,-4096,4096,0),y=bounded(v.y,-4096,4096,0),
        width=bounded(v.width,640,1300,760),height=bounded(v.height,390,1000,550),
        backgroundOpacity=bounded(v.backgroundOpacity,0.2,1,0.85),
        chromeOpacity=bounded(v.chromeOpacity,0.35,1,1)}
end
function State:SetStandaloneSettings(patch)
    if type(patch)~="table" then return false,"VIEW_SETTINGS_INVALID" end
    local current,err=self:GetStandaloneSettings();if not current then return false,err end
    for key,value in pairs(patch) do
        if key=="visible" then
            if type(value)~="boolean" then return false,"VIEW_SETTINGS_INVALID" end
        elseif key=="x" or key=="y" then
            if type(value)~="number" or value~=value or value==math.huge or value==-math.huge or math.abs(value)>4096 then
                return false,"VIEW_SETTINGS_INVALID" end
        elseif key=="width" or key=="height" then
            local lo,hi=key=="width" and 640 or 390,key=="width" and 1300 or 1000
            if type(value)~="number" or value~=value or value<lo or value>hi then return false,"VIEW_SETTINGS_INVALID" end
        elseif key=="backgroundOpacity" then
            if type(value)~="number" or value~=value or value<0.2 or value>1 then
                return false,"VIEW_SETTINGS_INVALID" end
        elseif key=="chromeOpacity" then
            if type(value)~="number" or value~=value or value<0.35 or value>1 then
                return false,"VIEW_SETTINGS_INVALID" end
        else return false,"VIEW_SETTINGS_UNKNOWN_FIELD" end
    end
    local s=store();if not s then return false,"DB_NOT_READY" end
    s.standalone=type(s.standalone)=="table" and s.standalone or {}
    for key,value in pairs(patch) do s.standalone[key]=value end
    return true
end
JLP:RegisterModule("GatheringSharedMapState",State)
