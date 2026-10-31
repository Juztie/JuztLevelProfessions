local _, JLP = ...

-- Runed enchanting rods are a strict capability hierarchy. A higher-tier rod
-- satisfies every lower-tier rod requirement. This module centralizes that rule
-- so readiness, acquisition and UI never ask the player to craft a weaker rod
-- when a stronger rod is already owned.
local EnchantingToolResolver = {
    contract = "production-enchanting-runed-rod-hierarchy-v1",
    professionKey = "ENCHANTING",
}

local function owned(itemID)
    local inventory = JLP:GetModule("Inventory")
    if inventory and inventory.GetOwned then
        local row = inventory:GetOwned(itemID)
        if type(row) == "table" then return row end
    end
    -- Without Inventory, only live bags may be known. Never label bank/
    -- reagent-bank items as carried tools when the player cannot use them.
    local total = nil
    if type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        local ok, value = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
        local n = ok and tonumber(value) or nil
        if n and n >= 0 and n < math.huge and n == math.floor(n) then total = n end
    elseif type(GetItemCount) == "function" then
        local ok, value = pcall(GetItemCount, itemID, false)
        local n = ok and tonumber(value) or nil
        if n and n >= 0 and n < math.huge and n == math.floor(n) then total = n end
    end
    -- A missing/failed count API does not prove that the player lacks a rod.
    -- Do not invent a zero bag observation, or promote storage certainty.
    return {itemID=tonumber(itemID),bags=total,bank=nil,total=total,
        bagKnown=total~=nil,bankKnown=false}
end

local function hierarchy()
    local data = JLP.data and JLP.data.enchanting
    return type(data and data.rodHierarchy) == "table" and data.rodHierarchy or {}
end

local positiveEvidence = "POSITIVE_OBSERVED_BAG_ROD_PLANNING_COMPETENCE"

local function validCompetence(record, key)
    if type(record) ~= "table" or record.evidence ~= positiveEvidence
        or record.identityConflict or (record.characterKey and record.characterKey ~= key) then return false end
    for _, rod in ipairs(hierarchy()) do
        if record.tier == rod.rodTier and record.itemID == rod.itemID then return true end
    end
    return false
end

-- Only the two keys established by CharacterIdentity for this player may merge.
-- Keep tier/item/evidence together; malformed claims never raise competence.
function EnchantingToolResolver:ReconcileCompetence(characters, identity, previousAlias)
    local result={moved=false,merged=false,key=identity.key}
    if not identity.stableKey or not identity.legacyKey
        or identity.legacyKey:find("Unknown",1,true) then
        result.reason="rod-identity-unresolved";return result
    end
    local legacy,stable=characters[identity.legacyKey],characters[identity.stableKey]
    if type(legacy)~="table" then result.reason="no-legacy-record";return result end
    if previousAlias==nil then
        local account=JLP.DB and JLP.DB.account
        local aliases=account and account.characterIdentity and account.characterIdentity.aliases
        previousAlias=aliases and aliases[identity.legacyKey]
    end
    if legacy.identityConflict or (previousAlias and previousAlias~=identity.stableKey) then
        legacy.identityConflict=legacy.identityConflict or {
            expectedStableKey=previousAlias,observedStableKey=identity.stableKey}
        result.reason="rod-identity-alias-conflict";return result
    end
    local stableValid=validCompetence(stable,identity.stableKey)
    local legacyValid=validCompetence(legacy,identity.legacyKey)
    if not stableValid and not legacyValid then
        result.reason="rod-evidence-conflict-preserved";return result
    end
    local winner=stableValid and stable or legacy
    if legacyValid and (not stableValid or legacy.tier>stable.tier) then winner=legacy end
    -- Preserve conflicting original claims explicitly, without treating them as
    -- capability or merging their scalar fields into the winning observation.
    local loser=winner==legacy and stable or legacy
    local loserValid=legacyValid
    if winner==legacy then loserValid=stableValid end
    if type(loser)=="table" and loser~=winner then
        if type(winner.reconciliationConflicts)~="table" then winner.reconciliationConflicts={} end
        local priorConflicts=type(loser.reconciliationConflicts)=="table" and loser.reconciliationConflicts or {}
        for _,claim in ipairs(priorConflicts) do
            winner.reconciliationConflicts[#winner.reconciliationConflicts+1]=claim
        end
        if not loserValid then
            winner.reconciliationConflicts[#winner.reconciliationConflicts+1]={
                tier=loser.tier,itemID=loser.itemID,evidence=loser.evidence,
                characterKey=loser.characterKey,reason="invalid-rod-confirmation"}
        end
    end
    winner.characterKey=identity.stableKey
    characters[identity.stableKey]=winner
    characters[identity.legacyKey]=nil
    result.moved=true;result.merged=type(stable)=="table"
    result.reason="highest-valid-rod-confirmation";return result
end

-- Historical planning competence, scoped through the existing character
-- identity/account store. This is never inventory or a native action ticket.
local function competenceStore(create)
    if not JLP.DB then return nil end
    local identity=JLP:GetModule("CharacterIdentity")
    local row=identity and identity.GetCurrent and identity:GetCurrent()
    local key=row and row.key
    if type(key)~="string" or key:find("Unknown",1,true) then return nil end
    JLP.DB.account=JLP.DB.account or {}
    local root=JLP.DB.account.enchantingRodCompetence
    if not root and create then root={schema=1,characters={}};JLP.DB.account.enchantingRodCompetence=root end
    if not root or type(root.characters)~="table" then return nil end
    if identity.ReconcileCharactersMap then identity:ReconcileCharactersMap(root.characters,row) end
    local store=root.characters[key]
    if store and (store.identityConflict or (store.characterKey and store.characterKey~=key)) then return nil end
    if not store and create then store={};root.characters[key]=store end
    return store
end

function EnchantingToolResolver:GetRequiredTier(tool)
    if type(tool) ~= "table" then return nil end
    for _, row in ipairs(hierarchy()) do
        if tonumber(row.itemID) == tonumber(tool.itemID) then
            if tool.rodTier~=nil and tonumber(tool.rodTier)~=tonumber(row.rodTier) then return nil end
            return tonumber(row.rodTier)
        end
    end
    return nil
end

function EnchantingToolResolver:Resolve(tool)
    if type(tool) ~= "table" then
        return {required=false,status="not-required",bags=0,bank=0,total=0,satisfied=true}
    end
    local requiredTier = self:GetRequiredTier(tool)
    local known=requiredTier and competenceStore(false)
    if known and validCompetence(known,known.characterKey) and known.tier>=requiredTier then
        return {required=true,requiredItemID=tool.itemID,requiredTier=requiredTier,
            itemID=known.itemID,rodTier=known.tier,name=tool.name,
            status="confirmed",satisfied=true,satisfaction="CHARACTER_HISTORICAL_ROD_COMPETENCE",
            inventoryKnown=false,bags=nil,bank=nil,total=nil,readOnly=true,
            nativeDispatchAllowed=false,contract=self.contract}
    end
    if not requiredTier then
        local store = owned(tool.itemID)
        local status = (tonumber(store.bags) or 0) > 0 and "bags"
            or (tonumber(store.total) or 0) > 0 and "bank"
            or (store.bagKnown ~= true and "unknown" or "missing")
        return {
            required=true,itemID=tool.itemID,name=tool.name or "Required tool",
            requiredItemID=tool.itemID,requiredName=tool.name,requiredTier=nil,
            bags=tonumber(store.bags) or 0,bank=tonumber(store.bank) or 0,total=tonumber(store.total) or 0,
            bankKnown=store.bankKnown and true or false,status=status,satisfied=status=="bags" or status=="bank",
            satisfaction="exact-item",
        }
    end

    local bestBag, bestStorage, unknownBag, unknownBank = nil, nil, false, false
    for _, row in ipairs(hierarchy()) do
        local tier = tonumber(row.rodTier) or 0
        if tier >= requiredTier then
            local store = owned(row.itemID)
            local candidate = {
                itemID=tonumber(row.itemID),name=row.name,rodTier=tier,skillRequired=tonumber(row.skillRequired),
                bags=tonumber(store.bags) or 0,bank=tonumber(store.bank) or 0,total=tonumber(store.total) or 0,
                bankKnown=store.bankKnown and true or false,
            }
            if store.bagKnown ~= true then unknownBag=true end
            if store.bankKnown ~= true then unknownBank=true end
            if store.bagKnown==true and candidate.bags > 0 and (not bestBag or candidate.rodTier > bestBag.rodTier) then bestBag=candidate end
            if candidate.total > 0 and (not bestStorage or candidate.rodTier > bestStorage.rodTier) then bestStorage=candidate end
        end
    end

    local match = bestBag or bestStorage
    if match then
        if bestBag then
            local store=competenceStore(true)
            if store then
                store.tier=bestBag.rodTier;store.itemID=bestBag.itemID
                store.evidence=positiveEvidence
                store.characterKey=JLP:GetModule("CharacterIdentity"):GetCurrent().key
            end
        end
        local status=bestBag and "bags" or unknownBag and "unknown" or "bank"
        return {
            required=true,
            requiredItemID=tonumber(tool.itemID),requiredName=tool.name,requiredTier=requiredTier,
            itemID=match.itemID,name=match.name,rodTier=match.rodTier,skillRequired=match.skillRequired,
            bags=match.bags,bank=match.bank,total=match.total,bankKnown=match.bankKnown,
            status=status,satisfied=status=="bags" or status=="bank",
            satisfaction=(match.rodTier == requiredTier) and "exact-tier" or "higher-tier",
            contract=self.contract,
        }
    end

    local exact = owned(tool.itemID)
    return {
        required=true,
        requiredItemID=tonumber(tool.itemID),requiredName=tool.name,requiredTier=requiredTier,
        itemID=tonumber(tool.itemID),name=tool.name or "Required tool",rodTier=requiredTier,
        bags=tonumber(exact.bags) or 0,bank=tonumber(exact.bank) or 0,total=tonumber(exact.total) or 0,
        bankKnown=exact.bankKnown and true or false,
        status=(unknownBag or unknownBank) and "unknown" or "missing",
        satisfied=false,
        satisfaction="missing-minimum-tier",contract=self.contract,
    }
end

function EnchantingToolResolver:IsSatisfied(tool, requireBags)
    local result = self:Resolve(tool)
    if result.required == false then return true, result end
    if result.status=="confirmed" and not requireBags then return true,result end
    if requireBags then return (tonumber(result.bags) or 0) > 0, result end
    return (tonumber(result.total) or 0) > 0, result
end

function EnchantingToolResolver:Validate()
    local rows = hierarchy()
    local errors = {}
    local expected = {[1]=6218,[2]=6339,[3]=11130,[4]=11145,[5]=16207}
    for tier=1,5 do
        local row = rows[tier]
        if not row or tonumber(row.rodTier) ~= tier or tonumber(row.itemID) ~= expected[tier] then
            errors[#errors+1] = "Enchanting rod hierarchy tier "..tostring(tier).." is invalid"
        end
    end
    return #errors == 0, errors, {}
end

JLP:RegisterModule("EnchantingToolResolver", EnchantingToolResolver)
