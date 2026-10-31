local _, JLP = ...
-- Build-bound, passive observation only. This module never confirms a native
-- transaction, modifies recipe authority, or infers a craft from a DB2 effect.
local Journal = {
    contract="JLP-CRAFT-OBSERVATION-70450-1", sourceBuild=70450,
    readOnly=true, nativeDispatchAllowed=false, executionEligible=false,
    productionAuthority=false, pending={}, pendingResults={}, seenCasts={},
    pendingLimit=24, historyLimit=150, windowSeconds=12, replayWindow=4,
    recentAnonymous={}, beforeCraft=nil, awaitingSkill=nil,
    eventTraceLimit=24, eventSequence=0,
}
local function positive(v)
    return type(v)=="number" and v==math.floor(v) and v>0 and v<9007199254740991
end
local function elapsed()
    if type(GetTime)=="function" then
        local ok,v=pcall(GetTime)
        if ok and type(v)=="number" and v==v and v>=0 and v<math.huge then return v end
    end
    return nil
end
local function epoch()
    if type(time)=="function" then
        local ok,v=pcall(time)
        if ok and type(v)=="number" then return v end
    end
    return nil
end
local function buildOK()
    local info=JLP:GetModule("ClientBuildInfo")
    local n=info and info.GetBuildNumber and info:GetBuildNumber()
    return type(n)=="number" and n>0 and n==math.floor(n) and n<math.huge
end
-- Optional fine-grained live identity, including interface version. If the
-- provider only exposes GetBuildNumber, the existing numeric build fence still
-- applies, but no full interface attestation is claimed.
local function clientSessionToken()
    local b=JLP:GetModule("ClientBuildInfo")
    if not b or type(b.Read)~="function" then return nil end
    local ok,info=pcall(b.Read,b)
    if not ok or type(info)~="table" or info.known~=true or
        type(info.token)~="string" or info.token=="" then return nil end
    return info.token
end
local function owner()
    local m=JLP:GetModule("CharacterIdentity")
    local id=m and m.GetKey and m:GetKey() or nil
    return type(id)=="string" and id~="" and id~="UnknownRealm:UnknownCharacter" and id or nil
end
local function stored(create)
    local key=owner()
    if not key then return nil,"OWNER_UNKNOWN" end
    if not JLP.DB or type(JLP.DB.account)~="table" then return nil,"DATABASE_UNAVAILABLE" end
    local root=JLP.DB.account.craftObservation70450
    if type(root)~="table" then
        if not create then return nil,"NO_HISTORY" end
        root={schema=1,characters={}}
        JLP.DB.account.craftObservation70450=root
    end
    if type(root.characters)~="table" then root.characters={} end
    local entry=root.characters[key]
    if type(entry)~="table" then
        if not create then return nil,"NO_HISTORY" end
        entry={rows={}}
        root.characters[key]=entry
    end
    if type(entry.rows)~="table" then entry.rows={} end
    return entry
end
local function normalize(payload)
    if type(payload)~="table" then return nil,"RESULT_NOT_A_TABLE" end
    local item=tonumber(payload.itemID)
    local qty=tonumber(payload.quantity)
    if not positive(item) or not positive(qty) then return nil,"RESULT_ITEM_OR_QUANTITY_UNVERIFIED" end
    local op=tonumber(payload.operationID)
    if not positive(op) then op=nil end
    local guid=payload.itemGUID
    if type(guid)~="string" or guid=="" then guid=nil end
    local explicitID=payload.recipeID or payload.spellID or payload.craftingSpellID
    if explicitID~=nil and not positive(tonumber(explicitID)) then
        return nil,"RESULT_RECIPE_IDENTITY_INVALID" end
    return {itemID=item,quantity=qty,operationID=op,itemGUID=guid,
        recipeID=explicitID~=nil and tonumber(explicitID) or nil}
end
local function resultIdentity(result)
    if result.operationID then return "op:"..result.operationID..":item:"..result.itemID end
    if result.itemGUID then return "itemguid:"..result.itemGUID..":item:"..result.itemID end
    return nil
end
local function exactMatch(p,itemID)
    for _,out in ipairs(p.outputs or {}) do
        if tonumber(out.itemID)==itemID then return true end
    end
    return false
end
function Journal:ResolveCandidate(spellID)
    if not positive(spellID) then return nil,"INVALID_SPELL_ID" end
    if not buildOK() then return nil,"CLIENT_BUILD_UNVERIFIED" end
    local api=JLP:GetModule("ProfessionAPI")
    local reg=JLP:GetModule("ProfessionRegistry")
    local catalogue=JLP:GetModule("Build70450RecipeCatalogue")
    if not api or not reg or not catalogue then return nil,"CATALOGUE_UNAVAILABLE" end
    local detected=api.GetDetected and api:GetDetected() or nil
    if type(detected)~="table" then return nil,"LIVE_PROFESSION_UNAVAILABLE" end
    local matched
    for _,key in ipairs(reg:GetKeys()) do
        local current=detected[key]
        if type(current)=="table" and current.cached~=true then
            local row=catalogue:GetRecipe(key,spellID,70450)
            if row and row.recordKind=="RECIPE_CANDIDATE" and row.readOnly==true and
                row.sourceBuild==70450 and row.professionKey==key and
                type(row.outputs)=="table" and #row.outputs>0 then
                if matched then return nil,"AMBIGUOUS_PROFESSION" end
                matched={professionKey=key,spellID=spellID,recipeName=row.name,
                    outputs=row.outputs,sourceBuild=70450}
            end
        end
    end
    return matched,matched and nil or "NO_UNAMBIGUOUS_ITEM_OUTPUT_CANDIDATE"
end
-- Bounded, passive diagnostics for user-supplied Forever client evidence.
-- An event snapshot is NOT a verified skill-up/no-gain or crafting authorization.
-- Persist only primitive observation fields; never persist OpenProfessionContext.
local function appendTrace(self, target, event, t, skill, detail, verified, ctx)
    if not target then return end
    local trace=target.eventTrace
    if type(trace)~="table" then trace={};target.eventTrace=trace end
    if #trace>=self.eventTraceLimit then
        target.eventTraceTruncated=true
        return
    end
    self.eventSequence=(self.eventSequence or 0)+1
    trace[#trace+1]={event=event, elapsed=t, epoch=epoch(), skill=skill,
        sequence=self.eventSequence, origin=(event=="TRADE_SKILL_CRAFT_BEGIN" or
            event=="UNIT_SPELLCAST_SUCCEEDED" or event=="TRADE_SKILL_ITEM_CRAFTED_RESULT" or
            event=="SKILL_LINES_CHANGED" or event=="TRADE_SKILL_UPDATE" or
            event=="TRADE_SKILL_LIST_UPDATE" or event=="CHAT_MSG_SKILL") and
            "CLIENT_EVENT" or "INTERNAL_STATE",
        panelVerified=verified==true, detail=detail,
        panelToken=ctx and ctx.panelToken or nil,
        panelRevision=ctx and ctx.panelRevision or nil,
        characterKey=ctx and ctx.characterKey or nil,
        build=ctx and ctx.build or nil,
        professionEnum=ctx and ctx.professionEnum or nil}
end
-- Merge a buffered raw client result at its original receipt position. The
-- later correlation is NOT a second client callback. Stable sequence, rather
-- than processing time, preserves equal-timestamp callback ordering.
local function mergeRawTrace(self,target,original)
    if type(original)~="table" then return end
    if type(target.eventTrace)~="table" then target.eventTrace={} end
    if #target.eventTrace>=self.eventTraceLimit then
        target.eventTraceTruncated=true;return end
    local seq=original.sequence or math.huge
    local i=#target.eventTrace+1
    while i>1 and (target.eventTrace[i-1].sequence or 0)>seq do
        target.eventTrace[i]=target.eventTrace[i-1];i=i-1
    end
    target.eventTrace[i]=original
end
local function tracePanel()
    -- Evaluated later via the same verified Tailoring context contract.
    local api=JLP:GetModule("ProfessionAPI")
    local ctx=api and api.GetOpenProfessionContext and api:GetOpenProfessionContext()
    if ctx and ctx.verified==true and ctx.professionKey=="TAILORING" and
       ctx.baseSkillLineID==197 and ctx.professionEnum==7 and
       ctx.characterKey==owner() and buildOK() and
       type(ctx.skill)=="number" and ctx.skill==math.floor(ctx.skill) then
        return ctx.skill,true,ctx
    end
    return nil,false,nil
end
-- Expiry changes the persisted observation status, NEVER its skillGain. A
-- delayed event cannot revive an old successful cast/output correlation.
local function expireAwaiting(self, reason)
    local pending=self.awaitingSkill
    if pending then
        local row=pending.row
        if row and row.skillGain==nil then
            appendTrace(self,row,"OBSERVATION_EXPIRED",elapsed(),nil,reason,false)
            row.skillObservationStatus="UNKNOWN_BEFORE_OR_AFTER"
            row.skillObservationReason=reason
        end
    end
    self.awaitingSkill=nil
end
function Journal:Prune(t)
    if type(t)~="number" or t~=t or t<0 or t==math.huge then
        expireAwaiting(self,"SKILL_OBSERVATION_CLOCK_INVALID")
        self.pending={};self.pendingResults={};self.seenCasts={}
        self.recentAnonymous={};self.beforeCraft=nil
        return
    end
    for _,list in ipairs({self.pending,self.pendingResults}) do
        for i=#list,1,-1 do
            local r=list[i]
            if t<r.when or t-r.when>self.windowSeconds then table.remove(list,i) end
        end
    end
    for k,v in pairs(self.seenCasts) do
        if t<v or t-v>self.windowSeconds then self.seenCasts[k]=nil end
    end
    if self.beforeCraft and (t<self.beforeCraft.when or t-self.beforeCraft.when>self.windowSeconds) then self.beforeCraft=nil end
    if self.awaitingSkill and (t<self.awaitingSkill.when or t-self.awaitingSkill.when>self.windowSeconds) then
        expireAwaiting(self, t<self.awaitingSkill.when and
            "SKILL_OBSERVATION_CLOCK_REGRESSION" or "SKILL_OBSERVATION_WINDOW_EXPIRED")
    end
    for k,v in pairs(self.recentAnonymous) do
        if t<v or t-v>self.replayWindow then self.recentAnonymous[k]=nil end
    end
end
-- All skill evidence is passive. GetBaseProfessionInfo provides an observed
-- panel skill but only its validated 70450 OpenProfessionContext may establish
-- character, profession, enum and panel-session identity.
local function tailoringPanel()
    if not buildOK() then return nil,"CLIENT_BUILD_UNVERIFIED" end
    local api=JLP:GetModule("ProfessionAPI")
    local ctx=api and api.GetOpenProfessionContext and api:GetOpenProfessionContext()
    if not ctx or ctx.verified~=true or ctx.professionKey~="TAILORING" or
        tonumber(ctx.baseSkillLineID)~=197 or ctx.professionEnum~=7 or
        type(ctx.panelToken)~="string" or type(ctx.panelRevision)~="number" or
        ctx.characterKey~=owner() or not buildOK() or
        ctx.build~=(JLP:GetModule("ClientBuildInfo") and JLP:GetModule("ClientBuildInfo"):GetBuildNumber()) then
        return nil,"IDENTITY_CONFLICT" end
    local skill=ctx.skill
    if type(skill)~="number" or skill~=skill or skill<0 or skill~=math.floor(skill) then
        return nil,"UNKNOWN_BEFORE_OR_AFTER" end
    if type(ctx.maxSkill)~="number" or ctx.maxSkill<skill or
        ctx.maxSkill~=math.floor(ctx.maxSkill) then
        return nil,"SKILL_RANK_UNVERIFIED" end
    return ctx
end
local function samePanel(a,b)
    return a and b and a.characterKey==b.characterKey and
        a.panelToken==b.panelToken and a.panelRevision==b.panelRevision and
        a.build==b.build and a.professionKey==b.professionKey and
        a.baseSkillLineID==b.baseSkillLineID and a.professionEnum==b.professionEnum
end
-- The BEGIN event is the only pre-action sampling point. Never reconstruct
-- a missing before-value from a post-craft GetDetected or persisted history.
function Journal:OnCraftBegin(recipeID)
    local t=elapsed();if not t then self:Prune(nil);return false,"CLOCK_UNAVAILABLE" end
    self:Prune(t)
    local ctx,reason=tailoringPanel()
    if not ctx then return false,reason end
    local id=tonumber(recipeID)
    if not positive(id) then return false,"INVALID_RECIPE_ID" end
    local infoAPI=C_TradeSkillUI
    local ok,info=false,nil
    if type(infoAPI)=="table" and type(infoAPI.GetRecipeInfo)=="function" then
        ok,info=pcall(infoAPI.GetRecipeInfo,id)
    end
    if not ok or type(info)~="table" or info.learned~=true then
        return false,"RECIPE_LEARNED_NOT_CURRENTLY_VERIFIED" end
    if info.relativeDifficulty==3 then
        return false,"GRAY_RECIPE_CANNOT_AUTHORIZE_SKILL_GAIN" end
    if type(info.relativeDifficulty)~="number" or
        info.relativeDifficulty~=math.floor(info.relativeDifficulty) or
        info.relativeDifficulty<0 or info.relativeDifficulty>2 then
        return false,"RECIPE_DIFFICULTY_UNVERIFIED" end
    local candidate,err=self:ResolveCandidate(id)
    if not candidate or candidate.professionKey~="TAILORING" then
        return false,err or "RECIPE_IDENTITY_UNQUALIFIED" end
    if self.beforeCraft or self.awaitingSkill or #self.pending>0 then
        if self.beforeCraft then self.beforeCraft.conflict="EVENT_CORRELATION_CONFLICT" end
        if self.awaitingSkill then
            self.awaitingSkill.row.skillObservationStatus="EVENT_CORRELATION_CONFLICT"
            self.awaitingSkill.row.skillGain=nil
        end
        -- A second BEGIN invalidates all unresolved exact-ID correlations.
        for _,pending in ipairs(self.pending) do
            pending.skillBefore=nil
            pending.skillPanel=nil
            pending.skillObservationReason="EVENT_CORRELATION_CONFLICT"
        end
        self.beforeCraft=nil;self.awaitingSkill=nil
        return false,"EVENT_CORRELATION_CONFLICT"
    end
    self.beforeCraft={recipeID=id,skill=ctx.skill,ctx=ctx,when=t,eventTrace={}}
    appendTrace(self,self.beforeCraft,"TRADE_SKILL_CRAFT_BEGIN",t,ctx.skill,
        "VERIFIED_BEFORE_SNAPSHOT",true,ctx)
    return true,"BEFORE_SKILL_OBSERVED"
end
function Journal:OnPanelLifecycle(reason)
    if self.awaitingSkill then
        appendTrace(self,self.awaitingSkill.row,reason or "PANEL_LIFECYCLE",elapsed(),
            nil,"SESSION_INVALIDATED",false)
    end
    if self.awaitingSkill and self.awaitingSkill.row.skillGain==nil then
        self.awaitingSkill.row.skillObservationStatus="IDENTITY_CONFLICT"
        self.awaitingSkill.row.skillObservationReason=reason or "PANEL_OR_SESSION_CHANGED"
    end
    for _,pending in ipairs(self.pending) do
        pending.skillBefore=nil
        pending.skillPanel=nil
        pending.skillObservationReason="IDENTITY_CONFLICT"
    end
    self.beforeCraft=nil;self.awaitingSkill=nil
end
-- A zero is qualified only by an actual post-result skill refresh, never by
-- the absence of SKILL_LINES_CHANGED. This function accepts only skill-related
-- event names already registered by Core.lua, not inventory or chat messages.
function Journal:OnSkillUpdate(event,internalReconciliation)
    if event~="SKILL_LINES_CHANGED" and event~="TRADE_SKILL_UPDATE" then
        return false,"NOT_A_SKILL_OBSERVATION" end
    -- A quiet session receives no periodic prune: EVERY arriving skill event
    -- must verify age/clock BEFORE it may qualify any old craft sample.
    local t=elapsed()
    if not t then
        self:Prune(nil)
        return false,"SKILL_OBSERVATION_CLOCK_INVALID"
    end
    local stale=self.awaitingSkill and (t<self.awaitingSkill.when or
        t-self.awaitingSkill.when>self.windowSeconds)
    self:Prune(t)
    if stale then return false,"SKILL_OBSERVATION_WINDOW_EXPIRED_OR_CLOCK_REGRESSION" end
    local awaiting=self.awaitingSkill
    if not awaiting then
        -- Forever may emit skill-line refresh before the crafted-item result.
        -- Keep a transient post-cast sample, and qualify it ONLY if the exact
        -- cast later acquires one unique crafted-result event.
        if #self.pending~=1 or self.beforeCraft then
            return false,"NO_CORRELATED_CRAFT_PENDING_SKILL" end
        local pending=self.pending[1]
        local diagSkill,diagOK,diagCtx=tracePanel()
        if not internalReconciliation then
            appendTrace(self,pending,event,t,diagSkill,"BEFORE_CRAFT_RESULT",diagOK,diagCtx)
        end
        if pending.professionKey~="TAILORING" or pending.skillBefore==nil then
            return false,"UNKNOWN_BEFORE_OR_AFTER" end
        local ctx,why=tailoringPanel()
        if not ctx or not samePanel(pending.skillPanel,ctx) then
            pending.skillBefore=nil
            pending.skillObservationReason=why=="UNKNOWN_BEFORE_OR_AFTER" and
                "UNKNOWN_BEFORE_OR_AFTER" or "IDENTITY_CONFLICT"
            return false,pending.skillObservationReason end
        if ctx.skill==pending.skillBefore then
            -- A pre-result zero is not evidence that the craft completed.
            return false,"CRAFT_RESULT_STILL_PENDING"
        end
        if ctx.skill<pending.skillBefore or ctx.skill-pending.skillBefore>1 then
            pending.skillBefore=nil
            pending.skillObservationReason="EVENT_CORRELATION_CONFLICT"
            return false,"EVENT_CORRELATION_CONFLICT"
        end
        if pending.preResultSkillAfter~=nil then
            if pending.preResultSkillAfter~=ctx.skill then
                pending.skillBefore=nil
                pending.skillObservationReason="EVENT_CORRELATION_CONFLICT"
                return false,"EVENT_CORRELATION_CONFLICT" end
            return false,"DUPLICATE_SKILL_OBSERVATION"
        end
        pending.preResultSkillAfter=ctx.skill
        pending.preResultSkillEvent=event
        pending.preResultSkillWhen=t
        pending.preResultSkillEpoch=epoch()
        return true,"POST_CAST_SKILL_SAMPLE_AWAITING_RESULT"
    end
    local row=awaiting.row
    local diagSkill,diagOK,diagCtx=tracePanel()
    -- Internally replaying an earlier sample must never invent another
    -- SKILL_LINES_CHANGED callback or change its original client timestamp.
    if not internalReconciliation then
        appendTrace(self,row,event,t,diagSkill,"AFTER_CRAFT_RESULT",diagOK,diagCtx)
    end
    if row.skillObservationStatus=="OBSERVED_GAIN" or row.skillObservationStatus=="OBSERVED_NO_GAIN" then
        return false,"ALREADY_QUALIFIED" end
    if self.beforeCraft or #self.pending>0 then
        row.skillObservationStatus="EVENT_CORRELATION_CONFLICT"
        row.skillGain=nil;self.awaitingSkill=nil
        return false,"EVENT_CORRELATION_CONFLICT" end
    local ctx,reason=tailoringPanel()
    if not ctx or not samePanel(awaiting.ctx,ctx) then
        row.skillObservationStatus=reason=="UNKNOWN_BEFORE_OR_AFTER" and
            "UNKNOWN_BEFORE_OR_AFTER" or "IDENTITY_CONFLICT"
        row.skillObservationReason=reason or "PANEL_OR_SESSION_CHANGED"
        row.skillGain=nil;self.awaitingSkill=nil
        return false,row.skillObservationStatus end
    if type(row.skillBefore)~="number" then
        row.skillObservationStatus="UNKNOWN_BEFORE_OR_AFTER"
        self.awaitingSkill=nil
        return false,"UNKNOWN_BEFORE_OR_AFTER" end
    local delta=ctx.skill-row.skillBefore
    if delta<0 or delta>1 then
        -- A single result cannot claim multiple skillpoints or unrelated gain.
        row.skillObservationStatus="EVENT_CORRELATION_CONFLICT"
        row.skillObservationReason="SKILL_DELTA_NOT_UNIQUELY_ATTRIBUTABLE"
        row.skillGain=nil;self.awaitingSkill=nil
        return false,"EVENT_CORRELATION_CONFLICT" end
    if delta==0 then
        -- Neither TRADE_SKILL_UPDATE nor SKILL_LINES_CHANGED has been proven
        -- to be the FINAL no-gain boundary in Forever 70450. A temporary
        -- unchanged value is a refresh, not a certified negative result.
        -- Keep the correlation live for a later actual positive event.
        row.skillObservationStatus="UNKNOWN_BEFORE_OR_AFTER"
        row.skillObservationReason="PROVISIONAL_ZERO_REFRESH_NOT_FINAL"
        row.skillGain=nil
        return false,"PROVISIONAL_ZERO_REFRESH_NOT_FINAL",row
    end
    row.skillAfter=ctx.skill;row.skillGain=delta
    row.skillObservationStatus="OBSERVED_GAIN"
    row.skillObservationReason=nil
    row.skillObservationEvent=event;row.skillObservationSource="CURRENT_PANEL_SKILL_AFTER_CLIENT_EVENT"
    row.skillObservedAt=internalReconciliation and row.preResultSkillEpoch or epoch()
    row.skillObservedElapsed=internalReconciliation and row.preResultSkillWhen or t
    self.awaitingSkill=nil
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("CRAFT_OBSERVATION_JOURNAL_UPDATED",row.professionKey)
    end
    return true,row.skillObservationStatus,row
end

-- Optional auxiliary events are diagnostic only. No chat text or API
-- payloads are saved, and these observations never finalize skillGain.
function Journal:ObserveAuxiliaryEvent(event)
    if event~="CHAT_MSG_SKILL" and event~="TRADE_SKILL_LIST_UPDATE" then
        return false,"NOT_A_DIAGNOSTIC_EVENT"
    end
    local t=elapsed()
    if not t then self:Prune(nil);return false,"CLOCK_UNAVAILABLE" end
    self:Prune(t)
    local target=self.awaitingSkill and self.awaitingSkill.row or
        (#self.pending==1 and self.pending[1] or nil)
    if not target or (target.professionKey and target.professionKey~="TAILORING") then
        return false,"NO_CORRELATED_CRAFT"
    end
    local skill,verified,ctx=tracePanel()
    appendTrace(self,target,event,t,skill,"DIAGNOSTIC_ONLY",verified,ctx)
    return true,"DIAGNOSTIC_EVENT_RECORDED"
end
local function previouslyCommitted(rows,castGUID,resultID)
    for _,row in ipairs(rows) do
        if row.castGUID==castGUID or (resultID and row.resultIdentity==resultID) then return true end
    end
    return false
end
function Journal:OnSpellcastSucceeded(unit,castGUID,spellID)
    if unit~="player" or type(castGUID)~="string" or castGUID=="" then
        return false,"CAST_IDENTITY_UNAVAILABLE" end
    local t=elapsed();if not t then self:Prune(nil);return false,"CLOCK_UNAVAILABLE" end
    self:Prune(t)
    if self.seenCasts[castGUID] then return false,"DUPLICATE_CAST" end
    local db=stored(false)
    if db and previouslyCommitted(db.rows,castGUID,nil) then return false,"PERSISTED_DUPLICATE_CAST" end
    local candidate,reason=self:ResolveCandidate(tonumber(spellID))
    if not candidate then return false,reason end
    local ownerKey=owner()
    if not ownerKey then return false,"OWNER_UNKNOWN" end
    candidate.ownerKey=ownerKey
    -- Capture the CLIENT build on receipt of this cast. A later build change
    -- must never reinterpret an old cast using another build's output policy.
    local buildModule=JLP:GetModule("ClientBuildInfo")
    local castBuild=buildModule and buildModule.GetBuildNumber and buildModule:GetBuildNumber()
    if not positive(castBuild) then return false,"CLIENT_BUILD_UNVERIFIED" end
    candidate.clientBuild=castBuild
    candidate.clientBuildToken=clientSessionToken()
    candidate.castGUID=castGUID;candidate.when=t
    if candidate.professionKey=="TAILORING" then
        local before=self.beforeCraft
        self.beforeCraft=nil
        if before and before.recipeID==candidate.spellID and not before.conflict and
            t>=before.when and t-before.when<=self.windowSeconds then
            local ctx=tailoringPanel()
            if ctx and samePanel(before.ctx,ctx) and ctx.skill==before.skill and
                #self.pending==0 and not self.awaitingSkill then
                candidate.skillBefore=before.skill;candidate.skillPanel=before.ctx
                candidate.eventTrace=before.eventTrace
            else candidate.skillObservationReason="IDENTITY_CONFLICT_OR_CONCURRENT_CRAFT" end
        else candidate.skillObservationReason="UNKNOWN_BEFORE_OR_AFTER" end
    end
    if candidate.professionKey=="TAILORING" then
        local skill,verified,ctx=tracePanel()
        appendTrace(self,candidate,"UNIT_SPELLCAST_SUCCEEDED",t,skill,
            "CAST_GUID_OBSERVED",verified,ctx)
    end
    self.seenCasts[castGUID]=t
    self.pending[#self.pending+1]=candidate
    while #self.pending>self.pendingLimit do table.remove(self.pending,1) end
    -- Results may arrive before the spellcast event. Only resolve when one
    -- matching cast exists; never pick an arbitrary candidate.
    for i=#self.pendingResults,1,-1 do
        local r=self.pendingResults[i]
        local clientBuildModule=JLP:GetModule("ClientBuildInfo")
        local liveBuild=clientBuildModule and clientBuildModule:GetBuildNumber()
        if r.clientBuild==castBuild and castBuild==liveBuild and
            r.clientBuildToken==candidate.clientBuildToken and
            candidate.clientBuildToken==clientSessionToken() and
            exactMatch(candidate,r.itemID) and
            (r.recipeID==nil or r.recipeID==candidate.spellID) then
            local count=0
            for _,p in ipairs(self.pending) do
                if p.clientBuild==liveBuild and
                    p.clientBuildToken==candidate.clientBuildToken and
                    exactMatch(p,r.itemID) and
                    (r.recipeID==nil or r.recipeID==p.spellID) then count=count+1 end
            end
            if count==1 then
                table.remove(self.pendingResults,i)
                local ok,row=self:OnCraftedResult(r,true)
                if ok then return true,"MATCHED_BUFFERED_RESULT",row end
            end
        end
    end
    return true,"PENDING_RESULT"
end
function Journal:OnCraftedResult(payload,bufferedReconciliation)
    if not buildOK() then return false,"CLIENT_BUILD_UNVERIFIED" end
    -- Targeted enchants modify an existing target, not a new inventory item.
    -- Their native ledger is the authority for a confirmed Enchant One.
    if type(payload)=="table" and payload.isEnchant==true then
        return false,"TARGET_ENCHANT_NO_SEPARATE_ITEM_OUTPUT"
    end
    local result,reason
    if bufferedReconciliation==true and type(payload)=="table" and
        type(payload.when)=="number" and type(payload.bufferedEventTrace)=="table" then
        -- Only the internal buffer re-entry carries receipt provenance.
        result=payload
    else
        result,reason=normalize(payload)
    end
    if not result then return false,reason end
    local t=elapsed();if not t then self:Prune(nil);return false,"CLOCK_UNAVAILABLE" end
    self:Prune(t)
    local clientBuildModule=JLP:GetModule("ClientBuildInfo")
    local liveBuild=clientBuildModule and clientBuildModule:GetBuildNumber()
    if not positive(liveBuild) then return false,"CLIENT_BUILD_UNVERIFIED" end
    local liveToken=clientSessionToken()
    if bufferedReconciliation==true then
        -- The raw result's original build was captured when the callback
        -- arrived. Internal reconciliation must not rewrite its provenance.
        if not positive(result.clientBuild) then
            return false,"BUFFERED_RESULT_BUILD_UNVERIFIED" end
        if result.clientBuild~=liveBuild then
            return false,"BUFFERED_RESULT_BUILD_MISMATCH" end
        if result.clientBuildToken~=liveToken then
            return false,"BUFFERED_RESULT_CLIENT_SESSION_MISMATCH" end
    else
        result.clientBuild=liveBuild
        result.clientBuildToken=liveToken
    end
    -- A result without a recipe ID is passive evidence only. On EVERY build
    -- it must correlate to one matching pending cast/output and obey the same
    -- unique-result, session-build and replay fences. An explicit conflicting
    -- recipe ID is rejected on every build; source 70450 alone proves none.
    local resultID=resultIdentity(result)
    local existing=stored(false)
    if existing and resultID then
        for _,r in ipairs(existing.rows) do
            if r.resultIdentity==resultID then return false,"PERSISTED_DUPLICATE_RESULT" end
        end
    end
    local fingerprint=tostring(result.itemID)..":"..tostring(result.quantity)
    -- Anonymous result identity cannot safely distinguish an event replay from
    -- a second immediate craft of the same output. Fail closed on that window.
    if not resultID and self.recentAnonymous[fingerprint] then
        return false,"ANONYMOUS_REPLAY_OR_DISTINCT_CRAFT_UNRESOLVED" end
    local match,index,count=nil,nil,0
    for i,p in ipairs(self.pending) do
        if exactMatch(p,result.itemID) and
            (result.recipeID==nil or result.recipeID==p.spellID) then
            -- Never match OR buffer a receipt against a pending cast captured
            -- on a different client build. No lifecycle event is assumed.
            if not positive(p.clientBuild) or p.clientBuild~=liveBuild then
                return false,"CRAFT_RESULT_BUILD_MISMATCH" end
            if p.clientBuildToken~=liveToken then
                return false,"CRAFT_RESULT_CLIENT_SESSION_MISMATCH" end
            match=p;index=i;count=count+1
        end
    end
    if count>1 then return false,"AMBIGUOUS_RESULT_CORRELATION" end
    if match and result.recipeID and result.recipeID~=match.spellID then
        return false,"RESULT_RECIPE_IDENTITY_CONFLICT" end
    if count==0 then
        result.when=t
        for _,r in ipairs(self.pendingResults) do
            if (resultID and resultIdentity(r)==resultID) or
               (not resultID and not resultIdentity(r) and r.itemID==result.itemID and r.quantity==result.quantity) then
                return false,"BUFFERED_DUPLICATE_OR_AMBIGUOUS_RESULT"
            end
        end
        -- Capture the raw callback NOW, not when a later cast matches it.
        local skill,verified,ctx=tracePanel()
        -- Receipt provenance belongs to the CALLBACK, even if its panel
        -- cannot be authenticated yet. Never reconstruct this as a new event
        -- when a later cast provides a valid panel/session context.
        appendTrace(self,result,"TRADE_SKILL_ITEM_CRAFTED_RESULT",t,skill,
            "RESULT_AWAITING_CAST",verified,ctx)
        result.bufferedEventTrace=result.eventTrace[1]
        result.receiptPanelVerified=verified==true
        result.eventTrace=nil
        self.pendingResults[#self.pendingResults+1]=result
        while #self.pendingResults>self.pendingLimit do table.remove(self.pendingResults,1) end
        return false,"RESULT_AWAITING_CAST"
    end
    if not match.ownerKey or match.ownerKey~=owner() then
        return false,"OWNER_CHANGED_OR_UNKNOWN"
    end
    -- A client-interface transition during correlation must not turn an old
    -- observation into a current receipt, even if the numeric build is equal.
    local finalBuildModule=JLP:GetModule("ClientBuildInfo")
    local finalBuild=finalBuildModule and finalBuildModule.GetBuildNumber and finalBuildModule:GetBuildNumber()
    if finalBuild~=liveBuild or clientSessionToken()~=liveToken then
        return false,"CLIENT_IDENTITY_CHANGED_DURING_RESULT" end
    local target,err=stored(true)
    if not target then return false,err end
    if previouslyCommitted(target.rows,match.castGUID,resultID) then
        return false,"PERSISTED_DUPLICATE_EVIDENCE" end
    local row={id="cast:"..match.castGUID,castGUID=match.castGUID,
        resultIdentity=resultID,operationID=result.operationID,itemGUID=result.itemGUID,
        professionKey=match.professionKey,recipeID=match.spellID,
        spellID=match.spellID,recipeName=match.recipeName,outputItemID=result.itemID,
        outputQuantity=result.quantity,outputQuantityEvidence="CLIENT_CRAFTED_RESULT_EVENT",
        status="observed_result",source="CLIENT_EVENTS_OBSERVED_BUILD",sourceBuild=70450,
        clientBuild=match.clientBuild,
        clientBuildToken=match.clientBuildToken,
        outputRelationSourceBuild=70450,outputRelationCurrentBuildVerified=false,
        evidence="UNIQUE_CAST_AND_OUTPUT_ITEM_MATCH",readOnly=true,
        confirmedCount=nil,requestedCount=nil,skillGain=nil,
        -- Correlation at a later time does not retroactively verify a
        -- previously unverified result receipt for skill-up attribution.
        skillBefore=match.skillBefore,skillAfter=nil,
        resultReceiptPanelVerified=nil,
        skillObservationStatus=match.professionKey=="TAILORING" and
            (match.skillBefore and "UNKNOWN_BEFORE_OR_AFTER" or
             (match.skillObservationReason=="IDENTITY_CONFLICT_OR_CONCURRENT_CRAFT" and "EVENT_CORRELATION_CONFLICT" or "UNKNOWN_BEFORE_OR_AFTER")) or nil,
        skillObservationReason=match.skillObservationReason,
        characterKey=match.ownerKey,
        panelToken=match.skillPanel and match.skillPanel.panelToken or nil,
        panelRevision=match.skillPanel and match.skillPanel.panelRevision or nil,
        skillEvidenceBuild=match.skillPanel and match.skillPanel.build or nil,
        eventTrace=match.professionKey=="TAILORING" and (match.eventTrace or {}) or nil,
        preResultSkillEpoch=match.preResultSkillEpoch,
        preResultSkillWhen=match.preResultSkillWhen,
        eventTraceTruncated=match.eventTraceTruncated,
        productionAuthority=false,finishedAt=epoch()}
    if match.professionKey=="TAILORING" then
        local skill,verified,ctx=tracePanel()
        if bufferedReconciliation and result.bufferedEventTrace then
            row.resultReceiptPanelVerified=result.receiptPanelVerified==true
            mergeRawTrace(self,row,result.bufferedEventTrace)
        else
            row.resultReceiptPanelVerified=verified
            appendTrace(self,row,"TRADE_SKILL_ITEM_CRAFTED_RESULT",t,skill,
                "UNIQUE_RESULT_MATCH",verified,ctx)
        end
    end
    if row.resultReceiptPanelVerified==false and
        match.professionKey=="TAILORING" then
        -- Keep the client output as passive history, but reject all fresh
        -- skill authority from an unauthenticated result receipt, whether
        -- it was immediately matched or buffered until the cast callback.
        row.skillBefore=nil
        row.skillObservationStatus="IDENTITY_CONFLICT"
        row.skillObservationReason="RESULT_RECEIPT_PANEL_UNVERIFIED"
    end
    target.rows[#target.rows+1]=row
    while #target.rows>self.historyLimit do table.remove(target.rows,1) end
    if not resultID then self.recentAnonymous[fingerprint]=t end
    if match.professionKey=="TAILORING" and row.skillBefore~=nil then
        if self.awaitingSkill or #self.pending>1 then
            row.skillObservationStatus="EVENT_CORRELATION_CONFLICT"
            if self.awaitingSkill then
                self.awaitingSkill.row.skillObservationStatus="EVENT_CORRELATION_CONFLICT"
                self.awaitingSkill.row.skillGain=nil
                self.awaitingSkill=nil
            end
        else
            -- Transient session context MUST NOT be written into SavedVariables.
            self.awaitingSkill={row=row,ctx=match.skillPanel,when=t}
        end
    end
    table.remove(self.pending,index)
    if self.awaitingSkill and self.awaitingSkill.row==row and match.preResultSkillAfter~=nil then
        local ctx=tailoringPanel()
        if ctx and samePanel(match.skillPanel,ctx) and ctx.skill==match.preResultSkillAfter and
            type(match.preResultSkillWhen)=="number" and
            t>=match.preResultSkillWhen and t-match.preResultSkillWhen<=self.windowSeconds then
            -- The buffered sample was taken after this exact cast; result
            -- correlation is now independently confirmed.
            self:OnSkillUpdate(match.preResultSkillEvent,true)
        else
            row.skillObservationStatus="IDENTITY_CONFLICT"
            row.skillObservationReason="POST_CAST_SKILL_IDENTITY_OR_WINDOW_CHANGED_BEFORE_RESULT"
            self.awaitingSkill=nil
        end
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("CRAFT_OBSERVATION_JOURNAL_UPDATED",row.professionKey)
    end
    return true,row
end
-- Expose value-copies only: viewers cannot mutate persisted evidence.
local function copyTrace(trace)
    if type(trace)~="table" then return nil end
    local result={}
    for i,entry in ipairs(trace) do
        local clone={}
        for k,v in pairs(entry) do
            if type(v)=="string" or type(v)=="number" or type(v)=="boolean" then
                clone[k]=v
            end
        end
        result[i]=clone
    end
    return result
end
-- Pending casts without independently matched outputs are not completed
-- crafts. Expose a diagnostic status without manufacturing persistent samples.
function Journal:GetPendingSkillEvidence()
    -- Read-only inspection is also an entry point after long inactivity.
    self:Prune(elapsed())
    if #self.pending>1 then return {status="EVENT_CORRELATION_CONFLICT",readOnly=true} end
    if #self.pending==1 or self.beforeCraft then
        local p=self.pending[1] or self.beforeCraft
        return {status="INCOMPLETE_CRAFT_EVIDENCE",readOnly=true,
            recipeID=p and (p.spellID or p.recipeID), eventTrace=p and copyTrace(p.eventTrace),
            eventTraceTruncated=p and p.eventTraceTruncated} end
    if self.awaitingSkill then
        return {status="UNKNOWN_BEFORE_OR_AFTER",readOnly=true,
            recipeID=self.awaitingSkill.row.recipeID,
            eventTrace=copyTrace(self.awaitingSkill.row.eventTrace),
            eventTraceTruncated=self.awaitingSkill.row.eventTraceTruncated} end
    return {status="NO_PENDING_SKILL_EVIDENCE",readOnly=true}
end
function Journal:GetHistory(limit,key)
    local reg=JLP:GetModule("ProfessionRegistry")
    if key~=nil then
        key=reg and reg.NormalizeKey and reg:NormalizeKey(key) or nil
        if not key then return nil,"UNKNOWN_PROFESSION" end
    end
    local db=stored(false)
    local rows={}
    limit=math.max(1,math.min(150,math.floor(tonumber(limit) or 40)))
    for i=#(db and db.rows or {}),1,-1 do
        local r=db.rows[i]
        if type(r)=="table" and (key==nil or key==r.professionKey) then
            rows[#rows+1]={id=r.id,key=r.professionKey,recipeID=r.recipeID,
                recipeName=r.recipeName,status="observed_result",kind="observed-craft-result",
                evidence=r.evidence,castGUID=r.castGUID,resultIdentity=r.resultIdentity,
                outputItemID=r.outputItemID,outputQuantity=r.outputQuantity,
                outputQuantityEvidence=r.outputQuantityEvidence,finishedAt=r.finishedAt,
                resultReceiptPanelVerified=r.resultReceiptPanelVerified,
                skillGain=r.skillGain,skillBefore=r.skillBefore,skillAfter=r.skillAfter,
                skillObservationStatus=r.skillObservationStatus,
                skillObservationReason=r.skillObservationReason,
                skillObservationEvent=r.skillObservationEvent,
                skillObservationSource=r.skillObservationSource,
                skillObservedAt=r.skillObservedAt,skillObservedElapsed=r.skillObservedElapsed,
                eventTrace=copyTrace(r.eventTrace),eventTraceTruncated=r.eventTraceTruncated,
                panelToken=r.panelToken,panelRevision=r.panelRevision,
                characterKey=r.characterKey,skillEvidenceBuild=r.skillEvidenceBuild,
                source=r.source,sourceBuild=r.sourceBuild or 70450,
                clientBuild=r.clientBuild or r.skillEvidenceBuild,
                clientBuildToken=r.clientBuildToken,
                outputRelationSourceBuild=r.outputRelationSourceBuild or 70450,
                outputRelationCurrentBuildVerified=r.outputRelationCurrentBuildVerified==true,
                readOnly=true,
                confirmedCount=nil,requestedCount=nil,productionAuthority=false}
        end
        if #rows>=limit then break end
    end
    return rows
end
function Journal:GetSummary(key)
    local rows,err=self:GetHistory(150,key)
    if not rows then return tostring(err) end
    return string.format("Passive observations (70450 source provenance): %d correlated output event(s); no native or rate authorization.",#rows)
end
JLP:RegisterModule("CraftObservationJournal70450",Journal)
