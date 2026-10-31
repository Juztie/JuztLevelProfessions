local _, JLP = ...
local ProgressTracker = { initialized = false, lastCastGUID = nil }

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end
local function observationKeys()
    return JLP.GetObservationKeys and JLP:GetObservationKeys() or productionKeys()
end
local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

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
    JLP.DB.account.progressTracking = JLP.DB.account.progressTracking or { characters = {} }
    JLP.DB.account.progressTracking.characters = JLP.DB.account.progressTracking.characters or {}
    local key = characterKey()
    local store = JLP.DB.account.progressTracking.characters[key]
    if type(store) ~= "table" then
        store = { professions = {}, updatedAt = nil }
        JLP.DB.account.progressTracking.characters[key] = store
    end
    store.professions = store.professions or {}
    return store
end

local function stepID(key, plan)
    if not plan then return tostring(key) .. "|none" end
    if plan.actionKind == "craft" and plan.step then
        return table.concat({
            tostring(key),
            "craft",
            tostring(plan.step.recipe or "unknown"),
            tostring(plan.step.skillTarget or 0),
        }, "|")
    end
    if plan.actionKind == "train" and plan.step then
        local gate = plan.step.trainer or {}
        return table.concat({
            tostring(key),
            "train",
            tostring(gate.rank or "rank"),
            tostring(gate.nextCap or plan.step.skillTarget or 0),
        }, "|")
    end
    return table.concat({tostring(key), tostring(plan.actionKind or plan.status or "unknown")}, "|")
end

local function spellName(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        local ok, value = pcall(C_Spell.GetSpellName, spellID)
        if ok and value and value ~= "" then return tostring(value) end
    end
    if type(GetSpellInfo) == "function" then
        local ok, value = pcall(GetSpellInfo, spellID)
        if ok and value and value ~= "" then return tostring(value) end
    end
    return nil
end

local function ensureRecord(store, key)
    local record = store.professions[key]
    if type(record) ~= "table" then
        record = {
            skill = nil,
            maxSkill = nil,
            currentStepID = nil,
            stepStartSkill = nil,
            stepCraftsObserved = 0,
            stepSkillGains = 0,
            totalCraftsObserved = 0,
            totalSkillGains = 0,
            transitions = 0,
            recentTransactions = {},
        }
        store.professions[key] = record
    end
    record.recentTransactions = type(record.recentTransactions)=="table" and record.recentTransactions or {}
    return record
end

local function validBagCount(v)
    return type(v)=="number" and v==v and v>=0 and v<math.huge and
        v==math.floor(v) and v or nil
end
local function bagCount(itemID)
    itemID=tonumber(itemID)
    if not itemID then return nil end
    local inventory=JLP:GetModule("Inventory")
    if inventory and type(inventory.GetOwned)=="function" then
        local ok,owned=pcall(inventory.GetOwned,inventory,itemID)
        if ok and type(owned)=="table" then
            -- Explicit UNKNOWN outweighs numeric 0 and stale snapshots.
            if owned.bagKnown==true then return validBagCount(owned.bags) end
            return nil
        end
    end
    if type(C_Item)=="table" and type(C_Item.GetItemCount)=="function" then
        local ok,value=pcall(C_Item.GetItemCount,itemID,false,false,true)
        if ok then return validBagCount(value) end
    end
    return nil
end

local function transactionID(action)
    if type(action)~="table" then return nil end
    if action.ledgerID then return tostring(action.ledgerID) end
    if action.transactionID then return tostring(action.transactionID) end
    if action.token==nil then return nil end
    local kind=action.transactionKind or (action.targetGUID and "enchant" or "craft")
    return tostring(kind)..":"..tostring(action.token)
end

local function transactionStepID(action)
    if type(action)~="table" then return nil end
    return table.concat({
        tostring(action.key or "UNKNOWN"),
        "craft",
        tostring(action.recipeName or action.recipeID or "unknown"),
        tostring(action.targetSkill or 0),
    }, "|")
end

function ProgressTracker:CaptureMaterialSnapshot(key, plan)
    if not plan or plan.actionKind~="craft" or not plan.step then return nil end
    local merged={}
    for _,material in ipairs(plan.step.materials or {}) do
        local itemID=tonumber(material.itemID)
        local qty=math.max(0,tonumber(material.quantity) or 0)
        if itemID and qty>0 then
            local row=merged[itemID]
            if not row then
                row={itemID=itemID,name=material.name,perCraft=0}
                merged[itemID]=row
            end
            row.perCraft=row.perCraft+qty
        end
    end
    local items={}
    for _,row in pairs(merged) do
        row.beforeBags=bagCount(row.itemID)
        row.bagsKnown=row.beforeBags~=nil
        items[#items+1]=row
    end
    table.sort(items,function(a,b) return (a.itemID or 0)<(b.itemID or 0) end)
    return {
        key=key,
        stepID=stepID(key,plan),
        recipe=plan.step.recipe,
        capturedAt=now(),
        items=items,
    }
end

function ProgressTracker:RecordTransaction(action)
    if type(action)~="table" or not action.key then return false end
    local id=transactionID(action)
    if not id then return false end
    local store=getStore()
    if not store then return false end
    local record=ensureRecord(store,action.key)
    local history=record.recentTransactions
    local entry,index
    for i,value in ipairs(history) do
        if value and value.id==id then entry,index=value,i break end
    end
    if not entry then
        entry={id=id}
        history[#history+1]=entry
        index=#history
    end

    entry.kind=action.transactionKind or (action.targetGUID and "enchant" or "craft")
    entry.ledgerID=action.ledgerID or action.transactionID or entry.ledgerID
    entry.key=action.key
    entry.recipeID=action.recipeID
    entry.recipeName=action.recipeName
    entry.targetName=action.targetName
    entry.status=action.status
    entry.mode=action.mode
    -- Strategy is historical only when the guarded ordinal authorization
    -- captured it. Never infer past strategy from the current Guide settings.
    local provenance=action.authorityProvenance
    if type(provenance)=="table" and
        (provenance.contract=="production-tailoring-native-craft-all-provenance-v1" or
         provenance.contract=="research-native-craft-all-provenance-v1") and
        (provenance.mode=="normal" or provenance.mode=="aggressive") then
        entry.strategy=provenance.mode
    end
    entry.requestedCount=tonumber(action.requestedCount) or (entry.kind=="enchant" and 1 or 1)
    local actionConfirmed=entry.kind=="enchant" and (action.status=="success" and 1 or 0) or math.max(0,tonumber(action.completedCount) or 0)
    local ledger=JLP:GetModule("TransactionLedger")
    local ledgerConfirmed=ledger and entry.ledgerID and ledger:GetConfirmedCount(entry.ledgerID) or 0
    entry.confirmedCount=math.max(tonumber(entry.confirmedCount) or 0,actionConfirmed,tonumber(ledgerConfirmed) or 0)
    entry.startedSkill=tonumber(action.startedSkill)
    entry.endingSkill=tonumber(action.endingSkill)
    entry.skillGain=math.max(0,tonumber(action.skillGain) or 0)
    entry.targetSkill=tonumber(action.targetSkill)
    entry.targetReached=action.targetReached and true or false
    entry.stepAdvanced=action.stepAdvanced and true or false
    entry.nextActionKind=action.nextActionKind
    entry.nextRecipe=action.nextRecipe
    entry.source=action.source
    entry.startedAt=action.startedAt
    entry.finishedAt=action.finishedAt or now()
    entry.stepID=entry.stepID or (action.materialSnapshot and action.materialSnapshot.stepID) or transactionStepID(action)
    entry.materialSnapshot=entry.materialSnapshot or action.materialSnapshot
    if ledger and entry.ledgerID and entry.status=="success" and ledger.ReconcileSkillAggregate then
        ledger:ReconcileSkillAggregate(entry.ledgerID,entry.startedSkill,entry.endingSkill)
    end
    if entry.status=="success" and entry.materialSnapshot and type(entry.materialSnapshot.items)=="table" and not entry.materialsReconciledAt then
        entry.needsMaterialReconcile=true
    end
    record.lastTransactionID=id
    record.lastTransactionAt=entry.finishedAt
    store.updatedAt=now()

    while #history>40 do table.remove(history,1) end
    if JLP.EventBus then JLP.EventBus:Emit("PROFESSION_TRANSACTION_UPDATED",action.key,entry) end
    return true,entry,index
end

function ProgressTracker:ReconcileMaterials(key)
    local store=getStore()
    if not store then return false end
    local changed=false
    for professionKey,record in pairs(store.professions or {}) do
        if not key or key==professionKey then
            for _,entry in ipairs(record.recentTransactions or {}) do
                if entry and entry.status=="success" and entry.needsMaterialReconcile and entry.materialSnapshot then
                    entry.materialReconcileAttempts=(tonumber(entry.materialReconcileAttempts) or 0)+1
                    local anyDelta=false
                    local consumption={}
                    local observationComplete=true
                    for _,item in ipairs(entry.materialSnapshot.items or {}) do
                        local after=bagCount(item.itemID)
                        local before=item.bagsKnown==true and validBagCount(item.beforeBags) or nil
                        if before==nil or after==nil then
                            observationComplete=false
                            break
                        end
                        local consumed=math.max(0,before-after)
                        local expected=math.max(0,(tonumber(item.perCraft) or 0)*(tonumber(entry.confirmedCount) or 0))
                        if consumed>0 then anyDelta=true end
                        consumption[#consumption+1]={
                            itemID=item.itemID,name=item.name,
                            perCraft=math.max(0,tonumber(item.perCraft) or 0),
                            beforeBags=before,afterBags=after,
                            consumed=consumed,expected=expected,
                        }
                    end
                    if observationComplete then
                        entry.materialConsumption=consumption
                        entry.materialObservationStatus="OBSERVED"
                        local ledger=JLP:GetModule("TransactionLedger")
                        if ledger and entry.ledgerID and ledger.ReconcileMaterialAggregate then
                            ledger:ReconcileMaterialAggregate(entry.ledgerID,consumption)
                        end
                        if anyDelta or entry.materialReconcileAttempts>=2 or
                            #(entry.materialSnapshot.items or {})==0 then
                            entry.needsMaterialReconcile=false
                            entry.materialsReconciledAt=now()
                        end
                    else
                        -- Do not write zero-delta material receipts or mark
                        -- reconciliation complete after N failed observations.
                        entry.materialObservationStatus="INVENTORY_UNKNOWN"
                        entry.materialConsumption=nil
                    end
                    changed=true
                end
            end
        end
    end
    if changed and JLP.EventBus then JLP.EventBus:Emit("PROFESSION_TRANSACTION_UPDATED",key or "ALL",nil) end
    return changed
end

function ProgressTracker:Initialize()
    self.initialized = true
    return self:Capture("player-login", true)
end

function ProgressTracker:Capture(reason, baseline)
    local store = getStore()
    local api = JLP:GetModule("ProfessionAPI")
    local planner = JLP:GetModule("Planner")
    if not store or not api or not planner then return { changed = false, professions = {} } end

    local detected = api:GetDetected()
    local result = { changed = false, professions = {} }

    for _, key in ipairs(observationKeys()) do
        local profession = detected[key]
        if profession then
            local record = ensureRecord(store, key)
            local oldSkill = tonumber(record.skill)
            local oldMax = tonumber(record.maxSkill)
            local currentSkill = tonumber(profession.skill) or 0
            local currentMax = tonumber(profession.maxSkill) or 0
            local plan = planner:GetProfessionPlan(key)
            local currentStepID = stepID(key, plan)
            local previousStepID = record.currentStepID
            local skillDelta = 0
            local rankChanged = false
            local stepChanged = previousStepID ~= nil and previousStepID ~= currentStepID

            if not baseline and oldSkill and currentSkill > oldSkill then
                skillDelta = currentSkill - oldSkill
                record.totalSkillGains = (tonumber(record.totalSkillGains) or 0) + skillDelta
                record.lastSkillGain = skillDelta
                record.lastSkillGainAt = now()
                result.changed = true
            end

            if not baseline and oldMax and currentMax ~= oldMax then
                rankChanged = true
                record.lastRankChange = { from = oldMax, to = currentMax, at = now() }
                result.changed = true
            end

            if previousStepID == nil then
                record.currentStepID = currentStepID
                record.stepStartSkill = currentSkill
                record.stepCraftsObserved = tonumber(record.stepCraftsObserved) or 0
                record.stepSkillGains = tonumber(record.stepSkillGains) or 0
            elseif stepChanged then
                record.lastTransition = {
                    from = previousStepID,
                    to = currentStepID,
                    at = now(),
                    reason = tostring(reason or "state-change"),
                }
                record.transitions = (tonumber(record.transitions) or 0) + 1
                record.currentStepID = currentStepID
                record.stepStartSkill = currentSkill
                record.stepCraftsObserved = 0
                record.stepSkillGains = 0
                result.changed = true
            elseif skillDelta > 0 then
                record.stepSkillGains = (tonumber(record.stepSkillGains) or 0) + skillDelta
            end

            -- A login/reload is a baseline observation, not a skill-gain event. If the
            -- persisted route step no longer matches, start tracking the newly observed
            -- step without inventing offline crafts or skill gains.
            if baseline and previousStepID ~= currentStepID then
                record.currentStepID = currentStepID
                record.stepStartSkill = currentSkill
                record.stepCraftsObserved = 0
                record.stepSkillGains = 0
            end

            record.skill = currentSkill
            record.maxSkill = currentMax
            record.currentActionKind = plan and plan.actionKind or nil
            record.currentRecipe = plan and plan.step and plan.step.recipe or nil
            record.currentTarget = plan and plan.step and plan.step.skillTarget or nil
            record.lastObservedAt = now()
            record.lastReason = tostring(reason or "capture")
            store.updatedAt = now()

            result.professions[key] = {
                skillDelta = skillDelta,
                rankChanged = rankChanged,
                stepChanged = stepChanged,
                plan = plan,
            }
        end
    end

    if result.changed and JLP.EventBus then
        JLP.EventBus:Emit("PROFESSION_PROGRESS_UPDATED", result)
    end
    return result
end

function ProgressTracker:RecordSpellcast(spellID, castGUID)
    -- An anonymous event cannot be de-duplicated across reloads. Do not use it
    -- to increment skill-route craft counters.
    if type(castGUID)~="string" or castGUID=="" then return false end
    local name = spellName(spellID)
    if not name then return false end

    local planner = JLP:GetModule("Planner")
    local api = JLP:GetModule("ProfessionAPI")
    local store = getStore()
    if not planner or not api or not store then return false end
    if characterKey()=="UnknownRealm:UnknownCharacter" then return false end
    -- Per-character persistent replay guard: lastCastGUID only rejected
    -- consecutive duplicates and failed on A,B,A event reordering/reload.
    store.craftCastEvidence=type(store.craftCastEvidence)=="table" and store.craftCastEvidence or {order={},ids={}}
    local replay=store.craftCastEvidence
    replay.order=type(replay.order)=="table" and replay.order or {}
    replay.ids=type(replay.ids)=="table" and replay.ids or {}
    if replay.ids[castGUID] then return false end

    local detected = api:GetDetected()
    for _, key in ipairs(observationKeys()) do
        if detected[key] then
            local plan = planner:GetProfessionPlan(key)
            local recipe = plan and plan.actionKind == "craft" and plan.step and plan.step.recipe
            if recipe and normalizeText(recipe) == normalizeText(name) then
                local buildInfo=JLP:GetModule("ClientBuildInfo")
                local activeBuild=buildInfo and buildInfo.GetBuildNumber and buildInfo:GetBuildNumber()
                -- A localized name never proves a cast. Exact numeric ID is
                -- required for every client build, including future builds.
                local expected=tonumber(plan.step and plan.step.recipeID)
                if not expected then
                    local crafting=JLP:GetModule("Crafting")
                    if crafting and crafting.ResolveRecipeID then
                        expected=tonumber(crafting:ResolveRecipeID(key,recipe))
                    end
                end
                if not expected or expected~=tonumber(spellID) then return false end
                local record = ensureRecord(store, key)
                local currentStepID = stepID(key, plan)
                if record.currentStepID ~= currentStepID then
                    record.currentStepID = currentStepID
                    record.stepStartSkill = tonumber(detected[key].skill) or 0
                    record.stepCraftsObserved = 0
                    record.stepSkillGains = 0
                end
                record.stepCraftsObserved = (tonumber(record.stepCraftsObserved) or 0) + 1
                record.totalCraftsObserved = (tonumber(record.totalCraftsObserved) or 0) + 1
                record.lastCraft = {
                    recipe = recipe,
                    spellID = tonumber(spellID),
                    castGUID = castGUID,
                    at = now(),
                }
                record.lastObservedAt = now()
                store.updatedAt = now()
                replay.ids[castGUID]=true
                replay.order[#replay.order+1]=castGUID
                while #replay.order>256 do
                    local oldest=table.remove(replay.order,1)
                    replay.ids[oldest]=nil
                end
                self.lastCastGUID=castGUID
                if JLP.EventBus then
                    JLP.EventBus:Emit("PROFESSION_CRAFT_OBSERVED", key, recipe, record.stepCraftsObserved)
                end
                return true, key, recipe
            end
        end
    end
    return false
end

-- Alpha269 presentation-only access to the existing capped, per-character
-- transaction store. No ledger or settlement mutation and no new DB schema.
function ProgressTracker:GetCraftHistory(limit)
    local store=getStore()
    local rows={}
    if type(store)~="table" then return rows end
    limit=math.max(1,math.min(100,math.floor(tonumber(limit) or 40)))
    for key,record in pairs(store.professions or {}) do
        for _,source in ipairs(record.recentTransactions or {}) do
            if type(source)=="table" and (source.status=="success" or source.status=="failed" or
                    source.status=="timeout" or source.status=="partial") then
                rows[#rows+1]={key=key,recipeName=source.recipeName,recipeID=source.recipeID,
                    status=source.status,kind=source.kind,mode=source.mode,
                    strategy=source.strategy,
                    confirmedCount=math.max(0,tonumber(source.confirmedCount) or 0),
                    requestedCount=math.max(0,tonumber(source.requestedCount) or 0),
                    targetSkill=source.targetSkill,finishedAt=source.finishedAt,
                    startedSkill=source.startedSkill,endingSkill=source.endingSkill,
                    id=source.id,source=source.source}
            end
        end
    end
    table.sort(rows,function(a,b)
        if (tonumber(a.finishedAt) or 0)==(tonumber(b.finishedAt) or 0) then
            return tostring(a.id or "")>tostring(b.id or "") end
        return (tonumber(a.finishedAt) or 0)>(tonumber(b.finishedAt) or 0)
    end)
    while #rows>limit do table.remove(rows) end
    return rows
end

function ProgressTracker:GetStatus(key)
    local store = getStore()
    if not store then return nil end
    local record = store.professions and store.professions[key]
    if not record then return nil end

    local planner = JLP:GetModule("Planner")
    local plan = planner and planner:GetProfessionPlan(key) or nil
    local liveStepID = stepID(key, plan)
    local stepConfirmed,stepSkillFromConfirmed,stepNoSkill,stepFailures=0,0,0,0
    local lastTransaction=nil
    for _,entry in ipairs(record.recentTransactions or {}) do
        if entry then
            if entry.id==record.lastTransactionID then lastTransaction=entry end
            if entry.stepID==liveStepID then
                if entry.status=="success" then
                    local confirmed=math.max(0,tonumber(entry.confirmedCount) or 0)
                    local gained=math.max(0,tonumber(entry.skillGain) or 0)
                    stepConfirmed=stepConfirmed+confirmed
                    stepSkillFromConfirmed=stepSkillFromConfirmed+gained
                    stepNoSkill=stepNoSkill+math.max(0,confirmed-math.min(confirmed,gained))
                elseif entry.status=="failed" or entry.status=="timeout" then
                    stepFailures=stepFailures+1
                end
            end
        end
    end
    return {
        key = key,
        skill = tonumber(record.skill) or 0,
        maxSkill = tonumber(record.maxSkill) or 0,
        actionKind = plan and plan.actionKind or record.currentActionKind,
        recipe = plan and plan.step and plan.step.recipe or record.currentRecipe,
        target = plan and plan.step and plan.step.skillTarget or record.currentTarget,
        stepCraftsObserved = liveStepID == record.currentStepID and (tonumber(record.stepCraftsObserved) or 0) or 0,
        stepSkillGains = liveStepID == record.currentStepID and (tonumber(record.stepSkillGains) or 0) or 0,
        stepConfirmedCrafts = stepConfirmed,
        stepConfirmedSkillGains = stepSkillFromConfirmed,
        stepNoSkillCrafts = stepNoSkill,
        stepTransactionFailures = stepFailures,
        totalCraftsObserved = tonumber(record.totalCraftsObserved) or 0,
        totalSkillGains = tonumber(record.totalSkillGains) or 0,
        transitions = tonumber(record.transitions) or 0,
        lastSkillGain = record.lastSkillGain,
        lastSkillGainAt = record.lastSkillGainAt,
        lastCraft = record.lastCraft,
        lastTransaction = lastTransaction,
        lastTransition = record.lastTransition,
        lastReason = record.lastReason,
    }
end

function ProgressTracker:FormatStatus(key)
    local status = self:GetStatus(key)
    if not status then return "Live tracking: no profession state recorded yet." end
    if status.actionKind == "craft" then
        if (status.stepConfirmedCrafts or 0)>0 then
            return string.format(
                "Live tracking: %d confirmed - +%d skill - %d without skill-up",
                status.stepConfirmedCrafts or 0,
                status.stepConfirmedSkillGains or 0,
                status.stepNoSkillCrafts or 0
            )
        end
        return string.format(
            "Live tracking: %d craft%s observed this step - +%d skill gained",
            status.stepCraftsObserved or 0,
            (status.stepCraftsObserved or 0) == 1 and "" or "s",
            status.stepSkillGains or 0
        )
    elseif status.actionKind == "train" then
        return "Live tracking: waiting for the next profession rank to register."
    elseif status.actionKind == "complete" then
        return "Live tracking: profession route complete."
    end
    return "Live tracking: profession state active."
end

function ProgressTracker:GetSummary()
    local lines = {}
    for _, key in ipairs(productionKeys()) do
        local status = self:GetStatus(key)
        if status then
            lines[#lines + 1] = string.format(
                "%s %d/%d - crafts observed %d - confirmed current-step %d - skill gains +%d - transitions %d",
                professionLabel(key),
                status.skill or 0,
                status.maxSkill or 0,
                status.totalCraftsObserved or 0,
                status.stepConfirmedCrafts or 0,
                status.totalSkillGains or 0,
                status.transitions or 0
            )
        end
    end
    if #lines == 0 then return "No profession progress has been observed yet." end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ProgressTracker", ProgressTracker)
