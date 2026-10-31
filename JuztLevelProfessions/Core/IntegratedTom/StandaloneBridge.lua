local _, JLP = ...
local JT = JLP._integratedTom
-- No JuztLevel files or database entries are modified. All external module
-- invocations are guarded; an absent JuztLevel is a normal standalone state.
local function jlp()
    local root=_G.JuztLevelProfessions
    return type(root)=="table" and type(root.GetModule)=="function" and root or nil
end
local function module(name)
    local root=jlp()
    if not root then return nil end
    local ok,result=pcall(root.GetModule,root,name)
    return ok and type(result)=="table" and result or nil
end
local function invoke(target,method,...)
    if type(target)~="table" or type(target[method])~="function" then return nil,"API_UNAVAILABLE" end
    local ok,a,b,c=pcall(target[method],target,...)
    if not ok then return nil,"API_ERROR" end
    return a,b,c
end
function JT:GetBridgeState()
    local root=jlp()
    return root and tostring(root.version or "connected") or "not installed"
end
function JT:ReadGathering()
    local state=module("GatheringSharedMapState")
    local router=module("GatheringRouteService")
    if not state or not router then return nil,"JUZTLEVEL_NOT_READY" end
    local snapshot=invoke(state,"GetSnapshot")
    if type(snapshot)~="table" then return nil,"MAP_STATE_UNAVAILABLE" end
    local owner=router._presentationContext
    local mapID=type(owner)=="table" and owner.mapID or snapshot.selectedMapID
    if not JT:ValidPoint(mapID,0,0) then return nil,"NO_ROUTE_MAP" end
    local current,reason=invoke(router,"ContextIsCurrent",mapID)
    if current~=true then return nil,reason or "ROUTE_CONTEXT_CHANGED" end
    local routes,status=invoke(router,"GetRoutes",mapID)
    if status~="READY" or type(routes)~="table" then return nil,status or "NO_READY_ROUTE" end
    -- v2 owner receipts are required after the user's Generate Route action.
    if type(owner)~="table" or owner.mapID~=mapID or
       owner.generation~=router._schedulerGeneration then return nil,"UNQUALIFIED_GENERATION" end
    local token=invoke(router,"GetContextToken",mapID)
    if type(token)~="string" or token=="" then return nil,"MISSING_CONTEXT_TOKEN" end
    local signature=mapID.."|"..token.."|"..tostring(owner.generation)
    local existing=JT.gatheringState
    if existing and existing.signature==signature then
        return {mapID=mapID,token=token,generation=owner.generation,routes=existing.routes}
    end
    local result={mapID=mapID,token=token,generation=owner.generation,routes={}}
    for _,key in ipairs({"HERBALISM","MINING"}) do
        local src=routes[key]
        if type(src)=="table" and type(src.points)=="table" then
            local points={}
            for i,p in ipairs(src.points) do
                if i>1000 then break end
                if type(p)=="table" and JT:ValidPoint(mapID,p.x,p.y) then
                    local label=tostring(p.resourceKey or key):gsub("_"," ")
                    points[#points+1]=JT:CleanPoint(mapID,p.x,p.y,label,"GATHERING")
                end
            end
            if #points>0 then result.routes[key]={key=key,points=points,closed=src.closed==true} end
        end
    end
    if not next(result.routes) then return nil,"NO_VALID_ROUTE_STOPS" end
    return result
end
function JT:GetPrimarySlots()
    local workspace=module("ProfessionWorkspace")
    if not workspace then return {},"PROFESSION_WORKSPACE_UNAVAILABLE" end
    local slots=invoke(workspace,"GetPrimarySlots")
    if type(slots)~="table" then return {},"PRIMARY_SLOTS_UNAVAILABLE" end
    local result={}
    for i=1,2 do
        local p=slots[i]
        if type(p)=="table" and p.state=="learned" and type(p.key)=="string" then
            result[#result+1]={key=p.key,name=tostring(p.name or p.key),skill=p.skill}
        end
    end
    return result
end
function JT:IsPrimarySelected(key)
    local p=self.profile
    if not p then return false end
    if not p.selectedSetExplicit then return true end
    return p.selected[key]==true
end
function JT:TogglePrimary(key)
    local slots=self:GetPrimarySlots()
    local isLearned=false
    for _,s in ipairs(slots) do if s.key==key then isLearned=true end end
    if not isLearned then return false,"PROFESSION_NOT_LEARNED" end
    local p=self.profile
    if not p.selectedSetExplicit then
        for _,s in ipairs(slots) do p.selected[s.key]=true end
        p.selectedSetExplicit=true
    end
    p.selected[key]=not p.selected[key]
    if self.focusPrimary==key and not p.selected[key] then self.focusPrimary=nil end
    self.stepCache=nil
    self:Refresh(true)
    return true
end
local function sourcePoint(source,profession,title)
    if type(source)~="table" or type(source.nav)~="table" then return nil end
    local nav=source.nav
    local point=JT:CleanPoint(nav.mapID,nav.x,nav.y,
        tostring(source.name or source.recipe or title or profession),"CURRENT_STEP")
    if point then
        point.key=profession
        point.description=tostring(title or "Current step")
        point.zone=source.zone
        point.evidence=nav.evidence or source.evidence
    end
    return point
end
function JT:GetCurrentTargets(force)
    if not force and type(self.stepCache)=="table" and self.stepCacheTicks and self.stepCacheTicks>0 then
        self.stepCacheTicks=self.stepCacheTicks-1
        return self.stepCache
    end
    local slots=self:GetPrimarySlots()
    local planner=module("Planner")
    local result={}
    for _,slot in ipairs(slots) do
        if self:IsPrimarySelected(slot.key) then
            local plan=invoke(planner,"GetProfessionPlan",slot.key)
            local source=type(plan)=="table" and
                (plan.sourceInfo or type(plan.step)=="table" and plan.step.sourceInfo) or nil
            local action=type(plan)=="table" and tostring(plan.action or "Current step") or "No plan available"
            local point=sourcePoint(source,slot.key,slot.name)
            -- A recipe or craft is not automatically a trip to an old trainer.
            -- Display an audited source coordinate ONLY when explicitly sourced.
            result[#result+1]={key=slot.key,name=slot.name,action=action,
                kind=type(plan)=="table" and plan.actionKind or "unavailable",point=point,
                skill=slot.skill,readOnly=type(plan)=="table" and plan.readOnly==true}
        end
    end
    self.stepCache=result
    self.stepCacheTicks=6 -- ~2 seconds on normal refresh cadence
    return result
end
function JT:ActiveCurrentStep(force)
    local candidates=self:GetCurrentTargets(force)
    if #candidates==0 then return nil,"SELECT_PRIMARY_PROFESSION" end
    local chosen
    for _,c in ipairs(candidates) do if c.key==self.focusPrimary then chosen=c;break end end
    chosen=chosen or candidates[1]
    self.focusPrimary=chosen.key
    if not chosen.point then
        return nil,(chosen.name..": NO_AUDITED_COORDINATE"),chosen
    end
    return chosen.point,nil,chosen
end
