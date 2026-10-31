local _, JLP = ...
local RouteProgress = { knownRecipes = {}, recipeScanAvailable = false, recipeScanState = {}, initialized = false, initializedCharacterKey = nil }

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return value end
    end
    return nil
end

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("%s+", " ")
    return value
end


local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function getStore()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.routeProgress = JLP.DB.account.routeProgress or { characters = {} }
    JLP.DB.account.routeProgress.characters = JLP.DB.account.routeProgress.characters or {}
    local key = characterKey()
    local store = JLP.DB.account.routeProgress.characters[key]
    if type(store) ~= "table" then
        store = { completed = {}, skipped = {}, updatedAt = nil }
        JLP.DB.account.routeProgress.characters[key] = store
    end
    store.completed = store.completed or {}
    store.skipped = store.skipped or {}
    store.invalidatedCompleted = store.invalidatedCompleted or {}
    return store
end

function RouteProgress:Initialize(force)
    if not JLP.DB then return false end
    local activeCharacterKey = characterKey()
    if self.initialized and not force and self.initializedCharacterKey == activeCharacterKey then return true end
    self.knownRecipes = {}
    self.recipeScanState = {}
    self.recipeScanAvailable = false
    local cache = JLP:GetModule("KnowledgeCache")
    if cache and cache.GetRecipeSnapshot then
        local known, states = cache:GetRecipeSnapshot()
        self.knownRecipes = known or {}
        self.recipeScanState = states or {}
        for _, state in pairs(self.recipeScanState) do
            if state and state.available then self.recipeScanAvailable = true break end
        end
    end
    self.initializedCharacterKey = activeCharacterKey
    self.initialized = true
    return true
end

-- Route visits are not execution assignments. Typed, length-prefixed atoms
-- keep absent values and embedded delimiters distinct, without volatile facts.
local function routeIdentity(...)
    local parts = {"route-visit-v2:"}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        local kind, text = type(value), nil
        if kind == "nil" then text = ""
        elseif kind == "string" then text = value
        elseif kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
            text = string.format("%.17g", value == 0 and 0 or value)
        elseif kind == "boolean" then text = value and "1" or "0"
        else return nil end
        parts[#parts + 1] = kind:sub(1, 1) .. #text .. ":" .. text
    end
    return table.concat(parts)
end

local function named(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

function RouteProgress:GetActionID(action)
    if type(action) ~= "table" or not named(action.kind) or not named(action.profession) or
        normalizeText(action.profession) == "unknown" or type(action.sourceInfo) ~= "table" then return nil end
    local source = action.sourceInfo
    if not (named(source.kind) or named(source.name) or named(source.recipe) or named(source.material) or
        (type(source.npcID) == "number" and source.npcID > 0) or
        (type(source.itemID) == "number" and source.itemID > 0)) then return nil end
    if source.nav ~= nil and type(source.nav) ~= "table" then return nil end
    local nav = source.nav or {}
    return routeIdentity(
        action.kind, action.profession, action.itemID, action.recipe, action.name,
        action.recipeID, action.recipeSpellID, action.spellID,
        action.requiredSkill, action.skillTarget, action.skillCap, action.nextCap, action.rank,
        source.kind, source.name, source.recipe, source.material, source.zone,
        source.itemID, source.npcID, source.sourceID,
        nav.mapDomain, nav.mapID, nav.uiMapID, nav.artID, nav.mapArtID,
        nav.instanceMapID, nav.floor, nav.x, nav.y, nav.z)
end

local function recipeIDSet(recipeIDs)
    local out = {}
    if type(recipeIDs) == "table" then
        for key, value in pairs(recipeIDs) do
            local id = tonumber(value) or tonumber(key)
            if id then out[id] = true end
        end
    end
    return out
end

function RouteProgress:InferProfessionFromRecipeIDs(recipeIDs)
    local observed = recipeIDSet(recipeIDs)
    local provider = JLP:GetModule("ProfessionDatasetProvider")
    local keys = provider and provider.GetRegisteredDatasetKeys and provider:GetRegisteredDatasetKeys() or {}
    local bestKey, bestScore, tied = nil, 0, false
    local scores = {}
    for _, professionKey in ipairs(keys) do
        local dataset = provider:GetRegisteredDataset(professionKey)
        local score = 0
        for _, step in ipairs((dataset and (dataset.route or dataset.steps)) or {}) do
            local id = tonumber(step and step.recipeID)
            if id and observed[id] then score = score + 1 end
        end
        scores[professionKey] = score
        if score > bestScore then
            bestKey, bestScore, tied = professionKey, score, false
        elseif score > 0 and score == bestScore then
            tied = true
        end
    end
    if bestScore <= 0 then return nil, "NO_MATCH", scores end
    if tied then return nil, "AMBIGUOUS", scores end
    return bestKey, "UNIQUE_MATCH", scores
end

local function currentSessionReceipt(builds)
    if type(builds)~="table" or type(builds.Read)~="function" then return nil,nil end
    local ok,info=pcall(builds.Read,builds)
    if not ok or type(info)~="table" or info.known~=true then return nil,nil end
    local build,interface=info.buildNumber,info.interfaceVersion
    if type(build)~="number" or build~=build or build<1 or build~=math.floor(build) or
       build>9007199254740991 or type(interface)~="number" or interface~=interface or
       interface<1 or interface~=math.floor(interface) or interface>9007199254740991 then
        return nil,nil
    end
    local token=string.format("forever:%s|interface:%s",tostring(build),tostring(interface))
    if info.token~=token then return nil,nil end
    return build,token
end

function RouteProgress:ScanKnownRecipes()
    local startBuild,startToken=currentSessionReceipt(JLP:GetModule("ClientBuildInfo"))
    local found,idsByName,conflictingNames,explicitUnlearned={}, {}, {}, {}
    local api=JLP:GetModule("ProfessionAPI")
    local initial=api and api.GetOpenProfessionContext and api:GetOpenProfessionContext() or nil
    local professionKey=initial and initial.verified and initial.professionKey or nil
    local trade=C_TradeSkillUI
    local validList=false
    local rawCount=0
    local duplicatePositions={}
    local observedByID={}
    local invalidRows={}
    local rawIDSequence={}
    if professionKey and type(trade)=="table" and
        type(trade.GetAllRecipeIDs)=="function" and type(trade.GetRecipeInfo)=="function" then
        local ok,list=pcall(trade.GetAllRecipeIDs)
        if ok and type(list)=="table" then
            local count,maxIndex,seen=0,0,{}
            validList=true
            for pos,id in pairs(list) do
                count=count+1
                if type(pos)~="number" or pos<1 or pos~=math.floor(pos) or pos>4096 or
                    type(id)~="number" or id<=0 or id~=math.floor(id) or count>4096 then
                    validList=false;break
                end
                if pos>maxIndex then maxIndex=pos end
            end
            if count==0 or count~=maxIndex then validList=false end
            if validList then
                rawCount=count
                for pos=1,count do
                    local id=list[pos]
                    rawIDSequence[pos]=id
                    if seen[id] then
                        duplicatePositions[#duplicatePositions+1]={recipeID=id,first=seen[id],again=pos}
                    else seen[id]=pos end
                end
                local registry=JLP:GetModule("ProfessionRegistry")
                for pos=1,count do
                    local id=list[pos]
                    if observedByID[id] then
                        -- A genuine disagreement across duplicate observations
                        -- is a conflict, not a structurally illegal duplicate.
                        local rereadOK,reread=pcall(trade.GetRecipeInfo,id)
                        local prior=observedByID[id]
                        if not rereadOK or type(reread)~="table" or
                            reread.learned~=prior.learned or reread.name~=prior.name then
                            validList=false
                            invalidRows[#invalidRows+1]={recipeID=id,state="CONFLICTING_DUPLICATE_OBSERVATION"}
                        end
                    else
                        local infoOK,info=pcall(trade.GetRecipeInfo,id)
                        local lineOK,line,parent=false,nil,nil
                        if type(trade.GetTradeSkillLineForRecipe)=="function" then
                            lineOK,line,_,parent=pcall(trade.GetTradeSkillLineForRecipe,id)
                        end
                        local state=registry and registry.ResolveRecipeLineage and
                            registry:ResolveRecipeLineage(professionKey,lineOK and line or nil,parent,id,
                                lineOK and "LIVE_PANEL_RECIPE_API" or nil) or "UNKNOWN_IDENTITY"
                        local record={recipeID=id,name=infoOK and type(info)=="table" and info.name or nil,
                            learned=infoOK and type(info)=="table" and info.learned or nil,
                            recipeSkillLineID=tonumber(line),parentSkillLineID=tonumber(parent),
                            identityState=state,verifiedMembership=state=="EXACT_BASE_MATCH" or
                                state=="VERIFIED_DESCENDANT_MATCH",sharedReference=state=="EXPLICIT_SHARED_REFERENCE"}
                        if infoOK and type(info)=="table" and info.learned==false then record.learned=false end
                        observedByID[id]=record
                        -- A shared list entry is diagnostic, never recipe authority.
                        if record.verifiedMembership and type(record.name)=="string" and record.name~="" then
                            local name=normalizeText(record.name)
                            if record.learned==false then
                                explicitUnlearned[name]=explicitUnlearned[name] or {}
                                explicitUnlearned[name][id]=true
                            elseif record.learned==true then
                                -- Preserve a positive exact-ID even if another ID
                                -- bearing the same name is explicitly unlearned.
                                if idsByName[name] and idsByName[name]~=id then
                                    conflictingNames[name]=true
                                else
                                    found[name]=true;idsByName[name]=id
                                end
                            end
                        else
                            invalidRows[#invalidRows+1]={recipeID=id,state=state}
                        end
                    end
                end
            end
        end
    end
    if validList and type(trade.GetAllRecipeIDs)=="function" then
        local rereadOK,latest=pcall(trade.GetAllRecipeIDs)
        if not rereadOK or type(latest)~="table" or #latest~=rawCount then
            validList=false
        else
            -- Disallow in-place mutation, reordered or filtered rows mid-scan.
            -- The replay order was captured before querying any recipe data.
            for pos=1,rawCount do
                if latest[pos]~=rawIDSequence[pos] then validList=false;break end
            end
        end
        if not validList then
            invalidRows[#invalidRows+1]={state="RECIPE_LIST_CHANGED_DURING_SCAN"}
        end
    end
    local finish=api and api.GetOpenProfessionContext and api:GetOpenProfessionContext() or nil
    local finishBuild,finishToken=currentSessionReceipt(JLP:GetModule("ClientBuildInfo"))
    -- Identical panel tokens cannot prove the interface remained unchanged.
    -- A scan without a full live client receipt is diagnostic-only.
    local stable=startBuild~=nil and startToken~=nil and
        startBuild==finishBuild and startToken==finishToken and
        validList and initial and finish and initial.verified and finish.verified and
        initial.panelToken==finish.panelToken and
        initial.panelRevision==finish.panelRevision and
        initial.professionKey==finish.professionKey and
        initial.build==finish.build and initial.characterKey==finish.characterKey and
        initial.skill==finish.skill and initial.maxSkill==finish.maxSkill
    self.lastRecipeScanDiagnostics={rawCount=rawCount,duplicates=duplicatePositions,
        uniqueCount=(function() local n=0 for _ in pairs(observedByID) do n=n+1 end return n end)(),
        rejected=invalidRows,stable=stable and true or false,scanAvailable=validList,
        panelStatus=initial and initial.reason or "NO_PANEL"}
    self.recipeScanAvailable=validList
    if validList and professionKey then
        local cache=JLP:GetModule("KnowledgeCache")
        if cache and cache.RememberRecipeScan then
            -- On mid-scan context drift, retain diagnostics but grant no
            -- transient learning/negative or persistent current observations.
            if stable then
                cache:RememberRecipeScan(professionKey,found,idsByName,
                    {sessionConfirmed=true,scanAvailable=true,scanComplete=false,
                    explicitUnlearned=explicitUnlearned,conflictingNames=conflictingNames,
                    observedByID=observedByID,panelToken=initial.panelToken,
                    panelRevision=initial.panelRevision})
            end
            local known,states=cache:GetRecipeSnapshot()
            self.knownRecipes=known or {};self.recipeScanState=states or {}
        end
        self.initialized=true
    end
    return validList and true or false, found, professionKey
end

function RouteProgress:IsRecipeKnown(recipeName)
    self:Initialize()
    local key = normalizeText(recipeName)
    if key == "" then return false end
    return self.knownRecipes[key] and true or false
end

function RouteProgress:GetRecipeKnowledge(recipeName, professionKey, refresh)
    self:Initialize()
    local key = normalizeText(recipeName)
    if key == "" then return "unknown" end
    if refresh then self:ScanKnownRecipes() end
    -- Session's union list can include a DIFFERENT profession. Consult the
    -- per-character/per-profession cache before any unscoped name fallback.
    if not professionKey and self.knownRecipes[key] then return "known" end
    local cache = JLP:GetModule("KnowledgeCache")
    if cache and cache.GetRecipeKnowledge and professionKey then
        local cached = cache:GetRecipeKnowledge(recipeName, professionKey)
        if cached ~= "unknown" then return cached end
    end
    -- Legacy recipeScanState is diagnostic only. A prior build-matching
    -- `complete` marker is not proof that the current client enumerated every
    -- recipe, or that the scan originated in this build/interface session.
    -- Only an explicit, freshly verified learned=false for the exact SpellID
    -- may yield not-known through KnowledgeCache above.
    return "unknown"
end

function RouteProgress:MarkCompleted(action, reason, observation)
    local id = self:GetActionID(action)
    local store = getStore()
    if not id or not store then return false end
    store.completed[id] = {
        at = now(),
        reason = tostring(reason or "completed"),
        observation = observation,
    }
    store.skipped[id] = nil
    store.updatedAt = now()
    return true
end

function RouteProgress:MarkSkipped(action, reason)
    local id = self:GetActionID(action)
    local store = getStore()
    if not id or not store then return false end
    if store.completed[id] then return false end
    store.skipped[id] = {
        at = now(),
        reason = tostring(reason or "manual-skip"),
    }
    store.updatedAt = now()
    return true
end

function RouteProgress:ClearSkipped(plan)
    local store = getStore()
    if not store then return 0 end
    local cleared = 0
    if plan and plan.actions then
        for _, action in ipairs(plan.actions) do
            local id = self:GetActionID(action)
            if id and store.skipped[id] then
                store.skipped[id] = nil
                cleared = cleared + 1
            end
        end
    else
        for id in pairs(store.skipped) do
            -- Ambiguous legacy keys remain historical; only clear this domain.
            if type(id) == "string" and id:sub(1, 15) == "route-visit-v2:" then
                store.skipped[id] = nil
                cleared = cleared + 1
            end
        end
    end
    if cleared > 0 then store.updatedAt = now() end
    return cleared
end

-- A verified build AND interface token is required for a live progress claim.
-- Raw build equality alone cannot establish a current-client observation.

-- A stored completion is not a live panel measurement. Validate the original
-- positive observation, its action identity, character and client session before
-- allowing it to survive a temporary absence of new panel data.
local function validObservedReceipt(action, receipt)
    if type(action) ~= "table" or action.kind ~= "profession-step" or
        type(receipt) ~= "table" or receipt.reason ~= "observed-profession-skill-target" then return false end
    local obs = receipt.observation
    local target = tonumber(action.skillTarget)
    if type(obs) ~= "table" or obs.verified ~= true or obs.kind ~= "open-panel-skill" or
        type(action.profession) ~= "string" or action.profession == "" or
        not target or target <= 0 or target ~= math.floor(target) or target == math.huge or
        obs.profession ~= action.profession or obs.skillTarget ~= target or
        type(obs.skill) ~= "number" or obs.skill ~= obs.skill or obs.skill == math.huge or
        obs.skill < target or type(obs.maxSkill) ~= "number" or
        obs.maxSkill ~= obs.maxSkill or obs.maxSkill == math.huge or obs.maxSkill < obs.skill or
        type(obs.baseSkillLineID) ~= "number" or obs.baseSkillLineID <= 0 or
        type(obs.professionEnum) ~= "number" or obs.professionEnum < 0 or
        type(obs.panelToken) ~= "string" or obs.panelToken == "" or
        type(obs.panelRevision) ~= "number" or obs.panelRevision < 1 then return false end
    local identity = JLP:GetModule("CharacterIdentity")
    local builds = JLP:GetModule("ClientBuildInfo")
    if not identity or type(identity.GetKey) ~= "function" or
        not builds then return false end
    local currentCharacter = identity:GetKey()
    local currentBuild,currentToken = currentSessionReceipt(builds)
    return type(currentCharacter) == "string" and currentCharacter ~= "" and
        not currentCharacter:find("UnknownCharacter",1,true) and
        obs.characterKey == currentCharacter and
        currentBuild~=nil and currentToken~=nil and
        obs.clientBuild == currentBuild and obs.clientBuildToken == currentToken
end

function RouteProgress:GetStatus(action)
    local id = self:GetActionID(action)
    local store = getStore()
    if not id or not store then return "pending", nil end
    if store.skipped[id] then return "skipped", store.skipped[id] end
    if store.completed[id] then
        local receipt = store.completed[id]
        if action.kind == "profession-step" and not validObservedReceipt(action, receipt) then
            return "pending", nil
        end
        return "completed", receipt
    end
    return "pending", nil
end

-- Return a stable, positive CURRENT observation of this particular profession,
-- even when it is BELOW the target. This is required to distinguish an actual
-- regression from panel closure, stale data or an unrelated profession panel.
-- Absence is UNKNOWN, never evidence of a negative skill state.
local function observeProfessionSkill(action)
    if type(action) ~= "table" or type(action.profession) ~= "string" then return nil end
    local target = tonumber(action.skillTarget)
    if not target or target <= 0 or target ~= math.floor(target) or target == math.huge then return nil end

    local api = JLP:GetModule("ProfessionAPI")
    local identity = JLP:GetModule("CharacterIdentity")
    local builds = JLP:GetModule("ClientBuildInfo")
    if not api or type(api.GetOpenProfessionContext) ~= "function" or
        not identity or type(identity.GetKey) ~= "function" or
        not builds then return nil end

    local character = identity:GetKey()
    local build,sessionToken = currentSessionReceipt(builds)
    if type(character) ~= "string" or character == "" or
        character:find("UnknownCharacter", 1, true) or
        build==nil or sessionToken==nil then return nil end

    local first = api:GetOpenProfessionContext()
    if type(first) ~= "table" or first.verified ~= true or
        (first.dataSourceChanging~=nil and first.dataSourceChanging~=false) or
        first.professionKey ~= action.profession or
        first.characterKey ~= character or first.build ~= build or
        type(first.panelToken) ~= "string" or first.panelToken == "" or
        type(first.panelRevision) ~= "number" or first.panelRevision < 1 or
        type(first.baseSkillLineID) ~= "number" or first.baseSkillLineID <= 0 or
        type(first.professionEnum) ~= "number" or first.professionEnum < 0 then return nil end

    local skill, cap = first.skill, first.maxSkill
    if type(skill) ~= "number" or type(cap) ~= "number" or
        skill ~= skill or cap ~= cap or skill < 0 or skill > cap or cap <= 0 or
        skill == math.huge or cap == math.huge then return nil end

    local second = api:GetOpenProfessionContext()
    if type(second) ~= "table" or second.verified ~= true or
        (second.dataSourceChanging~=nil and second.dataSourceChanging~=false) or
        second.professionKey ~= first.professionKey or
        second.characterKey ~= first.characterKey or second.build ~= first.build or
        second.panelToken ~= first.panelToken or
        second.panelRevision ~= first.panelRevision or
        second.baseSkillLineID ~= first.baseSkillLineID or
        second.professionEnum ~= first.professionEnum or
        second.skill ~= skill or second.maxSkill ~= cap or
        identity:GetKey() ~= character then return nil end
    local finalBuild,finalToken = currentSessionReceipt(builds)
    if finalBuild~=build or finalToken~=sessionToken then return nil end

    return {verified=true, kind="open-panel-skill", profession=action.profession,
        skill=skill, skillTarget=target, maxSkill=cap,
        characterKey=character, clientBuild=build, clientBuildToken=sessionToken,
        baseSkillLineID=first.baseSkillLineID, professionEnum=first.professionEnum,
        panelToken=first.panelToken, panelRevision=first.panelRevision}
end

local function verifiedSkillProgress(action)
    local observed = observeProfessionSkill(action)
    if observed and observed.skill >= observed.skillTarget then return observed end
    return nil
end

-- P1-177: transient skill evidence for guidance ONLY. A missing complete
-- build/interface receipt does not hide an otherwise stable live panel, but
-- this observation can NEVER mark a route action completed or enter SavedVariables.
function RouteProgress:GetReadOnlySkillObservation(action)
    local out={contract="route-skill-volatile-read-only-v1",readOnly=true,
        nativeDispatchAllowed=false,autoCompletionEligible=false,
        persistentReceiptEligible=false,observed=false,reason="UNVERIFIED"}
    if type(action)~="table" or action.kind~="profession-step" or
        type(action.profession)~="string" or action.profession=="" then
        out.reason="NOT_A_PROFESSION_STEP";return out
    end
    local target=tonumber(action.skillTarget)
    if not target or target~=target or target==math.huge or target<1 or
        target~=math.floor(target) then out.reason="SKILL_TARGET_INVALID";return out end
    local api=JLP:GetModule("ProfessionAPI")
    if not api or type(api.GetReadOnlyProfessionObservation)~="function" then
        out.reason="READ_ONLY_PANEL_API_UNAVAILABLE";return out
    end
    local live=api:GetReadOnlyProfessionObservation()
    if type(live)~="table" or live.observed~=true then
        out.reason=live and live.reason or "PANEL_UNVERIFIED";return out
    end
    if live.professionKey~=action.profession then
        out.reason="DIFFERENT_PROFESSION_PANEL";return out
    end
    local skill,cap=live.skill,live.maxSkill
    if type(skill)~="number" or type(cap)~="number" or skill~=skill or
        cap~=cap or skill<0 or skill>cap or cap<1 or
        skill~=math.floor(skill) or cap~=math.floor(cap) then
        out.reason="SKILL_DATA_INVALID";return out
    end
    out.observed=true
    out.skill=skill
    out.maxSkill=cap
    out.skillTarget=target
    out.targetReached=skill>=target
    out.professionKey=action.profession
    out.observationQuality=live.observationQuality
    out.reason="LIVE_SKILL_READ_ONLY"
    return out
end

function RouteProgress:GetReadOnlyStatus(action)
    local receipt=self:GetReadOnlySkillObservation(action)
    if not receipt.observed then return "unverified",receipt end
    return receipt.targetReached and "target-observed-read-only" or
        "progress-observed-read-only",receipt
end

function RouteProgress:AutoCompletionReason(action, detected)
    if not action or not action.sourceInfo then return nil end
    if action.kind == "profession-step" then
        local observed = verifiedSkillProgress(action)
        if observed then return "observed-profession-skill-target", observed end
        return nil
    end

    if action.kind == "train" then
        detected = detected or ((JLP:GetModule("ProfessionAPI") or {}).GetDetected and JLP:GetModule("ProfessionAPI"):GetDetected()) or {}
        local profession = detected[action.profession]
        local nextCap = tonumber(action.nextCap) or 0
        if action.profession=="TAILORING" and nextCap==150 then
            local api=JLP:GetModule("ProfessionAPI")
            local observed=api and api.Get and api:Get("TAILORING")
            if not profession or profession.cached~=false or not observed or observed.cached~=false or
                observed.key~="TAILORING" or observed.maxSkill~=profession.maxSkill or
                observed.skill~=profession.skill then return nil end
        end
        if profession and nextCap > 0 and (tonumber(profession.maxSkill) or 0) >= nextCap then
            return "profession-rank-registered"
        end
    end
    -- No other route action is automatically satisfied by a global recipe
    -- name or by possession of a teaching/source item. Those are distinct
    -- recipe-learning and material-acquisition contracts, not skill progress.
    return nil
end

local function archiveUnqualifiedCompletion(store, id, old, cause)
    if not old then return false end
    -- Preserve the original receipt for provenance/review; do not reinterpret
    -- a previously auto-saved recipe/item receipt as an observed craft.
    local entry = store.invalidatedCompleted[id]
    if type(entry) ~= "table" then
        entry = {previous=old, invalidatedAt=now(), cause=cause, events={}}
        store.invalidatedCompleted[id] = entry
    end
    local events = entry.events
    if type(events) ~= "table" then events={};entry.events=events end
    events[#events + 1] = {previous=old, invalidatedAt=now(), cause=cause}
    -- Limit historical diagnostics per route action, retaining the initial
    -- original receipt separately even when newer invalidations cycle.
    if #events > 16 then table.remove(events,1);entry.dropped=(entry.dropped or 0)+1 end
    store.completed[id] = nil
    store.updatedAt = now()
    return true
end

-- Only a 0.34.117 archival error may be restored, and only when its
-- ORIGINAL receipt independently passes the strict verified-evidence check.
-- A later contradictory observation must permanently cancel this recovery.
local function recoverableArchivedReceipt(store, id, action)
    local entry = store.invalidatedCompleted and store.invalidatedCompleted[id]
    if type(entry) ~= "table" then return nil, nil end
    local events = entry.events
    local last = type(events) == "table" and events[#events] or nil
    local record = last or entry
    if record.cause ~= "SKILL_TARGET_NOT_CURRENTLY_VERIFIED" or
        not validObservedReceipt(action, record.previous) then return nil, nil end
    return record.previous, entry
end

local function recordRestoration(entry)
    local history = entry.restorations
    if type(history) ~= "table" then history = {}; entry.restorations = history end
    history[#history + 1] = {at=now(), reason="RESTORED_PRIOR_VERIFIED_SKILL_RECEIPT"}
    if #history > 16 then table.remove(history, 1) end
end

function RouteProgress:Refresh(plan)
    if not plan then return 0 end
    self:Initialize()
    local api = JLP:GetModule("ProfessionAPI")
    local detected = api and api.GetDetected and api:GetDetected() or {}
    local store = getStore()
    local changed = 0
    for _, action in ipairs(plan.actions or {}) do
        if action.sourceInfo then
            local id = self:GetActionID(action)
            local old = store and id and store.completed[id] or nil
            if action.kind == "profession-step" then
                -- Observe once per refresh. An absent/unverified/foreign panel
                -- cannot negate a previous, correctly scoped observation.
                local observed = observeProfessionSkill(action)
                local qualifiedNow = observed and observed.skill >= observed.skillTarget
                local contradictory = observed and observed.skill < observed.skillTarget
                local validOld = old and validObservedReceipt(action, old)
                local identityConflict = observed and validOld and
                    (old.observation.baseSkillLineID ~= observed.baseSkillLineID or
                     old.observation.professionEnum ~= observed.professionEnum)
                if old and not validOld then
                    if archiveUnqualifiedCompletion(store, id, old, "INVALID_OR_INCOMPATIBLE_SKILL_RECEIPT") then
                        changed = changed + 1
                    end
                    old = nil
                elseif old and (contradictory or identityConflict) then
                    if archiveUnqualifiedCompletion(store, id, old, identityConflict and
                        "OBSERVED_PROFESSION_IDENTITY_CONFLICT" or "OBSERVED_PROFESSION_SKILL_BELOW_TARGET") then
                        changed = changed + 1
                    end
                    old = nil
                end
                if not old and not contradictory and not identityConflict and not (store and store.skipped[id]) then
                    if qualifiedNow then
                        self:MarkCompleted(action, "observed-profession-skill-target", observed)
                        changed = changed + 1
                    elseif store then
                        local previous, archive = recoverableArchivedReceipt(store, id, action)
                        if previous and (not observed or
                            (previous.observation.baseSkillLineID == observed.baseSkillLineID and
                             previous.observation.professionEnum == observed.professionEnum)) then
                            store.completed[id] = previous
                            store.updatedAt = now()
                            recordRestoration(archive)
                            changed = changed + 1
                        end
                    end
                end
            else
                local reason = self:AutoCompletionReason(action, detected)
                if reason then
                    local status = self:GetStatus(action)
                    if status == "pending" then
                        self:MarkCompleted(action, reason)
                        changed = changed + 1
                    end
                end
            end
        end
    end
    return changed
end

function RouteProgress:AnnotateRoute(route, plan)
    if not route then return route end
    self:Refresh(plan)
    local counts = { pending = 0, completed = 0, skipped = 0 }
    local pendingIndices = {}

    for index, stop in ipairs(route.stops or {}) do
        local pending, completed, skipped = 0, 0, 0
        for _, action in ipairs(stop.actions or {}) do
            local status, detail = self:GetStatus(action)
            action.routeStatus = status
            action.routeStatusDetail = detail
            if action.kind=="profession-step" then
                local _,advisory=self:GetReadOnlyStatus(action)
                action.readOnlySkillObservation=advisory
            end
            if status == "completed" then completed = completed + 1
            elseif status == "skipped" then skipped = skipped + 1
            else pending = pending + 1 end
        end
        stop.pendingActions = pending
        stop.completedActions = completed
        stop.skippedActions = skipped
        if pending > 0 then
            stop.status = "pending"
            counts.pending = counts.pending + 1
            pendingIndices[#pendingIndices + 1] = index
        elseif skipped > 0 then
            stop.status = "skipped"
            counts.skipped = counts.skipped + 1
        else
            stop.status = "completed"
            counts.completed = counts.completed + 1
        end
    end

    route.progressCounts = counts
    route.pendingIndices = pendingIndices
    route.pendingCount = #pendingIndices
    return route
end

function RouteProgress:SkipStop(stop)
    if not stop then return 0 end
    local skipped = 0
    for _, action in ipairs(stop.actions or {}) do
        local status = self:GetStatus(action)
        if status == "pending" and self:MarkSkipped(action, "manual-skip") then skipped = skipped + 1 end
    end
    return skipped
end

function RouteProgress:FormatStatus(stop)
    if not stop then return "pending" end
    if stop.status == "completed" then return "done" end
    if stop.status == "skipped" then return "skipped" end
    return "pending"
end

JLP:RegisterModule("RouteProgress", RouteProgress)
