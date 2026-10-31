local _, JLP = ...

-- Compatibility facade retained for /jlp requalify and existing diagnostics.
-- All policy/data/build parsing now belongs to BuildRequalificationService.
local Facade = {
    contract = "current-build-profession-requalification-v1",
    targetBuild = 70245,
    persisted = false,
    nativeDispatchAllowed = false,
}

local function service()
    return JLP:GetModule("BuildRequalificationService")
end

function Facade:AuditProfession(key, buildOverride)
    local svc = service()
    return svc and svc:AuditProfession(key, buildOverride) or {professionKey=key,state="service-missing",structuralReady=false,datasetRequalified=false}
end

function Facade:AuditAll(buildOverride)
    local svc = service()
    return svc and svc:AuditAll(buildOverride) or {contract=self.contract,targetBuild=self.targetBuild,rows={},structuralReadyCount=0,datasetRequalifiedCount=0,nativeDispatchAllowed=false,persisted=false}
end

function Facade:AssessOpenProfession()
    local svc = service()
    return svc and svc:AssessOpenProfession() or {state="service-missing",nativeDispatchAllowed=false,persisted=false}
end

function Facade:GetSummary()
    local svc = service()
    return svc and svc:GetSummary() or "Current-build requalification service unavailable · native dispatch forbidden"
end

function Facade:Validate()
    local svc = service()
    return svc and svc:ValidateStaticDatasets() or {"build-requalification-service-missing"}
end

JLP:RegisterModule("CurrentBuildRequalification", Facade)
