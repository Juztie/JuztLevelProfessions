local _, JLP = ...

-- Generic material metadata and acquisition-option resolver. It unifies item
-- identity across all registered profession datasets and the external/current
-- acquisition evidence catalogue. Alt-bank inventory is advisory acquisition
-- data only and is never counted as immediate CraftReadiness.
local MaterialCatalog = {
    contract = "generic-material-catalog-v1",
    acquisitionContract = "multi-source-acquisition-options-v1",
    _index = nil,
}

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function shallowMerge(dst, src)
    for k,v in pairs(src or {}) do
        if dst[k] == nil then dst[k] = v end
    end
end

-- Never infer client evidence from TOC/target constants or source build. The
-- live ClientBuildInfo parser is the only default build authority here.
local function observedBuild()
    local client=JLP:GetModule("ClientBuildInfo")
    local function valid(n)
        return type(n)=="number" and n==n and n>0 and
            n<=9007199254740991 and n==math.floor(n)
    end
    if type(client)~="table" then
        return nil,"CLIENT_BUILD_UNAVAILABLE",nil,false
    end
    if type(client.Read)=="function" then
        local ok,info=pcall(client.Read,client)
        if ok and type(info)=="table" and info.known==true and
            valid(info.buildNumber) then
            local build,interface=info.buildNumber,info.interfaceVersion
            local expected=string.format("forever:%s|interface:%s",
                tostring(build),tostring(valid(interface) and interface or "unknown"))
            if info.token==expected then
                if valid(interface) then
                    return build,"LIVE_CLIENT_SESSION",expected,true
                end
                -- A real build with no interface is still useful as a scope,
                -- but it must never be a verified LIVE session receipt.
                return build,"LIVE_CLIENT_BUILD_ONLY",expected,false
            end
        end
        return nil,"CLIENT_SESSION_UNVERIFIED",nil,false
    end
    -- Legacy stubs without Read() can supply a build-only advisory scope.
    -- They cannot certify a full live client receipt.
    if type(client.GetBuildNumber)=="function" then
        local ok,build=pcall(client.GetBuildNumber,client)
        if ok and valid(build) then
            return build,"LIVE_CLIENT_BUILD_ONLY",
                string.format("forever:%s|interface:unknown",tostring(build)),false
        end
    end
    return nil,"CLIENT_BUILD_UNVERIFIED",nil,false
end

function MaterialCatalog:Rebuild()
    local clientBuild,buildEvidence,clientToken,liveSessionVerified=observedBuild()
    local byID, byName = {}, {}
    local reg = JLP:GetModule("ProfessionRegistry")
    local provider = JLP:GetModule("ProfessionDatasetProvider")
    for _, key in ipairs(reg and reg:GetKeys() or {}) do
        local dataset = provider and select(1, provider:GetRegisteredDataset(key)) or nil
        local datasetMaterials={}
        for _,material in pairs(dataset and dataset.materials or {})do datasetMaterials[#datasetMaterials+1]=material end
        if (key=="ALCHEMY" or key=="BLACKSMITHING" or key=="ENGINEERING" or key=="LEATHERWORKING" or key=="FIRST_AID" or key=="COOKING") and dataset and dataset.progression and dataset.progression.contract==key:lower().."-70532-progression-v1" then
            for _,recipe in pairs(dataset.progression.recipes or {})do
                for _,material in ipairs(recipe.referenceMaterials or {})do datasetMaterials[#datasetMaterials+1]=material end
            end
        end
        for _, material in ipairs(datasetMaterials) do
            if type(material) == "table" then
                local id = tonumber(material.itemID)
                local nameKey = normalize(material.name)
                local row = id and byID[id] or nil
                -- Never collapse two different ItemIDs via a matching name.
                if not row and not id and nameKey ~= "" then row = byName[nameKey] end
                if not row then row = {itemID=id,name=material.name,professions={},sources={}} end
                row.itemID = row.itemID or id
                row.name = row.name or material.name
                row.professions[key] = true
                if material.source then row.sources[tostring(material.source)] = true end
                if id then byID[id] = row end
                if nameKey ~= "" and not byName[nameKey] then byName[nameKey] = row end
            end
        end
    end

    -- Primary static item metadata from the shared JLP professions catalogue.
    -- Advisory identity enrichment only: unknown names and client stock stay
    -- UNKNOWN, and existing per-item acquisition authority is not overwritten.
    local sharedCatalogue=JLP:GetModule("ProfessionsDataCatalogue")
    local materialIndex=nil
    local catalogueOK=true
    if sharedCatalogue and type(sharedCatalogue.GetReagentIndex)=="function" then
        local ok,result=pcall(sharedCatalogue.GetReagentIndex,sharedCatalogue,clientBuild)
        if ok and type(result)=="table" then materialIndex=result
        else catalogueOK=false end
    elseif sharedCatalogue then catalogueOK=false end
    -- Static index completeness and live session verification are separate.
    -- A build-only receipt may describe a reference scope but cannot prove
    -- LIVE identity. No client build may masquerade as source provenance.
    local function positiveBuild(value)
        return type(value)=="number" and value>0 and
            value==math.floor(value) and value<math.huge
    end
    -- Both unknown on the request and the provider is a consistent static
    -- reference scope; unknown is NEVER a verified client receipt.
    local scopeConsistent=materialIndex and
        materialIndex.clientBuild==clientBuild and
        materialIndex.requestedBuild==clientBuild and
        (clientBuild==nil or positiveBuild(clientBuild)) and
        materialIndex.qualificationScope=="STATIC_SOURCE_FIELDS_ONLY" and
        materialIndex.liveClientVerified==liveSessionVerified and
        materialIndex.liveClientToken==(liveSessionVerified and clientToken or nil)
    local errors=materialIndex and materialIndex.errors
    local emptyErrorReceipt=type(errors)=="table" and next(errors)==nil
    -- P1-D1: COMPLETE requires the *exact* current registry key set, not
    -- merely COMPLETE receipts for whichever professions a provider supplied.
    -- This verifies the bounded receipt envelope; it does not promote
    -- historical material evidence, stock, production or native permissions.
    local function validateProfessionReceipts()
        if not materialIndex or type(materialIndex.professions)~="table" then
            return false,"PROFESSION_RECEIPTS_MISSING"
        end
        if type(reg)~="table" or type(reg.GetKeys)~="function" then
            return false,"PROFESSION_REGISTRY_UNAVAILABLE"
        end
        local ok,keys=pcall(reg.GetKeys,reg)
        if not ok or type(keys)~="table" then
            return false,"PROFESSION_REGISTRY_INVALID"
        end
        local expected,count,maxIndex={},0,0
        for index,key in pairs(keys) do
            if type(index)~="number" or index<1 or index>64 or
                index~=math.floor(index) or type(key)~="string" or
                key=="" or expected[key] then
                return false,"PROFESSION_REGISTRY_INVALID"
            end
            expected[key]=true
            count=count+1
            if index>maxIndex then maxIndex=index end
        end
        if count==0 or maxIndex~=count then
            return false,"PROFESSION_REGISTRY_INVALID"
        end
        local observed=0
        for key,receipt in pairs(materialIndex.professions) do
            if not expected[key] then
                return false,"PROFESSION_RECEIPT_FOREIGN",key
            end
            if type(receipt)~="table" or receipt.status~="COMPLETE" or
                receipt.complete~=true or receipt.reason~=nil then
                return false,"PROFESSION_RECEIPT_INCOMPLETE",key
            end
            -- Q124 GetReagentIndex always emits a bounded complete pagination
            -- receipt. No implicit "legacy" exception: missing fields from an
            -- alternate provider cannot prove an entire index COMPLETE.
            -- These are recipe-row counts, not material ItemID counts.
            local n,total=receipt.count,receipt.total
            if type(n)~="number" or type(total)~="number" or
                n<0 or n>32768 or n==math.huge or
                n~=math.floor(n) or total~=n then
                return false,"PROFESSION_RECEIPT_COUNT_CONFLICT",key
            end
            -- Q124 requests pages of 12 rows and makes one empty request for
            -- a zero-row index. A completed receipt must have exactly the
            -- page count implied by the observed total; inflated/missing page
            -- metadata is never authority for global catalogue COMPLETE.
            local pages=receipt.numberOfPages
            local expectedPages=math.max(1,math.ceil(total/12))
            if type(pages)~="number" or pages~=math.floor(pages) or
                pages~=expectedPages then
                return false,"PROFESSION_RECEIPT_PAGES_INVALID",key
            end
            observed=observed+1
        end
        if observed~=count then
            for _,key in ipairs(keys) do
                if materialIndex.professions[key]==nil then
                    return false,"PROFESSION_RECEIPT_MISSING",key
                end
            end
            return false,"PROFESSION_RECEIPT_SET_CONFLICT"
        end
        return true,nil,nil,expected
    end
    local professionsComplete,receiptIssue,receiptProfession,expectedProfessions=
        validateProfessionReceipts()
    -- Do not trust COMPLETE if an alternate provider supplied sparse,
    -- duplicated or invalid ItemIDs; Q124 normally guarantees this shape.
    local indexRowsValid=materialIndex~=nil
    if indexRowsValid then
        local count,seenIDs=0,{}
        for k,v in pairs(materialIndex) do
            if type(k)=="number" then
                if k<1 or k>32768 or k~=math.floor(k) or
                    type(v)~="table" or not positiveBuild(v.itemID) or
                    seenIDs[v.itemID] then
                    indexRowsValid=false;break
                end
                seenIDs[v.itemID]=true
                count=count+1
            end
        end
        if indexRowsValid then
            for i=1,count do
                if type(materialIndex[i])~="table" then
                    indexRowsValid=false;break
                end
            end
        end
    end
    local catalogueComplete=catalogueOK and materialIndex~=nil and
        materialIndex.complete==true and materialIndex.status=="COMPLETE" and
        materialIndex.readOnly==true and materialIndex.nativeDispatchAllowed==false and
        emptyErrorReceipt and scopeConsistent and professionsComplete and
        indexRowsValid

    -- Qualify each item from its actual, positive source provenance; merely
    -- reporting an index status or sharing a build number is insufficient.
    -- Different historical source builds alone are never a field conflict.
    local function sourceProvenance(material)
        if type(material)~="table" or not positiveBuild(material.sourceBuild) or
            type(material.sourceBuilds)~="table" then return nil end
        local seen,copy,count,containsOrigin={},{},0,false
        for index,value in pairs(material.sourceBuilds) do
            if type(index)~="number" or index<1 or index>32768 or
                index~=math.floor(index) or not positiveBuild(value) or
                seen[value] then return nil end
            seen[value]=true
            count=count+1
            if value==material.sourceBuild then containsOrigin=true end
        end
        if count==0 or not containsOrigin then return nil end
        for i=1,count do
            if not positiveBuild(material.sourceBuilds[i]) then return nil end
            copy[i]=material.sourceBuilds[i]
        end
        return copy
    end
    -- An index that claims COMPLETE but contains any unqualified member is
    -- inconsistent; do not allow independent rows to mask the partial source.
    if catalogueComplete then
        for _,material in ipairs(materialIndex) do
            local memberOK=type(material.professions)=="table"
            local memberCount=0
            if memberOK then
                for key,value in pairs(material.professions) do
                    if not expectedProfessions[key] or value~=true then
                        memberOK=false;break
                    end
                    memberCount=memberCount+1
                end
            end
            if not memberOK or memberCount==0 or
                material.indexComplete~=true or
                material.evidenceState~="SOURCE_QUALIFIED" or
                material.buildQualified~=true or material.readOnly~=true or
                material.nativeDispatchAllowed~=false or
                sourceProvenance(material)==nil then
                catalogueComplete=false
                break
            end
        end
    end
    for _,material in ipairs(materialIndex or {}) do
        local id=tonumber(material.itemID)
        if id and id>0 and id==math.floor(id) then
            local row=byID[id] or {itemID=id,name=material.name,professions={},sources={}}
            row.name=row.name or material.name
            row.professions=row.professions or {}
            row.sources=row.sources or {}
            for key in pairs(material.professions or {}) do row.professions[key]=true end
            local sourceBuilds=sourceProvenance(material)
            local qualified=catalogueComplete and material.indexComplete==true and
                material.evidenceState=="SOURCE_QUALIFIED" and
                material.buildQualified==true and material.readOnly==true and
                material.nativeDispatchAllowed==false and sourceBuilds~=nil
            row.catalogueEvidenceState=qualified and "SOURCE_QUALIFIED" or
                (not clientBuild and "UNKNOWN" or
                    not scopeConsistent and "CONFLICT" or "PARTIAL")
            row.catalogueSourceBuild=material.sourceBuild
            row.catalogueSourceBuilds=sourceBuilds
            row.catalogueRequestedBuild=materialIndex and materialIndex.requestedBuild
            row.catalogueProductionAuthority="NOT_AUTHORIZED"
            row.catalogueIndexQualified=qualified
            row.catalogueCompleteness=qualified and "COMPLETE" or "PARTIAL"
            -- Advisory only; no material availability, trainer, cost, native
            -- production or fallback completeness is authorized by this merge.
            row.sources[qualified and "jlp-static-recipe-reference" or
                "jlp-static-recipe-reference-partial"]=true
            byID[id]=row
            local n=normalize(row.name)
            if n~="" and not byName[n] then byName[n]=row end
        end
    end

    local acquisition = JLP.data and JLP.data.materialAcquisitionSources
    for nameKey, source in pairs(acquisition and acquisition.materials or {}) do
        local id = tonumber(source.itemID)
        local normalizedName = normalize(source.name or nameKey)
        local row = id and byID[id] or byName[normalizedName]
        -- Historical name-only sources cannot rebind another exact ItemID.
        if id and row and row.itemID and row.itemID~=id then row=nil end
        if not row then row = {itemID=id,name=source.name,professions={},sources={}} end
        row.itemID = row.itemID or id
        row.name = row.name or source.name
        row.acquisition = row.acquisition or {}
        shallowMerge(row.acquisition, source)
        if source.plannerSource then row.sources[source.plannerSource] = true end
        if row.itemID then byID[row.itemID] = row end
        if normalizedName ~= "" and not byName[normalizedName] then byName[normalizedName] = row end
    end

    local de = JLP.data and JLP.data.disenchant
    for itemID, name in pairs(de and de.itemNames or {}) do
        itemID = tonumber(itemID)
        if itemID then
            local row = byID[itemID] or {itemID=itemID,name=name,professions={},sources={}}
            row.name = row.name or name
            byID[itemID] = row
            local normalized=normalize(row.name)
            if normalized~="" and not byName[normalized] then byName[normalized] = row end
        end
    end

    self._index = {byID=byID,byName=byName,
        catalogueCompleteness=catalogueComplete and "COMPLETE" or
            (clientBuild==nil and "UNKNOWN" or not scopeConsistent and "CONFLICT" or "PARTIAL"),
        catalogueClientBuild=clientBuild,
        catalogueClientToken=clientToken,
        catalogueRequestedBuild=materialIndex and materialIndex.requestedBuild,
        buildEvidence=buildEvidence,
        catalogueComplete=catalogueComplete,
        liveClientVerified=liveSessionVerified,
        qualificationScope="STATIC_SOURCE_FIELDS_ONLY",
        catalogueReceiptIssue=receiptIssue,
        catalogueReceiptProfession=receiptProfession,
        catalogueErrors=materialIndex and (type(materialIndex.errors)=="table" and
            materialIndex.errors or {{reason="CATALOGUE_ERRORS_MALFORMED"}}) or
            (catalogueOK and {{reason="CATALOGUE_INDEX_MISSING"}} or
                {{reason="CATALOGUE_PROVIDER_UNAVAILABLE"}}),
        catalogueProvenance=materialIndex and materialIndex.professions or {}}
    return self._index
end

local function index(self)
    local current,_,token,verified=observedBuild()
    if not self._index or self._index.catalogueClientBuild~=current or
        self._index.catalogueClientToken~=token or
        self._index.liveClientVerified~=verified then
        return self:Rebuild()
    end
    return self._index
end

function MaterialCatalog:GetCatalogueIndexStatus()
    local idx=index(self)
    return {complete=idx.catalogueComplete,status=idx.catalogueCompleteness,
        errors=idx.catalogueErrors,professions=idx.catalogueProvenance,
        receiptIssue=idx.catalogueReceiptIssue,
        receiptProfession=idx.catalogueReceiptProfession,
        clientBuild=idx.catalogueClientBuild,
        clientToken=idx.catalogueClientToken,
        requestedBuild=idx.catalogueRequestedBuild,buildEvidence=idx.buildEvidence,
        liveClientVerified=idx.liveClientVerified,
        qualificationScope=idx.qualificationScope,
        nativeDispatchAllowed=false}
end

-- Expose a bounded, read-only explanation for MATERIALS & SOURCES. Only
-- fixed internal reason codes are displayed; external provider error text is
-- retained in diagnostics but never treated as trusted UI or crafting evidence.
function MaterialCatalog:GetCatalogueHealthNotice(professionKey)
    if type(professionKey)~="string" or professionKey=="" then return nil end
    local snapshot=self:GetCatalogueIndexStatus()
    local profession=snapshot.professions and snapshot.professions[professionKey]
    if snapshot.complete then return nil end
    if not snapshot.clientBuild then
        return "Catalogue PARTIAL; static source receipts incomplete (client build unknown)"
    end
    local reason=profession and profession.reason or nil
    local receiptDescriptions={
        PROFESSION_RECEIPTS_MISSING="profession receipts unavailable",
        PROFESSION_REGISTRY_UNAVAILABLE="profession registry unavailable",
        PROFESSION_REGISTRY_INVALID="profession registry invalid",
        PROFESSION_RECEIPT_FOREIGN="unknown profession receipt",
        PROFESSION_RECEIPT_INCOMPLETE="incomplete profession receipt",
        PROFESSION_RECEIPT_COUNT_CONFLICT="profession receipt count conflict",
        PROFESSION_RECEIPT_PAGES_INVALID="profession receipt page conflict",
        PROFESSION_RECEIPT_MISSING="expected profession receipt missing",
        PROFESSION_RECEIPT_SET_CONFLICT="profession receipt set conflict",
    }
    if receiptDescriptions[snapshot.receiptIssue] then
        return "Catalogue PARTIAL ("..receiptDescriptions[snapshot.receiptIssue].."); verify materials manually"
    end
    local descriptions={
        PROVIDER_DECLARED_INCOMPLETE="provider declared an incomplete page",
        PROVIDER_STATUS_NOT_COMPLETE="provider reported a partial/unknown page",
        PROVIDER_REPORTED_ERRORS="provider reported source errors",
        PAGE_COMPLETE_MALFORMED="provider completeness flag invalid",
        PAGE_STATUS_MALFORMED="provider status invalid",
        PAGE_ERROR_ENTRY_MALFORMED="provider error receipt invalid",
        PAGE_ERRORS_NOT_ARRAY="provider error receipt invalid",
        PAGE_ERRORS_ARRAY_KEY_INVALID="provider error receipt has invalid keys",
        PAGE_ERRORS_ARRAY_SPARSE="provider error receipt has gaps",
    }
    if descriptions[reason] then
        return "Catalogue PARTIAL ("..descriptions[reason].."); verify materials manually"
    end
    return nil
end

function MaterialCatalog:Resolve(itemID, name)
    local idx = index(self)
    local row = tonumber(itemID) and idx.byID[tonumber(itemID)] or nil
    if not row and not itemID and name then row = idx.byName[normalize(name)] end
    return row
end

function MaterialCatalog:GetName(itemID, fallback)
    local row = self:Resolve(itemID, fallback)
    -- An exact current-build ItemID name takes precedence over historical
    -- datasets. Do not infer an ItemID from a coincidentally matching name.
    if tonumber(itemID) then
        local ref=JLP:GetModule("Build70450ItemMetadata")
        local item=ref and ref.GetItem and ref:GetItem(tonumber(itemID),70450)
        if item and type(item.name)=="string" and item.name~="" then return item.name end
    end
    if row and row.name and row.name ~= "" then return row.name end
    return fallback or (itemID and ("Item "..tostring(itemID))) or "Material"
end

local function addOption(out, seen, kind, label, meta)
    if not kind or not label then return end
    local token = tostring(kind).."|"..tostring(meta and meta.characterKey or "").."|"..tostring(meta and meta.professionKey or "")
    if seen[token] then return end
    seen[token] = true
    local row = {kind=kind,source=kind,label=label}
    for k,v in pairs(meta or {}) do row[k]=v end
    -- Existence in the catalogue is not proof of source eligibility.
    if row.eligible == nil then
        row.eligible = kind=="bags" or kind=="bank"
    end
    -- Static research, historical vendor types, and generic AH availability
    -- are suggestions only, never proof of current NPC stock or ownership.
    if kind~="bags" and kind~="bank" then
        row.eligible=false
        row.referenceOnly=true
        row.sourceVerifiedLive=false
    end
    row.availabilityState = row.availabilityState or
        (row.referenceOnly and "REFERENCE_ONLY" or
        (not row.eligible and "UNAVAILABLE" or
         (kind == "bags" and "AVAILABLE" or kind == "bank" and "RETRIEVE" or
          kind == "alt-bank" and "TRANSFER_ADVISORY" or "REFERENCE_ONLY")))
    out[#out+1] = row
end

function MaterialCatalog:GetAcquisitionOptions(itemID, name, explicitSource, storage)
    local resolver=JLP:GetModule("SourceResolver")
    local rod=resolver and resolver.GetOrdinaryRodAcquisition and resolver:GetOrdinaryRodAcquisition(itemID,1)
    if rod then return rod.options end -- exact producer join supersedes generic vendor labels
    local out, seen = {}, {}
    storage = type(storage)=="table" and storage or {}
    if storage.bagKnown==true and (tonumber(storage.bags) or 0) > 0 then addOption(out,seen,"bags","Bags",{currentAccessible=true,count=tonumber(storage.bags) or 0}) end
    if storage.bankKnown==true and (tonumber(storage.bank) or 0) > 0 then addOption(out,seen,"bank","Current bank",{currentAccessible=false,requiresRetrieve=true,count=tonumber(storage.bank) or 0}) end

    local inventory = JLP:GetModule("Inventory")
    for _, alt in ipairs(inventory and inventory.GetAltBankAvailability and inventory:GetAltBankAvailability(itemID,{sameRealm=true}) or {}) do
        if (tonumber(alt.count) or 0) > 0 then
            addOption(out,seen,"alt-bank",string.format("%s's bank x%d [%s]",tostring(alt.name or alt.characterKey),tonumber(alt.count) or 0,tostring(alt.freshness or "UNKNOWN")),{
                characterKey=alt.characterKey,characterName=alt.name,realm=alt.realm,count=alt.count,
                freshness=alt.freshness,updatedAt=alt.updatedAt,requiresTransfer=true,currentAccessible=false,
            })
        end
    end

    local row = self:Resolve(itemID,name)
    -- Join directly to the existing qualified create-item contract. The
    -- shared reagent index can be absent/partial and is not an output ledger.
    local alchemy
    local facts=JLP:GetModule("ProfessionPlanningFacts")
    local alchemyData=JLP.data and JLP.data.alchemy and JLP.data.alchemy.progression
    for id in pairs(alchemyData and alchemyData.recipes or {})do
        local candidate=facts and facts.GetAlchemyContract and facts:GetAlchemyContract(id)
        if candidate and candidate.output==itemID then alchemy=candidate;break end
    end
    if alchemy then
        addOption(out,seen,"craft","Craft via Alchemy (verify recipe/access)",{
            professionKey="ALCHEMY",recipeID=alchemy.id,sourceBuild=70532,
            requiredSkill=alchemy.minimum,outputEvidence=alchemy.outputStatus,
            cooldownMilliseconds=alchemy.cooldownMilliseconds,toolCategoryID=alchemy.toolCategoryID,
            currentAccessible=false,observedOutputCredit=0})
    end
    local smithData=JLP.data and JLP.data.blacksmithing and JLP.data.blacksmithing.progression
    for id in pairs(smithData and smithData.recipes or {})do
        local producer=facts and facts.GetBlacksmithingContract and facts:GetBlacksmithingContract(id)
        if producer and producer.output==itemID then
            addOption(out,seen,"craft","Craft via Blacksmithing (verify recipe, hammer and station)",{
                professionKey="BLACKSMITHING",recipeID=id,sourceBuild=70532,
                minimumStatus=producer.minimumStatus,learningMinimum=producer.learningMinimum,
                outputEvidence="CURRENT_FIXED_SCHEMATIC_REQUIRED",toolCategoryID=producer.toolCategoryID,
                focusID=producer.focusID,currentAccessible=false,observedOutputCredit=0})
            break
        end
    end
    local engineering=JLP.data and JLP.data.engineering and JLP.data.engineering.progression
    local recipeBoP=false
    for id in pairs(engineering and engineering.recipes or {})do
        local producer=facts and facts.GetEngineeringContract and facts:GetEngineeringContract(id)
        if producer and producer.output==itemID then
            addOption(out,seen,"craft","Craft via Engineering (verify learning, tools and station)",{
                professionKey="ENGINEERING",recipeID=id,sourceBuild=70532,requiredSkill=producer.minimum,
                outputEvidence="CURRENT_FIXED_SCHEMATIC_REQUIRED",toolRequirements=producer.toolRequirements,
                specializationRequired=producer.specializationRequired,currentAccessible=false,observedOutputCredit=0})
        end
        if producer and producer.recipeItemID==itemID and producer.patternBonding==1 then recipeBoP=true end
    end
    local leather=JLP.data and JLP.data.leatherworking and JLP.data.leatherworking.progression
    for id in pairs(leather and leather.recipes or {})do
        local producer=facts and facts.GetLeatherworkingContract and facts:GetLeatherworkingContract(id)
        if producer and producer.output==itemID then
            addOption(out,seen,"craft","Craft via Leatherworking (verify learned recipe, yield and access)",{
                professionKey="LEATHERWORKING",recipeID=id,sourceBuild=70532,requiredSkill=producer.minimum,
                outputEvidence="CURRENT_FIXED_SCHEMATIC_REQUIRED",focusID=producer.focusID,
                currentAccessible=false,observedOutputCredit=0})
        end
        if producer and producer.recipeItemID==itemID and producer.patternBonding==1 then recipeBoP=true end
    end
    local acquisition = row and row.acquisition or nil
    local kinds = acquisition and acquisition.acquisitionKinds or nil
    if type(kinds)=="table" then
        for _, kind in ipairs(kinds) do
            if kind=="vendor" then addOption(out,seen,"vendor","Vendor",{currentAccessible=false})
            elseif kind=="auction" then addOption(out,seen,"auction","Auction House",{currentAccessible=false})
            elseif kind=="farm" then
                local professionName = acquisition.gatheringProfession
                local reg=JLP:GetModule("ProfessionRegistry")
                local professionKey=reg and reg:NormalizeKey(professionName) or nil
                local api=JLP:GetModule("ProfessionAPI")
                local learned=professionKey and api and api:Get(professionKey) or nil
                addOption(out,seen,"gather",professionName and ("Gather with "..professionName) or "Farm in the world",{professionKey=professionKey,professionLearned=learned~=nil,eligible=learned~=nil,currentAccessible=false})
            elseif kind=="crafted" then
                local professionName=acquisition.productionProfession
                local reg=JLP:GetModule("ProfessionRegistry")
                local professionKey=reg and reg:NormalizeKey(professionName) or nil
                addOption(out,seen,"craft",professionName and ("Craft via "..professionName) or "Craft",{professionKey=professionKey,currentAccessible=false})
            elseif kind=="disenchant" then addOption(out,seen,"disenchant","Disenchant",{professionKey="ENCHANTING",currentAccessible=false})
            end
        end
    end

    local source=tostring(explicitSource or acquisition and acquisition.plannerSource or "")
    if source=="vendor" then addOption(out,seen,"vendor","Vendor",{currentAccessible=false})
    elseif source=="auction" then addOption(out,seen,"auction","Auction House",{currentAccessible=false})
    elseif source=="disenchant-or-auction" then
        addOption(out,seen,"disenchant","Disenchant",{professionKey="ENCHANTING",currentAccessible=false})
        addOption(out,seen,"auction","Auction House",{currentAccessible=false})
    elseif source=="crafted" or source=="craft" then
        addOption(out,seen,"craft","Craft",{currentAccessible=false})
    end
    -- A crafted intermediate may be bought directly as well as crafted.
    -- Explicit no-auction/non-tradeable evidence is the only exception.
    if (source=="crafted" or source=="craft" or source=="vendor") and
       not (acquisition and (acquisition.tradeable==false or acquisition.noAuction==true)) then
        addOption(out,seen,"auction","Auction House (direct)",{currentAccessible=false})
    end
    if recipeBoP then
        local permitted={}
        for _,option in ipairs(out)do
            if option.kind=="bags" or option.kind=="bank" or option.kind=="vendor" then permitted[#permitted+1]=option end
        end
        out=permitted
        if #out==0 then addOption(out,{},"vendor","Verify own-character BoP schematic source",{currentAccessible=false,bindOnPickup=true,transferAllowed=false})end
    end
    if #out==0 then addOption(out,seen,"external","External source",{currentAccessible=false}) end
    return out
end

function MaterialCatalog:FormatOptions(options)
    local parts={}
    for _, row in ipairs(options or {}) do parts[#parts+1]=tostring(row.label or row.kind) end
    return table.concat(parts,"  |  ")
end

-- Stable-ID taxonomy takes precedence over localized display strings.
-- Dataset names are canonical source metadata tied to item IDs, not UI locale.
function MaterialCatalog:GetCategory(itemID,meta)
    meta=type(meta)=="table" and meta or {}
    local class=tonumber(meta.classID)
    local sub=tonumber(meta.subclassID or meta.subClassID)
    if class==0 then return "food" end
    if class==9 then return "scrolls" end -- recipe/pattern class in supported clients
    if class==7 then
        local categories={[5]="cloth",[6]="leather",[7]="ores",[9]="herbs"}
        if sub and categories[sub] then return categories[sub] end
        return "crafting"
    end
    local row=self:Resolve(itemID)
    local source=row and normalize(row.name) or ""
    if source~="" then
        if source:find("cloth",1,true) or source:find("thread",1,true)
            or source:find("linen",1,true) or source:find("wool",1,true)
            or source:find("silk",1,true) or source:find("runecloth",1,true) then return "cloth" end
        if source:find("leather",1,true) or source:find("hide",1,true) then return "leather" end
        if source:find("ore",1,true) or source:find("bar",1,true) or source:find("stone",1,true) then return "ores" end
        if source:find("herb",1,true) or source:find("bloom",1,true) or source:find("leaf",1,true)
            or (row.acquisition and row.acquisition.gatheringProfession=="Herbalism") then return "herbs" end
        if source:find("potion",1,true) or source:find("elixir",1,true) then return "food" end
        if source:find("pattern",1,true) or source:find("formula",1,true) or source:find("recipe",1,true) then return "scrolls" end
    end
    if meta.isCraftingReagent then return "crafting" end
    return nil
end

function MaterialCatalog:GetSummary()
    local idx=index(self)
    local ids,names=0,0
    for _ in pairs(idx.byID) do ids=ids+1 end
    for _ in pairs(idx.byName) do names=names+1 end
    return string.format("Material Catalog: %d item IDs · %d normalized names · alt-bank advisory only",ids,names)
end

-- DQ01 research preview is an identity-only catalogue consumer. Raw
-- quantity fields must never populate missing/gross/owned totals or stock.
function MaterialCatalog:GetPrivateResearchReagentPreview(key,spellOrName,clientBuild)
    local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
    if not catalogue or type(catalogue.GetPrivateResearchAdvisory)~="function" then
        return nil,"PILOT_UNAVAILABLE"
    end
    local receipt,reason=catalogue:GetPrivateResearchAdvisory(key,spellOrName,clientBuild)
    if not receipt then return nil,reason end
    if receipt.state=="CONFLICT" then
        return {state="CONFLICT",rawItems={},actionable=false,
            materialTotals=nil,missing=nil,owned=nil,craftable=nil,
            nativeDispatchAllowed=false,planMutationAllowed=false},"CONFLICT_BLOCKED"
    end
    if receipt.reagentState=="UNKNOWN" then return nil,"RAW_REAGENT_SLOTS_UNKNOWN" end
    local entries={}
    for _,r in ipairs(receipt.rawReagentSlots or {}) do
        entries[#entries+1]={itemID=r.itemID,rawQuantity=r.rawQuantity,
            quantity=nil,quantitySemantics="UNKNOWN",stock="UNKNOWN",
            missing=nil,owned=nil,sourceQualification="NOT_APPROVED"}
    end
    return {state="PARTIAL",rawItems=entries,rawReagentCount=#entries,
        materialTotals=nil,missing=nil,owned=nil,craftable=nil,
        sourceQualified=false,actionable=false,nativeDispatchAllowed=false,
        planMutationAllowed=false,buildState=receipt.buildState,
        identityAnchor=receipt.identityAnchor},"RAW_REFERENCE_ONLY"
end
-- A selected-recipe, typed, read-only material receipt. Caller never
-- supplies quantities and the return value is never a purchase/stock plan.
function MaterialCatalog:GetCatalogueRecipeReagents(key,recipeID,clientBuild)
    local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
    if not catalogue or type(catalogue.GetRecipeFieldReceipt)~="function" then
        return nil,"CATALOGUE_UNAVAILABLE"
    end
    local record,why=catalogue:GetRecipeFieldReceipt(key,recipeID,clientBuild)
    if not record then return nil,why end
    local out={contract="JLP-CATALOGUE-REAGENT-PREVIEW-1",professionKey=key,
        recipeID=recipeID,fieldState=record.fields.reagents,
        staticRecipeComplete=record.staticRecipeComplete,
        items={},materialTotals=nil,required=nil,owned=nil,missing=nil,
        canPurchase=false,canWithdraw=false,canCraft=false,
        nativeDispatchAllowed=false,readOnly=true}
    for _,item in ipairs(record.reagents or {}) do
        out.items[#out.items+1]={itemID=item.itemID,
            -- Numbers from historical/partial sources may be displayed as
            -- references, but cannot become quantities in the plan or cart.
            referencePerCraft=item.quantity,
            usableForPlan=record.staticRecipeComplete==true,
            required=nil,missing=nil,owned=nil,sourceState=record.fields.reagents}
    end
    return out,nil
end
JLP:RegisterModule("MaterialCatalog", MaterialCatalog)
