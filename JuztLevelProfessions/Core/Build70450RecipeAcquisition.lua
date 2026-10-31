local _, JLP = ...
-- M10: read-only recipe-item teaching links and provenance-aware acquisition leads.
-- Server vendor inventories, trainer spells and creature loot are NOT in DB2 snapshot.
local Service={contract="JLP-BUILD70450-RECIPE-ACQUISITION-1",sourceBuild=70450,
    readOnly=true,nativeDispatchAllowed=false,executionEligible=false,pageLimit=30}
local BUILD=70450
local EXPECTED_SOURCE_SHA={SkillLineAbility="df6018b459f851bdee27edfc74d2f45678177cba50aeed4bf12bc9d5fa4973e4",ItemEffect="5282eec869e032a554a4e6e5f19fd21feaf4db4c0a077fa86309f5d858ce7583",ItemXItemEffect="d9c2721f9a59e9ac2ad71b62a1856e23bfd0f75e466cf06a5a731f7e6f4d3a8b",ItemSparse="98333a70d1a3f01489a3525cb8e8cdde14be5d1cab84c69bb43ef1ee6d87da8e"}
local function positive(n)
    return type(n)=="number" and n==math.floor(n) and n>0 and n<2147483647
end
local function sources()
    local r=JLP.data and JLP.data.build70450Acquisition
    local recipes=JLP.data and JLP.data.build70450Recipes
    local items=JLP.data and JLP.data.build70450ItemMetadata
    if type(r)~="table" or r.contract~="JLP-BUILD70450-ACQUISITION-RESEARCH-1" or r.sourceBuild~=BUILD or
       type(r.professions)~="table" or type(r.itemSources)~="table" or type(r.inputSHA256)~="table" then
        return nil,"ACQUISITION_DATA_UNAVAILABLE"
    end
    -- Immutable file-identity constants protect the compact item/spell link archive
    -- against accidental cross-build replacement, not against forged server proof.
    for k,expected in pairs(EXPECTED_SOURCE_SHA) do
        if r.inputSHA256[k]~=expected then return nil,"OWNER_SOURCE_SHA_CONFLICT_"..k end
    end
    if type(recipes)~="table" or not recipes.inputSHA256 or
       recipes.inputSHA256.SkillLineAbility~=r.inputSHA256.SkillLineAbility then
        return nil,"RECIPE_SHA_CONFLICT"
    end
    if type(items)~="table" or not items.sourceSHA256 or
       items.sourceSHA256.ItemSparse~=r.inputSHA256.ItemSparse then
        return nil,"ITEM_METADATA_SHA_CONFLICT"
    end
    return r
end
local function normalized(key)
    local registry=JLP:GetModule("ProfessionRegistry")
    local k=registry and registry.NormalizeKey and registry:NormalizeKey(key)
    return k
end
local function findRow(packed,spell)
    local needle=tostring(spell).."^";local i=1
    while true do
        local p=packed:find(needle,i,true)
        if not p then return nil end
        if p==1 or packed:sub(p-1,p-1)=="\n" then
            local finish=packed:find("\n",p,true)
            return packed:sub(p,finish and finish-1 or #packed)
        end
        i=p+#needle
    end
end
local function clientRelation()
    local info=JLP:GetModule("ClientBuildInfo")
    local number
    if info and type(info.GetBuildNumber)=="function" then
        local ok,n=pcall(info.GetBuildNumber,info)
        if ok and positive(n) then number=n end
    end
    return number==BUILD and "MATCH" or (number and "MISMATCH" or "UNKNOWN")
end
function Service:GetRecipeSources(key,spellID,sourceBuild)
    if sourceBuild~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    if not positive(spellID) then return nil,"INVALID_SPELL_ID" end
    local k=normalized(key)
    if not k then return nil,"UNKNOWN_PROFESSION" end
    local d,why=sources();if not d then return nil,why end
    local profession=d.professions[k]
    local registry=JLP:GetModule("ProfessionRegistry")
    local def=registry and registry:Get(k)
    if not profession or not def or def.skillLineID~=profession.skillLineID then
        return nil,"PROFESSION_SKILLLINE_CONFLICT"
    end
    local recipe=JLP:GetModule("Build70450RecipeCatalogue")
    if not recipe then return nil,"RECIPE_CATALOGUE_UNAVAILABLE" end
    local recipeRow,reason=recipe:GetRecipe(k,spellID,BUILD)
    if not recipeRow then return nil,reason end
    local packed=findRow(profession.packed,spellID)
    local ids={}
    if packed then
        local raw=packed:match("^%d+%^(.*)$")
        if not raw then return nil,"TEACH_ITEM_DATA_CORRUPT" end
        for digit in raw:gmatch("[^,]+") do
            local id=tonumber(digit)
            if not positive(id) then return nil,"INVALID_TEACHING_ITEM_ID" end
            ids[#ids+1]=id
        end
    end
    local metadata=JLP:GetModule("Build70450ItemMetadata")
    local teaching={};local leads={};local corroborated,conflict,historical=false,false,false
    for _,id in ipairs(ids) do
        local item=metadata and metadata.GetItem and metadata:GetItem(id,BUILD) or nil
        teaching[#teaching+1]={itemID=id,name=item and item.name or nil,
            itemNameState=item and item.nameEvidence or "ITEM_METADATA_UNAVAILABLE",
            relationEvidence="ITEMXITEMEFFECT_TO_ITEMEFFECT_TRIGGER_6_TO_SPELLID_70450",
            learningEffectObservedInClient=true,
            itemAcquisitionVerified=false,
            actualLearnedState="UNKNOWN"}
        for _,source in ipairs(d.itemSources[id] or {}) do
            local lead={teachingItemID=id,sourceType=source.sourceType,
                npcName=source.npcName~="" and source.npcName or nil,
                npcID=source.npcID,npcIDAuthority=source.npcIDAuthority,
                zone=source.zone~="" and source.zone or nil,
                factionReference=source.faction,
                externalReference=source.sourceReference,
                evidenceTier=source.evidenceTier,
                historicalStockLimited=source.limitedStockHistorical,
                evidenceCapturedBuild=source.legacyCapturedBuild,
                conflicted=source.conflict,conflictReason=source.conflictReason,
                sourceVerifiedLive70450=false,trainerSpellVerifiedLive70450=false,
                lootTableVerifiedLive70450=false,routeEligible=false,
                productionAuthority=false}
            -- Independent public references remain qualified leads, not server proof.
            local public=JLP:GetModule("Build70450NPCSourceEvidence")
            if public and type(public.GetPublicCrosschecks)=="function" then
                local linked,publicErr=public:GetPublicCrosschecks(id,source.sourceType,source.npcID,BUILD)
                if not linked then return nil,publicErr end
                local selected={}
                for _,candidate in ipairs(linked) do
                    if candidate.npcName==source.npcName and (not source.npcID or source.npcID==candidate.npcID) then
                        selected[#selected+1]=candidate
                    end
                end
                lead.publicCrosschecks=selected
            end
            leads[#leads+1]=lead
            if source.conflict then conflict=true end
            if source.evidenceTier=="PUBLIC_FOREVER_CORROBORATED" then corroborated=true else historical=true end
        end
        -- Public Forever QUEST rewards are independent of vendor inventory.
        -- Require the exact 70450 item-to-SpellID and profession match first.
        local publicQuest=JLP:GetModule("Build70450NPCSourceEvidence")
        if publicQuest and type(publicQuest.GetPublicQuestRewards)=="function" then
            local quests,questErr=publicQuest:GetPublicQuestRewards(id,BUILD)
            if not quests then return nil,questErr end
            for _,q in ipairs(quests) do
                if q.documentedSpellID~=spellID or k~="LEATHERWORKING" then
                    return nil,"PUBLIC_QUEST_TEACH_ITEM_SPELL_CONFLICT"
                end
                leads[#leads+1]={teachingItemID=id,sourceType="quest",questID=q.questID,
                    npcID=q.npcID,npcName=q.npcName,factionReference=q.factionReference,
                    externalReference=q.questURL,evidenceTier=q.evidenceTier,
                    sourceVerifiedLive70450=false,questCompletionVerified=false,
                    actualQuestEligibility="UNKNOWN",routeEligible=false,
                    productionAuthority=false,nativeDispatchAllowed=false,readOnly=true}
                corroborated=true
            end
        end
        -- The current public guide is independent of the older legacy-research
        -- inventory. A client-proven teaching item may have no historical lead.
        -- Attach only an EXACT item and spell+profession corroboration, and
        -- never infer current Horde inventory, server stock, or native rights.
        local public=JLP:GetModule("Build70450NPCSourceEvidence")
        if public and type(public.GetPublicCrosschecks)=="function" then
            local listed,listingErr=public:GetPublicCrosschecks(id,"vendor",nil,BUILD)
            if not listed then return nil,listingErr end
            for _,c in ipairs(listed) do
                if c.evidenceState=="WOWHEAD_FOREVER_ALLIANCE_GUIDE_2026_10_04" or
                   c.evidenceState=="WOWHEAD_FOREVER_ALLIANCE_BATCH_2026_10_19" or
                   c.evidenceState=="WOWHEAD_FOREVER_HORDE_COOKING_GUIDE_2026_10_11" or
                   c.evidenceState=="WOWHEAD_FOREVER_HORDE_PATTERN_ITEM_2026_10_19" then
                    if c.documentedSpellID~=spellID or c.documentedProfessionKey~=k then
                        return nil,"PUBLIC_GUIDE_TEACH_ITEM_SPELL_CONFLICT"
                    end
                    local duplicate=false
                    for _,old in ipairs(leads) do
                        if old.teachingItemID==id and old.sourceType=="vendor" and
                           old.npcID==c.npcID then duplicate=true;break end
                    end
                    if not duplicate then
                        leads[#leads+1]={teachingItemID=id,sourceType="vendor",
                            npcName=c.npcName,npcID=c.npcID,
                            npcIDAuthority="WOWHEAD_FOREVER_DIRECT_NPC_LINK",
                            factionReference=c.documentedVendorFaction,
                            itemFactionRequirement="UNKNOWN",
                            guideSkillRequired=c.guideSkillRequired,
                            merchantFavorCost=c.guideMerchantFavorCost,
                            externalReference=c.referenceURL,itemReferenceURL=c.itemReferenceURL,
                            evidenceTier=c.documentedVendorFaction=="Alliance" and
                                "WOWHEAD_FOREVER_ALLIANCE_PUBLIC_REFERENCE" or
                                "WOWHEAD_FOREVER_HORDE_PUBLIC_REFERENCE",
                            sourceVerifiedLive70450=false,trainerSpellVerifiedLive70450=false,
                            lootTableVerifiedLive70450=false,routeEligible=false,
                            productionAuthority=false,publicCrosschecks={c}}
                    end
                    corroborated=true
                end
            end
        end
    end
    local state=conflict and "CONFLICT_HOLD" or
        (corroborated and "PUBLIC_FOREVER_REFERENCE_NOT_LIVE" or
        (historical and "OLDER_JLP_RESEARCH_NOT_70450_LIVE" or
        (#teaching>0 and "TEACHING_ITEM_LINK_ONLY" or "NO_EXACT_TEACHING_ITEM_OR_SOURCE")))
    return {
        contract=self.contract,sourceBuild=BUILD,clientBuildRelation=clientRelation(),
        professionKey=k,skillLineID=def.skillLineID,spellID=spellID,
        recipeName=recipeRow.name,recordKind=recipeRow.recordKind,
        teachingItems=teaching,teachingItemCount=#teaching,
        researchSources=leads,researchSourceCount=#leads,
        sourceState=state,hasConflictingSource=conflict,
        vendorVerified=false,trainerVerified=false,npcVerified=false,dropVerified=false,
        questVerified=false,currentFactionAccess="UNKNOWN",specializationAccess="UNKNOWN",
        phaseAvailability="UNKNOWN",availableOnServer="UNKNOWN",
        itemSpellLinkVerifiedByClient=#teaching>0,
        currentBuildAcquisitionVerified=false,productionAuthority=false,
        nativeDispatchAllowed=false,readOnly=true,
        limitations="Client item use spells do not contain server NPC inventories, trainer spell lists, loot or current phase availability.",
    },nil
end
function Service:GetPage(key,offset,limit,sourceBuild)
    if sourceBuild~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
    offset=offset or 0;limit=limit or 15
    if type(offset)~="number" or offset<0 or offset>100000 or offset~=math.floor(offset) or
        type(limit)~="number" or limit<1 or limit>30 or limit~=math.floor(limit) then
        return nil,"INVALID_PAGE_BOUNDS"
    end
    local base=JLP:GetModule("Build70450RecipeCatalogue")
    if not base then return nil,"RECIPE_CATALOGUE_UNAVAILABLE" end
    local page,why=base:GetPage(key,offset,limit,BUILD)
    if not page then return nil,why end
    for _,row in ipairs(page.rows) do
        local a,err=self:GetRecipeSources(row.professionKey,row.spellID,BUILD)
        if not a then return nil,err end
        row.acquisitionReference=a
    end
    page.acquisitionContract=self.contract
    page.currentBuildAcquisitionVerified=false
    return page,nil
end
function Service:GetCoverage()
    local d,why=sources();if not d then return nil,why end
    return {contract=self.contract,sourceBuild=BUILD,clientBuildRelation=clientRelation(),
        counts={total=d.counts.total,withTeachingItems=d.counts.withTeachingItems,
            withoutTeachingItems=d.counts.withoutTeachingItems,
            withResearchSource=d.counts.withResearchSource,
            publicCorroborated=d.counts.publicCorroborated,
            conflict=d.counts.conflict,sourceRows=d.counts.sourceRows},
        currentBuildVerifiedNpcOrDropRelations=0,readOnly=true,productionAuthority=false}
end
JLP:RegisterModule("Build70450RecipeAcquisition",Service)
