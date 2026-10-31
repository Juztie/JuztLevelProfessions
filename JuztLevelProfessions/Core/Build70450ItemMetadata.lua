local _, JLP = ...
-- M9 build 70450: strictly read-only item metadata and reverse spell-item relations.
-- ItemEffects are spell associations, NOT demonstrated acquisition sources or learn-on-use.
local Service={contract="JLP-BUILD70450-ITEM-METADATA-READONLY-1",sourceBuild=70450,
    readOnly=true,nativeDispatchAllowed=false,productionAuthority=false,executionEligible=false}
local BUILD=70450
local EXPECT={
    Item="961f90227f41e952ccdb0f524d84756956d922110a7185892fc033caaa25e9ea",
    ItemSparse="98333a70d1a3f01489a3525cb8e8cdde14be5d1cab84c69bb43ef1ee6d87da8e",
    SkillLineAbility="df6018b459f851bdee27edfc74d2f45678177cba50aeed4bf12bc9d5fa4973e4",
    SpellName="88f0e96ad902ab1a15da366018edfc73ecf0b0ad3e02402c064527bdf9d1a912",
    ItemSearchName="358efe97e7bed4f857a9afc021bb494561b047c480de7a45dfae48ae22b60b65",
    ItemNameDescription="bc8c0524a8681283881ee34632f1797de2a8a4166c7b5a89d71c328b2619d479",
    ItemEffect="5282eec869e032a554a4e6e5f19fd21feaf4db4c0a077fa86309f5d858ce7583",
    ItemXItemEffect="d9c2721f9a59e9ac2ad71b62a1856e23bfd0f75e466cf06a5a731f7e6f4d3a8b"
}
local ROLE_NAMES={[1]="REAGENT",[2]="CRAFT_OUTPUT",[4]="SPELL_LINKED_ITEM",[8]="OPPOSITE_FACTION_REFERENCE",[16]="MODIFIED_REAGENT_REFERENCE"}
local PROF_KEYS={"TAILORING","ENCHANTING","ALCHEMY","BLACKSMITHING","ENGINEERING","LEATHERWORKING","HERBALISM","MINING","SKINNING","COOKING","FIRST_AID","FISHING"}
local function integer(n)
    return type(n)=="number" and n==math.floor(n) and n>0 and n<2147483647
end
local function source()
    local d=JLP.data and JLP.data.build70450ItemMetadata
    local recipes=JLP.data and JLP.data.build70450Recipes
    local output=JLP.data and JLP.data.build70450CraftOutputs
    if type(d)~="table" or d.contract~="JLP-BUILD70450-ITEM-METADATA-OWNER-1" or
        d.sourceBuild~=BUILD or type(d.packedByBucket)~="table" or
        type(d.relationsByBucket)~="table" or type(d.schemaFields)~="table" or
        type(d.sourceSHA256)~="table" or type(d.counts)~="table" or
        not recipes or recipes.sourceBuild~=BUILD or not output or output.sourceBuild~=BUILD then
        return nil,"M9_SOURCE_UNAVAILABLE"
    end
    for name,sha in pairs(EXPECT) do
        if d.sourceSHA256[name]~=sha or (recipes.inputSHA256 and recipes.inputSHA256[name] and recipes.inputSHA256[name]~=sha) or
            (output.inputSHA256 and output.inputSHA256[name] and output.inputSHA256[name]~=sha) then
            return nil,"M9_SOURCE_HASH_CONFLICT_"..name
        end
    end
    return d,nil
end
local function split(str,delimiter)
    local out={};local start=1
    while true do
        local p=str:find(delimiter,start,true)
        if not p then out[#out+1]=str:sub(start);break end
        out[#out+1]=str:sub(start,p-1);start=p+#delimiter
    end
    return out
end
local function rawLine(packed,id)
    if type(packed)~="string" then return nil end
    local needle=tostring(id).."^";local at=1
    while true do
        local p=packed:find(needle,at,true)
        if not p then return nil end
        if p==1 or packed:sub(p-1,p-1)=="\n" then
            local finish=packed:find("\n",p,true)
            return packed:sub(p,finish and finish-1 or #packed)
        end
        at=p+#needle
    end
end
local function observed()
    local m=JLP:GetModule("ClientBuildInfo")
    if not m or type(m.GetBuildNumber)~="function" then return nil end
    local ok,n=pcall(m.GetBuildNumber,m)
    -- Item IDs have a narrower numeric domain than client build identifiers.
    return ok and type(n)=="number" and n==n and n>0 and
        n==math.floor(n) and n<=9007199254740991 and n or nil
end
-- A live item observation must be bound to the actual build+interface
-- receipt, not merely a matching build number. Static 70450 metadata does not
-- depend on this helper and remains readable on other builds.
local function observedIdentity()
    local module=JLP:GetModule("ClientBuildInfo")
    if not module or type(module.Read)~="function" then return nil end
    local ok,info=pcall(module.Read,module)
    if not ok or type(info)~="table" or info.known~=true then return nil end
    local build,interface=info.buildNumber,info.interfaceVersion
    if type(build)~="number" or build~=build or build<=0 or
       build~=math.floor(build) or build>9007199254740991 then return nil end
    -- A missing/malformed interface can describe a readable client build,
    -- but is not a complete receipt for a LIVE item observation.
    if type(interface)~="number" or interface~=interface or
       interface<=0 or interface~=math.floor(interface) or interface>9007199254740991 then
        return nil
    end
    local token=string.format("forever:%s|interface:%s",tostring(build),tostring(interface or "unknown"))
    if info.token~=token then return nil end
    return {build=build,interface=interface,token=token}
end
local function identityStable(previous)
    local current=observedIdentity()
    return previous and current and current.token==previous.token
end
local function numberOrNil(raw)
    if raw=="?" or raw=="" then return nil end
    return tonumber(raw)
end
local function getRecord(id,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    if not integer(id) then return nil,"INVALID_ITEM_ID" end
    local d,err=source();if not d then return nil,err end
    local packed=d.packedByBucket[math.floor(id/1000)]
    local line=rawLine(packed,id)
    if not line then return nil,"ITEM_NOT_IN_PROFESSION_REFERENCE_SET" end
    local f=split(line,"^")
    if #f~=#d.schemaFields+6 or tonumber(f[1])~=id then
        return nil,"CORRUPT_ITEM_METADATA_RECORD"
    end
    local present=f[2]; local mask=tonumber(f[3]);local name=f[4]
    if not mask or mask~=math.floor(mask) or mask<1 or mask>31 or
        not present:match("^[I%-][S%-][Q%-]$") then
        return nil,"CORRUPT_ITEM_FLAGS"
    end
    local roles={}
    for bit,label in pairs(ROLE_NAMES) do if math.floor(mask/bit)%2==1 then roles[#roles+1]=label end end
    table.sort(roles)
    local rawFields={};local fields={};local evidence={}
    for i,key in ipairs(d.schemaFields) do
        local raw=f[i+4]
        rawFields[key]=raw~="?" and raw or nil
        fields[key]=numberOrNil(raw)
        evidence[key]=i<=5 and "ITEM_70450" or
            ((key=="OverallQualityID" or key=="RequiredLevel") and present:sub(3,3)=="Q") and "ITEMSEARCHNAME_70450" or
            "ITEMSPARSE_70450"
        if fields[key]==nil then evidence[key]="UNKNOWN_IN_SOURCE" end
    end
    local desc=f[#f-1];local rawDesc=f[#f]
    local suffixes=d.rawDescriptionSuffixByItemID
    local sourceSuffix=type(suffixes)=="table" and suffixes[id] or nil
    if sourceSuffix~=nil then
        if sourceSuffix~=" " and sourceSuffix~="\r\n" then
            return nil,"CORRUPT_DESCRIPTION_SUFFIX"
        end
        rawDesc=rawDesc..sourceSuffix
    end
    local actual=observed()
    return {
        contract=Service.contract,sourceBuild=BUILD,itemID=id,
        name=name~="" and name or nil,
        nameEvidence=name~="" and (present:sub(2,2)=="S" and "ITEMSPARSE_EXACT" or
            "ITEMSEARCHNAME_FALLBACK") or "UNKNOWN_NOT_IN_SOURCES",
        description=rawDesc~="" and rawDesc or nil,
        descriptionWhitespaceStatus=sourceSuffix and "EXACT_CSV_TRAILING_WHITESPACE_RESTORED" or "NO_RESTORE_NEEDED",
        itemNameDescription=desc~="" and desc or nil,
        presentInItem=present:sub(1,1)=="I",presentInItemSparse=present:sub(2,2)=="S",
        presentInItemSearchName=present:sub(3,3)=="Q",
        roles=roles,fields=fields,rawFields=rawFields,fieldEvidence=evidence,
        acquisition={trainer="UNKNOWN",vendor="UNKNOWN",drop="UNKNOWN",quest="UNKNOWN",
            itemLearningEffect="NOT_PROVEN",sourceNPCID=nil,verified=false,
            status="UNVERIFIED_NO_SOURCE_MAPPING_IN_EXPORT"},
        itemEffectSpellAssociationIsProofOfAcquisition=false,
        vendorBuyPriceIsProofOfVendorStock=false,
        currentClientBuild=actual,clientBuildRelation=actual==BUILD and "MATCH" or
            (actual and "MISMATCH" or "UNKNOWN"),
        readOnly=true,executionEligible=false,productionAuthority=false,nativeDispatchAllowed=false,
    },nil
end
function Service:GetItem(itemID,build)
    return getRecord(itemID,build)
end
-- Never synthesize |Hitem links from static metadata: enchant/suffix/bonuses,
-- localized text and link quality require an actual client-provided hyperlink.
-- This observation is transient, build-bound and cannot promote source authority.
local function validClientLink(link,expectedID)
    if type(link)~="string" or #link>2048 then return false,"CLIENT_ITEM_LINK_INVALID" end
    local pre,id,payload,label,suffix=link:match("^(.-)|Hitem:(%d+)([^|]*)|h%[([^|]+)%]|h(.-)$")
    if not id or not label or label=="" or
        (pre~="" and not pre:match("^|c%x%x%x%x%x%x%x%x$") and not pre:match("^|cnIQ%d+$")) or
        (suffix~="" and suffix~="|r") or
        not payload:match("^[%d:%-]*$") then
        return false,"CLIENT_ITEM_LINK_INVALID"
    end
    if tonumber(id)~=expectedID then return false,"CLIENT_ITEM_LINK_ID_MISMATCH" end
    return true,nil
end
function Service:GetClientItemLink(itemID,build)
    local item,err=getRecord(itemID,build)
    if not item then return nil,err end
    local clientBuild=item.currentClientBuild
    if not clientBuild then return nil,"CLIENT_BUILD_UNKNOWN" end
    local session=observedIdentity()
    if not session or session.build~=clientBuild then return nil,"LIVE_CLIENT_IDENTITY_UNVERIFIED" end
    local providers={}
    if type(C_Item)=="table" and type(C_Item.GetItemInfo)=="function" then
        providers[#providers+1]={fn=C_Item.GetItemInfo,label="C_Item.GetItemInfo"}
    end
    if type(GetItemInfo)=="function" then
        providers[#providers+1]={fn=GetItemInfo,label="GetItemInfo"}
    end
    if #providers==0 then return nil,"CLIENT_ITEM_INFO_API_UNAVAILABLE" end
    for _,provider in ipairs(providers) do
        local ok,name,link,quality=pcall(provider.fn,itemID)
        if ok and type(name)=="string" and name~="" and not name:find("|",1,true) then
            local valid,why=validClientLink(link,itemID)
            if not valid then return nil,why end
            if not identityStable(session) then return nil,"CLIENT_IDENTITY_CHANGED_DURING_OBSERVATION" end
            return {
                contract="JLP-ITEM-LINK-LIVE-70450-1",sourceBuild=BUILD,
                observedClientBuild=clientBuild,clientBuildToken=session.token,
                observedClientInterface=session.interface,
                clientBuildRelation=clientBuild==BUILD and "MATCH" or "MISMATCH",
                itemID=itemID,itemLink=link,
                clientName=name,sourceName=item.name,
                sourceNameEvidence=item.nameEvidence,
                clientNameEvidence="CURRENT_CLIENT_ITEMINFO_WITH_MATCHING_LINK",
                clientLinkEvidence=provider.label.."_VERIFIED_ITEM_ID",
                quality=type(quality)=="number" and quality or nil,
                temporaryClientObservation=true,persistedToSource=false,
                readOnly=true,productionAuthority=false,executionEligible=false,
                nativeDispatchAllowed=false
            },nil
        end
    end
    return nil,"CLIENT_ITEM_INFO_NOT_CACHED_OR_UNAVAILABLE"
end
-- Explicit cache request is advisory, does not supply a name or item hyperlink.
function Service:RequestClientItemData(itemID,build)
    local item,err=getRecord(itemID,build)
    if not item then return nil,err end
    local clientBuild=item.currentClientBuild
    if not clientBuild then return nil,"CLIENT_BUILD_UNKNOWN" end
    local session=observedIdentity()
    if not session or session.build~=clientBuild then return nil,"LIVE_CLIENT_IDENTITY_UNVERIFIED" end
    if type(C_Item)~="table" or type(C_Item.RequestLoadItemDataByID)~="function" then
        return nil,"CLIENT_ITEM_DATA_REQUEST_UNSUPPORTED"
    end
    local ok,result=pcall(C_Item.RequestLoadItemDataByID,itemID)
    if not ok or result==false then return nil,"CLIENT_ITEM_DATA_REQUEST_FAILED" end
    if not identityStable(session) then return nil,"CLIENT_IDENTITY_CHANGED_DURING_OBSERVATION" end
    return {itemID=itemID,sourceBuild=BUILD,observedClientBuild=clientBuild,
        clientBuildRelation=clientBuild==BUILD and "MATCH" or "MISMATCH",
        clientBuildToken=session.token,observedClientInterface=session.interface,
        status="REQUESTED_NOT_YET_VERIFIED",
        requestIsEvidenceOfItemExistence=false,name=item.name,
        readOnly=true,productionAuthority=false},nil
end
function Service:GetRelations(itemID,offset,limit,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local item,err=getRecord(itemID,build);if not item then return nil,err end
    offset=offset or 0;limit=limit or 20
    if type(offset)~="number" or offset<0 or offset~=math.floor(offset) or offset>100000 or
        type(limit)~="number" or limit<1 or limit>50 or limit~=math.floor(limit) then
        return nil,"INVALID_RELATION_PAGE"
    end
    local d=JLP.data.build70450ItemMetadata
    local s=rawLine(d.relationsByBucket[math.floor(itemID/1000)],itemID)
    if not s then return nil,"MISSING_ITEM_RELATION_SOURCE" end
    local raw=s:match("^%d+%^(.*)$")
    if not raw then return nil,"CORRUPT_ITEM_RELATIONS" end
    local rows={};local count=0;local roleBits=0
    if raw~="" then
        for token in raw:gmatch("[^,]+") do
            local role,idx,spell,fx,trigger=token:match("^(%d+):(%d+):(%d+):(%d+):(%d+)$")
            role,idx,spell,fx,trigger=tonumber(role),tonumber(idx),tonumber(spell),tonumber(fx),tonumber(trigger)
            if not ROLE_NAMES[role] or type(idx)~="number" or idx<0 or idx>#PROF_KEYS or
                not integer(spell) or type(fx)~="number" or fx<0 or type(trigger)~="number" or
                (role<=4 and idx==0) or (role>=8 and idx~=0) or (role==4 and fx==0) then
                return nil,"CORRUPT_ITEM_RELATION"
            end
            if math.floor(roleBits/role)%2==0 then roleBits=roleBits+role end
            if count>=offset and #rows<limit then
                local isItemRef=(role==8 or role==16)
                rows[#rows+1]={relation=ROLE_NAMES[role],professionKey=not isItemRef and PROF_KEYS[idx] or nil,
                    spellID=not isItemRef and spell or nil,relatedItemID=isItemRef and spell or nil,
                    itemEffectID=fx>0 and fx or nil,rawTriggerType=fx>0 and trigger or nil,
                    acquisitionVerified=false,relationEvidence=isItemRef and "ITEM_REFERENCE_FIELD" or
                        (role==4 and "ITEMXITEMEFFECT_JOIN" or (role==1 and "SPELLREAGENTS" or "SPELLEFFECT"))}
            end
            count=count+1
        end
    end
    -- Keep the packed relationship rows consistent with the role bitfield.
    -- A modified source must never silently manufacture new item relationships.
    local roleMask=0
    for _,label in ipairs(item.roles) do
        for bit,name in pairs(ROLE_NAMES) do
            if name==label then roleMask=roleMask+bit end
        end
    end
    if roleMask~=roleBits then return nil,"ITEM_ROLE_RELATION_MISMATCH" end
    return {contract="JLP-ITEM-RELATION-PAGE-70450-1",itemID=itemID,sourceBuild=BUILD,
        offset=offset,pageSize=limit,totalRelations=count,rows=rows,
        recipeAcquisitionVerified=false,readOnly=true,nativeDispatchAllowed=false},nil
end
function Service:GetPage(offset,limit,build,options)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    offset=offset or 0;limit=limit or 20
    if type(offset)~="number" or offset<0 or offset~=math.floor(offset) or offset>100000 or
        type(limit)~="number" or limit<1 or limit>50 or limit~=math.floor(limit) then
        return nil,"INVALID_PAGE_BOUNDS"
    end
    local d,err=source();if not d then return nil,err end
    options=type(options)=="table" and options or {}
    local ids={};local total=0
    for _,packed in pairs(d.packedByBucket) do
        for line in packed:gmatch("[^\n]+") do
            local id,presence,mask,name=line:match("^(%d+)%^([^%^]+)%^(%d+)%^([^%^]*)%^")
            id=tonumber(id);mask=tonumber(mask)
            if not id or not mask then return nil,"INVALID_ITEM_RECORD" end
            local include=(not options.missingNamesOnly or name=="") and
                (not options.missingSparseOnly or presence:sub(2,2)~="S") and
                (not options.missingItemOnly or presence:sub(1,1)~="I") and
                (not options.roleBit or (ROLE_NAMES[options.roleBit] and math.floor(mask/options.roleBit)%2==1))
            if include then ids[#ids+1]=id end
        end
    end
    table.sort(ids)
    total=#ids
    local rows={}
    for i=offset+1,math.min(total,offset+limit) do
        local item,e=getRecord(ids[i],BUILD)
        if not item then return nil,e end
        rows[#rows+1]=item
    end
    return {contract="JLP-ITEM-METADATA-PAGE-70450-1",sourceBuild=BUILD,
        offset=offset,pageSize=limit,totalMatches=total,rows=rows,readOnly=true},nil
end
-- Evidence summary for one item: never assigns acquisition, vendor stock,
-- server-side item existence or native permissions from raw DB2 references.
function Service:InspectItem(itemID,build)
    local item,err=getRecord(itemID,build)
    if not item then return nil,err end
    local relations,relationErr=self:GetRelations(itemID,0,1,build)
    if not relations then return nil,relationErr end
    local unknownFields={}
    for _,field in ipairs(JLP.data.build70450ItemMetadata.schemaFields) do
        if item.fieldEvidence[field]=="UNKNOWN_IN_SOURCE" then
            unknownFields[#unknownFields+1]=field
        end
    end
    return {
        contract="JLP-ITEM-EVIDENCE-AUDIT-70450-1",sourceBuild=BUILD,
        itemID=itemID,name=item.name,nameStatus=item.name and "SOURCE_IDENTIFIED" or "UNKNOWN_IN_CSV",
        itemRowStatus=item.presentInItem and "SOURCE_PRESENT" or "UNKNOWN_NO_ITEM_ROW",
        sparseStatus=item.presentInItemSparse and "SOURCE_PRESENT" or "UNKNOWN_NO_SPARSE_ROW",
        searchNameStatus=item.presentInItemSearchName and "SOURCE_PRESENT" or "UNKNOWN_NO_SEARCHNAME_ROW",
        fieldCount=#JLP.data.build70450ItemMetadata.schemaFields,
        missingFieldCount=#unknownFields,missingFields=unknownFields,
        totalRelations=relations.totalRelations,relationStatus="ROLE_MASK_MATCHES_PACKED_RELATIONS",
        relationRoleNames=item.roles,clientBuildRelation=item.clientBuildRelation,
        clientItemLinkStatus="NOT_OBSERVED_USE_ITEMPROBE70450",
        acquisitionStatus="UNKNOWN_NOT_SERVER_VERIFIED",
        -- Names and relationships in CSV cannot prove availability or production rights.
        readOnly=true,productionAuthority=false,executionEligible=false,
        nativeDispatchAllowed=false
    },nil
end
-- Bounded manual scan for missing names; clients may not have items cached.
-- Observations returned only to the caller, never merged into static source.
function Service:ScanMissingNames(offset,build)
    if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    local session=observedIdentity()
    local clientBuild=session and session.build
    if not clientBuild then return nil,"LIVE_CLIENT_IDENTITY_UNVERIFIED" end
    local page,err=self:GetPage(offset or 0,12,BUILD,{missingNamesOnly=true})
    if not page then return nil,err end
    local result={sourceBuild=BUILD,observedClientBuild=clientBuild,
        clientBuildToken=session.token,observedClientInterface=session.interface,
        clientBuildRelation=clientBuild==BUILD and "MATCH" or "MISMATCH",
        offset=page.offset,totalMatches=page.totalMatches,
        rows={},readOnly=true,productionAuthority=false,persistedToSource=false}
    for _,entry in ipairs(page.rows) do
        local link,why=self:GetClientItemLink(entry.itemID,BUILD)
        local row={itemID=entry.itemID,sourceName=entry.name,liveName=link and link.clientName or nil,
            itemLink=link and link.itemLink or nil,status=link and "CURRENT_CLIENT_ID_MATCH" or why,
            productionAuthority=false}
        if not link and why=="CLIENT_ITEM_INFO_NOT_CACHED_OR_UNAVAILABLE" then
            local request,requestError=self:RequestClientItemData(entry.itemID,BUILD)
            row.requestStatus=request and request.status or requestError
        end
        result.rows[#result.rows+1]=row
        if not identityStable(session) then return nil,"CLIENT_IDENTITY_CHANGED_DURING_OBSERVATION" end
    end
    -- Also guard empty pages: no loop iteration must not bypass the receipt
    -- stability requirement when the client identity changes during paging.
    if not identityStable(session) then return nil,"CLIENT_IDENTITY_CHANGED_DURING_OBSERVATION" end
    return result,nil
end
function Service:GetCoverage()
    local d,err=source();if not d then return nil,err end
    local actual=observed()
    local copy={};for key,v in pairs(d.counts) do copy[key]=v end
    return {contract=Service.contract,sourceBuild=BUILD,counts=copy,sourceSHA256=d.sourceSHA256,
        observedClientBuild=actual,clientBuildRelation=actual==BUILD and "MATCH" or
            (actual and "MISMATCH" or "UNKNOWN"),
        allAcquisitionSourcesVerified=false,allNamesVerified=false,
        unknownNamesRemainUnknown=true,itemHyperlinksRequireCurrentClientIdentity=true,
        accessResearchOnly=true,readOnly=true,productionAuthority=false,nativeDispatchAllowed=false},nil
end
JLP:RegisterModule("Build70450ItemMetadata",Service)
