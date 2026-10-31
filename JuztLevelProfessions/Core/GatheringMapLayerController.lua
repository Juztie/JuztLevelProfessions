local _, JLP = ...
-- Alpha150 presentation-only read model. No source-addon runtime or protected actions.
-- Learned state is evaluated anew on every request, never persisted as authority.
local Controller={contract="gathering-map-layer-controller-v1",nativeDispatchAllowed=false}
local KEYS={"HERBALISM","MINING"}
local function learned(key)
    local api=JLP:GetModule("ProfessionAPI")
    local p=api and api.Get and api:Get(key)
    return type(p)=="table" and p.key==key and p.cached~=true and type(p.skill)=="number",p
end
function Controller:GetLayerState(mapID)
    local shared=JLP:GetModule("GatheringSharedMapState")
    local registry=JLP:GetModule("GatheringDataRegistry")
    local state=shared and shared:GetSnapshot()
    if not state or not registry then return nil,"LAYER_DATA_UNAVAILABLE" end
    local out={mapID=mapID,layers={},nativeDispatchAllowed=false}
    for _,key in ipairs(KEYS) do
        local known,p=learned(key)
        local summary=registry:GetZoneResourceSummary(mapID,key)
        local filter=state.resourceFilters[key]
        local valid=filter==nil
        for _,r in ipairs(summary and summary.resources or {}) do
            if r.resourceKey==filter then valid=true end
        end
        if not valid then filter=nil end -- stale/unknown filter cannot leak unrelated nodes
        local chosen=state.resourceSelectionsByMap and state.resourceSelectionsByMap[mapID]
        chosen=chosen and chosen[key] or nil
        -- Selection keys are validated against available zone resources, never trusted from SavedVariables.
        if type(chosen)=="table" then
            local checked={}
            for _,r in ipairs(summary and summary.resources or {}) do if chosen[r.resourceKey] then checked[r.resourceKey]=true end end
            chosen=checked
            filter=nil -- Multi-select takes precedence over alpha150 single-cycle UI
        end
        local supply=state.supplyGoal
        local supplySelected=(key=="MINING"or key=="HERBALISM")and supply and supply.professionKey==key and supply.mapID==mapID and
            type(supply.resourceKey)=="string"and supply.sourceID~=nil
        if supplySelected then chosen={[supply.resourceKey]=true};filter=nil end
        -- Smart derives learned profession layers automatically. Manual layer
        -- toggles are only relevant to Custom; never grant an unlearned skill.
        out.layers[key]={learned=known,enabled=known and
            (state.mode=="SMART_PROFESSION" or state.layerEnabled[key]==true or supplySelected==true),
            skill=known and p.skill or nil,cached=p and p.cached==true or false,
            resourceFilter=filter,resourceSelection=chosen,resources=summary and summary.resources or {},
            referenceOnly=true}
    end
    return out
end
function Controller:CycleResource(mapID,key)
    if key~="HERBALISM" and key~="MINING" then return false,"LAYER_INVALID" end
    local state,err=self:GetLayerState(mapID)
    if not state then return false,err end
    local layer=state.layers[key]
    if not layer.learned then return false,"PROFESSION_NOT_LEARNED" end
    local list={}
    for _,r in ipairs(layer.resources) do list[#list+1]=r.resourceKey end
    local index=0
    for i,k in ipairs(list) do if k==layer.resourceFilter then index=i;break end end
    local nextKey=(index<#list) and list[index+1] or nil
    return JLP:GetModule("GatheringSharedMapState"):SetResourceFilter(key,nextKey)
end
function Controller:ToggleLayer(mapID,key)
    local shared=JLP:GetModule("GatheringSharedMapState")
    local opts=shared and shared:GetSnapshot()
    if opts and opts.mode=="SMART_PROFESSION" then
        return false,"SMART_LAYER_AUTOMATIC"
    end
    local state,err=self:GetLayerState(mapID)
    if not state then return false,err end
    local layer=state.layers[key]
    if not layer then return false,"LAYER_INVALID" end
    if not layer.learned then return false,"PROFESSION_NOT_LEARNED" end
    return JLP:GetModule("GatheringSharedMapState"):SetLayerEnabled(key,not layer.enabled)
end
function Controller:BuildOverlay(mapID)
    local state,err=self:GetLayerState(mapID)
    if not state then return nil,err end
    local registry=JLP:GetModule("GatheringDataRegistry")
    local shared=JLP:GetModule("GatheringSharedMapState")
    local options=shared and shared:GetSnapshot()
    -- Cached display snapshot: historical reference data are immutable until
    -- an explicit reload. Skills/learned flags and filters remain in cache key.
    local cacheKey=tostring(mapID)
    for _,key in ipairs(KEYS) do
        local layer=state.layers[key]
        cacheKey=cacheKey..":"..key..":"..tostring(layer.enabled)..":"..
            tostring(layer.resourceFilter)..":"..tostring(layer.skill)
        if layer.resourceSelection then
            for _,resource in ipairs(layer.resources) do
                cacheKey=cacheKey..":"..resource.resourceKey.."="..tostring(layer.resourceSelection[resource.resourceKey]==true)
            end
        end
    end
    local observations=JLP:GetModule("GatheringObservationStore")
    -- Imported references are mutable only through the registry epoch. A new
    -- import must invalidate the shared view projection even if filters match.
    cacheKey=cacheKey..":import="..tostring(registry._mutationEpoch or 0)..
        ":observed="..tostring(observations and observations:GetRevision() or 0)..
        ":source="..tostring(options and options.sourceFilter)
    if options and options.mode=="SMART_PROFESSION" and options.focus=="MATERIALS" then
        for _,profession in ipairs(KEYS) do
            local selected=options.smartMaterialTargets and options.smartMaterialTargets[profession] or {}
            local keys={}
            for key,value in pairs(selected) do if value then keys[#keys+1]=key end end
            table.sort(keys)
            cacheKey=cacheKey..":target:"..profession..":"..table.concat(keys,",")
        end
    end
    cacheKey=cacheKey..":supply="..tostring(options and options.supplyGoal and options.supplyGoal.sourceID)
    cacheKey=cacheKey..":"..tostring(options and options.showPins)..":"..
        tostring(options and options.mode)..":"..tostring(options and options.focus)
    local isSmart=options and options.mode=="SMART_PROFESSION"
    local bridge=isSmart and JLP:GetModule("GatheringMaterialBridge") or nil
    local needs,totalNeeds={},0
    if isSmart and bridge and type(bridge.ReadPlannerNeeds)=="function" then
        needs,totalNeeds=bridge:ReadPlannerNeeds()
        if type(needs)~="table" then needs={} end
    end
    if isSmart then
        local keys={}
        for id,value in pairs(needs) do
            if type(id)=="number" and type(value)=="number" and value>0 then
                keys[#keys+1]=tostring(id).."="..tostring(value)
            end
        end
        table.sort(keys)
        cacheKey=cacheKey..":demand="..table.concat(keys,",")
    end
    if self._overlayCacheKey==cacheKey and self._overlayCache then
        return self._overlayCache
    end
    local observed=observations and observations:GetZoneSnapshot(mapID)
    local verified={}
    for _,o in ipairs(observed and observed.verified or {}) do
        if o.matchedReferenceID then verified[o.matchedReferenceID]=o end
    end
    local result={mapID=mapID,referenceOnly=false,enabled=false,observationCount=0,
        unresolvedCount=observed and observed.unresolvedCount or 0,
        total=0,points={},layers=state.layers,nativeDispatchAllowed=false,
        -- One generated read-only display model, never a raw/import record.
        -- A matching receipt certifies the layer controller's snapshot epoch.
        __jlpLayerSnapshotKey=cacheKey}
    if not options or options.showPins==false then
        self._overlayCacheKey=cacheKey;self._overlayCache=result
        return result
    end
    local clothGoal=options and options.supplyGoal
    if clothGoal and clothGoal.professionKey=="CLOTH"and clothGoal.status=="CLOTH_LOOT"and clothGoal.mapID==mapID then
        local supply=JLP:GetModule("GatheringMaterialBridge")
        local point=supply and supply:GetClothWaypoint(clothGoal.itemID,clothGoal.sourceID)
        if point then
            result.enabled=true;result.total=result.total+1
            result.points[#result.points+1]={x=point.nav.x,y=point.nav.y,professionKey="CLOTH",resourceKey="CLOTH_"..clothGoal.itemID,
             npcID=point.npcID,itemID=clothGoal.itemID,sources={point.sourceURL,point.positionURL},sourceConfidence="HISTORICAL_CLOTH_REFERENCE_NOT_LIVE_SPAWN",clothLoot=true}
        end
    end
    local evaluator=isSmart and JLP:GetModule("NodeSkillEvaluator") or nil
    local smartMemo={}
    local function smartAllowed(profession,resource,required,skill)
        if not isSmart or not bridge or not evaluator then return false end
        local key=tostring(profession)..":"..tostring(resource)..":"..tostring(required)..":"..tostring(skill)
        if smartMemo[key]~=nil then return smartMemo[key] end
        local evaluated=evaluator:Evaluate({professionKey=profession,resourceKey=resource,requiredSkill=required},skill,"SMART_PROFESSION")
        local eligible=evaluated and evaluated.smartEligible==true
        local material=bridge:MatchMaterialNeeds(profession,resource,needs)
        local demand=material and (material.weightedDemand or 0)>0
        local progress=evaluated and evaluated.progressionEligibility=="POSSIBLE"
        local focus=options.focus
        local generic=false
        if (focus=="MATERIALS" or focus=="BALANCED") and totalNeeds==0 and
            type(bridge.HasQualifiedGenericOutput)=="function" then
            -- Historical coverage, not measured spawn probability / loot yield.
            generic=bridge:HasQualifiedGenericOutput(profession,resource)==true
        end
        if focus=="MATERIALS" then
            local supply=options.supplyGoal
            if (profession=="MINING"or profession=="HERBALISM")and supply and supply.professionKey==profession and supply.mapID==mapID and supply.resourceKey==resource then
                smartMemo[key]=eligible;return eligible
            end
            local selected=options.smartMaterialTargets and options.smartMaterialTargets[profession]
            local allowed=eligible and selected and selected[resource]==true or false
            smartMemo[key]=allowed
            return allowed
        end
        local allowed=eligible and ((focus=="SKILL" and progress) or
            (focus=="BALANCED" and (progress or demand or generic)) or
            (focus=="MATERIALS" and (demand or generic))) or false
        smartMemo[key]=allowed
        return allowed
    end
    for _,key in ipairs(KEYS) do
        local layer=state.layers[key]
        if layer.enabled then
            result.enabled=true
            local snapshot=registry:GetZoneSnapshot(mapID,key)
            for _,rec in ipairs(snapshot and snapshot.references or {}) do
                if rec.geometryType=="POINT" and (isSmart and smartAllowed(key,rec.resourceKey,rec.requiredSkill,layer.skill) or
                    not isSmart and layer.resourceSelection and layer.resourceSelection[rec.resourceKey]==true) then
                    local identity=JLP:GetModule("GatheringReferenceIdentity")
                    local id=identity and identity:FromReference(rec,mapID)
                    local own=verified[id]
                    if options.sourceFilter~="OBSERVED_ONLY" or own then
                        result.total=result.total+1
                        if own then result.observationCount=result.observationCount+1 end
                        result.points[#result.points+1]={x=rec.x,y=rec.y,resourceKey=rec.resourceKey,
                            professionKey=key,objectID=rec.objectID,requiredSkill=rec.requiredSkill,
                            sources=rec.sources,personallyObserved=own~=nil,
                            observedAt=own and own.observedAt,count=own and own.count,
                            sourceConfidence=rec.sourceConfidence,skill=layer.skill}
                    end
                end
            end
        end
    end
    -- Player-only positions are shown as approximate gather locations, not
    -- reclassified as preloaded historical reference nodes.
    for _,o in ipairs(observed and observed.verified or {}) do
        local layer=state.layers[o.professionKey]
        if layer and layer.enabled and not o.matchedReferenceID and
            (isSmart and smartAllowed(o.professionKey,o.resourceKey,o.requiredSkill,layer.skill) or
            not isSmart and layer.resourceSelection and layer.resourceSelection[o.resourceKey]==true) then
            result.total=result.total+1
            result.observationCount=result.observationCount+1
            result.points[#result.points+1]={x=o.x,y=o.y,professionKey=o.professionKey,
                resourceKey=o.resourceKey,personallyObserved=true,personalOnly=true,
                observedAt=o.observedAt,count=o.count,sources={"PERSONAL_OBSERVATION"},skill=layer.skill}
        end
    end
    self._overlayCacheKey=cacheKey;self._overlayCache=result
    return result
end
JLP:RegisterModule("GatheringMapLayerController",Controller)
