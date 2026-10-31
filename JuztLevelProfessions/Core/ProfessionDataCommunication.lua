local _, JLP = ...

-- Strict multiplexer for the archived 70374 and 70450 references.
-- Data source selection is independent of the running client's build;
-- explicit provenance selectors remain validated and reference-only.
local Service={contract="JLP-PROFESSION-DATA-COMMUNICATION-VERSIONED-1",
    readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
    productionAuthority=false,supportedSourceBuilds={[70374]=true,[70450]=true}}
local function actual()
    local info=JLP:GetModule("ClientBuildInfo")
    if not info or type(info.GetBuildNumber)~="function" then return nil end
    local ok,build=pcall(info.GetBuildNumber,info)
    if not ok or type(build)~="number" or build~=build or
        build<=0 or build~=math.floor(build) or build>9007199254740991 then return nil end
    return build
end
local function choose(options)
    options=type(options)=="table" and options or {}
    local observed=actual()
    -- Prefer the newest INSTALLED, qualified static reference, regardless of
    -- current client build. Explicit requests still pin their source build.
    local source=options.sourceBuild
    if source==nil then
        local latest=JLP:GetModule("ProfessionDataBridge70450")
        source=(latest and latest.sourceBuild==70450 and
            latest.readOnly==true and latest.nativeDispatchAllowed==false and
            latest.executionEligible==false) and 70450 or 70374
    end
    if type(source)~="number" or not Service.supportedSourceBuilds[source] then
        return nil,"SOURCE_DATASET_UNAVAILABLE"
    end
    local name=source==70450 and "ProfessionDataBridge70450" or "ProfessionDataBridge70374"
    local bridge=JLP:GetModule(name)
    if not bridge or bridge.sourceBuild~=source or bridge.readOnly~=true or
       bridge.nativeDispatchAllowed~=false or bridge.executionEligible~=false then
        return nil,"VERSIONED_BRIDGE_UNAVAILABLE_OR_PRIVILEGED"
    end
    return bridge,nil,observed
end
function Service:GetActiveBuild(options)
    local bridge,why,observed=choose(options)
    if not bridge then return nil,why end
    return {contract=self.contract,sourceBuild=bridge.sourceBuild,clientBuild=observed,
        clientBuildRelation=not observed and "UNKNOWN_CLIENT" or
            (observed==bridge.sourceBuild and "MATCH" or "HISTORICAL_REFERENCE"),
        bridgeContract=bridge.contract,readOnly=true,nativeDispatchAllowed=false,
        productionAuthority=false},nil
end
function Service:GetProfessionState(key,options)
    local b,why=choose(options);if not b then return nil,why end
    return b:GetProfessionState(key,options)
end
function Service:GetRecipeState(key,spellID,crafts,options)
    local b,why=choose(options);if not b then return nil,why end
    return b:GetRecipeState(key,spellID,crafts,options)
end
function Service:BuildMaterialsState(steps,options)
    local b,why=choose(options);if not b then return nil,why end
    return b:BuildMaterialsState(steps,options)
end
function Service:GetProgressionState(key,skill,options)
    local b,why=choose(options);if not b then return nil,why end
    return b:GetProgressionState(key,skill,options)
end
function Service:ValidateState(state)
    if type(state)~="table" or not self.supportedSourceBuilds[state.sourceBuild] then
        return false,"UNSUPPORTED_RECEIPT_SOURCE_BUILD" end
    local b,why=choose({sourceBuild=state.sourceBuild})
    if not b then return false,why end
    if state.contract~=b.contract then return false,"RECEIPT_CONTRACT_MISMATCH" end
    return b:ValidateState(state)
end
JLP:RegisterModule("ProfessionDataCommunication",Service)
