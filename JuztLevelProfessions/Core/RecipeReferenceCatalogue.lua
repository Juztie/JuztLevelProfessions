local _, JLP = ...
-- Source-specific, read-only catalogue. The index is rebuilt from already
-- shipped JLP evidence; it has no persistence and no authority to execute.
-- NEVER use this module as a recipe/skillup/trainer/price authorization gate.
local Catalogue={contract="jlp-recipe-reference-catalogue-v2",nativeDispatchAllowed=false,
    executionEligible=false,readOnly=true,pageLimit=12}
local skillLines={TAILORING=197,ENCHANTING=333,ALCHEMY=171,BLACKSMITHING=164,
    ENGINEERING=202,LEATHERWORKING=165,COOKING=185,FIRST_AID=129}
local function positive(n)
    return type(n)=="number" and n==n and n<math.huge and n>0 and n==math.floor(n)
end
local function copy(value,depth)
    if type(value)~="table" then return value end
    if (depth or 0)>9 then return nil end
    local result={}
    for k,v in pairs(value) do result[k]=copy(v,(depth or 0)+1) end
    return result
end
local function currentBuild()
    local client=JLP:GetModule("ClientBuildInfo")
    if type(client)=="table" and type(client.GetBuildNumber)=="function" then
        local ok,build=pcall(client.GetBuildNumber,client)
        if ok and positive(build) then return build end
    end
    return nil
end
local function metadata(key)
    local defs=JLP:GetModule("ProfessionRegistry")
    local def=defs and defs:Get(key)
    local expected=skillLines[key]
    if not expected or not def or tonumber(def.skillLineID)~=expected then return nil end
    return expected
end
local function materials(raw,form)
    if type(raw)~="table" or #raw<1 or #raw>32 then return nil,"REAGENTS_UNKNOWN" end
    local list,seen={},{}
    for _,r in ipairs(raw) do
        local id=form=="tuple" and r[1] or r.itemID
        local quantity=form=="tuple" and r[2] or r.quantity
        if not positive(id) or not positive(quantity) or seen[id] then return nil,"REAGENT_INVALID" end
        seen[id]=true
        list[#list+1]={itemID=id,quantity=quantity,name=type(r.name)=="string" and r.name or nil}
    end
    table.sort(list,function(a,b) return a.itemID<b.itemID end)
    return list
end
local function fingerprint(items)
    local parts={}
    for _,item in ipairs(items or {}) do parts[#parts+1]=item.itemID.."x"..item.quantity end
    return table.concat(parts,",")
end
local function newRecord(key,id,name,reagents,build,evidenceClass,source,notes)
    return {skillLineID=skillLines[key],professionKey=key,recipeID=id,
        spellID=id,identityType="SPELL", -- Existing JLP recipe IDs name crafting spells, not output items.
        name=name or ("Spell "..id),reagents=reagents,
        reagentFingerprint=fingerprint(reagents),reagentEvidence={class=evidenceClass,build=build,source=source},
        identityEvidence={class=evidenceClass,build=build,source=source},
        output={kind="UNKNOWN",quantityMin=nil,quantityMax=nil},
        outputEvidence={class="UNKNOWN",build=nil},
        fieldProvenance={},evidenceState="CANDIDATE",
        difficulty={basis="UNKNOWN",orange=nil,yellow=nil,green=nil,grey=nil,greenDerived=false},
        requirements={skill=nil,tools=nil,learned=nil},
        acquisition={hordeQualified=nil,trainer=nil,vendor=nil,scroll=nil,drop=nil},
        stock={bags="UNKNOWN",bank="UNKNOWN",stale=true},price={state="UNKNOWN"},
        conflicts={},sourceBuild=build,notes=notes,nativeDispatchAllowed=false,
        executionEligible=false,productionAuthority=false}
end
-- Field and acquisition qualification is delegated exclusively to
-- ProfessionsCatalogueQualification; legacy heuristics are not admission.
local function buildIndexUncached()
    -- Re-use the project's own curated source records rather than embedding or
    -- importing the 2,244 unqualified IDs from a third-party comparator.
    local byKey={}; local all={}; local counts={conflicts=0,ignored=0,sourceEntries=0,
        independentlyQualified70374=0,unresolvedRights=0}
    local function add(key,row,form,evidence,build,source,recipeName)
        local skill=metadata(key)
        if not skill or not positive(row.recipeID) then counts.ignored=counts.ignored+1;return end
        local mats,why=materials(form=="tuple" and row.materials or row.reagents or row.materials,form)
        if not mats then counts.ignored=counts.ignored+1;return end
        local byProfession=byKey[skill]
        if not byProfession then byProfession={};byKey[skill]=byProfession end
        local prior=byProfession[row.recipeID]
        counts.sourceEntries=counts.sourceEntries+1
        if prior then
            if prior.reagentFingerprint~=fingerprint(mats) then
                prior.conflicts[#prior.conflicts+1]={kind="REAGENT_MISMATCH",source=source,
                    build=build,otherFingerprint=fingerprint(mats)}
                counts.conflicts=counts.conflicts+1
            end
            return
        end
        local rec=newRecord(key,row.recipeID,recipeName or row.name or row.recipe or row.note,
            mats,build,evidence,source,row.notes)
        rec.requirements.skill=positive(row.requiredSkill) and row.requiredSkill or nil
        if rec.requirements.skill then rec.difficulty.basis="REQUIRED_SKILL_ONLY" end
        -- A source URL or historical build match alone is not a release license.
        -- Keep separate field-level evidence for identity, reagents, thresholds,
        -- output and acquisition; never infer missing items from a recipe label.
        rec.fieldProvenance={
            identity={source=source,sourceBuild=build,sourceClass=evidence,
                state="CANDIDATE",rightsReviewId="LEGACY_JLP_REFERENCE_PENDING"},
            reagents={source=source,sourceBuild=build,sourceClass=evidence,
                state="CANDIDATE",rightsReviewId="LEGACY_JLP_REFERENCE_PENDING"},
            output={state="UNKNOWN",reason="OUTPUT_ID_NOT_ATTESTED"},
            requiredSkill={state=rec.requirements.skill and "CANDIDATE" or "UNKNOWN",
                reason="HISTORICAL_SKILL_SOURCE_NOT_70374_QUALIFIED"},
            acquisition={state="UNKNOWN",reason="ACTOR_AND_HORDE_ACCESS_NOT_ATTESTED"},
            difficulty={state="UNKNOWN",reason="FOUR_THRESHOLDS_NOT_ATTESTED"},
        }
        if positive(row.outputPerCraft or row.outputQuantity) then
            rec.output.quantityMin=row.outputPerCraft or row.outputQuantity
            rec.output.quantityMax=rec.output.quantityMin
            rec.outputEvidence={class=evidence,build=build,source=source,
                basis="OUTPUT_PER_CRAFT_NOT_REFERENCE_MEAN"}
        end
        byProfession[row.recipeID]=rec;all[#all+1]=rec
    end
    local direct=JLP.data and JLP.data.currentBuildEvidence
    for key,group in pairs(direct and direct.professions or {}) do
        local build=tonumber(group.build) or tonumber(direct.targetBuild)
        for _,row in ipairs(group.rows or {}) do
            local sourceKey=row.sourceKey
            local source=direct.sources and direct.sources[sourceKey]
            add(key,row,"tuple","CURATED_FOREVER_DIRECT_REAGENTS",build,
                source and source.url or sourceKey,row.note)
        end
    end
    local public=JLP.data and JLP.data.publicCraftingRouteEvidence
    for key,group in pairs(public and public.professions or {}) do
        for _,row in ipairs(group.recipes or {}) do
            add(key,row,"object","CURATED_FOREVER_PUBLIC_REFERENCE",tonumber(row.sourceBuild),row.sourceURL,row.name)
        end
    end
    local secondary=JLP.data and JLP.data.foreverSecondaryRecipeEvidence
    for key,group in pairs(secondary and secondary.professions or {}) do
        for _,row in ipairs(group) do
            -- Secondary evidence provides URLs but does not pin its own
            -- client build: keep build UNKNOWN rather than assuming 70338.
            add(key,row,"object","CURATED_FOREVER_SECONDARY_REFERENCE",nil,row.evidenceURL,row.recipe)
        end
    end
    -- Separately curated yields enrich known IDs, but NEVER replace direct
    -- per-craft reagent facts or interpret an output as its own ingredient.
    local yieldData=JLP.data and JLP.data.foreverIntermediateOutputs
    for _,row in ipairs(yieldData and yieldData.rows or {}) do
        local id=skillLines[row.professionKey]
        local rec=id and byKey[id] and byKey[id][row.recipeID]
        if rec and positive(row.outputItemID) and positive(row.outputQuantity) then
            if rec.output.quantityMin and rec.output.quantityMin~=row.outputQuantity then
                rec.conflicts[#rec.conflicts+1]={kind="OUTPUT_PER_CRAFT_DISAGREEMENT",source=yieldData.source,
                    build=yieldData.build,observedQuantity=row.outputQuantity}
                counts.conflicts=counts.conflicts+1
            else
                rec.output={kind="ITEM",itemID=row.outputItemID,
                    quantityMin=row.outputQuantity,quantityMax=row.outputQuantity}
                rec.fieldProvenance.output={state="CANDIDATE",source=yieldData.source,
                    sourceBuild=yieldData.build,reason="INDEPENDENT_CURRENT_BUILD_CHECK_PENDING"}
                rec.outputEvidence={class="CURATED_FOREVER_INTERMEDIATE_OUTPUT",build=yieldData.build,
                    source=yieldData.source,basis="OUTPUT_PER_CRAFT_NOT_REFERENCE_MEAN"}
            end
        end
    end
    -- M11: admission belongs to the independent field/rights verifier.
    -- An unverified or malformed envelope is never a permission to import.
    local qualified=JLP.data and JLP.data.professionsCatalogueRecords
    local schema=JLP.data and JLP.data.professionsCatalogueSchema
    local rights=JLP.data and JLP.data.professionsCatalogueRights
    local verifier=JLP:GetModule("ProfessionsCatalogueQualification")
    local envelopeOK=verifier and verifier:ValidateRecordsEnvelope(qualified,schema,rights)
    if not envelopeOK then
        counts.envelopeBlocked=true
    else
        local seenDeclaration={}
        for _,r in ipairs(qualified.rows) do
            local proposed,why=verifier:ValidateRecord(r,schema,rights)
            local key=type(r)=="table" and r.professionKey or nil
            local skill=key and metadata(key)
            local id=type(r)=="table" and r.spellID or nil
            local identity=skill and positive(id) and (tostring(skill)..":"..tostring(id)) or nil
            local collision=identity and byKey[skill] and byKey[skill][id]
            if identity and seenDeclaration[identity] then
                proposed=nil;why="DUPLICATE_RECORD_IDENTITY"
            end
            if identity then seenDeclaration[identity]=true end
            if not proposed or collision then
                counts.ignored=counts.ignored+1
                counts.conflicts=counts.conflicts+1
                if collision then
                    collision.conflicts[#collision.conflicts+1]={kind="DUPLICATE_IDENTITY",
                        source="QUALIFIED_CATALOGUE",build=r and r.sourceBuild}
                    if collision.verifiedFieldSet then
                        collision.verifiedFieldSet=false
                        collision.verifiedAcquisition=false
                        counts.independentlyQualified70374=counts.independentlyQualified70374-1
                    end
                end
            else
                local rec=newRecord(key,id,proposed.name,proposed.reagents,
                    proposed.sourceBuild,"JLP_INDEPENDENTLY_QUALIFIED",
                    proposed.fieldProvenance.identity.url,r.notes)
                rec.fieldProvenance=proposed.fieldProvenance
                rec.requirements.skill=proposed.skillRequired
                rec.output=proposed.output
                rec.verifiedFieldSet=true
                rec.verifiedAcquisition=proposed.verifiedAcquisition
                rec.acquisition=proposed.acquisition
                rec.acquisitionQualificationReason=proposed.acquisitionReason
                rec.rightsReviewId=proposed.fieldProvenance.identity.rightsReviewId
                rec.locale=proposed.locale
                byKey[skill]=byKey[skill] or {}
                byKey[skill][id]=rec
                all[#all+1]=rec
                counts.independentlyQualified70374=counts.independentlyQualified70374+1
            end
        end
    end
    table.sort(all,function(a,b)
        if a.skillLineID~=b.skillLineID then return a.skillLineID<b.skillLineID end
        return a.recipeID<b.recipeID
    end)
    return {byKey=byKey,all=all,counts=counts}
end
local cachedIndex
local function buildIndex()
    -- The TOC intentionally loads historical public evidence after the facade.
    -- A very early bootstrap consumer must not cache an incomplete snapshot.
    local data=JLP.data or {}
    local ready=data.currentBuildEvidence and data.publicCraftingRouteEvidence and
        data.foreverSecondaryRecipeEvidence and data.foreverIntermediateOutputs and
        data.professionsCatalogueSchema and data.professionsCatalogueRights and
        data.professionsCatalogueRecords
    if not ready then return buildIndexUncached() end
    if not cachedIndex then cachedIndex=buildIndexUncached() end
    return cachedIndex
end
-- A build identifier is source provenance, not an admission or execution gate.
-- The independent field/rights verifier above decides whether a record has
-- a reviewed identity, reagent set, output and required-skill field bundle.
-- Cross-build reuse is permitted unless a concrete field conflict exists.
local conflictKinds={REAGENT_MISMATCH="reagents",
    OUTPUT_PER_CRAFT_DISAGREEMENT="output",DUPLICATE_IDENTITY="identity"}
local function sourceState(row,build)
    if #row.conflicts>0 then return "CONFLICT","SOURCE_FIELD_CONFLICT" end
    if #row.reagents==0 and not row.verifiedFieldSet then
        return "UNKNOWN","REAGENTS_UNKNOWN"
    end
    if row.verifiedFieldSet then
        -- Preserve exact sourceBuild and requestedBuild separately. Neither
        -- an unknown live build nor a mismatch disproves a reviewed field.
        if not positive(row.sourceBuild) then
            return "CANDIDATE","QUALIFIED_SOURCE_PROVENANCE_INCOMPLETE"
        end
        return "SOURCE_QUALIFIED","REVIEWED_FIELDS_NO_DOCUMENTED_CONFLICT"
    end
    -- Historical, incompletely reviewed records remain reference candidates
    -- regardless of whether their source build happens to equal this client.
    -- Matching a build must never qualify missing rights/output/skill evidence.
    if not positive(row.sourceBuild) then
        return "CANDIDATE","SOURCE_BUILD_UNKNOWN_AND_FIELDS_UNREVIEWED"
    end
    return "CANDIDATE","LEGACY_JLP_FIELDS_UNREVIEWED"
end
local function present(row,build)
    if not row then return nil end
    local rec=copy(row)
    rec.state,rec.qualificationReason=sourceState(row,build)
    rec.evidenceState=rec.state
    local conflicted={}
    for _,conflict in ipairs(row.conflicts) do
        local field=conflictKinds[conflict.kind]
        if field then conflicted[field]=true
        else
            -- Unknown collision kinds are not assumed harmless.
            conflicted.identity=true;conflicted.reagents=true
            conflicted.output=true;conflicted.requiredSkill=true
        end
    end
    rec.qualifiedFields={}
    for _,field in ipairs({"identity","reagents","output","requiredSkill"}) do
        local p=rec.fieldProvenance[field]
        if conflicted[field] then
            rec.fieldProvenance[field]=p or {}
            rec.fieldProvenance[field].state="CONFLICT"
            rec.fieldProvenance[field].reason="DOCUMENTED_FIELD_CONFLICT"
        end
        rec.qualifiedFields[field]=rec.verifiedFieldSet==true and
            type(p)=="table" and p.state=="SOURCE_QUALIFIED" and
            not conflicted[field] or false
    end
    local acquisition=rec.fieldProvenance.acquisition
    rec.qualifiedFields.acquisition=rec.verifiedFieldSet==true and
        rec.verifiedAcquisition==true and
        type(acquisition)=="table" and acquisition.state=="SOURCE_QUALIFIED" or false
    if conflicted.identity then rec.qualifiedFields.acquisition=false end
    rec.requestedBuild=build
    rec.nativeDispatchAllowed=false
    rec.executionEligible=false
    rec.productionAuthority=false
    return rec
end
function Catalogue:GetCandidate(skillLineID,recipeID,requestedBuild)
    if not positive(skillLineID) or not positive(recipeID) then return nil,"INVALID_KEY" end
    local index=buildIndex()
    local row=index.byKey[skillLineID] and index.byKey[skillLineID][recipeID]
    if not row then return nil,"SOURCE_UNAVAILABLE" end
    -- An explicit UNKNOWN supplied by the unified facade may not fall back
    -- to an unrelated target/requalification build.
    return present(row,requestedBuild==nil and currentBuild() or requestedBuild),nil
end
function Catalogue:List(skillLineID,query,offset,pageSize,requestedBuild)
    if skillLineID~=nil and not positive(skillLineID) then return nil,"INVALID_SKILL_LINE" end
    if type(query)~="string" or #query>96 then return nil,"INVALID_QUERY" end
    offset=tonumber(offset) or 0
    pageSize=tonumber(pageSize) or 8
    if offset<0 or offset~=math.floor(offset) or pageSize<1 or
        pageSize~=math.floor(pageSize) or pageSize>self.pageLimit then return nil,"INVALID_PAGE" end
    local normalized=query:lower();local index=buildIndex();local total=0;local rows={}
    for _,row in ipairs(index.all) do
        if (skillLineID==nil or row.skillLineID==skillLineID) and
            (normalized=="" or row.name:lower():find(normalized,1,true) or tostring(row.recipeID):find(normalized,1,true)) then
            total=total+1
            if total>offset and #rows<pageSize then rows[#rows+1]=present(row,requestedBuild==nil and currentBuild() or requestedBuild) end
        end
    end
    return {rows=rows,total=total,offset=offset,pageSize=pageSize,sourceEntries=index.counts.sourceEntries,
        conflicts=index.counts.conflicts,ignored=index.counts.ignored,
        independentlyQualified70374=index.counts.independentlyQualified70374,
        clientBuild=requestedBuild==nil and currentBuild() or requestedBuild,scope="JLP_CURATED_STATIC_IDS_ONLY",
        nativeDispatchAllowed=false},nil
end
function Catalogue:FindAlternatives(skillLineID,query,requestedBuild)
    local result,reason=self:List(skillLineID,query or "",0,self.pageLimit,requestedBuild)
    if not result then return nil,reason end
    return result.rows,nil
end
function Catalogue:GetCoverage()
    local index=buildIndex()
    local bySkill,qualifiedBySkill,acquisitionBySkill={},{},{}
    for _,row in ipairs(index.all) do
        bySkill[row.skillLineID]=(bySkill[row.skillLineID] or 0)+1
        if row.verifiedFieldSet and row.sourceBuild==70374 then
            qualifiedBySkill[row.skillLineID]=(qualifiedBySkill[row.skillLineID] or 0)+1
            if row.verifiedAcquisition then
                acquisitionBySkill[row.skillLineID]=(acquisitionBySkill[row.skillLineID] or 0)+1
            end
        end
    end
    return {distinct=#index.all,bySkill=bySkill,
        independentlyQualified70374=index.counts.independentlyQualified70374,
        qualifiedBySkill=qualifiedBySkill,acquisitionBySkill=acquisitionBySkill,
        historicalStaticIDs=#index.all-index.counts.independentlyQualified70374,
        productionAuthorized=0,sourceEntries=index.counts.sourceEntries,
        conflicts=index.counts.conflicts,ignored=index.counts.ignored,
        scope="EXPLICIT_STATIC_JLP_RECIPES_NOT_LIVE_LEARNED",nativeDispatchAllowed=false}
end
JLP:RegisterModule("RecipeReferenceCatalogue",Catalogue)
