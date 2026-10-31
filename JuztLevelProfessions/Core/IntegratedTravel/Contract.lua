-- JuztTravel portable core: no WoW APIs, UI elements or SavedVariables.
local _, JLP = ...
local T = JLP._integratedTravel
-- Internal portable engine: the sole owner is JLP, never _G.JuztTravel.
T.contract = 'juzt-travel-plan-v1'
T.engineVersion = '0.1.0-alpha6-test1'
T.CONTRACT_VERSION = 1
local M = {}
local floor, huge = math.floor, math.huge
function M.finite(x)
    return type(x)=='number' and x==x and x~=huge and x~=-huge
end
function M.point(p)
    if type(p)~='table' then return nil,'POINT_NOT_TABLE' end
    local m,x,y = p.mapID,p.x,p.y
    if not M.finite(m) or m<1 or floor(m)~=m then return nil,'INVALID_MAP_ID' end
    if not M.finite(x) or not M.finite(y) or x<0 or x>1 or y<0 or y>1 then
        return nil,'INVALID_NORMALIZED_COORDINATES'
    end
    return {mapID=m,x=x,y=y,label=tostring(p.label or ''), zone=tostring(p.zone or '')}
end
function M.copyPoint(p)
    return {mapID=p.mapID,x=p.x,y=p.y,label=p.label,zone=p.zone}
end
function M.shallowCopy(t)
    local result={}
    for k,v in pairs(t or {}) do result[k]=v end
    return result
end
function M.distance(a,b)
    if not a or not b or a.mapID~=b.mapID then return nil end
    local dx,dy=a.x-b.x,a.y-b.y
    return math.sqrt(dx*dx+dy*dy)
end
function M.validId(s)
    return type(s)=='string' and #s>0 and #s<=80 and not s:match('^__JT_') and s:match('^[%w_%.%-]+$')~=nil
end
T.Contract = M
