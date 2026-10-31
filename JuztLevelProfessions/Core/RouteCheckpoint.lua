local _, JLP = ...

-- Persists a compact, conservative checkpoint of the route execution surface.
-- Recovery never restores source verification, workspace completion or waypoint
-- ownership from SavedVariables alone. Live client evidence is authoritative.
--
-- v2 adds profession-scoped checkpoint projections and a bounded per-profession
-- history. This prevents a prior global Dual Mode session from being presented as
-- Tailoring history on the Enchanting card (or the reverse) after /reload.
local RouteCheckpoint = {
    contract = "evidence-reconciled-route-checkpoint-v2",
    checkpointSchema = 2,
    historyLimit = 12,
    initialized = false,
    current = nil,
    previousCheckpoint = nil,
    revision = 0,
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function stateKeys()
    local reg=registry()
    return reg and reg:GetStateKeys() or {}
end

local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local function normalizeProfession(value)
    local reg=registry()
    if reg then return reg:NormalizeKey(value) end
    local text = string.upper(tostring(value or ""))
    if text == "TAILORING" or text == "ENCHANTING" then return text end
    return nil
end

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok then return value end
    end
    return nil
end

local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function clonePoint(point)
    if type(point) ~= "table" then return nil end
    local mapID = tonumber(point.mapID or point.uiMapID)
    local x, y = tonumber(point.x), tonumber(point.y)
    if not mapID or not x or not y then return nil end
    return { mapID=mapID, uiMapID=mapID, x=x, y=y }
end

local function boundedActions(actions)
    local out = {}
    for index, entry in ipairs(actions or {}) do
        if index > 16 then break end
        out[#out + 1] = {
            id = entry.id,
            key = entry.key or entry.profession,
            kind = entry.kind,
            status = entry.status,
            text = entry.text,
        }
    end
    return out
end

local function getStore()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.routeCheckpoint = JLP.DB.account.routeCheckpoint or { characters = {} }
    JLP.DB.account.routeCheckpoint.characters = JLP.DB.account.routeCheckpoint.characters or {}
    local key = characterKey()
    local record = JLP.DB.account.routeCheckpoint.characters[key]
    if type(record) ~= "table" then
        record = { checkpoint=nil, lastRecovery=nil, recoveries=0, professionHistory={} }
        JLP.DB.account.routeCheckpoint.characters[key] = record
    end
    record.professionHistory = type(record.professionHistory) == "table" and record.professionHistory or {}
    for _, professionKey in ipairs(stateKeys()) do
        if type(record.professionHistory[professionKey]) ~= "table" then record.professionHistory[professionKey] = {} end
    end
    return record, key
end

local function executionSnapshot(key)
    local execution = JLP:GetModule("ExecutionProgress")
    local status = execution and execution.GetStatus and execution:GetStatus(key) or nil
    local active = status and status.active or nil
    local last = status and status.lastCompleted or nil
    return {
        activeID = active and active.id or nil,
        activeGroup = active and active.group or nil,
        activeKind = active and active.kind or nil,
        progressCurrent = tonumber(active and active.progress and active.progress.current) or nil,
        progressRequired = tonumber(active and active.progress and active.progress.required) or nil,
        lastCompletedID = last and last.id or nil,
        lastCompletedAt = last and last.completedAt or nil,
    }
end

local function routeSessionSnapshot()
    local module = JLP:GetModule("RouteSession")
    local status = module and module.GetStatus and module:GetStatus() or nil
    local session = status and status.session or nil
    if not session then return { status="idle" } end
    return {
        status = status.status,
        id = session.id,
        workspaceKey = session.workspaceKey,
        station = session.station,
        label = session.label,
        expectedSource = session.expectedSource,
        completedActions = tonumber(session.completedActions) or 0,
        totalActions = tonumber(session.totalActions) or 0,
        remainingActions = tonumber(session.remainingActions) or 0,
        entered = session.enteredAt ~= nil,
        actions = boundedActions(session.actions),
    }
end

local function travelSessionSnapshot()
    local module = JLP:GetModule("TravelSession")
    local status = module and module.GetStatus and module:GetStatus() or nil
    local plan = status and status.plan or nil
    local current = status and status.currentBatch or nil
    local nextBatch = status and status.nextBatch or nil
    local completed = {}
    for index, row in ipairs(status and status.completedWorkspaces or {}) do
        if index > 6 then break end
        completed[#completed + 1] = {
            routeSessionID = row.routeSessionID,
            workspaceKey = row.workspaceKey,
            label = row.label,
            completedActions = tonumber(row.completedActions) or 0,
            totalActions = tonumber(row.totalActions) or 0,
            finishedAt = row.finishedAt,
        }
    end
    return {
        status = status and status.status or "idle",
        sessionID = status and status.sessionID or nil,
        planSignature = plan and plan.signature or nil,
        currentWorkspaceKey = current and current.workspaceKey or nil,
        currentLabel = current and current.label or nil,
        nextWorkspaceKey = nextBatch and nextBatch.workspaceKey or nil,
        nextLabel = nextBatch and nextBatch.label or nil,
        routeComplete = plan and plan.routeComplete and true or false,
        completedWorkspaces = completed,
    }
end

local function transitionSnapshot()
    local module = JLP:GetModule("TravelTransition")
    local status = module and module.GetStatus and module:GetStatus() or nil
    return {
        stage = status and status.stage or nil,
        evidence = status and status.evidence or nil,
        workspaceKey = status and status.workspaceKey or nil,
        target = status and status.target or nil,
        sourceName = status and status.sourceName or nil,
        routeComplete = status and status.routeComplete and true or false,
    }
end

local function handoffSnapshot()
    local module = JLP:GetModule("DestinationHandoff")
    local status = module and module.GetStatus and module:GetStatus() or nil
    return {
        stage = status and status.stage or nil,
        evidence = status and status.evidence or nil,
        workspaceKey = status and status.workspaceKey or nil,
        currentSessionID = status and status.currentSessionID or nil,
        completedSessionID = status and status.completedSessionID or nil,
        nextDestination = status and status.nextDestination or nil,
        currentSource = status and status.currentSource or nil,
        showNextSource = status and status.showNextSource and true or false,
    }
end

local function transactionRecoverySnapshot()
    local module = JLP:GetModule("TransactionRecovery")
    local status = module and module.GetStatus and module:GetStatus() or nil
    local pending = module and module.GetCheckpoint and module:GetCheckpoint() or nil
    return {
        state = status and status.state or "IDLE",
        label = status and status.label or nil,
        key = status and status.key or pending and pending.key or nil,
        kind = status and status.kind or pending and pending.kind or nil,
        snapshotID = status and status.snapshotID or pending and pending.id or nil,
        pending = pending ~= nil,
        recipeID = pending and pending.recipeID or status and status.recipeID or nil,
        recipeName = pending and pending.recipeName or status and status.recipeName or nil,
    }
end

local function markerSnapshot()
    local module = JLP:GetModule("RouteMarkerLifecycle")
    if module and module.GetCheckpoint then return module:GetCheckpoint() end
    local status = module and module.GetStatus and module:GetStatus() or nil
    return {
        state = status and status.state or nil,
        destinationKey = status and status.destinationKey or nil,
        sourceName = status and status.sourceName or nil,
        target = clonePoint(status and status.target),
        markerOwned = status and status.markerOwned and true or false,
        replacedUserWaypoint = status and status.replacedUserWaypoint and true or false,
    }
end

local function actionIdentity(entry, index)
    return tostring(entry and (entry.id or entry.kind or entry.text) or index or "action")
end

local function professionRouteSnapshot(route, key)
    route = type(route) == "table" and route or {}
    local actions = {}
    for _, entry in ipairs(route.actions or {}) do
        if normalizeProfession(entry.key or entry.profession) == key then actions[#actions + 1] = entry end
    end
    if #actions == 0 then
        return {status="idle", actions={}, completedActions=0, totalActions=0, remainingActions=0, signature=nil}
    end
    local completed, signatureParts = 0, {
        tostring(route.workspaceKey or "workspace"),
        tostring(route.station or "station"),
    }
    for index, entry in ipairs(actions) do
        if entry.status == "completed" then completed = completed + 1 end
        signatureParts[#signatureParts + 1] = actionIdentity(entry, index)
    end
    return {
        status = completed >= #actions and "completed" or tostring(route.status or "active"),
        id = route.id,
        workspaceKey = route.workspaceKey,
        station = route.station,
        label = route.label,
        expectedSource = route.expectedSource,
        entered = route.entered and true or false,
        actions = actions,
        completedActions = completed,
        totalActions = #actions,
        remainingActions = math.max(0, #actions - completed),
        signature = table.concat(signatureParts, "|"),
    }
end

local function scopedTransition(snapshot, route)
    local transition = snapshot and snapshot.transition or nil
    if not transition or not route or (tonumber(route.totalActions) or 0) <= 0 then return nil end
    if route.workspaceKey and transition.workspaceKey and tostring(route.workspaceKey) ~= tostring(transition.workspaceKey) then return nil end
    return transition
end

local function scopedHandoff(snapshot, route)
    local handoff = snapshot and snapshot.handoff or nil
    if not handoff or not route or (tonumber(route.totalActions) or 0) <= 0 then return nil end
    if route.workspaceKey and handoff.workspaceKey and tostring(route.workspaceKey) ~= tostring(handoff.workspaceKey) then return nil end
    return handoff
end

local function professionSnapshot(snapshot, key)
    if type(snapshot) ~= "table" then return nil end
    if snapshot.professions and type(snapshot.professions[key]) == "table" then return snapshot.professions[key] end
    local route = professionRouteSnapshot(snapshot.routeSession, key)
    local execution = snapshot.executions and snapshot.executions[key] or nil
    local transaction = snapshot.transactionRecovery
    if normalizeProfession(transaction and transaction.key) ~= key then transaction = nil end
    local transition = scopedTransition(snapshot, route)
    local handoff = scopedHandoff(snapshot, route)
    return {
        key = key,
        profession = professionLabel(key),
        execution = execution,
        route = route,
        transition = transition,
        handoff = handoff,
        transactionRecovery = transaction,
        hadActivity = (execution and execution.activeID ~= nil) or (route.totalActions or 0) > 0 or transaction ~= nil,
    }
end

local function populateProfessionSnapshots(snapshot)
    snapshot.professions = {}
    for _, key in ipairs(stateKeys()) do snapshot.professions[key] = professionSnapshot(snapshot, key) end
    return snapshot
end

function RouteCheckpoint:BuildSnapshot(reason)
    local executions = {}
    for _, key in ipairs(stateKeys()) do executions[key] = executionSnapshot(key) end
    local snapshot = {
        schema = self.checkpointSchema,
        addonVersion = JLP.version,
        characterKey = characterKey(),
        savedAt = now(),
        reason = tostring(reason or "checkpoint"),
        executions = executions,
        routeSession = routeSessionSnapshot(),
        travelSession = travelSessionSnapshot(),
        transition = transitionSnapshot(),
        handoff = handoffSnapshot(),
        marker = markerSnapshot(),
        transactionRecovery = transactionRecoverySnapshot(),
    }
    return populateProfessionSnapshots(snapshot)
end

local function countExecutionContinuity(previous, live)
    local count, names, keys = 0, {}, {}
    for _, key in ipairs(stateKeys()) do
        local old = previous and previous.executions and previous.executions[key] or nil
        local new = live and live.executions and live.executions[key] or nil
        if old and new and old.activeID and old.activeID == new.activeID then
            count = count + 1
            names[#names + 1] = professionLabel(key)
            keys[#keys + 1] = key
        end
    end
    return count, names, keys
end

local function routeSignaturesMatch(previous, live)
    local old = previous and previous.travelSession and previous.travelSession.planSignature or nil
    local new = live and live.travelSession and live.travelSession.planSignature or nil
    if not old or not new then return false end
    return old == new
end

local function sourceVerified(transition)
    local stage = transition and transition.stage or nil
    return stage == "ARRIVED_SOURCE" or stage == "ACTION_READY"
end

local function previouslyVerifiedSource(previous)
    return sourceVerified(previous and previous.transition or nil)
end

local function currentlyVerifiedSource(live)
    return sourceVerified(live and live.transition or nil)
end

local function reconcileProfession(previous, live, key, reason)
    local label = professionLabel(key)
    local old = professionSnapshot(previous, key)
    local current = professionSnapshot(live, key) or {
        key=key, profession=label, route={status="idle",totalActions=0,completedActions=0,remainingActions=0}
    }
    local oldExecution = old and old.execution or nil
    local liveExecution = current.execution or nil
    local executionContinuity = oldExecution and liveExecution and oldExecution.activeID and oldExecution.activeID == liveExecution.activeID and 1 or 0
    local oldSignature = old and old.route and old.route.signature or nil
    local liveSignature = current.route and current.route.signature or nil
    local routeMatched = oldSignature ~= nil and liveSignature ~= nil and oldSignature == liveSignature
    local hadCheckpoint = previous ~= nil and old ~= nil and old.hadActivity and true or false
    local staleSourceClaim = sourceVerified(old and old.transition or nil) and not sourceVerified(current.transition)
    local state, text, tone

    if not hadCheckpoint then
        state, text, tone = "LIVE", "Live " .. label .. " state", "muted"
    elseif executionContinuity > 0 then
        state, text, tone = "RECOVERED", "Recovered · " .. label .. " execution", "good"
    elseif routeMatched then
        state, text, tone = "RECONCILED", label .. " route reconciled", "cyan"
    else
        state, text, tone = "LIVE_SUPERSEDES_CHECKPOINT", "Live " .. label .. " route rebuilt", "muted"
    end

    return {
        contract = RouteCheckpoint.contract,
        state = state,
        label = text,
        tone = tone,
        reason = tostring(reason or "reconcile"),
        recoveredAt = now(),
        scopedProfession = key,
        hadCheckpoint = hadCheckpoint,
        routeMatched = routeMatched,
        executionContinuity = executionContinuity,
        checkpointRouteSignature = oldSignature,
        liveRouteSignature = liveSignature,
        checkpointWorkspaceKey = old and old.route and old.route.workspaceKey or nil,
        liveWorkspaceKey = current.route and current.route.workspaceKey or nil,
        checkpointActions = old and old.route and tonumber(old.route.totalActions) or 0,
        liveActions = current.route and tonumber(current.route.totalActions) or 0,
        staleSourceClaimDiscarded = staleSourceClaim and true or false,
        sourceVerificationRestored = false,
        completionRestored = false,
    }
end

local function historyFingerprint(scoped)
    scoped = scoped or {}
    local route = scoped.route or {}
    local execution = scoped.execution or {}
    local transition = scoped.transition or {}
    local transaction = scoped.transactionRecovery or {}
    return table.concat({
        tostring(route.signature or "idle"),
        tostring(route.completedActions or 0),
        tostring(route.totalActions or 0),
        tostring(execution.activeID or "none"),
        tostring(execution.lastCompletedID or "none"),
        tostring(transition.stage or "none"),
        tostring(transaction.state or "none"),
        tostring(transaction.snapshotID or "none"),
    }, "#")
end

local function appendProfessionHistory(record, snapshot, reason, limit)
    if not record or not snapshot then return end
    for _, key in ipairs(stateKeys()) do
        local scoped = professionSnapshot(snapshot, key)
        if scoped and scoped.hadActivity then
            local list = record.professionHistory[key]
            local fingerprint = historyFingerprint(scoped)
            local last = list[#list]
            if not last or last.fingerprint ~= fingerprint then
                local route = scoped.route or {}
                local execution = scoped.execution or {}
                local transition = scoped.transition or {}
                list[#list + 1] = {
                    savedAt = snapshot.savedAt,
                    reason = tostring(reason or snapshot.reason or "checkpoint"),
                    fingerprint = fingerprint,
                    routeStatus = route.status or "idle",
                    routeSignature = route.signature,
                    workspaceKey = route.workspaceKey,
                    workspaceLabel = route.label,
                    completedActions = tonumber(route.completedActions) or 0,
                    totalActions = tonumber(route.totalActions) or 0,
                    executionActiveID = execution.activeID,
                    executionGroup = execution.activeGroup,
                    transitionStage = transition.stage,
                }
                while #list > (tonumber(limit) or 12) do table.remove(list, 1) end
            end
        end
    end
end

function RouteCheckpoint:Reconcile(previous, reason)
    local markerRestored, markerReason = false, nil
    if previous and previous.marker and previous.marker.markerOwned then
        local marker = JLP:GetModule("RouteMarkerLifecycle")
        if marker and marker.RestoreCheckpoint then
            markerRestored, markerReason = marker:RestoreCheckpoint(previous.marker)
        end
    end
    local live = self:BuildSnapshot("recovery-live")
    local executionCount, executionNames, executionKeys = countExecutionContinuity(previous, live)
    local routeMatch = routeSignaturesMatch(previous, live)
    local staleSourceClaim = previouslyVerifiedSource(previous) and not currentlyVerifiedSource(live)
    local state, label, tone

    if not previous then
        state, label, tone = "NO_CHECKPOINT", "Live route initialized · no prior checkpoint", "muted"
    elseif markerRestored or executionCount > 0 then
        state, tone = "RECOVERED", "good"
        local parts = {}
        if executionCount > 0 then parts[#parts + 1] = table.concat(executionNames, "+") .. " execution" end
        if markerRestored then parts[#parts + 1] = "route marker ownership" end
        label = "Recovered · " .. table.concat(parts, " + ")
    elseif routeMatch then
        state, label, tone = "RECONCILED", "Route checkpoint reconciled with live state", "cyan"
    else
        state, label, tone = "LIVE_SUPERSEDES_CHECKPOINT", "Live route rebuilt · checkpoint superseded", "warn"
    end

    local professions = {}
    for _, key in ipairs(stateKeys()) do professions[key] = reconcileProfession(previous, live, key, reason) end

    local status = {
        contract = self.contract,
        state = state,
        label = label,
        tone = tone,
        reason = tostring(reason or "reconcile"),
        recoveredAt = now(),
        hadCheckpoint = previous ~= nil,
        routeMatched = routeMatch,
        executionContinuity = executionCount,
        executionNames = executionNames,
        executionKeys = executionKeys,
        markerRestored = markerRestored and true or false,
        markerReason = markerReason,
        staleSourceClaimDiscarded = staleSourceClaim and true or false,
        sourceVerificationRestored = false,
        completionRestored = false,
        liveTravelSignature = live.travelSession and live.travelSession.planSignature or nil,
        checkpointTravelSignature = previous and previous.travelSession and previous.travelSession.planSignature or nil,
        checkpointSavedAt = previous and previous.savedAt or nil,
        transactionRecoveryState = live.transactionRecovery and live.transactionRecovery.state or "IDLE",
        transactionRecoveryPending = live.transactionRecovery and live.transactionRecovery.pending and true or false,
        professions = professions,
    }
    self.current = status
    self.revision = self.revision + 1
    local record = getStore()
    if record then
        record.lastRecovery = status
        record.recoveries = (tonumber(record.recoveries) or 0) + 1
    end
    if JLP.EventBus then JLP.EventBus:Emit("ROUTE_RECOVERY_UPDATED", self.revision, reason, self:GetStatus()) end
    return status
end

function RouteCheckpoint:Capture(reason)
    local record = getStore()
    if not record then return false end
    local snapshot = self:BuildSnapshot(reason)
    record.checkpoint = snapshot
    record.lastSavedAt = snapshot.savedAt
    appendProfessionHistory(record, snapshot, reason, self.historyLimit)
    return true, snapshot
end

function RouteCheckpoint:Initialize()
    if self.initialized then return self:GetStatus() end
    self.initialized = true
    local record = getStore()
    self.previousCheckpoint = record and record.checkpoint or nil
    local status = self:Reconcile(self.previousCheckpoint, "player-login")
    self:Capture("player-login-reconciled")
    if JLP.EventBus then
        for _, eventName in ipairs({
            "PROFESSION_EXECUTION_UPDATED", "ROUTE_SESSION_UPDATED", "TRAVEL_SESSION_UPDATED",
            "TRAVEL_TRANSITION_UPDATED", "ROUTE_MARKER_UPDATED", "DESTINATION_HANDOFF_UPDATED",
            "WORKSPACE_ORCHESTRATION_UPDATED", "CRAFT_ACTION_UPDATED", "ENCHANT_ACTION_UPDATED",
            "PROFESSION_TRANSACTION_UPDATED", "TRANSACTION_RECOVERY_UPDATED"
        }) do
            JLP.EventBus:On(eventName, function() RouteCheckpoint:Capture(eventName) end)
        end
    end
    return status
end

function RouteCheckpoint:OnLogout()
    return self:Capture("player-logout")
end

function RouteCheckpoint:GetStatus()
    if self.current then
        self.current.revision = self.revision
        return self.current
    end
    local record = getStore()
    local previous = record and record.lastRecovery or nil
    if previous then return previous end
    return {
        contract = self.contract,
        state = "NOT_INITIALIZED",
        label = "Recovery not initialized",
        tone = "muted",
        revision = self.revision,
    }
end

function RouteCheckpoint:GetProfessionStatus(key)
    key = normalizeProfession(key)
    if not key then
        return {contract=self.contract,state="UNSUPPORTED_PROFESSION",label="Unsupported profession",tone="bad",scopedProfession=nil,historyCount=0}
    end
    local status = self:GetStatus()
    local record = getStore()
    local history = record and record.professionHistory and record.professionHistory[key] or nil
    local scoped = status.professions and status.professions[key] or nil
    if scoped then
        scoped.historyCount = type(history) == "table" and #history or 0
        local runtime=JLP:GetModule("ProfessionRuntimeState")
        scoped.runtimeState=runtime and runtime.Get and runtime:Get(key) or nil
        return scoped
    end

    -- Backward compatibility for persisted v1 recovery records until a v2
    -- reconciliation has been captured on this client session.
    local label = professionLabel(key)
    local matched = false
    for _, value in ipairs(status.executionKeys or {}) do
        if normalizeProfession(value) == key then matched = true break end
    end
    if not matched then
        for _, value in ipairs(status.executionNames or {}) do
            if tostring(value) == label then matched = true break end
        end
    end
    if matched then
        return {
            contract = status.contract, state = status.state,
            label = "Recovered · " .. label .. " execution", tone = status.tone or "good",
            reason = status.reason, recoveredAt = status.recoveredAt,
            executionContinuity = 1, executionKeys = {key}, scopedProfession = key,
            historyCount = type(history) == "table" and #history or 0,
            runtimeState = (JLP:GetModule("ProfessionRuntimeState") and JLP:GetModule("ProfessionRuntimeState"):Get(key)) or nil,
        }
    end
    return {
        contract=status.contract, state="LIVE", label="Live " .. label .. " state", tone="muted",
        scopedProfession=key, historyCount=type(history) == "table" and #history or 0,
        runtimeState=(JLP:GetModule("ProfessionRuntimeState") and JLP:GetModule("ProfessionRuntimeState"):Get(key)) or nil,
    }
end

function RouteCheckpoint:GetProfessionHistory(key)
    key = normalizeProfession(key)
    if not key then return {} end
    local record = getStore()
    return record and record.professionHistory and record.professionHistory[key] or {}
end

function RouteCheckpoint:GetCheckpoint()
    local record = getStore()
    return record and record.checkpoint or nil
end

function RouteCheckpoint:GetHistorySummary()
    local lines = {"Route history: profession-scoped · bounded to " .. tostring(self.historyLimit) .. " state changes per profession"}
    for _, key in ipairs(stateKeys()) do
        local history = self:GetProfessionHistory(key)
        local latest = history[#history]
        local suffix = latest and string.format(" · latest %s · %d/%d actions · %s", tostring(latest.routeStatus or "idle"), tonumber(latest.completedActions) or 0, tonumber(latest.totalActions) or 0, tostring(latest.workspaceLabel or latest.workspaceKey or "workspace")) or " · no persisted route activity"
        lines[#lines + 1] = string.format("%s · %d record%s%s", professionLabel(key), #history, #history == 1 and "" or "s", suffix)
    end
    return table.concat(lines, "\n")
end

function RouteCheckpoint:GetSummary()
    local status = self:GetStatus()
    local lines = {
        "Route recovery: " .. tostring(status.label or status.state or "Unavailable"),
        "State: " .. tostring(status.state or "UNKNOWN"),
        "Route matched: " .. (status.routeMatched and "yes" or "no"),
        "Execution continuity: " .. tostring(status.executionContinuity or 0),
        "Marker ownership recovered: " .. (status.markerRestored and "yes" or "no"),
        "Source verification restored: no (live evidence required)",
        "Completion restored: no (live/evidence state required)",
        "Transaction recovery: " .. tostring(status.transactionRecoveryState or "IDLE"),
    }
    for _, key in ipairs(stateKeys()) do
        local scoped = self:GetProfessionStatus(key)
        lines[#lines + 1] = string.format("%s recovery: %s · history %d", professionLabel(key), tostring(scoped.label or scoped.state or "Unavailable"), tonumber(scoped.historyCount) or 0)
    end
    if status.markerReason then lines[#lines + 1] = "Marker recovery: " .. tostring(status.markerReason) end
    if status.staleSourceClaimDiscarded then lines[#lines + 1] = "Stale source verification discarded: yes" end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("RouteCheckpoint", RouteCheckpoint)
