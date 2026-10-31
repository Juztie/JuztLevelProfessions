local _, JLP = ...

-- Build-aware acquisition-source evidence for Formula/Pattern/Schematic/Recipe
-- gates in research routes. External Forever references can unlock a staging
-- access gate only on the build they were captured against. Live current-build
-- merchant/source observations are stronger and can re-corroborate a source
-- after a client update. This module never grants Planner/execution authority.
local RecipeAccessEvidence = {
    contract = "provenance-aware-recipe-access-evidence-v1",
    storeSchema = 1,
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
}

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function requirementKey(kind, name)
    return normalize(kind) .. ":" .. normalize(name)
end

local function currentBuildProvenance()
    -- Build-sensitive access evidence must come from the same live BuildInfo
    -- authority as requalification. A missing service/API is UNKNOWN, never a
    -- license to substitute the historical TARGET_BUILD constant.
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    if buildInfo and buildInfo.GetProvenance then
        return buildInfo:GetProvenance({allowTargetFallback=false})
    end
    return nil
end
local function epochNow()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function playerFaction()
    if type(UnitFactionGroup) == "function" then
        local ok, faction = pcall(UnitFactionGroup, "player")
        if ok and faction and faction ~= "" then return tostring(faction) end
    end
    return nil
end

local function catalogue()
    return JLP.data and JLP.data.recipeAccessSources or nil
end

local function referenceBuildState(reference)
    local root = catalogue()
    local metadata = root and root.sourceMetadata or nil
    local provenance = currentBuildProvenance()
    local capturedBuild = reference and tonumber(reference.capturedBuild) or (metadata and tonumber(metadata.capturedAgainstBuild) or nil)
    local currentBuild = provenance and tonumber(provenance.build) or nil
    -- Unknown build evidence is never equivalent to a current-build match.
    local matches = capturedBuild ~= nil and currentBuild ~= nil and currentBuild == capturedBuild
    return {
        capturedBuild = capturedBuild,
        currentBuild = currentBuild,
        matches = matches and true or false,
        unknown = currentBuild == nil,
        provenance = provenance,
    }
end

local function findReference(kind, name, itemID)
    local root = catalogue()
    if not root then return nil end
    itemID = tonumber(itemID)
    if itemID then
        for _, row in pairs(root.requirements or {}) do
            if tonumber(row.itemID) == itemID then return row end
        end
    end
    local key = requirementKey(kind, name)
    return root.requirements and root.requirements[key] or nil
end

local function getStore(create)
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    local root = JLP.DB.account.recipeAccessEvidence
    if type(root) ~= "table" then
        if not create then return nil end
        root = { schema=RecipeAccessEvidence.storeSchema, builds={} }
        JLP.DB.account.recipeAccessEvidence = root
    end
    root.schema = RecipeAccessEvidence.storeSchema
    root.builds = type(root.builds) == "table" and root.builds or {}
    return root
end

local function getBuildStore(create)
    local root = getStore(create)
    if not root then return nil, nil end
    local provenance = currentBuildProvenance()
    -- "unknown" tokens are not qualified live sessions. Never reuse or
    -- persist live evidence under a fabricated cross-build cache bucket.
    if not provenance or provenance.quality ~= "LIVE" or
       type(provenance.build) ~= "number" or provenance.build <= 0 then
        return root, nil
    end
    local actual = provenance.build
    if actual ~= math.floor(actual) or actual == math.huge or
       actual > 9007199254740991 then return root, nil end
    local expectedToken = string.format("forever:%s|interface:%s",
        tostring(actual), tostring(provenance.interface or "unknown"))
    local token = provenance.token
    if token ~= expectedToken then return root, nil end
    local build = root.builds[token]
    if type(build) ~= "table" then
        if not create then return root, nil end
        build = { provenance=provenance, requirements={} }
        root.builds[token] = build
    end
    -- P0/F1: the lookup key alone cannot establish the provenance of a
    -- persisted SavedVariables bucket. Do not promote legacy/contradictory
    -- buckets into LIVE evidence, and never silently rewrite their receipt.
    local stored = build.provenance
    if type(stored) ~= "table" or stored.quality ~= "LIVE" or
       stored.build ~= actual or stored.token ~= token or
       stored.interface ~= provenance.interface or
       stored.source ~= provenance.source then
        return root, nil
    end
    build.requirements = type(build.requirements) == "table" and build.requirements or {}
    return root, build
end


local function sourceMatchesFaction(source, faction)
    local sourceFaction = source and tostring(source.faction or "") or ""
    if sourceFaction == "" or sourceFaction == "Neutral" or faction == nil then return true end
    return sourceFaction == faction
end

local function selectReferenceSource(reference)
    if not reference or reference.conflict then return nil end
    local faction = playerFaction()
    local fallback
    for _, source in ipairs(reference.sources or {}) do
        if source.referenceEligible == true and sourceMatchesFaction(source, faction) then
            if tostring(source.faction or "") == faction then return source end
            fallback = fallback or source
        end
    end
    return fallback
end

local function itemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function merchantIdentity()
    local name, guid
    if type(UnitName) == "function" then
        local ok, value = pcall(UnitName, "npc")
        if ok and value and value ~= "" then name = tostring(value) end
    end
    if type(UnitGUID) == "function" then
        local ok, value = pcall(UnitGUID, "npc")
        if ok and value and value ~= "" then guid = tostring(value) end
    end
    return name, guid
end

function RecipeAccessEvidence:ObserveAccessItem(payload)
    if type(payload) ~= "table" then return false, "invalid-payload" end
    local reference = findReference(payload.kind, payload.name, payload.itemID)
    if not reference then return false, "untracked-access-item" end
    local sourceType = tostring(payload.sourceType or payload.type or "")
    local identity = payload.npc or payload.sourceName or payload.zone or payload.note
    if sourceType == "" or not identity or tostring(identity) == "" then return false, "incomplete-source" end

    local _, build = getBuildStore(true)
    if not build then return false, "build-unavailable" end
    local key = requirementKey(reference.kind, reference.name)
    local row = build.requirements[key]
    if type(row) ~= "table" then
        row = {
            kind = reference.kind,
            name = reference.name,
            itemID = tonumber(reference.itemID),
            accessItemName = reference.accessItemName,
            samples = 0,
            sources = {},
            evidenceIndex = {},
            firstObservedAt = epochNow(),
        }
        build.requirements[key] = row
    end

    local evidenceID = payload.evidenceID or payload.itemGUID
    if not evidenceID or evidenceID == "" then
        evidenceID = table.concat({sourceType, tostring(payload.npc or ""), tostring(payload.zone or ""), tostring(payload.itemID or reference.itemID or "")}, "|")
    end
    evidenceID = tostring(evidenceID)
    row.evidenceIndex = type(row.evidenceIndex) == "table" and row.evidenceIndex or {}
    if row.evidenceIndex[evidenceID] then return false, "duplicate-source-observation" end
    row.evidenceIndex[evidenceID] = true

    row.samples = math.max(0, tonumber(row.samples) or 0) + 1
    row.lastObservedAt = epochNow()
    row.lastSourceType = sourceType
    row.lastNpc = payload.npc
    row.lastNpcGUID = payload.npcGUID
    row.lastZone = payload.zone
    row.lastFaction = payload.faction or playerFaction()
    row.lastEvidence = payload.evidence or "live-current-build"
    row.sources = type(row.sources) == "table" and row.sources or {}
    local sourceKey = table.concat({sourceType, normalize(payload.npc), normalize(payload.zone)}, "|")
    local source = row.sources[sourceKey] or {sourceType=sourceType,npc=payload.npc,npcGUID=payload.npcGUID,zone=payload.zone,faction=payload.faction or playerFaction(),samples=0}
    source.samples = math.max(0, tonumber(source.samples) or 0) + 1
    source.lastObservedAt = row.lastObservedAt
    row.sources[sourceKey] = source

    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("RECIPE_ACCESS_EVIDENCE_UPDATED", row) end
    return true, row
end

function RecipeAccessEvidence:ObserveMerchant()
    if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemLink) ~= "function" then
        return 0, "merchant-api-unavailable"
    end
    local okCount, count = pcall(GetMerchantNumItems)
    count = okCount and tonumber(count) or 0
    if not count or count <= 0 then return 0, "merchant-empty" end
    local npc, npcGUID = merchantIdentity()
    local observed = 0
    for index=1,count do
        local okLink, link = pcall(GetMerchantItemLink, index)
        local itemID = okLink and itemIDFromLink(link) or nil
        local reference = itemID and findReference(nil, nil, itemID) or nil
        if reference then
            local accepted = self:ObserveAccessItem({
                kind = reference.kind,
                name = reference.name,
                itemID = itemID,
                sourceType = "vendor",
                npc = npc,
                npcGUID = npcGUID,
                faction = playerFaction(),
                evidenceID = table.concat({tostring(npcGUID or npc or "merchant"), tostring(itemID), tostring(index)}, "|"),
                evidence = "live-merchant-inventory",
            })
            if accepted then observed = observed + 1 end
        end
    end
    return observed, observed > 0 and "merchant-access-observed" or "no-tracked-access-items"
end

-- Current open merchant only. Cached positive source observations are NOT
-- stock, purchase eligibility, item possession or learning receipts.
function RecipeAccessEvidence:GetCurrentMerchantItem(itemID,npcID)
    local unknown={status="UNKNOWN",itemID=itemID,npcID=npcID,readOnly=true,nativeDispatchAllowed=false}
    if not MerchantFrame or type(MerchantFrame.IsShown)~="function" or not MerchantFrame:IsShown() or
        type(UnitGUID)~="function" or type(GetMerchantNumItems)~="function" or
        type(GetMerchantItemLink)~="function" then return unknown end
    local modern=type(C_MerchantFrame)=="table" and C_MerchantFrame.GetItemInfo
    local legacy=GetMerchantItemInfo
    if type(modern)~="function" and type(legacy)~="function" then return unknown end
    local function scan()
        local ok,guid=pcall(UnitGUID,"npc")
        if not ok or type(guid)~="string" or tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))~=npcID then return nil end
        local good,n=pcall(GetMerchantNumItems)
        if not good or type(n)~="number" or n<1 or n>500 or n~=math.floor(n) then return nil end
        local result={status="NOT_OFFERED",guid=guid,count=n,itemID=itemID,npcID=npcID}
        for i=1,n do
            local success,link=pcall(GetMerchantItemLink,i)
            local id=success and itemIDFromLink(link)
            if not id then return nil end -- incomplete vendor list is not absence
            if id==itemID then
                if result.slot then return nil end
                local read,name,available,purchasable,usable,price,stackCount,extended,currency
                if type(modern)=="function" then
                    local ok,info=pcall(modern,i)
                    read=ok and type(info)=="table"
                    if read then name=info.name;available=info.numAvailable;purchasable=info.isPurchasable;usable=info.isUsable
                        price=info.price;stackCount=info.stackCount;extended=info.hasExtendedCost;currency=info.currencyID end
                else
                    local ok,n,_,cost,quantity,stock,canBuy,canUse,extra=pcall(legacy,i)
                    read=ok;name=n;available=stock;purchasable=canBuy;usable=canUse
                    price=cost;stackCount=quantity;extended=extra
                end
                if not read or type(name)~="string" then return nil end
                result.slot=i;result.available=available;result.purchasable=purchasable;result.usable=usable
                result.price=price;result.stackCount=stackCount;result.hasExtendedCost=extended;result.currencyID=currency
                if purchasable==false or usable==false then result.status="INELIGIBLE"
                elseif available==0 then result.status="OUT_OF_STOCK"
                elseif type(available)=="number" and available==math.floor(available) and
                    (available>0 or available==-1) and purchasable==true and usable==true then result.status="AVAILABLE"
                else result.status="UNKNOWN" end
            end
        end
        return result
    end
    local a,b=scan(),scan()
    if not a or not b or not MerchantFrame:IsShown() or
        (type(C_MerchantFrame)=="table" and C_MerchantFrame.GetItemInfo or nil)~=modern or GetMerchantItemInfo~=legacy then return unknown end
    for _,k in ipairs({"status","guid","count","slot","available","purchasable","usable","price","stackCount","hasExtendedCost","currencyID"})do
        if a[k]~=b[k] then return unknown end
    end
    a.readOnly=true;a.nativeDispatchAllowed=false;a.source="STABLE_OPEN_MERCHANT_API"
    return a
end
-- Capability-checked advisory only. The exported MerchantItemInfo fields
-- (70450 API export) are not proof of availability in the current client.
-- Cost is per observed purchase unit; requested items are not stack counts.
function RecipeAccessEvidence:GetMerchantPurchaseAdvice(itemID,npcID,missing)
    local offer=self:GetCurrentMerchantItem(itemID,npcID)
    local result={status="VERIFY_OFFER",offer=offer,itemID=itemID,npcID=npcID,
        missing=missing,readOnly=true,nativeDispatchAllowed=false,observedOutputCredit=0}
    local function count(n)return type(n)=="number" and n>=0 and n<math.huge and n==math.floor(n)end
    if not count(missing) then result.status="UNKNOWN_QUANTITY";return result end
    if missing==0 then result.status="NO_PURCHASE_REQUIRED";return result end
    if offer.status~="AVAILABLE" then result.status=offer.status;return result end
    if not count(offer.stackCount) or offer.stackCount<1 or not count(offer.price) then return result end
    result.itemsPerPurchase=offer.stackCount
    result.purchaseUnits=math.ceil(missing/offer.stackCount)
    result.expectedItems=result.purchaseUnits*offer.stackCount
    if offer.hasExtendedCost~=false or (offer.currencyID~=nil and offer.currencyID~=0) then
        result.status="VERIFY_CURRENCY_REQUIREMENTS";return result end
    result.totalCopper=result.purchaseUnits*offer.price
    if type(GetMoney)~="function" then result.status="VERIFY_FUNDS";return result end
    local ok,a=pcall(GetMoney);local good,b=pcall(GetMoney)
    if not ok or not good or not count(a) or a~=b then result.status="VERIFY_FUNDS";return result end
    result.moneyCopper=a
    local current=self:GetCurrentMerchantItem(itemID,npcID)
    for _,k in ipairs({"status","guid","slot","count","available","price","stackCount","hasExtendedCost","currencyID"})do
        if current[k]~=offer[k]then result.status="VERIFY_CHANGED_OFFER";return result end
    end
    result.status=a<result.totalCopper and "INSUFFICIENT_FUNDS" or
        offer.available~=-1 and "VERIFY_LIMITED_STOCK" or "READY_MANUAL_PURCHASE"
    return result
end
-- A short-lived session hint prevents immediately sending the player back to
-- the just-inspected empty shop.120s is cache freshness, NOT a restock prediction.
-- Only negative snapshots are cached. It never establishes current stock/access.
local recentUnavailable={}
-- Read-only current trainer evidence. Exact spell links/IDs only; localized
-- names and an NPC rank never prove that a particular recipe is offered.
local function currentTrainerHint(self,spellID,npcID,teaching)
    local unknown={status="UNKNOWN",recipeID=spellID,npcID=npcID,readOnly=true,nativeDispatchAllowed=false}
    local frame=ClassTrainerFrame
    local countFn,infoFn=GetNumTrainerServices,GetTrainerServiceInfo
    local idFn,linkFn=GetTrainerServiceSpellID,GetTrainerServiceItemLink
    if not frame or type(frame.IsShown)~="function" or not frame:IsShown() or
       type(UnitGUID)~="function" or type(countFn)~="function" or type(infoFn)~="function" or
       (type(idFn)~="function" and type(linkFn)~="function")then return unknown end
    local function scan()
        local ok,guid=pcall(UnitGUID,"npc")
        if not ok or type(guid)~="string" or tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))~=npcID then return nil end
        local good,n=pcall(countFn)
        if not good or type(n)~="number" or n<1 or n>500 or n~=math.floor(n)then return nil end
        local complete=true
        if type(GetTrainerServiceTypeFilter)~="function" then complete=false
        else for _,filter in ipairs({"available","unavailable","used"})do
            local success,on=pcall(GetTrainerServiceTypeFilter,filter)
            if not success or (on~=true and on~=1)then complete=false end
        end end
        local result={status="UNKNOWN",guid=guid,count=n,recipeID=spellID,npcID=npcID,complete=complete,
            channel="STANDARD_TRAINER",menuScoped=true,teachingSpellID=teaching and teaching.spellID}
        local matches={}
        for i=1,n do
            local success,name,rank,kind=pcall(infoFn,i)
            if not success or type(name)~="string" then return nil end
            local id
            if type(idFn)=="function" then local success,value=pcall(idFn,i);if success and type(value)=="number" then id=value end end
            if not id and type(linkFn)=="function" then
                local success,link=pcall(linkFn,i)
                if success and type(link)=="string" then id=tonumber(link:match("|Hspell:(%d+)")or link:match("|Henchant:(%d+)"))end
            end
            if not id then return nil end -- headers/incomplete lists never establish absence
            if teaching and type(linkFn)=="function" and type(idFn)=="function" then
                local good,link=pcall(linkFn,i)
                local linked=good and type(link)=="string" and tonumber(link:match("|Hspell:(%d+)")or link:match("|Henchant:(%d+)"))
                if linked and linked~=id and not ((id==spellID or id==teaching.spellID)and (linked==spellID or linked==teaching.spellID))then
                    unknown.reason="CONFLICTING_TRAINER_ID_FIELDS";return nil
                end
            end
            if id==spellID or teaching and id==teaching.spellID then
                if result.slot and (not teaching or result.serviceType~=kind)then
                    unknown.reason="CONFLICTING_EXACT_TRAINER_IDENTITIES";return nil
                end
                result.slot=result.slot or i;result.serviceType=kind
                result.matchedSpellID=result.matchedSpellID or id
                matches[#matches+1]=i..":"..id..":"..tostring(kind)
                result.status=kind=="available" and "AVAILABLE" or kind=="unavailable" and "INELIGIBLE" or kind=="used" and "ALREADY_KNOWN_LISTED" or "UNKNOWN"
            end
        end
        result.matchesSignature=table.concat(matches,";")
        if not result.slot and complete then result.status="NOT_OFFERED"end
        return result
    end
    local a,b=scan(),scan()
    if not a or not b or not frame:IsShown() or frame~=ClassTrainerFrame or countFn~=GetNumTrainerServices or infoFn~=GetTrainerServiceInfo or idFn~=GetTrainerServiceSpellID or linkFn~=GetTrainerServiceItemLink then return unknown end
    for _,key in ipairs({"status","guid","count","slot","serviceType","complete","matchedSpellID","matchesSignature"})do if a[key]~=b[key]then return unknown end end
    a.readOnly=true;a.nativeDispatchAllowed=false;a.source="STABLE_OPEN_TRAINER_EXACT_SPELL_NOT_LEARNING_RECEIPT"
    return a
end
local recentTrainerUnavailable={}
function RecipeAccessEvidence:GetTrainerPlanningHint(spellID,npcID,professionKey)
    local facts=professionKey and JLP:GetModule("ProfessionPlanningFacts")
    local teaching=facts and facts.GetQualifiedTeachingRelation and facts:GetQualifiedTeachingRelation(professionKey,spellID)
    local current=currentTrainerHint(self,spellID,npcID,teaching)
    local identity=JLP:GetModule("CharacterIdentity")
    local row=identity and identity.GetCurrent and identity:GetCurrent()
    local key=row and row.key
    local ok,now=false,nil
    if type(GetTime)=="function" then ok,now=pcall(GetTime) end
    if type(key)=="string" and not key:find("Unknown",1,true) and ok and
        type(now)=="number" and now==now and now>=0 and now<math.huge then
        key=key..":"..tostring(npcID)..":"..tostring(spellID)..":"..tostring(professionKey or "EXACT_SPELL")
        if current.status=="NOT_OFFERED" or current.status=="INELIGIBLE" then recentTrainerUnavailable[key]=now
        elseif current.status=="AVAILABLE" or current.status=="ALREADY_KNOWN_LISTED" then recentTrainerUnavailable[key]=nil end
        local last=recentTrainerUnavailable[key]
        if last and now>=last and now-last<120 then
            current.recentUnavailable=true;current.recheckRequired=true
            current.negativeAgeSeconds=now-last
        end
    end
    return current
end
-- Optional exported GossipOptionUIInfo.spellID, never localized option text.
-- This is read-only associated-spell advice, not a verified Forever menu shape.
local function currentGossipTeachingHint(recipeID,npcID,teaching)
    local unknown={status="UNKNOWN",recipeID=recipeID,npcID=npcID,channel="GOSSIP",
        readOnly=true,nativeDispatchAllowed=false,menuScoped=true}
    local api=type(C_GossipInfo)=="table"and C_GossipInfo
    local fn=api and api.GetOptions;local frame=GossipFrame
    local statuses=type(Enum)=="table"and Enum.GossipOptionStatus
    if not teaching or type(fn)~="function"or not frame or type(frame.IsShown)~="function"or
       not frame:IsShown()or type(UnitGUID)~="function"or type(statuses)~="table"then return unknown end
    local function scan()
        local ok,guid=pcall(UnitGUID,"npc")
        if not ok or type(guid)~="string"or tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))~=npcID then return nil end
        local success,options=pcall(fn)
        if not success or type(options)~="table"or #options>500 then return nil end
        local result={status="UNKNOWN",guid=guid,recipeID=recipeID,npcID=npcID,
            channel="GOSSIP",menuScoped=true,teachingSpellID=teaching.spellID}
        local matches={}
        for _,option in ipairs(options)do
            if type(option)~="table"then return nil end
            if option.spellID==recipeID or option.spellID==teaching.spellID then
                local id=option.gossipOptionID
                if type(id)~="number"or id<1 or id>=math.huge or id~=math.floor(id)then return nil end
                local kind=option.status;local state="UNKNOWN"
                if type(kind)=="number"then
                    if kind==statuses.Available then state="AVAILABLE"
                    elseif kind==statuses.Unavailable or kind==statuses.Locked then state="INELIGIBLE"
                    elseif kind==statuses.AlreadyComplete then state="ALREADY_KNOWN_LISTED"end
                end
                if result.matchedSpellID~=nil and result.optionStatus~=kind then unknown.reason="CONFLICTING_EXACT_GOSSIP_IDENTITIES";return nil end
                result.optionStatus=kind;result.status=state;result.gossipOptionID=result.gossipOptionID or id
                result.matchedSpellID=result.matchedSpellID or option.spellID
                matches[#matches+1]=id..":"..option.spellID..":"..tostring(kind)
            end
        end
        result.matchesSignature=table.concat(matches,";")
        return result -- absent spellID is UNKNOWN, not NOT_OFFERED across channels
    end
    local a,b=scan(),scan()
    if not a or not b or not frame:IsShown()or frame~=GossipFrame or api~=C_GossipInfo or fn~=api.GetOptions then return unknown end
    for _,k in ipairs({"guid","status","optionStatus","gossipOptionID","matchedSpellID","matchesSignature"})do if a[k]~=b[k]then return unknown end end
    a.readOnly=true;a.nativeDispatchAllowed=false;a.source="STABLE_GOSSIP_EXACT_ASSOCIATED_SPELL_NOT_LEARNING_RECEIPT"
    return a
end
function RecipeAccessEvidence:GetRecipeLearningPlanningHint(key,recipeID,npcID)
    local facts=JLP:GetModule("ProfessionPlanningFacts")
    local teaching=facts and facts.GetQualifiedTeachingRelation and facts:GetQualifiedTeachingRelation(key,recipeID)
    local trainer=self:GetTrainerPlanningHint(recipeID,npcID,key)
    if not teaching then return trainer end
    local gossip=currentGossipTeachingHint(recipeID,npcID,teaching)
    local function actual(h)return h.status=="AVAILABLE"or h.status=="INELIGIBLE"or h.status=="ALREADY_KNOWN_LISTED"end
    if trainer.reason or gossip.reason or actual(trainer)and actual(gossip)and trainer.status~=gossip.status then
        return {status="UNKNOWN",recipeID=recipeID,npcID=npcID,reason="CONFLICTING_CURRENT_LEARNING_OFFERS",
            readOnly=true,nativeDispatchAllowed=false}
    end
    if actual(gossip)then return gossip end -- a standard-menu absence cannot negate this channel
    return trainer
end
function RecipeAccessEvidence:GetMerchantPlanningHint(itemID,npcID)
    local current=self:GetCurrentMerchantItem(itemID,npcID)
    local key=tostring(npcID)..":"..tostring(itemID)
    local ok,now=false,nil
    if type(GetTime)=="function" then ok,now=pcall(GetTime) end
    if ok and type(now)=="number" and now==now and now<math.huge then
        if current.status=="OUT_OF_STOCK" or current.status=="NOT_OFFERED" or current.status=="INELIGIBLE" then
            recentUnavailable[key]=now
        elseif current.status=="AVAILABLE" then recentUnavailable[key]=nil
        elseif recentUnavailable[key] and now>=recentUnavailable[key] and now-recentUnavailable[key]<=120 then
            current.recentUnavailable=true;current.previousObservationAge=now-recentUnavailable[key]
        end
    end
    return current
end

-- Current vendor prerequisite only. Never persists a quest, item, equipped
-- state or access grant. A usable exact offer can prove current interaction,
-- but cannot manufacture the item's acquisition history or quest completion.
function RecipeAccessEvidence:GetVendorAccessPlanningHint(npcID,offer)
 local d=JLP.data and JLP.data.blacksmithing and JLP.data.blacksmithing.magnusAccess
 if not d or npcID~=d.npcID then return nil end
 local result={npcID=npcID,itemID=d.itemID,itemName=d.itemName,status="UNKNOWN",
  readOnly=true,nativeDispatchAllowed=false,questCompletionCredit=false,
  source=d.evidence,questGuideURL=d.guideURL,internalObjectives=d.internalObjectives}
 local inventory=JLP:GetModule("Inventory")
 local owned=inventory and inventory.GetOwned and inventory:GetOwned(d.itemID)
 local function count(n)return type(n)=="number"and n>=0 and n<math.huge and n==math.floor(n)end
 if owned then
  if owned.bagKnown==true and count(owned.bags)then result.bags=owned.bags end
  if owned.bankKnown==true and count(owned.bank)then result.bank=owned.bank end
 end
 local equippedFn=type(C_Item)=="table"and C_Item.IsEquippedItem or IsEquippedItem
 if type(equippedFn)=="function"then
  local ok,value=pcall(equippedFn,d.itemID)
  if ok and type(value)=="boolean"then result.equipped=value end
 end
 if offer and offer.status=="AVAILABLE"and offer.source=="STABLE_OPEN_MERCHANT_API" then
  result.status="CURRENT_USABLE_OFFER";result.currentInteractionObserved=true;return result
 end
 if result.equipped==true then result.status="EQUIPPED";return result end
 if result.bags and result.bags>0 then result.status=result.equipped==false and "EQUIP_MANUALLY"or "VERIFY_EQUIPPED_STATE";return result end
 if result.bags==0 and result.bank and result.bank>0 then result.status="BANK";return result end
 if result.bags~=0 or result.bank~=0 then return result end -- UNKNOWN is not missing
 result.itemKnownAbsent=true
 local ok,level=false,nil
 if type(UnitLevel)=="function"then ok,level=pcall(UnitLevel,"player")end
 if not ok or not count(level)or level<1 then result.status="VERIFY_QUEST_LEVEL";return result end
 if level<d.questMinimumLevel then result.status="QUEST_LEVEL_UNMET";result.requiredLevel=d.questMinimumLevel;return result end
 local quest=type(C_QuestLog)=="table"and C_QuestLog or {}
 local flags={};result.questFlags=flags
 for _,row in ipairs(d.quests)do
  local success,complete=false,nil
  if type(quest.IsQuestFlaggedCompleted)=="function"then success,complete=pcall(quest.IsQuestFlaggedCompleted,row.id)end
  if success and type(complete)=="boolean"then flags[row.id]=complete end
  if not success or type(complete)~="boolean"then result.status="VERIFY_QUEST_STATE";result.questID=row.id;result.questName=row.name;return result end
  if complete==false then
   local active,ready
   if type(quest.IsOnQuest)=="function"then local good,v=pcall(quest.IsOnQuest,row.id);if good and type(v)=="boolean"then active=v end end
   if active==true and type(quest.ReadyForTurnIn)=="function"then local good,v=pcall(quest.ReadyForTurnIn,row.id);if good and type(v)=="boolean"then ready=v end end
   result.questID=row.id;result.questName=row.name;result.active=active;result.ready=ready
   result.status=active==false and "QUEST_START"or active==true and ready==true and "QUEST_RETURN"or active==true and "QUEST_OBJECTIVES"or "VERIFY_QUEST_LOG"
   return result
  end
 end
 result.status="VERIFY_MISSING_REWARD" -- completed quest is not a bag receipt/replacement offer
 return result
end

function RecipeAccessEvidence:GetLive(kind, name, itemID)
    local _, build = getBuildStore(false)
    if not build then return nil end
    local reference = findReference(kind, name, itemID)
    local key = reference and requirementKey(reference.kind, reference.name) or requirementKey(kind, name)
    return build.requirements and build.requirements[key] or nil
end

function RecipeAccessEvidence:GetReference(kind, name, itemID)
    return findReference(kind, name, itemID)
end

function RecipeAccessEvidence:Resolve(kind, name, itemID)
    local reference = findReference(kind, name, itemID)
    local live = self:GetLive(kind, name, itemID)
    local buildState = referenceBuildState(reference)
    local out = {
        kind = kind,
        name = name,
        itemID = itemID or (reference and reference.itemID),
        reference = reference,
        live = live,
        source = nil,
        sourceType = nil,
        ready = false,
        promotionEligible = false,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        currentBuild = buildState.currentBuild,
        referenceCapturedBuild = buildState.capturedBuild,
        referenceBuildMatch = buildState.matches,
        planningUsable = false,
        planningOnly = true,
    }

    if live and (tonumber(live.samples) or 0) >= 1 then
        local best
        for _, row in pairs(live.sources or {}) do
            if not best or (tonumber(row.samples) or 0) > (tonumber(best.samples) or 0) then best = row end
        end
        out.status = "live-current-build-access-source"
        out.state = out.status
        out.ready = true
        out.promotionEligible = true
        out.planningUsable = true
        out.planningOnly = false
        out.source = best or {sourceType=live.lastSourceType,npc=live.lastNpc,zone=live.lastZone,faction=live.lastFaction}
        out.sourceType = out.source and out.source.sourceType or live.lastSourceType
        out.evidence = live.lastEvidence or "live-current-build"
        out.confidence = (tonumber(live.samples) or 0) >= 2 and "verified" or "observed"
        out.liveVerified = true
        return out
    end

    if not reference then
        out.status = "access-source-reference-missing"
        out.state = out.status
        return out
    end
    if reference.conflict then
        out.status = "external-access-source-conflict"
        out.state = out.status
        out.conflict = true
        out.conflictReason = reference.conflictReason
        return out
    end
    local selected = selectReferenceSource(reference)
    if not selected then
        out.status = "external-access-source-unresolved"
        out.state = out.status
        return out
    end
    -- A documented access source is relevant to a research plan regardless
    -- of its captured build; it is NOT proof the recipe is learned or sold now.
    out.planningUsable = true
    if buildState.unknown then
        out.status = "external-access-source-build-unknown"
        out.state = out.status
        out.source = selected
        out.sourceType = selected.sourceType
        out.evidence = selected.evidence
        out.confidence = "unqualified-reference"
        return out
    end
    if not buildState.matches then
        out.status = "external-access-source-stale-build"
        out.state = out.status
        out.source = selected
        out.sourceType = selected.sourceType
        out.evidence = selected.evidence
        out.confidence = "historical-reference"
        return out
    end

    out.status = "external-forever-access-source"
    out.state = out.status
    out.ready = true
    out.promotionEligible = true
    out.source = selected
    out.sourceType = selected.sourceType
    out.evidence = selected.evidence
    out.confidence = selected.evidenceQuality or "external-reference"
    out.externalVerified = true
    return out
end

function RecipeAccessEvidence:Validate()
    local errors, warnings = {}, {}
    local root = catalogue()
    if not root then return {"recipe access source catalogue unavailable"}, warnings end
    if root.contract ~= "forever-recipe-access-source-reference-v1" then errors[#errors+1] = "recipe access source catalogue contract mismatch" end
    local research = JLP.data and JLP.data.professionResearchRoutes
    local seen = {}
    for professionKey, modes in pairs(research and research.professions or {}) do
        if professionKey ~= "HARNESS" and professionKey ~= "HARNESSCLOSURE" then
            for _, mode in pairs(modes or {}) do
                for _, step in ipairs(type(mode)=="table" and mode.steps or {}) do
                    local requirement = step.sourceRequirement
                    if requirement then
                        local key = requirementKey(requirement.kind, requirement.name)
                        seen[key] = true
                        if not root.requirements[key] then warnings[#warnings+1] = "missing access-source reference: " .. key end
                    end
                end
            end
        end
    end
    for key, row in pairs(root.requirements or {}) do
        if requirementKey(row.kind, row.name) ~= key then errors[#errors+1] = "access-source key mismatch: " .. tostring(key) end
        if not tonumber(row.itemID) then errors[#errors+1] = "access-source itemID missing: " .. tostring(key) end
        if type(row.sources) ~= "table" or #row.sources == 0 then errors[#errors+1] = "access-source source list missing: " .. tostring(key) end
        local hasEligible = false
        for _, source in ipairs(row.sources or {}) do
            if source.referenceEligible == true then hasEligible = true end
            if not source.sourceType or not source.evidence then errors[#errors+1] = "incomplete access-source evidence: " .. tostring(key) end
        end
        if not row.conflict and not hasEligible then warnings[#warnings+1] = "non-conflicting access source has no eligible reference: " .. tostring(key) end
    end
    return errors, warnings
end

local function formatSource(source)
    if not source then return "unresolved" end
    local parts = { tostring(source.sourceType or "source") }
    if source.npc then parts[#parts+1] = tostring(source.npc) end
    if source.zone then parts[#parts+1] = tostring(source.zone) end
    if source.faction then parts[#parts+1] = tostring(source.faction) end
    return table.concat(parts, " · ")
end

function RecipeAccessEvidence:GetSummary(kind, name)
    if kind and name then
        local row = self:Resolve(kind, name)
        local lines = {
            string.format("Recipe access evidence: %s: %s", tostring(kind), tostring(name)),
            "Status: " .. tostring(row.status),
            "Source: " .. formatSource(row.source),
            "Confidence: " .. tostring(row.confidence or "none"),
            "Current build: " .. tostring(row.currentBuild or "unknown"),
            "Reference build: " .. tostring(row.referenceCapturedBuild or "unknown"),
            "Promotion access gate: " .. tostring(row.promotionEligible == true),
            "Historical planning source (read-only): " .. tostring(row.planningUsable == true),
            "Planner authority: disabled",
        }
        if row.conflictReason then lines[#lines+1] = "Conflict: " .. tostring(row.conflictReason) end
        return table.concat(lines, "\n")
    end
    local root = catalogue()
    if not root then return "Recipe access evidence unavailable." end
    local total, eligible, conflicts = 0, 0, 0
    for _, row in pairs(root.requirements or {}) do
        total = total + 1
        if row.conflict then conflicts = conflicts + 1
        elseif selectReferenceSource(row) then eligible = eligible + 1 end
    end
    return table.concat({
        "Recipe access evidence:",
        string.format("External requirements: %d · reference-eligible %d · conflicted %d", total, eligible, conflicts),
        "Authority: live current-build source > same-build external Forever reference > unresolved/stale",
        "External references are not build-pinned; after a Forever build change they must be re-corroborated by live source observation.",
        "Planner authority disabled",
    }, "\n")
end

JLP:RegisterModule("RecipeAccessEvidence", RecipeAccessEvidence)
