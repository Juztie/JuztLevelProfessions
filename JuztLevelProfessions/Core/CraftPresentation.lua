local _, JLP = ...
-- Pure read-only ETA: strictly from observed, reconciled ordinal progress.
local Service={nativeDispatchAllowed=false,contract="craft-presentation-estimated-v1"}
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function clock()
    if type(GetTime)=="function" then return GetTime() end
    return nil
end
function Service:Get(key,plan)
    local c=JLP:GetModule("Crafting")
    local p=c and c.pendingCraft
    if type(p)~="table" or p.key~=key or p.mode~="all" then return {active=false,etaText="UNKNOWN"} end
    local result={active=true,completed=tonumber(p.completedCount) or 0,
        requested=tonumber(p.requestedCount) or 0,etaText="ETA UNKNOWN",nativeDispatchAllowed=false}
    if p.strictTargetSafeCraftAll~=true or p.strictAwaitingUserClick==true or p.repeatStopRequested or p.status=="recovery_unresolved" or
        p.status=="failed" or not plan or not plan.step or plan.step.recipe~=p.recipeName or
        tonumber(plan.step.skillTarget)~=tonumber(p.targetSkill) then
        result.reason=p.strictAwaitingUserClick==true and "NEXT_HARDWARE_CLICK_REQUIRED" or "UNVERIFIED_OR_STALE_ORDINAL_STATE";return result
    end
    local t=clock()
    if not finite(t) or not finite(p.startedAt) or t<p.startedAt or
        not finite(result.completed) or result.completed<1 or result.requested<result.completed then
        result.reason="INSUFFICIENT_CONFIRMED_ORDINALS";return result end
    local elapsed=t-p.startedAt
    if elapsed<=0 then return result end
    local left=math.ceil(elapsed/result.completed*(result.requested-result.completed))
    if not finite(left) or left<0 then return result end
    result.elapsed=elapsed;result.remainingSeconds=left
    result.etaText=string.format("%d/%d observed · %ds elapsed · ~%ds left (estimate)",
        result.completed,result.requested,math.floor(elapsed),left)
    return result
end
JLP:RegisterModule("CraftPresentation",Service)
