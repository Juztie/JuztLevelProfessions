local _, JLP = ...
-- Draw directly onto the existing shared canvas, above base map art and below
-- gathering-area ARTWORK:1, route ARTWORK:5, resource Buttons,
-- and the dedicated player-marker frame.
-- No per-pan texture allocations once the bounded pool has reached capacity.
local Renderer={contract="jlp-map-reveal-renderer-v1"}
local function fileSpan(v)
    local size=16
    while size<v and size<4096 do size=size*2 end
    return size
end
local function visible(canvas,region)
    return canvas and type(canvas.CreateTexture)=="function" and region~=nil
end
function Renderer:Clear(canvas)
    if not canvas then return end
    for _,tex in ipairs(canvas.jlpRevealTextures or {}) do
        if tex.SetVertexColor then tex:SetVertexColor(1,1,1,1) end
        tex:Hide()
    end
    canvas.__jlpRevealIdentity=nil
    canvas.jlpRevealVisible=0
end
function Renderer:Render(canvas,art)
    local service=JLP:GetModule("MapRevealService")
    local cfg=service and service:GetConfig()
    if not (cfg and cfg.enabled) then
        self:Clear(canvas)
        return false,cfg and cfg.reason or "REVEAL_UNAVAILABLE"
    end
    if not visible(canvas,art) then return false,"CANVAS_UNAVAILABLE" end
    local plan,why=service:GetPlan(art)
    if not plan then self:Clear(canvas);return false,why end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    if not map then self:Clear(canvas);return false,"MAP_RENDERER_UNAVAILABLE" end
    local t=map:ViewTransform(canvas,art)
    local zoomstate=canvas.gatheringView or {}
    local signature=table.concat({plan.key,cfg.key,tostring(t.width),tostring(t.height),
        tostring(zoomstate.zoom or 1),tostring(zoomstate.centerX or 0.5),
        tostring(zoomstate.centerY or 0.5)},":")
    if canvas.__jlpRevealIdentity==signature then return true,"CACHED" end
    -- Never hide/reset the entire pool at every viewport step. Only the
    -- currently visible subset receives updated anchors/texcoords; leftovers
    -- are hidden at the end. Clear() remains authoritative on disable/map exit.
    local pool=canvas.jlpRevealTextures or {}
    canvas.jlpRevealTextures=pool
    local index=0
    for _,r in ipairs(plan.regions) do
        local entry=r.region
        local cols,rows=r.cols,r.rows
        for row=0,rows-1 do
            for col=0,cols-1 do
                local offsetX,offsetY=col*art.tileWidth,row*art.tileHeight
                local srcW=math.min(art.tileWidth,entry.width-offsetX)
                local srcH=math.min(art.tileHeight,entry.height-offsetY)
                local x0=t.left+(entry.x+offsetX)*t.scale
                local y0=t.top+(entry.y+offsetY)*t.scale
                local x1,y1=x0+srcW*t.scale,y0+srcH*t.scale
                local vx0,vx1=math.max(0,x0),math.min(t.width,x1)
                local vy0,vy1=math.max(0,y0),math.min(t.height,y1)
                if vx1>vx0 and vy1>vy0 then
                    index=index+1
                    local tex=pool[index]
                    if not tex then
                        tex=canvas:CreateTexture(nil,"ARTWORK",nil,-1)
                        pool[index]=tex
                    end
                    if tex.ClearAllPoints then tex:ClearAllPoints() end
                    local fileID=entry.files[row*cols+col+1]
                    if tex.__jlpRevealFileID~=fileID then
                        tex:SetTexture(fileID)
                        tex.__jlpRevealFileID=fileID
                    end
                    tex:SetPoint("TOPLEFT",canvas,"TOPLEFT",vx0,-vy0)
                    tex:SetSize(vx1-vx0,vy1-vy0)
                    if tex.SetTexCoord then
                        local fw,fh=fileSpan(srcW),fileSpan(srcH)
                        tex:SetTexCoord((vx0-x0)/(fw*t.scale),(vx1-x0)/(fw*t.scale),
                            (vy0-y0)/(fh*t.scale),(vy1-y0)/(fh*t.scale))
                    end
                    if tex.SetVertexColor then
                        if not r.explored and cfg.tint then
                            tex:SetVertexColor(cfg.r,cfg.g,cfg.b,cfg.alpha)
                        else tex:SetVertexColor(1,1,1,1) end
                    end
                    tex:Show()
                end
            end
        end
    end
    for i=index+1,#pool do pool[i]:Hide() end
    canvas.__jlpRevealIdentity=signature
    canvas.jlpRevealVisible=index
    return true,"RENDERED"
end
JLP:RegisterModule("MapRevealRenderer",Renderer)
