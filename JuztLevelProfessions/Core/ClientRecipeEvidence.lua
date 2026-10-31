local _, JLP = ...
-- Read-only, ephemeral observations from an ACTUALLY OPEN Forever tradeskill window.
-- No persisted state, no recipe learning, no dispatch, no source-rights promotion.
-- Observations can enrich a plan but cannot qualify a shipped static record.
local Evidence={contract="jlp-open-client-recipe-observation-v1",readOnly=true,
    nativeDispatchAllowed=false,executionEligible=false,productionAuthority=false,
    maximumPageSize=12,maximumScan=4096}
local function positive(v)
    return type(v)=="number" and v>0 and v==math.floor(v) and v<math.huge
end
local function observedBuild(requested)
    local build=JLP:GetModule("ClientBuildInfo")
    -- A requested source/reference build is not a client execution requirement.
    -- Caller provenance may refer to 70374 while the open client is newer.
    if requested~=nil and not positive(requested) then return nil,"INVALID_REQUESTED_SOURCE_BUILD" end
    if type(build)~="table" or type(build.GetBuildNumber)~="function" then
        return nil,"LIVE_BUILD_UNAVAILABLE"
    end
    local ok,actual=pcall(build.GetBuildNumber,build)
    if not ok or not positive(actual) then return nil,"LIVE_BUILD_UNKNOWN" end
    return actual,nil
end
local function openProfession(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and reg:Get(key)
    local skill=def and def.skillLineID
    if not positive(skill) then return nil,"PROFESSION_UNAVAILABLE" end
    local api=JLP:GetModule("ProfessionAPI")
    if not api or type(api.GetOpenProfessionContext)~="function" then
        return nil,"OPEN_PROFESSION_CONTEXT_UNAVAILABLE"
    end
    local ctx=api:GetOpenProfessionContext()
    if not ctx or ctx.verified~=true or ctx.professionKey~=key or
       tonumber(ctx.baseSkillLineID)~=skill or type(ctx.clientBuildToken)~="string" or
       type(ctx.panelToken)~="string" or type(ctx.panelRevision)~="number" then
        return nil,"OPEN_PROFESSION_IDENTITY_UNVERIFIED"
    end
    return skill,nil,ctx
end
local function samePanel(first,second)
    return first and second and second.verified==true and
        first.clientBuildToken==second.clientBuildToken and
        first.panelToken==second.panelToken and
        first.panelRevision==second.panelRevision and
        first.characterKey==second.characterKey
end
local function recheckPanel(key,original)
    local skill,why,ctx=openProfession(key)
    if not skill then return nil,why end
    if not samePanel(original,ctx) then return nil,"OPEN_PROFESSION_CONTEXT_CHANGED" end
    return ctx,nil
end

-- Lua's length operator and ipairs do not prove array contiguity. Validate
-- every representable key before inspecting slot contents. Never silently
-- omit a required slot from a client-owned schematic.
local function denseArray(value,maxItems,allowEmpty)
    if type(value)~="table" then return nil,"ARRAY_NOT_TABLE" end
    local count,maxIndex=0,0
    for k in pairs(value) do
        if not positive(k) or k>maxItems then return nil,"ARRAY_KEY_INVALID" end
        count=count+1
        if k>maxIndex then maxIndex=k end
        if count>maxItems then return nil,"ARRAY_UNBOUNDED" end
    end
    if count~=maxIndex then return nil,"ARRAY_SPARSE" end
    if count==0 and not allowEmpty then return nil,"ARRAY_EMPTY" end
    return count,nil
end
local function recipeIds()
    local api=C_TradeSkillUI
    if type(api)~="table" or type(api.GetAllRecipeIDs)~="function" then
        return nil,"RECIPE_LIST_API_UNAVAILABLE"
    end
    local ok,ids=pcall(api.GetAllRecipeIDs)
    if not ok then return nil,"RECIPE_LIST_UNAVAILABLE_OR_UNBOUNDED" end
    local count,why=denseArray(ids,Evidence.maximumScan,true)
    if not count then return nil,"RECIPE_LIST_"..why end
    -- Capture numeric values, not the provider's mutable Lua table. Callback
    -- code may change the original table IN PLACE, including when the final
    -- GetAllRecipeIDs returns that very same reference.
    local seen,snapshot={},{}
    for i=1,count do
        local id=ids[i]
        if not positive(id) then return nil,"RECIPE_LIST_INVALID" end
        -- Live Forever recipe enumerations can contain repeated IDs. Preserve
        -- the raw positions for pagination and fingerprinting; only presence
        -- is deduplicated for membership checks.
        snapshot[i]=id
        seen[id]=true
    end
    return snapshot,seen
end
local function schematicReagents(recipeID)
    local api=C_TradeSkillUI
    if type(api)~="table" or type(api.GetRecipeSchematic)~="function" then
        return nil,"SCHEMATIC_API_UNAVAILABLE"
    end
    local ok,sc=pcall(api.GetRecipeSchematic,recipeID,false)
    if not ok then return nil,"SCHEMATIC_API_EXCEPTION" end
    if type(sc)~="table" then return nil,"SCHEMATIC_UNKNOWN" end
    local n,why=denseArray(sc.reagentSlotSchematics,256,false)
    if not n then return nil,"SCHEMATIC_SLOTS_"..why end
    local reagents,seen={},{}
    local hasRequired=false
    local requiredUnknown=false
    for index=1,n do
        local slot=sc.reagentSlotSchematics[index]
        if type(slot)~="table" then return nil,"SCHEMATIC_SLOT_INVALID" end
        -- Inspect every slot and alternative even if an earlier required flag
        -- is UNKNOWN. Preserve a specific duplicate/ambiguity diagnosis.
        local altCount,altWhy=denseArray(slot.reagents,64,false)
        if not altCount then return nil,"SCHEMATIC_ALTERNATIVES_"..altWhy end
        for i=1,altCount do
            local alternative=slot.reagents[i]
            if type(alternative)~="table" or not positive(alternative.itemID) then
                return nil,"SCHEMATIC_REAGENT_ID_INVALID"
            end
        end
        if altCount~=1 then return nil,"SCHEMATIC_OPTIONAL_OR_AMBIGUOUS" end
        local id=slot.reagents[1].itemID
        if seen[id] then return nil,"SCHEMATIC_REAGENT_ID_INVALID" end
        seen[id]=true
        if type(slot.required)~="boolean" then requiredUnknown=true end
        if slot.required==true then
            hasRequired=true
            if not positive(slot.quantityRequired) then return nil,"SCHEMATIC_QUANTITY_INVALID" end
            reagents[#reagents+1]={itemID=id,quantity=slot.quantityRequired}
        elseif slot.required==false then
            -- Optional reagents are not mandatory; do not assume selected.
        end
    end
    if requiredUnknown then return nil,"SCHEMATIC_REQUIRED_UNKNOWN" end
    if not hasRequired or #reagents==0 then return nil,"SCHEMATIC_REAGENTS_UNKNOWN" end
    table.sort(reagents,function(a,b) return a.itemID<b.itemID end)
    return reagents,nil
end
local function sameRecipeIds(first,second)
    -- Both arguments are independent validated snapshots, never API-owned
    -- references. The comparison covers order and length, not only membership.
    if #first~=#second then return false end
    for i=1,#first do if first[i]~=second[i] then return false end end
    return true
end
-- With a validated page snapshot, avoid a whole-list API call for every row.
-- Re-check the build and open profession on each row and at commit.
local function observeFromSnapshot(key,recipeID,requestedBuild,skill,seen,firstPanel)
    if not seen[recipeID] then return nil,"RECIPE_NOT_VISIBLE_IN_OPEN_PROFESSION" end
    local actual,why=observedBuild(requestedBuild)
    if not actual then return nil,why end
    local panel
    panel,why=recheckPanel(key,firstPanel)
    if not panel then return nil,why end
    local professionAPI=JLP:GetModule("ProfessionAPI")
    if not professionAPI or type(professionAPI.GetRecipeContext)~="function" then
        return nil,"UNIFIED_RECIPE_CONTEXT_UNAVAILABLE"
    end
    local context=professionAPI:GetRecipeContext(recipeID,key)
    if not context or context.verified~=true then
        return nil,"UNIFIED_RECIPE_"..tostring(context and context.reason or "UNAVAILABLE")
    end
    if context.panelToken~=firstPanel.panelToken or
       context.panelRevision~=firstPanel.panelRevision or
       context.clientSessionToken~=firstPanel.clientBuildToken then
        return nil,"OPEN_PROFESSION_CONTEXT_CHANGED"
    end
    local reagents,reagentReason=schematicReagents(recipeID)
    local currentBuild,buildWhy=observedBuild(requestedBuild)
    if not currentBuild then return nil,buildWhy end
    if currentBuild~=actual then return nil,"CLIENT_BUILD_CHANGED_DURING_OBSERVATION" end
    local finalPanel,contextWhy=recheckPanel(key,firstPanel)
    if not finalPanel then return nil,contextWhy end
    local learned=context.learned
    return {professionKey=key,skillLineID=skill,recipeID=recipeID,spellID=recipeID,
        identityType="SPELL",name=context.name,sourceBuild=actual,requestedBuild=requestedBuild,
        clientBuildToken=firstPanel.clientBuildToken,panelToken=firstPanel.panelToken,
        panelRevision=firstPanel.panelRevision,recipeLineage=context.lineage,
        state="CANDIDATE",evidenceState="CANDIDATE",observationState="CLIENT_OBSERVED",
        observationSource="ProfessionAPI.GetRecipeContext",observationBuild=actual,
        reagentObservationComplete=reagents~=nil,reagentObservationReason=reagentReason,
        reagents=reagents or {},observedLearned=learned,
        learnedEvidenceState=learned==nil and "UNKNOWN" or "LIVE_OBSERVED",
        output={kind="UNKNOWN"},difficulty={basis="UNKNOWN"},requirements={skill=nil},
        acquisition={hordeQualified=nil},fieldProvenance={
            identity={state="CANDIDATE",source="IN_CLIENT_OBSERVATION",sourceBuild=actual},
            reagents={state=reagents and "CANDIDATE" or "UNKNOWN",source="IN_CLIENT_OBSERVATION",sourceBuild=actual},
            output={state="UNKNOWN"},requiredSkill={state="UNKNOWN"},
            difficulty={state="UNKNOWN"},acquisition={state="UNKNOWN"}},
        verifiedFieldSet=false,verifiedAcquisition=false,qualifiedFields={},
        readOnly=true,productionAuthority=false,nativeDispatchAllowed=false,
        executionEligible=false,notForRedistribution=true},nil
end

function Evidence:Observe(key,recipeID,requestedBuild)
    if not positive(recipeID) then return nil,"RECIPE_ID_INVALID" end
    local actual,why=observedBuild(requestedBuild)
    if not actual then return nil,why end
    local skill
    local firstPanel
    skill,why,firstPanel=openProfession(key)
    if not skill then return nil,why end
    local ids,seen=recipeIds()
    if not ids then return nil,seen end
    local row,reason=observeFromSnapshot(key,recipeID,requestedBuild,skill,seen,firstPanel)
    if not row then return nil,reason end
    local finalIds,finalWhy=recipeIds()
    if not finalIds then return nil,finalWhy end
    if not sameRecipeIds(ids,finalIds) then return nil,"RECIPE_LIST_CHANGED_DURING_OBSERVATION" end
    local finalBuild=observedBuild(requestedBuild)
    if finalBuild~=actual then return nil,"CLIENT_BUILD_CHANGED_DURING_OBSERVATION" end
    local finalPanel,reason=recheckPanel(key,firstPanel)
    if not finalPanel then return nil,reason end
    return row,nil
end
-- Compare the original catalogue fingerprint to an actual, bounded client
-- observation. A mismatch is diagnostic; it neither rewrites authoritative
-- records nor silently replaces planned reagents.
function Evidence:CompareStatic(key,staticRow,clientBuild)
    if type(staticRow)~="table" or not positive(staticRow.recipeID) or
        type(staticRow.reagents)~="table" then return nil,"STATIC_RECIPE_INVALID" end
    local observed,why=self:Observe(key,staticRow.recipeID,clientBuild)
    if not observed then return nil,why end
    local out={state="UNKNOWN",readOnly=true,nativeDispatchAllowed=false,
        clientBuild=observed.observationBuild,sourceBuild=staticRow.sourceBuild,
        observationState="CLIENT_OBSERVED",recipeID=staticRow.recipeID,
        clientLearned=observed.observedLearned}
    if not observed.reagentObservationComplete then
        out.reason=observed.reagentObservationReason
        return out,nil
    end
    local staticCount,staticReason=denseArray(staticRow.reagents,256,false)
    if not staticCount then
        out.reason="STATIC_REAGENTS_"..staticReason
        return out,nil
    end
    local expected={}
    for _,r in ipairs(staticRow.reagents) do
        if not positive(r.itemID) or not positive(r.quantity) or expected[r.itemID] then
            out.reason="STATIC_REAGENTS_INVALID";return out,nil
        end
        expected[r.itemID]=r.quantity
    end
    local differences={}
    for _,r in ipairs(observed.reagents) do
        if expected[r.itemID]~=r.quantity then
            differences[#differences+1]={itemID=r.itemID,
                staticQuantity=expected[r.itemID],observedQuantity=r.quantity}
        end
        expected[r.itemID]=nil
    end
    for id,qty in pairs(expected) do
        differences[#differences+1]={itemID=id,staticQuantity=qty,observedQuantity=nil}
    end
    table.sort(differences,function(a,b) return a.itemID<b.itemID end)
    out.state=#differences==0 and "MATCH" or "CONFLICT"
    out.differences=differences
    out.checkedFields={identity=true,reagents=true,output=false,skill=false,acquisition=false}
    return out,nil
end
function Evidence:ObservePage(key,offset,pageSize,clientBuild)
    offset=offset or 0;pageSize=pageSize or self.maximumPageSize
    if type(offset)~="number" or offset<0 or offset~=math.floor(offset) or
        not positive(pageSize) or pageSize>self.maximumPageSize then
        return nil,"INVALID_PAGE"
    end
    local build,why=observedBuild(clientBuild)
    if not build then return nil,why end
    local skill
    local firstPanel
    skill,why,firstPanel=openProfession(key)
    if not skill then return nil,why end
    local ids,seen=recipeIds()
    if not ids then return nil,seen end
    local rows,errors={},{}
    for i=offset+1,math.min(#ids,offset+pageSize) do
        local row,reason=observeFromSnapshot(key,ids[i],clientBuild,skill,seen,firstPanel)
        if row then rows[#rows+1]=row else errors[#errors+1]={recipeID=ids[i],reason=reason} end
    end
    local finalBuild,finalReason=observedBuild(clientBuild)
    if not finalBuild then return nil,finalReason end
    if finalBuild~=build then return nil,"CLIENT_BUILD_CHANGED_DURING_PAGE" end
    local finalPanel
    finalPanel,finalReason=recheckPanel(key,firstPanel)
    if not finalPanel then return nil,finalReason end
    local finalIds
    finalIds,finalReason=recipeIds()
    if not finalIds then return nil,finalReason end
    if not sameRecipeIds(ids,finalIds) then return nil,"RECIPE_LIST_CHANGED_DURING_PAGE" end
    -- Whole-page snapshot can be unstable even when individual rows are valid.
    -- Never publish a falsely complete catalogue on this observational path.
    return {rows=rows,total=#ids,offset=offset,pageSize=pageSize,
        status=#errors==0 and "CLIENT_OBSERVED" or "PARTIAL",complete=false,
        errors=errors,sourceBuild=build,skillLineID=skill,
        evidenceState="CANDIDATE",readOnly=true,nativeDispatchAllowed=false},nil
end
-- P1-178: independent VOLATILE READ-ONLY client recipe inspection.
-- Legacy Observe / ObservePage retain full build+interface session fences.
-- A volatile row is NEVER a static candidate, a qualified source receipt,
-- a learned-cache entry, a Planner handoff, or native execution evidence.
function Evidence:ObserveReadOnly(key,recipeID,sourceBuild)
    if sourceBuild~=nil and not positive(sourceBuild) then
        return nil,"INVALID_SOURCE_BUILD"
    end
    if not positive(recipeID) or recipeID>=2147483648 then
        return nil,"RECIPE_ID_INVALID"
    end
    local api=JLP:GetModule("ProfessionAPI")
    if not api or type(api.GetReadOnlyRecipeObservation)~="function" then
        return nil,"READ_ONLY_RECIPE_API_UNAVAILABLE"
    end
    local live=api:GetReadOnlyRecipeObservation(recipeID,key)
    if type(live)~="table" or live.readOnlyObserved~=true or
        live.professionKey~=key or live.recipeID~=recipeID or
        type(live.learned)~="boolean" or type(live.name)~="string" then
        return nil,type(live)=="table" and live.reason or "READ_ONLY_RECIPE_UNVERIFIED"
    end
    return {
        contract="volatile-client-recipe-evidence-v1",professionKey=key,
        recipeID=recipeID,name=live.name,learned=live.learned,
        observationQuality=live.observationQuality,
        panelToken=live.observationToken, panelRevision=live.panelRevision,
        referenceSourceBuild=sourceBuild,
        -- Do not invent source or client build when no receipt is available.
        readOnly=true,readOnlyObserved=true,verified=false,
        nativeDispatchAllowed=false,executionEligible=false,
        productionAuthority=false,persistentReceiptEligible=false,
        datasetRequalified=false,plannerHandoffEligible=false,
        materialQualified=false,outputQualified=false,
        observationState="VOLATILE_READ_ONLY",reason="LIVE_RECIPE_OBSERVED_READ_ONLY",
    },nil
end

-- Bounded page browsing is diagnostic only. A change in profession or recipe
-- list during the page scan REVOKES the entire page, not only the final row.
function Evidence:ObservePageReadOnly(key,offset,pageSize,sourceBuild)
    offset=offset==nil and 0 or offset
    pageSize=pageSize==nil and self.maximumPageSize or pageSize
    if type(offset)~="number" or offset<0 or offset~=math.floor(offset) or
        type(pageSize)~="number" or pageSize<1 or pageSize~=math.floor(pageSize) or
        pageSize>self.maximumPageSize then return nil,"INVALID_PAGE" end
    if sourceBuild~=nil and not positive(sourceBuild) then
        return nil,"INVALID_SOURCE_BUILD" end
    local api=JLP:GetModule("ProfessionAPI")
    if not api or type(api.GetReadOnlyProfessionObservation)~="function" then
        return nil,"READ_ONLY_PROFESSION_API_UNAVAILABLE" end
    local first=api:GetReadOnlyProfessionObservation()
    if not first or first.observed~=true or first.professionKey~=key then
        return nil,"READ_ONLY_PROFESSION_UNVERIFIED" end
    local trade=C_TradeSkillUI
    if type(trade)~="table" or type(trade.GetAllRecipeIDs)~="function" then
        return nil,"RECIPE_LIST_API_UNAVAILABLE" end
    local listFn=trade.GetAllRecipeIDs
    local function snapshot()
        if C_TradeSkillUI~=trade or trade.GetAllRecipeIDs~=listFn then
            return nil,"RECIPE_PROVIDER_CHANGED" end
        local ok,ids=pcall(listFn)
        if not ok or type(ids)~="table" then return nil,"RECIPE_LIST_API_ERROR" end
        local n,max,counts=0,0,{}
        for i,id in pairs(ids) do
            if type(i)~="number" or i<1 or i~=math.floor(i) or
                i>self.maximumScan or not positive(id) or id>=2147483648 then
                return nil,"RECIPE_LIST_INVALID" end
            n=n+1;max=math.max(max,i);counts[id]=(counts[id] or 0)+1
        end
        if max~=n then return nil,"RECIPE_LIST_INVALID" end
        local copy={}
        for i=1,n do copy[i]=ids[i] end
        return copy,nil
    end
    local ids,why=snapshot()
    if not ids then return nil,why end
    local rows,errors={},{}
    for i=offset+1,math.min(#ids,offset+pageSize) do
        local row,err=self:ObserveReadOnly(key,ids[i],sourceBuild)
        if row then rows[#rows+1]=row
        else errors[#errors+1]={recipeID=ids[i],reason=err} end
    end
    local again,err=snapshot()
    if not again then return nil,err end
    if #ids~=#again then return nil,"RECIPE_LIST_CHANGED_DURING_PAGE" end
    for i=1,#ids do
        if ids[i]~=again[i] then return nil,"RECIPE_LIST_CHANGED_DURING_PAGE" end
    end
    local last=api:GetReadOnlyProfessionObservation()
    if not last or last.observed~=true or
        last.observationToken~=first.observationToken or
        last.professionKey~=first.professionKey or
        last.characterKey~=first.characterKey or
        last.skill~=first.skill or last.maxSkill~=first.maxSkill or
        last.clientBuild~=first.clientBuild or
        last.observationQuality~=first.observationQuality then
        return nil,"READ_ONLY_PANEL_CHANGED_DURING_PAGE" end
    return {contract="volatile-client-recipe-page-v1",rows=rows,errors=errors,
        total=#ids,offset=offset,pageSize=pageSize,
        status=#errors==0 and "VOLATILE_READ_ONLY" or "VOLATILE_PARTIAL",
        observationQuality=first.observationQuality,
        referenceSourceBuild=sourceBuild,complete=false,
        verified=false,readOnly=true,nativeDispatchAllowed=false,
        executionEligible=false,productionAuthority=false,
        datasetRequalified=false,persistentReceiptEligible=false},nil
end
JLP:RegisterModule("ClientRecipeEvidence",Evidence)
