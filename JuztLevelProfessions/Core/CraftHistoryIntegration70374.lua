local _,JLP=...
-- Shared, read-only, build-aware history facade. Keep the public module name
-- for old UI consumers; 70374 observations remain historical, 70450 is current.
-- Suppress passive rows ONLY with an exact confirmed ledger cast identity.
-- A nearby timestamp/recipe name is never proof of duplication.
local History={contract="JLP-UNIFIED-CRAFT-HISTORY-BUILD-AWARE-2",
    readOnly=true,nativeDispatchAllowed=false,productionAuthority=false}
local function asNum(n) return tonumber(n) or 0 end
local function proofIndex(ledger)
    local proof,byID={},{}
    if not ledger or not ledger.GetTransactions then return proof,byID end
    for _,tx in ipairs(ledger:GetTransactions() or {}) do
        if type(tx)=="table" and tx.id then
            byID[tostring(tx.id)]=tx
            for _,unit in pairs(tx.units or {}) do
                if type(unit)=="table" and unit.state=="confirmed" then
                    for _,e in ipairs(unit.evidence or {}) do
                        local guid=type(e.key)=="string" and e.key:match("^cast:(.+)$") or nil
                        if guid and guid~="" then
                            local version=tonumber(tx.buildProvenance and tx.buildProvenance.build)
                            if version then
                                proof[table.concat({tostring(version),tostring(tx.key or ""),
                                    tostring(tx.recipeID or ""),guid},"|")]=true
                            end
                        end
                    end
                end
            end
        end
    end
    return proof,byID
end
local function withOutputObservations(row,tx)
    if not tx then return end
    row.sourceBuild=tonumber(tx.buildProvenance and tx.buildProvenance.build)
    row.observedOutputEvents=0
    row.observedOutputItems={}
    local seen={}
    for _,unit in pairs(tx.units or {}) do
        for _,e in ipairs(type(unit)=="table" and unit.evidence or {}) do
            local d=e and e.data
            if type(d)=="table" and tostring(e.type or ""):find("crafted-result",1,true) then
                local item,quantity=tonumber(d.itemID),tonumber(d.quantity)
                local id=type(e.key)=="string" and e.key or nil
                if item and item>0 and quantity and quantity>0 and id and not seen[id] then
                    seen[id]=true
                    row.observedOutputEvents=row.observedOutputEvents+1
                    row.observedOutputItems[#row.observedOutputItems+1]={itemID=item,quantity=quantity,
                        evidence="LEDGER_CLIENT_RESULT_ASSOCIATED_NOT_ORDINAL_PROOF"}
                end
            end
        end
    end
end
function History:GetHistory(limit,key)
    limit=math.max(1,math.min(150,math.floor(tonumber(limit) or 40)))
    local reg=JLP:GetModule("ProfessionRegistry")
    if key~=nil then
        key=reg and reg.NormalizeKey and reg:NormalizeKey(key) or nil
        if not key then return nil,"UNKNOWN_PROFESSION" end
    end
    local tracker=JLP:GetModule("ProgressTracker")
    local ledger=JLP:GetModule("TransactionLedger")
    local managed=tracker and tracker.GetCraftHistory and tracker:GetCraftHistory(100) or {}
    local proof,txByID=proofIndex(ledger)
    local result={}
    for _,r in ipairs(managed or {}) do
        if type(r)=="table" and (not key or key==r.key) then
            local row={}
            for k,v in pairs(r) do row[k]=v end
            row.kind=row.kind or "managed-transaction"
            row.evidence="GUARDED_TRANSACTION_LEDGER"
            row.readOnly=true
            local tx=txByID[tostring(row.id or "")]
            withOutputObservations(row,tx)
            result[#result+1]=row
        end
    end
    for _,moduleName in ipairs({"CraftObservationJournal70450","CraftObservationJournal70374"}) do
        local journal=JLP:GetModule(moduleName)
        local observed=journal and journal.GetHistory and journal:GetHistory(150,key) or {}
        for _,r in ipairs(observed or {}) do
            if type(r)=="table" and (not r.castGUID or not proof[table.concat({
                tostring(r.sourceBuild or ""),tostring(r.key or ""),
                tostring(r.recipeID or ""),tostring(r.castGUID)},"|")]) then
                local row={}
                for k,v in pairs(r) do row[k]=v end
                row.readOnly=true
                row.productionAuthority=false
                result[#result+1]=row
            end
        end
    end
    table.sort(result,function(a,b)
        local x,y=asNum(a.finishedAt),asNum(b.finishedAt)
        if x==y then return tostring(a.id or "")>tostring(b.id or "") end
        return x>y
    end)
    while #result>limit do table.remove(result) end
    return result
end
function History:GetSummary(key)
    local rows,err=self:GetHistory(150,key)
    if not rows then return tostring(err) end
    local managed,observed=0,0
    for _,r in ipairs(rows) do
        if r.status=="observed_result" then observed=observed+1 else managed=managed+1 end
    end
    return string.format("Craft history%s: %d guarded transaction(s), %d independently correlated passive output event(s). Exact confirmed cast GUIDs are deduplicated; passive quantities are not craft counts.",
        key and (" ("..key..")") or "",managed,observed)
end
JLP:RegisterModule("CraftHistoryIntegration70374",History)
