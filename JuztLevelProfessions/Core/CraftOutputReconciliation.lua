local _, JLP = ...

-- P0-171: craft ordinals and output ITEM QUANTITIES are different evidence
-- domains. This is a read-only, volatile correlator, never a dispatch gate.
-- Anonymous, replayed, batch-wide and out-of-order item events cannot
-- generate a fixed output-per-craft claim or automatic route advancement.
local Output = {
    contract="native-craft-output-reconciliation-v2",
    lateReviewContract="read-only-post-terminal-output-journal-v1",
    maxTerminal=16,maxLatePerTerminal=24,
    sessionTerminalIDs={}, -- volatile: persisted records cannot block future client sessions
    readOnly=true, nativeDispatchAllowed=false, executionEligible=false,
    maxReceipts=64,
}

local function positive(value)
    return type(value)=="number" and value==math.floor(value) and
        value>0 and value<9007199254740991
end
local function validIdentity(data)
    local op=data and data.operationID
    if positive(op) or (type(op)=="string" and positive(tonumber(op))) then
        return "operation:"..tostring(op)
    end
    local guid=data and data.itemGUID
    if type(guid)=="string" and guid~="" and guid~="0" then
        return "itemguid:"..guid
    end
    return nil
end

function Output:Observe(pending,data)
    if type(pending)~="table" or type(data)~="table" then return false,"invalid-input" end
    -- Never guess recipe identity from the currently displayed profession.
    local rid=data.recipeID or data.spellID or data.craftingSpellID
    if rid==nil or tonumber(rid)~=tonumber(pending.recipeID) then
        return false,"recipe-identity-unverified"
    end
    if not positive(data.itemID) or not positive(data.quantity) then
        return false,"invalid-item-or-quantity"
    end
    local key=validIdentity(data)
    local list=pending.outputResultReceipts
    if type(list)~="table" then
        list={seen={},rows={},ambiguous=false,unattributed=0}; pending.outputResultReceipts=list
    end
    if not key then
        list.unattributed=list.unattributed+1
        return false,"result-identity-unverified"
    end
    -- Same operation may legitimately output multiple distinct item IDs.
    local composite=key..":item:"..tostring(data.itemID)
    local old=list.seen[composite]
    if old then
        if old~=data.quantity then list.ambiguous=true; return false,"conflicting-replayed-result" end
        return false,"duplicate-output-receipt"
    end
    if #list.rows>=self.maxReceipts then list.ambiguous=true; return false,"receipt-capacity-exceeded" end
    local row={key=composite,itemID=data.itemID,quantity=data.quantity,
        operationID=data.operationID,itemGUID=data.itemGUID,
        recipeID=tonumber(rid)}
    list.seen[composite]=data.quantity
    list.rows[#list.rows+1]=row
    return true,"observed",row
end

function Output:Summarize(pending,confirmed)
    confirmed=math.max(0,math.floor(tonumber(confirmed) or 0))
    local list=type(pending.outputResultReceipts)=="table" and pending.outputResultReceipts or {}
    local rows=list.rows or {}
    local observed=0
    local byItem={}
    for _,row in ipairs(rows) do
        observed=observed+row.quantity
        byItem[tostring(row.itemID)]=(byItem[tostring(row.itemID)] or 0)+row.quantity
    end
    local summary={contract=self.contract,confirmedCrafts=confirmed,
        requestedCrafts=math.max(1,tonumber(pending.requestedCount) or 1),
        receiptCount=#rows,unattributedEvents=list.unattributed or 0,
        ambiguous=list.ambiguous==true,observedReceiptUnits=observed,
        observedUnitsByItem=byItem,confirmedOutputUnits=nil,
        fixedYieldFromCurrentTransaction=nil,
        status="OUTPUT_UNKNOWN",expectedOutputUnits=nil,expectedSource="UNKNOWN"}
    -- Expected output is a reference for reconciliation, not a target count.
    local evidence=JLP:GetModule("RecipeOutputEvidence")
    local resolved=evidence and evidence.Resolve and evidence:Resolve(pending.recipeName,pending.recipeID) or nil
    if type(resolved)=="table" and resolved.liveVerified==true and
        resolved.fixed==true and positive(resolved.outputQuantity) then
        summary.expectedPerCraft=resolved.outputQuantity
        summary.expectedOutputUnits=confirmed*resolved.outputQuantity
        summary.expectedSource="LIVE_FIXED_YIELD_REFERENCE"
    end
    -- An entire multi-craft batch may emit one aggregate result; never divide
    -- by confirmedCount or use such a payload as one operation's yield.
    if confirmed~=1 or summary.requestedCrafts~=1 then
        summary.status=(#rows>0 and "BATCH_OUTPUT_UNATTRIBUTED" or "OUTPUT_UNKNOWN")
        return summary
    end
    if list.ambiguous or (list.unattributed or 0)>0 or #rows==0 then
        summary.status=(#rows>0 and "OUTPUT_RECEIPT_AMBIGUOUS" or "OUTPUT_UNKNOWN")
        return summary
    end
    -- An explicit same-operation identity can group several DISTINCT item
    -- types produced by a single confirmed cast. Multiple identities are not
    -- automatically multiple crafts, nor proof that they belong together.
    local shared=nil
    for _,receipt in ipairs(rows) do
        local op=receipt.operationID
        if not positive(op) and not (type(op)=="string" and positive(tonumber(op))) then
            shared=nil; break
        end
        local identity=tostring(op)
        if shared and shared~=identity then shared=nil;break end
        shared=identity
    end
    if #rows>1 then
        if not shared then
            summary.status="OUTPUT_RECEIPT_AMBIGUOUS"
            return summary
        end
        summary.status="CORRELATED_SINGLE_CRAFT_MULTI_OUTPUT"
        summary.confirmedOutputUnits=observed
        summary.confirmedOutputByItem=byItem
        summary.correlatedOperationID=shared
        summary.comparison="NOT_COMPARABLE_MULTI_ITEM"
        summary.expectedOutputUnits=nil -- historic primary-output yields cannot be compared to sum of bonus items
        summary.expectedSource="NOT_COMPARABLE_MULTI_ITEM"
        summary.fixedYieldFromCurrentTransaction=nil -- no fixed per-item yield training from composite output
        return summary
    end
    local receipt=rows[1]
    summary.status="CORRELATED_SINGLE_CRAFT_RECEIPT"
    summary.confirmedOutputUnits=receipt.quantity
    summary.confirmedOutputItemID=receipt.itemID
    summary.confirmedOutputByItem=byItem
    summary.fixedYieldFromCurrentTransaction=receipt.quantity
    if summary.expectedOutputUnits then
        summary.comparison=summary.expectedOutputUnits==receipt.quantity and "MATCH" or "DEVIATION"
    else summary.comparison="NO_FIXED_LIVE_REFERENCE" end
    return summary,receipt
end

-- Store a bounded diagnostic journal across /reload. A saved terminal record
-- NEVER authenticates a new cast after reload and cannot reopen the ledger.
local function journal()
    local db=JLP.DB
    if type(db)~="table" or type(db.account)~="table" then return nil end
    local ident=JLP:GetModule("CharacterIdentity")
    local ck=ident and ident.GetKey and ident:GetKey() or nil
    if type(ck)~="string" or ck=="" or ck=="UnknownRealm:UnknownCharacter" then return nil end
    local root=db.account.craftOutputLateReview
    if type(root)~="table" then
        root={schema=1,characters={}};db.account.craftOutputLateReview=root
    end
    root.characters=type(root.characters)=="table" and root.characters or {}
    local state=root.characters[ck]
    if type(state)~="table" then state={terminals={}};root.characters[ck]=state end
    state.terminals=type(state.terminals)=="table" and state.terminals or {}
    return state.terminals
end

local function eventIdentity(data)
    if type(data)~="table" then return nil end
    local op=data.operationID
    if positive(op) or (type(op)=="string" and positive(tonumber(op))) then return tostring(op) end
    return nil -- itemGUID is an item, not a unique crafting operation
end

local function idOf(data)
    return type(data)=="table" and tonumber(data.recipeID or data.spellID or data.craftingSpellID) or nil
end

function Output:RememberTerminal(pending,summary)
    local rows=journal()
    if not rows or type(pending)~="table" or type(pending.ledgerID)~="string" then return false end
    for _,old in ipairs(rows) do
        if old.ledgerID==pending.ledgerID then return false end
    end
    local entry={ledgerID=pending.ledgerID,recipeID=tonumber(pending.recipeID),
        originalStatus=summary.status,confirmedCrafts=summary.confirmedCrafts,
        originalConfirmedOutputUnits=summary.confirmedOutputUnits,
        seen={},operations={},late={},lateCount=0, readOnly=true}
    local receipts=type(pending.outputResultReceipts)=="table" and pending.outputResultReceipts.rows or nil
    for _,r in ipairs(receipts or {}) do
        if r.operationID and eventIdentity(r) then
            local op=eventIdentity(r)
            entry.operations[op]=true
            entry.seen[op..":"..tostring(r.itemID)]=r.quantity
        end
    end
    rows[#rows+1]=entry
    self.sessionTerminalIDs[pending.ledgerID]=true
    while #rows>self.maxTerminal do table.remove(rows,1) end
    return true
end

-- If a terminal operation reappears during a subsequent cast, reject it
-- BEFORE the new transaction's output or ledger can be changed.
function Output:IsTerminalReplay(data)
    local op=eventIdentity(data)
    if not op then return false end
    local rows=journal()
    for _,entry in ipairs(rows or {}) do
        if self.sessionTerminalIDs[entry.ledgerID] and
            type(entry.operations)=="table" and entry.operations[op] then
            return true,"prior-terminal-operation"
        end
    end
    return false
end

function Output:ObserveLate(data)
    local rid=idOf(data)
    if not positive(rid) or not positive(data.itemID) or not positive(data.quantity) then
        return false,"late-result-invalid"
    end
    local rows=journal()
    if not rows then return false,"late-journal-unavailable" end
    local op=eventIdentity(data)
    local owner
    local recipeSeen=false
    for i=#rows,1,-1 do
        local entry=rows[i]
        if entry.recipeID==rid then
            recipeSeen=true
            if op and entry.operations and entry.operations[op] then
                if owner then return false,"late-operation-ambiguous" end
                owner=entry
            end
        end
    end
    if not recipeSeen then return false,"no-terminal-recipe-match" end
    -- Without a previously observed matching operation, no transaction can
    -- be attributed. Record only an unassigned result against the latest
    -- same-recipe review slot (no ledgerID or receipt-count mutation).
    if not owner then
        for i=#rows,1,-1 do if rows[i].recipeID==rid then owner=rows[i];break end end
    end
    local fingerprint=op and (op..":"..tostring(data.itemID)) or nil
    local prior=fingerprint and owner.seen and owner.seen[fingerprint] or nil
    if prior then
        if prior==data.quantity then return false,"duplicate-terminal-result" end
        -- Conflicts must be visible, but cannot alter original quantities.
    end
    local inCurrentSession=self.sessionTerminalIDs[owner.ledgerID]==true
    local status=not inCurrentSession and "LATE_PRIOR_SESSION_UNATTRIBUTED"
        or prior and "LATE_TERMINAL_CONFLICT"
        or (op and owner.operations and owner.operations[op] and "LATE_MATCHED_OPERATION_UNVERIFIED")
        or "LATE_UNATTRIBUTED_RESULT"
    owner.late=type(owner.late)=="table" and owner.late or {}
    -- Deduplicate late observations by composite+quantity, including events
    -- with no operation ID. Never use the journal to produce fixed yields.
    local key=tostring(op or "none")..":"..tostring(data.itemID)..":"..tostring(data.quantity)
    for _,row in ipairs(owner.late) do
        if row.identity==key then return false,"duplicate-late-result" end
    end
    local row={identity=key,recipeID=rid,itemID=data.itemID,quantity=data.quantity,
        operationID=op,status=status,readOnly=true}
    owner.late[#owner.late+1]=row
    owner.lateCount=(tonumber(owner.lateCount) or 0)+1
    while #owner.late>self.maxLatePerTerminal do table.remove(owner.late,1) end
    return true,status
end

function Output:GetLateReview(recipeID,ledgerID)
    local rows=journal()
    for i=#(rows or {}),1,-1 do
        local v=rows[i]
        if (not recipeID or tonumber(recipeID)==v.recipeID) and
           (not ledgerID or ledgerID==v.ledgerID) then
            local recent={}
            for _,r in ipairs(v.late or {}) do
                recent[#recent+1]={recipeID=r.recipeID,itemID=r.itemID,quantity=r.quantity,
                    operationID=r.operationID,status=r.status}
            end
            return {contract=self.lateReviewContract,readOnly=true,nativeDispatchAllowed=false,
                ledgerID=v.ledgerID,recipeID=v.recipeID,originalStatus=v.originalStatus,
                originalConfirmedCrafts=v.confirmedCrafts,
                originalConfirmedOutputUnits=v.originalConfirmedOutputUnits,
                lateReceiptCount=v.lateCount or 0,lateReceipts=recent,
                automaticResume=false,fixedYieldQualified=false}
        end
    end
    return nil
end

function Output:Finalize(pending,confirmed)
    local ledger=JLP:GetModule("TransactionLedger")
    local tx=ledger and ledger.GetTransaction and ledger:GetTransaction(pending.ledgerID) or nil
    local isConfirmed=type(tx)=="table" and tx.kind=="craft" and
        tonumber(tx.recipeID)==tonumber(pending.recipeID) and
        tonumber(tx.confirmedCount)==tonumber(confirmed) and
        tonumber(tx.confirmedCount)>=1
    local summary,receipt=self:Summarize(pending,isConfirmed and confirmed or 0)
    if not isConfirmed then
        summary.status="OUTPUT_TRANSACTION_UNVERIFIED"
        receipt=nil
    end
    local evidence=JLP:GetModule("RecipeOutputEvidence")
    if receipt and pending.ledgerID and evidence and evidence.ObserveCraftResult then
        -- Settlement invokes this once, not the raw item event. The existing
        -- evidence module independently enforces unique operation identity.
        local accepted=evidence:ObserveCraftResult({
            key=pending.key,recipeID=pending.recipeID,recipeName=pending.recipeName,
            ledgerID=pending.ledgerID,confirmedCraftCount=1,
            qualifiedOutputReceipt=true,result=receipt,
        })
        summary.yieldSampleRecorded=accepted==true
    else
        summary.yieldSampleRecorded=false
    end
    self:RememberTerminal(pending,summary)
    return summary
end

JLP:RegisterModule("CraftOutputReconciliation",Output)
