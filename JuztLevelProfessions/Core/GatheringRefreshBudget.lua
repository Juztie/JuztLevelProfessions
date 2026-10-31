local _, JLP = ...
-- Alpha180: pure presentation scheduling, NOT a route/observation owner.
-- No timers or saved variables. The actual WoW frame remains in control.
local Budget={contract="jlp-gathering-refresh-budget-v1",nativeDispatchAllowed=false,heartbeatSeconds=6}
function Budget:New()
    return {idleSeconds=0,checked=0,refreshed=0,skipped=0,lastReason="INITIAL"}
end
function Budget:ShouldRefresh(job,elapsed,signals)
    if type(job)~="table" then return true,"NO_BUDGET" end
    signals=type(signals)=="table" and signals or {}
    local dt=type(elapsed)=="number" and elapsed>=0 and elapsed<60 and elapsed or 0
    job.idleSeconds=(job.idleSeconds or 0)+dt
    job.checked=(job.checked or 0)+1
    local reason=signals.viewportChanged and "VIEWPORT_CHANGED" or
        signals.force and "DIRTY_VIEW" or
        signals.generating and "ACTIVE_JOB" or
        signals.moving and "PLAYER_MOVING" or
        job.idleSeconds>=self.heartbeatSeconds and "HEARTBEAT" or nil
    if reason then
        job.idleSeconds=0
        job.refreshed=(job.refreshed or 0)+1
        job.lastReason=reason
        return true,reason
    end
    job.skipped=(job.skipped or 0)+1
    job.lastReason="UNCHANGED"
    return false,"UNCHANGED"
end
JLP:RegisterModule("GatheringRefreshBudget",Budget)
