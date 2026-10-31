-- Deterministic, WoW-independent journey state machine. All world observations injected.
local _, JLP = ...
local T = JLP._integratedTravel
local C=T.Contract
local Journey={}
Journey.__index=Journey
function Journey.New()
    return setmetatable({plan=nil,index=0,state='IDLE',lastLocation=nil,lastError=nil,sequence=0},Journey)
end
function Journey:Start(plan)
    if type(plan)~='table' or plan.contract~=T.contract or type(plan.legs)~='table' then return false,'PLAN_CONTRACT_MISMATCH' end
    self.plan=plan;self.index=1;self.sequence=self.sequence+1;self.lastError=nil;self.lastLocation=nil
    self.state=#plan.legs==0 and 'ARRIVED' or 'ACTIVE'
    return true
end
function Journey:Stop()
    self.plan=nil;self.index=0;self.state='IDLE';self.lastError=nil;self.sequence=self.sequence+1
end
function Journey:CurrentLeg()
    return self.plan and self.plan.legs[self.index] or nil
end
function Journey:Advance()
    if not self.plan or self.state=='IDLE' then return false,'NO_ACTIVE_PLAN' end
    self.index=self.index+1
    self.state=self.index>#self.plan.legs and 'ARRIVED' or 'ACTIVE'
    return true
end
function Journey:Observe(point,arrivalRadius)
    if not self.plan then return nil,'NO_ACTIVE_PLAN' end
    local loc,why=C.point(point);if not loc then return nil,why end
    self.lastLocation=loc
    local leg=self:CurrentLeg()
    if not leg then return self:Guidance() end
    local radius=tonumber(arrivalRadius) or 0.002
    if not C.finite(radius) or radius<=0 or radius>0.1 then radius=0.002 end
    if leg.mode=='WALK' then
        if loc.mapID==leg.to.mapID and C.distance(loc,leg.to)<=radius then
            self:Advance()
        elseif loc.mapID~=leg.from.mapID and loc.mapID~=leg.to.mapID then
            self.lastError='PLAYER_OFF_EXPECTED_MAP'
        else self.lastError=nil end
    else
        -- Cross-map transition: only arrival on destination map is strong enough
        -- to advance; never assume a transport trip from a simple distance check.
        if leg.to.mapID~=leg.from.mapID and loc.mapID==leg.to.mapID then
            self:Advance()
        elseif leg.to.mapID==leg.from.mapID and C.distance(loc,leg.to)<=radius then
            self:Advance()
        elseif loc.mapID~=leg.from.mapID and loc.mapID~=leg.to.mapID then
            self.lastError='UNEXPECTED_MAP_DURING_TRANSFER'
        else self.lastError=nil end
    end
    return self:Guidance()
end
function Journey:Guidance()
    if not self.plan then return {contract=T.contract,phase='IDLE',waypoint=nil} end
    if self.state=='ARRIVED' then return {contract=T.contract,phase='ARRIVED',waypoint=nil,index=self.index,total=#self.plan.legs} end
    local leg=self:CurrentLeg()
    if not leg then return {contract=T.contract,phase='ERROR',reason='MISSING_LEG'} end
    if leg.mode=='WALK' then
        local nextLeg=self.plan.legs[self.index+1]
        local flightDestination=nextLeg and nextLeg.mode=='FLIGHT' and
            nextLeg.from.mapID==leg.to.mapID and
            nextLeg.toPlaceName and nextLeg.toPlaceName~='' and nextLeg.toPlaceName or nil
        local marker=leg.to.label~='' and leg.to.label or 'the next waypoint'
        local instruction=flightDestination and
            ('Speak with Flight Master '..marker..' and fly to '..flightDestination..'.') or
            ('Travel toward '..marker..'.')
        return {contract=T.contract,phase='WALK_TO_WAYPOINT',waypoint=C.copyPoint(leg.to),
            instruction=instruction,
            displayTitle=flightDestination and ('Fly to '..flightDestination) or nil,
            displayDetail=flightDestination and ('Flight Master: '..marker) or nil,
            nextFlightDestination=flightDestination,
            index=self.index,total=#self.plan.legs,reason=self.lastError}
    end
    local atDestination=leg.from.mapID~=leg.to.mapID and self.lastLocation and self.lastLocation.mapID==leg.to.mapID
    return {contract=T.contract,phase=atDestination and 'TRANSFER_ARRIVAL' or 'WAIT_FOR_TRANSPORT',
        waypoint=nil,instruction='Use '..leg.mode..' transport to '..(leg.to.label~='' and leg.to.label or 'the next map')..'.',
        transport=leg.mode,from=C.copyPoint(leg.from),to=C.copyPoint(leg.to),
        index=self.index,total=#self.plan.legs,reason=self.lastError}
end
function Journey:ConfirmTransfer()
    local leg=self:CurrentLeg()
    if not leg or leg.mode=='WALK' then return false,'NO_TRANSFER_TO_CONFIRM' end
 if leg.from.mapID==leg.to.mapID then return false,'SAME_MAP_TRANSPORT_UNVERIFIED' end
    -- A manual confirmation is not sufficient to assert the player is on
    -- the target map. This is intentionally conservative.
    if not self.lastLocation or self.lastLocation.mapID~=leg.to.mapID then return false,'DESTINATION_MAP_NOT_OBSERVED' end
    return self:Advance()
end
T.Journey=Journey
