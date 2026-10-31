local _, JLP = ...
-- Optional read-only bridge. Leatrix remains the authority for its own setting.
-- This module never loads the other addon, changes its DB, or hooks its UI.
local Service={contract="jlp-map-reveal-service-v2",cacheSeconds=30}
local function loaded()
    local api=type(C_AddOns)=="table" and C_AddOns.IsAddOnLoaded
    if type(api)~="function" then api=_G.IsAddOnLoaded end
    if type(api)~="function" then return false end
    local ok,value=pcall(api,"Leatrix_Maps")
    return ok and value==true
end
local function clamp(v,default)
    if type(v)~="number" or v~=v then return default end
    return math.max(0,math.min(1,v))
end
function Service:GetConfig()
    if not loaded() then return {enabled=false,reason="LEATRIX_NOT_LOADED"} end
    local db=_G.LeaMapsDB
    if type(db)~="table" or db.RevealMap~="On" then
        return {enabled=false,reason="LEATRIX_REVEAL_OFF"}
    end
    local tint=db.RevTint=="On"
    local r=tint and clamp(db.tintRed,0.6) or 1
    local g=tint and clamp(db.tintGreen,0.6) or 1
    local b=tint and clamp(db.tintBlue,1) or 1
    local alpha=tint and clamp(db.tintAlpha,1) or 1
    return {enabled=true,tint=tint,r=r,g=g,b=b,alpha=alpha,
        key=table.concat({"ON",tostring(tint),tostring(r),tostring(g),tostring(b),tostring(alpha)},":")}
end
local function positive(v)
    return type(v)=="number" and v>0 and v<math.huge and v==math.floor(v)
end
local function keyFor(t)
    if type(t)~="table" then return nil end
    local w,h,x,y=t.textureWidth,t.textureHeight,t.offsetX,t.offsetY
    if not positive(w) or not positive(h) or type(x)~="number" or
        type(y)~="number" or x<0 or y<0 or x~=math.floor(x) or y~=math.floor(y) then return nil end
    return table.concat({w,h,x,y},":")
end
function Service:GetPlan(art)
    local data=JLP:GetModule("MapRevealData")
    local entry=data and data.maps and art and data.maps[art.mapID]
    if not entry then return nil,"MAP_NOT_QUALIFIED" end
    if not (type(C_Map)=="table" and type(C_Map.GetMapArtID)=="function") then
        return nil,"ART_ID_API_UNAVAILABLE" end
    local ok,liveArtID=pcall(C_Map.GetMapArtID,art.mapID)
    if not ok or liveArtID~=entry.mapArtID then return nil,"MAP_ART_ID_MISMATCH" end
    if entry.layerWidth~=art.width or entry.layerHeight~=art.height then
        return nil,"MAP_DIMENSIONS_MISMATCH" end
    -- MapArtID and validated texture dimensions establish compatibility.
    -- The packed texture source's build is provenance, never a client lock.
    if not (type(C_MapExplorationInfo)=="table" and
        type(C_MapExplorationInfo.GetExploredMapTextures)=="function") then
        return nil,"EXPLORATION_API_UNAVAILABLE" end
    -- Explored state may change independently of viewport transforms; query at
    -- most once per 30 seconds, even if the user pans and zooms continuously.
    local now=type(GetTime)=="function" and GetTime() or nil
    local cached=self._cached
    if cached and cached.mapID==art.mapID and now and cached.time and
        now>=cached.time and now-cached.time<self.cacheSeconds then
        return cached.plan
    end
    local success,explored=pcall(C_MapExplorationInfo.GetExploredMapTextures,art.mapID)
    if not success or (explored~=nil and type(explored)~="table") then
        self._cached=nil;return nil,"EXPLORATION_QUERY_FAILED"
    end
    -- nil is valid on maps with zero reported explored regions. For our
    -- qualified native dataset it means no region can be marked as explored.
    explored=explored or {}
    local observed={}
    for _,item in ipairs(explored) do
        local key=keyFor(item)
        if key then observed[key]=true end
    end
    local tileW,tileH=art.tileWidth,art.tileHeight
    if not positive(tileW) or not positive(tileH) then return nil,"TILE_DIMENSIONS_INVALID" end
    local regions={}
    local matchedRegions=0
    local count=0
    local total=0
    for _,region in ipairs(entry.regions) do
        if not (region.width>0 and region.height>0 and region.x>=0 and region.y>=0 and
            region.x+region.width<=art.width and region.y+region.height<=art.height) then
            return nil,"REGION_OUT_OF_BOUNDS" end
        local cols=math.ceil(region.width/tileW)
        local rows=math.ceil(region.height/tileH)
        local needed=cols*rows
        if needed>16 or #region.files~=needed then return nil,"REGION_TILE_MISMATCH" end
        for _,id in ipairs(region.files) do
            if not positive(id) then return nil,"REGION_FILE_ID_INVALID" end
        end
        total=total+needed
        if total>192 then return nil,"REGION_LIMIT" end
        if observed[region.key] then matchedRegions=matchedRegions+1 end
        regions[#regions+1]={region=region,explored=observed[region.key]==true,
            cols=cols,rows=rows}
        count=count+1
    end
    local plan={mapID=art.mapID,mapArtID=entry.mapArtID,qualification=entry.qualification,
        zoneName=entry.name,matchedRegions=matchedRegions,regions=regions,totalTiles=total,
        key=tostring(art.mapID)..":"..tostring(now or "no-clock")..":"..tostring(#explored),
        exploredCount=#explored,regionCount=count}
    self._cached={mapID=art.mapID,time=now,plan=plan}
    return plan
end
function Service:Invalidate() self._cached=nil end
JLP:RegisterModule("MapRevealService",Service)
-- Optional read-only diagnostics; reports submitted textures, never claims
-- the underlying image bytes have actually loaded without in-client QA.
_G.SLASH_JLP_MAP_REVEAL1="/jlpreveal"
SlashCmdList["JLP_MAP_REVEAL"]=function()
    local cfg=Service:GetConfig()
    local win=JLP.StandaloneGatheringMap
    local canvas=win and win.frame and win.frame.canvas
    local art=win and win.lastArt
    local status=not cfg.enabled and cfg.reason or "ENABLED"
    local qualification="NO_CURRENT_MAP"
    if art and cfg.enabled then
        local plan,reason=Service:GetPlan(art)
        qualification=plan and tostring(plan.qualification) or tostring(reason or "UNQUALIFIED")
    elseif art then qualification="LEATRIX_DISABLED" end
    if JLP.Print then JLP:Print("Map Reveal: Leatrix="..tostring(status)..
        " | map="..tostring(art and art.mapID).." | scope="..qualification..
        (art and cfg.enabled and (function()
            local plan=Service:GetPlan(art)
            return plan and (" | regions="..tostring(plan.regionCount)..
                " | matched explored="..tostring(plan.matchedRegions)..
                " | art="..tostring(plan.mapArtID)) or ""
        end)() or "")..
        " | submitted textures="..tostring(canvas and canvas.jlpRevealVisible or 0)..
        " | visual load unverified") end
end
