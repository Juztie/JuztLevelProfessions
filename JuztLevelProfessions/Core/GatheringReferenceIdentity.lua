local _, JLP = ...
-- Canonical reference identity. Observed player coordinates and preloaded
-- reference coordinates are distinct; never replace one with the other.
local Identity={contract="jlp-gathering-reference-identity-v1",nativeDispatchAllowed=false}
function Identity:FromFields(professionKey,resourceKey,mapID,x,y)
    if type(professionKey)~="string" or type(resourceKey)~="string" or
       type(mapID)~="number" or type(x)~="number" or type(y)~="number" or
       x~=x or y~=y or x<0 or y<0 or x>1 or y>1 then return nil end
    return table.concat({professionKey,resourceKey,mapID,
        math.floor(x*10000+0.5),math.floor(y*10000+0.5)},":")
end
function Identity:FromReference(record,mapID)
    if type(record)~="table" then return nil end
    return self:FromFields(record.professionKey,record.resourceKey,
        mapID or record.uiMapID or record.mapID,record.x,record.y)
end
JLP:RegisterModule("GatheringReferenceIdentity",Identity)
