local _, JLP = ...
-- Explicit user-triggered profiling snapshot. No background sampling,
-- scriptProfile toggle, saved variables, or native gameplay permission.
local Audit={contract="jlp-performance-observation-70450-v1",nativeDispatchAllowed=false}
local function nonnegative(value)
    return type(value)=="number" and value==value and value>=0 and value~=math.huge
end
local function count(t)
    if type(t)~="table" then return 0 end
    local n=0
    for _ in pairs(t) do n=n+1 end
    return n
end
local function readUsage(update, get)
    if type(update)~="function" or type(get)~="function" then return nil end
    local updated=pcall(update)
    if not updated then return nil end
    local ok,value=pcall(get,JLP.name)
    if ok and nonnegative(value) then return value end
    return nil
end
function Audit:Snapshot()
    local info=JLP:GetModule("ClientBuildInfo")
    local build=info and info.Compare and info:Compare(70450) or nil
    local profiling=false
    if type(GetCVar)=="function" then
        local ok,value=pcall(GetCVar,"scriptProfile")
        profiling=ok and tostring(value)=="1"
    end
    local registry=JLP:GetModule("GatheringDataRegistry")
    local db=JLP.DB
    local account=db and db.account
    local knowledge=account and account.knowledge
    local runtime=JLP.runtime or {}
    local backup=JuztLevelProfessionsDBBackup
    local dbModule=JLP:GetModule("DB")
    local backupStatus=dbModule and dbModule.GetBackupStatus and dbModule:GetBackupStatus() or nil
    local heapKiB=nil
    if type(collectgarbage)=="function" then
        local ok,value=pcall(collectgarbage,"count")
        if ok and nonnegative(value) then heapKiB=value end
    end
    return {
        contract=self.contract,
        clientBuild=build and build.clientBuild or nil,
        buildQualified=build and type(build.clientBuild)=="number" or false, -- observed, not reference matched
        addonMemoryKiB=readUsage(UpdateAddOnMemoryUsage,GetAddOnMemoryUsage),
        addonCpuMs=profiling and readUsage(UpdateAddOnCPUUsage,GetAddOnCPUUsage) or nil,
        cpuProfilingEnabled=profiling,
        historicalSummaryCacheEntries=registry and count(registry._summaryCache) or 0,
        decodedGatheringMaps=registry and count(registry._loadedMaps) or 0,
        totalLuaHeapKiB=heapKiB, -- Entire Lua VM, NOT per-addon allocation.
        persistentItemRecords=count(knowledge and knowledge.items),
        persistentItemNameKeys=count(knowledge and knowledge.itemNames),
        persistentCharacterRecords=count(knowledge and knowledge.characters),
        backupPresent=type(backup)=="table",
        backupQuarantined=backupStatus and backupStatus.protected==true or false,
        retainedRuntimeErrors=count(runtime.errors),
        coalescedRuntimeErrors=runtime.errorCoalesced or 0,
        droppedRuntimeErrors=runtime.errorDropped or 0,
        sourceScope="OBSERVATIONAL_ONLY",
        nativeDispatchAllowed=false,
    }
end
function Audit:Print()
    local s=self:Snapshot()
    if type(JLP.Print)~="function" then return s end
    local function value(x,unit)
        return nonnegative(x) and (string.format("%.2f",x)..(unit or "")) or "UNAVAILABLE"
    end
    JLP:Print("Performance 70450: build="..tostring(s.clientBuild or "UNKNOWN")..
        ", memory="..value(s.addonMemoryKiB," KiB")..
        ", CPU="..value(s.addonCpuMs," ms cumulative"))
    JLP:Print("Cache: historical summaries "..s.historicalSummaryCacheEntries..
        "/24; decoded gathering maps "..s.decodedGatheringMaps..
        "; CPU profiling "..(s.cpuProfilingEnabled and "enabled" or "disabled")..".")
    JLP:Print("SavedVariables knowledge: items="..s.persistentItemRecords..
        ", name keys="..s.persistentItemNameKeys..", characters="..s.persistentCharacterRecords..
        "; backup="..(s.backupQuarantined and "QUARANTINE" or (s.backupPresent and "CHECKPOINT" or "NONE"))..".")
    JLP:Print("Errors retained="..s.retainedRuntimeErrors.."/64, coalesced="..
        s.coalescedRuntimeErrors..", dropped="..s.droppedRuntimeErrors..
        "; full Lua VM heap="..value(s.totalLuaHeapKiB," KiB").." (not addon-only).")
    return s
end
JLP:RegisterModule("PerformanceAudit70450",Audit)
