local _, JLP = ...

-- P0-173: bounded chronological trace of observable native craft events.
-- This is DIAGNOSTIC data only: neither a castGUID nor an operationID here
-- grants permission to dispatch, confirm a craft, train yield, or resume.
local Correlation = {
    contract="native-craft-event-correlation-audit-v1", schema=1,
    maxEvents=128, readOnly=true, nativeDispatchAllowed=false,
    executionEligible=false, automaticResume=false, sessionID=nil,
}
local function clock()
    if type(time)=="function" then local ok,v=pcall(time);if ok and type(v)=="number" then return v end end
    return 0
end
local function characterKey()
    local id=JLP:GetModule("CharacterIdentity")
    local key=id and id.GetKey and id:GetKey() or nil
    if type(key)=="string" and key~="" and key~="UnknownRealm:UnknownCharacter" then return key end
    return nil
end
local function store()
    local db=JLP.DB
    if type(db)~="table" then return nil end
    db.account=db.account or {}
    local key=characterKey()
    if not key then return nil end
    local root=db.account.craftEventCorrelation
    if type(root)~="table" then root={schema=1,characters={}};db.account.craftEventCorrelation=root end
    root.characters=type(root.characters)=="table" and root.characters or {}
    local row=root.characters[key]
    if type(row)~="table" then row={nextSequence=0,events={},dropped=0};root.characters[key]=row end
    row.events=type(row.events)=="table" and row.events or {}
    row.nextSequence=math.max(0,tonumber(row.nextSequence) or 0)
    row.dropped=math.max(0,tonumber(row.dropped) or 0)
    return row
end
local function snapshot()
    local craft=JLP:GetModule("Crafting")
    local pending=craft and (craft.pendingCraft or craft.pendingEnchant) or nil
    local recovery=JLP:GetModule("TransactionRecovery")
    local checkpoint=not pending and recovery and recovery.GetCheckpoint and recovery:GetCheckpoint() or nil
    local context=pending or checkpoint
    local ledger=JLP:GetModule("TransactionLedger")
    local lid=context and (context.ledgerID or context.transactionID) or nil
    local tx=lid and ledger and ledger.GetTransaction and ledger:GetTransaction(lid) or nil
    return {ledgerID=lid,recipeID=context and tonumber(context.recipeID) or nil,
        mode=context and context.mode or nil,
        requested=context and tonumber(context.requestedCount) or nil,
        ordinalInFlight=context and context.strictOrdinalInFlight==true or false,
        awaitingClick=context and context.strictAwaitingUserClick==true or false,
        recovering=not pending and checkpoint~=nil,
        confirmed=tx and tonumber(tx.confirmedCount) or nil,
        status=tx and tx.status or nil,
        closed=tx and tx.closedAt~=nil or false}
end
function Correlation:Initialize()
    -- A rapid /reload can yield the SAME clock() second and GetTime() value,
    -- especially immediately after client startup. Never reuse an earlier
    -- diagnostic session's ticket identity just because both clocks match.
    local current=store()
    if not current then return false end
    if not self.sessionID then
        local previous=tonumber(current.sessionSequence)
        if not previous or previous~=previous or previous<0 or
           previous==math.huge or previous~=math.floor(previous) then previous=0 end
        -- Session generation is account/character-scoped and persisted solely
        -- for diagnostic ticket disambiguation, NEVER native entitlement.
        current.sessionSequence=previous+1
        local fractional=type(GetTime)=="function" and math.floor((tonumber(GetTime()) or 0)*1000) or 0
        self.sessionID=tostring(clock())..":"..tostring(fractional)..":"..
            tostring(JLP.version or "unknown")..":session-"..tostring(current.sessionSequence)
    end
    return true
end
local function payloadOf(event,...)
    local a,b,c=...
    if event=="TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        if type(a)~="table" then return {payloadType=type(a)} end
        return {recipeID=tonumber(a.recipeID or a.spellID or a.craftingSpellID),
            operationID=(type(a.operationID)=="number" or type(a.operationID)=="string") and tostring(a.operationID) or nil,
            castGUID=type(a.castGUID)=="string" and a.castGUID or nil,
            itemID=tonumber(a.itemID),quantity=tonumber(a.quantity),isEnchant=a.isEnchant==true}
    elseif event=="TRADE_SKILL_CRAFT_BEGIN" then return {recipeID=tonumber(a)}
    elseif event=="UNIT_SPELLCAST_SENT" then
        local unit,_,guid,spellID=...
        return {unit=unit,castGUID=type(guid)=="string" and guid or nil,spellID=tonumber(spellID)}
    else return {unit=a,castGUID=type(b)=="string" and b or nil,spellID=tonumber(c)} end
end
function Correlation:BeginEvent(event,...)
    if event~="TRADE_SKILL_CRAFT_BEGIN" and event~="TRADE_SKILL_ITEM_CRAFTED_RESULT" and
        event~="UNIT_SPELLCAST_SENT" and event~="UNIT_SPELLCAST_SUCCEEDED" and
        event~="UNIT_SPELLCAST_FAILED" and event~="UNIT_SPELLCAST_INTERRUPTED" then return nil end
    local current=store()
    if not current then return nil end
    self:Initialize()
    local evidence=payloadOf(event,...)
    local before=snapshot()
    local eventRecipe=evidence.recipeID or evidence.spellID
    local correlated=before.ledgerID~=nil and eventRecipe~=nil and eventRecipe==before.recipeID
    local row={sequence=current.nextSequence+1,sessionID=self.sessionID,
        observedAt=clock(),event=event,payload=evidence,
        characterKey=characterKey(),
        ledgerID=before.ledgerID,recipeID=before.recipeID,
        mode=before.mode,requestedCrafts=before.requested,
        beforeConfirmed=before.confirmed,beforeStatus=before.status,
        wasClosed=before.closed,recovering=before.recovering,
        ordinalInFlight=before.ordinalInFlight,awaitingClick=before.awaitingClick,
        context=correlated and "RECIPE_MATCH_OBSERVATION" or "UNATTRIBUTED",
        eventProcessed=false,nativeAuthority=false}
    if before.ledgerID and not correlated and eventRecipe==nil then row.context="IDENTITY_MISSING" end
    if before.awaitingClick or (before.mode=="all" and before.ordinalInFlight==false) then
        row.context="NO_IN_FLIGHT_ORDINAL"
    end
    current.nextSequence=row.sequence
    current.events[#current.events+1]=row
    while #current.events>self.maxEvents do table.remove(current.events,1);current.dropped=current.dropped+1 end
    return row.sequence
end
function Correlation:EndEvent(ticket)
    if not ticket then return false end
    local current=store()
    if not current then return false end
    local row
    for i=#current.events,1,-1 do
        if current.events[i].sequence==ticket then row=current.events[i];break end
    end
    if not row or row.eventProcessed then return false end
    -- A prior-session/cross-character ticket must not be finalized in the
    -- current diagnostic stream after /reload or a character switch.
    if row.sessionID~=self.sessionID or row.characterKey~=characterKey() then
        return false,"STALE_OR_FOREIGN_EVENT_TICKET"
    end
    local ledger=JLP:GetModule("TransactionLedger")
    local tx=row.ledgerID and ledger and ledger.GetTransaction and ledger:GetTransaction(row.ledgerID) or nil
    row.afterConfirmed=tx and tonumber(tx.confirmedCount) or nil
    row.afterStatus=tx and tx.status or nil
    row.afterClosed=tx and tx.closedAt~=nil or false
    row.confirmedDelta=type(row.beforeConfirmed)=="number" and
        type(row.afterConfirmed)=="number" and
        (row.afterConfirmed-row.beforeConfirmed) or 0
    row.eventProcessed=true
    -- The ledger owns the transaction outcome.  A foreign recipe event or
    -- no-in-flight ordinal cannot acquire a positive event correlation just
    -- because an unrelated ledger entry moved between snapshots.
    local matched=row.context=="RECIPE_MATCH_OBSERVATION" and
        row.ledgerID~=nil and tx~=nil and row.ledgerID==(tx.id or row.ledgerID)
    row.outcome=(row.confirmedDelta>0 and matched) and "LEDGER_CONFIRMED" or
        (row.confirmedDelta>0 and not matched) and "UNATTRIBUTED_LEDGER_CHANGE" or
        row.afterClosed and "TERMINAL_OBSERVATION" or "NO_NEW_LEDGER_CONFIRMATION"
    -- Observation cannot confirm a cast, upgrade data, change authority, or
    -- resume a previous session. The ledger continues to own confirmation.
    return true,row
end
function Correlation:GetRecent(limit)
    local current=store()
    local out={}
    local events=current and current.events or {}
    local count=math.min(tonumber(limit) or 25,128)
    for i=math.max(1,#events-count+1),#events do
        local r=events[i]
        out[#out+1]={sequence=r.sequence,event=r.event,sessionID=r.sessionID,
            ledgerID=r.ledgerID,context=r.context,outcome=r.outcome,
            beforeConfirmed=r.beforeConfirmed,afterConfirmed=r.afterConfirmed,
            confirmedDelta=r.confirmedDelta,afterStatus=r.afterStatus,
            recovering=r.recovering,payload=r.payload}
    end
    return out
end
function Correlation:GetSummary()
    local s=store()
    return {contract=self.contract,readOnly=true,executionEligible=false,
        nativeDispatchAllowed=false,automaticResume=false,
        records=s and #s.events or 0,dropped=s and s.dropped or 0,
        lastSequence=s and s.nextSequence or 0,sessionID=self.sessionID}
end
JLP:RegisterModule("CraftEventCorrelation",Correlation)
