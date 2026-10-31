local _,JLP=...
-- Unified JLP-owned, field-qualified data facade. Existing production datasets
-- remain guarded by ProfessionDatasetProvider/PlanAuthorityPolicy. This service
-- does not authorize execution or write SavedVariables. No third-party payloads.
local Catalogue={contract="jlp-professions-data-catalogue-v2",nativeDispatchAllowed=false,
    executionEligible=false,readOnly=true,sourcePriority="QUALIFIED_STATIC_THEN_ADVISORY"}
local function positive(v)
    return type(v)=="number" and v>0 and v==math.floor(v) and v<math.huge
end
local function normalize(v)
    return tostring(v or ""):lower():gsub("[%c%p]+"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
end
local function observedBuild()
    local info=JLP:GetModule("ClientBuildInfo")
    if type(info)~="table" or type(info.GetBuildNumber)~="function" then
        return nil,"CLIENT_BUILD_UNAVAILABLE"
    end
    local ok,build=pcall(info.GetBuildNumber,info)
    if not ok or not positive(build) then return nil,"CLIENT_BUILD_UNKNOWN" end
    return build,"LIVE_CLIENT_BUILD"
end
function Catalogue:GetObservedClientBuild()
    return observedBuild()
end
local function metadata(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and reg:Get(key)
    return def,def and def.skillLineID
end
local function safeCopy(value,depth)
    if type(value)~="table" then return value end
    if (depth or 0)>8 then return nil end
    local out={}
    for k,v in pairs(value) do out[k]=safeCopy(v,(depth or 0)+1) end
    return out
end
-- This research sidecar is intentionally distinct from GetRecipe and GetDirectMaterialNeeds.
-- DQ01 candidate rows do not change SOURCE_QUALIFIED or native execution authority.
function Catalogue:GetPrivatePilotResearch(key,spellOrName,clientBuild)
    local source=JLP.data and JLP.data.privatePilotResearch
    local reg=JLP:GetModule("ProfessionRegistry")
    if not (reg and reg:Get(key)) then return nil,"UNKNOWN_PROFESSION" end
    if type(source)~="table" or source.contract~="JLP-PRIVATE-OWNER-RESEARCH-PILOT-1" then
        return nil,"PILOT_UNAVAILABLE"
    end
    local isID=positive(spellOrName)
    local name=type(spellOrName)=="string" and normalize(spellOrName) or nil
    if not isID and (not name or name=="") then return nil,"INVALID_IDENTITY" end
    for _,conflict in ipairs(source.conflicts or {}) do
        if conflict.professionKey==key and ((isID and conflict.spellID==spellOrName) or
            (name and normalize(conflict.name)==name)) then
            return {professionKey=key,spellID=conflict.spellID,state="CONFLICT",
                sourceBuild=70374,locale="enUS",identityEvidence="CONFLICT",
                actionable=false,sourceQualified=false,productionAuthorized=false,
                nativeDispatchAllowed=false,planMutationAllowed=false,
                materialTotals=nil,reagents=nil},"CONFLICT_BLOCKED"
        end
    end
    for _,record in ipairs(source.rows or {}) do
        if record.professionKey==key and ((isID and record.spellID==spellOrName) or
            (name and normalize(record.name)==name)) then
            local result=safeCopy(record)
            -- Even a numeric match proves no output/yield, learned-state, skill
            -- thresholds, per-craft quantity, source actor, rights or client build.
            result.state="CANDIDATE"
            result.identityEvidence=isID and "OWNER_RAW_ID_MATCH" or "NAME_ONLY_MATCH_UNQUALIFIED"
            result.sourceBuild=source.sourceBuild;result.locale=source.locale
            result.buildEvidence=source.buildEvidence
            result.buildMatchesObserved=positive(clientBuild) and clientBuild==source.sourceBuild or false
            result.sourceQualified=false;result.productionAuthorized=false
            result.nativeDispatchAllowed=false;result.executionEligible=false
            result.actionable=false;result.planMutationAllowed=false
            result.materialTotals=nil;result.owned=nil;result.missing=nil;result.craftable=nil
            result.perCraftQuantityState="UNKNOWN"
            return result,"RAW_OWNER_RESEARCH_NOT_QUALIFIED"
        end
    end
    -- Wave1 supplies only raw identity leads, not reagent quantities.
    for _,lead in ipairs(source.wave1Identity or {}) do
        if lead.professionKey==key and ((isID and lead.spellID==spellOrName) or
            (name and normalize(lead.name)==name)) then
            local result=safeCopy(lead)
            result.state=lead.state=="CONFLICT" and "CONFLICT" or "CANDIDATE"
            result.identityEvidence=isID and "OWNER_RAW_ID_MATCH" or "NAME_ONLY_MATCH_UNQUALIFIED"
            result.sourceBuild=source.sourceBuild;result.locale=source.locale
            result.buildEvidence=source.buildEvidence
            result.rawReagentSlots=nil;result.reagentQuantitySemantics="UNKNOWN"
            result.materialTotals=nil;result.missing=nil;result.owned=nil;result.craftable=nil
            result.sourceQualified=false;result.productionAuthorized=false
            result.nativeDispatchAllowed=false;result.executionEligible=false
            result.actionable=false;result.planMutationAllowed=false
            return result,result.state=="CONFLICT" and "CONFLICT_BLOCKED" or "WAVE1_RAW_IDENTITY_ONLY"
        end
    end
    return nil,"PILOT_NOT_FOUND"
end
function Catalogue:GetPrivateResearchCoverage(key)
    local source=JLP.data and JLP.data.privatePilotResearch
    if type(source)~="table" then return nil,"PILOT_UNAVAILABLE" end
    for _,row in ipairs(source.professionCoverage or {}) do
        if row.professionKey==key then
            local result=safeCopy(row)
            result.integratedPilotSpellIDs=0 -- not an assertion of field qualification
            for _,pilot in ipairs(source.rows or {}) do
                if pilot.professionKey==key then result.integratedPilotSpellIDs=result.integratedPilotSpellIDs+1 end
            end
            result.integratedWave1IdentityOnly=0
            for _,lead in ipairs(source.wave1Identity or {}) do
                if lead.professionKey==key then
                    result.integratedWave1IdentityOnly=result.integratedWave1IdentityOnly+1
                end
            end
            return result,"READ_ONLY_RESEARCH_COVERAGE"
        end
    end
    return nil,"UNKNOWN_PROFESSION"
end
function Catalogue:ForPrivatePilotPlanStep(key,step,clientBuild)
    if type(step)~="table" then return nil,"INVALID_STEP" end
    local id=step.recipeID or step.spellID
    if step.recipeID~=nil and step.spellID~=nil and step.recipeID~=step.spellID then
        return nil,"STEP_ID_TYPE_CONFLICT"
    end
    if id~=nil then
        if not positive(id) then return nil,"INVALID_STEP_ID" end
        local result,reason=self:GetPrivatePilotResearch(key,id,clientBuild)
        -- A present recipe or recipeName is an identity constraint, never an ID override.
        -- Both aliases are independently checked to fail closed on stale plan labels.
        for _,alias in ipairs({"recipe", "recipeName"}) do
            local label=step[alias]
            if result and type(label)=="string" and normalize(label)~="" and
                result.name and normalize(result.name)~=normalize(label) then
                return nil,"STEP_NAME_IDENTITY_CONFLICT"
            end
        end
        return result,reason
    end
    return self:GetPrivatePilotResearch(key,step.recipe or step.recipeName,clientBuild)
end
-- Historical owner-provided source checksums. These bind raw references
-- to the owner-delivered file identity; they do not imply redistribution
-- permission, semantic validity, or any WoW client-build observation.
local OWNER_RAW_SOURCE_SHA={
    ["JuztLevel-SkillLineAbilitys_1.60.1.70374.csv"]="077de6cf6fd26b284b38f65d72622562885fbf145fb7dd18823475cc8ad6a300",
    ["JuztLevel-SpellNames_1.60.1.70374.csv"]="fe0cdd7710e24f9c2ee54c4c1c692822950e007c698691e426d19c07c7c606a8",
    ["JuztLevel-SpellReagents_1.60.1.70374.csv"]="9015a1474f67b23a45cedc484b4a606278bcb7ee80ff07c550e89138c8b96fa5",
    ["JuztLevel-SpellEffects_1.60.1.70374.csv"]="0433810b1e680af9660c2fcb79f2a3030333d98f3ea7ae90a50480bbde012049",
}
-- One bounded, non-executable sidecar receipt shared by the existing
-- Planner, Materials, Sources and Acquisition consumers. This is NOT an
-- evidence-admission API: owner CSV identifiers and numbers remain raw.
local function denseRawSlots(slots)
    if slots==nil then return nil,"UNKNOWN" end
    if type(slots)~="table" then return nil,"INVALID_RAW_SLOTS" end
    local count,maxIndex=0,0
    for index in pairs(slots) do
        if not positive(index) or index>32 then return nil,"INVALID_RAW_SLOT_INDEX" end
        count=count+1
        if index>maxIndex then maxIndex=index end
    end
    if count~=maxIndex then return nil,"SPARSE_RAW_SLOTS" end
    local out,seen={},{}
    for i=1,count do
        local slot=slots[i]
        if type(slot)~="table" or not positive(slot.itemID) or
            seen[slot.itemID] or slot.quantitySemantics~="UNKNOWN" then
            return nil,"INVALID_OR_DUPLICATE_RAW_SLOT"
        end
        seen[slot.itemID]=true
        -- Raw quantity is descriptive only; it cannot be used as a requirement.
        out[#out+1]={itemID=slot.itemID,rawQuantity=slot.rawQuantity,
            quantity=nil,quantityState="UNKNOWN",owned=nil,missing=nil,
            sourceQualification="NOT_APPROVED"}
    end
    return out,nil
end
function Catalogue:GetPrivateResearchAdvisory(key,spellOrName,clientBuild)
    local row,reason=self:GetPrivatePilotResearch(key,spellOrName,clientBuild)
    if not row then return nil,reason end
    local function locked(state,why)
        return {contract="JLP-PRIVATE-RESEARCH-ADVISORY-2",
            professionKey=key,spellID=row.spellID,state=state,
            status=state=="CONFLICT" and "CONFLICT" or "PARTIAL",
            sourceBuild=row.sourceBuild,locale=row.locale,
            observedClientBuild=positive(clientBuild) and clientBuild or nil,
            -- A valid older source is historical, not intrinsically corrupt.
            -- Only inconsistent row/anchor evidence produces CONFLICT.
            buildState=positive(clientBuild) and
                (clientBuild==row.sourceBuild and "TARGET_MATCH_UNVERIFIED" or "HISTORICAL_REFERENCE") or "UNKNOWN",
            identityEvidence=row.identityEvidence,rawReagentSlots=nil,
            rawReagentCount=0,materialTotals=nil,reagents=nil,owned=nil,missing=nil,
            sourceQualified=false,productionAuthorized=false,actionable=false,
            planMutationAllowed=false,nativeDispatchAllowed=false,executionEligible=false,
            craftable=nil,learned=nil,recipeActor=nil,trainer=nil,vendor=nil,
            hordeAccess=nil,acquisition=nil,bankActions=nil,auctionActions=nil,
            evidenceReason=why}
    end
    if row.state=="CONFLICT" then return locked("CONFLICT","IDENTITY_CONFLICT"),"CONFLICT_BLOCKED" end
    if row.state~="CANDIDATE" or not positive(row.spellID) then
        return locked("CONFLICT","INVALID_RESEARCH_IDENTITY"),"INVALID_RESEARCH_IDENTITY"
    end
    local source=JLP.data and JLP.data.privatePilotResearch
    local wave,found= nil,0
    for _,lead in ipairs(source and source.wave1Identity or {}) do
        if lead.professionKey==key and lead.spellID==row.spellID then
            found=found+1;wave=lead
        end
    end
    if found>1 or (found==1 and (wave.name~=row.name or
        type(wave.sourceSHA256)~="string" or #wave.sourceSHA256~=64 or
        wave.sourceSHA256~=OWNER_RAW_SOURCE_SHA["JuztLevel-SkillLineAbilitys_1.60.1.70374.csv"] or
        not positive(wave.ordinal) or not positive(wave.physicalStartLine) or
        not positive(wave.physicalEndLine) or wave.physicalEndLine<wave.physicalStartLine)) then
        return locked("CONFLICT","RAW_IDENTITY_ANCHOR_CONFLICT"),"RAW_IDENTITY_ANCHOR_CONFLICT"
    end
    local slots,slotReason=denseRawSlots(row.rawReagentSlots)
    if slotReason and slotReason~="UNKNOWN" then
        return locked("CONFLICT",slotReason),slotReason
    end
    -- Owner CSV fields are unqualified, yet even their *raw display values*
    -- must agree with the shipped, individually anchored field references.
    -- This is consistency checking, NOT legal or semantic qualification.
    local fieldReferences={}
    if row.rawReagentSlots~=nil then
        local expectations={
            {"identity","SpellID",row.spellID},
            {"name","SpellName",row.name},
            {"requiredSkill","MinSkillLineRank",row.rawRequiredSkill},
            {"typedEffectRaw","EffectItemType",row.rawOutputItemCandidate},
            {"effectParameters","EffectBasePoints",row.rawEffectBasePoints},
            {"difficultyRaw","TrivialRankLow",row.rawTrivialLow},
            {"difficultyRaw","TrivialRankHigh",row.rawTrivialHigh},
            {"acquisitionRaw","AcquisitionMethod",row.rawAcquisition},
        }
        for i,slot in ipairs(row.rawReagentSlots) do
            expectations[#expectations+1]={"reagentItemID","ReagentItemID_"..tostring(i-1),slot.itemID}
            expectations[#expectations+1]={"reagentQuantity","ReagentQuantity_"..tostring(i-1),slot.rawQuantity}
        end
        for _,expectation in ipairs(expectations) do
            local matched=nil;local matches=0
            for _,anchor in ipairs(source and source.fieldAnchors or {}) do
                if anchor.professionKey==key and anchor.spellID==row.spellID and
                    anchor.fieldFamily==expectation[1] and anchor.column==expectation[2] then
                    matches=matches+1;matched=anchor
                end
            end
            if matches~=1 or type(matched)~="table" or
                tostring(expectation[3])~=matched.rawValue or
                type(matched.sourceSHA256)~="string" or
                not matched.sourceSHA256:match("^[0-9a-f]+$") or
                #matched.sourceSHA256~=64 or
                OWNER_RAW_SOURCE_SHA[matched.sourceFile]~=matched.sourceSHA256 or
                type(matched.fieldAnchor)~="string" or
                not matched.fieldAnchor:match("^[0-9a-f]+$") or #matched.fieldAnchor~=64 or
                not positive(matched.ordinal) or not positive(matched.startLine) or
                not positive(matched.endLine) or matched.endLine<matched.startLine or
                matched.semanticState~="UNKNOWN" or matched.rightsState~="NOT_APPROVED" then
                return locked("CONFLICT","RAW_FIELD_ANCHOR_CONFLICT"),"RAW_FIELD_ANCHOR_CONFLICT"
            end
            fieldReferences[#fieldReferences+1]={fieldFamily=matched.fieldFamily,
                column=matched.column,sourceFile=matched.sourceFile,
                sourceSHA256=matched.sourceSHA256,fieldAnchor=matched.fieldAnchor,
                ordinal=matched.ordinal,startLine=matched.startLine,endLine=matched.endLine,
                semanticState="UNKNOWN",rightsState="NOT_APPROVED"}
        end
    end
    local receipt=locked("CANDIDATE",reason)
    receipt.name=row.name
    receipt.rawReagentSlots=slots
    receipt.ownerRawFieldReferences=fieldReferences
    receipt.rawReagentCount=slots and #slots or 0
    receipt.reagentState=slots and #slots>0 and "RAW_IDENTITIES_ONLY" or "UNKNOWN"
    receipt.outputState="UNKNOWN"
    receipt.yieldState="UNKNOWN"
    receipt.requiredSkillState="UNKNOWN"
    receipt.difficulty4State="UNKNOWN"
    receipt.acquisitionState="UNKNOWN"
    receipt.hordeState="UNKNOWN"
    receipt.rawOutputItemCandidate=positive(row.rawOutputItemCandidate) and row.rawOutputItemCandidate or nil
    receipt.rawRequiredSkill=positive(row.rawRequiredSkill) and row.rawRequiredSkill or nil
    receipt.rawEffectBasePoints=row.rawEffectBasePoints
    receipt.identityAnchor=found==1 and {
        sourceSHA256=wave.sourceSHA256,ordinal=wave.ordinal,
        physicalStartLine=wave.physicalStartLine,physicalEndLine=wave.physicalEndLine,
        state="OWNER_RAW_REFERENCE_UNVERIFIED"} or nil
    return receipt,"PARTIAL_OWNER_RESEARCH"
end
local function researchRecords(key)
    local research=JLP.data and JLP.data.professionResearchRoutes
    local data=research and research.professions and research.professions[key]
    local entries={};local seen={}
    for _,strategy in ipairs({"normal","aggressive"}) do
        local route=data and data[strategy]
        for _,step in ipairs(route and route.steps or {}) do
            if step.kind=="craft" and type(step.recipe)=="string" and step.recipe~="" then
                local fingerprint=normalize(step.recipe)
                local row=seen[fingerprint]
                if not row then
                    row={professionKey=key,recipeID=nil,recipeName=step.recipe,
                        identityState="NAME_ONLY_RESEARCH",state="CANDIDATE",
                        source="horde-profession-information-v2",sourceBuild=nil,
                        rawResearchRoutes={},reagents=nil,output=nil,
                        nativeDispatchAllowed=false,executionEligible=false,readOnly=true,
                        qualificationReason="MISSING_VERIFIED_RECIPE_ID_AND_ITEM_IDENTITIES"}
                    seen[fingerprint]=row;entries[#entries+1]=row
                end
                -- Research quantities are total route requirements, NOT per-craft reagents.
                row.rawResearchRoutes[#row.rawResearchRoutes+1]={strategy=strategy,
                    skillMin=step.skillMin,skillTarget=step.skillTarget,
                    expectedCrafts=step.expectedCrafts,estimated=step.estimated==true,
                    keep=step.keep==true,requirements=safeCopy(step.requirements)}
            end
        end
    end
    table.sort(entries,function(a,b) return normalize(a.recipeName)<normalize(b.recipeName) end)
    return entries
end
function Catalogue:GetRecipe(key,recipeID,clientBuild)
    local _,skill=metadata(key)
    if not skill or not positive(recipeID) then return nil,"INVALID_RECIPE_ID" end
    local reference=JLP:GetModule("RecipeReferenceCatalogue")
    if not reference then return nil,"CATALOGUE_UNAVAILABLE" end
    -- Explicit build is mandatory for source qualification (no target fallback).
    local row,reason=reference:GetCandidate(skill,recipeID,
        positive(clientBuild) and clientBuild or false)
    if not row and reason=="SOURCE_UNAVAILABLE" then
        -- A read-only live observation is useful for recipes absent from the
        -- static baseline. It cannot create or qualify shipped catalogue rows.
        local live=JLP:GetModule("ClientRecipeEvidence")
        if live and type(live.Observe)=="function" then
            local ok,observed,observationReason=pcall(live.Observe,live,key,recipeID,clientBuild)
            if ok and observed then row=observed
            elseif not ok then reason="CLIENT_OBSERVATION_EXCEPTION"
            else reason=observationReason or reason end
        end
    end
    if not row then
        -- Build 70374 owner-supplied references are useful for inspection, but
        -- cannot pass field qualification, production gates or native dispatch.
        local owner=JLP:GetModule("Build70374ProfessionReference")
        if owner and type(owner.GetRecipe)=="function" then
            -- The owner service takes a SOURCE selector, not a client-build
            -- observation. Passing the live build here silently removed the
            -- 70374 fallback on 70450/70532 and on unknown builds.
            local raw=owner:GetRecipe(key,recipeID,70374)
            if raw then row=raw;reason="OWNER_70374_READONLY_REFERENCE" end
        end
    end
    if not row then return nil,reason end
    -- Do not let a live comparison mutate the static catalogue index.
    if row.observationState~="CLIENT_OBSERVED" and positive(clientBuild) then
        local observer=JLP:GetModule("ClientRecipeEvidence")
        if observer and type(observer.CompareStatic)=="function" then
            local ok,comparison=pcall(observer.CompareStatic,observer,key,row,clientBuild)
            if ok and comparison then row.clientReagentComparison=comparison end
        end
    end
    row.dataCatalogueContract=self.contract
    row.readOnly=true;row.nativeDispatchAllowed=false;row.executionEligible=false
    return row,nil
end
-- Live client evidence remains a separate, explicitly non-qualifying path.
-- Direct needs are only shown when the exact open recipe schematic is complete;
-- a missing/ambiguous slot must never silently become an empty material list.
function Catalogue:GetClientObservedMaterialNeeds(key,recipeID,craftCount,clientBuild)
    if not positive(craftCount) or craftCount>9999 then return nil,"INVALID_CRAFT_COUNT" end
    local observer=JLP:GetModule("ClientRecipeEvidence")
    if not observer then return nil,"CLIENT_OBSERVATION_UNAVAILABLE" end
    local ok,row,reason=pcall(observer.Observe,observer,key,recipeID,clientBuild)
    if not ok then return nil,"CLIENT_OBSERVATION_EXCEPTION" end
    if not row then return nil,reason end
    if not row.reagentObservationComplete then return nil,row.reagentObservationReason end
    local needs={}
    for _,reagent in ipairs(row.reagents) do
        needs[#needs+1]={itemID=reagent.itemID,perCraft=reagent.quantity,
            quantity=reagent.quantity*craftCount,ownedState="UNKNOWN",missingState="UNKNOWN"}
    end
    return {professionKey=key,recipeID=recipeID,craftCount=craftCount,
        sourceBuild=row.sourceBuild,needs=needs,complete=true,
        evidenceState="CANDIDATE",observationState="CLIENT_OBSERVED",
        productionAuthority=false,nativeDispatchAllowed=false,readOnly=true},nil
end
function Catalogue:GetClientObservedPage(key,offset,pageSize,clientBuild)
    local observer=JLP:GetModule("ClientRecipeEvidence")
    if not observer then return nil,"CLIENT_OBSERVATION_UNAVAILABLE" end
    local ok,result,reason=pcall(observer.ObservePage,observer,key,offset,pageSize,clientBuild)
    if not ok then return nil,"CLIENT_OBSERVATION_EXCEPTION" end
    return result,reason
end
function Catalogue:GetResearchNames(key)
    if not metadata(key) then return nil,"UNKNOWN_PROFESSION" end
    return researchRecords(key),nil
end
function Catalogue:ForPlanStep(key,step,clientBuild)
    if not metadata(key) or type(step)~="table" then return nil,"INVALID_STEP" end
    local id=step.recipeID or step.spellID
    if positive(step.recipeID) and positive(step.spellID) and
        step.recipeID~=step.spellID then return nil,"STEP_ID_TYPE_CONFLICT" end
    if positive(id) then
        local row,reason=self:GetRecipe(key,id,clientBuild)
        if row then
            if row.observationState=="CLIENT_OBSERVED" then
                return row,"CLIENT_OBSERVED_SPELL_ID"
            end
            return row,"STATIC_SPELL_ID"
        end
        -- A typed numeric ID may NOT silently degrade to a name-only match.
        return nil,reason or "ID_SOURCE_UNAVAILABLE"
    end
    local name=normalize(step.recipe or step.recipeName)
    if name=="" then return nil,"STEP_IDENTITY_UNKNOWN" end
    for _,row in ipairs(researchRecords(key)) do
        if normalize(row.recipeName)==name then
            return safeCopy(row),"NAME_ONLY_RESEARCH_NO_ID_AUTHORITY"
        end
    end
    return nil,"SOURCE_UNAVAILABLE"
end
function Catalogue:GetAcquisitionEvidence(key,recipeID,clientBuild)
    local row,reason=self:GetRecipe(key,recipeID,clientBuild)
    if not row then return nil,reason end
    if row.state~="SOURCE_QUALIFIED" then return nil,"ACQUISITION_FIELD_UNQUALIFIED" end
    if row.acquisitionQualificationReason and
       row.acquisitionQualificationReason~="QUALIFIED_TYPED_ACQUISITION" then
        return nil,row.acquisitionQualificationReason
    end
    if not (row.verifiedAcquisition and row.qualifiedFields and
        row.qualifiedFields.acquisition) then return nil,"ACQUISITION_FIELD_UNQUALIFIED" end
    local provenance=row.fieldProvenance and row.fieldProvenance.acquisition
    -- An independently reviewed actor relation is scoped to its SOURCE build.
    -- Do not require the running client to have exactly that historical build
    -- merely to read the record. This does NOT prove the actor is live today.
    if type(provenance)~="table" or provenance.state~="SOURCE_QUALIFIED" or
        not positive(row.sourceBuild) or
        provenance.sourceBuild~=row.sourceBuild then
        return nil,"ACQUISITION_FIELD_UNQUALIFIED" end
    local a=row.acquisition
    if type(a)~="table" or a.sourceBuild~=row.sourceBuild or
        a.hordeQualified~=true then return nil,"ACQUISITION_FIELD_UNQUALIFIED" end
    local fields={TRAINER="trainerID",VENDOR="vendorID",NPC="npcID",SCROLL="scrollItemID",DROP="dropNPCID"}
    local field=fields[a.kind]
    if not field or not positive(a[field]) then return nil,"ACTOR_IDENTITY_UNKNOWN" end
    local out=safeCopy(a)
    out.sourceBuild=row.sourceBuild
    out.observedClientBuild=positive(clientBuild) and clientBuild or nil
    out.clientBuildRelation=not positive(clientBuild) and "UNKNOWN_CLIENT" or
        (clientBuild==row.sourceBuild and "MATCH" or "HISTORICAL_REFERENCE")
    -- Static acquisition is not a live actor, faction entitlement or
    -- navigable destination proof on *any* build, including source matches.
    out.currentClientAvailabilityVerified=false
    out.navigationQualified=false
    out.actionable=false
    out.readOnly=true
    out.nativeDispatchAllowed=false
    return out,nil
end
function Catalogue:GetDirectMaterialNeeds(key,recipeID,craftCount,clientBuild)
    if not positive(craftCount) or craftCount>9999 then return nil,"INVALID_CRAFT_COUNT" end
    local row,reason=self:GetRecipe(key,recipeID,clientBuild)
    if not row then return nil,reason end
    if row.state~="SOURCE_QUALIFIED" or
        not (row.qualifiedFields and row.qualifiedFields.reagents) then
        return nil,row.qualificationReason or "STATIC_REAGENTS_UNQUALIFIED"
    end
    local needs={}
    for _,reagent in ipairs(row.reagents or {}) do
        if not positive(reagent.itemID) or not positive(reagent.quantity) then return nil,"INVALID_REAGENT" end
        needs[#needs+1]={itemID=reagent.itemID,quantity=reagent.quantity*craftCount,
            perCraft=reagent.quantity,name=reagent.name,ownedState="UNKNOWN",missingState="UNKNOWN"}
    end
    return {recipeID=recipeID,professionKey=key,craftCount=craftCount,needs=needs,
        sourceBuild=row.sourceBuild,evidence=row.reagentEvidence,
        evidenceState=row.evidenceState,qualifiedFields=row.qualifiedFields,
        nativeDispatchAllowed=false,readOnly=true},nil
end
-- Static item references for the existing Materials/Bank/AH resolver only.
-- They do not assert item ownership, price, vendor stock or production rights.
-- Array-preserving v2 completeness contract: callers using ipairs keep
-- working, but a provider error MUST never silently turn a partial index into
-- a complete authoritative material source.
-- Validate all representable Lua keys; # and ipairs hide sparse, index-zero and
-- keyed corruption. The array contract remains intact for downstream consumers.
local function boundedDense(value,limit,allowEmpty)
    if type(value)~="table" then return nil,"NOT_ARRAY" end
    local count,maxIndex=0,0
    for index in pairs(value) do
        if not positive(index) or index>limit then return nil,"ARRAY_KEY_INVALID" end
        count=count+1
        if count>limit then return nil,"ARRAY_UNBOUNDED" end
        if index>maxIndex then maxIndex=index end
    end
    if count~=maxIndex then return nil,"ARRAY_SPARSE" end
    if count==0 and not allowEmpty then return nil,"ARRAY_EMPTY" end
    return count,nil
end
function Catalogue:GetReagentIndex(clientBuild)
    -- A caller-supplied build is only a requested scope. A complete LIVE
    -- receipt must be obtained independently from the current client.
    local observedClientToken=nil
    if positive(clientBuild) then
        local client=JLP:GetModule("ClientBuildInfo")
        if client and type(client.Read)=="function" then
            local ok,info=pcall(client.Read,client)
            if ok and type(info)=="table" and info.known==true and
                info.buildNumber==clientBuild and positive(info.interfaceVersion) then
                local expected=string.format("forever:%s|interface:%s",
                    tostring(clientBuild),tostring(info.interfaceVersion))
                if info.token==expected then observedClientToken=expected end
            end
        end
    end
    local reference=JLP:GetModule("RecipeReferenceCatalogue")
    local reg=JLP:GetModule("ProfessionRegistry")
    local items,byID={},{}
    items.complete=true
    items.status="COMPLETE"
    -- An aggregate of multiple source builds has no single sourceBuild.
    -- NEVER stamp the requested client build as if it were source provenance.
    items.sourceBuild=nil
    items.sourceBuilds={}
    items.clientBuild=positive(clientBuild) and clientBuild or nil
    items.requestedBuild=positive(clientBuild) and clientBuild or nil
    items.buildEvidenceState=positive(clientBuild) and "EXPLICIT_CLIENT_BUILD" or "CLIENT_BUILD_UNKNOWN"
    items.nativeDispatchAllowed=false
    items.readOnly=true
    items.errors={}
    items.professions={}
    -- Static source/field receipts have their OWN positive sourceBuild and
    -- independently reviewed rights. Absence of a live client build must not
    -- convert those historical references into partial data. This does NOT
    -- confer any live learned, inventory, difficulty or crafting authority.
    items.liveClientVerified=observedClientToken~=nil
    items.liveClientToken=observedClientToken
    items.qualificationScope="STATIC_SOURCE_FIELDS_ONLY"
    -- Q124: RecipeReferenceCatalogue's state string is descriptive, not an
    -- independent field receipt. Validate the actual Q123 facade receipt for
    -- each source-qualified row before indexing its reagent ItemIDs.
    local function qualifiedRecipeReceipt(key,row,clientBuild,reagentCount)
        if not positive(row.sourceBuild) then return false,"SOURCE_PROVENANCE_UNKNOWN" end
        if row.verifiedFieldSet~=true or type(row.qualifiedFields)~="table" then
            return false,"PAGE_FIELDS_UNQUALIFIED"
        end
        for _,field in ipairs({"identity","reagents","output","requiredSkill"}) do
            if row.qualifiedFields[field]~=true then
                return false,"PAGE_"..field.."_UNQUALIFIED"
            end
        end
        if type(self.GetRecipeFieldReceipt)~="function" then
            return false,"FIELD_RECEIPT_UNAVAILABLE"
        end
        local ok,receipt=pcall(self.GetRecipeFieldReceipt,self,key,row.recipeID,clientBuild)
        if not ok or type(receipt)~="table" then
            return false,"FIELD_RECEIPT_UNAVAILABLE"
        end
        if receipt.professionKey~=key or receipt.recipeID~=row.recipeID or
            receipt.sourceBuild~=row.sourceBuild or
            receipt.state~="SOURCE_QUALIFIED" or
            receipt.staticRecipeComplete~=true or receipt.sourceQualified~=true or
            receipt.readOnly~=true or receipt.nativeDispatchAllowed~=false or
            receipt.executionEligible~=false or
            type(receipt.fields)~="table" then
            return false,"FIELD_RECEIPT_UNQUALIFIED"
        end
        for _,field in ipairs({"identity","reagents","output","requiredSkill"}) do
            if receipt.fields[field]~="SOURCE_QUALIFIED" then
                return false,"FIELD_"..field.."_UNQUALIFIED"
            end
        end
        if not positive(receipt.requiredSkill) or
            type(receipt.reagents)~="table" then
            return false,"FIELD_SKILL_OR_REAGENTS_MISSING"
        end
        if type(row.requirements)~="table" or
            row.requirements.skill~=receipt.requiredSkill then
            return false,"FIELD_SKILL_MISMATCH"
        end
        local n,why=boundedDense(receipt.reagents,256,false)
        if not n or n~=reagentCount then
            return false,"FIELD_REAGENTS_"..(why or "COUNT_MISMATCH")
        end
        local expected={}
        for i=1,n do
            local r=receipt.reagents[i]
            if type(r)~="table" or not positive(r.itemID) or
                not positive(r.quantity) or r.usableForPlan~=true or
                expected[r.itemID] then
                return false,"FIELD_REAGENT_INVALID"
            end
            expected[r.itemID]=r.quantity
        end
        for i=1,reagentCount do
            local r=row.reagents[i]
            if type(r)~="table" or expected[r.itemID]~=r.quantity then
                return false,"FIELD_REAGENT_MISMATCH"
            end
        end
        local out=receipt.output
        if type(out)~="table" or
            (out.kind=="ITEM" and
                (not positive(out.itemID) or not positive(out.quantityMin) or
                 out.quantityMin~=out.quantityMax)) or
            (out.kind=="ENCHANTMENT" and
                (key~="ENCHANTING" or not positive(out.enchantmentID) or
                 out.itemID~=nil or out.quantityMin~=nil or out.quantityMax~=nil)) or
            (out.kind~="ITEM" and out.kind~="ENCHANTMENT") then
            return false,"FIELD_OUTPUT_UNQUALIFIED"
        end
        local proposed=row.output
        if type(proposed)~="table" or proposed.kind~=out.kind or
            (out.kind=="ITEM" and
                (proposed.itemID~=out.itemID or
                 proposed.quantityMin~=out.quantityMin or
                 proposed.quantityMax~=out.quantityMax)) or
            (out.kind=="ENCHANTMENT" and
                proposed.enchantmentID~=out.enchantmentID) then
            return false,"FIELD_OUTPUT_MISMATCH"
        end
        return true,nil
    end
    local maxRowsPerProfession=32768
    local function partial(key,reason,offset,total)
        items.complete=false
        items.status="PARTIAL"
        local rec={professionKey=key,reason=reason,offset=offset,expectedTotal=total,
            source="RecipeReferenceCatalogue.List",requestedBuild=clientBuild}
        items.errors[#items.errors+1]=rec
        return rec
    end
    if type(reference)~="table" or type(reference.List)~="function" or
       type(reg)~="table" or type(reg.GetKeys)~="function" or type(reg.Get)~="function" then
        partial("ALL","PROVIDER_UNAVAILABLE",0,nil)
        return items
    end
    local keyOK,keys=pcall(reg.GetKeys,reg)
    if not keyOK then
        partial("ALL","PROFESSION_REGISTRY_EXCEPTION",0,nil)
        return items
    end
    local keyCount,keyReason=boundedDense(keys,64,false)
    if not keyCount then
        partial("ALL","PROFESSION_KEYS_"..keyReason,0,nil)
        return items
    end
    local seenKeys={}
    for keyIndex=1,keyCount do
        local key=keys[keyIndex]
        if type(key)~="string" or key=="" or seenKeys[key] then
            partial("ALL","PROFESSION_KEY_DUPLICATE_OR_INVALID",0,nil)
            return items
        end
        seenKeys[key]=true
    end
    for keyIndex=1,keyCount do
        local key=keys[keyIndex]
        local defOK,def=pcall(reg.Get,reg,key)
        local offset,total,seen=0,nil,{}
        local localRows={}
        local failure=nil
        local unqualifiedRow=false
        local pages=0
        if not defOK or not (type(def)=="table" and positive(def.skillLineID)) then
            failure=partial(key,defOK and "SKILL_LINE_UNKNOWN" or "PROFESSION_LOOKUP_EXCEPTION",0,nil)
        else
            while offset<maxRowsPerProfession do
                pages=pages+1
                local ok,page=pcall(reference.List,reference,def.skillLineID,"",offset,12,clientBuild)
                if not ok or type(page)~="table" or type(page.rows)~="table" then
                    failure=partial(key,ok and "INVALID_PAGE" or "PROVIDER_EXCEPTION",offset,total)
                    break
                end
                local count,pageReason=boundedDense(page.rows,12,true)
                if not count then
                    failure=partial(key,"PAGE_ROWS_"..pageReason,offset,total)
                    break
                end
                local nextTotal=page.total
                if type(nextTotal)~="number" or nextTotal<0 or nextTotal~=math.floor(nextTotal) or
                   nextTotal==math.huge or nextTotal>maxRowsPerProfession or
                   (count==0 and (offset~=0 or nextTotal~=0)) or
                   offset+count>nextTotal or
                   count~=math.min(12,nextTotal-offset) then
                    failure=partial(key,"NONADVANCING_OR_MALFORMED_PAGE",offset,nextTotal)
                    break
                end
                if page.clientBuild~=nil and page.clientBuild~=clientBuild then
                    failure=partial(key,"PAGE_BUILD_CONFLICT",offset,nextTotal)
                    break
                end
                if total~=nil and nextTotal~=total then
                    failure=partial(key,"TOTAL_CHANGED_DURING_PAGINATION",offset,nextTotal)
                    break
                end
                if page.offset~=nil and page.offset~=offset then
                    failure=partial(key,"PAGE_OFFSET_MISMATCH",offset,nextTotal)
                    break
                end
                -- Optional provider receipts are authoritative NEGATIVE evidence.
                -- Legacy providers may omit them, but a supplied failure cannot
                -- be promoted to COMPLETE by correct row counts/pagination.
                local receiptFailure=nil
                if page.complete~=nil then
                    if type(page.complete)~="boolean" then
                        receiptFailure="PAGE_COMPLETE_MALFORMED"
                    elseif page.complete==false then
                        receiptFailure="PROVIDER_DECLARED_INCOMPLETE"
                    end
                end
                if page.status~=nil then
                    if type(page.status)~="string" or page.status~="COMPLETE" then
                        receiptFailure=receiptFailure or
                            (type(page.status)=="string" and "PROVIDER_STATUS_NOT_COMPLETE" or "PAGE_STATUS_MALFORMED")
                    end
                end
                local providerErrors={}
                if page.errors~=nil then
                    local errorCount,errorReason=boundedDense(page.errors,64,true)
                    if not errorCount then
                        receiptFailure=receiptFailure or "PAGE_ERRORS_"..errorReason
                    else
                        for errorIndex=1,errorCount do
                            local err=page.errors[errorIndex]
                            if type(err)~="table" or type(err.reason)~="string" or
                               err.reason=="" or #err.reason>160 then
                                receiptFailure=receiptFailure or "PAGE_ERROR_ENTRY_MALFORMED"
                                break
                            end
                            providerErrors[#providerErrors+1]={reason=err.reason}
                        end
                        if errorCount>0 then
                            receiptFailure=receiptFailure or "PROVIDER_REPORTED_ERRORS"
                        end
                    end
                end
                total=nextTotal
                local invalid=false
                for i=1,count do
                    local row=page.rows[i]
                    if type(row)~="table" then
                        invalid="INVALID_RECIPE_REAGENTS";break
                    end
                    local reagentCount,reagentReason=boundedDense(row.reagents,256,false)
                    if not reagentCount then
                        invalid="REAGENTS_"..reagentReason;break
                    end
                    if not positive(row.recipeID) or seen[row.recipeID] then
                        invalid="DUPLICATE_OR_INVALID_RECIPE_ID";break
                    end
                    seen[row.recipeID]=true
                    if row.state~="SOURCE_QUALIFIED" then
                        unqualifiedRow=true
                    else
                        -- Client build is informational; qualify actual source fields.
                        local qualified,why=qualifiedRecipeReceipt(key,row,clientBuild,reagentCount)
                        if not qualified then invalid=why;break end
                    end
                    local seenReagents={}
                    for reagentIndex=1,reagentCount do
                        local r=row.reagents[reagentIndex]
                        if type(r)~="table" or not positive(r.itemID) or
                            not positive(r.quantity) or seenReagents[r.itemID] then
                            invalid="DUPLICATE_OR_INVALID_REAGENT";break
                        end
                        seenReagents[r.itemID]=true
                        local existing=localRows[r.itemID]
                        if not existing then
                            existing={itemID=r.itemID,name=r.name,professions={},
                                evidenceState=row.state,sourceBuild=row.sourceBuild,
                                readOnly=true,nativeDispatchAllowed=false,
                                -- Legacy field name preserved: means a
                                -- reviewed source with known build, not equality.
                                buildQualified=row.state=="SOURCE_QUALIFIED" and positive(row.sourceBuild),
                                sourceBuilds=positive(row.sourceBuild) and {row.sourceBuild} or {}}
                            localRows[r.itemID]=existing
                        elseif positive(row.sourceBuild) then
                            -- Build differences alone are not ItemID conflicts.
                            -- Retain all actual source builds without relabeling.
                            local found=false
                            for _,b in ipairs(existing.sourceBuilds or {}) do
                                if b==row.sourceBuild then found=true;break end
                            end
                            if not found then
                                existing.sourceBuilds=existing.sourceBuilds or {}
                                existing.sourceBuilds[#existing.sourceBuilds+1]=row.sourceBuild
                                table.sort(existing.sourceBuilds)
                            end
                        end
                        existing.professions[key]=true
                    end
                    if invalid then break end
                end
                if invalid then failure=partial(key,invalid,offset,total);break end
                if receiptFailure then
                    failure=partial(key,receiptFailure,offset,total)
                    failure.reportedStatus=page.status
                    failure.reportedComplete=page.complete
                    failure.providerErrors=providerErrors
                    break
                end
                offset=offset+count
                if offset==total then break end
            end
            if offset< (total or 0) and not failure then
                failure=partial(key,"BOUNDED_LIMIT_REACHED",offset,total)
            end
            if unqualifiedRow and not failure then
                failure=partial(key,"UNQUALIFIED_ROWS_FOR_BUILD",offset,total)
            end
        end
        items.professions[key]={status=failure and "PARTIAL" or "COMPLETE",complete=failure==nil,
            count=offset,total=total,numberOfPages=pages,
            reason=failure and failure.reason or nil}
        -- Preserve observed identities as advisory when partial. Do not let a
        -- partial source become SOURCE_QUALIFIED in a downstream decision.
        for id,material in pairs(localRows) do
            local existing=byID[id]
            if not existing then
                existing=material
                byID[id]=existing;items[#items+1]=existing
            else
                existing.professions[key]=true
                -- Merge provenanced source builds; different builds for the
                -- same ItemID are not evidence of changed item identity.
                for _,b in ipairs(material.sourceBuilds or {}) do
                    local found=false
                    for _,prior in ipairs(existing.sourceBuilds or {}) do
                        if prior==b then found=true;break end
                    end
                    if not found then
                        existing.sourceBuilds=existing.sourceBuilds or {}
                        existing.sourceBuilds[#existing.sourceBuilds+1]=b
                    end
                end
                table.sort(existing.sourceBuilds)
                if material.evidenceState~="SOURCE_QUALIFIED" then
                    existing.evidenceState="PARTIAL"
                end
            end
            if failure then
                existing.indexComplete=false
                existing.evidenceState="PARTIAL"
            elseif existing.indexComplete~=false then
                existing.indexComplete=true
            end
        end
    end
    if not items.complete then
        -- Completeness is a property of the entire bounded source snapshot.
        -- A valid-looking entry must never escape as a complete material index
        -- while another profession/page was corrupted or unavailable.
        for _,material in ipairs(items) do
            material.indexComplete=false
            material.evidenceState="PARTIAL"
        end
    end
    -- Scanning can call several providers. A client update or interface
    -- transition DURING pagination must revoke the initial LIVE receipt.
    -- Static material/source records remain readable as historical reference.
    if observedClientToken then
        local client=JLP:GetModule("ClientBuildInfo")
        local ok,info=false,nil
        if client and type(client.Read)=="function" then
            ok,info=pcall(client.Read,client)
        end
        if not ok or type(info)~="table" or info.known~=true or
            info.buildNumber~=clientBuild or info.token~=observedClientToken then
            items.liveClientVerified=false
            items.liveClientToken=nil
            items.clientObservationStatus="CLIENT_SESSION_CHANGED_DURING_INDEX"
        end
    end
    -- Reflect only source-build identities actually present in indexed rows.
    local sourceSet={}
    for _,material in ipairs(items) do
        for _,sourceBuild in ipairs(material.sourceBuilds or {}) do
            if positive(sourceBuild) then sourceSet[sourceBuild]=true end
        end
    end
    for sourceBuild in pairs(sourceSet) do
        items.sourceBuilds[#items.sourceBuilds+1]=sourceBuild
    end
    table.sort(items.sourceBuilds)
    table.sort(items,function(a,b) return a.itemID<b.itemID end)
    return items
end

-- Shared gathering source envelope. It delegates to the existing bounded
-- registry: no new node decoding, new route authority, or live spawn assertion.
function Catalogue:GetGatheringReferenceCoverage(key,mapID,clientBuild)
    if key~="HERBALISM" and key~="MINING" and key~="SKINNING" and key~="FISHING" then
        return nil,"NOT_GATHERING_PROFESSION"
    end
    if not positive(mapID) then return nil,"MAP_ID_INVALID" end
    local registry=JLP:GetModule("GatheringDataRegistry")
    if type(registry)~="table" or type(registry.GetZoneResourceSummary)~="function" then
        return nil,"GATHERING_REFERENCE_UNAVAILABLE"
    end
    local ok,summary=pcall(registry.GetZoneResourceSummary,registry,mapID,key)
    if not ok or type(summary)~="table" then return nil,"GATHERING_REFERENCE_ERROR" end
    local out=safeCopy(summary)
    out.evidenceState="CANDIDATE" -- historical source is NOT 70374-verified
    out.sourceBuild=nil
    out.requestedBuild=positive(clientBuild) and clientBuild or nil
    out.buildEvidenceState=positive(clientBuild) and "EXPLICIT_CLIENT_BUILD" or "CLIENT_BUILD_UNKNOWN"
    out.productionAuthority="NOT_AUTHORIZED"
    out.nativeDispatchAllowed=false
    out.referenceOnly=true
    out.spatialPrecision="HISTORICAL_REFERENCE_UNCERTAIN"
    return out,nil
end
-- Explicitly separate PAGE-CLAIMED research leads from qualified runtime
-- recipe identities. In particular they never enter GetRecipe/ForPlanStep,
-- acquisition, reagent indexes or the native planner authority.
function Catalogue:GetResearchCandidates(key,clientBuild)
    if not metadata(key) then return nil,"UNKNOWN_PROFESSION" end
    local data=JLP.data and JLP.data.professionsCatalogueResearchCandidates
    local out={}
    for _,row in ipairs(data and data.rows or {}) do
        if row.professionKey==key then
            local candidate=safeCopy(row)
            candidate.state="CANDIDATE"
            candidate.evidenceState="CANDIDATE"
            candidate.requestedBuild=positive(clientBuild) and clientBuild or nil
            candidate.qualificationReason="REQUIRES_ID_FIELD_PROVENANCE_RIGHTS_AND_BUILD_REVIEW"
            candidate.productionAuthority=false
            candidate.executionEligible=false
            candidate.nativeDispatchAllowed=false
            candidate.readOnly=true
            out[#out+1]=candidate
        end
    end
    return out,nil
end
function Catalogue:GetCoverage()
    local admission=JLP:GetModule("ProfessionsCatalogueQualification")
    local audit=admission and admission:AssessInstalled() or nil
    local result={contract=self.contract,profession={},staticIDs=0,researchNames=0,
        nativeDispatchAllowed=false,externalBulkImported=0,productionPromotions=0,
        schemaVersion=2,qualified70374=0,productionAuthorized=0,
        newResearchCandidateSpellIDs=0,sourceRightsState="REVIEW_PENDING",
        catalogueAdmission=audit and safeCopy(audit) or nil}
    local reg=JLP:GetModule("ProfessionRegistry")
    local ref=JLP:GetModule("RecipeReferenceCatalogue")
    local coverage=ref and ref:GetCoverage() or {bySkill={}}
    result.staticIDs=coverage.distinct or 0
    result.qualified70374=coverage.independentlyQualified70374 or 0
    for _,key in ipairs(reg and reg:GetKeys() or {}) do
        local def=reg:Get(key)
        local names=researchRecords(key)
        local candidates=self:GetResearchCandidates(key,nil)
        result.newResearchCandidateSpellIDs=result.newResearchCandidateSpellIDs+#candidates
        local statics=coverage.bySkill and coverage.bySkill[def.skillLineID] or 0
        result.profession[key]={skillLineID=def.skillLineID,staticRecipeIDs=statics or 0,
            researchNames=#names,newResearchCandidateSpellIDs=#candidates,
            independentlyQualified70374=coverage.qualifiedBySkill and
                (coverage.qualifiedBySkill[def.skillLineID] or 0) or 0,
            qualifiedAcquisition70374=coverage.acquisitionBySkill and
                (coverage.acquisitionBySkill[def.skillLineID] or 0) or 0,
            newQualifiedIdentityNet70374=coverage.qualifiedBySkill and
                (coverage.qualifiedBySkill[def.skillLineID] or 0) or 0,
            productionAuthorized=0,source="LOCAL_JLP_CURATED_AND_USER_RESEARCH",
            productionAuthority="SEPARATE_EXISTING_GATES"}
        result.researchNames=result.researchNames+#names
    end
    return result
end
-- M2 catalogue-to-consumer contract: a bounded, typed view over ALL existing
-- JLP recipe identities. This is deliberately NOT a Recipe Reference UI page.
-- An owner-authorized trainer LOCATION is not evidence that a specific recipe
-- is trainer-taught, learned, or native-dispatchable.
local function fieldState(row,field)
    local p=type(row.fieldProvenance)=="table" and row.fieldProvenance[field] or nil
    if type(p)=="table" and p.state=="CONFLICT" then return "CONFLICT" end
    if row.state=="CONFLICT" then return "CONFLICT" end
    if row.verifiedFieldSet==true and row.state=="SOURCE_QUALIFIED" and
       type(p)=="table" and p.state=="SOURCE_QUALIFIED" then
        return "SOURCE_QUALIFIED"
    end
    if field=="acquisition" and row.verifiedAcquisition~=true then return "UNKNOWN" end
    if type(p)=="table" and p.state=="CANDIDATE" then return "PARTIAL" end
    return "UNKNOWN"
end
function Catalogue:GetRecipeFieldReceipt(key,recipeID,clientBuild)
    if not metadata(key) or not positive(recipeID) then return nil,"INVALID_RECIPE_ID" end
    local row,reason=self:GetRecipe(key,recipeID,clientBuild)
    if not row then return nil,reason or "RECIPE_ID_UNKNOWN" end
    local fields={}
    for _,field in ipairs({"identity","reagents","output","requiredSkill","difficulty","acquisition"}) do
        fields[field]=fieldState(row,field)
    end
    local fullyQualified=row.verifiedFieldSet==true and
        fields.identity=="SOURCE_QUALIFIED" and
        fields.reagents=="SOURCE_QUALIFIED" and
        fields.output=="SOURCE_QUALIFIED" and
        fields.requiredSkill=="SOURCE_QUALIFIED" and
        positive(row.sourceBuild)
    -- Reference receipts inherit independent field/rights qualification from
    -- RecipeReferenceCatalogue. A different or unavailable requested client
    -- build is provenance, not evidence of a field conflict. Keep dynamic
    -- learned/stock/production/native controls separate and unchanged.
    local reagents={}
    for _,r in ipairs(row.reagents or {}) do
        if not positive(r.itemID) or not positive(r.quantity) then
            return nil,"INVALID_REAGENT_RECORD"
        end
        reagents[#reagents+1]={itemID=r.itemID,quantity=r.quantity,name=r.name,
            usableForPlan=fullyQualified==true}
    end
    return {contract="JLP-CATALOGUE-RECIPE-FIELDS-1",professionKey=key,
        recipeID=row.recipeID,spellID=row.spellID,name=row.name,
        state=row.state=="CONFLICT" and "CONFLICT" or
            (fullyQualified and "SOURCE_QUALIFIED" or "PARTIAL"),
        fields=fields,sourceBuild=row.sourceBuild,
        clientBuild=positive(clientBuild) and clientBuild or nil,
        buildMatches=positive(clientBuild) and row.sourceBuild==clientBuild or false,
        identityType="SPELL",reagents=reagents,
        output=type(row.output)=="table" and safeCopy(row.output) or nil,
        requiredSkill=row.requirements and row.requirements.skill or nil,
        difficulty=type(row.difficulty)=="table" and safeCopy(row.difficulty) or nil,
        -- Acquisition requires a SEPARATE actor and faction qualification.
        acquisition=fields.acquisition=="SOURCE_QUALIFIED" and
            safeCopy(row.acquisition) or nil,
        sourceQualified=fullyQualified==true,
        staticRecipeComplete=fullyQualified==true,
        learnedState="UNKNOWN",inventoryState="UNKNOWN",
        hardwareState="REQUIRES_EXISTING_NATIVE_GATES",
        nativeDispatchAllowed=false,executionEligible=false,
        productionAuthority="SEPARATE_EXISTING_GATES",readOnly=true},nil
end
-- All Horde trainer/rank rows already owner-authorized in the internal
-- navigation producer, joined without inventing recipe-teaching actor IDs.
function Catalogue:GetOwnerHordeTrainers(key,rank)
    if not metadata(key) then return nil,"UNKNOWN_PROFESSION" end
    local owner=JLP:GetModule("OwnerAuthorizedNavigation")
    if type(owner)~="table" or type(owner.GetServiceList)~="function" or
        type(owner.GetWaypoint)~="function" then
        return nil,"OWNER_TRAINER_PRODUCER_UNAVAILABLE"
    end
    local ok,list=pcall(owner.GetServiceList,owner,"TRAINER")
    if not ok or type(list)~="table" then return nil,"OWNER_TRAINER_SOURCE_ERROR" end
    local out,seen={},{}
    for _,entry in ipairs(list) do
        if type(entry)=="table" and entry.profession==key and
            (rank==nil or entry.rank==rank) then
            local id=entry.serviceID
            if type(id)~="string" or id=="" or seen[id] then
                return nil,"OWNER_TRAINER_DUPLICATE_OR_INVALID_ID"
            end
            seen[id]=true
            local valid,waypoint=pcall(owner.GetWaypoint,owner,"TRAINER",id)
            local canonical=valid and type(waypoint)=="table" and waypoint or nil
            local matched=canonical and canonical.serviceID==id and
                canonical.profession==key and canonical.rank==entry.rank and
                canonical.name==entry.name and canonical.sourceQualified==true and
                canonical.state=="SOURCE_QUALIFIED"
            local record={serviceID=id,professionKey=key,name=entry.name,
                rank=entry.rank,faction="Horde",actorID=nil,recipeID=nil,
                trainerLocationState=matched and "OWNER_PRODUCTION_AUTHORIZED" or "UNKNOWN",
                recipeAcquisitionState="UNKNOWN",nativeDispatchAllowed=false,
                learnedState="UNKNOWN",readOnly=true}
            if matched then
                local nav=canonical.nav
                if type(nav)=="table" and positive(nav.mapID) and
                    type(nav.x)=="number" and type(nav.y)=="number" and
                    nav.x>=0 and nav.x<=1 and nav.y>=0 and nav.y<=1 and
                    nav.mapDomain=="UI_MAP_ID" then
                    record.nav={mapID=nav.mapID,x=nav.x,y=nav.y,mapDomain="UI_MAP_ID"}
                    record.sourceSHA=canonical.sourceSHA
                    record.sourceRow=canonical.sourceRow
                else
                    record.trainerLocationState="UNKNOWN"
                end
            end
            -- Skill/character rank requirements are already JLP-owned v1
            -- research. They must not be mistaken for a recipe's skill gate.
            local resolver=JLP:GetModule("SourceResolver")
            if resolver and type(resolver.GetRankRequirement)=="function" then
                local titleRank=type(entry.rank)=="string" and
                    (entry.rank:sub(1,1)..entry.rank:sub(2):lower()) or entry.rank
                local rankOK,required=pcall(resolver.GetRankRequirement,resolver,key,titleRank)
                if rankOK and type(required)=="table" then
                    record.rankRequirement=safeCopy(required)
                end
            end
            out[#out+1]=record
        end
    end
    table.sort(out,function(a,b)
        if a.rank~=b.rank then return tostring(a.rank)<tostring(b.rank) end
        return a.serviceID<b.serviceID
    end)
    return out,nil
end
-- Index for existing Guide/Planner/Materials/Source consumers; references are
-- reported separately from complete production recipes. No state mutation.
function Catalogue:GetProfessionRecipeIndex(key,offset,pageSize,clientBuild)
    local _,skill=metadata(key)
    if not skill then return nil,"UNKNOWN_PROFESSION" end
    offset=offset or 0;pageSize=pageSize or 12
    if type(offset)~="number" or offset<0 or offset~=math.floor(offset) or
        type(pageSize)~="number" or pageSize<1 or pageSize>12 or
        pageSize~=math.floor(pageSize) then return nil,"INVALID_PAGE" end
    local ref=JLP:GetModule("RecipeReferenceCatalogue")
    if type(ref)~="table" or type(ref.List)~="function" then
        return nil,"RECIPE_REFERENCE_PROVIDER_UNAVAILABLE"
    end
    local ok,page,reason=pcall(ref.List,ref,skill,"",offset,pageSize,
        positive(clientBuild) and clientBuild or false)
    if not ok then return nil,"RECIPE_REFERENCE_PROVIDER_EXCEPTION" end
    if type(page)~="table" or type(page.rows)~="table" then
        return nil,reason or "INVALID_RECIPE_REFERENCE_PAGE"
    end
    if type(page.total)~="number" or page.total<0 or page.total>32768 or
        page.total~=math.floor(page.total) or offset>page.total+pageSize or
        (page.offset~=nil and page.offset~=offset) or
        (page.clientBuild~=nil and page.clientBuild~=clientBuild) then
        return nil,"INVALID_RECIPE_PAGE_BOUNDS"
    end
    local count,denseReason=boundedDense(page.rows,pageSize,true)
    if not count then return nil,"RECIPE_PAGE_"..denseReason end
    if count~=math.min(pageSize,math.max(0,page.total-offset)) then
        return nil,"RECIPE_PAGE_COUNT_MISMATCH"
    end
    local rows={};local seen={}
    for _,raw in ipairs(page.rows) do
        local id=raw and raw.recipeID
        if not positive(id) or seen[id] or raw.professionKey~=key then
            return nil,"RECIPE_PAGE_ID_CONFLICT"
        end
        seen[id]=true
        local receipt,why=self:GetRecipeFieldReceipt(key,id,clientBuild)
        if not receipt then return nil,"RECIPE_PAGE_"..tostring(why) end
        if receipt.name~=raw.name or receipt.sourceBuild~=raw.sourceBuild then
            return nil,"RECIPE_PAGE_CHANGED_DURING_LOOKUP"
        end
        rows[#rows+1]=receipt
    end
    return {contract="JLP-CATALOGUE-PROFESSION-RECIPE-PAGE-1",
        professionKey=key,skillLineID=skill,rows=rows,total=page.total,
        offset=offset,pageSize=pageSize,sourceBuild=positive(clientBuild) and clientBuild or nil,
        indexKind="EXISTING_CURATED_STATIC_IDS",complete=true,
        qualifiedFullRecipeCount=0, -- page-local counters; not total coverage
        nativeDispatchAllowed=false,readOnly=true},nil
end
function Catalogue:GetProfessionDataSnapshot(key,clientBuild)
    if not metadata(key) then return nil,"UNKNOWN_PROFESSION" end
    -- A single-step planner must not scan all twelve professions on every
    -- refresh, nor require GetKeys from a minimal/test registry.
    local _,skill=metadata(key)
    local reference=JLP:GetModule("RecipeReferenceCatalogue")
    local coverage=reference and type(reference.GetCoverage)=="function" and
        reference:GetCoverage() or nil
    local names=researchRecords(key)
    local candidates=self:GetResearchCandidates(key,clientBuild)
    local c={skillLineID=skill,
        staticRecipeIDs=coverage and coverage.bySkill and coverage.bySkill[skill] or 0,
        independentlyQualified70374=coverage and coverage.qualifiedBySkill and
            coverage.qualifiedBySkill[skill] or 0,
        researchNames=#names,newResearchCandidateSpellIDs=#(candidates or {})}
    local trainers,why=self:GetOwnerHordeTrainers(key)
    local qualifiedTrainerCount=0
    for _,trainer in ipairs(trainers or {}) do
        if trainer.trainerLocationState=="OWNER_PRODUCTION_AUTHORIZED" and
            type(trainer.nav)=="table" then qualifiedTrainerCount=qualifiedTrainerCount+1 end
    end
    local progression=self:GetProgressionReferences(key)
    local raw70374=JLP:GetModule("Build70374ProfessionReference")
    local sourceCoverage=raw70374 and raw70374:GetCoverage() or nil
    local rawForKey=sourceCoverage and sourceCoverage.byProfession and sourceCoverage.byProfession[key]
    return {contract="JLP-CATALOGUE-PROFESSION-SNAPSHOT-1",
        professionKey=key,skillLineID=c.skillLineID,
        staticRecipeIDs=c.staticRecipeIDs or 0,
        rawBuild70374AbilityRows=rawForKey and rawForKey.skillLineAbilityRows or 0,
        rawBuild70374ReagentRows=rawForKey and rawForKey.reagentRecordRows or 0,
        rawBuild70374OutputRows=rawForKey and rawForKey.outputEffectRows or 0,
        rawBuild70374Status="RAW_OWNER_CSV_REFERENCE_ONLY",
        newlyQualifiedRecipeIDs=c.independentlyQualified70374 or 0,
        researchNameLeads=c.researchNames or 0,
        progressionReferenceRows=progression and #progression.rows or 0,
        progressionReferenceStatus=progression and progression.status or "UNKNOWN",
        rawCandidateSpellIDs=c.newResearchCandidateSpellIDs or 0,
        ownerTrainers=type(trainers)=="table" and #trainers or 0,
        ownerTrainersWithLocation=qualifiedTrainerCount,
        trainerSourceState=trainers and "OWNER_PRODUCTION_AUTHORIZED" or "UNKNOWN",
        trainerSourceReason=why,recipeCompletionState="PARTIAL",
        allRecipesImplemented=false,requestedClientBuild=positive(clientBuild) and clientBuild or nil,
        learnedState="CHARACTER_SPECIFIC_UNOBSERVED",
        gatheringReferenceState=(key=="HERBALISM" or key=="MINING" or
            key=="SKINNING" or key=="FISHING") and "REQUIRES_MAP_CONTEXT" or "NOT_APPLICABLE",
        productionAuthority="SEPARATE_EXISTING_GATES",nativeDispatchAllowed=false,
        readOnly=true},nil
end
-- Shared progression evidence across existing profession/gathering research.
-- Skill bands and guide shopping totals are NOT recipe IDs or per-craft input.
function Catalogue:GetProgressionReferences(key)
    if not metadata(key) then return nil,"UNKNOWN_PROFESSION" end
    local source=nil;local rows={};local kind="UNKNOWN"
    if key=="MINING" then
        source=JLP.data and JLP.data.foreverMiningSmeltingBands
        kind="SMELTING_NAME_ONLY_BANDS"
        for _,band in ipairs(source and source.entries or {}) do
            if type(band)=="table" and type(band.label)=="string" and
                type(band.from)=="number" and type(band.to)=="number" and
                band.from>=0 and band.to>band.from then
                local materials={}
                for _,m in ipairs(band.materials or {}) do
                    if type(m.name)=="string" and m.name~="" then
                        materials[#materials+1]={name=m.name,itemID=nil,
                            perCraftQuantity=nil,sourceCount=m.count,
                            quantityQualification="NAME_ONLY_REFERENCE"}
                    end
                end
                rows[#rows+1]={name=band.label,from=band.from,to=band.to,
                    spellID=nil,recipeID=nil,materials=materials,
                    sourceState="CANDIDATE",executionEligible=false}
            end
        end
    elseif key=="COOKING" or key=="FIRST_AID" then
        source=JLP.data and JLP.data.foreverSecondaryLeveling
        local group=source and source.professions and source.professions[key]
        kind="LEVELING_ROUTE_GUIDE_ESTIMATES"
        for _,step in ipairs(group and group.steps or {}) do
            if type(step)=="table" and type(step.recipe)=="string" then
                rows[#rows+1]={name=step.recipe,from=step.skillMin,to=step.skillMax,
                    spellID=nil,recipeID=nil,estimatedCrafts=step.estimatedCrafts,
                    requiredForPlan=nil,sourceState="CANDIDATE",executionEligible=false}
            end
        end
    elseif key=="FISHING" then
        source=JLP.data and JLP.data.foreverSecondaryLeveling
        local fishing=source and source.fishing
        kind="FISHING_SKILL_REFERENCE_NOT_WAYPOINTS"
        for _,tier in ipairs(fishing and fishing.tiers or {}) do
            rows[#rows+1]={name=tier.zone,from=tier.skillMin,to=tier.skillMax,
                minSkill=tier.minSkill,guaranteedCatchSkill=tier.guaranteedCatchSkill,
                mapID=nil,x=nil,y=nil,recipeID=nil,sourceState="CANDIDATE",
                executionEligible=false}
        end
    end
    return {contract="JLP-CATALOGUE-PROGRESSION-REFERENCE-1",
        professionKey=key,referenceType=kind,rows=rows,sourceAvailable=source~=nil,
        status=source and "PARTIAL" or "UNKNOWN",nativeDispatchAllowed=false,
        mapNavigationAuthorized=false,recipeQualification=false,readOnly=true},nil
end
-- Optional build-pinned M2 consumer APIs. All return RAW_OWNER_CSV receipts,
-- never SOURCE_QUALIFIED or an authority to perform native craft actions.
function Catalogue:GetBuild70374Recipe(key,spellID,build)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetRecipe(key,spellID,build)
end
function Catalogue:GetBuild70374Page(key,offset,pageSize,build,kind)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetPage(key,offset,pageSize,build,kind)
end
function Catalogue:GetBuild70374MaterialNeeds(key,spellID,crafts,build)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetMaterialRequirements(key,spellID,crafts,build)
end
function Catalogue:GetBuild70374Item(itemID,build)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetItem(itemID,build)
end
function Catalogue:GetBuild70374Coverage()
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetCoverage()
end
function Catalogue:GetBuild70374RecipeAccessItemCandidates(key,id,build)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetRecipeAccessItemCandidates(key,id,build)
end
function Catalogue:GetBuild70374MaterialVendorResearch(key,itemID,build)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetMaterialVendorResearch(key,itemID,build)
end
function Catalogue:GetBuild70374Trainers(key)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetKnownTrainers(key)
end
function Catalogue:GetBuild70374RecipeSourceResearch(key,id,build)
    local raw=JLP:GetModule("Build70374ProfessionReference")
    if not raw then return nil,"BUILD70374_SOURCE_UNAVAILABLE" end
    return raw:GetRecipeSourceResearch(key,id,build)
end
-- M3 cross-profession cost/material/progression façade; all remain advisory.
function Catalogue:GetBuild70374Economics(key,spellID,crafts,build,options)
    local e=JLP:GetModule("ProfessionEconomy70374")
    if not e then return nil,"ECONOMICS_UNAVAILABLE" end
    return e:QuoteRecipe(key,spellID,crafts,build,options)
end
function Catalogue:GetBuild70374MultiRecipeMaterials(steps,build,options)
    local e=JLP:GetModule("ProfessionEconomy70374")
    if not e then return nil,"ECONOMICS_UNAVAILABLE" end
    return e:BuildBill(steps,build,options)
end
function Catalogue:GetBuild70374ProgressionCandidates(key,skill,build,offset,limit)
    local e=JLP:GetModule("ProfessionEconomy70374")
    if not e then return nil,"ECONOMICS_UNAVAILABLE" end
    return e:GetProgressionCandidates(key,skill,build,offset,limit)
end
-- M4 consistent cross-module, live-build-gated read-only façade.
-- Separate from GetRecipe() / live-client production qualification.
function Catalogue:GetProfessionCommunication70374(key,options)
    local bridge=JLP:GetModule("ProfessionDataBridge70374")
    if not bridge then return nil,"COMMUNICATION_BRIDGE_UNAVAILABLE" end
    return bridge:GetProfessionState(key,options)
end
function Catalogue:GetRecipeCommunication70374(key,spellID,crafts,options)
    local bridge=JLP:GetModule("ProfessionDataBridge70374")
    if not bridge then return nil,"COMMUNICATION_BRIDGE_UNAVAILABLE" end
    return bridge:GetRecipeState(key,spellID,crafts,options)
end
function Catalogue:GetMaterialsCommunication70374(steps,options)
    local bridge=JLP:GetModule("ProfessionDataBridge70374")
    if not bridge then return nil,"COMMUNICATION_BRIDGE_UNAVAILABLE" end
    return bridge:BuildMaterialsState(steps,options)
end
function Catalogue:GetProgressionCommunication70374(key,skill,options)
    local bridge=JLP:GetModule("ProfessionDataBridge70374")
    if not bridge then return nil,"COMMUNICATION_BRIDGE_UNAVAILABLE" end
    return bridge:GetProgressionState(key,skill,options)
end
-- Provenance-aware, read-only communications: source selection is not tied
-- to the running client. Legacy *70374 methods still require explicit source ID.
local function versionedCommunication()
    local bridge=JLP:GetModule("ProfessionDataCommunication")
    return bridge
end
function Catalogue:GetProfessionCommunication(key,options)
    local b=versionedCommunication()
    if not b then return nil,"VERSIONED_COMMUNICATION_UNAVAILABLE" end
    return b:GetProfessionState(key,options)
end
function Catalogue:GetRecipeCommunication(key,spellID,crafts,options)
    local b=versionedCommunication()
    if not b then return nil,"VERSIONED_COMMUNICATION_UNAVAILABLE" end
    return b:GetRecipeState(key,spellID,crafts,options)
end
function Catalogue:GetMaterialsCommunication(steps,options)
    local b=versionedCommunication()
    if not b then return nil,"VERSIONED_COMMUNICATION_UNAVAILABLE" end
    return b:BuildMaterialsState(steps,options)
end
function Catalogue:GetProgressionCommunication(key,skill,options)
    local b=versionedCommunication()
    if not b then return nil,"VERSIONED_COMMUNICATION_UNAVAILABLE" end
    return b:GetProgressionState(key,skill,options)
end
function Catalogue:ValidateCommunicationState(state)
    local b=versionedCommunication()
    if not b then return false,"VERSIONED_COMMUNICATION_UNAVAILABLE" end
    return b:ValidateState(state)
end
function Catalogue:GetProfessionCommunication70450(key,options)
    options=type(options)=="table" and options or {}
    if options.sourceBuild~=nil and options.sourceBuild~=70450 then
        return nil,"SOURCE_BUILD_MISMATCH"
    end
    local forwarded={}
    for k,v in pairs(options) do forwarded[k]=v end
    forwarded.sourceBuild=70450
    return self:GetProfessionCommunication(key,forwarded)
end
function Catalogue:GetRecipeCommunication70450(key,spellID,crafts,options)
    options=type(options)=="table" and options or {}
    if options.sourceBuild~=nil and options.sourceBuild~=70450 then
        return nil,"SOURCE_BUILD_MISMATCH"
    end
    local forwarded={}
    for k,v in pairs(options) do forwarded[k]=v end
    forwarded.sourceBuild=70450
    return self:GetRecipeCommunication(key,spellID,crafts,forwarded)
end
function Catalogue:GetMaterialsCommunication70450(steps,options)
    options=type(options)=="table" and options or {}
    if options.sourceBuild~=nil and options.sourceBuild~=70450 then
        return nil,"SOURCE_BUILD_MISMATCH"
    end
    local forwarded={}
    for k,v in pairs(options) do forwarded[k]=v end
    forwarded.sourceBuild=70450
    return self:GetMaterialsCommunication(steps,forwarded)
end
function Catalogue:GetProgressionCommunication70450(key,skill,options)
    options=type(options)=="table" and options or {}
    if options.sourceBuild~=nil and options.sourceBuild~=70450 then
        return nil,"SOURCE_BUILD_MISMATCH"
    end
    local forwarded={}
    for k,v in pairs(options) do forwarded[k]=v end
    forwarded.sourceBuild=70450
    return self:GetProgressionCommunication(key,skill,forwarded)
end
-- M6 build-70450 classification and recipe identity reference. All calls are read-only.
-- Never promote these rows into the older protected crafting or economics gates.
function Catalogue:GetBuild70450Recipe(key,spellID,sourceBuild)
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then return nil,"BUILD70450_CATALOGUE_UNAVAILABLE" end
    return ref:GetRecipe(key,spellID,sourceBuild)
end
function Catalogue:GetBuild70450Page(key,offset,limit,sourceBuild,options)
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then return nil,"BUILD70450_CATALOGUE_UNAVAILABLE" end
    return ref:GetPage(key,offset,limit,sourceBuild,options)
end
function Catalogue:GetBuild70450Materials(key,spellID,crafts,sourceBuild)
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then return nil,"BUILD70450_CATALOGUE_UNAVAILABLE" end
    return ref:GetMaterialNeeds(key,spellID,crafts,sourceBuild)
end
function Catalogue:GetBuild70450Coverage()
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then return nil,"BUILD70450_CATALOGUE_UNAVAILABLE" end
    return ref:GetCoverage()
end
function Catalogue:GetBuild70450MissingFrom70374()
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then return nil,"BUILD70450_CATALOGUE_UNAVAILABLE" end
    return ref:GetMissingFrom70374()
end
-- M7 build 70450 output/yield reference. These data never authorize a craft
-- or upgrade the source-only SpellEffect base into a confirmed server result.
function Catalogue:GetBuild70450CraftOutput(key,spellID,crafts,sourceBuild)
    local service=JLP:GetModule("Build70450CraftOutput")
    if not service then return nil,"BUILD70450_OUTPUT_UNAVAILABLE" end
    return service:GetRecipeOutput(key,spellID,crafts,sourceBuild)
end
function Catalogue:GetBuild70450OutputAndMaterials(key,spellID,crafts,sourceBuild)
    local service=JLP:GetModule("Build70450CraftOutput")
    if not service then return nil,"BUILD70450_OUTPUT_UNAVAILABLE" end
    return service:GetOutputWithMaterials(key,spellID,crafts,sourceBuild)
end
function Catalogue:GetBuild70450LiveTradeSkillYield(key,spellID,index,crafts,sourceBuild)
    local service=JLP:GetModule("Build70450CraftOutput")
    if not service then return nil,"CRAFT_OUTPUT_UNAVAILABLE" end
    return service:GetClientTradeSkillYield(key,spellID,index,crafts,sourceBuild)
end
function Catalogue:GetBuild70450OutputCoverage()
    local service=JLP:GetModule("Build70450CraftOutput")
    if not service then return nil,"BUILD70450_OUTPUT_UNAVAILABLE" end
    return service:GetCoverage()
end
-- M8: source-exact, two-field difficulty reference; no computed orange/green bands.
function Catalogue:GetBuild70450Difficulty(key,spellID,sourceBuild)
    local service=JLP:GetModule("Build70450SkillDifficulty")
    if not service then return nil,"BUILD70450_DIFFICULTY_UNAVAILABLE" end
    return service:GetDifficulty(key,spellID,sourceBuild)
end
function Catalogue:GetBuild70450DifficultyAtSkill(key,spellID,skill,sourceBuild)
    local service=JLP:GetModule("Build70450SkillDifficulty")
    if not service then return nil,"BUILD70450_DIFFICULTY_UNAVAILABLE" end
    return service:GetAtSkill(key,spellID,skill,sourceBuild)
end
function Catalogue:GetBuild70450LiveDifficultyColor(key,spellID,index,sourceBuild)
    local service=JLP:GetModule("Build70450SkillDifficulty")
    if not service then return nil,"BUILD70450_DIFFICULTY_UNAVAILABLE" end
    return service:GetLiveTradeSkillColor(key,spellID,index,sourceBuild)
end
function Catalogue:GetBuild70450DifficultyCoverage()
    local service=JLP:GetModule("Build70450SkillDifficulty")
    if not service then return nil,"BUILD70450_DIFFICULTY_UNAVAILABLE" end
    return service:GetCoverage()
end
-- M9: item metadata and relation evidence from owner-provided build 70450 snapshot.
-- Never infer NPC/vendor/trainer/drop acquisition from buy prices or spell links.
function Catalogue:GetBuild70450ItemMetadata(itemID,sourceBuild)
    local m=JLP:GetModule("Build70450ItemMetadata")
    if not m then return nil,"BUILD70450_ITEM_METADATA_UNAVAILABLE" end
    return m:GetItem(itemID,sourceBuild)
end
function Catalogue:GetBuild70450ItemRelations(itemID,offset,limit,sourceBuild)
    local m=JLP:GetModule("Build70450ItemMetadata")
    if not m then return nil,"BUILD70450_ITEM_METADATA_UNAVAILABLE" end
    return m:GetRelations(itemID,offset,limit,sourceBuild)
end
function Catalogue:GetBuild70450ItemMetadataPage(offset,limit,sourceBuild,options)
    local m=JLP:GetModule("Build70450ItemMetadata")
    if not m then return nil,"BUILD70450_ITEM_METADATA_UNAVAILABLE" end
    return m:GetPage(offset,limit,sourceBuild,options)
end
function Catalogue:GetBuild70450ItemMetadataCoverage()
    local m=JLP:GetModule("Build70450ItemMetadata")
    if not m then return nil,"BUILD70450_ITEM_METADATA_UNAVAILABLE" end
    return m:GetCoverage()
end
-- M9 client-only, non-persistent, item-ID-validated hyperlink observation.
function Catalogue:GetBuild70450ClientItemLink(itemID,sourceBuild)
    local m=JLP:GetModule("Build70450ItemMetadata")
    if not m then return nil,"BUILD70450_ITEM_METADATA_UNAVAILABLE" end
    return m:GetClientItemLink(itemID,sourceBuild)
end
function Catalogue:RequestBuild70450ClientItemData(itemID,sourceBuild)
    local m=JLP:GetModule("Build70450ItemMetadata")
    if not m then return nil,"BUILD70450_ITEM_METADATA_UNAVAILABLE" end
    return m:RequestClientItemData(itemID,sourceBuild)
end
function Catalogue:ScanBuild70450MissingItemNames(offset,sourceBuild)
    local m=JLP:GetModule("Build70450ItemMetadata")
    if not m then return nil,"BUILD70450_ITEM_METADATA_UNAVAILABLE" end
    return m:ScanMissingNames(offset,sourceBuild)
end
-- M10: exact teaching-item references and conservatively qualified source research.
-- Common M15 read-only consumer of current-build reagents, item identities,
-- observed storage, acquisition reference and raw output status.
function Catalogue:GetBuild70450MaterialsSources(key,spellID,crafts,sourceBuild)
    local service=JLP:GetModule("MaterialsSources70450")
    if not service then return nil,"MATERIALS_SOURCES_REFERENCE_UNAVAILABLE" end
    return service:GetRecipe(key,spellID,crafts,sourceBuild)
end
function Catalogue:GetBuild70450RecipeAcquisition(key,spellID,sourceBuild)
    local m=JLP:GetModule("Build70450RecipeAcquisition")
    if not m then return nil,"BUILD70450_ACQUISITION_UNAVAILABLE" end
    return m:GetRecipeSources(key,spellID,sourceBuild)
end
function Catalogue:GetBuild70450AcquisitionPage(key,offset,limit,sourceBuild)
    local m=JLP:GetModule("Build70450RecipeAcquisition")
    if not m then return nil,"BUILD70450_ACQUISITION_UNAVAILABLE" end
    return m:GetPage(key,offset,limit,sourceBuild)
end
function Catalogue:GetBuild70450AcquisitionCoverage()
    local m=JLP:GetModule("Build70450RecipeAcquisition")
    if not m then return nil,"BUILD70450_ACQUISITION_UNAVAILABLE" end
    return m:GetCoverage()
end
JLP:RegisterModule("ProfessionsDataCatalogue",Catalogue)
