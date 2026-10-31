local _, JLP = ...

-- Registry-driven presentation model for profession-facing UI surfaces.
-- This layer is deliberately read-only: it reflects learned professions and
-- maturity/capability metadata, but it never fabricates a profession identity
-- and it never grants Planner or execution authority.
local ProfessionWorkspace = {
    contract = "registry-driven-profession-workspace-v1",
    guideModesContract = "profession-guide-modes-v1",
    primarySlotsContract = "profession-primary-slots-v1",
    authority = "presentation-only",
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function api() return JLP:GetModule("ProfessionAPI") end

local function copyProfession(row, seen)
    if type(row) ~= "table" then return row end
    seen=seen or {};if seen[row] then return seen[row] end
    local out={};seen[row]=out
    for k,v in pairs(row) do out[k]=copyProfession(v,seen) end
    return out
end

local function skillNumber(n)
    return type(n)=="number" and n==n and n>=0 and n<math.huge and n or nil
end

-- Pure presentation: canonical ownership admits a key, never a stale list row.
-- Numeric identity conflicts discard that row's skill/slot, not character facts.
local function presentation(category, detected)
    local p,reg=api(),registry()
    if not (p and type(p.GetOwnership)=="function" and reg) then return {},true end
    if not detected then
        detected={}
        if p.GetDetected then detected=p:GetDetected() or {}
        else
            local rows=category=="PRIMARY" and p.GetPrimaryPair and p:GetPrimaryPair() or
                category=="SECONDARY" and p.GetSecondaryProfessions and p:GetSecondaryProfessions() or {}
            for _,row in ipairs(rows) do if row.key then detected[row.key]=row end end
        end
    end
    local out,unknown={},false
    for _,key in ipairs(reg:GetKeys({category=category})) do
        local ownership=p:GetOwnership(key)
        if ownership and ownership.owned==true then
            local row=detected[key] or {};local def=reg:Get(key)
            local resolved=reg:ResolveStableIdentity(row.skillLine,row.professionEnum)
            local conflict=(row.key~=nil and row.key~=key) or
                ((row.skillLine~=nil or row.professionEnum~=nil) and resolved~=key) or
                (row.characterKey~=nil and ownership.characterKey~=nil and row.characterKey~=ownership.characterKey)
            local current=not conflict and resolved==key and row.cached~=true and ownership.state=="OWNED"
            local copy=not conflict and copyProfession(row) or {}
            copy.key=key;copy.name=copy.name or reg:GetDisplayNameOrKey(key)
            local icons=JLP.UIIconResolver
            copy.icon=copy.icon or (icons and icons:GetFallback())
            copy.definition=copyProfession(def)
            copy.ownershipState=ownership.state
            copy.presentationState=conflict and "conflict" or current and "learned" or "historical"
            copy.presentationConflict=conflict and "PROFESSION_IDENTITY_CONFLICT" or nil
            copy.cached=not current
            copy.skill=skillNumber(copy.skill);copy.maxSkill=skillNumber(copy.maxSkill)
            copy.primarySlot=nil
            local n=row.primarySlot
            if not conflict and (n==1 or n==2) and
               ((current and row.detectionSource=="get-professions-primary" and row.primarySlotHistorical~=true) or
                (not current and row.primarySlotHistorical==true and row.slotObservationSource=="knowledge-cache")) then
                copy.primarySlot=n
            end
            copy.nativeDispatchAllowed=false
            copy.productionEnabled=def.maturity and def.maturity.production==true or false
            copy.productionCandidate=def.maturity and def.maturity.candidate==true or false
            copy.researchEnabled=def.maturity and def.maturity.research==true or false
            out[#out+1]=copy
        elseif not ownership or ownership.state~="PROFESSION_NOT_LEARNED" then unknown=true end
    end
    if category=="PRIMARY" and #out>2 then
        -- Preserve visible positive references without inventing a third slot
        -- or letting contradictory input establish an active Guide selection.
        for _,row in ipairs(out) do
            row.primarySlot=nil;row.presentationState="conflict"
            row.presentationConflict="PRIMARY_COUNT_CONFLICT"
        end
    end
    return out,unknown
end

local function learnedPrimary()
    local rows=presentation("PRIMARY");local out={}
    for _,row in ipairs(rows) do if not row.presentationConflict then out[#out+1]=row end end
    return out
end

local function containsKey(rows, key)
    key = tostring(key or ""):upper()
    for _, row in ipairs(rows or {}) do
        if tostring(row.key or ""):upper() == key then return row end
    end
    return nil
end

function ProfessionWorkspace:GetPrimaryLearned()
    return learnedPrimary()
end

local function primarySlots(learned, unknown)
    local bySlot, slots, claims, unplaced = {}, {}, {[1]={},[2]={}}, {}
    -- A cached slot is only the *last observed* layout. Never squeeze a
    -- slot-unknown SavedVariables row into the first empty live UI position.
    for _, p in ipairs(learned) do
        local n=p.primarySlot
        if n==1 or n==2 then claims[n][#claims[n]+1]=p
        else unplaced[#unplaced+1]=p end
    end
    for n=1,2 do
        if #claims[n]==1 then bySlot[n]=claims[n][1]
        elseif #claims[n]>1 then
            -- Conflicting legacy/corrupt claims cannot establish the slot.
            for _,p in ipairs(claims[n]) do p.primarySlot=nil;p.slotConflict=true;unplaced[#unplaced+1]=p end
        end
    end
    -- Expose unresolved historical professions explicitly to presentation
    -- callers without associating them with Primary 1 or Primary 2.
    slots.unplacedHistorical=unplaced
    for i=1,2 do
        local p = bySlot[i]
        if p then
            slots[i] = {
                contract = ProfessionWorkspace.primarySlotsContract,
                slot = i,
                state = p.presentationState,
                key = p.key,
                name = p.cached==true and tostring(p.name or p.key).." (historical)" or p.name,
                slotObservationSource = p.cached==true and "historical-cache" or "live-api",
                cached = p.cached==true,
                skill = p.skill,
                maxSkill = p.maxSkill,
                icon = p.icon,
                profession = p,
                productionEnabled = p.productionEnabled,
                productionCandidate = p.productionCandidate,
                researchEnabled = p.researchEnabled,
            }
        else
            slots[i] = {
                contract = ProfessionWorkspace.primarySlotsContract,
                slot = i,
                state = (unknown or #unplaced>0) and "unknown" or "empty",
                key = nil,
                name = (unknown or #unplaced>0) and "Primary slot not confirmed" or
                    (i == 1 and "Learn a primary profession" or "Learn second profession"),
                profession = nil,
                productionEnabled = false,
                productionCandidate = false,
                researchEnabled = false,
            }
        end
    end
    return slots
end

function ProfessionWorkspace:GetPrimarySlots()
    return primarySlots(presentation("PRIMARY"))
end

function ProfessionWorkspace:GetGuideModes()
    local learned = learnedPrimary()
    local modes = {}
    if #learned >= 2 then
        modes[#modes+1] = {contract=self.guideModesContract,mode="dual",label="Dual Mode",kind="combined"}
        for _, p in ipairs(learned) do
            modes[#modes+1] = {contract=self.guideModesContract,mode=p.key,label=p.name or p.key,kind="profession",profession=p}
        end
    elseif #learned == 1 then
        local p = learned[1]
        modes[#modes+1] = {contract=self.guideModesContract,mode=p.key,label=p.name or p.key,kind="profession",profession=p}
        modes[#modes+1] = {contract=self.guideModesContract,mode="learn-second",label="Learn second profession",kind="onboarding"}
    else
        modes[#modes+1] = {contract=self.guideModesContract,mode="onboarding",label="Learn a primary profession",kind="onboarding"}
    end
    return modes
end

function ProfessionWorkspace:ResolveGuideMode(requested)
    local learned = learnedPrimary()
    local raw = tostring(requested or "")
    local lower = raw:lower()
    if #learned >= 2 and lower == "dual" then return "dual", nil, "combined" end
    if #learned == 1 and (lower == "dual" or lower == "") then
        return learned[1].key, learned[1], "profession"
    end
    if #learned == 0 then return "onboarding", nil, "onboarding" end
    if lower == "learn-second" and #learned == 1 then return "learn-second", nil, "onboarding" end
    if lower == "onboarding" and #learned == 0 then return "onboarding", nil, "onboarding" end

    local key = tostring(raw):upper()
    local p = containsKey(learned, key)
    if p then return p.key, p, "profession" end
    if #learned >= 2 then return "dual", nil, "combined" end
    return learned[1].key, learned[1], "profession"
end

function ProfessionWorkspace:GetFocusedPrimary(preferred)
    local learned = learnedPrimary()
    if #learned == 0 then return nil end
    local preferredRow = containsKey(learned, preferred)
    if preferredRow then return preferredRow end
    local saved = JLP.DB and JLP.DB.character and JLP.DB.character.selectedProfession or nil
    local savedRow = containsKey(learned, saved)
    if savedRow then return savedRow end
    return learned[1]
end

function ProfessionWorkspace:SetFocusedPrimary(key)
    local p = self:GetFocusedPrimary(key)
    if not p or tostring(p.key) ~= tostring(key):upper() then return false, "profession-not-learned" end
    if JLP.DB and JLP.DB.profile then JLP.DB.profile.activeSecondaryCurrentStep=nil end
    local supply=JLP:GetModule("GatheringSharedMapState")
    if supply and supply.ObserveSupplyProfessionFocus then supply:ObserveSupplyProfessionFocus(p.key) end
    if JLP.DB and JLP.DB.character then JLP.DB.character.selectedProfession = p.key end
    return true, p
end

local function headerSubtitle(learned,unknown)
    if #learned==0 then return unknown and "Primary ownership not confirmed" or "No primary professions learned" end
    local parts={}
    for _,p in ipairs(learned) do
        local label=tostring(p.name or p.key)
        if p.cached==true then
            local n=p.primarySlot
            label=label..((n==1 or n==2) and
                (" (historical Primary "..n..")") or " (historical, slot unknown)")
        end
        parts[#parts+1]=label
    end
    if #learned==1 and learned[1].cached~=true then
        parts[#parts+1]="open primary slot"
    end
    return table.concat(parts," + ")
end

function ProfessionWorkspace:GetHeaderSubtitle()
    return headerSubtitle(presentation("PRIMARY"))
end

function ProfessionWorkspace:HasLearned(key)
    return containsKey(learnedPrimary(), key) ~= nil
end

function ProfessionWorkspace:HasCapability(capability)
    local reg = registry()
    for _, p in ipairs(learnedPrimary()) do
        if reg and reg:HasCapability(p.key, capability) then return true, p.key end
    end
    return false, nil
end

function ProfessionWorkspace:GetOverviewModel()
    local p=api();local detected=p and p.GetOwnership and p.GetDetected and p:GetDetected() or nil
    local primary,unknown=presentation("PRIMARY",detected)
    local secondary,secondaryUnknown=presentation("SECONDARY",detected)
    local slots=primarySlots(primary,unknown)
    local eligible={};for _,row in ipairs(primary) do if not row.presentationConflict then eligible[#eligible+1]=row end end
    local saved=JLP.DB and JLP.DB.character and JLP.DB.character.selectedProfession
    local focused=containsKey(eligible,saved) or eligible[1]
    local hasDisenchant,disenchantKey=false,nil
    for _,row in ipairs(eligible) do if registry():HasCapability(row.key,"disenchant") then hasDisenchant=true;disenchantKey=row.key;break end end
    return {
        contract = self.contract,
        slots = slots,
        unplacedHistorical = slots.unplacedHistorical,
        secondaries = secondary,
        secondaryOwnershipUnknown = secondaryUnknown,
        learnedCount = (slots[1].state == "learned" and 1 or 0) + (slots[2].state == "learned" and 1 or 0),
        focused = focused,
        focusedKey = focused and focused.key or nil,
        headerSubtitle = headerSubtitle(primary,unknown),
        secondaryCardKind = hasDisenchant and "disenchant" or "acquisition",
        secondaryCardProfession = disenchantKey,
        nativeDispatchAllowed = false,
    }
end

function ProfessionWorkspace:Validate()
    local errors = {}
    local learned = learnedPrimary()
    if #learned > 2 then errors[#errors+1] = "primary-learned-count-exceeds-two" end
    local seen = {}
    local reg = registry()
    for _, p in ipairs(learned) do
        local def = reg and reg:Get(p.key) or nil
        if not def or def.category ~= "PRIMARY" then errors[#errors+1] = "non-primary-in-primary-workspace:"..tostring(p.key) end
        if seen[p.key] then errors[#errors+1] = "duplicate-primary:"..tostring(p.key) end
        seen[p.key] = true
    end
    for _, mode in ipairs(self:GetGuideModes()) do
        if mode.kind == "profession" and not seen[mode.mode] then errors[#errors+1] = "guide-mode-fabricated-profession:"..tostring(mode.mode) end
    end
    return errors
end

JLP:RegisterModule("ProfessionWorkspace", ProfessionWorkspace)
