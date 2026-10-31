local _, JLP = ...
-- M5: passive result correlation for all registered professions. This module
-- NEVER authorizes or invokes native crafting. DB2 effects are candidates;
-- only the client's cast+result pair establishes an observed event.
local Journal = {
    contract="JLP-CRAFT-OBSERVATION-70374-1", sourceBuild=70374,
    readOnly=true, nativeDispatchAllowed=false, executionEligible=false,
    pending={}, pendingResults={}, seenCasts={}, pendingLimit=16, historyLimit=60, windowSeconds=12,
}
local function uint(n)
    return type(n)=="number" and n==math.floor(n) and n>0 and n<9007199254740991
end
local function clock()
    if type(GetTime)=="function" then return GetTime() end
    if type(time)=="function" then return time() end
    return nil
end
local function wall()
    if type(time)=="function" then return time() end
    return nil
end
-- Treat a build as an observation session, not as a source selector. An
-- archive's 70374 sourceBuild MUST NOT replace the build observed for a cast.
local function currentSession()
    local b=JLP:GetModule("ClientBuildInfo")
    if not b then return nil end
    local build,token
    if type(b.Read)=="function" then
        local ok,info=pcall(b.Read,b)
        if ok and type(info)=="table" and info.known==true then
            build=info.buildNumber
            token=info.token
        else return nil end
    elseif type(b.GetBuildNumber)=="function" then
        -- Backward-compatible test/older provider. Its token is explicitly
        -- weaker than the full build+interface client identity.
        local ok,n=pcall(b.GetBuildNumber,b)
        if ok then build=n end
    end
    if not uint(build) then return nil end
    if type(token)~="string" or token=="" then
        token="forever:"..tostring(build).."|interface:unknown"
    end
    return {build=build,token=token}
end
local function sameSession(a,b)
    return type(a)=="table" and type(b)=="table" and
        uint(a.build) and a.build==b.build and
        type(a.token)=="string" and a.token==b.token
end
local function identity()
    local ident=JLP:GetModule("CharacterIdentity")
    local key=ident and ident.GetKey and ident:GetKey() or nil
    if type(key)~="string" or key=="" or key=="UnknownRealm:UnknownCharacter" then return nil end
    return key
end
local function store(create)
    local owner=identity()
    if not owner then return nil,"OWNER_UNKNOWN" end
    local db=JLP.DB
    if not db or type(db.account)~="table" then return nil,"DATABASE_UNAVAILABLE" end
    local main=db.account.craftObservation70374
    if type(main)~="table" then
        if not create then return nil,"NO_HISTORY" end
        main={schema=1,characters={}}
        db.account.craftObservation70374=main
    end
    if type(main.characters)~="table" then main.characters={} end
    local target=main.characters[owner]
    if type(target)~="table" then
        if not create then return nil,"NO_HISTORY" end
        target={rows={}}
        main.characters[owner]=target
    end
    if type(target.rows)~="table" then target.rows={} end
    return target
end
local function normalizeResult(payload)
    if type(payload)~="table" then return nil end
    if not uint(payload.itemID) or not uint(payload.quantity) then return nil end
    return {itemID=payload.itemID,quantity=payload.quantity,
        operationID=uint(payload.operationID) and payload.operationID or nil}
end
local function detectedProfessionKeys()
    local api=JLP:GetModule("ProfessionAPI")
    local detected=api and api.GetDetected and api:GetDetected() or {}
    return type(detected)=="table" and detected or {}
end
function Journal:ResolveCandidate(spellID)
    if not uint(spellID) then return nil,"INVALID_SPELL" end
    if not currentSession() then return nil,"CLIENT_BUILD_UNVERIFIED" end
    local ref=JLP:GetModule("Build70374ProfessionReference")
    local registry=JLP:GetModule("ProfessionRegistry")
    if not ref or not registry then return nil,"CATALOGUE_UNAVAILABLE" end
    local detected=detectedProfessionKeys()
    local matched
    for _,key in ipairs(registry:GetKeys()) do
        local observed=detected[key]
        -- A cached profession alone cannot attest to live ownership.
        if type(observed)=="table" and observed.cached~=true then
            local row=ref:GetRecipe(key,spellID,70374)
            if row and row.recordKind=="RECIPE_REFERENCE" and
               type(row.reagents)=="table" and #row.reagents>0 and
               type(row.outputs)=="table" and #row.outputs>0 then
                if matched then return nil,"AMBIGUOUS_PROFESSION" end
                matched={professionKey=key,spellID=spellID,recipeName=row.name,
                    outputs=row.outputs,sourceBuild=70374}
            end
        end
    end
    return matched,matched and nil or "NO_UNAMBIGUOUS_CRAFT_RECIPE"
end
function Journal:Prune(now)
    if not now then self.pending={};self.pendingResults={} return end
    for i=#self.pendingResults,1,-1 do
        local row=self.pendingResults[i]
        if now-row.when>self.windowSeconds or now<row.when then
            table.remove(self.pendingResults,i)
        end
    end
    for i=#self.pending,1,-1 do
        local p=self.pending[i]
        if p.settled or now-p.when>self.windowSeconds or now<p.when then
            table.remove(self.pending,i)
        end
    end
    for guid,t in pairs(self.seenCasts) do
        if now-t>self.windowSeconds or now<t then self.seenCasts[guid]=nil end
    end
end
function Journal:OnSpellcastSucceeded(unit,castGUID,spellID)
    if unit~="player" or type(castGUID)~="string" or castGUID=="" then
        return false,"CAST_IDENTITY_UNAVAILABLE" end
    local t=clock()
    if not t then return false,"CLOCK_UNAVAILABLE" end
    self:Prune(t)
    if self.seenCasts[castGUID] then return false,"DUPLICATE_CAST" end
    local session=currentSession()
    if not session then return false,"CLIENT_BUILD_UNVERIFIED" end
    local candidate,reason=self:ResolveCandidate(tonumber(spellID))
    if not candidate then return false,reason end
    if not sameSession(session,currentSession()) then
        return false,"CLIENT_IDENTITY_CHANGED_DURING_CAST" end
    candidate.clientBuild=session.build
    candidate.clientBuildToken=session.token
    self.seenCasts[castGUID]=t
    candidate.castGUID=castGUID
    candidate.when=t
    self.pending[#self.pending+1]=candidate
    while #self.pending>self.pendingLimit do table.remove(self.pending,1) end
    -- Client event ordering is not assumed. A previously buffered result is
    -- consumed only if this is the sole pending candidate for its output.
    for i=#self.pendingResults,1,-1 do
        local observed=self.pendingResults[i]
        local count=0
        for _,pending in ipairs(self.pending) do
            if pending.clientBuild==session.build and pending.clientBuildToken==session.token and
                observed.clientBuild==session.build and observed.clientBuildToken==session.token then
                for _,output in ipairs(pending.outputs) do
                    if output.itemID==observed.itemID then count=count+1 break end
                end
            end
        end
        if count==1 and observed.clientBuild==session.build and
            observed.clientBuildToken==session.token then
            for _,output in ipairs(candidate.outputs) do
                if output.itemID==observed.itemID then
                    local ok,row=self:OnCraftedResult(observed,true)
                    if ok then
                        table.remove(self.pendingResults,i)
                        return true,"MATCHED_BUFFERED_CLIENT_RESULT",row
                    end
                    break
                end
            end
        end
    end
    return true,"PENDING_CLIENT_RESULT"
end
function Journal:OnCraftedResult(payload,bufferedReconciliation)
    local session=currentSession()
    if not session then return false,"CLIENT_BUILD_UNVERIFIED" end
    local result=normalizeResult(payload)
    if not result then return false,"RESULT_PAYLOAD_UNSUPPORTED" end
    if bufferedReconciliation==true then
        -- These fields belong to the original event; never overwrite them at
        -- reconciliation time, even when its item ID still matches.
        if type(payload)~="table" or
            payload.clientBuild~=session.build or
            payload.clientBuildToken~=session.token then
            return false,"BUFFERED_RESULT_CLIENT_IDENTITY_MISMATCH" end
    end
    result.clientBuild=session.build
    result.clientBuildToken=session.token
    local t=clock()
    if not t then return false,"CLOCK_UNAVAILABLE" end
    self:Prune(t)
    local match,index
    -- Match only an actual output item from the same recent spell candidate.
    -- Multiple concurrent matching candidates are deliberately unresolved.
    for i,p in ipairs(self.pending) do
        if not p.settled then
            for _,output in ipairs(p.outputs) do
                if output.itemID==result.itemID then
                    if p.clientBuild~=session.build or p.clientBuildToken~=session.token then
                        return false,"CAST_RESULT_CLIENT_IDENTITY_MISMATCH" end
                    if match then return false,"AMBIGUOUS_RESULT_CORRELATION" end
                    match,index=p,i
                    break
                end
            end
        end
    end
    if not match then
        -- Hold a small transient result buffer (not SavedVariables). Never
        -- mark a result as history without a uniquely matching player cast.
        result.when=t
        local duplicate=false
        for _,old in ipairs(self.pendingResults) do
            if result.operationID and old.operationID==result.operationID and
               result.itemID==old.itemID then duplicate=true break end
        end
        if not duplicate then
            self.pendingResults[#self.pendingResults+1]=result
            while #self.pendingResults>self.pendingLimit do table.remove(self.pendingResults,1) end
        end
        return false,"RESULT_AWAITING_CAST"
    end
    if not sameSession(session,currentSession()) then
        return false,"CLIENT_IDENTITY_CHANGED_DURING_RESULT" end
    local target,reason=store(true)
    if not target then return false,reason end
    local rid=match.castGUID..":"..tostring(result.operationID or "no-operation")
    for _,row in ipairs(target.rows) do
        if row.id==rid then return false,"DUPLICATE_CRAFT_RESULT" end
    end
    local row={
        id=rid,professionKey=match.professionKey,spellID=match.spellID,
        recipeID=match.spellID,recipeName=match.recipeName,
        status="observed_result",evidence="CAST_AND_OUTPUT_EVENT_MATCHED",
        source="CLIENT_EVENTS_70374",outputItemID=result.itemID,
        outputQuantity=result.quantity,operationID=result.operationID,
        castGUID=match.castGUID,finishedAt=wall(),sourceBuild=70374,
        observedClientBuild=session.build,observedClientBuildToken=session.token,
        observationBuildState="LIVE_SESSION_CORRELATED",
        -- A craft result's item quantity does NOT certify cast count or skill gain.
        confirmedCount=nil,requestedCount=nil,skillGain=nil,readOnly=true,
    }
    target.rows[#target.rows+1]=row
    while #target.rows>self.historyLimit do table.remove(target.rows,1) end
    table.remove(self.pending,index)
    if JLP.EventBus then JLP.EventBus:Emit("CRAFT_OBSERVATION_JOURNAL_UPDATED",row.professionKey) end
    return true,row
end
function Journal:GetHistory(limit,key)
    local registry=JLP:GetModule("ProfessionRegistry")
    if key~=nil then
        key=registry and registry:NormalizeKey(key)
        if not key then return nil,"UNKNOWN_PROFESSION" end
    end
    local target=store(false)
    local out={}
    for i=#(target and target.rows or {}),1,-1 do
        local r=target.rows[i]
        if type(r)=="table" and (key==nil or r.professionKey==key) then
            out[#out+1]={id=r.id,key=r.professionKey,recipeID=r.recipeID,
                recipeName=r.recipeName,status=r.status,evidence=r.evidence,
                source=r.source,finishedAt=r.finishedAt,outputItemID=r.outputItemID,
                outputQuantity=r.outputQuantity,operationID=r.operationID,
                castGUID=r.castGUID,observedClientBuild=r.observedClientBuild,
                observedClientBuildToken=r.observedClientBuildToken,
                observationBuildState=(uint(r.observedClientBuild) and
                    type(r.observedClientBuildToken)=="string") and
                    "LIVE_SESSION_CORRELATED" or "LEGACY_BUILD_UNVERIFIED",
                readOnly=true,kind="observed-craft-result",sourceBuild=70374}
        end
        if #out>=math.max(1,math.min(100,math.floor(tonumber(limit) or 40))) then break end
    end
    return out
end
function Journal:GetSummary(key)
    local rows,err=self:GetHistory(100,key)
    if not rows then return "Craft observations: "..tostring(err) end
    return string.format("M5 crafting history: %d recorded client-correlated result(s)%s. Cast-only events and ambiguous output are excluded; no native dispatch.",
        #rows,key and (" for "..key) or "")
end
JLP:RegisterModule("CraftObservationJournal70374",Journal)
