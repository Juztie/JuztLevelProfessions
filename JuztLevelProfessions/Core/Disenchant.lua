local _, JLP = ...
local Disenchant = {}

-- Knowing the spell is necessary, but says nothing about a particular item's
-- quality/skill restrictions. The supplied Forever data/API export contains
-- no item-specific eligibility contract, so report that precise evidence gap.
function Disenchant:GetFeasibility(candidate)
    local result={verified=false,feasible=false,reason="DISENCHANT_ABILITY_UNVERIFIED",
        itemID=candidate and candidate.itemID,readOnly=true,nativeDispatchAllowed=false}
    local known=nil
    if type(C_SpellBook)=="table" and type(C_SpellBook.ContainsAnyDisenchantSpell)=="function" then
        local ok,value=pcall(C_SpellBook.ContainsAnyDisenchantSpell)
        if ok and type(value)=="boolean" then known=value end
    elseif type(IsSpellKnown)=="function" then
        local ok,value=pcall(IsSpellKnown,13262)
        if ok and type(value)=="boolean" then known=value end
    end
    result.abilityKnown=known
    if known==false then result.reason="DISENCHANT_NOT_LEARNED"
    elseif known==true then result.reason="DISENCHANT_ITEM_REQUIREMENTS_UNVERIFIED" end
    return result
end

-- Explicit level-domain API. Old ItemLevel callers cannot silently consume
-- the new guide's Requires Level bands, and quality alone grants no eligibility.
function Disenchant:GetGuideEstimate(candidate)
    candidate=type(candidate)=="table" and candidate or {}
    local guide=JLP.data and JLP.data.disenchant and JLP.data.disenchant.foreverGuide
    local out={status="UNKNOWN",outputs={},eligibility=self:GetFeasibility(candidate),
        levelDomain="REQUIRES_LEVEL",sourceURL=guide and guide.sourceURL,
        evidence=guide and guide.evidence,guaranteed=false,observedInventory=false,
        inventoryCreditAllowed=false,nativeDispatchAllowed=false,readOnly=true}
    local level=candidate.requiredLevel
    if not guide or guide.levelDomain~="REQUIRES_LEVEL" or type(level)~="number" or
        level<1 or level>60 or level~=math.floor(level) or
        (candidate.kind~="armor" and candidate.kind~="weapon") or
        (candidate.quality~=2 and candidate.quality~=3 and candidate.quality~=4) then
        out.reason="EXPLICIT_REQUIRED_LEVEL_TYPE_AND_QUALITY_NEEDED";return out
    end
    local band
    for _,b in ipairs(guide.bands or {})do if level>=b[1] and level<=b[2] then band=b;break end end
    if not band then return out end
    out.status="GUIDE_ESTIMATE_ELIGIBILITY_UNVERIFIED";out.requiredLevelMin=band[1];out.requiredLevelMax=band[2]
    local function add(category,id,min,max,chance,range)
        if id then out.outputs[#out.outputs+1]={category=category,itemID=id,minQty=min,maxQty=max,
            chanceEstimate=chance,chanceRangeEstimate=range,guaranteed=false,observedInventory=false,
            quantityStatus=min and "GUIDE_RANGE_NOT_OBSERVED" or "UNKNOWN",
            evidence=guide.evidence,nativeDispatchAllowed=false}end
    end
    if candidate.quality==2 then
        add("dust",band[3],band[4],band[5],candidate.kind=="armor" and .75 or .20)
        add("essence",band[6],band[7],band[8],candidate.kind=="weapon" and .75 or .20)
        add("shard",band[9],nil,nil,nil,{minimum=.03,maximum=.05})
    elseif candidate.quality==3 then
        add("shard",band[9]);add("crystal",band[10],nil,nil,.005)
        out.probabilityStatus=guide.rareProbabilityConflict
    else
        -- Guide's epic level cutoff is not a precise, qualified item mapping.
        add("shard",band[9]);add("crystal",band[10])
        out.probabilityStatus="EPIC_EXACT_BOUNDARY_AND_QUANTITY_UNKNOWN"
    end
    return out
end

local function bands(kind)
    local data = JLP.data and JLP.data.disenchant
    if not data then return {} end
    return kind == "weapon" and (data.weapon or {}) or (data.armor or {})
end

function Disenchant:GetBand(itemLevel, kind)
    itemLevel = tonumber(itemLevel) or 0
    for _, band in ipairs(bands(kind)) do
        if itemLevel >= band[1] and itemLevel <= band[2] then
            return band
        end
    end
    return nil
end

function Disenchant:GetExpectedOutputs(itemLevel, kind)
    local band = self:GetBand(itemLevel, kind)
    local out = {}
    if not band then return out end
    for i=3,#band do
        local row=band[i]
        local average=((tonumber(row.minQty) or 0)+(tonumber(row.maxQty) or 0))/2
        out[#out+1]={
            itemID=row.itemID,
            name=row.name,
            chance=row.chance,
            minQty=row.minQty,
            maxQty=row.maxQty,
            expected=(tonumber(row.chance) or 0)*average,
            itemLevelMin=band[1],
            itemLevelMax=band[2],
            kind=kind or "armor",
            evidenceStatus="HISTORICAL_REFERENCE_NOT_70532_LOOT_DISTRIBUTION",
            guaranteed=false,observedInventory=false,nativeDispatchAllowed=false,
        }
    end
    return out
end

function Disenchant:GetBandsForMaterial(itemID, kind)
    local result={}
    local kinds = kind and {kind} or {"armor","weapon"}
    for _, k in ipairs(kinds) do
        for _, band in ipairs(bands(k)) do
            for i=3,#band do
                local row=band[i]
                if row.itemID==itemID then
                    result[#result+1]={
                        kind=k,
                        itemLevelMin=band[1],
                        itemLevelMax=band[2],
                        chance=row.chance,
                        minQty=row.minQty,
                        maxQty=row.maxQty,
                    }
                end
            end
        end
    end
    return result
end

function Disenchant:DescribeMaterial(itemID)
    local guide=JLP.data and JLP.data.disenchant and JLP.data.disenchant.foreverGuide
    if guide and guide.levelDomain=="REQUIRES_LEVEL" then
        local low,high
        for _,b in ipairs(guide.bands or {})do
            if b[3]==itemID or b[6]==itemID or b[9]==itemID or b[10]==itemID then
                low=low and math.min(low,b[1]) or b[1];high=high and math.max(high,b[2]) or b[2]
            end
        end
        if low then return string.format("Forever guide possibility: equipment Requires Level %d-%d; item eligibility and actual output must be verified. This is not ItemLevel or guaranteed material supply.",low,high)end
    end
    local rows=self:GetBandsForMaterial(itemID)
    if #rows==0 then return nil end
    local best=rows[1]
    for _,row in ipairs(rows) do
        if (row.chance or 0) > (best.chance or 0) then best=row end
    end
    return string.format(
        "Disenchant %s items at item level %d-%d (about %d%% chance, %d-%d each).",
        best.kind,
        best.itemLevelMin,
        best.itemLevelMax,
        math.floor((best.chance or 0)*100+0.5),
        best.minQty or 0,
        best.maxQty or 0
    )
end

function Disenchant:GetStatus()
    local data=JLP.data and JLP.data.disenchant
    return data and data.status or "missing"
end

JLP:RegisterModule("Disenchant",Disenchant)
