local _, JLP = ...
-- Fishing species identity is an itemID, not a text label. Grid cells are
-- historical catch AREAS, never fishing-pool POINTs or navigable destinations.
local M={contract="jlp-fishing-resources-70450-v1",nativeDispatchAllowed=false,
    sourceAuthority="HISTORICAL_REFERENCE_ONLY"}
local ROOT="Interface\\AddOns\\JuztLevelProfessions\\Assets\\gathering\\fish\\"
local FILES={
 "inv_misc_fish_01","inv_misc_fish_02","inv_misc_fish_03","inv_misc_fish_04",
 "inv_misc_fish_06","inv_misc_fish_08","inv_misc_fish_11","inv_misc_fish_12",
 "inv_misc_fish_13","inv_misc_fish_14","inv_misc_fish_19","inv_misc_fish_20",
 "inv_misc_fish_21","inv_misc_fish_23","inv_misc_fish_24","inv_misc_fish_25",
 "inv_misc_fish_30","inv_misc_fish_32","inv_misc_monsterhead_01",
 "inv_misc_monsterhead_02","inv_misc_monsterhead_03","inv_misc_monsterhead_04"
}
-- Stable external icon references, cross-checked against item identity.
-- These are art associations only, never proof of catch location or 70450 loot.
local EXTERNAL_ICON={
 [6289]="inv_misc_fish_32", -- Wowhead Classic item 6289
 [6291]="inv_misc_fish_08", -- Wowhead Forever/Classic item 6291
 [6303]="inv_misc_fish_24", -- Wowhead Classic icon 133910
 [6522]="inv_misc_fish_03", -- Wowhead Classic spell/item Deviate Fish
 [8365]="inv_misc_fish_02", -- Wowhead Forever item 8365
 [13422]="inv_misc_fish_11", -- Wowhead Classic item 13422
 [13759]="inv_misc_fish_23", -- Wowhead Forever item 13759
 [13760]="inv_misc_fish_19", -- Wowhead Classic item 13760
}
local approved={}

for _,name in ipairs(FILES) do approved[name]=true end
local function positive(v) return type(v)=="number" and v>=1 and v==math.floor(v) end
local function raw(mapID)
    local source=JLP.data and JLP.data.fishingCatchAreaReference
    return type(source)=="table" and source.maps and source.maps[mapID] or nil
end
function M:GetChoices(mapID)
    if not positive(mapID) then return nil,"MAP_ID_INVALID" end
    local rows=raw(mapID) or {}
    local result,seen={},{}
    for _,row in ipairs(rows) do
        if positive(row.itemID) and not seen[row.itemID] and type(row.name)=="string" and row.name~="" then
            seen[row.itemID]=true
            result[#result+1]={itemID=row.itemID,name=row.name,
                sampleCount=positive(row.sampleCount) and row.sampleCount or 0,
                hasSpatialReference=type(row.cells)=="string" and row.cells~="",
                source="GATHERLITE_FISHING_FOREVER",confidence="HISTORICAL_APPROXIMATE",
                hasVerifiedPoolCoordinates=false,nativeDispatchAllowed=false}
        end
    end
    local secondary=JLP.data and JLP.data.foreverSecondaryLeveling
    local refs=secondary and secondary.fishing and secondary.fishing.speciesZoneReferences
    for itemID,ref in pairs(refs or {})do
        for _,id in ipairs(ref.mapIDs)do if id==mapID then
            local found
            for _,r in ipairs(result)do if r.itemID==itemID then found=r;break end end
            if not found then
                found={itemID=itemID,name=ref.name,sampleCount=0,hasSpatialReference=false,
                    hasVerifiedPoolCoordinates=false,nativeDispatchAllowed=false}
                result[#result+1]=found
            end
            found.source=ref.sourceURL;found.confidence=ref.evidence;found.zoneReferenceOnly=true
            found.spatialEvidence=found.hasSpatialReference and "SEPARATE_HISTORICAL_GRID_NOT_FOREVER_POINT"or nil
            break
        end end
    end
    table.sort(result,function(a,b)
        if a.name==b.name then return a.itemID<b.itemID end
        return a.name<b.name
    end)
    return result
end
function M:Find(mapID,itemID)
    if not positive(itemID) then return nil,"ITEM_ID_INVALID" end
    local choices,why=self:GetChoices(mapID)
    if not choices then return nil,why end
    for _,row in ipairs(choices) do if row.itemID==itemID then return row end end
    return nil,"FISH_NOT_DOCUMENTED_IN_ZONE"
end
local function fromClient(itemID)
    local candidates={}
    if type(C_Item)=="table" then
        if type(C_Item.GetItemInfoInstant)=="function" then
            local ok,actual,_,_,_,icon=pcall(C_Item.GetItemInfoInstant,itemID)
            if ok and actual==itemID and type(icon)=="string" then candidates[#candidates+1]=icon end
        end
        if type(C_Item.GetItemIconByID)=="function" then
            local ok,icon=pcall(C_Item.GetItemIconByID,itemID)
            if ok and type(icon)=="string" then candidates[#candidates+1]=icon end
        end
    end
    if type(GetItemInfoInstant)=="function" then
        local ok,actual,_,_,_,icon=pcall(GetItemInfoInstant,itemID)
        if ok and actual==itemID and type(icon)=="string" then candidates[#candidates+1]=icon end
    end
    if type(GetItemIcon)=="function" then
        local ok,icon=pcall(GetItemIcon,itemID)
        if ok and type(icon)=="string" then candidates[#candidates+1]=icon end
    end
    local differentNativeIcon=false
    for _,texture in ipairs(candidates) do
        local normalized=texture:lower():gsub("/","\\"):gsub("%.tga$",""):gsub("%.blp$","")
        -- The icon MUST be an exact native item icon filename, and MUST
        -- exist among the user-supplied fish artwork. No numeric guesses.
        local name=normalized:match("^interface\\icons\\([%w_]+)$")
        if name and approved[name] then return name,"CLIENT_ITEM_ICON_MATCHED" end
        if name then differentNativeIcon=true end
    end
    if differentNativeIcon then return nil,"CLIENT_ICON_OUTSIDE_PACK" end
end
function M:ResolveIcon(mapID,itemID)
    if not positive(mapID) then return nil,"MAP_ID_INVALID" end
    if itemID~=nil then
        local row,why=self:Find(mapID,itemID)
        if not row then return nil,why end
        local name,proof=fromClient(itemID)
        if name then return ROOT..name..".tga",proof end
        if proof~="CLIENT_ICON_OUTSIDE_PACK" and EXTERNAL_ICON[itemID] and
            approved[EXTERNAL_ICON[itemID]] then
            return ROOT..EXTERNAL_ICON[itemID]..".tga","EXTERNAL_ITEM_ICON_REFERENCE"
        end
    end
    return ROOT.."Fishhook.tga","GENERIC_FISHING_AREA_NOT_SPECIES_ICON"
end
function M:IsRoutable(mapID,itemID)
    if not positive(mapID) then return false,"MAP_ID_INVALID" end
    if itemID then
        local row,reason=self:Find(mapID,itemID)
        if not row then return false,reason end
    end
    return false,"NO_VERIFIED_FISHING_POOL_POINTS"
end
JLP:RegisterModule("FishingResourceCatalogue70450",M)
