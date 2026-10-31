local _, JLP = ...
-- Discovers zone IDs only through C_Map. No hardcoded / guessed uiMapIDs.
-- Lists EXACT unambiguous matching Fishing-guide zone names from the current continent.
local Browser={contract="forever-fishing-zone-browser-v1",nativeDispatchAllowed=false,maxZones=256}
local function posint(v)
    return type(v)=="number" and v==v and v~=math.huge and v>=1 and v==math.floor(v)
end
local function safe(fn,...)
    if type(fn)~="function" then return nil end
    local ok,result=pcall(fn,...);if ok then return result end
end
function Browser:Discover(currentZone)
    local api=C_Map
    if type(api)~="table" or type(api.GetMapInfo)~="function" or
        type(api.GetMapChildrenInfo)~="function" then return {},"MAP_BROWSER_API_UNAVAILABLE" end
    if not currentZone or not posint(currentZone.mapID) then return {},"PLAYER_ZONE_UNAVAILABLE" end
    local id=currentZone.mapID
    local seen={}
    local continent
    for _=1,8 do
        if seen[id] then return {},"MAP_PARENT_CYCLE" end
        seen[id]=true
        local info=safe(api.GetMapInfo,id)
        if type(info)~="table" then return {},"MAP_PARENT_UNAVAILABLE" end
        if info.mapType==2 then continent=id;break end
        id=info.parentMapID
        if not posint(id) then return {},"CONTINENT_UNAVAILABLE" end
    end
    if not continent then return {},"CONTINENT_UNAVAILABLE" end
    local children=safe(api.GetMapChildrenInfo,continent,3,true)
    if type(children)~="table" then return {},"ZONE_LIST_UNAVAILABLE" end
    local zone=JLP:GetModule("ForeverFishingZoneModel")
    if not zone then return {},"FISHING_EVIDENCE_UNAVAILABLE" end
    local entries={};local visited={}
    local shared=JLP:GetModule("GatheringSharedMapState")
    local preferences=shared and shared:GetSnapshot()
    local layerFlags=preferences and preferences.layerEnabled
    local wantsGathering=layerFlags and (layerFlags.HERBALISM or layerFlags.MINING)
    -- Bound both enumerated candidates and accepted options; client-owned IDs.
    for i=1,math.min(#children,1024) do
        local item=children[i]
        if type(item)=="table" and posint(item.mapID) and not visited[item.mapID] and item.mapType==3 then
            visited[item.mapID]=true
            local info=safe(api.GetMapInfo,item.mapID)
            if type(info)=="table" and info.mapType==3 and info.name==item.name and
                type(info.name)=="string" and info.name~="" then
                -- Fishing guide entries containing area exclusions cannot be equated
                -- with a whole zone just because the label shares a base name.
                local proof=zone:LookupMap(item.mapID,0,nil)
                -- Existing Fishing guide zones remain primary. If a learned
                -- gathering layer is explicitly enabled, also browse zones with
                -- packaged historical references. IDs and labels still come
                -- from the CLIENT, not the addon source dataset.
                local gathering=false
                local layers=wantsGathering and JLP:GetModule("GatheringMapLayerController")
                local active=layers and layers:GetLayerState(item.mapID)
                if active then
                    for _,key in ipairs({"HERBALISM","MINING"}) do
                        local row=active.layers[key]
                        if row and row.enabled and #(row.resources or {})>0 then
                            gathering=true;break
                        end
                    end
                end
                if (proof and proof.selected) or gathering then
                    entries[#entries+1]={mapID=item.mapID,name=info.name,
                        minSkill=proof and proof.selected and proof.selected.minSkill or nil,
                        guaranteedCatchSkill=proof and proof.selected and proof.selected.guaranteedCatchSkill or nil,
                        sourceURL=proof and proof.sourceURL or nil,
                        gatheringReferenceOnly=gathering and not (proof and proof.selected) or false}
                end
            end
        end
    end
    table.sort(entries,function(a,b) if a.name==b.name then return a.mapID<b.mapID end return a.name<b.name end)
    if #entries>self.maxZones then
        for i=#entries,self.maxZones+1,-1 do entries[i]=nil end
    end
    return entries,#entries>0 and "CLIENT_SOURCED" or "NO_MATCHING_FISHING_ZONES"
end
-- Named continent navigation for the standalone map. Anchor zones are known
-- native mapIDs; their continent parents and the complete zone list are always
-- resolved from the running client's C_Map registry (including Forever zones).
-- No guessed zone IDs, zone-name matching, fishing-skill filtering or route data.
local CONTINENTS={KALIMDOR={anchor=1413},EASTERN_KINGDOMS={anchor=1428}}
function Browser:GetContinentMapID(key)
    local spec=CONTINENTS[key]
    if not spec then return nil,"CONTINENT_INVALID" end
    local api=C_Map
    if type(api)~="table" or type(api.GetMapInfo)~="function" then
        return nil,"MAP_BROWSER_API_UNAVAILABLE" end
    local id=spec.anchor
    local seen={}
    for _=1,8 do
        if not posint(id) or seen[id] then return nil,"CONTINENT_UNAVAILABLE" end
        seen[id]=true
        local info=safe(api.GetMapInfo,id)
        if type(info)~="table" then return nil,"MAP_PARENT_UNAVAILABLE" end
        if info.mapType==2 then return id,"CLIENT_CONTINENT" end
        id=info.parentMapID
    end
    return nil,"CONTINENT_UNAVAILABLE"
end
-- Check the complete native parent chain. This permits cross-continent
-- selections even if the player is standing on the opposite continent.
function Browser:IsContinentZone(mapID,key)
    if not posint(mapID) then return false end
    local api=C_Map
    if type(api)~="table" or type(api.GetMapInfo)~="function" then return false end
    local info=safe(api.GetMapInfo,mapID)
    if type(info)~="table" or info.mapType~=3 then return false end
    local root=self:GetContinentMapID(key)
    if not root then return false end
    local id=mapID
    local seen={}
    for _=1,9 do
        if not posint(id) or seen[id] then return false end
        if id==root then return true end
        seen[id]=true
        local parent=safe(api.GetMapInfo,id)
        id=parent and parent.parentMapID
    end
    return false
end
function Browser:DiscoverContinent(key)
    local api=C_Map
    if type(api)~="table" or type(api.GetMapChildrenInfo)~="function" then
        return {},"ZONE_LIST_UNAVAILABLE" end
    local root,reason=self:GetContinentMapID(key)
    if not root then return {},reason end
    local children=safe(api.GetMapChildrenInfo,root,3,true)
    if type(children)~="table" then return {},"ZONE_LIST_UNAVAILABLE" end
    local entries,seen={},{}
    for i=1,math.min(#children,1024) do
        local row=children[i]
        local id=type(row)=="table" and row.mapID
        if posint(id) and not seen[id] then
            seen[id]=true
            local info=safe(api.GetMapInfo,id)
            if type(info)=="table" and info.mapType==3 and
                type(info.name)=="string" and info.name~="" and
                self:IsContinentZone(id,key) then
                entries[#entries+1]={mapID=id,name=info.name,continent=key}
            end
        end
    end
    table.sort(entries,function(a,b)
        if a.name==b.name then return a.mapID<b.mapID end
        return a.name<b.name
    end)
    if #entries>self.maxZones then
        for i=#entries,self.maxZones+1,-1 do entries[i]=nil end
    end
    return entries,#entries>0 and "CLIENT_SOURCED" or "NO_CLIENT_ZONES"
end
function Browser:ResolveSelection(currentZone,rawSkill,bonus)
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    if not currentZone or not map then return nil,"PLAYER_ZONE_UNAVAILABLE" end
    local zones,status=self:Discover(currentZone)
    local shared=JLP:GetModule("GatheringSharedMapState")
    local snapshot=shared and shared:GetSnapshot()
    local wanted=snapshot and snapshot.selectedMapID
    -- A continent-menu selection is not limited to the player's current
    -- continent or to the fishing guide's evidence-filtered legacy list.
    if posint(wanted) and (self:IsContinentZone(wanted,"KALIMDOR") or
        self:IsContinentZone(wanted,"EASTERN_KINGDOMS")) then
        local context=map:GetZoneByID(wanted,rawSkill,bonus)
        if context then
            return {context=context,zones=zones,index=nil,browsing=true,
                source="CLIENT_CONTINENT_SELECTION"}
        end
    end
    local selectedIndex=nil
    for i,z in ipairs(zones) do if z.mapID==wanted then selectedIndex=i;break end end
    local selected=selectedIndex and zones[selectedIndex]
    if selected then
        local context=map:GetZoneByID(selected.mapID,rawSkill,bonus)
        if context then return {context=context,zones=zones,index=selectedIndex,
            browsing=true,source=status} end
    end
    local currentIndex=nil
    for i,z in ipairs(zones) do if z.mapID==currentZone.mapID then currentIndex=i;break end end
    return {context=currentZone,zones=zones,index=currentIndex,browsing=false,source=status}
end
function Browser:Step(currentZone,direction)
    if direction~=1 and direction~=-1 then return false,"DIRECTION_INVALID" end
    local shared=JLP:GetModule("GatheringSharedMapState")
    local snapshot=shared and shared:GetSnapshot()
    local requested=snapshot and snapshot.selectedMapID
    local continentMode=snapshot and snapshot.zoneBrowseScope=="CONTINENT"
    if continentMode and posint(requested) and not (self:IsContinentZone(requested,"KALIMDOR") or
        self:IsContinentZone(requested,"EASTERN_KINGDOMS")) then
        return false,"SELECTED_ZONE_UNAVAILABLE"
    end
    local resolved,reason=self:ResolveSelection(currentZone)
    if not resolved then return false,reason end
    local zones=resolved.zones
    local index=resolved.index
    -- Persisted selection origin disambiguates continent-menu choices from
    -- ordinary guide arrows; both can have a valid selectedMapID.
    -- The guide flow MUST remain guide-filtered after repeated arrow clicks.
    if continentMode then
        local selected=resolved.context and resolved.context.mapID
        local continent=selected and (self:IsContinentZone(selected,"KALIMDOR") and "KALIMDOR" or
            self:IsContinentZone(selected,"EASTERN_KINGDOMS") and "EASTERN_KINGDOMS")
        if not continent then return false,"SELECTED_CONTINENT_UNAVAILABLE" end
        local list,why=self:DiscoverContinent(continent)
        if type(list)~="table" or #list==0 then return false,why or "NO_CLIENT_ZONES" end
        zones=list
        index=nil
        for i,row in ipairs(zones) do if row.mapID==selected then index=i;break end end
        if not index then return false,"SELECTED_ZONE_NOT_IN_CLIENT_LIST" end
    end
    if type(zones)~="table" or #zones==0 then return false,"NO_MATCHING_FISHING_ZONES" end
    if not continentMode and posint(requested) then
        -- ResolveSelection can display an explicitly selected zone without
        -- assigning its index in the guide-filtered list. Recompute it here.
        for i,row in ipairs(zones) do if row.mapID==requested then index=i;break end end
    end
    index=index or (direction==1 and 0 or 1)
    local nextIndex=((index-1+direction)%#zones)+1
    if not shared then return false,"MAP_STATE_UNAVAILABLE" end
    return shared:SelectMap(zones[nextIndex].mapID,continentMode and "CONTINENT" or "GUIDE")
end
JLP:RegisterModule("ForeverFishingZoneBrowser",Browser)
