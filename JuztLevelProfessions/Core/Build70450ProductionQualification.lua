local _, JLP = ...
-- 70450 catalogue source/rights admission. A SOURCE_QUALIFIED receipt is
-- about independently reviewed DATA; it NEVER enables native crafting, buying,
-- routing, protected API calls, or alters any existing execution gates.
local BUILD=70450
local REQUIRED={"identity","reagents","output","requiredSkill","availability",
    "faction","specialization","phase","acquisition"}
local DB2_FIELDS={identity="SkillLineAbility",reagents="SpellReagents",requiredSkill="SkillLineAbility"}
local Q={contract="JLP-70450-PRODUCTION-QUALIFICATION-1",sourceBuild=BUILD,
    readOnly=true,nativeDispatchAllowed=false,executionEligible=false,productionAuthority=false}
local function uint(n)
    return type(n)=="number" and n>0 and n<2147483647 and n==math.floor(n)
end
local function text(v)
    return type(v)=="string" and #v>0 and #v<=256 and not v:find("[%c]")
end
local function sha(v)
    return type(v)=="string" and #v==64 and v:match("^[0-9a-fA-F]+$")~=nil
end
local function utc(v)
    return type(v)=="string" and v:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$")~=nil
end
local function exactArray(a,limit)
    if type(a)~="table" then return nil end
    local n,hi=0,0
    for key in pairs(a) do
        if type(key)~="number" or key<1 or key>limit or key~=math.floor(key) then return nil end
        n=n+1;if key>hi then hi=key end
    end
    return n==hi and n or nil
end
local function key(k,id) return k..":"..tostring(id) end
local function liveBuild()
    local m=JLP:GetModule("ClientBuildInfo")
    if not m or type(m.GetBuildNumber)~="function" then return nil end
    local ok,n=pcall(m.GetBuildNumber,m)
    return ok and uint(n) and n or nil
end
local function fail(code,k,id,client)
    return {contract=Q.contract,sourceBuild=BUILD,clientBuild=client,
        professionKey=k,spellID=id,state="NOT_SOURCE_QUALIFIED",reason=code,
        sourceQualified=false,productionCandidateQualified=false,
        productionAuthority=false,nativeDispatchAllowed=false,
        executionEligible=false,readOnly=true}
end
local function trustRegistry(reg)
    return type(reg)=="table" and reg.contract=="JLP-70450-PRODUCTION-RIGHTS-1" and
        reg.sourceBuild==BUILD and reg.nativeDispatchAllowed==false and
        reg.executionEligible==false and type(reg.sourceReferences)=="table" and
        type(reg.reviews)=="table" and type(reg.records)=="table"
end
local function proveField(reg,record,field)
    local p=type(record.provenance)=="table" and record.provenance[field]
    if type(p)~="table" or p.state~="SOURCE_QUALIFIED" or not text(p.sourceId) or
        not text(p.rightsReviewId) or not text(p.reviewer) or
        not text(p.url) or not p.url:match("^https://") or
        not sha(p.inputSHA256) or p.sourceBuild~=BUILD or
        p.locale~=record.locale or not utc(p.observedAtUTC) or
        (p.transformation~="DIRECT_VERBATIM" and
         p.transformation~="OWNER_REVIEWED_NORMALIZATION") then
        return false,"FIELD_PROVENANCE_INVALID_"..field
    end
    local source=reg.sourceReferences[p.sourceId]
    if type(source)~="table" or source.verified~=true or
        source.redistributionApproved~=true or not text(source.licenseId) or
        source.rightsScope~="CATALOGUE_FIELDS" or source.url~=p.url or
        source.sourceBuild~=BUILD or source.locale~=record.locale or
        not sha(source.inputSHA256) or
        source.inputSHA256:lower()~=p.inputSHA256:lower() then
        return false,"SOURCE_OR_LICENSE_NOT_VERIFIED_"..field
    end
    local db2=DB2_FIELDS[field]
    if db2 then
        local r=JLP.data and JLP.data.build70450Recipes
        local expected=r and r.inputSHA256 and r.inputSHA256[db2]
        if source.kind~="CLIENT_DB2_70450" or not sha(expected) or
            source.inputSHA256:lower()~=expected:lower() then
            return false,"CANONICAL_CLIENT_SOURCE_SHA_NOT_PINNED_"..field
        end
    else
        -- Current-build server restrictions, output yields and acquisition are
        -- NEVER promoted merely because a client DB2 source is present.
        if source.kind~="LIVE_FOREVER_70450" or
            source.observedBuild~=BUILD or source.observedSpellID~=record.spellID or
            source.observedProfessionKey~=record.professionKey or
            source.artifactVerified~=true or not text(source.artifactId) or
            not utc(source.observedAtUTC) then
            return false,"INDEPENDENT_LIVE_EVIDENCE_NOT_REVIEWED_"..field
        end
    end
    local review=reg.reviews[p.rightsReviewId]
    local scopes=type(review)=="table" and review.approvedRecords and
        review.approvedRecords[key(record.professionKey,record.spellID)]
    if type(review)~="table" or review.status~="APPROVED" or
        review.redistributionApproved~=true or review.sourceId~=p.sourceId or
        review.sourceBuild~=BUILD or review.locale~=record.locale or
        review.inputSHA256~=p.inputSHA256 or review.reviewer~=p.reviewer or
        not utc(review.reviewedAtUTC) or type(scopes)~="table" or scopes[field]~=true then
        return false,"FIELD_RIGHTS_UNAPPROVED_"..field
    end
    return true
end
local function compareReagents(a,b)
    local n=exactArray(a,32)
    if n==nil or n==0 or n~=#b then return false end
    local expected,seen={},{ }
    for _,r in ipairs(b) do
        if not uint(r.itemID) or not uint(r.quantity) or expected[r.itemID] then return false end
        expected[r.itemID]=r.quantity
    end
    for i=1,n do
        local r=a[i]
        if type(r)~="table" or not uint(r.itemID) or not uint(r.quantity) or
            seen[r.itemID] or expected[r.itemID]~=r.quantity then return false end
        seen[r.itemID]=true
    end
    return true
end
local function compareOutput(out,canonical)
    if type(out)~="table" or out.liveYieldVerified~=true or
        out.observedBuild~=BUILD or out.spellID~=canonical.spellID then return false end
    local craft=canonical.craftOutput
    if type(craft)~="table" or type(craft.effects)~="table" then return false end
    local matches=0
    if out.kind=="ITEM" then
        if not uint(out.itemID) or not uint(out.min) or not uint(out.max) or
            out.min>out.max or out.max>999999 or
            (out.evidenceType~="TRADE_SKILL_UI_EXACT_RECIPE_LINK" and
             out.evidenceType~="EXECUTED_CRAFT_SETTLEMENT") then return false end
        for _,effect in ipairs(craft.effects) do
            if effect.kind=="CREATED_ITEM" then
                if effect.itemID~=out.itemID then return false end
                matches=matches+1
            else return false end
        end
    elseif out.kind=="ENCHANTMENT" then
        if canonical.professionKey~="ENCHANTING" or not uint(out.enchantmentID) or
            out.itemID~=nil or out.min~=nil or out.max~=nil or
            out.evidenceType~="CLIENT_TARGET_ENCHANTMENT_CONFIRMED" then return false end
        for _,effect in ipairs(craft.effects) do
            if effect.kind=="TARGET_ITEM_ENCHANTMENT" then
                if effect.enchantmentID~=out.enchantmentID then return false end
                matches=matches+1
            else return false end
        end
    else return false end
    return matches==1
end
local function restrictions(record,canonical)
    local r=record.requirements
    if type(r)~="table" or r.observedBuild~=BUILD or
        r.spellID~=record.spellID or r.professionKey~=record.professionKey or
        r.serverAvailability~="VERIFIED_AVAILABLE" or r.availabilityVerified~=true or
        r.factionVerified~=true or r.specializationVerified~=true or
        r.phaseVerified~=true or r.acquisitionVerified~=true then
        return false,"ACCESS_REQUIREMENTS_UNVERIFIED"
    end
    if r.faction~="HORDE" and r.faction~="ALLIANCE" and r.faction~="NEUTRAL" then
        return false,"FACTION_UNVERIFIED"
    end
    if not text(r.specialization) or not text(r.phase) then
        return false,"SPECIALIZATION_OR_PHASE_UNKNOWN"
    end
    if canonical.seasonOfDiscoveryCategory and r.phase=="NOT_APPLICABLE" then
        return false,"SOD_PHASE_NOT_ATTESTED"
    end
    local a=record.acquisition
    if type(a)~="table" or a.observedBuild~=BUILD or
        a.spellID~=record.spellID or a.professionKey~=record.professionKey or
        a.verified~=true then return false,"ACQUISITION_UNVERIFIED" end
    if a.kind=="TRAINER" or a.kind=="VENDOR" or a.kind=="NPC" or a.kind=="DROP" then
        if not uint(a.npcID) then return false,"ACQUISITION_NPC_ID_UNKNOWN" end
        if a.kind=="VENDOR" and not uint(a.teachingItemID) then
            return false,"ACQUISITION_TEACHING_ITEM_UNKNOWN"
        end
    elseif a.kind=="STARTER" then
        if a.npcID~=nil or a.teachingItemID~=nil then return false,"STARTER_ACTOR_CONFLICT" end
    else return false,"ACQUISITION_TYPE_UNVERIFIED" end
    if a.faction~=r.faction and a.faction~="NEUTRAL" then return false,"ACQUISITION_FACTION_CONFLICT" end
    -- A current-build teaching item relation does not itself prove a sale/drop.
    if a.teachingItemID then
        local acquisition=JLP:GetModule("Build70450RecipeAcquisition")
        if not acquisition then return false,"TEACHING_ITEM_REFERENCE_UNAVAILABLE" end
        local src,err=acquisition:GetRecipeSources(record.professionKey,record.spellID,BUILD)
        if not src then return false,"TEACHING_ITEM_REFERENCE_"..tostring(err) end
        local found=false
        for _,item in ipairs(src.teachingItems or {}) do
            if item.itemID==a.teachingItemID then found=true end
        end
        if not found then return false,"TEACHING_ITEM_NOT_LINKED_TO_SPELL" end
    end
    return true
end
function Q:AssessRecipe(professionKey,spellID,requestedBuild)
    if requestedBuild~=BUILD then return fail("EXPLICIT_BUILD_70450_REQUIRED",professionKey,spellID,liveBuild()) end
    local live=liveBuild()
    -- Source qualification is build-scoped evidence, not a running-client gate.
    -- All returned receipts remain advisory and nativeDispatchAllowed=false.
    local reg=JLP:GetModule("ProfessionRegistry")
    local keyName=reg and reg.NormalizeKey and reg:NormalizeKey(professionKey)
    local def=keyName and reg:Get(keyName)
    if not def or not uint(spellID) then return fail("INVALID_PROFESSION_OR_SPELL",keyName,spellID,live) end
    local catalogue=JLP:GetModule("Build70450RecipeCatalogue")
    if not catalogue then return fail("RECIPE_CATALOGUE_UNAVAILABLE",keyName,spellID,live) end
    local canonical,reason=catalogue:GetRecipe(keyName,spellID,BUILD)
    if not canonical then return fail("CANONICAL_RECIPE_"..tostring(reason),keyName,spellID,live) end
    if canonical.recordKind~="RECIPE_CANDIDATE" or canonical.sourceBuild~=BUILD or
        canonical.skillLineID~=def.skillLineID or canonical.professionKey~=keyName or
        canonical.spellID~=spellID or (canonical.clientBuildRelation~="MATCH" and canonical.clientBuildRelation~="MISMATCH" and canonical.clientBuildRelation~="UNKNOWN") or
        canonical.productionAuthority~=false or canonical.nativeDispatchAllowed~=false or
        canonical.executionEligible~=false or canonical.readOnly~=true then
        return fail("CANONICAL_RECIPE_IDENTITY_OR_AUTHORITY_INVALID",keyName,spellID,live)
    end
    local registry=JLP.data and JLP.data.build70450ProductionRights
    if not trustRegistry(registry) then return fail("RIGHTS_REGISTRY_INVALID",keyName,spellID,live) end
    local record=registry.records[key(keyName,spellID)]
    if not record then return fail("NO_INDEPENDENTLY_REVIEWED_RECORD",keyName,spellID,live) end
    if type(record)~="table" or record.contract~="JLP-70450-PRODUCTION-RECORD-1" or
        record.evidenceState~="SOURCE_QUALIFIED" or record.sourceBuild~=BUILD or
        record.professionKey~=keyName or record.skillLineID~=def.skillLineID or
        record.spellID~=spellID or not text(record.locale) or
        record.nativeDispatchAllowed~=false or record.executionEligible~=false or
        record.productionAuthority~=false or record.readOnly~=true or
        record.name~=canonical.name or not text(record.name) then
        return fail("RECORD_IDENTITY_OR_BUILD_CONFLICT",keyName,spellID,live)
    end
    if not compareReagents(record.reagents,canonical.reagents or {}) then
        return fail("CANONICAL_REAGENT_MISMATCH_OR_MISSING",keyName,spellID,live)
    end
    if not uint(record.requiredSkill) or record.requiredSkill~=canonical.rawMinSkillLineRank then
        return fail("REQUIRED_SKILL_NOT_VERIFIED",keyName,spellID,live)
    end
    if not compareOutput(record.output,canonical) then
        return fail("LIVE_OUTPUT_EVIDENCE_OR_ITEM_MISMATCH",keyName,spellID,live)
    end
    local permitted,why=restrictions(record,canonical)
    if not permitted then return fail(why,keyName,spellID,live) end
    for _,field in ipairs(REQUIRED) do
        local ok,problem=proveField(registry,record,field)
        if not ok then return fail(problem,keyName,spellID,live) end
    end
    return {contract=self.contract,sourceBuild=BUILD,clientBuild=live,
        professionKey=keyName,spellID=spellID,skillLineID=def.skillLineID,
        state="SOURCE_QUALIFIED",reason="FIELD_BY_FIELD_SOURCE_AND_RIGHTS_REVIEWED",
        sourceQualified=true,productionCandidateQualified=true,
        sourceBuildRelation=live==BUILD and "MATCH" or (live and "HISTORICAL_REFERENCE" or "CLIENT_UNKNOWN"),
        qualifiedFields={identity=true,reagents=true,output=true,requiredSkill=true,
            availability=true,faction=true,specialization=true,phase=true,acquisition=true},
        -- Explicit bounded projection; do not return arbitrary reviewer-supplied
        -- keys that might masquerade as nested action/dispatch permissions.
        reviewedAccess={serverAvailability=record.requirements.serverAvailability,
            faction=record.requirements.faction,
            specialization=record.requirements.specialization,phase=record.requirements.phase},
        reviewedAcquisition={kind=record.acquisition.kind,npcID=record.acquisition.npcID,
            teachingItemID=record.acquisition.teachingItemID,faction=record.acquisition.faction},
        reviewedOutput={kind=record.output.kind,itemID=record.output.itemID,
            enchantmentID=record.output.enchantmentID,min=record.output.min,max=record.output.max},
        productionAuthority=false,nativeDispatchAllowed=false,
        executionEligible=false,readOnly=true,nativeExecutionGate="EXISTING_INDEPENDENT_GATES"}
end
function Q:AuditInstalled()
    local registry=JLP.data and JLP.data.build70450ProductionRights
    local result={contract=self.contract,sourceBuild=BUILD,declared=0,qualified=0,rejected=0,
        referenceSpellIdentities=(JLP.data and JLP.data.build70450Recipes and
            JLP.data.build70450Recipes.metadata and JLP.data.build70450Recipes.metadata.uniqueProfSpell) or 0,
        verifiedProductionPermissions=0,
        nativeDispatchAllowed=false,executionEligible=false,productionAuthority=false,
        readOnly=true,rejectionReasons={},status="REVIEW_PENDING"}
    if not trustRegistry(registry) then
        result.status="BLOCKED";result.reason="RIGHTS_REGISTRY_INVALID";return result
    end
    for identity,record in pairs(registry.records) do
        result.declared=result.declared+1
        local k,id
        if type(identity)=="string" then k,id=identity:match("^([A-Z_]+):(%d+)$") end
        id=tonumber(id)
        if type(record)~="table" or not id or record.professionKey~=k or record.spellID~=id then
            result.rejected=result.rejected+1
            result.rejectionReasons.INVALID_RECORD_KEY=(result.rejectionReasons.INVALID_RECORD_KEY or 0)+1
        else
            local receipt=self:AssessRecipe(k,id,BUILD)
            if receipt.sourceQualified then result.qualified=result.qualified+1 else
                result.rejected=result.rejected+1
                result.rejectionReasons[receipt.reason]=(result.rejectionReasons[receipt.reason] or 0)+1
            end
        end
    end
    result.status=result.qualified>0 and result.rejected==0 and "PARTIALLY_QUALIFIED_READ_ONLY" or
        (result.rejected>0 and "BLOCKED_OR_PARTIAL" or "REVIEW_PENDING")
    return result
end
JLP:RegisterModule("Build70450ProductionQualification",Q)
