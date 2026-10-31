local _, JLP = ...

-- UI-facing profession isolation layer. Global route orchestration remains
-- available to optimize the combined Tailoring + Enchanting journey, but each
-- profession card receives a self-contained projection so another profession's
-- batch, journey, handoff or recovery state can never leak into READINESS &
-- WORKSPACE.
local ProfessionGuideScope = {
    contract = "profession-isolated-guide-scope-v1",
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end
local function professionLabel(key)
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local function copyTable(source)
    local out = {}
    for k, v in pairs(source or {}) do out[k] = v end
    return out
end

local function actionBelongs(entry, key)
    if type(entry) ~= "table" then return false end
    return tostring(entry.key or entry.profession or "") == tostring(key or "")
end

local function filterSession(session, key)
    if type(session) ~= "table" then return nil end
    local actions = {}
    for _, entry in ipairs(session.actions or {}) do
        if actionBelongs(entry, key) then actions[#actions + 1] = entry end
    end
    if #actions == 0 then return nil end
    local out = copyTable(session)
    out.actions = actions
    out.professionKey = key
    out.profession = professionLabel(key)
    local completed = 0
    for _, entry in ipairs(actions) do if entry.status == "completed" then completed = completed + 1 end end
    out.completedActions = completed
    out.totalActions = #actions
    out.remainingActions = math.max(0, #actions - completed)
    out.ratio = #actions > 0 and math.min(1, completed / #actions) or 1
    return out
end

local function routeStatusFor(key, localPlan)
    local route = JLP:GetModule("RouteSession")
    local global = route and route.GetStatus and route:GetStatus() or nil
    local active = filterSession(global and global.active, key)
    if active then
        return {
            contract = "profession-scoped-route-session-v1",
            status = active.status or "active",
            active = active,
            session = active,
            sessionID = active.id,
            workspaceKey = active.workspaceKey,
            station = active.station,
            label = active.label,
            expectedSource = active.expectedSource,
            enteredAt = active.enteredAt,
            completedActions = active.completedActions,
            totalActions = active.totalActions,
            remainingActions = active.remainingActions,
            ratio = active.ratio,
            progressText = string.format("%d / %d actions completed here", active.completedActions or 0, active.totalActions or 0),
            lastCompleted = filterSession(global and global.lastCompleted, key),
            scopedProfession = key,
        }
    end

    local completed = filterSession(global and global.lastCompleted, key)
    if not completed and global and global.status == "completed" then completed = filterSession(global.session, key) end
    if completed then
        return {
            contract = "profession-scoped-route-session-v1",
            status = "completed",
            active = nil,
            session = completed,
            sessionID = completed.id,
            workspaceKey = completed.workspaceKey,
            station = completed.station,
            label = completed.label,
            expectedSource = completed.expectedSource,
            completedActions = completed.completedActions,
            totalActions = completed.totalActions,
            remainingActions = completed.remainingActions,
            ratio = completed.ratio,
            progressText = string.format("%d / %d actions completed here", completed.completedActions or 0, completed.totalActions or 0),
            lastCompleted = completed,
            scopedProfession = key,
        }
    end

    -- No global route-session currently belongs to this profession. Expose its
    -- next local workspace batch as a planned 0/N batch instead of borrowing the
    -- other profession's active batch.
    local batch = localPlan and localPlan.currentBatch or nil
    if batch then
        local actions = {}
        for _, entry in ipairs(batch.actions or {}) do if actionBelongs(entry, key) then actions[#actions + 1] = entry end end
        if #actions > 0 then
            local session = {
                id = "profession-plan:" .. tostring(key) .. ":" .. tostring(batch.workspaceKey or batch.station or "workspace"),
                key = key,
                profession = professionLabel(key),
                workspaceKey = batch.workspaceKey,
                station = batch.station,
                label = batch.label,
                expectedSource = batch.sourceName,
                actions = actions,
                completedActions = 0,
                totalActions = #actions,
                remainingActions = #actions,
                ratio = 0,
                status = "planned",
            }
            return {
                contract = "profession-scoped-route-session-v1",
                status = "planned",
                active = nil,
                session = session,
                sessionID = session.id,
                workspaceKey = session.workspaceKey,
                station = session.station,
                label = session.label,
                expectedSource = session.expectedSource,
                completedActions = 0,
                totalActions = #actions,
                remainingActions = #actions,
                ratio = 0,
                progressText = string.format("0 / %d actions planned here", #actions),
                lastCompleted = nil,
                scopedProfession = key,
            }
        end
    end

    return {
        contract = "profession-scoped-route-session-v1",
        status = "idle",
        active = nil,
        session = nil,
        completedActions = 0,
        totalActions = 0,
        remainingActions = 0,
        ratio = 1,
        scopedProfession = key,
    }
end

local function travelStatusFor(key, plan)
    local labels = {}
    for _, batch in ipairs(plan and plan.batches or {}) do labels[#labels + 1] = tostring(batch.label or batch.station or "Workspace") end
    local displayText = #labels > 0 and table.concat(labels, " → ") or "Route complete"
    local guide = {}
    for i = 1, math.min(#labels, 3) do guide[#guide + 1] = labels[i] end
    if #labels > 3 then guide[#guide + 1] = "+" .. tostring(#labels - 3) end
    return {
        contract = "profession-scoped-travel-session-v1",
        status = plan and not plan.routeComplete and "active" or "completed",
        plan = plan,
        currentBatch = plan and plan.currentBatch or nil,
        nextBatch = plan and plan.nextBatch or nil,
        batchCount = plan and plan.batchCount or 0,
        workspaceSwitches = plan and plan.workspaceSwitches or 0,
        auditedTransitions = plan and plan.auditedTransitions or 0,
        unknownTransitions = plan and plan.unknownTransitions or 0,
        chainText = plan and plan.chainText or "Route complete",
        displayText = displayText,
        guideText = #guide > 0 and table.concat(guide, " → ") or "Route complete",
        completedWorkspaces = {},
        scopedProfession = key,
    }
end

local function scopedMarker(key, transition)
    local lifecycle = JLP:GetModule("RouteMarkerLifecycle")
    local global = lifecycle and lifecycle.GetStatus and lifecycle:GetStatus() or nil
    local checkpoint = lifecycle and lifecycle.GetCheckpoint and lifecycle:GetCheckpoint() or nil
    local localWorkspace = transition and transition.workspaceKey or nil
    local markerWorkspace = checkpoint and checkpoint.workspaceKey or nil
    if global and localWorkspace and markerWorkspace and tostring(localWorkspace) == tostring(markerWorkspace) then
        local out = copyTable(global)
        out.workspaceKey = markerWorkspace
        out.scopedProfession = key
        return out
    end
    return {
        contract = "profession-scoped-route-marker-v1",
        state = "IDLE",
        label = "No " .. professionLabel(key) .. " route marker session",
        tone = "muted",
        markerOwned = false,
        workspaceKey = localWorkspace,
        scopedProfession = key,
    }
end

local function recoveryStatusFor(key)
    local checkpoint = JLP:GetModule("RouteCheckpoint")
    if checkpoint and checkpoint.GetProfessionStatus then return checkpoint:GetProfessionStatus(key) end
    local status = checkpoint and checkpoint.GetStatus and checkpoint:GetStatus() or nil
    if not status then return nil end
    return {
        contract = status.contract,
        state = "LIVE",
        label = "Live " .. professionLabel(key) .. " state",
        tone = "muted",
        scopedProfession = key,
    }
end

function ProfessionGuideScope:Build(key, plan, prepared)
    prepared = type(prepared) == "table" and prepared or {}
    local workspaceModule = JLP:GetModule("WorkspaceOrchestrator")
    local context = prepared.context or (workspaceModule and workspaceModule.GetContext and workspaceModule:GetContext()) or {station="world",label="World"}
    local workspace = workspaceModule and workspaceModule.Build and workspaceModule:Build(key, {plan=plan, queue=prepared.queue, action=prepared.action, assist=prepared.assist, context=context}) or nil
    local router = JLP:GetModule("TravelRouter")
    local origin = router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil

    local nextBestModule = JLP:GetModule("NextBestAction")
    local models = {[key] = workspace}
    local decision = nextBestModule and nextBestModule.Select and nextBestModule:Select(models, context, origin) or nil

    local travelModule = JLP:GetModule("TravelSession")
    local travelPlan = travelModule and travelModule.BuildFromModels and travelModule:BuildFromModels(models, context, origin) or nil
    local travelStatus = travelStatusFor(key, travelPlan)
    local routeStatus = routeStatusFor(key, travelPlan)

    local transitionModule = JLP:GetModule("TravelTransition")
    local transition = transitionModule and transitionModule.BuildFrom and transitionModule:BuildFrom(travelStatus, context, origin, routeStatus) or nil
    local navigationModule = JLP:GetModule("NavigationGuidance")
    local navigation = navigationModule and navigationModule.BuildFrom and navigationModule:BuildFrom(transition) or nil
    local marker = scopedMarker(key, transition)
    local handoffModule = JLP:GetModule("DestinationHandoff")
    local handoff = handoffModule and handoffModule.BuildFrom and handoffModule:BuildFrom(transition, routeStatus, marker, navigation, context, nil) or nil

    if decision then
        decision.travelPlan = travelPlan
        decision.travelTransition = transition
        decision.navigationGuidance = navigation
        decision.destinationHandoff = handoff
        decision.scopedProfession = key
        if decision.selected then
            decision.selected.routeSession = routeStatus
            decision.selected.routeSessionEngaged = routeStatus and routeStatus.active and routeStatus.active.enteredAt ~= nil and (routeStatus.remainingActions or 0) > 0 or false
        end
    end

    return {
        contract = self.contract,
        key = key,
        profession = professionLabel(key),
        workspace = workspace,
        nextBest = decision,
        routeSession = routeStatus,
        travelSession = travelStatus,
        travelTransition = transition,
        navigationGuidance = navigation,
        routeMarker = marker,
        destinationHandoff = handoff,
        recovery = recoveryStatusFor(key),
    }
end

function ProfessionGuideScope:GetSummary()
    local lines = {"Profession Guide scope: isolated READINESS & WORKSPACE projections"}
    for _, key in ipairs(productionKeys()) do
        local status = self:Build(key)
        local selected = status.nextBest and status.nextBest.selected or nil
        lines[#lines + 1] = string.format("%s · next %s · travel %s · recovery %s", professionLabel(key), tostring(selected and selected.requiredLabel or "complete"), tostring(status.travelSession and status.travelSession.guideText or "unavailable"), tostring(status.recovery and status.recovery.label or "unavailable"))
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ProfessionGuideScope", ProfessionGuideScope)
