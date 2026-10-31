local _, JLP = ...
-- M11: independent, read-only field admission. A source string, checksum,
-- historical JLP row, or client-spell match can never authorize execution.
local Q = {contract="JLP-CATALOGUE-FIELD-ADMISSION-3",targetBuild=70374,
    nativeDispatchAllowed=false,executionEligible=false,readOnly=true}
local required={"identity","reagents","output","requiredSkill"}
local actors={TRAINER="trainerID",VENDOR="vendorID",NPC="npcID",
    SCROLL="scrollItemID",DROP="dropNPCID"}
local actorNames={"trainerID","vendorID","npcID","scrollItemID","dropNPCID"}
local function uint(n) return type(n)=="number" and n==n and n<math.huge and n>0 and n==math.floor(n) end
local function str(v) return type(v)=="string" and v~="" and #v<=256 and not v:find("[%c]") end
local function sha(v) return type(v)=="string" and #v==64 and v:match("^[0-9a-fA-F]+$")~=nil end
local function utc(v) return type(v)=="string" and v:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$")~=nil end
local function dense(t,limit,allowEmpty)
    if type(t)~="table" then return nil end
    local n,hi=0,0
    for k in pairs(t) do
        if type(k)~="number" or k~=math.floor(k) or k<1 or k>limit then return nil end
        n=n+1;if k>hi then hi=k end
    end
    if n~=hi or (n==0 and not allowEmpty) then return nil end
    return n
end
local function snapshot(value,depth)
    if type(value)~="table" then return value end
    if (depth or 0)>6 then return nil end
    local copy={}
    for k,v in pairs(value) do copy[k]=snapshot(v,(depth or 0)+1) end
    return copy
end
local function keyFor(row) return row.professionKey..":"..tostring(row.spellID) end
local function verifiedField(field,row,rights,locale)
    local p=row.fieldProvenance and row.fieldProvenance[field]
    if type(p)~="table" or p.state~="SOURCE_QUALIFIED" or
       not str(p.sourceId) or not str(p.url) or not p.url:match("^https://") or
       p.sourceBuild~=row.sourceBuild or p.locale~=locale or not utc(p.observedAtUTC) or
       not sha(p.inputSHA256) or not str(p.rightsReviewId) or not str(p.reviewer) or
       (p.transformation~="DIRECT_VERBATIM" and p.transformation~="OWNER_REVIEWED_NORMALIZATION") then
        return false,"FIELD_PROVENANCE_INVALID_"..field
    end
    local ref=rights.sourceReferences and rights.sourceReferences[p.sourceId]
    if type(ref)~="table" or ref.url~=p.url or ref.sourceBuild~=row.sourceBuild or
       ref.locale~=locale or type(ref.inputSHA256)~="string" or
       ref.inputSHA256:lower()~=p.inputSHA256:lower() or ref.verified~=true then
        return false,"SOURCE_REFERENCE_NOT_VERIFIED_"..field
    end
    local review=rights.reviews and rights.reviews[p.rightsReviewId]
    local approval=type(review)=="table" and review.approvedRecords and
        review.approvedRecords[keyFor(row)]
    if type(review)~="table" or review.status~="APPROVED" or
        review.redistribution~=true or review.sourceId~=p.sourceId or
        review.sourceBuild~=row.sourceBuild or review.locale~=locale or
        type(review.inputSHA256)~="string" or
        review.inputSHA256:lower()~=p.inputSHA256:lower() or
        review.reviewer~=p.reviewer or not utc(review.reviewedAtUTC) or
        type(approval)~="table" or approval[field]~=true then
        return false,"FIELD_RIGHTS_OR_REVIEW_UNAPPROVED_"..field
    end
    return true
end
function Q:ValidateRecordsEnvelope(rows,schema,rights)
    if type(rows)~="table" or rows.contract~="jlp-professions-catalogue-records-v2" or
       rows.schemaVersion~=2 or rows.nativeDispatchAllowed~=false or
       rows.executionEligible~=false or not dense(rows.rows,5000,true) then
        return false,"RECORDS_ENVELOPE_INVALID"
    end
    if type(schema)~="table" or schema.contract~="jlp-professions-catalogue-schema-v2" or
       schema.version~=2 or schema.nativeDispatchAllowed~=false or schema.executionEligible~=false or
       type(schema.professions)~="table" then return false,"SCHEMA_INVALID" end
    if type(rights)~="table" or rights.contract~="jlp-catalogue-rights-v1" or
       type(rights.reviews)~="table" or type(rights.sourceReferences)~="table" then
        return false,"RIGHTS_REGISTRY_INVALID"
    end
    return true,nil
end
function Q:ValidateRecord(row,schema,rights)
    if type(row)~="table" or not str(row.professionKey) or
       not(schema and schema.professions and schema.professions[row.professionKey]) or
       not uint(row.spellID) or row.identityType~="SPELL" or
       (row.recipeID~=nil and row.recipeID~=row.spellID) or
       row.sourceBuild~=self.targetBuild or row.evidenceState~="SOURCE_QUALIFIED" or
       not str(row.name) or not str(row.locale) or
       not uint(row.skillRequired) then
        return nil,"IDENTITY_BUILD_OR_SKILL_UNQUALIFIED"
    end
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and reg:Get(row.professionKey)
    if not def or not uint(def.skillLineID) or
       (row.skillLineID~=nil and row.skillLineID~=def.skillLineID) then
        return nil,"PROFESSION_SKILL_LINE_CONFLICT"
    end
    local n=dense(row.reagents,32,true)
    if n==nil then return nil,"REAGENT_ARRAY_INVALID" end
    local seen={}
    local mats={}
    for i=1,n do
        local r=row.reagents[i]
        if type(r)~="table" or not uint(r.itemID) or not uint(r.quantity) or
           r.quantity>999999 or seen[r.itemID] then return nil,"REAGENT_ID_OR_QUANTITY_INVALID" end
        seen[r.itemID]=true
        mats[#mats+1]={itemID=r.itemID,quantity=r.quantity,name=r.name}
    end
    local o=row.output
    if type(o)~="table" then return nil,"OUTPUT_MISSING" end
    if o.kind=="ITEM" then
        if not uint(o.itemID) or not uint(o.quantityMin) or
           o.quantityMin~=o.quantityMax or o.quantityMin>999999 then
            return nil,"OUTPUT_ITEM_OR_YIELD_UNVERIFIED"
        end
    elseif o.kind=="ENCHANTMENT" then
        -- An enchant changes an existing target item; no invented output ItemID.
        if row.professionKey~="ENCHANTING" or not uint(o.enchantmentID) or
           o.itemID~=nil or o.quantityMin~=nil or o.quantityMax~=nil then
            return nil,"ENCHANTMENT_OUTPUT_INVALID"
        end
    else
        return nil,"OUTPUT_KIND_UNQUALIFIED"
    end
    if type(row.fieldProvenance)~="table" then return nil,"FIELD_PROVENANCE_MISSING" end
    for _,field in ipairs(required) do
        local ok,reason=verifiedField(field,row,rights,row.locale)
        if not ok then return nil,reason end
    end
    local acquisition,acquisitionReason=nil,"ACQUISITION_UNVERIFIED"
    local a=row.acquisition
    if a~=nil then
        if type(a)~="table" or (a.faction~="Horde" and a.faction~="Neutral") or
           a.hordeQualified~=true or a.sourceBuild~=row.sourceBuild or
           a.locale~=row.locale then
            acquisitionReason="ACQUISITION_FACTION_BUILD_OR_LOCALE_INVALID"
        else
            local field=actors[a.kind]
            if not field or not uint(a[field]) then
                acquisitionReason="ACQUISITION_ACTOR_UNKNOWN"
            else
                local conflict=false
                for _,name in ipairs(actorNames) do
                    if name~=field and a[name]~=nil then conflict=true end
                end
                if conflict then acquisitionReason="AMBIGUOUS_ACTOR_IDENTITY"
                else
                    local ok,reason=verifiedField("acquisition",row,rights,row.locale)
                    if not ok then acquisitionReason=reason
                    else
                        acquisition={kind=a.kind,faction=a.faction,hordeQualified=true,
                            sourceBuild=row.sourceBuild,locale=row.locale,
                            readOnly=true,nativeDispatchAllowed=false,
                            productionAuthority="NOT_AUTHORIZED"}
                        acquisition[field]=a[field]
                        acquisitionReason="QUALIFIED_TYPED_ACQUISITION"
                    end
                end
            end
        end
    end
    return {professionKey=row.professionKey,skillLineID=def.skillLineID,
        spellID=row.spellID,recipeID=row.spellID,identityType="SPELL",
        name=row.name,locale=row.locale,sourceBuild=row.sourceBuild,
        skillRequired=row.skillRequired,output=snapshot(o),reagents=mats,
        fieldProvenance=snapshot(row.fieldProvenance),acquisition=acquisition,
        acquisitionReason=acquisitionReason,verifiedAcquisition=acquisition~=nil,
        verifiedFieldSet=true,sourceQualified=true,nativeDispatchAllowed=false,
        executionEligible=false,productionAuthority=false,readOnly=true},nil
end
function Q:AssessInstalled()
    local data=JLP.data or {}
    local env=data.professionsCatalogueRecords
    local ok,reason=self:ValidateRecordsEnvelope(env,data.professionsCatalogueSchema,data.professionsCatalogueRights)
    local result={contract=self.contract,status=ok and "AUDITED" or "BLOCKED",
        reason=reason,sourceBuild=self.targetBuild,approved=0,rejected=0,
        declared=0,nativeDispatchAllowed=false,executionEligible=false,readOnly=true,
        rejectionReasons={}}
    if not ok then return result end
    result.declared=#env.rows
    local seen={}
    for _,row in ipairs(env.rows) do
        local key=type(row)=="table" and tostring(row.professionKey)..":"..tostring(row.spellID) or "INVALID"
        local valid,why=self:ValidateRecord(row,data.professionsCatalogueSchema,data.professionsCatalogueRights)
        if seen[key] then valid=nil;why="DUPLICATE_RECORD_IDENTITY" end
        seen[key]=true
        if valid then result.approved=result.approved+1 else
            result.rejected=result.rejected+1
            result.rejectionReasons[why]=(result.rejectionReasons[why] or 0)+1
        end
    end
    return result
end
JLP:RegisterModule("ProfessionsCatalogueQualification",Q)
